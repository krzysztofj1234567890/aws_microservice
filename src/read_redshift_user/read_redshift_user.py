import boto3
import os
import logging
import time
import traceback
from collections import OrderedDict

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

  # TODO redshift_workgroup_name=event['kj-workgroup']
  # TODO redshift_database_name = event['redshift_database']
  redshift_workgroup_name='kj-workgroup'
  redshift_database_name = 'kj_database'

  sql_statements = OrderedDict()
  res = OrderedDict()

  body = {}
  statusCode = 200

  try:
    if resourceId == "GET /redshift_users":
        redshift_data_api_client = boto3.client('redshift-data')
        sql_statements['CREATE'] = "CREATE TABLE IF NOT EXISTS public.email (" + \
        "EMAIL varchar(25) NOT NULL )) " + \
        "diststyle all;"
        sql_statements['SELECT'] = "SELECT email from public.email;"
        logger.info("Running sql queries \n")
        for command, query in sql_statements.items():
            logging.info("Example of {} command :".format(command))
            res[command + " STATUS: "] = execute_sql_data_api(redshift_data_api_client, 
                                                              redshift_database_name, 
                                                              command, 
                                                              query,
                                                              redshift_workgroup_name,
                                                              False )
    
  except Exception as ex:
    statusCode = 400
    raise Exception(str(ex) + "\n" + traceback.format_exc())

  return res

def execute_sql_data_api(redshift_data_api_client, redshift_database_name, command, query, redshift_workgroup_name, isSynchronous):
    logger.info("execute_sql_data_api: START \n")
    MAX_WAIT_CYCLES = 20
    attempts = 0
    # Calling Redshift Data API with executeStatement()
    logger.info("execute_sql_data_api: before execute_statement \n")
    res = redshift_data_api_client.execute_statement(
        Database=redshift_database_name, 
        WorkgroupName=redshift_workgroup_name, 
        Sql=query)
    logger.info("execute_sql_data_api: after execute_statement \n")
    query_id = res["Id"]
    desc = redshift_data_api_client.describe_statement(Id=query_id)
    query_status = desc["Status"]
    logger.info( "Query status: {} .... for query-->{}".format(query_status, query))
    done = False

    # Wait until query is finished or max cycles limit has been reached.
    while not done and isSynchronous and attempts < MAX_WAIT_CYCLES:
        attempts += 1
        time.sleep(1)
        desc = redshift_data_api_client.describe_statement(Id=query_id)
        query_status = desc["Status"]

        if query_status == "FAILED":
            raise Exception('SQL query failed:' + query_id + ": " + desc["Error"])

        elif query_status == "FINISHED":
            logger.info("query status is: {} for query id: {} and command: {}".format(query_status, query_id, command))
            done = True
            # print result if there is a result (typically from Select statement)
            if desc['HasResultSet']:
                response = redshift_data_api_client.get_statement_result(Id=query_id)
                logger.info("Printing response of {} query --> {}".format(command, response['Records']))
        else:
            logger.info("Current working... query status is: {} ".format(query_status))

    # Timeout Precaution
    if done == False and attempts >= MAX_WAIT_CYCLES and isSynchronous:
        logger.info("Limit for MAX_WAIT_CYCLES has been reached before the query was able to finish. We have exited out of the while-loop. You may increase the limit accordingly. \n")
        raise Exception("query status is: {} for query id: {} and command: {}".format( query_status, query_id, command))

    logger.info("execute_sql_data_api: END \n")
    return query_status