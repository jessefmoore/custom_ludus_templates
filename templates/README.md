# Packer templates

Each `templates/<name>/` directory is a standard Ludus Packer template —
same shape as the [Bad Sector Labs source](https://github.com/badsectorlabs/ludus-source-bsl/tree/main/templates).
Templates install per-user, keyed by the `*-template` name in the `.pkr.hcl`
(the `vm_name`, not the folder name — `ludus templates list` reports that
name). Run `ludus templates build -n <name>` after `ludus source add` to
produce the VM image.

| Directory | Template name | Description |
| --- | --- | --- |
| [`alpine-3.24-x64-server/`](alpine-3.24-x64-server/) | `alpine-3.24-x64-server-template` | Alpine Linux 3.24 (`virt` flavor) minimal x64 server. |

See each template's own README for build-specific notes, and the top-level
[README's "Known limitations"](../README.md#known-limitations) section for
anything that applies to *using* a template once it's built.
