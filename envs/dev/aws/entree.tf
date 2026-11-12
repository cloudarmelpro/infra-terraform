# Point d'entrée public des applications, selon var.mode_entree :
#   « nlb »   : Traefik derrière un Network Load Balancer portant une IP fixe par zone (architecture cible) ;
#   « noeud » : Traefik écoute directement sur les ports 80/443 du nœud d'entrée, qui porte l'IP fixe de la zone a
#               (contournement quand le compte AWS n'autorise pas encore Elastic Load Balancing).
# Elles sont créées et détruites avec le cluster (aucun coût quand il est éteint) ; le nom DuckDNS
# est mis à jour automatiquement à chaque démarrage (workflow « demarrer »).
resource "aws_eip" "entree" {
  for_each = toset(["a", "b", "c"])
  domain   = "vpc"
  tags     = { Name = "gitops-dev-entree-${each.key}" }
}

# Rôle d'AWS Load Balancer Controller, qui crée le NLB à partir du Service de Traefik
module "lb_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name                            = "aws-load-balancer-controller"
  attach_aws_lb_controller_policy = true

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }
}

output "entree_ip" { value = aws_eip.entree["a"].public_ip }
output "entree_allocation_ids" { value = join(",", [for z in ["a", "b", "c"] : aws_eip.entree[z].allocation_id]) }

# Mode « noeud » : seuls HTTP et HTTPS sont ouverts sur Internet, et seulement sur le nœud d'entrée
resource "aws_security_group" "entree" {
  name        = "${local.name}-entree"
  description = "HTTP et HTTPS publics vers le noeud entree (Traefik)"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "${local.name}-entree" }
}

resource "aws_vpc_security_group_ingress_rule" "entree" {
  for_each          = { http = 80, https = 443 }
  security_group_id = aws_security_group.entree.id
  description       = upper(each.key)
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
}

# Associe l'IP fixe de la zone a à l'instance du nœud d'entrée (rejoué si le groupe de nœuds est recréé)
resource "terraform_data" "ip_noeud_entree" {
  count            = var.mode_entree == "noeud" ? 1 : 0
  triggers_replace = [module.eks.eks_managed_node_groups["entree"].node_group_id, aws_eip.entree["a"].allocation_id]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      NG=$(echo "${module.eks.eks_managed_node_groups["entree"].node_group_id}" | cut -d: -f2)
      ASG=$(aws eks describe-nodegroup --cluster-name ${module.eks.cluster_name} --nodegroup-name "$NG" --region us-east-1 --query 'nodegroup.resources.autoScalingGroups[0].name' --output text)
      for i in $(seq 60); do
        INST=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" --region us-east-1 --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`]|[0].InstanceId' --output text)
        [ -n "$INST" ] && [ "$INST" != "None" ] && break
        sleep 10
      done
      aws ec2 associate-address --allocation-id ${aws_eip.entree["a"].allocation_id} --instance-id "$INST" --allow-reassociation --region us-east-1 >/dev/null
      echo "IP fixe ${aws_eip.entree["a"].public_ip} associée au nœud d'entrée $INST"
    EOT
  }
}

output "mode_entree" { value = var.mode_entree }
