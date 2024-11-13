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
module "lambda_function" {
  source = "terraform-aws-modules/lambda/aws"
  function_name = "Hello"
  description   = "My awesome lambda function"
  handler       = "hello.handler"
  runtime       = "nodejs20.x"
  source_path = "src/lambda_hello"
  store_on_s3 = true
  s3_bucket   = aws_s3_bucket.lambda_bucket.id
}

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
}

resource "aws_iam_role" "lambda_exec" {
  name = "LambdaDdbPost"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_exec_role" {
  name = "lambda-tf-pattern-db-post"
  policy = <<POLICY
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
POLICY
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_exec_role.arn
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

### hello.js

# configure api gateway to use the lambda function
resource "aws_apigatewayv2_integration" "hello" {
  api_id = aws_apigatewayv2_api.lambda.id
  integration_uri    = module.lambda_function.lambda_function_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

# routing to lambda
resource "aws_apigatewayv2_route" "hello" {
  api_id = aws_apigatewayv2_api.lambda.id
  route_key = "GET /hello"
  target    = "integrations/${aws_apigatewayv2_integration.hello.id}"
}

resource "aws_lambda_permission" "api_gw_hello" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_function.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}

### write_user.py

resource "aws_apigatewayv2_integration" "write_user" {
  api_id = aws_apigatewayv2_api.lambda.id
  integration_uri    = module.lambda_write_user.lambda_function_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "post" {
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
