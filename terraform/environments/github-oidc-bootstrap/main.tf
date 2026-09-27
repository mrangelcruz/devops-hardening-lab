terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "github_org" {
  description = "Your GitHub username or org (e.g. the account that owns the fork)"
  type        = string
}

variable "github_repo" {
  description = "Repo name, defaults to this project's name"
  type        = string
  default     = "devops-hardening-lab"
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

module "github_oidc" {
  source = "../../modules/github-oidc"

  github_org  = var.github_org
  github_repo = var.github_repo
}

output "plan_role_arn" {
  description = "Put this in your repo's PLAN_ROLE_ARN GitHub Actions variable"
  value       = module.github_oidc.plan_role_arn
}

output "apply_role_arn" {
  description = "Put this in your repo's APPLY_ROLE_ARN GitHub Actions variable"
  value       = module.github_oidc.apply_role_arn
}
