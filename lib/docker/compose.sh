#!/bin/bash

# =============================================================================
# Centralized Docker Compose Module for Milou CLI
# Enhanced with volume management, credential detection, and advanced features
# =============================================================================

# Logging is handled by the centralized module loader

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
    
    log "DEBUG" "Initializing Docker environment..."
    
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
        log "ERROR" "Environment file not found in any of the search paths"
        return 1
    fi
    
    # Determine working directory from env file location
    local working_dir
    working_dir="$(dirname "$env_file")"
    
    # Change to working directory
    if [[ -d "$working_dir" ]]; then
        cd "$working_dir" || {
            log "ERROR" "Cannot change to working directory: $working_dir"
            return 1
        }
    fi
    
    # Set Docker Compose file path
    local compose_file="static/docker-compose.yml"
    if [[ ! -f "$compose_file" ]]; then
        compose_file="$(pwd)/static/docker-compose.yml"
        if [[ ! -f "$compose_file" ]]; then
            log "ERROR" "Docker Compose file not found: $compose_file"
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
    
    log "DEBUG" "Docker environment initialized successfully"
    log "DEBUG" "  Environment file: $DOCKER_ENV_FILE"
    log "DEBUG" "  Compose file: $DOCKER_COMPOSE_FILE"
    log "DEBUG" "  Working directory: $(pwd)"
    
    return 0
}

# Validate Docker setup
milou_docker_validate_setup() {
    # Check Docker access
    if ! command -v docker >/dev/null 2>&1; then
        log "ERROR" "Docker is not installed or not in PATH"
        return 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        log "ERROR" "Cannot connect to Docker daemon"
        return 1
    fi
    
    # Check Docker Compose file
    if [[ ! -f "$DOCKER_COMPOSE_FILE" ]]; then
        log "ERROR" "Docker Compose file not found: $DOCKER_COMPOSE_FILE"
        return 1
    fi
    
    # Check environment file
    if [[ ! -f "$DOCKER_ENV_FILE" ]]; then
        log "ERROR" "Docker environment file not found: $DOCKER_ENV_FILE"
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
            log "ERROR" "Failed to initialize Docker environment"
            return 1
        fi
    fi
    
    # Validate files exist
    if [[ ! -f "$DOCKER_ENV_FILE" ]]; then
        log "ERROR" "Environment file not found: $DOCKER_ENV_FILE"
        return 1
    fi
    
    if [[ ! -f "$DOCKER_COMPOSE_FILE" ]]; then
        log "ERROR" "Compose file not found: $DOCKER_COMPOSE_FILE"
        return 1
    fi
    
    log "TRACE" "Running: docker compose --env-file '$DOCKER_ENV_FILE' -f '$DOCKER_COMPOSE_FILE' $*"
    docker compose --env-file "$DOCKER_ENV_FILE" -f "$DOCKER_COMPOSE_FILE" "$@"
}

# Test Docker Compose configuration
milou_docker_test_config() {
    log "DEBUG" "Testing Docker Compose configuration..."
    
    if milou_docker_compose config --quiet; then
        log "SUCCESS" "Docker Compose configuration is valid"
        return 0
    else
        log "ERROR" "Docker Compose configuration is invalid"
        log "INFO" "💡 Check your environment file: ${DOCKER_ENV_FILE:-not set}"
        log "INFO" "💡 Check your compose file: ${DOCKER_COMPOSE_FILE:-not set}"
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
        log "DEBUG" "No previous credentials hash found - treating as changed"
        return 0  # No previous hash, assume changed
    fi
    
    local stored_hash
    stored_hash=$(cat "$credentials_hash_file" 2>/dev/null)
    
    if [[ "$current_hash" != "$stored_hash" ]]; then
        log "DEBUG" "Credentials have changed since last run"
        return 0  # Changed
    else
        log "DEBUG" "Credentials unchanged since last run"
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
        log "WARN" "Could not store credentials hash"
        return 1
    }
    
    log "DEBUG" "Stored new credentials hash"
    return 0
}

