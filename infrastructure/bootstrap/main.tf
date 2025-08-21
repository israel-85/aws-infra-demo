terraform {
  required_version = ">= 1.6.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Local values for consistent tagging
locals {
  common_tags = {
    Project     = var.project_name
    Environment = "bootstrap"
    ManagedBy   = "terraform"
  }
}

# GitHub OIDC Provider and IAM Role
module "github_oidc" {
  source = "../modules/github-oidc"

  project_name      = var.project_name
  github_repository = var.github_repository
  aws_region        = var.aws_region
  tags              = local.common_tags
}

# S3 bucket for Terraform state storage - staging
resource "aws_s3_bucket" "terraform_state_staging" {
  bucket = "${var.project_name}-terraform-state-staging"

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-terraform-state-staging"
    Environment = "staging"
    Purpose     = "Terraform State"
  })
}

# S3 bucket versioning for Terraform state - staging
resource "aws_s3_bucket_versioning" "terraform_state_staging" {
  bucket = aws_s3_bucket.terraform_state_staging.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption for Terraform state - staging
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_staging" {
  bucket = aws_s3_bucket.terraform_state_staging.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block for Terraform state - staging
resource "aws_s3_bucket_public_access_block" "terraform_state_staging" {
  bucket = aws_s3_bucket.terraform_state_staging.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket for Terraform state storage - production
resource "aws_s3_bucket" "terraform_state_production" {
  bucket = "${var.project_name}-terraform-state-production"

  tags = merge(local.common_tags, {
    Name        = "${var.project_name}-terraform-state-production"
    Environment = "production"
    Purpose     = "Terraform State"
  })
}

# S3 bucket versioning for Terraform state - production
resource "aws_s3_bucket_versioning" "terraform_state_production" {
  bucket = aws_s3_bucket.terraform_state_production.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption for Terraform state - production
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_production" {
  bucket = aws_s3_bucket.terraform_state_production.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block for Terraform state - production
resource "aws_s3_bucket_public_access_block" "terraform_state_production" {
  bucket = aws_s3_bucket.terraform_state_production.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for Terraform state locking
resource "aws_dynamodb_table" "terraform_locks" {
  name           = "${var.project_name}-terraform-locks"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-terraform-locks"
    Purpose = "Terraform State Locking"
  })
}