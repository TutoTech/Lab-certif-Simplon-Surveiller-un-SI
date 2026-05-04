#!/usr/bin/env bash
# ============================================================
#  03-sqli-admingo.sh
#  Rejoue le scénario D3 : injection SQL sur AdminGo.
#  Doit déclencher la règle Wazuh ID 100220.
# ============================================================
set -euo pipefail

TARGET="${TARGET:-https://adm.lab.tutotech.org}"

echo "==> [D3] Tentatives d'injection SQL contre ${TARGET}"
echo "    Cette attaque DOIT déclencher la règle Wazuh ID 100220 (level 13)."
echo

# Phase 1 : injections SQL classiques visibles dans les logs Traefik
PAYLOADS=(
  "/admingo/quiz/1' OR 1=1--"
  "/admingo/quiz/1 UNION SELECT username,password FROM users"
  "/admingo/answer'%3B%20DROP%20TABLE%20users%3B--"
)

for p in "${PAYLOADS[@]}"; do
  url="${TARGET}${p}"
  echo "    → ${url}"
  curl -ks -o /dev/null -w "       HTTP %{http_code}\n" "${url}"
  sleep 1
done

# Phase 2 : XSS reflété
echo
echo "==> Tentatives XSS..."
curl -ks -o /dev/null "${TARGET}/admingo/quiz/<script>alert(1)</script>"

# Phase 3 : sqlmap si disponible (plus complet)
if command -v sqlmap >/dev/null; then
  echo
  echo "==> Lancement de sqlmap (ne déclenchera la règle qu'au niveau réseau)..."
  sqlmap -u "${TARGET}/admingo/quiz/1" --batch --level=1 --risk=1 --threads=2 --timeout=10 --tamper=space2comment || true
fi

echo
echo "==> Vérifier dans Wazuh : rule.groups : tutotech,d3,attack"
