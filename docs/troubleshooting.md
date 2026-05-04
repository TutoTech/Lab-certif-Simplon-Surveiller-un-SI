# Troubleshooting

Récapitulatif des problèmes les plus fréquents lors du déploiement et de
l'exploitation du lab.

---

## Terraform

### `Error: failed to retrieve API token`
- Vérifier le format du token : `user@realm!tokenid=secret-uuid`.
- Tester manuellement : `curl -k -H "Authorization: PVEAPIToken=...' https://proxmox/api2/json/version`

### `Error: error retrieving VM 9000`
- Le template Debian n'a pas été créé. Relancer `01-prepare-templates.sh`.

### `Error: VM <id> already exists`
- Une exécution précédente a laissé des ressources. Soit `terraform import`, soit supprimer manuellement la VM dans Proxmox.

### Cloud-init n'applique pas l'IP statique
- Vérifier que la VM Debian a bien `qemu-guest-agent` installé (le template doit l'avoir).
- Vérifier le datastore cloud-init : `ide0` doit être configuré sur le storage.

---

## pfSense

### Pas d'accès Internet depuis pfSense après install
- Vérifier que vtnet0 est bien en DHCP et a obtenu une IP du WAN Proxmox.
- Tester depuis la console pfSense : option 7 *Ping host*.

### Le tunnel WireGuard ne monte pas
- Vérifier le port-forwarding UDP/51820 sur le Proxmox Simplon.
- Vérifier les règles pfSense → *WireGuard* (autoriser tout depuis le tunnel pour le lab).
- Côté client : `wg show lab` → si `latest handshake` n'apparaît jamais, le port est filtré.

### Suricata charge mais ne détecte rien
- Vérifier que les rulesets sont bien téléchargés : *Updates* → *Update*.
- Vérifier les catégories cochées sur l'interface WAN.
- Tester avec un payload connu : `curl http://testmynids.org/uid/index.html` depuis Internet.

---

## Ansible

### `UNREACHABLE - Permission denied (publickey)`
- Vérifier que la clé SSH du `ssh_public_key` Terraform correspond à votre clé locale.
- Le LXC Wazuh utilise root + mot de passe (cf. inventaire), pas la clé apps.

### Le rôle `geerlingguy.docker` échoue sur Debian 13
- S'assurer que `requirements.yml` impose la version `7.4.0` minimum.
- Vérifier que l'hôte a accès Internet via pfSense.

### Le playbook wazuh-install.yml plante en cours
- Le script officiel Wazuh peut échouer en cas de RAM insuffisante. Vérifier `free -h` (au moins 4 Go libres pendant l'install).
- En cas d'install partielle : `bash /opt/wazuh-install/wazuh-install.sh -u` pour désinstaller, puis relancer.

---

## Docker apps

### Moodle ne démarre pas
- Premier démarrage : il faut 3 à 5 minutes (initialisation BDD).
- Vérifier les logs : `docker compose logs -f moodle`.
- Erreurs de connexion BDD : confirmer que `MOODLE_DB_PASSWORD` correspond entre `moodle` et `moodle-db` dans `.env`.

### Traefik ne crée pas les certificats Let's Encrypt
- En lab on utilise le **staging** : les certificats sont reconnus comme invalides par les navigateurs (normal).
- Pour passer en prod : retirer la ligne `--certificatesresolvers.le.acme.caserver=...staging...` dans `docker-compose.yml`.
- Vérifier que les ports 80/443 sont ouverts depuis Internet (challenge HTTP).

---

## Wazuh

### Le dashboard est inaccessible
- Vérifier les services : `systemctl status wazuh-manager wazuh-indexer wazuh-dashboard`.
- L'indexer met 1-2 minutes à démarrer.
- Tester l'API : `curl -k -u admin:<password> https://10.10.10.20:9200/_cluster/health`.

### Les agents apparaissent en `Disconnected`
- Vérifier la connectivité réseau : agent → manager port 1514 (events) et 1515 (enroll).
- Sur l'agent : `tail -f /var/ossec/logs/ossec.log`.

### Les règles D1-D6 ne déclenchent pas
- Tester le décodeur : `/var/ossec/bin/wazuh-logtest`.
- Vérifier les groupes dans le dashboard : *Discover* → filtre `rule.groups : tutotech*`.
- Si rien n'apparaît : vérifier que `local_rules.xml` est bien lu (`grep "100200" /var/ossec/etc/rules/*.xml`).
- Recharger après modification : `ansible-playbook playbooks/wazuh-rules.yml`.

---

## Performance

### Le LXC Wazuh est très lent
- Augmenter à 8 Go RAM si vous indexez plus de 500 Mo/jour.
- L'indexer OpenSearch a besoin d'au moins 2 Go heap (configuré dans `/etc/wazuh-indexer/jvm.options`).

### La VM apps swap
- Limiter Moodle : ajouter dans son service docker-compose `mem_limit: 1.5g`.
- Désactiver des modules WordPress non utilisés.
