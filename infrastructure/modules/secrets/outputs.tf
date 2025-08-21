output "app_config_secret_arn" {
  description = "ARN of the application configuration secret"
  value       = aws_secretsmanager_secret.app_config.arn
}

output "app_config_secret_name" {
  description = "Name of the application configuration secret"
  value       = aws_secretsmanager_secret.app_config.name
}

output "database_secret_arn" {
  description = "ARN of the database credentials secret"
  value       = var.create_database_secret ? aws_secretsmanager_secret.database_credentials[0].arn : null
}

output "database_secret_name" {
  description = "Name of the database credentials secret"
  value       = var.create_database_secret ? aws_secretsmanager_secret.database_credentials[0].name : null
}

output "api_keys_secret_arn" {
  description = "ARN of the API keys secret"
  value       = var.create_api_keys_secret ? aws_secretsmanager_secret.api_keys[0].arn : null
}

output "api_keys_secret_name" {
  description = "Name of the API keys secret"
  value       = var.create_api_keys_secret ? aws_secretsmanager_secret.api_keys[0].name : null
}

output "rotation_lambda_arn" {
  description = "ARN of the rotation Lambda function"
  value       = var.enable_rotation && var.create_rotation_lambda ? aws_lambda_function.rotation_lambda[0].arn : null
}