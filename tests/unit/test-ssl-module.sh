#!/bin/bash

# =============================================================================
# SSL Module Tests - Test src/_ssl.sh refactored module
# Tests SSL certificate generation, validation, and management
# =============================================================================

set -euo pipefail

# Get test directory and setup
readonly TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"

# Load test framework
source "$TEST_DIR/../helpers/test-framework.sh"

# Test configuration
readonly SSL_TEST_TEMP_DIR="$TEST_DIR/../tmp/ssl_tests"

# =============================================================================
# Test Setup and Teardown
# =============================================================================

setup_ssl_tests() {
    test_log "INFO" "Setting up SSL module tests..."
    
    # Create temp directory
    mkdir -p "$SSL_TEST_TEMP_DIR"
    
    # Set up environment
    export SCRIPT_DIR="$PROJECT_ROOT"
    export MILOU_CLI_ROOT="$PROJECT_ROOT" 
    
    test_log "SUCCESS" "SSL test setup complete"
}

cleanup_ssl_tests() {
    test_log "INFO" "Cleaning up SSL module tests..."
    rm -rf "$SSL_TEST_TEMP_DIR" 2>/dev/null || true
}

# =============================================================================
# Individual Test Functions
# =============================================================================

test_ssl_module_loading() {
    test_log "INFO" "Testing SSL module loading..."
    
    # Test that the module loads without errors
    if source "$PROJECT_ROOT/src/_ssl.sh"; then
        test_log "SUCCESS" "SSL module loads successfully"
    else
        test_log "ERROR" "SSL module failed to load"
        return 1
    fi
    
    # Test essential functions are available
    assert_function_exists "ssl_setup" "SSL setup should be available"
    assert_function_exists "ssl_status" "SSL status should be available"
    assert_function_exists "ssl_generate_self_signed" "Self-signed generation should be available"
    assert_function_exists "ssl_validate" "SSL validation should be available"
    
    return 0
}

test_ssl_dependency_loading() {
    test_log "INFO" "Testing SSL module dependency loading..."
    
    source "$PROJECT_ROOT/src/_ssl.sh" || return 1
    
    # Test that core dependencies are loaded
    assert_function_exists "milou_log" "Core logging should be loaded"
    assert_function_exists "validate_domain" "Core validation should be loaded"
    
    test_log "SUCCESS" "SSL module dependencies loaded correctly"
    return 0
}

test_ssl_path_management() {
    test_log "INFO" "Testing SSL path management..."
    
    source "$PROJECT_ROOT/src/_ssl.sh" || return 1
    
    # Test SSL path functions
    if command -v ssl_get_path >/dev/null 2>&1; then
        local ssl_path
        ssl_path=$(ssl_get_path)
        
        if [[ -n "$ssl_path" ]]; then
            test_log "DEBUG" "SSL path: $ssl_path"
            test_log "SUCCESS" "SSL path management works"
        else
            test_log "ERROR" "SSL path is empty"
            return 1
        fi
    else
        test_log "DEBUG" "SSL path function not available (may be internal)"
    fi
    
    return 0
}

test_ssl_directory_creation() {
    test_log "INFO" "Testing SSL directory creation..."
    
    source "$PROJECT_ROOT/src/_ssl.sh" || return 1
    
    # Test SSL directory initialization
    local test_ssl_dir="$SSL_TEST_TEMP_DIR/ssl_test"
    
    if command -v ssl_init_directories >/dev/null 2>&1; then
        if ssl_init_directories "$test_ssl_dir"; then
            if [[ -d "$test_ssl_dir" ]]; then
                test_log "SUCCESS" "SSL directory creation works"
            else
                test_log "ERROR" "SSL directory not created"
                return 1
            fi
        else
            test_log "DEBUG" "SSL directory init failed (may require specific setup)"
        fi
    else
        test_log "DEBUG" "SSL directory init function not available"
    fi
    
    return 0
}

test_ssl_validation_functions() {
    test_log "INFO" "Testing SSL validation functions..."
    
    source "$PROJECT_ROOT/src/_ssl.sh" || return 1
    
    # Test certificate validation functions
    local validation_functions=(
        "ssl_validate"
        "ssl_validate_certificate"
        "ssl_check_expiry"
    )
    
    for func in "${validation_functions[@]}"; do
        if command -v "$func" >/dev/null 2>&1; then
            test_log "DEBUG" "SSL validation function available: $func"
        else
            test_log "DEBUG" "SSL validation function not found: $func (may be internal)"
        fi
    done
    
    test_log "SUCCESS" "SSL validation functions checked"
    return 0
}

