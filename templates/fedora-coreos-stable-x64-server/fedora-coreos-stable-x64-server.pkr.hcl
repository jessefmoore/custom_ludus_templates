variable "description" {
  type    = string
  default = "Fedora CoreOS (stable stream) x64 server."
}

variable "icon_path" {
  type    = string
  default = "icon.png"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:89172c8f99eb3a9f699027d68077918c107b0fd24999404553267170bea2d844"
}

# The operating system. Can be wxp, w2k, w2k3, w2k8, wvista, win7, win8, win10, win11, l24 (Linux 2.4), l26 (Linux 2.6+), solaris or other. Defaults to other.
variable "os" {
  type    = string
  default = "l26"
}

variable "iso_url" {
  type    = string
  default = "https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/45.20261030.3.1/x86_64/fedora-coreos-45.20261030.3.1-live-iso.x86_64.iso"
}

variable "vm_cpu_cores" {
  type    = string
  default = "2"
}

variable "vm_disk_size" {
  type    = string
  default = "20G"
}

variable "vm_memory" {
  type    = string
  default = "2048"
}

variable "vm_name" {
  type    = string
  default = "fedora-coreos-stable-x64-server-template"
}

# CoreOS's "core" user is SSH-key-only, by design - there is no password
# login, ever, regardless of anything set here or in Ignition. ssh_password
# does not exist as a variable for this template; see ssh_private_key_file
# below instead.
variable "ssh_username" {
  type    = string
  default = "core"
}

# This block has to be in each file or packer won't be able to use the variables
variable "proxmox_url" {
  type = string
}
variable "proxmox_host" {
  type = string
}
variable "proxmox_username" {
  type = string
}
variable "proxmox_password" {
  type      = string
  sensitive = true
}
variable "proxmox_storage_pool" {
  type = string
}
variable "proxmox_storage_format" {
  type = string
}
variable "proxmox_skip_tls_verify" {
  type = bool
}
variable "proxmox_pool" {
  type = string
}
variable "iso_storage_pool" {
  type = string
}
variable "ansible_home" {
  type = string
}
variable "ludus_nat_interface" {
  type = string
}
####

locals {
  template_description = "Fedora CoreOS stable template built ${legacy_isotime("2006-01-02 03:04:05")} - key-only SSH, user: core (see keys/id_ed25519 in this template dir)"
}

source "proxmox-iso" "fedora-coreos" {
  # Not fighting isolinux's boot menu at all (see README "Boot media" -
  # that approach was abandoned after two failed attempts at tuning
  # boot_wait against a 5s menu timeout that the live environment's own
  # boot-to-shell time could beat just as easily). Instead: let the ISO
  # boot completely normally to its live "core" auto-login shell (FCOS
  # live media always does this, with no Ignition config present, by
  # design - the "Ignition: no config provided by user" line confirms
  # it's just the stock live environment, not a stuck/broken boot), then
  # drive the install the same way every other template in this repo
  # drives shell-based provisioning: type real commands at a real prompt.
  # `&&` chains install -> reboot so shell sequencing (not a blind Packer
  # wait) governs timing regardless of how long coreos-installer takes.
  boot_command = [
    "<wait20s>sudo coreos-installer install /dev/sda --ignition-url http://{{ .HTTPIP }}:{{ .HTTPPort }}/config.ign --insecure-ignition && sudo systemctl reboot<enter>"
  ]
  boot_key_interval = "100ms"
  # Generous settle time before typing anything - no competing timeout
  # to race here, so erring long costs nothing.
  boot_wait         = "25s"
  http_directory    = "./http"

  boot_iso {
    type              = "ide"
    iso_checksum      = "${var.iso_checksum}"
    iso_url           = "${var.iso_url}"
    iso_storage_pool  = "${var.iso_storage_pool}"
    iso_download_pve  = true
    unmount           = true
    keep_cdrom_device = false
  }

  communicator           = "ssh"
  ssh_private_key_file   = "keys/id_ed25519"
  cores                  = "${var.vm_cpu_cores}"
  cpu_type               = "host"
  scsi_controller        = "virtio-scsi-single"
  disks {
    disk_size    = "${var.vm_disk_size}"
    format       = "${var.proxmox_storage_format}"
    storage_pool = "${var.proxmox_storage_pool}"
    type         = "scsi"
    discard      = true
    io_thread    = true
  }
  pool                     = "${var.proxmox_pool}"
  insecure_skip_tls_verify = "${var.proxmox_skip_tls_verify}"
  memory                   = "${var.vm_memory}"
  network_adapters {
    bridge = "${var.ludus_nat_interface}"
    model  = "virtio"
  }
  node                 = "${var.proxmox_host}"
  os                   = "${var.os}"
  password             = "${var.proxmox_password}"
  proxmox_url          = "${var.proxmox_url}"
  template_description = "${local.template_description}"
  username             = "${var.proxmox_username}"
  vm_name              = "${var.vm_name}"
  ssh_username         = "${var.ssh_username}"
  # Generous: coreos-installer writing the disk, Ignition's first boot,
  # rpm-ostree layering python3+qemu-guest-agent over the network, and the
  # reboot that applies them all have to happen before SSH is reachable
  # with python3 actually present.
  ssh_wait_timeout     = "25m"
  task_timeout         = "20m" // On slow disks the imgcopy operation takes > 1m
}

build {
  sources = ["source.proxmox-iso.fedora-coreos"]

  # Ludus's server-side tar extraction doesn't preserve the 0600 mode this
  # key is packaged with (confirmed live: it lands as 0644) - OpenSSH's
  # strict client-side permission check then refuses to load it for the
  # ansible provisioner's own ssh subprocess, even though Packer's own Go
  # ssh client (used for the main communicator) doesn't enforce that and
  # connects fine regardless. Re-assert the mode locally right before
  # Ansible needs it.
  provisioner "shell-local" {
    inline = ["chmod 600 keys/id_ed25519"]
  }

  provisioner "ansible" {
    playbook_file = "ansible/reset-ssh-host-keys.yml"
    use_proxy     = false
    user          = "${var.ssh_username}"
    # No ssh_private_key_file here - that's not a field this provisioner
    # recognizes at all (checked packer-plugin-ansible's source directly).
    # It automatically reuses whatever key the communicator connected
    # with via its own -e ansible_ssh_private_key_file injection, matching
    # the "Using ssh keys from Packer communicator..." line every build in
    # this repo logs regardless of auth method.
    # No ansible_password/ansible_sudo_pass - "core" is SSH-key-only, and
    # has passwordless NOPASSWD wheel sudo by default on CoreOS, so
    # `become` needs no password either.
    extra_arguments = ["--extra-vars", "{ansible_python_interpreter: /usr/bin/python3}"]
    ansible_env_vars = ["ANSIBLE_HOME=${var.ansible_home}", "ANSIBLE_LOCAL_TEMP=${var.ansible_home}/tmp", "ANSIBLE_PERSISTENT_CONTROL_PATH_DIR=${var.ansible_home}/pc", "ANSIBLE_SSH_CONTROL_PATH_DIR=${var.ansible_home}/cp"]
    skip_version_check = true
  }
}
