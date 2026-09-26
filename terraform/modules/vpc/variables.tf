variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.30.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the single public subnet"
  type        = string
  default     = "10.30.10.0/24"
}

variable "az" {
  description = "Availability zone for the public subnet"
  type        = string
}

variable "project_tag" {
  description = "Project name used in resource naming/tagging"
  type        = string
  default     = "devops-hardening-lab"
}

variable "environment" {
  description = "Environment name (dev, etc.)"
  type        = string
}
