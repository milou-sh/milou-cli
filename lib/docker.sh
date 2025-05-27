#!/bin/bash

# =============================================================================
# Milou CLI - Consolidated Docker Module
# All Docker functionality in one organized module (500 lines max)
# =============================================================================

# Preserve PATH to prevent corruption during environment loading
if [[ -n "${SYSTEM_PATH:-}" ]]; then
    export PATH="$SYSTEM_PATH"
fi

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
        "${CONFIG_DIR:-${HOME}/.milou}/.env"
        "${ENV_FILE:-}"
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
    
    # Find compose file (look in script directory, not env file directory)
    local compose_file="${script_dir}/${DEFAULT_COMPOSE_FILE}"
    if [[ ! -f "$compose_file" ]]; then
        # Try relative to current directory
        compose_file="$DEFAULT_COMPOSE_FILE"
        if [[ ! -f "$compose_file" ]]; then
            log "ERROR" "Docker Compose file not found: $compose_file"
            log "DEBUG" "Searched in: ${script_dir}/${DEFAULT_COMPOSE_FILE} and $DEFAULT_COMPOSE_FILE"
            return 1
        fi
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
    
    # Get service status using docker ps directly since docker_compose might not be initialized
    local services_status
    services_status=$(docker ps --filter "name=milou-" --format "{{.Names}} {{.Status}}" 2>/dev/null || true)
    
    if [[ -z "$services_status" ]]; then
        log "WARN" "No Milou services found"
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
            
            if [[ "$status" =~ (Up|running) ]]; then
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

# =============================================================================
# Update and Version Management (Lines 601-700)
# =============================================================================

# Update Docker images to new versions
docker_update_images() {
    local target_version="${1:-latest}"
    local services=("${@:2}")
    
    log "STEP" "Updating Docker images to version: $target_version"
    
    # Validate GitHub token for private registry access
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        log "ERROR" "GitHub token required for image updates"
        log "INFO" "Use: ./milou.sh update --token YOUR_GITHUB_TOKEN"
        return 1
    fi
    
    # Login to GitHub Container Registry
    # For GitHub Container Registry, use the token as both username and password
    if ! docker_registry_login "ghcr.io" "${GITHUB_TOKEN}" "${GITHUB_TOKEN}"; then
        log "ERROR" "Failed to authenticate with GitHub Container Registry"
        return 1
    fi
    
    # Create backup before update
    if ! docker_backup_before_update; then
        log "ERROR" "Failed to create backup before update"
        return 1
    fi
    
    # Get current image versions for rollback
    local current_images
    current_images=$(docker_compose config --images 2>/dev/null)
    echo "$current_images" > "/tmp/milou-images-backup-$(date +%Y%m%d-%H%M%S).txt"
    
    # Update image tags in environment
    if ! docker_update_image_tags "$target_version" "${services[@]}"; then
        log "ERROR" "Failed to update image tags"
        return 1
    fi
    
    # Pull new images
    log "INFO" "Pulling new Docker images..."
    if ! docker_pull_images; then
        log "ERROR" "Failed to pull new images"
        return 1
    fi
    
    # Validate new images
    if ! docker_validate_images; then
        log "ERROR" "Image validation failed"
        return 1
    fi
    
    log "SUCCESS" "Docker images updated successfully"
    return 0
}

