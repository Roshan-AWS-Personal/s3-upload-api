########################################
# CloudFront for S3 site + API Gateway
########################################

resource "aws_cloudfront_origin_access_control" "s3_oac" {
  name                              = "upload-site-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
  description                       = "OAC for S3 frontend site"
}

# Region helper for API origin hostname
data "aws_region" "current" {}

# Cache policies
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

# Origin request policies
resource "aws_cloudfront_origin_request_policy" "s3_safe" {
  name = "s3-safe-policy"

  cookies_config { cookie_behavior = "none" }
  headers_config { header_behavior = "none" }
  query_strings_config { query_string_behavior = "none" }
}

# Forward only the headers the API needs (incl. Authorization)
resource "aws_cloudfront_origin_request_policy" "api_auth_headers" {
  name = "api-auth-headers-policy"

  cookies_config { cookie_behavior = "none" }

  headers_config {
    header_behavior = "whitelist"
    headers {
      items = [
        "Authorization",
        "Content-Type",
        "Origin"
      ]
    }
  }

  query_strings_config { query_string_behavior = "none" }
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  default_root_object = "index.html"

  # S3 origin (frontend site)
  origin {
    domain_name              = aws_s3_bucket.frontend_site.bucket_regional_domain_name
    origin_id                = "s3-upload-site"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3_oac.id
  }

  # API Gateway origin (host-only; stage via origin_path)
  origin {
    domain_name = "${aws_api_gateway_rest_api.upload_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com"
    origin_id   = "api-gateway-origin"

    # e.g. "/dev" or "/prod" — from your aws_api_gateway_stage.stage
    origin_path = "/${aws_api_gateway_stage.stage.stage_name}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Default behavior -> S3 site
  default_cache_behavior {
    allowed_methods         = ["GET", "HEAD"]
    cached_methods          = ["GET", "HEAD"]
    target_origin_id        = "s3-upload-site"
    viewer_protocol_policy  = "redirect-to-https"
    compress                = true

    cache_policy_id          = data.aws_cloudfront_cache_policy.optimized.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.s3_safe.id
  }

  # Route /upload -> API (no cache, forward auth)
  ordered_cache_behavior {
    path_pattern            = "/upload"
    target_origin_id        = "api-gateway-origin"
    viewer_protocol_policy  = "https-only"
    allowed_methods         = ["GET", "HEAD", "OPTIONS", "POST", "PUT", "DELETE", "PATCH"]
    cached_methods          = ["GET", "HEAD", "OPTIONS"]
    compress                = true

    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.api_auth_headers.id
  }

  # Route /files -> API (no cache, forward auth)
  ordered_cache_behavior {
    path_pattern            = "/files"
    target_origin_id        = "api-gateway-origin"
    viewer_protocol_policy  = "https-only"
    allowed_methods         = ["GET", "HEAD", "OPTIONS", "POST", "PUT", "DELETE", "PATCH"]
    cached_methods          = ["GET", "HEAD", "OPTIONS"]
    compress                = true

    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.api_auth_headers.id
  }

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
