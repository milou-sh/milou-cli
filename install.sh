#!/bin/bash

# =============================================================================
# Milou CLI - One-Line Installer
# =============================================================================

set -euo pipefail

# Determine default installation directory
get_default_install_dir() {
    local username
    if [[ $EUID -eq 0 ]]; then
        # For root user, prefer /opt for system-wide installation
        echo "/opt/milou-cli"
    else
        # For regular users, use home directory
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
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m' # No Color

# Symbols
readonly CHECKMARK='✓'
readonly CROSSMARK='✗'

# Global variables
QUIET=false
FORCE=false
AUTO_START=true
INTERACTIVE=true

# Check if running in interactive mode
check_interactive_mode() {
    if [[ ! -t 1 ]]; then # Check only stdout to allow for piping
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
        read -p "$prompt [$default]: " response < /dev/tty
        echo "${response:-$default}"
    else
        read -p "$prompt: " response < /dev/tty
        echo "$response"
    fi
}

# Error handling
handle_error() {
    local error_msg="$1"
    echo -e "${RED}Error: $error_msg${NC}" >&2
    
    if [[ "$INTERACTIVE" == "false" ]] || [[ "$QUIET" == "true" ]]; then
        exit 1
    fi
    
    local choice
    choice=$(prompt_user "Try again? (y/N)" "n")
    
    case "$choice" in
        [Yy]*)
            return 0
            ;;
        *)
            exit 1
            ;;
    esac
}

# Logging functions
log() {
    [[ "$QUIET" != "true" ]] && echo -e "$*"
}

warn() {
    echo -e "${YELLOW}Warning: $*${NC}" >&2
}

error() {
    echo -e "${RED}Error: $*${NC}" >&2
}

success() {
    echo -e "${GREEN}$*${NC}"
}

# Show minimal logo
show_minimal_logo() {
    [[ "$QUIET" == "true" ]] && return
    echo -e "${BLUE}Milou CLI Installer - The One-Line Installers${NC}"
}

# Prompt for installation directory
prompt_installation_directory() {
    if [[ "$INTERACTIVE" == "false" ]] || [[ "$QUIET" == "true" ]]; then
        return 0
    fi
    
    local current_install_dir="$INSTALL_DIR"
    
    echo -e "${BLUE}📁 Installation Directory Setup${NC}"
    echo -e "${DIM}Choose where to install Milou CLI on your system.${NC}"
    echo
    
    echo -e "${BOLD}${CYAN}Recommended options:${NC}"
    echo
    if [[ $EUID -eq 0 ]]; then
        echo -e "${GREEN}   1) ${BOLD}System-wide${NC} ${DIM}(/opt/milou-cli)${NC}"
        echo -e "      ${GREEN}${CHECKMARK}${NC} Accessible to all users"
        echo -e "      ${GREEN}${CHECKMARK}${NC} Standard system location"
        echo -e "      ${GREEN}${CHECKMARK}${NC} Recommended for production servers"
        echo
        echo -e "${BLUE}   2) ${BOLD}Custom location${NC} ${DIM}(specify your own path)${NC}"
        echo -e "      ${BLUE}✓${NC} Full control over location"
        echo -e "      ${BLUE}✓${NC} For advanced setups"
        echo
        
        local dir_choice
        while true; do
            echo -ne "${BOLD}${GREEN}Choose installation location${NC} [${CYAN}1-2${NC}] (recommended: ${BOLD}1${NC}): "
            read -r dir_choice < /dev/tty
            if [[ -z "$dir_choice" ]]; then
                dir_choice="1"
            fi
            
            case "$dir_choice" in
                1) 
                    INSTALL_DIR="/opt/milou-cli"
                    echo -e "   ${GREEN}${CHECKMARK} System-wide installation!${NC} Using: ${BOLD}$INSTALL_DIR${NC}"
                    break
                    ;;
                2) 
                    echo -e "   ${BLUE}${CHECKMARK} Custom location selected!${NC}"
                    local custom_dir
                    custom_dir=$(prompt_user "Installation directory" "/opt/milou-cli")
                    if [[ -n "$custom_dir" ]]; then
                        INSTALL_DIR="$custom_dir"
                        echo -e "   ${GREEN}${CHECKMARK}${NC} Using custom location: ${BOLD}$INSTALL_DIR${NC}"
                    else
                        echo -e "   ${RED}${CROSSMARK} No path entered, using default${NC}"
                        INSTALL_DIR="/opt/milou-cli"
                    fi
                    break
                    ;;
                *) 
                    echo -e "   ${RED}${CROSSMARK} Please choose 1 or 2${NC}"
                    echo
                    ;;
            esac
        done
    else
        echo -e "${GREEN}   1) ${BOLD}Default location${NC} ${DIM}($current_install_dir)${NC}"
        echo -e "      ${GREEN}${CHECKMARK}${NC} Recommended for your user"
        echo -e "      ${GREEN}${CHECKMARK}${NC} No additional permissions needed"
        echo
        echo -e "${BLUE}   2) ${BOLD}Custom location${NC} ${DIM}(specify your own path)${NC}"
        echo -e "      ${BLUE}✓${NC} Choose your preferred location"
        echo -e "      ${YELLOW}✓${NC} May require different permissions"
        echo
        
        local dir_choice
        while true; do
            echo -ne "${BOLD}${GREEN}Choose installation location${NC} [${CYAN}1-2${NC}] (recommended: ${BOLD}1${NC}): "
            read -r dir_choice < /dev/tty
            if [[ -z "$dir_choice" ]]; then
                dir_choice="1"
            fi
            
            case "$dir_choice" in
                1) 
                    echo -e "   ${GREEN}${CHECKMARK} Default location!${NC} Using: ${BOLD}$INSTALL_DIR${NC}"
                    break
                    ;;
                2) 
                    echo -e "   ${BLUE}${CHECKMARK} Custom location selected!${NC}"
                    local custom_dir
                    custom_dir=$(prompt_user "Installation directory" "$HOME/milou-cli")
                    if [[ -n "$custom_dir" ]]; then
                        INSTALL_DIR="$custom_dir"
                        echo -e "   ${GREEN}${CHECKMARK}${NC} Using custom location: ${BOLD}$INSTALL_DIR${NC}"
                    else
                        echo -e "   ${RED}${CROSSMARK} No path entered, using default${NC}"
                    fi
                    break
                    ;;
                *) 
                    echo -e "   ${RED}${CROSSMARK} Please choose 1 or 2${NC}"
                    echo
                    ;;
            esac
        done
    fi
    
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
    echo "  --install-dir=DIR     Install to specific directory"
    echo "  --branch=BRANCH       Install from specific branch (default: main)"
    echo "  --help, -h            Show this help"
}

