# Terraform-Projects
This repo contains the terraform code related to specific AWS infrastructure. One can use these in their own infrastructure or modify it as per their need

# Prerequisites

- AWS account
- Terraform installed (version >= 1.5)

# infrastructure

This project basically contains four infrastructure scripts which creates:-

- A three tier application (consists of cloudfront, s3, lambda and dynamoDB)
- A VPC(virtual private cloud)
- VPC peering connection (A connection that helps in communication between two VPCs without taking internet route)
- VPC endpoint (This endpoint helps to use the external services of aws without taking the request through internet gateway)

Note:- This whole setup for creating and testing may cost somewhere around $1 or less. Make sure to delete the resource after you have tested the things to avoid recurring cost.