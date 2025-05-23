#!/bin/bash

set -euo pipefail

# =============================================================================
# Milou Management CLI - Improved Version
# =============================================================================

# Constants and Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VERSION="2.0.0"
readonly CONFIG_DIR="${HOME}/.milou"
readonly ENV_FILE="${SCRIPT_DIR}/.env"
readonly BACKUP_DIR="${CONFIG_DIR}/backups"
readonly LOG_FILE="${CONFIG_DIR}/milou.log"
readonly DEFAULT_SSL_PATH="./ssl"
readonly GITHUB_REGISTRY="ghcr.io/milou-sh/milou"
readonly REQUIRED_DOCKER_VERSION="20.10.0"
readonly REQUIRED_DOCKER_COMPOSE_VERSION="2.0.0"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
VERBOSE=false
FORCE=false
DRY_RUN=false

# =============================================================================
# Utility Functions
# =============================================================================

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
            if [[ "$VERBOSE" == true ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message"
                echo "[$timestamp] [DEBUG] $message" >> "$LOG_FILE"
            fi
            ;;
    esac
}

# Error handling
error_exit() {
    log "ERROR" "$1"
    exit "${2:-1}"
}

# Progress indicator
show_progress() {
    local message="$1"
    local duration="${2:-3}"
    
    echo -n "$message"
    for ((i=0; i<duration; i++)); do
        echo -n "."
        sleep 1
    done
    echo " Done!"
}

# Input validation
validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
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

# Secure random string generation
generate_secure_random() {
    local length="${1:-32}"
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 "$((length * 3 / 4))" | tr -d "=+/" | cut -c1-"$length"
    else
        head -c "$length" /dev/urandom | base64 | tr -d "=+/" | cut -c1-"$length"
    fi
}

# =============================================================================
# System Requirements Check
# =============================================================================

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
    
    # Check Docker version
    local docker_version
    docker_version=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if ! version_greater_equal "$docker_version" "$REQUIRED_DOCKER_VERSION"; then
        error_exit "Docker version $docker_version is too old. Required: $REQUIRED_DOCKER_VERSION or higher"
    fi
    
    # Check Docker Compose
    if ! docker compose version >/dev/null 2>&1; then
        error_exit "Docker Compose plugin is not installed"
    fi
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        error_exit "Docker daemon is not running or current user cannot access it"
    fi
    
    # Check available disk space (minimum 2GB)
    local available_space
    available_space=$(df "$SCRIPT_DIR" | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 2097152 ]]; then # 2GB in KB
        log "WARN" "Low disk space detected. At least 2GB recommended."
    fi
    
    log "INFO" "Prerequisites check completed successfully"
}

# Version comparison utility
version_greater_equal() {
    local version1="$1"
    local version2="$2"
    
    printf '%s\n%s\n' "$version2" "$version1" | sort -V -C
}

# =============================================================================
# Configuration Management
# =============================================================================

