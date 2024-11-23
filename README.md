# aws_microservice

## Setup

Check aws configration

```
cat ~/.aws/*
```

## Deploy

```
terraform init
terraform plan
terraform apply
```

### Test

Test lambda
```
aws lambda invoke --region=us-east-1 --function-name=$(terraform output -raw function_name) response.json
cat response.json
```

Test lambda and API gateway
```
curl "$(terraform output -raw gateway_url)/hello"
curl "$(terraform output -raw gateway_url)/hello?Name=Terraform"

curl -X POST "$(terraform output -raw gateway_url)/users"
curl -X POST "$(terraform output -raw gateway_url)/users" --header 'Content-Type: application/json' -d '{"email":"kj@kj.com"}'
```

## Destroy

```
terraform destroy
```

## References
https://developer.hashicorp.com/terraform/tutorials/aws/lambda-api-gateway 

https://github.com/aws-samples/serverless-patterns/blob/main/apigw-lambda-dynamodb-terraform/main.tf