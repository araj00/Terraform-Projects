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
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Recipe      = "content-delivery-networks-cloudfront-origin-access-controls"
    },
  var.tags)
}

# Generate a private S3 bucket
resource "aws_s3_bucket" "my-bucket-s3" {
  bucket = local.content_bucket_name

  tags = merge(local.common_tags, {
    Name        = "${local.name_suffix}-content"
    Description = "Primary content bucket for CloudFront CDN"
  })
}

# Block all public access to my-bucket-s3 - Security best practice
resource "aws_s3_bucket_public_access_block" "my-bucket-s3" {
  bucket = aws_s3_bucket.my-bucket-s3.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
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

# OAC for cloudfront to s3 secure access
resource "aws_cloudfront_origin_access_control" "my-cloudfront-cdn" {
  name                              = "${local.name_suffix}-oac"
  description                       = "Origin access control for ${local.content_bucket_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# cloudfront distribution
resource "aws_s3_bucket_policy" "my-bucket-s3" {
  bucket = aws_s3_bucket.my-bucket-s3.id
  policy = data.aws_iam_policy_document.origin_bucket_policy.json
}

# Origin bucket policy to enable OAC with cloudfront
data "aws_iam_policy_document" "origin_bucket_policy" {
  statement {
    sid    = "AllowCloudFrontServicePrincipalReadWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.my-bucket-s3.arn}/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"

      values = [aws_cloudfront_distribution.s3_distribution.arn]
    }
  }
}

# uploading files to s3 bucket
resource "aws_s3_object" "s3-object" {
  bucket   = aws_s3_bucket.my-bucket-s3.id
  for_each = { for item in var.files_source : item.file => item }
  key      = basename(each.value.file)
  source   = each.value.file
  content_type = each.value.content-type
}

# CloudFront distribution with multiple cache behaviors and security features
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    origin_access_control_id = aws_cloudfront_origin_access_control.my-cloudfront-cdn.id
    domain_name              = aws_s3_bucket.my-bucket-s3.bucket_regional_domain_name
    origin_id                = local.content_bucket_name
  }

  enabled             = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  viewer_certificate {
    minimum_protocol_version       = "TLSv1.2_2021"
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    target_origin_id       = local.content_bucket_name
    viewer_protocol_policy = "redirect-to-https"
  }
}

# Package the Lambda function code
data "archive_file" "lambda_function" {
  type = "zip"
  source_file = "${path.module}/files/getUser.js"
  output_path = "${path.module}/files/getUser.zip"
}

# IAM role for Lambda execution
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "my-lambda-iam-role" {
  name               = "${local.name_suffix}-lambda-permission"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}


resource "aws_lambda_function" "my-lambda-function" {
  function_name = "${local.name_suffix}-lambda"
  filename = data.archive_file.lambda_function.output_path
  role = aws_iam_role.my-lambda-iam-role.arn

  runtime = "nodejs24.x"
  handler = "getUser.handler"

}