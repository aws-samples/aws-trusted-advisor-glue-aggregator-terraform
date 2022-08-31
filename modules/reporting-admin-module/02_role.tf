
# define who can assume this role
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = [aws_iam_role.ta_lambda_execution_role.arn]
      type        = "AWS"
    }
  }
}

# define what this role allow to do
# allow to assume member-accounts role
data "aws_iam_policy_document" "inline_policy" {
  statement {
    actions   = ["sts:AssumeRole"]
    resources = ["arn:aws:iam::*:role/${var.member_account_role_name}"]
  }
}

resource "aws_iam_role" "adminRole" {
  name               = var.admin_account_role_name
  description        = "Admin role allowed to assume role on Organization Unit Member accounts"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = var.custom_tags

  inline_policy {
    name   = "AllowAssumeMemberRolePolicy"
    policy = data.aws_iam_policy_document.inline_policy.json
  }
}

