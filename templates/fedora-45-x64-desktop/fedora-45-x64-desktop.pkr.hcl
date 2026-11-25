variable "description" {
  type    = string
  default = "Fedora 45 Workstation (GNOME desktop) x64."
}

variable "icon_path" {
  type    = string
  default = "icon.png"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:a1e916f139a05955b943cf183b020780cca9c399b02b8f5ec4354c9e5c1dff1a"
}

# The operating system. Can be wxp, w2k, w2k3, w2k8, wvista, win7, win8, win10, win11, l24 (Linux 2.4), l26 (Linux 2.6+), solaris or other. Defaults to other.
variable "os" {
  type    = string
  default = "l26"
}

variable "iso_url" {
  type    = string
  default = "https://dl.fedoraproject.org/pub/fedora/linux/releases/45/Server/x86_64/iso/Fedora-Server-netinst-x86_64-45-1.4.iso"
}

variable "vm_cpu_cores" {
  type    = string
  default = "4"
}

variable "vm_disk_size" {
  type    = string
  default = "60G"
}

variable "vm_memory" {
  type    = string
  default = "4096"
}

variable "vm_name" {
  type    = string
  default = "fedora-45-x64-desktop-template"
}

variable "ssh_password" {
  type      = string
  default   = "root"
  sensitive = true
}

variable "ssh_username" {
  type    = string
  default = "root"
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
  template_description = "Fedora 45 Workstation template built ${legacy_isotime("2006-01-02 03:04:05")} username:password => localuser:password (root:root for SSH)"
}

source "proxmox-iso" "fedora" {
  # Unlike Rocky 9's netinst ISO (BIOS/isolinux menu, <tab> appends
  # directly), Fedora 45's netinst ISO boots via GRUB2 even in BIOS mode -
  # confirmed on console, same as the Workstation Live ISO. Fedora has
  # moved to GRUB2 across all its media, not just Live.
  #
  # Rather than editing a pre-existing menuentry (GRUB2 'e' edit mode,
  # cursor navigation, <end>, <f10>) - which a real attempt corrupted into
  # a kernel panic ("Unable to mount root fs"), most likely because <end>
  # and <f10> have no explicit mapping in packer-plugin-proxmox's VNC key
  # driver (bootcommand_driver.go) and fall through as raw, unverified
  # QEMU keycode names - this drops into GRUB's command-line console ('c',
  # a plain, universally-supported key) and types the full linux/initrd/
  # boot sequence from scratch. No cursor movement, no editing, no
  # dependency on keys that may not actually be wired up correctly.
  # inst.stage2 and the bare /images/pxeboot/... paths are copied verbatim
  # from this ISO's actual boot/grub2/grub.cfg (extracted and read
  # directly, not inferred) - `search --set=root -l 'Fedora-S-dvd-x86_64-45'`
  # runs globally before the menu ever renders, so $root is already set by
  # the time we reach the command line, same as it is for the built-in
  # menuentries that also use bare paths.
  boot_command = [
    "<wait10>c",
    "<wait>linux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=Fedora-S-dvd-x86_64-45 inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/fedora-45-workstation-ks.cfg text<enter>",
    "<wait>initrd /images/pxeboot/initrd.img<enter>",
    "<wait>boot<enter>"
  ]
  boot_wait         = "20s"
  boot_key_interval = "100ms"
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

  communicator    = "ssh"
  cores           = "${var.vm_cpu_cores}"
  cpu_type        = "host"
  scsi_controller = "virtio-scsi-single"
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
  ssh_password         = "${var.ssh_password}"
  ssh_username         = "${var.ssh_username}"
  ssh_wait_timeout     = "45m" // Workstation's package set + dnf update -y is much heavier than a minimal server install
  task_timeout         = "20m" // On slow disks the imgcopy operation takes > 1m
}

build {
  sources = ["source.proxmox-iso.fedora"]

  provisioner "ansible" {
    playbook_file = "ansible/reset-ssh-host-keys.yml"
    use_proxy     = false
    user          = "${var.ssh_username}"
    extra_arguments = ["--extra-vars", "{ansible_python_interpreter: /usr/bin/python3, ansible_password: ${var.ssh_password}, ansible_sudo_pass: ${var.ssh_password}}"]
    ansible_env_vars = ["ANSIBLE_HOME=${var.ansible_home}", "ANSIBLE_LOCAL_TEMP=${var.ansible_home}/tmp", "ANSIBLE_PERSISTENT_CONTROL_PATH_DIR=${var.ansible_home}/pc", "ANSIBLE_SSH_CONTROL_PATH_DIR=${var.ansible_home}/cp"]
    skip_version_check = true
  }
}
