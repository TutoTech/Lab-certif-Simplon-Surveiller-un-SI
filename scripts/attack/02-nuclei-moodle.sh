#!/usr/bin/env bash
# ============================================================
#  02-nuclei-moodle.sh
#  Rejoue le scénario D2 : exploit web simulé via Nuclei.
#  Doit déclencher Suricata ET ainsi la règle Wazuh ID 100210.
# ============================================================
set -euo pipefail

TARGET="${TARGET:-https://lms.lab.tutotech.org}"

echo "==> [D2] Scan Nuclei contre ${TARGET}"
echo "    Cette attaque DOIT déclencher la règle Wazuh ID 100210 (level 14)."
echo

if ! command -v nuclei >/dev/null; then
  echo "    Installation de Nuclei..."
  sudo apt-get update -qq && sudo apt-get install -y nuclei
  nuclei -update-templates
fi

# Templates ciblant les CMS, en mode rapide
nuclei -u "${TARGET}" \
  -t cves/ \
  -t exposures/ \
  -t misconfiguration/ \
  -severity medium,high,critical \
  -rate-limit 10 \
  -timeout 5 \
  -no-color || true

echo
echo "==> Vérifier dans Wazuh :"
echo "    rule.groups : tutotech,d2,attack"
