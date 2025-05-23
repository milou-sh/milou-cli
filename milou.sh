#!/bin/bash

set -euo pipefail

# Constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="1.1.0"
CONFIG_DIR="${HOME}/.milou"
ENV_FILE="${SCRIPT_DIR}/.env"
BACKUP_DIR="${CONFIG_DIR}/backups"
DEFAULT_SSL_PATH="./ssl"
LOG_FILE="${CONFIG_DIR}/milou.log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Source utility functions
source "${SCRIPT_DIR}/utils/configure.sh"
source "${SCRIPT_DIR}/utils/docker.sh"
source "${SCRIPT_DIR}/utils/ssl.sh"
source "${SCRIPT_DIR}/utils/backup.sh"
source "${SCRIPT_DIR}/utils/update.sh"
source "${SCRIPT_DIR}/utils/utils.sh"
source "${SCRIPT_DIR}/utils/setup_wizard.sh"

# Create config directory if it doesn't exist
mkdir -p "${CONFIG_DIR}"
mkdir -p "${BACKUP_DIR}"
touch "${LOG_FILE}"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" >&2
            echo "[$timestamp] [ERROR] $message" >> "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" >&2
            echo "[$timestamp] [WARN] $message" >> "$LOG_FILE"
            ;;
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message"
            echo "[$timestamp] [INFO] $message" >> "$LOG_FILE"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message"
            echo "[$timestamp] [DEBUG] $message" >> "$LOG_FILE"
            ;;
    esac
}

# Input validation functions
validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]] && [[ "$domain" != "localhost" ]]; then
        return 1
    fi
    return 0
}

validate_github_token() {
    local token="$1"
    if [[ ! "$token" =~ ^gh[pousr]_[A-Za-z0-9_]{36,251}$ ]]; then
        return 1
    fi
    return 0
}

# Error handling
error_exit() {
    log "ERROR" "$1"
    exit "${2:-1}"
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking system prerequisites..."
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        error_exit "This script should not be run as root for security reasons"
    fi
    
    # Check Docker installation
    if ! command -v docker >/dev/null 2>&1; then
        error_exit "Docker is not installed. Please install Docker first."
    fi
    
    # Check Docker Compose
    if ! docker compose version >/dev/null 2>&1; then
        error_exit "Docker Compose plugin is not installed"
    fi
    
    log "INFO" "Prerequisites check completed"
}

# Print usage information
function show_usage() {
    echo "Milou Management CLI v${VERSION}"
    echo ""
    echo "Usage: $(basename "$0") [command] [options]"
    echo ""
    echo "Commands:"
    echo "  setup             Interactive setup wizard (recommended for first-time setup)"
    echo "  start             Start all services"
    echo "  stop              Stop all services"
    echo "  restart           Restart all services"
    echo "  status            Show status of services"
    echo "  backup            Create a backup"
    echo "    --type TYPE     Backup type (full|config) [default: full]"
    echo "    --config-only   Create configuration-only backup"  
    echo "    --list          List available backups"
    echo "    --clean [DAYS]  Clean old backups (default: 30 days)"
    echo "  restore [file]    Restore from a backup file"
    echo "  update            Update to the latest version"
    echo "  logs [service]    View logs for all or specific service"
    echo "  cert              Manage SSL certificates"
    echo "  config            View or edit configuration"
    echo "  health            Run health checks"
    echo "  help              Show this help message"
    echo ""
    echo "Options:"
    echo "  --token VALUE     GitHub Personal Access Token for authentication"
    echo "  --ssl-path PATH   Path to SSL certificates directory (default: ${DEFAULT_SSL_PATH})"
    echo "  --domain DOMAIN   Domain name for the installation"
    echo "  --force           Force operation without confirmation"
    echo "  --verbose         Show detailed output"
    echo "  --non-interactive Run setup without interactive prompts"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") setup                    # Interactive setup wizard (recommended)"
    echo "  $(basename "$0") setup --token ghp_1234abcd... --domain example.com  # Non-interactive"
    echo "  $(basename "$0") start"
    echo "  $(basename "$0") cert --ssl-path /path/to/certificates"
    echo ""
    echo "For SSL certificates, simply place these files in your SSL directory:"
    echo "  - milou.crt: Your SSL certificate"
    echo "  - milou.key: Your private key"
    echo ""
    echo "SECURITY NOTE: Never store GitHub tokens in configuration files!"
    echo "Always pass tokens via command line arguments."
    echo ""
}

