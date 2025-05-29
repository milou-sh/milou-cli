#!/bin/bash

# =============================================================================
# Milou CLI Test Framework
# Comprehensive testing utilities for unit, integration, and system tests
# =============================================================================

set -euo pipefail

# Test framework globals
if [[ -z "${TEST_FRAMEWORK_VERSION:-}" ]]; then
    readonly TEST_FRAMEWORK_VERSION="2.0.0"
fi

# Simple robust path resolution - only set if not already set
if [[ -z "${TEST_DIR:-}" ]]; then
    TEST_DIR="$(pwd)/tests"
fi

if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(pwd)"
fi

if [[ -z "${TEST_TEMP_DIR:-}" ]]; then
    TEST_TEMP_DIR="$TEST_DIR/tmp"
fi

# Test counters - ensure they're always initialized
TEST_TOTAL=${TEST_TOTAL:-0}
TEST_PASSED=${TEST_PASSED:-0}
TEST_FAILED=${TEST_FAILED:-0}
TEST_SKIPPED=${TEST_SKIPPED:-0}

# Test state
TEST_CURRENT_SUITE=""
TEST_START_TIME=""
TEST_VERBOSE=${TEST_VERBOSE:-false}

# Colors for output
if [[ -z "${RED:-}" ]]; then
    readonly RED='\033[0;31m'
fi
if [[ -z "${GREEN:-}" ]]; then
    readonly GREEN='\033[0;32m'
fi
if [[ -z "${YELLOW:-}" ]]; then
    readonly YELLOW='\033[1;33m'
fi
if [[ -z "${BLUE:-}" ]]; then
    readonly BLUE='\033[0;34m'
fi
if [[ -z "${PURPLE:-}" ]]; then
    readonly PURPLE='\033[0;35m'
fi
if [[ -z "${CYAN:-}" ]]; then
    readonly CYAN='\033[0;36m'
fi
if [[ -z "${BOLD:-}" ]]; then
    readonly BOLD='\033[1m'
fi
if [[ -z "${NC:-}" ]]; then
    readonly NC='\033[0m'
fi

# =============================================================================
# Core Test Framework Functions
# =============================================================================

# Initialize test framework
test_init() {
    local suite_name="$1"
    TEST_CURRENT_SUITE="$suite_name"
    TEST_START_TIME=$(date +%s)
    
    echo -e "${BOLD}${CYAN}=================================${NC}"
    echo -e "${BOLD}${CYAN}$suite_name${NC}"
    echo -e "${BOLD}${CYAN}=================================${NC}"
    echo
}

# Log with different levels
test_log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${BLUE}ℹ️  [$timestamp] $message${NC}"
            ;;
        "SUCCESS")
            echo -e "${GREEN}✅ [$timestamp] $message${NC}"
            ;;
        "WARN")
            echo -e "${YELLOW}⚠️  [$timestamp] $message${NC}"
            ;;
        "ERROR")
            echo -e "${RED}❌ [$timestamp] $message${NC}"
            ;;
        "DEBUG")
            if [[ "$TEST_VERBOSE" == "true" ]]; then
                echo -e "${PURPLE}🔍 [$timestamp] $message${NC}"
            fi
            ;;
        *)
            echo -e "[$timestamp] $message"
            ;;
    esac
}

# Setup test environment
test_setup() {
    test_log "INFO" "Setting up test environment..."
    
    # Create temp directory
    mkdir -p "$TEST_TEMP_DIR"
    
    # Ensure we're in project root
    cd "$PROJECT_ROOT"
    
    test_log "SUCCESS" "Test environment ready"
}

