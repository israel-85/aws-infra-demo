# Rollback Automation Scripts

This directory contains comprehensive rollback automation scripts for the AWS Infrastructure Demo project. These scripts provide automated rollback capabilities with validation and testing procedures.

## Scripts Overview

### 1. `rollback.sh` - Main Rollback Automation Script

The primary script for performing automated rollbacks to previous successful deployments.

**Features:**

- Identifies previous successful deployments from S3 metadata
- Supports rollback to specific versions or automatic previous version selection
- Performs deployment validation and health checks
- Includes dry-run mode for testing rollback procedures
- Comprehensive logging and error handling

**Usage:**

```bash
# Rollback staging to previous version
./scripts/rollback.sh -e staging

# Rollback production to specific version
./scripts/rollback.sh -e production -v v1.2.3

# List available versions for rollback
./scripts/rollback.sh -e staging --list

# Dry run to preview rollback actions
./scripts/rollback.sh -e production --dry-run

# Show help
./scripts/rollback.sh --help
```

### 2. `deployment-metadata.sh` - Deployment Metadata Management

Manages deployment metadata required for rollback operations.

**Features:**

- Creates deployment metadata with version, SHA, and artifact information
- Updates deployment status (pending, success, failed)
- Lists deployment history
- Cleans up old metadata files

**Usage:**

```bash
# Create deployment metadata
./scripts/deployment-metadata.sh create -e staging -v v1.2.3 -s abc123 -a deployments/staging/deployment-abc123.tar.gz

# Update deployment status
./scripts/deployment-metadata.sh update -e staging -v v1.2.3 -t success

# List deployment history
./scripts/deployment-metadata.sh list -e production

# Cleanup old metadata (keep last 30 days)
./scripts/deployment-metadata.sh cleanup -e staging -d 30
```

### 3. `rollback-validation.sh` - Post-Rollback Validation

Comprehensive validation script to verify rollback success.

**Features:**

- Validates infrastructure state (ASG, ALB, instances)
- Performs application health checks
- Runs automated test suites
- Validates rollback metadata
- Generates validation reports

**Usage:**

```bash
# Validate rollback to specific version
./scripts/rollback-validation.sh -e staging -v v1.2.3

# Validate with custom timeout
./scripts/rollback-validation.sh -e production -v v1.1.0 -t 600

# Skip automated tests
./scripts/rollback-validation.sh -e staging -v v1.2.3 --skip-tests
```

## Prerequisites

### Required Tools

- AWS CLI v2 (configured with appropriate credentials)
- `jq` for JSON processing
- `curl` for HTTP requests
- `uuidgen` for generating unique IDs
- Node.js and npm (for running automated tests)

### AWS Permissions

The scripts require the following AWS permissions:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:ListBucket",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::aws-infra-demo-artifacts",
                "arn:aws:s3:::aws-infra-demo-artifacts/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "autoscaling:DescribeAutoScalingGroups",
                "ec2:DescribeInstances",
                "ec2:CreateTags",
                "elbv2:DescribeLoadBalancers",
                "elbv2:DescribeTargetGroups",
                "elbv2:DescribeTargetHealth",
                "ssm:SendCommand",
                "ssm:GetCommandInvocation"
            ],
            "Resource": "*"
        }
    ]
}
```

### Environment Variables

Set these environment variables for customization:

```bash
export PROJECT_NAME="aws-infra-demo"
export AWS_REGION="us-east-1"
```

## Rollback Process Flow

### 1. Pre-Rollback Validation

- Verify AWS credentials and permissions
- Check target environment exists
- Validate rollback target availability
- Confirm artifact integrity

### 2. Rollback Execution

- Download target deployment artifact
- Deploy to Auto Scaling Group instances via SSM
- Update instance tags with new version
- Create rollback metadata record

### 3. Post-Rollback Validation

- Verify infrastructure state
- Perform application health checks
- Run automated test suites
- Generate validation report

## Deployment Metadata Structure

The scripts use structured metadata stored in S3 to track deployments:

```json
{
    "version": "v1.2.3",
    "git_sha": "abc123def456",
    "environment": "staging",
    "deployment_status": "success",
    "timestamp": "2024-01-15T10:30:00Z",
    "artifact_path": "deployments/staging/deployment-abc123def456.tar.gz",
    "deployed_by": "github-actions",
    "deployment_id": "550e8400-e29b-41d4-a716-446655440000",
    "checksum": "d41d8cd98f00b204e9800998ecf8427e",
    "metadata_version": "1.0"
}
```

## S3 Bucket Structure

The rollback system uses the following S3 structure:

```text
aws-infra-demo-artifacts/
├── deployments/
│   ├── staging/
│   │   ├── deployment-{git_sha}.tar.gz
│   │   └── metadata-{git_sha}.json
│   └── production/
│       ├── deployment-{git_sha}.tar.gz
│       └── metadata-{git_sha}.json
├── rollbacks/
│   ├── staging/
│   │   └── rollback-{timestamp}.json
│   └── production/
│       └── rollback-{timestamp}.json
└── validation-reports/
    ├── staging/
    │   └── rollback-validation-{timestamp}.json
    └── production/
        └── rollback-validation-{timestamp}.json