# Update image tags in environment file
docker_update_image_tags() {
    local target_version="$1"
    shift
    local services=("$@")
    
    log "INFO" "Updating image tags to version: $target_version"
    
    # Backup current .env file
    cp "$DOCKER_ENV_FILE" "${DOCKER_ENV_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
    
    # Define image tag mappings
    local -A image_tags=(
        ["backend"]="MILOU_BACKEND_TAG"
        ["frontend"]="MILOU_FRONTEND_TAG"
        ["engine"]="MILOU_ENGINE_TAG"
        ["nginx"]="MILOU_NGINX_TAG"
        ["database"]="MILOU_DATABASE_TAG"
    )
    
    # Update specific services or all if none specified
    if [[ ${#services[@]} -eq 0 ]]; then
        services=("${!image_tags[@]}")
    fi
    
    # Update each service tag
    for service in "${services[@]}"; do
        local tag_var="${image_tags[$service]:-}"
        if [[ -n "$tag_var" ]]; then
            log "INFO" "Updating $service to version $target_version"
            
            # Update or add the tag in .env file
            if grep -q "^${tag_var}=" "$DOCKER_ENV_FILE"; then
                sed -i "s/^${tag_var}=.*/${tag_var}=${target_version}/" "$DOCKER_ENV_FILE"
            else
                echo "${tag_var}=${target_version}" >> "$DOCKER_ENV_FILE"
            fi
        else
            log "WARN" "Unknown service: $service"
        fi
    done
    
    log "SUCCESS" "Image tags updated in environment file"
    return 0
}

# Validate Docker images integrity and availability
docker_validate_images() {
    log "INFO" "Validating Docker images..."
    
    # Get list of images from updated compose file
    local images
    images=$(docker_compose config --images 2>/dev/null || true)
    
    if [[ -z "$images" ]]; then
        log "ERROR" "No images found in compose configuration"
        return 1
    fi
    
    local validation_errors=0
    
    # Validate each image
    while IFS= read -r image; do
        if [[ -n "$image" ]]; then
            log "INFO" "Validating image: $image"
            
            # Check if image exists locally
            if ! docker image inspect "$image" >/dev/null 2>&1; then
                log "ERROR" "Image not found locally: $image"
                ((validation_errors++))
                continue
            fi
            
            # Check image size (basic validation)
            local image_size
            image_size=$(docker image inspect "$image" --format '{{.Size}}' 2>/dev/null || echo "0")
            if [[ "$image_size" -lt 1000000 ]]; then  # Less than 1MB is suspicious
                log "WARN" "Image seems unusually small: $image ($image_size bytes)"
            fi
            
            log "SUCCESS" "✅ Image validated: $image"
        fi
    done <<< "$images"
    
    if [[ $validation_errors -eq 0 ]]; then
        log "SUCCESS" "All images validated successfully"
        return 0
    else
        log "ERROR" "Image validation failed with $validation_errors errors"
        return 1
    fi
}

# Create comprehensive backup before update
docker_backup_before_update() {
    local backup_timestamp
    backup_timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_dir="./backups/pre-update-${backup_timestamp}"
    
    log "STEP" "Creating comprehensive backup before update..."
    
    # Create backup directory
    safe_mkdir "$backup_dir"
    
    # Backup configuration files
    log "INFO" "Backing up configuration files..."
    cp "$DOCKER_ENV_FILE" "$backup_dir/env-backup.txt"
    cp "$DOCKER_COMPOSE_FILE" "$backup_dir/compose-backup.yml"
    
    # Backup current image list
    log "INFO" "Backing up current image versions..."
    docker_compose config --images > "$backup_dir/images-backup.txt" 2>/dev/null || true
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}" > "$backup_dir/docker-images-backup.txt"
    
    # Backup Docker volumes
    log "INFO" "Backing up Docker volumes..."
    if ! docker_backup_volumes "$backup_dir/volumes"; then
        log "WARN" "Volume backup failed, continuing anyway..."
    fi
    
    # Create database backup if database service is running
    if docker_compose ps db | grep -q "Up"; then
        log "INFO" "Creating database backup..."
        docker_backup_database "$backup_dir/database-backup.sql" || {
            log "WARN" "Database backup failed, continuing anyway..."
        }
    fi
    
    # Store backup location for potential rollback
    echo "$backup_dir" > "/tmp/milou-last-backup-location.txt"
    
    log "SUCCESS" "Comprehensive backup created: $backup_dir"
    return 0
}

# Backup database specifically
docker_backup_database() {
    local backup_file="${1:-./database-backup-$(date +%Y%m%d-%H%M%S).sql}"
    
    log "INFO" "Creating database backup: $backup_file"
    
    # Get database credentials from environment
    local db_user db_password db_name
    db_user=$(grep "^POSTGRES_USER=" "$DOCKER_ENV_FILE" | cut -d'=' -f2)
    db_password=$(grep "^POSTGRES_PASSWORD=" "$DOCKER_ENV_FILE" | cut -d'=' -f2)
    db_name=$(grep "^POSTGRES_DB=" "$DOCKER_ENV_FILE" | cut -d'=' -f2)
    
    if [[ -z "$db_user" || -z "$db_password" || -z "$db_name" ]]; then
        log "ERROR" "Database credentials not found in environment file"
        return 1
    fi
    
    # Create database backup using pg_dump
    docker_compose exec -T db pg_dump \
        -U "$db_user" \
        -d "$db_name" \
        --clean \
        --if-exists \
        --create \
        --verbose > "$backup_file" 2>/dev/null || {
        log "ERROR" "Failed to create database backup"
        return 1
    }
    
    # Verify backup file
    if [[ -f "$backup_file" && -s "$backup_file" ]]; then
        local backup_size
        backup_size=$(du -h "$backup_file" | cut -f1)
        log "SUCCESS" "Database backup created: $backup_file ($backup_size)"
        return 0
    else
        log "ERROR" "Database backup file is empty or missing"
        return 1
    fi
}

# Rollback to previous image versions
docker_rollback_images() {
    local backup_location="${1:-}"
    
    if [[ -z "$backup_location" && -f "/tmp/milou-last-backup-location.txt" ]]; then
        backup_location=$(cat "/tmp/milou-last-backup-location.txt")
    fi
    
    if [[ -z "$backup_location" || ! -d "$backup_location" ]]; then
        log "ERROR" "Backup location not found for rollback"
        return 1
    fi
    
    log "STEP" "Rolling back Docker images from backup: $backup_location"
    
    # Stop current services
    log "INFO" "Stopping current services..."
    docker_compose down
    
    # Restore configuration files
    log "INFO" "Restoring configuration files..."
    if [[ -f "$backup_location/env-backup.txt" ]]; then
        cp "$backup_location/env-backup.txt" "$DOCKER_ENV_FILE"
    fi
    
    # Restore database if backup exists
    if [[ -f "$backup_location/database-backup.sql" ]]; then
        log "INFO" "Restoring database backup..."
        docker_restore_database "$backup_location/database-backup.sql" || {
            log "WARN" "Database restore failed"
        }
    fi
    
    # Restore volumes if backup exists
    if [[ -d "$backup_location/volumes" ]]; then
        log "INFO" "Restoring volume backups..."
        docker_restore_volumes "$backup_location/volumes" || {
            log "WARN" "Volume restore failed"
        }
    fi
    
    # Start services with restored configuration
    log "INFO" "Starting services with restored configuration..."
    if docker_start; then
        log "SUCCESS" "Rollback completed successfully"
        return 0
    else
        log "ERROR" "Failed to start services after rollback"
        return 1
    fi
}

# Restore database from backup
docker_restore_database() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        log "ERROR" "Database backup file not found: $backup_file"
        return 1
    fi
    
    log "INFO" "Restoring database from backup: $backup_file"
    
    # Start database service if not running
    if ! docker_compose ps db | grep -q "Up"; then
        docker_compose up -d db
        sleep 10  # Wait for database to be ready
    fi
    
    # Restore database
    docker_compose exec -T db psql \
        -U "$(grep "^POSTGRES_USER=" "$DOCKER_ENV_FILE" | cut -d'=' -f2)" \
        -d postgres < "$backup_file" || {
        log "ERROR" "Failed to restore database"
        return 1
    }
    
    log "SUCCESS" "Database restored successfully"
    return 0
}

# Extended health check for updates
docker_health_check_extended() {
    local timeout="${1:-300}"  # 5 minutes default timeout
    local check_interval="${2:-10}"  # 10 seconds between checks
    
    log "INFO" "Running extended health check (timeout: ${timeout}s)..."
    
    # In development mode, skip extended health checks if no services are running
    if command -v milou_is_development >/dev/null 2>&1 && milou_is_development; then
        log "INFO" "Development mode detected - checking for running services..."
        if ! docker_compose ps --services --filter "status=running" 2>/dev/null | grep -q .; then
            log "INFO" "No services running in development mode - skipping extended health check"
            log "SUCCESS" "✅ Health check skipped (development mode, no services)"
            return 0
        fi
    fi
    
    local start_time
    start_time=$(date +%s)
    
    while true; do
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $timeout ]]; then
            log "ERROR" "Health check timeout after ${timeout} seconds"
            return 1
        fi
        
        # Run standard health check
        if docker_health_check; then
            # Additional checks for update validation
            if docker_validate_service_connectivity && docker_validate_api_endpoints; then
                log "SUCCESS" "Extended health check passed"
                return 0
            fi
        fi
        
        log "INFO" "Health check in progress... (${elapsed}/${timeout}s)"
        sleep "$check_interval"
    done
}

