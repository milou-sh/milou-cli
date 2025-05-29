#!/bin/bash

# =============================================================================
# Integration Tests for Modernized Command Handlers
# Tests the command structure and integration between modules
# =============================================================================

# Load test framework
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/test-framework.sh"

# Test configuration
readonly TEST_CLI_SCRIPT="$PROJECT_ROOT/milou.sh"

# =============================================================================
# Test Setup and Teardown
# =============================================================================

setup_integration_tests() {
    test_log "INFO" "Setting up command integration tests..."
    
    # Ensure the main CLI script exists
    if [[ ! -f "$TEST_CLI_SCRIPT" ]]; then
        test_log "ERROR" "Main CLI script not found: $TEST_CLI_SCRIPT"
        return 1
    fi
    
    # Make sure it's executable
    chmod +x "$TEST_CLI_SCRIPT"
    
    test_log "SUCCESS" "Command integration test setup complete"
}

cleanup_integration_tests() {
    test_log "INFO" "Cleaning up command integration tests..."
    # Nothing specific to clean up for these tests
}

# =============================================================================
# Helper Functions
# =============================================================================

# Run CLI command and capture output
run_cli_command() {
    local -a cmd_args=("$@")
    local output
    local exit_code=0
    
    output=$(cd "$PROJECT_ROOT" && timeout 30 "$TEST_CLI_SCRIPT" "${cmd_args[@]}" 2>&1) || exit_code=$?
    
    echo "$output"
    return $exit_code
}

# Check if CLI help includes expected content
check_help_content() {
    local help_output="$1"
    local expected_commands=("backup" "admin" "ssl" "update" "status")
    
    for cmd in "${expected_commands[@]}"; do
        if ! echo "$help_output" | grep -q "$cmd"; then
            test_log "ERROR" "Help output missing command: $cmd"
            return 1
        fi
    done
    
    return 0
}

# =============================================================================
# Individual Test Functions
# =============================================================================

test_cli_basic_functionality() {
    test_log "INFO" "Testing CLI basic functionality..."
    
    # Test that CLI runs without errors
    local output
    output=$(run_cli_command --help 2>&1) || true
    
    # Should show help and not crash
    assert_contains "$output" "Usage\|USAGE\|Commands\|COMMANDS" "Should show usage information"
    assert_not_contains "$output" "command not found" "Should not have command not found errors"
    
    test_log "SUCCESS" "CLI basic functionality tests passed"
    return 0
}

test_help_system_integration() {
    test_log "INFO" "Testing help system integration..."
    
    # Test main help
    local main_help
    main_help=$(run_cli_command --help 2>&1) || true
    
    assert_contains "$main_help" "milou" "Should mention milou in help"
    check_help_content "$main_help" || return 1
    
    # Test subcommand help
    local backup_help
    backup_help=$(run_cli_command backup --help 2>&1) || true
    assert_contains "$backup_help" "backup\|Backup" "Should show backup-specific help"
    
    local admin_help
    admin_help=$(run_cli_command admin --help 2>&1) || true
    assert_contains "$admin_help" "admin\|Admin" "Should show admin-specific help"
    
    test_log "SUCCESS" "Help system integration tests passed"
    return 0
}

test_admin_command_integration() {
    test_log "INFO" "Testing admin command integration..."
    
    # Test admin command structure
    local admin_output
    admin_output=$(run_cli_command admin --help 2>&1) || true
    
    # Should have admin subcommands
    assert_contains "$admin_output" "credentials\|show" "Should have credentials command"
    assert_contains "$admin_output" "reset" "Should have reset command"
    assert_contains "$admin_output" "create" "Should have create command"
    
    # Test that admin commands can be called (even if they fail due to missing setup)
    local creds_output
    creds_output=$(run_cli_command admin credentials 2>&1) || true
    
    # Should attempt to execute, not crash with syntax errors
    assert_not_contains "$creds_output" "syntax error\|command not found" "Should not have syntax errors"
    
    test_log "SUCCESS" "Admin command integration tests passed"
    return 0
}

test_backup_command_integration() {
    test_log "INFO" "Testing backup command integration..."
    
    # Test backup command structure
    local backup_output
    backup_output=$(run_cli_command backup --help 2>&1) || true
    
    # Should have backup options
    assert_contains "$backup_output" "full\|config\|data\|ssl" "Should have backup types"
    
    # Test backup command execution (should handle missing dependencies gracefully)
    local backup_attempt
    backup_attempt=$(run_cli_command backup config --name test_backup 2>&1) || true
    
    # Should attempt to execute, not crash
    assert_not_contains "$backup_attempt" "syntax error\|command not found" "Should not have syntax errors"
    
    test_log "SUCCESS" "Backup command integration tests passed"
    return 0
}

test_ssl_command_integration() {
    test_log "INFO" "Testing SSL command integration..."
    
    # Test SSL command structure
    local ssl_output
    ssl_output=$(run_cli_command ssl --help 2>&1) || true
    
    # Should have SSL subcommands
    assert_contains "$ssl_output" "setup\|status\|validate" "Should have SSL commands"
    
    # Test SSL status (should work even without certificates)
    local ssl_status
    ssl_status=$(run_cli_command ssl status 2>&1) || true
    
    # Should attempt to check status, not crash
    assert_not_contains "$ssl_status" "syntax error\|command not found" "Should not have syntax errors"
    
    test_log "SUCCESS" "SSL command integration tests passed"
    return 0
}

