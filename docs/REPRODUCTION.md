# Reproduction and integration

This is a source/configuration integration kit. It does not distribute the
original Generic x86_64 BSP, a BSP-derived complete buildfile, QNX headers or
libraries, or a generated image. Obtain those from QNX under your own license.
Keep the vendor BSP unchanged and modify a local working copy.

## Recorded toolchain

| Component | Recorded local version |
|---|---|
| QNX Software Center | 2.0.4, Conservative update policy |
| QNX SDP | 8.0 family, local installation SDP805 / OS 8.0.5 |
| Generic x86_64 BSP | 0.3.0, JBN337; QSC displayed Validated (GA8.0.3) |
| BSP package | `com.qnx.qnx800.bsp.hw.x86_64`, `0.3.0.00337T202507311444L` |
| io-sock package | `0.5.0.00015T202605220948L` |
| devs-rt package | `0.5.0.00006T202605051035L` |
| PCI x86 hardware package | `3.1.0.02005T202411230033L` |
| Compiler target / GCC | `gcc_ntox86_64` / 12.2.0 |

These are the recorded build inputs, not a claim about the newest available
packages. Use compatible components from QNX Software Center. The lab's BSP ZIP
was `BSP_x86_64_be-800_SVN1019295_JBN337.zip`.

## Windows setup

Use ASCII paths without spaces, for example `C:\QNX\SDP805`, `C:\QNXCONFIG`,
`C:\m6-qnx-security-gateway`, and `C:\QNX-BSP-work`. Run the official environment
script in a command prompt before building the local BSP:

```bat
call C:\QNX\SDP805\qnxsdp-env.bat
set QNX_CONFIGURATION=C:\QNXCONFIG
set QNX_CONFIGURATION_EXCLUSIVE=C:\QNXCONFIG
set BSP_ROOT_DIR=C:\QNX-BSP-work
echo %QNX_HOST%
echo %QNX_TARGET%
echo %QNX_BASE%
where qcc
where mkifs
where make
```

Configuration-directory overrides are appropriate only for an already provisioned
QNX configuration. Do not move or publish credentials to make a build pass.
Use the installed BSP's documented make targets and UEFI buildfile.

## Prepare original project files

Copy `config/ports.conf.example` to ignored `config/ports.conf`, then set the
measured upstream/protected MACs. Keep B at 192.168.77.1/24 for this policy.
The sample MACs are deliberately rejected by the staging helper.

```powershell
Copy-Item config\ports.conf.example config\ports.conf
# Edit config\ports.conf with your measured MAC addresses before staging.
& .\scripts\stage-overlay.ps1 -Mode normal
```

Compile the original diagnostic service from an ASCII repository location:

```bat
scripts\build-diagnostic.cmd C:\QNX\SDP805 C:\QNXCONFIG
```

The helper produces ignored `output/m6-diag`. It does not build an IFS. Staging
produces `build/overlay-normal/MANIFEST.txt` and original configuration/scripts;
it does not edit the vendor BSP or USB. `forwarding-off` is a separate staging
mode. `syntax-error` is available for future controlled fault injection, but has
not been tested on the hardware or installed on the normal USB.

## Local BSP integration contract

Apply QNX's documented AMD change to the Generic x86_64 working BSP: use
`pci_hw-AMD_x86.so`, including the `PCI_HW_MODULE` setting and the PCI server
configuration, instead of the Intel hardware module. Retain the BSP's compatible
PCI support/plugin set. Do not substitute an Intel prebuilt IFS.

Integrate the staged files at the paths in `MANIFEST.txt`, and the compiled
diagnostic at `/usr/sbin/m6-diag`. The local UEFI buildfile must also provide:

- `startup-x86`, the x86_64 kernel (`procnto-smp-instr` in the measured image),
  runtime loader, correct shared-library search paths, and required symlinks.
- `pci-server`, `pci-tool`, AMD PCI hardware/support modules, and
  `/etc/system/config/pci/pci_server.cfg` from the locally configured BSP.
- `io-sock`, `mods-pci.so`, `mods-phy.so`, `devs-rt.so`, `pfctl`, `ifconfig`,
  `sysctl`, `route`, `dhcpcd`, plus their actual ELF and dynamic dependencies.
