# Milou CLI Refactoring Roadmap - Step-by-Step Implementation

## Overview

This roadmap provides a detailed, step-by-step approach to refactor the Milou CLI codebase following Bash best practices. Each phase is designed to preserve functionality while systematically eliminating code duplication and improving maintainability.

## Phase 1: Critical Deduplication (Week 1)

### Day 1-2: Consolidate Validation Functions

#### Step 1.1: Create Unified Validation Module
```bash
# Target: lib/core/validation.sh becomes the single source of truth

# New structure:
lib/core/validation.sh
├── milou_validate_github_token()     # Main implementation
├── milou_validate_docker_access()    # Consolidated Docker checks
├── milou_validate_ssl_certificates() # Unified SSL validation
├── milou_validate_system_requirements() # System checks
└── Backward compatibility aliases
```

**Implementation Steps:**

1. **Audit existing validation functions:**
```bash
# Find all validation functions
grep -r "validate.*(" lib/ commands/ | grep -E "(github|docker|ssl)" > validation_audit.txt

# Analyze differences between implementations
for func in validate_github_token milou_validate_github_token; do
    echo "=== $func ==="
    grep -A 10 "$func()" lib/*/**.sh
done
```

2. **Create master validation function:**
```bash
# lib/core/validation.sh - Enhanced version
milou_validate_github_token() {
    local token="$1"
    local test_auth="${2:-true}"
    local quiet="${3:-false}"
    
    # Input validation
    [[ -z "$token" ]] && {
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "GitHub token is required"
        return 1
    }
    
    # Format validation
    if [[ ! "$token" =~ ^gh[pousr]_[A-Za-z0-9_]{36,251}$ ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Invalid GitHub token format"
        return 1
    fi
    
    # Authentication test (if requested)
    if [[ "$test_auth" == "true" ]]; then
        milou_test_github_authentication "$token" "$quiet"
        return $?
    fi
    
    return 0
}
```

3. **Remove duplicate implementations:**
```bash
# Remove from lib/docker/registry/auth.sh
sed -i '/^validate_github_token()/,/^}/d' lib/docker/registry/auth.sh

# Update callers to use the unified function
find lib/ commands/ -name "*.sh" -exec sed -i 's/validate_github_token(/milou_validate_github_token(/g' {} \;
```

#### Step 1.2: Consolidate Docker Validation

**Target Function Structure:**
```bash
milou_validate_docker_access() {
    local check_daemon="${1:-true}"
    local check_permissions="${2:-true}"
    local check_compose="${3:-true}"
    local quiet="${4:-false}"
    
    local errors=0
    
    # Check Docker installation
    if ! command -v docker >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Docker is not installed"
        ((errors++))
    fi
    
    # Check daemon access
    if [[ "$check_daemon" == "true" ]]; then
        if ! docker info >/dev/null 2>&1; then
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "Cannot access Docker daemon"
            ((errors++))
        fi
    fi
    
    # Check user permissions
    if [[ "$check_permissions" == "true" ]]; then
        if [[ $EUID -ne 0 ]] && ! groups | grep -q docker; then
            [[ "$quiet" != "true" ]] && milou_log "WARN" "User not in docker group"
            ((errors++))
        fi
    fi
    
    # Check Docker Compose
    if [[ "$check_compose" == "true" ]]; then
        if ! docker compose version >/dev/null 2>&1; then
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "Docker Compose not available"
            ((errors++))
        fi
    fi
    
    return $errors
}
```

**Removal Steps:**
```bash
# Remove duplicates from multiple files
files_to_clean=(
    "lib/docker/core.sh"
    "lib/docker/registry/access.sh" 
    "lib/system/prerequisites.sh"
)

for file in "${files_to_clean[@]}"; do
    # Remove Docker check functions
    sed -i '/^check_docker_access()/,/^}/d' "$file"
    sed -i '/^validate_docker_installation()/,/^}/d' "$file"
    sed -i '/^check_docker_resources()/,/^}/d' "$file"
done
```

### Day 3-4: Standardize Logging System

#### Step 1.3: Implement Unified Logging

**Target: Single logging system with proper fallbacks**

