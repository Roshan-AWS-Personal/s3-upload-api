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
  default = "prod"
}

variable "upload_api_secret" {
  description = "The secret token used to authenticate API calls"
  type        = string
  sensitive   = true
}
variable "stage_name" {
  description = "The stage name for the API Gateway"
  type        = string
  default     = "prod"
}

variable "upload_api_url" {
  description = "URL for the API Gateway"
  type        = string
  default     = "prod"
}

variable "login_redirect_url" {
  description = "Frontend URL to redirect after successful login"
  type        = string
}

variable "logout_redirect_url" {
  description = "Frontend URL to redirect after logout"
  type        = string
}

variable "list_api_url" {
  description = "List URL for the API Gateway"
  type        = string
  default     = "dev"
}

variable "redirect_uri_list" {
  description = "URL for the list API Gateway"
  type        = string  
}

variable "cognito_domain" {
  description = "Cognito Hosted UI domain"
  type        = string
}

variable "cognito_client_id" {
  description = "Cognito App Client ID"
  type        = string
}

