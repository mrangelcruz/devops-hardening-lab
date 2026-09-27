# Minimal VPC for the drift-detection lab: one public subnet, no NAT
# Gateway (keeps forker cost near-zero -- NAT Gateways run ~$32/mo each
# even idle, and this lab's EC2 instance is SSM-reachable via a public IP
# + security group, doesn't need outbound-via-NAT).

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name    = "${var.project_tag}-${var.environment}"
    version = var.company_version
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.az
  map_public_ip_on_launch = true

  tags = {
    Name    = "${var.project_tag}-${var.environment}-public"
    Tier    = "public"
    version = var.company_version
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name    = "${var.project_tag}-${var.environment}-igw"
    version = var.company_version
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name    = "${var.project_tag}-${var.environment}-public-rt"
    version = var.company_version
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
