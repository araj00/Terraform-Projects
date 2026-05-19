# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming convention using project name and random suffix
  name_suffix = "${var.project_name}-${random_id.suffix.hex}"

  content_bucket_name = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
  common_tags = merge({
    Environment = var.environment
    Project = var.project_name
    ManagedBy = "Terraform"
    Recipe      = "content-delivery-networks-cloudfront-origin-access-controls"
  }, 
  var.tags)
}

# Generate a private S3 bucket
resource "aws_s3_bucket" "my-bucket-s3" {
  bucket = local.content_bucket_name

  tags = merge(local.common_tags, {
    Name = "${local.name_suffix}-content"
    Description = "Primary content bucket for CloudFront CDN"
  })
}

# Block all public access to my-bucket-s3 - Security best practice
resource "aws_s3_bucket_public_access_block" "my-bucket-s3"{
    bucket = aws_s3_bucket.my-bucket-s3.id

    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "my-bucket-s3" {
  bucket = aws_s3_bucket.my-bucket-s3.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}