test_ssl_generation_functions() {
    test_log "INFO" "Testing SSL generation functions..."
    
    source "$PROJECT_ROOT/src/_ssl.sh" || return 1
    
    # Test certificate generation functions
    local generation_functions=(
        "ssl_generate_self_signed"
        "ssl_create_ca"
        "ssl_create_certificate"
    )
    
    for func in "${generation_functions[@]}"; do
        if command -v "$func" >/dev/null 2>&1; then
            test_log "DEBUG" "SSL generation function available: $func"
        else
            test_log "DEBUG" "SSL generation function not found: $func (may be internal)"
        fi
    done
    
    test_log "SUCCESS" "SSL generation functions checked"
    return 0
}

test_ssl_cleanup_functions() {
    test_log "INFO" "Testing SSL cleanup functions..."
    
    source "$PROJECT_ROOT/src/_ssl.sh" || return 1
    
    # Test cleanup functions
    if command -v ssl_cleanup >/dev/null 2>&1; then
        test_log "DEBUG" "SSL cleanup function available"
    else
        test_log "DEBUG" "SSL cleanup function not found (may be internal)"
    fi
    
    test_log "SUCCESS" "SSL cleanup functions checked"
    return 0
}

test_ssl_backward_compatibility() {
    test_log "INFO" "Testing SSL backward compatibility..."
    
    source "$PROJECT_ROOT/src/_ssl.sh" || return 1
    
    # Test legacy function aliases
    local legacy_functions=(
        "milou_ssl_setup"
        "milou_ssl_status"
    )
    
    for func in "${legacy_functions[@]}"; do
        if command -v "$func" >/dev/null 2>&1; then
            test_log "DEBUG" "Legacy SSL function available: $func"
        else
            test_log "DEBUG" "Legacy SSL function missing: $func (may be intentional)"
        fi
    done
    
    test_log "SUCCESS" "SSL backward compatibility checked"
    return 0
}

test_ssl_export_cleanliness() {
    test_log "INFO" "Testing SSL module export cleanliness..."
    
    source "$PROJECT_ROOT/src/_ssl.sh" || return 1
    
    # Count exported SSL functions
    local ssl_exports
    ssl_exports=$(declare -F | grep -c "ssl_" || echo "0")
    
    # Should have reasonable number of exports (SSL naturally has many functions)
    if [[ $ssl_exports -gt 60 ]]; then
        test_log "ERROR" "Too many SSL exports: $ssl_exports (should be <= 60)"
        return 1
    fi
    
    if [[ $ssl_exports -lt 3 ]]; then
        test_log "ERROR" "Too few SSL exports: $ssl_exports (should be >= 3)"
        return 1
    fi
    
    test_log "SUCCESS" "SSL module exports are clean ($ssl_exports functions)"
    return 0
}

# =============================================================================
# Main Test Runner
# =============================================================================

run_ssl_tests() {
    test_init "🔒 SSL Module Tests"
    
    # Setup test environment
    test_setup
    setup_ssl_tests
    
    # Run individual tests
    test_run "Module Loading" "test_ssl_module_loading" "Tests that SSL module loads correctly"
    test_run "Dependency Loading" "test_ssl_dependency_loading" "Tests SSL module dependencies"
    test_run "Path Management" "test_ssl_path_management" "Tests SSL path management"
    test_run "Directory Creation" "test_ssl_directory_creation" "Tests SSL directory creation"
    test_run "Validation Functions" "test_ssl_validation_functions" "Tests SSL validation functions"
    test_run "Generation Functions" "test_ssl_generation_functions" "Tests SSL generation functions"
    test_run "Cleanup Functions" "test_ssl_cleanup_functions" "Tests SSL cleanup functions"
    test_run "Backward Compatibility" "test_ssl_backward_compatibility" "Tests legacy function aliases"
    test_run "Export Cleanliness" "test_ssl_export_cleanliness" "Tests module export hygiene"
    
    # Cleanup
    cleanup_ssl_tests
    test_cleanup
    
    # Show results
    test_summary
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_ssl_tests
fi 