```

## Integration with CI/CD Pipeline

### GitHub Actions Integration

Add the following to your GitHub Actions workflow for automated rollback capabilities:

```yaml
rollback-staging:
  if: failure()
  needs: [deploy-staging]
  runs-on: ubuntu-latest
  steps:
    - name: Checkout
      uses: actions/checkout@v4
    
    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
        aws-region: us-east-1
    
    - name: Rollback staging deployment
      run: |
        chmod +x scripts/rollback.sh
        ./scripts/rollback.sh -e staging
    
    - name: Validate rollback
      run: |
        chmod +x scripts/rollback-validation.sh
        ./scripts/rollback-validation.sh -e staging -v $(git describe --tags --abbrev=0)
```

### Manual Rollback Trigger

Create a manual workflow for emergency rollbacks:

```yaml
name: Manual Rollback
on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to rollback'
        required: true
        type: choice
        options:
          - staging
          - production
      version:
        description: 'Target version (leave empty for previous)'
        required: false
        type: string

jobs:
  rollback:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-east-1
      
      - name: Execute rollback
        run: |
          chmod +x scripts/rollback.sh
          if [ -n "${{ github.event.inputs.version }}" ]; then
            ./scripts/rollback.sh -e ${{ github.event.inputs.environment }} -v ${{ github.event.inputs.version }}
          else
            ./scripts/rollback.sh -e ${{ github.event.inputs.environment }}
          fi
      
      - name: Validate rollback
        run: |
          chmod +x scripts/rollback-validation.sh
          VERSION="${{ github.event.inputs.version }}"
          if [ -z "$VERSION" ]; then
            VERSION=$(git describe --tags --abbrev=0)
          fi
          ./scripts/rollback-validation.sh -e ${{ github.event.inputs.environment }} -v "$VERSION"
```

## Troubleshooting

### Common Issues

1. **AWS Credentials Not Found**

   ```bash
   aws configure list
   aws sts get-caller-identity
   ```

2. **S3 Bucket Access Denied**
   - Verify bucket exists and permissions are correct
   - Check bucket policy and IAM roles

3. **SSM Command Failures**
   - Ensure EC2 instances have SSM agent installed
   - Verify IAM instance profile has SSM permissions

4. **Health Check Failures**
   - Check ALB target group health
   - Verify security group rules
   - Check application logs

### Debug Mode

Enable debug mode for detailed logging:

```bash
export DEBUG=1
./scripts/rollback.sh -e staging
```

### Log Files

All scripts generate detailed log files in `/tmp/`:

- `rollback-{timestamp}.log` - Main rollback operations
- `rollback-validation-{environment}-{timestamp}.json` - Validation reports

## Security Considerations

1. **Least Privilege Access**: Scripts use minimal required AWS permissions
2. **Audit Trail**: All operations are logged and stored in S3
3. **Validation**: Comprehensive validation before and after rollback
4. **Metadata Integrity**: Checksum validation for deployment artifacts
5. **Access Control**: S3 bucket policies restrict access to authorized users

## Monitoring and Alerting

Consider setting up CloudWatch alarms for:

- Failed rollback operations
- Health check failures post-rollback
- Unusual rollback frequency
- S3 bucket access patterns

## Best Practices

1. **Test Rollback Procedures**: Regularly test rollback scripts in staging
2. **Keep Metadata Current**: Ensure deployment metadata is always updated
3. **Monitor Artifact Storage**: Implement lifecycle policies for old artifacts
4. **Document Rollback Reasons**: Include reason in rollback metadata
5. **Validate Before Production**: Always validate rollbacks in staging first
6. **Backup Before Rollback**: Scripts automatically create backups
7. **Monitor Post-Rollback**: Watch metrics and logs after rollback completion

## Support

For issues or questions about the rollback automation scripts:

1. Check the troubleshooting section above
2. Review log files for detailed error information
3. Verify AWS permissions and configuration
4. Test in staging environment first