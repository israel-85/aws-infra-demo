variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "aws-infra-demo"
}

variable "github_repository" {
  description = "GitHub repository in the format 'owner/repo' (e.g., 'myorg/aws-infra-demo')"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}
