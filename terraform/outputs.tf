output "apps_lan_ip" {
  description = "IP LAN de la VM apps"
  value       = "10.10.10.10"
}

output "wazuh_lan_ip" {
  description = "IP LAN du LXC Wazuh"
  value       = "10.10.10.20"
}

output "kali_lan_ip" {
  description = "IP LAN de la VM Kali"
  value       = "10.10.10.99"
}

output "pfsense_lan_ip" {
  description = "IP LAN de pfSense (passerelle du lab)"
  value       = var.lab_gateway
}

output "wazuh_root_password" {
  description = "Mot de passe root du LXC Wazuh (à reporter dans votre coffre-fort puis détruire le state)"
  value       = random_password.wazuh_root.result
  sensitive   = true
}

output "next_steps" {
  description = "Prochaines étapes manuelles"
  value       = <<EOT
========================================================================
  Provisionnement Terraform terminé. Étapes suivantes :
========================================================================

  1. Démarrer la VM pfSense (UI Proxmox) et suivre l'install console.
     Voir README.md § 5.

  2. Une fois pfSense configuré et WireGuard actif côté client,
     vérifier la connectivité :

     ping 10.10.10.10   # apps
     ping 10.10.10.20   # wazuh
     ssh debian@10.10.10.10

  3. Lancer Ansible :
     cd ../ansible/
     ansible-galaxy install -r requirements.yml
     ansible-playbook -i inventory/lab.yml playbooks/site.yml

  4. Récupérer le mot de passe root LXC wazuh (sensible) :
     terraform output -raw wazuh_root_password

========================================================================
EOT
}
