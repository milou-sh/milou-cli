#!/bin/bash

set -euo pipefail

# =============================================================================
# Milou Management CLI - Enhanced Edition v3.1.0
# State-of-the-art CLI with comprehensive improvements using modular utilities
# =============================================================================

# Version and Constants
readonly SCRIPT_VERSION="3.1.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Simple log function that works before modules are loaded
log() {
    if command -v milou_log >/dev/null 2>&1; then
        milou_log "$@"
    else
        # Fallback for before modules are loaded (no colors to avoid conflicts)
        local level="$1"
        shift
        local message="$*"
        case "$level" in
            "ERROR") echo "[ERROR] $message" >&2 ;;
            "WARN") echo "[WARN] $message" >&2 ;;
            "INFO") echo "[INFO] $message" ;;
            "DEBUG") [[ "${VERBOSE:-false}" == "true" ]] && echo "[DEBUG] $message" ;;
            *) echo "[INFO] $message" ;;
        esac
    fi
}

# Simple error_exit function
error_exit() {
    log "ERROR" "$1"
    exit "${2:-1}"
}

# Smart configuration directory determination
determine_config_directory() {
    # If running as root but milou user exists, prefer milou's home
    if [[ $EUID -eq 0 ]] && command -v getent >/dev/null 2>&1 && getent passwd milou >/dev/null 2>&1; then
        local milou_home
        milou_home=$(getent passwd milou | cut -d: -f6)
        echo "${milou_home}/.milou"
    else
        # Use current user's home
        echo "${HOME}/.milou"
    fi
}

readonly CONFIG_DIR="$(determine_config_directory)"
readonly ENV_FILE="${SCRIPT_DIR}/.env"
readonly BACKUP_DIR="${CONFIG_DIR}/backups"
readonly LOG_FILE="${CONFIG_DIR}/milou.log"
readonly CACHE_DIR="${CONFIG_DIR}/cache"
readonly DEFAULT_SSL_PATH="./ssl"

# Global State - Enhanced with better defaults
declare -g VERBOSE=false
declare -g FORCE=false
declare -g DRY_RUN=false
declare -g GITHUB_TOKEN=""
declare -g USE_LATEST_IMAGES=true
declare -g SKIP_VERSION_CHECK=false
declare -g INTERACTIVE=true
declare -g AUTO_CREATE_USER=false
declare -g SKIP_USER_CHECK=false
declare -g FRESH_INSTALL=false
declare -g AUTO_INSTALL_DEPS=false

# Enhanced state management for user switching
declare -g ORIGINAL_COMMAND=""
declare -g ORIGINAL_ARGUMENTS=()
declare -g USER_SWITCH_IN_PROGRESS=false

# NEW MODULAR SYSTEM
# Initialize module loader and load essential modules
if [[ -f "${SCRIPT_DIR}/lib/core/module-loader.sh" ]]; then
    source "${SCRIPT_DIR}/lib/core/module-loader.sh"
    milou_modules_init "$SCRIPT_DIR"
    milou_load_essentials
    
    # Initialize logging with the correct config directory
    if command -v milou_log_init >/dev/null 2>&1; then
        milou_log_init "$CONFIG_DIR"
    fi
else
    # No fallback to old system - force use of new modular system
    echo "ERROR: New module system not found, cannot continue" >&2
    echo "Please ensure the lib/ directory structure is complete" >&2
    exit 1
fi

# Create necessary directories with proper ownership handling
ensure_config_directories() {
    # Create directories first
    mkdir -p "${CONFIG_DIR}" "${BACKUP_DIR}" "${CACHE_DIR}" 2>/dev/null || true
    
    # Create log file with proper permissions
    touch "${LOG_FILE}" 2>/dev/null || true
    
    # Simple ownership handling - only if milou user exists and we can check safely
    if [[ $EUID -eq 0 ]] && getent passwd milou >/dev/null 2>&1; then
        local milou_home
        milou_home=$(getent passwd milou | cut -d: -f6 2>/dev/null) || milou_home="/home/milou"
        
        # If CONFIG_DIR is in milou's home, set proper ownership
        if [[ "${CONFIG_DIR}" == "${milou_home}/.milou" ]]; then
            chown -R milou:milou "${CONFIG_DIR}" 2>/dev/null || true
            chown -R milou:milou "${BACKUP_DIR}" 2>/dev/null || true  
            chown -R milou:milou "${CACHE_DIR}" 2>/dev/null || true
            chown milou:milou "${LOG_FILE}" 2>/dev/null || true
        fi
    fi
}

