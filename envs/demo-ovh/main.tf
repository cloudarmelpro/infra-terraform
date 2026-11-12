# Cluster de démonstration sur OVHcloud Managed Kubernetes (soutenance).
# La plateforme de référence reste Amazon EKS (envs/dev/aws) ; ce cluster montre que la même
# configuration GitOps (gitops-config) et les mêmes politiques Kyverno fonctionnent ailleurs.
# Identifiants : variables OVH_ENDPOINT, OVH_APPLICATION_KEY, OVH_APPLICATION_SECRET, OVH_CONSUMER_KEY
# (fichier ~/.ovh-demo.env, jamais versionné). État local : ce cluster est temporaire.
terraform {
  required_version = ">= 1.10"
  required_providers {
    ovh = { source = "ovh/ovh", version = "~> 2.0" }
  }
}

provider "ovh" {}

variable "projet_ovh" {
  description = "Identifiant du projet Public Cloud OVH (service_name)"
  type        = string
}

variable "region" {
  description = "Région OVH qui propose Managed Kubernetes (voir la page de création d'un cluster)"
  type        = string
}

variable "gabarit" {
  description = "Gabarit des nœuds (2 vCPU et 8 Go de mémoire suffisent pour la démonstration)"
  type        = string
  default     = "b3-8"
}

resource "ovh_cloud_project_kube" "demo" {
  service_name = var.projet_ovh
  name         = "gitops-demo"
  region       = var.region
}

resource "ovh_cloud_project_kube_nodepool" "noeuds" {
  service_name  = var.projet_ovh
  kube_id       = ovh_cloud_project_kube.demo.id
  name          = "noeuds"
  flavor_name   = var.gabarit
  desired_nodes = 2
  min_nodes     = 2
  max_nodes     = 3
}

output "kubeconfig" {
  value     = ovh_cloud_project_kube.demo.kubeconfig
  sensitive = true
}
