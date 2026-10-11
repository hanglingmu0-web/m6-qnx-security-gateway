/* Development-only, read-only TCP snapshot. No request interpreter or commands. */
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#define SNAPSHOT "/var/run/m6/diagnostic.txt"
#define MAX_SNAPSHOT (96 * 1024)
static volatile sig_atomic_t expired;
static void deadline(int signum) { (void)signum; expired = 1; }

static int send_all(int fd, const char *data, size_t length)
{
    while (length != 0) {
        if (expired) return -1;
        ssize_t n = send(fd, data, length, 0);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return -1;
        data += n;
        length -= (size_t)n;
    }
    return 0;
}

int main(void)
{
    struct sockaddr_in address = {0};
    struct sigaction action = {0};
    int listener, one = 1;
    signal(SIGPIPE, SIG_IGN);
    action.sa_handler = deadline;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGALRM, &action, NULL) < 0) return 1;
    /* Bind only B, never INADDR_ANY, and refuse privilege-drop failure. */
    if (setgroups(0, NULL) < 0 || setregid(65534, 65534) < 0 ||
        setreuid(65534, 65534) < 0 || getuid() != 65534 || geteuid() != 65534) {
        perror("diagnostic privilege drop");
        return 1;
    }
    listener = socket(AF_INET, SOCK_STREAM, 0);
    if (listener < 0) { perror("diagnostic socket"); return 1; }
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    address.sin_family = AF_INET;
    address.sin_port = htons(18080);
    inet_pton(AF_INET, "192.168.77.1", &address.sin_addr);
    if (bind(listener, (struct sockaddr *)&address, sizeof(address)) < 0 ||
        listen(listener, 4) < 0) {
        perror("diagnostic bind/listen");
        close(listener);
        return 1;
    }
    printf("DIAGNOSTIC_LISTEN=192.168.77.1:18080 UID=%lu\n", (unsigned long)geteuid());
    fflush(stdout);
    for (;;) {
        struct sockaddr_in peer;
        socklen_t peer_length = sizeof(peer);
        struct timeval timeout = {2, 0};
        struct stat st;
        char buffer[4096], header[160];
        size_t remaining = MAX_SNAPSHOT;
        int client = accept(listener, (struct sockaddr *)&peer, &peer_length);
        int input;
        if (client < 0) { if (errno == EINTR) continue; perror("accept"); sleep(1); continue; }
        /* Additional peer restriction, independent of PF. No received bytes parsed. */
        unsigned long ip = ntohl(peer.sin_addr.s_addr);
        if (peer.sin_family != AF_INET || (ip & 0xffffff00UL) != 0xc0a84d00UL ||
            (ip & 255UL) < 2 || (ip & 255UL) == 255) { close(client); continue; }
        if (setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout)) < 0) {
            close(client); continue;
        }
        /* A slow reader cannot monopolize this single-process service. */
        expired = 0;
        alarm(5);
        input = open(SNAPSHOT, O_RDONLY | O_NOFOLLOW);
        if (input < 0 || fstat(input, &st) < 0 || !S_ISREG(st.st_mode)) {
            static const char unavailable[] = "SNAPSHOT=UNAVAILABLE\nREADY=UNKNOWN\n";
            send_all(client, unavailable, sizeof(unavailable)-1);
        } else {
            time_t now = time(NULL);
            long age = (long)(now - st.st_mtime);
            int n = snprintf(header, sizeof(header),
                "SNAPSHOT_AGE_SECONDS=%ld\nSNAPSHOT_FRESH=%s\n", age,
                age >= 0 && age <= 15 ? "YES" : "NO_DO_NOT_TRUST_CACHED_STATUS");
            if (n > 0 && send_all(client, header, (size_t)n) == 0) {
                while (remaining != 0 && !expired) {
                    size_t amount = remaining < sizeof(buffer) ? remaining : sizeof(buffer);
                    ssize_t count = read(input, buffer, amount);
                    if (count < 0 && errno == EINTR) continue;
                    if (count <= 0 || send_all(client, buffer, (size_t)count) < 0) break;
                    remaining -= (size_t)count;
                }
            }
        }
        if (input >= 0) close(input);
        close(client);
        alarm(0);
    }
}
