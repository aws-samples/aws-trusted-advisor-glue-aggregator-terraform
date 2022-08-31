
# define who can assume this role
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = [var.admin_account_role_arn]
      type        = "AWS"
    }
  }
}

# define what this role allow to do
# allow to read trusted advisor info
data "aws_iam_policy_document" "inline_policy" {
  statement {
    actions   = ["support:DescribeTrustedAdvisorChecks", "support:DescribeTrustedAdvisorCheckResult"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "memberRole" {
  name               = var.member_account_role_name
  description        = "Member role allowed to get trusted advisor info"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = var.custom_tags

  inline_policy {
    name   = "AllowGetTrustedAdvisorInfoPolicy"
    policy = data.aws_iam_policy_document.inline_policy.json
  }
}