# Command handlers
function handle_setup() {
    log "INFO" "Starting Milou setup..."
    
    # Parse setup-specific arguments
    local github_token=""
    local domain="localhost"
    local ssl_path="${DEFAULT_SSL_PATH}"
    local force=false
    local interactive=true
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --token)
                github_token="$2"
                interactive=false
                shift 2
                ;;
            --domain)
                domain="$2"
                shift 2
                ;;
            --ssl-path)
                ssl_path="$2"
                shift 2
                ;;
            --force)
                force=true
                shift
                ;;
            --non-interactive)
                interactive=false
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # If no token provided and not interactive, show help
    if [[ -z "$github_token" && "$interactive" == "false" ]]; then
        error_exit "GitHub token is required for non-interactive setup. Use --token to provide a GitHub Personal Access Token."
    fi
    
    # Run interactive setup if no arguments provided or interactive mode requested
    if [[ "$interactive" == "true" && -z "$github_token" ]]; then
        interactive_setup
        return $?
    fi
    
    # Non-interactive setup (original functionality)
    log "INFO" "Running non-interactive setup..."
    
    # Check prerequisites first
    check_prerequisites
    
    # Validate GitHub token format
    if ! validate_github_token "$github_token"; then
        error_exit "Invalid GitHub token format. Token should start with 'ghp_', 'gho_', 'ghu_', 'ghs_', or 'ghr_'."
    fi
    
    # Validate domain
    if ! validate_domain "$domain"; then
        error_exit "Invalid domain name: $domain"
    fi
    
    # Validate SSL path
    if [[ ! -d "$(dirname "$ssl_path")" ]]; then
        error_exit "SSL path directory does not exist: $(dirname "$ssl_path")"
    fi
    
    log "INFO" "Configuration validated successfully"
    
    # Login to GitHub Container Registry
    log "INFO" "Authenticating with GitHub Container Registry..."
    if ! echo "${github_token}" | docker login ghcr.io -u "token" --password-stdin 2>/dev/null; then
        error_exit "Failed to authenticate with GitHub Container Registry. Please check your token."
    fi
    log "INFO" "Authentication successful"
    
    # Generate configuration
    log "INFO" "Generating secure configuration..."
    if ! generate_config "${domain}" "${ssl_path}"; then
        error_exit "Failed to generate configuration"
    fi
    
    # Set secure permissions on .env file
    chmod 600 "${ENV_FILE}" || log "WARN" "Could not set secure permissions on .env file"
    
    # Set up SSL certificates
    log "INFO" "Setting up SSL certificates..."
    if ! setup_ssl "${ssl_path}" "${domain}"; then
        error_exit "Failed to setup SSL certificates"
    fi
    
    # Pull Docker images
    log "INFO" "Pulling Docker images..."
    if ! pull_images "${github_token}"; then
        error_exit "Failed to pull Docker images"
    fi
    
    # Start services
    if [[ "$force" == true ]] || confirm "Start services now?"; then
        log "INFO" "Starting services..."
        if start_services; then
            log "INFO" "Setup complete! Milou is now running."
            log "INFO" "Access your instance at: https://${domain}"
        else
            error_exit "Failed to start services"
        fi
    else
        log "INFO" "Setup complete! Start services with: ./milou.sh start"
    fi
}

function handle_start() {
    log "INFO" "Starting Milou services..."
    if start_services; then
        log "INFO" "Services started successfully"
    else
        error_exit "Failed to start services"
    fi
}

function handle_stop() {
    log "INFO" "Stopping Milou services..."
    if stop_services; then
        log "INFO" "Services stopped successfully"
    else
        error_exit "Failed to stop services"
    fi
}

function handle_restart() {
    log "INFO" "Restarting Milou services..."
    if restart_services; then
        log "INFO" "Services restarted successfully"
    else
        error_exit "Failed to restart services"
    fi
}

function handle_status() {
    log "INFO" "Checking service status..."
    check_service_status
}

