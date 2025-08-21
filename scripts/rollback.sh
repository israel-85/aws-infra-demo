#!/bin/bash

# Rollback automation script for AWS Infrastructure Demo
# This script handles rollback to previous successful deployments

set -euo pipefail

# Configuration
PROJECT_NAME="${PROJECT_NAME:-aws-infra-demo}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ARTIFACTS_BUCKET="${PROJECT_NAME}-artifacts"
LOG_FILE="/tmp/rollback-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# Function to show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Rollback automation script for AWS Infrastructure Demo

OPTIONS:
    -e, --environment ENVIRONMENT    Target environment (staging|production)
    -v, --version VERSION           Specific version to rollback to (optional)
    -l, --list                      List available versions for rollback
    -d, --dry-run                   Show what would be done without executing
    -h, --help                      Show this help message

EXAMPLES:
    $0 -e staging                   # Rollback staging to previous version
    $0 -e production -v v1.2.3      # Rollback production to specific version
    $0 -e staging --list            # List available versions for staging
    $0 -e production --dry-run      # Preview rollback actions for production

EOF
}

# Function to validate environment
validate_environment() {
    local env="$1"
    if [[ "$env" != "staging" && "$env" != "production" ]]; then
        error "Invalid environment: $env. Must be 'staging' or 'production'"
        exit 1
    fi
}

# Function to check AWS CLI and credentials
check_aws_setup() {
    log "Checking AWS CLI setup..."
    
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed"
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    success "AWS CLI setup verified"
}

# Function to get deployment history from S3
get_deployment_history() {
    local environment="$1"
    local limit="${2:-10}"
    
    log "Fetching deployment history for $environment environment..."
    
    # Get deployment artifacts from S3, sorted by last modified (newest first)
    aws s3api list-objects-v2 \
        --bucket "$ARTIFACTS_BUCKET" \
        --prefix "deployments/$environment/" \
        --query 'Contents[?contains(Key, `deployment-`) && contains(Key, `.tar.gz`)].[Key,LastModified,Size]' \
        --output table \
        --region "$AWS_REGION" \
        2>/dev/null || {
        error "Failed to fetch deployment history from S3"
        return 1
    }
}

# Function to get successful deployments from deployment metadata
get_successful_deployments() {
    local environment="$1"
    local limit="${2:-5}"
    
    log "Identifying successful deployments for $environment..."
    
    # Create temporary file for successful deployments
    local temp_file="/tmp/successful_deployments_$environment.json"
    
    # Get deployment metadata files
    aws s3 ls "s3://$ARTIFACTS_BUCKET/deployments/$environment/" \
        --recursive \
        --region "$AWS_REGION" | \
        grep "metadata.json" | \
        sort -k1,2 -r | \
        head -n "$limit" | \
        while read -r line; do
            local s3_key=$(echo "$line" | awk '{print $4}')
            local metadata_content
            
            # Download and check metadata
            if metadata_content=$(aws s3 cp "s3://$ARTIFACTS_BUCKET/$s3_key" - --region "$AWS_REGION" 2>/dev/null); then
                local status=$(echo "$metadata_content" | jq -r '.deployment_status // "unknown"')
                local version=$(echo "$metadata_content" | jq -r '.version // "unknown"')
                local timestamp=$(echo "$metadata_content" | jq -r '.timestamp // "unknown"')
                local git_sha=$(echo "$metadata_content" | jq -r '.git_sha // "unknown"')
                
                if [[ "$status" == "success" ]]; then
                    echo "$metadata_content" | jq -c ". + {s3_key: \"$s3_key\"}"
                fi
            fi
        done > "$temp_file"
    
    if [[ -s "$temp_file" ]]; then
        cat "$temp_file"
        rm -f "$temp_file"
        return 0
    else
        error "No successful deployments found for $environment"
        rm -f "$temp_file"
        return 1
    fi
}

# Function to list available versions for rollback
list_versions() {
    local environment="$1"
    
    log "Available versions for rollback in $environment environment:"
    echo
    
    local successful_deployments
    if successful_deployments=$(get_successful_deployments "$environment" 10); then
        echo "$successful_deployments" | jq -r '
            "Version: " + .version + 
            " | SHA: " + .git_sha[0:8] + 
            " | Date: " + .timestamp + 
            " | Status: " + .deployment_status
        ' | nl -w3 -s'. '
    else
        error "No successful deployments available for rollback"
        exit 1
    fi
}