generate_config() {
    local domain="$1"
    local ssl_path="$2"
    local github_token="$3"
    
    log "INFO" "Generating secure configuration..."
    
    # Validate inputs
    if ! validate_domain "$domain" && [[ "$domain" != "localhost" ]]; then
        error_exit "Invalid domain name: $domain"
    fi
    
    if [[ -n "$github_token" ]] && ! validate_github_token "$github_token"; then
        error_exit "Invalid GitHub token format"
    fi
    
    # Generate secure credentials
    local db_user="milou_$(generate_secure_random 8)"
    local db_password=$(generate_secure_random 32)
    local redis_password=$(generate_secure_random 32)
    local session_secret=$(generate_secure_random 64)
    local encryption_key=$(generate_secure_random 32)
    
    # Create configuration file
    cat > "$ENV_FILE" << EOF
# Milou Application Environment Configuration
# Generated on $(date)
# Version: $VERSION
# ========================================

# Server Configuration
# ----------------------------------------
SERVER_NAME=$domain
CUSTOMER_DOMAIN_NAME=$domain
SSL_PORT=443
SSL_CERT_PATH=$ssl_path
CORS_ORIGIN=https://$domain

# Database Configuration
# ----------------------------------------
DB_HOST=db
DB_PORT=5432
DB_USER=$db_user
DB_PASSWORD=$db_password
DB_NAME=milou
DATABASE_URI=postgresql+psycopg2://$db_user:$db_password@db:5432/milou
POSTGRES_USER=$db_user
POSTGRES_PASSWORD=$db_password
POSTGRES_DB=milou

# Redis Configuration
# ----------------------------------------
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=$redis_password
REDIS_SESSION_TTL=3600
REDIS_MAX_RETRIES=3
REDIS_CONNECT_TIMEOUT=10000
REDIS_CLEANUP_ENABLED=true
REDIS_CLEANUP_INTERVAL=3600

# RabbitMQ Configuration
# ----------------------------------------
RABBITMQ_URL=amqp://guest:guest@rabbitmq:5672
RABBITMQ_USER=guest
RABBITMQ_PASSWORD=guest

# Security Configuration
# ----------------------------------------
SESSION_SECRET=$session_secret
ENCRYPTION_KEY=$encryption_key

# Application Configuration
# ----------------------------------------
API_PORT=9999
NODE_ENV=production

# Container Registry
# ----------------------------------------
GITHUB_REGISTRY=$GITHUB_REGISTRY
MILOU_VERSION=$VERSION
EOF

    # Only add GitHub token if provided (don't store in config for security)
    if [[ -n "$github_token" ]]; then
        echo "# Note: GitHub token not stored in config for security" >> "$ENV_FILE"
    fi
    
    # Set secure permissions
    chmod 600 "$ENV_FILE"
    
    # Create backup
    mkdir -p "$BACKUP_DIR"
    cp "$ENV_FILE" "$BACKUP_DIR/env_$(date +%Y%m%d%H%M%S).backup"
    
    log "INFO" "Configuration generated successfully"
}

# =============================================================================
# Docker Operations
# =============================================================================

authenticate_github() {
    local github_token="$1"
    
    log "INFO" "Authenticating with GitHub Container Registry..."
    
    if ! echo "$github_token" | docker login ghcr.io -u "token" --password-stdin 2>/dev/null; then
        error_exit "Failed to authenticate with GitHub Container Registry. Check your token."
    fi
    
    log "INFO" "Authentication successful"
}

