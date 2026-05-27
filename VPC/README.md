# Run the setup

- cd ./VPC
- create private and public key for private and public ec2-instance respectively using ssh-keygen command in the current folder with private-server-key and public-server-key name
- terraform init
- terraform plan
- terraform apply
- terraform output
- ssh into the public ec2 instance using public ip address derived from terraform output command and public-server-key
- Ping the private ec2 instance using its private ip address derived from terraform output comman
- ssh into the private ec2 instance from this public ec2 instance using private key and ping public ec2 instance using its private ip address. Exit from both instances
- terraform destroy
