output "public_ec2_instance_ip" {
  value = aws_instance.public-ec2-instance-VPC.public_ip
}

output "aws_s3_bucket_arn" {
  value = aws_s3_bucket.my-bucket-s3.arn
}