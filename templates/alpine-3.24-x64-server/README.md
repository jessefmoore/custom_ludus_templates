# alpine-3.24-x64-server

Minimal Alpine Linux 3.24.3 (`virt` flavor, x86_64) Ludus template. Credentials:
`root` / `alpine`.

## Why this looks different from the Debian/Ubuntu templates

Alpine has no preseed file and no systemd:

- The `virt` ISO boots straight to an unauthenticated root shell, not an
  installer menu, so the whole unattended install is driven by typing
  commands at that shell (`boot_command`) instead of serving a preseed or
  cloud-init `user-data` file over HTTP. There's no `http/` directory here.
- Host-key regeneration on first boot uses an OpenRC `/etc/local.d` script
  + `rc-update add local default` instead of a systemd oneshot unit
  (`ansible/reset-ssh-host-keys.yml`).
- `python3` isn't installed by default, so it's `apk add`-ed during
  `boot_command`, before the Ansible provisioner needs it.
- Neither is `sudo` — but Ludus's docs list it as a hard template
  requirement regardless of whether the default account is already root:
  Ludus's post-clone bootstrap play uses a sudo-escalated step to create
  its own dedicated `ludus` management account, and silently skips (then
  fails further downstream) if `sudo` isn't installed. `apk add`-ed
  alongside `python3`.
- `/etc/alpine-release` and `/etc/os-release` get overwritten at the end of
  `boot_command` to say `3.24.3` explicitly — see "Version pinning" below.

## Files

```
alpine-3.24-x64-server.pkr.hcl   Packer template (proxmox-iso builder)
ansible/reset-ssh-host-keys.yml  OpenRC-based first-boot SSH host key reset
icon.png                         256x256 PNG shown in the Ludus template list (add your own)
```

`icon.png` is a plain placeholder (flat-color mountain glyph, hand-built
with a raw PNG writer since no image tooling was available) — swap it for
a real Alpine logo asset if you want something nicer; Ludus just displays
it in the template list.

## Installing

See the [repo README](../../README.md#installing) for the `ludus source add`
commands. Watch the build with `ludus templates logs` (or `GET
/templates/logs` if you're hitting the API directly).

## Using this template in a range

Credentials are `root` / `alpine`. VMs built from this template **must** be
marked `unmanaged: true` in the range config — see the repo README's
["Known limitations"](../../README.md#known-limitations) for why (short
version: Ludus has no `group_vars` for Alpine, so its post-clone management
plays can't connect, and skipping them via `unmanaged: true` is the fix).

## Version pinning

`iso_url`/`iso_checksum` are pinned to the 3.24.3 **ISO** (released
2026-10-21), but that only pins which installer image boots. Alpine's `apk`
branch repo (`.../v3.24/main`) serves only the latest build per package —
there's no historical per-point-release index like Debian's
`snapshot.debian.org` — so `apk update`/`apk add` during `boot_command`
always pulls whatever's newest in the `v3.24` line regardless of the ISO.
As of this writing that's 3.24.4, even though the ISO says 3.24.3.

The `boot_command` corrects just `/etc/alpine-release` and
`/etc/os-release` to say `3.24.3` (sourced from Alpine's permanently
archived minirootfs tarball for that release — unlike the apk repo, the
`releases/` artifact tree keeps every past ISO/minirootfs indefinitely).
**This is cosmetic, not a true pin**: the kernel, OpenRC, and every
`apk`-installed package (`python3`, `sudo`, `qemu-guest-agent` above) are
still whatever's current in the branch at build time — Alpine has no
supported mechanism to pin those to an exact point release (confirmed: the
live apk repo for `v3.24` has already dropped the 3.24.3 build of
`alpine-base`; only the newest is ever kept). Doing a true pin would mean
hand-building the system from the bare minirootfs (no kernel, bootloader,
or init system included) instead of the ISO installer — real engineering
risk for a benefit that still wouldn't cover the add-on packages anyway.

Bump `iso_url` and `iso_checksum` together when you want a newer point
release — checksum comes from the matching `.iso.sha256` file at
`https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/x86_64/`. Update the
two `echo`/`printf` lines in `boot_command` to match.
- The boot_command assumes the NIC comes up as `eth0` and the install disk
  as `/dev/sda` (forced by `scsi_controller = "virtio-scsi-single"` +
  `disks.type = "scsi"`). If you change the controller/disk type, the
  `setup-disk`/`mount` steps need updating too.
- SSH as `root` is intentional (matches Alpine's own minimal-image
  convention). `sudo` is still installed per Ludus's requirements (see
  above) even though this account doesn't need it to escalate itself.
