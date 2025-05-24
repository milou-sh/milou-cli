#!/bin/bash

# =============================================================================
# Docker Service Manager - Centralized Docker Operations
# State-of-the-art Docker service management for Milou CLI
# =============================================================================

# Source environment manager
source "${BASH_SOURCE%/*}/environment-manager.sh" 2>/dev/null || true

# Global Docker state
declare -g DOCKER_ENV_FILE=""
declare -g DOCKER_COMPOSE_FILE=""
declare -g DOCKER_PROJECT_NAME=""
declare -g DOCKER_VOLUMES_CLEANED=false

# =============================================================================
# Docker Environment Setup
# =============================================================================

# Initialize Docker environment
initialize_docker_environment() {
    log "DEBUG" "Initializing Docker environment..."
    
    # Ensure environment is loaded
    if ! is_environment_configured; then
        if ! initialize_environment_manager; then
            log "ERROR" "Failed to initialize environment manager"
            return 1
        fi
    fi
    
    # Set up Docker paths
    DOCKER_COMPOSE_FILE="${SCRIPT_DIR}/static/docker-compose.yml"
    DOCKER_ENV_FILE=$(export_environment_for_docker)
    DOCKER_PROJECT_NAME=$(get_env_var "COMPOSE_PROJECT_NAME" "static")
    
    # Ensure SSL path is absolute for Docker
    if command -v resolve_ssl_path_for_docker >/dev/null 2>&1; then
        local ssl_path
        ssl_path=$(get_env_var "SSL_CERT_PATH" "./ssl")
        local absolute_ssl_path
        absolute_ssl_path=$(resolve_ssl_path_for_docker "$ssl_path")
        
        # Update environment with absolute SSL path
        if [[ "$ssl_path" != "$absolute_ssl_path" ]]; then
            log "DEBUG" "Updating SSL_CERT_PATH: $ssl_path -> $absolute_ssl_path"
            export SSL_CERT_PATH="$absolute_ssl_path"
            
            # Update the environment file
            if [[ -f "$DOCKER_ENV_FILE" ]]; then
                sed -i "s|^SSL_CERT_PATH=.*|SSL_CERT_PATH=$absolute_ssl_path|" "$DOCKER_ENV_FILE"
            fi
        fi
    fi
    
    # Validate Docker setup
    if ! validate_docker_setup; then
        return 1
    fi
    
    log "DEBUG" "Docker environment initialized successfully"
    return 0
}

# Validate Docker setup
validate_docker_setup() {
    # Check Docker access
    if ! check_docker_access; then
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
    
    # Test Docker Compose configuration
    if ! test_docker_compose_config; then
        return 1
    fi
    
    return 0
}

# =============================================================================
# Enhanced Docker Compose Operations
# =============================================================================

# Run Docker Compose with proper environment
run_docker_compose() {
    if [[ -z "$DOCKER_ENV_FILE" || -z "$DOCKER_COMPOSE_FILE" ]]; then
        if ! initialize_docker_environment; then
            log "ERROR" "Failed to initialize Docker environment"
            return 1
        fi
    fi
    
    log "TRACE" "Running: docker compose --env-file '$DOCKER_ENV_FILE' -f '$DOCKER_COMPOSE_FILE' $*"
    docker compose --env-file "$DOCKER_ENV_FILE" -f "$DOCKER_COMPOSE_FILE" "$@"
}

# Test Docker Compose configuration
test_docker_compose_config() {
    log "DEBUG" "Testing Docker Compose configuration..."
    
    if run_docker_compose config --quiet; then
        log "SUCCESS" "Docker Compose configuration is valid"
        return 0
    else
        log "ERROR" "Docker Compose configuration is invalid"
        log "INFO" "💡 Check your environment file: $DOCKER_ENV_FILE"
        log "INFO" "💡 Check your compose file: $DOCKER_COMPOSE_FILE"
        return 1
    fi
}

# =============================================================================
# Volume Management with Credential Change Detection
# =============================================================================

# Clean up volumes when credentials change
cleanup_volumes_on_credential_change() {
    if ! check_credentials_changed; then
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
    run_docker_compose down
    
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
    store_credentials_hash
    DOCKER_VOLUMES_CLEANED=true
    
    log "SUCCESS" "Volume cleanup completed"
    log "INFO" "All services will start with fresh credentials"
    return 0
}

# =============================================================================
# Service Management
# =============================================================================

