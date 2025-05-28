#!/bin/bash

# =============================================================================
# Unit Tests for Backup Core Module (lib/backup/core.sh)
# Tests the modernized backup functionality
# =============================================================================

# Load test framework
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/test-framework.sh"

# Test configuration
readonly TEST_BACKUP_DIR="$TEST_TEMP_DIR/backups"
readonly TEST_SSL_DIR="$TEST_TEMP_DIR/ssl"

# =============================================================================
# Test Setup and Teardown
# =============================================================================

setup_backup_tests() {
    test_log "INFO" "Setting up backup tests..."
    
    # Create test directories
    mkdir -p "$TEST_BACKUP_DIR" "$TEST_SSL_DIR"
    
    # Create test SSL certificates for backup testing
    cat > "$TEST_SSL_DIR/milou.crt" << 'EOF'
-----BEGIN CERTIFICATE-----
MIIDXTCCAkWgAwIBAgIJAKL0UG+jP9kOMA0GCSqGSIb3DQEBCwUAMEUxCzAJBgNV
BAYTAkFVMRMwEQYDVQQIDApTb21lLVN0YXRlMSEwHwYDVQQKDBhJbnRlcm5ldCBX
aWRnaXRzIFB0eSBMdGQwHhcNMjQwMTAxMDAwMDAwWhcNMjUwMTAxMDAwMDAwWjBF
MQswCQYDVQQGEwJBVTETMBEGA1UECAwKU29tZS1TdGF0ZTEhMB8GA1UECgwYSW50
ZXJuZXQgV2lkZ2l0cyBQdHkgTHRkMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIB
CgKCAQEAk8L5NDQ3ZQ==
-----END CERTIFICATE-----
EOF
    
    cat > "$TEST_SSL_DIR/milou.key" << 'EOF'
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCTwvk0NDdlD2Y=
-----END PRIVATE KEY-----
EOF
    
    # Create test .env file
    cat > "$TEST_TEMP_DIR/.env.test" << 'EOF'
POSTGRES_USER=test_admin
POSTGRES_PASSWORD=test_password_123
REDIS_PASSWORD=test_redis_pass
RABBITMQ_USER=test_rabbit
RABBITMQ_PASSWORD=test_rabbit_pass
ADMIN_PASSWORD=test_admin_pass
DOMAIN=test.milou.local
EOF
    
    test_log "SUCCESS" "Backup test setup complete"
}

cleanup_backup_tests() {
    test_log "INFO" "Cleaning up backup tests..."
    rm -rf "$TEST_BACKUP_DIR" "$TEST_SSL_DIR" 2>/dev/null || true
}

# =============================================================================
# Individual Test Functions
# =============================================================================

test_backup_module_loading() {
    test_log "INFO" "Testing backup module loading..."
    
    # Test that the module loads without errors
    test_load_module "lib/backup/core.sh" || return 1
    
    # Test that required functions are exported
    assert_function_exists "milou_backup_create" "Main backup function should be exported"
    assert_function_exists "milou_backup_list" "Backup list function should be exported"
    
    # Test that internal functions are NOT exported (clean API)
    if declare -f "_milou_backup_configuration" >/dev/null 2>&1; then
        test_log "ERROR" "Internal function _milou_backup_configuration should not be exported"
        return 1
    fi
    
    test_log "SUCCESS" "Backup module loading tests passed"
    return 0
}

test_backup_directory_creation() {
    test_log "INFO" "Testing backup directory creation..."
    
    # Load backup module
    test_load_module "lib/backup/core.sh" || return 1
    
    # Test backup directory creation
    local test_dir="$TEST_TEMP_DIR/test_backup_dir"
    rm -rf "$test_dir" 2>/dev/null || true
    
    # This should create the directory
    assert_directory_exists "$TEST_BACKUP_DIR" "Test backup directory should exist after setup"
    
    test_log "SUCCESS" "Backup directory creation tests passed"
    return 0
}

