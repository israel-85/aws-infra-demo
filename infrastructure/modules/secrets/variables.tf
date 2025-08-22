variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (staging, production)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "recovery_window_in_days" {
  description = "Number of days that AWS Secrets Manager waits before it can delete the secret"
  type        = number
  default     = 7
}

variable "enable_rotation" {
  description = "Enable automatic rotation for application configuration secrets"
  type        = bool
  default     = false
}

variable "rotation_days" {
  description = "Number of days between automatic rotations"
  type        = number
  default     = 30
}

variable "create_database_secret" {
  description = "Create a separate secret for database credentials"
  type        = bool
  default     = true
}

variable "enable_db_rotation" {
  description = "Enable automatic rotation for database credentials"
  type        = bool
  default     = false
}

variable "db_rotation_days" {
  description = "Number of days between database credential rotations"
  type        = number
  default     = 30
}

variable "create_api_keys_secret" {
  description = "Create a separate secret for API keys and external service credentials"
  type        = bool
  default     = true
}

variable "create_rotation_lambda" {
  description = "Create Lambda function for secret rotation"
  type        = bool
  default     = false
}
