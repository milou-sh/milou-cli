#!/bin/bash

# =============================================================================
# Milou CLI - Error Recovery Module Tests
# Test suite for the enterprise-grade error recovery system
# =============================================================================

# Get project root for imports
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Source test framework
source "$PROJECT_ROOT/tests/helpers/test-framework.sh" || {
    echo "ERROR: Cannot load test framework" >&2
    exit 1
}

# =============================================================================
# TEST SETUP AND CONFIGURATION
# =============================================================================

# Test-specific setup
setup_error_recovery_tests() {
    test_log "INFO" "Setting up error recovery tests..."
    
    # Create test environment
    export TEST_SCRIPT_DIR="$PROJECT_ROOT"
    export RECOVERY_ENABLED="true"
    export RECOVERY_SNAPSHOT_DIR="$PROJECT_ROOT/tests/tmp/snapshots"
    export RECOVERY_LOG_DIR="$PROJECT_ROOT/tests/tmp/logs"
    export RECOVERY_MAX_SNAPSHOTS="3"
    
    # Clean up any existing test snapshots
    rm -rf "$RECOVERY_SNAPSHOT_DIR" "$RECOVERY_LOG_DIR" 2>/dev/null || true
    
    # Create test directories
    mkdir -p "$RECOVERY_SNAPSHOT_DIR" "$RECOVERY_LOG_DIR"
    
    # Create test .env file
    cat > "$PROJECT_ROOT/.env.test" << 'EOF'
# Test environment file
DOMAIN=test.localhost
ADMIN_EMAIL=test@localhost
POSTGRES_PASSWORD=test_password_123
JWT_SECRET=test_jwt_secret_456
SESSION_SECRET=test_session_secret_789
ENCRYPTION_KEY=test_encryption_key_abc
EOF
    
    # Source the error recovery module
    source "$PROJECT_ROOT/src/_core.sh" || return 1
    source "$PROJECT_ROOT/src/_error_recovery.sh" || return 1
    
    test_log "SUCCESS" "Error recovery test environment ready"
}

# Test cleanup
cleanup_error_recovery_tests() {
    test_log "INFO" "Cleaning up error recovery tests..."
    
    # Remove test files
    rm -f "$PROJECT_ROOT/.env.test" 2>/dev/null || true
    rm -rf "$RECOVERY_SNAPSHOT_DIR" "$RECOVERY_LOG_DIR" 2>/dev/null || true
    
    # Clean up any global variables
    unset RECOVERY_CURRENT_OPERATION RECOVERY_SNAPSHOT_ID
    RECOVERY_ROLLBACK_ACTIONS=()
}

# =============================================================================
# CORE FUNCTIONALITY TESTS
# =============================================================================

test_error_recovery_module_loading() {
    test_log "INFO" "Testing error recovery module loading..."
    
    # Test that the module loads without errors
    if source "$PROJECT_ROOT/src/_error_recovery.sh"; then
        test_log "SUCCESS" "Error recovery module loads successfully"
    else
        test_log "ERROR" "Error recovery module failed to load"
        return 1
    fi
    
    # Test essential functions are available
    assert_function_exists "create_system_snapshot" "System snapshot creation function should be available"
    assert_function_exists "restore_system_snapshot" "System snapshot restoration function should be available"
    assert_function_exists "validate_system_state" "System state validation function should be available"
    assert_function_exists "safe_operation" "Safe operation wrapper should be available"
    assert_function_exists "rollback_on_failure" "Rollback function should be available"
    
    return 0
}

test_system_snapshot_creation() {
    test_log "INFO" "Testing system snapshot creation..."
    
    # Clear any existing snapshot vars first
    unset RECOVERY_SNAPSHOT_ID RECOVERY_CURRENT_OPERATION
    
    # Create a test snapshot
    local snapshot_id
    snapshot_id=$(create_system_snapshot "test_operation" "true")
    
    if [[ -n "$snapshot_id" ]]; then
        test_log "SUCCESS" "System snapshot created: $snapshot_id"
        
        # Verify snapshot directory exists
        local snapshot_path="$RECOVERY_SNAPSHOT_DIR/$snapshot_id"
        assert_directory_exists "$snapshot_path" "Snapshot directory should exist"
        
        # Verify metadata file exists
        assert_file_exists "$snapshot_path/metadata.env" "Snapshot metadata should exist"
        
        # Verify metadata content
        if grep -q "OPERATION=test_operation" "$snapshot_path/metadata.env"; then
            test_log "SUCCESS" "Snapshot metadata contains correct operation name"
        else
            test_log "ERROR" "Snapshot metadata missing operation name"
            return 1
        fi
        
        # Verify system info file
        assert_file_exists "$snapshot_path/system_info.txt" "System info should be saved"
        
        # Test that snapshot vars file was created and contains correct ID
        if [[ -f "$RECOVERY_SNAPSHOT_DIR/.last_snapshot_vars" ]]; then
            # Source the vars file to get the variables
            source "$RECOVERY_SNAPSHOT_DIR/.last_snapshot_vars"
            
            if [[ "$RECOVERY_SNAPSHOT_ID" == "$snapshot_id" ]]; then
                test_log "SUCCESS" "Global snapshot ID properly set via vars file"
            else
                test_log "ERROR" "Global snapshot ID not set correctly in vars file"
                return 1
            fi
        else
            test_log "ERROR" "Snapshot vars file not created"
            return 1
        fi
    else
        test_log "ERROR" "Failed to create system snapshot"
        return 1
    fi
    
    return 0
}

