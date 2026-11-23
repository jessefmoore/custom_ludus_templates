variable "description" {
  type    = string
  default = "Alpine Linux 3.24 (virt) minimal x64 server."
}

variable "icon_path" {
  type    = string
  default = "icon.png"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:cdc1bc0efc64d8d611bf3733f54868172a545888dfd726f518bf279bcb0ff1af"
}

# The operating system. Can be wxp, w2k, w2k3, w2k8, wvista, win7, win8, win10, win11, l24 (Linux 2.4), l26 (Linux 2.6+), solaris or other. Defaults to other.
variable "os" {
  type    = string
  default = "l26"
}

variable "iso_url" {
  type    = string
  default = "https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/x86_64/alpine-virt-3.24.3-x86_64.iso"
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
  default = "1024"
}

variable "vm_name" {
  type    = string
  default = "alpine-3.24-x64-server-template"
}

variable "ssh_password" {
  type      = string
  default   = "alpine"
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
  template_description = "Alpine Linux 3.24 template built ${legacy_isotime("2006-01-02 03:04:05")} username:password => root:alpine"
}

source "proxmox-iso" "alpine" {
  # Alpine's "virt" ISO boots straight to an unauthenticated root shell -
  # there is no installer menu, so the whole unattended install is driven
  # by typing commands at that shell instead of a preseed/answerfile.
  boot_command = [
    "root<enter><wait>",
    "ifconfig eth0 up && udhcpc -i eth0<enter><wait5s>",
    "setup-alpine -q<enter><wait>",
    # setup-alpine -q still prompts for keyboard layout + variant.
    "us<enter>",
    "us<enter><wait10s>",
    "setup-timezone -z UTC<enter><wait>",
    "setup-sshd -c openssh<enter><wait>",
    "setup-disk -m sys<enter>",
    # Accept the only disk offered (sda, via the virtio-scsi-single controller).
    "<enter>",
    "y<enter><wait15s>",
    "mount /dev/sda3 /mnt<enter><wait>",
    "echo 'PermitRootLogin yes' >> /mnt/etc/ssh/sshd_config<enter>",
    # Reboot into the installed system so Packer can SSH in.
    "reboot<enter><wait30s>",
    "root<enter><wait>",
    "echo 'root:${var.ssh_password}' | chpasswd<enter>",
    "sed -i 's:#\\(.*/v.*/community\\):\\1:' /etc/apk/repositories<enter>",
    "apk update<enter><wait5s>",
    # sudo is a hard Ludus template requirement: its post-clone bootstrap
    # play creates a dedicated "ludus" management account via a
    # sudo-escalated step, and silently skips (then fails later) if sudo
    # isn't present, even though our ssh_username is already root.
    "apk add python3 qemu-guest-agent sudo<enter><wait10s>",
    # Embed an unexpanded $(...) in the init script so OpenRC resolves the
    # real virtio-serial port number at service-start time, since the
    # vportNpM index isn't fixed across VM configs.
    "sed -i 's:/dev/virtio-ports/org.qemu.guest_agent.0:$(find /dev/vport* | head -n 1):' /etc/init.d/qemu-guest-agent<enter>",
    "rc-update add qemu-guest-agent<enter>",
    "rc-service qemu-guest-agent start<enter>",
  ]
  boot_key_interval = "100ms"
  boot_wait          = "15s"

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
  ssh_wait_timeout     = "15m"
  task_timeout         = "20m" // On slow disks the imgcopy operation takes > 1m
}

build {
  sources = ["source.proxmox-iso.alpine"]

  provisioner "ansible" {
    playbook_file = "ansible/reset-ssh-host-keys.yml"
    use_proxy     = false
    user          = "${var.ssh_username}"
    extra_arguments = ["--extra-vars", "{ansible_python_interpreter: /usr/bin/python3, ansible_password: ${var.ssh_password}, ansible_sudo_pass: ${var.ssh_password}}"]
    ansible_env_vars = ["ANSIBLE_HOME=${var.ansible_home}", "ANSIBLE_LOCAL_TEMP=${var.ansible_home}/tmp", "ANSIBLE_PERSISTENT_CONTROL_PATH_DIR=${var.ansible_home}/pc", "ANSIBLE_SSH_CONTROL_PATH_DIR=${var.ansible_home}/cp"]
    skip_version_check = true
  }
}
