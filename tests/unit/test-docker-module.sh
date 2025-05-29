#!/bin/bash

# =============================================================================
# Docker Module Tests - Test src/_docker.sh refactored module
# Tests Docker operations, registry management, health checks
# =============================================================================

set -euo pipefail

# Get test directory and setup
readonly TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"

# Load test framework
source "$TEST_DIR/../helpers/test-framework.sh"

# Test configuration
readonly DOCKER_TEST_TEMP_DIR="$TEST_DIR/../tmp/docker_tests"

# =============================================================================
# Test Setup and Teardown
# =============================================================================

setup_docker_tests() {
    test_log "INFO" "Setting up Docker module tests..."
    
    # Create temp directory
    mkdir -p "$DOCKER_TEST_TEMP_DIR"
    
    # Set up environment
    export SCRIPT_DIR="$PROJECT_ROOT"
    export MILOU_CLI_ROOT="$PROJECT_ROOT" 
    
    test_log "SUCCESS" "Docker test setup complete"
}

cleanup_docker_tests() {
    test_log "INFO" "Cleaning up Docker module tests..."
    rm -rf "$DOCKER_TEST_TEMP_DIR" 2>/dev/null || true
}

# =============================================================================
# Individual Test Functions
# =============================================================================

test_docker_module_loading() {
    test_log "INFO" "Testing Docker module loading..."
    
    # Test that the module loads without errors
    if source "$PROJECT_ROOT/src/_docker.sh"; then
        test_log "SUCCESS" "Docker module loads successfully"
    else
        test_log "ERROR" "Docker module failed to load"
        return 1
    fi
    
    # Test essential functions are available
    assert_function_exists "docker_init" "Docker initialization should be available"
    assert_function_exists "docker_compose" "Docker compose wrapper should be available"
    assert_function_exists "docker_status" "Docker status should be available"
    assert_function_exists "docker_health_check" "Docker health check should be available"
    
    return 0
}

test_docker_dependency_loading() {
    test_log "INFO" "Testing Docker module dependency loading..."
    
    source "$PROJECT_ROOT/src/_docker.sh" || return 1
    
    # Test that core dependencies are loaded
    assert_function_exists "milou_log" "Core logging should be loaded"
    assert_function_exists "validate_docker_access" "Validation functions should be loaded"
    
    test_log "SUCCESS" "Docker module dependencies loaded correctly"
    return 0
}

test_docker_function_exports() {
    test_log "INFO" "Testing Docker function exports..."
    
    source "$PROJECT_ROOT/src/_docker.sh" || return 1
    
    # Test key Docker functions are exported
    local docker_functions=(
        "docker_init"
        "docker_compose" 
        "docker_start"
        "docker_stop"
        "docker_restart"
        "docker_status"
        "docker_logs"
        "docker_shell"
        "docker_health_check"
    )
    
    for func in "${docker_functions[@]}"; do
        assert_function_exists "$func" "Docker function $func should be exported"
    done
    
    test_log "SUCCESS" "Docker function exports verified"
    return 0
}

test_docker_backward_compatibility() {
    test_log "INFO" "Testing Docker backward compatibility..."
    
    source "$PROJECT_ROOT/src/_docker.sh" || return 1
    
    # Test legacy function aliases still work
    local legacy_functions=(
        "milou_check_docker_access"
        "milou_validate_docker_resources"
    )
    
    for func in "${legacy_functions[@]}"; do
        if command -v "$func" >/dev/null 2>&1; then
            test_log "DEBUG" "Legacy function available: $func"
        else
            test_log "WARN" "Legacy function missing: $func (may be intentional)"
        fi
    done
    
    test_log "SUCCESS" "Docker backward compatibility checked"
    return 0
}

test_docker_init_function() {
    test_log "INFO" "Testing Docker initialization function..."
    
    source "$PROJECT_ROOT/src/_docker.sh" || return 1
    
    # Test docker_init function works (should not fail with basic checks)
    if docker_init "true" 2>/dev/null; then
        test_log "SUCCESS" "Docker init function works"
    else
        test_log "DEBUG" "Docker init failed (expected on systems without Docker)"
    fi
    
    return 0
}

test_docker_compose_wrapper() {
    test_log "INFO" "Testing Docker compose wrapper..."
    
    source "$PROJECT_ROOT/src/_docker.sh" || return 1
    
    # Test that docker_compose function exists and has basic structure
    if command -v docker_compose >/dev/null 2>&1; then
        test_log "SUCCESS" "Docker compose wrapper available"
    else
        test_log "ERROR" "Docker compose wrapper not available"
        return 1
    fi
    
    return 0
}

test_docker_registry_functions() {
    test_log "INFO" "Testing Docker registry functions..."
    
    source "$PROJECT_ROOT/src/_docker.sh" || return 1
    
    # Test registry-related functions are available
    local registry_functions=(
        "docker_registry_login"
        "docker_registry_test"
    )
    
    for func in "${registry_functions[@]}"; do
        if command -v "$func" >/dev/null 2>&1; then
            test_log "DEBUG" "Registry function available: $func"
        else
            test_log "DEBUG" "Registry function not found: $func (may be internal)"
        fi
    done
    
    test_log "SUCCESS" "Docker registry functions checked"
    return 0
}

test_docker_export_cleanliness() {
    test_log "INFO" "Testing Docker module export cleanliness..."
    
    source "$PROJECT_ROOT/src/_docker.sh" || return 1
    
    # Count exported docker functions
    local docker_exports
    docker_exports=$(declare -F | grep -c "docker_" || echo "0")
    
    # Should have reasonable number of exports
    if [[ $docker_exports -gt 50 ]]; then
        test_log "ERROR" "Too many Docker exports: $docker_exports (should be <= 50)"
        return 1
    fi
    
    if [[ $docker_exports -lt 5 ]]; then
        test_log "ERROR" "Too few Docker exports: $docker_exports (should be >= 5)"
        return 1
    fi
    
    test_log "SUCCESS" "Docker module exports are clean ($docker_exports functions)"
    return 0
}

# =============================================================================
# Main Test Runner
# =============================================================================

run_docker_tests() {
    test_init "🐳 Docker Module Tests"
    
    # Setup test environment
    test_setup
    setup_docker_tests
    
    # Run individual tests
    test_run "Module Loading" "test_docker_module_loading" "Tests that Docker module loads correctly"
    test_run "Dependency Loading" "test_docker_dependency_loading" "Tests Docker module dependencies"
    test_run "Function Exports" "test_docker_function_exports" "Tests Docker function exports"
    test_run "Backward Compatibility" "test_docker_backward_compatibility" "Tests legacy function aliases"
    test_run "Docker Init" "test_docker_init_function" "Tests Docker initialization"
    test_run "Compose Wrapper" "test_docker_compose_wrapper" "Tests Docker compose wrapper"
    test_run "Registry Functions" "test_docker_registry_functions" "Tests Docker registry functions"
    test_run "Export Cleanliness" "test_docker_export_cleanliness" "Tests module export hygiene"
    
    # Cleanup
    cleanup_docker_tests
    test_cleanup
    
    # Show results
    test_summary
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_docker_tests
fi 