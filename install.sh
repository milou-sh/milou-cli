#!/bin/bash

# =============================================================================
# Milou CLI - One-Line Installer
# Easy installation script for Milou CLI
# Usage: curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/milou-cli/main/install.sh | bash
# =============================================================================

set -euo pipefail

# Configuration
readonly REPO_URL="https://github.com/YOUR_ORG/milou-cli"
readonly REPO_RAW_URL="https://raw.githubusercontent.com/YOUR_ORG/milou-cli/main"
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
                                        @@@@@@@@@@@@@@@@@@@@                                        
                                        @@@@@@@@@@@@@@@@@@@@                                        
                                        @@@@@@@@@@@@@@@@@@@@                                        
                                        @@@@@@@@@@@@@@@@@@@@                                        
                                        @@@@@@@@@@@@@@@@@@@@                                        
                                        @@@@@@@@@@@@@@@@@@@@                                        
                                        @@@@@@@@@@@@@@@@@@@@                                        
                                        @@@@@@@@@@@@@@@@@@@@                                        
                                        @@@@@@@@@@@@@@@@@@@@                                        
                                        @@@@@@@@@@@@@@@@@@@@                                        
                    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                    
                    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                    
                    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                    
                    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                    
                    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                    
                    @@@@@@@@@@@@@@@@@@@      @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                    
                    @@@@@@@@@@@@@@@@@@        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                    
                    @@@@@@@@@@@@@@@@@@        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                    
                    @@@@@@@@@@@@@@@@@@@      @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                    
                    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                    
                    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                    
                    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@         @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@     @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                                                            
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                                                            
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                                                            
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                                                            
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                                                            
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                                                            
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                                                            
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                                                            
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                                                            
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                                                            
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
    echo "Usage: curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/milou-cli/main/install.sh | bash"
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
    echo "  curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/milou-cli/main/install.sh | bash"
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
    
    # Create parent directory if needed
    local parent_dir
    parent_dir="$(dirname "$INSTALL_DIR")"
    if [[ ! -d "$parent_dir" ]]; then
        mkdir -p "$parent_dir"
    fi
    
    # Clone the repository
    log "Cloning repository from $REPO_URL..."
    if ! git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$INSTALL_DIR"; then
        error "Failed to clone repository"
        exit 1
    fi
    
    # Make scripts executable
    log "Setting up permissions..."
    chmod +x "$INSTALL_DIR/milou.sh"
    
    # Make main script executable if it exists
    if [[ -f "$INSTALL_DIR/src/milou" ]]; then
        chmod +x "$INSTALL_DIR/src/milou"
    fi
    
    success "Milou CLI installed successfully"
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
    echo "═══════════════════════════════════════════════════"
    echo -e "            ${BOLD}${GREEN}INSTALLATION COMPLETE!${NC}"
    echo "═══════════════════════════════════════════════════"
    echo
    echo "📍 Installation Location:"
    echo "  $INSTALL_DIR"
    echo
    echo "🚀 Quick Start:"
    echo "  cd $INSTALL_DIR"
    echo "  ./milou.sh setup"
    echo
    echo "💡 Or if you restart your shell:"
    echo "  milou setup"
    echo
    echo "📚 Documentation:"
    echo "  README.md         - Overview and quick start"
    echo "  docs/USER_GUIDE.md - Complete setup guide"
    echo "  ./milou.sh --help - All available commands"
    echo
    echo "🔗 Useful Commands:"
    echo "  ./milou.sh status    - Check system status"
    echo "  ./milou.sh logs      - View service logs"
    echo "  ./milou.sh backup    - Create system backup"
    echo
}

# Start interactive setup if requested
start_setup() {
    if [[ "$AUTO_START" == "true" ]]; then
        echo -e "${YELLOW}Starting interactive setup in 3 seconds...${NC}"
        echo -e "${YELLOW}Press Ctrl+C to cancel${NC}"
        sleep 3
        
        echo
        step "Starting Milou setup..."
        cd "$INSTALL_DIR"
        exec ./milou.sh setup
    else
        echo "To start setup manually:"
        echo "  cd $INSTALL_DIR && ./milou.sh setup"
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