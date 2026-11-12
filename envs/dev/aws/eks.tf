module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.name
  cluster_version = "1.37" # en « standard support » jusqu'en décembre 2027 (1.33 : support étendu, 6 fois plus cher)

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = concat(["${var.admin_ip}/32"], var.acces_ci_cidrs)
  cluster_endpoint_private_access      = true

  authentication_mode = "API"
  # Accès administrateur explicite : avec « cluster creator », le plan lancé par la CI
  # (rôle en lecture seule) voyait un faux écart sur l'entrée d'accès.
  enable_cluster_creator_admin_permissions = false
  kms_key_administrators                   = [var.admin_principal_arn]
  access_entries = {
    cluster_creator = {
      principal_arn = var.admin_principal_arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
    # Rôle des workflows GitHub (environnement « infra ») : installe ArgoCD et arrête proprement l'environnement
    ci_apply = {
      principal_arn = "arn:aws:iam::${data.aws_caller_identity.courant.account_id}:role/github-infra-apply"
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  cluster_enabled_log_types = ["api", "audit", "authenticator"]

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    # L'agent réserve le port 80 de chaque nœud : il est exclu du nœud d'entrée, où Traefik occupe 80/443
    eks-pod-identity-agent = {
      configuration_values = jsonencode({
        affinity = {
          nodeAffinity = {
            requiredDuringSchedulingIgnoredDuringExecution = {
              nodeSelectorTerms = [{
                matchExpressions = [
                  { key = "kubernetes.io/os", operator = "In", values = ["linux"] },
                  { key = "kubernetes.io/arch", operator = "In", values = ["amd64", "arm64"] },
                  { key = "eks.amazonaws.com/compute-type", operator = "NotIn", values = ["fargate", "hybrid", "auto"] },
                  { key = "role", operator = "NotIn", values = ["entree"] },
                ]
              }]
            }
          }
        }
      })
    }
    vpc-cni = {
      before_compute       = true
      configuration_values = jsonencode({ enableNetworkPolicy = "true" })
    }
  }

  eks_managed_node_groups = merge(
    {
      default = {
        instance_types = ["m7i-flex.large"] # 2 vCPU, 8 Go ; éligible au « Free plan » AWS (t3.medium ne l'est pas)
        min_size       = 2
        max_size       = 4
        desired_size   = local.noeuds
      }
    },
    # Nœud d'entrée (mode « noeud ») : sous-réseau public de la zone a, IP fixe, réservé à Traefik (marque « role=entree »)
    { for nom, ng in {
      entree = {
        instance_types         = ["m7i-flex.large"]
        subnet_ids             = [module.vpc.public_subnets[0]]
        min_size               = 1
        max_size               = 1
        desired_size           = 1
        labels                 = { role = "entree" }
        taints                 = { entree = { key = "role", value = "entree", effect = "NO_SCHEDULE" } }
        vpc_security_group_ids = [aws_security_group.entree.id]
      }
    } : nom => ng if var.mode_entree == "noeud" }
  )
}

# Le module ignore desired_size après la création (pour ne pas contrarier une mise à l'échelle automatique).
# Ce bloc applique quand même la valeur du code quand elle change.
resource "terraform_data" "taille_noeuds" {
  triggers_replace = [module.eks.eks_managed_node_groups["default"].node_group_id, local.noeuds]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"] # même comportement sur le poste (Git Bash) et sur les runners Linux
    command     = <<-EOT
      NG=$(echo "${module.eks.eks_managed_node_groups["default"].node_group_id}" | cut -d: -f2)
      ACTUEL=$(aws eks describe-nodegroup --cluster-name ${module.eks.cluster_name} --nodegroup-name "$NG" --region us-east-1 --query nodegroup.scalingConfig.desiredSize --output text)
      if [ "$ACTUEL" != "${local.noeuds}" ]; then
        aws eks update-nodegroup-config --cluster-name ${module.eks.cluster_name} --nodegroup-name "$NG" --region us-east-1 --scaling-config desiredSize=${local.noeuds}
      fi
    EOT
  }
}

output "cluster_name" { value = module.eks.cluster_name }
output "vpc_id" { value = module.vpc.vpc_id }
output "public_subnets" { value = module.vpc.public_subnets }
