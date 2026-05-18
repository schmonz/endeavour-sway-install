# Quiet boot on EndeavourOS (systemd-boot + dracut)

Tested on: EndeavourOS, kernel 6.19.10-arch1-1, systemd-boot, dracut, greetd, LUKS.

Two tiers of change are described below:

- **Tier 1** — suppress boot messages with no new packages (quick, reversible)
- **Tier 2** — add Plymouth for a graphical splash screen like Manjaro/Mint (more involved)

Tier 1 is a prerequisite for Tier 2.

---

## Tier 1 — Suppress boot messages

### Step 1 — Edit the kernel cmdline

`/etc/kernel/cmdline` is the single source of truth for boot parameters on this
system. The kernel install hooks read it and stamp its contents into both boot
entries under `/efi/loader/entries/` whenever a kernel is installed or
reinstalled.

Add four parameters to the end of the existing line:

```
quiet loglevel=3 rd.udev.log_level=3 rd.systemd.show_status=auto
```

What each one does:

| Parameter | Effect |
|---|---|
| `quiet` | Tells the kernel to suppress most console messages |
| `loglevel=3` | Sets the kernel ring-buffer print threshold to ERR; only genuine errors surface even if something re-enables console logging |
| `rd.udev.log_level=3` | Same ERR threshold for udev during the dracut initrd phase (suppresses device enumeration chatter around LUKS unlock) |
| `rd.systemd.show_status=auto` | Tells the in-initrd systemd to print unit status lines only on failure; clean boots are silent, broken boots show what failed |

The full updated file should read:

```
nvme_load=YES nowatchdog rw rootflags=subvol=/@ rd.luks.uuid=8161eb54-0770-49d8-ae0e-d2befd09915a root=/dev/mapper/luks-8161eb54-0770-49d8-ae0e-d2befd09915a rd.luks.uuid=b07acbbc-64ee-4dad-a74c-05aa5d5777e9 resume=/dev/mapper/luks-b07acbbc-64ee-4dad-a74c-05aa5d5777e9 zswap.enabled=1 zswap.compressor=zstd zswap.zpool=z3fold zswap.max_pool_percent=20 quiet loglevel=3 rd.udev.log_level=3 rd.systemd.show_status=auto
```

### Step 2 — Regenerate boot entries

```bash
sudo reinstall-kernels
```

This reruns the kernel install hooks, which rewrite both
`/efi/loader/entries/*.conf` files from the updated cmdline.

Verify the change landed:

```bash
sudo grep ^options /efi/loader/entries/ba452d1d9150404d98db101cb77c4b59-6.19.10-arch1-1.conf
```

### Step 3 — Restore verbosity in the fallback entry

Both entries are generated from the same cmdline, so both are now quiet.
The fallback entry should remain verbose so you always have an escape hatch
when something goes wrong. Edit it manually after each `reinstall-kernels`:

```bash
sudo nano /efi/loader/entries/ba452d1d9150404d98db101cb77c4b59-6.19.10-arch1-1-fallback.conf
```

On the `options` line, remove the four parameters added in Step 1
(`quiet loglevel=3 rd.udev.log_level=3 rd.systemd.show_status=auto`),
or replace `loglevel=3` with `loglevel=7` to make verbosity explicit.

To reach the fallback entry at boot: hold **Space** immediately after the
firmware hands off to the bootloader. The systemd-boot menu appears; select
the fallback entry. You can also press **e** on any entry to edit its
parameters for a single boot without permanently changing anything.

### Step 4 (optional) — Hide the boot menu

Currently `/efi/loader/loader.conf` shows the systemd-boot selection menu for
5 seconds on every boot. To skip it by default (like Mint/Manjaro hide their
GRUB menu):

```bash
sudo nano /efi/loader/loader.conf
```

Change:
```
timeout 5
```
to:
```
timeout 0
```

The menu is still reachable by holding **Space** at boot — same muscle memory
as holding Shift for GRUB.

---

## Tier 2 — Plymouth graphical splash (optional)

Plymouth puts an animated logo/spinner on screen from early in the initrd all
the way through to the login greeter, fully covering any residual console
output. This is exactly what Mint and Manjaro do.