# Check prerequisites
check_prerequisites() {
    for cmd in curl tar; do
        if ! command -v "$cmd" &> /dev/null; then
            handle_error "Missing required dependency: $cmd. Please install it and try again."
            return 1
        fi
    done
    return 0
}

# Check if installation directory exists
check_existing_installation() {
    if [[ -d "$INSTALL_DIR" ]]; then
        local is_milou_installation=false
        if [[ -f "$INSTALL_DIR/milou.sh" ]] && [[ -f "$INSTALL_DIR/.env.example" ]]; then
            is_milou_installation=true
        fi
        
        if [[ "$FORCE" == "true" ]]; then
            if ! rm -rf "$INSTALL_DIR"; then
                handle_error "Failed to remove existing installation directory"
                return 1
            fi
        elif [[ "$is_milou_installation" == "true" ]]; then
            warn "Existing Milou CLI installation detected"
            
            if [[ "$INTERACTIVE" == "false" ]] || [[ "$QUIET" == "true" ]]; then
                local backup_dir="${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
                if mv "$INSTALL_DIR" "$backup_dir"; then
                    log "Backup created: $backup_dir"
                else
                    handle_error "Failed to backup existing installation"
                    return 1
                fi
            else
                local choice
                choice=$(prompt_user "Update existing installation? (Y/n)" "y")
                if [[ "$choice" =~ ^[Yy]$ ]]; then
                    local backup_dir="${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
                    if mv "$INSTALL_DIR" "$backup_dir"; then
                        log "Backup created: $backup_dir"
                    else
                        handle_error "Failed to backup existing installation"
                        return 1
                    fi
                else
                    echo "Installation cancelled."
                    exit 1
                fi
            fi
        else
            handle_error "Directory exists: $INSTALL_DIR (use --force to overwrite)"
            
            local choice
            choice=$(prompt_user "Remove existing directory? (y/N)" "n")
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                if ! rm -rf "$INSTALL_DIR"; then
                    handle_error "Failed to remove existing directory"
                    exit 1
                fi
            else
                echo "Installation cancelled."
                exit 1
            fi
        fi
    fi
}

