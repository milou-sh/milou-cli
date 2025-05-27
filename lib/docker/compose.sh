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
    
    # Build compose command with base file
    local compose_cmd="docker compose --env-file '$DOCKER_ENV_FILE' -f '$DOCKER_COMPOSE_FILE'"
    
    # Check for local development override ONLY if DEV_MODE is enabled
    if [[ "${DEV_MODE:-false}" == "true" ]]; then
        local override_file="$(dirname "$DOCKER_COMPOSE_FILE")/docker-compose.local.yml"
        if [[ -f "$override_file" ]]; then
            compose_cmd="$compose_cmd -f '$override_file'"
    milou_log "DEBUG" "Using local development override: $override_file"
        else
    milou_log "WARN" "Development mode enabled but local override file not found: $override_file"
        fi
    fi
    
    # Check for standard override file
    local standard_override="$(dirname "$DOCKER_COMPOSE_FILE")/docker-compose.override.yml"
    if [[ -f "$standard_override" ]]; then
        compose_cmd="$compose_cmd -f '$standard_override'"
    milou_log "DEBUG" "Using standard override file: $standard_override"
    fi
    
    milou_log "TRACE" "Running: $compose_cmd $*"
    eval "$compose_cmd" "$@"
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
    
    # Detect current mode and handle conflicts
    local current_mode="prod"
    if [[ "${DEV_MODE:-false}" == "true" ]]; then
        current_mode="dev"
    fi
    
    # Detect and handle conflicting environments
    if command -v detect_and_handle_conflicts >/dev/null 2>&1; then
        if ! detect_and_handle_conflicts "$current_mode"; then
    milou_log "ERROR" "Failed to resolve environment conflicts"
            return 1
        fi
    fi
    
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

# Map service name to container name based on docker-compose.yml
get_container_name_for_service() {
    local service="$1"
    case "$service" in
        db) echo "milou-database" ;;
        redis) echo "milou-redis" ;;
        rabbitmq) echo "milou-rabbitmq" ;;
        backend) echo "milou-backend" ;;
        frontend) echo "milou-frontend" ;;
        engine) echo "milou-engine" ;;
        nginx) echo "milou-nginx" ;;
        monitor) echo "milou-monitor" ;;
        *) echo "milou-${service}" ;;  # fallback to milou-<service>
    esac
}

