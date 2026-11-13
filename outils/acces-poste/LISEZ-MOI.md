# Accès d'un poste de l'équipe au cluster (kubectl)

Pour un poste Ubuntu, à faire une seule fois :

```bash
git clone https://github.com/cloudarmelpro/uaa-platform-infra.git
aws configure --profile uaa          # clé d'accès reçue en privé, région us-east-1, format json
bash uaa-platform-infra/outils/acces-poste/installer.sh
```

Le script installe `kubectl` si besoin, configure le contexte `gitops-dev` et installe une tâche cron
qui autorise automatiquement l'IP publique du poste sur l'API Kubernetes toutes les 5 minutes
(changement de Wi-Fi ou de 4G pris en charge ; journal : `~/.uaa/suivi-ip.log`).
L'IP est enregistrée dans SSM (`/uaa/acces-api/<utilisateur>`), où Terraform la relit : elle n'est
pas effacée par les mises à jour de l'infrastructure.

Les sites (`https://<env>.elyse-cloud.duckdns.org/api/`) et ArgoCD (`https://argocd.elyse-cloud.duckdns.org`)
ne dépendent pas de l'IP du poste.
