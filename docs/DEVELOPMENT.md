# Milou CLI Development Guide

**Version 3.1.0** - Complete Modular Architecture

This guide provides comprehensive information for developers contributing to the Milou CLI project.

---

## 🏗️ **Architecture Overview**

### **Design Philosophy**

The Milou CLI follows a **modular architecture** inspired by enterprise CLI tools like PlexTrac Manager. Key principles:

- **Single Responsibility**: Each module has one clear purpose
- **Clean Dependencies**: Explicit dependency management
- **Professional Quality**: Enterprise-grade code standards
- **Maintainability**: Easy to understand and modify
- **Testability**: Comprehensive test coverage

### **Directory Structure**

```
milou-cli/
├── src/                    # All source code (PlexTrac pattern)
│   ├── milou              # Main CLI entry point
│   ├── _core.sh           # Core utilities & logging
│   ├── _validation.sh     # All validation functions
│   ├── _docker.sh         # Docker operations
│   ├── _ssl.sh            # SSL management
│   ├── _config.sh         # Configuration management
│   ├── _setup.sh          # Setup operations
│   ├── _backup.sh         # Backup operations
│   ├── _user.sh           # User management
│   ├── _update.sh         # Update operations
│   └── _admin.sh          # Admin operations
├── tests/                 # Test suite
│   ├── unit/             # Unit tests for each module
│   ├── integration/      # Integration tests
│   └── helpers/          # Test utilities
├── docs/                 # Documentation
│   ├── API.md           # API documentation
│   ├── DEVELOPMENT.md   # This file
│   └── TROUBLESHOOTING.md
├── scripts/              # Development scripts
│   └── dev/             # Development utilities
├── static/              # Static files & templates
├── ssl/                 # SSL certificates
├── backups/             # System backups
└── milou.sh            # Main wrapper script
```

---

## 🔧 **Development Setup**

### **Prerequisites**

- **Bash 4.0+**: Modern bash features required
- **Docker 20.10+**: For container operations
- **Docker Compose 2.0+**: For service orchestration
- **Git**: Version control
- **Text Editor**: VS Code, vim, etc.

### **Getting Started**

```bash
# Clone repository
git clone <repository>
cd milou-cli

# Make scripts executable
chmod +x milou.sh
chmod +x scripts/dev/*.sh
chmod +x tests/unit/*.sh

# Run development setup
./scripts/dev/test-setup.sh

# Verify installation
./milou.sh --help
```

### **Development Environment**

```bash
# Enable debug mode
export MILOU_DEBUG=1

# Set development paths
export MILOU_DEV_MODE=1

# Run in development mode
./milou.sh setup --dev
```

---

## 📝 **Coding Standards**

### **Shell Script Standards**

#### **File Headers**
```bash
#!/usr/bin/env bash
#
# Milou CLI - [Module Name]
# [Brief description of module purpose]
#
# This module provides [functionality description]
#

set -euo pipefail  # Strict error handling
```

#### **Function Documentation**
```bash
#
# Function: function_name
# Description: Brief description of what the function does
# Parameters:
#   $1 - parameter_name: Description of parameter
#   $2 - optional_param: Optional parameter description
# Returns:
#   0 - Success
#   1 - Error condition
# Example:
#   function_name "value1" "value2"
#
function_name() {
    local param1="$1"
    local param2="${2:-default_value}"
    
    # Function implementation
}
```

#### **Variable Naming**
```bash
# Global constants (readonly)
readonly MILOU_VERSION="3.1.0"
readonly DEFAULT_TIMEOUT=30

# Local variables (lowercase with underscores)
local config_file="/path/to/config"
local user_input=""

# Environment variables (uppercase)
export MILOU_CONFIG_DIR="${MILOU_CONFIG_DIR:-/etc/milou}"
```

#### **Error Handling**
```bash
# Always check return codes
if ! command_that_might_fail; then
    milou_log "ERROR" "Command failed" "context"
    return 1
fi

# Use proper error messages
if [[ ! -f "$config_file" ]]; then
    milou_log "ERROR" "Configuration file not found: $config_file"
    return 1
fi

# Validate parameters
if [[ $# -lt 1 ]]; then
    milou_log "ERROR" "Missing required parameter"
    return 1
fi
```

