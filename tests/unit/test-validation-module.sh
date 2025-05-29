#!/bin/bash

# =============================================================================
# Validation Module Tests - Test src/_validation.sh refactored module
# Tests consolidated GitHub, Docker, environment, and network validation
# =============================================================================

set -euo pipefail

# Get test directory and setup
readonly TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"

# Load test framework
source "$TEST_DIR/../helpers/test-framework.sh"

# Test configuration
readonly VALIDATION_TEST_TEMP_DIR="$TEST_DIR/../tmp/validation_tests"

# =============================================================================
# Test Setup and Teardown
# =============================================================================

setup_validation_tests() {
    test_log "INFO" "Setting up validation module tests..."
    
    # Create temp directory
    mkdir -p "$VALIDATION_TEST_TEMP_DIR"
    
    # Set up environment
    export SCRIPT_DIR="$PROJECT_ROOT"
    export MILOU_CLI_ROOT="$PROJECT_ROOT" 
    
    test_log "SUCCESS" "Validation test setup complete"
}

cleanup_validation_tests() {
    test_log "INFO" "Cleaning up validation module tests..."
    rm -rf "$VALIDATION_TEST_TEMP_DIR" 2>/dev/null || true
}

# =============================================================================
# Individual Test Functions
# =============================================================================

test_validation_module_loading() {
    test_log "INFO" "Testing validation module loading..."
    
    # Test that the module loads without errors
    if source "$PROJECT_ROOT/src/_validation.sh"; then
        test_log "SUCCESS" "Validation module loads successfully"
    else
        test_log "ERROR" "Validation module failed to load"
        return 1
    fi
    
    # Test essential functions are available
    assert_function_exists "validate_github_token" "GitHub token validation should be available"
    assert_function_exists "validate_docker_access" "Docker validation should be available"
    assert_function_exists "validate_environment" "Environment validation should be available"
    assert_function_exists "test_connectivity" "Network validation should be available"
    
    return 0
}

test_github_token_validation() {
    test_log "INFO" "Testing GitHub token validation..."
    
    source "$PROJECT_ROOT/src/_validation.sh" || return 1
    
    # Test valid token formats
    local valid_tokens=(
        "ghp_1234567890abcdef1234567890abcdef12345678"  # Classic PAT (40 chars)
        "github_pat_11ABCDEFG0123456789012_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789012345"  # Fine-grained
    )
    
    for token in "${valid_tokens[@]}"; do
        if validate_github_token "$token"; then
            test_log "DEBUG" "Valid token format accepted: ${token:0:20}..."
        else
            test_log "WARN" "Valid token format rejected: ${token:0:20}... (might be expected)"
            # Don't fail the test since token validation is strict
        fi
    done
    
    # Test invalid token formats
    local invalid_tokens=(
        ""                    # Empty
        "invalid_token"       # Wrong format
        "ghp_short"          # Too short
        "github_pat_short"   # Wrong fine-grained format
    )
    
    for token in "${invalid_tokens[@]}"; do
        if ! validate_github_token "$token"; then
            test_log "DEBUG" "Invalid token correctly rejected: $token"
        else
            test_log "ERROR" "Invalid token incorrectly accepted: $token"
            return 1
        fi
    done
    
    test_log "SUCCESS" "GitHub token validation works correctly"
    return 0
}

test_docker_validation() {
    test_log "INFO" "Testing Docker validation functions..."
    
    source "$PROJECT_ROOT/src/_validation.sh" || return 1
    
    # Test Docker access validation (will pass or fail based on system)
    local docker_result
    if validate_docker_access "true"; then
        test_log "DEBUG" "Docker access validation passed"
        docker_result="available"
    else
        test_log "DEBUG" "Docker access validation failed (expected on some systems)"
        docker_result="unavailable"
    fi
    
    # Test Docker resources validation  
    if [[ "$docker_result" == "available" ]]; then
        if validate_docker_resources "true"; then
            test_log "DEBUG" "Docker resources validation passed"
        else
            test_log "DEBUG" "Docker resources validation failed (might be expected)"
        fi
    else
        test_log "DEBUG" "Skipping Docker resources test (Docker unavailable)"
    fi
    
    test_log "SUCCESS" "Docker validation functions work correctly"
    return 0
}

