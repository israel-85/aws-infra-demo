#!/bin/bash

# Application deployment script for AWS Infrastructure Demo
# This script handles deployment of application artifacts to EC2 instances

set -euo pipefail

# Configuration
PROJECT_NAME="${PROJECT_NAME:-aws-infra-demo}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ARTIFACTS_BUCKET="${PROJECT_NAME}-artifacts"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to show usage
usage() {
    cat << EOF
Usage: $0 ENVIRONMENT GIT_SHA

Deploy application to specified environment

ARGUMENTS:
    ENVIRONMENT    Target environment (staging|production)
    GIT_SHA        Git commit SHA of the deployment artifact

EXAMPLES:
    $0 staging abc123def456
    $0 production v1.2.3-abc123

EOF
}

# Function to validate inputs
validate_inputs() {
    local environment="$1"
    local git_sha="$2"
    
    if [[ "$environment" != "staging" && "$environment" != "production" ]]; then
        error "Invalid environment: $environment. Must be 'staging' or 'production'"
        exit 1
    fi
    
    if [[ -z "$git_sha" ]]; then
        error "Git SHA is required"
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking deployment prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Check required tools
    for tool in jq curl; do
        if ! command -v "$tool" &> /dev/null; then
            error "$tool is not installed"
            exit 1
        fi
    done
    
    success "Prerequisites check passed"
}

# Function to get target instances
get_target_instances() {
    local environment="$1"
    
    log "Getting target instances for $environment environment..."
    
    local asg_name="$PROJECT_NAME-$environment-asg"
    local instances
    
    instances=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$asg_name" \
        --query $'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [[ -z "$instances" ]]; then
        error "No running instances found in Auto Scaling Group: $asg_name"
        exit 1
    fi
    
    log "Found instances: $instances"
    echo "$instances"
}

# Function to deploy to instance
deploy_to_instance() {
    local instance_id="$1"
    local artifact_path="$2"
    local environment="$3"
    local git_sha="$4"
    
    log "Deploying to instance: $instance_id"
    
    # Create deployment commands
    local deployment_commands=(
        "echo 'Starting nginx deployment on instance $instance_id'"
        "sudo /opt/deploy.sh 'https://$ARTIFACTS_BUCKET.s3.$AWS_REGION.amazonaws.com/$artifact_path' '$environment'"
        "echo 'Deployment completed on instance $instance_id'"
    )
    
    # Convert commands to JSON array for SSM
    local commands_json
    commands_json=$(printf '%s\n' "${deployment_commands[@]}" | jq -R . | jq -s .)
    
    # Send deployment command via SSM
    local command_id
    command_id=$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name "AWS-RunShellScript" \
        --parameters "commands=$commands_json" \
        --region "$AWS_REGION" \
        --query 'Command.CommandId' \
        --output text)
    
    if [[ -z "$command_id" ]]; then
        error "Failed to send deployment command to instance: $instance_id"
        return 1
    fi
    
    log "Deployment command sent to instance $instance_id (Command ID: $command_id)"
    
    # Wait for command completion
    local max_wait=600  # 10 minutes
    local wait_count=0
    
    while [[ $wait_count -lt $max_wait ]]; do
        local command_status
        command_status=$(aws ssm get-command-invocation \
            --command-id "$command_id" \
            --instance-id "$instance_id" \
            --query 'Status' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "InProgress")
        
        case "$command_status" in
            "Success")
                success "Deployment completed successfully on instance: $instance_id"
                return 0
                ;;
            "Failed")
                error "Deployment failed on instance: $instance_id"
                # Get error details
                aws ssm get-command-invocation \
                    --command-id "$command_id" \
                    --instance-id "$instance_id" \
                    --query 'StandardErrorContent' \
                    --output text \
                    --region "$AWS_REGION" 2>/dev/null | head -10
                return 1
                ;;
            "Cancelled")
                error "Deployment was cancelled on instance: $instance_id"
                return 1
                ;;
            "InProgress"|"Pending")
                if [[ $((wait_count % 30)) -eq 0 ]]; then
                    log "Deployment in progress on instance $instance_id (${wait_count}s elapsed)..."
                fi
                ;;
        esac
        
        sleep 5
        ((wait_count += 5))
    done
    
    error "Deployment timed out on instance: $instance_id"
    return 1
}

# Function to update instance tags
update_instance_tags() {
    local instance_id="$1"
    local environment="$2"
    local git_sha="$3"
    local version="$4"
    
    log "Updating tags for instance: $instance_id"
    
    aws ec2 create-tags \
        --resources "$instance_id" \
        --tags \
            "Key=Version,Value=$version" \
            "Key=GitSHA,Value=$git_sha" \
            "Key=DeploymentTimestamp,Value=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --region "$AWS_REGION" || warning "Failed to update tags for instance: $instance_id"
}

# Function to perform health check
perform_health_check() {
    local environment="$1"
    local max_attempts="${2:-20}"
    local wait_time="${3:-15}"
    
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
            
            # Validate health response
            local health_response
            if health_response=$(curl -f -s --max-time 10 "$health_url" 2>/dev/null); then
                local health_status
                health_status=$(echo "$health_response" | jq -r '.status // "unknown"')
                if [[ "$health_status" == "healthy" ]]; then
                    success "Application is healthy"
                    return 0
                fi
            fi
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

# Main deployment function
main() {
    local environment="$1"
    local git_sha="$2"
    local version="${3:-$git_sha}"
    
    log "Starting deployment to $environment environment"
    log "Git SHA: $git_sha"
    log "Version: $version"
    
    validate_inputs "$environment" "$git_sha"
    check_prerequisites
    
    # Verify artifact exists
    local artifact_path="builds/deployment-$git_sha.tar.gz"
    if ! aws s3 head-object \
        --bucket "$ARTIFACTS_BUCKET" \
        --key "$artifact_path" \
        --region "$AWS_REGION" &>/dev/null; then
        error "Deployment artifact not found: s3://$ARTIFACTS_BUCKET/$artifact_path"
        exit 1
    fi
    
    success "Deployment artifact verified: s3://$ARTIFACTS_BUCKET/$artifact_path"
    
    # Get target instances
    local instances
    instances=$(get_target_instances "$environment")
    
    # Deploy to each instance
    local deployment_success=true
    local successful_instances=()
    local failed_instances=()
    
    for instance_id in $instances; do
        if deploy_to_instance "$instance_id" "$artifact_path" "$environment" "$git_sha"; then
            successful_instances+=("$instance_id")
            update_instance_tags "$instance_id" "$environment" "$git_sha" "$version"
        else
            failed_instances+=("$instance_id")
            deployment_success=false
        fi
    done
    
    # Report deployment results
    if [[ ${#successful_instances[@]} -gt 0 ]]; then
        success "Deployment succeeded on instances: ${successful_instances[*]}"
    fi
    
    if [[ ${#failed_instances[@]} -gt 0 ]]; then
        error "Deployment failed on instances: ${failed_instances[*]}"
    fi
    
    # Perform health check
    if [[ "$deployment_success" == true ]]; then
        if perform_health_check "$environment"; then
            success "Deployment completed successfully!"
            success "Environment: $environment"
            success "Version: $version"
            success "SHA: $git_sha"
            exit 0
        else
            error "Deployment completed but health check failed"
            exit 1
        fi
    else
        error "Deployment failed on one or more instances"
        exit 1
    fi
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    if [[ $# -lt 2 ]]; then
        usage
        exit 1
    fi
    
    main "$@"
fi