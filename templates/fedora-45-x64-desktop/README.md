# fedora-45-x64-desktop

Fedora 45 Workstation (GNOME desktop) Ludus template, built from the
**Server netinst** ISO — not the Workstation Live ISO; see "Why not Live
media" below — via a kickstart (`inst.ks=`) passed on the boot line, same
Anaconda-based technique as the
[Bad Sector Labs `rocky-9-x64-server`](https://github.com/badsectorlabs/ludus-source-bsl/tree/main/templates/rocky-9-x64-server)
template. The `%packages` kickstart section selects the Workstation
environment group instead of a minimal one — that's what makes this a
desktop template despite booting the same installer medium as a server
build. Credentials: `root`/`root` for Packer's own SSH connection; the
real login account is `localuser`/`password` (wheel/sudo), created via a
proper kickstart `user` directive rather than a `%post useradd` so GNOME
Initial Setup recognizes an admin already exists and doesn't prompt on
first login.

## Why not Live media

The obvious approach — boot the official Workstation **Live** ISO,
pass `inst.ks=` on the boot line — doesn't work, and not for a fixable
boot_command reason. Confirmed against
[Fedora's own wiki](https://fedoraproject.org/wiki/Anaconda/Kickstart/KickstartingFedoraLiveInstallation):
**live media cannot do kickstart installs at all.** Live ISOs are built to
always boot to the desktop; installation is a manual, in-session action
(the "Install to Hard Drive" icon, i.e. `liveinst`), not something a
boot-time kernel parameter can trigger. This was learned the hard way,
burning two full build attempts:

1. First attempt copied Rocky's `<tab> text inst.ks=...` verbatim. It did
   nothing — Fedora's Workstation Live ISO boots via **GRUB2** even in BIOS
   mode, unlike Rocky's isolinux-menu netinst, so `<tab>` isn't the right
   key at all. The build sat at the GRUB menu until aborted.
2. Second attempt fixed that: entered GRUB2 edit mode properly (`e`, then
   `<down>` far more times than the entry has lines so it reliably lands on
   the last line regardless of exact count, `<up>` once to land on
   `linux ...`, `<end>`, append, `<f10>` to boot). The edit mechanics were
   right this time — and it *still* just booted to an idle GNOME desktop
   with an "Install Fedora" icon sitting there. `inst.ks=` was correctly on
   the kernel command line; Live media simply ignores it.

Switching to the Server **netinst** ISO sidesteps the live-media problem —
it's the same Anaconda/kickstart installer as Rocky, with no live desktop
to boot into instead. It does **not**, however, bring back Rocky's simple
isolinux `<tab>`: Fedora 45's netinst ISO *also* boots via GRUB2 (confirmed
on console), not the isolinux-style BIOS menu Rocky 9 still uses — Fedora
has moved to GRUB2 across all its media, live or otherwise, not just Live.

3. Third attempt reused the GRUB2 edit-mode sequence from attempt 2
   against netinst media — and it produced a **kernel panic**
   (`Unable to mount root fs on unknown-block(0,0)`), meaning the edit
   corrupted the entry rather than cleanly appending to it. Checked
   packer-plugin-proxmox's actual VNC key driver
   (`builder/proxmox/common/bootcommand_driver.go`): `<end>` and `<f10>`
   have **no explicit mapping** there — they fall through as raw,
   unverified QEMU keycode names. That's a real gap for exactly this
   technique (editing an existing multi-line entry depends on both of
   those keys working correctly), and a very plausible source of the
   corruption.
4. Fourth attempt (current) abandons editing an existing menuentry
   entirely. Instead it drops into **GRUB's command-line console** (`c` —
   a plain, universally-supported key, no special-key mapping concerns)
   and types the full `linux`/`initrd`/`boot` sequence from scratch at a
   blank prompt. No cursor navigation, no `<end>`, no `<f10>`. The exact
   `inst.stage2=hd:LABEL=...` value and bare `/images/pxeboot/...` paths
   were copied verbatim from this ISO's real `boot/grub2/grub.cfg`
   (extracted and read directly — `7z e -so Fedora-Server-netinst-...iso
   boot/grub2/grub.cfg` — not inferred from assumptions about Fedora's
   installer layout). That file also confirmed `search --set=root -l
   'Fedora-S-dvd-x86_64-45'` runs globally before the menu ever renders,
   so `$root` is already set by the time the command line is reached,
   same as it is for the built-in menuentries that also use bare paths.
