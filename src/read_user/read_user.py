import boto3
import os
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb_client = boto3.client('dynamodb')
dynamodb_resource = boto3.resource("dynamodb")

def lambda_handler(event, context):
  table = os.environ.get('DB_TABLE')
  logging.info(f"## Loaded table name from environemt variable DB_TABLE: {table}")
  dynamodb_table = dynamodb_resource.Table( table )
  logging.info( event )
  body = dynamodb_table.scan()
  body = body["Items"]
  logging.info( body )
  statusCode = 200

  responseBody = []
  for items in body:
        responseItems = [
            {'email': items['email']}]
        responseBody.append(responseItems)
  body = responseBody
  body = json.dumps(body)
  res = {
        "statusCode": statusCode,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": body
  }
  return res
