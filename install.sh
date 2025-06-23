#!/bin/bash

# =============================================================================
# Milou CLI - One-Line Installer
# =============================================================================

set -euo pipefail

# --- Start of UI Library ---
# A lightweight, self-contained set of UI functions for a consistent look and feel.

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly PURPLE='\033[0;35m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m' # No Color

# Symbols
readonly CHECKMARK='✔'
readonly CROSSMARK='✖'
readonly ROCKET='🚀'

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    
    [[ "${QUIET:-false}" == "true" ]] && [[ "$level" != "ERROR" ]] && return 0

    case "$level" in
        ERROR)
            echo -e "${RED}${BOLD}${CROSSMARK} ERROR:${NC} ${message}" >&2
            ;;
        WARN)
            echo -e "${YELLOW}▲ WARNING:${NC} ${message}" >&2
            ;;
        SUCCESS)
            echo -e "${GREEN}${CHECKMARK} SUCCESS:${NC} ${message}"
            ;;
        STEP)
            echo -e "\n${BLUE}━━━ ${BOLD}Step: ${message}${NC} ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
            ;;
        INFO)
            echo -e "${CYAN}→ INFO:${NC} ${message}"
            ;;
        *)
            echo -e "${message}"
            ;;
    esac
}

# --- End of UI Library ---

# Tries to detect the branch name from the curl command used to run this script.
# This makes the one-line installer branch-aware.
detect_branch_from_curl() {
    # This function is only effective when the script is piped from curl.
    # We check for the parent process ID (PPID) to determine the calling command.
    if [[ -z "$PPID" ]]; then
        return
    fi
    
    local parent_cmd=""
    # Use /proc for a more reliable method on Linux systems
    if [[ -r /proc/$PPID/cmdline ]]; then
        # Read the null-delimited arguments into a string
        parent_cmd=$(tr -d '\0' < /proc/$PPID/cmdline)
    # Fallback to using ps for other systems (like macOS)
    elif command -v ps >/dev/null; then
        parent_cmd=$(ps -o args= -p "$PPID")
    else
        return # Cannot determine parent command
    fi

    # Check if the parent command is curl and extract branch from the URL.
    # It also handles the jsdelivr CDN URL format.
    if [[ "$parent_cmd" =~ curl ]]; then
        if [[ "$parent_cmd" =~ milou-sh/milou-cli@([^/]+)/install\.sh ]] || \
           [[ "$parent_cmd" =~ milou-sh/milou-cli/([^/]+)/install\.sh ]]; then
            local detected_branch="${BASH_REMATCH[1]}"
            if [[ -n "$detected_branch" && "$detected_branch" != "$BRANCH" ]]; then
                log "INFO" "Installer branch detected: ${BOLD}$detected_branch${NC}. Overriding default branch."
                BRANCH="$detected_branch" # Override the global BRANCH variable
            fi
        fi
    fi
}

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
readonly REPO_RAW_URL="https://raw.githubusercontent.com/milou-sh/milou-cli/main-gemini"
INSTALL_DIR="${MILOU_INSTALL_DIR:-$(get_default_install_dir)}"
BRANCH="${MILOU_BRANCH:-main}"

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
    log "ERROR" "$error_msg"
    
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

# Show minimal logo
show_minimal_logo() {
    [[ "$QUIET" == "true" ]] && return
    echo -e "${BOLD}${PURPLE}"
    cat << 'EOF'

    ███╗   ███╗██╗██╗      ██████╗ ██╗   ██╗
    ████╗ ████║██║██║     ██╔═══██╗██║   ██║  
    ██╔████╔██║██║██║     ██║   ██║██║   ██║  
    ██║╚██╔╝██║██║██║     ██║   ██║██║   ██║  
    ██║ ╚═╝ ██║██║███████╗╚██████╔╝╚██████╔╝  
    ╚═╝     ╚═╝╚═╝╚══════╝ ╚═════╝  ╚═════╝   
    
EOF
    echo -e "${NC}"
    log "STEP" "Milou CLI Installer"
}