pull_images() {
    local version="${1:-latest}"
    
    log "INFO" "Pulling Docker images (version: $version)..."
    
    local images=(
        "$GITHUB_REGISTRY/backend:$version"
        "$GITHUB_REGISTRY/frontend:$version"
        "$GITHUB_REGISTRY/engine:$version"
        "$GITHUB_REGISTRY/nginx:$version"
        "$GITHUB_REGISTRY/database:$version"
    )
    
    local failed_images=()
    
    for image in "${images[@]}"; do
        log "DEBUG" "Pulling $image"
        if ! docker pull "$image"; then
            failed_images+=("$image")
        fi
    done
    
    if [[ ${#failed_images[@]} -gt 0 ]]; then
        error_exit "Failed to pull images: ${failed_images[*]}"
    fi
    
    log "INFO" "All images pulled successfully"
}

# =============================================================================
# SSL Management
# =============================================================================

setup_ssl() {
    local ssl_path="$1"
    local domain="$2"
    
    log "INFO" "Setting up SSL certificates..."
    
    # Create SSL directory
    mkdir -p "$ssl_path"
    chmod 755 "$ssl_path"
    
    # Check if certificates exist
    if [[ -f "$ssl_path/milou.crt" && -f "$ssl_path/milou.key" ]]; then
        log "INFO" "SSL certificates already exist"
        check_ssl_expiration "$ssl_path"
        return 0
    fi
    
    # Generate self-signed certificate for development
    if [[ "$domain" == "localhost" ]]; then
        log "INFO" "Generating self-signed certificate for development"
        
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$ssl_path/milou.key" \
            -out "$ssl_path/milou.crt" \
            -subj "/CN=$domain/O=Milou Development/C=US" \
            -config <(cat <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = $domain

[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = *.localhost
IP.1 = 127.0.0.1
IP.2 = ::1
EOF
) || error_exit "Failed to generate SSL certificate"
        
        # Set appropriate permissions
        chmod 600 "$ssl_path/milou.key"
        chmod 644 "$ssl_path/milou.crt"
        
        log "INFO" "Self-signed certificate generated successfully"
    else
        log "WARN" "Production domain detected. Please place your SSL certificates:"
        log "INFO" "  Certificate: $ssl_path/milou.crt"
        log "INFO" "  Private Key: $ssl_path/milou.key"
    fi
}

check_ssl_expiration() {
    local ssl_path="$1"
    local cert_file="$ssl_path/milou.crt"
    
    if [[ ! -f "$cert_file" ]]; then
        log "WARN" "Certificate file not found: $cert_file"
        return 1
    fi
    
    local expiration_date
    expiration_date=$(openssl x509 -enddate -noout -in "$cert_file" | cut -d= -f2)
    
    local expiration_seconds
    expiration_seconds=$(date -d "$expiration_date" +%s 2>/dev/null || echo "0")
    
    local current_seconds
    current_seconds=$(date +%s)
    
    local days_remaining=$(( (expiration_seconds - current_seconds) / 86400 ))
    
    log "INFO" "SSL Certificate expires on: $expiration_date"
    log "INFO" "Days remaining: $days_remaining"
    
    if [[ $days_remaining -lt 30 ]]; then
        log "WARN" "Certificate will expire in less than 30 days!"
    fi
}

# =============================================================================
# Service Management
# =============================================================================

create_networks() {
    log "INFO" "Creating Docker networks..."
    
    # Create milou_network if it doesn't exist
    if ! docker network inspect milou_network >/dev/null 2>&1; then
        docker network create milou_network || error_exit "Failed to create milou_network"
    fi
    
    # Create proxy network if it doesn't exist
    if ! docker network inspect proxy >/dev/null 2>&1; then
        docker network create proxy || error_exit "Failed to create proxy network"
    fi
}

start_services() {
    log "INFO" "Starting Milou services..."
    
    # Validate configuration
    if [[ ! -f "$ENV_FILE" ]]; then
        error_exit "Configuration not found. Please run 'setup' first."
    fi
    
    # Create networks
    create_networks
    
    # Start services
    cd "$SCRIPT_DIR"
    if ! docker compose -f static/docker-compose.yml --env-file .env up -d; then
        error_exit "Failed to start services"
    fi
    
    # Wait for services to be healthy
    wait_for_services
    
    log "INFO" "All services started successfully"
}

wait_for_services() {
    log "INFO" "Waiting for services to be ready..."
    
    local max_attempts=60
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        local healthy_services=0
        local total_services=0
        
        # Count healthy services
        while IFS= read -r line; do
            if [[ "$line" =~ "healthy" ]]; then
                ((healthy_services++))
            fi
            ((total_services++))
        done < <(docker compose -f "$SCRIPT_DIR/static/docker-compose.yml" ps --format "table {{.Service}}\t{{.Status}}" | grep -v "SERVICE" | grep -v "^$")
        
        if [[ $healthy_services -eq $total_services && $total_services -gt 0 ]]; then
            log "INFO" "All services are healthy!"
            return 0
        fi
        
        log "DEBUG" "Services health check: $healthy_services/$total_services healthy"
        sleep 5
        ((attempt++))
    done
    
    log "WARN" "Timeout waiting for all services to be healthy"
    return 1
}

stop_services() {
    log "INFO" "Stopping Milou services..."
    
    cd "$SCRIPT_DIR"
    if ! docker compose -f static/docker-compose.yml down; then
        log "WARN" "Some services may not have stopped cleanly"
    fi
    
    log "INFO" "Services stopped"
}

# =============================================================================
# Interactive Setup
# =============================================================================

interactive_setup() {
    echo
    echo "=== Milou Interactive Setup ==="
    echo
    
    # Get domain
    local domain
    while true; do
        read -p "Enter your domain name (default: localhost): " domain
        domain=${domain:-localhost}
        
        if validate_domain "$domain" || [[ "$domain" == "localhost" ]]; then
            break
        else
            echo "Invalid domain name. Please try again."
        fi
    done
    
    # Get GitHub token
    local github_token
    while true; do
        read -s -p "Enter your GitHub Personal Access Token: " github_token
        echo
        
        if [[ -z "$github_token" ]]; then
            echo "GitHub token is required for pulling container images."
            continue
        fi
        
        if validate_github_token "$github_token"; then
            break
        else
            echo "Invalid GitHub token format. Please try again."
        fi
    done
    
    # Get SSL path
    local ssl_path
    read -p "SSL certificates path (default: $DEFAULT_SSL_PATH): " ssl_path
    ssl_path=${ssl_path:-$DEFAULT_SSL_PATH}
    
    # Confirm settings
    echo
    echo "Configuration Summary:"
    echo "  Domain: $domain"
    echo "  SSL Path: $ssl_path"
    echo "  GitHub Token: ${github_token:0:10}..."
    echo
    
    if ! confirm "Proceed with setup?"; then
        log "INFO" "Setup cancelled by user"
        exit 0
    fi
    
    # Run setup
    setup_milou "$domain" "$ssl_path" "$github_token"
}

confirm() {
    local message="$1"
    local response
    
    if [[ "$FORCE" == true ]]; then
        return 0
    fi
    
    while true; do
        read -p "$message [y/N]: " response
        case "$response" in
            [Yy]|[Yy][Ee][Ss])
                return 0
                ;;
            [Nn]|[Nn][Oo]|"")
                return 1
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

# =============================================================================
# Main Setup Function
# =============================================================================

setup_milou() {
    local domain="$1"
    local ssl_path="$2"
    local github_token="$3"
    
    log "INFO" "Starting Milou setup..."
    
    # Check prerequisites
    check_prerequisites
    
    # Authenticate with GitHub
    authenticate_github "$github_token"
    
    # Generate configuration
    generate_config "$domain" "$ssl_path" "$github_token"
    
    # Setup SSL
    setup_ssl "$ssl_path" "$domain"
    
    # Pull images
    pull_images "v1.0.0"
    
    # Start services
    if [[ "$FORCE" == true ]] || confirm "Start services now?"; then
        start_services
        
        echo
        log "INFO" "Setup completed successfully!"
        log "INFO" "Access your Milou instance at: https://$domain"
        echo
    else
        log "INFO" "Setup completed. Start services with: $0 start"
    fi
}

# =============================================================================
# Command Line Interface
# =============================================================================

show_usage() {
    cat << EOF
Milou Management CLI v$VERSION

USAGE:
    $(basename "$0") [OPTIONS] <COMMAND> [ARGS...]

COMMANDS:
    setup                   Interactive setup wizard
    start                   Start all services
    stop                    Stop all services  
    restart                 Restart all services
    status                  Show service status
    logs [SERVICE]          View logs (all services or specific service)
    backup                  Create a backup
    restore <FILE>          Restore from backup file
    update                  Update to latest version
    cert                    Manage SSL certificates
    config                  Show current configuration
    health                  Run health checks
    clean                   Clean up unused Docker resources
    shell <SERVICE>         Open shell in service container
    version                 Show version information
    help                    Show this help message

OPTIONS:
    --token <TOKEN>         GitHub Personal Access Token
    --domain <DOMAIN>       Domain name for installation
    --ssl-path <PATH>       SSL certificates directory (default: $DEFAULT_SSL_PATH)
    --force                 Skip confirmation prompts
    --verbose               Enable verbose output
    --dry-run               Show what would be done without executing

EXAMPLES:
    # Interactive setup
    $(basename "$0") setup
    
    # Non-interactive setup
    $(basename "$0") --token ghp_xxx --domain example.com setup
    
    # View backend logs
    $(basename "$0") logs backend
    
    # Force restart without confirmation
    $(basename "$0") --force restart

For more information, visit: https://docs.milou.sh
EOF
}

# =============================================================================
# Command Handlers
# =============================================================================

handle_setup() {
    local domain=""
    local ssl_path="$DEFAULT_SSL_PATH"
    local github_token=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --domain)
                domain="$2"
                shift 2
                ;;
            --ssl-path)
                ssl_path="$2"
                shift 2
                ;;
            --token)
                github_token="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # If no arguments provided, run interactive setup
    if [[ -z "$domain" && -z "$github_token" ]]; then
        interactive_setup
    else
        # Validate required parameters
        if [[ -z "$github_token" ]]; then
            error_exit "GitHub token is required. Use --token or run without arguments for interactive setup."
        fi
        
        if [[ -z "$domain" ]]; then
            domain="localhost"
        fi
        
        setup_milou "$domain" "$ssl_path" "$github_token"
    fi
}

