import os
import logging

from abstract_fetcher import AbstractFetcher
import concurrent.futures


logger = logging.getLogger()
logger.setLevel(os.getenv("LOG_LEVEL", "INFO")) # NB: changing an ENVIRONMENT VARIABLE value in the console affect only the $LATEST version, not the published version.


def lambda_handler(event, context):
    logger.info(f"Executing Lambda Function version {context.function_version}, invoked via '{context.invoked_function_arn}'")
    logger.debug(f"event = {event}")
    logger.debug(f"context = {context}")
    FetchTrustedAdvisorEntries().process_event(event, context)



class FetchTrustedAdvisorEntries(AbstractFetcher):


    S3_FILENAME_PREFIX = 'trusted_advisor_checks'
    S3_FILENAME_SUFFIX = '.json'
    MAX_WORKERS_THREAD = None # above ~5 does not improve anymore

    @AbstractFetcher.log_method_time
    def __init__(self):
        super().__init__()  
        self.admin_role_name = os.getenv('ASSUME_ROLE_ADMIN_NAME')
        self.member_role_name = os.getenv('ASSUME_ROLE_MEMBER_NAME')  



    @AbstractFetcher.log_method_time
    def process_event(self, event, context):

        current_account_id = context.invoked_function_arn.split(":")[4]

        # one lambda function execution receive and process a batch of multiple SQS entries.
        for record in event['Records']:
            payload = record["body"]

            member_account_id = payload

            # fetch data for one account
            array_of_checks = self._get_trusted_advisor_data(member_account_id, current_account_id)
            if array_of_checks:
                self._put_checks_to_s3(array_of_checks, member_account_id)


    def _get_trusted_advisor_data(self, member_account_id, current_account_id):

        logger.info(f"Getting Trusted Advisor checks for account: {member_account_id}")

        admin_role_arn = f"arn:aws:iam::{current_account_id}:role/{self.admin_role_name}" # assumption: this lambda run in the OU admin account
        member_role_arn = f"arn:aws:iam::{member_account_id}:role/{self.member_role_name}"
        support_client = self._new_client("support", "us-east-1", admin_role_arn, member_role_arn) # trusted advisor is a global service, AWS recommend to access via us-east-1
        
        checks = self._get_checks(support_client)
        array_of_checks_output = self._get_all_checks_results(checks, member_account_id, support_client)
        if not array_of_checks_output:
            logger.error(f"Failed to extract Trusted Advisor checks for account: {member_account_id}")

        return array_of_checks_output    


    @AbstractFetcher.log_method_time   
    def _get_checks(self, support_client):
        describe_trusted_advisor_checks_response = support_client.describe_trusted_advisor_checks(language="en")
        #logger.debug(f"describe_trusted_advisor_checks command output = {checks_response}")
        response_metadata = describe_trusted_advisor_checks_response.get('ResponseMetadata') 
        http_status_code = response_metadata.get('HTTPStatusCode') 
        logger.debug(f"describe_trusted_advisor_checks response status = {http_status_code}")
        if http_status_code != 200:
            logger.error(f"Failed to get list of all Trusted Advisor checks. Response was ({http_status_code}): {describe_trusted_advisor_checks_response}")
            return []

        checks = describe_trusted_advisor_checks_response.get("checks")
        logger.info(f"Received data for {len(checks)} checks")
        return checks


    @AbstractFetcher.log_method_time   
    def _get_all_checks_results(self, checks, member_account_id, support_client):
        """
          Boto3 client use multiple threads to isolate API calls, but all is syncronised in the single main thread to avoid concurency issue. So apparent behavior is single-threaded execution.
          Boto3 client methods are blocking, so not releasing (=yield) the current thread. But IO access are releasing the thread.
          So the strategy is to execute IO intensive task in multiple threads in parallelle.
          The number of CPU cores allocated to Lambda execution depend of the memory allocated. Below ~2 GB it is single core.
          Considered python libs: 
           asyncio: but would not benefit of having multi CPU core access, but is faster as it does not instanciate new threads resources.
        """   
        array_of_checks_output = []
        with concurrent.futures.ThreadPoolExecutor(max_workers=FetchTrustedAdvisorEntries.MAX_WORKERS_THREAD) as executor:
            futures_to_check = {executor.submit(self._get_check_result, support_client, check.get("id")): check for check in checks}
            for future in concurrent.futures.as_completed(futures_to_check):
                check = futures_to_check[future]
                try:
                    check_output = check
                    check_output["account_id"] = member_account_id
                    check_result = future.result()
                    check_output["result"] = check_result
                    logger.debug(f"Completed check {check.get('id')}")
                    array_of_checks_output.append(check_output)
                except Exception as e:
                    logging.error(f"Exception = {e}" )

        return array_of_checks_output



    @AbstractFetcher.log_method_time   
    def _get_check_result(self, support_client, check_id):
        describe_trusted_advisor_check_result_response = support_client.describe_trusted_advisor_check_result(checkId=check_id, language="en")
        response_metadata = describe_trusted_advisor_check_result_response.get('ResponseMetadata') 
        http_status_code = response_metadata.get('HTTPStatusCode') 
        logger.debug(f"describe_trusted_advisor_check_result response status = {http_status_code}")
        if http_status_code != 200:
            logger.error(f"Failed to get check result. Response was ({http_status_code}): {describe_trusted_advisor_check_result_response}")
            check_result = {}
        else:    
            check_result = describe_trusted_advisor_check_result_response.get("result")
        logger.debug(f"check_result={check_result}")             
        return check_result


    @AbstractFetcher.log_method_time
    def _put_checks_to_s3(self, array_of_checks, account_id):
        logger.info(f"Writing {len(array_of_checks)} Trusted Advisor checks to S3")
        s3_key= self.s3_prefix_path + FetchTrustedAdvisorEntries.S3_FILENAME_PREFIX + "_" + account_id + FetchTrustedAdvisorEntries.S3_FILENAME_SUFFIX
        payload_string = self._format_json_output_data(array_of_checks)
        payload_bytes = payload_string.encode('UTF-8')   
        s3_value = payload_bytes
        output = self._put_to_s3(self.s3_bucket_name, s3_key, s3_value, 'application/json')        
        return output