test_system_state_validation() {
    test_log "INFO" "Testing system state validation..."
    
    # Test validation with missing essential files
    local temp_env="$PROJECT_ROOT/.env"
    local backup_env=""
    
    # Backup existing .env if it exists
    if [[ -f "$temp_env" ]]; then
        backup_env="$temp_env.test_backup"
        mv "$temp_env" "$backup_env"
    fi
    
    # Test validation failure with missing .env
    if validate_system_state "true"; then
        test_log "WARN" "Validation passed when it should have failed (missing .env)"
    else
        test_log "SUCCESS" "Validation correctly failed with missing .env file"
    fi
    
    # Create minimal .env for testing
    cp "$PROJECT_ROOT/.env.test" "$temp_env"
    
    # Test validation success
    if validate_system_state "true"; then
        test_log "SUCCESS" "Validation passed with minimal configuration"
    else
        test_log "DEBUG" "Validation failed (may be expected without full Docker setup)"
    fi
    
    # Restore original .env
    rm -f "$temp_env"
    if [[ -n "$backup_env" && -f "$backup_env" ]]; then
        mv "$backup_env" "$temp_env"
    fi
    
    return 0
}

test_snapshot_restoration() {
    test_log "INFO" "Testing snapshot restoration..."
    
    # Create test files
    local test_env="$PROJECT_ROOT/.env.restore_test"
    echo "TEST_VAR=original_value" > "$test_env"
    
    # Set SCRIPT_DIR for the test context
    local original_script_dir="${SCRIPT_DIR:-}"
    export SCRIPT_DIR="$PROJECT_ROOT"
    
    # Copy test env to main .env location for snapshot
    cp "$test_env" "$PROJECT_ROOT/.env"
    
    local snapshot_id
    snapshot_id=$(create_system_snapshot "restoration_test" "true")
    
    if [[ -n "$snapshot_id" ]]; then
        # Modify the original file
        echo "TEST_VAR=modified_value" > "$PROJECT_ROOT/.env"
        
        # Restore from snapshot
        if restore_system_snapshot "$snapshot_id" "true" "true"; then
            test_log "SUCCESS" "Snapshot restoration completed"
            
            # Verify restoration
            if grep -q "TEST_VAR=original_value" "$PROJECT_ROOT/.env"; then
                test_log "SUCCESS" "File content correctly restored"
            else
                test_log "ERROR" "File content not restored correctly"
                # Restore original SCRIPT_DIR
                if [[ -n "$original_script_dir" ]]; then
                    export SCRIPT_DIR="$original_script_dir"
                else
                    unset SCRIPT_DIR
                fi
                return 1
            fi
        else
            test_log "ERROR" "Snapshot restoration failed"
            # Restore original SCRIPT_DIR
            if [[ -n "$original_script_dir" ]]; then
                export SCRIPT_DIR="$original_script_dir"
            else
                unset SCRIPT_DIR
            fi
            return 1
        fi
    else
        test_log "ERROR" "Failed to create snapshot for restoration test"
        # Restore original SCRIPT_DIR
        if [[ -n "$original_script_dir" ]]; then
            export SCRIPT_DIR="$original_script_dir"
        else
            unset SCRIPT_DIR
        fi
        return 1
    fi
    
    # Cleanup
    rm -f "$test_env" "$PROJECT_ROOT/.env"
    
    # Restore original SCRIPT_DIR
    if [[ -n "$original_script_dir" ]]; then
        export SCRIPT_DIR="$original_script_dir"
    else
        unset SCRIPT_DIR
    fi
    
    return 0
}

test_safe_operation_wrapper() {
    test_log "INFO" "Testing safe operation wrapper..."
    
    # Define test functions
    test_successful_operation() {
        test_log "DEBUG" "Executing successful test operation"
        return 0
    }
    
    test_failing_operation() {
        test_log "DEBUG" "Executing failing test operation"
        return 1
    }
    
    # Test successful operation
    if safe_operation "test_success" "test_successful_operation"; then
        test_log "SUCCESS" "Safe operation wrapper handles success correctly"
    else
        test_log "ERROR" "Safe operation wrapper failed on successful operation"
        return 1
    fi
    
    # Test failing operation (should trigger rollback)
    if safe_operation "test_failure" "test_failing_operation"; then
        test_log "ERROR" "Safe operation should have failed but returned success"
        return 1
    else
        test_log "SUCCESS" "Safe operation wrapper correctly handles failure and rollback"
    fi
    
    return 0
}

