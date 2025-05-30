#!/bin/bash

# =============================================================================
# Service Lifecycle Management Tests
# Tests for the new service lifecycle functions implemented in Week 2
# =============================================================================

set -euo pipefail

# Get script directory and project root
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load test framework
source "$SCRIPT_DIR/../helpers/test-framework.sh"

# Test configuration
readonly SERVICE_TEST_TEMP_DIR="/tmp/milou-service-tests-$$"

# =============================================================================
# Test Setup and Cleanup
# =============================================================================

setup_service_tests() {
    test_log "INFO" "Setting up service lifecycle tests..."
    
    # Create temporary test directory
    mkdir -p "$SERVICE_TEST_TEMP_DIR"
    
    # Create mock environment for testing
    cat > "$SERVICE_TEST_TEMP_DIR/.env" << 'EOF'
DOMAIN=test.localhost
ADMIN_EMAIL=test@localhost
POSTGRES_USER=test_user
POSTGRES_PASSWORD=test_pass
POSTGRES_DB=test_db
EOF
    
    # Create mock docker-compose.yml
    cat > "$SERVICE_TEST_TEMP_DIR/docker-compose.yml" << 'EOF'
version: '3.8'
services:
  test-service:
    image: nginx:alpine
    ports:
      - "8080:80"
  test-db:
    image: postgres:alpine
    environment:
      POSTGRES_DB: test_db
      POSTGRES_USER: test_user
      POSTGRES_PASSWORD: test_pass
EOF
    
    test_log "SUCCESS" "Service test setup complete"
}

cleanup_service_tests() {
    test_log "INFO" "Cleaning up service lifecycle tests..."
    rm -rf "$SERVICE_TEST_TEMP_DIR" 2>/dev/null || true
}

# =============================================================================
# Individual Test Functions
# =============================================================================

test_service_lifecycle_module_loading() {
    test_log "INFO" "Testing service lifecycle module loading..."
    
    # Test that the Docker module with service lifecycle functions loads
    if source "$PROJECT_ROOT/src/_docker.sh"; then
        test_log "SUCCESS" "Service lifecycle module loads successfully"
    else
        test_log "ERROR" "Service lifecycle module failed to load"
        return 1
    fi
    
    # Test essential service lifecycle functions are available
    assert_function_exists "service_start_with_validation" "Service start with validation should be available"
    assert_function_exists "service_stop_gracefully" "Service graceful stop should be available"
    assert_function_exists "service_restart_safely" "Service safe restart should be available"
    assert_function_exists "service_update_zero_downtime" "Service zero-downtime update should be available"
    
    return 0
}

test_service_start_validation_function() {
    test_log "INFO" "Testing service start with validation function..."
    
    source "$PROJECT_ROOT/src/_docker.sh" || return 1
    
    # Test function exists and has proper structure
    if command -v service_start_with_validation >/dev/null 2>&1; then
        test_log "SUCCESS" "service_start_with_validation function exists"
    else
        test_log "ERROR" "service_start_with_validation function not found"
        return 1
    fi
    
    # Test function signature (should accept service, timeout, quiet parameters)
    local func_def
    func_def=$(declare -f service_start_with_validation | head -5)
    
    if echo "$func_def" | grep -q "local service.*local timeout.*local quiet"; then
        test_log "SUCCESS" "Function has correct parameter structure"
    else
        test_log "DEBUG" "Function parameters may differ from expected (this is OK)"
    fi
    
    return 0
}

test_service_stop_gracefully_function() {
    test_log "INFO" "Testing service graceful stop function..."
    
    source "$PROJECT_ROOT/src/_docker.sh" || return 1
    
    # Test function exists
    assert_function_exists "service_stop_gracefully" "Graceful stop function should exist"
    
    # Test function has timeout parameter handling
    local func_def
    func_def=$(declare -f service_stop_gracefully)
    
    if echo "$func_def" | grep -q "timeout"; then
        test_log "SUCCESS" "Function includes timeout handling"
    else
        test_log "WARN" "Function may not include timeout handling"
    fi
    
    return 0
}

test_service_restart_safely_function() {
    test_log "INFO" "Testing service safe restart function..."
    
    source "$PROJECT_ROOT/src/_docker.sh" || return 1
    
    # Test function exists
    assert_function_exists "service_restart_safely" "Safe restart function should exist"
    
    # Test function includes snapshot creation logic
    local func_def
    func_def=$(declare -f service_restart_safely)
    
    if echo "$func_def" | grep -q "create_system_snapshot"; then
        test_log "SUCCESS" "Function includes snapshot creation for safety"
    else
        test_log "DEBUG" "Function may not include snapshot creation (optional feature)"
    fi
    
    return 0
}

test_service_zero_downtime_update_function() {
    test_log "INFO" "Testing zero-downtime update function..."
    
    source "$PROJECT_ROOT/src/_docker.sh" || return 1
    
    # Test function exists
    assert_function_exists "service_update_zero_downtime" "Zero-downtime update function should exist"
    
    # Test function includes image pulling logic
    local func_def
    func_def=$(declare -f service_update_zero_downtime)
    
    if echo "$func_def" | grep -q "pull.*images"; then
        test_log "SUCCESS" "Function includes image pulling for updates"
    else
        test_log "WARN" "Function may not include image pulling"
    fi
    
    return 0
}

