resource "aws_dynamodb_table" "file_upload_metadata" {
  name         = "file_upload_metadata"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "upload_id"

  attribute {
    name = "upload_id"
    type = "S"
  }

  # Add the attribute you plan to query on
  attribute {
    name = "username"
    type = "S"
  }

  # Define the GSI so you can KeyConditionExpression on username
  global_secondary_index {
    name               = "username-index"
    hash_key           = "username"
    projection_type    = "ALL"
    # No need for read/write capacity under PAY_PER_REQUEST
  }

  tags = {
    Project     = "S3 Upload API"
    Environment = var.env
  }
}
