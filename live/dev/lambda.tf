# This Terraform code sets up two separate Lambdas:
# 1. image_uploader: for generating pre-signed URLs
# 2. s3_event_logger: for logging actual S3 uploads to DynamoDB


locals {
    name = "ai-kb-dev"
    ingest_build_id = sha256(join("", [
      filesha256("${path.root}/lambda/ingest/Dockerfile"),
      filesha256("${path.root}/lambda/ingest/requirements.txt"),
      filesha256("${path.root}/lambda/ingest/app.py"),
    ]))

    query_build_id = sha256(join("", [
      filesha256("${path.root}/lambda/query/Dockerfile"),
      filesha256("${path.root}/lambda/query/requirements.txt"),
      filesha256("${path.root}/lambda/query/app.py"),
    ]))
}

resource "aws_iam_role" "s3_event_lambda_role" {
  name = "s3-event-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy_attachment" "s3_event_lambda_logs" {
  name       = "attach-s3-event-logs"
  roles      = [aws_iam_role.s3_event_lambda_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy_attachment" "s3_event_dynamodb_access" {
  name       = "attach-s3-event-dynamodb"
  roles      = [aws_iam_role.s3_event_lambda_role.name]
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_lambda_function" "s3_event_logger" {
  function_name = "s3-event-logger"
  handler       = "event_logger.lambda_handler"
  runtime       = "python3.11"
  role          = aws_iam_role.s3_event_lambda_role.arn
  filename      = data.archive_file.s3_event_lambda_zip.output_path
  source_code_hash = data.archive_file.s3_event_lambda_zip.output_base64sha256
  timeout       = 10
  environment {
    variables = {
      DYNAMODB_TABLE = var.dynamodb_table
    }
  }
}

# For the event logger Lambda (from event_logger.py)
data "archive_file" "s3_event_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/event_logger"
  output_path = "${path.module}/zips/s3_event_logger.zip"
}

# For the uploader Lambda (from upload_handler.py)
data "archive_file" "upload_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/upload_handler"
  output_path = "${path.module}/zips/upload_handler.zip"
}

resource "aws_s3_bucket_notification" "images_trigger" {
  bucket = aws_s3_bucket.image_upload_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_event_logger.arn
    events              = ["s3:ObjectCreated:Put"]
  }

  depends_on = [aws_lambda_permission.allow_s3_trigger]
}

resource "aws_lambda_permission" "allow_s3_trigger" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_event_logger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.image_upload_bucket.arn

}

resource "aws_s3_bucket_notification" "documents_trigger" {
  bucket = aws_s3_bucket.documents_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_event_logger.arn
    events              = ["s3:ObjectCreated:Put"]
  }

  depends_on = [aws_lambda_permission.allow_s3_trigger_documents]
}

resource "aws_lambda_permission" "allow_s3_trigger_documents" {
  statement_id  = "AllowS3InvokeDocuments"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_event_logger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.documents_bucket.arn
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

resource "aws_lambda_function" "image_uploader" {
  function_name = "image-uploader-dev"
  kms_key_arn   = aws_kms_key.lambda_key.arn

  filename         = data.archive_file.upload_lambda_zip.output_path
  source_code_hash = data.archive_file.upload_lambda_zip.output_base64sha256

  role    = aws_iam_role.image_uploader_lambda_exec_role.arn
  handler = "upload_handler.lambda_handler"
  runtime = "python3.11"

  environment {
    variables = {
      IMAGES_BUCKET      = aws_s3_bucket.image_upload_bucket.bucket
      DOCUMENTS_BUCKET   = aws_s3_bucket.documents_bucket.bucket
      UPLOAD_API_SECRET  = var.upload_api_secret
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_s3_policy,
    aws_kms_key.lambda_key
  ]
}

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

resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "lambda-s3-upload-policy"
  role = aws_iam_role.image_uploader_lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["s3:PutObject"],
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
        Action = ["kms:Decrypt"],
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
        Action = ["ses:SendEmail", "ses:SendRawEmail"],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "dynamodb_write_policy" {
  name = "LambdaDynamoDBWritePolicy"
  role = aws_iam_role.image_uploader_lambda_exec_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = ["dynamodb:PutItem"],
        Effect = "Allow",
        Resource = aws_dynamodb_table.file_upload_metadata.arn
      }
    ]
  })
}

