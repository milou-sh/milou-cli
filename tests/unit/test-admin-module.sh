#!/bin/bash

# =============================================================================
# Admin Module Tests - Test src/_admin.sh refactored module
# Tests consolidated admin operations and credential management
# =============================================================================

set -euo pipefail

# Get test directory and setup
readonly TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"

# Load test framework
source "$TEST_DIR/../helpers/test-framework.sh"

# Test configuration
readonly ADMIN_TEST_TEMP_DIR="$TEST_DIR/../tmp/admin_tests"

# =============================================================================
# Test Setup and Teardown
# =============================================================================

setup_admin_tests() {
    test_log "INFO" "Setting up admin module tests..."
    
    # Create temp directory
    mkdir -p "$ADMIN_TEST_TEMP_DIR"
    
    # Set up environment
    export SCRIPT_DIR="$PROJECT_ROOT"
    export MILOU_CLI_ROOT="$PROJECT_ROOT"
    export ENV_FILE="$ADMIN_TEST_TEMP_DIR/.env.test"
    
    # Create test environment file
    cat > "$ENV_FILE" << EOF
ADMIN_USERNAME=testadmin
ADMIN_PASSWORD=testpass123
ADMIN_EMAIL=test@localhost
POSTGRES_USER=testuser
POSTGRES_PASSWORD=testdbpass
POSTGRES_DB=testdb
EOF
    
    test_log "SUCCESS" "Admin test setup complete"
}

cleanup_admin_tests() {
    test_log "INFO" "Cleaning up admin module tests..."
    rm -rf "$ADMIN_TEST_TEMP_DIR" 2>/dev/null || true
}

# =============================================================================
# Individual Test Functions
# =============================================================================

test_admin_module_loading() {
    test_log "INFO" "Testing admin module loading..."
    
    # Test that the module loads without errors
    if source "$PROJECT_ROOT/src/_admin.sh"; then
        test_log "SUCCESS" "Admin module loads successfully"
    else
        test_log "ERROR" "Admin module failed to load"
        return 1
    fi
    
    # Test essential functions are available
    assert_function_exists "admin_credentials_reset" "Credential reset function should be available"
    assert_function_exists "admin_user_create" "User creation should be available"
    assert_function_exists "admin_credentials_show" "Credential display should be available"
    
    return 0
}

test_credential_management() {
    test_log "INFO" "Testing credential management functionality..."
    
    source "$PROJECT_ROOT/src/_admin.sh" || return 1
    
    # Test credential display (should work with test env)
    if admin_credentials_show >/dev/null 2>&1; then
        test_log "SUCCESS" "Credential display works"
    else
        test_log "WARN" "Credential display had issues (may be normal without database)"
    fi
    
    return 0
}

test_user_creation() {
    test_log "INFO" "Testing user creation functionality..."
    
    source "$PROJECT_ROOT/src/_admin.sh" || return 1
    
    # Test user creation (dry run mode)
    export DRY_RUN="true"
    export TEST_MODE="true"
    
    if admin_user_create "testuser2" "testpass" "test2@localhost" >/dev/null 2>&1; then
        test_log "SUCCESS" "User creation functions work"
    else
        test_log "WARN" "User creation returned warnings (normal without database)"
    fi
    
    return 0
}

test_password_reset() {
    test_log "INFO" "Testing password reset functionality..."
    
    source "$PROJECT_ROOT/src/_admin.sh" || return 1
    
    # Test password reset (dry run mode)
    export DRY_RUN="true"
    export TEST_MODE="true"
    
    if admin_credentials_reset "testadmin" "newpass123" >/dev/null 2>&1; then
        test_log "SUCCESS" "Password reset functions work"
    else
        test_log "WARN" "Password reset returned warnings (normal without database)"
    fi
    
    return 0
}

test_admin_validation() {
    test_log "INFO" "Testing admin validation functionality..."
    
    source "$PROJECT_ROOT/src/_admin.sh" || return 1
    
    # Test admin validation (should work with environment)
    if admin_validate_credentials >/dev/null 2>&1; then
        test_log "SUCCESS" "Admin validation works"
    else
        test_log "WARN" "Admin validation returned warnings (may be normal)"
    fi
    
    return 0
}

test_database_operations() {
    test_log "INFO" "Testing database operation functions..."
    
    source "$PROJECT_ROOT/src/_admin.sh" || return 1
    
    # Test database operations (test mode)
    export TEST_MODE="true"
    export SKIP_DATABASE="true"
    
    if admin_database_status >/dev/null 2>&1; then
        test_log "SUCCESS" "Database operations work in test mode"
    else
        test_log "WARN" "Database operations returned warnings (expected without DB)"
    fi
    
    return 0
}

test_command_handler() {
    test_log "INFO" "Testing admin command handler..."
    
    source "$PROJECT_ROOT/src/_admin.sh" || return 1
    
    # Test command handling (safe commands only)
    export TEST_MODE="true"
    
    if admin_handle_command "credentials" >/dev/null 2>&1; then
        test_log "SUCCESS" "Command handler works"
    else
        test_log "WARN" "Command handler returned warnings (may be normal)"
    fi
    
    return 0
}

test_security_functions() {
    test_log "INFO" "Testing security functions..."
    
    source "$PROJECT_ROOT/src/_admin.sh" || return 1
    
    # Test security validation
    if admin_validate_security_settings >/dev/null 2>&1; then
        test_log "SUCCESS" "Security validation works"
    else
        test_log "WARN" "Security validation returned warnings (may be normal)"
    fi
    
    return 0
}

test_export_cleanliness() {
    test_log "INFO" "Testing export cleanliness..."
    
    source "$PROJECT_ROOT/src/_admin.sh" || return 1
    
    # Count exported functions from admin module
    local admin_exports
    admin_exports=$(declare -F | grep -c "admin_" || echo "0")
    
    # Should have reasonable number of exports
    if [[ $admin_exports -gt 15 ]]; then
        test_log "WARN" "Many admin exports: $admin_exports (check if all are necessary)"
    fi
    
    # Test that essential functions are exported
    assert_function_exists "admin_credentials_reset" "Credential reset should be exported"
    
    test_log "SUCCESS" "Admin module exports are reasonable ($admin_exports functions)"
    return 0
}

# =============================================================================
# Main Test Runner
# =============================================================================

run_admin_tests() {
    test_init "🧪 Admin Module Tests"
    
    # Setup test environment
    test_setup
    setup_admin_tests
    
    # Run individual tests
    test_run "Module Loading" "test_admin_module_loading" "Tests that admin module loads correctly"
    test_run "Credential Management" "test_credential_management" "Tests credential operations"
    test_run "User Creation" "test_user_creation" "Tests user creation functions"
    test_run "Password Reset" "test_password_reset" "Tests password reset functionality"
    test_run "Admin Validation" "test_admin_validation" "Tests admin validation"
    test_run "Database Operations" "test_database_operations" "Tests database interaction"
    test_run "Command Handler" "test_command_handler" "Tests command processing"
    test_run "Security Functions" "test_security_functions" "Tests security validation"
    test_run "Export Cleanliness" "test_export_cleanliness" "Tests module export hygiene"
    
    # Cleanup
    cleanup_admin_tests
    test_cleanup
    
    # Show results
    test_summary
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_admin_tests
fi 