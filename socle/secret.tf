# Seul le contenant du secret est décrit ici. Sa valeur est saisie avec la CLI, jamais dans Git.
resource "aws_secretsmanager_secret" "app_demo" {
  name = "gitops/dev/app-demo"
}
