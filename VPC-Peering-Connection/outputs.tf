output "public-ec2-instance-private-ip" {
  description = "Private ip address of public ec2 instance"
  value = aws_instance.public-ec2-instance-VPC-A.private_ip
}

output "public-ec2-instance-public-ip" {
  description = "Public ip address of public ec2 instance"
  value = aws_instance.public-ec2-instance-VPC-A.public_ip
}

output "private-ec2-instance-private-ip" {
  description = "Private ip address of private ec2 instance"
  value = aws_instance.private-ec2-instance-VPC-B.private_ip
}