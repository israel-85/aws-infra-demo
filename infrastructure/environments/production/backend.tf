terraform {
  backend "s3" {
    bucket         = "aws-infra-demo-terraform-state-production"
    key            = "production/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "aws-infra-demo-terraform-locks"
  }
}
