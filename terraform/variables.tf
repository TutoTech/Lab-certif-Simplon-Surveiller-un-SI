variable "proxmox_endpoint" {
  type        = string
  description = "URL de l'API Proxmox (ex: https://pve.example.com:8006/)"
}

variable "proxmox_api_token" {
  type        = string
  description = "API token au format 'user@realm!tokenid=secret'"
  sensitive   = true
}

variable "proxmox_tls_insecure" {
  type        = bool
  description = "Désactiver la vérification du certificat TLS Proxmox (utile si certificat auto-signé)"
  default     = true
}

variable "proxmox_node" {
  type        = string
  description = "Nom du nœud Proxmox sur lequel déployer"
}

variable "lab_bridge" {
  type        = string
  description = "Nom du bridge Linux Proxmox utilisé pour le LAN du lab (isolé)"
  default     = "vmbr1"
}

variable "wan_bridge" {
  type        = string
  description = "Bridge fournissant l'accès WAN à pfSense (typiquement vmbr0)"
  default     = "vmbr0"
}

variable "storage_pool" {
  type        = string
  description = "Storage Proxmox pour les disques des VMs (ex: local-lvm)"
  default     = "local-lvm"
}

variable "iso_storage" {
  type        = string
  description = "Storage Proxmox contenant les ISO et templates LXC (ex: local)"
  default     = "local"
}

variable "ssh_public_key" {
  type        = string
  description = "Clé publique SSH injectée dans les VMs Debian/Kali via cloud-init"
}

variable "lab_domain" {
  type        = string
  description = "Domaine DNS du lab"
  default     = "lab.tutotech.org"
}

variable "lab_subnet" {
  type        = string
  description = "Sous-réseau LAN du lab"
  default     = "10.10.10.0/24"
}

variable "lab_gateway" {
  type        = string
  description = "IP de pfSense côté LAN (passerelle des VMs)"
  default     = "10.10.10.1"
}

variable "debian_template_id" {
  type        = number
  description = "VMID du template Debian 13 préparé par 01-prepare-templates.sh"
  default     = 9000
}

variable "kali_iso" {
  type        = string
  description = "Nom de l'ISO Kali dans le storage iso_storage"
  default     = "kali-linux-2025.1-installer-netinst-amd64.iso"
}

variable "pfsense_iso" {
  type        = string
  description = "Nom de l'ISO pfSense CE dans le storage iso_storage"
  default     = "pfSense-CE-2.7.2-RELEASE-amd64.iso"
}

variable "lxc_template" {
  type        = string
  description = "Template LXC Debian (au format vztmpl du storage iso)"
  default     = "debian-13-standard_13.0-1_amd64.tar.zst"
}
