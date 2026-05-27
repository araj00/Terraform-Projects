output "api_gateway_stage_endpoint" {
    description = "api gateway stage endpoint"
    value = aws_api_gateway_stage.my-lambda-function-api-method.invoke_url
}

output "api_to_fetch_from" {
    value = "${aws_api_gateway_stage.my-lambda-function-api-method.invoke_url}${aws_api_gateway_resource.my-lambda-rest-api-resource.path}"
}

output "cloudfront-distribution-name" {
  description = "cloudfront domain name"
  value = "https://${aws_cloudfront_distribution.s3_distribution.domain_name}"
}