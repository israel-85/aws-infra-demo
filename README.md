# AWS Infrastructure Demo with Terraform and CI/CD

This repository demonstrates a complete AWS infrastructure setup using Terraform Infrastructure as Code (IaC) with a comprehensive CI/CD pipeline using GitHub Actions. The project includes a sample Nginx static application deployed to staging and production environments with automated testing, security scanning, and rollback capabilities.

## Architecture Overview

### Infrastructure Components

- **VPC** with public and private subnets across multiple availability zones
- **Application Load Balancer** distributing traffic to EC2 instances
- **EC2 instances** in Auto Scaling Groups for staging and production
- **Security Groups** implementing least privilege access
- **S3 buckets** for static assets and build artifacts
- **NAT Gateways** for outbound internet access from private subnets

### CI/CD Pipeline

- **Automated testing** on every code push with comprehensive test coverage
- **Security scanning** with tfsec and HTML validation
- **Automatic deployment** to staging on develop branch merge
- **Manual approval** required for production deployment with environment protection
- **Artifact storage** in S3 with SHA-based versioning and metadata tracking
- **Deployment metadata management** with status tracking (pending/success/failed)
- **Automatic rollback capabilities** triggered on deployment failures
- **Manual rollback workflows** for emergency recovery scenarios

## Project Structure

```text
├── infrastructure/           # Terraform Infrastructure as Code
│   ├── modules/             # Reusable Terraform modules
│   │   ├── networking/      # VPC, subnets, routing
│   │   ├── compute/         # EC2, ALB, Auto Scaling
│   │   ├── security/        # Security groups, IAM
│   │   ├── storage/         # S3 buckets
│   ├── environments/        # Environment-specific configurations
│   │   ├── staging/         # Staging environment
│   │   └── production/      # Production environment
│   └── shared/              # Shared variables and locals
├── .github/workflows/       # GitHub Actions CI/CD pipelines
├── app/                     # Sample Nginx static application
│   ├── src/                 # Application source code
│   ├── tests/               # Test suites
│   └── package.json         # Dependencies and scripts
├── scripts/                 # Deployment and utility scripts
└── README.md               # This file
```

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **AWS Account** with appropriate permissions for VPC, EC2, ALB, and S3
2. **AWS CLI** configured with credentials (for local development and setup)
3. **Terraform** >= 1.6.0 installed locally
4. **Docker** (optional) for local testing of containerized applications
5. **GitHub repository** with Actions enabled and environment protection configured
6. **GitHub Secrets** configured for AWS authentication

## Current Implementation Status

This project demonstrates a production-ready AWS infrastructure setup with:

- ✅ **Modular Terraform infrastructure** with networking, compute, security, and storage modules
- ✅ **Sample Nginx static application** with health endpoints and security headers
- ✅ **GitHub Actions CI/CD pipeline** with security scanning and automated deployment
- ✅ **Comprehensive test suites** (HTML validation, smoke tests) for static content validation
- ✅ **Deployment metadata management** with status tracking and audit trails
- ✅ **Automatic rollback automation** with failure detection and recovery workflows
- ✅ **Rollback validation scripts** for post-rollback verification and testing

## Initial Setup

### 1. Set Up GitHub OIDC Authentication

Instead of using long-lived AWS credentials, this project uses OpenID Connect (OIDC) for secure authentication between GitHub Actions and AWS.

First, configure your local AWS credentials for initial setup:

```bash
# Configure AWS CLI for local development
aws configure
```

Then deploy the bootstrap infrastructure to create the OIDC provider, IAM role, and Terraform state backend:

```bash
# Navigate to bootstrap directory
cd infrastructure/bootstrap

# Copy and configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and set your GitHub repository (e.g., "your-username/aws-infra-demo")

# Initialize and apply
terraform init
terraform apply
```

After deployment, add the outputted IAM role ARN to your GitHub repository secrets:

- Secret name: `AWS_ROLE_TO_ASSUME`
- Secret value: The ARN from terraform output (e.g., `arn:aws:iam::123456789012:role/aws-infra-demo-github-actions-role`)