# Clean up volumes when credentials change
milou_cleanup_volumes_on_credential_change() {
    if ! milou_check_credentials_changed; then
        log "DEBUG" "No credential changes detected, skipping volume cleanup"
        return 0
    fi
    
    log "STEP" "Credential changes detected - cleaning up volumes..."
    
    local -a volumes_to_clean=(
        "${DOCKER_PROJECT_NAME}_pgdata"
        "${DOCKER_PROJECT_NAME}_rabbitmq_data" 
        "${DOCKER_PROJECT_NAME}_redis_data"
    )
    
    # Stop services first
    log "INFO" "Stopping services for volume cleanup..."
    milou_docker_compose down --remove-orphans
    
    # Remove volumes with stale credentials
    for volume in "${volumes_to_clean[@]}"; do
        if docker volume inspect "$volume" >/dev/null 2>&1; then
            log "INFO" "Removing volume with stale credentials: $volume"
            if docker volume rm "$volume" 2>/dev/null; then
                log "SUCCESS" "Removed volume: $volume"
            else
                log "WARN" "Failed to remove volume: $volume"
            fi
        fi
    done
    
    # Store new credentials hash
    milou_store_credentials_hash
    DOCKER_VOLUMES_CLEANED=true
    
    log "SUCCESS" "Volume cleanup completed"
    log "INFO" "All services will start with fresh credentials"
    return 0
}

# Create Docker networks if they don't exist
milou_create_networks() {
    local network_name="${DOCKER_PROJECT_NAME}_default"
    
    # Create default project network
    if ! docker network inspect "$network_name" >/dev/null 2>&1; then
        log "INFO" "Creating Docker network: $network_name"
        if docker network create "$network_name" >/dev/null 2>&1; then
            log "SUCCESS" "Created network: $network_name"
        else
            log "WARN" "Failed to create network: $network_name"
        fi
    fi
    
    # Create external proxy network if it doesn't exist
    if ! docker network inspect "proxy" >/dev/null 2>&1; then
        log "INFO" "Creating external proxy network: proxy"
        if docker network create "proxy" >/dev/null 2>&1; then
            log "SUCCESS" "Created external network: proxy"
        else
            log "WARN" "Failed to create external network: proxy"
        fi
    else
        log "DEBUG" "External proxy network already exists"
    fi
}

# =============================================================================
# Service Management
# =============================================================================

# Start services with enhanced error handling
milou_docker_start() {
    log "STEP" "Starting Milou services..."
    
    # Initialize Docker environment
    if ! milou_docker_init; then
        return 1
    fi
    
    # Authenticate with Docker registry if GitHub token is available
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        log "DEBUG" "GitHub token available, setting up Docker registry authentication..."
        if command -v ensure_docker_credentials >/dev/null 2>&1; then
            if ! ensure_docker_credentials "$GITHUB_TOKEN"; then
                log "WARN" "Docker registry authentication failed, but continuing..."
                log "INFO" "💡 Some images may fail to pull from private registry"
            else
                log "SUCCESS" "Docker registry authentication successful"
            fi
        else
            log "WARN" "Docker registry authentication function not available"
        fi
    else
        log "WARN" "No GitHub token provided - private registry images may fail to pull"
        log "INFO" "💡 Use --token <your_github_token> to authenticate with private registry"
    fi
    
    # Clean volumes if credentials changed
    milou_cleanup_volumes_on_credential_change
    
    # Create networks
    milou_create_networks
    
    # Test configuration first
    if ! milou_docker_test_config; then
        log "ERROR" "Docker Compose configuration is invalid"
        return 1
    fi
    
    # Start services
    log "INFO" "Starting services with Docker Compose..."
    if milou_docker_compose up -d --remove-orphans; then
        log "SUCCESS" "Services started successfully"
        
        # Give services a moment to initialize if volumes were cleaned
        if [[ "$DOCKER_VOLUMES_CLEANED" == "true" ]]; then
            log "INFO" "Volumes were cleaned - allowing extra time for service initialization..."
            sleep 10
        fi
        
        return 0
    else
        log "ERROR" "Failed to start services"
        return 1
    fi
}

# Stop services
milou_docker_stop() {
    log "STEP" "Stopping Milou services..."
    
    if ! milou_docker_init; then
        return 1
    fi
    
    if milou_docker_compose down --remove-orphans; then
        log "SUCCESS" "Services stopped successfully"
        return 0
    else
        log "ERROR" "Failed to stop services"
        return 1
    fi
}

