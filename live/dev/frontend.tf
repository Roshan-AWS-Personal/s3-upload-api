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
    BEARER_TOKEN = jsonencode("gW75T+AcsXW4LLPMhup9Rv944JZ64EA9D6te5b/RxDI=")
  }
}


resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.frontend_site.id
  key          = "index.html"
  content      = data.template_file.index_html.rendered
  content_type = "text/html"
}

