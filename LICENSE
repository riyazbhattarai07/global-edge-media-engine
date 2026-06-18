# ---------------------------------------------------------------------------
# Network. Encoder tasks run in public subnets with egress-only access (no
# inbound rules) and reach S3 / ECR / CloudWatch over the Internet Gateway.
# This avoids NAT-gateway cost, so idle cost stays at $0. For a hardened
# variant, switch to private subnets + VPC interface endpoints (ecr.api,
# ecr.dkr, logs) + an S3 gateway endpoint.
# ---------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${local.name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-igw" }
}

resource "aws_subnet" "public" {
  count                   = length(local.azs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "${local.name}-public-${local.azs[count.index]}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${local.name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "encoder" {
  name        = "${local.name}-encoder-sg"
  description = "Encoder tasks: egress only, no inbound."
  vpc_id      = aws_vpc.main.id

  egress {
    description = "All egress (S3, ECR, CloudWatch)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-encoder-sg" }
}