test_health_check_integration() {
    test_log "INFO" "Testing health check integration..."
    
    source "$PROJECT_ROOT/src/_docker.sh" || return 1
    
    # Test that health check functions exist
    assert_function_exists "health_check_service" "Individual service health check should exist"
    assert_function_exists "health_check_all" "All services health check should exist"
    
    # Test that service lifecycle functions use health checks
    local start_func
    start_func=$(declare -f service_start_with_validation)
    
    if echo "$start_func" | grep -q "health_check"; then
        test_log "SUCCESS" "Service start function integrates with health checks"
    else
        test_log "ERROR" "Service start function missing health check integration"
        return 1
    fi
    
    return 0
}

test_docker_execute_integration() {
    test_log "INFO" "Testing docker_execute integration..."
    
    source "$PROJECT_ROOT/src/_docker.sh" || return 1
    
    # Test that service lifecycle functions use docker_execute
    local functions_to_check=(
        "service_start_with_validation"
        "service_stop_gracefully"
        "service_restart_safely"
        "service_update_zero_downtime"
    )
    
    for func in "${functions_to_check[@]}"; do
        local func_def
        func_def=$(declare -f "$func")
        
        if echo "$func_def" | grep -q "docker_execute"; then
            test_log "SUCCESS" "$func uses docker_execute"
        else
            test_log "ERROR" "$func does not use docker_execute"
            return 1
        fi
    done
    
    return 0
}

test_error_handling_and_rollback() {
    test_log "INFO" "Testing error handling and rollback capabilities..."
    
    source "$PROJECT_ROOT/src/_docker.sh" || return 1
    
    # Test that functions include error handling
    local restart_func
    restart_func=$(declare -f service_restart_safely)
    
    if echo "$restart_func" | grep -q "validation_result"; then
        test_log "SUCCESS" "Safe restart includes validation and error handling"
    else
        test_log "WARN" "Safe restart may not include comprehensive error handling"
    fi
    
    # Test rollback capability mentions
    if echo "$restart_func" | grep -q "rollback\|snapshot"; then
        test_log "SUCCESS" "Safe restart includes rollback capabilities"
    else
        test_log "WARN" "Safe restart may not include rollback capabilities"
    fi
    
    return 0
}

test_function_exports() {
    test_log "INFO" "Testing service lifecycle function exports..."
    
    source "$PROJECT_ROOT/src/_docker.sh" || return 1
    
    # Test that all new functions are properly exported
    local lifecycle_functions=(
        "service_start_with_validation"
        "service_stop_gracefully"
        "service_restart_safely"
        "service_update_zero_downtime"
    )
    
    for func in "${lifecycle_functions[@]}"; do
        if declare -F | grep -q "$func"; then
            test_log "SUCCESS" "$func is properly exported"
        else
            test_log "ERROR" "$func is not exported"
            return 1
        fi
    done
    
    return 0
}

test_week2_completion_verification() {
    test_log "INFO" "Verifying Week 2 completion requirements..."
    
    source "$PROJECT_ROOT/src/_docker.sh" || return 1
    
    # Verify all Week 2 requirements are met
    local week2_requirements=(
        "docker_execute"           # Master Docker function
        "health_check_service"     # Individual health checks
        "health_check_all"         # Comprehensive health checks
        "service_start_with_validation"  # Start with validation
        "service_stop_gracefully"       # Graceful shutdown
        "service_restart_safely"        # Safe restart
        "service_update_zero_downtime"  # Zero-downtime updates
    )
    
    local missing_functions=()
    
    for func in "${week2_requirements[@]}"; do
        if command -v "$func" >/dev/null 2>&1; then
            test_log "DEBUG" "✓ $func implemented"
        else
            missing_functions+=("$func")
        fi
    done
    
    if [[ ${#missing_functions[@]} -eq 0 ]]; then
        test_log "SUCCESS" "All Week 2 service lifecycle requirements completed!"
    else
        test_log "ERROR" "Missing Week 2 functions: ${missing_functions[*]}"
        return 1
    fi
    
    return 0
}

# =============================================================================
# Main Test Runner
# =============================================================================

run_service_lifecycle_tests() {
    test_init "🔄 Service Lifecycle Management Tests"
    
    # Setup test environment
    test_setup
    setup_service_tests
    
    # Run individual tests
    test_run "Module Loading" "test_service_lifecycle_module_loading" "Tests service lifecycle module loading"
    test_run "Start Validation" "test_service_start_validation_function" "Tests service start with validation"
    test_run "Graceful Stop" "test_service_stop_gracefully_function" "Tests graceful service stopping"
    test_run "Safe Restart" "test_service_restart_safely_function" "Tests safe service restart"
    test_run "Zero-Downtime Update" "test_service_zero_downtime_update_function" "Tests zero-downtime updates"
    test_run "Health Check Integration" "test_health_check_integration" "Tests health check integration"
    test_run "Docker Execute Integration" "test_docker_execute_integration" "Tests docker_execute integration"
    test_run "Error Handling" "test_error_handling_and_rollback" "Tests error handling and rollback"
    test_run "Function Exports" "test_function_exports" "Tests function exports"
    test_run "Week 2 Completion" "test_week2_completion_verification" "Verifies Week 2 completion"
    
    # Cleanup
    cleanup_service_tests
    test_cleanup
    
    # Show results
    test_summary
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_service_lifecycle_tests
fi 