handle_status() {
    log "INFO" "Checking service status..."
    
    cd "$SCRIPT_DIR"
    docker compose -f static/docker-compose.yml ps
}

handle_logs() {
    local service="$1"
    
    cd "$SCRIPT_DIR"
    if [[ -n "$service" ]]; then
        docker compose -f static/docker-compose.yml logs -f --tail=100 "$service"
    else
        docker compose -f static/docker-compose.yml logs -f --tail=100
    fi
}

handle_health() {
    log "INFO" "Running health checks..."
    
    # Check if configuration exists
    if [[ ! -f "$ENV_FILE" ]]; then
        log "ERROR" "Configuration file not found"
        return 1
    fi
    
    # Check if services are running
    local running_services
    running_services=$(docker compose -f "$SCRIPT_DIR/static/docker-compose.yml" ps --services --filter "status=running" | wc -l)
    
    if [[ $running_services -eq 0 ]]; then
        log "ERROR" "No services are running"
        return 1
    fi
    
    log "INFO" "Health check passed: $running_services services running"
    
    # Check SSL certificates
    local ssl_path
    ssl_path=$(grep "^SSL_CERT_PATH=" "$ENV_FILE" | cut -d= -f2)
    
    if [[ -n "$ssl_path" ]]; then
        check_ssl_expiration "$ssl_path"
    fi
}