### **Module Structure**

#### **Standard Module Template**
```bash
#!/usr/bin/env bash
#
# Milou CLI - [Module Name] Module
# [Description]
#

set -euo pipefail

# Module metadata
readonly MODULE_NAME="[module_name]"
readonly MODULE_VERSION="3.1.0"

# Load dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_core.sh"

# Module-specific constants
readonly MODULE_CONSTANT="value"

# Private functions (prefixed with _)
_private_function() {
    # Implementation
}

# Public functions (exported)
public_function() {
    milou_log "INFO" "Starting public function" "$MODULE_NAME"
    
    # Implementation
    
    milou_log "SUCCESS" "Function completed" "$MODULE_NAME"
}

# Export public functions
export -f public_function

milou_log "DEBUG" "Loaded $MODULE_NAME module" "$MODULE_NAME"
```

---

## 🧪 **Testing Framework**

### **Test Structure**

```bash
#!/usr/bin/env bash
#
# Unit tests for [Module Name]
#

set -euo pipefail

# Test setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load test framework
source "$PROJECT_ROOT/tests/helpers/test-framework.sh"

# Load module under test
source "$PROJECT_ROOT/src/_module.sh"

# Test functions
test_function_basic() {
    local result
    
    # Setup
    setup_test_environment
    
    # Execute
    result=$(function_to_test "input")
    
    # Assert
    assert_equals "expected" "$result"
    assert_not_empty "$result"
    
    # Cleanup
    cleanup_test_environment
}

# Run tests
run_test "test_function_basic"
show_test_results
```

### **Test Utilities**

#### **Assertions**
```bash
# Basic assertions
assert_equals "expected" "$actual"
assert_not_equals "unexpected" "$actual"
assert_empty "$variable"
assert_not_empty "$variable"
assert_true "$condition"
assert_false "$condition"

# File assertions
assert_file_exists "/path/to/file"
assert_file_not_exists "/path/to/file"
assert_directory_exists "/path/to/dir"

# Command assertions
assert_command_succeeds "command arg1 arg2"
assert_command_fails "command arg1 arg2"
```

#### **Test Environment**
```bash
# Setup test environment
setup_test_environment() {
    export MILOU_TEST_MODE=1
    export MILOU_CONFIG_DIR="$TEST_TMP_DIR/config"
    mkdir -p "$MILOU_CONFIG_DIR"
}

# Cleanup test environment
cleanup_test_environment() {
    rm -rf "$TEST_TMP_DIR"
    unset MILOU_TEST_MODE
}
```

### **Running Tests**

```bash
# Run all tests
./test-refactoring-success.sh

# Run specific module tests
./tests/unit/test-core.sh
./tests/unit/test-validation.sh

# Run with verbose output
MILOU_DEBUG=1 ./tests/unit/test-core.sh

# Run integration tests
./tests/integration/test-setup.sh
```

---

## 🔄 **Module Development**

### **Creating a New Module**

1. **Create module file**:
```bash
cp src/_core.sh src/_new_module.sh
```

2. **Update module metadata**:
```bash
# Edit module header
readonly MODULE_NAME="new_module"
```

3. **Implement functions**:
```bash
new_module_function() {
    milou_log "INFO" "Starting new function" "$MODULE_NAME"
    # Implementation
}

export -f new_module_function
```

4. **Create tests**:
```bash
cp tests/unit/test-core.sh tests/unit/test-new-module.sh
# Update test functions
```

5. **Update dependencies**:
```bash
# Add to other modules that need it
source "${SCRIPT_DIR}/_new_module.sh"
```

### **Module Dependencies**

#### **Dependency Loading**
```bash
# Always load core first
source "${SCRIPT_DIR}/_core.sh"

# Load other dependencies
if [[ ! -f "${SCRIPT_DIR}/_validation.sh" ]]; then
    milou_log "ERROR" "Validation module not found"
    exit 1
fi
source "${SCRIPT_DIR}/_validation.sh"
```

#### **Circular Dependency Prevention**
```bash
# Use guard variables
if [[ -n "${MODULE_LOADED:-}" ]]; then
    return 0
fi
readonly MODULE_LOADED=1
```