function handle_backup() {
    local backup_type="full"
    
    # Parse backup arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)
                backup_type="$2"
                shift 2
                ;;
            --config-only)
                backup_type="config"
                shift
                ;;
            --list)
                list_backups
                return $?
                ;;
            --clean)
                local days="${2:-30}"
                if [[ "$2" =~ ^[0-9]+$ ]]; then
                    shift 2
                else
                    shift
                fi
                clean_old_backups "$days"
                return $?
                ;;
            *)
                shift
                ;;
        esac
    done
    
    log "INFO" "Creating $backup_type backup..."
    if create_backup "$backup_type"; then
        log "INFO" "Backup created successfully"
    else
        error_exit "Failed to create backup"
    fi
}

function handle_restore() {
    local backup_file="$1"
    if [[ -z "$backup_file" ]]; then
        error_exit "Backup file path is required. Usage: $(basename "$0") restore [backup_file]"
    fi
    
    if [[ ! -f "$backup_file" ]]; then
        error_exit "Backup file does not exist: $backup_file"
    fi
    
    log "INFO" "Restoring from backup: $backup_file"
    if restore_backup "$backup_file"; then
        log "INFO" "Restore completed successfully"
    else
        error_exit "Failed to restore from backup"
    fi
}

function handle_update() {
    log "INFO" "Checking for updates..."
    if update_milou; then
        log "INFO" "Update completed successfully"
    else
        error_exit "Failed to update"
    fi
}

function handle_logs() {
    local service="$1"
    log "INFO" "Viewing logs for ${service:-all services}"
    view_logs "$service"
}

function handle_cert() {
    local ssl_path="${DEFAULT_SSL_PATH}"
    local domain=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ssl-path)
                ssl_path="$2"
                shift 2
                ;;
            --domain)
                domain="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    log "INFO" "Managing SSL certificates..."
    if setup_ssl "${ssl_path}" "${domain}"; then
        log "INFO" "SSL certificates setup completed"
        
        # Show certificate info if it exists
        if [ -f "${ssl_path}/milou.crt" ]; then
            check_ssl_expiration
        fi
    else
        error_exit "Failed to setup SSL certificates"
    fi
}

function handle_config() {
    if [[ -f "${ENV_FILE}" ]]; then
        log "INFO" "Current configuration:"
        cat "${ENV_FILE}"
    else
        error_exit "Configuration file not found. Please run setup first."
    fi
}

function handle_health() {
    log "INFO" "Running health checks..."
    
    # Check if configuration exists
    if [[ ! -f "${ENV_FILE}" ]]; then
        error_exit "Configuration file not found. Please run setup first."
    fi
    
    # Check if Docker is accessible
    if ! docker info >/dev/null 2>&1; then
        error_exit "Cannot access Docker daemon. Please check Docker installation and permissions."
    fi
    
    # Check if services are running
    local running_services
    if running_services=$(docker compose -f "${SCRIPT_DIR}/static/docker-compose.yml" ps --services --filter "status=running" 2>/dev/null); then
        local service_count=$(echo "$running_services" | wc -l)
        if [[ $service_count -gt 0 ]]; then
            log "INFO" "Health check passed: $service_count services running"
        else
            log "WARN" "No services are currently running"
        fi
    else
        log "WARN" "Could not check service status"
    fi
    
    log "INFO" "Health check completed"
}

# Main command handler
if [[ $# -eq 0 ]]; then
    show_usage
    exit 0
fi

# Parse command and arguments
COMMAND="$1"
shift

case "$COMMAND" in
    setup)
        handle_setup "$@"
        ;;
    start)
        handle_start
        ;;
    stop)
        handle_stop
        ;;
    restart)
        handle_restart
        ;;
    status)
        handle_status
        ;;
    backup)
        handle_backup "$@"
        ;;
    restore)
        handle_restore "$1"
        ;;
    update)
        handle_update
        ;;
    logs)
        handle_logs "$1"
        ;;
    cert)
        handle_cert "$@"
        ;;
    config)
        handle_config
        ;;
    health)
        handle_health
        ;;
    help|--help|-h)
        show_usage
        ;;
    *)
        error_exit "Unknown command '$COMMAND'. Use 'help' to see available commands."
        ;;
esac

exit 0
