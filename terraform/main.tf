# ============================================================
#  TutoTech Lab — Infrastructure as Code
#  Provider : bpg/proxmox
# ============================================================

# ----------------------------------------------------------------------
# 1. pfSense — VM (FreeBSD, créée éteinte avec ISO attachée)
# ----------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "pfsense" {
  name        = "pfsense-lab"
  description = "TutoTech lab - pfSense firewall + Suricata + WireGuard"
  tags        = ["tutotech", "lab", "firewall"]
  node_name   = var.proxmox_node
  vm_id       = 100
  on_boot     = true
  started     = false # démarré manuellement après l'install console

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 2048
  }

  # Disque
  disk {
    datastore_id = var.storage_pool
    interface    = "virtio0"
    size         = 20
    file_format  = "raw"
    iothread     = true
  }

  # CD/DVD avec l'ISO pfSense
  cdrom {
    file_id   = "${var.iso_storage}:iso/${var.pfsense_iso}"
    interface = "ide2"
  }

  # WAN
  network_device {
    bridge = var.wan_bridge
    model  = "virtio"
  }

  # LAN
  network_device {
    bridge = var.lab_bridge
    model  = "virtio"
  }

  operating_system {
    type = "other" # FreeBSD
  }

  serial_device {} # console série pour console noVNC fluide
}

# ----------------------------------------------------------------------
# 2. VM apps — Debian 13 (Docker host)
# ----------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "apps" {
  name        = "apps-lab"
  description = "TutoTech lab - Hôte applicatif Docker (Traefik + Moodle + WP + AdminGo)"
  tags        = ["tutotech", "lab", "apps"]
  node_name   = var.proxmox_node
  vm_id       = 110
  on_boot     = true
  started     = true

  # Clone du template Debian 13
  clone {
    vm_id = var.debian_template_id
    full  = true
  }

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = var.storage_pool
    interface    = "virtio0"
    size         = 40
    file_format  = "raw"
    iothread     = true
  }

  network_device {
    bridge = var.lab_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  agent {
    enabled = true
  }

  initialization {
    datastore_id = var.storage_pool
    interface    = "ide0"

    ip_config {
      ipv4 {
        address = "10.10.10.10/24"
        gateway = var.lab_gateway
      }
    }

    user_account {
      username = "debian"
      keys     = [var.ssh_public_key]
    }

    dns {
      servers = [var.lab_gateway]
      domain  = var.lab_domain
    }
  }

  depends_on = [proxmox_virtual_environment_vm.pfsense]
}

# ----------------------------------------------------------------------
# 3. LXC wazuh — Debian 13 (SIEM all-in-one)
# ----------------------------------------------------------------------
resource "proxmox_virtual_environment_container" "wazuh" {
  description   = "TutoTech lab - Wazuh manager + indexer + dashboard"
  tags          = ["tutotech", "lab", "siem"]
  node_name     = var.proxmox_node
  vm_id         = 120
  start_on_boot = true
  started       = true
  unprivileged  = false # Wazuh indexer nécessite des capacités systèmes

  # LXC privilégié + features nécessaires à Wazuh indexer (mlock pour OpenSearch)
  features {
    nesting = true
  }

  cpu {
    cores = 4
  }

  memory {
    dedicated = 6144
    swap      = 2048
  }

  disk {
    datastore_id = var.storage_pool
    size         = 50
  }

  operating_system {
    template_file_id = "${var.iso_storage}:vztmpl/${var.lxc_template}"
    type             = "debian"
  }

  network_interface {
    name     = "eth0"
    bridge   = var.lab_bridge
    firewall = false
  }

  initialization {
    hostname = "wazuh-lab"

    ip_config {
      ipv4 {
        address = "10.10.10.20/24"
        gateway = var.lab_gateway
      }
    }

    dns {
      servers = [var.lab_gateway]
      domain  = var.lab_domain
    }

    user_account {
      keys     = [var.ssh_public_key]
      password = random_password.wazuh_root.result
    }
  }

  depends_on = [proxmox_virtual_environment_vm.pfsense]
}

resource "random_password" "wazuh_root" {
  length  = 32
  special = false # caractères spéciaux fragiles dans les LXC pveconf
}

# ----------------------------------------------------------------------
# 4. VM kali — attaquant pour les scénarios de validation
# ----------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "kali" {
  name        = "kali-lab"
  description = "TutoTech lab - Poste attaquant Kali (rejeu MITRE ATT&CK)"
  tags        = ["tutotech", "lab", "attacker"]
  node_name   = var.proxmox_node
  vm_id       = 199
  on_boot     = false # démarré à la demande
  started     = false

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = var.storage_pool
    interface    = "virtio0"
    size         = 30
    file_format  = "raw"
    iothread     = true
  }

  cdrom {
    file_id   = "${var.iso_storage}:iso/${var.kali_iso}"
    interface = "ide2"
  }

  network_device {
    bridge = var.lab_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  serial_device {}
}
