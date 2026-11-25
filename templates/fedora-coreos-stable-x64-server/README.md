# fedora-coreos-stable-x64-server

Fedora CoreOS (`stable` stream) Ludus template. Genuinely different from
every other template in this repo, not just a variant of the Fedora
Workstation one — CoreOS is an immutable, container-focused OS configured
by **Ignition** instead of Kickstart or cloud-init.

## Credentials: SSH key only, not a password

The `core` user has **no password, ever** — this is CoreOS's design, not
a limitation of this template. `sshd_config` disables password
authentication unconditionally, regardless of anything set in Ignition.
So unlike every other template here (`root`/`alpine`, `localuser`/`password`,
etc.), there's no `ssh_password` variable at all. Instead:

- `keys/id_ed25519` / `keys/id_ed25519.pub` — a fixed keypair committed to
  this repo, matching the same "publicly documented, not a secret" spirit
  as the fixed passwords used elsewhere in this repo. This is a disposable
  lab template; don't reuse this key for anything that matters.
- The public key is baked into `butane.yaml` → `http/config.ign` for the
  `core` user.
- The Packer source block's `ssh_private_key_file` points at the private
  key for its own connection.
- The Ansible provisioner needs **no** `ssh_private_key_file` field of its
  own — checked `packer-plugin-ansible`'s source directly: it has no such
  field, and instead auto-derives `ansible_ssh_private_key_file` from
  whatever key the main communicator already connected with (that's the
  "Using ssh keys from Packer communicator..." line every build in this
  repo logs, regardless of auth method).
- No `ansible_password`/`ansible_sudo_pass` either — `core` has
  passwordless `wheel` sudo by default, so `become` needs nothing extra.

## Butane/Ignition instead of Kickstart

