variable "name_prefix" {
  description = "Prefix used in the name of all created resources"
  type        = string
}

variable "custom_tags" {
  description = "Tags applied to created resources"
  type        = map(string)
  default     = {}
}

variable "admin_account_role_arn" {
  description = "Role arn in admin accounts, that can be used to assume an elevated role in the member account (= var.member_account_role_name)"
  type        = string
}

variable "member_account_role_name" {
  description = "Role name in member accounts, that can be used to fetch information"
  type        = string
}