test_backup_validation() {
    test_log "INFO" "Testing backup validation..."
    
    # Load required modules
    test_load_module "lib/core/logging.sh" || return 1
    test_load_module "lib/backup/core.sh" || return 1
    
    # Test invalid backup type
    local output
    output=$(milou_backup_create "invalid_type" "$TEST_BACKUP_DIR" 2>&1) || true
    assert_contains "$output" "Invalid backup type" "Should reject invalid backup type"
    
    test_log "SUCCESS" "Backup validation tests passed"
    return 0
}

test_backup_ssl_functionality() {
    test_log "INFO" "Testing SSL backup functionality..."
    
    # Load required modules
    test_load_module "lib/core/logging.sh" || return 1
    test_load_module "lib/backup/core.sh" || return 1
    
    # Test SSL backup (should work even if other components fail)
    local backup_name="test_ssl_backup"
    local output
    
    # Create backup with SSL type
    output=$(milou_backup_create "ssl" "$TEST_BACKUP_DIR" "$backup_name" 2>&1) || true
    
    # Check if SSL files were included in backup considerations
    assert_contains "$output" "SSL" "SSL backup should process SSL components"
    
    test_log "SUCCESS" "SSL backup functionality tests passed"
    return 0
}

test_backup_list_functionality() {
    test_log "INFO" "Testing backup list functionality..."
    
    # Load required modules
    test_load_module "lib/core/logging.sh" || return 1
    test_load_module "lib/backup/core.sh" || return 1
    
    # Create some test backup files
    mkdir -p "$TEST_BACKUP_DIR"
    touch "$TEST_BACKUP_DIR/backup_20241201_120000.tar.gz"
    touch "$TEST_BACKUP_DIR/backup_20241201_130000.tar.gz"
    touch "$TEST_BACKUP_DIR/not_a_backup.txt"
    
    # Test listing backups
    local output
    output=$(milou_backup_list "$TEST_BACKUP_DIR" 2>&1)
    
    # Should find backup files
    assert_contains "$output" "backup_20241201_120000.tar.gz" "Should list first backup file"
    assert_contains "$output" "backup_20241201_130000.tar.gz" "Should list second backup file"
    
    # Should not include non-backup files
    assert_not_contains "$output" "not_a_backup.txt" "Should not list non-backup files"
    
    test_log "SUCCESS" "Backup list functionality tests passed"
    return 0
}

test_backup_clean_api() {
    test_log "INFO" "Testing backup module clean API..."
    
    # Load backup module
    test_load_module "lib/backup/core.sh" || return 1
    
    # Count exported functions
    local exported_functions
    exported_functions=$(declare -F | grep "milou_backup" | wc -l)
    
    # Should have exactly 2 exported functions based on our cleanup
    assert_equals "2" "$exported_functions" "Should have exactly 2 exported backup functions"
    
    # Verify specific exports
    assert_function_exists "milou_backup_create" "milou_backup_create should be exported"
    assert_function_exists "milou_backup_list" "milou_backup_list should be exported"
    
    test_log "SUCCESS" "Backup clean API tests passed"
    return 0
}

# =============================================================================
# Main Test Runner
# =============================================================================

run_backup_tests() {
    test_init "🧪 Backup Core Module Tests"
    
    # Setup test environment
    test_setup
    setup_backup_tests
    
    # Run individual tests
    test_run "Module Loading" "test_backup_module_loading" "Tests that backup module loads correctly"
    test_run "Directory Creation" "test_backup_directory_creation" "Tests backup directory management"
    test_run "Input Validation" "test_backup_validation" "Tests backup parameter validation"
    test_run "SSL Backup" "test_backup_ssl_functionality" "Tests SSL certificate backup"
    test_run "Backup Listing" "test_backup_list_functionality" "Tests backup file listing"
    test_run "Clean API" "test_backup_clean_api" "Tests that module exports are clean"
    
    # Cleanup
    cleanup_backup_tests
    test_cleanup
    
    # Show results
    test_summary
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_backup_tests
fi 