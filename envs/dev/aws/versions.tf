terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket       = "tfstate-didacloudops-gitops"
    key          = "dev/aws/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = { Project = "gitops-eks", Environment = "dev", ManagedBy = "terraform" }
  }
}

variable "admin_ip" {
  description = "Adresse IP publique autorisée à joindre l'API Kubernetes (fichier admin.auto.tfvars)"
  type        = string
}

locals {
  name = "gitops-dev"
  azs  = ["us-east-1a", "us-east-1b", "us-east-1c"]
  # Nœuds du groupe principal : en mode « noeud », un des trois nœuds devient le nœud d'entrée (même coût)
  noeuds = var.mode_entree == "noeud" ? 2 : 3
}

variable "admin_principal_arn" {
  description = "Identité IAM qui administre le cluster (accès EKS explicite)"
  type        = string
}

variable "acces_ci_cidrs" {
  description = "Adresses ajoutées temporairement à l'accès public de l'API (runner GitHub pendant les workflows démarrer/arrêter)"
  type        = list(string)
  default     = []
}

data "aws_caller_identity" "courant" {}

variable "mode_entree" {
  description = "Point d'entrée public : « nlb » (Network Load Balancer, cible) ou « noeud » (nœud public + Traefik sur 80/443, quand le compte n'autorise pas encore ELB)"
  type        = string
  default     = "noeud"
  validation {
    condition     = contains(["nlb", "noeud"], var.mode_entree)
    error_message = "mode_entree vaut « nlb » ou « noeud »."
  }
}
