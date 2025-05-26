#!/bin/bash

set -euo pipefail

# =============================================================================
# Milou Management CLI - Consolidated Edition v3.2.0
# Simplified architecture with consolidated modules
# =============================================================================

# Version and Constants
readonly SCRIPT_VERSION="3.2.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# SIMPLE MODULE LOADING - No complex loader needed!
# =============================================================================

# Load all consolidated modules in dependency order
source "${SCRIPT_DIR}/lib-new/utils.sh"    # Core utilities & logging (must be first)
source "${SCRIPT_DIR}/lib-new/config.sh"   # Configuration management
source "${SCRIPT_DIR}/lib-new/ssl.sh"      # SSL certificate management
source "${SCRIPT_DIR}/lib-new/docker.sh"   # Docker operations
source "${SCRIPT_DIR}/lib-new/users.sh"    # User management
source "${SCRIPT_DIR}/lib-new/system.sh"   # System operations

# =============================================================================
# CONFIGURATION
# =============================================================================

# Default Configuration
readonly CONFIG_DIR="${HOME}/.milou"
readonly ENV_FILE="${CONFIG_DIR}/.env"

# Get milou user config directory
get_milou_config_dir() {
    local milou_home
    milou_home=$(getent passwd milou | cut -d: -f6)
    echo "${milou_home}/.milou"
}

# Initialize configuration system
config_init

# Global State
ORIGINAL_COMMAND=""
ORIGINAL_ARGUMENTS=()
ORIGINAL_ARGUMENTS_STR=""
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# =============================================================================
# ARGUMENT PRESERVATION FOR USER SWITCHING
# =============================================================================

preserve_arguments() {
    ORIGINAL_COMMAND="$1"
    shift
    ORIGINAL_ARGUMENTS=("$@")
    
    # Create a safe string representation for debugging
    local debug_args_str=""
    for arg in "${ORIGINAL_ARGUMENTS[@]}"; do
        if [[ "$arg" =~ ^--token$ ]] || [[ "$arg" =~ ^ghp_ ]]; then
            debug_args_str+="[TOKEN] "
        else
            debug_args_str+="$arg "
        fi
    done
    
    log "DEBUG" "Preserved command: '$ORIGINAL_COMMAND' with ${#ORIGINAL_ARGUMENTS[@]} arguments"
    log "DEBUG" "All arguments (sanitized): $debug_args_str"
    
    # Ensure the GitHub token is properly exported for user switching
    if [[ -n "${GITHUB_TOKEN}" ]]; then
        export GITHUB_TOKEN
        log "DEBUG" "GitHub token preserved for user switching (length: ${#GITHUB_TOKEN})"
    fi
}

# Resume after user switch
resume_after_user_switch() {
    log "DEBUG" "Resuming after user switch with command: $ORIGINAL_COMMAND"
    log "DEBUG" "Original arguments: ${ORIGINAL_ARGUMENTS_STR:-none}"
    
    # Re-execute with preserved arguments
    exec "$0" "$ORIGINAL_COMMAND" "${ORIGINAL_ARGUMENTS[@]}"
}

# =============================================================================
# HELP SYSTEM
# =============================================================================

