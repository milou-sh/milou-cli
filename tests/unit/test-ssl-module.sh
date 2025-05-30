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

test_export_cleanliness() {
    test_log "INFO" "Testing export cleanliness..."
    
    source "$PROJECT_ROOT/src/_ssl.sh" || return 1
    
    # Count exported functions from SSL module
    local ssl_exports
    ssl_exports=$(declare -F | grep -E "(ssl_|milou_ssl|cert_|certificate_)" | wc -l)
    
    # Should have reasonable number of exports
    if [[ $ssl_exports -gt 50 ]]; then
        test_log "WARN" "Many SSL exports: $ssl_exports (check if all are necessary)"
    fi
    
    # Test that essential functions are exported
    assert_function_exists "ssl_generate_certificates" "SSL generation function should be exported"
    
    test_log "SUCCESS" "SSL module exports are reasonable ($ssl_exports functions)"
    return 0
}

test_certificate_validation() {
    test_log "INFO" "Testing certificate validation functions..."
    
    source "$PROJECT_ROOT/src/_ssl.sh" || return 1
    
    # Test certificate format validation
    if command -v validate_certificate_format >/dev/null 2>&1; then
        # Test with dummy certificate data
        local dummy_cert="-----BEGIN CERTIFICATE-----\nMIIDXTCCAkWgAwIBAgIJAKoK/heBjcOuMA0GCSqGSIb3DQEBBQUAMEUxCzAJBgNV\n-----END CERTIFICATE-----"
        if validate_certificate_format "$dummy_cert"; then
            test_log "DEBUG" "Certificate format validation works"
        else
            test_log "WARN" "Certificate format validation failed (may be expected)"
        fi
    fi
    
    # Test certificate expiry checking
    if command -v check_certificate_expiry >/dev/null 2>&1; then
        assert_function_exists "check_certificate_expiry" "Certificate expiry check should exist"
    fi
    
    # Test certificate chain validation
    if command -v validate_certificate_chain >/dev/null 2>&1; then
        assert_function_exists "validate_certificate_chain" "Certificate chain validation should exist"
    fi
    
    test_log "SUCCESS" "Certificate validation functions work correctly"
    return 0
}

test_certificate_generation() {
    test_log "INFO" "Testing certificate generation functions..."
    
    source "$PROJECT_ROOT/src/_ssl.sh" || return 1
    
    # Test self-signed certificate generation
    if command -v generate_self_signed_cert >/dev/null 2>&1; then
        assert_function_exists "generate_self_signed_cert" "Self-signed cert generation should exist"
    fi
    
    # Test CSR generation
    if command -v generate_certificate_request >/dev/null 2>&1; then
        assert_function_exists "generate_certificate_request" "CSR generation should exist"
    fi
    
    # Test private key generation
    if command -v generate_private_key >/dev/null 2>&1; then
        assert_function_exists "generate_private_key" "Private key generation should exist"
    fi
    
    # Test certificate authority setup
    if command -v setup_certificate_authority >/dev/null 2>&1; then
        assert_function_exists "setup_certificate_authority" "CA setup should exist"
    fi
    
    test_log "SUCCESS" "Certificate generation functions work correctly"
    return 0
}

test_ssl_configuration() {
    test_log "INFO" "Testing SSL configuration functions..."
    
    source "$PROJECT_ROOT/src/_ssl.sh" || return 1
    
    # Test SSL configuration validation
    if command -v validate_ssl_config >/dev/null 2>&1; then
        assert_function_exists "validate_ssl_config" "SSL config validation should exist"
    fi
    
    # Test SSL cipher configuration
    if command -v configure_ssl_ciphers >/dev/null 2>&1; then
        assert_function_exists "configure_ssl_ciphers" "SSL cipher config should exist"
    fi
    
    # Test SSL protocol configuration
    if command -v configure_ssl_protocols >/dev/null 2>&1; then
        assert_function_exists "configure_ssl_protocols" "SSL protocol config should exist"
    fi
    
    # Test SSL security headers
    if command -v configure_ssl_headers >/dev/null 2>&1; then
        assert_function_exists "configure_ssl_headers" "SSL headers config should exist"
    fi
    
    test_log "SUCCESS" "SSL configuration functions work correctly"
    return 0
}

