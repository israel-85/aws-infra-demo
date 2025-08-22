# Dynamic Backend Configuration

This directory uses a dynamic backend configuration approach that automatically adapts to different AWS accounts.

## How it works

1. **Template files**: Each environment has a `backend.hcl.template` file with placeholder values
2. **Dynamic generation**: The `init-terraform.sh` script generates actual `backend.hcl` files based on current AWS credentials
3. **Account-specific buckets**: S3 bucket names include the AWS account ID to ensure uniqueness

## Usage

### Initialize an environment

```bash
# Initialize staging environment
./scripts/init-terraform.sh staging

# Initialize production environment  
./scripts/init-terraform.sh production
```

### Manual initialization (if needed)

```bash
cd infrastructure/environments/staging

# Generate backend config manually
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
sed "s/{{ACCOUNT_ID}}/$ACCOUNT_ID/g" backend.hcl.template > backend.hcl

# Initialize with generated config
terraform init -backend-config="backend.hcl" -reconfigure
```

## Benefits

- **Account flexibility**: Automatically works with different AWS accounts
- **No hardcoded values**: Backend configuration adapts to current credentials
- **Unique bucket names**: Prevents conflicts between different deployments
- **Version controlled templates**: Templates are tracked in git, generated files are ignored

## Files

- `backend.tf`: Minimal backend configuration (version controlled)
- `backend.hcl.template`: Template with placeholders (version controlled)  
- `backend.hcl`: Generated configuration (ignored by git)

## Switching AWS Accounts

When switching to a different AWS account:

1. Update your AWS credentials
2. Run the bootstrap process to create infrastructure in the new account
3. Re-run `./scripts/init-terraform.sh <environment>` to update backend configuration
4. Terraform will automatically use the new account-specific buckets
