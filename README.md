# TutoTech Lab — Surveillance d'un SI sur des critères de sécurité

Repo de déploiement automatisé de l'environnement de pré-production / lab de l'association **TutoTech**, hébergé sur le Proxmox pédagogique de Simplon. Cet environnement reproduit fidèlement l'infrastructure de production de TutoTech et sert de support à la mise en œuvre du dispositif de surveillance présenté dans le rapport de certification *Surveiller un système d'information sur des critères de sécurité informatique*.

> **Auteur** : Nicolas BODAINE — co-fondateur TutoTech, formateur sysadmin/cloud/cybersécurité chez Simplon.

---

## Sommaire

1. [Vue d'ensemble](#1-vue-densemble)
2. [Prérequis](#2-prérequis)
3. [Préparation du Proxmox](#3-préparation-du-proxmox)
4. [Provisionnement avec Terraform](#4-provisionnement-avec-terraform)
5. [Configuration de pfSense](#5-configuration-de-pfsense)
6. [Configuration des hôtes avec Ansible](#6-configuration-des-hôtes-avec-ansible)
7. [Déploiement des applications (Docker Compose)](#7-déploiement-des-applications-docker-compose)
8. [Installation de Wazuh](#8-installation-de-wazuh)
9. [Activation de Suricata sur pfSense](#9-activation-de-suricata-sur-pfsense)
10. [Validation par scénarios d'attaque](#10-validation-par-scénarios-dattaque)
11. [Maintenance et exploitation](#11-maintenance-et-exploitation)

---

## 1. Vue d'ensemble

### Topologie cible

```
                        Internet
                            │
                            │ (IP publique Proxmox Simplon)
                            ▼
              ┌─────────────────────────────┐
              │       Proxmox VE (host)     │
              │                             │
              │  ┌───────────────────────┐  │
              │  │   pfSense (VM)        │  │  WAN : vmbr0 (DHCP)
              │  │   - Suricata          │  │  LAN : vmbr-lab (10.10.10.1/24)
              │  │   - WireGuard VPN     │  │
              │  └──────────┬────────────┘  │
              │             │ vmbr-lab      │
              │   ┌─────────┼──────────┐    │
              │   │         │          │    │
              │   ▼         ▼          ▼    │
              │ ┌─────┐  ┌──────┐  ┌──────┐ │
              │ │apps │  │wazuh │  │kali  │ │
              │ │ VM  │  │ LXC  │  │ VM   │ │
              │ │.10  │  │.20   │  │.99   │ │
              │ └─────┘  └──────┘  └──────┘ │
              └─────────────────────────────┘
```

| Composant | Type | OS | vCPU | RAM | Disque | IP LAN |
|---|---|---|---|---|---|---|
| **pfSense** | VM | FreeBSD (pfSense CE 2.7) | 2 | 2 Go | 20 Go | 10.10.10.1 (LAN) |
| **apps** | VM | Debian 13 | 4 | 4 Go | 40 Go | 10.10.10.10 |
| **wazuh** | LXC | Debian 13 | 4 | 6 Go | 50 Go | 10.10.10.20 |
| **kali** | VM | Kali Rolling | 2 | 4 Go | 30 Go | 10.10.10.99 |

**Total : 12 vCPU / 16 Go RAM / 140 Go disque.**

### Stack applicative

Sur la VM `apps`, un reverse proxy Traefik route les flux entrants vers trois conteneurs Docker :
- **WordPress** (site institutionnel) → `wp.lab.tutotech.org`
- **Moodle** (LMS) → `lms.lab.tutotech.org`
- **AdminGo** (application Flask custom de révision) → `adm.lab.tutotech.org`

### Ce que ce repo automatise

- Création et configuration de l'utilisateur Terraform sur Proxmox (script bash).
- Téléchargement et préparation des images cloud Debian 13 et Kali (script bash).
- Provisionnement complet des 4 instances via **Terraform + provider `bpg/proxmox`**.
- Configuration des hôtes Linux via **Ansible** : durcissement, agent Wazuh, Docker.
- Déploiement des trois applications via **docker-compose** sur la VM apps.
- Installation Wazuh manager + indexer + dashboard via le script officiel, piloté par Ansible.

### Ce qui reste manuel (et pourquoi)

- **Configuration initiale de pfSense** : le wizard de pfSense ne s'automatise pas proprement sans installer un agent pré-configuré dans l'image. Le tutoriel guide l'opération en 15 minutes via la console Proxmox.
- **Configuration de Suricata** : exposée dans la GUI pfSense, plus rapide en clics qu'en API.
- **DNS** : la délégation `lab.tutotech.org` est gérée par vos soins chez votre registrar / Scaleway DNS. Les enregistrements à créer sont listés au § 5.4.

---

## 2. Prérequis

### Sur votre poste de travail

| Outil | Version min. | Installation Debian/Ubuntu |
|---|---|---|
| Terraform | 1.6+ | `sudo apt install terraform` (HashiCorp APT) ou tfenv |
| Ansible | 2.16+ | `sudo apt install ansible` |
| Git | 2.x | `sudo apt install git` |
| `jq` | 1.6+ | `sudo apt install jq` |
| `wireguard-tools` | 1.x | `sudo apt install wireguard-tools` |
| `sshpass` | 1.x | `sudo apt install sshpass` (utilisé pour le bootstrap initial) |

```bash
# Vérification
terraform version
ansible --version
wg --version
```

### Côté Proxmox Simplon

- Un compte avec privilèges suffisants pour créer un utilisateur API et un rôle (typiquement `root@pam` au premier coup).
- Le nom du **bridge LAN isolé** mis à disposition par Simplon (à reporter dans `terraform/terraform.tfvars` sous la variable `lab_bridge`). Sa configuration IP n'a pas d'importance : c'est pfSense qui gérera le 10.10.10.0/24 derrière.
- Un **storage** Proxmox capable d'accueillir au moins 140 Go (typiquement `local-lvm`, à confirmer avec `pvesm status`).

### Côté DNS (à votre charge)

Avant le § 5.4, créez chez votre fournisseur DNS pour `tutotech.org` :

```
*.lab.tutotech.org    A    <IP publique du Proxmox Simplon>
```

Cet enregistrement « wildcard » suffit pour exposer tous les sous-domaines du lab.

---

## 3. Préparation du Proxmox

### 3.1 Cloner ce repo

```bash
git clone https://example.com/your-fork/tutotech-lab.git
cd tutotech-lab
```

### 3.2 Créer l'utilisateur API Terraform

Connectez-vous en SSH sur l'hôte Proxmox (`ssh root@<proxmox>`), puis copiez-y le script `scripts/00-bootstrap-proxmox.sh` :

```bash
scp scripts/00-bootstrap-proxmox.sh root@<proxmox>:/root/
ssh root@<proxmox> "bash /root/00-bootstrap-proxmox.sh"
```

Le script :
1. Crée le rôle `TerraformProv` avec les privilèges minimaux nécessaires.
2. Crée l'utilisateur `terraform@pve`.
3. Génère un API token `terraform@pve!automation` et **affiche son secret une seule fois** : copiez-le immédiatement, il ne sera plus jamais re-affichable.
4. Affiche les commandes pour le déclarer côté Terraform.

### 3.3 Préparer les images cloud

Toujours sur l'hôte Proxmox :

```bash
scp scripts/01-prepare-templates.sh root@<proxmox>:/root/
ssh root@<proxmox> "bash /root/01-prepare-templates.sh"
```

Le script :
- Télécharge l'image cloud Debian 13 (genericcloud, qcow2) et crée le template VMID **9000** nommé `debian-13-template`.
- Télécharge l'ISO Kali (`kali-linux-2025.1-installer-netinst-amd64.iso`) dans le storage ISO.
- Télécharge l'ISO pfSense CE 2.7 dans le storage ISO.
- Télécharge le template LXC Debian 13 via `pveam`.

### 3.4 Vérifier le bridge LAN

```bash
ssh root@<proxmox> "ip -br link show | grep vmbr"
```

Si le bridge isolé Simplon (par exemple `vmbr1`) n'apparaît pas, demandez-le à votre référent. **Notez-le précisément**, vous le mettrez dans `terraform/terraform.tfvars`.

---

## 4. Provisionnement avec Terraform

### 4.1 Configuration des variables

Copiez le fichier d'exemple et complétez-le :

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars
```

Variables à renseigner :

```hcl
proxmox_endpoint   = "https://proxmox-simplon.example.com:8006/"
proxmox_node       = "pve-simplon-01"          # nom du nœud Proxmox
proxmox_api_token  = "terraform@pve!automation=<secret-copié-au-3.2>"
lab_bridge         = "vmbr1"                   # bridge LAN isolé Simplon
storage_pool       = "local-lvm"               # storage qcow2
ssh_public_key     = "ssh-ed25519 AAAA... vous@poste"
```

> ⚠️ **Ne committez jamais `terraform.tfvars`** dans Git. Il est listé dans `.gitignore`.

### 4.2 Initialiser et appliquer

```bash
terraform init
terraform plan -out=lab.plan
terraform apply lab.plan
```

Durée : environ 5 à 8 minutes (téléchargement et démarrage des 3 instances Linux). pfSense est créé éteint, vous le démarrerez manuellement au § 5.

### 4.3 Sortie attendue

À la fin, Terraform affiche les IP attribuées par pfSense (résolution interne) et un résumé :

```
Outputs:

apps_lan_ip   = "10.10.10.10"
wazuh_lan_ip  = "10.10.10.20"
kali_lan_ip   = "10.10.10.99"
pfsense_note  = "VM pfSense créée éteinte. Suivez le § 5 du README pour la configurer."
```

À ce stade, les VMs Debian et Kali sont créées **mais inaccessibles** : pfSense n'est pas encore configuré comme passerelle.

---

## 5. Configuration de pfSense

Cette étape est manuelle (~ 15 minutes) car elle dépend de l'interaction console.

### 5.1 Démarrer la VM pfSense

Dans l'interface Proxmox, sélectionnez la VM `pfsense` → *Start* → *Console (noVNC)*.

### 5.2 Installation initiale

Dans le menu d'installation pfSense :
1. *Accept* la licence.
2. *Install* (clavier US par défaut, vous changerez après).
3. Partitionnement *Auto (UFS)*.
4. À la fin, *Reboot*.

Au reboot, retirez l'ISO via Proxmox (*Hardware* → *CD/DVD Drive* → *Do not use any media*).

### 5.3 Assignation des interfaces

Au prompt console pfSense :

```
Should VLANs be set up now? n
Enter the WAN interface name: vtnet0
Enter the LAN interface name: vtnet1
Enter the Optional 1 interface name: <Enter>
Do you want to proceed? y
```

Puis option **2** *Set interface(s) IP address* :

```
Interface to configure: 2 (LAN)
Configure IPv4 address LAN interface via DHCP? n
Enter new LAN IPv4 address: 10.10.10.1
Subnet bit count: 24
For a WAN, enter upstream gateway: <Enter>
Enable DHCP server on LAN? y
Start address: 10.10.10.100
End address:   10.10.10.200
Revert HTTPS to HTTP for webConfigurator? n
```

L'interface web pfSense est désormais accessible depuis une VM du LAN à `https://10.10.10.1/` (login `admin` / mdp `pfsense`).

### 5.4 Configuration via l'interface web

Lancez d'abord la VM `apps` pour servir de poste de rebond temporaire :

```bash
# Depuis votre poste, en attendant le VPN :
ssh -J root@<proxmox> debian@10.10.10.10
# Puis depuis la VM apps :
ssh -L 8443:10.10.10.1:443 debian@10.10.10.10
```

Ouvrez `https://localhost:8443/` dans le navigateur (acceptez le certificat auto-signé).

Wizard initial :
- *Hostname* : `pfsense-lab`
- *Domain* : `lab.tutotech.org`
- *Primary DNS* : `1.1.1.1`, *Secondary* : `9.9.9.9`
- *Timezone* : `Europe/Paris`
- *Admin password* : choisissez un mot de passe robuste, **stockez-le immédiatement dans votre gestionnaire**.

### 5.5 Installation des packages pfSense

*System* → *Package Manager* → *Available Packages*, installer :
- **`pfBlockerNG-devel`** (optionnel, recommandé en lab pour tester les listes de blocage)
- **`Suricata`** (obligatoire pour le projet)
- **`WireGuard`** (obligatoire pour l'accès VPN)

### 5.6 Configurer WireGuard

*VPN* → *WireGuard* → *Tunnels* → *Add Tunnel* :
- *Description* : `wg-admin`
- *Listen Port* : `51820`
- *Interface Keys* → *Generate*

*Peers* → *Add Peer* :
- *Description* : `nicolas-laptop`
- *Public Key* : votre clé publique WireGuard locale
- *Allowed IPs* : `10.10.20.2/32`

Sur votre poste, le client `wg-quick` :

```ini
# /etc/wireguard/lab.conf
[Interface]
PrivateKey = <votre clé privée>
Address    = 10.10.20.2/32
DNS        = 10.10.10.1

[Peer]
PublicKey  = <clé publique pfSense côté tunnel>
Endpoint   = <IP publique Proxmox>:51820
AllowedIPs = 10.10.10.0/24, 10.10.20.0/24
PersistentKeepalive = 25
```

Sur le Proxmox Simplon, **ajoutez une règle de port-forwarding** UDP/51820 → IP de la VM pfSense (à demander à votre référent ou à faire via `iptables` si vous avez les droits).

```bash
sudo wg-quick up lab
ping 10.10.10.1
```

À partir de ce point, **abandonnez le rebond SSH** : tous les accès passent par WireGuard.

### 5.7 Règles de pare-feu de base

*Firewall* → *Rules* → *LAN* (le default-allow-LAN-to-any est conservé pour le lab).

*Firewall* → *Rules* → *WireGuard* : ajouter une règle *Pass IPv4 any* pour permettre l'accès aux ressources LAN depuis le tunnel.

### 5.8 DNS interne

*Services* → *DNS Resolver* → *Host Overrides* → *Add* (un enregistrement par service) :

| Hostname | Domain | IP |
|---|---|---|
| `wp` | `lab.tutotech.org` | `10.10.10.10` |
| `lms` | `lab.tutotech.org` | `10.10.10.10` |
| `adm` | `lab.tutotech.org` | `10.10.10.10` |
| `wazuh` | `lab.tutotech.org` | `10.10.10.20` |
| `pfsense` | `lab.tutotech.org` | `10.10.10.1` |

---

## 6. Configuration des hôtes avec Ansible

À ce stade, vous accédez aux VMs via WireGuard.

### 6.1 Inventaire

Le fichier `ansible/inventory/lab.yml` est déjà préparé. Vérifiez les IP si vous avez modifié la topologie.

### 6.2 Installer les rôles Galaxy

```bash
cd ansible/
ansible-galaxy install -r requirements.yml
```

### 6.3 Vérifier la connectivité

```bash
ansible -i inventory/lab.yml all -m ping
```

Sortie attendue :

```
apps    | SUCCESS => { "ping": "pong" }
wazuh   | SUCCESS => { "ping": "pong" }
```

### 6.4 Lancer le playbook principal

```bash
ansible-playbook -i inventory/lab.yml playbooks/site.yml
```

Ce playbook :
- Met à jour le système (`apt upgrade`).
- Applique un durcissement minimal (SSH par clé uniquement, fail2ban, unattended-upgrades).
- Sur `apps` : installe Docker et Docker Compose plugin via `geerlingguy.docker`.
- Sur `wazuh` : prépare le système, installe les dépendances pour le script officiel d'install Wazuh.

Durée : 10-15 minutes.

---

## 7. Déploiement des applications (Docker Compose)

### 7.1 Copier la stack sur la VM apps

```bash
scp -r docker-compose/apps/ debian@10.10.10.10:/srv/apps/
ssh debian@10.10.10.10
cd /srv/apps/
cp .env.example .env
$EDITOR .env  # mots de passe BDD, secret AdminGo
```

### 7.2 Démarrer la stack

```bash
docker compose up -d
docker compose ps
```

Tous les conteneurs doivent être *healthy* sous 1-2 minutes (Moodle peut mettre jusqu'à 5 minutes au premier démarrage le temps d'installer les tables).

### 7.3 Premier accès

Depuis votre poste (WireGuard up) :
- `https://wp.lab.tutotech.org/` — wizard WordPress
- `https://lms.lab.tutotech.org/` — wizard Moodle (compte admin à créer)
- `https://adm.lab.tutotech.org/` — page d'accueil AdminGo

Traefik émet ses propres certificats auto-signés via la résolveur ACME *staging* : pour le lab, c'est suffisant. Pour basculer en *production* Let's Encrypt, dé-commentez la ligne dédiée dans `docker-compose/apps/traefik/traefik.yml`.

---

## 8. Installation de Wazuh

L'installation utilise le script officiel **wazuh-install.sh** (mode all-in-one), piloté par un playbook Ansible dédié.

### 8.1 Lancer l'installation

```bash
cd ansible/
ansible-playbook -i inventory/lab.yml playbooks/wazuh-install.yml
```

Le playbook :
1. Télécharge le script officiel Wazuh sur le LXC `wazuh`.
2. Génère le fichier `config.yml` adapté (un seul nœud, IP `10.10.10.20`).
3. Exécute l'installation en mode `--all-in-one`.
4. Récupère les credentials générés (admin du dashboard, kibanaserver, etc.) dans `/root/wazuh-install-files/` et **les copie en local sur votre poste** dans `wazuh-credentials.txt` (à mettre dans votre coffre-fort, puis supprimer).

Durée : 20-30 minutes.

### 8.2 Premier accès au dashboard

`https://wazuh.lab.tutotech.org/` (compte `admin` + mot de passe récupéré).

### 8.3 Installer les agents Wazuh

```bash
ansible-playbook -i inventory/lab.yml playbooks/wazuh-agents.yml
```

Ce playbook installe et enregistre l'agent Wazuh sur :
- la VM `apps` (groupe `linux`)
- l'hôte Proxmox lui-même via SSH (groupe `proxmox`) — ⚠ **demandez l'autorisation à Simplon avant** ; sinon, retirez l'hôte de l'inventaire.

Vérification dans le dashboard Wazuh : *Agents* doit afficher 2 agents `Active`.

### 8.4 Charger les règles personnalisées du projet

Les règles D1 à D6 (cf. rapport § 3.4) sont versionnées dans `ansible/roles/wazuh-rules/files/local_rules.xml` et déployées par le playbook ci-dessus dans `/var/ossec/etc/rules/local_rules.xml`.

Pour recharger après une modification :

```bash
ansible-playbook -i inventory/lab.yml playbooks/wazuh-rules.yml
```

---

## 9. Activation de Suricata sur pfSense

(Manuel, ~ 10 minutes — la GUI pfSense pour Suricata est plus simple en clics qu'en API.)

### 9.1 Configuration globale

Sur l'interface pfSense, *Services* → *Suricata* → *Global Settings* :
- *Install ETOpen Emerging Threats rules* : ✅
- *Install Snort GPLv2 community rules* : ✅
- *Install Feodo Tracker IP Blocklist* (abuse.ch) : ✅
- *Update Interval* : `4 hours`
- *Save*.

*Updates* → *Update*. Attendre la fin du téléchargement.

### 9.2 Interface WAN

*Services* → *Suricata* → *Interfaces* → *Add* :
- *Interface* : `WAN`
- *Description* : `wan-ids`
- *Send Alerts to System Log* : ✅
- *EVE JSON Log* : ✅ (champ obligatoire pour Wazuh)
- *EVE Output Type* : `FILE`
- *EVE Logged Traffic* : `Alerts, HTTP, DNS, TLS`

Onglet *WAN Categories* → cocher au minimum `emerging-exploit`, `emerging-web_specific_apps`, `emerging-scan`, `emerging-shellcode` → *Save*.

Onglet *WAN Rules* → vérifier que les règles sont chargées.

Démarrer la sonde : icône ▶ en face de l'interface dans la liste.

### 9.3 Transmettre les logs Suricata à Wazuh

Sur l'hôte Proxmox **ou** dans une console VM ayant accès au pfSense, configurer un agent Wazuh dédié pour la sonde n'est pas pratique (FreeBSD non standardisé chez Wazuh). À la place, on utilise le mécanisme **syslog** de pfSense :

*Status* → *System Logs* → *Settings* → *Remote Logging* :
- *Source Address* : `LAN`
- *Remote log servers* : `10.10.10.20:514`
- ✅ *Everything*
- *Save*

Côté Wazuh, le décodeur Suricata (déjà inclus dans la base 4.x) parse automatiquement les événements EVE encapsulés dans syslog.

Vérifier dans le dashboard Wazuh : *Discover* → filtrer sur `agent.name : pfsense-lab` ou `data.suricata.alert.signature : *`.

---

## 10. Validation par scénarios d'attaque

Tous les scénarios sont rejoués depuis la VM `kali` (10.10.10.99). Les scripts sont fournis dans `scripts/attack/`.

```bash
ssh kali@10.10.10.99
git clone https://example.com/your-fork/tutotech-lab.git
cd tutotech-lab/scripts/attack/
```

| Scénario | Script | Règle déclenchée | Sévérité attendue |
|---|---|---|---|
| Brute-force SSH puis succès | `01-bruteforce-ssh.sh` | D1 | 12 |
| Exploit web simulé via Nuclei | `02-nuclei-moodle.sh` | D2 | 14 |
| SQL injection avec sqlmap sur AdminGo | `03-sqli-admingo.sh` | D3 | 13 |
| Export volumineux MariaDB | `04-massive-export.sh` | D4 | 12 |
| Chiffrement de masse simulé | `05-mass-encrypt.sh` | D5 | 14 |
| Flood HTTP avec wrk | `06-http-flood.sh` | D6 | 12 |

Chaque script affiche une commande `curl` à exécuter dans la foulée pour vérifier la remontée d'alerte via l'API Wazuh.

---

## 11. Maintenance et exploitation

### 11.1 Mises à jour

| Composant | Méthode | Périodicité |
|---|---|---|
| Debian (apps + wazuh) | `unattended-upgrades` (rôle hardening) | quotidien |
| Conteneurs Docker apps | `docker compose pull && docker compose up -d` | hebdomadaire |
| pfSense + packages | GUI *System* → *Update* | mensuel |
| Wazuh | `apt upgrade` puis redémarrage des services | sur publication CVE |

### 11.2 Sauvegardes

- **VMs Proxmox** : utiliser le mécanisme natif *Datacenter* → *Backup* vers le storage `local` ou un NFS. Snapshot au moins 1×/semaine.
- **Bases de données apps** : dump quotidien automatisé via le service `db-backup` du `docker-compose.yml` (volumes nommés conservés 7 jours).
- **Wazuh** : exporter les configurations critiques dans Git (`/var/ossec/etc/rules/local_rules.xml`, `local_decoder.xml`, `ossec.conf`).

### 11.3 Tearing down

Pour démolir le lab proprement :

```bash
cd terraform/
terraform destroy
```

Sur le Proxmox, supprimer manuellement le template VMID 9000 et les ISO si vous voulez tout nettoyer :

```bash
ssh root@<proxmox> "qm destroy 9000 && rm -f /var/lib/vz/template/iso/{kali,pfSense,debian}*"
```

---

## Annexe — Arborescence du repo

```
tutotech-lab/
├── README.md                       # Ce fichier
├── .gitignore
├── terraform/
│   ├── main.tf                     # Ressources Proxmox (VMs, LXC)
│   ├── variables.tf
│   ├── outputs.tf
│   ├── providers.tf
│   ├── cloud-init/
│   │   ├── debian.yml.tftpl        # Template cloud-init Debian
│   │   └── kali.yml.tftpl
│   └── terraform.tfvars.example
├── ansible/
│   ├── ansible.cfg
│   ├── requirements.yml            # Rôles Galaxy
│   ├── inventory/
│   │   └── lab.yml
│   ├── group_vars/
│   │   ├── all.yml
│   │   └── linux.yml
│   ├── playbooks/
│   │   ├── site.yml                # Orchestration globale
│   │   ├── hardening.yml
│   │   ├── docker.yml
│   │   ├── wazuh-install.yml
│   │   ├── wazuh-agents.yml
│   │   └── wazuh-rules.yml
│   └── roles/
│       └── wazuh-rules/
│           └── files/
│               └── local_rules.xml # Règles D1-D6
├── docker-compose/
│   └── apps/
│       ├── docker-compose.yml      # Traefik + WP + Moodle + AdminGo
│       ├── .env.example
│       ├── traefik/
│       │   └── traefik.yml
│       └── admingo/                # Code source minimal AdminGo
│           ├── Dockerfile
│           ├── app.py
│           └── requirements.txt
├── scripts/
│   ├── 00-bootstrap-proxmox.sh     # Création user + token Terraform
│   ├── 01-prepare-templates.sh     # Téléchargement images & ISO
│   └── attack/
│       ├── 01-bruteforce-ssh.sh
│       ├── 02-nuclei-moodle.sh
│       ├── 03-sqli-admingo.sh
│       ├── 04-massive-export.sh
│       ├── 05-mass-encrypt.sh
│       └── 06-http-flood.sh
└── docs/
    ├── architecture.md             # Schéma détaillé + flux
    ├── runbook-incident.md         # Que faire en cas d'alerte ?
    └── troubleshooting.md
```

---

## Licence

Ce projet est diffusé sous licence MIT. Voir `LICENSE`.

## Crédits & références

- Méthode EBIOS Risk Manager — ANSSI
- [Wazuh documentation](https://documentation.wazuh.com/)
- [pfSense documentation](https://docs.netgate.com/pfsense/)
- [Terraform Proxmox provider `bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- [Rôle Ansible `geerlingguy.docker`](https://galaxy.ansible.com/geerlingguy/docker)
