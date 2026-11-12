# Renommé en backend.tf APRÈS la première création du socle (voir ROADMAP, étape 9)
terraform {
  backend "s3" {
    bucket       = "tfstate-elyse-gitops"
    key          = "socle/terraform.tfstate"
    region       = "eu-west-3"
    encrypt      = true
    use_lockfile = true
  }
}
