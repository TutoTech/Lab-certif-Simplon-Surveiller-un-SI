#!/usr/bin/env bash
# ============================================================
#  06-http-flood.sh
#  Rejoue le scénario D6 : flood HTTP/HTTPS contre les services exposés.
#  Doit déclencher la règle Wazuh ID 100250.
# ============================================================
set -euo pipefail

TARGET="${TARGET:-https://wp.lab.tutotech.org/}"
DURATION="${DURATION:-30s}"
THREADS="${THREADS:-4}"
CONNECTIONS="${CONNECTIONS:-100}"

echo "==> [D6] Flood HTTP contre ${TARGET}"
echo "    ${THREADS} threads, ${CONNECTIONS} connexions, durée ${DURATION}"
echo "    Cette attaque DOIT déclencher la règle Wazuh ID 100250 (level 12)."
echo

if ! command -v wrk >/dev/null; then
  echo "    Installation de wrk..."
  sudo apt-get update -qq && sudo apt-get install -y wrk
fi

wrk -t${THREADS} -c${CONNECTIONS} -d${DURATION} --timeout 5s "${TARGET}"

echo
echo "==> Vérifier dans Wazuh : rule.groups : tutotech,d6,attack"
echo "==> Vérifier dans pfSense : Services → Suricata → Alerts (alert ET DOS)"
