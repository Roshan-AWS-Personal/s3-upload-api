resource "aws_dynamodb_table" "file_upload_metadata" {
  name         = "file_upload_metadata"
  billing_mode = "PAY_PER_REQUEST"  # On-demand, no need to manage throughput
  hash_key     = "upload_id"

  attribute {
    name = "upload_id"
    type = "S"
  }

  tags = {
    Project     = "S3 Upload API"
    Environment = var.env
  }
}
