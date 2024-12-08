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
terraform apply -auto-approve
```

### Test

Test lambda and API gateway
```
# write
curl -X POST "$(terraform output -raw gateway_url)/users" --header 'Content-Type: application/json' -d '{"email":"kj@kj.com"}'
curl -X POST "$(terraform output -raw gateway_url)/users" --header 'Content-Type: application/json' -d '{"email":"test@test.com"}'

# read
curl -X GET "$(terraform output -raw gateway_url)/users" --header 'Content-Type: application/json'
curl -X GET "$(terraform output -raw gateway_url)/users/kj@kj.com" --header 'Content-Type: application/json'

# read redshift - run 3 times
curl -X GET "$(terraform output -raw gateway_url)/redshift_users" --header 'Content-Type: application/json'
curl -X GET "$(terraform output -raw gateway_url)/redshift_users" --header 'Content-Type: application/json'
curl -X GET "$(terraform output -raw gateway_url)/redshift_users" --header 'Content-Type: application/json'
```

Error:
```
curl -X GET "$(terraform output -raw gateway_url)/kj" --header 'Content-Type: application/json'
```

## Destroy

```
terraform destroy
```

## TODO
- propagate data from DynamoDB to Redshift

## References

https://developer.hashicorp.com/terraform/tutorials/aws/lambda-api-gateway 

https://github.com/aws-samples/serverless-patterns/blob/main/apigw-lambda-dynamodb-terraform/main.tf

https://registry.terraform.io/modules/terraform-aws-modules/lambda/aws/latest

https://github.com/terraform-aws-modules/terraform-aws-lambda/blob/master/examples/complete/main.tf

https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-dynamo-db.html

https://aws.amazon.com/blogs/big-data/get-started-with-amazon-dynamodb-zero-etl-integration-with-amazon-redshift/

https://github.com/aws-samples/getting-started-with-amazon-redshift-data-api/blob/main/quick-start/python/RedShiftServerlessDataAPI.py

https://aws.amazon.com/blogs/big-data/use-the-amazon-redshift-data-api-to-interact-with-amazon-redshift-serverless/

https://github.com/opszero/terraform-aws-redshift-serverless/blob/main/main.tf

