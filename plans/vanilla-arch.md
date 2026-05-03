# Plan: Migrate gatherd base from EndeavourOS to vanilla Arch Linux

## Context

gatherd automates first-boot configuration on top of EndeavourOS Sway Community Edition. The
owner wants vanilla Arch as the base for a fully automated (no GUI clicking) install pipeline,
as a prerequisite to a later Artix Linux / s6 migration.

The EOS-specific surface is smaller than expected, with one deep dependency: the `desktop` role
only *patches* Sway config files that `setup_sway_isomode.bash` lays down. Making gatherd
self-contained requires internalizing those base configs before removing the EOS trigger.

---

## Inventory of EOS-specific dependencies

| What | Where | Notes |
|------|-------|-------|
| Calamares hook + `setup_sway_isomode.bash` call | `postinstall` | The install trigger; Sway base config source |
| `setup_dir` path `…/endeavour-setup` | `group_vars/all.yml:3` | Naming artifact |
| Completion marker `/etc/endeavour-setup-complete` | `site.yml:74`, `gatherd.service:7` | Naming artifact |
| Service description "EndeavourOS Sway first-boot setup" | `gatherd.service:2` | Naming artifact |
| `endeavour-post-setup.txt` | `roles/desktop/tasks/main.yml:134` | Naming artifact |
| `eos-update-notifier` package + 4 config tasks | `roles/system/tasks/main.yml:62,178-184,364-365,367` | EOS-only package |
| "Disable EOS greeter" task (`EOS-greeter.conf`) | `roles/desktop/tasks/main.yml:67-75` | EOS-only file |
| Sway base configs (default, autostart_applications, waybar, foot) | *not in repo* | Created by `setup_sway_isomode.bash` |
| Broadcom `wl` driver detection + install | *not in repo* | EOS live ISO detects and offers this; gatherd needs to own it |

---

## Steps

### Step 1 — Rename distro-specific identifiers
*Safe. No behavior change. Can be done on a live EOS install without breaking it.*

- `group_vars/all.yml:3`: `setup_dir` → `/usr/local/lib/gatherd`
- `gatherd.service:2`: description → `"gatherd first-boot setup"`
- `gatherd.service:7`: `ConditionPathExists=!/etc/endeavour-setup-complete` → `!/etc/gatherd-complete`
- `site.yml:74`: marker → `/etc/gatherd-complete`
- `roles/desktop/tasks/main.yml:134`: `endeavour-post-setup.txt` → `gatherd-post-setup.txt`

**Test:** `grep -r 'endeavour' . --include='*.yml' --include='*.service' --include='*.j2'`
returns hits only in README/TODO.

---

### Step 2 — Remove `eos-update-notifier`
*Removes the only EOS-specific package and its four associated tasks.*

Files: `roles/system/tasks/main.yml`
- Remove package entry (line 62)
- Remove system config block (lines 178–184, `/etc/eos-update-notifier.conf`)
- Remove user init task (lines 364–365, `eos-update-notifier -init`)
- Remove user config file task (line 367, `~/.config/eos-update-notifier.conf`)
- Optionally add `informant` (AUR) as a replacement — hooks into pacman to surface Arch news

**Test:** `ansible-playbook --check site.yml` against an Arch VM/container shows no task
failures in the system role.

---

### Step 3 — Replace the EOS greeter task with a generic greetd config
*Removes a dead task; adds the Arch equivalent.*

Files: `roles/desktop/tasks/main.yml`
- Remove "Disable EOS greeter" block (lines 67–75, writes `~/.config/EOS-greeter.conf`)
- Add task to write `/etc/greetd/config.toml` configuring autologin to Sway for the target user

**Test:** greetd auto-logs in to Sway after first-boot setup on a clean Arch VM.

---

### Step 3b — Handle Broadcom `wl` driver
*EOS live install detects Broadcom wifi and offers to install the out-of-tree driver. Vanilla
Arch won't do this, so gatherd must detect and install it, and the bootstrap must handle the
live-environment chicken-and-egg problem.*

**Post-install (Ansible side):**

- `roles/machine_facts/tasks/main.yml`: add `has_broadcom_wifi` probe using `lspci -n`.
  Broadcom wifi PCI IDs include `14e4:4311`, `14e4:4312`, `14e4:4313`, `14e4:4315`,
  `14e4:4318`, `14e4:4319`, `14e4:431a`, `14e4:4320`, `14e4:4324`, `14e4:4325`,
  `14e4:4328`, `14e4:4329`, `14e4:432b`, `14e4:432c`, `14e4:432d`, `14e4:4331`,
  `14e4:4335`, `14e4:4339`, `14e4:43a0`, `14e4:43b1` — match with a regex
  `'14e4:(43[0-9a-f]{2}|431[0-9a-f]|43[0-9a-f]{2})'` or a curated whitelist.

