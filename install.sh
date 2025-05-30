#!/bin/bash

# =============================================================================
# Milou CLI - One-Line Installer
# Easy installation script for Milou CLI
# Usage: curl -fsSL https://raw.githubusercontent.com/milou-sh/milou-cli/main/install.sh | bash
# =============================================================================

set -euo pipefail

# Determine default installation directory
# Always use /home/ instead of /root/ even when running as root
get_default_install_dir() {
    local username
    if [[ $EUID -eq 0 ]]; then
        # Running as root - use the first regular user's home, or fall back to /home/milou
        username=$(getent passwd 2>/dev/null | awk -F: '$3 >= 1000 && $3 < 65534 { print $1; exit }' || true)
        if [[ -n "$username" ]]; then
            echo "/home/$username/milou-cli"
        else
            echo "/home/milou/milou-cli"
        fi
    else
        echo "$HOME/milou-cli"
    fi
}

# Configuration
readonly REPO_URL="https://github.com/milou-sh/milou-cli"
readonly REPO_RAW_URL="https://raw.githubusercontent.com/milou-sh/milou-cli/main"
INSTALL_DIR="${MILOU_INSTALL_DIR:-$(get_default_install_dir)}"
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
INTERACTIVE=true

# Check if running in interactive mode
check_interactive_mode() {
    # Check if stdin is a terminal and stdout is a terminal
    if [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
        INTERACTIVE=false
    fi
}

# Interactive prompt function
prompt_user() {
    local prompt="$1"
    local default="${2:-}"
    local response
    
    if [[ "$INTERACTIVE" == "false" ]] || [[ "$QUIET" == "true" ]]; then
        echo "$default"
        return 0
    fi
    
    if [[ -n "$default" ]]; then
        read -p "$prompt [$default]: " response
        echo "${response:-$default}"
    else
        read -p "$prompt: " response
        echo "$response"
    fi
}

# Interactive error handler
handle_error() {
    local error_msg="$1"
    local context="${2:-}"
    local suggestions=("${@:3}")
    
    error "$error_msg"
    
    if [[ -n "$context" ]]; then
        echo -e "${YELLOW}Context:${NC} $context"
    fi
    
    if [[ ${#suggestions[@]} -gt 0 ]]; then
        echo
        echo -e "${YELLOW}💡 Suggested solutions:${NC}"
        for i in "${!suggestions[@]}"; do
            echo "   $((i+1)). ${suggestions[$i]}"
        done
    fi
    
    if [[ "$INTERACTIVE" == "false" ]] || [[ "$QUIET" == "true" ]]; then
        echo -e "${RED}❌ Installation failed. Please address the issue and try again.${NC}"
        exit 1
    fi
    
    echo
    echo -e "${CYAN}What would you like to do?${NC}"
    echo "1. Try again"
    echo "2. Exit installation"
    echo "3. Continue anyway (not recommended)"
    
    local choice
    choice=$(prompt_user "Enter your choice (1-3)" "2")
    
    case "$choice" in
        1)
            echo -e "${BLUE}Retrying...${NC}"
            return 0  # Continue execution
            ;;
        3)
            warn "Continuing despite error - installation may not work properly"
            return 0  # Continue execution
            ;;
        *)
            echo -e "${RED}Exiting installation.${NC}"
            exit 1
            ;;
    esac
}

# Logging functions
log() {
    if [[ "$QUIET" != "true" ]]; then
        echo -e "${CYAN}• INFO${NC} $*"
    fi
}

warn() {
    echo -e "${YELLOW}${BOLD}⚠️  WARNING${NC} $*" >&2
}

error() {
    echo -e "${RED}${BOLD}❌ ERROR${NC} $*" >&2
}

success() {
    echo -e "${GREEN}${BOLD}✓ SUCCESS${NC} $*"
}

step() {
    echo -e "${BLUE}${BOLD}�� STEP${NC} $*"
}

# Show enhanced Milou logo with better design
show_milou_logo() {
    echo -e "${BOLD}${PURPLE}"
    cat << 'EOF'

    ███╗   ███╗██╗██╗      ██████╗ ██╗   ██╗
    ████╗ ████║██║██║     ██╔═══██╗██║   ██║  
    ██╔████╔██║██║██║     ██║   ██║██║   ██║  
    ██║╚██╔╝██║██║██║     ██║   ██║██║   ██║  
    ██║ ╚═╝ ██║██║███████╗╚██████╔╝╚██████╔╝  
    ╚═╝     ╚═╝╚═╝╚══════╝ ╚═════╝  ╚═════╝   
    
    ┌─────────────────────────────────────────┐
    │   Professional Docker Management        │
    │   🚀 Simple • Secure • Reliable        │
    └─────────────────────────────────────────┘

EOF
    echo -e "${NC}"
    echo -e "${BOLD}${CYAN}Welcome to the Milou CLI Installer!${NC}"
    echo -e "${DIM}Quick installation with automatic setup wizard${NC}"
    echo
}

# Prompt user for installation directory
prompt_installation_directory() {
    if [[ "$INTERACTIVE" == "false" ]] || [[ "$QUIET" == "true" ]]; then
        return 0  # Use default directory
    fi
    
    echo -e "${CYAN}📁 Installation Directory Selection${NC}"
    echo
    echo -e "Default installation directory: ${BOLD}$INSTALL_DIR${NC}"
    echo
    echo -e "${YELLOW}💡 Recommendations:${NC}"
    echo -e "   • ${BOLD}/home/username/milou-cli${NC} - Recommended for personal use"
    echo -e "   • ${BOLD}/opt/milou${NC} - Good for system-wide installation"
    echo -e "   • ${BOLD}/usr/local/milou${NC} - Alternative system-wide location"
    echo
    
    local choice
    choice=$(prompt_user "Use default directory? (y/N)" "y")
    
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        local custom_dir
        custom_dir=$(prompt_user "Enter custom installation directory" "/opt/milou")
        
        if [[ -n "$custom_dir" ]]; then
            INSTALL_DIR="$custom_dir"
            log "Installation directory changed to: $INSTALL_DIR"
        fi
    fi
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
    echo "  --install-dir=DIR     Install to specific directory (default: auto-detected in /home/)"
    echo "  --branch=BRANCH       Install from specific branch (default: main)"
    echo "  --help, -h            Show this help"
    echo
    echo "Environment Variables:"
    echo "  MILOU_INSTALL_DIR     Installation directory"
    echo "  MILOU_BRANCH          Git branch to install from"
    echo
    echo "Installation Directory:"
    echo "  By default, installs to /home/username/milou-cli"
    echo "  If running as root, detects first regular user or uses /home/milou/milou-cli"
    echo "  Interactive mode will prompt for directory choice"
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
        local suggestions=()
        
        # Provide installation hints based on OS
        if command -v apt-get &> /dev/null; then
            suggestions+=("Run: sudo apt-get update && sudo apt-get install ${missing_deps[*]}")
        elif command -v yum &> /dev/null; then
            suggestions+=("Run: sudo yum install ${missing_deps[*]}")
        elif command -v dnf &> /dev/null; then
            suggestions+=("Run: sudo dnf install ${missing_deps[*]}")
        elif command -v brew &> /dev/null; then
            suggestions+=("Run: brew install ${missing_deps[*]}")
        elif command -v pacman &> /dev/null; then
            suggestions+=("Run: sudo pacman -S ${missing_deps[*]}")
        else
            suggestions+=("Install ${missing_deps[*]} using your system's package manager")
        fi
        
        suggestions+=("Manually download and install the missing tools")
        suggestions+=("Use a different system with the required tools")
        
        handle_error "Missing required dependencies: ${missing_deps[*]}" \
                     "Milou CLI requires git and curl to download and install" \
                     "${suggestions[@]}"
        
        # If user chose to continue, we exit here since we can't proceed without dependencies
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Check if installation directory exists
check_existing_installation() {
    if [[ -d "$INSTALL_DIR" ]]; then
        # Check if this is an existing Milou installation
        local is_milou_installation=false
        if [[ -f "$INSTALL_DIR/milou.sh" ]] && [[ -f "$INSTALL_DIR/.env.example" ]]; then
            is_milou_installation=true
        fi
        
        if [[ "$FORCE" == "true" ]]; then
            warn "Installation directory exists, removing due to --force flag"
            if ! rm -rf "$INSTALL_DIR"; then
                handle_error "Failed to remove existing installation directory" \
                             "Could not delete $INSTALL_DIR" \
                             "Check directory permissions" \
                             "Use a different installation directory with --install-dir" \
                             "Run as root/sudo if necessary"
                return 1
            fi
        elif [[ "$is_milou_installation" == "true" ]]; then
            # This is an existing Milou installation - handle as update
            warn "Existing Milou CLI installation detected at $INSTALL_DIR"
            log "This appears to be an update/reinstall of Milou CLI"
            
            # If running non-interactively, backup and proceed
            if [[ "$INTERACTIVE" == "false" ]] || [[ "$QUIET" == "true" ]]; then
                local backup_dir="${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
                log "Creating backup of existing installation..."
                if mv "$INSTALL_DIR" "$backup_dir"; then
                    log "✅ Backup created: $backup_dir"
                    log "Proceeding with installation update..."
                else
                    handle_error "Failed to backup existing installation" \
                                 "Could not move $INSTALL_DIR to $backup_dir" \
                                 "Check directory permissions" \
                                 "Run with sudo if needed"
                    return 1
                fi
            else
                # Interactive mode - let user choose
                local choice
                choice=$(prompt_user "Update existing installation? (Y/n)" "y")
                if [[ "$choice" =~ ^[Yy]$ ]]; then
                    local backup_dir="${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
                    log "Creating backup of existing installation..."
                    if mv "$INSTALL_DIR" "$backup_dir"; then
                        log "✅ Backup created: $backup_dir"
                        log "Proceeding with installation update..."
                    else
                        handle_error "Failed to backup existing installation" \
                                     "Could not move $INSTALL_DIR to $backup_dir" \
                                     "Check directory permissions" \
                                     "Run with sudo if needed"
                        return 1
                    fi
                else
                    echo -e "${RED}Installation cancelled by user.${NC}"
                    exit 1
                fi
            fi
        else
            # Not a Milou installation - show error with suggestions
            local suggestions=(
                "Use --force flag: curl -fsSL https://raw.githubusercontent.com/milou-sh/milou-cli/main/install.sh | bash -s -- --force"
                "Remove manually: rm -rf '$INSTALL_DIR'"
                "Choose different directory: MILOU_INSTALL_DIR=/opt/milou curl -fsSL https://raw.githubusercontent.com/milou-sh/milou-cli/main/install.sh | bash"
                "Continue with existing installation (if it's a previous Milou installation)"
            )
            
            handle_error "Installation directory already exists: $INSTALL_DIR" \
                         "Cannot install over existing directory without --force flag" \
                         "${suggestions[@]}"
            
            # Let user decide what to do
            local choice
            choice=$(prompt_user "Remove existing directory and continue? (y/N)" "n")
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                warn "Removing existing installation directory..."
                if ! rm -rf "$INSTALL_DIR"; then
                    handle_error "Failed to remove existing directory" \
                                 "Could not delete $INSTALL_DIR" \
                                 "Check permissions and try again" \
                                 "Run with sudo if needed"
                    exit 1
                fi
            else
                echo -e "${RED}Installation cancelled by user.${NC}"
                exit 1
            fi
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
        if ! mkdir -p "$parent_dir"; then
            handle_error "Failed to create installation directory" \
                         "Could not create $parent_dir" \
                         "Check directory permissions" \
                         "Use a different installation directory" \
                         "Run with appropriate permissions"
            return 1
        fi
    fi
    
    # Clone the repository
    log "⬇️  Downloading Milou CLI from GitHub..."
    echo -e "   ${DIM}Repository: $REPO_URL${NC}"
    echo -e "   ${DIM}Branch: $BRANCH${NC}"
    echo
    
    local git_output
    if ! git_output=$(git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$INSTALL_DIR" 2>&1); then
        local suggestions=(
            "Check your internet connection"
            "Verify the repository URL: $REPO_URL"
            "Try a different branch: MILOU_BRANCH=main"
            "Check if git is properly configured"
            "Try cloning manually: git clone $REPO_URL $INSTALL_DIR"
        )
        
        handle_error "Failed to download repository" \
                     "Git clone failed: $git_output" \
                     "${suggestions[@]}"
        return 1
    else
        # Show progress output if available
        echo "$git_output" | grep -E "(Cloning|Receiving|Resolving)" | sed 's/^/   /' || true
    fi
    
    # Make scripts executable
    log "🔧 Setting up permissions..."
    if ! chmod +x "$INSTALL_DIR/milou.sh"; then
        handle_error "Failed to set executable permissions" \
                     "Could not make $INSTALL_DIR/milou.sh executable" \
                     "Check file permissions and ownership" \
                     "Run with appropriate permissions"
        return 1
    fi
    
    # Make main script executable if it exists
    if [[ -f "$INSTALL_DIR/src/milou" ]]; then
        if ! chmod +x "$INSTALL_DIR/src/milou"; then
            warn "Could not make src/milou executable, but installation can continue"
        fi
    fi
    
    # Verify installation
    if [[ -f "$INSTALL_DIR/milou.sh" ]]; then
        success "✅ Milou CLI downloaded and configured successfully"
    else
        handle_error "Installation verification failed" \
                     "milou.sh script not found after installation" \
                     "Try installing again" \
                     "Check for disk space issues" \
                     "Verify repository integrity"
        return 1
    fi
    
    # Set proper ownership if installed as root but for regular user
    if [[ $EUID -eq 0 ]] && [[ "$INSTALL_DIR" == /home/* ]]; then
        local target_user
        target_user=$(echo "$INSTALL_DIR" | cut -d'/' -f3)
        if id "$target_user" &>/dev/null; then
            log "🔐 Setting proper ownership for user $target_user..."
            chown -R "$target_user:$target_user" "$INSTALL_DIR" || \
                warn "Could not set ownership, but installation can continue"
        fi
    fi
}

# Set up PATH and shell integration
setup_shell_integration() {
    step "Setting up shell integration..."
    
    # Determine target user's shell config
    local target_user=""
    local shell_rc=""
    
    if [[ $EUID -eq 0 ]] && [[ "$INSTALL_DIR" == /home/* ]]; then
        target_user=$(echo "$INSTALL_DIR" | cut -d'/' -f3)
        if id "$target_user" &>/dev/null; then
            local user_shell
            user_shell=$(getent passwd "$target_user" | cut -d: -f7)
            case "$user_shell" in
                */bash)
                    shell_rc="/home/$target_user/.bashrc"
                    ;;
                */zsh)
                    shell_rc="/home/$target_user/.zshrc"
                    ;;
                */fish)
                    shell_rc="/home/$target_user/.config/fish/config.fish"
                    ;;
            esac
        fi
    else
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
    fi
    
    if [[ -n "$shell_rc" && -f "$shell_rc" ]]; then
        local alias_line="alias milou='$INSTALL_DIR/milou.sh'"
        
        if ! grep -q "alias milou=" "$shell_rc" 2>/dev/null; then
            echo "" >> "$shell_rc"
            echo "# Milou CLI alias" >> "$shell_rc"
            echo "$alias_line" >> "$shell_rc"
            log "Added milou alias to $shell_rc"
            
            # Set proper ownership if needed
            if [[ -n "$target_user" ]]; then
                chown "$target_user:$target_user" "$shell_rc" 2>/dev/null || true
            fi
        else
            log "Milou alias already exists in $shell_rc"
        fi
    fi
    
    success "Shell integration configured"
}

# Enhanced progress indicator
show_progress() {
    local current="$1"
    local total="$2"
    local description="$3"
    local percentage=$((current * 100 / total))
    local filled=$((current * 20 / total))
    local empty=$((20 - filled))
    
    printf "\r${BLUE}${BOLD}Progress:${NC} ["
    printf "%*s" $filled | tr ' ' '█'
    printf "%*s" $empty | tr ' ' '░'
    printf "] %d%% ${CYAN}(%d/%d)${NC} %s" $percentage $current $total "$description"
    
    if [[ $current -eq $total ]]; then
        echo
    fi
}

# Enhanced installation summary
show_completion() {
    echo
    success "🎉 Milou CLI installation completed successfully!"
    echo
    echo -e "${BOLD}${BLUE}┌──────────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}${BLUE}│        🎊 INSTALLATION COMPLETE! 🎊        │${NC}"
    echo -e "${BOLD}${BLUE}└──────────────────────────────────────────────┘${NC}"
    echo
    echo -e "${BOLD}${CYAN}📍 Your Installation Details:${NC}"
    echo -e "   ${BOLD}Location:${NC}     $INSTALL_DIR"
    echo -e "   ${BOLD}Version:${NC}      Latest from $BRANCH branch"
    echo -e "   ${BOLD}Command:${NC}      ${CYAN}milou${NC} (available after shell restart)"
    echo
    echo -e "${BOLD}${GREEN}🚀 What's Next?${NC}"
    echo -e "   ${CYAN}1.${NC} Start the setup wizard: ${BOLD}cd $INSTALL_DIR && ./milou.sh setup${NC}"
    echo -e "   ${CYAN}2.${NC} View all commands: ${BOLD}./milou.sh --help${NC}"
    echo -e "   ${CYAN}3.${NC} Read the documentation: ${BOLD}docs/USER_GUIDE.md${NC}"
    echo
    echo -e "${BOLD}${YELLOW}💡 Pro Tip:${NC} Restart your terminal to use the ${CYAN}milou${NC} command globally"
    echo
}

# Enhanced ready to start message
start_setup() {
    if [[ "$AUTO_START" == "true" ]]; then
        echo
        echo -e "${BOLD}${GREEN}🎯 Ready to Configure Your System!${NC}"
        echo
        echo -e "${CYAN}The setup wizard will help you:${NC}"
        echo -e "   ${GREEN}✓${NC} Configure your domain and SSL certificates"
        echo -e "   ${GREEN}✓${NC} Set up admin credentials securely"
        echo -e "   ${GREEN}✓${NC} Install and start all services"
        echo -e "   ${GREEN}✓${NC} Verify everything works perfectly"
        echo
        echo -e "${DIM}Estimated time: 3-5 minutes${NC}"
        echo
        
        local choice
        choice=$(prompt_user "Start the setup wizard now? (Y/n)" "y")
        
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            echo
            step "Launching the interactive setup wizard..."
            echo -e "${DIM}Switching to setup mode for optimal configuration experience...${NC}"
            cd "$INSTALL_DIR"
            
            # Ensure setup runs in interactive mode
            export INTERACTIVE=true
            export MILOU_INTERACTIVE=true
            unset FORCE QUIET
            
            # Handle stdin redirection for curl | bash
            if [[ ! -t 0 ]]; then
                exec ./milou.sh setup < /dev/tty
            else
                exec ./milou.sh setup
            fi
        else
            echo
            echo -e "${BOLD}${BLUE}🎯 Manual Setup Instructions${NC}"
            echo -e "   ${CYAN}1.${NC} Open a new terminal (to activate the milou command)"
            echo -e "   ${CYAN}2.${NC} Run: ${BOLD}cd $INSTALL_DIR${NC}"
            echo -e "   ${CYAN}3.${NC} Run: ${BOLD}./milou.sh setup${NC}"
            echo
            echo -e "${YELLOW}💡 Tip:${NC} You can also run ${CYAN}milou setup${NC} from anywhere after restarting your terminal"
        fi
    else
        echo
        echo -e "${BOLD}${BLUE}🎯 Ready for Configuration${NC}"
        echo -e "   ${CYAN}When you're ready:${NC} ${BOLD}cd $INSTALL_DIR && ./milou.sh setup${NC}"
        echo -e "   ${CYAN}Or globally:${NC} ${BOLD}milou setup${NC} (after terminal restart)"
        echo
    fi
}

# Main installation function
main() {
    # Check if running interactively
    check_interactive_mode
    
    # Parse arguments if running as script
    if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]] || [[ -z "${BASH_SOURCE[0]:-}" ]]; then
        parse_args "$@"
    fi
    
    # Show logo unless quiet
    if [[ "$QUIET" != "true" ]]; then
        show_milou_logo
    fi
    
    step "Starting Milou CLI installation..."
    
    # Prompt for installation directory (if interactive and not overridden)
    if [[ -z "${MILOU_INSTALL_DIR:-}" ]]; then
        prompt_installation_directory
    fi
    
    log "Installation directory: $INSTALL_DIR"
    
    # Run installation steps with error handling
    if ! check_prerequisites; then
        exit 1
    fi
    
    if ! check_existing_installation; then
        exit 1
    fi
    
    if ! install_milou; then
        exit 1
    fi
    
    setup_shell_integration
    
    # Show completion message
    if [[ "$QUIET" != "true" ]]; then
        show_completion
    fi
    
    # Start setup if requested
    start_setup
}

# Handle script being piped from curl
# Use a safer check that works with curl | bash
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]] || [[ -z "${BASH_SOURCE[0]:-}" ]]; then
    # Running as script or via curl | bash
    main "$@"
else
    # Being sourced (shouldn't happen with curl | bash)
    main "$@"
fi 