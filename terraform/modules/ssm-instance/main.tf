# The EC2 instance whose security group is the target of the drift
# scenario. SSM-only access by design (no key_name, no SSH inbound) --
# see docs/DRIFT-DETECTION.md for the full incident-response narrative
# this module supports.

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_instance" "this" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.this.id]
  iam_instance_profile   = aws_iam_instance_profile.this.name

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only (CKV_AWS_79)
  }

  root_block_device {
    encrypted = true # CKV_AWS_8
  }

  tags = {
    Name    = "${var.project_tag}-${var.environment}"
    version = var.company_version
  }
}

# THE DRIFT TARGET: declared with zero inbound rules. The break-glass
# playbook (ansible/playbooks/break-glass-enable.yml) adds a real,
# temporary rule directly via the AWS API -- out-of-band from this
# declaration -- which is exactly the drift this lab demonstrates.
resource "aws_security_group" "this" {
  name        = "${var.project_tag}-${var.environment}-sg"
  description = "No inbound rules by default -- reachable only via SSM Session Manager"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound (required to reach SSM endpoints)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_tag}-${var.environment}"
    Environment = var.environment
    version     = var.company_version
  }
}

resource "aws_iam_role" "this" {
  name_prefix = "${var.project_tag}-${var.environment}-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "${var.project_tag}-${var.environment}"
    Environment = var.environment
    version     = var.company_version
  }
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Least-privilege S3 access scoped to the relay bucket's ssm-relay/ prefix
# only -- required by the community.aws.aws_ssm Ansible connection plugin,
# which uses S3 as a file-transfer relay (SSM's session channel has no
# native file-transfer mechanism).
resource "aws_iam_role_policy" "ssm_relay_bucket" {
  count = var.ssm_relay_bucket_arn != "" ? 1 : 0

  name = "${var.project_tag}-${var.environment}-ssm-relay-bucket"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetEncryptionConfiguration", "s3:GetBucketLocation"]
        Resource = var.ssm_relay_bucket_arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${var.ssm_relay_bucket_arn}/ssm-relay/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "this" {
  name_prefix = "${var.project_tag}-${var.environment}-"
  role        = aws_iam_role.this.name

  tags = {
    Name    = "${var.project_tag}-${var.environment}"
    version = var.company_version
  }

  depends_on = [aws_iam_role_policy_attachment.ssm_core]
}
