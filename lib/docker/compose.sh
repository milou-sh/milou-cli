#!/bin/bash

# =============================================================================
# Centralized Docker Compose Module for Milou CLI
# Enhanced with volume management, credential detection, and advanced features
# =============================================================================

# Ensure logging is available
if ! command -v milou_log >/dev/null 2>&1; then
    source "${SCRIPT_DIR}/lib/core/logging.sh" 2>/dev/null || {
        echo "ERROR: Cannot load logging module" >&2
        exit 1
    }
fi

# Load Docker registry modules for authentication
source "${BASH_SOURCE%/*}/registry.sh" 2>/dev/null || true

# Docker environment variables
declare -g DOCKER_ENV_FILE=""
declare -g DOCKER_COMPOSE_FILE=""
declare -g DOCKER_PROJECT_NAME="static"
declare -g DOCKER_VOLUMES_CLEANED=false

# =============================================================================
# Docker Environment Initialization
# =============================================================================

# Initialize Docker Compose environment with enhanced detection
milou_docker_init() {
    local script_dir="${1:-${SCRIPT_DIR:-$(pwd)}}"
    
    milou_log "DEBUG" "Initializing Docker environment..."
    
    # Try to find environment file in multiple locations
    local env_file=""
    local -a env_search_paths=(
        "${script_dir}/.env"
        "$(pwd)/.env"
        "${PWD}/.env"
        "/home/milou/milou-cli/.env"
        "/opt/milou-cli/.env"
        "/usr/local/milou-cli/.env"
    )
    
    for path in "${env_search_paths[@]}"; do
        if [[ -f "$path" && -s "$path" ]]; then
            env_file="$path"
            break
        fi
    done
    
    if [[ -z "$env_file" ]]; then
        milou_log "ERROR" "Environment file not found in any of the search paths"
        return 1
    fi
    
    # Determine working directory from env file location
    local working_dir
    working_dir="$(dirname "$env_file")"
    
    # Change to working directory
    if [[ -d "$working_dir" ]]; then
        cd "$working_dir" || {
            milou_log "ERROR" "Cannot change to working directory: $working_dir"
            return 1
        }
    fi
    
    # Set Docker Compose file path
    local compose_file="static/docker-compose.yml"
    if [[ ! -f "$compose_file" ]]; then
        compose_file="$(pwd)/static/docker-compose.yml"
        if [[ ! -f "$compose_file" ]]; then
            milou_log "ERROR" "Docker Compose file not found: $compose_file"
            return 1
        fi
    fi
    
    # Export environment variables
    export DOCKER_ENV_FILE="$env_file"
    export DOCKER_COMPOSE_FILE="$compose_file"
    
    # Get project name from environment or use default
    local project_name
    project_name=$(grep "^COMPOSE_PROJECT_NAME=" "$env_file" 2>/dev/null | cut -d '=' -f 2- || echo "static")
    export DOCKER_PROJECT_NAME="$project_name"
    
    # Validate Docker setup
    if ! milou_docker_validate_setup; then
        return 1
    fi
    
    milou_log "DEBUG" "Docker environment initialized successfully"
    milou_log "DEBUG" "  Environment file: $DOCKER_ENV_FILE"
    milou_log "DEBUG" "  Compose file: $DOCKER_COMPOSE_FILE"
    milou_log "DEBUG" "  Working directory: $(pwd)"
    
    return 0
}

# Validate Docker setup
milou_docker_validate_setup() {
    # Check Docker access
    if ! command -v docker >/dev/null 2>&1; then
        milou_log "ERROR" "Docker is not installed or not in PATH"
        return 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        milou_log "ERROR" "Cannot connect to Docker daemon"
        return 1
    fi
    
    # Check Docker Compose file
    if [[ ! -f "$DOCKER_COMPOSE_FILE" ]]; then
        milou_log "ERROR" "Docker Compose file not found: $DOCKER_COMPOSE_FILE"
        return 1
    fi
    
    # Check environment file
    if [[ ! -f "$DOCKER_ENV_FILE" ]]; then
        milou_log "ERROR" "Docker environment file not found: $DOCKER_ENV_FILE"
        return 1
    fi
    
    return 0
}