1. **Enhanced core logging (lib/core/logging.sh):**
```bash
# Add module detection and safe fallbacks
milou_log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local caller="${FUNCNAME[2]:-main}"
    
    # Validate log level
    case "$level" in
        ERROR|WARN|INFO|SUCCESS|DEBUG|TRACE|STEP) ;;
        *) level="INFO" ;;
    esac
    
    # Skip if quiet mode (except errors/warnings)
    if [[ "${QUIET:-false}" == "true" ]] && [[ "$level" != "ERROR" && "$level" != "WARN" ]]; then
        _safe_log_to_file "[$timestamp] [$level] [$caller] $message"
        return 0
    fi
    
    # Only show debug/trace in verbose mode
    if [[ "$level" == "DEBUG" || "$level" == "TRACE" ]]; then
        if [[ "${VERBOSE:-false}" != "true" && "${DEBUG:-false}" != "true" ]]; then
            _safe_log_to_file "[$timestamp] [$level] [$caller] $message"
            return 0
        fi
    fi
    
    # Format and output message
    local color emoji prefix
    _get_log_formatting "$level" color emoji prefix
    
    if [[ "$level" == "ERROR" || "$level" == "WARN" ]]; then
        echo -e "${color}${emoji} ${prefix}${NC} $message" >&2
    else
        echo -e "${color}${emoji} ${prefix}${NC} $message"
    fi
    
    # Log to file if configured
    _safe_log_to_file "[$timestamp] [$level] [$caller] $message"
}

_get_log_formatting() {
    local level="$1"
    local -n color_ref="$2"
    local -n emoji_ref="$3" 
    local -n prefix_ref="$4"
    
    case "$level" in
        ERROR)   color_ref="$RED";    emoji_ref="❌"; prefix_ref="[ERROR]" ;;
        WARN)    color_ref="$YELLOW"; emoji_ref="⚠️";  prefix_ref="[WARN]" ;;
        INFO)    color_ref="$GREEN";  emoji_ref="ℹ️";  prefix_ref="[INFO]" ;;
        SUCCESS) color_ref="$GREEN";  emoji_ref="✅"; prefix_ref="[SUCCESS]" ;;
        DEBUG)   color_ref="$BLUE";   emoji_ref="🔍"; prefix_ref="[DEBUG]" ;;
        TRACE)   color_ref="$DIM";    emoji_ref="🔍"; prefix_ref="[TRACE]" ;;
        STEP)    color_ref="$CYAN";   emoji_ref="⚙️";  prefix_ref="[STEP]" ;;
    esac
}
```

2. **Remove duplicate log functions:**
```bash
# Create script to remove logging duplicates
cat > remove_log_duplicates.sh << 'EOF'
#!/bin/bash

# Files with duplicate logging functions
ssl_modules=(
    "lib/system/ssl/generation.sh"
    "lib/system/ssl/interactive.sh"
    "lib/system/ssl/nginx_integration.sh"
    "lib/system/ssl/validation.sh"
    "lib/system/ssl/paths.sh"
)

# Remove local milou_log definitions
for file in "${ssl_modules[@]}"; do
    if [[ -f "$file" ]]; then
        echo "Cleaning $file"
        # Remove local milou_log function (lines 22-30 typically)
        sed -i '/^milou_log() {/,/^}/d' "$file"
        
        # Add proper module header with logging dependency
        cat > temp_header << 'HEADER'
#!/bin/bash

# Ensure logging is available
if ! command -v milou_log >/dev/null 2>&1; then
    # Fallback for module testing
    milou_log() { echo "[$1] ${*:2}"; }
fi

HEADER
        
        # Prepend header to file
        cat temp_header "$file" > temp_file && mv temp_file "$file"
        rm temp_header
        
        echo "✅ Cleaned $file"
    fi
done

# Remove custom logging from other modules
sed -i '/^mlog()/,/^}/d' lib/user/environment.sh
sed -i '/^mseclog()/,/^}/d' lib/user/environment.sh

echo "✅ All logging duplicates removed"
EOF

chmod +x remove_log_duplicates.sh
./remove_log_duplicates.sh
```

### Day 5: Unify Error Handling

#### Step 1.4: Standardize Error Patterns

**Target Pattern:**
```bash
# Standard error handling pattern for all functions
milou_function_template() {
    local param1="$1"
    local param2="${2:-default}"
    local quiet="${QUIET:-false}"
    
    # Input validation
    if [[ -z "$param1" ]]; then
        milou_log "ERROR" "param1 is required"
        return 1
    fi
    
    # Function logic with error handling
    if ! some_operation; then
        milou_log "ERROR" "Operation failed: $(some_operation 2>&1)"
        return 1
    fi
    
    # Success logging
    milou_log "DEBUG" "Function completed successfully"
    return 0
}
```