# Validate service connectivity
docker_validate_service_connectivity() {
    log "INFO" "Validating service connectivity..."
    
    # Check database connectivity
    if docker_compose exec -T db pg_isready >/dev/null 2>&1; then
        log "SUCCESS" "✅ Database connectivity verified"
    else
        log "ERROR" "❌ Database connectivity failed"
        return 1
    fi
    
    # Check Redis connectivity
    if docker_compose exec -T redis redis-cli ping >/dev/null 2>&1; then
        log "SUCCESS" "✅ Redis connectivity verified"
    else
        log "ERROR" "❌ Redis connectivity failed"
        return 1
    fi
    
    # Check RabbitMQ connectivity
    if docker_compose exec -T rabbitmq rabbitmqctl status >/dev/null 2>&1; then
        log "SUCCESS" "✅ RabbitMQ connectivity verified"
    else
        log "ERROR" "❌ RabbitMQ connectivity failed"
        return 1
    fi
    
    return 0
}

# Validate API endpoints
docker_validate_api_endpoints() {
    log "INFO" "Validating API endpoints..."
    
    # Get backend port
    local backend_port
    backend_port=$(grep "^PORT=" "$DOCKER_ENV_FILE" | cut -d'=' -f2 || echo "9999")
    
    # Check backend health endpoint
    local backend_health_url="http://localhost:${backend_port}/health"
    if curl -f -s "$backend_health_url" >/dev/null 2>&1; then
        log "SUCCESS" "✅ Backend API endpoint verified"
    else
        log "ERROR" "❌ Backend API endpoint failed: $backend_health_url"
        return 1
    fi
    
    # Check frontend accessibility
    if curl -f -s "http://localhost:80/" >/dev/null 2>&1; then
        log "SUCCESS" "✅ Frontend endpoint verified"
    else
        log "ERROR" "❌ Frontend endpoint failed"
        return 1
    fi
    
    return 0
}