ensure_config_directories

# =============================================================================
# Enhanced State Management
# =============================================================================

# Save the original command and arguments for user switching
preserve_original_command() {
    # Store everything as arguments for proper reconstruction
    ORIGINAL_ARGUMENTS=("$@")
    export ORIGINAL_COMMAND="${1:-}"
    # Export ALL arguments including the command for simpler handling in subshells
    export ORIGINAL_ARGUMENTS_STR="$(printf '%q ' "$@")"
    
    # Enhanced logging with token awareness (but don't log the actual token)
    local debug_args_str="$ORIGINAL_ARGUMENTS_STR"
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        debug_args_str=$(echo "$debug_args_str" | sed 's/ghp_[A-Za-z0-9]\{36\}/***TOKEN***/g')
    fi
    
    if command -v milou_log >/dev/null 2>&1; then
        milou_log "DEBUG" "Preserved command: '$ORIGINAL_COMMAND' with ${#ORIGINAL_ARGUMENTS[@]} arguments"
        milou_log "DEBUG" "All arguments (sanitized): $debug_args_str"
    fi
    
    # Ensure the GitHub token is properly exported for user switching
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        export GITHUB_TOKEN
        if command -v milou_log >/dev/null 2>&1; then
            milou_log "DEBUG" "GitHub token preserved for user switching (length: ${#GITHUB_TOKEN})"
        fi
    fi
}

# Check if we're resuming after a user switch
check_user_switch_resume() {
    if [[ "${USER_SWITCH_IN_PROGRESS:-false}" == "true" && -n "${ORIGINAL_COMMAND:-}" ]]; then
        if command -v milou_log >/dev/null 2>&1; then
            milou_log "DEBUG" "Resuming after user switch with command: $ORIGINAL_COMMAND"
            milou_log "DEBUG" "Original arguments: ${ORIGINAL_ARGUMENTS_STR:-none}"
        fi
        return 0
    fi
    return 1
}

# =============================================================================
# Enhanced Help System
# =============================================================================