Extra complexity on this system comes from three sources:

1. **dracut** instead of mkinitcpio — Plymouth is a dracut module, not a HOOK
2. **LUKS** — Plymouth must own the screen before the passphrase prompt
3. **greetd** — unlike GDM/SDDM/LightDM, greetd does not natively signal
   Plymouth to quit; a small drop-in is needed

### Step 5 — Install Plymouth and a theme

```bash
sudo pacman -S plymouth
```

Browse available themes:

```bash
plymouth-set-default-theme --list
```

EndeavourOS ships `plymouth-theme-endeavouros` in the AUR; BGRT (uses your
firmware's OEM logo) is in the main repos and requires no extra download:

```bash
# Option A — OEM/firmware logo (no AUR needed)
sudo plymouth-set-default-theme bgrt

# Option B — EndeavourOS branded theme
paru -S plymouth-theme-endeavouros
sudo plymouth-set-default-theme endeavouros
```

### Step 6 — Add Plymouth to dracut

Create `/etc/dracut.conf.d/plymouth.conf`:

```bash
sudo tee /etc/dracut.conf.d/plymouth.conf <<'EOF'
# Load Plymouth in the initrd so it owns the screen before LUKS unlock.
# sd-plymouth must come before sd-encrypt in the module chain;
# dracut handles ordering automatically when both are declared here.
add_dracutmodules+=" plymouth "
EOF
```

### Step 7 — Add `splash` to the kernel cmdline

Return to `/etc/kernel/cmdline` (already edited in Step 1) and add `splash`
alongside `quiet`:

```
... quiet splash loglevel=3 rd.udev.log_level=3 rd.systemd.show_status=auto
```

`splash` is the signal Plymouth watches for; without it Plymouth installs into
the initrd but stays inactive.

### Step 8 — Rebuild the initramfs and boot entries

```bash
sudo reinstall-kernels
```

This rebuilds the dracut initramfs (now with the Plymouth module baked in)
**and** rewrites the boot entries with the updated cmdline in one pass.

Re-apply the verbose fallback edit from Step 3 afterwards.

### Step 9 — Tell greetd to hand off to Plymouth cleanly

greetd does not call `plymouth quit` on its own the way GDM/SDDM do. Without
this step Plymouth lingers and the login screen never appears. Add a systemd
drop-in:

```bash
sudo mkdir -p /etc/systemd/system/greetd.service.d
sudo tee /etc/systemd/system/greetd.service.d/plymouth-quit.conf <<'EOF'
[Service]
# Quit Plymouth and hand control of the VT to greetd.
ExecStartPre=/usr/bin/plymouth quit --retain-splash
EOF
```

`--retain-splash` keeps the splash visible for an extra moment while greetd
initialises, avoiding a flash of console text.

### Step 10 — Enable the Plymouth systemd units

```bash
sudo systemctl enable plymouth-start.service
sudo systemctl enable plymouth-read-write.service
sudo systemctl enable plymouth-quit-wait.service
```

### Verify

Reboot. The sequence should be:

1. Firmware POST (nothing changes here)
2. systemd-boot entry selected (instantly if timeout 0, or after Space + menu)
3. Plymouth splash appears — covers LUKS passphrase prompt graphically
4. After unlock: spinner continues while the OS comes up
5. Plymouth fades out as greetd presents the login prompt
6. Log in; desktop loads normally

If the splash does not appear, boot the fallback entry (verbose) and check:

```bash
journalctl -b 0 | grep -i plymouth
```

---

## Reverting

To undo everything and return to the current verbose state:

```bash
# Remove quiet params from cmdline
sudo nano /etc/kernel/cmdline   # remove: quiet splash loglevel=3 rd.udev.log_level=3 rd.systemd.show_status=auto

# Remove Plymouth dracut config (if added)
sudo rm -f /etc/dracut.conf.d/plymouth.conf

# Remove greetd drop-in (if added)
sudo rm -f /etc/systemd/system/greetd.service.d/plymouth-quit.conf

# Rebuild
sudo reinstall-kernels

# Restore boot menu timeout (if changed)
sudo nano /efi/loader/loader.conf   # restore: timeout 5
```
