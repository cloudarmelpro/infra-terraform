# Point d'entrée public des applications : une IP fixe par zone de disponibilité pour le NLB de Traefik.
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