`butane.yaml` is the human-editable source; `http/config.ign` is the
compiled Ignition JSON actually served to the installer (regenerate it
with `butane --strict --pretty butane.yaml -o http/config.ign` after any
edit — don't hand-edit the `.ign` file). It does three things:

1. Sets the `core` user's SSH authorized key.
2. Enables `qemu-guest-agent.service`. Ignition doesn't require the unit
   file to exist yet to create the enablement symlink — the package isn't
   in the base image, but once it's layered in (next point) the symlink's
   already there and it just starts working.
3. Defines `layer-ludus-packages.service`, a oneshot unit that runs
   `rpm-ostree install -y python3 qemu-guest-agent` then reboots.
   `python3` isn't in the base CoreOS image either, and Ansible needs it
   (this playbook uses `ansible.builtin.copy`/`systemd`, not just `raw` -
   those require a real interpreter). `Before=sshd.service` keeps SSH
   from accepting connections on *this* boot before the unit is done -
   it never finishes in the normal sense, since its last action is
   `systemctl reboot`, which is exactly what holds sshd back here.
   `ConditionPathExists=!/etc/ludus-packages-layered` stops it from
   re-running after that reboot.

Net effect: Packer's `ssh_wait_timeout` has to span coreos-installer
writing the disk, the first boot's Ignition run, the package-layering
reboot, and the second boot where SSH and python3 are finally both
present together. Set generously (25m) for that reason.

## Boot media: not driven via kernel args at all

Worth calling out given how much the Fedora Workstation template's build
log fought GRUB2: FCOS's live ISO actually uses a plain
**isolinux/vesamenu** BIOS boot menu — its own `isolinux.cfg` literally
has a comment saying "Press [Tab] message". Confirmed by extracting it
directly (`7z e -so fedora-coreos-*.iso isolinux/isolinux.cfg`), not
assumed from the Workstation lessons carrying over. CoreOS also has its
own supported unattended-install mechanism for exactly this situation —
`coreos.inst.install_dev=` / `coreos.inst.ignition_url=` kernel args,
triggering `coreos-installer` the same way `inst.ks=` triggers Anaconda.

That mechanism is **not what this template ends up using**, though — see
below for why. Documented here anyway because the journey to the final
approach matters for maintaining this template:

1. First attempt appended the kernel args via `<tab>` on the default boot
   line, Rocky-style. Silently did nothing: `coreos.inst.install_dev=sda`
   (a bare device name) turned out to be invalid syntax — `coreos-installer`
   needs the **full path** (`/dev/sda`). The live environment just booted
   normally with nothing happening, indefinitely, no further signal (a
   25-minute timeout with zero change in the log).
2. Fixed the path, tried again — same silent nothing. FCOS's
   `isolinux.cfg` sets `timeout 50` (tenths of a second = **5 seconds**),
   far shorter than other distros' defaults the `boot_wait: 15s`
   convention elsewhere in this repo assumes. By the time Packer started
   typing, the menu had already auto-booted past itself.
3. Reduced `boot_wait` to `3s` — still under that 5s window, in theory.
   Still failed, with a much more informative console this time: the live
   environment's own Ignition explicitly logged `no config provided by
   user`, confirming the kernel-arg edit never landed at all (not even
   garbled — just entirely absent), then auto-logged into a `core` shell
   (stock FCOS live-media behavior, unrelated to anything in this
   template), where the stray keystrokes meant for the boot line landed
   instead and got interpreted as a command (`-bash: da: command not
   found` — a mangled tail of `/dev/sda`). So even 3s wasn't reliably
   winning the race — the live environment can reach a working shell
   *faster* than isolinux's own 5s countdown would suggest, or Packer's
   VNC-connect overhead eats into the margin, or both. Either way, tuning
   `boot_wait` any further is just guessing against a race with no solid
   floor.
4. Stopped racing the menu entirely. Let it boot all the way through on
   its own (isolinux default → kernel → Ignition's "no config" no-op →
   auto-login) to the stable `core@localhost` shell that steps 1–3 kept
   landing on *by accident* anyway — then drive the install the same way
   every other shell-based template in this repo works: type a real
   command at a real prompt,
   `sudo coreos-installer install /dev/sda --ignition-url http://.../config.ign
   && sudo systemctl reboot`. Chaining with `&&` means shell semantics
   (not another blind Packer wait) decide when the reboot happens,
   regardless of how long the actual install takes. `boot_wait` is a
   generous `25s` here on purpose — with no countdown left to race,
   erring long costs nothing. This got `coreos-installer` to actually
   run for the first time (no more garbled/absent command), confirming
   the isolinux-race theory in steps 2–3 was a red herring all along —
   the real fix was always "stop sending keystrokes before a shell
   exists to receive them."
5. `coreos-installer` ran but refused with
   `ERROR: Refusing to fetch Ignition config over HTTP without
   --ignition-hash or --insecure-ignition` — a deliberate safety check
   against tampering with an unauthenticated HTTP fetch, not a bug.
   Packer's `http_directory` server is local and ephemeral (same trust
   tier as the kickstart-over-HTTP setup every Anaconda template in this
   repo already relies on), so `--insecure-ignition` is the appropriate
   fix here, not a real security compromise.

Net effect: this template installs CoreOS via a manually-typed
`coreos-installer` shell command, not via kernel-arg automation — the
opposite of the Workstation/Rocky convention, but the only approach that
survived contact with FCOS's unusually tight live-menu timing.

## Key file permissions get reset on upload

Once the install/boot/layering sequence above actually worked (confirmed
by Packer's own communicator successfully connecting over SSH), the
build still failed — at the very last step, the Ansible provisioner,
with `Permissions 0644 for 'keys/id_ed25519' are too open... This
private key will be ignored`. The key is packaged in this repo and in
the upload tarball at `0600`; Ludus's server-side tar extraction doesn't
preserve that bit, so it lands as `0644` once installed on the Ludus
server. Packer's own Go SSH client (used for the main communicator)
doesn't enforce OpenSSH's strict client-side permission check and
connects fine either way — only the Ansible provisioner's own
`ansible-playbook`/`ssh` subprocess refuses the file. Fixed with a
`shell-local` provisioner (`chmod 600 keys/id_ed25519`) placed right
before the `ansible` provisioner in the build block, so the mode is
always re-asserted locally regardless of what extraction did to it.

## No kickstart-style partitioning

`coreos-installer` has its own fixed, well-tested partition layout and
handles BIOS vs. UEFI boot partitioning internally — unlike the Anaconda
templates in this repo, there's no `biosboot`/GPT gotcha to work around
here at all.

## Using this template in a range

Same as every other non-mainstream-distro template in this repo: VMs
built from this template almost certainly need `unmanaged: true` — there's
no `group_vars` entry for `fedora-coreos` (or any CoreOS variant) in
Ludus core, matching the same `ID=`-based dynamic-inventory-grouping gap
as Alpine and Fedora Workstation. See the repo README's
["Known limitations"](../../README.md#known-limitations).

Also worth remembering when actually using a deployed VM: SSH in with
`-i keys/id_ed25519 core@<ip>`, not a password prompt.

**`<ip>` is not the hostname and not `ip_last_octet` — both are wrong for
this VM.** Confirmed live, reproduced twice on a real deploy: the router's
DNS/`/etc/hosts` are generated from the config's `ip_last_octet` regardless
of `unmanaged` status, but this VM never gets told to use that address —
it's on whatever its DHCP lease actually is, which can differ from
`ip_last_octet` and can change on redeploy. Run `ludus range list` and use
the `ip` field it reports for this VM as `<ip>` above.