# Start services with enhanced error handling
start_services() {
    log "STEP" "Starting Milou services..."
    
    # Initialize Docker environment
    if ! initialize_docker_environment; then
        return 1
    fi
    
    # Clean volumes if credentials changed
    cleanup_volumes_on_credential_change
    
    # Create networks
    create_networks
    
    # Test configuration before starting
    if ! test_docker_compose_config; then
        log "ERROR" "Docker Compose configuration is invalid"
        return 1
    fi
    
    # Start services
    log "INFO" "Starting services with Docker Compose..."
    if run_docker_compose up -d; then
        log "SUCCESS" "Services started successfully"
        
        # Give RabbitMQ a moment to initialize if volumes were cleaned
        if [[ "$DOCKER_VOLUMES_CLEANED" == "true" ]]; then
            log "INFO" "Volumes were cleaned - allowing extra time for RabbitMQ initialization..."
            sleep 10
        fi
        
        # Wait for services to be healthy
        if wait_for_services_healthy; then
            log "SUCCESS" "All services are healthy"
        else
            log "WARN" "Some services may need more time to become healthy"
            
            # Check for specific RabbitMQ authentication issues
            if check_rabbitmq_auth_issues; then
                log "INFO" "Attempting to resolve RabbitMQ authentication issues..."
                if restart_rabbitmq_dependent_services; then
                    log "SUCCESS" "RabbitMQ authentication issues resolved"
                else
                    log "WARN" "RabbitMQ authentication issues may persist"
                fi
            fi
        fi
        
        return 0
    else
        log "ERROR" "Failed to start services"
        return 1
    fi
}

# Stop services
stop_services() {
    log "STEP" "Stopping Milou services..."
    
    if ! initialize_docker_environment; then
        return 1
    fi
    
    if run_docker_compose down; then
        log "SUCCESS" "Services stopped successfully"
        return 0
    else
        log "ERROR" "Failed to stop services"
        return 1
    fi
}

# Restart services
restart_services() {
    log "STEP" "Restarting Milou services..."
    
    if stop_services && start_services; then
        log "SUCCESS" "Services restarted successfully"
        return 0
    else
        log "ERROR" "Failed to restart services"
        return 1
    fi
}

# =============================================================================
# Service Health Monitoring
# =============================================================================

# Wait for services to become healthy
wait_for_services_healthy() {
    local max_wait=300  # 5 minutes
    local wait_interval=10
    local elapsed=0
    
    log "INFO" "Waiting for services to become healthy..."
    
    while [[ $elapsed -lt $max_wait ]]; do
        local healthy_count=0
        local total_count=0
        
        # Get service status
        local services_info
        services_info=$(run_docker_compose ps --format "json" 2>/dev/null || echo "[]")
        
        if [[ "$services_info" != "[]" ]]; then
            while read -r service; do
                if [[ -n "$service" ]]; then
                    ((total_count++))
                    local health_status
                    health_status=$(echo "$service" | jq -r '.Health // "unknown"' 2>/dev/null || echo "unknown")
                    local service_name
                    service_name=$(echo "$service" | jq -r '.Service // "unknown"' 2>/dev/null || echo "unknown")
                    
                    case "$health_status" in
                        "healthy")
                            ((healthy_count++))
                            ;;
                        "unhealthy")
                            log "WARN" "Service $service_name is unhealthy"
                            ;;
                        "starting")
                            log "DEBUG" "Service $service_name is starting..."
                            ;;
                        *)
                            # For services without health checks, check if they're running
                            local status
                            status=$(echo "$service" | jq -r '.Status // ""' 2>/dev/null || echo "")
                            if [[ "$status" =~ ^Up ]]; then
                                ((healthy_count++))
                            fi
                            ;;
                    esac
                fi
            done <<< "$(echo "$services_info" | jq -c '.[]' 2>/dev/null || echo "")"
        fi
        
        if [[ $healthy_count -eq $total_count && $total_count -gt 0 ]]; then
            log "SUCCESS" "All $total_count services are healthy"
            return 0
        fi
        
        log "DEBUG" "Services healthy: $healthy_count/$total_count, waiting..."
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
    done
    
    log "WARN" "Timeout waiting for services to become healthy"
    return 1
}

