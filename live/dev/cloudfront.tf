resource "aws_cloudfront_origin_access_control" "s3_oac" {
  name                              = "upload-site-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
  description                       = "OAC for S3 frontend site"
}

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
    origin_path = "/${var.stage_name}"  # e.g. /dev
  }

  default_cache_behavior {
    target_origin_id       = "s3-upload-site"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  ordered_cache_behavior {
    path_pattern           = "/upload*"
    target_origin_id       = "api-upload"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "OPTIONS", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id            = "Managed-CachingDisabled"
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.forward_auth.id
  }

  ordered_cache_behavior {
    path_pattern           = "/files*"
    target_origin_id       = "api-upload"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "OPTIONS", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id            = "Managed-CachingDisabled"
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.forward_auth.id
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
