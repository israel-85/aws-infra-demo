#!/bin/bash

# Deployment metadata management script
# This script manages deployment metadata for rollback capabilities

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
Usage: $0 [COMMAND] [OPTIONS]

Deployment metadata management for rollback capabilities

COMMANDS:
    create      Create deployment metadata
    update      Update deployment status
    list        List deployment metadata
    cleanup     Clean up old metadata

OPTIONS:
    -e, --environment ENVIRONMENT    Target environment (staging|production)
    -v, --version VERSION           Deployment version
    -s, --sha GIT_SHA              Git commit SHA
    -t, --status STATUS            Deployment status (pending|success|failed)
    -a, --artifact-path PATH       Path to deployment artifact
    -d, --days DAYS                Days to keep metadata (for cleanup)
    -h, --help                     Show this help message

EXAMPLES:
    $0 create -e staging -v v1.2.3 -s abc123 -a deployments/staging/deployment-abc123.tar.gz
    $0 update -e staging -v v1.2.3 -t success
    $0 list -e production
    $0 cleanup -e staging -d 30

EOF
}

# Function to create deployment metadata
create_metadata() {
    local environment="$1"
    local version="$2"
    local git_sha="$3"
    local artifact_path="$4"
    local status="${5:-pending}"
    
    log "Creating deployment metadata for $environment environment"
    
    # Generate metadata
    local metadata
    metadata=$(cat << EOF
{
    "version": "$version",
    "git_sha": "$git_sha",
    "environment": "$environment",
    "deployment_status": "$status",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "artifact_path": "$artifact_path",
    "deployed_by": "$(whoami)",
    "deployment_id": "$(uuidgen | tr '[:upper:]' '[:lower:]')",
    "metadata_version": "1.0"
}
EOF
)
    
    # Calculate artifact checksum if artifact exists
    if aws s3 head-object --bucket "$ARTIFACTS_BUCKET" --key "$artifact_path" --region "$AWS_REGION" &>/dev/null; then
        local checksum
        checksum=$(aws s3api head-object \
            --bucket "$ARTIFACTS_BUCKET" \
            --key "$artifact_path" \
            --region "$AWS_REGION" \
            --query 'ETag' --output text | tr -d '"')
        
        metadata=$(echo "$metadata" | jq ". + {checksum: \"$checksum\"}")
    fi
    
    # Store metadata in S3
    local metadata_key="deployments/$environment/metadata-$git_sha.json"
    
    if echo "$metadata" | aws s3 cp - "s3://$ARTIFACTS_BUCKET/$metadata_key" --region "$AWS_REGION"; then
        success "Deployment metadata created: s3://$ARTIFACTS_BUCKET/$metadata_key"
        echo "$metadata" | jq '.'
    else
        error "Failed to create deployment metadata"
        return 1
    fi
}

# Function to update deployment status
update_status() {
    local environment="$1"
    local version="$2"
    local new_status="$3"
    
    log "Updating deployment status for $version in $environment to $new_status"
    
    # Find metadata file by version
    local metadata_files
    metadata_files=$(aws s3 ls "s3://$ARTIFACTS_BUCKET/deployments/$environment/" --recursive --region "$AWS_REGION" | grep "metadata-.*\.json" | awk '{print $4}')
    
    local target_metadata_key=""
    local current_metadata=""
    
    for metadata_key in $metadata_files; do
        local metadata_content
        if metadata_content=$(aws s3 cp "s3://$ARTIFACTS_BUCKET/$metadata_key" - --region "$AWS_REGION" 2>/dev/null); then
            local file_version=$(echo "$metadata_content" | jq -r '.version // "unknown"')
            if [[ "$file_version" == "$version" ]]; then
                target_metadata_key="$metadata_key"
                current_metadata="$metadata_content"
                break
            fi
        fi
    done
    
    if [[ -z "$target_metadata_key" ]]; then
        error "Metadata not found for version $version in $environment"
        return 1
    fi
    
    # Update metadata
    local updated_metadata
    updated_metadata=$(echo "$current_metadata" | jq ". + {
        deployment_status: \"$new_status\",
        status_updated_at: \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
        status_updated_by: \"$(whoami)\"
    }")
    
    # Store updated metadata
    if echo "$updated_metadata" | aws s3 cp - "s3://$ARTIFACTS_BUCKET/$target_metadata_key" --region "$AWS_REGION"; then
        success "Deployment status updated to $new_status"
        echo "$updated_metadata" | jq '.'
    else
        error "Failed to update deployment status"
        return 1
    fi
}

