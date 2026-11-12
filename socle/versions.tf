terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "eu-west-3"
  default_tags {
    tags = { Project = "gitops-eks", Layer = "socle", ManagedBy = "terraform" }
  }
}
