import os
import logging
from abc import ABC, abstractmethod
from functools import wraps
from time import time
import boto3
from botocore.exceptions import ClientError
import json
import datetime
from json import JSONEncoder

try:
    import liblogging
except ImportError:
    pass


# NB: changing an ENVIRONMENT VARIABLE value in the console affect only the $LATEST version, not the published version.
logger = logging.getLogger()
logger.setLevel(os.getenv("LOG_LEVEL", "INFO"))


class AbstractFetcher(ABC):

    logging.getLogger("boto3").setLevel(logging.WARNING)
    logging.getLogger("botocore").setLevel(logging.WARNING)


    def __init__(self):  
        self.s3_bucket_name = os.getenv("S3_BUCKET_NAME")
        self.s3_prefix_path = os.getenv("S3_PREFIX_PATH")
        logger.info(f"S3 target = {self.s3_bucket_name}/{self.s3_prefix_path}")        
        self.s3_client = self._new_client('s3')
    

    @staticmethod
    def log_method_time(f):
        @wraps(f)
        def wrapper(*args, **kwds):
            start = time()
            result = f(*args, **kwds)
            elapsed = time() - start
            logger.debug(f"{f.__name__} method took {elapsed: .3f} seconds")  
            return result
        return wrapper
 

    def _new_client(self, service, region=None, role1_arn=None, role2_arn = None,):
        """
        Credential start with current lambda execution role.
        Then if 'role1_arn' is defined it will chain-role assume it.
        Then if 'role2_arn' is defined it will chain-role assume it.
        """

        logger.debug(f"Creating new AWS API client for AWS service: {service}")
        try:

            if not role1_arn and not role2_arn:
                logger.debug(f"Not assumming another role, new client with current lambda execution role")
                aws_access_key_id = None
                aws_secret_access_key = None
                aws_session_token = None
            else: 

                sts_client_with_execution_role_credential = boto3.client('sts')
                sts_client = sts_client_with_execution_role_credential

                if role1_arn:
                    logger.debug(f"Assumming role 1: {role1_arn}")
                    assumedRoleObject = sts_client.assume_role(
                        RoleArn=role1_arn,
                        RoleSessionName="AssumeRole1"
                    )
                    credentials = assumedRoleObject['Credentials']
                    aws_access_key_id = credentials['AccessKeyId']
                    aws_secret_access_key = credentials['SecretAccessKey']
                    aws_session_token = credentials['SessionToken']

                    sts_client_with_role1_credential = boto3.client(
                        'sts',
                        aws_access_key_id=aws_access_key_id,
                        aws_secret_access_key=aws_secret_access_key,
                        aws_session_token=aws_session_token
                    )
                    sts_client = sts_client_with_role1_credential


                if role2_arn:
                    logger.debug(f"Assumming role 2: {role2_arn}")
                    assumedRoleObject = sts_client.assume_role(
                        RoleArn=role2_arn,
                        RoleSessionName="AssumeRole2"
                    )
                    credentials = assumedRoleObject['Credentials']
                    aws_access_key_id = credentials['AccessKeyId']
                    aws_secret_access_key = credentials['SecretAccessKey']
                    aws_session_token = credentials['SessionToken']
        

            client = boto3.client(
                service,
                aws_access_key_id=aws_access_key_id,
                aws_secret_access_key=aws_secret_access_key,
                aws_session_token=aws_session_token,
                region_name = region
            )
            return client 

        except ClientError as e:
            logging.error(f"Unexpected error when creating new AWS API client: {e}")
            return None



    def _put_to_s3(self, s3_bucket_name, s3_key, s3_value, s3_content_type):
        logger.info(f"Writing {len(s3_value)} bytes to S3 : {s3_bucket_name}/{s3_key}")
        response_dict = self.s3_client.put_object(
            Bucket = s3_bucket_name,
            Key = s3_key,
            Body = s3_value,
            ContentType = s3_content_type,
        )

        logger.debug(f"S3 put command output = {response_dict}")
        response_metadata = response_dict.get('ResponseMetadata') 
        http_status_code = response_metadata.get('HTTPStatusCode') 
        logger.info(f"S3 put HTTP response status = {http_status_code}")
        if http_status_code != 200:
            logger.error(f"Failed to put data in S3. Response was ({http_status_code}): {response_dict}")
        return response_dict


    def _format_json_output_data(self, array_of_objects): # array of python structs (dict, array, string) that can be converted to json
        # Mandatory for simple AWS Glue/Athena ingestion is:
        #  one distinct JSON string line per row
        #  no comma separator between rows and no enclosing array markers
        one_long_string = ''
        for entry in array_of_objects:
            json_string = json.dumps(entry, cls=DateTimeEncoder)
            one_long_string +=  json_string + "\n"
        return one_long_string


class DateTimeEncoder(JSONEncoder):
    # Override the default method
    def default(self, obj):
        if isinstance(obj, (datetime.date, datetime.datetime)):
            return obj.isoformat()