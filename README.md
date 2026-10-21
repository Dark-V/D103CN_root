# D103CN FEL root
<img width="1443" height="814" alt="image" src="https://github.com/user-attachments/assets/ecd9a565-941f-471b-aa3d-f8cd7917bbe2" />

Physical-access UART root for the Xiaomi Mijia M30S (`xiaomi.vacuum.d103cn`). [Русский](README.ru.md) · [Research / SSH Wiki](https://github.com/Dark-V/D103CN_root/wiki)

**Experimental portable v2.** The original, personalized v1 obtained UART and SSH root on one R2405 v4 / firmware 4.5.6_1409 unit. This new per-device worker/writer has compiled and passed offline parsing checks against two saved captures of that same unit. **v2 has not been executed on a board. It is not a tested one-click installer.**

## What it does

```text
USB FEL → own raw backup → own factory DDR/NAND backend in RAM
→ locate device.conf through NFTL/ext4 → add UART hook → normal stock boot → root
```

It finds `/data/config/miio/device.conf` on this device, preserves its factory assignments, and constructs its own replacement page. No personal config, fixed target sector, firmware download, HAR, cookie, account, shared SSH key or supplied proprietary firmware is required. ELF files and an ARM compiler are not needed on the user's PC.

It does **not** replace signed boot/rootfs, forge an RSA signature, boot a custom Linux, disable thermal protection, issue NAND ERASE, or install SSH automatically. APPLY modifies NAND: one logical 4 KiB page through the pinned factory NFTL backend and paired PROGRAM callback. That write is **not physically atomic**. Power loss, an unsupported layout or a bug can brick the device. A raw backup is **not** a proven full-brick recovery procedure. Do not treat an OTA `.bin` as a raw-NAND restore image.

Only the pinned D103CN bootloader/DDR profile, SoC `1755`, NAND ID `98 da 90 15 76 16 08 00`, 512 MiB RAM, 462848 logical sectors and inspected ext4/JBD2 features are accepted. Unknown factory profiles/layouts, existing hooks and configs without space for a same-size edit are rejected. Do not bypass these checks. The tool does not independently identify the active Linux firmware version: matching bootloader hashes do not prove matching rootfs startup scripts. A factory Wi-Fi/BLE startup branch must source the config; writing the hook does not prove that branch will execute on every setup. Wi-Fi reset/OTA may remove access.

## 1. PC setup and FEL

Use Python 3.10+ (3.12 used in development) and a compatible libusb driver for **only** `VID_1F3A:PID_EFE8` on Windows. Do not replace drivers for unrelated devices. See [FEL / board precautions](https://github.com/Dark-V/D103CN_root/wiki/FEL-method) and [recovery limits](https://github.com/Dark-V/D103CN_root/wiki/Backup-and-recovery). There is no verified universal pinout in this release: do not short random pads. Use stable power, insulate exposed electronics, and stop on actual overheating or power faults.

From the repository directory, in PowerShell:

```powershell
py -3 -m venv .venv
.venv\Scripts\python.exe -m pip install -r requirements.txt
.venv\Scripts\python.exe exploit.py
```

Without hardware flags it prints the offline status and **does not open USB**. Never run this against a device you do not own/have authorization to modify.

Enter fresh FEL using the procedure verified for your board and connect USB. FEL and UART are different connections.

## 2. Full private backup

This command explicitly uploads and executes the pinned **read-only SRAM NAND reader**. It reads BootROM plus all 131072 physical pages (main + OOB), shows progress, and hashes the saved chunks:

```powershell
.venv\Scripts\python.exe exploit.py --capture --out ..\D103CN-private\backup-01
```

Allow time for the complete 285212672-byte capture. A USB error stops the command and preserves the partial files; an incomplete backup cannot authorize APPLY. This version has no automatic retry or cross-session resume. Do not reset/power off during capture. Never publish `D103CN-private`: the raw dump contains credentials and device data.

Extract **this backup's** verified factory components offline:

```powershell
.venv\Scripts\python.exe exploit.py --extract-factory ..\D103CN-private\backup-01\nand.raw.bin --brom ..\D103CN-private\backup-01\brom.bin --out ..\D103CN-private\factory-01
```

TOC0 is BCH80-corrected and SHA256-pinned. TOC1 copies are BCH32-verified; the required components are pinned individually. The trainer is reconstructed locally from the captured TOC0. No firmware/code is fetched from the Internet.

## 3. Discover and prepare — no PROGRAM enabled

Fully power-cycle, then enter fresh FEL. Use a complete backup acquired less than six hours ago. Preparation rereads 256 physical pages in 32 batches, including random samples, and compares them with the backup. Sampling is not a full identity/consistency proof.

```powershell
.venv\Scripts\python.exe exploit.py --prepare --inputs ..\D103CN-private\factory-01 --backup ..\D103CN-private\backup-01\receipt.json --session ..\D103CN-private\session-01 --accept-unverified-hardware
```

The RAM backend denies PROGRAM and ERASE while locating the file. The planner checks the MBR, ext4 allocation, inode, mapping and active journal, preserves neighboring bytes, and rereads the metadata used in that decision. If it reports `PREPARE_OK`, it has found and checked a candidate, **not installed root**. Any rejection means stop; do not force addresses or substitute another unit's files.

## 4. Explicit one-shot NAND write

Do **not** reset or disconnect after PREPARE. Within ten minutes, using the same powered RAM session:

```powershell
.venv\Scripts\python.exe exploit.py --apply --session ..\D103CN-private\session-01 --accept-unverified-hardware --accept-nand-write
```

This rereads the live guards, permits one paired PROGRAM attempt, flushes, and checks native readback. `NATIVE_READBACK_OK` is not proof of a working stock-OS shell or independent physical recovery. `APPLY-CONSUMED` deliberately prevents repeating the attempt. On a timeout/error preserve everything and investigate; **do not remove the marker or blindly rerun**. There is no ERASE, automatic reboot or automated raw restore command.

After success, boot **normally, not in FEL**. Connect a suitable UART adapter with verified signal levels/pinout, 115200 8N1 and no flow control. Do not apply 5 V to UART signal pins. Press Enter and run:

```sh
id
```

Expected: `uid=0(root)` from the **stock OS**. The bootstrap hook is:

```sh
sh<>/dev/ttyS0>&0&
```

It opens a passwordless physical root shell; it does not create a vendor login/password prompt. Do not publish your `device.conf`.

## 5. Fix competing UART shells

Repeated config sourcing can start multiple short-hook shells: characters are consumed by different readers (`id` becomes `i`/`di`), or output mixes with logs. It does not mean root was lost. The fix used on the first device was replacing the short hook with:

```sh
mkdir /tmp/d103-uart 2>/dev/null && setsid /sbin/getty -n -l /bin/sh -L 115200 ttyS0 &
```

The included `uart-fix.sh` performs that replacement in the **stock root shell**, backing up the config and preserving its factory assignments. Transfer it locally via UART or the existing vacuum AP. For example, serve only this public folder on the PC at `192.168.5.100`:

```powershell
py -3 -m http.server 8765 --bind 192.168.5.100 --directory .
```

In UART, one command at a time (no prompt text):

```sh
curl -f http://192.168.5.100:8765/uart-fix.sh -o /tmp/uart-fix.sh
sha256sum /tmp/uart-fix.sh
```

Compare that hash with the PC's `Get-FileHash .\uart-fix.sh -Algorithm SHA256`, then:

```sh
sh /tmp/uart-fix.sh
```

Stop the HTTP server and perform a **normal reboot** to remove existing competing processes. Verify `id` again. The `/tmp` lock resets on reboot; getty is not automatically respawned if it exits within that session.

## 6. SSH, after UART root works

Follow [SSH + Wi-Fi instructions](https://github.com/Dark-V/D103CN_root/wiki/SSH). The optional package, sources and licenses are in the Wiki, not the root exploit tree. It uses your own Ed25519 client key and generates a new host key on the robot. No systemd, shared root password or shared authorization key is required. The existing prebuilt SSH addon supports only the documented AP/LAN subnets; it is not a WAN firewall. Verify login after a normal reboot before claiming persistence.

Research, original native code, build notes and offline check results: [Wiki](https://github.com/Dark-V/D103CN_root/wiki). The small tree contains only the root runtime, UART fix and instructions. Original project code is MIT; externally installed dependencies keep their own licenses.
