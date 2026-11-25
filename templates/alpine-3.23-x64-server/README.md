# alpine-3.23-x64-server

Minimal Alpine Linux 3.23.0 (`virt` flavor, x86_64) Ludus template. Credentials:
`root` / `alpine`. Same approach as [`alpine-3.24-x64-server`](../alpine-3.24-x64-server/)
— see that template's README for the general Alpine-on-Ludus rationale
(no preseed, OpenRC instead of systemd, `python3`/`sudo` not installed by
default). This README only covers what's different about this one.

## Difference from alpine-3.24-x64-server: pre-uploaded ISO

This template references an ISO **already uploaded to Proxmox's ISO
storage**, rather than having Packer download one:

```hcl
boot_iso {
  type              = "ide"
  iso_checksum      = "${var.iso_checksum}"
  iso_file          = "${var.iso_storage_pool}:iso/${var.iso_filename}"
  unmount           = true
  keep_cdrom_device = false
}
```

`iso_file` (format `<storage>:iso/<filename>`) tells the `proxmox-iso`
builder to use an existing file instead of `iso_url`/`iso_download_pve` —
no download step. Before building this template, upload
`alpine-virt-3.23.0-x86_64.iso` to the same Proxmox storage pool Ludus uses
for ISOs (`iso_storage_pool`, injected at build time — whatever pool that
resolves to on your server is where the file needs to live). If you rename
the file or use a different point release, update the `iso_filename`
variable's default and `iso_checksum` to match.

## Version pinning

Same situation and same fix as `alpine-3.24-x64-server`: Alpine's `apk`
branch repo for `v3.23` only ever serves the latest build per package, so
`apk add` during `boot_command` installs whatever's current in that branch
regardless of which exact point-release ISO was used. `boot_command`
overlays `/etc/alpine-release` and `/usr/lib/os-release` with the 3.23.0
values (sourced from Alpine's permanently-archived
`alpine-minirootfs-3.23.0-x86_64.tar.gz`) so the template's advertised
version matches. This is cosmetic, not a true pin — see the 3.24 template's
README for the full explanation of why a true pin isn't achievable through
any supported Alpine channel.

## Using this template in a range

Same as `alpine-3.24-x64-server`: VMs built from this template **must** be
marked `unmanaged: true` in the range config — see the repo README's
["Known limitations"](../../README.md#known-limitations).

**Don't SSH to the hostname or to `ip_last_octet` — both are wrong for this
VM.** Confirmed live: the router's DNS/`/etc/hosts` are generated from the
config's `ip_last_octet` regardless of `unmanaged` status, but this VM never
gets told to use that address — it's on whatever its DHCP lease actually is.
Run `ludus range list` and SSH to the `ip` field it reports for this VM.
