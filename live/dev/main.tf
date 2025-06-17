
resource "aws_s3_bucket" "image_upload_bucket" {
  bucket = "s3-image-upload-api-2712"
  force_destroy = true

  tags = {
    Name = "image-upload-api-bucket"
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