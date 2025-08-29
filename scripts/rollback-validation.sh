#!/bin/bash

# Rollback validation and testing script
# This script performs comprehensive validation after rollback operations

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
Usage: $0 [OPTIONS]

Rollback validation and testing script

OPTIONS:
    -e, --environment ENVIRONMENT    Target environment (staging|production)
    -v, --version VERSION           Expected version after rollback
    -t, --timeout TIMEOUT          Timeout for validation tests (default: 300s)
    -s, --skip-tests               Skip automated test execution
    -h, --help                     Show this help message

EXAMPLES:
    $0 -e staging -v v1.2.3                    # Validate staging rollback to v1.2.3
    $0 -e production -v v1.1.0 --skip-tests    # Validate production rollback, skip tests

EOF
}

# Function to validate infrastructure state
validate_infrastructure() {
    local environment="$1"
    local expected_version="$2"
    
    log "Validating infrastructure state for $environment environment..."
    
    # Check Auto Scaling Group
    local asg_name="$PROJECT_NAME-$environment-asg"
    local asg_status
    asg_status=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$asg_name" \
        --query 'AutoScalingGroups[0].{DesiredCapacity:DesiredCapacity,MinSize:MinSize,MaxSize:MaxSize,HealthCheckType:HealthCheckType}' \
        --output json \
        --region "$AWS_REGION" 2>/dev/null || echo "{}")
    
    if [[ "$asg_status" == "{}" ]]; then
        error "Auto Scaling Group not found: $asg_name"
        return 1
    fi
    
    local desired_capacity
    desired_capacity=$(echo "$asg_status" | jq -r '.DesiredCapacity // 0')
    local health_check_type
    health_check_type=$(echo "$asg_status" | jq -r '.HealthCheckType // "unknown"')
    
    log "ASG Status - Desired Capacity: $desired_capacity, Health Check: $health_check_type"
    
    # Check running instances
    local running_instances
    running_instances=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$asg_name" \
        --query $'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' \
        --output text \
        --region "$AWS_REGION")
    
    local instance_count
    instance_count=$(echo "$running_instances" | wc -w)
    
    if [[ $instance_count -eq 0 ]]; then
        error "No running instances found in ASG"
        return 1
    fi
    
    log "Found $instance_count running instances"
    
    # Validate instance versions
    local version_mismatch=false
    for instance_id in $running_instances; do
        local instance_version
        instance_version=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query $'Reservations[0].Instances[0].Tags[?Key==`Version`].Value' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "unknown")
        
        if [[ "$instance_version" != "$expected_version" ]]; then
            warning "Instance $instance_id has version $instance_version, expected $expected_version"
            version_mismatch=true
        else
            log "Instance $instance_id version validated: $instance_version"
        fi
    done
    
    if [[ "$version_mismatch" == true ]]; then
        error "Version mismatch detected on some instances"
        return 1
    fi
    
    # Check Load Balancer
    local alb_name="$PROJECT_NAME-$environment-alb"
    local alb_status
    alb_status=$(aws elbv2 describe-load-balancers \
        --names "$alb_name" \
        --query 'LoadBalancers[0].{State:State.Code,DNSName:DNSName}' \
        --output json \
        --region "$AWS_REGION" 2>/dev/null || echo "{}")
    
    if [[ "$alb_status" == "{}" ]]; then
        error "Application Load Balancer not found: $alb_name"
        return 1
    fi
    
    local alb_state
    alb_state=$(echo "$alb_status" | jq -r '.State // "unknown"')
    local alb_dns
    alb_dns=$(echo "$alb_status" | jq -r '.DNSName // "unknown"')
    
    if [[ "$alb_state" != "active" ]]; then
        error "ALB is not active. Current state: $alb_state"
        return 1
    fi
    
    log "ALB Status: $alb_state, DNS: $alb_dns"
    
    # Check target group health
    local target_groups
    target_groups=$(aws elbv2 describe-target-groups \
        --names "$PROJECT_NAME-$environment-tg" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [[ -n "$target_groups" && "$target_groups" != "None" ]]; then
        local healthy_targets
        healthy_targets=$(aws elbv2 describe-target-health \
            --target-group-arn "$target_groups" \
            --query $'TargetHealthDescriptions[?TargetHealth.State==`healthy`].Target.Id' \
            --output text \
            --region "$AWS_REGION" | wc -w)
        
        log "Healthy targets in target group: $healthy_targets"
        
        if [[ $healthy_targets -eq 0 ]]; then
            error "No healthy targets in target group"
            return 1
        fi
    fi
    
    success "Infrastructure validation passed"
    return 0
}

