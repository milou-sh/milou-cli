#!/bin/bash

# =============================================================================
# Unit Tests for Update Module (src/_update.sh)
# Tests the modernized self-update and system update functionality
# =============================================================================

# Load test framework
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/test-framework.sh"

# Test configuration
readonly TEST_UPDATE_DIR="$TEST_TEMP_DIR/updates"

# =============================================================================
# Test Setup and Teardown
# =============================================================================

setup_self_update_tests() {
    test_log "INFO" "Setting up self-update tests..."
    
    # Create test directories
    mkdir -p "$TEST_UPDATE_DIR"
    
    # Mock GitHub token for testing
    readonly MOCK_GITHUB_TOKEN="ghp_1234567890abcdef1234567890abcdef12345678"
    
    test_log "SUCCESS" "Self-update test setup complete"
}

cleanup_self_update_tests() {
    test_log "INFO" "Cleaning up self-update tests..."
    rm -rf "$TEST_UPDATE_DIR" 2>/dev/null || true
}

# =============================================================================
# Individual Test Functions
# =============================================================================

test_update_module_loading() {
    test_log "INFO" "Testing update module loading..."
    
    # Test that the module loads without errors
    if source "$PROJECT_ROOT/src/_update.sh"; then
        test_log "SUCCESS" "Update module loads successfully"
    else
        test_log "ERROR" "Update module failed to load"
        return 1
    fi
    
    # Test that required functions are exported
    assert_function_exists "milou_self_update_check" "CLI update check function should be exported"
    assert_function_exists "milou_self_update_perform" "CLI update perform function should be exported"
    assert_function_exists "milou_update_system" "System update function should be exported"
    
    test_log "SUCCESS" "Update module loading tests passed"
    return 0
}

test_cli_update_check() {
    test_log "INFO" "Testing CLI update check functionality..."
    
    # Load update module
    source "$PROJECT_ROOT/src/_update.sh" || return 1
    
    # Test version checking with mock (this should work without GitHub API)
    local output
    output=$(milou_self_update_check "latest" 2>&1) || true
    
    # Should not crash and should provide some feedback
    assert_not_contains "$output" "command not found" "Update check should be callable"
    
    test_log "SUCCESS" "CLI update check tests passed"
    return 0
}

test_system_update_functionality() {
    test_log "INFO" "Testing system update functionality..."
    
    # Load update module
    source "$PROJECT_ROOT/src/_update.sh" || return 1
    
    # Test system update help
    local help_output
    help_output=$(handle_update --help 2>&1) || true
    
    # Should provide help information
    assert_contains "$help_output" "update\|Update" "Should show update help"
    
    test_log "SUCCESS" "System update functionality tests passed"
    return 0
}

test_update_status_check() {
    test_log "INFO" "Testing update status check..."
    
    # Load update module
    source "$PROJECT_ROOT/src/_update.sh" || return 1
    
    # Test status check functionality
    local status_output
    status_output=$(milou_update_check_status 2>&1) || true
    
    # Should not crash and should provide status information
    assert_not_contains "$status_output" "command not found" "Status check should be callable"
    
    test_log "SUCCESS" "Update status check tests passed"
    return 0
}

test_error_handling() {
    test_log "INFO" "Testing error handling..."
    
    # Load update module
    source "$PROJECT_ROOT/src/_update.sh" || return 1
    
    # Test CLI update with invalid version
    local output
    output=$(milou_self_update_perform "invalid-version-12345" 2>&1) || true
    
    # Should handle invalid versions gracefully
    assert_contains "$output" "ERROR\|error\|Error\|Failed\|failed" "Should report error on invalid version"
    
    test_log "SUCCESS" "Error handling tests passed"
    return 0
}

test_command_handlers() {
    test_log "INFO" "Testing command handlers..."
    
    # Load update module
    source "$PROJECT_ROOT/src/_update.sh" || return 1
    
    # Test CLI update handler
    assert_function_exists "handle_update_cli" "CLI update handler should be exported"
    assert_function_exists "handle_update" "System update handler should be exported"
    assert_function_exists "handle_check_cli_updates" "CLI update check handler should be exported"
    
    # Test handler help
    local cli_help
    cli_help=$(handle_update_cli --help 2>&1) || true
    assert_contains "$cli_help" "help\|Help\|usage\|Usage" "CLI update handler should show help"
    
    test_log "SUCCESS" "Command handlers tests passed"
    return 0
}

test_update_clean_api() {
    test_log "INFO" "Testing update module clean API..."
    
    # Load update module
    source "$PROJECT_ROOT/src/_update.sh" || return 1
    
    # Count exported functions with update-related names
    local exported_functions
    exported_functions=$(declare -F | grep -E "milou_.*update|handle_.*update|handle_.*rollback|handle_check_cli" | wc -l)
    
    # Should have reasonable number of exported functions (updated expectation)
    if [[ $exported_functions -ge 8 && $exported_functions -le 15 ]]; then
        test_log "DEBUG" "Update module has reasonable export count: $exported_functions functions"
    else
        test_log "WARN" "Update module export count: $exported_functions (outside expected range 8-15)"
    fi
    
    # Verify core exports exist
    assert_function_exists "milou_update_system" "System update should be exported"
    assert_function_exists "milou_self_update_check" "CLI update check should be exported"
    
    test_log "SUCCESS" "Update clean API tests passed"
    return 0
}

# =============================================================================
# Main Test Runner
# =============================================================================

run_self_update_tests() {
    test_init "🚀 Update Module Tests"
    
    # Setup test environment
    test_setup
    setup_self_update_tests
    
    # Run individual tests
    test_run "Module Loading" "test_update_module_loading" "Tests that update module loads correctly"
    test_run "CLI Update Check" "test_cli_update_check" "Tests CLI update checking"
    test_run "System Update" "test_system_update_functionality" "Tests system update features"
    test_run "Status Check" "test_update_status_check" "Tests update status checking"
    test_run "Error Handling" "test_error_handling" "Tests error handling"
    test_run "Command Handlers" "test_command_handlers" "Tests command handler functions"
    test_run "Clean API" "test_update_clean_api" "Tests that module exports are clean"
    
    # Cleanup
    cleanup_self_update_tests
    test_cleanup
    
    # Show results
    test_summary
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_self_update_tests
fi 