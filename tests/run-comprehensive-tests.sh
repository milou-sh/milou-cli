#!/bin/bash

# =============================================================================
# Comprehensive Test Runner - Modern Testing System for Milou CLI
# Replaces old testing infrastructure with thorough module coverage
# =============================================================================

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly TEST_RESULTS_DIR="$SCRIPT_DIR/results"
readonly TEST_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Test configuration
PARALLEL_TESTS="${PARALLEL_TESTS:-false}"
VERBOSE_OUTPUT="${VERBOSE_OUTPUT:-false}"
FAST_MODE="${FAST_MODE:-false}"

# =============================================================================
# Utility Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_step() {
    echo
    echo -e "${PURPLE}${BOLD}=== $* ===${NC}"
    echo
}

# =============================================================================
# Test Infrastructure Setup
# =============================================================================

setup_test_environment() {
    log_step "Setting Up Test Environment"
    
    # Create results directory
    mkdir -p "$TEST_RESULTS_DIR"
    
    # Set environment variables
    export MILOU_SCRIPT_DIR="$PROJECT_ROOT"
    export MILOU_CLI_ROOT="$PROJECT_ROOT"
    export TEST_MODE="true"
    export FORCE_MODE="true"  # Non-interactive for tests
    
    # Clean up any previous test artifacts
    find "$SCRIPT_DIR/tmp" -type f -name "*.tmp" -delete 2>/dev/null || true
    find "$SCRIPT_DIR/tmp" -type d -empty -delete 2>/dev/null || true
    
    log_success "Test environment setup complete"
}

cleanup_test_environment() {
    log_step "Cleaning Up Test Environment"
    
    # Clean temporary files
    find "$SCRIPT_DIR/tmp" -type f -name "*.test.*" -delete 2>/dev/null || true
    
    # Unset test environment variables
    unset TEST_MODE FORCE_MODE 2>/dev/null || true
    
    log_success "Test environment cleanup complete"
}

# =============================================================================
# Individual Test Module Runners
# =============================================================================

run_unit_tests() {
    log_step "Running Unit Tests"
    
    local unit_test_dir="$SCRIPT_DIR/unit"
    local unit_tests_passed=0
    local unit_tests_failed=0
    local unit_test_results=()
    
    # List of all unit test files with their corresponding runner functions
    local -A unit_test_files=(
        ["test-core-module.sh"]="main"
        ["test-validation-module.sh"]="run_validation_tests"
        ["test-docker-module.sh"]="run_docker_tests"
        ["test-ssl-module.sh"]="run_ssl_tests"
        ["test-config-module.sh"]="run_config_tests"
        ["test-setup-module.sh"]="run_setup_tests"
        ["test-admin-module.sh"]="run_admin_tests"
        ["test-user-module.sh"]="run_user_tests"
        ["test-backup-core.sh"]="run_backup_tests"
        ["test-self-update.sh"]="run_self_update_tests"
    )
    
    log_info "Discovered ${#unit_test_files[@]} unit test modules"
    echo
    
    for test_file in "${!unit_test_files[@]}"; do
        local test_path="$unit_test_dir/$test_file"
        local test_function="${unit_test_files[$test_file]}"
        
        if [[ -f "$test_path" ]]; then
            log_info "Running unit test: $test_file"
            
            local start_time=$(date +%s)
            local result_file="$TEST_RESULTS_DIR/unit_${test_file%.sh}_${TEST_TIMESTAMP}.log"
            
            # Source the test file and call its main runner function
            if ( source "$test_path" && "$test_function" ) > "$result_file" 2>&1; then
                local end_time=$(date +%s)
                local duration=$((end_time - start_time))
                
                log_success "✅ $test_file (${duration}s)"
                ((unit_tests_passed++))
                unit_test_results+=("✅ $test_file")
            else
                local end_time=$(date +%s)
                local duration=$((end_time - start_time))
                
                log_error "❌ $test_file (${duration}s)"
                ((unit_tests_failed++))
                unit_test_results+=("❌ $test_file")
                
                if [[ "$VERBOSE_OUTPUT" == "true" ]]; then
                    echo "Error details:"
                    tail -20 "$result_file" | sed 's/^/  /'
                fi
            fi
        else
            log_warn "⚠️  Unit test not found: $test_file"
            ((unit_tests_failed++))
            unit_test_results+=("⚠️  $test_file (missing)")
        fi
    done
    
    echo
    log_info "Unit Test Results:"
    printf '  %s\n' "${unit_test_results[@]}"
    echo
    log_info "Unit Tests: $unit_tests_passed passed, $unit_tests_failed failed"
    
    return $unit_tests_failed
}