# =============================================================================
# Docker Compose Operations
# =============================================================================

# Run Docker Compose with proper environment
milou_docker_compose() {
    # Auto-initialize if not already done
    if [[ -z "$DOCKER_ENV_FILE" || -z "$DOCKER_COMPOSE_FILE" ]]; then
        if ! milou_docker_init; then
            milou_log "ERROR" "Failed to initialize Docker environment"
            return 1
        fi
    fi
    
    # Validate files exist
    if [[ ! -f "$DOCKER_ENV_FILE" ]]; then
        milou_log "ERROR" "Environment file not found: $DOCKER_ENV_FILE"
        return 1
    fi
    
    if [[ ! -f "$DOCKER_COMPOSE_FILE" ]]; then
        milou_log "ERROR" "Compose file not found: $DOCKER_COMPOSE_FILE"
        return 1
    fi
    
    milou_log "TRACE" "Running: docker compose --env-file '$DOCKER_ENV_FILE' -f '$DOCKER_COMPOSE_FILE' $*"
    docker compose --env-file "$DOCKER_ENV_FILE" -f "$DOCKER_COMPOSE_FILE" "$@"
}

# Test Docker Compose configuration
milou_docker_test_config() {
    milou_log "DEBUG" "Testing Docker Compose configuration..."
    
    if milou_docker_compose config --quiet; then
        milou_log "SUCCESS" "Docker Compose configuration is valid"
        return 0
    else
        milou_log "ERROR" "Docker Compose configuration is invalid"
        milou_log "INFO" "💡 Check your environment file: ${DOCKER_ENV_FILE:-not set}"
        milou_log "INFO" "💡 Check your compose file: ${DOCKER_COMPOSE_FILE:-not set}"
        return 1
    fi
}

# =============================================================================
# Volume Management with Credential Change Detection
# =============================================================================

# Check if credentials have changed since last run
milou_check_credentials_changed() {
    local env_file="${DOCKER_ENV_FILE:-}"
    if [[ -z "$env_file" || ! -f "$env_file" ]]; then
        return 1  # Assume changed if we can't check
    fi
    
    local credentials_hash_file="${CONFIG_DIR:-$(dirname "$env_file")}/.credentials_hash"
    
    # Extract credential-related environment variables
    local current_hash
    current_hash=$(grep -E "^(DB_PASSWORD|REDIS_PASSWORD|SESSION_SECRET|ENCRYPTION_KEY|JWT_SECRET)=" "$env_file" 2>/dev/null | sort | sha256sum | cut -d' ' -f1)
    
    if [[ ! -f "$credentials_hash_file" ]]; then
        milou_log "DEBUG" "No previous credentials hash found - treating as changed"
        return 0  # No previous hash, assume changed
    fi
    
    local stored_hash
    stored_hash=$(cat "$credentials_hash_file" 2>/dev/null)
    
    if [[ "$current_hash" != "$stored_hash" ]]; then
        milou_log "DEBUG" "Credentials have changed since last run"
        return 0  # Changed
    else
        milou_log "DEBUG" "Credentials unchanged since last run"
        return 1  # Unchanged
    fi
}

# Store current credentials hash
milou_store_credentials_hash() {
    local env_file="${DOCKER_ENV_FILE:-}"
    if [[ -z "$env_file" || ! -f "$env_file" ]]; then
        return 1
    fi
    
    local credentials_hash_file="${CONFIG_DIR:-$(dirname "$env_file")}/.credentials_hash"
    
    # Extract and hash credential-related environment variables
    local current_hash
    current_hash=$(grep -E "^(DB_PASSWORD|REDIS_PASSWORD|SESSION_SECRET|ENCRYPTION_KEY|JWT_SECRET)=" "$env_file" 2>/dev/null | sort | sha256sum | cut -d' ' -f1)
    
    # Store the hash
    echo "$current_hash" > "$credentials_hash_file" 2>/dev/null || {
        milou_log "WARN" "Could not store credentials hash"
        return 1
    }
    
    milou_log "DEBUG" "Stored new credentials hash"
    return 0
}

