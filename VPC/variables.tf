variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "ap-south-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be a valid region format (e.g., us-east-1)."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix for S3 bucket names (will be combined with random suffix for uniqueness)"
  type        = string
  default     = "vpc-bucket-s3"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name_prefix))
    error_message = "Bucket prefix must contain only lowercase letters, numbers, and hyphens, and cannot start or end with a hyphen."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.environment))
    error_message = "Environment must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "vpc-project"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project_name))
    error_message = "Project name must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to all resources"
  default = {
  }
}

variable "myIP" {
  type        = string
  description = "Your ip address"
}