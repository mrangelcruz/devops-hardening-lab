variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "project_tag" {
  type    = string
  default = "devops-hardening-lab"
}

variable "environment" {
  type = string
}

variable "ssm_relay_bucket_arn" {
  description = "ARN of the S3 bucket used by community.aws.aws_ssm for file-transfer relay. Empty skips granting S3 access."
  type        = string
  default     = ""
}