# Download and install Milou CLI
install_milou() {
    log "Installing Milou CLI to $INSTALL_DIR..."
    
    local parent_dir
    parent_dir="$(dirname "$INSTALL_DIR")"
    if [[ ! -d "$parent_dir" ]]; then
        if ! mkdir -p "$parent_dir"; then
            handle_error "Failed to create installation directory"
            return 1
        fi
    fi
    
    log "Downloading from GitHub ($BRANCH branch)..."
    
    # Create the installation directory first
    mkdir -p "$INSTALL_DIR"
    
    # Download and extract the tarball in one go
    if ! curl -fsSL "$REPO_URL/archive/refs/heads/$BRANCH.tar.gz" | tar -xz -C "$INSTALL_DIR" --strip-components=1; then
        handle_error "Failed to download and extract repository archive"
        return 1
    fi
    
    if ! chmod +x "$INSTALL_DIR/milou.sh"; then
        handle_error "Failed to set executable permissions"
        return 1
    fi
    
    if [[ -f "$INSTALL_DIR/src/milou" ]]; then
        chmod +x "$INSTALL_DIR/src/milou" 2>/dev/null || true
    fi
    
    if [[ ! -f "$INSTALL_DIR/milou.sh" ]]; then
        handle_error "Installation verification failed"
        return 1
    fi
    
    if [[ $EUID -eq 0 ]] && [[ "$INSTALL_DIR" == /home/* ]]; then
        local target_user
        target_user=$(echo "$INSTALL_DIR" | cut -d'/' -f3)
        if id "$target_user" &>/dev/null; then
            chown -R "$target_user:$target_user" "$INSTALL_DIR" 2>/dev/null || true
        fi
    fi
    
    success "Installation completed"
    return 0
}

# Set up PATH and shell integration
setup_shell_integration() {
    local target_user=""
    local shell_rc=""
    
    if [[ $EUID -eq 0 ]] && [[ "$INSTALL_DIR" == /home/* ]]; then
        target_user=$(echo "$INSTALL_DIR" | cut -d'/' -f3)
        if id "$target_user" &>/dev/null; then
            local user_shell
            user_shell=$(getent passwd "$target_user" | cut -d: -f7)
            case "$user_shell" in
                */bash) shell_rc="/home/$target_user/.bashrc" ;;
                */zsh) shell_rc="/home/$target_user/.zshrc" ;;
                */fish) shell_rc="/home/$target_user/.config/fish/config.fish" ;;
            esac
        fi
    else
        case "$SHELL" in
            */bash) shell_rc="$HOME/.bashrc" ;;
            */zsh) shell_rc="$HOME/.zshrc" ;;
            */fish) shell_rc="$HOME/.config/fish/config.fish" ;;
            *) return 0 ;;
        esac
    fi
    
    if [[ -n "$shell_rc" && -f "$shell_rc" ]]; then
        local alias_line="alias milou='$INSTALL_DIR/milou.sh'"
        
        if ! grep -q "alias milou=" "$shell_rc" 2>/dev/null; then
            echo "" >> "$shell_rc"
            echo "# Milou CLI alias" >> "$shell_rc"
            echo "$alias_line" >> "$shell_rc"
            
            if [[ -n "$target_user" ]]; then
                chown "$target_user:$target_user" "$shell_rc" 2>/dev/null || true
            fi
        fi
    fi
}

# Show completion
show_completion() {
    [[ "$QUIET" == "true" ]] && return
    success "Milou CLI installed to $INSTALL_DIR"
}

# Ready to start message
start_setup() {
    if [[ "$AUTO_START" == "true" ]]; then
        [[ "$QUIET" != "true" ]] 
        
        local choice
        choice=$(prompt_user "Start setup wizard now? (Y/n)" "y")
        
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            cd "$INSTALL_DIR"
            export INTERACTIVE=true
            export MILOU_INTERACTIVE=true
            unset FORCE QUIET
            
            if [[ ! -t 0 ]]; then
                exec ./milou.sh setup < /dev/tty
            else
                exec ./milou.sh setup
            fi
        else
            echo "Run: cd $INSTALL_DIR && ./milou.sh setup (when ready)"
        fi
    else
        [[ "$QUIET" != "true" ]] && echo "Run: cd $INSTALL_DIR && ./milou.sh setup (when ready)"
    fi
}

# Main installation function
main() {
    check_interactive_mode
    
    if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]] || [[ -z "${BASH_SOURCE[0]:-}" ]]; then
        parse_args "$@"
    fi
    
    show_minimal_logo
    
    if [[ -z "${MILOU_INSTALL_DIR:-}" ]]; then
        prompt_installation_directory
    fi
    
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
    
    show_completion
    start_setup
}

# Handle script being piped from curl
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]] || [[ -z "${BASH_SOURCE[0]:-}" ]]; then
    main "$@"
else
    main "$@"
fi 