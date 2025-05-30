#!/bin/bash

# =============================================================================
# Milou CLI Development Test Script
# Tests setup functionality in development environment
# =============================================================================

# Load shared utilities to eliminate code duplication
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$script_dir/shared-utils.sh" ]]; then
    source "$script_dir/shared-utils.sh"
else
    echo "ERROR: Cannot find shared-utils.sh in $script_dir" >&2
    exit 1
fi

set -euo pipefail

# =============================================================================
# Test Setup Script for Milou CLI Development
# Sets up test environment for development and testing
# Location: scripts/dev/test-setup.sh
# =============================================================================

# Development test configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly TEST_DIR="/tmp/milou-dev-test-$$"

# Test setup commands and functionality
echo "Development test script running..."
log "Testing Milou CLI setup functionality"

# Remove duplicate logging function definitions since they're now provided by shared-utils.sh
# Enhanced log function that uses milou_log if available
log_enhanced() {
    if command -v milou_log >/dev/null 2>&1; then
        milou_log "$@"
    else
        # Fallback for standalone script execution (shouldn't happen with shared-utils.sh)
        log "$@"
    fi
}

# Setup test environment
setup_test_environment() {
    milou_log "INFO" "🧪 Setting up test environment for Milou CLI"
    
    # Change to project root
    cd "$PROJECT_ROOT"
    
    # Create necessary directories
    mkdir -p tests/ssl static/ssl ssl/backups
    
    # Copy environment template if needed
    if [[ ! -f .env && -f .env.example ]]; then
    milou_log "INFO" "📋 Copying .env.example to .env"
        cp .env.example .env
    fi
    
    # Setup SSL directory structure
    if [[ ! -d static/ssl ]]; then
        mkdir -p static/ssl/backups
    milou_log "INFO" "📁 Created SSL directory structure"
    fi
    
    milou_log "INFO" "✅ Test environment setup complete"
}

# Main function
main() {
    milou_log "INFO" "🚀 Milou CLI Test Setup"
    echo "Project Root: $PROJECT_ROOT"
    echo
    
    setup_test_environment
    
    milou_log "INFO" "🎉 Setup completed successfully!"
    milou_log "INFO" "You can now run development commands from: $PROJECT_ROOT"
}

# Show help if requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Milou CLI Development Test Setup"
    echo
    echo "Usage: $0"
    echo
    echo "Sets up the development environment for testing Milou CLI"
    echo "Creates necessary directories and copies configuration templates"
    echo
    exit 0
fi

main "$@" 