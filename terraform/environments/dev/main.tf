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

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "environment" {
  type    = string
  default = "dev"
}

data "terraform_remote_state" "bootstrap" {
  backend = "local"
  config = {
    path = "${path.module}/../bootstrap/terraform.tfstate"
  }
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
  ssm_relay_bucket_arn = data.terraform_remote_state.bootstrap.outputs.bucket_arn
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
