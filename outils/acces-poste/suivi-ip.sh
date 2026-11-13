#!/usr/bin/env bash
# Autorise l'IP publique courante de ce poste sur l'API du cluster EKS gitops-dev.
# Lancé par cron toutes les 5 minutes (installé par installer.sh) ; journal : ~/.uaa/suivi-ip.log
# L'IP est aussi enregistrée dans SSM (/uaa/acces-api/<poste>) : Terraform la conserve lors des mises à jour.
set -uo pipefail
PROFIL=${UAA_PROFIL:-uaa}
POSTE=${UAA_POSTE:-$(whoami)}
REGION=us-east-1
CLUSTER=gitops-dev
mkdir -p ~/.uaa
log() { echo "$(date '+%F %T') $*" >> ~/.uaa/suivi-ip.log; }
aws_() { aws --profile "$PROFIL" --region "$REGION" "$@"; }

exec 9>/tmp/uaa-suivi-ip.verrou
flock -n 9 || exit 0

IP=$(curl -s -4 -m 10 https://checkip.amazonaws.com | tr -d '[:space:]')
[[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 0

# 1. IP mémorisée dans SSM (lue par Terraform)
ANCIENNE=$(aws_ ssm get-parameter --name "/uaa/acces-api/$POSTE" --query Parameter.Value --output text 2>/dev/null || true)
if [ "$IP" != "$ANCIENNE" ]; then
  aws_ ssm put-parameter --name "/uaa/acces-api/$POSTE" --type String --value "$IP" --overwrite >/dev/null \
    && log "Nouvelle IP $IP (ancienne : ${ANCIENNE:-aucune})"
fi

# 2. Cluster (s'il est allumé) : ajoute l'IP courante et retire l'ancienne de ce poste
[ "$(aws_ eks describe-cluster --name $CLUSTER --query cluster.status --output text 2>/dev/null)" = "ACTIVE" ] || exit 0
ACTUELLES=$(aws_ eks describe-cluster --name $CLUSTER --query 'cluster.resourcesVpcConfig.publicAccessCidrs' --output text | tr '\t' '\n')
echo "$ACTUELLES" | grep -qx "$IP/32" && exit 0
NOUVELLES=$( { echo "$ACTUELLES" | grep -vx "${ANCIENNE:-x}/32"; echo "$IP/32"; } | sort -u | paste -sd, -)
if aws_ eks update-cluster-config --name $CLUSTER --resources-vpc-config "publicAccessCidrs=$NOUVELLES" >/dev/null 2>/tmp/uaa-suivi-ip.err; then
  log "Accès à l'API Kubernetes demandé pour $IP (actif dans 1 à 3 minutes)"
else
  log "Échec (nouvel essai dans 5 minutes) : $(head -1 /tmp/uaa-suivi-ip.err)"
fi
