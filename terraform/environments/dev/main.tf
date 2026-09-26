terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Bucket/region/encrypt via -backend-config (see backend.hcl.example).
  backend "s3" {
    key = "terraform/dev/terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "ssm_relay_bucket_arn" {
  description = "ARN of the Ansible SSM relay bucket (created once by environments/bootstrap). Set via TF_VAR_ssm_relay_bucket_arn or repo Variable SSM_RELAY_BUCKET_ARN — not via terraform_remote_state, so GitOps apply does not depend on bootstrap state."
  type        = string
}

module "vpc" {
  source = "../../modules/vpc"

  az          = "${var.aws_region}a"
  environment = var.environment
}

module "ssm_instance" {
  source = "../../modules/ssm-instance"

  vpc_id               = module.vpc.vpc_id
  subnet_id            = module.vpc.public_subnet_id
  environment          = var.environment
  ssm_relay_bucket_arn = var.ssm_relay_bucket_arn
}

output "instance_id" {
  value = module.ssm_instance.instance_id
}

output "security_group_id" {
  value = module.ssm_instance.security_group_id
}

output "vpc_id" {
  value = module.vpc.vpc_id
}