resource "aws_lambda_function" "list_uploads" {
  function_name = "list_uploads"
  runtime       = "python3.12"
  role          = aws_iam_role.list_uploads_exec_role.arn
  handler       = "list_uploads.lambda_handler"

  filename         = data.archive_file.list_uploads_zip.output_path
  source_code_hash = data.archive_file.list_uploads_zip.output_base64sha256

  environment {
    variables = {
      DDB_TABLE = "file_upload_metadata"
      IMAGES_BUCKET      = aws_s3_bucket.image_upload_bucket.bucket
      DOCUMENTS_BUCKET   = aws_s3_bucket.documents_bucket.bucket
    }
  }
}

data "archive_file" "list_uploads_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/list_uploads"
  output_path = "${path.module}/zips/list_uploads.zip"
}

resource "aws_iam_role_policy" "lambda_dynamodb_read_policy" {
  name = "lambda-dynamodb-read-policy"
  role = aws_iam_role.list_uploads_exec_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          # your table
          aws_dynamodb_table.file_upload_metadata.arn,
          # your GSI on that table
          "${aws_dynamodb_table.file_upload_metadata.arn}/index/username-index"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject"
        ],
        Resource = [
          # replace with your actual bucket name or use the bucket resource
          "${aws_s3_bucket.image_upload_bucket.arn}/*",
          "${aws_s3_bucket.documents_bucket.arn}/*"
        ]
      }
    ]
  })
}


resource "aws_iam_role" "list_uploads_exec_role" {
  name = "list-uploads-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}


############################################
# ECR repositories (one per lambda)
############################################
resource "aws_ecr_repository" "ingest_repo" {
  name                 = "${local.name}-ingest"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
  force_delete = true
}

resource "aws_ecr_repository" "query_repo" {
  name                 = "${local.name}-query"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
  force_delete = true
}

############################################
# Build & push images with Terraform
############################################
# INGEST
# In docker_image blocks
resource "docker_image" "ingest" {
  name = "${aws_ecr_repository.ingest_repo.repository_url}:latest"
  build {
    context    = "${path.root}/lambda/ingest"
    dockerfile = "Dockerfile"
    platform   = "linux/amd64"
    build_args = { BUILD_ID = local.ingest_build_id }
  }
  keep_locally = true
  depends_on   = [aws_ecr_repository.ingest_repo]
}

resource "docker_registry_image" "ingest" {
  name          = docker_image.ingest.name
  keep_remotely = true
}

# QUERY

resource "docker_image" "query" {
  name = "${aws_ecr_repository.query_repo.repository_url}:latest"
  build {
    context    = "${path.root}/lambda/query"
    dockerfile = "Dockerfile"
    platform   = "linux/amd64"
    build_args = { BUILD_ID = local.query_build_id }
  }
  keep_locally = true
  depends_on   = [aws_ecr_repository.query_repo]
}

resource "docker_registry_image" "query" {
  name          = docker_image.query.name
  keep_remotely = true
}

############################################
# IAM: Ingest Lambda
############################################
resource "aws_iam_role" "ingest_exec" {
  name = "${local.name}-ingest-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Action    = "sts:AssumeRole",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ingest_logs" {
  role       = aws_iam_role.ingest_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "ingest_runtime" {
  name = "${local.name}-ingest-runtime"
  role = aws_iam_role.ingest_exec.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid      = "DocsReadList",
        Effect   = "Allow",
        Action   = ["s3:ListBucket"],
        Resource = [aws_s3_bucket.documents_bucket.arn],
        Condition = { StringLike = { "s3:prefix" = ["docs/*", "docs/"] } }
      },
      {
        Sid      = "DocsReadObjects",
        Effect   = "Allow",
        Action   = ["s3:GetObject"],
        Resource = ["${aws_s3_bucket.documents_bucket.arn}/docs/*"]
      },
      {
        Sid      = "IndexWrite",
        Effect   = "Allow",
        Action   = ["s3:PutObject", "s3:DeleteObject", "s3:GetObject", "s3:HeadObject"],
        Resource = ["${aws_s3_bucket.documents_bucket.arn}/indexes/*"]
      },
      {
        Sid      = "BedrockInvoke",
        Effect   = "Allow",
        Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"],
        Resource = "*"
      }
    ]
  })
}

