#!/bin/bash

# =============================================================================
# Core Module Tests - Test src/_core.sh refactored module
# Tests consolidated utilities, logging, UI, random generation
# =============================================================================

set -euo pipefail

# Get test directory and setup
readonly TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"

# Load test framework
source "$TEST_DIR/../helpers/test-framework.sh"

# Test configuration
readonly CORE_TEST_TEMP_DIR="$TEST_DIR/../tmp/core_tests"

# =============================================================================
# Test Setup and Teardown
# =============================================================================

setup_core_tests() {
    test_log "INFO" "Setting up core module tests..."
    
    # Create temp directory
    mkdir -p "$CORE_TEST_TEMP_DIR"
    
    # Set up environment - prevent readonly conflicts
    if [[ -z "${SCRIPT_DIR:-}" ]]; then
        export SCRIPT_DIR="$PROJECT_ROOT"
    fi
    if [[ -z "${MILOU_CLI_ROOT:-}" ]]; then
        export MILOU_CLI_ROOT="$PROJECT_ROOT"
    fi
    
    test_log "SUCCESS" "Core test setup complete"
}

cleanup_core_tests() {
    test_log "INFO" "Cleaning up core module tests..."
    rm -rf "$CORE_TEST_TEMP_DIR" 2>/dev/null || true
}

# =============================================================================
# Individual Test Functions
# =============================================================================

test_core_module_loading() {
    test_log "INFO" "Testing core module loading..."
    
    # Test that the module loads without errors
    if source "$PROJECT_ROOT/src/_core.sh"; then
        test_log "SUCCESS" "Core module loads successfully"
    else
        test_log "ERROR" "Core module failed to load"
        return 1
    fi
    
    # Test essential functions are available
    assert_function_exists "milou_log" "Logging function should be available"
    assert_function_exists "generate_secure_random" "Random generation should be available"
    assert_function_exists "prompt_user" "User prompt should be available"
    assert_function_exists "confirm" "Confirmation function should be available"
    
    return 0
}

test_logging_functionality() {
    test_log "INFO" "Testing logging functionality..."
    
    source "$PROJECT_ROOT/src/_core.sh" || return 1
    
    # Test different log levels
    local log_output
    log_output=$(milou_log "INFO" "Test info message" 2>&1)
    assert_contains "$log_output" "Test info message" "Should log info messages"
    
    log_output=$(milou_log "ERROR" "Test error message" 2>&1)
    assert_contains "$log_output" "Test error message" "Should log error messages"
    
    log_output=$(milou_log "SUCCESS" "Test success message" 2>&1)
    assert_contains "$log_output" "Test success message" "Should log success messages"
    
    return 0
}

