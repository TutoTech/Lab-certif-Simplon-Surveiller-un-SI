#!/usr/bin/env bash
# ============================================================
#  05-mass-encrypt.sh
#  Rejoue le scénario D5 : chiffrement de masse simulé.
#  ⚠️  À EXÉCUTER UNIQUEMENT SUR LA VM apps EN LAB.
#  Doit déclencher la règle Wazuh ID 100240/100241.
# ============================================================
set -euo pipefail

LAB_DIR="${LAB_DIR:-/tmp/lab-encrypt-test}"

echo "==> [D5] Simulation de rançongiciel dans ${LAB_DIR}"
echo "    Cette attaque DOIT déclencher la règle Wazuh ID 100240 ou 100241 (level 14)."
echo
echo "⚠️  Vérifiez que ${LAB_DIR} est bien un répertoire jetable."
read -p "Appuyer sur Entrée pour continuer ou Ctrl+C pour annuler..."

mkdir -p "${LAB_DIR}"
cd "${LAB_DIR}"

# Phase 1 : créer 200 fichiers innocents
echo "==> Phase 1 : création de 200 fichiers cobayes..."
for i in $(seq 1 200); do
  echo "Document ${i} - $(date)" > "doc-${i}.txt"
done

# Le syscheck Wazuh doit avoir vu ces fichiers (au prochain scan)
echo "==> Attente 30s pour un scan FIM..."
sleep 30

# Phase 2 : chiffrement de masse (simulé - on renomme avec une extension caractéristique)
echo "==> Phase 2 : 'chiffrement' (renommage rapide en .locked)"
for f in *.txt; do
  # On chiffre vraiment avec openssl pour avoir un changement de contenu détectable
  openssl enc -aes-256-cbc -salt -pbkdf2 -in "$f" -out "${f}.locked" -k "ransom-key-lab" 2>/dev/null
  rm -f "$f"
done

# Phase 3 : note de rançon
cat > "READ_ME_NOW.txt" <<EOF
Vos fichiers ont été chiffrés !
Pour les récupérer, contactez attacker@evil.example
(scénario de lab — aucun véritable rançongiciel exécuté)
EOF

echo
echo "==> Vérifier dans Wazuh : rule.groups : tutotech,d5,attack"
echo "==> Pour nettoyer : rm -rf ${LAB_DIR}"
