resource "aws_cloudfront_origin_access_control" "s3_oac" {
  name                              = "upload-site-oac"
  description                       = "OAC for S3 static frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# You already have these — shown for completeness:
resource "aws_cloudfront_origin_request_policy" "forward_auth" {
  name = "forward-auth-and-origin"

  cookies_config {
    cookie_behavior = "none"
  }

  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["Authorization", "Origin"]
    }
  }

  query_strings_config {
    query_string_behavior = "none"
  }
}

resource "aws_cloudfront_origin_request_policy" "s3_safe" {
  name = "s3-safe-policy"

  cookies_config {
    cookie_behavior = "none"
  }

  headers_config {
    header_behavior = "none"
  }

  query_strings_config {
    query_string_behavior = "none"
  }
}

data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  default_root_object = "index.html"

  origin {
    domain_name = aws_s3_bucket.frontend_site.bucket_regional_domain_name
    origin_id   = "s3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3_oac.id
  }

  origin {
    domain_name = "${aws_apigatewayv2_api.api.api_id}.execute-api.${var.aws_region}.amazonaws.com"
    origin_id   = "api-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "s3-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id           = data.aws_cloudfront_cache_policy.optimized.id
    origin_request_policy_id  = aws_cloudfront_origin_request_policy.s3_safe.id
  }

  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = "api-origin"
    viewer_protocol_policy   = "redirect-to-https"

    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "DELETE", "PATCH"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = true

    cache_policy_id           = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id  = aws_cloudfront_origin_request_policy.forward_auth.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Project = "s3-image-upload"
  }
}
