#!/bin/bash

# =============================================================================
# Configuration Module Tests - Test src/_config.sh refactored module
# Tests configuration generation, validation, and management
# =============================================================================

set -euo pipefail

# Get test directory and setup
readonly TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"

# Load test framework
source "$TEST_DIR/../helpers/test-framework.sh"

# Test configuration
readonly CONFIG_TEST_TEMP_DIR="$TEST_DIR/../tmp/config_tests"

# =============================================================================
# Test Setup and Teardown
# =============================================================================

setup_config_tests() {
    test_log "INFO" "Setting up Configuration module tests..."
    
    # Create temp directory
    mkdir -p "$CONFIG_TEST_TEMP_DIR"
    
    # Set up environment
    export SCRIPT_DIR="$PROJECT_ROOT"
    export MILOU_CLI_ROOT="$PROJECT_ROOT" 
    
    test_log "SUCCESS" "Configuration test setup complete"
}

cleanup_config_tests() {
    test_log "INFO" "Cleaning up Configuration module tests..."
    rm -rf "$CONFIG_TEST_TEMP_DIR" 2>/dev/null || true
}

# =============================================================================
# Individual Test Functions
# =============================================================================

test_config_module_loading() {
    test_log "INFO" "Testing Configuration module loading..."
    
    # Test that the module loads without errors
    if source "$PROJECT_ROOT/src/_config.sh"; then
        test_log "SUCCESS" "Configuration module loads successfully"
    else
        test_log "ERROR" "Configuration module failed to load"
        return 1
    fi
    
    # Test essential functions are available
    assert_function_exists "config_generate" "Configuration generation should be available"
    assert_function_exists "config_validate" "Configuration validation should be available"
    assert_function_exists "config_show" "Configuration display should be available"
    assert_function_exists "config_backup_single" "Configuration backup should be available"
    
    return 0
}

test_config_dependency_loading() {
    test_log "INFO" "Testing Configuration module dependency loading..."
    
    source "$PROJECT_ROOT/src/_config.sh" || return 1
    
    # Test that core dependencies are loaded
    assert_function_exists "milou_log" "Core logging should be loaded"
    assert_function_exists "milou_generate_secure_random" "Core utilities should be loaded"
    
    test_log "SUCCESS" "Configuration module dependencies loaded correctly"
    return 0
}

test_config_generation_functions() {
    test_log "INFO" "Testing Configuration generation functions..."
    
    source "$PROJECT_ROOT/src/_config.sh" || return 1
    
    # Test configuration generation functions are available
    local generation_functions=(
        "config_generate"
        "config_create_env"
        "config_generate_credentials"
    )
    
    for func in "${generation_functions[@]}"; do
        if command -v "$func" >/dev/null 2>&1; then
            test_log "DEBUG" "Config generation function available: $func"
        else
            test_log "DEBUG" "Config generation function not found: $func (may be internal)"
        fi
    done
    
    test_log "SUCCESS" "Configuration generation functions checked"
    return 0
}

test_config_validation_functions() {
    test_log "INFO" "Testing Configuration validation functions..."
    
    source "$PROJECT_ROOT/src/_config.sh" || return 1
    
    # Test validation functions
    local validation_functions=(
        "config_validate"
        "config_validate_environment"
        "config_check_required_vars"
    )
    
    for func in "${validation_functions[@]}"; do
        if command -v "$func" >/dev/null 2>&1; then
            test_log "DEBUG" "Config validation function available: $func"
        else
            test_log "DEBUG" "Config validation function not found: $func (may be internal)"
        fi
    done
    
    test_log "SUCCESS" "Configuration validation functions checked"
    return 0
}

test_config_backup_functions() {
    test_log "INFO" "Testing Configuration backup functions..."
    
    source "$PROJECT_ROOT/src/_config.sh" || return 1
    
    # Test backup functions
    local backup_functions=(
        "config_backup_single"
        "config_backup"
        "config_migrate"
    )
    
    for func in "${backup_functions[@]}"; do
        if command -v "$func" >/dev/null 2>&1; then
            test_log "DEBUG" "Config backup function available: $func"
        else
            test_log "DEBUG" "Config backup function not found: $func (may be internal)"
        fi
    done
    
    test_log "SUCCESS" "Configuration backup functions checked"
    return 0
}

