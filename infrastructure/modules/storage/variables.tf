variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (staging/production)"
  type        = string
}

variable "enable_cloudfront" {
  description = "Enable CloudFront distribution for static assets"
  type        = bool
  default     = true
}