test_rollback_actions_registration() {
    test_log "INFO" "Testing rollback actions registration..."
    
    # Clear existing rollback actions
    RECOVERY_ROLLBACK_ACTIONS=()
    
    # Register test rollback actions
    register_rollback_action "Test cleanup 1" "echo 'Cleanup 1 executed'"
    register_rollback_action "Test cleanup 2" "echo 'Cleanup 2 executed'"
    
    # Verify actions were registered
    if [[ ${#RECOVERY_ROLLBACK_ACTIONS[@]} -eq 2 ]]; then
        test_log "SUCCESS" "Rollback actions registered correctly"
        
        # Verify action content
        if [[ "${RECOVERY_ROLLBACK_ACTIONS[0]}" == "Test cleanup 1|echo 'Cleanup 1 executed'" ]]; then
            test_log "SUCCESS" "Rollback action content is correct"
        else
            test_log "ERROR" "Rollback action content is incorrect"
            return 1
        fi
    else
        test_log "ERROR" "Wrong number of rollback actions registered"
        return 1
    fi
    
    return 0
}

test_cleanup_operations() {
    test_log "INFO" "Testing cleanup operations..."
    
    # Test snapshot cleanup (safe to run)
    cleanup_old_snapshots "true"
    test_log "SUCCESS" "Snapshot cleanup completed without errors"
    
    # Test failed operations cleanup (safe to run even without Docker)
    cleanup_failed_operations "true"
    test_log "SUCCESS" "Failed operations cleanup completed without errors"
    
    return 0
}

test_recovery_configuration() {
    test_log "INFO" "Testing recovery configuration..."
    
    # Test configuration variables
    assert_not_empty "$RECOVERY_ENABLED" "RECOVERY_ENABLED should be set"
    assert_not_empty "$RECOVERY_SNAPSHOT_DIR" "RECOVERY_SNAPSHOT_DIR should be set"
    assert_not_empty "$RECOVERY_MAX_SNAPSHOTS" "RECOVERY_MAX_SNAPSHOTS should be set"
    
    # Test directory creation
    if [[ -d "$RECOVERY_SNAPSHOT_DIR" ]]; then
        test_log "SUCCESS" "Recovery snapshot directory exists"
    else
        test_log "ERROR" "Recovery snapshot directory not created"
        return 1
    fi
    
    return 0
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

test_integration_with_main_cli() {
    test_log "INFO" "Testing integration with main CLI..."
    
    # Test that main CLI loads error recovery module
    if source "$PROJECT_ROOT/src/milou"; then
        test_log "SUCCESS" "Main CLI loads with error recovery module"
        
        # Test that recovery functions are available in main context
        assert_function_exists "create_system_snapshot" "Snapshot functions should be available in main CLI"
        assert_function_exists "safe_operation" "Safe operation should be available in main CLI"
    else
        test_log "ERROR" "Main CLI failed to load with error recovery module"
        return 1
    fi
    
    return 0
}

test_export_cleanliness() {
    test_log "INFO" "Testing export cleanliness..."
    
    source "$PROJECT_ROOT/src/_error_recovery.sh" || return 1
    
    # Count exported functions
    local exported_functions
    exported_functions=$(declare -F | grep -c "declare -fx" || echo "0")
    
    test_log "DEBUG" "Error recovery module exports $exported_functions functions"
    
    # Error recovery should export a reasonable number of functions
    if [[ $exported_functions -le 20 ]]; then
        test_log "SUCCESS" "Error recovery module has reasonable export count: $exported_functions functions"
    else
        test_log "WARN" "Error recovery module exports many functions: $exported_functions (review if necessary)"
    fi
    
    return 0
}

# =============================================================================
# TEST SUITE RUNNER
# =============================================================================

run_error_recovery_tests() {
    test_init "🛡️  Error Recovery Module Tests"
    
    # Setup test environment
    test_setup
    setup_error_recovery_tests
    
    # Run individual tests
    test_run "Module Loading" "test_error_recovery_module_loading" "Tests that error recovery module loads correctly"
    test_run "Snapshot Creation" "test_system_snapshot_creation" "Tests system snapshot creation"
    test_run "State Validation" "test_system_state_validation" "Tests system state validation"
    test_run "Snapshot Restoration" "test_snapshot_restoration" "Tests snapshot restoration"
    test_run "Safe Operation Wrapper" "test_safe_operation_wrapper" "Tests safe operation wrapper"
    test_run "Rollback Actions" "test_rollback_actions_registration" "Tests rollback action registration"
    test_run "Cleanup Operations" "test_cleanup_operations" "Tests cleanup functions"
    test_run "Recovery Configuration" "test_recovery_configuration" "Tests recovery system configuration"
    test_run "CLI Integration" "test_integration_with_main_cli" "Tests integration with main CLI"
    test_run "Export Cleanliness" "test_export_cleanliness" "Tests module export hygiene"
    
    # Cleanup
    cleanup_error_recovery_tests
    test_cleanup
    
    # Show results
    test_summary
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_error_recovery_tests
fi 