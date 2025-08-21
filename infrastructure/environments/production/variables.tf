# Import shared variables
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "aws-infra-demo"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

# Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = []
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = []
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = []
}

# Compute Configuration
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "min_size" {
  description = "Minimum number of instances in ASG"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum number of instances in ASG"
  type        = number
  default     = 6
}

variable "desired_capacity" {
  description = "Desired number of instances in ASG"
  type        = number
  default     = 2
}

variable "key_name" {
  description = "EC2 Key Pair name for SSH access"
  type        = string
  default     = ""
}

# SSL Configuration
variable "ssl_certificate_arn" {
  description = "ARN of SSL certificate for HTTPS listener"
  type        = string
  default     = ""
}

# Feature Flags
variable "enable_cloudfront" {
  description = "Enable CloudFront distribution for static assets"
  type        = bool
  default     = true
}

variable "enable_alb_logs" {
  description = "Enable ALB access logs to S3"
  type        = bool
  default     = true
}