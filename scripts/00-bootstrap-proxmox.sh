#!/usr/bin/env bash
# ============================================================
#  00-bootstrap-proxmox.sh
#  Crée le rôle, l'utilisateur et le token API Terraform sur Proxmox.
#  À exécuter UNE FOIS sur l'hôte Proxmox en tant que root.
# ============================================================
set -euo pipefail

ROLE_ID="TerraformProv"
USER_ID="terraform@pve"
TOKEN_ID="automation"

# --- Privilèges minimaux requis par bpg/proxmox pour gérer VMs et LXC ---
PRIVS="VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit \
VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network \
VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt \
Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit \
Pool.Allocate Sys.Audit Sys.Console Sys.Modify SDN.Use Mapping.Use"

echo "==> Création du rôle ${ROLE_ID}..."
if pveum role list --output-format=json | grep -q "\"roleid\":\"${ROLE_ID}\""; then
  echo "    Rôle déjà présent, mise à jour des privilèges."
  pveum role modify "${ROLE_ID}" -privs "${PRIVS}"
else
  pveum role add "${ROLE_ID}" -privs "${PRIVS}"
fi

echo "==> Création de l'utilisateur ${USER_ID}..."
if pveum user list --output-format=json | grep -q "\"userid\":\"${USER_ID}\""; then
  echo "    Utilisateur déjà présent."
else
  pveum user add "${USER_ID}" --comment "Terraform automation user (TutoTech lab)"
fi

echo "==> Attribution du rôle à l'utilisateur sur le datacenter (/)..."
pveum acl modify / --users "${USER_ID}" --roles "${ROLE_ID}" --propagate 1

echo "==> Génération du token API ${USER_ID}!${TOKEN_ID}..."
echo
echo "⚠️  COPIEZ IMMÉDIATEMENT LE SECRET CI-DESSOUS, IL NE SERA PLUS RÉ-AFFICHÉ ⚠️"
echo

# --privsep 0 → le token hérite des droits de l'utilisateur (plus simple en lab)
pveum user token add "${USER_ID}" "${TOKEN_ID}" --privsep 0 --output-format=json

echo
echo "============================================================"
echo "  Reportez la valeur dans terraform/terraform.tfvars :"
echo
echo "  proxmox_api_token = \"${USER_ID}!${TOKEN_ID}=<secret-affiché-ci-dessus>\""
echo "============================================================"
