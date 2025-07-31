resource "aws_s3_bucket" "frontend_site" {
  bucket = "image-uploader-frontend-${var.env}"

  tags = {
    Name = format("Frontend Site Dev")
    Environment = var.env
  }
}

resource "aws_s3_bucket_website_configuration" "frontend_site" {
  bucket = aws_s3_bucket.frontend_site.id

  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend_site" {
  bucket                  = aws_s3_bucket.frontend_site.id
  block_public_acls       = false
  block_public_policy     = false
  restrict_public_buckets = false
  ignore_public_acls      = false
}

resource "aws_s3_bucket_policy" "allow_public_read" {
  bucket = aws_s3_bucket.frontend_site.id

  depends_on = [aws_s3_bucket_public_access_block.frontend_site]

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = "*",
        Action    = ["s3:GetObject"],
        Resource  = "${aws_s3_bucket.frontend_site.arn}/*"
      }
    ]
  })
}
data "template_file" "index_html" {
  template = file("${path.module}/frontend/index.html.tpl")

  vars = {
    BEARER_TOKEN    = var.upload_api_secret
    API_URL         = var.upload_api_url
    COGNITO_DOMAIN  = var.cognito_domain
    CLIENT_ID       = var.cognito_client_id
    REDIRECT_URI    = var.login_redirect_url
    LOGOUT_URI      = var.logout_redirect_url
  }
}


resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.frontend_site.id
  key          = "index.html"
  content      = data.template_file.index_html.rendered
  content_type = "text/html"
}

resource "aws_s3_object" "list_html" {
  bucket = aws_s3_bucket.frontend_site.id
  key    = "list.html"
  content = data.template_file.list_html.rendered
  content_type = "text/html"
}

data "template_file" "list_html" {
  template = file("${path.module}/frontend/list.html.tpl")

  vars = {
    API_URL         = var.upload_api_url
    COGNITO_DOMAIN  = var.cognito_domain
    CLIENT_ID       = var.cognito_client_id
    REDIRECT_URI    = var.logout_redirect_url
  }
}




