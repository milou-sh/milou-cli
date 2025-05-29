#!/bin/bash

# =============================================================================
# Milou CLI - Comprehensive Test Suite Runner
# Executes all tests for the modernized CLI components
# =============================================================================

set -euo pipefail

# Get test directory and project root
readonly TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"

# Load test framework
source "$TEST_DIR/helpers/test-framework.sh"

# Test configuration
readonly TEST_REPORT_FILE="$TEST_DIR/test-results.log"
readonly TEST_SUMMARY_FILE="$TEST_DIR/test-summary.txt"


# =============================================================================
# Test Suite Configuration
# =============================================================================

# Available test suites
declare -A TEST_SUITES=(
    ["unit"]="Unit Tests - Individual module testing"
    ["integration"]="Integration Tests - Command and module integration"
    ["regression"]="Regression Tests - Ensure modernization didn't break functionality"
    ["performance"]="Performance Tests - Check CLI responsiveness"
    ["security"]="Security Tests - Validate security improvements"
)

# Available unit tests
declare -a UNIT_TESTS=(
    "test-backup-core.sh"
    "test-self-update.sh"
    # Add more unit tests as they're created
)

# Available integration tests
declare -a INTEGRATION_TESTS=(
    "test-command-integration.sh"
    # Add more integration tests as they're created
)

# =============================================================================
# Test Suite Functions
# =============================================================================

# Run unit tests
run_unit_tests() {
    test_log "INFO" "🧪 Running Unit Tests"
    echo "======================================="
    
    local unit_passed=0
    local unit_total=0
    
    for unit_test in "${UNIT_TESTS[@]}"; do
        local test_file="$TEST_DIR/unit/$unit_test"
        
        if [[ -f "$test_file" ]]; then
            echo
            test_log "INFO" "Running unit test: $unit_test"
            
            if bash "$test_file"; then
                ((unit_passed++))
                test_log "SUCCESS" "✅ $unit_test PASSED"
            else
                test_log "ERROR" "❌ $unit_test FAILED"
            fi
            ((unit_total++))
        else
            test_log "WARN" "Unit test file not found: $test_file"
        fi
    done
    
    echo
    test_log "INFO" "Unit Tests Summary: $unit_passed/$unit_total passed"
    
    return $((unit_total - unit_passed))
}

# Run integration tests
run_integration_tests() {
    test_log "INFO" "🔗 Running Integration Tests"
    echo "======================================="
    
    local integration_passed=0
    local integration_total=0
    
    for integration_test in "${INTEGRATION_TESTS[@]}"; do
        local test_file="$TEST_DIR/integration/$integration_test"
        
        if [[ -f "$test_file" ]]; then
            echo
            test_log "INFO" "Running integration test: $integration_test"
            
            if bash "$test_file"; then
                ((integration_passed++))
                test_log "SUCCESS" "✅ $integration_test PASSED"
            else
                test_log "ERROR" "❌ $integration_test FAILED"
            fi
            ((integration_total++))
        else
            test_log "WARN" "Integration test file not found: $test_file"
        fi
    done
    
    echo
    test_log "INFO" "Integration Tests Summary: $integration_passed/$integration_total passed"
    
    return $((integration_total - integration_passed))
}

