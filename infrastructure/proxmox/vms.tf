resource "proxmox_virtual_environment_vm" "dnsmasq" {
  name      = "dnsmasq"
  node_name = "pve"
  vm_id     = 100

  on_boot = false

  cpu {
    cores = 1
    type  = "x86-64-v2-AES"
  }

  bios = "seabios"

  operating_system {
    type = "l26"
  }

  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 16
    iothread     = true
  }

  network_device {
    bridge      = "vmbr0"
    mac_address = "BC:24:11:C1:B5:FF"
    firewall    = true
  }
}

resource "proxmox_virtual_environment_vm" "control_plane" {
  name      = "control-plane"
  node_name = "pve"
  vm_id     = 101

  on_boot = false

  cpu {
    cores = 4
    type  = "x86-64-v2-AES"
  }

  bios = "seabios"

  operating_system {
    type = "l26"
  }

  memory {
    dedicated = 5120
  }

  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 32
    iothread     = true
  }

  network_device {
    bridge      = "vmbr0"
    mac_address = "BC:24:11:13:D5:30"
    firewall    = true
  }
}

resource "proxmox_virtual_environment_vm" "worker_01" {
  name      = "worker-01"
  node_name = "pve-i3"
  vm_id     = 102

  on_boot = false

  cpu {
    cores = 1
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096
  }

  bios = "seabios"

  operating_system {
    type = "l26"
  }

  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 32
    iothread     = true
  }

  network_device {
    bridge      = "vmbr0"
    mac_address = "BC:24:11:56:E0:0B"
    firewall    = true
  }
}

resource "proxmox_virtual_environment_vm" "worker_02" {
  name      = "worker-02"
  node_name = "pve-i3"
  vm_id     = 103

  on_boot = false

  cpu {
    cores = 1
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096
  }

  bios = "seabios"

  operating_system {
    type = "l26"
  }

  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 32
    iothread     = true
  }

  network_device {
    bridge      = "vmbr0"
    mac_address = "BC:24:11:21:19:E4"
    firewall    = true
  }
}