show_help() {
    log "INFO" "${BOLD}${PURPLE}Milou Management CLI v${SCRIPT_VERSION}${NC}"
    echo
    
    log "INFO" "${BOLD}USAGE:${NC}"
    echo "    milou-new.sh [COMMAND] [OPTIONS]"
    echo
    
    log "INFO" "${BOLD}COMMANDS:${NC}"
    echo "    ${CYAN}setup${NC}             Interactive setup wizard (recommended for first-time setup)"
    echo "    ${CYAN}start${NC}             Start all services"
    echo "    ${CYAN}stop${NC}              Stop all services"
    echo "    ${CYAN}restart${NC}           Restart all services"
    echo "    ${CYAN}status${NC}            Show detailed status of all services"
    echo "    ${CYAN}logs${NC} [SERVICE]    View logs for all or specific service"
    echo "    ${CYAN}health${NC}            Run comprehensive health checks"
    echo "    ${CYAN}config${NC}            View current configuration"
    echo "    ${CYAN}validate${NC}          Validate configuration and environment"
    echo "    ${CYAN}backup${NC}            Create system backup"
    echo "    ${CYAN}restore${NC} [FILE]    Restore from backup file"
    echo "    ${CYAN}update${NC}            Update to latest version"
    echo "    ${CYAN}ssl${NC}               Manage SSL certificates"
    echo "    ${CYAN}cleanup${NC}           Clean up Docker resources"
    echo "    ${CYAN}shell${NC} [SERVICE]   Get shell access to a running container"
    echo "    ${CYAN}user-status${NC}       Show current user and permission status"
    echo "    ${CYAN}create-user${NC}       Create dedicated milou user (requires sudo)"
    echo "    ${CYAN}security-check${NC}    Run comprehensive security assessment"
    echo "    ${CYAN}install-deps${NC}      Install system dependencies"
    echo "    ${CYAN}build-images${NC}      Build Docker images locally for development"
    echo "    ${CYAN}help${NC}              Show this help message"
    echo
    
    log "INFO" "${BOLD}OPTIONS:${NC}"
    echo "    ${CYAN}--verbose${NC}         Enable verbose output"
    echo "    ${CYAN}--force${NC}           Force operations without confirmation"
    echo "    ${CYAN}--dry-run${NC}         Show what would be done without executing"
    echo "    ${CYAN}--token TOKEN${NC}     GitHub personal access token"
    echo "    ${CYAN}--domain DOMAIN${NC}   Domain name for SSL certificates"
    echo "    ${CYAN}--ssl-path PATH${NC}   Path to SSL certificates"
    echo "    ${CYAN}--email EMAIL${NC}     Admin email address"
    echo "    ${CYAN}--latest${NC}          Use latest Docker images (default)"
    echo "    ${CYAN}--fixed-version${NC}   Use fixed/pinned Docker image versions"
    echo "    ${CYAN}--non-interactive${NC} Run in non-interactive mode"
    echo "    ${CYAN}--auto-create-user${NC} Automatically create milou user if needed"
    echo "    ${CYAN}--skip-user-check${NC}  Skip user permission validation"
    echo "    ${CYAN}--auto-install-deps${NC} Automatically install missing dependencies"
    echo "    ${CYAN}--fresh-install${NC}   Optimize for fresh server installation"
    echo "    ${CYAN}--dev${NC}             Enable development mode (use local Docker images)"
    echo "    ${CYAN}--help, -h${NC}        Show this help message"
    echo
    
    log "INFO" "${BOLD}EXAMPLES:${NC}"
    echo "    milou-new.sh setup --fresh-install"
    echo "    milou-new.sh start --verbose"
    echo "    milou-new.sh backup"
    echo "    milou-new.sh setup --token ghp_xxxx --domain example.com --non-interactive"
    echo "    milou-new.sh security-check --verbose"
    echo
}

# =============================================================================
# COMMAND HANDLERS
# =============================================================================

cmd_setup() {
    log "INFO" "🚀 Starting Milou setup..."
    
    # Check prerequisites first
    if ! milou_check_prerequisites; then
        if [[ "${AUTO_INSTALL_DEPS}" == "true" ]] || ask_yes_no "Install missing prerequisites?"; then
            milou_install_prerequisites || return 1
        else
            log "ERROR" "Prerequisites required for setup"
            return 1
        fi
    fi
    
    # Run setup wizard
    milou_setup_wizard
}

cmd_start() {
    log "INFO" "🚀 Starting Milou services..."
    docker_start "$@"
}

cmd_stop() {
    log "INFO" "🛑 Stopping Milou services..."
    docker_stop "$@"
}

cmd_restart() {
    log "INFO" "🔄 Restarting Milou services..."
    docker_restart "$@"
}

cmd_status() {
    log "INFO" "📊 Checking service status..."
    docker_status "$@"
}

cmd_logs() {
    log "INFO" "📋 Viewing service logs..."
    docker_logs "$@"
}

cmd_health() {
    log "INFO" "🏥 Running health checks..."
    milou_system_health
    docker_health_check
}