# Clean up volumes when credentials change
milou_cleanup_volumes_on_credential_change() {
    if ! milou_check_credentials_changed; then
        milou_log "DEBUG" "No credential changes detected, skipping volume cleanup"
        return 0
    fi
    
    milou_log "STEP" "Credential changes detected - cleaning up volumes..."
    
    local -a volumes_to_clean=(
        "${DOCKER_PROJECT_NAME}_pgdata"
        "${DOCKER_PROJECT_NAME}_rabbitmq_data" 
        "${DOCKER_PROJECT_NAME}_redis_data"
    )
    
    # Stop services first
    milou_log "INFO" "Stopping services for volume cleanup..."
    milou_docker_compose down --remove-orphans
    
    # Remove volumes with stale credentials
    for volume in "${volumes_to_clean[@]}"; do
        if docker volume inspect "$volume" >/dev/null 2>&1; then
            milou_log "INFO" "Removing volume with stale credentials: $volume"
            if docker volume rm "$volume" 2>/dev/null; then
                milou_log "SUCCESS" "Removed volume: $volume"
            else
                milou_log "WARN" "Failed to remove volume: $volume"
            fi
        fi
    done
    
    # Store new credentials hash
    milou_store_credentials_hash
    DOCKER_VOLUMES_CLEANED=true
    
    milou_log "SUCCESS" "Volume cleanup completed"
    milou_log "INFO" "All services will start with fresh credentials"
    return 0
}

# Create Docker networks if they don't exist
milou_create_networks() {
    local network_name="${DOCKER_PROJECT_NAME}_default"
    
    # Create default project network
    if ! docker network inspect "$network_name" >/dev/null 2>&1; then
        milou_log "INFO" "Creating Docker network: $network_name"
        if docker network create "$network_name" >/dev/null 2>&1; then
            milou_log "SUCCESS" "Created network: $network_name"
        else
            milou_log "WARN" "Failed to create network: $network_name"
        fi
    fi
    
    # Create external proxy network if it doesn't exist
    if ! docker network inspect "proxy" >/dev/null 2>&1; then
        milou_log "INFO" "Creating external proxy network: proxy"
        if docker network create "proxy" >/dev/null 2>&1; then
            milou_log "SUCCESS" "Created external network: proxy"
        else
            milou_log "WARN" "Failed to create external network: proxy"
        fi
    else
        milou_log "DEBUG" "External proxy network already exists"
    fi
}

# =============================================================================
# Service Management
# =============================================================================

# Start services with enhanced error handling
milou_docker_start() {
    milou_log "STEP" "Starting Milou services..."
    
    # Initialize Docker environment
    if ! milou_docker_init; then
        return 1
    fi
    
    # Authenticate with Docker registry if GitHub token is available
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        milou_log "DEBUG" "GitHub token available, setting up Docker registry authentication..."
        if command -v ensure_docker_credentials >/dev/null 2>&1; then
            if ! ensure_docker_credentials "$GITHUB_TOKEN"; then
                milou_log "WARN" "Docker registry authentication failed, but continuing..."
                milou_log "INFO" "💡 Some images may fail to pull from private registry"
            else
                milou_log "SUCCESS" "Docker registry authentication successful"
            fi
        else
            milou_log "WARN" "Docker registry authentication function not available"
        fi
    else
        milou_log "WARN" "No GitHub token provided - private registry images may fail to pull"
        milou_log "INFO" "💡 Use --token <your_github_token> to authenticate with private registry"
    fi
    
    # Clean volumes if credentials changed
    milou_cleanup_volumes_on_credential_change
    
    # Create networks
    milou_create_networks
    
    # Test configuration first
    if ! milou_docker_test_config; then
        milou_log "ERROR" "Docker Compose configuration is invalid"
        return 1
    fi
    
    # Start services
    milou_log "INFO" "Starting services with Docker Compose..."
    if milou_docker_compose up -d --remove-orphans; then
        milou_log "SUCCESS" "Services started successfully"
        
        # Give services a moment to initialize if volumes were cleaned
        if [[ "$DOCKER_VOLUMES_CLEANED" == "true" ]]; then
            milou_log "INFO" "Volumes were cleaned - allowing extra time for service initialization..."
            sleep 10
        fi
        
        return 0
    else
        milou_log "ERROR" "Failed to start services"
        return 1
    fi
}