# Prompt for installation directory
prompt_installation_directory() {
    if [[ "$INTERACTIVE" == "false" ]] || [[ "$QUIET" == "true" ]]; then
        return 0
    fi
    
    local current_install_dir="$INSTALL_DIR"
    
    log "INFO" "Please choose where to install Milou CLI."
    
    echo -e "${BOLD}${CYAN}Recommended options:${NC}"
    echo
    if [[ $EUID -eq 0 ]]; then
        echo -e "${GREEN}   1) ${BOLD}System-wide${NC} ${DIM}(/opt/milou-cli)${NC}"
        echo -e "      ${CHECKMARK} Accessible to all users"
        echo -e "      ${CHECKMARK} Standard system location"
        echo -e "      ${CHECKMARK} Recommended for production servers"
        echo
        echo -e "${BLUE}   2) ${BOLD}Custom location${NC} ${DIM}(specify your own path)${NC}"
        echo -e "      ${CHECKMARK} Full control over location"
        echo -e "      ${CHECKMARK} For advanced setups"
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
                    log "SUCCESS" "System-wide installation selected. Using: ${BOLD}$INSTALL_DIR${NC}"
                    break
                    ;;
                2) 
                    log "INFO" "Custom location selected."
                    local custom_dir
                    custom_dir=$(prompt_user "Installation directory" "/opt/milou-cli")
                    if [[ -n "$custom_dir" ]]; then
                        INSTALL_DIR="$custom_dir"
                        log "SUCCESS" "Using custom location: ${BOLD}$INSTALL_DIR${NC}"
                    else
                        log "WARN" "No path entered, using default."
                        INSTALL_DIR="/opt/milou-cli"
                    fi
                    break
                    ;;
                *) 
                    log "ERROR" "Please choose 1 or 2"
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
                    log "SUCCESS" "Default location selected. Using: ${BOLD}$INSTALL_DIR${NC}"
                    break
                    ;;
                2) 
                    log "INFO" "Custom location selected."
                    local custom_dir
                    custom_dir=$(prompt_user "Installation directory" "$HOME/milou-cli")
                    if [[ -n "$custom_dir" ]]; then
                        INSTALL_DIR="$custom_dir"
                        log "SUCCESS" "Using custom location: ${BOLD}$INSTALL_DIR${NC}"
                    else
                        log "WARN" "No path entered, using default."
                    fi
                    break
                    ;;
                *) 
                    log "ERROR" "Please choose 1 or 2"
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
                log "WARN" "Unknown option: $1"
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
    log "STEP" "Checking prerequisites..."
    for cmd in curl tar; do
        if ! command -v "$cmd" &> /dev/null; then
            handle_error "Missing required dependency: $cmd. Please install it and try again."
            return 1
        fi
    done
    log "SUCCESS" "All prerequisites are met."
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
            log "WARN" "Existing Milou CLI installation detected."
            
            if [[ "$INTERACTIVE" == "false" ]] || [[ "$QUIET" == "true" ]]; then
                local backup_dir="${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
                if mv "$INSTALL_DIR" "$backup_dir"; then
                    log "INFO" "Backup created: $backup_dir"
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
                        log "INFO" "Backup created: $backup_dir"
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
    log "STEP" "Installing Milou CLI to $INSTALL_DIR..."
    
    local parent_dir
    parent_dir="$(dirname "$INSTALL_DIR")"
    if [[ ! -d "$parent_dir" ]]; then
        if ! mkdir -p "$parent_dir"; then
            handle_error "Failed to create installation directory"
            return 1
        fi
    fi
    
    log "INFO" "Downloading from GitHub ($BRANCH branch)..."
    
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
            log "INFO" "Set ownership of $INSTALL_DIR to user '$target_user'"
        fi
    fi
    
    log "SUCCESS" "Installation completed."
    return 0
}

# Set up PATH and shell integration
setup_shell_integration() {
    log "STEP" "Setting up shell integration..."
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
            log "SUCCESS" "Milou alias added to $shell_rc"
        fi
    fi
}

# Show completion
show_completion() {
    [[ "$QUIET" == "true" ]] && return
    log "SUCCESS" "Milou CLI was installed to $INSTALL_DIR"
}

# Ready to start message
start_setup() {
    if [[ "$AUTO_START" == "true" ]]; then
        log "STEP" "Finalizing Setup"
        
        local choice
        choice=$(prompt_user "Start setup wizard now? (Y/n)" "y")
        
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            cd "$INSTALL_DIR"
            export MILOU_INSTALLER_RUN="true"
            export INTERACTIVE=true
            export MILOU_INTERACTIVE=true
            unset FORCE QUIET
            
            if [[ ! -t 0 ]]; then
                exec ./milou.sh setup --from-installer < /dev/tty
            else
                exec ./milou.sh setup --from-installer
            fi
        else
            log "INFO" "Run: cd $INSTALL_DIR && ./milou.sh setup (when ready)"
        fi
    else
        log "INFO" "Run: cd $INSTALL_DIR && ./milou.sh setup (when ready)"
    fi
}

# Main installation function
main() {
    check_interactive_mode
    
    # Auto-detect branch from curl command BEFORE parsing args.
    # This allows --branch flag to override the detection.
    detect_branch_from_curl

    if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]] || [[ -z "${BASH_SOURCE[0]:-}" ]]; then
        parse_args "$@"
    fi
    
    # Suppress logo if setup will be run immediately after
    if [[ "$AUTO_START" == "true" ]]; then
        export MILOU_INSTALLER_RUN="true"
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
    # When piped, MILOU_INSTALLER_RUN will be set to avoid double logo
    export MILOU_INSTALLER_RUN="true"
    main "$@"
fi 