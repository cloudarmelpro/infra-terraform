# Rôle d'AWS Load Balancer Controller, qui crée le NLB à partir du Service de Traefik.
# L'adresse IP fixe du point d'entrée est gérée dans le socle (socle/entree.tf).
removed {
  from = aws_eip.entree
  lifecycle { destroy = false }
}

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
