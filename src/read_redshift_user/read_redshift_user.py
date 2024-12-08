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
#        sql_statements['CREATE_SCHEMA'] = "CREATE SCHEMA IF NOT EXISTS kj ;" 
#        sql_statements['CREATE_SCHEMA'] = "CREATE ROLE kj ;" 
##        sql_statements['CREATE_TABLE'] = "CREATE TABLE IF NOT EXISTS public.kj_email ( EMAIL varchar(25) NOT NULL ) ;" 
##        sql_statements['INSERT'] = "INSERT INTO public.kj_email(email) VALUES ('kjkj2@kj2.com');"
#        sql_statements['SELECT'] = "SELECT * FROM public.kj_email;"
##        logger.info("Running sql queries \n")
##        for command, query in sql_statements.items():
##            logging.info("Example of {} command :".format(command))
##            res[command + " STATUS: "] = execute_sql_data_api(redshift_data_api_client, 
##                                                              redshift_database_name, 
##                                                              command, 
##                                                              query,
##                                                              redshift_workgroup_name,
##                                                              True )

        create_table( redshift_data_api_client, redshift_database_name, redshift_workgroup_name )

        tables = list_tables( redshift_data_api_client, redshift_database_name, redshift_workgroup_name )
        logger.info("List of Tables:")
        for table in tables:
            logger.info (table)

        insert_into_table( redshift_data_api_client, redshift_database_name, redshift_workgroup_name )

        select_from_table( redshift_data_api_client, redshift_database_name, redshift_workgroup_name )

    logging.error("PRINT Result")
    logging.error("Result: {}:".format(res))

    result = {
        "statusCode": statusCode,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": "SUCCESS"
    }

  except BaseException as ex:
    logging.error("ERROR: {}:".format(ex))
    statusCode = 400
    logging.error(str(ex) + "\n" + traceback.format_exc())
    result = {
        "statusCode": statusCode,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": "ERROR"
    }

  return result

def execute_sql_data_api(redshift_data_api_client, redshift_database_name, command, query, redshift_workgroup_name, isSynchronous):
    MAX_WAIT_CYCLES = 20
    attempts = 0
    # Calling Redshift Data API with executeStatement()
    logger.info("====================")
    query_status = "UNKNOWN"
    try:
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
            logger.info( "attempts {}".format( attempts) )
            attempts += 1
            time.sleep(1)
            desc = redshift_data_api_client.describe_statement(Id=query_id)
            query_status = desc["Status"]
            logger.info("status: {}".format(query_status))
            logger.info("status: {} ---desc: {}".format(query_status, desc))

            if query_status == "FAILED":
                logger.error( 'SQL query failed:' + desc["Error"])
                raise Exception('SQL query failed:' + query_id + ": " + desc["Error"])

            elif query_status == "FINISHED":
                logger.info("query status is: {} for query id: {} and command: {}".format(query_status, query_id, command))
                done = True
                # print result if there is a result (typically from Select statement)
                logger.info("result")
                if desc['HasResultSet']:
                    response = redshift_data_api_client.get_statement_result(Id=query_id)
                    logger.info("Printing response of {} query --> {}".format(command, response['Records']))
            else:
                logger.info("Current working... query status is: {} ".format(query_status))

        # Timeout Precaution
        if done == False and attempts >= MAX_WAIT_CYCLES and isSynchronous:
            logger.info("Limit for MAX_WAIT_CYCLES has been reached before the query was able to finish. We have exited out of the while-loop. You may increase the limit accordingly. \n")
            raise Exception("query status is: {} for query id: {} and command: {}".format( query_status, query_id, command))

    except (ActiveSessionsExceededException, ActiveStatementsExceededException,  ExecuteStatementException,  InternalServerException,  ValidationException )  as ex:
        logging.error("ERROR: {}:".format(ex))    

    except BaseException  as ex:
        logging.error("ERROR: {}:".format(ex))

    return query_status

def list_tables( redshift_data_api_client, redshift_database_name, redshift_workgroup_name ):
    logger.info("------------- list_tables --------------")
    response = redshift_data_api_client.list_tables(
        Database=redshift_database_name, 
        WorkgroupName=redshift_workgroup_name, 
        MaxResults=100,
        TablePattern="kj%"
    )
    return response['Tables']

def create_table( redshift_data_api_client, redshift_database_name, redshift_workgroup_name ):
    logger.info("------------- create_table --------------")
    res = redshift_data_api_client.execute_statement(
        Database=redshift_database_name, 
        WorkgroupName=redshift_workgroup_name, 
        Sql="CREATE TABLE IF NOT EXISTS public.kj_email ( EMAIL varchar(25) NOT NULL )")
    
    query_id = res["Id"]
    desc = redshift_data_api_client.describe_statement(Id=query_id)
    query_status = desc["Status"]
    logger.info( "Query status: {}".format(query_status))

def insert_into_table( redshift_data_api_client, redshift_database_name, redshift_workgroup_name ):
    logger.info("------------- insert_into_table --------------")
    res = redshift_data_api_client.execute_statement(
        Database=redshift_database_name, 
        WorkgroupName=redshift_workgroup_name, 
        Sql="INSERT INTO public.kj_email( EMAIL ) VALUES ('kjkj2@kj2.com'")
    
    query_id = res["Id"]
    desc = redshift_data_api_client.describe_statement(Id=query_id)
    query_status = desc["Status"]
    logger.info( "Query status: {}".format(query_status))
    logger.info( "Query result: {}".format(  res ))

def select_from_table( redshift_data_api_client, redshift_database_name, redshift_workgroup_name ):
    logger.info("------------- select_from_table --------------")
    res = redshift_data_api_client.execute_statement(
        Database=redshift_database_name, 
        WorkgroupName=redshift_workgroup_name, 
        Sql="SELECT * FROM public.kj_email")
    
    query_id = res["Id"]
    desc = redshift_data_api_client.describe_statement(Id=query_id)
    query_status = desc["Status"]
    logger.info( "Query status: {}".format(query_status))
    logger.info( "Query result: {}".format(  res ))

    MAX_WAIT_CYCLES = 20
    attempts = 0
    done = False
    while not done and attempts < MAX_WAIT_CYCLES:
        attempts += 1
        time.sleep(1)
        desc = redshift_data_api_client.describe_statement(Id=query_id)
        query_status = desc["Status"]
        if query_status == "FAILED":
            done = True
            logger.error( 'SQL query failed:' + desc["Error"])
        elif query_status == "FINISHED":
            logger.info("query status is: {} for query id: {}".format(query_status, query_id ))
            done = True
            logger.info("result")
            if desc['HasResultSet']:
                response = redshift_data_api_client.get_statement_result(Id=query_id)
                logger.info("Printing response of query --> {}".format( response['Records']))
        else:
            logger.info("Current working... query status is: {} ".format(query_status))