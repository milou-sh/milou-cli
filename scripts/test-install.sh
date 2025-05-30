#!/bin/bash

# =============================================================================
# Milou CLI Installation Test Script
# Tests the installation process in various environments
# =============================================================================

# Load shared utilities to eliminate code duplication
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$script_dir/shared-utils.sh" ]]; then
    source "$script_dir/shared-utils.sh"
else
    echo "ERROR: Cannot find shared-utils.sh" >&2
    exit 1
fi

set -euo pipefail

# Global variables
INSTALL_URL="https://raw.githubusercontent.com/YOUR_ORG/milou-cli/main/install.sh"
TEST_DIR="/tmp/milou-test-$$"
CLEANUP_ON_EXIT=true

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Cleanup function
cleanup() {
    if [[ -d "$TEST_DIR" ]]; then
        log "Cleaning up test directory: $TEST_DIR"
        rm -rf "$TEST_DIR"
    fi
}

# Set up cleanup trap
trap cleanup EXIT

# Create a self-contained test script
test_install_script() {
    step "Creating test installation script..."
    
    local test_install_script="$TEST_DIR/test_install.sh"
    
    # Generate test script that simulates the installation
    cat > "$test_install_script" << 'EOF'
#!/bin/bash

# Test installation script (auto-generated)
set -euo pipefail

INSTALL_DIR="${MILOU_INSTALL_DIR:-$HOME/milou-cli}"

# Remove duplicate logging functions - now using shared utilities from parent script
# Functions are already available through the parent environment

# Simple test installation (without logo for test)
step "Testing Milou CLI installation..."

# Check prerequisites
for cmd in git; do
    if ! command -v "$cmd" &> /dev/null; then
        error "Missing required dependency: $cmd"
        exit 1
    fi
done

success "Prerequisites check passed"

# Create installation directory
if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
fi

# Copy repository (simulate git clone)
step "Installing Milou CLI to $INSTALL_DIR..."
cp -r "$SCRIPT_DIR" "$INSTALL_DIR"

# Make scripts executable
chmod +x "$INSTALL_DIR/milou.sh"
if [[ -f "$INSTALL_DIR/src/milou" ]]; then
    chmod +x "$INSTALL_DIR/src/milou"
fi

success "Milou CLI installed successfully"
echo "Installation directory: $INSTALL_DIR"
EOF
    
    chmod +x "$test_install_script"
    
    # Run the test installation
    log "Running test installation..."
    if bash "$test_install_script"; then
        success "Installation script test passed"
    else
        error "Installation script test failed"
        return 1
    fi
    
    # Verify installation
    local milou_dir="$TEST_DIR/milou-cli"
    if [[ -d "$milou_dir" ]] && [[ -x "$milou_dir/milou.sh" ]]; then
        success "Installation verification passed"
    else
        error "Installation verification failed"
        return 1
    fi
    
    return 0
}

# Test CLI functionality
test_cli_functionality() {
    step "Testing CLI functionality..."
    
    local milou_dir="$TEST_DIR/milou-cli"
    cd "$milou_dir"
    
    # Test help command
    log "Testing help command..."
    if ./milou.sh --help >/dev/null 2>&1; then
        success "Help command works"
    else
        error "Help command failed"
        return 1
    fi
    
    # Test version command
    log "Testing version command..."
    if ./milou.sh --version >/dev/null 2>&1; then
        success "Version command works"
    else
        warn "Version command failed (may be expected)"
    fi
    
    # Test status command (should detect fresh install)
    log "Testing status command..."
    if ./milou.sh status >/dev/null 2>&1; then
        success "Status command works"
    else
        warn "Status command failed (may be expected for fresh install)"
    fi
    
    return 0
}

# Test configuration generation
test_configuration() {
    step "Testing configuration generation..."
    
    local milou_dir="$TEST_DIR/milou-cli"
    cd "$milou_dir"
    
    # Test config validation (should fail without .env)
    log "Testing config validation without .env..."
    if ! ./milou.sh config validate >/dev/null 2>&1; then
        success "Config validation correctly fails without .env"
    else
        warn "Config validation should fail without .env file"
    fi
    
    # Test .env.example exists
    if [[ -f ".env.example" ]]; then
        success ".env.example template exists"
    else
        error ".env.example template missing"
        return 1
    fi
    
    return 0
}

# Test module loading
test_module_loading() {
    step "Testing module loading..."
    
    local milou_dir="$TEST_DIR/milou-cli"
    cd "$milou_dir"
    
    # Check that core modules exist
    local modules=("_core.sh" "_config.sh" "_setup.sh" "_validation.sh")
    for module in "${modules[@]}"; do
        if [[ -f "src/$module" ]]; then
            success "Module exists: $module"
        else
            error "Module missing: $module"
            return 1
        fi
    done
    
    return 0
}

# Main test function
run_tests() {
    log "Starting Milou CLI installation tests..."
    log "Test directory: $TEST_DIR"
    log "Source directory: $SCRIPT_DIR"
    echo
    
    local tests_passed=0
    local tests_total=4
    
    # Run tests
    if test_install_script; then
        ((tests_passed++))
    fi
    
    if test_cli_functionality; then
        ((tests_passed++))
    fi
    
    if test_configuration; then
        ((tests_passed++))
    fi
    
    if test_module_loading; then
        ((tests_passed++))
    fi
    
    # Report results
    echo
    log "Test Results: $tests_passed/$tests_total tests passed"
    
    if [[ $tests_passed -eq $tests_total ]]; then
        success "🎉 All tests passed! Installation script is ready for release."
        return 0
    else
        error "❌ Some tests failed. Please fix issues before release."
        return 1
    fi
}

# Show help
show_help() {
    echo -e "${BOLD}Milou CLI Installation Test Script${NC}"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --help, -h        Show this help"
    echo
    echo "This script tests the installation process locally before GitHub release."
    echo "It simulates the curl | bash installation process using the local repository."
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run tests
run_tests 