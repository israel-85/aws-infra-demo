# Networking Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.networking.private_subnet_ids
}

# Load Balancer Outputs
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.compute.alb_dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = module.compute.alb_zone_id
}

# Auto Scaling Group Outputs
output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = module.compute.autoscaling_group_name
}

# Storage Outputs
output "static_assets_bucket" {
  description = "Name of the static assets S3 bucket"
  value       = module.storage.static_assets_bucket_id
}

output "artifacts_bucket" {
  description = "Name of the artifacts S3 bucket"
  value       = module.storage.artifacts_bucket_id
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = module.storage.cloudfront_domain_name
}

# Application URL
output "application_url" {
  description = "URL to access the application"
  value       = var.ssl_certificate_arn != "" ? "https://${module.compute.alb_dns_name}" : "http://${module.compute.alb_dns_name}"
}