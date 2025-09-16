###############################################
# CloudFront: S3 site + TWO API Gateways
# - REST API for upload/list
# - HTTP API for chat
###############################################

locals {
  # Build execute-api hostnames (no scheme)
  upload_api_domain = "${aws_api_gateway_rest_api.upload_api.id}.execute-api.${var.aws_region}.amazonaws.com"
  chat_api_domain   = var.chat_api_domain # <-- replace ID if your HTTP API changes

  # Stages
  upload_api_stage = var.stage_name          # e.g., "dev" or "prod" (you already have this var)
  chat_api_stage   = "$default"              # change if you use a named stage
}

locals {
  s3_origin_id           = "s3-upload-site"
  upload_api_origin_id   = "upload-api-origin" # REST API
  chat_api_origin_id     = "chat-api-origin"   # HTTP API
}

# ------------ Origin Access Control (S3) ------------
resource "aws_cloudfront_origin_access_control" "s3_oac" {
  name                              = "upload-site-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
  description                       = "OAC for S3 frontend site"
}

# ------------ Cache/Origin-Request Policies ------------
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}
data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

# S3: forward nothing (DON'T forward Authorization to S3)
resource "aws_cloudfront_origin_request_policy" "s3_safe" {
  name = "s3-safe-policy"

  cookies_config       { cookie_behavior        = "none" }
  headers_config       { header_behavior        = "none" }
  query_strings_config { query_string_behavior  = "none" }
}

# APIs: forward all viewer headers except Host (so Authorization reaches API GW)
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
    domain_name = local.upload_api_domain
    origin_id   = local.upload_api_origin_id
    origin_path = local.upload_api_stage == "$default" ? "" : "/${local.upload_api_stage}"

    custom_origin_config {
      origin_protocol_policy = "https-only"
      http_port              = 80
      https_port             = 443
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # HTTP API: chat
  origin {
    domain_name = local.chat_api_domain
    origin_id   = local.chat_api_origin_id
    origin_path = local.chat_api_stage == "$default" ? "" : "/${local.chat_api_stage}"

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
    origin_request_policy_id = aws_cloudfront_origin_request_policy.s3_safe.id
    compress                 = true
  }

  # Upload API (REST)
  ordered_cache_behavior {
    path_pattern             = "/upload*"
    target_origin_id         = local.upload_api_origin_id
    allowed_methods          = ["GET","HEAD","OPTIONS","PUT","POST","PATCH","DELETE"]
    cached_methods           = ["GET","HEAD","OPTIONS"]
    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  # List API (REST)
  ordered_cache_behavior {
    path_pattern             = "/files*"
    target_origin_id         = local.upload_api_origin_id
    allowed_methods          = ["GET","HEAD","OPTIONS","PUT","POST","PATCH","DELETE"]
    cached_methods           = ["GET","HEAD","OPTIONS"]
    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  # Chat API (HTTP)
  ordered_cache_behavior {
    path_pattern             = "/query*"
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

  tags = { Environment = var.env }
}

output "cloudfront_url" {
  value = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}
