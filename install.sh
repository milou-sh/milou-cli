#!/bin/bash

# =============================================================================
# Milou CLI - One-Line Installer
# Easy installation script for Milou CLI
# Usage: curl -fsSL https://raw.githubusercontent.com/milou-sh/milou-cli/main/install.sh | bash
# =============================================================================

set -euo pipefail

# Configuration
readonly REPO_URL="https://github.com/milou-sh/milou-cli"
readonly REPO_RAW_URL="https://raw.githubusercontent.com/milou-sh/milou-cli/main"
readonly INSTALL_DIR="${MILOU_INSTALL_DIR:-$HOME/milou-cli}"
readonly BRANCH="${MILOU_BRANCH:-main}"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color
readonly DIM='\033[2m'

# Global variables
QUIET=false
FORCE=false
AUTO_START=true

# Logging functions
log() {
    if [[ "$QUIET" != "true" ]]; then
        echo -e "${GREEN}[INFO]${NC} $*"
    fi
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

step() {
    echo -e "${BLUE}[STEP]${NC} $*"
}

# Show Milou ASCII art
show_milou_logo() {
    echo -e "${PURPLE}"
    cat << 'EOF'
                     @@@@@@@@@@@                     
                     @@@@@@@@@@@                     
                     @@@@@@@@@@@                     
                     @@@@@@@@@@@                     
                     @@@@@@@@@@@                     
          @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@          
          @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@          
          @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@          
          @@@@@@@@@@@   @@@@@@@@@@@@@@@@@@@          
          @@@@@@@@@@    @@@@@@@@@@@@@@@@@@@          
          @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@          
          @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
          @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
          @@@@@@@@@@@@@@@@@@@@@    @@@@@@@@@@@@@@@@@@
          @@@@@@@@@@@@@@@@@@@@@@  @@@@@@@@@@@@@@@@@@@
          @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
          @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@                               
@@@@@@@@@@@@@@@@@@@@@@                               
@@@@@@@@@@@@@@@@@@@@@@                               
@@@@@@@@@@@@@@@@@@@@@@                               
@@@@@@@@@@@@@@@@@@@@@@                                                                                                                 
EOF
    echo -e "${NC}"
    echo -e "${BOLD}${CYAN}             Milou CLI - Professional Docker Management${NC}"
    echo -e "${CYAN}                    One-Line Installation${NC}"
    echo
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --quiet|-q)
                QUIET=true
                shift
                ;;
            --force|-f)
                FORCE=true
                shift
                ;;
            --no-start)
                AUTO_START=false
                shift
                ;;
            --install-dir=*)
                INSTALL_DIR="${1#*=}"
                shift
                ;;
            --branch=*)
                BRANCH="${1#*=}"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                warn "Unknown option: $1"
                shift
                ;;
        esac
    done
}

# Show help
show_help() {
    echo "Milou CLI Installer"
    echo
    echo "Usage: curl -fsSL https://raw.githubusercontent.com/milou-sh/milou-cli/main/install.sh | bash"
    echo "   or: bash install.sh [OPTIONS]"
    echo
    echo "Options:"
    echo "  --quiet, -q           Quiet installation"
    echo "  --force, -f           Force installation over existing directory"
    echo "  --no-start            Don't start setup automatically"
    echo "  --install-dir=DIR     Install to specific directory (default: ~/milou-cli)"
    echo "  --branch=BRANCH       Install from specific branch (default: main)"
    echo "  --help, -h            Show this help"
    echo
    echo "Environment Variables:"
    echo "  MILOU_INSTALL_DIR     Installation directory"
    echo "  MILOU_BRANCH          Git branch to install from"
    echo
    echo "Examples:"
    echo "  # Basic installation"
    echo "  curl -fsSL https://raw.githubusercontent.com/milou-sh/milou-cli/main/install.sh | bash"
    echo
    echo "  # Install to specific directory"
    echo "  MILOU_INSTALL_DIR=/opt/milou curl -fsSL ... | bash"
    echo
    echo "  # Install specific branch"
    echo "  MILOU_BRANCH=develop curl -fsSL ... | bash"
}

# Check prerequisites
check_prerequisites() {
    step "Checking prerequisites..."
    
    local missing_deps=()
    
    # Check required commands
    for cmd in git curl; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing_deps[*]}"
        echo "Please install missing dependencies and try again."
        
        # Provide installation hints based on OS
        if command -v apt-get &> /dev/null; then
            echo "Try: sudo apt-get update && sudo apt-get install ${missing_deps[*]}"
        elif command -v yum &> /dev/null; then
            echo "Try: sudo yum install ${missing_deps[*]}"
        elif command -v brew &> /dev/null; then
            echo "Try: brew install ${missing_deps[*]}"
        fi
        
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Check if installation directory exists
check_existing_installation() {
    if [[ -d "$INSTALL_DIR" ]]; then
        if [[ "$FORCE" == "true" ]]; then
            warn "Installation directory exists, removing due to --force flag"
            rm -rf "$INSTALL_DIR"
        else
            error "Installation directory already exists: $INSTALL_DIR"
            echo "Use --force to overwrite or choose a different directory with --install-dir"
            echo "Or run: rm -rf '$INSTALL_DIR' && curl -fsSL ... | bash"
            exit 1
        fi
    fi
}