### **Function Design**

#### **Public vs Private Functions**
```bash
# Public functions (exported)
module_public_function() {
    # Available to other modules
}
export -f module_public_function

# Private functions (not exported)
_module_private_function() {
    # Internal use only
}
```

#### **Parameter Validation**
```bash
function_with_params() {
    # Validate parameter count
    if [[ $# -lt 2 ]]; then
        milou_log "ERROR" "Usage: function_with_params <param1> <param2>"
        return 1
    fi
    
    local param1="$1"
    local param2="$2"
    local optional_param="${3:-default}"
    
    # Validate parameter values
    if [[ -z "$param1" ]]; then
        milou_log "ERROR" "Parameter 1 cannot be empty"
        return 1
    fi
}
```

---

## 🐛 **Debugging**

### **Debug Logging**

```bash
# Enable debug mode
export MILOU_DEBUG=1

# Use debug logging
milou_log "DEBUG" "Debug information" "context"

# Trace function calls
set -x  # Enable trace mode
function_call
set +x  # Disable trace mode
```

### **Common Issues**

#### **Module Loading Failures**
```bash
# Check module exists
if [[ ! -f "src/_module.sh" ]]; then
    echo "Module not found"
    exit 1
fi

# Check syntax
bash -n "src/_module.sh"

# Load with error checking
if ! source "src/_module.sh"; then
    echo "Failed to load module"
    exit 1
fi
```

#### **Function Not Found**
```bash
# Check if function is exported
if declare -f function_name >/dev/null; then
    echo "Function available"
else
    echo "Function not found"
fi

# List all exported functions
declare -F | grep -E "^declare -f [^_]"
```

#### **Variable Issues**
```bash
# Check variable is set
if [[ -z "${VARIABLE:-}" ]]; then
    echo "Variable not set"
fi

# Debug variable values
milou_log "DEBUG" "Variable value: ${VARIABLE:-unset}"
```

---

## 📊 **Performance Considerations**

### **Module Loading Optimization**

```bash
# Lazy loading
load_heavy_module() {
    if [[ -z "${HEAVY_MODULE_LOADED:-}" ]]; then
        source "${SCRIPT_DIR}/_heavy_module.sh"
        readonly HEAVY_MODULE_LOADED=1
    fi
}

# Conditional loading
if [[ "$OPERATION" == "docker" ]]; then
    source "${SCRIPT_DIR}/_docker.sh"
fi
```

### **Function Optimization**

```bash
# Cache expensive operations
get_system_info() {
    if [[ -z "${SYSTEM_INFO_CACHE:-}" ]]; then
        SYSTEM_INFO_CACHE=$(expensive_system_call)
        readonly SYSTEM_INFO_CACHE
    fi
    echo "$SYSTEM_INFO_CACHE"
}

# Avoid subshells when possible
# Instead of: result=$(command)
# Use: command > tmpfile; result=$(cat tmpfile)
```

---

## 🔒 **Security Considerations**

### **Input Validation**

