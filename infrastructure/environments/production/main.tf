terraform {
  required_version = ">= 1.6.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local values
locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    CreatedAt   = timestamp()
  }

  # Generate availability zones if not provided
  availability_zones = length(var.availability_zones) > 0 ? var.availability_zones : [
    "${var.aws_region}a",
    "${var.aws_region}b"
  ]

  # Generate subnet CIDRs if not provided
  public_subnet_cidrs = length(var.public_subnet_cidrs) > 0 ? var.public_subnet_cidrs : [
    cidrsubnet(var.vpc_cidr, 8, 1),
    cidrsubnet(var.vpc_cidr, 8, 2)
  ]

  private_subnet_cidrs = length(var.private_subnet_cidrs) > 0 ? var.private_subnet_cidrs : [
    cidrsubnet(var.vpc_cidr, 8, 10),
    cidrsubnet(var.vpc_cidr, 8, 20)
  ]
}

# Networking Module
module "networking" {
  source = "../../modules/networking"

  project_name           = var.project_name
  environment           = var.environment
  vpc_cidr              = var.vpc_cidr
  availability_zones    = local.availability_zones
  public_subnet_cidrs   = local.public_subnet_cidrs
  private_subnet_cidrs  = local.private_subnet_cidrs
}

# Security Module
module "security" {
  source = "../../modules/security"

  project_name   = var.project_name
  environment    = var.environment
  vpc_id         = module.networking.vpc_id
  vpc_cidr       = module.networking.vpc_cidr_block
  aws_region     = data.aws_region.current.name
  aws_account_id = data.aws_caller_identity.current.account_id
}

# Storage Module
module "storage" {
  source = "../../modules/storage"

  project_name      = var.project_name
  environment       = var.environment
  enable_cloudfront = var.enable_cloudfront
}

# Secrets Module
module "secrets" {
  source = "../../modules/secrets"

  project_name = var.project_name
  environment  = var.environment
  tags         = local.common_tags
}

# Compute Module
module "compute" {
  source = "../../modules/compute"

  project_name                = var.project_name
  environment                = var.environment
  vpc_id                     = module.networking.vpc_id
  public_subnet_ids          = module.networking.public_subnet_ids
  private_subnet_ids         = module.networking.private_subnet_ids
  alb_security_group_id      = module.security.alb_security_group_id
  ec2_security_group_id      = module.security.ec2_security_group_id
  ec2_instance_profile_name  = module.security.ec2_instance_profile_name
  ssl_certificate_arn        = var.ssl_certificate_arn
  enable_alb_logs           = var.enable_alb_logs
  instance_type             = var.instance_type
  min_size                  = var.min_size
  max_size                  = var.max_size
  desired_capacity          = var.desired_capacity
  key_name                  = var.key_name
}
