#!/bin/bash

# Script to initialize Terraform with dynamic backend configuration
# Usage: ./scripts/init-terraform.sh <environment>

set -e

ENVIRONMENT=${1:-staging}
SCRIPT_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT=""
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_DIR="$PROJECT_ROOT/infrastructure/environments/$ENVIRONMENT"

if [ ! -d "$ENV_DIR" ]; then
    echo "Error: Environment directory $ENV_DIR does not exist"
    exit 1
fi

# Get current AWS account ID
echo "Getting current AWS account ID..."
ACCOUNT_ID=""
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

if [ -z "$ACCOUNT_ID" ]; then
    echo "Error: Could not retrieve AWS account ID. Please check your AWS credentials."
    exit 1
fi

echo "AWS Account ID: $ACCOUNT_ID"
echo "Environment: $ENVIRONMENT"

# Generate backend configuration from template
TEMPLATE_FILE="$ENV_DIR/backend.hcl.template"
BACKEND_FILE="$ENV_DIR/backend.hcl"

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: Template file $TEMPLATE_FILE does not exist"
    exit 1
fi

echo "Generating backend configuration..."
sed "s/{{ACCOUNT_ID}}/$ACCOUNT_ID/g" "$TEMPLATE_FILE" > "$BACKEND_FILE"

echo "Generated backend configuration:"
cat "$BACKEND_FILE"

# Initialize Terraform with the generated backend configuration
echo "Initializing Terraform..."
cd "$ENV_DIR"
terraform init -backend-config="backend.hcl" -reconfigure

echo "Terraform initialization complete for $ENVIRONMENT environment"
