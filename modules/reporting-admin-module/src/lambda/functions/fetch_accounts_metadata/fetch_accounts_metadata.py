import os
import logging
from botocore.exceptions import ClientError
from abstract_fetcher import AbstractFetcher


logger = logging.getLogger()
logger.setLevel(os.getenv("LOG_LEVEL", "INFO")) # NB: changing an ENVIRONMENT VARIABLE value in the console affect only the $LATEST version, not the published version.


def lambda_handler(event, context):
    logger.info(f"Executing Lambda Function version {context.function_version}, invoked via '{context.invoked_function_arn}'")
    logger.debug(f"event = {event}")
    logger.debug(f"context = {context}")
    FetchAccountsMetadata().process_event(event, context)


class FetchAccountsMetadata(AbstractFetcher):


    SQS_SEND_BATCH_SIZE = 10


    @AbstractFetcher.log_method_time
    def __init__(self):
        super().__init__()   
        self.ta_sqs_url = os.getenv("FETCH_TRUSTED_ADVISOR_ACCOUNTS_QUEUE_URL")
        if self.ta_sqs_url:
            self.sqs_client = self._new_client('sqs')

    @AbstractFetcher.log_method_time
    def process_event(self, event, context):

        accounts = []

        # TODO: add logic to fetch dynamicaly  the list of accounts in scope ...
        # BTW, here is also good place to save these accounts organisational metadata (owner, cost center, contact, etc.) into the data S3 bucket (to have even more data to analyse and join in the queries)
        # for this educative article we will just hardcode few accounts
        accounts.append('123456789012')
        accounts.append('111222333444')
        

        self._register_all_account_for_trust_advisor_checks_extract(accounts)



    @AbstractFetcher.log_method_time
    def _register_all_account_for_trust_advisor_checks_extract(self, accounts):
        if not self.ta_sqs_url:
            logger.debug("Skipping sending accounts list to SQS for Trusted Advisor checks extraction")
            return    
        logger.info(f"Sending accounts list for Trusted Advisor checks extraction to SQS: {self.ta_sqs_url}")


        batched_entries = []
        count_total_sent_message = 0
        for account_id in accounts:

            entry =  {
                'Id': 'id-%s' % str(account_id),
                'MessageBody': str(account_id)
                }
            batched_entries.append(entry)            

            if len(batched_entries) >= FetchAccountsMetadata.SQS_SEND_BATCH_SIZE:
                self._rsend_sqs_message_for_trust_advisor_checks_extract(batched_entries)
                count_total_sent_message += len(batched_entries)
                batched_entries = []

        if batched_entries:
            # send last batch even if not full (=not at max batch size)
            self._rsend_sqs_message_for_trust_advisor_checks_extract(batched_entries)
            count_total_sent_message += len(batched_entries)
            batched_entries = []

        logger.debug(f"count_total_sent_message = {count_total_sent_message}")


    def _rsend_sqs_message_for_trust_advisor_checks_extract(self, batched_entries):
        send_message_batch_response = self.sqs_client.send_message_batch(QueueUrl=self.ta_sqs_url, Entries=batched_entries)
        array_failed_sent_entries = send_message_batch_response.get("Failed")
        if array_failed_sent_entries:
            logger.error(f"Failed to send some messages to SQS ({self.ta_sqs_url}) = {send_message_batch_response}")
        else:
            #logger.debug(f"send_message_batch_response = {send_message_batch_response}")
            pass