show_help() {
    # Use colors if available, otherwise plain text
    local bold="${BOLD:-}"
    local purple="${PURPLE:-}"
    local cyan="${CYAN:-}"
    local nc="${NC:-}"
    
    printf "${bold}${purple}Milou Management CLI v${SCRIPT_VERSION}${nc}\n\n"

    printf "${bold}USAGE:${nc}\n"
    printf "    $(basename "$0") [COMMAND] [OPTIONS]\n\n"

    printf "${bold}COMMANDS:${nc}\n"
    printf "    ${cyan}setup${nc}             Interactive setup wizard (recommended for first-time setup)\n"
    printf "    ${cyan}start${nc}             Start all services\n"
    printf "    ${cyan}stop${nc}              Stop all services\n"
    printf "    ${cyan}restart${nc}           Restart all services\n"
    printf "    ${cyan}status${nc}            Show detailed status of all services\n"
    printf "    ${cyan}detailed-status${nc}   Show comprehensive system status and conflicts\n"
    printf "    ${cyan}logs${nc} [SERVICE]    View logs for all or specific service\n"
    printf "    ${cyan}health${nc}            Run comprehensive health checks\n"
    printf "    ${cyan}health-check${nc}      Quick health check for running services\n"
    printf "    ${cyan}config${nc}            View current configuration\n"
    printf "    ${cyan}validate${nc}          Validate configuration and environment\n"
    printf "    ${cyan}backup${nc}            Create system backup\n"
    printf "    ${cyan}restore${nc} [FILE]    Restore from backup file\n"
    printf "    ${cyan}update${nc}            Update to latest version\n"
    printf "    ${cyan}ssl${nc}               Manage SSL certificates\n"
    printf "    ${cyan}cleanup${nc}           Clean up Docker resources\n"
    printf "    ${cyan}shell${nc} [SERVICE]   Get shell access to a running container\n"
    printf "    ${cyan}debug-images${nc}      Debug Docker image availability (troubleshooting)\n"
    printf "    ${cyan}diagnose${nc}          Run comprehensive Docker environment diagnosis\n"
    printf "    ${cyan}user-status${nc}       Show current user and permission status\n"
    printf "    ${cyan}create-user${nc}       Create dedicated milou user (requires sudo)\n"
    printf "    ${cyan}migrate-user${nc}      Migrate existing installation to milou user\n"
    printf "    ${cyan}security-check${nc}    Run comprehensive security assessment\n"
    printf "    ${cyan}security-harden${nc}   Apply security hardening measures (requires sudo)\n"
    printf "    ${cyan}security-report${nc}   Generate detailed security report\n"
    printf "    ${cyan}install-deps${nc}      Install system dependencies (Docker, tools, etc.)\n"
    printf "    ${cyan}cleanup-test-files${nc} Remove test configuration files\n"
    printf "    ${cyan}help${nc}              Show this help message\n\n"

    printf "${bold}OPTIONS:${nc}\n"
    printf "    ${cyan}--verbose${nc}         Enable verbose output\n"
    printf "    ${cyan}--force${nc}           Force operations without confirmation\n"
    printf "    ${cyan}--dry-run${nc}         Show what would be done without executing\n"
    printf "    ${cyan}--token TOKEN${nc}     GitHub personal access token\n"
    printf "    ${cyan}--domain DOMAIN${nc}   Domain name for SSL certificates\n"
    printf "    ${cyan}--ssl-path PATH${nc}   Path to SSL certificates\n"
    printf "    ${cyan}--email EMAIL${nc}     Admin email address\n"
    printf "    ${cyan}--latest${nc}          Use latest Docker images (default)\n"
    printf "    ${cyan}--fixed-version${nc}   Use fixed/pinned Docker image versions\n"
    printf "    ${cyan}--non-interactive${nc} Run in non-interactive mode\n"
    printf "    ${cyan}--auto-create-user${nc} Automatically create milou user if needed\n"
    printf "    ${cyan}--skip-user-check${nc}  Skip user permission validation\n"
    printf "    ${cyan}--auto-install-deps${nc} Automatically install missing dependencies\n"
    printf "    ${cyan}--fresh-install${nc}   Optimize for fresh server installation\n"
    printf "    ${cyan}--help, -h${nc}        Show this help message\n\n"

    printf "${bold}EXAMPLES:${nc}\n"
    printf "    $(basename "$0") setup --fresh-install\n"
    printf "    $(basename "$0") start --verbose\n"
    printf "    $(basename "$0") backup\n"
    printf "    $(basename "$0") setup --token ghp_xxxx --domain example.com --non-interactive\n"
    printf "    $(basename "$0") security-check --verbose\n\n"

    printf "${bold}DOCUMENTATION:${nc}\n"
    printf "    For detailed documentation, visit: https://github.com/dougxc/milou\n"
    printf "    For support, create an issue at: https://github.com/dougxc/milou/issues\n\n"
}

# =============================================================================
# Main Function - Streamlined with Modular Commands
# =============================================================================

