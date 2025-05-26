#!/bin/bash

# =============================================================================
# Milou CLI - Consolidated Docker Module
# All Docker functionality in one organized module (500 lines max)
# =============================================================================

# Module guard to prevent multiple loading
if [[ "${MILOU_DOCKER_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_DOCKER_LOADED="true"

# Ensure logging is available
if ! command -v log >/dev/null 2>&1; then
    source "${BASH_SOURCE%/*}/utils.sh" 2>/dev/null || {
        echo "ERROR: Cannot load utilities module" >&2
        return 1
    }
fi

# =============================================================================
# Docker Configuration and Variables (Lines 1-50)
# =============================================================================

# Docker environment variables
declare -g DOCKER_ENV_FILE=""
declare -g DOCKER_COMPOSE_FILE=""
declare -g DOCKER_PROJECT_NAME="static"
declare -g DOCKER_VOLUMES_CLEANED=false

# Default paths
DEFAULT_COMPOSE_FILE="static/docker-compose.yml"
DEFAULT_ENV_FILE=".env"

# Docker registry configuration
DOCKER_REGISTRY_URL="${DOCKER_REGISTRY_URL:-}"
DOCKER_REGISTRY_USERNAME="${DOCKER_REGISTRY_USERNAME:-}"
DOCKER_REGISTRY_PASSWORD="${DOCKER_REGISTRY_PASSWORD:-}"

# Initialize Docker environment
docker_init() {
    local script_dir="${1:-${SCRIPT_DIR:-$(pwd)}}"
    
    log "DEBUG" "Initializing Docker environment..."
    
    # Find environment file
    local env_file=""
    local -a env_search_paths=(
        "${script_dir}/.env"
        "$(pwd)/.env"
        "${PWD}/.env"
        "/home/milou/milou-cli/.env"
        "/opt/milou-cli/.env"
    )
    
    for path in "${env_search_paths[@]}"; do
        if [[ -f "$path" && -s "$path" ]]; then
            env_file="$path"
            break
        fi
    done
    
    if [[ -z "$env_file" ]]; then
        log "ERROR" "Environment file not found"
        return 1
    fi
    
    # Set working directory
    local working_dir="$(dirname "$env_file")"
    if [[ -d "$working_dir" ]]; then
        cd "$working_dir" || {
            log "ERROR" "Cannot change to working directory: $working_dir"
            return 1
        }
    fi
    
    # Find compose file
    local compose_file="$DEFAULT_COMPOSE_FILE"
    if [[ ! -f "$compose_file" ]]; then
        log "ERROR" "Docker Compose file not found: $compose_file"
        return 1
    fi
    
    # Export variables
    export DOCKER_ENV_FILE="$env_file"
    export DOCKER_COMPOSE_FILE="$compose_file"
    
    # Get project name
    local project_name
    project_name=$(grep "^COMPOSE_PROJECT_NAME=" "$env_file" 2>/dev/null | cut -d '=' -f 2- || echo "static")
    export DOCKER_PROJECT_NAME="$project_name"
    
    # Validate setup
    if ! docker_validate_setup; then
        return 1
    fi
    
    log "SUCCESS" "Docker environment initialized"
    return 0
}

# =============================================================================
# Docker Validation and Prerequisites (Lines 51-100)
# =============================================================================

# Validate Docker setup
docker_validate_setup() {
    # Check Docker installation
    if ! command_exists docker; then
        log "ERROR" "Docker is not installed"
        return 1
    fi
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        log "ERROR" "Cannot connect to Docker daemon"
        log "INFO" "Try: sudo systemctl start docker"
        return 1
    fi
    
    # Check Docker Compose
    if ! docker compose version >/dev/null 2>&1; then
        log "ERROR" "Docker Compose is not available"
        return 1
    fi
    
    # Check files
    if [[ ! -f "$DOCKER_COMPOSE_FILE" ]]; then
        log "ERROR" "Docker Compose file not found: $DOCKER_COMPOSE_FILE"
        return 1
    fi
    
    if [[ ! -f "$DOCKER_ENV_FILE" ]]; then
        log "ERROR" "Environment file not found: $DOCKER_ENV_FILE"
        return 1
    fi
    
    return 0
}

# Test Docker Compose configuration
docker_test_config() {
    log "DEBUG" "Testing Docker Compose configuration..."
    
    if docker_compose config --quiet; then
        log "SUCCESS" "Docker Compose configuration is valid"
        return 0
    else
        log "ERROR" "Docker Compose configuration is invalid"
        log "INFO" "Check environment file: $DOCKER_ENV_FILE"
        log "INFO" "Check compose file: $DOCKER_COMPOSE_FILE"
        return 1
    fi
}

# Check Docker system resources
docker_check_resources() {
    log "INFO" "Docker System Resources:"
    
    # Check disk space
    local docker_root
    docker_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "/var/lib/docker")
    
    if command_exists df; then
        local available_space
        available_space=$(df -h "$docker_root" | awk 'NR==2 {print $4}')
        echo "  Available disk space: $available_space"
    fi
    
    # Check memory
    if [[ -f /proc/meminfo ]]; then
        local available_mem
        available_mem=$(grep MemAvailable /proc/meminfo | awk '{print int($2/1024/1024)"GB"}')
        echo "  Available memory: $available_mem"
    fi
    
    # Check running containers
    local running_containers
    running_containers=$(docker ps --format "table {{.Names}}" | tail -n +2 | wc -l)
    echo "  Running containers: $running_containers"
    
    return 0
}

# =============================================================================
# Docker Compose Operations (Lines 101-200)
# =============================================================================

# Run Docker Compose with proper environment
docker_compose() {
    # Auto-initialize if needed
    if [[ -z "$DOCKER_ENV_FILE" || -z "$DOCKER_COMPOSE_FILE" ]]; then
        if ! docker_init; then
            log "ERROR" "Failed to initialize Docker environment"
            return 1
        fi
    fi
    
    # Build compose command
    local compose_cmd="docker compose --env-file '$DOCKER_ENV_FILE' -f '$DOCKER_COMPOSE_FILE'"
    
    # Add development override if enabled
    if [[ "${DEV_MODE:-false}" == "true" ]]; then
        local dev_override="$(dirname "$DOCKER_COMPOSE_FILE")/docker-compose.local.yml"
        if [[ -f "$dev_override" ]]; then
            compose_cmd="$compose_cmd -f '$dev_override'"
            log "DEBUG" "Using development override: $dev_override"
        fi
    fi
    
    # Add standard override
    local override_file="$(dirname "$DOCKER_COMPOSE_FILE")/docker-compose.override.yml"
    if [[ -f "$override_file" ]]; then
        compose_cmd="$compose_cmd -f '$override_file'"
        log "DEBUG" "Using override file: $override_file"
    fi
    
    log "TRACE" "Running: $compose_cmd $*"
    eval "$compose_cmd" "$@"
}

# Start services
docker_start() {
    local services=("$@")
    
    log "STEP" "Starting Docker services..."
    
    if [[ ${#services[@]} -eq 0 ]]; then
        docker_compose up -d
    else
        docker_compose up -d "${services[@]}"
    fi
    
    if [[ $? -eq 0 ]]; then
        log "SUCCESS" "Docker services started"
        docker_status
    else
        log "ERROR" "Failed to start Docker services"
        return 1
    fi
}

# Stop services
docker_stop() {
    local services=("$@")
    
    log "STEP" "Stopping Docker services..."
    
    if [[ ${#services[@]} -eq 0 ]]; then
        docker_compose down
    else
        docker_compose stop "${services[@]}"
    fi
    
    if [[ $? -eq 0 ]]; then
        log "SUCCESS" "Docker services stopped"
    else
        log "ERROR" "Failed to stop Docker services"
        return 1
    fi
}

# Restart services
docker_restart() {
    local services=("$@")
    
    log "STEP" "Restarting Docker services..."
    
    if [[ ${#services[@]} -eq 0 ]]; then
        docker_compose restart
    else
        docker_compose restart "${services[@]}"
    fi
    
    if [[ $? -eq 0 ]]; then
        log "SUCCESS" "Docker services restarted"
        docker_status
    else
        log "ERROR" "Failed to restart Docker services"
        return 1
    fi
}

# Show service status
docker_status() {
    log "INFO" "Docker Services Status:"
    docker_compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
    
    # Show resource usage
    echo
    log "INFO" "Resource Usage:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null || true
}

# View logs
docker_logs() {
    local service="${1:-}"
    local follow="${2:-false}"
    
    if [[ -z "$service" ]]; then
        if [[ "$follow" == "true" ]]; then
            docker_compose logs -f
        else
            docker_compose logs --tail=50
        fi
    else
        if [[ "$follow" == "true" ]]; then
            docker_compose logs -f "$service"
        else
            docker_compose logs --tail=50 "$service"
        fi
    fi
}

# =============================================================================
# Volume and Data Management (Lines 201-300)
# =============================================================================

# Clean Docker volumes
docker_clean_volumes() {
    local force="${1:-false}"
    
    if [[ "$force" != "true" ]]; then
        log "WARN" "This will remove all unused Docker volumes"
        if ! ask_yes_no "Continue with volume cleanup?"; then
            log "INFO" "Volume cleanup cancelled"
            return 0
        fi
    fi
    
    log "STEP" "Cleaning Docker volumes..."
    
    # Stop services first
    docker_compose down
    
    # Remove unused volumes
    docker volume prune -f
    
    # Remove project-specific volumes if they exist
    local project_volumes
    project_volumes=$(docker volume ls --filter "name=${DOCKER_PROJECT_NAME}_" --format "{{.Name}}" 2>/dev/null || true)
    
    if [[ -n "$project_volumes" ]]; then
        log "INFO" "Removing project volumes: $project_volumes"
        echo "$project_volumes" | xargs docker volume rm 2>/dev/null || true
    fi
    
    DOCKER_VOLUMES_CLEANED=true
    log "SUCCESS" "Docker volumes cleaned"
}

# Backup Docker volumes
docker_backup_volumes() {
    local backup_dir="${1:-./docker-backups/$(date +%Y%m%d-%H%M%S)}"
    
    log "STEP" "Backing up Docker volumes to: $backup_dir"
    
    safe_mkdir "$backup_dir"
    
    # Get list of volumes for this project
    local volumes
    volumes=$(docker_compose config --volumes 2>/dev/null || true)
    
    if [[ -z "$volumes" ]]; then
        log "WARN" "No volumes found to backup"
        return 0
    fi
    
    # Backup each volume
    while IFS= read -r volume; do
        if [[ -n "$volume" ]]; then
            log "INFO" "Backing up volume: $volume"
            
            # Create a temporary container to access the volume
            docker run --rm \
                -v "${DOCKER_PROJECT_NAME}_${volume}:/data:ro" \
                -v "$backup_dir:/backup" \
                alpine:latest \
                tar czf "/backup/${volume}.tar.gz" -C /data . 2>/dev/null || {
                log "WARN" "Failed to backup volume: $volume"
            }
        fi
    done <<< "$volumes"
    
    log "SUCCESS" "Volume backup completed: $backup_dir"
}

# Restore Docker volumes
docker_restore_volumes() {
    local backup_dir="$1"
    
    if [[ ! -d "$backup_dir" ]]; then
        log "ERROR" "Backup directory not found: $backup_dir"
        return 1
    fi
    
    log "STEP" "Restoring Docker volumes from: $backup_dir"
    
    # Stop services
    docker_compose down
    
    # Restore each volume backup
    for backup_file in "$backup_dir"/*.tar.gz; do
        if [[ -f "$backup_file" ]]; then
            local volume_name
            volume_name=$(basename "$backup_file" .tar.gz)
            
            log "INFO" "Restoring volume: $volume_name"
            
            # Create volume if it doesn't exist
            docker volume create "${DOCKER_PROJECT_NAME}_${volume_name}" >/dev/null 2>&1 || true
            
            # Restore data
            docker run --rm \
                -v "${DOCKER_PROJECT_NAME}_${volume_name}:/data" \
                -v "$backup_dir:/backup:ro" \
                alpine:latest \
                tar xzf "/backup/${volume_name}.tar.gz" -C /data 2>/dev/null || {
                log "WARN" "Failed to restore volume: $volume_name"
            }
        fi
    done
    
    log "SUCCESS" "Volume restore completed"
}

# =============================================================================
# Registry and Authentication (Lines 301-400)
# =============================================================================

# Docker registry login
docker_registry_login() {
    local registry="${1:-$DOCKER_REGISTRY_URL}"
    local username="${2:-$DOCKER_REGISTRY_USERNAME}"
    local registry_pass="${3:-$DOCKER_REGISTRY_PASSWORD}"
    
    if [[ -z "$registry" || -z "$username" || -z "$registry_pass" ]]; then
        log "ERROR" "Registry credentials not provided"
        return 1
    fi
    
    log "STEP" "Logging into Docker registry: $registry"
    
    echo "$registry_pass" | docker login "$registry" --username "$username" --password-stdin || {
        log "ERROR" "Failed to login to Docker registry"
        return 1
    }
    
    log "SUCCESS" "Successfully logged into Docker registry"
}

# Pull images
docker_pull_images() {
    log "STEP" "Pulling Docker images..."
    
    # Get list of images from compose file
    local images
    images=$(docker_compose config --images 2>/dev/null || true)
    
    if [[ -z "$images" ]]; then
        log "WARN" "No images found in compose file"
        return 0
    fi
    
    # Pull each image
    while IFS= read -r image; do
        if [[ -n "$image" ]]; then
            log "INFO" "Pulling image: $image"
            docker pull "$image" || {
                log "WARN" "Failed to pull image: $image"
            }
        fi
    done <<< "$images"
    
    log "SUCCESS" "Image pull completed"
}

# Build images
docker_build_images() {
    local no_cache="${1:-false}"
    
    log "STEP" "Building Docker images..."
    
    local build_args=""
    if [[ "$no_cache" == "true" ]]; then
        build_args="--no-cache"
    fi
    
    docker_compose build $build_args || {
        log "ERROR" "Failed to build Docker images"
        return 1
    }
    
    log "SUCCESS" "Docker images built successfully"
}

# =============================================================================
# Container Management and Utilities (Lines 401-500)
# =============================================================================

# Execute command in container
docker_exec() {
    local service="$1"
    shift
    local command=("$@")
    
    if [[ -z "$service" ]]; then
        log "ERROR" "Service name required"
        return 1
    fi
    
    # Check if service is running
    if ! docker_compose ps "$service" | grep -q "Up"; then
        log "ERROR" "Service '$service' is not running"
        return 1
    fi
    
    # Execute command
    if [[ ${#command[@]} -eq 0 ]]; then
        # Interactive shell
        docker_compose exec "$service" /bin/bash || docker_compose exec "$service" /bin/sh
    else
        # Execute specific command
        docker_compose exec "$service" "${command[@]}"
    fi
}

# Get container shell
docker_shell() {
    local service="${1:-app}"
    
    log "INFO" "Opening shell in service: $service"
    docker_exec "$service"
}

# Clean Docker system
docker_clean_system() {
    local force="${1:-false}"
    
    if [[ "$force" != "true" ]]; then
        log "WARN" "This will remove all unused Docker resources"
        if ! ask_yes_no "Continue with system cleanup?"; then
            log "INFO" "System cleanup cancelled"
            return 0
        fi
    fi
    
    log "STEP" "Cleaning Docker system..."
    
    # Stop all containers
    docker_compose down
    
    # Remove unused resources
    docker system prune -f
    
    # Remove unused images
    docker image prune -f
    
    # Remove unused networks
    docker network prune -f
    
    log "SUCCESS" "Docker system cleaned"
}

# Show Docker system information
docker_system_info() {
    log "INFO" "Docker System Information:"
    
    # Docker version
    local docker_version
    docker_version=$(docker --version | cut -d' ' -f3 | tr -d ',')
    echo "  Docker Version: $docker_version"
    
    # Docker Compose version
    local compose_version
    compose_version=$(docker compose version --short 2>/dev/null || echo "unknown")
    echo "  Docker Compose Version: $compose_version"
    
    # System info
    echo "  Root Directory: $(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo 'unknown')"
    echo "  Storage Driver: $(docker info --format '{{.Driver}}' 2>/dev/null || echo 'unknown')"
    
    # Resource usage
    echo
    log "INFO" "Resource Usage:"
    docker system df 2>/dev/null || echo "  Unable to get system usage"
}

# Health check for services
docker_health_check() {
    log "INFO" "Docker Services Health Check:"
    
    # Get service status
    local services_status
    services_status=$(docker_compose ps --format "{{.Name}} {{.Status}}" 2>/dev/null || true)
    
    if [[ -z "$services_status" ]]; then
        log "WARN" "No services found"
        return 1
    fi
    
    local healthy=0
    local total=0
    
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local service_name status
            service_name=$(echo "$line" | awk '{print $1}')
            status=$(echo "$line" | awk '{print $2}')
            
            ((total++))
            
            if [[ "$status" =~ Up|running ]]; then
                echo "  ✅ $service_name: $status"
                ((healthy++))
            else
                echo "  ❌ $service_name: $status"
            fi
        fi
    done <<< "$services_status"
    
    echo
    if [[ $healthy -eq $total ]]; then
        log "SUCCESS" "All services are healthy ($healthy/$total)"
        return 0
    else
        log "WARN" "Some services are unhealthy ($healthy/$total)"
        return 1
    fi
}

# Export main functions for external use
export -f docker_init docker_validate_setup docker_test_config docker_check_resources
export -f docker_compose docker_start docker_stop docker_restart docker_status docker_logs
export -f docker_clean_volumes docker_backup_volumes docker_restore_volumes
export -f docker_registry_login docker_pull_images docker_build_images
export -f docker_exec docker_shell docker_clean_system docker_system_info docker_health_check 