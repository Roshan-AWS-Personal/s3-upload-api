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


resource "aws_s3_bucket_versioning" "upload_bucket_versioning" {
  bucket = aws_s3_bucket.image_upload_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# IAM Role that Lambda will assume
resource "aws_iam_role" "image_uploader_lambda_exec_role" {
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

resource "aws_iam_role_policy" "dynamodb_write_policy" {
  name        = "LambdaDynamoDBWritePolicy"
  role       = aws_iam_role.image_uploader_lambda_exec_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "dynamodb:PutItem"
        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.file_upload_metadata.arn
      }
    ]
  })
}
# IAM Policy to allow Lambda to write to S3
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name   = "lambda-s3-upload-policy"
  role   = aws_iam_role.image_uploader_lambda_exec_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject"
        ],
        Resource = [
          "${aws_s3_bucket.image_upload_bucket.arn}/*",
          "${aws_s3_bucket.documents_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      },
            {
        Effect = "Allow",
        Action = [
          "kms:Decrypt"
        ],
        Resource = aws_kms_key.lambda_key.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_ses_policy" {
  name = "lambda-ses-send-policy"
  role = aws_iam_role.image_uploader_lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_key" "lambda_key" {
  description         = "KMS key for encrypting Lambda environment variables"
  enable_key_rotation = false

  policy = jsonencode({
    Version = "2012-10-17",
    Id      = "key-lambda-upload",
    Statement: [
      {
        Sid: "AllowLambdaToDecrypt",
        Effect: "Allow",
        Principal: {
          AWS: aws_iam_role.image_uploader_lambda_exec_role.arn
        },
        Action: [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ],
        Resource: "*"
      },
      {
        Sid: "AllowRootAccountFullAccess",
        Effect: "Allow",
        Principal: {
          AWS: "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action: "kms:*",
        Resource: "*"
      }
    ]
  })
}

resource "aws_kms_alias" "lambda_key_alias" {
  name          = "alias/image-upload-lambda"
  target_key_id = aws_kms_key.lambda_key.id
}

data "aws_caller_identity" "current" {}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "image_uploader" {
  function_name = "image-uploader-dev"
  kms_key_arn = aws_kms_key.lambda_key.arn

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  role    = aws_iam_role.image_uploader_lambda_exec_role.arn
  handler = "handler.lambda_handler"
  runtime = "python3.11"

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.image_upload_bucket.bucket
      DOCUMENTS_BUCKET = aws_s3_bucket.documents_bucket.bucket
      IMAGES_BUCKET   = aws_s3_bucket.documents_bucket.bucket
      UPLOAD_API_SECRET = var.upload_api_secret
    }
  }

  depends_on = [
  aws_iam_role_policy.lambda_s3_policy,
  aws_kms_key.lambda_key
  ]
}