# Show service status with detailed information
milou_docker_status() {
    local show_header="${1:-true}"
    
    if [[ "$show_header" == "true" ]]; then
    milou_log "INFO" "📊 Checking Milou services status..."
    fi
    
    # Check if this is a fresh installation
    local is_fresh_install=false
    local has_config=false
    local has_containers=false
    
    # Check for configuration
    if [[ -f "${ENV_FILE:-${SCRIPT_DIR}/.env}" ]]; then
        has_config=true
    fi
    
    # Check for any existing containers (running or stopped)
    local existing_containers
    existing_containers=$(docker ps -a --filter "name=milou-" --format "{{.Names}}" 2>/dev/null || true)
    if [[ -n "$existing_containers" ]]; then
        has_containers=true
    fi
    
    # Determine if this is a fresh install
    if [[ "$has_config" == false && "$has_containers" == false ]]; then
        is_fresh_install=true
    fi
    
    # Handle fresh installation case
    if [[ "$is_fresh_install" == true ]]; then
        echo
    milou_log "INFO" "🆕 Fresh Installation Detected"
        echo
    milou_log "INFO" "It looks like Milou hasn't been set up yet on this system."
        echo
    milou_log "INFO" "🚀 To get started, run the setup wizard:"
    milou_log "INFO" "   ./milou.sh setup"
        echo
    milou_log "INFO" "📖 Or see all available commands:"
    milou_log "INFO" "   ./milou.sh help"
        echo
        return 0
    fi
    
    # Initialize Docker environment for status checking
    if ! milou_docker_init; then
    milou_log "ERROR" "Failed to initialize Docker environment"
        echo
    milou_log "INFO" "💡 Try running setup to fix configuration issues:"
    milou_log "INFO" "   ./milou.sh setup"
        return 1
    fi
    
    echo
    milou_log "INFO" "Service Status Overview:"
    echo
    
    # Get service status with better error handling
    local compose_status
    if ! compose_status=$(milou_docker_compose ps 2>&1); then
    milou_log "ERROR" "Failed to get service status"
        echo "$compose_status" | head -3
        echo
    milou_log "INFO" "💡 Troubleshooting options:"
    milou_log "INFO" "   • Check configuration: ./milou.sh validate"
    milou_log "INFO" "   • Run setup again: ./milou.sh setup"
    milou_log "INFO" "   • View detailed diagnosis: ./milou.sh diagnose"
        return 1
    fi
    
    # Display the compose status output
    echo "$compose_status"
    echo
    
    # Get accurate service counts
    local total_services running_services stopped_services unhealthy_services
    
    # Count total services defined in compose file
    total_services=$(milou_docker_compose config --services 2>/dev/null | wc -l || echo "0")
    
    # Count running services more accurately
    running_services=0
    stopped_services=0
    unhealthy_services=0
    
    if [[ "$total_services" -gt 0 ]]; then
        # Get detailed status of each service
        while IFS= read -r service; do
            if [[ -n "$service" ]]; then
                local container_name
                container_name=$(get_container_name_for_service "$service")
                local service_status
                service_status=$(docker ps --filter "name=${container_name}" --format "{{.Status}}" 2>/dev/null || echo "")
                
                if [[ -n "$service_status" ]]; then
                    if [[ "$service_status" =~ ^Up ]]; then
                        if [[ "$service_status" =~ "unhealthy" ]]; then
                            unhealthy_services=$((unhealthy_services + 1))
                        else
                            running_services=$((running_services + 1))
                        fi
                    else
                        stopped_services=$((stopped_services + 1))
                    fi
                else
                    stopped_services=$((stopped_services + 1))
                fi
            fi
        done < <(milou_docker_compose config --services 2>/dev/null)
    fi
    
    # Display service summary with color coding
    if [[ $running_services -eq $total_services && $total_services -gt 0 ]]; then
    milou_log "SUCCESS" "✅ All services running: $running_services/$total_services"
    elif [[ $running_services -gt 0 ]]; then
    milou_log "WARN" "⚠️  Services partially running: $running_services/$total_services"
        if [[ $unhealthy_services -gt 0 ]]; then
    milou_log "WARN" "   Unhealthy services: $unhealthy_services"
        fi
        if [[ $stopped_services -gt 0 ]]; then
    milou_log "WARN" "   Stopped services: $stopped_services"
        fi
    else
    milou_log "ERROR" "❌ No services running: 0/$total_services"
    fi
    
    # Show network status
    local network_name="${DOCKER_PROJECT_NAME}_default"
    if docker network inspect "$network_name" >/dev/null 2>&1; then
    milou_log "INFO" "🌐 Network status: $network_name (active)"
    else
    milou_log "WARN" "🌐 Network status: $network_name (not found)"
    fi
    
    # Provide helpful suggestions based on status
    echo
    if [[ $running_services -eq 0 && $total_services -gt 0 ]]; then
    milou_log "INFO" "💡 Services are stopped. To start them:"
    milou_log "INFO" "   ./milou.sh start"
        echo
    elif [[ $running_services -lt $total_services && $running_services -gt 0 ]]; then
    milou_log "INFO" "💡 Some services are not running. Try:"
    milou_log "INFO" "   ./milou.sh restart    # Restart all services"
    milou_log "INFO" "   ./milou.sh logs       # Check logs for issues"
    milou_log "INFO" "   ./milou.sh diagnose   # Run comprehensive diagnosis"
        echo
    elif [[ $unhealthy_services -gt 0 ]]; then
    milou_log "INFO" "💡 Some services are unhealthy. Try:"
    milou_log "INFO" "   ./milou.sh health     # Run health checks"
    milou_log "INFO" "   ./milou.sh logs       # Check logs for issues"
    milou_log "INFO" "   ./milou.sh restart    # Restart unhealthy services"
        echo
    fi
    
    # Show quick access information if services are running
    if [[ $running_services -gt 0 ]]; then
        # Load domain and SSL settings from environment file
        local domain="localhost"
        local ssl_path="./ssl"
        local http_port="80"
        local ssl_port="443"
        
        if [[ -f "$DOCKER_ENV_FILE" ]]; then
            # Extract configuration values from environment file
            domain=$(grep "^SERVER_NAME=" "$DOCKER_ENV_FILE" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "localhost")
            ssl_path=$(grep "^SSL_CERT_PATH=" "$DOCKER_ENV_FILE" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "./ssl")
            http_port=$(grep "^HTTP_PORT=" "$DOCKER_ENV_FILE" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "80")
            ssl_port=$(grep "^SSL_PORT=" "$DOCKER_ENV_FILE" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "443")
        fi
        
    milou_log "INFO" "🌐 Access Information:"
        
        # Check for SSL certificates and show appropriate URLs
        local full_ssl_path
        if [[ "$ssl_path" = /* ]]; then
            full_ssl_path="$ssl_path"
        else
            full_ssl_path="$(dirname "$DOCKER_COMPOSE_FILE")/$ssl_path"
        fi
        
        if [[ -f "$full_ssl_path/milou.crt" && -f "$full_ssl_path/milou.key" ]]; then
            if [[ "$ssl_port" == "443" ]]; then
    milou_log "INFO" "   🔒 HTTPS: https://$domain"
            else
    milou_log "INFO" "   🔒 HTTPS: https://$domain:$ssl_port"
            fi
        fi
        
        if [[ "$http_port" == "80" ]]; then
    milou_log "INFO" "   🌐 HTTP:  http://$domain"
        else
    milou_log "INFO" "   🌐 HTTP:  http://$domain:$http_port"
        fi
        
        # Admin credentials moved to dedicated command for security
        # Use './milou.sh admin-credentials' to view login credentials
        
        echo
    milou_log "INFO" "📊 Quick Commands:"
    milou_log "INFO" "   ./milou.sh logs       # View service logs"
    milou_log "INFO" "   ./milou.sh health     # Run health checks"
    milou_log "INFO" "   ./milou.sh shell <service>  # Access service shell"
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
# Enhanced Service Management with Checks
# =============================================================================

# Enhanced start services with comprehensive checks
start_services_with_checks() {
    local setup_mode="${1:-false}"
    
    milou_log "STEP" "Starting Milou services with pre-flight checks..."
    
    # Initialize Docker environment if not already done
    if ! milou_docker_init; then
    milou_log "ERROR" "Failed to initialize Docker environment"
        return 1
    fi
    
    # Check SSL certificates if configured
    local ssl_path
    if [[ -f "$DOCKER_ENV_FILE" ]]; then
        ssl_path=$(grep "^SSL_CERT_PATH=" "$DOCKER_ENV_FILE" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "")
        
        if [[ -n "$ssl_path" ]]; then
    milou_log "INFO" "Checking SSL certificates..."
            local full_ssl_path
            if [[ "$ssl_path" = /* ]]; then
                full_ssl_path="$ssl_path"
            else
                full_ssl_path="$(dirname "$DOCKER_COMPOSE_FILE")/$ssl_path"
            fi
            
            if [[ -f "$full_ssl_path/milou.crt" && -f "$full_ssl_path/milou.key" ]]; then
    milou_log "SUCCESS" "SSL certificates found"
            else
    milou_log "WARN" "SSL certificates not found at $full_ssl_path"
    milou_log "INFO" "💡 Services will start but SSL may not work properly"
            fi
        fi
    fi
    
    # Create required networks
    milou_create_networks
    
    # Handle credential changes and volume cleanup
    milou_cleanup_volumes_on_credential_change
    
    # Enhanced conflict detection for non-setup mode
    if [[ "$setup_mode" != "true" ]]; then
    milou_log "DEBUG" "Normal startup mode - checking for conflicts"
        
        # Check for running containers that might conflict
        local running_containers
        running_containers=$(docker ps --filter "name=${DOCKER_PROJECT_NAME}-" --format "{{.Names}}" 2>/dev/null || true)
        
        if [[ -n "$running_containers" ]]; then
    milou_log "WARN" "Found running Milou containers:"
            while IFS= read -r container; do
                [[ -n "$container" ]] && log "WARN" "  🐳 $container"
            done <<< "$running_containers"
            
            if [[ "${FORCE:-false}" == "true" ]]; then
    milou_log "WARN" "Force mode enabled - stopping existing services first"
                if ! milou_docker_stop; then
    milou_log "WARN" "Failed to stop some services, continuing anyway..."
                fi
                sleep 3
            else
    milou_log "ERROR" "Cannot start services due to conflicts"
    milou_log "INFO" "💡 Solutions:"
    milou_log "INFO" "  • Use --force flag to stop existing services"
    milou_log "INFO" "  • Run: ./milou.sh stop (to stop Milou services)"
    milou_log "INFO" "  • Run: ./milou.sh restart (to restart services)"
                return 1
            fi
        fi
    fi
    
    # Test configuration before starting
    if ! milou_docker_test_config; then
    milou_log "ERROR" "Docker Compose configuration is invalid"
        return 1
    fi
    
    # Start services using the main start function
    if milou_docker_start; then
    milou_log "SUCCESS" "✅ Services started successfully with all checks passed"
        
        # Wait a moment for services to initialize
    milou_log "INFO" "Waiting for services to initialize..."
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
            
    milou_log "INFO" "Services status: $healthy_services/$total_services running"
            
            if [[ "$healthy_services" -eq "$total_services" ]]; then
    milou_log "SUCCESS" "All services are running successfully"
            else
    milou_log "WARN" "Some services may still be starting up"
    milou_log "INFO" "💡 Check status with: ./milou.sh status"
            fi
        fi
        
        return 0
    else
    milou_log "ERROR" "❌ Failed to start services"
        return 1
    fi
}

# =============================================================================
# Module Exports
# =============================================================================

# Export functions for external use
export -f milou_docker_init milou_docker_compose milou_docker_test_config
export -f milou_docker_start milou_docker_stop milou_docker_restart
export -f milou_docker_status milou_docker_logs milou_docker_shell
export -f milou_check_credentials_changed milou_store_credentials_hash
export -f milou_cleanup_volumes_on_credential_change milou_create_networks
export -f start_services_with_checks

# Export health check functions
export -f run_health_checks quick_health_check 

# =============================================================================
# Image Extraction and Resolution
# =============================================================================

# Extract Milou-specific images from docker-compose.yml
get_milou_images_from_compose() {
    local compose_file="${1:-${DOCKER_COMPOSE_FILE:-static/docker-compose.yml}}"
    local use_latest="${2:-true}"
    
    if [[ ! -f "$compose_file" ]]; then
    milou_log "ERROR" "Docker Compose file not found: $compose_file" >&2
        return 1
    fi
    
    milou_log "DEBUG" "Extracting Milou images from: $compose_file" >&2
    milou_log "DEBUG" "Use latest tags: $use_latest" >&2
    
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
    milou_log "DEBUG" "Found Milou image: $image_spec -> $image_spec:$tag" >&2
            fi
        fi
    done < "$compose_file"
    
    if [[ ${#milou_images[@]} -eq 0 ]]; then
    milou_log "WARN" "No Milou images found in docker-compose.yml" >&2
        return 1
    fi
    
    milou_log "DEBUG" "Extracted ${#milou_images[@]} Milou images: ${milou_images[*]}" >&2
    
    # Output the images (one per line for easy parsing)
    printf '%s\n' "${milou_images[@]}"
    return 0
}

# Get all required images (Milou + third-party) with resolved tags
get_all_required_images() {
    local compose_file="${1:-${DOCKER_COMPOSE_FILE:-static/docker-compose.yml}}"
    local use_latest="${2:-true}"
    
    if [[ ! -f "$compose_file" ]]; then
    milou_log "ERROR" "Docker Compose file not found: $compose_file" >&2
        return 1
    fi
    
    milou_log "DEBUG" "Getting all required images from: $compose_file" >&2
    
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
    milou_log "WARN" "No images found to validate/pull" >&2
        return 1
    fi
    
    milou_log "DEBUG" "Total images to process: ${#all_images[@]}" >&2
    
    # Output the images
    printf '%s\n' "${all_images[@]}"
    return 0
}

# Validate that required images exist in the registry
validate_required_images() {
    local token="$1"
    local use_latest="${2:-true}"
    local compose_file="${3:-${DOCKER_COMPOSE_FILE:-static/docker-compose.yml}}"
    
    milou_log "DEBUG" "Validating required images (use_latest: $use_latest)" >&2
    
    # Get the list of required images
    local required_images
    required_images=$(get_all_required_images "$compose_file" "$use_latest")
    if [[ $? -ne 0 || -z "$required_images" ]]; then
    milou_log "ERROR" "Failed to get required images list" >&2
        return 1
    fi
    
    # Convert to array
    local -a images_array=()
    while IFS= read -r image; do
        [[ -n "$image" ]] && images_array+=("$image")
    done <<< "$required_images"
    
    milou_log "INFO" "Validating ${#images_array[@]} required images..." >&2
    
    # Call the existing validate_images_exist function with the correct parameters
    if command -v validate_images_exist >/dev/null 2>&1; then
        validate_images_exist "$token" "${images_array[@]}"
    else
    milou_log "ERROR" "validate_images_exist function not available" >&2
        return 1
    fi
}

# Pull all required images
pull_required_images() {
    local token="$1"
    local use_latest="${2:-true}"
    local compose_file="${3:-${DOCKER_COMPOSE_FILE:-static/docker-compose.yml}}"
    
    milou_log "DEBUG" "Pulling required images (use_latest: $use_latest)" >&2
    
    # Get the list of required images
    local required_images
    required_images=$(get_all_required_images "$compose_file" "$use_latest")
    if [[ $? -ne 0 || -z "$required_images" ]]; then
    milou_log "ERROR" "Failed to get required images list" >&2
        return 1
    fi
    
    # Convert to array
    local -a images_array=()
    while IFS= read -r image; do
        [[ -n "$image" ]] && images_array+=("$image")
    done <<< "$required_images"
    
    milou_log "INFO" "Pulling ${#images_array[@]} required images..." >&2
    
    # Call the existing pull_images function with the correct parameters
    if command -v pull_images >/dev/null 2>&1; then
        pull_images "$token" "${images_array[@]}"
    else
    milou_log "ERROR" "pull_images function not available" >&2
        return 1
    fi
}

# Export the new functions
export -f get_milou_images_from_compose get_all_required_images
export -f validate_required_images pull_required_images

# =============================================================================
# Health Check Functions
# =============================================================================

# Run comprehensive health checks
run_health_checks() {
    milou_log "STEP" "Running comprehensive health checks..."
    
    # Initialize if needed
    if ! milou_docker_init; then
    milou_log "ERROR" "Failed to initialize Docker environment"
        return 1
    fi
    
    local issues_found=0
    
    echo
    milou_log "INFO" "🏥 Health Check Report"
    echo
    
    # 1. Docker daemon check
    milou_log "INFO" "1️⃣  Docker Daemon Status"
    if docker info >/dev/null 2>&1; then
    milou_log "SUCCESS" "   ✅ Docker daemon is running"
    else
    milou_log "ERROR" "   ❌ Docker daemon is not accessible"
        ((issues_found++))
    fi
    
    # 2. Service status check
    milou_log "INFO" "2️⃣  Service Status"
    local total_services running_services
    total_services=$(milou_docker_compose config --services 2>/dev/null | wc -l || echo "0")
    running_services=$(milou_docker_compose ps --services --filter "status=running" 2>/dev/null | wc -l || echo "0")
    
    if [[ "$running_services" -eq "$total_services" && "$total_services" -gt 0 ]]; then
    milou_log "SUCCESS" "   ✅ All services running ($running_services/$total_services)"
    else
    milou_log "WARN" "   ⚠️  Some services not running ($running_services/$total_services)"
        ((issues_found++))
    fi
    
    # 3. Network connectivity
    milou_log "INFO" "3️⃣  Network Connectivity"
    local network_name="${DOCKER_PROJECT_NAME}_default"
    if docker network inspect "$network_name" >/dev/null 2>&1; then
    milou_log "SUCCESS" "   ✅ Docker network exists: $network_name"
    else
    milou_log "ERROR" "   ❌ Docker network missing: $network_name"
        ((issues_found++))
    fi
    
    # 4. Volume health
    milou_log "INFO" "4️⃣  Volume Health"
    local volumes
    volumes=$(docker volume ls --filter "name=${DOCKER_PROJECT_NAME}_" --format "{{.Name}}" 2>/dev/null || true)
    if [[ -n "$volumes" ]]; then
        local volume_count
        volume_count=$(echo "$volumes" | wc -l)
    milou_log "SUCCESS" "   ✅ Data volumes found: $volume_count volumes"
    else
    milou_log "WARN" "   ⚠️  No data volumes found"
    fi
    
    # 5. Configuration validation
    milou_log "INFO" "5️⃣  Configuration Validation"
    if [[ -f "$DOCKER_ENV_FILE" ]]; then
    milou_log "SUCCESS" "   ✅ Environment file exists"
    else
    milou_log "ERROR" "   ❌ Environment file missing"
        ((issues_found++))
    fi
    
    if [[ -f "$DOCKER_COMPOSE_FILE" ]]; then
    milou_log "SUCCESS" "   ✅ Docker Compose file exists"
    else
    milou_log "ERROR" "   ❌ Docker Compose file missing"
        ((issues_found++))
    fi
    
    # 6. Port accessibility test
    milou_log "INFO" "6️⃣  Port Accessibility"
    if curl -k -s https://localhost >/dev/null 2>&1; then
    milou_log "SUCCESS" "   ✅ HTTPS endpoint accessible"
    else
    milou_log "WARN" "   ⚠️  HTTPS endpoint not accessible"
        ((issues_found++))
    fi
    
    # Summary
    echo
    if [[ $issues_found -eq 0 ]]; then
    milou_log "SUCCESS" "🎉 Health check passed! No issues found."
    else
    milou_log "WARN" "⚠️  Health check completed with $issues_found issue(s) found."
    milou_log "INFO" "💡 Run './milou.sh diagnose' for detailed troubleshooting"
    fi
    
    echo
    return $issues_found
}

# Quick health check
quick_health_check() {
    milou_log "INFO" "⚡ Running quick health check..."
    
    if ! milou_docker_init; then
    milou_log "ERROR" "Docker environment not available"
        return 1
    fi
    
    local running_services
    running_services=$(milou_docker_compose ps --services --filter "status=running" 2>/dev/null | wc -l || echo "0")
    local total_services
    total_services=$(milou_docker_compose config --services 2>/dev/null | wc -l || echo "0")
    
    if [[ "$running_services" -eq "$total_services" && "$total_services" -gt 0 ]]; then
    milou_log "SUCCESS" "✅ Quick check passed: All $total_services services running"
        return 0
    else
    milou_log "WARN" "⚠️  Quick check: $running_services/$total_services services running"
        return 1
    fi
} 