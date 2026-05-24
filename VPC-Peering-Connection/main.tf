resource "random_id" "suffix" {
  byte_length = 4
}
locals {
  # Common naming convention using project name and random suffix
  name_suffix = "${var.project_name}-${random_id.suffix.hex}"

  common_tags = merge({
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Recipe      = "virtual-private-network"
    },
  var.tags)
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "random_integer" "az_index" {
  min = 0
  max = length(data.aws_availability_zones.available.names) - 1
}

# Initialize a VPC network with a CIDR block
resource "aws_vpc" "Private-VPC-Network-A" {
  cidr_block       = "10.1.0.0/16"
  instance_tenancy = "default"

  tags = merge(local.common_tags, {
    Name        = "${local.name_suffix}-Priavte-VPC-A"
    Description = "A private VPC network for isolated network"
  })
}

resource "aws_vpc" "Private-VPC-Network-B" {
  cidr_block       = "10.2.0.0/16"
  instance_tenancy = "default"

  tags = merge(local.common_tags, {
    Name        = "${local.name_suffix}-Priavte-VPC-B"
    Description = "A private VPC network for isolated network"
  })
}

resource "aws_subnet" "private-subnet-VPC-A" {
  vpc_id            = aws_vpc.Private-VPC-Network-A.id
  cidr_block        = cidrsubnet(aws_vpc.Private-VPC-Network-A.cidr_block, 8, 2)
  availability_zone = data.aws_availability_zones.available.names[random_integer.az_index.result]

  tags = merge(local.common_tags, {
    Name        = "${local.name_suffix}-private-subnet-VPC-A"
    Description = "A private subnet network for VPC"
  })
}

resource "aws_subnet" "private-subnet-VPC-B" {
  vpc_id            = aws_vpc.Private-VPC-Network-B.id
  cidr_block        = cidrsubnet(aws_vpc.Private-VPC-Network-B.cidr_block, 8, 2)
  availability_zone = data.aws_availability_zones.available.names[random_integer.az_index.result]

  tags = merge(local.common_tags, {
    Name        = "${local.name_suffix}-private-subnet-VPC-B"
    Description = "A private subnet network for VPC"
  })
}
resource "aws_vpc_peering_connection" "VPC-peercon" {
  peer_vpc_id   = aws_vpc.Private-VPC-Network-A.id
  vpc_id        = aws_vpc.Private-VPC-Network-B.id
  auto_accept   = true
}

resource "aws_default_route_table" "VPC-1-route-table" {
  default_route_table_id = aws_vpc.Private-VPC-Network-A.default_route_table_id

  route {
    cidr_block = aws_vpc.Private-VPC-Network-B.cidr_block
    vpc_peering_connection_id = aws_vpc_peering_connection.VPC-peercon.id
  }
}

resource "aws_default_route_table" "VPC-2-route-table" {
  default_route_table_id = aws_vpc.Private-VPC-Network-B.default_route_table_id

  route {
    cidr_block = aws_vpc.Private-VPC-Network-A.cidr_block
    vpc_peering_connection_id = aws_vpc_peering_connection.VPC-peercon.id
  }
}

resource "aws_default_network_acl" "aws-deny-all-outer-traffic-to-VPC-A" {
  
  default_network_acl_id = aws_vpc.Private-VPC-Network-A.default_network_acl_id

  ingress {
    protocol   = "icmp"
    rule_no    = 100
    action     = "allow"
    cidr_block = aws_vpc.Private-VPC-Network-B.cidr_block
    from_port  = 0
    to_port    = 0
    icmp_code = 0
    icmp_type = 8
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = aws_vpc.Private-VPC-Network-B.cidr_block
    from_port  = 22
    to_port    = 22
    icmp_code = 0
    icmp_type = 8
  }
  egress {
    protocol   = "icmp"
    rule_no    = 100
    action     = "allow"
    cidr_block = aws_vpc.Private-VPC-Network-B.cidr_block
    from_port  = 0
    to_port    = 0
    icmp_code = 0
    icmp_type = 0
  }

  egress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = aws_vpc.Private-VPC-Network-B.cidr_block
    from_port  = 1024
    to_port    = 65535
    icmp_code = 0
    icmp_type = 0
  }
}

resource "aws_default_network_acl" "aws-deny-all-outer-traffic-to-VPC-B" {
  
  default_network_acl_id = aws_vpc.Private-VPC-Network-B.default_network_acl_id

  ingress {
    protocol   = "icmp"
    rule_no    = 100
    action     = "allow"
    cidr_block = aws_vpc.Private-VPC-Network-A.cidr_block
    from_port  = 0
    to_port    = 0
    icmp_code = 0
    icmp_type = 8
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = aws_vpc.Private-VPC-Network-A.cidr_block
    from_port  = 22
    to_port    = 22
    icmp_code = 0
    icmp_type = 8
  }
  egress {
    protocol   = "icmp"
    rule_no    = 100
    action     = "allow"
    cidr_block = aws_vpc.Private-VPC-Network-A.cidr_block
    from_port  = 0
    to_port    = 0
    icmp_code = 0
    icmp_type = 0
  }

  egress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = aws_vpc.Private-VPC-Network-A.cidr_block
    from_port  = 1024
    to_port    = 65535
    icmp_code = 0
    icmp_type = 0
  }
}