# Function to get current deployment version
get_current_version() {
    local environment="$1"
    
    # Try to get current version from EC2 instances via tags or metadata
    local current_version
    current_version=$(aws ec2 describe-instances \
        --filters "Name=tag:Environment,Values=$environment" \
                  "Name=tag:Project,Values=$PROJECT_NAME" \
                  "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].Tags[?Key==`Version`].Value' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "unknown")
    
    if [[ "$current_version" == "None" || "$current_version" == "unknown" ]]; then
        warning "Could not determine current deployment version"
        return 1
    fi
    
    echo "$current_version"
}

# Function to select rollback target
select_rollback_target() {
    local environment="$1"
    local target_version="$2"
    
    local successful_deployments
    if ! successful_deployments=$(get_successful_deployments "$environment" 10); then
        error "No successful deployments available for rollback"
        exit 1
    fi
    
    if [[ -n "$target_version" ]]; then
        # Specific version requested
        local target_deployment
        target_deployment=$(echo "$successful_deployments" | jq -r "select(.version == \"$target_version\")")
        
        if [[ -z "$target_deployment" ]]; then
            error "Version $target_version not found in successful deployments"
            exit 1
        fi
        
        echo "$target_deployment"
    else
        # Get previous version (second most recent successful deployment)
        local current_version
        current_version=$(get_current_version "$environment" || echo "unknown")
        
        if [[ "$current_version" != "unknown" ]]; then
            # Skip current version and get the next one
            local target_deployment
            target_deployment=$(echo "$successful_deployments" | jq -r "select(.version != \"$current_version\")" | head -n1)
            
            if [[ -z "$target_deployment" ]]; then
                error "No previous version available for rollback"
                exit 1
            fi
            
            echo "$target_deployment"
        else
            # If we can't determine current version, use most recent successful
            echo "$successful_deployments" | head -n1
        fi
    fi
}

# Function to validate rollback target
validate_rollback_target() {
    local environment="$1"
    local target_deployment="$2"
    
    local version=$(echo "$target_deployment" | jq -r '.version')
    local git_sha=$(echo "$target_deployment" | jq -r '.git_sha')
    local artifact_path="deployments/$environment/deployment-$git_sha.tar.gz"
    
    log "Validating rollback target: $version ($git_sha)"
    
    # Check if artifact exists in S3
    if ! aws s3 head-object \
        --bucket "$ARTIFACTS_BUCKET" \
        --key "$artifact_path" \
        --region "$AWS_REGION" &>/dev/null; then
        error "Deployment artifact not found: s3://$ARTIFACTS_BUCKET/$artifact_path"
        return 1
    fi
    
    # Validate artifact integrity if checksum is available
    local expected_checksum=$(echo "$target_deployment" | jq -r '.checksum // empty')
    if [[ -n "$expected_checksum" ]]; then
        log "Validating artifact checksum..."
        local actual_checksum
        actual_checksum=$(aws s3api head-object \
            --bucket "$ARTIFACTS_BUCKET" \
            --key "$artifact_path" \
            --region "$AWS_REGION" \
            --query 'ETag' --output text | tr -d '"')
        
        if [[ "$actual_checksum" != "$expected_checksum" ]]; then
            error "Artifact checksum mismatch. Expected: $expected_checksum, Got: $actual_checksum"
            return 1
        fi
    fi
    
    success "Rollback target validation passed"
    return 0
}

# Function to perform health check
perform_health_check() {
    local environment="$1"
    local max_attempts="${2:-30}"
    local wait_time="${3:-10}"
    
    log "Performing health check for $environment environment..."
    
    # Get ALB DNS name
    local alb_dns
    alb_dns=$(aws elbv2 describe-load-balancers \
        --names "$PROJECT_NAME-$environment-alb" \
        --query 'LoadBalancers[0].DNSName' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [[ -z "$alb_dns" || "$alb_dns" == "None" ]]; then
        error "Could not find ALB DNS name for $environment"
        return 1
    fi
    
    local health_url="http://$alb_dns/health"
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        log "Health check attempt $attempt/$max_attempts..."
        
        if curl -f -s --max-time 10 "$health_url" >/dev/null 2>&1; then
            success "Health check passed"
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            log "Health check failed, waiting ${wait_time}s before retry..."
            sleep "$wait_time"
        fi
        
        ((attempt++))
    done
    
    error "Health check failed after $max_attempts attempts"
    return 1
}

# Function to execute rollback
execute_rollback() {
    local environment="$1"
    local target_deployment="$2"
    local dry_run="$3"
    
    local version=$(echo "$target_deployment" | jq -r '.version')
    local git_sha=$(echo "$target_deployment" | jq -r '.git_sha')
    local timestamp=$(echo "$target_deployment" | jq -r '.timestamp')
    
    log "Executing rollback to version $version (SHA: $git_sha) in $environment"
    log "Target deployment timestamp: $timestamp"
    
    if [[ "$dry_run" == "true" ]]; then
        log "DRY RUN MODE - No actual changes will be made"
        log "Would rollback $environment to:"
        echo "$target_deployment" | jq '.'
        return 0
    fi
    
    # Create rollback metadata
    local rollback_metadata
    rollback_metadata=$(cat << EOF
{
    "rollback_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "rollback_initiated_by": "$(whoami)",
    "target_version": "$version",
    "target_git_sha": "$git_sha",
    "target_deployment_timestamp": "$timestamp",
    "environment": "$environment",
    "rollback_reason": "Manual rollback via automation script"
}
EOF
)
    
    # Store rollback metadata
    local rollback_key="rollbacks/$environment/rollback-$(date +%Y%m%d-%H%M%S).json"
    echo "$rollback_metadata" | aws s3 cp - "s3://$ARTIFACTS_BUCKET/$rollback_key" --region "$AWS_REGION"
    
    # Download target deployment artifact
    local artifact_path="deployments/$environment/deployment-$git_sha.tar.gz"
    local local_artifact="/tmp/rollback-artifact-$git_sha.tar.gz"
    
    log "Downloading deployment artifact..."
    if ! aws s3 cp "s3://$ARTIFACTS_BUCKET/$artifact_path" "$local_artifact" --region "$AWS_REGION"; then
        error "Failed to download deployment artifact"
        return 1
    fi
    
    # Get Auto Scaling Group name
    local asg_name="$PROJECT_NAME-$environment-asg"
    
    # Get current instances in ASG
    local current_instances
    current_instances=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$asg_name" \
        --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' \
        --output text \
        --region "$AWS_REGION")
    
    if [[ -z "$current_instances" ]]; then
        error "No running instances found in Auto Scaling Group: $asg_name"
        return 1
    fi
    
    log "Found instances for rollback: $current_instances"
    
    # Deploy to each instance
    for instance_id in $current_instances; do
        log "Deploying rollback to instance: $instance_id"
        
        # Get instance IP
        local instance_ip
        instance_ip=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].PrivateIpAddress' \
            --output text \
            --region "$AWS_REGION")
        
        if [[ -z "$instance_ip" || "$instance_ip" == "None" ]]; then
            error "Could not get IP for instance: $instance_id"
            continue
        fi
        
        # Use Systems Manager to execute deployment on instance
        local command_id
        command_id=$(aws ssm send-command \
            --instance-ids "$instance_id" \
            --document-name "AWS-RunShellScript" \
            --parameters "commands=[
                'cd /opt/app',
                'sudo systemctl stop app',
                'sudo cp -r /opt/app /opt/app.backup.$(date +%Y%m%d-%H%M%S)',
                'wget -O /tmp/rollback-artifact.tar.gz \"https://$ARTIFACTS_BUCKET.s3.$AWS_REGION.amazonaws.com/$artifact_path\"',
                'sudo tar -xzf /tmp/rollback-artifact.tar.gz -C /opt/app --strip-components=1',
                'sudo chown -R app:app /opt/app',
                'sudo systemctl start app',
                'rm -f /tmp/rollback-artifact.tar.gz'
            ]" \
            --region "$AWS_REGION" \
            --query 'Command.CommandId' \
            --output text)
        
        if [[ -z "$command_id" ]]; then
            error "Failed to send rollback command to instance: $instance_id"
            continue
        fi
        
        log "Waiting for rollback deployment on instance: $instance_id (Command: $command_id)"
        
        # Wait for command completion
        local max_wait=300  # 5 minutes
        local wait_count=0
        while [[ $wait_count -lt $max_wait ]]; do
            local command_status
            command_status=$(aws ssm get-command-invocation \
                --command-id "$command_id" \
                --instance-id "$instance_id" \
                --query 'Status' \
                --output text \
                --region "$AWS_REGION" 2>/dev/null || echo "InProgress")
            
            if [[ "$command_status" == "Success" ]]; then
                success "Rollback completed on instance: $instance_id"
                break
            elif [[ "$command_status" == "Failed" ]]; then
                error "Rollback failed on instance: $instance_id"
                # Get command output for debugging
                aws ssm get-command-invocation \
                    --command-id "$command_id" \
                    --instance-id "$instance_id" \
                    --query 'StandardErrorContent' \
                    --output text \
                    --region "$AWS_REGION" | head -20
                return 1
            fi
            
            sleep 5
            ((wait_count += 5))
        done
        
        if [[ $wait_count -ge $max_wait ]]; then
            error "Rollback timed out on instance: $instance_id"
            return 1
        fi
    done
    
    # Update instance tags with new version
    for instance_id in $current_instances; do
        aws ec2 create-tags \
            --resources "$instance_id" \
            --tags "Key=Version,Value=$version" "Key=GitSHA,Value=$git_sha" \
            --region "$AWS_REGION" || warning "Failed to update tags for instance: $instance_id"
    done
    
    # Cleanup
    rm -f "$local_artifact"
    
    success "Rollback deployment completed"
    return 0
}

# Function to run rollback validation tests
run_rollback_validation() {
    local environment="$1"
    local target_version="$2"
    
    log "Running rollback validation tests for $environment (version: $target_version)..."
    
    # Perform health check
    if ! perform_health_check "$environment" 20 15; then
        error "Health check failed during rollback validation"
        return 1
    fi
    
    # Run smoke tests if available
    if [[ -f "app/tests/smoke/deployment.test.js" ]]; then
        log "Running smoke tests..."
        
        # Set environment variables for tests
        export NODE_ENV="$environment"
        export TARGET_VERSION="$target_version"
        
        if (cd app && npm run test:smoke); then
            success "Smoke tests passed"
        else
            error "Smoke tests failed"
            return 1
        fi
    fi
    
    # Validate application endpoints
    local alb_dns
    alb_dns=$(aws elbv2 describe-load-balancers \
        --names "$PROJECT_NAME-$environment-alb" \
        --query 'LoadBalancers[0].DNSName' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [[ -n "$alb_dns" && "$alb_dns" != "None" ]]; then
        log "Validating application endpoints..."
        
        # Test health endpoint
        if curl -f -s --max-time 10 "http://$alb_dns/health" | jq -e '.status == "healthy"' >/dev/null; then
            success "Health endpoint validation passed"
        else
            error "Health endpoint validation failed"
            return 1
        fi
        
        # Test ready endpoint
        if curl -f -s --max-time 10 "http://$alb_dns/ready" | jq -e '.status == "ready"' >/dev/null; then
            success "Ready endpoint validation passed"
        else
            error "Ready endpoint validation failed"
            return 1
        fi
    fi
    
    success "Rollback validation completed successfully"
    return 0
}

# Main function
main() {
    local environment=""
    local target_version=""
    local list_versions_flag=false
    local dry_run=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                environment="$2"
                shift 2
                ;;
            -v|--version)
                target_version="$2"
                shift 2
                ;;
            -l|--list)
                list_versions_flag=true
                shift
                ;;
            -d|--dry-run)
                dry_run=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "$environment" ]]; then
        error "Environment is required"
        usage
        exit 1
    fi
    
    validate_environment "$environment"
    check_aws_setup
    
    log "Starting rollback automation for $environment environment"
    log "Log file: $LOG_FILE"
    
    # Handle list versions request
    if [[ "$list_versions_flag" == true ]]; then
        list_versions "$environment"
        exit 0
    fi
    
    # Select rollback target
    local target_deployment
    if ! target_deployment=$(select_rollback_target "$environment" "$target_version"); then
        error "Failed to select rollback target"
        exit 1
    fi
    
    local selected_version=$(echo "$target_deployment" | jq -r '.version')
    local selected_sha=$(echo "$target_deployment" | jq -r '.git_sha')
    
    log "Selected rollback target: $selected_version (SHA: $selected_sha)"
    
    # Validate rollback target
    if ! validate_rollback_target "$environment" "$target_deployment"; then
        error "Rollback target validation failed"
        exit 1
    fi
    
    # Confirm rollback (unless dry run)
    if [[ "$dry_run" != true ]]; then
        echo
        warning "This will rollback $environment environment to version $selected_version"
        warning "Current running applications will be replaced with the selected version"
        echo
        read -p "Are you sure you want to proceed? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log "Rollback cancelled by user"
            exit 0
        fi
    fi
    
    # Execute rollback
    if ! execute_rollback "$environment" "$target_deployment" "$dry_run"; then
        error "Rollback execution failed"
        exit 1
    fi
    
    # Skip validation for dry run
    if [[ "$dry_run" == true ]]; then
        success "Dry run completed successfully"
        exit 0
    fi
    
    # Run validation tests
    if ! run_rollback_validation "$environment" "$selected_version"; then
        error "Rollback validation failed"
        warning "Consider investigating the deployment or performing another rollback"
        exit 1
    fi
    
    success "Rollback completed successfully!"
    success "Environment: $environment"
    success "Version: $selected_version"
    success "SHA: $selected_sha"
    success "Log file: $LOG_FILE"
}

# Run main function with all arguments
main "$@"