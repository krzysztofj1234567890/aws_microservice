output "lambda_bucket_name" {
  description = "Name of the S3 bucket used to store function code."
  value = aws_s3_bucket.lambda_bucket.id
}
output "lambda_write_user" {
  description = "Name of the Lambda write function."
  value = module.lambda_write_user.lambda_function_name
}
output "lambda_read_user" {
  description = "Name of the Lambda read function."
  value = module.lambda_read_user.lambda_function_name
}
output "gateway_url" {
  description = "Base URL for API Gateway stage."
  value = aws_apigatewayv2_stage.lambda.invoke_url
}