# Cleanup test environment
test_cleanup() {
    test_log "INFO" "Cleaning up test environment..."
    
    # Remove temp directory
    if [[ -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
    
    test_log "SUCCESS" "Test cleanup complete"
}

# Run individual test
test_run() {
    local test_name="$1"
    local test_function="$2"
    local test_description="$3"
    
    # Safe arithmetic that won't exit with set -e
    TEST_TOTAL=$((TEST_TOTAL + 1))
    
    echo -e "${BOLD}🧪 Test: $test_name${NC}"
    echo -e "   📄 $test_description"
    
    local start_time=$(date +%s%N)
    
    if eval "$test_function"; then
        local end_time=$(date +%s%N)
        local duration=$(( (end_time - start_time) / 1000000 ))
        
        # Safe arithmetic
        TEST_PASSED=$((TEST_PASSED + 1))
        test_log "SUCCESS" "✅ $test_name PASSED (${duration}ms)"
    else
        local end_time=$(date +%s%N)
        local duration=$(( (end_time - start_time) / 1000000 ))
        
        # Safe arithmetic
        TEST_FAILED=$((TEST_FAILED + 1))
        test_log "ERROR" "❌ $test_name FAILED (${duration}ms)"
    fi
    
    echo
}

# Show test summary
test_summary() {
    local end_time=$(date +%s)
    local total_duration=$((end_time - TEST_START_TIME))
    
    echo -e "${BOLD}${CYAN}=================================${NC}"
    echo -e "${BOLD}${CYAN}TEST SUMMARY: $TEST_CURRENT_SUITE${NC}"
    echo -e "${BOLD}${CYAN}=================================${NC}"
    echo
    echo -e "${BOLD}📊 Results:${NC}"
    echo -e "   Total Tests:  $TEST_TOTAL"
    echo -e "   ${GREEN}✅ Passed:     $TEST_PASSED${NC}"
    echo -e "   ${RED}❌ Failed:     $TEST_FAILED${NC}"
    echo -e "   ${YELLOW}⏭️  Skipped:    $TEST_SKIPPED${NC}"
    echo
    echo -e "${BOLD}⏱️  Duration:    ${total_duration}s${NC}"
    
    if [[ $TEST_FAILED -eq 0 ]]; then
        echo -e "${BOLD}${GREEN}🎉 ALL TESTS PASSED!${NC}"
        return 0
    else
        echo -e "${BOLD}${RED}💥 SOME TESTS FAILED!${NC}"
        return 1
    fi
}

# =============================================================================
# Test Assertion Functions
# =============================================================================

# Assert that a condition is true
assert_true() {
    local condition="$1"
    local message="${2:-Condition should be true}"
    
    if eval "$condition"; then
        test_log "DEBUG" "✅ $message"
        return 0
    else
        test_log "ERROR" "❌ $message"
        return 1
    fi
}

# Assert that a condition is false
assert_false() {
    local condition="$1"
    local message="${2:-Condition should be false}"
    
    if ! eval "$condition"; then
        test_log "DEBUG" "✅ $message"
        return 0
    else
        test_log "ERROR" "❌ $message"
        return 1
    fi
}

# Assert that two values are equal
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should be equal}"
    
    if [[ "$expected" == "$actual" ]]; then
        test_log "DEBUG" "✅ $message (expected: '$expected', actual: '$actual')"
        return 0
    else
        test_log "ERROR" "❌ $message (expected: '$expected', actual: '$actual')"
        return 1
    fi
}

# Assert that two values are not equal
assert_not_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should not be equal}"
    
    if [[ "$expected" != "$actual" ]]; then
        test_log "DEBUG" "✅ $message"
        return 0
    else
        test_log "ERROR" "❌ $message (both values: '$expected')"
        return 1
    fi
}

# Assert that a string contains a substring
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should contain substring}"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        test_log "DEBUG" "✅ $message"
        return 0
    else
        test_log "ERROR" "❌ $message (looking for: '$needle' in: '$haystack')"
        return 1
    fi
}

# Assert that a string does not contain a substring
assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should not contain substring}"
    
    if [[ "$haystack" != *"$needle"* ]]; then
        test_log "DEBUG" "✅ $message"
        return 0
    else
        test_log "ERROR" "❌ $message (unexpectedly found: '$needle' in: '$haystack')"
        return 1
    fi
}

# Assert that a file exists
assert_file_exists() {
    local file_path="$1"
    local message="${2:-File should exist}"
    
    if [[ -f "$file_path" ]]; then
        test_log "DEBUG" "✅ $message ($file_path)"
        return 0
    else
        test_log "ERROR" "❌ $message ($file_path)"
        return 1
    fi
}

# Assert that a directory exists
assert_directory_exists() {
    local dir_path="$1"
    local message="${2:-Directory should exist}"
    
    if [[ -d "$dir_path" ]]; then
        test_log "DEBUG" "✅ $message ($dir_path)"
        return 0
    else
        test_log "ERROR" "❌ $message ($dir_path)"
        return 1
    fi
}