# Download and install Milou CLI
install_milou() {
    step "Installing Milou CLI to $INSTALL_DIR..."
    echo
    
    # Create parent directory if needed
    local parent_dir
    parent_dir="$(dirname "$INSTALL_DIR")"
    if [[ ! -d "$parent_dir" ]]; then
        log "📁 Creating installation directory..."
        mkdir -p "$parent_dir"
    fi
    
    # Clone the repository
    log "⬇️  Downloading Milou CLI from GitHub..."
    echo -e "   ${DIM}Repository: $REPO_URL${NC}"
    echo -e "   ${DIM}Branch: $BRANCH${NC}"
    echo
    
    if ! git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$INSTALL_DIR" 2>&1 | grep -E "(Cloning|Receiving|Resolving)" | sed 's/^/   /' ; then
        error "Failed to download repository"
        echo
        echo -e "${YELLOW}💡 Troubleshooting:${NC}"
        echo "   • Check internet connection"
        echo "   • Verify repository exists: $REPO_URL"
        echo "   • Try a different branch: MILOU_BRANCH=main curl ... | bash"
        exit 1
    fi
    
    # Make scripts executable
    log "🔧 Setting up permissions..."
    chmod +x "$INSTALL_DIR/milou.sh"
    
    # Make main script executable if it exists
    if [[ -f "$INSTALL_DIR/src/milou" ]]; then
        chmod +x "$INSTALL_DIR/src/milou"
    fi
    
    # Verify installation
    if [[ -f "$INSTALL_DIR/milou.sh" ]]; then
        success "✅ Milou CLI downloaded and configured successfully"
    else
        error "Installation verification failed"
        exit 1
    fi
}

# Set up PATH and shell integration
setup_shell_integration() {
    step "Setting up shell integration..."
    
    local shell_rc=""
    case "$SHELL" in
        */bash)
            shell_rc="$HOME/.bashrc"
            ;;
        */zsh)
            shell_rc="$HOME/.zshrc"
            ;;
        */fish)
            shell_rc="$HOME/.config/fish/config.fish"
            ;;
        *)
            warn "Unknown shell: $SHELL, skipping shell integration"
            return 0
            ;;
    esac
    
    if [[ -n "$shell_rc" && -f "$shell_rc" ]]; then
        local alias_line="alias milou='$INSTALL_DIR/milou.sh'"
        
        if ! grep -q "alias milou=" "$shell_rc" 2>/dev/null; then
            echo "" >> "$shell_rc"
            echo "# Milou CLI alias" >> "$shell_rc"
            echo "$alias_line" >> "$shell_rc"
            log "Added milou alias to $shell_rc"
        else
            log "Milou alias already exists in $shell_rc"
        fi
    fi
    
    success "Shell integration configured"
}

# Show completion message
show_completion() {
    echo
    success "🎉 Milou CLI installation completed!"
    echo
    echo -e "${BOLD}${BLUE}┌──────────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}${BLUE}│             INSTALLATION COMPLETE!          │${NC}"
    echo -e "${BOLD}${BLUE}└──────────────────────────────────────────────┘${NC}"
    echo
    echo -e "${CYAN}📍 Installation Details:${NC}"
    echo -e "   Location: ${BOLD}$INSTALL_DIR${NC}"
    echo -e "   Version:  ${BOLD}Latest from $BRANCH branch${NC}"
    echo -e "   Command:  ${BOLD}milou${NC} (available after shell restart)"
    echo
    echo -e "${GREEN}🚀 Quick Start Commands:${NC}"
    echo -e "   ${BOLD}cd $INSTALL_DIR${NC}"
    echo -e "   ${BOLD}./milou.sh setup${NC}      # Start interactive setup"
    echo -e "   ${BOLD}./milou.sh --help${NC}     # View all commands"
    echo
    echo -e "${YELLOW}💡 Shell Integration:${NC}"
    echo -e "   Restart your terminal or run: ${BOLD}source ~/.bashrc${NC}"
    echo -e "   Then you can use: ${BOLD}milou setup${NC}"
    echo
}

# Start interactive setup if requested
start_setup() {
    if [[ "$AUTO_START" == "true" ]]; then
        echo
        echo -e "${BOLD}${GREEN}🚀 Ready to Start Setup!${NC}"
        echo
        echo -e "${CYAN}The interactive setup wizard will:${NC}"
        echo -e "   • Guide you through configuration"
        echo -e "   • Set up SSL certificates"
        echo -e "   • Configure admin credentials"
        echo -e "   • Start your Docker services"
        echo
        
        echo -e "${YELLOW}Starting in 3 seconds... (Press Ctrl+C to cancel)${NC}"
        
        for i in 3 2 1; do
            echo -ne "\r${YELLOW}Starting in $i seconds... (Press Ctrl+C to cancel)${NC}"
            sleep 1
        done
        echo -ne "\r${GREEN}Starting setup now!                                ${NC}\n"
        echo
        
        step "Launching Milou setup wizard..."
        cd "$INSTALL_DIR"
        exec ./milou.sh setup
    else
        echo
        echo -e "${BOLD}${BLUE}🎯 Manual Setup${NC}"
        echo -e "${CYAN}To start setup when ready:${NC}"
        echo -e "   ${BOLD}cd $INSTALL_DIR${NC}"
        echo -e "   ${BOLD}./milou.sh setup${NC}"
        echo
    fi
}

# Main installation function
main() {
    # Parse arguments if running as script
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        parse_args "$@"
    fi
    
    # Show logo unless quiet
    if [[ "$QUIET" != "true" ]]; then
        show_milou_logo
    fi
    
    step "Starting Milou CLI installation..."
    
    # Run installation steps
    check_prerequisites
    check_existing_installation
    install_milou
    setup_shell_integration
    
    # Show completion message
    if [[ "$QUIET" != "true" ]]; then
        show_completion
    fi
    
    # Start setup if requested
    start_setup
}

# Handle script being piped from curl
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Running as script
    main "$@"
else
    # Being sourced (shouldn't happen with curl | bash)
    main "$@"
fi 