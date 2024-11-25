#######################################################
# create S3
#######################################################

# create S3 bucket
resource "aws_s3_bucket" "lambda_bucket" {
    bucket = var.bucket_name
}

# bucket ownership
resource "aws_s3_bucket_ownership_controls" "lambda_bucket" {
    bucket = aws_s3_bucket.lambda_bucket.id
    rule {
        object_ownership = "BucketOwnerPreferred"
    }
}

# bucket acl
resource "aws_s3_bucket_acl" "lambda_bucket" {
    depends_on = [
        aws_s3_bucket_ownership_controls.lambda_bucket,
    ]
    bucket  = aws_s3_bucket.lambda_bucket.id
    acl     = "private"
}

#######################################################
# create database
#######################################################
resource "aws_dynamodb_table" "user_table" {
  name           = "user_table"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "email"
  attribute {
    name = "email"
    type = "S"
  }
}

#######################################################
# create lambda(s)
#######################################################
module "lambda_write_user" {
  source = "terraform-aws-modules/lambda/aws"
  function_name = "WriteUser"
  description   = "Create or update user"
  handler       = "write_user.lambda_handler"
  runtime       = "python3.8"
  source_path = "src/write_user"
  store_on_s3 = true
  s3_bucket   = aws_s3_bucket.lambda_bucket.id
  environment_variables = {
    DB_TABLE = "user_table"
  }
  logging_log_group             = "/aws/lambda/write_user_test"
  logging_log_format            = "JSON"
  logging_application_log_level = "INFO"
  logging_system_log_level      = "DEBUG"

  attach_policy_jsons = true
  policy_jsons = [
    <<-EOT
      {
          "Version": "2012-10-17",
          "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "dynamodb:GetItem",
                    "dynamodb:PutItem",
                    "dynamodb:UpdateItem"
                ],
                "Resource": "arn:aws:dynamodb:*:*:table/user_table"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ],
                "Resource": "*"
            }
          ]
      }
    EOT
  ]
  number_of_policy_jsons = 1
}

module "lambda_read_user" {
  source = "terraform-aws-modules/lambda/aws"
  function_name = "ReadUser"
  description   = "List users"
  handler       = "read_user.lambda_handler"
  runtime       = "python3.8"
  source_path = "src/read_user"
  store_on_s3 = true
  s3_bucket   = aws_s3_bucket.lambda_bucket.id
  environment_variables = {
    DB_TABLE = "user_table"
  }
  logging_log_group             = "/aws/lambda/read_user_test"
  logging_log_format            = "JSON"
  logging_application_log_level = "INFO"
  logging_system_log_level      = "DEBUG"

  attach_policy_jsons = true
  policy_jsons = [
    <<-EOT
      {
          "Version": "2012-10-17",
          "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "dynamodb:GetItem",
                    "dynamodb:PutItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:Scan"
                ],
                "Resource": "arn:aws:dynamodb:*:*:table/user_table"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ],
                "Resource": "*"
            }
          ]
      }
    EOT
  ]
  number_of_policy_jsons = 1
}

#######################################################
# create API Gateway
#######################################################

resource "aws_apigatewayv2_api" "lambda" {
  name          = "serverless_lambda_gw"
  protocol_type = "HTTP"
}

# define single stage
resource "aws_apigatewayv2_stage" "lambda" {
  api_id = aws_apigatewayv2_api.lambda.id
  name        = "serverless_lambda_stage"
  auto_deploy = true
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/api_gw/${aws_apigatewayv2_api.lambda.name}"
  retention_in_days = 3
}

#######################################################
# Lambda(s) routing
#######################################################

### write_user.py

resource "aws_apigatewayv2_integration" "write_user" {
  api_id = aws_apigatewayv2_api.lambda.id
  integration_uri    = module.lambda_write_user.lambda_function_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "write_user" {
  api_id = aws_apigatewayv2_api.lambda.id
  route_key = "POST /users"
  target    = "integrations/${aws_apigatewayv2_integration.write_user.id}"
}

resource "aws_lambda_permission" "api_gw_write_user" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_write_user.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}

## read_user.py

resource "aws_apigatewayv2_integration" "read_user" {
  api_id = aws_apigatewayv2_api.lambda.id
  integration_uri    = module.lambda_read_user.lambda_function_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "read_user_1" {
  api_id = aws_apigatewayv2_api.lambda.id
  route_key = "GET /users"
  target    = "integrations/${aws_apigatewayv2_integration.read_user.id}"
}

resource "aws_apigatewayv2_route" "read_user_2" {
  api_id = aws_apigatewayv2_api.lambda.id
  route_key = "GET /users/{email+}"
  target    = "integrations/${aws_apigatewayv2_integration.read_user.id}"
}

resource "aws_lambda_permission" "api_gw_read_user" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_read_user.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}