# Smart Docker startup that handles all scenarios
smart_docker_start() {
    log "STEP" "🧠 Smart Docker startup for all installation scenarios"
    
    # Clean conflicting environment variables before starting
    clean_system_env_vars
    
    # Ensure environment files are synced
    if [[ -f ".env" ]]; then
        sync_env_files ".env" "static/.env"
    fi
    
    # Detect current state
    local install_state=$(detect_installation_state)
    local has_running_services=$(docker ps -q --filter "name=milou-" | wc -l)
    
    log "INFO" "Installation state: $install_state"
    log "INFO" "Running services: $has_running_services"
    
    # Handle different scenarios
    case "$install_state" in
        "fresh")
            log "INFO" "Fresh installation - starting all services"
            docker_start_fresh
            ;;
        "partial")
            log "INFO" "Partial installation - cleaning up and restarting"
            docker_start_partial
            ;;
        "complete")
            # Check if all expected services are running
            local expected_containers=("milou-database" "milou-redis" "milou-rabbitmq" "milou-backend" "milou-frontend" "milou-nginx")
            local running_expected=0
            
            for container in "${expected_containers[@]}"; do
                if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
                    ((running_expected++))
                fi
            done
            
            if [[ $running_expected -eq ${#expected_containers[@]} ]]; then
                log "INFO" "All services running - performing health check"
                docker_health_check || docker_restart_unhealthy
            elif [[ $running_expected -gt 0 ]]; then
                log "INFO" "Partial services running ($running_expected/${#expected_containers[@]}) - restarting all"
                docker_start_partial
            else
                log "INFO" "Complete installation - starting services"
                docker_start_complete
            fi
            ;;
        "corrupted")
            log "WARN" "Corrupted installation - performing recovery startup"
            docker_start_recovery
            ;;
        *)
            log "ERROR" "Unknown installation state: $install_state"
            return 1
            ;;
    esac
    
    # Final health check and validation
    if docker_startup_validation; then
        log "SUCCESS" "Smart Docker startup completed successfully"
        return 0
    else
        log "ERROR" "Smart Docker startup validation failed"
        return 1
    fi
}

# Start fresh Docker installation
docker_start_fresh() {
    log "INFO" "Starting fresh Docker installation"
    
    # Ensure proxy network exists
    if ! docker network ls | grep -q "proxy"; then
        log "INFO" "Creating proxy network"
        docker network create proxy || log "WARN" "Failed to create proxy network"
    fi
    
    # Start services
    docker_compose_up
}

