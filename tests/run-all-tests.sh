#!/bin/bash

# =============================================================================
# Milou CLI - Comprehensive Test Runner
# Week 3 Testing Infrastructure Implementation
# =============================================================================

set -euo pipefail

# Get script directory and project root
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Test configuration
readonly TEST_RESULTS_DIR="$PROJECT_ROOT/test-results"
readonly COVERAGE_DIR="$PROJECT_ROOT/coverage"
readonly TEST_TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Global test tracking
declare -g TOTAL_TESTS=0
declare -g TOTAL_PASSED=0
declare -g TOTAL_FAILED=0
declare -g TOTAL_SKIPPED=0
declare -g TEST_START_TIME=0
declare -g FAILED_TESTS=()

# =============================================================================
# LOGGING AND OUTPUT FUNCTIONS
# =============================================================================

log() {
    echo -e "${CYAN}[$(date +'%H:%M:%S')]${NC} $*"
}

success() {
    echo -e "${GREEN}${BOLD}✅ SUCCESS${NC} $*"
}

error() {
    echo -e "${RED}${BOLD}❌ ERROR${NC} $*"
}

warn() {
    echo -e "${YELLOW}${BOLD}⚠️  WARNING${NC} $*"
}

step() {
    echo -e "${BLUE}${BOLD}🔄 STEP${NC} $*"
}

# =============================================================================
# TEST INFRASTRUCTURE SETUP
# =============================================================================

setup_test_infrastructure() {
    step "Setting up test infrastructure..."
    
    # Create test results directory
    mkdir -p "$TEST_RESULTS_DIR"
    mkdir -p "$COVERAGE_DIR"
    
    # Initialize test tracking
    TEST_START_TIME=$(date +%s)
    
    # Create test summary file
    cat > "$TEST_RESULTS_DIR/test-summary-$TEST_TIMESTAMP.json" << EOF
{
  "timestamp": "$TEST_TIMESTAMP",
  "start_time": "$TEST_START_TIME",
  "project": "milou-cli",
  "version": "4.0.0",
  "test_suites": []
}
EOF
    
    success "Test infrastructure ready"
}

# =============================================================================
# INDIVIDUAL TEST SUITE RUNNERS
# =============================================================================

run_test_suite() {
    local test_file="$1"
    local suite_name="$2"
    local description="$3"
    
    log "Running test suite: $suite_name"
    echo "  📄 $description"
    
    local start_time=$(date +%s)
    local test_output_file="$TEST_RESULTS_DIR/${suite_name}-${TEST_TIMESTAMP}.log"
    
    # Run the test and capture output
    local exit_code=0
    if bash "$test_file" > "$test_output_file" 2>&1; then
        local suite_result="PASSED"
        echo -e "  ${GREEN}✅ $suite_name PASSED${NC}"
    else
        exit_code=$?
        local suite_result="FAILED"
        echo -e "  ${RED}❌ $suite_name FAILED${NC}"
        FAILED_TESTS+=("$suite_name")
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Extract test metrics from output
    local tests_run=$(grep -o "Total Tests:.*[0-9]" "$test_output_file" | grep -o "[0-9]*" | tail -1 || echo "0")
    local tests_passed=$(grep -o "Passed:.*[0-9]" "$test_output_file" | grep -o "[0-9]*" | tail -1 || echo "0")
    local tests_failed=$(grep -o "Failed:.*[0-9]" "$test_output_file" | grep -o "[0-9]*" | tail -1 || echo "0")
    local tests_skipped=$(grep -o "Skipped:.*[0-9]" "$test_output_file" | grep -o "[0-9]*" | tail -1 || echo "0")
    
    # Update global counters
    TOTAL_TESTS=$((TOTAL_TESTS + tests_run))
    TOTAL_PASSED=$((TOTAL_PASSED + tests_passed))
    TOTAL_FAILED=$((TOTAL_FAILED + tests_failed))
    TOTAL_SKIPPED=$((TOTAL_SKIPPED + tests_skipped))
    
    # Add to summary JSON
    local temp_file=$(mktemp)
    jq --arg name "$suite_name" \
       --arg description "$description" \
       --arg result "$suite_result" \
       --argjson duration "$duration" \
       --argjson tests_run "$tests_run" \
       --argjson tests_passed "$tests_passed" \
       --argjson tests_failed "$tests_failed" \
       --argjson tests_skipped "$tests_skipped" \
       --arg log_file "$(basename "$test_output_file")" \
       '.test_suites += [{
         name: $name,
         description: $description,
         result: $result,
         duration: $duration,
         tests_run: $tests_run,
         tests_passed: $tests_passed,
         tests_failed: $tests_failed,
         tests_skipped: $tests_skipped,
         log_file: $log_file
       }]' "$TEST_RESULTS_DIR/test-summary-$TEST_TIMESTAMP.json" > "$temp_file" 2>/dev/null || {
        # Fallback if jq is not available
        echo "  (JSON summary update skipped - jq not available)"
    }
    
    if [[ -f "$temp_file" ]] && [[ -s "$temp_file" ]]; then
        mv "$temp_file" "$TEST_RESULTS_DIR/test-summary-$TEST_TIMESTAMP.json"
    else
        rm -f "$temp_file" 2>/dev/null || true
    fi
    
    echo "  ⏱️  Duration: ${duration}s"
    echo
    
    return $exit_code
}

