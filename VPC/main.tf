resource "random_id" "suffix" {
  byte_length = 4
}
locals {
  # Common naming convention using project name and random suffix
  name_suffix = "${var.project_name}-${random_id.suffix.hex}"

  content_bucket_name = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
  common_tags = merge({
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Recipe      = "virtual-private-network"
    },
  var.tags)
}

data "aws_availability_zone" "available" {
  name  = "${var.aws_region}a"
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# Initialize a VPC network with a CIDR block
resource "aws_vpc" "VPC-Network-A" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = merge(local.common_tags, {
    Name        = "${local.name_suffix}-VPC-A"
    Description = "A VPC network for isolated network"
  })
}

# Associate the subnet with VPC network
resource "aws_subnet" "public-subnet-VPC-A" {
  vpc_id                  = aws_vpc.VPC-Network-A.id
  cidr_block              = cidrsubnet(aws_vpc.VPC-Network-A.cidr_block, 8, 1)
  availability_zone       = data.aws_availability_zone.available.name
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name        = "${local.name_suffix}-public-subnet-VPC-A"
    Description = "A public subnet network for VPC A"
  })
}

# Attach IG to the VPC for internet access
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.VPC-Network-A.id

  tags = merge(local.common_tags, {
    Name        = "VPC-ig"
    Description = "An internet gateway for the VPC"
  })
}

# Create a custom route table for the VPC by adding the route table for IG
resource "aws_route_table" "public-route-table-subnet-A" {
  vpc_id = aws_vpc.VPC-Network-A.id

  route {
    gateway_id = aws_internet_gateway.gw.id
    cidr_block = "0.0.0.0/0"
  }
}

resource "aws_subnet" "private-subnet-VPC-A" {
  vpc_id            = aws_vpc.VPC-Network-A.id
  cidr_block        = cidrsubnet(aws_vpc.VPC-Network-A.cidr_block, 8, 2)
  availability_zone = data.aws_availability_zone.available.name

  tags = merge(local.common_tags, {
    Name        = "${local.name_suffix}-private-subnet-VPC-A"
    Description = "A private subnet network for VPC A"
  })
}

resource "aws_route_table_association" "public-subnet-route-association" {
  subnet_id      = aws_subnet.public-subnet-VPC-A.id
  route_table_id = aws_route_table.public-route-table-subnet-A.id
}

resource "aws_route_table_association" "private-subnet-route-association" {
  subnet_id      = aws_subnet.private-subnet-VPC-A.id
  route_table_id = aws_vpc.VPC-Network-A.main_route_table_id
}

resource "aws_network_acl" "private-nacl-VPC-A" {
  vpc_id = aws_vpc.VPC-Network-A.id

  egress {
    rule_no    = 100
    protocol   = "icmp"
    action     = "allow"
    cidr_block = aws_vpc.VPC-Network-A.cidr_block
    from_port  = 0
    to_port    = 0
  }

  egress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.myIP
    from_port  = 22
    to_port    = 22
  }

  ingress {
    rule_no    = 100
    protocol   = "icmp"
    action     = "allow"
    cidr_block = aws_vpc.VPC-Network-A.cidr_block
    from_port  = 8
    to_port    = 0
  }

  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.myIP
    from_port  = 22
    to_port    = 22
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_suffix}-private-nacl-VPC-A"
    Description = "A private network ACL for VPC A"
  })
}

# resource "aws_default_network_acl" "default-NACL-VPC-A" {
#   default_network_acl_id = aws_vpc.VPC-Network-A.default_network_acl_id
#   ingress {
#     rule_no    = 100
#     protocol   = "tcp"
#     action     = "allow"
#     cidr_block = var.myIP
#     from_port  = 22
#     to_port    = 22
#   }

#   ingress {
#     rule_no    = 110
#     protocol   = "icmp"
#     action     = "allow"
#     cidr_block = aws_vpc.VPC-Network-A.cidr_block
#     from_port  = 1
#     to_port    = 1
#   }

#   egress {
#     rule_no    = 110
#     protocol   = "icmp"
#     action     = "allow"
#     cidr_block = aws_vpc.VPC-Network-A.cidr_block
#     from_port  = 8
#     to_port    = 8
#   }

#   egress {
#     rule_no    = 100
#     protocol   = "tcp"
#     action     = "allow"
#     cidr_block = var.myIP
#     from_port  = 22
#     to_port    = 22
#   }

# }
resource "aws_network_acl_association" "private-nacl-VPC-A" {
  network_acl_id = aws_network_acl.private-nacl-VPC-A.id
  subnet_id      = aws_subnet.private-subnet-VPC-A.id
}

resource "aws_security_group" "allow_ssh_and_icmp" {
  name        = "${local.name_suffix}_allow_ssh_and_icmp"
  description = "Allow TLS inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.VPC-Network-A.id

  tags = {
    Name = "allow_ssh_and_icmp_and_icmp"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_icmp_reply" {
  security_group_id = aws_security_group.allow_ssh_and_icmp.id
  cidr_ipv4         = aws_vpc.VPC-Network-A.cidr_block
  from_port         = 8
  ip_protocol       = "icmp"
  to_port           = 0
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv4" {
  security_group_id = aws_security_group.allow_ssh_and_icmp.id
  cidr_ipv4         = var.myIP
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}
resource "aws_vpc_security_group_egress_rule" "allow_icmp_request" {
  security_group_id = aws_security_group.allow_ssh_and_icmp.id
  cidr_ipv4         = aws_vpc.VPC-Network-A.cidr_block
  ip_protocol       = "icmp" # semantically equivalent to all ports
  from_port = 0
  to_port = 0
}