**Note**: The bootstrap process automatically creates the Terraform state backend (S3 buckets and DynamoDB table), so no manual backend setup is required.

### 2. GitHub Actions Permissions

The CI/CD pipeline is configured with the following permissions:

- `id-token: write` - Required for JWT token handling and OIDC authentication
- `contents: read` - Required for repository checkout operations

These permissions enable secure authentication with AWS services and repository access during pipeline execution.


## Deployment Guide

### Manual Infrastructure Deployment

#### Bootstrap Setup (One-time)

Before deploying environments, set up the GitHub OIDC authentication:

**Option 1: Using the setup script (recommended)**

```bash
# Run the automated setup script
./scripts/setup-oidc.sh
```

**Option 2: Manual setup**

```bash
cd infrastructure/bootstrap

# Configure your repository
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your GitHub repository name

# Deploy OIDC provider and IAM role
terraform init
terraform apply

# Note the output role ARN and add it to GitHub secrets as AWS_ROLE_TO_ASSUME
```

#### Deploy Staging Environment

```bash
cd infrastructure/environments/staging

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply
```

#### Deploy Production Environment

```bash
cd infrastructure/environments/production

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply
```

### Automated Deployment via CI/CD

The CI/CD pipeline automatically handles deployments:

1. **Push to `develop` branch**: Triggers staging deployment
2. **Push to `main` branch**: Triggers production deployment (with approval)

## How the CI/CD Pipeline Works

### Pipeline Architecture

The CI/CD pipeline uses GitHub Actions with secure JWT-based authentication to AWS services. The workflow includes proper permissions management, comprehensive deployment tracking, and automatic failure recovery mechanisms.

### Pipeline Stages

1. **Test Stage**
   - Runs HTML validation and syntax checks
   - Validates static content structure
   - Uses lightweight validation tools for performance
   - Fails fast if tests don't pass

2. **Security Scan Stage**
   - Scans Terraform code with tfsec for security vulnerabilities
   - Validates HTML and static content for security issues
   - Runs in parallel with test stage for efficiency
   - Blocks deployment if critical issues are found

3. **Build Stage**
   - Builds the application and creates deployment artifacts
   - Creates compressed deployment packages with Git SHA versioning
   - Uploads artifacts to S3 for deployment and rollback purposes
   - Requires both test and security scan stages to pass

4. **Deploy Staging** (triggered by `develop` branch)
   - Uses GitHub environment protection for staging
   - Deploys infrastructure changes with Terraform 1.6.0
   - Deploys application to staging EC2 instances
   - **Creates deployment metadata** with pending status
   - Runs smoke tests to verify deployment health
   - **Updates deployment status** to success/failed based on results
   - **Triggers automatic rollback** if deployment fails

5. **Deploy Production** (triggered by `main` branch)
   - Requires manual approval through GitHub environment protection
   - Deploys infrastructure changes with validation
   - Deploys application to production EC2 instances
   - Runs comprehensive smoke tests
   - **Creates deployment metadata** with comprehensive tracking
   - Updates deployment records for rollback tracking
   - **Updates deployment status** with success/failure tracking
   - **Triggers automatic rollback** on any deployment failure

### Branch Strategy

- **Feature branches**: Create pull requests for code review
- **`develop` branch**: Automatically deploys to staging
- **`main` branch**: Automatically deploys to production (with approval)

### Environment Protection

Both staging and production environments are protected with:
- **GitHub environment protection rules** with required reviewers for production
- **Required status checks** ensuring all tests and security scans pass
- **Manual approval gates** for production deployments
- **Deployment history tracking** with Git SHA-based versioning
- **JWT-based authentication** for secure AWS service access
- **Artifact versioning** enabling reliable rollbacks
- **Deployment metadata management** tracking status, timestamps, and deployment details
- **Automatic failure detection** with immediate rollback triggers
- **Comprehensive audit trail** for all deployment activities

## Rollback Procedures

### Automatic Rollback