- `roles/hardware/tasks/broadcom_wifi.yml` (new file): install `broadcom-wl-dkms` (AUR),
  write `/etc/modprobe.d/broadcom-wl.conf` to blacklist conflicting `b43`, `b43legacy`,
  `ssb`, `bcma`, `brcmsmac`, `brcmfmac` modules, and run `modprobe wl`.

- `roles/hardware/tasks/main.yml`: add dispatch block mirroring the existing pattern:
  ```yaml
  - name: Import Broadcom wifi tasks
    ansible.builtin.import_tasks: broadcom_wifi.yml
    when: has_broadcom_wifi
  ```

**During bootstrap (live environment):**

The Arch ISO does not ship the `wl` module. If the target machine has only Broadcom wifi
(no ethernet), the bootstrap script cannot reach the network to run `pacstrap`.

Options in order of preference:
1. **Use ethernet for bootstrap** — document this as a requirement in `bootstrap.sh` and
   README; the Ansible role handles wifi after first boot.
2. **Auto-detect and load `wl` in `bootstrap.sh`** — before any network operations, probe
   `lspci -n` for Broadcom PCI IDs, and if found: install `broadcom-wl` (available in
   `archlinux-keyring` / AUR, or carry it on a second USB), blacklist conflicting modules,
   run `modprobe wl`. This is fragile on the live ISO but avoids the ethernet requirement.
3. **Use a custom Arch ISO** with `broadcom-wl` pre-loaded — most robust but requires
   maintaining an ISO build.

Option 1 is the starting point; document the constraint clearly. Option 2 can be added
later if needed.

**Test:** On a machine with a Broadcom wifi card (no ethernet), run `bootstrap.sh` via
ethernet, reboot, confirm wifi is working in the Sway session (NetworkManager / `wl`
module loaded, no conflicting modules).

---

### Step 4 — Internalize the Sway base configuration
*The key step. Makes gatherd self-contained by owning the configs it currently only patches.*

4a. Read `setup_sway_isomode.bash` from the EOS Community Editions repo and identify every
    config file it writes: `~/.config/sway/config`, `config.d/default`,
    `config.d/autostart_applications`, `~/.config/waybar/config`, `~/.config/foot/foot.ini`

4b. Reproduce those files verbatim as Jinja2 templates in `roles/desktop/templates/sway/`.

4c. Add tasks in `roles/desktop/tasks/main.yml` to deploy those templates *before* the
    existing patch tasks. The existing `lineinfile`/`replace`/`blockinfile` tasks stay unchanged.

4d. Remove the `setup_sway_isomode.bash` curl+bash line from `postinstall` (still Calamares
    for now). Confirm the role is fully self-contained.

**Test:** On a fresh Arch VM with no prior Sway config, run the playbook. Sway starts with
correct keybindings, waybar, foot terminal, and all autostart entries.

---

### Step 5 — Replace `postinstall` with an Arch bootstrap
*Swaps the Calamares trigger for a fully scriptable Arch install.*

- Keep `postinstall` intact (rename to `postinstall.eos`) until this step is proven
- **Ethernet required** for bootstrap if the machine has Broadcom wifi (see Step 3b).
  Document this prominently at the top of `bootstrap.sh`.
- Create `bootstrap.sh` that:
  - Drives `archinstall` with a committed `archinstall-config.json` (locale, disk layout,
    user, packages) for zero-interaction disk setup, OR uses a raw `pacstrap` + `arch-chroot`
    script if more control is needed
  - Installs `ansible git` in the new system
  - Clones gatherd to `/usr/local/lib/gatherd`
  - `systemctl enable gatherd` for first-boot execution
- `gatherd.service` ordering already references `greetd.service` — ensure greetd is in
  the archinstall package list

**Test:** Boot an Arch ISO in QEMU, run `bootstrap.sh` with no interaction, reboot, confirm
a working Sway session. Zero keystrokes after launching the script.

---

### Step 6 — Clean up docs and remove EOS artifacts
- `README.md`: replace EOS install steps with Arch bootstrap instructions
- `TODO.md`: prune EOS-specific entries and links
- Delete `postinstall.eos` once `bootstrap.sh` has been proven on multiple machines

**Test:** `grep -rE 'EndeavourOS|endeavour|EOS' . --exclude-dir=.git` returns nothing in
active code paths.

---

## Verification (end-to-end)

1. Boot Arch ISO in QEMU (or bare metal)
2. Run `bash <(curl -fsSL …/bootstrap.sh)` — no further input
3. System reboots, `gatherd.service` fires, playbook completes
4. Sway session is usable, all configured services running, hardware quirks applied
5. `/etc/gatherd-complete` exists; service does not re-run on next boot

---

## Notes for subsequent Artix/s6 migration

Steps 1–6 leave systemd intact. The rename in Step 1 (`/etc/gatherd-complete`,
`/usr/local/lib/gatherd`) means the first-boot marker and service directory are already
init-system-neutral. Steps 2–4 do not add new systemd dependencies. Step 5's bootstrap
script will need a parallel `bootstrap-artix.sh` when that migration happens.
