terraform {
  required_version = ">= 1.10"
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.0" }
    helm       = { source = "hashicorp/helm", version = "~> 2.17" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.35" }
  }
  backend "s3" {
    bucket       = "tfstate-elyse-gitops"
    key          = "dev/platform/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

variable "activer_metriques" {
  description = "Active les ServiceMonitor d'ArgoCD (après l'installation de Prometheus)"
  type        = bool
  default     = false
}

provider "aws" { region = "us-east-1" }

data "aws_eks_cluster" "this" { name = "gitops-dev" }

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", "gitops-dev", "--region", "us-east-1"]
    }
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", "gitops-dev", "--region", "us-east-1"]
  }
}

locals {
  metriques = { enabled = var.activer_metriques, serviceMonitor = { enabled = var.activer_metriques } }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "10.18.0"
  namespace        = "argocd"
  create_namespace = true

  values = [yamlencode({
    controller = { metrics = local.metriques }
    server     = { metrics = local.metriques }
    configs = {
      rbac = { "policy.default" = "role:readonly" }
      cm = {
        # Les vagues de synchronisation attendent qu'une Application soit prête
        "resource.customizations.health.argoproj.io_Application" = <<-EOT
          hs = {}
          hs.status = "Progressing"
          hs.message = ""
          if obj.status ~= nil and obj.status.health ~= nil then
            hs.status = obj.status.health.status
            if obj.status.health.message ~= nil then
              hs.message = obj.status.health.message
            end
          end
          return hs
        EOT
      }
    }
  })]
}

# =====================================================================================
# Pont GitOps (modèle « GitOps Bridge ») : Terraform transmet à ArgoCD tout ce qui dépend
# du compte AWS, puis ArgoCD installe la plateforme depuis gitops-config. Aucune valeur
# propre au compte (numéro, région, VPC, IP fixes) n'est écrite dans gitops-config.
# =====================================================================================

variable "composants" {
  description = "Composants de la plateforme installés par ArgoCD (label enable_<nom> du cluster)"
  type        = map(bool)
  default = {
    kyverno                      = true
    politiques                   = true
    external_secrets             = true
    supervision                  = true
    aws_load_balancer_controller = true
    cert_manager                 = true
    traefik                      = true
  }
}

data "terraform_remote_state" "socle" {
  backend = "s3"
  config  = { bucket = "tfstate-elyse-gitops", key = "socle/terraform.tfstate", region = "us-east-1" }
}

data "terraform_remote_state" "aws" {
  backend = "s3"
  config  = { bucket = "tfstate-elyse-gitops", key = "dev/aws/terraform.tfstate", region = "us-east-1" }
}

data "aws_caller_identity" "courant" {}

locals {
  registre_ecr = split("/", data.terraform_remote_state.socle.outputs.ecr_repository_url)[0]
}

# Le cluster tel qu'ArgoCD le voit : ses labels activent les composants, ses annotations
# portent les valeurs lues par les ApplicationSet de gitops-config (bootstrap/apps).
resource "kubernetes_secret" "cluster" {
  metadata {
    name      = "in-cluster"
    namespace = "argocd"
    labels = merge(
      { "argocd.argoproj.io/secret-type" = "cluster" },
      { for nom, actif in var.composants : "enable_${nom}" => tostring(actif) }
    )
    annotations = {
      aws_account_id         = data.aws_caller_identity.courant.account_id
      aws_region             = "us-east-1"
      cluster_name           = data.aws_eks_cluster.this.name
      aws_vpc_id             = data.terraform_remote_state.aws.outputs.vpc_id
      entree_subnets         = join(",", data.terraform_remote_state.aws.outputs.public_subnets)
      entree_eip_allocations = data.terraform_remote_state.socle.outputs.entree_allocation_ids
      registre_ecr           = local.registre_ecr
    }
  }
  data = {
    name   = "in-cluster"
    server = "https://kubernetes.default.svc"
    config = jsonencode({ tlsClientConfig = { insecure = false } })
  }
  depends_on = [helm_release.argocd]
}

# Lue par la politique Kyverno restrict-images : seul le registre ECR du compte est autorisé
resource "kubernetes_config_map" "parametres" {
  metadata {
    name      = "parametres-plateforme"
    namespace = "kube-system"
  }
  data = { registre_ecr = local.registre_ecr }
}

# Application racine : ArgoCD prend ensuite le relais et installe tout depuis gitops-config
resource "helm_release" "racine" {
  name       = "racine"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.8"
  namespace  = "argocd"

  values = [yamlencode({
    applications = {
      root = {
        namespace = "argocd"
        project   = "default"
        source = {
          repoURL        = "https://github.com/cloudarmelpro/gitops-config.git"
          targetRevision = "main"
          path           = "bootstrap/apps"
        }
        destination = { server = "https://kubernetes.default.svc", namespace = "argocd" }
        syncPolicy  = { automated = { prune = true, selfHeal = true } }
      }
    }
  })]
  depends_on = [kubernetes_secret.cluster, kubernetes_config_map.parametres]
}