main() {
    local command="${1:-help}"
    
    # Show help if no command provided
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    # Preserve original command for potential user switching
    preserve_original_command "$@"
    
    # Early command validation - exit fast for help
    case "$command" in
        help|--help|-h)
            show_help
            exit 0
            ;;
    esac

    shift

    # Enhanced argument parsing with better error handling
    local -a remaining_args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose)
                VERBOSE=true
                export VERBOSE
                shift
                ;;
            --force)
                FORCE=true
                export FORCE
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                export DRY_RUN
                shift
                ;;
            --token)
                if [[ -n "${2:-}" ]]; then
                    GITHUB_TOKEN="$2"
                    export GITHUB_TOKEN
                    if command -v milou_log >/dev/null 2>&1; then
                        milou_log "DEBUG" "Token parsed from arguments: length=${#GITHUB_TOKEN}"
                    fi
                    shift 2
                else
                    error_exit "GitHub token value is required after --token"
                fi
                ;;
            --domain)
                if [[ -n "${2:-}" ]]; then
                    DOMAIN="$2"
                    export DOMAIN
                    shift 2
                else
                    error_exit "Domain value is required after --domain"
                fi
                ;;
            --ssl-path)
                if [[ -n "${2:-}" ]]; then
                    SSL_PATH="$2"
                    export SSL_PATH
                    shift 2
                else
                    error_exit "SSL path value is required after --ssl-path"
                fi
                ;;
            --email)
                if [[ -n "${2:-}" ]]; then
                    ADMIN_EMAIL="$2"
                    export ADMIN_EMAIL
                    shift 2
                else
                    error_exit "Email value is required after --email"
                fi
                ;;
            --latest)
                USE_LATEST_IMAGES=true
                export USE_LATEST_IMAGES
                shift
                ;;
            --fixed-version)
                USE_LATEST_IMAGES=false
                export USE_LATEST_IMAGES
                shift
                ;;
            --non-interactive)
                INTERACTIVE=false
                export INTERACTIVE
                shift
                ;;
            --auto-create-user)
                AUTO_CREATE_USER=true
                export AUTO_CREATE_USER
                shift
                ;;
            --skip-user-check)
                SKIP_USER_CHECK=true
                export SKIP_USER_CHECK
                shift
                ;;
            --auto-install-deps)
                AUTO_INSTALL_DEPS=true
                export AUTO_INSTALL_DEPS
                shift
                ;;
            --fresh-install)
                FRESH_INSTALL=true
                AUTO_CREATE_USER=true  # Automatically enable auto-create-user for fresh installs
                AUTO_INSTALL_DEPS=true  # Automatically enable auto-install-deps for fresh installs
                export FRESH_INSTALL
                export AUTO_CREATE_USER
                export AUTO_INSTALL_DEPS
                shift
                ;;
            --help|-h)
                # Command-specific help
                if [[ "$command" == "cleanup" || "$command" == "backup" || "$command" == "ssl" ]]; then
                    remaining_args+=("$1")
                    shift
                else
                    show_help
                    exit 0
                fi
                ;;
            *)
                remaining_args+=("$1")
                shift
                ;;
        esac
    done
    
    # Log script start with enhanced information
    log "DEBUG" "Milou CLI v$SCRIPT_VERSION started"
    log "DEBUG" "Command: $command, User: $(whoami), PID: $$"
    log "DEBUG" "Working directory: $(pwd)"
    
    # Check if we're resuming after user switch
    if check_user_switch_resume; then
        log "DEBUG" "Resuming operation after user switch"
        
        # Re-parse the original arguments completely
        if [[ -n "${ORIGINAL_ARGUMENTS_STR:-}" ]]; then
            log "DEBUG" "Re-parsing original arguments: $ORIGINAL_ARGUMENTS_STR"
            
            # Reset everything and re-parse from the original arguments
            eval "set -- $ORIGINAL_ARGUMENTS_STR"
            command="$1"
            shift
            
            # Re-parse flags (abbreviated version for resume scenario)
            remaining_args=()
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --verbose) VERBOSE=true; export VERBOSE; shift ;;
                    --force) FORCE=true; export FORCE; shift ;;
                    --dry-run) DRY_RUN=true; export DRY_RUN; shift ;;
                    --token) [[ -n "${2:-}" ]] && { GITHUB_TOKEN="$2"; export GITHUB_TOKEN; shift 2; } || shift ;;
                    --domain) [[ -n "${2:-}" ]] && { DOMAIN="$2"; export DOMAIN; shift 2; } || shift ;;
                    --ssl-path) [[ -n "${2:-}" ]] && { SSL_PATH="$2"; export SSL_PATH; shift 2; } || shift ;;
                    --email) [[ -n "${2:-}" ]] && { ADMIN_EMAIL="$2"; export ADMIN_EMAIL; shift 2; } || shift ;;
                    --latest) USE_LATEST_IMAGES=true; export USE_LATEST_IMAGES; shift ;;
                    --fixed-version) USE_LATEST_IMAGES=false; export USE_LATEST_IMAGES; shift ;;
                    --non-interactive) INTERACTIVE=false; export INTERACTIVE; shift ;;
                    --auto-create-user) AUTO_CREATE_USER=true; export AUTO_CREATE_USER; shift ;;
                    --skip-user-check) SKIP_USER_CHECK=true; export SKIP_USER_CHECK; shift ;;
                    --auto-install-deps) AUTO_INSTALL_DEPS=true; export AUTO_INSTALL_DEPS; shift ;;
                    --fresh-install) 
                        FRESH_INSTALL=true; AUTO_CREATE_USER=true; AUTO_INSTALL_DEPS=true
                        export FRESH_INSTALL AUTO_CREATE_USER AUTO_INSTALL_DEPS; shift ;;
                    *) remaining_args+=("$1"); shift ;;
                esac
            done
            
            log "DEBUG" "Resumed with command: $command, verbose: $VERBOSE, remaining args: ${#remaining_args[@]}"
        else
            # Fallback to ORIGINAL_COMMAND only
            command="$ORIGINAL_COMMAND"
            remaining_args=()
        fi
    fi
    
    # Enhanced command routing with modular system
    log "DEBUG" "Before command routing: GITHUB_TOKEN=${GITHUB_TOKEN:-NOT_SET} (length: ${#GITHUB_TOKEN})"
    
