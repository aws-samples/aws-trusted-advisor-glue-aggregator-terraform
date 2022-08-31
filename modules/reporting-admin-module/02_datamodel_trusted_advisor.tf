resource "aws_glue_catalog_table" "trusted_advisor_checks_table" {
  name          = lower(replace("trusted_advisor_checks", "-", "_"))
  description   = "Trusted Advisor checks and checks results"
  database_name = aws_glue_catalog_database.reporting_database.name

  storage_descriptor {
    location      = "s3://${module.reporting_bucket.s3_id}/${local.s3_raw_ingestion_path_ta}"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "accounts_metadata-ser-stream"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "account_id"
      type = "string"
    }

    columns {
      name = "id"
      type = "string"
    }

    columns {
      name = "category"
      type = "string"
    }

    columns {
      name = "name"
      type = "string"
    }

    columns {
      name = "description"
      type = "string"
    }

    columns {
      name = "metadata"
      type = "string"
    }

    columns {
      name = "result"
      type = "struct<checkid:string,timestamp:string,status:string,resourcessummary:struct<resourcesprocessed:int,resourcesflagged:int,resourcesignored:int,resourcessuppressed:int>,categoryspecificsummary:string,flaggedresources:array<struct<status:string,region:string,resourceid:string,issuppressed:boolean,metadata:array<string>>>>"
    }

  }
}

