#!/bin/bash

set -e

# Constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="1.0.0"
CONFIG_DIR="${HOME}/.milou"
ENV_FILE="${SCRIPT_DIR}/.env"
BACKUP_DIR="${CONFIG_DIR}/backups"
DEFAULT_SSL_PATH="./ssl"

# Source utility functions
source "${SCRIPT_DIR}/utils/configure.sh"
source "${SCRIPT_DIR}/utils/docker.sh"
source "${SCRIPT_DIR}/utils/ssl.sh"
source "${SCRIPT_DIR}/utils/backup.sh"
source "${SCRIPT_DIR}/utils/update.sh"
source "${SCRIPT_DIR}/utils/utils.sh"

# Create config directory if it doesn't exist
mkdir -p "${CONFIG_DIR}"
mkdir -p "${BACKUP_DIR}"

# Print usage information
function show_usage() {
    echo "Milou Management CLI v${VERSION}"
    echo ""
    echo "Usage: $(basename "$0") [command] [options]"
    echo ""
    echo "Commands:"
    echo "  setup             Initial setup and configuration"
    echo "  start             Start all services"
    echo "  stop              Stop all services"
    echo "  restart           Restart all services"
    echo "  status            Show status of services"
    echo "  backup            Create a backup"
    echo "  restore [file]    Restore from a backup file"
    echo "  update            Update to the latest version"
    echo "  logs [service]    View logs for all or specific service"
    echo "  cert              Manage SSL certificates"
    echo "  config            View or edit configuration"
    echo "  help              Show this help message"
    echo ""
    echo "Options:"
    echo "  --token VALUE     GitHub Personal Access Token for authentication"
    echo "  --ssl-path PATH   Path to SSL certificates directory (default: ${DEFAULT_SSL_PATH})"
    echo "  --domain DOMAIN   Domain name for the installation"
    echo "  --force           Force operation without confirmation"
    echo "  --verbose         Show detailed output"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") setup --token ghp_1234abcd... --domain example.com"
    echo "  $(basename "$0") start"
    echo "  $(basename "$0") cert --ssl-path /path/to/certificates"
    echo ""
    echo "For SSL certificates, simply place these files in your SSL directory:"
    echo "  - milou.crt: Your SSL certificate"
    echo "  - milou.key: Your private key"
    echo ""
}

# Command handlers
function handle_setup() {
    echo "Setting up Milou..."
    
    # Parse setup-specific arguments
    local github_token=""
    local domain="localhost"
    local ssl_path="${DEFAULT_SSL_PATH}"
    local force=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --token)
                github_token="$2"
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
            *)
                shift
                ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "$github_token" ]]; then
        echo "Error: GitHub token is required for setup."
        echo "Use --token to provide a GitHub Personal Access Token."
        exit 1
    fi
    
    # Login to GitHub Container Registry
    echo "Authenticating with GitHub Container Registry..."
    echo "${github_token}" | docker login ghcr.io -u "token" --password-stdin || {
        echo "Error: Failed to authenticate with GitHub Container Registry."
        exit 1
    }
    
    # Generate configuration
    echo "Generating configuration..."
    generate_config "${domain}" "${ssl_path}"
    
    # Set up SSL certificates
    echo "Setting up SSL certificates..."
    setup_ssl "${ssl_path}" "${domain}"
    
    # Pull Docker images
    echo "Pulling Docker images..."
    pull_images "${github_token}"
    
    # Start services
    if [[ "$force" == true ]] || confirm "Start services now?"; then
        start_services
        echo "Setup complete! Milou is now running."
        echo "Access your instance at: https://${domain}"
    else
        echo "Setup complete! Start services with: ./milou.sh start"
    fi
}

function handle_start() {
    echo "Starting Milou services..."
    start_services
}

function handle_stop() {
    echo "Stopping Milou services..."
    stop_services
}

function handle_restart() {
    echo "Restarting Milou services..."
    restart_services
}

function handle_status() {
    echo "Checking service status..."
    check_service_status
}

function handle_backup() {
    echo "Creating backup..."
    create_backup
}

function handle_restore() {
    local backup_file="$1"
    if [[ -z "$backup_file" ]]; then
        echo "Error: Backup file path is required."
        echo "Usage: $(basename "$0") restore [backup_file]"
        exit 1
    fi
    
    echo "Restoring from backup: $backup_file"
    restore_backup "$backup_file"
}

function handle_update() {
    echo "Checking for updates..."
    update_milou
}

function handle_logs() {
    local service="$1"
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
    
    echo "Managing SSL certificates..."
    setup_ssl "${ssl_path}" "${domain}"
    
    # Show certificate info if it exists
    if [ -f "${ssl_path}/milou.crt" ]; then
        check_ssl_expiration
    fi
}

function handle_config() {
    echo "Current configuration:"
    cat "${ENV_FILE}"
}

# Main command handler
if [[ $# -eq 0 ]]; then
    show_usage
    exit 0
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed. Please install Docker before running this script."
    exit 1
fi

# Check if Docker Compose plugin is installed
if ! docker compose version &> /dev/null; then
    echo "Error: Docker Compose plugin is not installed. Please install the Docker Compose plugin."
    exit 1
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
        handle_backup
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
    help|--help|-h)
        show_usage
        ;;
    *)
        echo "Error: Unknown command '$COMMAND'"
        show_usage
        exit 1
        ;;
esac

exit 0
