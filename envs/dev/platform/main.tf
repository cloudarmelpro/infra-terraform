terraform {
  required_version = ">= 1.10"
  required_providers {
    aws  = { source = "hashicorp/aws", version = "~> 5.0" }
    helm = { source = "hashicorp/helm", version = "~> 2.17" }
  }
  backend "s3" {
    bucket       = "tfstate-elyse-gitops"
    key          = "dev/platform/terraform.tfstate"
    region       = "eu-west-3"
    encrypt      = true
    use_lockfile = true
  }
}

variable "activer_metriques" {
  description = "Active les ServiceMonitor d'ArgoCD (après l'installation de Prometheus)"
  type        = bool
  default     = false
}

provider "aws" { region = "eu-west-3" }

data "aws_eks_cluster" "this" { name = "gitops-dev" }

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", "gitops-dev", "--region", "eu-west-3"]
    }
  }
}

locals {
  metriques = { enabled = var.activer_metriques, serviceMonitor = { enabled = var.activer_metriques } }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "<VERSION_ARGOCD>"
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
