data "aws_caller_identity" "current" {}
data "aws_region" "current" {}


locals {

  admin_account_id  = data.aws_caller_identity.current.account_id
  admin_region_name = data.aws_region.current.name

  s3_raw_ingestion_path_ta = "data/trusted-advisor/json/" # if not empty must end with "/"    

  functions_src_path = "${path.module}/src/lambda/functions"
  layers_src_path    = "${path.module}/src/lambda/layers"

}

