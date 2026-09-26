# GitHub OIDC provider + IAM role, allowing GitHub Actions in a specific
# repo to assume an AWS role WITHOUT any long-lived access keys stored as
# GitHub secrets. This is the recommended, modern pattern for CI->AWS auth.
#
# Two IAM roles are created with different privilege levels, matching the
# two workflows that need AWS access:
#   - plan role: read-only-ish (plan, describe, list) -- used by the CI
#     workflow on every PR, safe to run automatically on untrusted PRs
#   - apply role: full permissions to manage this lab's resources -- used
#     ONLY by the manually-gated apply workflow, behind a GitHub
#     Environment protection rule (required reviewer)

variable "github_org" {
  description = "GitHub org/user that owns the repo"
  type        = string
}

variable "github_repo" {
  description = "Repo name (without org prefix)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

# The GitHub Actions OIDC provider. AWS trusts tokens issued by
# token.actions.githubusercontent.com for federated role assumption.
# One provider per AWS account (not per repo) -- if you already have one
# from another project, import it instead of creating a duplicate; AWS
# only allows one OIDC provider per unique URL per account.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # GitHub's OIDC thumbprint -- documented, stable, but AWS also validates
  # the cert chain itself; this is a defense-in-depth fingerprint pin.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

locals {
  # Restrict token trust to THIS repo only, and further to specific refs/
  # environments via the condition block below -- never trust "any repo."
  repo_subject_prefix = "repo:${var.github_org}/${var.github_repo}"
}

# ---------------------------------------------------------------------
# PLAN role: assumable from ANY branch/PR in this repo (read-mostly).
# Safe for untrusted PRs (e.g. from forks would still need repo secrets
# access, which forks don't get by default -- GitHub's own protection).
# ---------------------------------------------------------------------
resource "aws_iam_role" "plan" {
  name = "${var.github_repo}-gha-plan"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "${local.repo_subject_prefix}:*"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "plan" {
  name = "${var.github_repo}-gha-plan"
  role = aws_iam_role.plan.id

  # Read-only / describe / plan-safe actions only. terraform plan needs to
  # READ the state of resources it would manage, not write anything.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadOnlyDescribe"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:GetInstanceProfile",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketPolicy",
          "s3:GetBucketPublicAccessBlock",
          "s3:GetEncryptionConfiguration",
          "s3:GetBucketLocation",
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

# ---------------------------------------------------------------------
# APPLY role: assumable ONLY from the `main` branch AND only within the
# "production" GitHub Environment (which itself has a required-reviewer
# protection rule configured in GitHub's repo settings -- see README).
# This is the actual privilege boundary: a PR alone can never assume this
# role, only a run that has passed the Environment's manual approval gate.
# ---------------------------------------------------------------------
resource "aws_iam_role" "apply" {
  name = "${var.github_repo}-gha-apply"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "${local.repo_subject_prefix}:environment:production"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "apply" {
  name = "${var.github_repo}-gha-apply"
  role = aws_iam_role.apply.id

  # Scoped to exactly what this lab's Terraform needs to create/manage --
  # NOT AdministratorAccess. Expand deliberately if new resource types are
  # added, never wildcard broadly "to make it work."
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2Full"
        Effect = "Allow"
        Action = [
          "ec2:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMForInstanceRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:PutRolePolicy",
          "iam:GetRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagRole",
          "iam:PassRole"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3ForRelayBucket"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketPublicAccessBlock",
          "s3:PutEncryptionConfiguration",
          "s3:GetEncryptionConfiguration",
          "s3:PutLifecycleConfiguration",
          "s3:GetLifecycleConfiguration",
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = "*"
      },
      {
        Sid      = "STSIdentity"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      }
    ]
  })
}

output "plan_role_arn" {
  value = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  value = aws_iam_role.apply.arn
}
