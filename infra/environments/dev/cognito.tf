resource "aws_cognito_user_pool" "main" {
  name = "taskflow-users"

  username_attributes = ["email"]

  password_policy {
    minimum_length                   = 8
    require_uppercase                = true
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  mfa_configuration = "OFF"

  auto_verified_attributes = ["email"]

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1 # 第一選択：メール
    }
    recovery_mechanism {
      name     = "verified_phone_number"
      priority = 2 # 第二選択：SMS
    }
  }

  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  tags = merge(local.common_tags, {
    Name = "taskflow-user-pool"
  })
}

resource "aws_cognito_user_pool_client" "web" {
  user_pool_id = aws_cognito_user_pool.main.id
  name         = "taskflow-web-client"

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}

resource "aws_cognito_user_group" "guest" {
  user_pool_id = aws_cognito_user_pool.main.id
  name         = "Guest"
  description  = "Read-only access"
  precedence   = 3 # 優先度（小さいほど優先。ユーザーが複数グループに属する場合に使用）
}

resource "aws_cognito_user_group" "user" {
  user_pool_id = aws_cognito_user_pool.main.id
  name         = "User"
  description  = "Standard user access"
  precedence   = 2
}

resource "aws_cognito_user_group" "admin" {
  user_pool_id = aws_cognito_user_pool.main.id
  name         = "Admin"
  description  = "Full administrative access"
  precedence   = 1 # 最高優先度
}
