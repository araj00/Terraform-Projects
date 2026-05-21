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

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# Generate a private S3 bucket
resource "aws_s3_bucket" "my-bucket-s3" {
  bucket = local.content_bucket_name

  tags = merge(local.common_tags, {
    Name        = "${local.name_suffix}-bucket"
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
  source_file = "${path.module}/files/getUser.mjs"
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

# AWS IAM role for lambda function 
resource "aws_iam_role" "my-lambda-iam-role" {
  name               = "${local.name_suffix}-lambda-permission"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# Create lambda function with required handler and iam-roles
resource "aws_lambda_function" "my-lambda-function" {
  function_name = "${local.name_suffix}-RetrieveUserData"
  filename = data.archive_file.lambda_function.output_path
  role = aws_iam_role.my-lambda-iam-role.arn

  runtime = "nodejs24.x"
  handler = "getUser.handler"
}

# Create resource api-gateway
resource "aws_api_gateway_rest_api" "my-lambda-rest-api" {
  name = "${local.name_suffix}-rest-api-gateway"
  description = "This is an API for retrieving user details"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# Create an api gateway resource
resource "aws_api_gateway_resource" "my-lambda-rest-api-resource" {
  parent_id   = aws_api_gateway_rest_api.my-lambda-rest-api.root_resource_id
  path_part   = "user"
  rest_api_id = aws_api_gateway_rest_api.my-lambda-rest-api.id
}

# Create endpoint of api gateway as per its method
resource "aws_api_gateway_method" "my-lambda-function-api-method" {
  rest_api_id = aws_api_gateway_rest_api.my-lambda-rest-api.id
  resource_id = aws_api_gateway_resource.my-lambda-rest-api-resource.id
  http_method = "GET"
  authorization = "NONE"
}

# Integrate lambda proxy in api method so that all request body can be deserialized in lambda function
resource "aws_api_gateway_integration" "my-lambda-function-api-method" {
  resource_id = aws_api_gateway_resource.my-lambda-rest-api-resource.id
  rest_api_id = aws_api_gateway_rest_api.my-lambda-rest-api.id
  http_method = aws_api_gateway_method.my-lambda-function-api-method.http_method
  integration_http_method = "POST"
  type = "AWS_PROXY"
  uri = aws_lambda_function.my-lambda-function.invoke_arn
}

# Allow permission to invoke lambda function through api gateway
resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.my-lambda-function.function_name
  principal     = "apigateway.amazonaws.com"

  # More: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
  source_arn = "arn:${data.aws_partition.current.partition}:execute-api:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.my-lambda-rest-api.id}/*/${aws_api_gateway_method.my-lambda-function-api-method.http_method}${aws_api_gateway_resource.my-lambda-rest-api-resource.path}"
}

# Create the deployment of api gateway so that we can use its url instead of direction lambda function uri
resource "aws_api_gateway_deployment" "my-lambda-function-api-method" {
  rest_api_id = aws_api_gateway_rest_api.my-lambda-rest-api.id
  description = "Deployment for staging ${var.environment}"

  triggers = {
    # NOTE: The configuration below will satisfy ordering considerations,
    #       but not pick up all future REST API changes. More advanced patterns
    #       are possible, such as using the filesha1() function against the
    #       Terraform configuration file(s) or removing the .id references to
    #       calculate a hash against whole resources. Be aware that using whole
    #       resources will show a difference after the initial implementation.
    #       It will stabilize to only change when resources change afterwards.
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.my-lambda-rest-api-resource.id,
      aws_api_gateway_method.my-lambda-function-api-method.id,
      aws_api_gateway_integration.my-lambda-function-api-method.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Create a staging for the api gateway. Chose dev but it can be production , testing for staging
resource "aws_api_gateway_stage" "my-lambda-function-api-method" {
  deployment_id = aws_api_gateway_deployment.my-lambda-function-api-method.id
  rest_api_id   = aws_api_gateway_rest_api.my-lambda-rest-api.id
  stage_name    = var.environment
}

resource "aws_dynamodb_table" "user-dynamodb-table" {
  name           = "UserData"
  billing_mode   = "PROVISIONED"
  read_capacity  = 20
  write_capacity = 20
  hash_key       = "userId"

  attribute {
    name = "userId"
    type = "S"
  }
}

resource "aws_dynamodb_table_item" "user-dynamodb_table" {
  table_name = aws_dynamodb_table.user-dynamodb-table.name
  hash_key   = aws_dynamodb_table.user-dynamodb-table.hash_key

  item = <<ITEM
{
  "userId": {"S": "1"},
  "email": {"S": "abc@gmail.com"},
  "name": {"S": "abc"}
}
ITEM
}

# Create the IAM Policy for DynamoDB Access
resource "aws_iam_policy" "dynamodb_lambda_policy" {
  name        = "${local.name_suffix}-dynamodb-lambda-policy"
  description = "Policy to allow Lambda to access DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem"
        ]
        Resource = [
          aws_dynamodb_table.user-dynamodb-table.arn
        ]
      }
    ]
  })
}

# Attach the Policy to the Role
resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.my-lambda-iam-role.name
  policy_arn = aws_iam_policy.dynamodb_lambda_policy.arn
}