The CI/CD pipeline includes comprehensive automatic rollback capabilities:
- **Deployment failure detection** with immediate rollback triggers
- **Failed smoke tests** automatically trigger rollback workflows
- **Infrastructure validation failures** initiate recovery procedures
- **GitHub workflow dispatch** for seamless rollback automation
- **Deployment metadata tracking** enables precise rollback targeting

### Deployment Metadata Management

The system tracks comprehensive deployment metadata:

- **Deployment status tracking** (pending/success/failed)
- **Git SHA and version correlation** for precise rollback targeting
- **Artifact path tracking** for reliable deployment package retrieval
- **Timestamp and audit information** for deployment history
- **Automated status updates** throughout the deployment lifecycle

### Manual Rollback

#### Using Rollback Scripts

```bash
# List recent deployments with metadata
./scripts/deployment-metadata.sh list -e production

# Rollback to previous version
./scripts/rollback.sh -e production

# Rollback to specific version
./scripts/rollback.sh -e production -v v1.2.3

# Dry run rollback (preview actions)
./scripts/rollback.sh -e production --dry-run

# Validate rollback success
./scripts/rollback-validation.sh -e production -v v1.2.3
```

#### Application Rollback

```bash
# List recent deployments
aws s3 ls s3://aws-infra-demo-artifacts/deployments/

# Check deployment metadata
./scripts/deployment-metadata.sh list -e production

# Rollback to previous version
./scripts/rollback.sh production <previous-commit-sha>
```

#### Infrastructure Rollback

```bash
cd infrastructure/environments/production

# Revert to previous Terraform state
terraform plan -destroy -target=<resource-to-rollback>
terraform apply -target=<resource-to-rollback>
```

### Rollback Testing

Regular rollback drills are recommended:

```bash
# Test rollback procedure in staging
./scripts/test-rollback-scripts.sh

# Test rollback automation
./scripts/rollback.sh -e staging --dry-run
```

### CI/CD Pipeline Integration

The deployment pipeline includes comprehensive metadata tracking and automatic rollback capabilities:

#### Deployment Metadata Tracking

Every deployment creates detailed metadata records:

```bash
# Metadata is automatically created during deployment
./scripts/deployment-metadata.sh create \
  -e production \
  -v "main" \
  -s "abc123def456" \
  -a "builds/deployment-abc123def456.tar.gz" \
  -t pending

# Status is updated throughout the deployment lifecycle
./scripts/deployment-metadata.sh update \
  -e production \
  -v "main" \
  -t success
```

#### Automatic Rollback Triggers

The CI/CD pipeline automatically triggers rollbacks on:

- **Deployment failures** during infrastructure or application deployment
- **Failed smoke tests** after deployment completion
- **Health check failures** during post-deployment validation
- **Infrastructure validation errors** during Terraform apply

#### GitHub Workflow Dispatch Integration

Failed deployments automatically trigger the rollback workflow:

```yaml
# Automatic rollback trigger (built into CI/CD pipeline)
curl -X POST \
  -H "Authorization: token ${{ secrets.GITHUB_TOKEN }}" \
  https://api.github.com/repos/${{ github.repository }}/actions/workflows/rollback.yml/dispatches \
  -d '{
    "ref": "${{ github.ref }}",
    "inputs": {
      "environment": "production",
      "trigger_reason": "deployment_failure",
      "failed_version": "${{ github.ref_name }}"
    }
  }'
```

## Deployment Metadata and Artifact Management

### S3 Bucket Structure

The deployment and rollback system uses the following S3 structure:

