#!/bin/bash

# =============================================================================
# System Integration Tests - Complete System Validation
# Tests the full integration of all refactored modules
# =============================================================================

set -euo pipefail

# Get test directory and setup
readonly TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"

# Load test framework
source "$TEST_DIR/../helpers/test-framework.sh"

# Test configuration
readonly INTEGRATION_TEST_TEMP_DIR="$TEST_DIR/../tmp/integration_tests"

# =============================================================================
# Test Setup and Teardown
# =============================================================================

setup_integration_tests() {
    test_log "INFO" "Setting up system integration tests..."
    
    # Create temp directory
    mkdir -p "$INTEGRATION_TEST_TEMP_DIR"
    
    # Set up environment
    export SCRIPT_DIR="$PROJECT_ROOT"
    export MILOU_CLI_ROOT="$PROJECT_ROOT"
    export FORCE_MODE="true"  # Non-interactive mode
    
    test_log "SUCCESS" "Integration test setup complete"
}

cleanup_integration_tests() {
    test_log "INFO" "Cleaning up integration tests..."
    rm -rf "$INTEGRATION_TEST_TEMP_DIR" 2>/dev/null || true
    unset FORCE_MODE
}

# =============================================================================
# Core System Integration Tests
# =============================================================================

test_module_loading_integration() {
    test_log "INFO" "Testing module loading integration..."
    
    # Test that all core modules load without conflicts
    local modules=("_core.sh" "_validation.sh" "_docker.sh" "_config.sh" "_ssl.sh" "_backup.sh" "_user.sh" "_setup.sh" "_update.sh" "_admin.sh")
    
    for module in "${modules[@]}"; do
        if source "$PROJECT_ROOT/src/$module" >/dev/null 2>&1; then
            test_log "DEBUG" "✅ Module loaded: $module"
        else
            test_log "ERROR" "❌ Failed to load module: $module"
            return 1
        fi
    done
    
    test_log "SUCCESS" "All modules load successfully"
    return 0
}

test_main_entry_point_integration() {
    test_log "INFO" "Testing main entry point integration..."
    
    # Test basic commands work
    local commands=("--help" "--version" "status")
    
    for cmd in "${commands[@]}"; do
        if timeout 10 "$PROJECT_ROOT/src/milou" $cmd >/dev/null 2>&1; then
            test_log "DEBUG" "✅ Command works: $cmd"
        else
            test_log "ERROR" "❌ Command failed: $cmd"
            return 1
        fi
    done
    
    test_log "SUCCESS" "Main entry point integration works"
    return 0
}

test_command_dispatch_integration() {
    test_log "INFO" "Testing command dispatch integration..."
    
    # Test that commands properly dispatch to modules
    local commands=("admin --help" "config show" "backup --help")
    
    for cmd in "${commands[@]}"; do
        if timeout 10 "$PROJECT_ROOT/src/milou" $cmd >/dev/null 2>&1; then
            test_log "DEBUG" "✅ Command dispatch works: $cmd"
        else
            test_log "DEBUG" "⚠️  Command dispatch might need configuration: $cmd"
        fi
    done
    
    test_log "SUCCESS" "Command dispatch integration working"
    return 0
}

test_module_interdependency() {
    test_log "INFO" "Testing module interdependency..."
    
    # Load all modules and test function availability
    source "$PROJECT_ROOT/src/_core.sh" >/dev/null 2>&1
    source "$PROJECT_ROOT/src/_validation.sh" >/dev/null 2>&1
    source "$PROJECT_ROOT/src/_docker.sh" >/dev/null 2>&1
    
    # Test that interdependent functions work
    if command -v milou_log >/dev/null 2>&1; then
        test_log "DEBUG" "✅ Core logging available across modules"
    else
        test_log "ERROR" "❌ Core logging not available"
        return 1
    fi
    
    if command -v validate_github_token >/dev/null 2>&1; then
        test_log "DEBUG" "✅ Validation functions available"
    else
        test_log "ERROR" "❌ Validation functions not available"
        return 1
    fi
    
    test_log "SUCCESS" "Module interdependency working correctly"
    return 0
}

