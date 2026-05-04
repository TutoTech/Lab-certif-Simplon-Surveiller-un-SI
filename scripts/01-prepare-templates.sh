#!/usr/bin/env bash
# ============================================================
#  01-prepare-templates.sh
#  Télécharge et prépare :
#   - Template VM Debian 13 cloud (VMID 9000)
#   - ISO pfSense CE 2.7
#   - ISO Kali Linux
#   - Template LXC Debian 13
#  À exécuter en root sur l'hôte Proxmox.
# ============================================================
set -euo pipefail

# --- Configuration (à ajuster si nécessaire) ---
TEMPLATE_VMID="${TEMPLATE_VMID:-9000}"
STORAGE_DISK="${STORAGE_DISK:-local-lvm}"
STORAGE_ISO="${STORAGE_ISO:-local}"
NODE_NAME="$(hostname -s)"

DEBIAN_VERSION="13"
DEBIAN_IMAGE="debian-${DEBIAN_VERSION}-genericcloud-amd64.qcow2"
DEBIAN_URL="https://cloud.debian.org/images/cloud/trixie/latest/${DEBIAN_IMAGE}"

PFSENSE_ISO="pfSense-CE-2.7.2-RELEASE-amd64.iso"
PFSENSE_URL="https://atxfiles.netgate.com/mirror/downloads/${PFSENSE_ISO}.gz"

KALI_ISO="kali-linux-2025.1-installer-netinst-amd64.iso"
KALI_URL="https://cdimage.kali.org/kali-2025.1/${KALI_ISO}"

LXC_TEMPLATE="debian-13-standard_13.0-1_amd64.tar.zst"

WORKDIR="/var/tmp/tutotech-lab-prep"
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

# ----------------------------------------------------------------
# 1. Template VM Debian 13
# ----------------------------------------------------------------
echo "==> [1/4] Préparation du template Debian ${DEBIAN_VERSION} (VMID ${TEMPLATE_VMID})"

if qm status "${TEMPLATE_VMID}" >/dev/null 2>&1; then
  echo "    Template VMID ${TEMPLATE_VMID} déjà présent, skip."
else
  if [ ! -f "${DEBIAN_IMAGE}" ]; then
    echo "    Téléchargement de l'image Debian cloud..."
    wget -q --show-progress "${DEBIAN_URL}"
  fi

  # Installer libguestfs-tools pour personnaliser l'image (qemu-guest-agent)
  if ! command -v virt-customize >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq libguestfs-tools
  fi

  echo "    Injection de qemu-guest-agent dans l'image..."
  virt-customize -a "${DEBIAN_IMAGE}" --install qemu-guest-agent --quiet

  echo "    Création de la VM template..."
  qm create "${TEMPLATE_VMID}" \
    --name debian-13-template \
    --memory 2048 \
    --cores 2 \
    --net0 virtio,bridge=vmbr0 \
    --ostype l26 \
    --agent enabled=1 \
    --serial0 socket \
    --vga serial0

  qm importdisk "${TEMPLATE_VMID}" "${DEBIAN_IMAGE}" "${STORAGE_DISK}" --format raw
  qm set "${TEMPLATE_VMID}" --scsihw virtio-scsi-pci --virtio0 "${STORAGE_DISK}:vm-${TEMPLATE_VMID}-disk-0"
  qm set "${TEMPLATE_VMID}" --boot c --bootdisk virtio0
  qm set "${TEMPLATE_VMID}" --ide2 "${STORAGE_DISK}:cloudinit"
  qm template "${TEMPLATE_VMID}"
  echo "    Template Debian créé : VMID ${TEMPLATE_VMID}."
fi

# ----------------------------------------------------------------
# 2. ISO pfSense
# ----------------------------------------------------------------
echo "==> [2/4] Téléchargement de l'ISO pfSense"

ISO_DIR="/var/lib/vz/template/iso"
if [ ! -f "${ISO_DIR}/${PFSENSE_ISO}" ]; then
  cd "${WORKDIR}"
  wget -q --show-progress "${PFSENSE_URL}"
  echo "    Décompression..."
  gunzip "${PFSENSE_ISO}.gz"
  mv "${PFSENSE_ISO}" "${ISO_DIR}/"
  echo "    ISO pfSense placée dans ${ISO_DIR}/${PFSENSE_ISO}."
else
  echo "    ISO pfSense déjà présente."
fi

# ----------------------------------------------------------------
# 3. ISO Kali
# ----------------------------------------------------------------
echo "==> [3/4] Téléchargement de l'ISO Kali"

if [ ! -f "${ISO_DIR}/${KALI_ISO}" ]; then
  cd "${WORKDIR}"
  wget -q --show-progress "${KALI_URL}"
  mv "${KALI_ISO}" "${ISO_DIR}/"
  echo "    ISO Kali placée dans ${ISO_DIR}/${KALI_ISO}."
else
  echo "    ISO Kali déjà présente."
fi

# ----------------------------------------------------------------
# 4. Template LXC Debian
# ----------------------------------------------------------------
echo "==> [4/4] Téléchargement du template LXC Debian"

if pveam list "${STORAGE_ISO}" 2>/dev/null | grep -q "${LXC_TEMPLATE}"; then
  echo "    Template LXC déjà présent."
else
  pveam update >/dev/null
  pveam download "${STORAGE_ISO}" "${LXC_TEMPLATE}"
  echo "    Template LXC téléchargé."
fi

echo
echo "============================================================"
echo "  Préparation terminée."
echo
echo "  Vous pouvez maintenant lancer Terraform depuis votre poste :"
echo "    cd terraform/"
echo "    terraform init && terraform apply"
echo "============================================================"