cmd_config() {
    case "${1:-show}" in
        "show")
            show_config
            ;;
        "edit")
            ssl_interactive_setup
            ;;
        "validate")
            test_config
            ;;
        *)
            log "ERROR" "Unknown config command: $1"
            log "INFO" "Available: show, edit, validate"
            return 1
            ;;
    esac
}

cmd_validate() {
    log "INFO" "🔍 Validating system..."
    milou_validate_system
}

cmd_backup() {
    local backup_name="${1:-milou-backup-$(date +%Y%m%d-%H%M%S)}"
    log "INFO" "💾 Creating backup: $backup_name"
    milou_system_backup "$backup_name"
}

cmd_restore() {
    local backup_file="$1"
    if [[ -z "$backup_file" ]]; then
        log "ERROR" "Backup file required"
        log "INFO" "Usage: milou restore <backup-file>"
        return 1
    fi
    log "INFO" "📥 Restoring from backup: $backup_file"
    milou_system_restore "$backup_file"
}

cmd_update() {
    log "INFO" "🔄 Updating Milou system..."
    milou_system_update "$@"
}

cmd_ssl() {
    case "${1:-status}" in
        "generate")
            shift
            generate_ssl_certificate "$@"
            ;;
        "validate")
            validate_ssl_certificate
            ;;
        "status")
            show_ssl_status
            ;;
        "setup")
            ssl_interactive_setup
            ;;
        "renew")
            generate_ssl_certificate --renew
            ;;
        *)
            log "ERROR" "Unknown SSL command: $1"
            log "INFO" "Available: generate, validate, status, setup, renew"
            return 1
            ;;
    esac
}

cmd_cleanup() {
    log "INFO" "🧹 Cleaning up Docker resources..."
    docker_clean_system "$@"
}

cmd_shell() {
    local service="${1:-app}"
    log "INFO" "🐚 Opening shell to $service..."
    docker_shell "$service"
}

cmd_user_status() {
    log "INFO" "👤 Checking user status..."
    show_user_info
}

cmd_create_user() {
    log "INFO" "👤 Creating milou user..."
    create_milou_user
}

cmd_security_check() {
    log "INFO" "🔒 Running security check..."
    show_milou_status
}

cmd_install_deps() {
    log "INFO" "📦 Installing dependencies..."
    milou_install_prerequisites
}

