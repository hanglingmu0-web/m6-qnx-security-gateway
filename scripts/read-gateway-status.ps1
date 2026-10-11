# Run on the downstream PC connected to B. Read-only, no HTTP or login.
$ErrorActionPreference = 'Stop'
$client = [Net.Sockets.TcpClient]::new()
try {
    $pending = $client.ConnectAsync('192.168.77.1',18080)
    if (-not $pending.Wait(5000)) { throw 'Diagnostic TCP connection timed out.' }
    $client.ReceiveTimeout = 10000
    $reader = [IO.StreamReader]::new($client.GetStream(), [Text.Encoding]::UTF8)
    try { $reader.ReadToEnd() } finally { $reader.Dispose() }
} finally { $client.Dispose() }