# Stop services
milou_docker_stop() {
    milou_log "STEP" "Stopping Milou services..."
    
    if ! milou_docker_init; then
        return 1
    fi
    
    if milou_docker_compose down --remove-orphans; then
        milou_log "SUCCESS" "Services stopped successfully"
        return 0
    else
        milou_log "ERROR" "Failed to stop services"
        return 1
    fi
}

# Restart services
milou_docker_restart() {
    milou_log "STEP" "Restarting Milou services..."
    
    if milou_docker_stop && sleep 2 && milou_docker_start; then
        milou_log "SUCCESS" "Services restarted successfully"
        return 0
    else
        milou_log "ERROR" "Failed to restart services"
        return 1
    fi
}

# Show service status with detailed information
milou_docker_status() {
    milou_log "INFO" "📊 Checking Milou services status..."
    milou_log "INFO" "Service Status Overview:"
    echo
    
    if ! milou_docker_init; then
        return 1
    fi
    
    if ! milou_docker_compose ps; then
        milou_log "ERROR" "Failed to get service status"
        return 1
    fi
    
    echo
    
    # Additional status information
    local total_services running_services
    total_services=$(milou_docker_compose config --services 2>/dev/null | wc -l)
    running_services=$(milou_docker_compose ps --services --filter "status=running" 2>/dev/null | wc -l || echo "0")
    
    milou_log "INFO" "Services running: $running_services/$total_services"
    
    # Show network status
    local network_name="${DOCKER_PROJECT_NAME}_default"
    if docker network inspect "$network_name" >/dev/null 2>&1; then
        milou_log "INFO" "Network status: $network_name (active)"
    else
        milou_log "WARN" "Network status: $network_name (not found)"
    fi
    
    return 0
}

# Show service logs
milou_docker_logs() {
    local service="${1:-}"
    local follow="${2:-false}"
    
    if ! milou_docker_init; then
        return 1
    fi
    
    if [[ -n "$service" ]]; then
        milou_log "INFO" "📋 Showing logs for service: $service"
        if [[ "$follow" == "true" ]]; then
            milou_docker_compose logs -f "$service"
        else
            milou_docker_compose logs --tail=50 "$service"
        fi
    else
        milou_log "INFO" "📋 Showing logs for all services"
        if [[ "$follow" == "true" ]]; then
            milou_docker_compose logs -f
        else
            milou_docker_compose logs --tail=50
        fi
    fi
}

# Get shell access to a service
milou_docker_shell() {
    local service="$1"
    local shell="${2:-/bin/bash}"
    
    if [[ -z "$service" ]]; then
        milou_log "ERROR" "Service name is required"
        return 1
    fi
    
    if ! milou_docker_init; then
        return 1
    fi
    
    milou_log "INFO" "🐚 Opening shell in $service container..."
    
    # Try bash first, then sh as fallback
    if ! milou_docker_compose exec "$service" "$shell"; then
        if [[ "$shell" == "/bin/bash" ]]; then
            milou_log "INFO" "Bash not available, trying sh..."
            milou_docker_compose exec "$service" /bin/sh
        else
            return 1
        fi
    fi
}

# =============================================================================
# Backward Compatibility Aliases
# =============================================================================

# Maintain backward compatibility with existing function names
run_docker_compose() { milou_docker_compose "$@"; }
start_services() { milou_docker_start "$@"; }
stop_services() { milou_docker_stop "$@"; }
restart_services() { milou_docker_restart "$@"; }
show_service_status() { milou_docker_status "$@"; }
show_service_logs() { milou_docker_logs "$@"; }
get_service_shell() { milou_docker_shell "$@"; }
exec_in_service() { milou_docker_shell "$@"; }

# Export functions for external use
export -f milou_docker_init milou_docker_compose milou_docker_test_config
export -f milou_docker_start milou_docker_stop milou_docker_restart
export -f milou_docker_status milou_docker_logs milou_docker_shell
export -f milou_check_credentials_changed milou_store_credentials_hash
export -f milou_cleanup_volumes_on_credential_change milou_create_networks

# Export backward compatibility functions
export -f run_docker_compose start_services stop_services restart_services
export -f show_service_status show_service_logs get_service_shell exec_in_service 