# Start partial Docker installation
docker_start_partial() {
    log "INFO" "Starting partial Docker installation"
    
    # Stop any running services first
    log "INFO" "Stopping existing services"
    docker_compose_down || true
    
    # Clean up orphaned containers
    docker_cleanup_orphaned
    
    # Ensure networks exist
    docker_ensure_networks
    
    # Start services
    docker_compose_up
}

# Start complete Docker installation
docker_start_complete() {
    log "INFO" "Starting complete Docker installation"
    
    # Ensure networks exist
    docker_ensure_networks
    
    # Start services
    docker_compose_up
}

# Start recovery Docker installation
docker_start_recovery() {
    log "WARN" "Starting recovery Docker installation"
    
    # Stop everything
    log "INFO" "Stopping all services for recovery"
    docker_compose_down || true
    
    # Clean up everything
    docker_cleanup_all
    
    # Recreate networks
    docker_recreate_networks
    
    # Start with force recreate
    docker_compose_up_force_recreate
}

# Ensure required networks exist
docker_ensure_networks() {
    log "INFO" "Ensuring required Docker networks exist"
    
    # Check and create proxy network
    if ! docker network ls | grep -q "proxy"; then
        log "INFO" "Creating proxy network"
        docker network create proxy || log "WARN" "Failed to create proxy network"
    fi
    
    # Check milou_network (should be created by compose)
    if ! docker network ls | grep -q "static_milou_network"; then
        log "DEBUG" "Milou network will be created by docker-compose"
    fi
}

# Recreate networks (for recovery)
docker_recreate_networks() {
    log "INFO" "Recreating Docker networks"
    
    # Remove existing networks (ignore errors)
    docker network rm proxy 2>/dev/null || true
    docker network rm static_milou_network 2>/dev/null || true
    
    # Recreate proxy network
    docker network create proxy || log "ERROR" "Failed to recreate proxy network"
}

# Clean up orphaned containers
docker_cleanup_orphaned() {
    log "INFO" "Cleaning up orphaned containers"
    
    # Remove stopped containers
    docker container prune -f >/dev/null 2>&1 || true
    
    # Remove orphaned volumes
    docker volume prune -f >/dev/null 2>&1 || true
}

# Clean up everything (for recovery)
docker_cleanup_all() {
    log "WARN" "Performing complete Docker cleanup"
    
    # Stop and remove all milou containers
    docker ps -a --filter "name=milou-" -q | xargs -r docker rm -f 2>/dev/null || true
    
    # Remove unused networks
    docker network prune -f >/dev/null 2>&1 || true
    
    # Remove unused volumes (be careful here)
    docker volume ls --filter "label=project=milou" -q | xargs -r docker volume rm 2>/dev/null || true
}

# Docker compose up with error handling
docker_compose_up() {
    log "INFO" "Starting Docker services with compose"
    
    local compose_file="./static/docker-compose.yml"
    local env_file=".env"
    
    # Check if files exist
    if [[ ! -f "$compose_file" ]]; then
        log "ERROR" "Docker compose file not found: $compose_file"
        return 1
    fi
    
    if [[ ! -f "$env_file" ]]; then
        log "ERROR" "Environment file not found: $env_file"
        return 1
    fi
    
    # Use docker compose (new syntax) or docker-compose (legacy)
    local compose_cmd="docker compose"
    if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
        if command -v docker-compose >/dev/null 2>&1; then
            compose_cmd="docker-compose"
        else
            log "ERROR" "Neither 'docker compose' nor 'docker-compose' is available"
            return 1
        fi
    fi
    
    # Start services
    log "INFO" "Executing: $compose_cmd -f $compose_file --env-file $env_file up -d"
    
    if $compose_cmd -f "$compose_file" --env-file "$env_file" up -d; then
        log "SUCCESS" "Docker services started successfully"
        return 0
    else
        log "ERROR" "Failed to start Docker services"
        return 1
    fi
}

# Docker compose up with force recreate
docker_compose_up_force_recreate() {
    log "INFO" "Starting Docker services with force recreate"
    
    local compose_file="./static/docker-compose.yml"
    local env_file=".env"
    
    # Use docker compose (new syntax) or docker-compose (legacy)
    local compose_cmd="docker compose"
    if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
        if command -v docker-compose >/dev/null 2>&1; then
            compose_cmd="docker-compose"
        else
            log "ERROR" "Neither 'docker compose' nor 'docker-compose' is available"
            return 1
        fi
    fi
    
    # Start services with force recreate
    log "INFO" "Executing: $compose_cmd -f $compose_file --env-file $env_file up -d --force-recreate"
    
    if $compose_cmd -f "$compose_file" --env-file "$env_file" up -d --force-recreate; then
        log "SUCCESS" "Docker services started with force recreate"
        return 0
    else
        log "ERROR" "Failed to start Docker services with force recreate"
        return 1
    fi
}