- `ksh`, `slogger2`, `mqueue`, `random`, `waitfor`, `pidin`, `devinfo`, `slay`,
  `kill`, `shutdown`, `pipe`, and the standard text/file utilities used by the
  scripts (`cat`, `sed`, `grep`, `tr`, `mkdir`, `rm`, `rmdir`, `mv`, `date`,
  `sleep`, `tail`, `printf`, `chmod`, `uname`).
- A local `/proc/boot/ram-state.sh` which creates RAM-backed `/var` and its
  `run`, `db`, `log`, and `tmp` directories before network control starts.
  The measured BSP integration used `devf-ram`/`flashctl` with a 16 MiB RAM
  device, not a physical disk. Follow the installed BSP RAM-storage instructions.
- QNX runtime configuration/data required by the selected components, such as
  crypto backend configuration and PF/protocol data. Resolve shared-library
  dependencies using QNX tools against your installed packages.

The script starts `io-sock -m pci -m phy -d rt`. Start
`ksh /proc/boot/network-bringup.sh` asynchronously from the IFS startup script
after basic process/pipe setup. Do not wait on HDMI console readiness before
starting networking. USB keyboard/console support is optional to this network
test and must use components from the local BSP.

Do not include physical NVMe/filesystem mounting, qconn, SSH, a Web UI, Wi-Fi,
Bluetooth, or an unrelated DHCP server in this gateway image. The provided
original scripts have one IPv4 forwarding-on function, gated by PF checks.

Use `mkifs` through the BSP's UEFI build target. Check actual dependencies and
image contents using the installed QNX tools. These integration instructions
do not make the public tree a byte-for-byte recipe for the private baseline:
the published SHA-256 identifies that tested artifact, not every future build.

## USB and hardware validation

Use only a USB explicitly assigned to this experiment. Confirm its USB bus,
vendor/product, capacity, and identity before writing. Do not identify it by
disk number alone. Follow the Generic x86_64 BSP's official UEFI removable-media
procedure; in this lab the UEFI IFS was placed at `EFI\BOOT\BOOTX64.EFI` on FAT32.
FAT32 alone is not proof of a valid boot structure.

Do not modify the Windows SSD/ESP, BCD, firmware boot order, or Secure Boot to
follow this procedure. The measured lab used UEFI with Secure Boot already off.
Select the USB manually from the one-time firmware boot menu. Preserve a known
normal image before testing a control variant and compare the source/USB file
hash after copying. Then follow [TEST_PLAN.md](TEST_PLAN.md).

## Host tests

From the repository root in a POSIX-compatible shell:

```sh
sh tests/run-host-tests.sh
```

In PowerShell:

```powershell
& .\tests\Test-BaselineSampler.ps1
```

Network/PF operations are mocked in these tests. They check gate and diagnostic
logic; they do not run PF or validate QNX driver behavior. Network test helpers
under `tests/` that create a listener/temporary route are separate, explicit
hardware-test procedures.

## Official references

Consult the documentation matching your installed components:

- [Generic x86_64 BSP build guidance](https://www.qnx.com/developers/docs/BSP8.0/com.qnx.doc.bsp_x86_64.generic_8.0/topic/bsp_build.html): BSP and AMD build configuration.
- [BSP command-line build](https://www.qnx.com/developers/docs/BSP8.0/com.qnx.doc.bsp_x86_64.generic_8.0/topic/build_commandline.html): local working BSP and environment.
- [devs-rt.so](https://www.qnx.com/developers/docs/8.0/com.qnx.doc.neutrino.utilities/topic/d/devs-rt.so.html): Realtek RTL8125/8126 driver and loading.
- [mods-pci.so](https://www.qnx.com/developers/docs/8.0/com.qnx.doc.neutrino.utilities/topic/m/mods-pci.so.html): PCI support for io-sock.
- [mkifs](https://www.qnx.com/developers/docs/8.0/com.qnx.doc.neutrino.utilities/topic/m/mkifs.html): IFS generation and attributes.
- [io-sock packet filtering](https://www.qnx.com/developers/docs/8.0/com.qnx.doc.neutrino.io_sock/topic/overview_Filtering.html): PF usage.
- [Transferring an x86 image](https://www.qnx.com/developers/docs/8.0/com.qnx.doc.neutrino.building/topic/bsp/bsp_img_tfr_x86.html): boot-media guidance.

The installed SDP also ships local copies of its utilities/network documentation.
QNX components and their licensing remain separate from this MIT-licensed project.
