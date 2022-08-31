resource "random_id" "new" {
  byte_length = 4
}


locals {
  name_prefix              = "${lower(random_id.new.id)}-"
  tags                     = {}
  lambda_alias_name        = "LIVE"
  admin_account_role_name  = "${local.name_prefix}AdminAccountRole"  # include path prefix without starting /
  member_account_role_name = "${local.name_prefix}MemberAccountRole" # include path prefix without starting /
}


module "reporting-admin-standalone" {
  source                             = "./modules/reporting-admin-module"
  name_prefix                        = local.name_prefix
  custom_tags                        = local.tags
  lambda_logs_level                  = "DEBUG"
  lambda_alias_name                  = local.lambda_alias_name
  lambda_logs_retention_days         = "1"
  data_ingestion_schedule_expression = "rate(3 days)"
  admin_account_role_name            = local.admin_account_role_name
  member_account_role_name           = local.member_account_role_name
}


module "reporting-member-standalone" {
  depends_on = [
    module.reporting-admin-standalone
  ]
  source                   = "./modules/reporting-member-single-module"
  custom_tags              = local.tags
  name_prefix              = local.name_prefix
  admin_account_role_arn   = module.reporting-admin-standalone.admin_role_arn
  member_account_role_name = local.member_account_role_name
}

output "admin_account_id" {
  value = module.reporting-admin-standalone.admin_account_id
}

output "admin_region" {
  value = module.reporting-admin-standalone.admin_region_name
}

output "admin_s3_arn" {
  value = module.reporting-admin-standalone.s3_arn
}

output "member_account_id" {
  value = module.reporting-member-standalone.account_id
}

output "member_region_name" {
  value = module.reporting-member-standalone.region_name
}

