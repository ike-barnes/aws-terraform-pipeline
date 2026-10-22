# A private network baseline: a VPC with private subnets in two
# Availability Zones, no internet route, and the default security
# group locked down. Everything here is free except the KMS key.

# Allowlist the exact zones by name. Without this filter the result set
# would silently grow if AWS added a zone, and resources could shift.
# (Flagged by Checkov CKV_AWS_394 on the first pipeline run.)
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "zone-name"
    values = var.availability_zones
  }
}

locals {
  azs = data.aws_availability_zones.available.names
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name}-vpc"
  }
}

resource "aws_subnet" "private" {
  for_each = { for i, az in local.azs : az => i }

  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.key
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, each.value + 10)
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name}-private-${each.key}"
    Tier = "private"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name}-private"
  }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# The default security group allows all traffic between its members.
# Taking it under Terraform management with no rules removes that.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name}-default-locked"
  }
}
