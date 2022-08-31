resource "aws_athena_workgroup" "query_workgroup" {
  name          = "${var.name_prefix}reporting-workgroup"
  description   = "process named query"
  force_destroy = true
  tags          = var.custom_tags

  configuration {
    enforce_workgroup_configuration = false
    result_configuration {
      output_location = "s3://${module.reporting_bucket.s3_id}/queries_output/"
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }
}



resource "aws_athena_named_query" "query_trusted_advisor_issues" {
  name        = "${var.name_prefix}reporting.trusted_advisor_issues"
  description = "trusted advisor entries that require investigations or remediations"
  database    = aws_glue_catalog_database.reporting_database.name
  workgroup   = aws_athena_workgroup.query_workgroup.id
  query       = <<-EOT
    SELECT 
        account_id,
        category,
        name,
        result.status,
        result.resourcesSummary.resourcesFlagged,
        result.timestamp,
        description 

    FROM "dev_reporting"."trusted_advisor_checks" 
    WHERE result.status NOT IN ('ok', 'not_available')
    order BY result.status, category, result.resourcesSummary.resourcesFlagged desc
    LIMIT 100;
  EOT
}

