variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository in the format 'owner/repo'"
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
