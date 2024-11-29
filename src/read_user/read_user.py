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
  logging.info( f"event: {event}" )
  requestContext = event['requestContext']
  resourceId = requestContext['resourceId'] 
  logging.info( f"resourceId: {resourceId}" )
  pathParameters = event['pathParameters']
  logging.info( f"pathParameters: {pathParameters}" )

  body = {}
  statusCode = 200

  try:
    if resourceId == "GET /users":
        body = dynamodb_table.scan()
        body = body["Items"]
        logging.info( f"body: {body}" )
        responseBody = []
        for items in body:
            responseItems = [
                {'email': items['email']}
            ]
            responseBody.append(responseItems)
        body = responseBody
    elif resourceId == "GET /users/{email+}":
        logging.info( f"pathParameters: {pathParameters['email']}" )
        logging.info( f"BEFORE QUERY" )
        value = pathParameters['email']
        logging.info( f"value: {value}" )
        body = dynamodb_table.get_item( Key={'email': value})
        logging.info( f"AFTER QUERY" )
        logging.info( f"body: {body}" )
        body = body["Item"]
        logging.info( f"body: {body}" )
        responseBody = [{'email': body['email']}]
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