**Implementation Script:**
```bash
# Create error handling standardization script
cat > standardize_errors.sh << 'EOF'
#!/bin/bash

# Find all exit calls in library functions (should be return instead)
echo "Finding exit calls in library functions..."
grep -r "exit [0-9]" lib/ | grep -v "test\|example" > exit_audit.txt

# Replace exit with return in library functions
find lib/ -name "*.sh" -exec sed -i 's/exit 1$/return 1/g' {} \;
find lib/ -name "*.sh" -exec sed -i 's/exit 0$/return 0/g' {} \;

# Standardize error messages to use milou_log
find lib/ -name "*.sh" -exec sed -i 's/echo "ERROR:/milou_log "ERROR"/g' {} \;
find lib/ -name "*.sh" -exec sed -i 's/echo "WARN:/milou_log "WARN"/g' {} \;

echo "✅ Error handling standardized"
EOF

chmod +x standardize_errors.sh
./standardize_errors.sh
```

## Phase 2: Function Decomposition (Week 2)

### Day 6-8: Break Down Monolithic Functions

#### Step 2.1: Decompose handle_setup() Function

**Current: 441 lines → Target: 6 focused functions**

```bash
# New file structure: commands/setup/
mkdir -p commands/setup/

# Split into focused modules:
commands/setup/
├── analysis.sh      # System analysis and detection
├── dependencies.sh  # Dependency installation
├── user.sh         # User management
├── configuration.sh # Configuration wizard  
├── validation.sh   # Final validation
└── services.sh     # Service startup
```

**Example decomposition:**

1. **System Analysis Module (commands/setup/analysis.sh):**
```bash
#!/bin/bash

setup_analyze_system() {
    milou_log "STEP" "System Analysis and Detection"
    
    local analysis_result
    analysis_result=$(create_system_analysis)
    
    # Set global flags based on analysis
    export IS_FRESH_SERVER
    export NEEDS_DEPS_INSTALL
    export NEEDS_USER_MANAGEMENT
    
    milou_log "INFO" "System analysis completed"
    return 0
}

create_system_analysis() {
    local fresh_indicators=0
    local fresh_reasons=()
    
    detect_fresh_server_indicators fresh_indicators fresh_reasons
    determine_setup_requirements "$fresh_indicators"
    
    echo "Analysis complete: $fresh_indicators indicators found"
}

detect_fresh_server_indicators() {
    local -n indicators_ref="$1"
    local -n reasons_ref="$2"
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        ((indicators_ref++))
        reasons_ref+=("Running as root user")
    fi
    
    # Check for milou user
    if ! milou_user_exists; then
        ((indicators_ref++))
        reasons_ref+=("No dedicated milou user")
    fi
    
    # Check for configuration
    if [[ ! -f "${ENV_FILE:-}" ]]; then
        ((indicators_ref++))
        reasons_ref+=("No existing configuration")
    fi
    
    # Additional checks...
}
```

2. **Configuration Module (commands/setup/configuration.sh):**
```bash
#!/bin/bash

setup_run_configuration_wizard() {
    local setup_mode="${1:-interactive}"
    
    milou_log "STEP" "Configuration Setup"
    
    case "$setup_mode" in
        interactive)
            run_interactive_configuration_wizard
            ;;
        non-interactive)
            run_non_interactive_configuration
            ;;
        *)
            milou_log "ERROR" "Unknown setup mode: $setup_mode"
            return 1
            ;;
    esac
}

run_interactive_configuration_wizard() {
    milou_log "INFO" "Starting interactive configuration wizard"
    
    # Collect configuration step by step
    collect_basic_configuration
    collect_domain_configuration  
    collect_ssl_configuration
    collect_admin_configuration
    
    # Validate and save
    validate_collected_configuration
    save_configuration_to_env
}

collect_basic_configuration() {
    # Domain configuration
    milou_prompt_user "Enter domain name" "${DOMAIN:-localhost}" "domain" "false" 3
    DOMAIN="$REPLY"
    
    # Email configuration
    milou_prompt_user "Enter admin email" "${ADMIN_EMAIL:-admin@localhost}" "email" "false" 3
    ADMIN_EMAIL="$REPLY"
}
```

