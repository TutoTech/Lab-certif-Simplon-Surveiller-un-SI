# Architecture détaillée du lab TutoTech

## Schéma logique

```
                      ┌────────────────────────────────────────────┐
                      │            Internet (WAN)                   │
                      └───────────────────────┬────────────────────┘
                                              │
                                              │ IP publique Proxmox Simplon
                                              ▼
                                  ┌──────────────────────┐
                                  │  Proxmox VE (host)   │
                                  │     vmbr0 (WAN)      │
                                  └─────────┬────────────┘
                                            │
                            ┌───────────────┴────────────────┐
                            │                                │
                       ┌────▼─────┐                          │
                       │ pfSense  │  vtnet0 (WAN, DHCP)      │
                       │   VM     │  vtnet1 (LAN)            │
                       │          │  10.10.10.1/24           │
                       │ Suricata │  WireGuard :51820        │
                       │WireGuard │                          │
                       └────┬─────┘                          │
                            │                                │
                            │ vmbr-lab (LAN isolé)           │
                            │                                │
        ┌───────────────────┼───────────────────────────┐    │
        │                   │                           │    │
   ┌────▼──────┐      ┌─────▼──────┐            ┌───────▼────────┐
   │  apps VM  │      │ wazuh LXC  │            │   kali VM      │
   │ Debian 13 │      │ Debian 13  │            │  Kali Rolling  │
   │ 10.10.10. │      │10.10.10.20 │            │ 10.10.10.99    │
   │    10     │      │            │            │                │
   │           │      │ • Manager  │            │ • Hydra        │
   │ • Traefik │─────►│ • Indexer  │            │ • Nuclei       │
   │ • WP      │ logs │ • Dashboard│            │ • sqlmap       │
   │ • Moodle  │      │            │            │ • wrk          │
   │ • AdminGo │      │            │            │                │
   │ • Wazuh   │      └────────────┘            └────────────────┘
   │   agent   │            ▲
   └───────────┘            │
                            │ syslog UDP/514
                       ┌────┴─────┐
                       │ pfSense  │
                       │ + Suricata│
                       └──────────┘
```

## Flux de données par scénario

### Flux légitime apprenant (sens horaire)
1. Apprenant — VPN WireGuard — pfSense (WAN)
2. pfSense — NAT vers `apps` (10.10.10.10:443)
3. Traefik — routage par hôte (`lms.lab.tutotech.org`) vers conteneur Moodle
4. Moodle — accès BDD `moodle-db` (réseau Docker `internal`)
5. Réponse HTTP retour, logs accès dans `traefik/logs/access.log`
6. Wazuh agent (apps) lit le log, transmet au manager (10.10.10.20:1514)

### Flux suspect Internet → service exposé
1. Attaquant Internet — pfSense (WAN)
2. Suricata (sur pfSense) inspecte le flux et déclenche éventuellement une signature
3. Si signature ET Open ou règle locale match → événement EVE JSON émis
4. pfSense relaye en syslog vers Wazuh manager (10.10.10.20:514)
5. Décodeur Suricata Wazuh extrait les champs, règle 86601 (event) → corrélation locale (ex : règle 100210 = D2)
6. Si seuil franchi → alerte → webhook Discord

### Flux post-exploitation interne
1. Attaquant ayant compromis `apps` exécute commandes
2. Auditd / Sysmon-Linux / fichiers `/var/log/auth.log` capturent les actions
3. Wazuh agent (apps) transmet en temps réel
4. Règles 100200 (D1), 100240/100241 (D5) déclenchent selon le pattern

## Plan d'adressage

| Sous-réseau | Usage | Notes |
|---|---|---|
| WAN Proxmox | DHCP Scaleway | géré par Simplon |
| 10.10.10.0/24 | LAN du lab | géré par pfSense |
| 10.10.20.0/24 | Tunnel WireGuard | clients VPN admin |

| IP fixe | Hôte | Description |
|---|---|---|
| 10.10.10.1 | pfSense | passerelle, DNS resolver |
| 10.10.10.10 | apps | Docker host |
| 10.10.10.20 | wazuh | LXC SIEM |
| 10.10.10.99 | kali | Attaquant |
| 10.10.10.100-200 | DHCP pool | Réservé aux invités/tests ponctuels |
| 10.10.20.2 | nicolas-laptop | Premier client WireGuard |

## Ports exposés

### Sur l'IP publique du Proxmox (port-forwarding via pfSense ou règles iptables Proxmox)
| Port | Protocole | Cible interne | Usage |
|---|---|---|---|
| 51820 | UDP | pfSense | WireGuard |
| 443 | TCP | apps:443 | Site WordPress / Moodle / AdminGo (au choix) |

### Sur le LAN 10.10.10.0/24 (accessibles via VPN seulement)
| Port | Protocole | Hôte | Usage |
|---|---|---|---|
| 443 | TCP | 10.10.10.10 | Traefik (HTTPS apps) |
| 443 | TCP | 10.10.10.20 | Wazuh dashboard |
| 1514, 1515 | TCP | 10.10.10.20 | Wazuh agents enroll + events |
| 514 | UDP | 10.10.10.20 | Syslog (depuis pfSense) |
| 22 | TCP | toutes | SSH admin |

## Volumétrie estimée

| Source | Volume / jour | Notes |
|---|---|---|
| pfSense (firewall + Suricata) | 200-300 Mo | dominant |
| Traefik | 50-100 Mo | proportionnel au trafic |
| Moodle / WordPress | 20-50 Mo | logs PHP+Apache |
| AdminGo | 10 Mo | application légère |
| Wazuh interne (alerts.json) | 50-100 Mo | dépend du nombre d'alertes |
| **Total** | **~ 400-500 Mo / jour** | |

Avec une rétention chaude de 90 jours, prévoir ≈ 50 Go indexés sur la VM Wazuh
(d'où le disque de 50 Go alloué).