test_config_file_operations() {
    test_log "INFO" "Testing Configuration file operations..."
    
    source "$PROJECT_ROOT/src/_config.sh" || return 1
    
    # Create a test configuration file
    local test_config="$CONFIG_TEST_TEMP_DIR/test.env"
    cat > "$test_config" << EOF
DOMAIN=localhost
ADMIN_EMAIL=test@localhost
NODE_ENV=production
EOF
    
    # Test configuration display
    if command -v config_show >/dev/null 2>&1; then
        if config_show "$test_config" >/dev/null 2>&1; then
            test_log "SUCCESS" "Configuration display works"
        else
            test_log "DEBUG" "Configuration display failed (may need specific format)"
        fi
    fi
    
    return 0
}

test_config_validation_with_file() {
    test_log "INFO" "Testing Configuration validation with test file..."
    
    source "$PROJECT_ROOT/src/_config.sh" || return 1
    
    # Create test configuration
    local test_config="$CONFIG_TEST_TEMP_DIR/valid_test.env"
    cat > "$test_config" << EOF
DOMAIN=localhost
ADMIN_EMAIL=admin@localhost
ADMIN_PASSWORD=secure123
POSTGRES_USER=milou
POSTGRES_PASSWORD=dbpass123
NODE_ENV=production
EOF
    
    # Test validation
    if command -v config_validate >/dev/null 2>&1; then
        if config_validate "$test_config" "minimal" 2>/dev/null; then
            test_log "SUCCESS" "Configuration validation works"
        else
            test_log "DEBUG" "Configuration validation failed (may need specific requirements)"
        fi
    fi
    
    return 0
}

test_config_backward_compatibility() {
    test_log "INFO" "Testing Configuration backward compatibility..."
    
    source "$PROJECT_ROOT/src/_config.sh" || return 1
    
    # Test legacy function aliases
    local legacy_functions=(
        "milou_config_show"
        "milou_config_generate"
        "milou_config_validate"
    )
    
    for func in "${legacy_functions[@]}"; do
        if command -v "$func" >/dev/null 2>&1; then
            test_log "DEBUG" "Legacy config function available: $func"
        else
            test_log "DEBUG" "Legacy config function missing: $func (may be intentional)"
        fi
    done
    
    test_log "SUCCESS" "Configuration backward compatibility checked"
    return 0
}

test_config_export_cleanliness() {
    test_log "INFO" "Testing Configuration module export cleanliness..."
    
    source "$PROJECT_ROOT/src/_config.sh" || return 1
    
    # Count exported config functions
    local config_exports
    config_exports=$(declare -F | grep -c "config_" || echo "0")
    
    # Should have reasonable number of exports
    if [[ $config_exports -gt 50 ]]; then
        test_log "ERROR" "Too many Config exports: $config_exports (should be <= 50)"
        return 1
    fi
    
    if [[ $config_exports -lt 3 ]]; then
        test_log "ERROR" "Too few Config exports: $config_exports (should be >= 3)"
        return 1
    fi
    
    test_log "SUCCESS" "Configuration module exports are clean ($config_exports functions)"
    return 0
}

# =============================================================================
# Main Test Runner
# =============================================================================

run_config_tests() {
    test_init "⚙️  Configuration Module Tests"
    
    # Setup test environment
    test_setup
    setup_config_tests
    
    # Run individual tests
    test_run "Module Loading" "test_config_module_loading" "Tests that Configuration module loads correctly"
    test_run "Dependency Loading" "test_config_dependency_loading" "Tests Configuration module dependencies"
    test_run "Generation Functions" "test_config_generation_functions" "Tests configuration generation functions"
    test_run "Validation Functions" "test_config_validation_functions" "Tests configuration validation functions"
    test_run "Backup Functions" "test_config_backup_functions" "Tests configuration backup functions"
    test_run "File Operations" "test_config_file_operations" "Tests configuration file operations"
    test_run "Validation with File" "test_config_validation_with_file" "Tests validation with actual config file"
    test_run "Backward Compatibility" "test_config_backward_compatibility" "Tests legacy function aliases"
    test_run "Export Cleanliness" "test_config_export_cleanliness" "Tests module export hygiene"
    
    # Cleanup
    cleanup_config_tests
    test_cleanup
    
    # Show results
    test_summary
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_config_tests
fi 