#### Step 2.2: Extract Common Patterns

**Create reusable pattern modules:**

1. **Confirmation Pattern (lib/core/patterns/confirmation.sh):**
```bash
#!/bin/bash

milou_confirm_with_options() {
    local prompt="$1"
    local default="${2:-N}"
    local timeout="${3:-0}"
    local help_text="${4:-}"
    
    # Enhanced confirmation with help
    while true; do
        if [[ -n "$help_text" ]]; then
            echo -e "\n$help_text\n"
        fi
        
        if milou_confirm "$prompt" "$default" "$timeout"; then
            return 0
        else
            if [[ -n "$help_text" ]]; then
                if milou_confirm "Show help again?" "N"; then
                    continue
                fi
            fi
            return 1
        fi
    done
}

milou_confirm_critical_action() {
    local action="$1"
    local warning="$2"
    local confirmation_phrase="${3:-YES}"
    
    milou_log "WARN" "$warning"
    echo
    milou_log "WARN" "This action: $action"
    milou_log "WARN" "Type '$confirmation_phrase' to confirm:"
    
    read -r response
    if [[ "$response" == "$confirmation_phrase" ]]; then
        return 0
    else
        milou_log "INFO" "Action cancelled"
        return 1
    fi
}
```

2. **Retry Pattern (lib/core/patterns/retry.sh):**
```bash
#!/bin/bash

milou_retry_with_backoff() {
    local max_attempts="$1"
    local base_delay="$2"
    local command_to_retry="$3"
    shift 3
    local args=("$@")
    
    local attempt=1
    local delay="$base_delay"
    
    while [[ $attempt -le $max_attempts ]]; do
        milou_log "DEBUG" "Attempt $attempt/$max_attempts: $command_to_retry"
        
        if "$command_to_retry" "${args[@]}"; then
            milou_log "DEBUG" "Command succeeded on attempt $attempt"
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            milou_log "WARN" "Attempt $attempt failed, retrying in ${delay}s..."
            sleep "$delay"
            delay=$((delay * 2))  # Exponential backoff
        fi
        
        ((attempt++))
    done
    
    milou_log "ERROR" "Command failed after $max_attempts attempts"
    return 1
}
```

### Day 9-10: Validate and Test Phase 2

## Phase 3: Module Reorganization (Week 3)

### Day 11-13: Clear Module Boundaries

#### Step 3.1: Reorganize by Single Responsibility

**New Module Structure:**
```bash
lib/
├── core/                    # Core utilities, no external dependencies
│   ├── logging.sh          # Centralized logging
│   ├── validation.sh       # All validation functions
│   ├── utilities.sh        # Core utilities
│   ├── user-interface.sh   # UI functions
│   └── patterns/           # Reusable patterns
│       ├── confirmation.sh
│       ├── retry.sh
│       └── progress.sh
├── docker/                 # Docker operations only
│   ├── compose.sh         # Docker Compose operations
│   ├── registry.sh        # Registry operations  
│   ├── health.sh          # Health checks
│   └── management.sh      # Container management
├── system/                 # System management only
│   ├── configuration.sh   # Config management
│   ├── prerequisites.sh   # System requirements
│   ├── ssl.sh             # SSL operations
│   └── security.sh        # System security
└── user/                   # User management only
    ├── core.sh            # Core user functions
    ├── permissions.sh     # Permission management
    └── security.sh        # User security
```

**Migration Script:**
```bash
#!/bin/bash
# migrate_modules.sh

# Step 1: Move misplaced functions to correct modules
echo "Phase 3.1: Moving misplaced functions..."

# Move SSL functions from core/validation.sh to system/ssl.sh
ssl_functions=(
    "milou_validate_ssl_certificates"
    "check_ssl_expiration" 
    "validate_ssl_certificates"
)

for func in "${ssl_functions[@]}"; do
    # Extract function from core/validation.sh
    sed -n "/^$func()/,/^}/p" lib/core/validation.sh >> temp_ssl_functions.sh
    # Remove from core/validation.sh
    sed -i "/^$func()/,/^}/d" lib/core/validation.sh
done

# Append to system/ssl.sh
cat temp_ssl_functions.sh >> lib/system/ssl.sh
rm temp_ssl_functions.sh

# Update exports in core/validation.sh
sed -i '/milou_validate_ssl_certificates/d' lib/core/validation.sh
sed -i '/validate_ssl_certificates/d' lib/core/validation.sh

echo "✅ SSL functions moved to system/ssl.sh"
```