# Function to list deployment metadata
list_metadata() {
    local environment="$1"
    local limit="${2:-10}"
    
    log "Listing deployment metadata for $environment environment (limit: $limit)"
    
    # Get metadata files
    local metadata_files
    metadata_files=$(aws s3 ls "s3://$ARTIFACTS_BUCKET/deployments/$environment/" --recursive --region "$AWS_REGION" | \
        grep "metadata-.*\.json" | \
        sort -k1,2 -r | \
        head -n "$limit" | \
        awk '{print $4}')
    
    if [[ -z "$metadata_files" ]]; then
        warning "No deployment metadata found for $environment"
        return 0
    fi
    
    echo
    printf "%-20s %-12s %-10s %-20s %-15s\n" "VERSION" "SHA" "STATUS" "TIMESTAMP" "DEPLOYED_BY"
    printf "%-20s %-12s %-10s %-20s %-15s\n" "--------" "---" "------" "---------" "-----------"
    
    for metadata_key in $metadata_files; do
        local metadata_content
        if metadata_content=$(aws s3 cp "s3://$ARTIFACTS_BUCKET/$metadata_key" - --region "$AWS_REGION" 2>/dev/null); then
            local version=$(echo "$metadata_content" | jq -r '.version // "unknown"')
            local git_sha=$(echo "$metadata_content" | jq -r '.git_sha[0:8] // "unknown"')
            local status=$(echo "$metadata_content" | jq -r '.deployment_status // "unknown"')
            local timestamp=$(echo "$metadata_content" | jq -r '.timestamp // "unknown"' | cut -d'T' -f1)
            local deployed_by=$(echo "$metadata_content" | jq -r '.deployed_by // "unknown"')
            
            printf "%-20s %-12s %-10s %-20s %-15s\n" "$version" "$git_sha" "$status" "$timestamp" "$deployed_by"
        fi
    done
    echo
}

# Function to cleanup old metadata
cleanup_metadata() {
    local environment="$1"
    local days="${2:-30}"
    
    log "Cleaning up deployment metadata older than $days days for $environment"
    
    # Calculate cutoff date
    local cutoff_date
    if command -v gdate &> /dev/null; then
        # macOS with GNU date
        cutoff_date=$(gdate -d "$days days ago" -u +%Y-%m-%dT%H:%M:%SZ)
    else
        # Linux date
        cutoff_date=$(date -d "$days days ago" -u +%Y-%m-%dT%H:%M:%SZ)
    fi
    
    log "Cutoff date: $cutoff_date"
    
    # Get all metadata files
    local metadata_files
    metadata_files=$(aws s3 ls "s3://$ARTIFACTS_BUCKET/deployments/$environment/" --recursive --region "$AWS_REGION" | \
        grep "metadata-.*\.json" | \
        awk '{print $4}')
    
    local deleted_count=0
    local kept_successful=0
    
    for metadata_key in $metadata_files; do
        local metadata_content
        if metadata_content=$(aws s3 cp "s3://$ARTIFACTS_BUCKET/$metadata_key" - --region "$AWS_REGION" 2>/dev/null); then
            local timestamp=$(echo "$metadata_content" | jq -r '.timestamp // "unknown"')
            local status=$(echo "$metadata_content" | jq -r '.deployment_status // "unknown"')
            local version=$(echo "$metadata_content" | jq -r '.version // "unknown"')
            
            # Always keep at least 5 successful deployments regardless of age
            if [[ "$status" == "success" && $kept_successful -lt 5 ]]; then
                log "Keeping successful deployment: $version (protected)"
                ((kept_successful++))
                continue
            fi
            
            # Delete if older than cutoff date
            if [[ "$timestamp" < "$cutoff_date" ]]; then
                log "Deleting old metadata: $version ($timestamp)"
                if aws s3 rm "s3://$ARTIFACTS_BUCKET/$metadata_key" --region "$AWS_REGION"; then
                    ((deleted_count++))
                else
                    warning "Failed to delete: $metadata_key"
                fi
            fi
        fi
    done
    
    success "Cleanup completed. Deleted $deleted_count metadata files, kept $kept_successful successful deployments"
}

# Main function
main() {
    local command=""
    local environment=""
    local version=""
    local git_sha=""
    local status=""
    local artifact_path=""
    local days="30"
    
    # Parse command line arguments
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi
    
    # Handle help flag first
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        usage
        exit 0
    fi
    
    command="$1"
    shift
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                environment="$2"
                shift 2
                ;;
            -v|--version)
                version="$2"
                shift 2
                ;;
            -s|--sha)
                git_sha="$2"
                shift 2
                ;;
            -t|--status)
                status="$2"
                shift 2
                ;;
            -a|--artifact-path)
                artifact_path="$2"
                shift 2
                ;;
            -d|--days)
                days="$2"
                shift 2
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
    
    # Validate AWS setup
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed"
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Execute command
    case $command in
        create)
            if [[ -z "$environment" || -z "$version" || -z "$git_sha" || -z "$artifact_path" ]]; then
                error "create command requires: -e environment -v version -s sha -a artifact-path"
                exit 1
            fi
            create_metadata "$environment" "$version" "$git_sha" "$artifact_path" "$status"
            ;;
        update)
            if [[ -z "$environment" || -z "$version" || -z "$status" ]]; then
                error "update command requires: -e environment -v version -t status"
                exit 1
            fi
            update_status "$environment" "$version" "$status"
            ;;
        list)
            if [[ -z "$environment" ]]; then
                error "list command requires: -e environment"
                exit 1
            fi
            list_metadata "$environment"
            ;;
        cleanup)
            if [[ -z "$environment" ]]; then
                error "cleanup command requires: -e environment"
                exit 1
            fi
            cleanup_metadata "$environment" "$days"
            ;;
        *)
            error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"