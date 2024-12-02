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
  point_in_time_recovery {
    enabled = true
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

#######################################################
# Redshift 
#######################################################
data "aws_availability_zones" "available" {}

locals {
  # name     = "kj-${basename(path.cwd)}"
  name        = "kj-redshift"
  vpc_cidr    = var.vpc_cidr
  azs         = slice(data.aws_availability_zones.available.names, 0, 3)
  s3_prefix   = "redshift/${local.name}/"
}

module "redshift" {
  source = "terraform-aws-modules/redshift/aws"
  cluster_identifier      = local.name
  allow_version_upgrade   = true
  node_type               = "ra3.xlplus"
  number_of_nodes         = 3
  database_name           = "kjdb"
  master_username         = "kjdbuser"
  create_random_password  = true
  #manage_master_password  = true
  #manage_master_password_rotation              = true
  #master_password_rotation_schedule_expression = "rate(90 days)"
  encrypted               = true
  #kms_key_arn             = aws_kms_key.redshift.arn
  enhanced_vpc_routing    = true
  vpc_security_group_ids  = [module.security_group.security_group_id]
  subnet_ids              = module.vpc.redshift_subnets
  availability_zone_relocation_enabled = false
  logging = {
    # bucket_name   = aws_s3_bucket.lambda_bucket.id
    bucket_name     = module.s3_logs.s3_bucket_id
    s3_key_prefix = local.s3_prefix
  }
}

module "vpc" {
  source            = "terraform-aws-modules/vpc/aws"
  version           = "~> 5.0"
  name              = local.name
  cidr              = local.vpc_cidr
  azs               = local.azs
#  private_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
#  redshift_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 10)]
  private_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  redshift_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k + 4)]
  create_redshift_subnet_group = false
}

module "security_group" {
  source  = "terraform-aws-modules/security-group/aws//modules/redshift"
  version = "~> 5.0"
  name        = local.name
  description = "Redshift security group"
  vpc_id      = module.vpc.vpc_id
  # Allow ingress rules to be accessed only within current VPC
  ingress_rules       = ["redshift-tcp"]
  ingress_cidr_blocks = [module.vpc.vpc_cidr_block]
  # Allow all rules for all protocols
  egress_rules = ["all-all"]
}

#resource "aws_kms_key" "redshift" {
#  description             = "Customer managed key for encrypting Redshift cluster"
#  deletion_window_in_days = 7
#  enable_key_rotation     = true
#}

data "aws_iam_policy_document" "s3_redshift" {
  statement {
    sid       = "RedshiftAcl"
    actions   = ["s3:GetBucketAcl"]
    resources = [module.s3_logs.s3_bucket_arn]
    principals {
      type        = "Service"
      identifiers = ["redshift.amazonaws.com"]
    }
  }

  statement {
    sid       = "RedshiftWrite"
    actions   = ["s3:PutObject"]
    resources = ["${module.s3_logs.s3_bucket_arn}/${local.s3_prefix}*"]
    condition {
      test     = "StringEquals"
      values   = ["bucket-owner-full-control"]
      variable = "s3:x-amz-acl"
    }
    principals {
      type        = "Service"
      identifiers = ["redshift.amazonaws.com"]
    }
  }
}

module "s3_logs" {
  source                = "terraform-aws-modules/s3-bucket/aws"
  version               = "~> 3.0"
  bucket_prefix         = local.name
  acl                   = "log-delivery-write"
  control_object_ownership = true
  object_ownership      = "ObjectWriter"
  attach_policy         = true
  policy                = data.aws_iam_policy_document.s3_redshift.json
  attach_deny_insecure_transport_policy = true
  force_destroy         = true
}