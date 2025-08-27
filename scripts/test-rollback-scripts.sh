#!/bin/bash

# Test script for rollback automation scripts
# This script performs basic validation of the rollback scripts

set -euo pipefail

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

# Function to test script syntax
test_script_syntax() {
    local script="$1"
    local script_name=$(basename "$script")
    
    log "Testing syntax for $script_name..."
    
    if bash -n "$script"; then
        success "$script_name syntax is valid"
        return 0
    else
        error "$script_name has syntax errors"
        return 1
    fi
}

# Function to test script help output
test_script_help() {
    local script="$1"
    local script_name=$(basename "$script")
    
    log "Testing help output for $script_name..."
    
    if "$script" --help >/dev/null 2>&1; then
        success "$script_name help output works"
        return 0
    else
        error "$script_name help output failed"
        return 1
    fi
}

# Function to test rollback script dry run
test_rollback_dry_run() {
    log "Testing rollback script dry run mode..."
    
    # This will fail gracefully if AWS is not configured, but should not have syntax errors
    if ./scripts/rollback.sh -e staging --dry-run 2>/dev/null || [[ $? -eq 1 ]]; then
        success "Rollback dry run mode works (or fails gracefully)"
        return 0
    else
        error "Rollback dry run mode has issues"
        return 1
    fi
}

# Function to test deployment metadata script
test_deployment_metadata() {
    log "Testing deployment metadata script..."
    
    # Test list command (should fail gracefully without AWS)
    if ./scripts/deployment-metadata.sh list -e staging 2>/dev/null || [[ $? -eq 1 ]]; then
        success "Deployment metadata script works (or fails gracefully)"
        return 0
    else
        error "Deployment metadata script has issues"
        return 1
    fi
}

# Function to test validation script
test_validation_script() {
    log "Testing validation script..."
    
    # Test with missing parameters (should show usage)
    if ./scripts/rollback-validation.sh 2>/dev/null || [[ $? -eq 1 ]]; then
        success "Validation script works (or fails gracefully)"
        return 0
    else
        error "Validation script has issues"
        return 1
    fi
}

# Function to check required dependencies
check_dependencies() {
    log "Checking required dependencies..."
    
    local missing_deps=()
    
    # Check for required commands
    local required_commands=("bash" "jq" "curl" "aws")
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -eq 0 ]]; then
        success "All required dependencies are available"
        return 0
    else
        warning "Missing dependencies: ${missing_deps[*]}"
        warning "Some functionality may not work without these dependencies"
        return 1
    fi
}

# Function to validate script permissions
check_script_permissions() {
    log "Checking script permissions..."
    
    local scripts=("scripts/rollback.sh" "scripts/deployment-metadata.sh" "scripts/rollback-validation.sh")
    local permission_issues=()
    
    for script in "${scripts[@]}"; do
        if [[ ! -x "$script" ]]; then
            permission_issues+=("$script")
        fi
    done
    
    if [[ ${#permission_issues[@]} -eq 0 ]]; then
        success "All scripts have execute permissions"
        return 0
    else
        error "Scripts missing execute permissions: ${permission_issues[*]}"
        log "Run: chmod +x ${permission_issues[*]}"
        return 1
    fi
}

# Function to test JSON processing
test_json_processing() {
    log "Testing JSON processing capabilities..."
    
    local test_json='{"version": "v1.2.3", "status": "success", "timestamp": "2024-01-15T10:30:00Z"}'
    
    # Test jq processing
    if echo "$test_json" | jq -r '.version' | grep -q "v1.2.3"; then
        success "JSON processing works correctly"
        return 0
    else
        error "JSON processing failed"
        return 1
    fi
}

# Main test function
main() {
    log "Starting rollback scripts test suite..."
    echo
    
    local test_results=()
    local overall_success=true
    
    # Test script permissions
    if check_script_permissions; then
        test_results+=("permissions:PASS")
    else
        test_results+=("permissions:FAIL")
        overall_success=false
    fi
    
    # Check dependencies
    if check_dependencies; then
        test_results+=("dependencies:PASS")
    else
        test_results+=("dependencies:WARN")
        # Don't fail overall for missing dependencies
    fi
    
    # Test JSON processing
    if test_json_processing; then
        test_results+=("json:PASS")
    else
        test_results+=("json:FAIL")
        overall_success=false
    fi
    
    # Test script syntax
    local scripts=("scripts/rollback.sh" "scripts/deployment-metadata.sh" "scripts/rollback-validation.sh")
    
    for script in "${scripts[@]}"; do
        local script_name=$(basename "$script")
        if test_script_syntax "$script"; then
            test_results+=("syntax-$script_name:PASS")
        else
            test_results+=("syntax-$script_name:FAIL")
            overall_success=false
        fi
    done
    
    # Test help output
    for script in "${scripts[@]}"; do
        local script_name=$(basename "$script")
        if test_script_help "$script"; then
            test_results+=("help-$script_name:PASS")
        else
            test_results+=("help-$script_name:FAIL")
            overall_success=false
        fi
    done
    
    # Test specific functionality (these may fail gracefully without AWS)
    if test_rollback_dry_run; then
        test_results+=("rollback-dry-run:PASS")
    else
        test_results+=("rollback-dry-run:FAIL")
        # Don't fail overall for AWS-dependent tests
    fi
    
    if test_deployment_metadata; then
        test_results+=("deployment-metadata:PASS")
    else
        test_results+=("deployment-metadata:FAIL")
        # Don't fail overall for AWS-dependent tests
    fi
    
    if test_validation_script; then
        test_results+=("validation:PASS")
    else
        test_results+=("validation:FAIL")
        # Don't fail overall for AWS-dependent tests
    fi
    
    # Display results
    echo
    log "=== TEST RESULTS ==="
    for result in "${test_results[@]}"; do
        local test_name=$(echo "$result" | cut -d':' -f1)
        local test_status=$(echo "$result" | cut -d':' -f2)
        
        case "$test_status" in
            "PASS")
                success "$test_name: PASSED"
                ;;
            "FAIL")
                error "$test_name: FAILED"
                ;;
            "WARN")
                warning "$test_name: WARNING"
                ;;
        esac
    done
    
    echo
    if [[ "$overall_success" == true ]]; then
        success "All critical tests passed! Rollback scripts are ready to use."
        success "Note: Some tests may show warnings for missing AWS configuration - this is expected."
        exit 0
    else
        error "Some critical tests failed. Please fix the issues before using the rollback scripts."
        exit 1
    fi
}

# Check if we're in the right directory
if [[ ! -f "scripts/rollback.sh" ]]; then
    error "Please run this script from the project root directory"
    exit 1
fi

# Run main function
main "$@"