```text
aws-infra-demo-artifacts/
├── builds/                          # Build artifacts from CI/CD
│   └── deployment-{git_sha}.tar.gz
├── deployments/
│   ├── staging/
│   │   ├── deployment-{git_sha}.tar.gz
│   │   └── metadata-{git_sha}.json
│   └── production/
│       ├── deployment-{git_sha}.tar.gz
│       ├── metadata-{git_sha}.json
│       └── production-current.txt   # Current deployment tracking
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

### Deployment Metadata Structure

Each deployment creates comprehensive metadata for tracking and rollback purposes:

```json
{
  "version": "main",
  "git_sha": "abc123def456",
  "environment": "production",
  "deployment_status": "success",
  "timestamp": "2024-01-15T10:30:00Z",
  "artifact_path": "builds/deployment-abc123def456.tar.gz",
  "deployed_by": "github-actions",
  "deployment_id": "550e8400-e29b-41d4-a716-446655440000",
  "checksum": "d41d8cd98f00b204e9800998ecf8427e",
  "metadata_version": "1.0",
  "status_updated_at": "2024-01-15T10:35:00Z",
  "status_updated_by": "github-actions"
}
```

### Deployment Metadata Management Commands

```bash
# Create deployment metadata
./scripts/deployment-metadata.sh create \
  -e production \
  -v "v1.2.3" \
  -s "abc123def456" \
  -a "builds/deployment-abc123def456.tar.gz" \
  -t pending

# Update deployment status
./scripts/deployment-metadata.sh update \
  -e production \
  -v "v1.2.3" \
  -t success

# List deployment history
./scripts/deployment-metadata.sh list -e production

# Clean up old metadata (keep last 30 days)
./scripts/deployment-metadata.sh cleanup -e production -d 30
```

### Security Configuration

- **No long-lived AWS credentials** stored in GitHub secrets  
- **JWT-based authentication** with short-lived tokens and automatic rotation
- **IAM roles** with least privilege access for all AWS services
- **Multi-factor authentication** for sensitive operations
- **Environment-specific access controls** with proper permission boundaries
- **Scoped permissions** based on repository and branch

### Network Security

- **Private subnets** for application servers
- **Security groups** with least privilege access
- **NACLs** for additional network-level security
- **VPC Flow Logs** for network monitoring

### CI/CD Security

- **JWT-based authentication** eliminates credential storage risks
- **Branch-based access control** through OIDC conditions
- **Environment protection rules** with required reviewers
- **Immutable deployment artifacts** with SHA-based versioning

### Security Scanning

- **Infrastructure scanning** with tfsec for Terraform security compliance
- **Static content validation** with HTML and configuration checks
- **JWT-based authentication** for secure CI/CD pipeline access
- **GitHub Actions permissions** following least privilege principles
- **Regular security assessments** integrated into the deployment pipeline
- **Automated security updates** through dependabot (recommended)
- **Audit logging** with AWS CloudTrail
- **Resource tagging** for governance and cost tracking

## Monitoring and Logging

### Application Monitoring

- **Health check endpoints** (`/health`, `/ready`) for load balancer integration with comprehensive metrics
- **Dedicated metrics endpoint** (`/metrics`) providing real-time application performance data
- **Request tracking** with automatic request counting and uptime monitoring
- **Error tracking** with centralized error counting and alerting capabilities
- **Nginx access logs** with structured logging for request monitoring
- **Static content serving** with optimized caching and compression
- **Performance metrics** including memory usage, CPU usage, and system resource monitoring
- **Deployment verification** through automated smoke tests

### Infrastructure Monitoring

- CloudWatch metrics for all AWS resources
- Auto Scaling based on CPU and memory usage
- Load balancer health checks
- Database performance monitoring

### Log Aggregation

- Centralized logging with CloudWatch Logs
- Log retention policies
- Log analysis and alerting
- Security event monitoring

## Cost Optimization

### Resource Optimization

- **Right-sizing** instances based on usage patterns
- **Auto Scaling** to handle traffic variations
- **Spot instances** for non-critical workloads
- **Reserved instances** for predictable workloads

### Storage Optimization

- **S3 lifecycle policies** for artifact retention
- **EBS volume optimization**
- **CloudFront** for static asset delivery
- **Data compression** and archiving

## Troubleshooting

### Common Issues

#### Terraform State Lock

```bash
# If state is locked, force unlock (use carefully)
terraform force-unlock <lock-id>
```

#### Deployment Failures

```bash
# Check GitHub Actions workflow logs
# Navigate to Actions tab in your GitHub repository

# Check deployment metadata and status
./scripts/deployment-metadata.sh list -e production

# View recent deployment artifacts
aws s3 ls s3://aws-infra-demo-artifacts/builds/ --recursive