# =============================================================================
# COVERAGE ANALYSIS
# =============================================================================

analyze_test_coverage() {
    step "Analyzing test coverage..."
    
    local total_functions=0
    local tested_functions=0
    local coverage_report="$COVERAGE_DIR/coverage-report-$TEST_TIMESTAMP.txt"
    
    # Count total functions in source modules
    log "Scanning source modules for functions..."
    
    local modules=(
        "_core.sh"
        "_state.sh"
        "_docker.sh"
        "_config.sh"
        "_validation.sh"
        "_setup.sh"
        "_error_recovery.sh"
        "_update.sh"
        "_admin.sh"
        "_backup.sh"
        "_ssl.sh"
        "_user.sh"
    )
    
    {
        echo "# Milou CLI Test Coverage Report"
        echo "Generated: $(date)"
        echo "Timestamp: $TEST_TIMESTAMP"
        echo ""
        echo "## Module Coverage Analysis"
        echo ""
    } > "$coverage_report"
    
    for module in "${modules[@]}"; do
        local module_file="$PROJECT_ROOT/src/$module"
        if [[ -f "$module_file" ]]; then
            local module_functions
            module_functions=$(grep -E "^[a-zA-Z_][a-zA-Z0-9_]*\(\)" "$module_file" | wc -l || echo "0")
            total_functions=$((total_functions + module_functions))
            
            echo "### $module" >> "$coverage_report"
            echo "Functions found: $module_functions" >> "$coverage_report"
            echo "" >> "$coverage_report"
            
            log "  $module: $module_functions functions"
        fi
    done
    
    # Estimate tested functions (basic heuristic)
    local test_files=(
        "test-core-module.sh"
        "test-docker-module.sh"
        "test-config-module.sh"
        "test-validation-module.sh"
        "test-setup-module.sh"
        "test-error-recovery.sh"
        "test-service-lifecycle.sh"
        "test-admin-module.sh"
        "test-backup-core.sh"
        "test-ssl-module.sh"
        "test-user-module.sh"
    )
    
    echo "## Test Coverage Estimation" >> "$coverage_report"
    echo "" >> "$coverage_report"
    
    for test_file in "${test_files[@]}"; do
        local test_path="$PROJECT_ROOT/tests/unit/$test_file"
        if [[ -f "$test_path" ]]; then
            local test_assertions
            test_assertions=$(grep -c "assert_function_exists\|command -v.*>/dev/null" "$test_path" || echo "0")
            tested_functions=$((tested_functions + test_assertions))
            
            echo "- $test_file: ~$test_assertions function tests" >> "$coverage_report"
            log "  $test_file: ~$test_assertions function tests"
        fi
    done
    
    # Calculate coverage percentage
    local coverage_percentage=0
    if [[ $total_functions -gt 0 ]]; then
        coverage_percentage=$(( (tested_functions * 100) / total_functions ))
    fi
    
    {
        echo ""
        echo "## Summary"
        echo "- Total functions found: $total_functions"
        echo "- Functions with tests: ~$tested_functions"
        echo "- Estimated coverage: ~$coverage_percentage%"
        echo ""
        echo "## Coverage Goals"
        echo "- Week 3 Target: 80%"
        echo "- Current Status: $coverage_percentage%"
        
        if [[ $coverage_percentage -ge 80 ]]; then
            echo "- Status: ✅ TARGET ACHIEVED"
        elif [[ $coverage_percentage -ge 60 ]]; then
            echo "- Status: 🟡 GOOD PROGRESS"
        else
            echo "- Status: 🔴 NEEDS IMPROVEMENT"
        fi
    } >> "$coverage_report"
    
    success "Coverage analysis complete: ~$coverage_percentage% (Target: 80%)"
    log "Coverage report: $coverage_report"
    
    return 0
}

# =============================================================================
# PERFORMANCE BENCHMARKS
# =============================================================================

