# Custom Ludus Templates

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A [Ludus source](https://docs.ludus.cloud/docs/using-ludus/sources) — a
versioned bundle of Packer templates, served from this git repo, a tarball,
or a local directory. `ludus source add` registers the contents in one step.

This is a templates-only source (a source doesn't need to ship blueprints or
Ansible roles/collections). It covers Linux distros and editions not
shipped by the [Bad Sector Labs source](https://github.com/badsectorlabs/ludus-source-bsl)
(Alpine; Fedora Workstation), and is meant to grow to hold other custom
templates over time.

## Installing

Local directory (works today, no remote needed):

```bash
ludus source add -d ./custom_ludus_templates --id custom-templates
ludus templates build -n alpine-3.24-x64-server-template
```

Or straight from this repo:

```bash
ludus source add https://github.com/jessefmoore/custom_ludus_templates
ludus templates build -n alpine-3.24-x64-server-template
```

## What's shipped

| Template | Description |
| --- | --- |
| `alpine-3.24-x64-server-template` | Alpine Linux 3.24 (`virt` flavor) minimal x64 server. Credentials: `root` / `alpine`. See [templates/alpine-3.24-x64-server/README.md](templates/alpine-3.24-x64-server/README.md) for build details. |
| `alpine-3.23-x64-server-template` | Alpine Linux 3.23 (`virt` flavor) minimal x64 server. Credentials: `root` / `alpine`. Builds from an ISO you upload yourself rather than one Packer downloads — see [templates/alpine-3.23-x64-server/README.md](templates/alpine-3.23-x64-server/README.md). |
| `fedora-45-x64-desktop-template` | Fedora 45 Workstation (GNOME desktop) x64. Credentials: `localuser` / `password` (wheel/sudo); `root` / `root` for Packer's own build-time SSH. See [templates/fedora-45-x64-desktop/README.md](templates/fedora-45-x64-desktop/README.md) for the build's history — six attempts, each a genuinely different fix. |
| `fedora-coreos-stable-x64-server-template` | Fedora CoreOS (`stable` stream) x64, immutable/container-focused server. SSH-key-only login as `core` (no password, ever) — key shipped at `templates/fedora-coreos-stable-x64-server/keys/id_ed25519`. Configured via Ignition, not kickstart; python3 and qemu-guest-agent are layered on top of the base image via `rpm-ostree`. See [templates/fedora-coreos-stable-x64-server/README.md](templates/fedora-coreos-stable-x64-server/README.md) for why this one installs via a typed shell command instead of kernel-arg automation. |

## Known limitations

**Any VM built from any template in this repo must be marked
`unmanaged: true` in its range-config entry:**

```yaml
ludus:
  - vm_name: "{{ range_id }}-alpine"
    template: alpine-3.24-x64-server-template
    vlan: 10
    ip_last_octet: 10
    ram_gb: 1
    cpus: 2
    linux: true
    unmanaged: true   # required — see below
```

Why: Ludus's core range-management Ansible identifies a Linux VM's
connection credentials by distro, using `group_vars` files it ships for
`debian`, `ubuntu`, `kali`, `rocky`, `rhel`, `centos`, `almalinux`, `macos`,
and `windows`. There's no `alpine.yml` and no `fedora.yml` either (checked
directly, not assumed — same missing-group_vars failure confirmed live for
both). Without a match, Ludus's post-clone plays fall back to connecting
as a `ludus` management user that's never created on the guest, and the
deploy fails with an `UNREACHABLE` error trying to open
`/home/ludus/.ansible/tmp`.

`unmanaged: true` excludes the VM from those plays entirely, which also means
Ludus's own static-IP-assignment step gets skipped — the VM keeps whatever
IP it gets via DHCP from the range's router instead of the config's
`ip_last_octet`. If you need a predictable static IP, set it yourself inside
the guest (e.g. during the template's own Packer provisioning, or manually
over SSH after deploy) rather than relying on Ludus to assign it.

This isn't specific to Alpine — the same applies to any template built on a
distro outside Ludus's recognized `group_vars` list.

## Local development workflow

```bash
ludus source add -d ./custom_ludus_templates --id custom-templates   # first time
ludus source update custom-templates -d ./custom_ludus_templates     # after edits
```

Full reference: [Sources](https://docs.ludus.cloud/docs/using-ludus/sources).
