output "github_actions_role_arn" {
  description = "ARN of the IAM role for GitHub Actions - add this to your GitHub repository secrets as AWS_ROLE_TO_ASSUME"
  value       = module.github_oidc.github_actions_role_arn
}

output "terraform_state_bucket_staging" {
  description = "Name of the S3 bucket for Terraform state storage - staging"
  value       = aws_s3_bucket.terraform_state_staging.id
}

output "terraform_state_bucket_production" {
  description = "Name of the S3 bucket for Terraform state storage - production"
  value       = aws_s3_bucket.terraform_state_production.id
}

output "terraform_locks_table_name" {
  description = "Name of the DynamoDB table for Terraform state locking"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "setup_instructions" {
  description = "Instructions for completing the setup"
  value = <<-EOT
    
    Setup Instructions:
    
    1. Add the following secret to your GitHub repository:
       - Name: AWS_ROLE_TO_ASSUME
       - Value: ${module.github_oidc.github_actions_role_arn}
    
    2. Update your repository name in infrastructure/bootstrap/terraform.tfvars:
       - github_repository = "your-org/your-repo-name"
    
    3. Configure Terraform backend for your environments using these resources:
       - Staging state bucket: ${aws_s3_bucket.terraform_state_staging.id}
       - Production state bucket: ${aws_s3_bucket.terraform_state_production.id}
       - DynamoDB locks table: ${aws_dynamodb_table.terraform_locks.name}
    
    4. Your GitHub Actions workflows can now authenticate to AWS using OIDC!
    
  EOT
}