# Load command on-demand and execute
milou_load_and_execute_command() {
    local cmd="$1"
    shift
    local args=("$@")
    
    # Load command-specific modules using centralized loader
    if command -v milou_load_command_modules >/dev/null 2>&1; then
        milou_load_command_modules "$cmd"
    fi
    
    # Try to load command handler on-demand
    local commands_dir="${SCRIPT_DIR}/commands"
    local handler_function="handle_${cmd//-/_}"
    
    # Map commands to their handler files
    local handler_file=""
    case "$cmd" in
        setup)
            handler_file="setup.sh"
            ;;
        start|stop|restart|status|detailed-status|logs|health|health-check|shell|debug-images)
            handler_file="docker-services.sh"
            ;;
        config|validate|backup|restore|update|ssl|cleanup|cleanup-test-files|install-deps|diagnose)
            handler_file="system.sh"
            ;;
        user-status|create-user|migrate-user|security-check|security-harden|security-report)
            handler_file="user-security.sh"
            ;;
        *)
            log "ERROR" "Unknown command: $cmd"
            return 1
            ;;
    esac
    
    # Load handler file if it exists
    if [[ -n "$handler_file" && -f "${commands_dir}/${handler_file}" ]]; then
        if source "${commands_dir}/${handler_file}" 2>/dev/null; then
            log "DEBUG" "Loaded handler file: $handler_file"
        else
            log "WARN" "Failed to load handler file: $handler_file"
        fi
    fi
    
    # Try to execute the handler function
    if command -v "$handler_function" >/dev/null 2>&1; then
        "$handler_function" "${args[@]}"
    else
        log "ERROR" "Command handler not available: $handler_function"
        log "INFO" "Falling back to legacy system..."
        
        # Fallback to original monolithic handlers if they exist
        if command -v handle_"$cmd" >/dev/null 2>&1; then
            handle_"$cmd" "${args[@]}"
        else
            log "ERROR" "No handler available for command: $cmd"
            exit 1
        fi
    fi
}

    case "$command" in
        help|--help|-h)
            show_help
            ;;
        *)
            milou_load_and_execute_command "$command" "${remaining_args[@]}"
            ;;
    esac
}

# =============================================================================
# Enhanced Script Entry Point
# =============================================================================

# Enhanced cleanup on exit
cleanup_on_exit() {
    local exit_code=$?
    log "DEBUG" "Script execution completed with exit code: $exit_code"
    
    # Clean up temporary files
    cleanup_user_management 2>/dev/null || true
    
    # Reset terminal if needed
    if [[ -t 1 ]]; then
        tput sgr0 2>/dev/null || true
    fi
    
    exit $exit_code
}

# Set up signal handlers
trap cleanup_on_exit EXIT
trap 'log "WARN" "Script interrupted by user"; exit 130' INT TERM

# Validate environment before starting
if [[ ! -d "$SCRIPT_DIR" ]]; then
    echo "ERROR: Script directory not found: $SCRIPT_DIR" >&2
    exit 1
fi

if [[ ! -d "$SCRIPT_DIR/utils" ]]; then
    echo "ERROR: Utils directory not found: $SCRIPT_DIR/utils" >&2
    exit 1
fi

# Run main function with all arguments
main "$@" 