run_performance_benchmarks() {
    step "Running performance benchmarks..."
    
    local benchmark_file="$TEST_RESULTS_DIR/benchmarks-$TEST_TIMESTAMP.txt"
    
    {
        echo "# Milou CLI Performance Benchmarks"
        echo "Generated: $(date)"
        echo ""
    } > "$benchmark_file"
    
    # Test CLI startup time
    log "Benchmarking CLI startup time..."
    local startup_times=()
    for i in {1..5}; do
        local start_time=$(date +%s%N)
        "$PROJECT_ROOT/milou.sh" --version >/dev/null 2>&1 || true
        local end_time=$(date +%s%N)
        local duration=$(( (end_time - start_time) / 1000000 )) # Convert to milliseconds
        startup_times+=("$duration")
    done
    
    # Calculate average startup time
    local total_time=0
    for time in "${startup_times[@]}"; do
        total_time=$((total_time + time))
    done
    local avg_startup_time=$((total_time / ${#startup_times[@]}))
    
    echo "## CLI Startup Performance" >> "$benchmark_file"
    echo "- Average startup time: ${avg_startup_time}ms" >> "$benchmark_file"
    echo "- Target: <2000ms" >> "$benchmark_file"
    
    if [[ $avg_startup_time -lt 2000 ]]; then
        echo "- Status: ✅ TARGET ACHIEVED" >> "$benchmark_file"
        success "CLI startup time: ${avg_startup_time}ms (Target: <2000ms)"
    else
        echo "- Status: 🔴 NEEDS IMPROVEMENT" >> "$benchmark_file"
        warn "CLI startup time: ${avg_startup_time}ms (Target: <2000ms)"
    fi
    
    # Test state detection performance
    log "Benchmarking state detection..."
    local state_times=()
    for i in {1..3}; do
        local start_time=$(date +%s%N)
        "$PROJECT_ROOT/milou.sh" status >/dev/null 2>&1 || true
        local end_time=$(date +%s%N)
        local duration=$(( (end_time - start_time) / 1000000 ))
        state_times+=("$duration")
    done
    
    local total_state_time=0
    for time in "${state_times[@]}"; do
        total_state_time=$((total_state_time + time))
    done
    local avg_state_time=$((total_state_time / ${#state_times[@]}))
    
    echo "" >> "$benchmark_file"
    echo "## State Detection Performance" >> "$benchmark_file"
    echo "- Average state detection time: ${avg_state_time}ms" >> "$benchmark_file"
    echo "- Target: <1000ms" >> "$benchmark_file"
    
    if [[ $avg_state_time -lt 1000 ]]; then
        echo "- Status: ✅ TARGET ACHIEVED" >> "$benchmark_file"
        success "State detection time: ${avg_state_time}ms (Target: <1000ms)"
    else
        echo "- Status: 🔴 NEEDS IMPROVEMENT" >> "$benchmark_file"
        warn "State detection time: ${avg_state_time}ms (Target: <1000ms)"
    fi
    
    log "Performance benchmarks: $benchmark_file"
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

show_test_header() {
    echo
    echo -e "${BOLD}${PURPLE}"
    cat << 'EOF'
    ╔══════════════════════════════════════════════════════════════╗
    ║                    🧪 MILOU CLI TEST SUITE                  ║
    ║                  Week 3 Testing Infrastructure              ║
    ╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo -e "${CYAN}Comprehensive test execution with coverage analysis${NC}"
    echo
}

run_all_tests() {
    local run_coverage="${1:-true}"
    local run_benchmarks="${2:-true}"
    
    show_test_header
    setup_test_infrastructure
    
    step "Executing all test suites..."
    echo
    
    # Core module tests
    if [[ -f "$PROJECT_ROOT/tests/unit/test-core-module.sh" ]]; then
        run_test_suite "$PROJECT_ROOT/tests/unit/test-core-module.sh" \
                      "core-module" \
                      "Core functionality and utilities"
    fi
    
    # Docker module tests
    if [[ -f "$PROJECT_ROOT/tests/unit/test-docker-module.sh" ]]; then
        run_test_suite "$PROJECT_ROOT/tests/unit/test-docker-module.sh" \
                      "docker-module" \
                      "Docker operations and management"
    fi
    
    # Service lifecycle tests (our new Week 2 completion)
    if [[ -f "$PROJECT_ROOT/tests/unit/test-service-lifecycle.sh" ]]; then
        run_test_suite "$PROJECT_ROOT/tests/unit/test-service-lifecycle.sh" \
                      "service-lifecycle" \
                      "Service lifecycle management functions"
    fi
    
    # Configuration module tests
    if [[ -f "$PROJECT_ROOT/tests/unit/test-config-module.sh" ]]; then
        run_test_suite "$PROJECT_ROOT/tests/unit/test-config-module.sh" \
                      "config-module" \
                      "Configuration management"
    fi
    
    # Validation module tests
    if [[ -f "$PROJECT_ROOT/tests/unit/test-validation-module.sh" ]]; then
        run_test_suite "$PROJECT_ROOT/tests/unit/test-validation-module.sh" \
                      "validation-module" \
                      "System validation and checks"
    fi
    
    # Error recovery tests
    if [[ -f "$PROJECT_ROOT/tests/unit/test-error-recovery.sh" ]]; then
        run_test_suite "$PROJECT_ROOT/tests/unit/test-error-recovery.sh" \
                      "error-recovery" \
                      "Error recovery and rollback systems"
    fi
    
    # Setup module tests
    if [[ -f "$PROJECT_ROOT/tests/unit/test-setup-module.sh" ]]; then
        run_test_suite "$PROJECT_ROOT/tests/unit/test-setup-module.sh" \
                      "setup-module" \
                      "Installation and setup procedures"
    fi
    
    # Additional module tests
    for test_file in "$PROJECT_ROOT/tests/unit"/test-*.sh; do
        if [[ -f "$test_file" ]]; then
            local basename_file=$(basename "$test_file")
            case "$basename_file" in
                "test-core-module.sh"|"test-docker-module.sh"|"test-service-lifecycle.sh"|"test-config-module.sh"|"test-validation-module.sh"|"test-error-recovery.sh"|"test-setup-module.sh")
                    # Already run above
                    ;;
                *)
                    local test_name=$(echo "$basename_file" | sed 's/test-//g' | sed 's/.sh//g')
                    run_test_suite "$test_file" "$test_name" "Additional module tests"
                    ;;
            esac
        fi
    done
    
    # Run coverage analysis
    if [[ "$run_coverage" == "true" ]]; then
        echo
        analyze_test_coverage
    fi
    
    # Run performance benchmarks
    if [[ "$run_benchmarks" == "true" ]]; then
        echo
        run_performance_benchmarks
    fi
    
    # Show final summary
    show_final_summary
}

show_final_summary() {
    local end_time=$(date +%s)
    local total_duration=$((end_time - TEST_START_TIME))
    
    echo
    echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║                    📊 FINAL TEST SUMMARY                    ║${NC}"
    echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    echo -e "${BOLD}📊 Test Results:${NC}"
    echo "   Total Tests:     $TOTAL_TESTS"
    echo -e "   ${GREEN}✅ Passed:        $TOTAL_PASSED${NC}"
    echo -e "   ${RED}❌ Failed:        $TOTAL_FAILED${NC}"
    echo -e "   ${YELLOW}⏭️  Skipped:       $TOTAL_SKIPPED${NC}"
    echo
    
    echo -e "${BOLD}⏱️  Execution Time:${NC} ${total_duration}s"
    echo -e "${BOLD}📁 Results Directory:${NC} $TEST_RESULTS_DIR"
    echo
    
    if [[ $TOTAL_FAILED -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}🎉 ALL TESTS PASSED!${NC}"
        echo -e "${GREEN}✅ Week 3 Testing Infrastructure: SUCCESSFUL${NC}"
    else
        echo -e "${RED}${BOLD}❌ SOME TESTS FAILED${NC}"
        echo -e "${RED}Failed test suites: ${FAILED_TESTS[*]}${NC}"
        echo -e "${YELLOW}💡 Check individual test logs in: $TEST_RESULTS_DIR${NC}"
    fi
    
    echo
    echo -e "${CYAN}📋 Next Steps:${NC}"
    echo "   • Review test results in $TEST_RESULTS_DIR"
    echo "   • Check coverage report in $COVERAGE_DIR"
    echo "   • Address any failed tests"
    echo "   • Continue with Week 3 quality improvements"
    echo
}

# =============================================================================
# COMMAND LINE INTERFACE
# =============================================================================

show_help() {
    echo "Milou CLI Test Runner - Week 3 Testing Infrastructure"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --no-coverage     Skip coverage analysis"
    echo "  --no-benchmarks   Skip performance benchmarks"
    echo "  --help, -h        Show this help"
    echo
    echo "Examples:"
    echo "  $0                    # Run all tests with coverage and benchmarks"
    echo "  $0 --no-coverage     # Run tests without coverage analysis"
    echo "  $0 --no-benchmarks   # Run tests without performance benchmarks"
}

main() {
    local run_coverage="true"
    local run_benchmarks="true"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --no-coverage)
                run_coverage="false"
                shift
                ;;
            --no-benchmarks)
                run_benchmarks="false"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Change to project root
    cd "$PROJECT_ROOT"
    
    # Run all tests
    run_all_tests "$run_coverage" "$run_benchmarks"
    
    # Exit with appropriate code
    if [[ $TOTAL_FAILED -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 