# Run regression tests
run_regression_tests() {
    test_log "INFO" "🔄 Running Regression Tests"
    echo "======================================="
    
    # Test that existing functionality still works after modernization
    local regression_passed=0
    local regression_total=0
    
    # Test 1: CLI still responds to basic commands
    test_log "INFO" "Testing basic CLI responsiveness..."
    if timeout 10 "$PROJECT_ROOT/milou.sh" --help >/dev/null 2>&1; then
        test_log "SUCCESS" "✅ CLI help command works"
        ((regression_passed++))
    else
        test_log "ERROR" "❌ CLI help command failed"
    fi
    ((regression_total++))
    
    # Test 2: Module loading doesn't break
    test_log "INFO" "Testing core module loading..."
    if bash -c "cd '$PROJECT_ROOT' && source src/_core.sh && echo 'Module loading works'" >/dev/null 2>&1; then
        test_log "SUCCESS" "✅ Core modules load successfully"
        ((regression_passed++))
    else
        test_log "ERROR" "❌ Core module loading failed"
    fi
    ((regression_total++))
    
    # Test 3: Command modules can be sourced
    test_log "INFO" "Testing command module loading..."
    if bash -c "cd '$PROJECT_ROOT' && source src/_admin.sh && echo 'Command loading works'" >/dev/null 2>&1; then
        test_log "SUCCESS" "✅ Command modules load successfully"
        ((regression_passed++))
    else
        test_log "ERROR" "❌ Command module loading failed"
    fi
    ((regression_total++))
    
    # Test 4: Exported function count is reasonable
    test_log "INFO" "Testing export cleanliness..."
    local total_exports
    total_exports=$(bash -c "
        cd '$PROJECT_ROOT'
        source src/_backup.sh 2>/dev/null || true
        source src/_update.sh 2>/dev/null || true
        source src/_admin.sh 2>/dev/null || true
        declare -F | grep 'milou\|handle_' | wc -l
    " 2>/dev/null || echo "0")
    
    if [[ $total_exports -lt 100 ]]; then
        test_log "SUCCESS" "✅ Function exports are clean ($total_exports functions)"
        ((regression_passed++))
    else
        test_log "ERROR" "❌ Too many exported functions: $total_exports"
    fi
    ((regression_total++))
    
    echo
    test_log "INFO" "Regression Tests Summary: $regression_passed/$regression_total passed"
    
    return $((regression_total - regression_passed))
}

# Run performance tests
run_performance_tests() {
    test_log "INFO" "⚡ Running Performance Tests"
    echo "======================================="
    
    local performance_passed=0
    local performance_total=0
    
    # Test 1: CLI startup time
    test_log "INFO" "Testing CLI startup performance..."
    local start_time end_time duration
    start_time=$(date +%s%N)
    
    if timeout 5 "$PROJECT_ROOT/milou.sh" --help >/dev/null 2>&1; then
        end_time=$(date +%s%N)
        duration=$(( (end_time - start_time) / 1000000 )) # Convert to milliseconds
        
        if [[ $duration -lt 3000 ]]; then # Less than 3 seconds
            test_log "SUCCESS" "✅ CLI startup time: ${duration}ms (good)"
            ((performance_passed++))
        else
            test_log "WARN" "⚠️ CLI startup time: ${duration}ms (slow)"
        fi
    else
        test_log "ERROR" "❌ CLI startup timeout"
    fi
    ((performance_total++))
    
    # Test 2: Module loading performance
    test_log "INFO" "Testing module loading performance..."
    start_time=$(date +%s%N)
    
    if bash -c "
        cd '$PROJECT_ROOT'
        source src/_core.sh
        source src/_backup.sh
        source src/_update.sh
        source src/_admin.sh
        echo 'Modules loaded'
    " >/dev/null 2>&1; then
        end_time=$(date +%s%N)
        duration=$(( (end_time - start_time) / 1000000 ))
        
        if [[ $duration -lt 1000 ]]; then # Less than 1 second
            test_log "SUCCESS" "✅ Module loading time: ${duration}ms (good)"
            ((performance_passed++))
        else
            test_log "WARN" "⚠️ Module loading time: ${duration}ms (slow)"
        fi
    else
        test_log "ERROR" "❌ Module loading failed"
    fi
    ((performance_total++))
    
    echo
    test_log "INFO" "Performance Tests Summary: $performance_passed/$performance_total passed"
    
    return $((performance_total - performance_passed))
}

# Run security tests
run_security_tests() {
    test_log "INFO" "🔒 Running Security Tests"
    echo "======================================="
    
    local security_passed=0
    local security_total=0
    
    # Test 1: No hardcoded secrets in modules
    test_log "INFO" "Scanning for hardcoded secrets..."
    local secret_patterns=("password=" "token=" "key=" "secret=")
    local secrets_found=false
    
    for pattern in "${secret_patterns[@]}"; do
        if grep -r -i "$pattern" "$PROJECT_ROOT/src" 2>/dev/null | grep -v "test" | grep -v "#" >/dev/null; then
            secrets_found=true
            break
        fi
    done
    
    if [[ "$secrets_found" == "false" ]]; then
        test_log "SUCCESS" "✅ No hardcoded secrets found"
        ((security_passed++))
    else
        test_log "WARN" "⚠️ Potential hardcoded secrets found"
    fi
    ((security_total++))
    
    # Test 2: Proper file permissions on key files
    test_log "INFO" "Checking file permissions..."
    local secure_perms=true
    
    # Check that shell scripts are not world-writable
    while IFS= read -r -d '' file; do
        local perms
        perms=$(stat -c "%a" "$file" 2>/dev/null || echo "000")
        if [[ "${perms: -1}" -gt 5 ]]; then # World-writable
            secure_perms=false
            break
        fi
    done < <(find "$PROJECT_ROOT" -name "*.sh" -type f -print0 2>/dev/null)
    
    if [[ "$secure_perms" == "true" ]]; then
        test_log "SUCCESS" "✅ File permissions are secure"
        ((security_passed++))
    else
        test_log "WARN" "⚠️ Some files have insecure permissions"
    fi
    ((security_total++))
    
    # Test 3: No dangerous shell practices
    test_log "INFO" "Checking for dangerous shell practices..."
    local dangerous_practices=false
    
    # Check for eval usage (can be dangerous)
    if grep -r "eval " "$PROJECT_ROOT/src" 2>/dev/null | grep -v "test" >/dev/null; then
        dangerous_practices=true
    fi
    
    if [[ "$dangerous_practices" == "false" ]]; then
        test_log "SUCCESS" "✅ No dangerous shell practices found"
        ((security_passed++))
    else
        test_log "WARN" "⚠️ Potentially dangerous shell practices found"
    fi
    ((security_total++))
    
    echo
    test_log "INFO" "Security Tests Summary: $security_passed/$security_total passed"
    
    return $((security_total - security_passed))
}

# =============================================================================
# Main Test Runner
# =============================================================================

# Show test suite help
show_help() {
    echo "Milou CLI Test Suite Runner"
    echo "=========================="
    echo
    echo "Usage: $0 [OPTIONS] [TEST_SUITE...]"
    echo
    echo "Test Suites:"
    for suite in "${!TEST_SUITES[@]}"; do
        echo "  $suite    ${TEST_SUITES[$suite]}"
    done
    echo
    echo "Options:"
    echo "  --help, -h        Show this help"
    echo "  --list, -l        List available tests"
    echo "  --verbose, -v     Enable verbose output"
    echo "  --report, -r      Generate detailed report"
    echo "  --all             Run all test suites (default)"
    echo
    echo "Examples:"
    echo "  $0                Run all tests"
    echo "  $0 unit           Run only unit tests"
    echo "  $0 unit integration  Run unit and integration tests"
    echo "  $0 --verbose --report  Run all tests with verbose output and reporting"
}

# List available tests
list_tests() {
    echo "Available Tests:"
    echo "==============="
    echo
    echo "Unit Tests:"
    for test in "${UNIT_TESTS[@]}"; do
        echo "  $test"
    done
    echo
    echo "Integration Tests:"
    for test in "${INTEGRATION_TESTS[@]}"; do
        echo "  $test"
    done
}

# Generate test report
generate_report() {
    local total_suites_run="$1"
    local total_suites_passed="$2"
    
    cat > "$TEST_SUMMARY_FILE" << EOF
Milou CLI Test Suite Results
============================
Generated: $(date)

Test Environment:
- Project Root: $PROJECT_ROOT
- Test Directory: $TEST_DIR
- Shell: $SHELL

Test Suites Run: $total_suites_run
Test Suites Passed: $total_suites_passed

Overall Result: $([ $total_suites_passed -eq $total_suites_run ] && echo "✅ ALL PASSED" || echo "❌ SOME FAILED")

Details:
EOF
    
    if [[ -f "$TEST_REPORT_FILE" ]]; then
        cat "$TEST_REPORT_FILE" >> "$TEST_SUMMARY_FILE"
    fi
    
    echo
    test_log "INFO" "Test report generated: $TEST_SUMMARY_FILE"
}

# Main function
main() {
    local -a test_suites_to_run=()
    local verbose=false
    local generate_report_flag=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --list|-l)
                list_tests
                exit 0
                ;;
            --verbose|-v)
                verbose=true
                export TEST_VERBOSE=true
                shift
                ;;
            --report|-r)
                generate_report_flag=true
                shift
                ;;
            --all)
                test_suites_to_run=("unit" "integration" "regression" "performance" "security")
                shift
                ;;
            unit|integration|regression|performance|security)
                test_suites_to_run+=("$1")
                shift
                ;;
            *)
                echo "Unknown option: $1" >&2
                show_help
                exit 1
                ;;
        esac
    done
    
    # Default to all suites if none specified
    if [[ ${#test_suites_to_run[@]} -eq 0 ]]; then
        test_suites_to_run=("unit" "integration" "regression" "performance" "security")
    fi
    
    # Initialize test framework
    test_init "🚀 Milou CLI Comprehensive Test Suite"
    
    # Initialize reporting
    if [[ "$generate_report_flag" == "true" ]]; then
        echo "Test execution started: $(date)" > "$TEST_REPORT_FILE"
    fi
    
    echo "Running test suites: ${test_suites_to_run[*]}"
    echo
    
    local suites_run=0
    local suites_passed=0
    
    # Run selected test suites
    for suite in "${test_suites_to_run[@]}"; do
        ((suites_run++))
        
        case "$suite" in
            "unit")
                if run_unit_tests; then
                    ((suites_passed++))
                fi
                ;;
            "integration")
                if run_integration_tests; then
                    ((suites_passed++))
                fi
                ;;
            "regression")
                if run_regression_tests; then
                    ((suites_passed++))
                fi
                ;;
            "performance")
                if run_performance_tests; then
                    ((suites_passed++))
                fi
                ;;
            "security")
                if run_security_tests; then
                    ((suites_passed++))
                fi
                ;;
            *)
                test_log "WARN" "Unknown test suite: $suite"
                ;;
        esac
        
        echo
    done
    
    # Final summary
    echo -e "${BOLD}=====================================${NC}"
    echo -e "${BOLD}FINAL TEST RESULTS${NC}"
    echo -e "${BOLD}=====================================${NC}"
    echo
    echo "Test Suites Run: $suites_run"
    echo "Test Suites Passed: $suites_passed"
    echo "Test Suites Failed: $((suites_run - suites_passed))"
    echo
    
    if [[ $suites_passed -eq $suites_run ]]; then
        test_log "SUCCESS" "🎉 ALL TEST SUITES PASSED!"
        echo
        test_log "SUCCESS" "🚀 Milou CLI modernization is ready for production!"
    else
        test_log "ERROR" "❌ Some test suites failed"
        echo
        test_log "INFO" "📋 Review test output and fix issues before proceeding"
    fi
    
    # Generate report if requested
    if [[ "$generate_report_flag" == "true" ]]; then
        generate_report "$suites_run" "$suites_passed"
    fi
    
    # Exit with appropriate code
    exit $((suites_run - suites_passed))
}

# Run main function
main "$@" 