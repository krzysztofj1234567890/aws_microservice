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

Test lambda and API gateway
```
# write
curl -X POST "$(terraform output -raw gateway_url)/users" --header 'Content-Type: application/json' -d '{"email":"kj@kj.com"}'

# read
curl -X GET "$(terraform output -raw gateway_url)/users" --header 'Content-Type: application/json'
```

## Destroy

```
terraform destroy
```

## References
https://developer.hashicorp.com/terraform/tutorials/aws/lambda-api-gateway 

https://github.com/aws-samples/serverless-patterns/blob/main/apigw-lambda-dynamodb-terraform/main.tf

https://registry.terraform.io/modules/terraform-aws-modules/lambda/aws/latest

https://github.com/terraform-aws-modules/terraform-aws-lambda/blob/master/examples/complete/main.tf