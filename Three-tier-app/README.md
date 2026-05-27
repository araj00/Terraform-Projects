# Run the setup

- cd ./Three-tier-app
- go to getUser.mjs under files folder, and replace the region wihth your region
- terraform init
- terraform plan
- terraform apply
- terraform output
- copy the api_to_fetch_from from the output
- go to files/script.js and replace the endpoint with yours endpoint
- go to your s3 bucket in aws account and upload the new updated script.js
- Now, go to your defined lambda function in aws account and replace the access-control-allow-origin value with the value derived from cloudfront-distribution-name on terraform output result. Deploy that lambda function
- Now, go to a new tab and paste your cloudfront-distribution-name and enter value 1. You will get the user details
- At last, don't forget to destroy your infrastructure by command terraform destroy
