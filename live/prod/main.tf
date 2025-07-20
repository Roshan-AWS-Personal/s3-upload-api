terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.35" # or 5.30, 5.27, etc.
    }
  }

  required_version = ">= 1.5.0"
}
resource "aws_s3_bucket" "image_upload_bucket" {
  bucket = "s3-image-upload-api-2712-prod"
  force_destroy = true

  tags = {
    Name = "image-upload-api-bucket"
  }
}

resource "aws_s3_bucket" "documents_bucket" {
  bucket = "s3-upload-documents"
  force_destroy = true
    tags = {
    Name = "document-upload-api-bucket"
  }
}

resource "aws_s3_bucket_cors_configuration" "upload_bucket_cors" {
  bucket = aws_s3_bucket.image_upload_bucket.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "GET"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_cors_configuration" "documents_bucket_cors" {
  bucket = aws_s3_bucket.documents_bucket.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "GET"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_versioning" "upload_bucket_versioning" {
  bucket = aws_s3_bucket.image_upload_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

