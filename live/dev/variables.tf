variable "aws_region" {
  type = string
}
variable "state_bucket" {
  type = string
}
variable "state_prefix" {
  type = string
}
variable "dynamodb_table" {
  type = string
}
variable "env" {
  type    = string
  default = "dev"
}

variable "upload_api_secret" {
  description = "The secret token used to authenticate API calls"
  type        = string
  sensitive   = true
}
variable "stage_name" {
  description = "The stage name for the API Gateway"
  type        = string
  default     = "dev"
}

variable "upload_api_url" {
  description = "URL for the API Gateway"
  type        = string
  default     = "dev"
}

variable "login_redirect_url" {
  description = "Frontend URL to redirect after successful login"
  type        = string
}

variable "logout_redirect_url" {
  description = "Frontend URL to redirect after logout"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

