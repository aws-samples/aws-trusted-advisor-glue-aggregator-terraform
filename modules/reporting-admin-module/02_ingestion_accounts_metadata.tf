# define who can assume this role
data "aws_iam_policy_document" "acc_meta_lambda_role_trust_policy" {
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
data "aws_iam_policy_document" "acc_meta_lambda_role_policy" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:SendMessage"
    ]
    resources = [
      aws_sqs_queue.ta_accounts_to_process_queue.arn,
    ]
  }
}

resource "aws_iam_role" "acc_meta_lambda_execution_role" {
  name               = "${var.name_prefix}reporting-acc-meta-lambda-exec-role"
  assume_role_policy = data.aws_iam_policy_document.acc_meta_lambda_role_trust_policy.json
  inline_policy {
    name   = "AllowPutAccountInSQS"
    policy = data.aws_iam_policy_document.acc_meta_lambda_role_policy.json
  }
  tags = var.custom_tags
}


# define what this role allow to do
resource "aws_iam_role_policy_attachment" "acc_meta_lambda_role_managed_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",   # write logs to CLoudWatch Logs
    "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess",                   # upload traces to XRay
    "arn:aws:iam::aws:policy/CloudWatchLambdaInsightsExecutionRolePolicy" # Permission to write runtime metrics to CloudWatch Lambda Insights.
  ])
  role       = aws_iam_role.acc_meta_lambda_execution_role.name
  policy_arn = each.key
}


data "archive_file" "acc_meta_lambda_function_zip" {
  type        = "zip"
  source_dir  = "${local.functions_src_path}/fetch_accounts_metadata/"
  output_path = "${local.functions_src_path}/fetch_accounts_metadata.zip"
}


resource "aws_lambda_function" "acc_meta_lambda_function" {
  depends_on       = [data.archive_file.acc_meta_lambda_function_zip, aws_lambda_layer_version.lambda_layer_common, aws_iam_role.acc_meta_lambda_execution_role, aws_sqs_queue.ta_accounts_to_process_queue]
  function_name    = "${var.name_prefix}reporting-fetch-accounts-metadata"
  description      = "Retrieve list of AWS accounts"
  filename         = data.archive_file.acc_meta_lambda_function_zip.output_path
  source_code_hash = data.archive_file.acc_meta_lambda_function_zip.output_base64sha256
  layers           = [aws_lambda_layer_version.lambda_layer_common.arn]
  role             = aws_iam_role.acc_meta_lambda_execution_role.arn
  handler          = "fetch_accounts_metadata.lambda_handler"
  publish          = true
  runtime          = "python3.9"
  architectures    = ["arm64"] # ARM graviton 2 instead of intel
  timeout          = 180       # seconds
  tracing_config {
    mode = "Active"
  }
  environment {
    variables = {
      LOG_LEVEL                                = var.lambda_logs_level,
      FETCH_TRUSTED_ADVISOR_ACCOUNTS_QUEUE_URL = aws_sqs_queue.ta_accounts_to_process_queue.url
    }
  }
  tags = var.custom_tags
}

resource "aws_lambda_alias" "acc_meta_lambda_alias_live" {
  depends_on       = [aws_lambda_function.acc_meta_lambda_function]
  name             = var.lambda_alias_name
  description      = "Live Alias for Lambda function"
  function_name    = aws_lambda_function.acc_meta_lambda_function.arn
  function_version = aws_lambda_function.acc_meta_lambda_function.version
}


resource "aws_cloudwatch_log_group" "acc_meta_lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.acc_meta_lambda_function.function_name}"
  retention_in_days = var.lambda_logs_retention_days
  tags              = var.custom_tags
}


resource "aws_cloudwatch_event_rule" "acc_meta_scheduled_event_generator" {
  name                = "${var.name_prefix}reporting-refresh-data-required-event"
  description         = "Fires when need to refresh data, based on schedule plan"
  schedule_expression = var.data_ingestion_schedule_expression
  tags                = var.custom_tags
}

resource "aws_cloudwatch_event_target" "acc_meta_react_to_scheduled_event" {
  rule = aws_cloudwatch_event_rule.acc_meta_scheduled_event_generator.name
  arn  = aws_lambda_alias.acc_meta_lambda_alias_live.arn
}

# Allow Event-Bridge (scheduler) to invoke the Lambda function
resource "aws_lambda_permission" "acc_meta_allow_scheduled_event_to_invoke_lambda" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.acc_meta_lambda_function.function_name
  qualifier     = aws_lambda_alias.acc_meta_lambda_alias_live.name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.acc_meta_scheduled_event_generator.arn
}

