resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# ---- Rôle 1 : la CI de app-demo peut envoyer des images dans ECR, rien d'autre ----
data "aws_iam_policy_document" "ci_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      # Deux formats possibles : classique, ou « immuable » (identifiants numériques, dépôts récents)
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:cloudarmelpro/app-demo:ref:refs/heads/main",
        "repo:cloudarmelpro@*/app-demo@*:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "github_ci" {
  name               = "github-ci-app-demo"
  assume_role_policy = data.aws_iam_policy_document.ci_trust.json
}

data "aws_iam_policy_document" "ecr_push" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:DescribeImages"
    ]
    resources = [aws_ecr_repository.app_demo.arn]
  }
}

resource "aws_iam_role_policy" "github_ci_ecr" {
  role   = aws_iam_role.github_ci.id
  policy = data.aws_iam_policy_document.ecr_push.json
}

# ---- Rôle 2 : infra-terraform peut LIRE le compte (plan, Conftest, détection des écarts) ----
data "aws_iam_policy_document" "readonly_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:cloudarmelpro/infra-terraform:*",
        "repo:cloudarmelpro@*/infra-terraform@*:*",
      ]
    }
  }
}

resource "aws_iam_role" "github_readonly" {
  name               = "github-infra-readonly"
  assume_role_policy = data.aws_iam_policy_document.readonly_trust.json
}

resource "aws_iam_role_policy_attachment" "github_readonly" {
  role       = aws_iam_role.github_readonly.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# ---- Rôle 3 : infra-terraform peut APPLIQUER, uniquement depuis l'environnement GitHub « infra » ----
# Cet environnement exige une approbation humaine : aucun job ne reçoit ces droits sans validation.
data "aws_iam_policy_document" "apply_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:cloudarmelpro/infra-terraform:environment:infra",
        "repo:cloudarmelpro@*/infra-terraform@*:environment:infra",
      ]
    }
  }
}

resource "aws_iam_role" "github_apply" {
  name                 = "github-infra-apply"
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  max_session_duration = 7200 # la création complète du cluster dure environ 25 minutes
}

# Terraform crée des rôles IAM, un VPC, un cluster : seuls des droits d'administration le permettent.
# La protection repose sur l'OIDC (dépôt + environnement) et sur l'approbation obligatoire.
resource "aws_iam_role_policy_attachment" "github_apply" {
  role       = aws_iam_role.github_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

output "github_ci_role_arn" { value = aws_iam_role.github_ci.arn }
output "github_readonly_role_arn" { value = aws_iam_role.github_readonly.arn }
output "github_apply_role_arn" { value = aws_iam_role.github_apply.arn }