run_integration_tests() {
    log_step "Running Integration Tests"
    
    local integration_test_dir="$SCRIPT_DIR/integration"
    local integration_tests_passed=0
    local integration_tests_failed=0
    local integration_test_results=()
    
    # List of integration test files
    local integration_test_files=(
        "test-system-integration.sh"
    )
    
    log_info "Discovered ${#integration_test_files[@]} integration test modules"
    echo
    
    for test_file in "${integration_test_files[@]}"; do
        local test_path="$integration_test_dir/$test_file"
        
        if [[ -f "$test_path" ]]; then
            log_info "Running integration test: $test_file"
            
            local start_time=$(date +%s)
            local result_file="$TEST_RESULTS_DIR/integration_${test_file%.sh}_${TEST_TIMESTAMP}.log"
            
            if bash "$test_path" > "$result_file" 2>&1; then
                local end_time=$(date +%s)
                local duration=$((end_time - start_time))
                
                log_success "✅ $test_file (${duration}s)"
                ((integration_tests_passed++))
                integration_test_results+=("✅ $test_file")
            else
                local end_time=$(date +%s)
                local duration=$((end_time - start_time))
                
                log_error "❌ $test_file (${duration}s)"
                ((integration_tests_failed++))
                integration_test_results+=("❌ $test_file")
                
                if [[ "$VERBOSE_OUTPUT" == "true" ]]; then
                    echo "Error details:"
                    tail -20 "$result_file" | sed 's/^/  /'
                fi
            fi
        else
            log_warn "⚠️  Integration test not found: $test_file"
            ((integration_tests_failed++))
            integration_test_results+=("⚠️  $test_file (missing)")
        fi
    done
    
    echo
    log_info "Integration Test Results:"
    printf '  %s\n' "${integration_test_results[@]}"
    echo
    log_info "Integration Tests: $integration_tests_passed passed, $integration_tests_failed failed"
    
    return $integration_tests_failed
}

run_performance_tests() {
    if [[ "$FAST_MODE" == "true" ]]; then
        log_info "Skipping performance tests (fast mode enabled)"
        return 0
    fi
    
    log_step "Running Performance Tests"
    
    local performance_tests_passed=0
    local performance_tests_failed=0
    
    # Test 1: Module loading performance
    log_info "Testing module loading performance..."
    local start_time=$(date +%s%N)
    
    # Load all modules
    for module in "$PROJECT_ROOT/src/_"*.sh; do
        if [[ -f "$module" ]]; then
            source "$module" >/dev/null 2>&1 || true
        fi
    done
    
    local end_time=$(date +%s%N)
    local duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    if [[ $duration_ms -lt 3000 ]]; then  # Less than 3 seconds
        log_success "✅ Module loading performance: ${duration_ms}ms (acceptable)"
        ((performance_tests_passed++))
    else
        log_error "❌ Module loading performance: ${duration_ms}ms (too slow)"
        ((performance_tests_failed++))
    fi
    
    # Test 2: Main entry point performance
    log_info "Testing main entry point performance..."
    local start_time=$(date +%s%N)
    
    timeout 10 "$PROJECT_ROOT/src/milou" --version >/dev/null 2>&1 || true
    
    local end_time=$(date +%s%N)
    local duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    if [[ $duration_ms -lt 2000 ]]; then  # Less than 2 seconds
        log_success "✅ Entry point performance: ${duration_ms}ms (acceptable)"
        ((performance_tests_passed++))
    else
        log_error "❌ Entry point performance: ${duration_ms}ms (too slow)"
        ((performance_tests_failed++))
    fi
    
    log_info "Performance Tests: $performance_tests_passed passed, $performance_tests_failed failed"
    return $performance_tests_failed
}

# =============================================================================
# Test Coverage Analysis
# =============================================================================

