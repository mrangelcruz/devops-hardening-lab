terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Local state on purpose: bootstrap is a one-time bucket create. The lab
  # GitOps path (apply.yml / ci.yml) does not read this state — it takes
  # the bucket ARN as a GitHub Actions variable (SSM_RELAY_BUCKET_ARN).
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

variable "bucket_name" {
  description = "Globally-unique S3 bucket name for the Ansible SSM relay. Must be changed if the default is already taken."
  type        = string
}

module "relay_bucket" {
  source = "../../modules/bucket"

  bucket_name = var.bucket_name
  environment = "bootstrap"
}

output "bucket_id" {
  value = module.relay_bucket.bucket_id
}

output "bucket_arn" {
  value = module.relay_bucket.bucket_arn
}