# Assert that a function exists
assert_function_exists() {
    local function_name="$1"
    local message="${2:-Function should exist}"
    
    if declare -f "$function_name" >/dev/null 2>&1; then
        test_log "DEBUG" "✅ $message ($function_name)"
        return 0
    else
        test_log "ERROR" "❌ $message ($function_name)"
        return 1
    fi
}

# Assert that a string is not empty
assert_not_empty() {
    local value="$1"
    local message="${2:-Value should not be empty}"
    
    if [[ -n "$value" ]]; then
        test_log "DEBUG" "✅ $message"
        return 0
    else
        test_log "ERROR" "❌ $message (value is empty)"
        return 1
    fi
}

# Assert that a string is empty
assert_empty() {
    local value="$1"
    local message="${2:-Value should be empty}"
    
    if [[ -z "$value" ]]; then
        test_log "DEBUG" "✅ $message"
        return 0
    else
        test_log "ERROR" "❌ $message (value: '$value')"
        return 1
    fi
}

# =============================================================================
# Test Utility Functions
# =============================================================================

# Load a module safely for testing
test_load_module() {
    local module_path="$1"
    local full_path="$PROJECT_ROOT/$module_path"
    
    if [[ -f "$full_path" ]]; then
        if source "$full_path" 2>/dev/null; then
            test_log "DEBUG" "Module loaded successfully: $module_path"
            return 0
        else
            test_log "ERROR" "Failed to load module: $module_path"
            return 1
        fi
    else
        test_log "ERROR" "Module not found: $full_path"
        return 1
    fi
}

# Create a temporary file for testing
test_create_temp_file() {
    local content="$1"
    local temp_file="$TEST_TEMP_DIR/test_file_$$_$RANDOM"
    
    mkdir -p "$TEST_TEMP_DIR"
    echo "$content" > "$temp_file"
    echo "$temp_file"
}

# Mock a command for testing
test_mock_command() {
    local command_name="$1"
    local mock_output="$2"
    local mock_exit_code="${3:-0}"
    
    local mock_script="$TEST_TEMP_DIR/mock_$command_name"
    
    cat > "$mock_script" << EOF
#!/bin/bash
echo "$mock_output"
exit $mock_exit_code
EOF
    
    chmod +x "$mock_script"
    export PATH="$TEST_TEMP_DIR:$PATH"
}

# Restore original PATH (remove mocks)
test_restore_path() {
    export PATH=$(echo "$PATH" | sed "s|$TEST_TEMP_DIR:||g")
}

# =============================================================================
# Test Data Generators
# =============================================================================

# Generate random test data
test_generate_random_string() {
    local length="${1:-10}"
    head /dev/urandom | tr -dc A-Za-z0-9 | head -c"$length"
}

# Generate test environment variables
test_generate_env_file() {
    local env_file="$TEST_TEMP_DIR/.env.test"
    
    cat > "$env_file" << EOF
# Test environment file
POSTGRES_USER=test_user_$(test_generate_random_string 8)
POSTGRES_PASSWORD=test_pass_$(test_generate_random_string 16)
POSTGRES_DB=test_db
REDIS_PASSWORD=test_redis_$(test_generate_random_string 12)
DOMAIN=test.local
EOF
    
    echo "$env_file"
}

# =============================================================================
# Test Reporting Functions
# =============================================================================

# Generate JUnit XML report (for CI integration)
test_generate_junit_report() {
    local report_file="$TEST_DIR/junit-results.xml"
    
    cat > "$report_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="$TEST_CURRENT_SUITE" tests="$TEST_TOTAL" failures="$TEST_FAILED" errors="0" skipped="$TEST_SKIPPED" time="$(($(date +%s) - TEST_START_TIME))">
EOF
    
    # Note: Individual test cases would be added here in a real implementation
    echo "</testsuite>" >> "$report_file"
    
    test_log "INFO" "JUnit report generated: $report_file"
}

# =============================================================================
# Framework Initialization
# =============================================================================

# Ensure framework is properly initialized
if [[ -z "${TEST_FRAMEWORK_LOADED:-}" ]]; then
    export TEST_FRAMEWORK_LOADED="true"
    test_log "DEBUG" "Test framework v$TEST_FRAMEWORK_VERSION loaded"
fi 