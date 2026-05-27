# Run the setup

- cd ./VPC-Endpoint
- create private key for public and private ec2-instances using ssh-keygen command in the current folder with private-server-key name. (Just use single key for both instances for simplicity)
- terraform init
- terraform plan
- terraform apply
- terraform output
- ssh into the public ec2 instance using public ip address derived from terraform output command and public-server-key
- ping the private ip address of private instance in another VPC and ssh into it from this ec2 instance using the ssh key. Try to ping the public ec2 instance of first VPC. It works. Now, try to ping any ip address on the internet, it will not work as it is not connected to internet
- terraform destroy