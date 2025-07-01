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
  bucket = "s3-image-upload-api-2712"
  force_destroy = true

  tags = {
    Name = "image-upload-api-bucket"
  }
}

resource "aws_s3_bucket_versioning" "upload_bucket_versioning" {
  bucket = aws_s3_bucket.image_upload_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# IAM Role that Lambda will assume
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_s3_upload_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Principal = {
        Service = "lambda.amazonaws.com"
      },
      Effect = "Allow",
      Sid    = ""
    }]
  })
}

# IAM Policy to allow Lambda to write to S3
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name   = "lambda-s3-upload-policy"
  role   = aws_iam_role.lambda_exec_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject"
        ],
        Resource = "${aws_s3_bucket.image_upload_bucket.arn}/*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "image_uploader" {
  function_name = "image-uploader-dev"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  role    = aws_iam_role.lambda_exec_role.arn
  handler = "handler.lambda_handler"
  runtime = "python3.11"

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.image_upload_bucket.bucket
      UPLOAD_API_SECRET = "gW75T+AcsXW4LLPMhup9Rv944JZ64EA9D6te5b/RxDI="
    }
  }

  depends_on = [aws_iam_role_policy.lambda_s3_policy]
}
