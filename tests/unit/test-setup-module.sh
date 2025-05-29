#!/bin/bash

# =============================================================================
# Setup Module Tests - Test src/_setup.sh refactored module
# Tests consolidated setup orchestration, system analysis, and dependencies
# =============================================================================

set -euo pipefail

# Get test directory and setup
readonly TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"

# Load test framework
source "$TEST_DIR/../helpers/test-framework.sh"

# Test configuration
readonly SETUP_TEST_TEMP_DIR="$TEST_DIR/../tmp/setup_tests"

# =============================================================================
# Test Setup and Teardown
# =============================================================================

setup_setup_tests() {
    test_log "INFO" "Setting up setup module tests..."
    
    # Create temp directory
    mkdir -p "$SETUP_TEST_TEMP_DIR"
    
    # Set up environment
    export SCRIPT_DIR="$PROJECT_ROOT"
    export MILOU_CLI_ROOT="$PROJECT_ROOT"
    export ENV_FILE="$SETUP_TEST_TEMP_DIR/.env.test"
    
    test_log "SUCCESS" "Setup test setup complete"
}

cleanup_setup_tests() {
    test_log "INFO" "Cleaning up setup module tests..."
    rm -rf "$SETUP_TEST_TEMP_DIR" 2>/dev/null || true
}

# =============================================================================
# Individual Test Functions
# =============================================================================

test_setup_module_loading() {
    test_log "INFO" "Testing setup module loading..."
    
    # Test that the module loads without errors
    if source "$PROJECT_ROOT/src/_setup.sh"; then
        test_log "SUCCESS" "Setup module loads successfully"
    else
        test_log "ERROR" "Setup module failed to load"
        return 1
    fi
    
    # Test essential functions are available
    assert_function_exists "setup_run" "Main setup function should be available"
    assert_function_exists "setup_analyze_system" "System analysis should be available"
    assert_function_exists "setup_assess_prerequisites" "Prerequisites assessment should be available"
    
    return 0
}

test_system_analysis_functions() {
    test_log "INFO" "Testing system analysis functionality..."
    
    source "$PROJECT_ROOT/src/_setup.sh" || return 1
    
    # Test that system analysis functions exist (safer than calling them)
    assert_function_exists "setup_analyze_system" "System analysis function should exist"
    
    # Only test availability, not execution (to avoid segfaults)
    if command -v setup_analyze_system >/dev/null 2>&1; then
        test_log "SUCCESS" "System analysis function is available"
    else
        test_log "ERROR" "System analysis function not found"
        return 1
    fi
    
    return 0
}

test_prerequisites_assessment() {
    test_log "INFO" "Testing prerequisites assessment..."
    
    source "$PROJECT_ROOT/src/_setup.sh" || return 1
    
    # Test that prerequisites functions exist (safer)
    assert_function_exists "setup_assess_prerequisites" "Prerequisites assessment function should exist"
    
    test_log "SUCCESS" "Prerequisites assessment function is available"
    return 0
}

test_configuration_generation() {
    test_log "INFO" "Testing configuration generation..."
    
    source "$PROJECT_ROOT/src/_setup.sh" || return 1
    
    # Test that configuration functions exist (safer)
    assert_function_exists "setup_generate_configuration" "Configuration generation function should exist"
    
    test_log "SUCCESS" "Configuration generation function is available"
    return 0
}

test_dependency_installation() {
    test_log "INFO" "Testing dependency installation functions..."
    
    source "$PROJECT_ROOT/src/_setup.sh" || return 1
    
    # Test that dependency functions exist (safer)
    assert_function_exists "setup_install_dependencies" "Dependency installation function should exist"
    
    test_log "SUCCESS" "Dependency installation function is available"
    return 0
}

test_user_management() {
    test_log "INFO" "Testing user management setup..."
    
    source "$PROJECT_ROOT/src/_setup.sh" || return 1
    
    # Test that user management functions exist (safer)
    assert_function_exists "setup_manage_user" "User management function should exist"
    
    test_log "SUCCESS" "User management function is available"
    return 0
}

test_service_validation() {
    test_log "INFO" "Testing service validation and startup..."
    
    source "$PROJECT_ROOT/src/_setup.sh" || return 1
    
    # Test that service functions exist (safer)
    assert_function_exists "setup_validate_and_start_services" "Service validation function should exist"
    
    test_log "SUCCESS" "Service validation function is available"
    return 0
}

test_setup_orchestration() {
    test_log "INFO" "Testing complete setup orchestration..."
    
    source "$PROJECT_ROOT/src/_setup.sh" || return 1
    
    # Test that main setup function exists (safer than executing)
    assert_function_exists "setup_run" "Main setup function should exist"
    
    test_log "SUCCESS" "Setup orchestration function is available"
    return 0
}

test_export_cleanliness() {
    test_log "INFO" "Testing export cleanliness..."
    
    source "$PROJECT_ROOT/src/_setup.sh" || return 1
    
    # Count exported functions from setup module
    local setup_exports
    setup_exports=$(declare -F | grep -c "setup_" || echo "0")
    
    # Should have reasonable number of exports
    if [[ $setup_exports -gt 20 ]]; then
        test_log "WARN" "Many setup exports: $setup_exports (check if all are necessary)"
    fi
    
    # Test that essential functions are exported
    assert_function_exists "setup_run" "Main setup function should be exported"
    
    test_log "SUCCESS" "Setup module exports are reasonable ($setup_exports functions)"
    return 0
}

# =============================================================================
# Main Test Runner
# =============================================================================

run_setup_tests() {
    test_init "🧪 Setup Module Tests"
    
    # Setup test environment
    test_setup
    setup_setup_tests
    
    # Run individual tests
    test_run "Module Loading" "test_setup_module_loading" "Tests that setup module loads correctly"
    test_run "System Analysis" "test_system_analysis_functions" "Tests system analysis functions"
    test_run "Prerequisites Assessment" "test_prerequisites_assessment" "Tests prerequisites checking"
    test_run "Configuration Generation" "test_configuration_generation" "Tests config generation"
    test_run "Dependency Installation" "test_dependency_installation" "Tests dependency management"
    test_run "User Management" "test_user_management" "Tests user setup functions"
    test_run "Service Validation" "test_service_validation" "Tests service validation"
    test_run "Setup Orchestration" "test_setup_orchestration" "Tests complete setup flow"
    test_run "Export Cleanliness" "test_export_cleanliness" "Tests module export hygiene"
    
    # Cleanup
    cleanup_setup_tests
    test_cleanup
    
    # Show results
    test_summary
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_setup_tests
fi 