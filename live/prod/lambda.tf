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

  lifecycle {
    create_before_destroy = true
  }
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

  lifecycle {
    create_before_destroy = true
  }
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

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role" "image_uploader_lambda_exec_role" {
  name = "lambda_s3_upload_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [ {
      Action = "sts:AssumeRole",
      Principal = {
        Service = "lambda.amazonaws.com"
      },
      Effect = "Allow",
      Sid    = ""
    }]
  })

  lifecycle {
    create_before_destroy = true
  }
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

  lifecycle {
    create_before_destroy = true
  }
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

  lifecycle {
    create_before_destroy = true
  }
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

  lifecycle {
    create_before_destroy = true
  }
}
