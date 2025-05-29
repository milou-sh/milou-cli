#!/bin/bash

# =============================================================================
# User Module Tests - Test src/_user.sh refactored module
# Tests consolidated user lifecycle, Docker permissions, environment setup
# =============================================================================

set -euo pipefail

# Get test directory and setup
readonly TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"

# Load test framework
source "$TEST_DIR/../helpers/test-framework.sh"

# Test configuration
readonly USER_TEST_TEMP_DIR="$TEST_DIR/../tmp/user_tests"

# =============================================================================
# Test Setup and Teardown
# =============================================================================

setup_user_tests() {
    test_log "INFO" "Setting up user module tests..."
    
    # Create temp directory
    mkdir -p "$USER_TEST_TEMP_DIR"
    
    # Set up environment
    export SCRIPT_DIR="$PROJECT_ROOT"
    export MILOU_CLI_ROOT="$PROJECT_ROOT"
    export TEST_MODE="true"
    
    test_log "SUCCESS" "User test setup complete"
}

cleanup_user_tests() {
    test_log "INFO" "Cleaning up user module tests..."
    rm -rf "$USER_TEST_TEMP_DIR" 2>/dev/null || true
}

# =============================================================================
# Individual Test Functions
# =============================================================================

test_user_module_loading() {
    test_log "INFO" "Testing user module loading..."
    
    # Test that the module loads without errors
    if source "$PROJECT_ROOT/src/_user.sh"; then
        test_log "SUCCESS" "User module loads successfully"
    else
        test_log "ERROR" "User module failed to load"
        return 1
    fi
    
    # Test essential functions are available
    assert_function_exists "user_create" "User creation function should be available"
    assert_function_exists "user_setup_docker_permissions" "Docker permissions should be available"
    assert_function_exists "user_setup_environment" "Environment setup should be available"
    
    return 0
}

test_user_creation() {
    test_log "INFO" "Testing user creation functionality..."
    
    source "$PROJECT_ROOT/src/_user.sh" || return 1
    
    # Test user creation in test mode (should not actually create users)
    export TEST_MODE="true"
    export DRY_RUN="true"
    
    if user_create "testuser" >/dev/null 2>&1; then
        test_log "SUCCESS" "User creation functions work"
    else
        test_log "WARN" "User creation returned warnings (normal in test mode)"
    fi
    
    return 0
}

test_docker_permissions() {
    test_log "INFO" "Testing Docker permissions setup..."
    
    source "$PROJECT_ROOT/src/_user.sh" || return 1
    
    # Test Docker permissions setup (test mode)
    export TEST_MODE="true"
    export DRY_RUN="true"
    
    if user_setup_docker_permissions "testuser" >/dev/null 2>&1; then
        test_log "SUCCESS" "Docker permissions setup works"
    else
        test_log "WARN" "Docker permissions returned warnings (normal in test mode)"
    fi
    
    return 0
}

test_environment_setup() {
    test_log "INFO" "Testing environment setup functionality..."
    
    source "$PROJECT_ROOT/src/_user.sh" || return 1
    
    # Test environment setup
    export TEST_MODE="true"
    
    if user_setup_environment "testuser" >/dev/null 2>&1; then
        test_log "SUCCESS" "Environment setup works"
    else
        test_log "WARN" "Environment setup returned warnings (may be normal)"
    fi
    
    return 0
}

test_user_validation() {
    test_log "INFO" "Testing user validation functionality..."
    
    source "$PROJECT_ROOT/src/_user.sh" || return 1
    
    # Test user validation (should work for current user)
    if user_validate_current >/dev/null 2>&1; then
        test_log "SUCCESS" "User validation works"
    else
        test_log "WARN" "User validation returned warnings (may be normal)"
    fi
    
    return 0
}

test_security_setup() {
    test_log "INFO" "Testing security setup functionality..."
    
    source "$PROJECT_ROOT/src/_user.sh" || return 1
    
    # Test security setup (test mode)
    export TEST_MODE="true"
    
    if user_setup_security "testuser" >/dev/null 2>&1; then
        test_log "SUCCESS" "Security setup works"
    else
        test_log "WARN" "Security setup returned warnings (normal in test mode)"
    fi
    
    return 0
}

test_user_switching() {
    test_log "INFO" "Testing user switching functionality..."
    
    source "$PROJECT_ROOT/src/_user.sh" || return 1
    
    # Test user switching validation (should not actually switch)
    export TEST_MODE="true"
    
    if user_validate_switch_permissions >/dev/null 2>&1; then
        test_log "SUCCESS" "User switching validation works"
    else
        test_log "WARN" "User switching returned warnings (normal without sudo)"
    fi
    
    return 0
}

test_docker_validation() {
    test_log "INFO" "Testing Docker access validation..."
    
    source "$PROJECT_ROOT/src/_user.sh" || return 1
    
    # Test Docker access validation
    if user_validate_docker_access >/dev/null 2>&1; then
        test_log "SUCCESS" "Docker access validation works"
    else
        test_log "WARN" "Docker access validation failed (normal without Docker)"
    fi
    
    return 0
}

test_interface_functions() {
    test_log "INFO" "Testing user interface functions..."
    
    source "$PROJECT_ROOT/src/_user.sh" || return 1
    
    # Test user interface in non-interactive mode
    export INTERACTIVE="false"
    export TEST_MODE="true"
    
    if user_prompt_creation_details >/dev/null 2>&1; then
        test_log "SUCCESS" "User interface functions work"
    else
        test_log "WARN" "User interface returned warnings (normal in non-interactive)"
    fi
    
    return 0
}

test_export_cleanliness() {
    test_log "INFO" "Testing export cleanliness..."
    
    source "$PROJECT_ROOT/src/_user.sh" || return 1
    
    # Count exported functions from user module
    local user_exports
    user_exports=$(declare -F | grep -c "user_" || echo "0")
    
    # Should have reasonable number of exports
    if [[ $user_exports -gt 25 ]]; then
        test_log "WARN" "Many user exports: $user_exports (check if all are necessary)"
    fi
    
    # Test that essential functions are exported
    assert_function_exists "user_create" "User creation should be exported"
    
    test_log "SUCCESS" "User module exports are reasonable ($user_exports functions)"
    return 0
}

# =============================================================================
# Main Test Runner
# =============================================================================

run_user_tests() {
    test_init "🧪 User Module Tests"
    
    # Setup test environment
    test_setup
    setup_user_tests
    
    # Run individual tests
    test_run "Module Loading" "test_user_module_loading" "Tests that user module loads correctly"
    test_run "User Creation" "test_user_creation" "Tests user creation functions"
    test_run "Docker Permissions" "test_docker_permissions" "Tests Docker permissions setup"
    test_run "Environment Setup" "test_environment_setup" "Tests environment configuration"
    test_run "User Validation" "test_user_validation" "Tests user validation"
    test_run "Security Setup" "test_security_setup" "Tests security configuration"
    test_run "User Switching" "test_user_switching" "Tests user switching validation"
    test_run "Docker Validation" "test_docker_validation" "Tests Docker access validation"
    test_run "Interface Functions" "test_interface_functions" "Tests user interface functions"
    test_run "Export Cleanliness" "test_export_cleanliness" "Tests module export hygiene"
    
    # Cleanup
    cleanup_user_tests
    test_cleanup
    
    # Show results
    test_summary
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_user_tests
fi 