# Check deployment metadata for specific version
./scripts/deployment-metadata.sh list -e production

# Check nginx logs on EC2 instances
aws logs tail /aws/ec2/aws-infra-demo/production --follow

# Validate current deployment
./scripts/rollback-validation.sh -e production -v $(git describe --tags --abbrev=0)
```

#### Application Issues

```bash
# Check nginx access and error logs
aws logs tail /aws/ec2/aws-infra-demo/production --follow

# Verify health endpoints with metrics
curl https://your-alb-dns/health
curl https://your-alb-dns/ready

# Check basic service metrics
curl https://your-alb-dns/metrics

# Check load balancer target health
aws elbv2 describe-target-health --target-group-arn <target-group-arn>

# Test static content endpoints
curl https://your-alb-dns/

# Test static content serving
# The main page serves a responsive HTML application

```

#### Deployment and Rollback Issues

```bash
# Check deployment metadata and history
./scripts/deployment-metadata.sh list -e production

# View specific deployment metadata
aws s3 cp s3://aws-infra-demo-artifacts/deployments/production/metadata-{git_sha}.json -

# Check rollback history
aws s3 ls s3://aws-infra-demo-artifacts/rollbacks/production/ --recursive

# Test rollback scripts
./scripts/test-rollback-scripts.sh

# Perform manual rollback
./scripts/rollback.sh -e production -v v1.2.3

# Validate rollback success
./scripts/rollback-validation.sh -e production -v v1.2.3

# Clean up old deployment metadata
./scripts/deployment-metadata.sh cleanup -e production -d 30
```


### Support and Maintenance

- **Regular updates** of dependencies and base images
- **Security patches** applied promptly
- **Performance monitoring** and optimization
- **Disaster recovery** procedures tested regularly

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Technology Stack

### Infrastructure

- **Terraform** 1.6.0 for Infrastructure as Code
- **AWS** as cloud provider (default region: us-east-1)
- **GitHub Actions** for CI/CD pipeline automation

### Application

- **Nginx** web server for static content delivery
- **Static HTML/CSS/JS** with responsive design and modern styling
- **Security headers**: X-Frame-Options, X-Content-Type-Options, X-XSS-Protection, Referrer-Policy
- **Application monitoring**: Health check endpoints for load balancer integration
- **Testing**: HTML validation and smoke tests for static content

### CI/CD Pipeline

- **GitHub Actions** with JWT-based authentication
- **tfsec** for Terraform security scanning
- **HTML validation** for static content verification
- **Codecov** for test coverage reporting

### AWS Services

- **VPC** with multi-AZ public/private subnets
- **Application Load Balancer** with health checks
- **EC2** with Auto Scaling Groups
- **S3** for artifacts and static assets
- **CloudWatch** for monitoring and logging

## Application Monitoring Endpoints

The application provides comprehensive monitoring capabilities through dedicated endpoints:

### Health Check Endpoint (`/health`)

Returns basic health information for load balancer integration:

- Service status
- Environment information
- Timestamp for monitoring freshness

```json
{
  "status": "healthy",
  "service": "nginx",
  "timestamp": "2024-01-15T10:30:00.000Z",
  "environment": "production"
}
```

### Ready Check Endpoint (`/ready`)

Lightweight endpoint for load balancer health checks:

```json
{
  "status": "ready",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

### Metrics Endpoint (`/metrics`)

Basic service metrics for monitoring:

```json
{
  "service": "nginx",
  "environment": "production",
  "timestamp": "2024-01-15T10:30:00.000Z",
  "status": "running"
}
```

### Monitoring Integration

- **Load Balancer Health Checks**: Uses `/ready` endpoint for fast health verification
- **Service Monitoring**: `/metrics` endpoint provides basic service status for monitoring
- **Access Logging**: Nginx access logs provide request tracking and analytics
- **Static Content Delivery**: Optimized serving of HTML, CSS, and JavaScript files


## Additional Resources

- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [AWS SDK for JavaScript](https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Nginx Security Best Practices](https://nginx.org/en/docs/http/ngx_http_ssl_module.html)
- [GitHub Environment Protection Rules](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)
