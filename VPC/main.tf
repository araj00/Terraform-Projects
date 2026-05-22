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
  name = "${var.aws_region}a"
  state = "available"
  filter {
    name = "opt-in-status"
    values = ["opt-in-not-required"]
}
}
resource "aws_vpc" "VPC-Network-A" {
  cidr_block = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = merge(local.common_tags,{
    Name = "${local.name_suffix}-VPC-A"
    Description = "A VPC network for isolated network"
  })
}

resource "aws_subnet" "subnet-VPC-A" {
  vpc_id = aws_vpc.VPC-Network-A.id
  cidr_block = cidrsubnet(aws_vpc.VPC-Network-A.cidr_block,8,1)
  availability_zone = data.aws_availability_zone.available.name
  map_public_ip_on_launch = true

  tags = merge(local.common_tags,{
    Name = "${local.name_suffix}-subnet-VPC-A"
    Description = "A subnet network for VPC A"
  })
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.VPC-Network-A.id

  tags = merge(local.common_tags,{
    Name = "VPC-ig"
    Description = "An internet gateway for the VPC"
  })
}

resource "aws_route_table" "public-route-table-subnet-A" {
  vpc_id = aws_vpc.VPC-Network-A.id

  route {
    cidr_block = aws_vpc.VPC-Network-A.cidr_block
    gateway_id = "local"
  }

  route {
    gateway_id = aws_internet_gateway.gw.id
    cidr_block = "0.0.0.0/0"
  }
}

resource "aws_route_table_association" "subnet-route-association" {
  subnet_id = aws_subnet.subnet-VPC-A.id
  route_table_id = aws_route_table.public-route-table-subnet-A.id
}