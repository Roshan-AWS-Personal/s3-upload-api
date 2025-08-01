resource "aws_cloudfront_origin_access_control" "s3_oac" {
  name                              = "upload-site-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
  description                       = "OAC for S3 frontend site"
}

resource "aws_cloudfront_origin_request_policy" "forward_auth" {
  name = "forward-auth-header"

  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["Authorization", "Origin"]
    }
  }

  cookies_config {
    cookie_behavior = "none"
  }

  query_strings_config {
    query_string_behavior = "all"
  }
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  default_root_object = "index.html"

  origin {
    domain_name = aws_s3_bucket.frontend_site.bucket_regional_domain_name
    origin_id   = "s3-upload-site"

    origin_access_control_id = aws_cloudfront_origin_access_control.s3_oac.id
  }

  origin {
    domain_name = "${aws_api_gateway_rest_api.upload_api.id}.execute-api.${var.aws_region}.amazonaws.com"
    origin_id   = "api-upload"

    custom_origin_config {
      origin_protocol_policy = "https-only"
      http_port              = 80
      https_port             = 443
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-upload-site"

    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  ordered_cache_behavior {
    path_pattern     = "upload*"
    allowed_methods  = ["GET", "OPTIONS", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "api-upload"

    viewer_protocol_policy     = "redirect-to-https"
    cache_policy_id            = "Managed-CachingDisabled"
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.forward_auth.id
    compress                   = true
  }

  ordered_cache_behavior {
    path_pattern     = "files*"
    allowed_methods  = ["GET", "OPTIONS", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "api-upload"

    viewer_protocol_policy     = "redirect-to-https"
    cache_policy_id            = "Managed-CachingDisabled"
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.forward_auth.id
    compress                   = true
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
    Environment = var.env
  }
}

output "cloudfront_url" {
  value = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}
