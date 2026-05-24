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

# Associate the subnet with VPC network and auto-assign ipv4 setting
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

# Create a custom route table for the VPC making it public by adding the route table for IG
resource "aws_route_table" "public-route-table-subnet-A" {
  vpc_id = aws_vpc.VPC-Network-A.id

  route {
    gateway_id = aws_internet_gateway.gw.id
    cidr_block = "0.0.0.0/0"
  }
}

# Create a private route table to be within VPC network without internet access
resource "aws_subnet" "private-subnet-VPC-A" {
  vpc_id            = aws_vpc.VPC-Network-A.id
  cidr_block        = cidrsubnet(aws_vpc.VPC-Network-A.cidr_block, 8, 2)
  availability_zone = data.aws_availability_zone.available.name

  tags = merge(local.common_tags, {
    Name        = "${local.name_suffix}-private-subnet-VPC-A"
    Description = "A private subnet network for VPC A"
  })
}

# Associating public subnet with public route table
resource "aws_route_table_association" "public-subnet-route-association" {
  subnet_id      = aws_subnet.public-subnet-VPC-A.id
  route_table_id = aws_route_table.public-route-table-subnet-A.id
}

# Associating private subnet with private route table
resource "aws_route_table_association" "private-subnet-route-association" {
  subnet_id      = aws_subnet.private-subnet-VPC-A.id
  route_table_id = aws_vpc.VPC-Network-A.main_route_table_id
}

# Create a network acl for the subnet with network policies
resource "aws_network_acl" "private-nacl-VPC-A" {
  vpc_id = aws_vpc.VPC-Network-A.id

  ingress {
    rule_no    = 100
    protocol   = "icmp"
    action     = "allow"
    cidr_block = aws_subnet.public-subnet-VPC-A.cidr_block
    from_port  = 0
    to_port    = 0
    icmp_type = -1
    icmp_code = -1
  }

  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = aws_subnet.public-subnet-VPC-A.cidr_block
    from_port  = 22
    to_port    = 22
  }
  egress {
    rule_no    = 100
    protocol   = "icmp"
    action     = "allow"
    cidr_block = aws_subnet.public-subnet-VPC-A.cidr_block
    from_port  = 0
    to_port    = 0
    icmp_type = -1 # equivalent to all port range if type and code both are -1
    icmp_code = -1
  }
  egress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = aws_subnet.public-subnet-VPC-A.cidr_block
    from_port  = 1024
    to_port    = 65535
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_suffix}-private-nacl-VPC-A"
    Description = "A private network ACL for VPC A"
  })
}

# Associating private NACL with private subnet whereas default NACL are attached to default subnet of VPC
resource "aws_network_acl_association" "private-nacl-VPC-A" {
  network_acl_id = aws_network_acl.private-nacl-VPC-A.id
  subnet_id      = aws_subnet.private-subnet-VPC-A.id
}

# Security groups are for the ec2 instances defined in the given subnet
resource "aws_vpc_security_group_ingress_rule" "default-security-ssh-rule-VPC-A" {
  security_group_id = aws_vpc.VPC-Network-A.default_security_group_id

  cidr_ipv4   = var.myIP
  from_port   = 22
  ip_protocol = "tcp"
  to_port     = 22
}

# custom policy rules for default security groups in VPC
resource "aws_vpc_security_group_ingress_rule" "default-security-icmp-rule-VPC-A" {
  security_group_id = aws_vpc.VPC-Network-A.default_security_group_id

  cidr_ipv4   = var.myIP
  from_port   = -1
  ip_protocol = "icmp"
  to_port     = -1
}

resource "aws_vpc_security_group_ingress_rule" "default-security-icmp-rule-subnet-2-VPC-A" {
  security_group_id = aws_vpc.VPC-Network-A.default_security_group_id

  cidr_ipv4   = aws_subnet.private-subnet-VPC-A.cidr_block
  from_port   = -1
  ip_protocol = "icmp"
  to_port     = -1
}

# custom security groups in VPC
resource "aws_security_group" "allow_ssh_and_icmp" {
  name        = "${local.name_suffix}_allow_ssh_and_icmp"
  description = "Allow TLS inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.VPC-Network-A.id

  tags = {
    Name = "allow_ssh_and_icmp_and_icmp"
  }
}

# custom policy rules for custom security groups in VPC
resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv4" {
  security_group_id = aws_security_group.allow_ssh_and_icmp.id
  cidr_ipv4         = aws_subnet.public-subnet-VPC-A.cidr_block
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}
resource "aws_vpc_security_group_ingress_rule" "allow_icmp_request" {
  security_group_id = aws_security_group.allow_ssh_and_icmp.id
  cidr_ipv4         = aws_subnet.public-subnet-VPC-A.cidr_block
  ip_protocol       = "icmp"
  from_port = -1
  to_port = -1
}

resource "aws_vpc_security_group_egress_rule" "allow_icmp_request" {
  security_group_id = aws_security_group.allow_ssh_and_icmp.id
  cidr_ipv4         = aws_subnet.public-subnet-VPC-A.cidr_block
  ip_protocol       = "icmp"
  from_port = -1
  to_port = -1
}

# Attach the key pair to ssh into public ec2-instances after initialization
resource "aws_key_pair" "public-ec2-key" {
  key_name   = var.public-ec2-key-name
  public_key = file("${path.module}/public-server-key.pub")
}

# A public ec2-instance in public subnet with internet gateway
resource "aws_instance" "public-ec2-instance" {
  ami                    = var.instance-ami
  instance_type          = var.instance-type
  key_name               = aws_key_pair.public-ec2-key.key_name
  vpc_security_group_ids = [aws_vpc.VPC-Network-A.default_security_group_id]
  subnet_id              = aws_subnet.public-subnet-VPC-A.id

  tags = merge(local.common_tags, {
    Name = "Public-ec2-instance-VPC-A"
  })
}

# Attach the key pair to ssh into private ec2-instance through public ec2 instance as private does not have any internet access
resource "aws_key_pair" "private-ec2-key" {
  key_name   = var.private-ec2-key-name
  public_key = file("${path.module}/private-server-key.pub")
}

# A private ec2-instance in private VPC
resource "aws_instance" "private-ec2-instance" {
  ami                    = var.instance-ami
  instance_type          = var.instance-type
  key_name               = aws_key_pair.private-ec2-key.key_name
  vpc_security_group_ids = [aws_security_group.allow_ssh_and_icmp.id]
  subnet_id              = aws_subnet.private-subnet-VPC-A.id

  tags = merge(local.common_tags, {
    Name = "Private-ec2-instance-VPC-A"
  })
}