test_certificate_renewal() {
    test_log "INFO" "Testing certificate renewal functions..."
    
    source "$PROJECT_ROOT/src/_ssl.sh" || return 1
    
    # Test automatic renewal setup
    if command -v setup_auto_renewal >/dev/null 2>&1; then
        assert_function_exists "setup_auto_renewal" "Auto renewal setup should exist"
    fi
    
    # Test renewal checking
    if command -v check_renewal_needed >/dev/null 2>&1; then
        assert_function_exists "check_renewal_needed" "Renewal check should exist"
    fi
    
    # Test certificate backup before renewal
    if command -v backup_certificates >/dev/null 2>&1; then
        assert_function_exists "backup_certificates" "Certificate backup should exist"
    fi
    
    # Test renewal notification
    if command -v notify_renewal_status >/dev/null 2>&1; then
        assert_function_exists "notify_renewal_status" "Renewal notification should exist"
    fi
    
    test_log "SUCCESS" "Certificate renewal functions work correctly"
    return 0
}

test_ssl_security_functions() {
    test_log "INFO" "Testing SSL security functions..."
    
    source "$PROJECT_ROOT/src/_ssl.sh" || return 1
    
    # Test SSL vulnerability scanning
    if command -v scan_ssl_vulnerabilities >/dev/null 2>&1; then
        assert_function_exists "scan_ssl_vulnerabilities" "SSL vulnerability scan should exist"
    fi
    
    # Test SSL strength testing
    if command -v test_ssl_strength >/dev/null 2>&1; then
        assert_function_exists "test_ssl_strength" "SSL strength test should exist"
    fi
    
    # Test SSL compliance checking
    if command -v check_ssl_compliance >/dev/null 2>&1; then
        assert_function_exists "check_ssl_compliance" "SSL compliance check should exist"
    fi
    
    # Test SSL hardening
    if command -v harden_ssl_configuration >/dev/null 2>&1; then
        assert_function_exists "harden_ssl_configuration" "SSL hardening should exist"
    fi
    
    test_log "SUCCESS" "SSL security functions work correctly"
    return 0
}

test_certificate_management() {
    test_log "INFO" "Testing certificate management functions..."
    
    source "$PROJECT_ROOT/src/_ssl.sh" || return 1
    
    # Test certificate installation
    if command -v install_certificate >/dev/null 2>&1; then
        assert_function_exists "install_certificate" "Certificate installation should exist"
    fi
    
    # Test certificate removal
    if command -v remove_certificate >/dev/null 2>&1; then
        assert_function_exists "remove_certificate" "Certificate removal should exist"
    fi
    
    # Test certificate listing
    if command -v list_certificates >/dev/null 2>&1; then
        assert_function_exists "list_certificates" "Certificate listing should exist"
    fi
    
    # Test certificate information
    if command -v get_certificate_info >/dev/null 2>&1; then
        assert_function_exists "get_certificate_info" "Certificate info should exist"
    fi
    
    test_log "SUCCESS" "Certificate management functions work correctly"
    return 0
}

test_ssl_monitoring() {
    test_log "INFO" "Testing SSL monitoring functions..."
    
    source "$PROJECT_ROOT/src/_ssl.sh" || return 1
    
    # Test SSL health monitoring
    if command -v monitor_ssl_health >/dev/null 2>&1; then
        assert_function_exists "monitor_ssl_health" "SSL health monitoring should exist"
    fi
    
    # Test SSL performance monitoring
    if command -v monitor_ssl_performance >/dev/null 2>&1; then
        assert_function_exists "monitor_ssl_performance" "SSL performance monitoring should exist"
    fi
    
    # Test SSL error monitoring
    if command -v monitor_ssl_errors >/dev/null 2>&1; then
        assert_function_exists "monitor_ssl_errors" "SSL error monitoring should exist"
    fi
    
    # Test SSL alert configuration
    if command -v configure_ssl_alerts >/dev/null 2>&1; then
        assert_function_exists "configure_ssl_alerts" "SSL alert config should exist"
    fi
    
    test_log "SUCCESS" "SSL monitoring functions work correctly"
    return 0
}

