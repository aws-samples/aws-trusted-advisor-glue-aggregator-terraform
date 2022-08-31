# define who can assume this role
data "aws_iam_policy_document" "ta_lambda_role_trust_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = [
        "lambda.amazonaws.com",
      ]
    }
  }
}

# define what this role allow to do
data "aws_iam_policy_document" "ta_lambda_role_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
    ]
    resources = [
      "${module.reporting_bucket.s3_arn}/${local.s3_raw_ingestion_path_ta}*"
    ]
  }
  statement {
    # allow this role to assume admin-accounts role
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    resources = [
      "arn:aws:iam::${local.admin_account_id}:role/${var.admin_account_role_name}"
    ]
  }
}

resource "aws_iam_role" "ta_lambda_execution_role" {
  name               = "${var.name_prefix}reporting-ta-lambda-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ta_lambda_role_trust_policy.json
  inline_policy {
    name   = "AllowWriteToS3AndConnectToMemberAccount"
    policy = data.aws_iam_policy_document.ta_lambda_role_policy.json
  }
  tags = var.custom_tags
}


# define what this role allow to do
resource "aws_iam_role_policy_attachment" "ta_lambda_role_managed_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",    # write logs to CLoudWatch Logs
    "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess",                    # upload traces to XRay
    "arn:aws:iam::aws:policy/CloudWatchLambdaInsightsExecutionRolePolicy", # Permission to write runtime metrics to CloudWatch Lambda Insights
    "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"  # Allow to read SQS queue (and be invoked)
  ])
  role       = aws_iam_role.ta_lambda_execution_role.name
  policy_arn = each.key
}


data "archive_file" "ta_lambda_function_zip" {
  type        = "zip"
  source_dir  = "${local.functions_src_path}/fetch_trusted_advisor/"
  output_path = "${local.functions_src_path}/fetch_trusted_advisor.zip"
}


resource "aws_lambda_function" "ta_lambda_function" {
  depends_on       = [data.archive_file.ta_lambda_function_zip, aws_lambda_layer_version.lambda_layer_common, aws_iam_role.ta_lambda_execution_role, aws_sqs_queue.ta_accounts_to_process_queue]
  function_name    = "${var.name_prefix}reporting-fetch-trusted-advisor"
  description      = "Retrieve Trusted Advisor checks of a member account and store it in S3 Bucket"
  filename         = data.archive_file.ta_lambda_function_zip.output_path
  source_code_hash = data.archive_file.ta_lambda_function_zip.output_base64sha256
  layers           = [aws_lambda_layer_version.lambda_layer_common.arn]
  role             = aws_iam_role.ta_lambda_execution_role.arn
  handler          = "fetch_trusted_advisor.lambda_handler"
  publish          = true
  runtime          = "python3.9"
  architectures    = ["arm64"] # ARM graviton 2 instead of intel      
  timeout          = 240       # seconds
  tracing_config {
    mode = "Active"
  }
  environment {
    variables = {
      LOG_LEVEL               = var.lambda_logs_level,
      S3_BUCKET_NAME          = module.reporting_bucket.s3_id,
      S3_PREFIX_PATH          = local.s3_raw_ingestion_path_ta,
      ASSUME_ROLE_ADMIN_NAME  = var.admin_account_role_name
      ASSUME_ROLE_MEMBER_NAME = var.member_account_role_name
    }
  }
  tags = var.custom_tags
}

resource "aws_lambda_alias" "ta_lambda_alias_live" {
  depends_on       = [aws_lambda_function.ta_lambda_function]
  name             = var.lambda_alias_name
  description      = "Live Alias for Lambda function"
  function_name    = aws_lambda_function.ta_lambda_function.arn
  function_version = aws_lambda_function.ta_lambda_function.version
}


resource "aws_cloudwatch_log_group" "ta_lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.ta_lambda_function.function_name}"
  retention_in_days = var.lambda_logs_retention_days
  tags              = var.custom_tags
}



resource "aws_sqs_queue" "ta_accounts_to_process_queue" {
  name                       = "${var.name_prefix}reporting-input-accounts-queue"
  sqs_managed_sse_enabled    = true
  visibility_timeout_seconds = 10 * 60
  tags                       = var.custom_tags
}


resource "aws_lambda_event_source_mapping" "ta_sqs_to_lambda" {
  event_source_arn = aws_sqs_queue.ta_accounts_to_process_queue.arn
  function_name    = aws_lambda_function.ta_lambda_function.arn
}