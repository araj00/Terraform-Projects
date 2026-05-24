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
resource "aws_vpc" "Private-VPC-Network" {
  count = 2
  cidr_block       = "10.${count.index}.0.0/16"
  instance_tenancy = "default"

  tags = merge(local.common_tags, {
    Name        = "${local.name_suffix}-Priavte-VPC-${count.index}"
    Description = "A private VPC network for isolated network"
  })
}

resource "aws_subnet" "private-subnet-VPC" {
  count = length(aws_vpc.Private-VPC-Network)
  vpc_id            = aws_vpc.Private-VPC-Network[count.index].id
  cidr_block        = cidrsubnet(aws_vpc.Private-VPC-Network[count.index].cidr_block, 8, 2)
  availability_zone = data.aws_availability_zones.available.names[random_integer.az_index.result]

  tags = merge(local.common_tags, {
    Name        = "${local.name_suffix}-private-subnet-VPC-${count.index}"
    Description = "A private subnet network for VPC"
  })
}

resource "aws_vpc_peering_connection" "VPC-peercon" {
  peer_vpc_id   = aws_vpc.Private-VPC-Network[0].id
  vpc_id        = aws_vpc.Private-VPC-Network[1].id
  auto_accept   = true
}

resource "aws_default_route_table" "VPC-1-route-table" {
  default_route_table_id = aws_vpc.Private-VPC-Network[0].default_route_table_id

  route {
    cidr_block = aws_vpc.Private-VPC-Network[1].cidr_block
    vpc_peering_connection_id = aws_vpc_peering_connection.VPC-peercon.id
  }
}

resource "aws_default_route_table" "VPC-2-route-table" {
  default_route_table_id = aws_vpc.Private-VPC-Network[1].default_route_table_id

  route {
    cidr_block = aws_vpc.Private-VPC-Network[0].cidr_block
    vpc_peering_connection_id = aws_vpc_peering_connection.VPC-peercon.id
  }
}