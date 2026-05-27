# Run the setup

- cd ./VPC-Endpoint
- create public key for public ec2-instance using ssh-keygen command in the current folder with public-server-key name
- terraform init
- terraform plan
- terraform apply
- terraform output
- ssh into the public ec2 instance using public ip address derived from terraform output command and public-server-key
- Use command like aws s3 ls YOUR-BUCKET-NAME , s3 mv, s3 rm etc to list , move and remove objects.
- Before destroying the infra, first delete the created s3-bucket and its object from instance only as it is only accessible through this vpc only not even through aws dashboard
- terraform destroy