#### Step 3.2: Eliminate Circular Dependencies

**New Loading Order:**
```bash
# lib/core/module-loader.sh - Updated loading strategy
milou_load_essentials() {
    # Load in strict dependency order
    local -a essential_modules=(
        "core/logging"        # First - no dependencies
        "core/utilities"      # Second - only needs logging
        "core/validation"     # Third - needs logging + utilities  
        "core/user-interface" # Fourth - needs all above
    )
    
    # Load modules sequentially with dependency checking
    for module in "${essential_modules[@]}"; do
        if ! milou_load_module "$module"; then
            milou_log "ERROR" "Failed to load essential module: $module"
            return 1
        fi
        
        # Verify module loaded correctly
        if ! milou_verify_module_functions "$module"; then
            milou_log "ERROR" "Module $module missing required functions"
            return 1
        fi
    done
}

milou_verify_module_functions() {
    local module="$1"
    
    case "$module" in
        "core/logging")
            command -v milou_log >/dev/null 2>&1
            ;;
        "core/utilities")
            command -v milou_generate_secure_random >/dev/null 2>&1
            ;;
        "core/validation")
            command -v milou_validate_github_token >/dev/null 2>&1
            ;;
        "core/user-interface")
            command -v milou_prompt_user >/dev/null 2>&1
            ;;
        *)
            return 0  # Unknown module, assume valid
            ;;
    esac
}
```

## Phase 4: Code Quality Improvements (Week 4)

### Day 16-18: Standardize Function Signatures

#### Step 4.1: Implement Standard Function Pattern

**Template Generator Script:**
```bash
#!/bin/bash
# generate_function_template.sh

generate_milou_function() {
    local function_name="$1"
    local description="$2"
    local -a params=("${@:3}")
    
    cat << EOF
#=============================================================================
# Function: $function_name
# Purpose: $description
# Parameters:
$(for i in "${!params[@]}"; do
    echo "#   \$$(($i+1)) - ${params[$i]}"
done)
# Returns: 0 on success, 1 on error, 2 on invalid input
# Example: $function_name $(printf '"%s" ' "${params[@]}" | head -c -1)
#=============================================================================
$function_name() {
$(for i in "${!params[@]}"; do
    local param_name=$(echo "${params[$i]}" | cut -d'(' -f1)
    local param_default=$(echo "${params[$i]}" | grep -o '(.*)'  | tr -d '()' || echo "")
    if [[ -n "$param_default" ]]; then
        echo "    local $param_name=\"\${$(($i+1)):-$param_default}\""
    else
        echo "    local $param_name=\"\$$(($i+1))\""
    fi
done)
    local quiet="\${QUIET:-false}"
    
    # Input validation
$(for i in "${!params[@]}"; do
    local param_name=$(echo "${params[$i]}" | cut -d'(' -f1)
    if [[ "${params[$i]}" != *"(optional)"* ]]; then
        echo "    [[ -z \"\$$param_name\" ]] && { milou_log \"ERROR\" \"$param_name is required\"; return 2; }"
    fi
done)
    
    # Function logic here
    
    # Success
    milou_log "DEBUG" "$function_name completed successfully"
    return 0
}
EOF
}

# Example usage:
generate_milou_function "milou_validate_github_token" \
    "Validates GitHub personal access token format and authentication" \
    "token" "test_auth(optional)" "quiet(optional)"
```

#### Step 4.2: Add Comprehensive Documentation

**Documentation Generator:**
```bash
#!/bin/bash
# generate_module_docs.sh

generate_module_documentation() {
    local module_file="$1"
    local output_file="${module_file%.sh}.md"
    
    echo "# $(basename "$module_file" .sh) Module Documentation" > "$output_file"
    echo "" >> "$output_file"
    echo "Generated on: $(date)" >> "$output_file"
    echo "" >> "$output_file"
    
    # Extract functions and their documentation
    while IFS= read -r line; do
        if [[ "$line" =~ ^#.*Function: ]]; then
            # Extract function documentation block
            extract_function_docs "$module_file" "$line" >> "$output_file"
        fi
    done < "$module_file"
}

extract_function_docs() {
    local file="$1"
    local function_line="$2"
    
    # Find the function documentation block
    local in_docs=false
    local function_name=""
    
    while IFS= read -r line; do
        if [[ "$line" == "$function_line" ]]; then
            in_docs=true
            function_name=$(echo "$line" | sed 's/.*Function: //')
            echo "## $function_name"
            echo ""
            continue
        fi
        
        if [[ "$in_docs" == true ]]; then
            if [[ "$line" =~ ^#.*= ]]; then
                break
            elif [[ "$line" =~ ^# ]]; then
                echo "${line#\# }"
            fi
        fi
    done < "$file"
    
    echo ""
}

# Generate docs for all modules
find lib/ -name "*.sh" -exec bash generate_module_docs.sh {} \;
```