############################################
# IAM: Query Lambda
############################################
resource "aws_iam_role" "query_exec" {
  name = "${local.name}-query-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Action    = "sts:AssumeRole",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "query_logs" {
  role       = aws_iam_role.query_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "query_runtime" {
  name = "${local.name}-query-runtime"
  role = aws_iam_role.query_exec.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid      = "IndexRead",
        Effect   = "Allow",
        Action   = ["s3:GetObject", "s3:HeadObject"],
        Resource = ["${aws_s3_bucket.documents_bucket.arn}/indexes/*"]
      },
      {
        Sid      = "BedrockInvoke",
        Effect   = "Allow",
        Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"],
        Resource = "*"
      }
    ]
  })
}

############################################
# Lambda (container images) – no OpenSearch
############################################
# We reference the **digest** so any image rebuild triggers an update automatically.
# image_uri format: <repo-url>@<sha256-digest>

resource "aws_lambda_function" "ingest" {
  function_name = "${local.name}-ingest"
  role          = aws_iam_role.ingest_exec.arn
  package_type  = "Image"

  # Digest from pushed image
  image_uri = "${aws_ecr_repository.ingest_repo.repository_url}@${docker_registry_image.ingest.sha256_digest}"

  timeout       = 300
  memory_size   = 1024
  architectures = ["x86_64"]

  environment {
    variables = {
      S3_BUCKET      = aws_s3_bucket.documents_bucket.bucket
      DOCS_PREFIX    = "docs/"
      INDEX_PREFIX   = "indexes/latest/"
      BEDROCK_REGION = var.aws_region
      EMBED_MODEL_ID = "amazon.titan-embed-text-v2:0"
      EMBED_DIM      = "1024"
    }
  }

  depends_on = [docker_registry_image.ingest]
}

resource "aws_lambda_function" "query" {
  function_name = "${local.name}-query"
  role          = aws_iam_role.query_exec.arn
  package_type  = "Image"

  image_uri = "${aws_ecr_repository.query_repo.repository_url}@${docker_registry_image.query.sha256_digest}"

  timeout       = 60
  memory_size   = 2048
  architectures = ["x86_64"]

  ephemeral_storage { size = 4096 } # room for FAISS files in /tmp

  environment {
    variables = {
      S3_BUCKET      = aws_s3_bucket.documents_bucket.bucket
      INDEX_PREFIX   = "indexes/latest/"
      BEDROCK_REGION = var.aws_region
      EMBED_MODEL_ID = "amazon.titan-embed-text-v2:0"
      EMBED_DIM      = "1024"
      TOP_K          = "5"
    }
  }

  depends_on = [docker_registry_image.query]
}

# Quick public URL (for dev). Secure with IAM/JWT later.
resource "aws_lambda_function_url" "query_url" {
  function_name      = aws_lambda_function.query.arn
  authorization_type = "NONE"
  cors {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST"]
    allow_headers = ["*"]
  }
}

############################################
# Outputs
############################################
output "ingest_repo_url" {
  value       = aws_ecr_repository.ingest_repo.repository_url
  description = "ECR repo for ingest image"
}

output "query_repo_url" {
  value       = aws_ecr_repository.query_repo.repository_url
  description = "ECR repo for query image"
}

output "query_function_url" {
  value       = aws_lambda_function_url.query_url.function_url
  description = "Public URL for query Lambda (dev)"
}

output "ingest_image_digest" { value = docker_registry_image.ingest.sha256_digest }
output "query_image_digest"  { value = docker_registry_image.query.sha256_digest  }
