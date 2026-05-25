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
    Recipe      = "VPC-endpoint"
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
resource "aws_vpc" "Public-VPC-Network" {
  cidr_block       = "10.1.0.0/16"
  instance_tenancy = "default"

  tags = merge(local.common_tags, {
    Name        = "${local.name_suffix}-Public-VPC"
    Description = "A private VPC network for isolated network"
  })
}

resource "aws_subnet" "public-subnet-VPC" {
  vpc_id            = aws_vpc.Public-VPC-Network.id
  cidr_block        = cidrsubnet(aws_vpc.Public-VPC-Network.cidr_block, 8, 2)
  availability_zone = data.aws_availability_zones.available.names[random_integer.az_index.result]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name        = "${local.name_suffix}-public-subnet-VPC"
    Description = "A private subnet network for VPC"
  })
}

resource "aws_internet_gateway" "public-subnet-IG" {
vpc_id = aws_vpc.Public-VPC-Network.id
  tags = merge(local.common_tags, {
    Name        = "VPC-ig"
    Description = "An internet gateway for the VPC"
  })
}

resource "aws_default_route_table" "VPC-1-route-table" {
  default_route_table_id = aws_vpc.Public-VPC-Network.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.public-subnet-IG.id
  }
}

resource "aws_default_security_group" "default-security-group-VPC" {
  vpc_id = aws_vpc.Public-VPC-Network.id
  ingress {
    protocol  = "icmp"
    from_port = -1
    to_port   = -1
    cidr_blocks = [var.myIP]
  }

  ingress {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
    cidr_blocks = [var.myIP]
  }

  egress {
    protocol = "tcp"
    from_port = 443
    to_port = 443
    prefix_list_ids = [aws_vpc_endpoint.s3-vpc-endpoint.prefix_list_id]
  }

}

resource "aws_key_pair" "ec2-key" {
  key_name   = var.ec2-key-name
  public_key = file("${path.module}/public-server-key.pub")
}

# A public ec2-instance in public subnet with internet gateway
resource "aws_instance" "public-ec2-instance-VPC" {
  ami                    = var.instance-ami
  instance_type          = var.instance-type
  key_name               = aws_key_pair.ec2-key.key_name
  vpc_security_group_ids = [aws_vpc.Public-VPC-Network.default_security_group_id]
  subnet_id = aws_subnet.public-subnet-VPC.id

  tags = merge(local.common_tags, {
    Name = "Public-ec2-instance-VPC"
  })
}

# Generate a private S3 bucket
resource "aws_s3_bucket" "my-bucket-s3" {
  bucket = local.content_bucket_name

  tags = merge(local.common_tags, {
    Name        = "${local.name_suffix}-bucket"
    Description = "Primary content bucket for CloudFront CDN"
  })
}

# S3 Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "my-bucket-s3" {
  bucket = aws_s3_bucket.my-bucket-s3.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "s3-object" {
  bucket   = aws_s3_bucket.my-bucket-s3.id
  for_each = { for item in var.files_source : item.file => item }
  key      = basename(each.value.file)
  source   = each.value.file
  content_type = each.value.content-type
}

# Gateway VPC Endpoint for S3 with restricted policy
resource "aws_vpc_endpoint" "s3-vpc-endpoint" {
  vpc_id       = aws_vpc.Public-VPC-Network.id
  service_name = "com.amazonaws.ap-south-1.s3"
  vpc_endpoint_type = "Gateway"

  # Associate with route tables - this automatically adds routes
  route_table_ids = [aws_vpc.Public-VPC-Network.main_route_table_id]

  tags = {
    Name = "s3-gateway-endpoint"
  }
}

resource "aws_s3_bucket_policy" "allow_access_to_specific_vpce_only" {
  bucket = aws_s3_bucket.my-bucket-s3.id

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
        "Sid": "Access-to-specific-VPCE-only",
        "Principal": "*",
        "Action": "s3:*",
        "Effect": "Deny",
        "Resource": ["${aws_s3_bucket.my-bucket-s3.arn}",
                    "${aws_s3_bucket.my-bucket-s3.arn}/*"],
        "Condition": {
            "StringNotEquals": {
            "aws:SourceVpce": "${aws_vpc_endpoint.s3-vpc-endpoint.id}"
            }
        }
    }
    ]
  })

  depends_on = [ aws_vpc_endpoint.s3-vpc-endpoint, aws_s3_object.s3-object, aws_s3_bucket_server_side_encryption_configuration.my-bucket-s3 ]
}