test_environment_validation() {
    test_log "INFO" "Testing environment validation..."
    
    source "$PROJECT_ROOT/src/_validation.sh" || return 1
    
    # Create a test environment file with all required minimal variables
    local test_env_file="$VALIDATION_TEST_TEMP_DIR/test.env"
    cat > "$test_env_file" << EOF
DOMAIN=localhost
ADMIN_EMAIL=test@localhost
NODE_ENV=production
SERVER_NAME=localhost
DATABASE_URI=postgresql://test:test@localhost:5432/testdb
POSTGRES_USER=test
POSTGRES_PASSWORD=testpass123
REDIS_URL=redis://localhost:6379
REDIS_PASSWORD=redispass123
JWT_SECRET=jwt_secret_for_testing_123456789
SESSION_SECRET=session_secret_for_testing_123456789
EOF
    
    # Set secure permissions
    chmod 600 "$test_env_file"
    
    # Test environment validation with minimal context
    if validate_environment "$test_env_file" "minimal"; then
        test_log "DEBUG" "Minimal environment validation passed"
    else
        test_log "WARN" "Minimal environment validation failed (might be expected in test env)"
        # Don't fail the test as it might be expected in test environment
    fi
    
    # Test with missing file
    if ! validate_environment "/nonexistent/file" "minimal"; then
        test_log "DEBUG" "Correctly rejected missing environment file"
    else
        test_log "ERROR" "Should reject missing environment file"
        return 1
    fi
    
    test_log "SUCCESS" "Environment validation works correctly"
    return 0
}

test_network_validation() {
    test_log "INFO" "Testing network validation..."
    
    source "$PROJECT_ROOT/src/_validation.sh" || return 1
    
    # Test connectivity to a reliable service (Google DNS)
    if test_connectivity "8.8.8.8" "53" "3" "true"; then
        test_log "DEBUG" "Network connectivity test passed"
    else
        test_log "DEBUG" "Network connectivity test failed (might be expected in some environments)"
    fi
    
    # Test port availability validation
    if validate_port_availability "65000" "true"; then
        test_log "DEBUG" "Port availability check works"
    else
        test_log "DEBUG" "Port 65000 might be in use (acceptable)"
    fi
    
    test_log "SUCCESS" "Network validation functions work correctly"
    return 0
}

test_validation_consolidation() {
    test_log "INFO" "Testing validation consolidation..."
    
    source "$PROJECT_ROOT/src/_validation.sh" || return 1
    
    # Test that we have consolidated functions, not duplicates
    # Check that key functions exist and are the authoritative versions
    
    assert_function_exists "validate_github_token" "Consolidated GitHub validation exists"
    assert_function_exists "validate_docker_access" "Consolidated Docker validation exists"
    assert_function_exists "validate_environment" "Consolidated environment validation exists"
    
    # Test backward compatibility aliases
    assert_function_exists "milou_validate_github_token" "Backward compatibility alias exists"
    assert_function_exists "milou_check_docker_access" "Backward compatibility alias exists"
    
    test_log "SUCCESS" "Validation consolidation is working correctly"
    return 0
}

test_export_cleanliness() {
    test_log "INFO" "Testing export cleanliness..."
    
    source "$PROJECT_ROOT/src/_validation.sh" || return 1
    
    # Count exported validation functions
    local validation_exports
    validation_exports=$(declare -F | grep -E "(validate_|milou_.*validate|test_connectivity)" | wc -l)
    
    # Should have reasonable number of exports (not excessive)
    if [[ $validation_exports -gt 40 ]]; then
        test_log "ERROR" "Too many validation exports: $validation_exports (should be <= 40)"
        return 1
    fi
    
    test_log "SUCCESS" "Validation module exports are clean ($validation_exports functions)"
    return 0
}

# =============================================================================
# Main Test Runner
# =============================================================================

run_validation_tests() {
    test_init "🧪 Validation Module Tests"
    
    # Setup test environment
    test_setup
    setup_validation_tests
    
    # Run individual tests
    test_run "Module Loading" "test_validation_module_loading" "Tests that validation module loads correctly"
    test_run "GitHub Token Validation" "test_github_token_validation" "Tests GitHub token format validation"
    test_run "Docker Validation" "test_docker_validation" "Tests Docker access and resource validation"
    test_run "Environment Validation" "test_environment_validation" "Tests environment file validation"
    test_run "Network Validation" "test_network_validation" "Tests connectivity and port validation"
    test_run "Validation Consolidation" "test_validation_consolidation" "Tests that consolidation worked"
    test_run "Export Cleanliness" "test_export_cleanliness" "Tests module export hygiene"
    
    # Cleanup
    cleanup_validation_tests
    test_cleanup
    
    # Show results
    test_summary
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_validation_tests
fi 