test_update_command_integration() {
    test_log "INFO" "Testing update command integration..."
    
    # Test update command structure
    local update_output
    update_output=$(run_cli_command update --help 2>&1) || true
    
    # Should have update functionality
    assert_contains "$update_output" "update\|Update" "Should show update help"
    
    # Test new CLI update commands
    local cli_update_help
    cli_update_help=$(run_cli_command update-cli --help 2>&1) || true
    
    # Should have CLI self-update functionality
    assert_contains "$cli_update_help" "update\|version\|CLI" "Should show CLI update help"
    
    test_log "SUCCESS" "Update command integration tests passed"
    return 0
}

test_new_self_update_commands() {
    test_log "INFO" "Testing new self-update commands..."
    
    # Test all new CLI update commands exist
    local commands=("update-cli" "update-status" "rollback" "list-backups")
    
    for cmd in "${commands[@]}"; do
        local cmd_output
        cmd_output=$(run_cli_command "$cmd" --help 2>&1) || true
        
        # Should respond to help, not show command not found
        assert_not_contains "$cmd_output" "Unknown command\|command not found" "Command $cmd should exist"
    done
    
    test_log "SUCCESS" "New self-update commands tests passed"
    return 0
}

test_command_module_loading() {
    test_log "INFO" "Testing command module loading..."
    
    # Test that the main modules can be loaded
    if ! source "$PROJECT_ROOT/src/_admin.sh"; then
        test_log "ERROR" "Failed to load admin module"
        return 1
    fi
    
    if ! source "$PROJECT_ROOT/src/_backup.sh"; then
        test_log "ERROR" "Failed to load backup module"
        return 1
    fi
    
    if ! source "$PROJECT_ROOT/src/_update.sh"; then
        test_log "ERROR" "Failed to load update module"
        return 1
    fi
    
    # Test that command handlers are available after loading
    assert_function_exists "handle_admin" "Admin command handler should be available"
    assert_function_exists "handle_backup" "Backup command handler should be available"
    assert_function_exists "handle_update" "Update command handler should be available"
    
    test_log "SUCCESS" "Command module loading tests passed"
    return 0
}

test_error_handling_integration() {
    test_log "INFO" "Testing error handling integration..."
    
    # Test invalid command
    local invalid_output
    invalid_output=$(run_cli_command invalid_command_xyz 2>&1) || true
    
    # Should provide helpful error message
    assert_contains "$invalid_output" "Unknown\|Invalid\|not found\|help" "Should provide helpful error for invalid command"
    
    # Test invalid subcommand
    local invalid_sub
    invalid_sub=$(run_cli_command admin invalid_subcommand 2>&1) || true
    
    # Should handle invalid subcommands gracefully
    assert_contains "$invalid_sub" "Unknown\|Invalid\|help" "Should handle invalid subcommands"
    
    test_log "SUCCESS" "Error handling integration tests passed"
    return 0
}

test_export_cleanup_validation() {
    test_log "INFO" "Testing export cleanup validation..."
    
    # Load all main modules
    source "$PROJECT_ROOT/src/_admin.sh" || return 1
    source "$PROJECT_ROOT/src/_backup.sh" || return 1
    source "$PROJECT_ROOT/src/_update.sh" || return 1
    source "$PROJECT_ROOT/src/_config.sh" || return 1
    source "$PROJECT_ROOT/src/_ssl.sh" || return 1
    
    # Count total exported functions from all modules
    local total_exports
    total_exports=$(declare -F | grep -E "(handle_|milou_|config_|ssl_)" | wc -l)
    
    # Should have a reasonable number of exports (updated expectation for modular system)
    if [[ $total_exports -gt 100 ]]; then
        test_log "ERROR" "Too many exported functions: $total_exports (should be < 100)"
        return 1
    fi
    
    test_log "SUCCESS" "Export cleanup validation tests passed (exports: $total_exports)"
    return 0
}

test_full_command_workflow() {
    test_log "INFO" "Testing full command workflow..."
    
    # Test a complete command workflow
    # 1. Check status
    local status_output
    status_output=$(run_cli_command status 2>&1) || true
    
    # 2. Show admin help
    local admin_help
    admin_help=$(run_cli_command admin --help 2>&1) || true
    
    # 3. Check SSL status
    local ssl_status
    ssl_status=$(run_cli_command ssl status 2>&1) || true
    
    # All should execute without syntax errors
    assert_not_contains "$status_output" "syntax error" "Status command should work"
    assert_not_contains "$admin_help" "syntax error" "Admin help should work"
    assert_not_contains "$ssl_status" "syntax error" "SSL status should work"
    
    test_log "SUCCESS" "Full command workflow tests passed"
    return 0
}

# =============================================================================
# Main Test Runner
# =============================================================================

run_integration_tests() {
    test_init "🔗 Command Integration Tests"
    
    # Setup test environment
    test_setup
    setup_integration_tests
    
    # Run individual tests
    test_run "CLI Basic Functionality" "test_cli_basic_functionality" "Tests basic CLI operation"
    test_run "Help System Integration" "test_help_system_integration" "Tests help system across commands"
    test_run "Admin Command Integration" "test_admin_command_integration" "Tests admin command structure"
    test_run "Backup Command Integration" "test_backup_command_integration" "Tests backup command structure"
    test_run "SSL Command Integration" "test_ssl_command_integration" "Tests SSL command structure"
    test_run "Update Command Integration" "test_update_command_integration" "Tests update command structure"
    test_run "New Self-Update Commands" "test_new_self_update_commands" "Tests new CLI update commands"
    test_run "Command Module Loading" "test_command_module_loading" "Tests command module loading"
    test_run "Error Handling Integration" "test_error_handling_integration" "Tests error handling across commands"
    test_run "Export Cleanup Validation" "test_export_cleanup_validation" "Tests that exports are cleaned up"
    test_run "Full Command Workflow" "test_full_command_workflow" "Tests complete command workflows"
    
    # Cleanup
    cleanup_integration_tests
    test_cleanup
    
    # Show results
    test_summary
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_integration_tests
fi 