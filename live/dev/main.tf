terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
    docker = { source = "kreuzwerker/docker" }
  }
}

provider "aws" {}

data "aws_ecr_authorization_token" "ecr" {}

locals {
  ecr_address = replace(data.aws_ecr_authorization_token.ecr.proxy_endpoint, "https://", "")
}

provider "docker" {
  registry_auth {
    address  = local.ecr_address
    username = data.aws_ecr_authorization_token.ecr.user_name
    password = data.aws_ecr_authorization_token.ecr.password
  }
}
resource "aws_s3_bucket" "image_upload_bucket" {
  bucket = "s3-image-upload-api-2712"
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

data "aws_iam_policy_document" "s3_to_sqs" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.ingest_queue.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.documents_bucket.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "allow_s3" {
  queue_url = aws_sqs_queue.ingest_queue.id
  policy    = data.aws_iam_policy_document.s3_to_sqs.json
}

resource "aws_s3_bucket_notification" "documents_notifications" {
  bucket = aws_s3_bucket.documents_bucket.id

  # S3 -> SQS (for ingest pipeline)
  queue {
    queue_arn     = aws_sqs_queue.ingest_queue.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "docs/"   # only docs/ trigger ingest
  }

  # S3 -> logger Lambda (keep your existing logger, optional)
  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_event_logger.arn
    events              = ["s3:ObjectCreated:Put"]
    filter_prefix       = ""  # or "docs/" if you only want docs/
  }

  depends_on = [
    aws_sqs_queue_policy.allow_s3,
    aws_lambda_permission.allow_s3_trigger_documents
  ]
}