5. That fixed the boot sequence (clean dracut boot, no panic), but
   Anaconda then stopped at the Installation Destination step with
   **"Kickstart insufficient"** on the text-mode install hub. Root cause:
   Fedora 45's Anaconda defaults to GPT disk labeling even for BIOS boot,
   and GPT + BIOS needs a dedicated `biosboot` partition for GRUB2's
   `core.img` — without one, Anaconda can't resolve where to put the
   bootloader. Added `part biosboot --fstype="biosboot" --size=1` plus an
   explicit `bootloader --location=mbr --boot-drive=sda`. Rocky 9's
   kickstart (adapted for everything else in this template) never needed
   this, most likely because its older Anaconda still defaults to
   MBR/msdos labeling for a disk this size.
6. That build succeeded and converted to a template cleanly - but
   deploying a clone into a real Ludus range (to validate it, not just
   the Packer build) surfaced two more issues, both found by logging into
   the clone directly at the Proxmox console rather than over SSH (which
   was itself unreachable at the time - *mis*-attributed then to an
   unrelated, external network-routing side effect of the range's router
   having been recreated, since the Alpine template in the same range was
   equally unreachable and the router's own deploy log showed zero
   failures. Root cause confirmed later, live, against this exact
   range/template combo: it's the `unmanaged: true`-vs-DNS mismatch
   documented under "Using this template in a range" below, not a routing
   fault. `router deploy log showing zero failures` was actually the
   correct signal all along - the router really had no failures; it just
   also had no idea the VM wasn't at the address its own DNS said it was):
   - It booted to a **text login**, not GDM. `@^workstation-product-environment`
     doesn't reliably flip the default systemd target on its own; `%post`
     now sets it explicitly with `systemctl set-default graphical.target`.
   - `sshd` was confirmed active and listening at the console, yet
     unreachable - because **firewalld** was still enabled at its install
     default and had never been addressed. Rocky's kickstart (which this
     one is otherwise adapted from) explicitly removes firewalld in
     `%post`; that line never got carried over. Added it back.

   Rebuilt with both fixes, redeployed into the same range, and confirmed
   at the console: **GDM login screen**, booting correctly to
   `graphical.target`. This is the current, working state of the template.

## Netinst specifics

- `url --mirrorlist=...` (not `repo`/`cdrom`) is the kickstart's *primary*
  install source — netinst, unlike Rocky's "minimal" ISO, bundles no
  packages at all, so everything (base system included) comes from the
  network repo.
- `@^workstation-product-environment` (not `@^minimal-environment`) pulls
  in GNOME + GDM. No `skipx` — we want the graphical target.
- `openssh-server` isn't enabled by default on Workstation, so it's
  explicitly listed in `%packages` and enabled via `services --enabled=`.
- `ansible/reset-ssh-host-keys.yml` targets `sshd.service`, not `ssh.service`
  — that's the RHEL/Fedora-family systemd unit name for the SSH daemon,
  different from Debian/Ubuntu's `ssh.service`. Copying the Debian version
  of this playbook as-is would silently no-op the `Before=` ordering
  against a unit name that doesn't exist.

## Resource defaults

Bumped up from the server templates' minimal defaults for a full desktop:
4 cores, 4GB RAM, 60GB disk. `ssh_wait_timeout` is 45m (vs. 15–30m
elsewhere) since Workstation's package set plus the `%post dnf update -y`
takes meaningfully longer than a minimal server install.

## Using this template in a range

VMs built from this template almost certainly **must** be marked
`unmanaged: true` in the range config, same as the Alpine templates in
this repo — see the repo README's
["Known limitations"](../../README.md#known-limitations). Checked Ludus's
`group_vars` directly: it ships `almalinux`, `centos`, `debian`, `kali`,
`macos`/`osx`, `rhel`, `rocky`, `ubuntu`, and `windows` — no `fedora.yml`.
Ludus's dynamic inventory groups a Linux VM by the literal OS `ID` the
qemu-guest-agent reports from `/etc/os-release` (`ID=fedora` here), so
without a matching `group_vars` file, the same `ansible_user` fallback
failure that affects Alpine applies here too — confirmed live, not just
inferred from the missing file.

**Don't SSH to the hostname or to `ip_last_octet` — both are wrong for this
VM.** Confirmed live, reproduced twice on a real deploy: the router's
DNS/`/etc/hosts` are generated from the config's `ip_last_octet` regardless
of `unmanaged` status, but this VM never gets told to use that address —
it's on whatever its DHCP lease actually is, which can differ from
`ip_last_octet` and can change on redeploy. (This is what the "Why not Live
media" section above originally mis-blamed on an unrelated routing issue —
it wasn't; it's this.) Run `ludus range list` and SSH to the `ip` field it
reports for this VM. Details: repo README's
["Known limitations"](../../README.md#known-limitations).
