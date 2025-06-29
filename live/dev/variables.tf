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
  type      = string
  sensitive = true
}