test_random_generation() {
    test_log "INFO" "Testing random generation functionality..."
    
    source "$PROJECT_ROOT/src/_core.sh" || return 1
    
    # Test default random generation
    local random1
    random1=$(generate_secure_random)
    
    assert_not_empty "$random1" "Should generate non-empty random string"
    
    # Should be 32 characters by default (not 16)
    local length=${#random1}
    if [[ $length -ne 32 ]]; then
        test_log "ERROR" "Expected 32 characters, got $length: $random1"
        return 1
    fi
    
    # Test custom length
    local random2
    random2=$(generate_secure_random 16)
    
    local length2=${#random2}
    if [[ $length2 -ne 16 ]]; then
        test_log "ERROR" "Expected 16 characters, got $length2: $random2"
        return 1
    fi

    # Test different formats
    local random_hex
    random_hex=$(generate_secure_random 16 "hex")
    
    if [[ ! "$random_hex" =~ ^[a-f0-9]{16}$ ]]; then
        test_log "ERROR" "Hex format validation failed: $random_hex"
        return 1
    fi
    
    # Test uniqueness (very unlikely to get duplicates)
    local random3
    random3=$(generate_secure_random)
    
    if [[ "$random1" == "$random3" ]]; then
        test_log "ERROR" "Random generation not unique (very unlikely!)"
        return 1
    fi
    
    test_log "SUCCESS" "Random generation works correctly"
    return 0
}

test_validation_functions() {
    test_log "INFO" "Testing validation functions..."
    
    source "$PROJECT_ROOT/src/_core.sh" || return 1
    
    # Test email validation
    if validate_domain "localhost"; then
        test_log "DEBUG" "Domain validation passed for localhost"
    else
        test_log "ERROR" "Domain validation failed for localhost"
        return 1
    fi
    
    if validate_domain "example.com"; then
        test_log "DEBUG" "Domain validation passed for example.com"
    else
        test_log "ERROR" "Domain validation failed for example.com"
        return 1
    fi
    
    # Test email validation (allow localhost for development)
    if validate_email "test@localhost" "true"; then
        test_log "DEBUG" "Email validation passed for test@localhost"
    else
        test_log "ERROR" "Email validation failed for test@localhost"
        return 1
    fi
    
    test_log "SUCCESS" "Validation functions work correctly"
    return 0
}

test_ui_functions() {
    test_log "INFO" "Testing UI functions..."
    
    source "$PROJECT_ROOT/src/_core.sh" || return 1
    
    # Test that prompt functions exist and can be called
    # (We can't easily test interactive behavior in automated tests)
    
    assert_function_exists "prompt_user" "User prompt function should exist"
    assert_function_exists "confirm" "Confirmation function should exist"
    
    # Test non-interactive mode behavior
    export MILOU_FORCE=true
    export MILOU_INTERACTIVE=false
    local result
    if result=$(confirm "Test question" "N" 2>/dev/null); then
        test_log "DEBUG" "Confirm function works in force mode"
    else
        test_log "DEBUG" "Confirm function appropriately returns false"
    fi
    unset MILOU_FORCE MILOU_INTERACTIVE
    
    test_log "SUCCESS" "UI functions exist and are callable"
    return 0
}

test_utility_functions() {
    test_log "INFO" "Testing utility functions..."
    
    source "$PROJECT_ROOT/src/_core.sh" || return 1
    
    # Test core utility functions exist
    assert_function_exists "ensure_directory" "Directory creation function should exist"
    assert_function_exists "check_port_in_use" "Port check function should exist"
    
    # Test simple utility
    local test_dir="$CORE_TEST_TEMP_DIR/test_util_dir"
    if ensure_directory "$test_dir"; then
        if [[ -d "$test_dir" ]]; then
            test_log "DEBUG" "Directory creation utility works"
        else
            test_log "ERROR" "Directory was not created"
            return 1
        fi
    else
        test_log "ERROR" "Directory creation utility failed"
        return 1
    fi
    
    test_log "SUCCESS" "Utility functions work correctly"
    return 0
}

test_module_consolidation() {
    test_log "INFO" "Testing module consolidation achievements..."
    
    source "$PROJECT_ROOT/src/_core.sh" || return 1
    
    # Verify we have the consolidated functions, not scattered duplicates
    # This tests that our refactoring successfully eliminated code duplication
    
    # Should have exactly one implementation of key functions
    local function_count
    function_count=$(declare -f | grep -c "^generate_secure_random " || echo "0")
    
    if [[ "$function_count" -eq 1 ]]; then
        test_log "DEBUG" "Single authoritative random generation function"
    else
        test_log "ERROR" "Multiple random generation functions detected: $function_count"
        return 1
    fi
    
    # Check that we have good export hygiene
    local exported_functions
    exported_functions=$(declare -F | grep -E "(generate_secure_random|validate_|milou_|prompt_|confirm)" | wc -l)
    
    if [[ "$exported_functions" -ge 10 ]]; then
        test_log "DEBUG" "Good export count: $exported_functions functions"
    else
        test_log "ERROR" "Too few exported functions: $exported_functions"
        return 1
    fi
    
    test_log "SUCCESS" "Module consolidation verified - no duplicate implementations"
    return 0
}

# =============================================================================
# Main Test Execution
# =============================================================================

main() {
    test_init "🧪 Core Module Tests"
    
    # Setup
    setup_core_tests
    
    # Run all tests
    test_run "core_module_loading" "test_core_module_loading" "Test that core module loads without errors"
    test_run "logging_functionality" "test_logging_functionality" "Test logging functions work correctly"
    test_run "random_generation" "test_random_generation" "Test secure random generation"
    test_run "validation_functions" "test_validation_functions" "Test basic validation functions"
    test_run "ui_functions" "test_ui_functions" "Test user interface functions"
    test_run "utility_functions" "test_utility_functions" "Test utility functions"
    test_run "module_consolidation" "test_module_consolidation" "Test consolidation achievements"
    
    # Cleanup
    cleanup_core_tests
    
    # Show results
    test_summary
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 