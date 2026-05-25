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
    Recipe      = "virtual-private-network-with-peering-connection"
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
resource "aws_vpc" "Public-VPC-Network-A" {
  cidr_block       = "10.1.0.0/16"
  instance_tenancy = "default"

  tags = merge(local.common_tags, {
    Name        = "${local.name_suffix}-Public-VPC-A"
    Description = "A private VPC network for isolated network"
  })
}

resource "aws_vpc" "Private-VPC-Network-B" {
  cidr_block       = "10.2.0.0/16"
  instance_tenancy = "default"

  tags = merge(local.common_tags, {
    Name        = "${local.name_suffix}-Private-VPC-B"
    Description = "A private VPC network for isolated network"
  })
}

resource "aws_subnet" "public-subnet-VPC-A" {
  vpc_id            = aws_vpc.Public-VPC-Network-A.id
  cidr_block        = cidrsubnet(aws_vpc.Public-VPC-Network-A.cidr_block, 8, 2)
  availability_zone = data.aws_availability_zones.available.names[random_integer.az_index.result]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name        = "${local.name_suffix}-public-subnet-VPC-A"
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
  peer_vpc_id   = aws_vpc.Public-VPC-Network-A.id
  vpc_id        = aws_vpc.Private-VPC-Network-B.id
  auto_accept   = true
}

resource "aws_internet_gateway" "public-subnet-IG" {
vpc_id = aws_vpc.Public-VPC-Network-A.id
  tags = merge(local.common_tags, {
    Name        = "VPC-ig"
    Description = "An internet gateway for the VPC-A"
  })
}

resource "aws_default_route_table" "VPC-1-route-table" {
  default_route_table_id = aws_vpc.Public-VPC-Network-A.default_route_table_id

  route {
    cidr_block = aws_vpc.Private-VPC-Network-B.cidr_block
    vpc_peering_connection_id = aws_vpc_peering_connection.VPC-peercon.id
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.public-subnet-IG.id
  }
}

resource "aws_default_route_table" "VPC-2-route-table" {
  default_route_table_id = aws_vpc.Private-VPC-Network-B.default_route_table_id

  route {
    cidr_block = aws_vpc.Public-VPC-Network-A.cidr_block
    vpc_peering_connection_id = aws_vpc_peering_connection.VPC-peercon.id
  }
}

resource "aws_default_network_acl" "aws-deny-all-outer-traffic-to-VPC-B" {
  
  default_network_acl_id = aws_vpc.Private-VPC-Network-B.default_network_acl_id
  subnet_ids = [aws_subnet.private-subnet-VPC-B.id]

  ingress {
    protocol   = "icmp"
    rule_no    = 100
    action     = "allow"
    cidr_block = aws_vpc.Public-VPC-Network-A.cidr_block
    from_port  = 0
    to_port    = 0
    icmp_code = -1
    icmp_type = -1
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = aws_vpc.Public-VPC-Network-A.cidr_block
    from_port  = 22
    to_port    = 22
  }
  egress {
    protocol   = "icmp"
    rule_no    = 100
    action     = "allow"
    cidr_block = aws_vpc.Public-VPC-Network-A.cidr_block
    from_port  = 0
    to_port    = 0
    icmp_code = -1
    icmp_type = -1
  }

  egress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = aws_vpc.Public-VPC-Network-A.cidr_block
    from_port  = 1024
    to_port    = 65535
  }
}

resource "aws_default_security_group" "default-security-group-VPC-A" {
  vpc_id = aws_vpc.Public-VPC-Network-A.id
  ingress {
    protocol  = "icmp"
    from_port = -1
    to_port   = -1
    cidr_blocks = [aws_vpc.Private-VPC-Network-B.cidr_block, var.myIP]
  }

  egress {
    protocol  = "icmp"
    from_port = -1
    to_port   = -1
    cidr_blocks = [aws_vpc.Private-VPC-Network-B.cidr_block]
  }
  ingress {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
    cidr_blocks = [var.myIP]
  }

  egress {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
    cidr_blocks = [aws_vpc.Private-VPC-Network-B.cidr_block]
  }

}

resource "aws_default_security_group" "default-security-group-VPC-B" {
  vpc_id = aws_vpc.Private-VPC-Network-B.id
  ingress {
    protocol  = "icmp"
    from_port = -1
    to_port   = -1
    cidr_blocks = [aws_vpc.Public-VPC-Network-A.cidr_block]
  }

  egress {
    protocol  = "icmp"
    from_port = -1
    to_port   = -1
    cidr_blocks = [aws_vpc.Public-VPC-Network-A.cidr_block]
  }
  ingress {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
    cidr_blocks = [aws_vpc.Public-VPC-Network-A.cidr_block]
  }
}
resource "aws_key_pair" "ec2-key" {
  key_name   = var.ec2-key-name
  public_key = file("${path.module}/private-server-key.pub")
}

# A public ec2-instance in public subnet with internet gateway
resource "aws_instance" "public-ec2-instance-VPC-A" {
  ami                    = var.instance-ami
  instance_type          = var.instance-type
  key_name               = aws_key_pair.ec2-key.key_name
  vpc_security_group_ids = [aws_vpc.Public-VPC-Network-A.default_security_group_id]
  subnet_id = aws_subnet.public-subnet-VPC-A.id

  tags = merge(local.common_tags, {
    Name = "Public-ec2-instance-VPC-A"
  })
}

# A private ec2-instance in private VPC
resource "aws_instance" "private-ec2-instance-VPC-B" {
  ami                    = var.instance-ami
  instance_type          = var.instance-type
  key_name               = aws_key_pair.ec2-key.key_name
  vpc_security_group_ids = [aws_vpc.Private-VPC-Network-B.default_security_group_id]
  subnet_id = aws_subnet.private-subnet-VPC-B.id

  tags = merge(local.common_tags, {
    Name = "Private-ec2-instance-VPC-B"
  })
}