# Check if services are running
check_services_running() {
    if ! initialize_docker_environment; then
        return 1
    fi
    
    local running_services
    running_services=$(run_docker_compose ps --services --filter "status=running" 2>/dev/null | wc -l)
    
    if [[ "$running_services" -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Show service status
show_service_status() {
    if ! initialize_docker_environment; then
        return 1
    fi
    
    log "INFO" "Service Status Overview:"
    echo
    
    # Show detailed status
    run_docker_compose ps
    
    echo
    local running_count
    running_count=$(run_docker_compose ps --services --filter "status=running" 2>/dev/null | wc -l)
    local total_count
    total_count=$(run_docker_compose ps --services 2>/dev/null | wc -l)
    
    log "INFO" "Services running: $running_count/$total_count"
    
    # Show resource usage if available
    if command -v docker >/dev/null 2>&1; then
        echo
        log "INFO" "Resource Usage:"
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" \
            $(run_docker_compose ps -q 2>/dev/null) 2>/dev/null || log "DEBUG" "Could not get resource usage"
    fi
    
    return 0
}

# =============================================================================
# Network Management
# =============================================================================

# Create Docker networks if they don't exist
create_networks() {
    log "DEBUG" "Creating Docker networks..."
    
    local -a networks=("milou_network")
    
    # Add proxy network if it doesn't exist externally
    if ! docker network inspect proxy >/dev/null 2>&1; then
        networks+=("proxy")
    fi
    
    for network in "${networks[@]}"; do
        if ! docker network inspect "$network" >/dev/null 2>&1; then
            log "DEBUG" "Creating network: $network"
            if docker network create "$network" >/dev/null 2>&1; then
                log "SUCCESS" "Created network: $network"
            else
                log "WARN" "Failed to create network: $network"
            fi
        else
            log "DEBUG" "Network already exists: $network"
        fi
    done
}

# =============================================================================
# Docker Access Validation
# =============================================================================

# Check if Docker daemon is accessible
check_docker_access() {
    if ! command -v docker >/dev/null 2>&1; then
        log "ERROR" "Docker is not installed"
        log "INFO" "💡 Install Docker: curl -fsSL https://get.docker.com | sh"
        return 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        log "ERROR" "Cannot access Docker daemon"
        log "INFO" "Please ensure:"
        log "INFO" "  1. Docker daemon is running"
        log "INFO" "  2. Current user has Docker permissions"
        log "INFO" "  3. Try: sudo usermod -aG docker \$USER && newgrp docker"
        return 1
    fi
    
    if ! docker compose version >/dev/null 2>&1; then
        log "ERROR" "Docker Compose is not available"
        log "INFO" "💡 Docker Compose should be included with modern Docker installations"
        return 1
    fi
    
    return 0
}

# =============================================================================
# Logging and Debugging
# =============================================================================

# Show logs for specific service or all services
show_service_logs() {
    local service="${1:-}"
    local follow="${2:-false}"
    
    if ! initialize_docker_environment; then
        return 1
    fi
    
    if [[ -n "$service" ]]; then
        log "INFO" "Viewing logs for service: $service"
        if [[ "$follow" == "true" ]]; then
            run_docker_compose logs --tail=100 -f "$service"
        else
            run_docker_compose logs --tail=100 "$service"
        fi
    else
        log "INFO" "Viewing logs for all services"
        if [[ "$follow" == "true" ]]; then
            run_docker_compose logs --tail=100 -f
        else
            run_docker_compose logs --tail=100
        fi
    fi
}

# Execute command in service container
exec_in_service() {
    local service="$1"
    shift
    local cmd="${*:-/bin/bash}"
    
    if ! initialize_docker_environment; then
        return 1
    fi
    
    if ! run_docker_compose ps "$service" | grep -q "Up"; then
        log "ERROR" "Service $service is not running"
        return 1
    fi
    
    log "INFO" "Executing in $service container: $cmd"
    run_docker_compose exec "$service" $cmd
}

# =============================================================================
# Cleanup Operations
# =============================================================================

# Clean up Docker resources
cleanup_docker_resources() {
    local cleanup_type="${1:-regular}"
    
    case "$cleanup_type" in
        "complete")
            log "STEP" "Performing complete cleanup of Milou resources..."
            complete_cleanup_milou_resources
            ;;
        "volumes")
            log "STEP" "Cleaning up Docker volumes..."
            cleanup_docker_volumes
            ;;
        *)
            log "STEP" "Performing regular Docker cleanup..."
            regular_cleanup_docker_resources
            ;;
    esac
}

