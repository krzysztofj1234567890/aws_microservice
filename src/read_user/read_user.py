import boto3
import os
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

client = boto3.client('dynamodb')
dynamodb = boto3.resource("dynamodb")

def lambda_handler(event, context):
  table = os.environ.get('DB_TABLE')
  logging.info(f"## Loaded table name from environemt variable DB_TABLE: {table}")
  dynamodb_table = dynamodb.Table( table )
  logging.info( event )
  requestContext = event['requestContext']
  resourceId = requestContext['resourceId'] 
  logging.info( resourceId )
  pathParameters = event['pathParameters']
  logging.info( pathParameters )

  body = {}
  statusCode = 200

  try:
    if resourceId == "GET /users":
        body = dynamodb_table.scan()
        body = body["Items"]
        logging.info( body )
        responseBody = []
        for items in body:
            responseItems = [
                {'email': items['email']}
            ]
            responseBody.append(responseItems)
        body = responseBody
    if resourceId == "GET /users/{email}":
        body = dynamodb_table.get_item( Key={'email': pathParameters['email']})
        body = body["Item"]
        logging.info( body )
        responseBody = [{'email': items['email']}]
        body = responseBody
  except KeyError:
     statusCode = 400
     body = 'Unsupported route: ' + resourceId

  body = json.dumps(body)
  result = {
        "statusCode": statusCode,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": body
  }
  return result