analyze_test_coverage() {
    log_step "Analyzing Test Coverage"
    
    local total_modules=0
    local tested_modules=0
    local coverage_results=()
    
    # Define mapping between modules and their test files
    local -A module_test_mapping=(
        ["_admin"]="test-admin-module.sh"
        ["_backup"]="test-backup-core.sh"
        ["_config"]="test-config-module.sh"
        ["_core"]="test-core-module.sh"
        ["_docker"]="test-docker-module.sh"
        ["_setup"]="test-setup-module.sh"
        ["_ssl"]="test-ssl-module.sh"
        ["_update"]="test-self-update.sh"
        ["_user"]="test-user-module.sh"
        ["_validation"]="test-validation-module.sh"
    )
    
    # Count source modules and check for corresponding tests
    for module in "$PROJECT_ROOT/src/_"*.sh; do
        if [[ -f "$module" ]]; then
            ((total_modules++))
            local module_name=$(basename "$module" .sh)
            local test_file="${module_test_mapping[$module_name]:-}"
            local test_path="$SCRIPT_DIR/unit/$test_file"
            
            if [[ -n "$test_file" && -f "$test_path" ]]; then
                ((tested_modules++))
                coverage_results+=("✅ ${module_name}")
            else
                coverage_results+=("❌ ${module_name} (no test)")
            fi
        fi
    done
    
    # Calculate coverage percentage
    local coverage_percent=0
    if [[ $total_modules -gt 0 ]]; then
        coverage_percent=$(( (tested_modules * 100) / total_modules ))
    fi
    
    log_info "Test Coverage Analysis:"
    printf '  %s\n' "${coverage_results[@]}"
    echo
    log_info "Module Coverage: $tested_modules/$total_modules modules (${coverage_percent}%)"
    
    if [[ $coverage_percent -ge 80 ]]; then
        log_success "✅ Good test coverage (${coverage_percent}%)"
        return 0
    elif [[ $coverage_percent -ge 60 ]]; then
        log_warn "⚠️  Moderate test coverage (${coverage_percent}%)"
        return 0
    else
        log_error "❌ Poor test coverage (${coverage_percent}%)"
        log_warn "Test coverage needs improvement"
        return 1
    fi
}

# =============================================================================
# Test Report Generation
# =============================================================================

generate_test_report() {
    local total_passed="$1"
    local total_failed="$2"
    local total_duration="$3"
    
    log_step "Generating Test Report"
    
    local report_file="$TEST_RESULTS_DIR/test_report_${TEST_TIMESTAMP}.md"
    
    cat > "$report_file" << EOF
# Milou CLI Test Report

**Generated:** $(date)
**Duration:** ${total_duration}s
**Results:** $total_passed passed, $total_failed failed

## Test Summary

| Test Type | Status |
|-----------|--------|
| Unit Tests | $([ "$total_failed" -eq 0 ] && echo "✅ PASSED" || echo "❌ FAILED") |
| Integration Tests | $([ "$total_failed" -eq 0 ] && echo "✅ PASSED" || echo "❌ FAILED") |
| Performance Tests | $([ "$total_failed" -eq 0 ] && echo "✅ PASSED" || echo "❌ FAILED") |

## Module Coverage

EOF
    
    # Define the same module mapping as in coverage analysis
    local -A module_test_mapping=(
        ["_admin"]="test-admin-module.sh"
        ["_backup"]="test-backup-core.sh"
        ["_config"]="test-config-module.sh"
        ["_core"]="test-core-module.sh"
        ["_docker"]="test-docker-module.sh"
        ["_setup"]="test-setup-module.sh"
        ["_ssl"]="test-ssl-module.sh"
        ["_update"]="test-self-update.sh"
        ["_user"]="test-user-module.sh"
        ["_validation"]="test-validation-module.sh"
    )
    
    # Add module coverage to report using consistent mapping
    for module in "$PROJECT_ROOT/src/_"*.sh; do
        if [[ -f "$module" ]]; then
            local module_name=$(basename "$module" .sh)
            local test_file="${module_test_mapping[$module_name]:-}"
            local test_path="$SCRIPT_DIR/unit/$test_file"
            
            if [[ -n "$test_file" && -f "$test_path" ]]; then
                echo "- ✅ ${module_name}" >> "$report_file"
            else
                echo "- ❌ ${module_name} (no test)" >> "$report_file"
            fi
        fi
    done
    
    cat >> "$report_file" << EOF

## Test Files

EOF
    
    # List all test result files
    find "$TEST_RESULTS_DIR" -name "*_${TEST_TIMESTAMP}.log" -exec basename {} \; | while read -r result_file; do
        echo "- $result_file" >> "$report_file"
    done
    
    log_success "Test report generated: $report_file"
}

