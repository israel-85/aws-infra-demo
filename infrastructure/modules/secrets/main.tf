# Application secrets stored in AWS Secrets Manager
resource "aws_secretsmanager_secret" "app_config" {
  name                    = "${var.project_name}/${var.environment}/app-config"
  description             = "Application configuration secrets for ${var.environment}"
  recovery_window_in_days = var.recovery_window_in_days

  # Enable automatic rotation if rotation configuration is provided
  dynamic "rotation_rules" {
    for_each = var.enable_rotation ? [1] : []
    content {
      automatically_after_days = var.rotation_days
    }
  }

  tags = var.tags
}

# Database credentials secret (separate from app config)
resource "aws_secretsmanager_secret" "database_credentials" {
  count                   = var.create_database_secret ? 1 : 0
  name                    = "${var.project_name}/${var.environment}/database-credentials"
  description             = "Database credentials for ${var.environment}"
  recovery_window_in_days = var.recovery_window_in_days

  # Enable automatic rotation for database credentials
  dynamic "rotation_rules" {
    for_each = var.enable_db_rotation ? [1] : []
    content {
      automatically_after_days = var.db_rotation_days
    }
  }

  tags = var.tags
}

# API keys and external service credentials
resource "aws_secretsmanager_secret" "api_keys" {
  count                   = var.create_api_keys_secret ? 1 : 0
  name                    = "${var.project_name}/${var.environment}/api-keys"
  description             = "External API keys and service credentials for ${var.environment}"
  recovery_window_in_days = var.recovery_window_in_days

  tags = var.tags
}

# Example secret values (in production, these would be set externally)
resource "aws_secretsmanager_secret_version" "app_config" {
  secret_id = aws_secretsmanager_secret.app_config.id
  secret_string = jsonencode({
    apiVersion = "1.0"
    features = [
      "health-checks",
      "metrics",
      "logging"
    ]
    database = {
      maxConnections = 100
      timeout        = 30
    }
    cache = {
      ttl     = 300
      enabled = true
    }
    logging = {
      level = var.environment == "production" ? "info" : "debug"
    }
    # Add other non-sensitive configuration here
    # Sensitive values should be set manually or via separate process
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# Initial database credentials (placeholder - should be updated externally)
resource "aws_secretsmanager_secret_version" "database_credentials" {
  count     = var.create_database_secret ? 1 : 0
  secret_id = aws_secretsmanager_secret.database_credentials[0].id
  secret_string = jsonencode({
    username = "app_user"
    password = "CHANGE_ME_IN_PRODUCTION"
    engine   = "mysql"
    host     = "localhost"
    port     = 3306
    dbname   = "${var.project_name}_${var.environment}"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# Lambda function for secret rotation (if rotation is enabled)
resource "aws_lambda_function" "rotation_lambda" {
  count            = var.enable_rotation && var.create_rotation_lambda ? 1 : 0
  filename         = "rotation_lambda.zip"
  function_name    = "${var.project_name}-${var.environment}-secret-rotation"
  role            = aws_iam_role.rotation_lambda_role[0].arn
  handler         = "index.handler"
  source_code_hash = data.archive_file.rotation_lambda_zip[0].output_base64sha256
  runtime         = "python3.9"
  timeout         = 30

  environment {
    variables = {
      SECRETS_MANAGER_ENDPOINT = "https://secretsmanager.${var.aws_region}.amazonaws.com"
    }
  }

  tags = var.tags
}

# Create rotation lambda zip file
data "archive_file" "rotation_lambda_zip" {
  count       = var.enable_rotation && var.create_rotation_lambda ? 1 : 0
  type        = "zip"
  output_path = "rotation_lambda.zip"
  source {
    content = templatefile("${path.module}/rotation_lambda.py", {
      secret_arn = aws_secretsmanager_secret.app_config.arn
    })
    filename = "index.py"
  }
}

# IAM role for rotation lambda
resource "aws_iam_role" "rotation_lambda_role" {
  count = var.enable_rotation && var.create_rotation_lambda ? 1 : 0
  name  = "${var.project_name}-${var.environment}-rotation-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# IAM policy for rotation lambda
resource "aws_iam_policy" "rotation_lambda_policy" {
  count = var.enable_rotation && var.create_rotation_lambda ? 1 : 0
  name  = "${var.project_name}-${var.environment}-rotation-lambda-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage"
        ]
        Resource = [
          aws_secretsmanager_secret.app_config.arn,
          var.create_database_secret ? aws_secretsmanager_secret.database_credentials[0].arn : ""
        ]
      }
    ]
  })

  tags = var.tags
}

# Attach policy to rotation lambda role
resource "aws_iam_role_policy_attachment" "rotation_lambda_policy_attachment" {
  count      = var.enable_rotation && var.create_rotation_lambda ? 1 : 0
  role       = aws_iam_role.rotation_lambda_role[0].name
  policy_arn = aws_iam_policy.rotation_lambda_policy[0].arn
}

# Configure rotation for app config secret
resource "aws_secretsmanager_secret_rotation" "app_config_rotation" {
  count               = var.enable_rotation && var.create_rotation_lambda ? 1 : 0
  secret_id           = aws_secretsmanager_secret.app_config.id
  rotation_lambda_arn = aws_lambda_function.rotation_lambda[0].arn

  rotation_rules {
    automatically_after_days = var.rotation_days
  }

  depends_on = [aws_lambda_function.rotation_lambda]
}