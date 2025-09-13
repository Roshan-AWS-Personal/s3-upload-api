###############################################
# CloudFront: S3 site + TWO API Gateways
# - REST API for upload/list
# - HTTP API for chat
###############################################

# REST API (uploads & list)
# Example: "n3bcr23wm1.execute-api.ap-southeast-2.amazonaws.com"
variable "upload_api_execute_domain" {
  type        = string
  description = "image-upload REST API execute-api domain (no scheme)"
}
# Example: "prod" or "$default" (REST usually named like 'prod', 'dev')
variable "upload_api_stage" {
  type        = string
  description = "image-upload REST API stage (e.g., prod/dev)"
}

# HTTP API (chat)
# Example: "tzfwnff860.execute-api.ap-southeast-2.amazonaws.com"
variable "chat_api_execute_domain" {
  type        = string
  default = "https://tzfwnff860.execute-api.ap-southeast-2.amazonaws.com"
  description = "ai-kb HTTP API execute-api domain (no scheme)"
}
# Example: "$default" or 'dev'
variable "chat_api_stage" {
  type        = string
  default     = "$default"
  description = "ai-kb HTTP API stage"
}

# ------------ Locals ------------
locals {
  s3_origin_id        = "s3-upload-site"
  upload_api_origin_id = "upload-api-origin" # REST API
  chat_api_origin_id   = "chat-api-origin"   # HTTP API
}

# ------------ Origin Access Control (S3) ------------
resource "aws_cloudfront_origin_access_control" "s3_oac" {
  name                              = "upload-site-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
  description                       = "OAC for S3 frontend site"
}

# ------------ Managed Policies ------------
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}
data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

# Safe for S3 (no auth/header forwarding to S3)
data "aws_cloudfront_origin_request_policy" "s3_safe" {
  name = "Managed-S3Origin"
}

# Forward almost everything (so Authorization reaches APIs)
data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

# ------------ Distribution ------------
resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  default_root_object = "index.html"
  comment             = "Frontend site with multi-API routing"

  # ----- Origins -----
  # S3 static site
  origin {
    domain_name              = aws_s3_bucket.frontend_site.bucket_regional_domain_name
    origin_id                = local.s3_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.s3_oac.id
  }

  # REST API: uploads/list
  origin {
    domain_name = var.upload_api_execute_domain
    origin_id   = local.upload_api_origin_id
    origin_path = var.upload_api_stage == "$default" ? "" : "/${var.upload_api_stage}"

    custom_origin_config {
      origin_protocol_policy = "https-only"
      http_port              = 80
      https_port             = 443
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # HTTP API: chat
  origin {
    domain_name = var.chat_api_execute_domain
    origin_id   = local.chat_api_origin_id
    origin_path = var.chat_api_stage == "$default" ? "" : "/${var.chat_api_stage}"

    custom_origin_config {
      origin_protocol_policy = "https-only"
      http_port              = 80
      https_port             = 443
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # ----- Behaviors -----
  # Default: S3 site
  default_cache_behavior {
    target_origin_id         = local.s3_origin_id
    allowed_methods          = ["GET", "HEAD"]
    cached_methods           = ["GET", "HEAD"]
    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_optimized.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.s3_safe.id
    compress                 = true
  }

  # Upload API (REST): presign endpoint
  ordered_cache_behavior {
    path_pattern             = "/api/upload*"
    target_origin_id         = local.upload_api_origin_id
    allowed_methods          = ["GET","HEAD","OPTIONS","PUT","POST","PATCH","DELETE"]
    cached_methods           = ["GET","HEAD","OPTIONS"]
    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  # List API (REST): listing endpoint(s)
  ordered_cache_behavior {
    path_pattern             = "/api/list*"
    target_origin_id         = local.upload_api_origin_id
    allowed_methods          = ["GET","HEAD","OPTIONS","PUT","POST","PATCH","DELETE"]
    cached_methods           = ["GET","HEAD","OPTIONS"]
    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  # Chat API (HTTP): chat endpoint(s)
  ordered_cache_behavior {
    path_pattern             = "/api/chat*"
    target_origin_id         = local.chat_api_origin_id
    allowed_methods          = ["GET","HEAD","OPTIONS","PUT","POST","PATCH","DELETE"]
    cached_methods           = ["GET","HEAD","OPTIONS"]
    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  # ----- Misc -----
  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Environment = var.env
  }
}

output "cloudfront_url" {
  value = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}