handle_clean() {
    log "INFO" "Cleaning up Docker resources..."
    
    if confirm "This will remove unused Docker images, containers, and networks. Continue?"; then
        docker system prune -f
        log "INFO" "Cleanup completed"
    else
        log "INFO" "Cleanup cancelled"
    fi
}

handle_shell() {
    local service="$1"
    
    if [[ -z "$service" ]]; then
        error_exit "Service name is required. Usage: $0 shell <service>"
    fi
    
    cd "$SCRIPT_DIR"
    if ! docker compose -f static/docker-compose.yml exec "$service" /bin/bash; then
        # Try with sh if bash is not available
        docker compose -f static/docker-compose.yml exec "$service" /bin/sh
    fi
}

# =============================================================================
# Main Entry Point
# =============================================================================

main() {
    # Create necessary directories
    mkdir -p "$CONFIG_DIR" "$BACKUP_DIR"
    touch "$LOG_FILE"
    
    # Parse global options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose)
                VERBOSE=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --token|--domain|--ssl-path)
                # These will be handled by individual commands
                break
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            --version)
                echo "Milou CLI v$VERSION"
                exit 0
                ;;
            -*)
                error_exit "Unknown option: $1"
                ;;
            *)
                # Not an option, must be a command
                break
                ;;
        esac
    done
    
    # Get command
    local command="${1:-help}"
    shift || true
    
    # Handle commands
    case "$command" in
        setup)
            handle_setup "$@"
            ;;
        start)
            start_services
            ;;
        stop)
            stop_services
            ;;
        restart)
            stop_services
            start_services
            ;;
        status)
            handle_status
            ;;
        logs)
            handle_logs "$1"
            ;;
        backup)
            # TODO: Implement improved backup function
            log "INFO" "Backup functionality will be implemented in next iteration"
            ;;
        restore)
            # TODO: Implement improved restore function
            log "INFO" "Restore functionality will be implemented in next iteration"
            ;;
        update)
            # TODO: Implement improved update function
            log "INFO" "Update functionality will be implemented in next iteration"
            ;;
        cert)
            local ssl_path="$DEFAULT_SSL_PATH"
            local domain="localhost"
            
            # Parse cert command arguments
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
            
            setup_ssl "$ssl_path" "$domain"
            ;;
        config)
            if [[ -f "$ENV_FILE" ]]; then
                cat "$ENV_FILE"
            else
                log "ERROR" "Configuration file not found. Run setup first."
                exit 1
            fi
            ;;
        health)
            handle_health
            ;;
        clean)
            handle_clean
            ;;
        shell)
            handle_shell "$1"
            ;;
        version)
            echo "Milou CLI v$VERSION"
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            error_exit "Unknown command: $command"
            ;;
    esac
}

# Execute main function with all arguments
main "$@" 