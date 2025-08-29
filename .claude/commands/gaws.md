---
description: Clean setup of AWS OIDC authentication with validation and GitHub secret configuration
allowed-tools: ["Read", "WebFetch", "Bash"]
---

1. Validate AWS environment variables: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are set, otherwise prompt user
2. Validate AWS account access with `aws sts get-caller-identity`
3. Remove existing GitHub secrets: `gh secret delete AWS_ROLE_TO_ASSUME` (ignore errors if not found)
4. Clean up previous infrastructure: remove existing terraform state in infrastructure/bootstrap/
5. Run clean OIDC setup: `./scripts/setup-oidc.sh` to create fresh infrastructure
6. Extract AWS_ROLE_TO_ASSUME value from terraform output
7. Add AWS_ROLE_TO_ASSUME as GitHub repository secret using `gh secret set`

Usage: /gaws