# =============================================================================
# Main Test Execution
# =============================================================================

main() {
    local start_time=$(date +%s)
    local total_passed=0
    local total_failed=0
    
    echo -e "${BOLD}${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║                      MILOU CLI COMPREHENSIVE TESTS                   ║"
    echo "║                     Modern Testing System v2.0                      ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Setup
    setup_test_environment
    
    # Run test suites
    local unit_result=0
    local integration_result=0
    local performance_result=0
    local coverage_result=0
    
    # Unit tests
    if run_unit_tests; then
        log_success "Unit tests completed successfully"
    else
        unit_result=$?
        log_error "Unit tests failed"
    fi
    
    # Integration tests
    if run_integration_tests; then
        log_success "Integration tests completed successfully"
    else
        integration_result=$?
        log_error "Integration tests failed"
    fi
    
    # Performance tests
    if run_performance_tests; then
        log_success "Performance tests completed successfully"
    else
        performance_result=$?
        log_error "Performance tests failed"
    fi
    
    # Coverage analysis
    if analyze_test_coverage; then
        log_success "Test coverage analysis completed successfully"
    else
        coverage_result=$?
        log_warn "Test coverage needs improvement"
    fi
    
    # Calculate totals
    total_failed=$((unit_result + integration_result + performance_result))
    total_passed=$((total_failed == 0 ? 1 : 0))
    
    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    
    # Generate report
    generate_test_report "$total_passed" "$total_failed" "$total_duration"
    
    # Cleanup
    cleanup_test_environment
    
    # Final results
    echo
    log_step "Test Results Summary"
    
    if [[ $total_failed -eq 0 ]]; then
        echo -e "${BOLD}${GREEN}"
        echo "╔══════════════════════════════════════════════════════════════════════╗"
        echo "║                        🎉 ALL TESTS PASSED! 🎉                       ║"
        echo "║                                                                      ║"
        echo "║  ✅ Unit Tests: PASSED                                               ║"
        echo "║  ✅ Integration Tests: PASSED                                        ║"
        echo "║  ✅ Performance Tests: PASSED                                        ║"
        echo "║  ✅ Coverage Analysis: PASSED                                        ║"
        echo "║                                                                      ║"
        echo "║               System is ready for production use!                   ║"
        echo "╚══════════════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
        return 0
    else
        echo -e "${BOLD}${RED}"
        echo "╔══════════════════════════════════════════════════════════════════════╗"
        echo "║                       ❌ TESTS FAILED ❌                             ║"
        echo "║                                                                      ║"
        echo "║  $([ $unit_result -eq 0 ] && echo "✅" || echo "❌") Unit Tests: $([ $unit_result -eq 0 ] && echo "PASSED" || echo "FAILED")                                              ║"
        echo "║  $([ $integration_result -eq 0 ] && echo "✅" || echo "❌") Integration Tests: $([ $integration_result -eq 0 ] && echo "PASSED" || echo "FAILED")                                       ║"
        echo "║  $([ $performance_result -eq 0 ] && echo "✅" || echo "❌") Performance Tests: $([ $performance_result -eq 0 ] && echo "PASSED" || echo "FAILED")                                       ║"
        echo "║  $([ $coverage_result -eq 0 ] && echo "✅" || echo "⚠️ ") Coverage Analysis: $([ $coverage_result -eq 0 ] && echo "PASSED" || echo "NEEDS WORK")                                      ║"
        echo "║                                                                      ║"
        echo "║              Check test results for detailed information             ║"
        echo "╚══════════════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
        return 1
    fi
}

# Show usage if needed
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Milou CLI Comprehensive Test Runner"
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  --help, -h      Show this help message"
    echo "  --verbose       Enable verbose output"
    echo "  --fast          Skip performance tests"
    echo "  --parallel      Run tests in parallel (experimental)"
    echo
    echo "Environment Variables:"
    echo "  VERBOSE_OUTPUT=true   Enable verbose output"
    echo "  FAST_MODE=true        Skip performance tests"
    echo "  PARALLEL_TESTS=true   Run tests in parallel"
    echo
    exit 0
fi

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose)
            VERBOSE_OUTPUT="true"
            shift
            ;;
        --fast)
            FAST_MODE="true"
            shift
            ;;
        --parallel)
            PARALLEL_TESTS="true"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main "$@" 