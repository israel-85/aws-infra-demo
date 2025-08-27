# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a comprehensive AWS Infrastructure Demo that showcases a complete CI/CD pipeline with Infrastructure as Code (IaC) using Terraform, GitHub Actions, and a Nginx application. The project demonstrates production-ready AWS deployment patterns with multi-environment support, comprehensive testing, security scanning, and automated rollback capabilities.

## Key Components and Patterns

### Infrastructure Modules (`infrastructure/modules/`)
- **Networking**: VPC with multi-AZ public/private subnets, NAT gateways, and security groups
- **Compute**: ALB + EC2 Auto Scaling Groups with health checks
- **Security**: IAM roles, security groups with least privilege principles
- **Storage**: S3 buckets with lifecycle policies for artifacts and state
- **Secrets**: AWS Secrets Manager with Lambda-based rotation (Python 3.9)
- **GitHub OIDC**: JWT-based authentication for secure CI/CD pipeline access

### Infrastructure Configuration
- **`infrastructure/bootstrap/main.tf`**: OIDC provider and Terraform state backend setup
- **`infrastructure/environments/*/backend.hcl.template`**: Dynamic backend configuration templates
- **`infrastructure/shared/`**: Common variables and locals for consistent configuration

## Development Workflow

### Infrastructure Changes
1. Modify Terraform modules or environment configurations
2. Run `terraform plan` in relevant environment directory
3. Test in staging environment first
4. Use CI/CD pipeline for production deployment with approval gates

## Common Troubleshooting

### Infrastructure Issues
```bash
# Check Terraform state
cd infrastructure/environments/production
terraform plan

# Force unlock state if needed (use carefully)
terraform force-unlock <lock-id>

# Re-initialize backend configuration
./scripts/init-terraform.sh production
```
## Key Dependencies and Versions

### Infrastructure Stack
- **Terraform**: >= 1.6.0 (specified in terraform blocks)
- **AWS Provider**: ~> 5.0 for latest AWS features
- **GitHub Actions**: JWT-based OIDC authentication with environment protection