# Restart services
milou_docker_restart() {
    log "STEP" "Restarting Milou services..."
    
    if milou_docker_stop && sleep 2 && milou_docker_start; then
        log "SUCCESS" "Services restarted successfully"
        return 0
    else
        log "ERROR" "Failed to restart services"
        return 1
    fi
}

# Show service status with detailed information
milou_docker_status() {
    log "INFO" "📊 Checking Milou services status..."
    log "INFO" "Service Status Overview:"
    echo
    
    if ! milou_docker_init; then
        return 1
    fi
    
    if ! milou_docker_compose ps; then
        log "ERROR" "Failed to get service status"
        return 1
    fi
    
    echo
    
    # Additional status information
    local total_services running_services
    total_services=$(milou_docker_compose config --services 2>/dev/null | wc -l)
    running_services=$(milou_docker_compose ps --services --filter "status=running" 2>/dev/null | wc -l || echo "0")
    
    log "INFO" "Services running: $running_services/$total_services"
    
    # Show network status
    local network_name="${DOCKER_PROJECT_NAME}_default"
    if docker network inspect "$network_name" >/dev/null 2>&1; then
        log "INFO" "Network status: $network_name (active)"
    else
        log "WARN" "Network status: $network_name (not found)"
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
        log "INFO" "📋 Showing logs for service: $service"
        if [[ "$follow" == "true" ]]; then
            milou_docker_compose logs -f "$service"
        else
            milou_docker_compose logs --tail=50 "$service"
        fi
    else
        log "INFO" "📋 Showing logs for all services"
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
        log "ERROR" "Service name is required"
        return 1
    fi
    
    if ! milou_docker_init; then
        return 1
    fi
    
    log "INFO" "🐚 Opening shell in $service container..."
    
    # Try bash first, then sh as fallback
    if ! milou_docker_compose exec "$service" "$shell"; then
        if [[ "$shell" == "/bin/bash" ]]; then
            log "INFO" "Bash not available, trying sh..."
            milou_docker_compose exec "$service" /bin/sh
        else
            return 1
        fi
    fi
}

# =============================================================================
# Enhanced Service Management with Checks
# =============================================================================

