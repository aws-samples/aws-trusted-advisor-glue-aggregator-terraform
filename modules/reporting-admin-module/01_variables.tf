variable "name_prefix" {
  description = "Prefix used in the name of all created resources"
  type        = string
}

variable "custom_tags" {
  description = "Tags applied to created resources"
  type        = map(string)
  default     = {}
}

variable "lambda_logs_level" {
  type        = string
  description = "Lambda function Logs verbosity level (CRITICAL, ERROR, WARNING, INFO, DEBUG)"
  default     = "INFO"
}

variable "lambda_logs_retention_days" {
  type        = string
  description = "Lambda Logs Retention in Days"
  default     = "14"
}

variable "lambda_alias_name" {
  description = "Lambda function alias name, used by AWS Config custom rule"
  type        = string
}

variable "data_ingestion_schedule_expression" {
  description = "For the non-events-driven data ingestion, define schedule to trigger ingestion process. See: https://docs.aws.amazon.com/AmazonCloudWatch/latest/events/ScheduledEvents.html"
  type        = string
}

variable "admin_account_role_name" {
  description = "Role name in admin accounts, that can be used to assume an elevated role in the member account (= var.member_account_role_name)"
  type        = string
}

variable "member_account_role_name" {
  description = "Role name in member accounts, that can be used to fetch information"
  type        = string
}