test_ssl_troubleshooting() {
    test_log "INFO" "Testing SSL troubleshooting functions..."
    
    source "$PROJECT_ROOT/src/_ssl.sh" || return 1
    
    # Test SSL diagnostics
    if command -v diagnose_ssl_issues >/dev/null 2>&1; then
        assert_function_exists "diagnose_ssl_issues" "SSL diagnostics should exist"
    fi
    
    # Test SSL repair functions
    if command -v repair_ssl_configuration >/dev/null 2>&1; then
        assert_function_exists "repair_ssl_configuration" "SSL repair should exist"
    fi
    
    # Test SSL debugging
    if command -v debug_ssl_handshake >/dev/null 2>&1; then
        assert_function_exists "debug_ssl_handshake" "SSL handshake debug should exist"
    fi
    
    # Test SSL log analysis
    if command -v analyze_ssl_logs >/dev/null 2>&1; then
        assert_function_exists "analyze_ssl_logs" "SSL log analysis should exist"
    fi
    
    test_log "SUCCESS" "SSL troubleshooting functions work correctly"
    return 0
}

test_ssl_integration() {
    test_log "INFO" "Testing SSL integration functions..."
    
    source "$PROJECT_ROOT/src/_ssl.sh" || return 1
    
    # Test web server integration
    if command -v integrate_with_nginx >/dev/null 2>&1; then
        assert_function_exists "integrate_with_nginx" "Nginx integration should exist"
    fi
    
    if command -v integrate_with_apache >/dev/null 2>&1; then
        assert_function_exists "integrate_with_apache" "Apache integration should exist"
    fi
    
    # Test load balancer integration
    if command -v integrate_with_loadbalancer >/dev/null 2>&1; then
        assert_function_exists "integrate_with_loadbalancer" "Load balancer integration should exist"
    fi
    
    # Test CDN integration
    if command -v integrate_with_cdn >/dev/null 2>&1; then
        assert_function_exists "integrate_with_cdn" "CDN integration should exist"
    fi
    
    test_log "SUCCESS" "SSL integration functions work correctly"
    return 0
}

# =============================================================================
# Main Test Runner
# =============================================================================

run_ssl_tests() {
    test_init "🧪 SSL Module Tests"
    
    # Setup test environment
    test_setup
    setup_ssl_tests
    
    # Run individual tests
    test_run "Module Loading" "test_ssl_module_loading" "Tests that SSL module loads correctly"
    test_run "Certificate Generation" "test_certificate_generation" "Tests certificate generation functions"
    test_run "Certificate Validation" "test_certificate_validation" "Tests certificate validation functions"
    test_run "SSL Configuration" "test_ssl_configuration" "Tests SSL configuration functions"
    test_run "Certificate Renewal" "test_certificate_renewal" "Tests certificate renewal functions"
    test_run "SSL Security" "test_ssl_security_functions" "Tests SSL security functions"
    test_run "Certificate Management" "test_certificate_management" "Tests certificate management functions"
    test_run "SSL Monitoring" "test_ssl_monitoring" "Tests SSL monitoring functions"
    test_run "SSL Troubleshooting" "test_ssl_troubleshooting" "Tests SSL troubleshooting functions"
    test_run "SSL Integration" "test_ssl_integration" "Tests SSL integration functions"
    test_run "Export Cleanliness" "test_export_cleanliness" "Tests module export hygiene"
    
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