# Enhanced start services with comprehensive checks
start_services_with_checks() {
    local setup_mode="${1:-false}"
    
    log "STEP" "Starting Milou services with pre-flight checks..."
    
    # Initialize Docker environment if not already done
    if ! milou_docker_init; then
        log "ERROR" "Failed to initialize Docker environment"
        return 1
    fi
    
    # Check SSL certificates if configured
    local ssl_path
    if [[ -f "$DOCKER_ENV_FILE" ]]; then
        ssl_path=$(grep "^SSL_CERT_PATH=" "$DOCKER_ENV_FILE" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "")
        
        if [[ -n "$ssl_path" ]]; then
            log "INFO" "Checking SSL certificates..."
            local full_ssl_path
            if [[ "$ssl_path" = /* ]]; then
                full_ssl_path="$ssl_path"
            else
                full_ssl_path="$(dirname "$DOCKER_COMPOSE_FILE")/$ssl_path"
            fi
            
            if [[ -f "$full_ssl_path/milou.crt" && -f "$full_ssl_path/milou.key" ]]; then
                log "SUCCESS" "SSL certificates found"
            else
                log "WARN" "SSL certificates not found at $full_ssl_path"
                log "INFO" "💡 Services will start but SSL may not work properly"
            fi
        fi
    fi
    
    # Create required networks
    milou_create_networks
    
    # Handle credential changes and volume cleanup
    milou_cleanup_volumes_on_credential_change
    
    # Enhanced conflict detection for non-setup mode
    if [[ "$setup_mode" != "true" ]]; then
        log "DEBUG" "Normal startup mode - checking for conflicts"
        
        # Check for running containers that might conflict
        local running_containers
        running_containers=$(docker ps --filter "name=${DOCKER_PROJECT_NAME}-" --format "{{.Names}}" 2>/dev/null || true)
        
        if [[ -n "$running_containers" ]]; then
            log "WARN" "Found running Milou containers:"
            while IFS= read -r container; do
                [[ -n "$container" ]] && log "WARN" "  🐳 $container"
            done <<< "$running_containers"
            
            if [[ "${FORCE:-false}" == "true" ]]; then
                log "WARN" "Force mode enabled - stopping existing services first"
                if ! milou_docker_stop; then
                    log "WARN" "Failed to stop some services, continuing anyway..."
                fi
                sleep 3
            else
                log "ERROR" "Cannot start services due to conflicts"
                log "INFO" "💡 Solutions:"
                log "INFO" "  • Use --force flag to stop existing services"
                log "INFO" "  • Run: ./milou.sh stop (to stop Milou services)"
                log "INFO" "  • Run: ./milou.sh restart (to restart services)"
                return 1
            fi
        fi
    fi
    
    # Test configuration before starting
    if ! milou_docker_test_config; then
        log "ERROR" "Docker Compose configuration is invalid"
        return 1
    fi
    
    # Start services using the main start function
    if milou_docker_start; then
        log "SUCCESS" "✅ Services started successfully with all checks passed"
        
        # Wait a moment for services to initialize
        log "INFO" "Waiting for services to initialize..."
        sleep 5
        
        # Basic health check
        local healthy_services=0
        local total_services
        total_services=$(milou_docker_compose config --services 2>/dev/null | wc -l || echo "0")
        
        if [[ "$total_services" -gt 0 ]]; then
            # Give services time to start
            local max_wait=30
            local wait_time=0
            
            while [[ $wait_time -lt $max_wait ]]; do
                healthy_services=$(milou_docker_compose ps --services --filter "status=running" 2>/dev/null | wc -l || echo "0")
                
                if [[ "$healthy_services" -eq "$total_services" ]]; then
                    break
                fi
                
                sleep 2
                ((wait_time += 2))
            done
            
            log "INFO" "Services status: $healthy_services/$total_services running"
            
            if [[ "$healthy_services" -eq "$total_services" ]]; then
                log "SUCCESS" "All services are running successfully"
            else
                log "WARN" "Some services may still be starting up"
                log "INFO" "💡 Check status with: ./milou.sh status"
            fi
        fi
        
        return 0
    else
        log "ERROR" "❌ Failed to start services"
        return 1
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
export -f start_services_with_checks

# Export backward compatibility functions
export -f run_docker_compose start_services stop_services restart_services
export -f show_service_status show_service_logs get_service_shell exec_in_service 

# =============================================================================
# Image Extraction and Resolution
# =============================================================================

# Extract Milou-specific images from docker-compose.yml
get_milou_images_from_compose() {
    local compose_file="${1:-${DOCKER_COMPOSE_FILE:-static/docker-compose.yml}}"
    local use_latest="${2:-true}"
    
    if [[ ! -f "$compose_file" ]]; then
        log "ERROR" "Docker Compose file not found: $compose_file" >&2
        return 1
    fi
    
    log "DEBUG" "Extracting Milou images from: $compose_file" >&2
    log "DEBUG" "Use latest tags: $use_latest" >&2
    
    local -a milou_images=()
    
    # Extract lines with ghcr.io/milou-sh/milou images
    while IFS= read -r line; do
        if [[ "$line" =~ image:.*ghcr\.io/milou-sh/milou/ ]]; then
            # Extract the image specification - handle both static and variable formats
            local image_spec
            if [[ "$line" =~ image:.*ghcr\.io/milou-sh/milou/([^:]+):\$\{[^}]+\} ]]; then
                # Handle format: ghcr.io/milou-sh/milou/service:${VAR:-default}
                image_spec=$(echo "$line" | sed -n 's/.*image: *ghcr\.io\/milou-sh\/milou\/\([^:]*\):.*/\1/p')
            elif [[ "$line" =~ image:.*ghcr\.io/milou-sh/milou/([^:]+):[^[:space:]]+ ]]; then
                # Handle format: ghcr.io/milou-sh/milou/service:tag
                image_spec=$(echo "$line" | sed -n 's/.*image: *ghcr\.io\/milou-sh\/milou\/\([^:]*\):.*/\1/p')
            fi
            
            if [[ -n "$image_spec" ]]; then
                # Determine the tag based on user preference
                local tag
                if [[ "$use_latest" == "true" ]]; then
                    tag="latest"
                else
                    tag="v1.0.0"
                fi
                
                # Add the complete image specification
                milou_images+=("$image_spec:$tag")
                log "DEBUG" "Found Milou image: $image_spec -> $image_spec:$tag" >&2
            fi
        fi
    done < "$compose_file"
    
    if [[ ${#milou_images[@]} -eq 0 ]]; then
        log "WARN" "No Milou images found in docker-compose.yml" >&2
        return 1
    fi
    
    log "DEBUG" "Extracted ${#milou_images[@]} Milou images: ${milou_images[*]}" >&2
    
    # Output the images (one per line for easy parsing)
    printf '%s\n' "${milou_images[@]}"
    return 0
}

# Get all required images (Milou + third-party) with resolved tags
get_all_required_images() {
    local compose_file="${1:-${DOCKER_COMPOSE_FILE:-static/docker-compose.yml}}"
    local use_latest="${2:-true}"
    
    if [[ ! -f "$compose_file" ]]; then
        log "ERROR" "Docker Compose file not found: $compose_file" >&2
        return 1
    fi
    
    log "DEBUG" "Getting all required images from: $compose_file" >&2
    
    local -a all_images=()
    
    # Get Milou-specific images
    local milou_images
    milou_images=$(get_milou_images_from_compose "$compose_file" "$use_latest")
    if [[ $? -eq 0 && -n "$milou_images" ]]; then
        while IFS= read -r image; do
            [[ -n "$image" ]] && all_images+=("$image")
        done <<< "$milou_images"
    fi
    
    # Note: We only validate/pull Milou-specific images since third-party images
    # (redis, rabbitmq) are pulled automatically by docker-compose and don't need
    # authentication with our GitHub registry
    
    if [[ ${#all_images[@]} -eq 0 ]]; then
        log "WARN" "No images found to validate/pull" >&2
        return 1
    fi
    
    log "DEBUG" "Total images to process: ${#all_images[@]}" >&2
    
    # Output the images
    printf '%s\n' "${all_images[@]}"
    return 0
}

# Validate that required images exist in the registry
validate_required_images() {
    local token="$1"
    local use_latest="${2:-true}"
    local compose_file="${3:-${DOCKER_COMPOSE_FILE:-static/docker-compose.yml}}"
    
    log "DEBUG" "Validating required images (use_latest: $use_latest)" >&2
    
    # Get the list of required images
    local required_images
    required_images=$(get_all_required_images "$compose_file" "$use_latest")
    if [[ $? -ne 0 || -z "$required_images" ]]; then
        log "ERROR" "Failed to get required images list" >&2
        return 1
    fi
    
    # Convert to array
    local -a images_array=()
    while IFS= read -r image; do
        [[ -n "$image" ]] && images_array+=("$image")
    done <<< "$required_images"
    
    log "INFO" "Validating ${#images_array[@]} required images..." >&2
    
    # Call the existing validate_images_exist function with the correct parameters
    if command -v validate_images_exist >/dev/null 2>&1; then
        validate_images_exist "$token" "${images_array[@]}"
    else
        log "ERROR" "validate_images_exist function not available" >&2
        return 1
    fi
}

# Pull all required images
pull_required_images() {
    local token="$1"
    local use_latest="${2:-true}"
    local compose_file="${3:-${DOCKER_COMPOSE_FILE:-static/docker-compose.yml}}"
    
    log "DEBUG" "Pulling required images (use_latest: $use_latest)" >&2
    
    # Get the list of required images
    local required_images
    required_images=$(get_all_required_images "$compose_file" "$use_latest")
    if [[ $? -ne 0 || -z "$required_images" ]]; then
        log "ERROR" "Failed to get required images list" >&2
        return 1
    fi
    
    # Convert to array
    local -a images_array=()
    while IFS= read -r image; do
        [[ -n "$image" ]] && images_array+=("$image")
    done <<< "$required_images"
    
    log "INFO" "Pulling ${#images_array[@]} required images..." >&2
    
    # Call the existing pull_images function with the correct parameters
    if command -v pull_images >/dev/null 2>&1; then
        pull_images "$token" "${images_array[@]}"
    else
        log "ERROR" "pull_images function not available" >&2
        return 1
    fi
}

# Export the new functions
export -f get_milou_images_from_compose get_all_required_images
export -f validate_required_images pull_required_images 