# Regular Docker cleanup
regular_cleanup_docker_resources() {
    log "INFO" "Cleaning up unused Docker resources..."
    
    # Remove unused containers
    if docker container prune -f >/dev/null 2>&1; then
        log "SUCCESS" "Cleaned up unused containers"
    fi
    
    # Remove unused images
    if docker image prune -f >/dev/null 2>&1; then
        log "SUCCESS" "Cleaned up unused images"
    fi
    
    # Remove unused networks
    if docker network prune -f >/dev/null 2>&1; then
        log "SUCCESS" "Cleaned up unused networks"
    fi
    
    # Remove unused volumes (with confirmation)
    local unused_volumes
    unused_volumes=$(docker volume ls -qf dangling=true)
    if [[ -n "$unused_volumes" ]]; then
        if [[ "${FORCE:-false}" == "true" ]] || confirm "Remove unused Docker volumes?" "N"; then
            echo "$unused_volumes" | xargs -r docker volume rm
            log "SUCCESS" "Cleaned up unused volumes"
        fi
    fi
}

# Complete cleanup of Milou resources
complete_cleanup_milou_resources() {
    if ! initialize_docker_environment; then
        return 1
    fi
    
    log "WARN" "This will remove ALL Milou containers, images, and volumes!"
    if [[ "${FORCE:-false}" != "true" ]] && ! confirm "Continue with complete cleanup?" "N"; then
        log "INFO" "Complete cleanup cancelled"
        return 0
    fi
    
    # Stop and remove all containers
    run_docker_compose down -v --remove-orphans
    
    # Remove project-specific volumes
    local volumes
    volumes=$(docker volume ls -q --filter "name=${DOCKER_PROJECT_NAME}_")
    if [[ -n "$volumes" ]]; then
        echo "$volumes" | xargs -r docker volume rm
        log "SUCCESS" "Removed project volumes"
    fi
    
    # Remove project-specific images
    local images
    images=$(docker images --filter "reference=*milou*" -q)
    if [[ -n "$images" ]]; then
        echo "$images" | xargs -r docker rmi -f
        log "SUCCESS" "Removed Milou images"
    fi
    
    log "SUCCESS" "Complete cleanup completed"
}

# =============================================================================
# RabbitMQ-specific Functions
# =============================================================================

# Check for RabbitMQ authentication issues
check_rabbitmq_auth_issues() {
    local engine_logs
    engine_logs=$(run_docker_compose logs engine --tail=20 2>/dev/null)
    
    if echo "$engine_logs" | grep -q "ACCESS_REFUSED.*authentication mechanism PLAIN"; then
        log "DEBUG" "RabbitMQ authentication issues detected in engine logs"
        return 0
    fi
    
    # Also check RabbitMQ logs for 'guest' user attempts
    local rabbitmq_logs
    rabbitmq_logs=$(run_docker_compose logs rabbitmq --tail=10 2>/dev/null)
    
    if echo "$rabbitmq_logs" | grep -q "PLAIN login refused: user 'guest'"; then
        log "DEBUG" "Engine attempting to use 'guest' credentials instead of configured ones"
        return 0
    fi
    
    return 1
}

# Restart RabbitMQ-dependent services
restart_rabbitmq_dependent_services() {
    log "INFO" "Restarting RabbitMQ-dependent services..."
    
    # First, restart RabbitMQ to ensure it's fully initialized
    log "INFO" "Restarting RabbitMQ service..."
    if run_docker_compose restart rabbitmq; then
        log "SUCCESS" "RabbitMQ service restarted"
        
        # Wait for RabbitMQ to be fully ready
        log "INFO" "Waiting for RabbitMQ to be ready..."
        sleep 15
        
        # Now restart engine service
        log "INFO" "Restarting engine service..."
        if run_docker_compose restart engine; then
            log "SUCCESS" "Engine service restarted"
            
            # Wait a moment for it to connect
            sleep 10
            
            # Check if authentication issue is resolved
            if ! check_rabbitmq_auth_issues; then
                log "SUCCESS" "RabbitMQ authentication issues resolved"
                return 0
            else
                log "WARN" "Authentication issues persist after restart"
            fi
        else
            log "ERROR" "Failed to restart engine service"
        fi
    else
        log "ERROR" "Failed to restart RabbitMQ service"
    fi
    
    return 1
}

# =============================================================================
# Auto-initialization
# =============================================================================

# Auto-initialize Docker environment when sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Only auto-initialize if not in setup mode
    if [[ "${1:-}" != "setup" ]]; then
        initialize_docker_environment >/dev/null 2>&1 || true
    fi
fi 