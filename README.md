# Custom Ludus Templates

A [Ludus source](https://docs.ludus.cloud/docs/using-ludus/sources) — a
versioned bundle of Packer templates, served from this git repo, a tarball,
or a local directory. `ludus source add` registers the contents in one step.

This is a templates-only source (a source doesn't need to ship blueprints or
Ansible roles/collections). It starts with an Alpine Linux template that
isn't covered by the [Bad Sector Labs source](https://github.com/badsectorlabs/ludus-source-bsl),
and is meant to grow to hold other custom templates over time.

## Installing

Local directory (works today, no remote needed):

```bash
ludus source add -d ./custom_ludus_templates --id custom-templates
ludus templates build -n alpine-3.24-x64-server-template
```

Once pushed to a git host (GitHub, GitLab, self-hosted — any works):

```bash
ludus source add https://github.com/<you>/custom_ludus_templates
ludus templates build -n alpine-3.24-x64-server-template
```

## What's shipped

| Template | Description |
| --- | --- |
| `alpine-3.24-x64-server-template` | Alpine Linux 3.24 (`virt` flavor) minimal x64 server. Credentials: `root` / `alpine`. See [templates/alpine-3.24-x64-server/README.md](templates/alpine-3.24-x64-server/README.md) for build details. |

## Known limitations

**Any VM built from `alpine-3.24-x64-server-template` must be marked
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
and `windows`. There's no `alpine.yml`. Without a match, Ludus's post-clone
plays fall back to connecting as a `ludus` management user that's never
created on the guest, and the deploy fails with an `UNREACHABLE` error
trying to open `/home/ludus/.ansible/tmp`.

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