# Docker compose down with error handling
docker_compose_down() {
    log "INFO" "Stopping Docker services with compose"
    
    local compose_file="./static/docker-compose.yml"
    local env_file=".env"
    
    # Use docker compose (new syntax) or docker-compose (legacy)
    local compose_cmd="docker compose"
    if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
        if command -v docker-compose >/dev/null 2>&1; then
            compose_cmd="docker-compose"
        else
            log "WARN" "Neither 'docker compose' nor 'docker-compose' is available"
            return 1
        fi
    fi
    
    # Stop services
    log "INFO" "Executing: $compose_cmd -f $compose_file --env-file $env_file down"
    
    if $compose_cmd -f "$compose_file" --env-file "$env_file" down; then
        log "SUCCESS" "Docker services stopped successfully"
        return 0
    else
        log "WARN" "Some issues occurred while stopping Docker services"
        return 1
    fi
}

# Restart unhealthy services
docker_restart_unhealthy() {
    log "INFO" "Restarting unhealthy Docker services"
    
    # Get unhealthy containers
    local unhealthy_containers=$(docker ps --filter "health=unhealthy" --format "{{.Names}}" | grep "milou-" || true)
    
    if [[ -n "$unhealthy_containers" ]]; then
        log "WARN" "Found unhealthy containers: $unhealthy_containers"
        
        # Restart each unhealthy container
        echo "$unhealthy_containers" | while read -r container; do
            if [[ -n "$container" ]]; then
                log "INFO" "Restarting unhealthy container: $container"
                docker restart "$container" || log "ERROR" "Failed to restart $container"
            fi
        done
    else
        log "INFO" "No unhealthy containers found"
    fi
}

# Startup validation
docker_startup_validation() {
    log "INFO" "Performing Docker startup validation"
    
    local validation_errors=0
    
    # Check if all expected containers are running
    local expected_containers=("milou-database" "milou-redis" "milou-rabbitmq" "milou-backend" "milou-frontend" "milou-nginx")
    
    for container in "${expected_containers[@]}"; do
        if ! docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
            log "ERROR" "Expected container not running: $container"
            ((validation_errors++))
        else
            log "DEBUG" "Container running: $container"
        fi
    done
    
    # Wait for health checks to pass
    log "INFO" "Waiting for health checks to pass..."
    local max_wait=120  # 2 minutes
    local wait_time=0
    
    while [[ $wait_time -lt $max_wait ]]; do
        local unhealthy_count=$(docker ps --filter "health=unhealthy" --format "{{.Names}}" | grep "milou-" | wc -l)
        
        if [[ $unhealthy_count -eq 0 ]]; then
            log "SUCCESS" "All health checks passed"
            break
        fi
        
        log "INFO" "Waiting for $unhealthy_count services to become healthy... (${wait_time}s/${max_wait}s)"
        sleep 10
        ((wait_time += 10))
    done
    
    # Final health check
    if ! docker_health_check; then
        log "ERROR" "Health check failed after startup"
        ((validation_errors++))
    fi
    
    if [[ $validation_errors -eq 0 ]]; then
        log "SUCCESS" "Docker startup validation passed"
        return 0
    else
        log "ERROR" "Docker startup validation failed with $validation_errors errors"
        return 1
    fi
}

# Export main functions for external use
export -f docker_init docker_validate_setup docker_test_config docker_check_resources
export -f docker_compose docker_start docker_stop docker_restart docker_status docker_logs
export -f docker_clean_volumes docker_backup_volumes docker_restore_volumes
export -f docker_registry_login docker_pull_images docker_build_images
export -f docker_exec docker_shell docker_clean_system docker_system_info docker_health_check
export -f docker_update_images docker_update_image_tags docker_validate_images
export -f docker_backup_before_update docker_backup_database docker_rollback_images
export -f docker_restore_database docker_health_check_extended docker_validate_service_connectivity
export -f docker_validate_api_endpoints 