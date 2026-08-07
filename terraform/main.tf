# ═══════════════════════════════════════════════════════════════
# Secure File Transfer to S3 from a Private EC2 Instance
# Author: Emmanuel Mulenga | github.com/e-mulenga/private-ec2-to-s3
#
# Private EC2 instance transfers files to S3 via a Gateway VPC
# Endpoint — no NAT Gateway, no Internet Gateway route, no public IP.
# ═══════════════════════════════════════════════════════════════

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" { state = "available" }

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ── VPC ───────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "private-ec2-s3-vpc" }
}

# ── Private Subnet — NO route to an Internet Gateway ──────────

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false
  tags = { Name = "private-ec2-s3-private-subnet", Tier = "Private" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "private-ec2-s3-private-rt" }
  # Deliberately no 0.0.0.0/0 route here — this subnet has no
  # internet egress path at all, by design.
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ── S3 Gateway VPC Endpoint ────────────────────────────────────
# This is the core of the architecture: associating this endpoint
# with the private route table injects a route for S3's IP prefix
# list, so S3 traffic never needs to leave the AWS network.

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = { Name = "private-ec2-s3-gateway-endpoint" }
}

# ── S3 Destination Bucket ──────────────────────────────────────

resource "aws_s3_bucket" "destination" {
  bucket = "private-ec2-transfer-${data.aws_caller_identity.current.account_id}"
  tags   = { Name = "private-ec2-s3-destination-bucket" }
}

resource "aws_s3_bucket_public_access_block" "destination" {
  bucket                  = aws_s3_bucket.destination.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "destination" {
  bucket = aws_s3_bucket.destination.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_versioning" "destination" {
  bucket = aws_s3_bucket.destination.id
  versioning_configuration { status = "Enabled" }
}

# ── IAM Role — least privilege S3 access + SSM management ─────

resource "aws_iam_role" "instance" {
  name = "private-ec2-s3-instance-role-${data.aws_caller_identity.current.account_id}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Scoped to this bucket only — not s3:* on all resources
resource "aws_iam_role_policy" "s3_transfer" {
  name = "s3-transfer-policy"
  role = aws_iam_role.instance.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowObjectTransfer"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject"]
        Resource = "${aws_s3_bucket.destination.arn}/*"
      },
      {
        Sid      = "AllowListBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.destination.arn
      }
    ]
  })
}

# SSM access — no SSH key required for management
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "instance" {
  name = "private-ec2-s3-instance-profile"
  role = aws_iam_role.instance.name
}

# ── Security Group — no inbound from the internet ─────────────

resource "aws_security_group" "instance" {
  name        = "private-ec2-s3-sg"
  description = "Private instance — no inbound internet access required"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "All traffic from within the VPC only"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "private-ec2-s3-sg" }
}

# ── Private EC2 Instance ───────────────────────────────────────

resource "aws_instance" "private" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.private.id
  vpc_security_group_ids      = [aws_security_group.instance.id]
  iam_instance_profile        = aws_iam_instance_profile.instance.name
  associate_public_ip_address = false

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  user_data = <<-EOF
    #!/bin/bash
    dnf install -y amazon-ssm-agent
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
  EOF

  tags = { Name = "private-ec2-s3-instance", Tier = "Private" }

  depends_on = [aws_vpc_endpoint.s3]
}
