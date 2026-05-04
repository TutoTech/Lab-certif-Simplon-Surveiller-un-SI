# Runbook — Réponse aux alertes du lab

Ce document décrit la procédure à suivre lorsqu'une alerte Wazuh
correspondant à l'une des règles D1 à D6 du projet est déclenchée.

> **Principe** : qualification rapide → confinement si nécessaire → investigation → restauration → retour d'expérience.

---

## D1 — Brute-force suivi d'un succès (compte admin)

**Sévérité Wazuh** : 12 — règle ID 100200

### Qualification (5 min)
- Identifier la cible : champ `data.dstuser`, `agent.name`.
- Identifier la source : champ `data.srcip`. Vérifier sa réputation sur AbuseIPDB.
- Vérifier l'historique : autres événements du même `srcip` sur les 24 dernières heures.

### Confinement
- Si l'IP source est externe et clairement malveillante :
  - Bloquer dans pfSense → *Firewall* → *Aliases* → ajouter à `bogons-attack` → règle WAN deny.
- Si compte interne légitime utilisant un mauvais mot de passe puis le bon : pas d'action, contacter l'utilisateur pour reset volontaire.

### Investigation
- Extraire les logs SSH/Moodle/WP de la cible sur les 1h précédant l'alerte.
- Vérifier qu'aucune action sensible n'a été effectuée après le login (création de compte, modif droits).

### Restauration
- Si compromission confirmée : reset du mot de passe, révocation des sessions, audit des actions effectuées.

---

## D2 — Exploitation web Suricata

**Sévérité Wazuh** : 14 — règle ID 100210

### Qualification (5 min)
- Identifier la signature Suricata : `data.suricata.alert.signature`.
- Vérifier `data.suricata.alert.category`.
- Examiner la cible : URL, méthode, code retour.

### Confinement
- Bloquer l'IP source dans pfSense.
- Si la cible est un service spécifique : envisager une mise en mode maintenance temporaire.

### Investigation
- Identifier la CVE concernée si la signature est explicite (regex `CVE-`).
- Vérifier la version du composant cible.
- Si version vulnérable : patcher en priorité.

### Restauration
- Patch + restart du conteneur concerné (`docker compose pull <service> && docker compose up -d`).
- Audit applicatif : recherche de webshell, fichiers récemment modifiés dans le conteneur.

---

## D3 — Injection SQL/XSS sur AdminGo

**Sévérité Wazuh** : 13 — règle ID 100220

### Qualification (5 min)
- Identifier le payload : champ `full_log` ou `data.url`.
- Vérifier le code retour applicatif.

### Confinement
- Si exploitation manifeste : isoler le conteneur AdminGo (`docker compose stop admingo`).
- Bloquer l'IP source dans pfSense.

### Investigation
- Examiner les logs de la base PostgreSQL d'AdminGo.
- Vérifier si des données ont été extraites (gros SELECT non sollicité).

### Restauration
- Patch du code AdminGo (revue OWASP).
- Si fuite confirmée : notification CNIL si données apprenants concernées.

---

## D4 — Exfiltration / volume sortant anormal

**Sévérité Wazuh** : 12 — règles ID 100230, 100231

### Qualification (10 min)
- Quel hôte ? Quelle table ?
- Vérifier le volume réel via `iftop` ou les graphes pfSense.

### Confinement
- Bloquer l'IP de destination si externe identifiable.
- Couper la connexion sortante de la VM si exfiltration active.

### Investigation
- Logs MariaDB/PostgreSQL : qui a effectué les SELECT ?
- Comptes compromis ?

### Restauration
- Reset des credentials de service.
- Notification CNIL obligatoire si fuite confirmée (72h).

---

## D5 — Rançongiciel / chiffrement de masse

**Sévérité Wazuh** : 14 — règles ID 100240, 100241

### Qualification (immédiate, < 2 min)
- Confirmer le scope : un seul hôte ou plusieurs ?
- Vérifier si extensions caractéristiques.

### Confinement (priorité absolue)
- **ISOLER l'hôte** : `pfctl -t blocklist -T add 10.10.10.X` ou couper l'interface.
- Stopper Proxmox si l'hyperviseur est touché.

### Investigation (différée à après confinement)
- Identifier le vecteur d'entrée (corrélation D1 ou D2 dans les heures précédentes).
- Préserver les artefacts (snapshot Proxmox de la VM compromise).

### Restauration
- **Ne PAS payer de rançon.**
- Restauration depuis les sauvegardes Proxmox Backup Server.
- Reset complet des credentials.
- Renforcement post-mortem.

---

## D6 — Déni de service

**Sévérité Wazuh** : 12 — règle ID 100250

### Qualification (5 min)
- Volume de trafic réel (graphes pfSense → *Status* → *Traffic Graph*).
- Cible : un service ou tous ?

### Confinement
- Activer la limite de débit Traefik si pas déjà active.
- Bloquer les top sources via pfBlockerNG.
- Si DDoS volumétrique : escalader vers Scaleway (protection native).

### Investigation
- Pic ponctuel (mauvais bot indexant) ou attaque ciblée ?
- Pattern dans les User-Agent ?

### Restauration
- Lever les blocages temporaires une fois l'incident clos.

---

## Communication post-incident

Pour tout incident D1-D6 ayant nécessité une action de confinement :

1. **Bulletin interne** : courriel aux co-fondateurs + bénévoles formateurs si impact pédagogique.
2. **Mise à jour du registre des incidents** (fichier privé Git).
3. **Notification CNIL** : obligatoire sous 72 h si données personnelles compromises (D3, D4 surtout).
4. **Retour d'expérience** : revue des règles dans `local_rules.xml`, ajustement des seuils.
