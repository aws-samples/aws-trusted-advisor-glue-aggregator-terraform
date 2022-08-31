data "archive_file" "lambda_layer_common_zip" {
  type        = "zip"
  source_dir  = "${local.layers_src_path}/common"
  output_path = "${local.layers_src_path}/layer_common.zip"
}

resource "aws_lambda_layer_version" "lambda_layer_common" {
  filename                 = data.archive_file.lambda_layer_common_zip.output_path
  description              = "Reusable code for ingestion of data"
  layer_name               = "${var.name_prefix}reporting-common"
  compatible_runtimes      = ["python3.8", "python3.9"]
  source_code_hash         = data.archive_file.lambda_layer_common_zip.output_base64sha256
  compatible_architectures = ["arm64", "x86_64"] # add ARM graviton2 to default intel x86
}

