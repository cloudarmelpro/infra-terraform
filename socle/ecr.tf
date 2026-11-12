resource "aws_ecr_repository" "app_demo" {
  name                 = "app-demo"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "KMS" }
}

output "ecr_repository_url" { value = aws_ecr_repository.app_demo.repository_url }
