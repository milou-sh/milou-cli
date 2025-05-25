#!/bin/bash

set -euo pipefail

# =============================================================================
# Test Setup Script for Milou CLI Development
# Sets up test environment for development and testing
# Location: scripts/dev/test-setup.sh
# =============================================================================

# Get script directory and project root
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log() {
    local level="$1"
    shift
    local message="$*"
    case "$level" in
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
        "WARN") echo -e "${YELLOW}[WARN]${NC} $message" >&2 ;;
        "INFO") echo -e "${GREEN}[INFO]${NC} $message" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $message" ;;
        *) echo "[INFO] $message" ;;
    esac
}

# Setup test environment
setup_test_environment() {
    log "INFO" "🧪 Setting up test environment for Milou CLI"
    
    # Change to project root
    cd "$PROJECT_ROOT"
    
    # Create necessary directories
    mkdir -p tests/ssl static/ssl ssl/backups
    
    # Copy environment template if needed
    if [[ ! -f .env && -f .env.example ]]; then
        log "INFO" "📋 Copying .env.example to .env"
        cp .env.example .env
    fi
    
    # Setup SSL directory structure
    if [[ ! -d static/ssl ]]; then
        mkdir -p static/ssl/backups
        log "INFO" "📁 Created SSL directory structure"
    fi
    
    log "INFO" "✅ Test environment setup complete"
}

# Main function
main() {
    log "INFO" "🚀 Milou CLI Test Setup"
    echo "Project Root: $PROJECT_ROOT"
    echo
    
    setup_test_environment
    
    log "INFO" "🎉 Setup completed successfully!"
    log "INFO" "You can now run development commands from: $PROJECT_ROOT"
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