```bash
validate_input() {
    local input="$1"
    
    # Check for dangerous characters
    if [[ "$input" =~ [;&|`$] ]]; then
        milou_log "ERROR" "Invalid characters in input"
        return 1
    fi
    
    # Validate length
    if [[ ${#input} -gt 255 ]]; then
        milou_log "ERROR" "Input too long"
        return 1
    fi
}
```

### **File Operations**

```bash
# Safe file operations
safe_write_file() {
    local file="$1"
    local content="$2"
    
    # Create with secure permissions
    umask 077
    echo "$content" > "$file"
    chmod 600 "$file"
}

# Validate paths
validate_path() {
    local path="$1"
    
    # Prevent directory traversal
    if [[ "$path" =~ \.\. ]]; then
        milou_log "ERROR" "Invalid path: $path"
        return 1
    fi
}
```

### **Credential Handling**

```bash
# Never log credentials
handle_password() {
    local password="$1"
    
    # Don't log the actual password
    milou_log "INFO" "Processing password" "auth"
    
    # Use secure storage
    echo "$password" | secure_store
    
    # Clear from memory
    unset password
}
```

---

## 📚 **Documentation Standards**

### **Function Documentation**

```bash
#
# Function: setup_ssl_certificates
# Description: Generate and configure SSL certificates for the application
# Parameters:
#   $1 - domain: Primary domain name (required)
#   $2 - mode: Certificate mode (self-signed|letsencrypt|existing) (optional, default: self-signed)
#   $3 - email: Email for Let's Encrypt (required if mode=letsencrypt)
# Returns:
#   0 - Certificates successfully configured
#   1 - Invalid parameters
#   2 - Certificate generation failed
#   3 - Certificate installation failed
# Example:
#   setup_ssl_certificates "example.com" "letsencrypt" "admin@example.com"
#   setup_ssl_certificates "localhost" "self-signed"
# Dependencies:
#   - _core.sh (logging)
#   - _validation.sh (domain validation)
# Side Effects:
#   - Creates SSL certificates in ssl/ directory
#   - Updates nginx configuration
#   - Restarts nginx service
#
setup_ssl_certificates() {
    # Implementation
}
```

### **Module Documentation**

```bash
#!/usr/bin/env bash
#
# Milou CLI - SSL Management Module
# 
# This module provides comprehensive SSL certificate management functionality
# including generation, validation, and configuration of SSL certificates for
# the Milou application stack.
#
# Features:
#   - Self-signed certificate generation
#   - Let's Encrypt certificate automation
#   - Existing certificate import
#   - Certificate validation and monitoring
#   - Automatic renewal scheduling
#
# Dependencies:
#   - _core.sh: Logging and utility functions
#   - _validation.sh: Domain and certificate validation
#   - _docker.sh: Nginx service management
#
# Configuration:
#   - SSL_DIR: Directory for SSL certificates (default: ./ssl)
#   - SSL_MODE: Default SSL mode (default: self-signed)
#   - SSL_KEY_SIZE: RSA key size (default: 2048)
#
# Author: Milou Development Team
# Version: 3.1.0
#
```

---

## 🚀 **Release Process**

### **Version Management**

```bash
# Update version in all files
./scripts/dev/update-version.sh "3.2.0"

# Tag release
git tag -a "v3.2.0" -m "Release version 3.2.0"
git push origin "v3.2.0"
```

### **Testing Before Release**

```bash
# Run full test suite
./test-refactoring-success.sh

# Run integration tests
./tests/integration/test-full-setup.sh

# Test on clean system
docker run -it ubuntu:20.04 bash
# Install and test Milou CLI
```

### **Documentation Updates**

```bash
# Update API documentation
./scripts/dev/generate-api-docs.sh

# Update changelog
echo "## Version 3.2.0" >> CHANGELOG.md
echo "- Feature additions" >> CHANGELOG.md
echo "- Bug fixes" >> CHANGELOG.md
```

---

## 🤝 **Contributing Guidelines**

### **Pull Request Process**

1. **Fork and branch**:
```bash
git checkout -b feature/new-feature
```

2. **Implement changes**:
   - Follow coding standards
   - Add tests
   - Update documentation

3. **Test thoroughly**:
```bash
./test-refactoring-success.sh
./tests/unit/test-new-feature.sh
```

4. **Submit pull request**:
   - Clear description
   - Reference issues
   - Include test results

### **Code Review Checklist**

- [ ] Follows coding standards
- [ ] Includes comprehensive tests
- [ ] Documentation updated
- [ ] No security vulnerabilities
- [ ] Performance considerations addressed
- [ ] Backwards compatibility maintained

---

## 📞 **Getting Help**

### **Development Support**

- **Documentation**: Check `docs/` directory
- **Examples**: See `examples/` directory
- **Tests**: Review `tests/` for usage patterns
- **Issues**: Create GitHub issue with details

### **Debugging Resources**

```bash
# Enable verbose debugging
export MILOU_DEBUG=1
export BASH_XTRACEFD=2

# Run with trace
bash -x ./milou.sh command

# Check logs
tail -f /var/log/milou.log
```

---

This development guide provides comprehensive information for contributing to the Milou CLI project. For specific API details, see `docs/API.md`. For troubleshooting, see `docs/TROUBLESHOOTING.md`. 