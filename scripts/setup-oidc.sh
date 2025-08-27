#!/bin/bash

# Setup script for GitHub OIDC authentication
set -e

echo "🚀 Setting up GitHub OIDC authentication for AWS..."

# Check if we're in the right directory
if [ ! -d "infrastructure/bootstrap" ]; then
    echo "❌ Error: Please run this script from the project root directory"
    exit 1
fi

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "❌ Error: Terraform is not installed. Please install Terraform >= 1.6.0"
    exit 1
fi

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ Error: AWS CLI is not configured. Please run 'aws configure' first"
    exit 1
fi

echo "✅ Prerequisites check passed"

# Navigate to bootstrap directory
cd infrastructure/bootstrap

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo "📝 Creating terraform.tfvars from example..."
    cp terraform.tfvars.example terraform.tfvars
    
    echo ""
    echo "⚠️  Please edit infrastructure/bootstrap/terraform.tfvars and set your GitHub repository:"
    echo "   github_repository = \"your-username/your-repo-name\""
    echo ""
    read -p "Press Enter after you've updated the terraform.tfvars file..."
fi

# Initialize Terraform
echo "🔧 Initializing Terraform..."
terraform init

# Plan the deployment
echo "📋 Planning the deployment..."
terraform plan

# Ask for confirmation
echo ""
read -p "Do you want to apply these changes? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Deployment cancelled"
    exit 1
fi

# Apply the configuration
echo "🚀 Deploying OIDC configuration..."
terraform apply -auto-approve

echo ""
echo "✅ OIDC setup complete!"
echo ""
echo "📋 Next steps:"
echo "1. Copy the AWS_ROLE_TO_ASSUME value from the output above"
echo "2. Add it as a secret in your GitHub repository:"
echo "   - Go to your GitHub repository"
echo "   - Navigate to Settings > Secrets and variables > Actions"
echo "   - Click 'New repository secret'"
echo "   - Name: AWS_ROLE_TO_ASSUME"
echo "   - Value: [paste the role ARN from above]"
echo ""
echo "3. Your GitHub Actions workflows can now authenticate to AWS using OIDC!"
echo ""
echo "🔒 Security benefits:"
echo "   ✅ No long-lived credentials stored in GitHub"
echo "   ✅ Automatic token rotation"
echo "   ✅ Scoped permissions based on repository and branch"
echo ""