# Function to validate application health
validate_application_health() {
    local environment="$1"
    local timeout="${2:-300}"
    
    log "Validating application health for $environment environment..."
    
    # Get ALB DNS name
    local alb_dns
    alb_dns=$(aws elbv2 describe-load-balancers \
        --names "$PROJECT_NAME-$environment-alb" \
        --query 'LoadBalancers[0].DNSName' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [[ -z "$alb_dns" || "$alb_dns" == "None" ]]; then
        error "Could not find ALB DNS name"
        return 1
    fi
    
    local base_url="http://$alb_dns"
    local start_time
    start_time=$(date +%s)
    local end_time
    end_time=$((start_time + timeout))
    
    # Test health endpoint
    log "Testing health endpoint: $base_url/health"
    while [[ $(date +%s) -lt $end_time ]]; do
        if curl -f -s --max-time 10 "$base_url/health" >/dev/null 2>&1; then
            success "Health endpoint is responding"
            break
        fi
        
        log "Health endpoint not ready, waiting..."
        sleep 10
    done
    
    # Validate health response
    local health_response
    if health_response=$(curl -f -s --max-time 10 "$base_url/health" 2>/dev/null); then
        local health_status
        health_status=$(echo "$health_response" | jq -r '.status // "unknown"')
        local app_version
        app_version=$(echo "$health_response" | jq -r '.version // "unknown"')
        
        if [[ "$health_status" == "healthy" ]]; then
            success "Health check passed - Status: $health_status, Version: $app_version"
        else
            error "Health check failed - Status: $health_status"
            return 1
        fi
    else
        error "Failed to get health response"
        return 1
    fi
    
    # Test ready endpoint
    log "Testing ready endpoint: $base_url/ready"
    local ready_response
    if ready_response=$(curl -f -s --max-time 10 "$base_url/ready" 2>/dev/null); then
        local ready_status
        ready_status=$(echo "$ready_response" | jq -r '.status // "unknown"')
        
        if [[ "$ready_status" == "ready" ]]; then
            success "Ready check passed - Status: $ready_status"
        else
            error "Ready check failed - Status: $ready_status"
            return 1
        fi
    else
        error "Failed to get ready response"
        return 1
    fi
    
    # Test basic functionality endpoints
    log "Testing basic application endpoints..."
    
    # Test root endpoint
    if curl -f -s --max-time 10 "$base_url/" >/dev/null 2>&1; then
        success "Root endpoint is accessible"
    else
        warning "Root endpoint is not accessible (may be expected)"
    fi
    
    success "Application health validation passed"
    return 0
}

# Function to run automated tests
run_automated_tests() {
    local environment="$1"
    local expected_version="$2"
    
    log "Running automated tests for $environment environment..."
    
    # Set environment variables for tests
    export NODE_ENV="$environment"
    export TARGET_VERSION="$expected_version"
    export TEST_ENVIRONMENT="$environment"
    
    # Get ALB DNS for tests
    local alb_dns
    alb_dns=$(aws elbv2 describe-load-balancers \
        --names "$PROJECT_NAME-$environment-alb" \
        --query 'LoadBalancers[0].DNSName' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    
    if [[ -n "$alb_dns" && "$alb_dns" != "None" ]]; then
        export TEST_BASE_URL="http://$alb_dns"
    fi
    
    local test_results=0
    
    # Run nginx deployment smoke tests
    if [[ -f "app/tests/smoke/nginx-deployment.test.js" ]]; then
        log "Running nginx deployment smoke tests..."
        if (cd app && node tests/smoke/nginx-deployment.test.js 2>/dev/null); then
            success "Nginx deployment smoke tests passed"
        else
            error "Nginx deployment smoke tests failed"
            test_results=1
        fi
    else
        log "No nginx deployment smoke tests found, skipping..."
    fi
    
    return $test_results
}

# Function to validate rollback metadata
validate_rollback_metadata() {
    local environment="$1"
    local expected_version="$2"
    
    log "Validating rollback metadata..."
    
    # Check if rollback metadata exists
    local rollback_files
    rollback_files=$(aws s3 ls "s3://$ARTIFACTS_BUCKET/rollbacks/$environment/" --region "$AWS_REGION" 2>/dev/null | tail -5 | awk '{print $4}')
    
    if [[ -z "$rollback_files" ]]; then
        warning "No rollback metadata found"
        return 0
    fi
    
    # Get the most recent rollback metadata
    local latest_rollback
    latest_rollback=$(echo "$rollback_files" | tail -1)
    
    if [[ -n "$latest_rollback" ]]; then
        local rollback_metadata
        if rollback_metadata=$(aws s3 cp "s3://$ARTIFACTS_BUCKET/rollbacks/$environment/$latest_rollback" - --region "$AWS_REGION" 2>/dev/null); then
            local target_version
            target_version=$(echo "$rollback_metadata" | jq -r '.target_version // "unknown"')
            local rollback_timestamp
            rollback_timestamp=$(echo "$rollback_metadata" | jq -r '.rollback_timestamp // "unknown"')
            local initiated_by
            initiated_by=$(echo "$rollback_metadata" | jq -r '.rollback_initiated_by // "unknown"')
            
            log "Latest rollback metadata:"
            log "  Target Version: $target_version"
            log "  Timestamp: $rollback_timestamp"
            log "  Initiated By: $initiated_by"
            
            if [[ "$target_version" == "$expected_version" ]]; then
                success "Rollback metadata matches expected version"
            else
                warning "Rollback metadata version ($target_version) doesn't match expected ($expected_version)"
            fi
        fi
    fi
    
    return 0
}

# Function to generate validation report
generate_validation_report() {
    local environment="$1"
    local expected_version="$2"
    local validation_results="$3"
    
    log "Generating validation report..."
    
    local report_timestamp
    report_timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local report_file
    report_file="/tmp/rollback-validation-$environment-$(date +%Y%m%d-%H%M%S).json"
    
    # Create validation report
    local report
    report=$(cat << EOF
{
    "validation_timestamp": "$report_timestamp",
    "environment": "$environment",
    "expected_version": "$expected_version",
    "validation_results": $validation_results,
    "validated_by": "$(whoami)",
    "validation_type": "post_rollback",
    "aws_region": "$AWS_REGION",
    "project_name": "$PROJECT_NAME"
}
EOF
)
    
    # Save report locally
    echo "$report" > "$report_file"
    
    # Upload report to S3
    local report_key
    report_key="validation-reports/$environment/rollback-validation-$(date +%Y%m%d-%H%M%S).json"
    if aws s3 cp "$report_file" "s3://$ARTIFACTS_BUCKET/$report_key" --region "$AWS_REGION" 2>/dev/null; then
        success "Validation report uploaded: s3://$ARTIFACTS_BUCKET/$report_key"
    else
        warning "Failed to upload validation report to S3"
    fi
    
    log "Local validation report: $report_file"
    
    # Display summary
    echo
    log "=== VALIDATION SUMMARY ==="
    echo "$report" | jq '.'
    echo
}

# Main function
main() {
    local environment=""
    local expected_version=""
    local timeout=300
    local skip_tests=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                environment="$2"
                shift 2
                ;;
            -v|--version)
                expected_version="$2"
                shift 2
                ;;
            -t|--timeout)
                timeout="$2"
                shift 2
                ;;
            -s|--skip-tests)
                skip_tests=true
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
    
    if [[ -z "$expected_version" ]]; then
        error "Expected version is required"
        usage
        exit 1
    fi
    
    # Validate environment
    if [[ "$environment" != "staging" && "$environment" != "production" ]]; then
        error "Invalid environment: $environment. Must be 'staging' or 'production'"
        exit 1
    fi
    
    # Check AWS setup
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed"
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    log "Starting rollback validation for $environment environment"
    log "Expected version: $expected_version"
    log "Timeout: ${timeout}s"
    
    local validation_results='{"infrastructure": false, "application": false, "tests": false, "metadata": false}'
    local overall_success=true
    
    # Validate infrastructure
    if validate_infrastructure "$environment" "$expected_version"; then
        validation_results=$(echo "$validation_results" | jq '.infrastructure = true')
    else
        error "Infrastructure validation failed"
        overall_success=false
    fi
    
    # Validate application health
    if validate_application_health "$environment" "$timeout"; then
        validation_results=$(echo "$validation_results" | jq '.application = true')
    else
        error "Application health validation failed"
        overall_success=false
    fi
    
    # Run automated tests (unless skipped)
    if [[ "$skip_tests" != true ]]; then
        if run_automated_tests "$environment" "$expected_version"; then
            validation_results=$(echo "$validation_results" | jq '.tests = true')
        else
            error "Automated tests failed"
            overall_success=false
        fi
    else
        log "Skipping automated tests as requested"
        validation_results=$(echo "$validation_results" | jq '.tests = "skipped"')
    fi
    
    # Validate rollback metadata
    if validate_rollback_metadata "$environment" "$expected_version"; then
        validation_results=$(echo "$validation_results" | jq '.metadata = true')
    else
        warning "Rollback metadata validation had issues"
        # Don't fail overall validation for metadata issues
    fi
    
    # Generate validation report
    generate_validation_report "$environment" "$expected_version" "$validation_results"
    
    # Final result
    if [[ "$overall_success" == true ]]; then
        success "Rollback validation completed successfully!"
        success "Environment: $environment"
        success "Version: $expected_version"
        exit 0
    else
        error "Rollback validation failed!"
        error "Check the validation report for details"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"