### Day 19-20: Final Quality Assurance

#### Step 4.3: Implement Testing Framework

**Test Framework (tests/framework.sh):**
```bash
#!/bin/bash
# Lightweight testing framework for Milou CLI

declare -g TESTS_PASSED=0
declare -g TESTS_FAILED=0
declare -g CURRENT_TEST=""

test_start() {
    local test_name="$1"
    CURRENT_TEST="$test_name"
    echo "🧪 Testing: $test_name"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Expected '$expected', got '$actual'}"
    
    if [[ "$expected" == "$actual" ]]; then
        echo "  ✅ $message"
        ((TESTS_PASSED++))
    else
        echo "  ❌ $message"
        ((TESTS_FAILED++))
    fi
}

assert_command_succeeds() {
    local command="$1"
    local message="${2:-Command should succeed: $command}"
    
    if eval "$command" >/dev/null 2>&1; then
        echo "  ✅ $message"
        ((TESTS_PASSED++))
    else
        echo "  ❌ $message"
        ((TESTS_FAILED++))
    fi
}

test_summary() {
    echo ""
    echo "Test Summary:"
    echo "  Passed: $TESTS_PASSED"
    echo "  Failed: $TESTS_FAILED"
    echo "  Total:  $((TESTS_PASSED + TESTS_FAILED))"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "🎉 All tests passed!"
        return 0
    else
        echo "💥 Some tests failed!"
        return 1
    fi
}
```

**Example Test Suite (tests/test_validation.sh):**
```bash
#!/bin/bash

source "$(dirname "$0")/framework.sh"
source "$(dirname "$0")/../lib/core/validation.sh"

# Test GitHub token validation
test_start "GitHub Token Validation"

assert_command_succeeds "milou_validate_github_token 'ghp_EXAMPLE_TOKEN_FOR_TESTING_ONLY' false"
assert_equals "1" "$?" "Invalid token should fail"

# Test Docker validation
test_start "Docker Access Validation"
assert_command_succeeds "command -v milou_validate_docker_access"

test_summary
```

## Quality Assurance Checklist

### Code Quality Standards
- [ ] All functions follow standard naming convention (`milou_*`)
- [ ] All functions have documentation headers
- [ ] No function exceeds 50 lines
- [ ] No code duplication (< 5%)
- [ ] All variables properly scoped
- [ ] Consistent error handling patterns
- [ ] All modules have single responsibility

### Bash Best Practices Applied
- [ ] Proper error handling with `set -euo pipefail`
- [ ] All variables quoted appropriately
- [ ] Array handling follows best practices
- [ ] Function return codes consistent (0=success, 1=error, 2=invalid input)
- [ ] Global variables minimized and properly exported
- [ ] Temporary files cleaned up
- [ ] Shellcheck passes on all files

### Testing Coverage
- [ ] Unit tests for all validation functions
- [ ] Integration tests for main commands
- [ ] Error path testing
- [ ] Cross-platform compatibility tests

### Documentation
- [ ] README updated with new structure
- [ ] All modules documented
- [ ] Usage examples provided
- [ ] Migration guide created

## Success Metrics

### Quantitative Goals
- **Code Reduction**: 35% reduction in total lines achieved
- **Duplication**: <5% code duplication (from ~50%)
- **Function Size**: Average function size <30 lines
- **Module Count**: Reduced from 45+ to ~25 focused modules
- **Test Coverage**: >80% function coverage

### Qualitative Improvements
- **Maintainability**: Clear module boundaries and responsibilities
- **Readability**: Consistent naming and documentation
- **Reliability**: Comprehensive error handling and validation
- **Extensibility**: Easy to add new features without duplication

This roadmap ensures systematic refactoring while preserving all existing functionality and following Bash best practices throughout the process. 