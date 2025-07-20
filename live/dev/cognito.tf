resource "aws_cognito_user_pool" "main" {
  name = "upload-user-pool"
  auto_verified_attributes = ["email"]

  username_attributes = ["email"]
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = false
    require_numbers   = true
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "frontend" {
  name         = "upload-frontend-client"
  user_pool_id = aws_cognito_user_pool.main.id
  generate_secret = false

  allowed_oauth_flows = ["code"]
  allowed_oauth_scopes = ["openid", "email", "profile"]
  allowed_oauth_flows_user_pool_client = true

  callback_urls = [var.login_redirect_url]
  logout_urls   = [var.logout_redirect_url]

  supported_identity_providers = ["COGNITO"]
}

resource "aws_cognito_user_pool_domain" "ui" {
  domain       = "upload-auth"
  user_pool_id = aws_cognito_user_pool.main.id
}

output "cognito_login_url" {
  value = "${var.cognito_domain}/login?client_id=${var.cognito_client_id}&response_type=code&scope=openid+email&redirect_uri=${var.login_redirect_url}"
}