cmd_build_images() {
    log "INFO" "🔨 Building Docker images..."
    docker_build_images "$@"
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

parse_arguments() {
    local remaining_args=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose)
                VERBOSE=true
                export LOG_LEVEL="DEBUG"
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
                    log "DEBUG" "Token parsed from arguments: length=${#GITHUB_TOKEN}"
                    shift 2
                else
                    log "ERROR" "GitHub token value is required after --token"
                    return 1
                fi
                ;;
            --domain)
                if [[ -n "${2:-}" ]]; then
                    DOMAIN="$2"
                    export DOMAIN
                    shift 2
                else
                    log "ERROR" "Domain value is required after --domain"
                    return 1
                fi
                ;;
            --ssl-path)
                if [[ -n "${2:-}" ]]; then
                    SSL_PATH="$2"
                    export SSL_PATH
                    shift 2
                else
                    log "ERROR" "SSL path value is required after --ssl-path"
                    return 1
                fi
                ;;
            --email)
                if [[ -n "${2:-}" ]]; then
                    EMAIL="$2"
                    export EMAIL
                    shift 2
                else
                    log "ERROR" "Email value is required after --email"
                    return 1
                fi
                ;;
            --latest)
                USE_LATEST=true
                export USE_LATEST
                shift
                ;;
            --fixed-version)
                USE_LATEST=false
                export USE_LATEST
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
                export FRESH_INSTALL
                shift
                ;;
            --dev)
                DEV_MODE=true
                export DEV_MODE
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            -*)
                log "ERROR" "Unknown option: $1"
                return 1
                ;;
            *)
                remaining_args+=("$1")
                shift
                ;;
        esac
    done
    
    # Return remaining arguments
    printf '%s\n' "${remaining_args[@]}"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    # Parse arguments and get command
    local remaining_args
    mapfile -t remaining_args < <(parse_arguments "$@")
    
    local command="${remaining_args[0]:-help}"
    local args=("${remaining_args[@]:1}")
    
    log "DEBUG" "Milou CLI v$SCRIPT_VERSION started"
    log "DEBUG" "Command: $command, User: $(whoami), PID: $$"
    log "DEBUG" "Working directory: $(pwd)"
    
    # Handle resumption after user switch
    if [[ -n "${MILOU_RESUMED:-}" ]]; then
        log "DEBUG" "Resuming operation after user switch"
        unset MILOU_RESUMED
        
        # Re-parse original arguments if available
        if [[ -n "${ORIGINAL_ARGUMENTS_STR:-}" ]]; then
            log "DEBUG" "Re-parsing original arguments: $ORIGINAL_ARGUMENTS_STR"
            
            # Convert string back to array
            local original_args_array
            IFS=' ' read -ra original_args_array <<< "$ORIGINAL_ARGUMENTS_STR"
            
            # Re-parse arguments
            mapfile -t remaining_args < <(parse_arguments "${original_args_array[@]}")
            command="${remaining_args[0]:-help}"
            args=("${remaining_args[@]:1}")
        fi
    else
        # First run - preserve arguments for potential user switching
        preserve_arguments "$command" "${args[@]}"
        
        # Create arguments string for user switching
        ORIGINAL_ARGUMENTS_STR=""
        for arg in "${ORIGINAL_ARGUMENTS[@]}"; do
            if [[ "$arg" =~ [[:space:]] ]]; then
                ORIGINAL_ARGUMENTS_STR+="\"$arg\" "
            else
                ORIGINAL_ARGUMENTS_STR+="$arg "
            fi
        done
        ORIGINAL_ARGUMENTS_STR="${ORIGINAL_ARGUMENTS_STR% }"  # Remove trailing space
        export ORIGINAL_ARGUMENTS_STR
        
        log "DEBUG" "Resumed with command: $command, verbose: $VERBOSE, remaining args: ${#remaining_args[@]}"
    fi
    
    # Initialize modules
    users_init
    docker_init
    
    log "DEBUG" "Before command routing: GITHUB_TOKEN=${GITHUB_TOKEN:-NOT_SET} (length: ${#GITHUB_TOKEN})"
    
    # Route to command handlers
    case "$command" in
        "setup")
            cmd_setup "${args[@]}"
            ;;
        "start")
            cmd_start "${args[@]}"
            ;;
        "stop")
            cmd_stop "${args[@]}"
            ;;
        "restart")
            cmd_restart "${args[@]}"
            ;;
        "status")
            cmd_status "${args[@]}"
            ;;
        "logs")
            cmd_logs "${args[@]}"
            ;;
        "health")
            cmd_health "${args[@]}"
            ;;
        "config")
            cmd_config "${args[@]}"
            ;;
        "validate")
            cmd_validate "${args[@]}"
            ;;
        "backup")
            cmd_backup "${args[@]}"
            ;;
        "restore")
            cmd_restore "${args[@]}"
            ;;
        "update")
            cmd_update "${args[@]}"
            ;;
        "ssl")
            cmd_ssl "${args[@]}"
            ;;
        "cleanup")
            cmd_cleanup "${args[@]}"
            ;;
        "shell")
            cmd_shell "${args[@]}"
            ;;
        "user-status")
            cmd_user_status "${args[@]}"
            ;;
        "create-user")
            cmd_create_user "${args[@]}"
            ;;
        "security-check")
            cmd_security_check "${args[@]}"
            ;;
        "install-deps")
            cmd_install_deps "${args[@]}"
            ;;
        "build-images")
            cmd_build_images "${args[@]}"
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            log "ERROR" "Unknown command: $command"
            log "INFO" "Use 'milou help' to see available commands"
            exit 1
            ;;
    esac
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Set up error handling and cleanup
cleanup() {
    local exit_code=$?
    log "DEBUG" "Script execution completed with exit code: $exit_code"
    exit $exit_code
}

# Set up signal handlers
trap cleanup EXIT
trap 'log "WARN" "Script interrupted by user"; exit 130' INT TERM

# Execute main function with all arguments
main "$@" 