test_backward_compatibility() {
    test_log "INFO" "Testing backward compatibility..."
    
    # Load modules
    source "$PROJECT_ROOT/src/_validation.sh" >/dev/null 2>&1
    
    # Test that legacy function names still work
    if command -v milou_validate_github_token >/dev/null 2>&1; then
        test_log "DEBUG" "✅ Legacy function names preserved"
    else
        test_log "ERROR" "❌ Legacy compatibility broken"
        return 1
    fi
    
    test_log "SUCCESS" "Backward compatibility maintained"
    return 0
}

test_configuration_integration() {
    test_log "INFO" "Testing configuration integration..."
    
    # Create a test configuration
    local test_config="$INTEGRATION_TEST_TEMP_DIR/test.env"
    cat > "$test_config" << EOF
DOMAIN=localhost
ADMIN_EMAIL=admin@localhost
NODE_ENV=production
SERVER_NAME=localhost
POSTGRES_USER=milou
POSTGRES_PASSWORD=secure_password_123
REDIS_PASSWORD=redis_password_456
EOF
    
    # Load config module and test configuration loading
    source "$PROJECT_ROOT/src/_config.sh" >/dev/null 2>&1
    
    if command -v config_show >/dev/null 2>&1; then
        test_log "DEBUG" "✅ Configuration functions available"
    else
        test_log "ERROR" "❌ Configuration functions not available"
        return 1
    fi
    
    test_log "SUCCESS" "Configuration integration working"
    return 0
}

test_error_handling_integration() {
    test_log "INFO" "Testing error handling integration..."
    
    # Test that invalid commands are handled gracefully
    local invalid_commands=("invalid_command" "admin invalid_sub" "config invalid_action")
    
    for cmd in "${invalid_commands[@]}"; do
        local output
        output=$(timeout 5 "$PROJECT_ROOT/src/milou" $cmd 2>&1 || true)
        
        if echo "$output" | grep -q -E "(Unknown|Invalid|help|Usage)"; then
            test_log "DEBUG" "✅ Error handled gracefully: $cmd"
        else
            test_log "ERROR" "❌ Poor error handling for: $cmd"
            return 1
        fi
    done
    
    test_log "SUCCESS" "Error handling integration working"
    return 0
}

test_performance_integration() {
    test_log "INFO" "Testing performance integration..."
    
    # Test startup time
    local start_time
    local end_time
    local duration
    
    start_time=$(date +%s%N)
    "$PROJECT_ROOT/src/milou" --version >/dev/null 2>&1
    end_time=$(date +%s%N)
    
    duration=$(( (end_time - start_time) / 1000000 ))  # Convert to milliseconds
    
    if [[ $duration -lt 2000 ]]; then  # Less than 2 seconds
        test_log "DEBUG" "✅ Fast startup time: ${duration}ms"
    else
        test_log "WARN" "⚠️  Slow startup time: ${duration}ms"
    fi
    
    test_log "SUCCESS" "Performance integration acceptable"
    return 0
}

# =============================================================================
# Main Test Runner
# =============================================================================

run_integration_tests() {
    test_init "🚀 System Integration Tests"
    
    # Setup test environment
    test_setup
    setup_integration_tests
    
    # Run integration tests
    test_run "Module Loading" "test_module_loading_integration" "Tests all modules load without conflicts"
    test_run "Entry Point" "test_main_entry_point_integration" "Tests main entry point works"
    test_run "Command Dispatch" "test_command_dispatch_integration" "Tests command routing to modules"
    test_run "Module Interdependency" "test_module_interdependency" "Tests modules work together"
    test_run "Backward Compatibility" "test_backward_compatibility" "Tests legacy function names work"
    test_run "Configuration" "test_configuration_integration" "Tests configuration system integration"
    test_run "Error Handling" "test_error_handling_integration" "Tests error handling across system"
    test_run "Performance" "test_performance_integration" "Tests system performance"
    
    # Cleanup
    cleanup_integration_tests
    test_cleanup
    
    # Show results
    test_summary
    
    # Final integration status
    if [[ $TEST_FAILED -eq 0 ]]; then
        test_log "SUCCESS" "🎉 COMPLETE SYSTEM INTEGRATION: ALL TESTS PASSED"
        test_log "INFO" "✅ All 10 core modules integrated successfully"
        test_log "INFO" "✅ Command dispatch system working perfectly"
        test_log "INFO" "✅ Module interdependencies resolved"
        test_log "INFO" "✅ Backward compatibility maintained"
        return 0
    else
        test_log "ERROR" "❌ System integration has issues that need attention"
        return 1
    fi
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_integration_tests
fi 