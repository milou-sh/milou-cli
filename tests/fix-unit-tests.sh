#!/bin/bash

# =============================================================================
# Unit Test Fixer - Convert all unit tests to self-contained format
# Fixes the test framework variable initialization issues
# =============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly UNIT_TEST_DIR="$SCRIPT_DIR/unit"

# List of unit test files to fix
TEST_FILES=(
    "test-validation-module.sh"
    "test-docker-module.sh" 
    "test-ssl-module.sh"
    "test-config-module.sh"
    "test-setup-module.sh"
    "test-admin-module.sh"
    "test-user-module.sh"
    "test-backup-core.sh"
    "test-self-update.sh"
)

echo "🔧 Fixing unit tests to use self-contained test framework..."

for test_file in "${TEST_FILES[@]}"; do
    test_path="$UNIT_TEST_DIR/$test_file"
    
    if [[ -f "$test_path" ]]; then
        echo "📝 Fixing $test_file..."
        
        # Create backup
        cp "$test_path" "$test_path.backup"
        
        # Fix the test by replacing the problematic test framework loading
        sed -i '
            # Remove the test framework source line
            /source.*test-framework\.sh/d
            
            # Add self-contained framework after the project root definition
            /readonly PROJECT_ROOT=/a\
\
# Simple test framework - self-contained\
TEST_TOTAL=0\
TEST_PASSED=0\
TEST_FAILED=0\
\
# Colors for output\
readonly RED='"'"'\\033[0;31m'"'"'\
readonly GREEN='"'"'\\033[0;32m'"'"'\
readonly YELLOW='"'"'\\033[1;33m'"'"'\
readonly BLUE='"'"'\\033[0;34m'"'"'\
readonly CYAN='"'"'\\033[0;36m'"'"'\
readonly BOLD='"'"'\\033[1m'"'"'\
readonly NC='"'"'\\033[0m'"'"'\
\
# Simple logging\
test_log() {\
    local level="$1"\
    local message="$2"\
    local timestamp=$(date '"'"'+%H:%M:%S'"'"')\
    \
    case "$level" in\
        "INFO")\
            echo -e "${BLUE}ℹ️  [$timestamp] $message${NC}"\
            ;;\
        "SUCCESS")\
            echo -e "${GREEN}✅ [$timestamp] $message${NC}"\
            ;;\
        "ERROR")\
            echo -e "${RED}❌ [$timestamp] $message${NC}"\
            ;;\
    esac\
}\
\
# Simple assertions\
assert_not_empty() {\
    local value="$1"\
    local message="${2:-Value should not be empty}"\
    \
    if [[ -n "$value" ]]; then\
        return 0\
    else\
        test_log "ERROR" "$message (value is empty)"\
        return 1\
    fi\
}\
\
assert_contains() {\
    local haystack="$1"\
    local needle="$2"\
    local message="${3:-String should contain substring}"\
    \
    if [[ "$haystack" == *"$needle"* ]]; then\
        return 0\
    else\
        test_log "ERROR" "$message (looking for: '"'"'$needle'"'"' in: '"'"'$haystack'"'"')"\
        return 1\
    fi\
}\
\
assert_function_exists() {\
    local function_name="$1"\
    local message="${2:-Function should exist}"\
    \
    if declare -f "$function_name" >/dev/null 2>&1; then\
        return 0\
    else\
        test_log "ERROR" "$message ($function_name)"\
        return 1\
    fi\
}\
\
# Test runner\
run_test() {\
    local test_name="$1"\
    local test_function="$2"\
    local test_description="$3"\
    \
    # Safe arithmetic initialization\
    TEST_TOTAL=$((${TEST_TOTAL:-0} + 1))\
    \
    echo -e "${BOLD}🧪 Test: $test_name${NC}"\
    echo -e "   📄 $test_description"\
    \
    if eval "$test_function"; then\
        TEST_PASSED=$((${TEST_PASSED:-0} + 1))\
        test_log "SUCCESS" "✅ $test_name PASSED"\
    else\
        TEST_FAILED=$((${TEST_FAILED:-0} + 1))\
        test_log "ERROR" "❌ $test_name FAILED"\
    fi\
    \
    echo\
}

        ' "$test_path"
        
        # Fix the test runner calls
        sed -i '
            s/test_run(/run_test(/g
            s/test_init.*//g
            s/test_setup//g
            s/test_cleanup//g
            s/test_summary/# Show results\
    echo -e "${BOLD}${CYAN}==================================${NC}"\
    echo -e "${BOLD}${CYAN}TEST SUMMARY${NC}"\
    echo -e "${BOLD}${CYAN}==================================${NC}"\
    echo\
    echo -e "${BOLD}📊 Results:${NC}"\
    echo -e "   Total Tests:  $TEST_TOTAL"\
    echo -e "   ${GREEN}✅ Passed:     $TEST_PASSED${NC}"\
    echo -e "   ${RED}❌ Failed:     $TEST_FAILED${NC}"\
    echo\
    \
    if [[ $TEST_FAILED -eq 0 ]]; then\
        echo -e "${BOLD}${GREEN}🎉 ALL TESTS PASSED!${NC}"\
        return 0\
    else\
        echo -e "${BOLD}${RED}💥 SOME TESTS FAILED!${NC}"\
        return 1\
    fi/g
        ' "$test_path"
        
        echo "✅ Fixed $test_file"
    else
        echo "❌ Test file not found: $test_file"
    fi
done

echo "✨ All unit tests have been fixed!"
echo "💡 Original files backed up with .backup extension" 