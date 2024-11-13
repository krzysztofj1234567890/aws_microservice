import boto3
import os
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb_client = boto3.client('dynamodb')

def lambda_handler(event, context):
  table = os.environ.get('DDB_TABLE')
  logging.info(f"## Loaded table name from environemt variable DB_TABLE: {table}")
  if event["body"]:
      item = json.loads(event["body"])
      logging.info(f"## Received payload: {item}")
      email = str(item["email"])
      dynamodb_client.put_item(TableName=table,Item={"email": {'S':email}})
      message = "Successfully inserted data!"
      return {
          "statusCode": 200,
          "headers": {
              "Content-Type": "application/json"
          },
          "body": json.dumps({"message": message})
      }
  else:
      logging.info("## Received request without a payload")
      dynamodb_client.put_item(TableName=table,Item={"email": {'S':'test@test.com'}})
      message = "Successfully inserted data!"
      return {
          "statusCode": 200,
          "headers": {
              "Content-Type": "application/json"
          },
          "body": json.dumps({"message": message})
      }