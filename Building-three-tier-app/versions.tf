# Terraform version and provider requirements
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.45"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.0"
    }

    archive = {
      source = "hashicorp/archive"
      version = "~> 2.8.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Recipe      = "content-delivery-networks-cloudfront-origin-access-controls"
    }
  }
}

