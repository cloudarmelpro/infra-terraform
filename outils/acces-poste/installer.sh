#!/usr/bin/env bash
# Prépare un poste Ubuntu de l'équipe pour administrer le cluster EKS gitops-dev avec kubectl.
# Prérequis (une fois) :  aws configure --profile uaa   (clé d'accès fournie en privé, région us-east-1)
# Puis :                  bash installer.sh
set -euo pipefail
PROFIL=uaa
DOSSIER=$(cd "$(dirname "$0")" && pwd)

command -v aws >/dev/null || { echo "Installez d'abord AWS CLI v2 : https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"; exit 1; }
aws --profile $PROFIL sts get-caller-identity --query Arn --output text >/dev/null \
  || { echo "Profil « $PROFIL » absent ou invalide : lancez  aws configure --profile $PROFIL"; exit 1; }

if ! command -v kubectl >/dev/null; then
  echo "== Installation de kubectl"
  V=$(curl -Ls https://dl.k8s.io/release/stable.txt)
  curl -sLo /tmp/kubectl "https://dl.k8s.io/release/$V/bin/linux/amd64/kubectl"
  sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
fi

echo "== Suivi automatique de l'IP du poste (cron, toutes les 5 minutes)"
mkdir -p ~/.uaa
install -m 0755 "$DOSSIER/suivi-ip.sh" ~/.uaa/suivi-ip.sh
LIGNE="*/5 * * * * UAA_PROFIL=$PROFIL $HOME/.uaa/suivi-ip.sh"
# (sans crontab existante, « crontab -l » et « grep -v » échouent : on l'ignore)
{ crontab -l 2>/dev/null | grep -v '.uaa/suivi-ip.sh' || true; echo "$LIGNE"; } | crontab -
echo "Tâche cron installée."
UAA_PROFIL=$PROFIL ~/.uaa/suivi-ip.sh || true

echo "== Configuration de kubectl"
aws eks update-kubeconfig --name gitops-dev --region us-east-1 --profile $PROFIL --alias gitops-dev
echo "Attente de l'autorisation de l'IP du poste (1 à 3 minutes)…"
for i in $(seq 1 30); do kubectl get nodes >/dev/null 2>&1 && break; sleep 10; done
kubectl get nodes && echo && echo "Poste prêt : kubectl fonctionne (contexte gitops-dev)." \
  || echo "kubectl ne répond pas encore : réessayez dans quelques minutes (journal : ~/.uaa/suivi-ip.log)."
