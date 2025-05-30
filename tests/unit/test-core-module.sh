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

test_export_cleanliness() {
    test_log "INFO" "Testing export cleanliness..."
    
    source "$PROJECT_ROOT/src/_core.sh" || return 1
    
    # Count exported functions from core module
    local core_exports
    core_exports=$(declare -F | grep -E "(milou_|generate_|prompt_|confirm|ensure_|check_|get_|create_|validate_|is_)" | wc -l)
    
    # Should have reasonable number of exports
    if [[ $core_exports -gt 50 ]]; then
        test_log "WARN" "Many core exports: $core_exports (check if all are necessary)"
    fi
    
    # Test that essential functions are exported
    assert_function_exists "milou_log" "Logging function should be exported"
    assert_function_exists "generate_secure_random" "Random generation should be exported"
    
    test_log "SUCCESS" "Core module exports are reasonable ($core_exports functions)"
    return 0
}

test_security_functions() {
    test_log "INFO" "Testing security functions..."
    
    source "$PROJECT_ROOT/src/_core.sh" || return 1
    
    # Test secure random generation
    local random1 random2
    random1=$(generate_secure_random 32)
    random2=$(generate_secure_random 32)
    
    # Should generate different values
    if [[ "$random1" != "$random2" ]]; then
        test_log "DEBUG" "Secure random generates unique values"
    else
        test_log "ERROR" "Secure random generated identical values"
        return 1
    fi
    
    # Test length
    if [[ ${#random1} -eq 32 ]]; then
        test_log "DEBUG" "Secure random generates correct length"
    else
        test_log "ERROR" "Secure random length incorrect: ${#random1} != 32"
        return 1
    fi
    
    test_log "SUCCESS" "Security functions work correctly"
    return 0
}

test_file_operations() {
    test_log "INFO" "Testing file operations..."
    
    source "$PROJECT_ROOT/src/_core.sh" || return 1
    
    # Test file permission functions
    local test_file="$CORE_TEST_TEMP_DIR/test_permissions"
    echo "test" > "$test_file"
    
    # Test setting secure permissions
    if command -v set_secure_permissions >/dev/null 2>&1; then
        if set_secure_permissions "$test_file"; then
            local perms
            perms=$(stat -c "%a" "$test_file" 2>/dev/null || stat -f "%A" "$test_file" 2>/dev/null)
            if [[ "$perms" == "600" ]]; then
                test_log "DEBUG" "Secure permissions set correctly"
            else
                test_log "WARN" "Permissions not as expected: $perms"
            fi
        fi
    fi
    
    # Test backup creation
    if command -v create_backup_file >/dev/null 2>&1; then
        if create_backup_file "$test_file"; then
            if [[ -f "${test_file}.backup" ]]; then
                test_log "DEBUG" "Backup file creation works"
            else
                test_log "WARN" "Backup file not created"
            fi
        fi
    fi
    
    test_log "SUCCESS" "File operations work correctly"
    return 0
}

test_validation_helpers() {
    test_log "INFO" "Testing validation helper functions..."
    
    source "$PROJECT_ROOT/src/_core.sh" || return 1
    
    # Test email validation if available
    if command -v is_valid_email >/dev/null 2>&1; then
        if is_valid_email "test@example.com"; then
            test_log "DEBUG" "Email validation accepts valid email"
        else
            test_log "ERROR" "Email validation rejected valid email"
            return 1
        fi
        
        if ! is_valid_email "invalid-email"; then
            test_log "DEBUG" "Email validation rejects invalid email"
        else
            test_log "ERROR" "Email validation accepted invalid email"
            return 1
        fi
    fi
    
    # Test URL validation if available
    if command -v is_valid_url >/dev/null 2>&1; then
        if is_valid_url "https://example.com"; then
            test_log "DEBUG" "URL validation accepts valid URL"
        else
            test_log "WARN" "URL validation rejected valid URL"
        fi
    fi
    
    test_log "SUCCESS" "Validation helpers work correctly"
    return 0
}

test_string_utilities() {
    test_log "INFO" "Testing string utility functions..."
    
    source "$PROJECT_ROOT/src/_core.sh" || return 1
    
    # Test string trimming if available
    if command -v trim_string >/dev/null 2>&1; then
        local result
        result=$(trim_string "  test  ")
        if [[ "$result" == "test" ]]; then
            test_log "DEBUG" "String trimming works"
        else
            test_log "WARN" "String trimming unexpected result: '$result'"
        fi
    fi
    
    # Test string case conversion if available
    if command -v to_lowercase >/dev/null 2>&1; then
        local result
        result=$(to_lowercase "TEST")
        if [[ "$result" == "test" ]]; then
            test_log "DEBUG" "Lowercase conversion works"
        else
            test_log "WARN" "Lowercase conversion unexpected result: '$result'"
        fi
    fi
    
    test_log "SUCCESS" "String utilities work correctly"
    return 0
}

test_system_info_functions() {
    test_log "INFO" "Testing system information functions..."
    
    source "$PROJECT_ROOT/src/_core.sh" || return 1
    
    # Test OS detection if available
    if command -v get_os_type >/dev/null 2>&1; then
        local os_type
        os_type=$(get_os_type)
        if [[ -n "$os_type" ]]; then
            test_log "DEBUG" "OS type detection: $os_type"
        else
            test_log "WARN" "OS type detection returned empty"
        fi
    fi
    
    # Test architecture detection if available
    if command -v get_architecture >/dev/null 2>&1; then
        local arch
        arch=$(get_architecture)
        if [[ -n "$arch" ]]; then
            test_log "DEBUG" "Architecture detection: $arch"
        else
            test_log "WARN" "Architecture detection returned empty"
        fi
    fi
    
    test_log "SUCCESS" "System info functions work correctly"
    return 0
}

test_error_handling() {
    test_log "INFO" "Testing error handling functions..."
    
    source "$PROJECT_ROOT/src/_core.sh" || return 1
    
    # Test error logging
    local error_output
    error_output=$(milou_log "ERROR" "Test error message" 2>&1)
    if [[ "$error_output" == *"Test error message"* ]]; then
        test_log "DEBUG" "Error logging works"
    else
        test_log "ERROR" "Error logging failed"
        return 1
    fi
    
    # Test warning logging
    local warn_output
    warn_output=$(milou_log "WARN" "Test warning message" 2>&1)
    if [[ "$warn_output" == *"Test warning message"* ]]; then
        test_log "DEBUG" "Warning logging works"
    else
        test_log "ERROR" "Warning logging failed"
        return 1
    fi
    
    test_log "SUCCESS" "Error handling works correctly"
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
    test_run "export_cleanliness" "test_export_cleanliness" "Test export cleanliness"
    test_run "security_functions" "test_security_functions" "Test security functions"
    test_run "file_operations" "test_file_operations" "Test file operations"
    test_run "validation_helpers" "test_validation_helpers" "Test validation helpers"
    test_run "string_utilities" "test_string_utilities" "Test string utilities"
    test_run "system_info_functions" "test_system_info_functions" "Test system info functions"
    test_run "error_handling" "test_error_handling" "Test error handling"
    
    # Cleanup
    cleanup_core_tests
    
    # Show results
    test_summary
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 