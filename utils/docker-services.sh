#!/bin/bash

# =============================================================================
# Docker Service Management and Container Operations
# Focused module for handling service lifecycle
# =============================================================================

# =============================================================================
# Docker Compose Helper Functions
# =============================================================================

# Run docker-compose with proper env file loading
run_docker_compose() {
    local compose_file="static/docker-compose.yml"
    local env_file="${SCRIPT_DIR}/.env"
    
    # Ensure we're in the right directory
    cd "$SCRIPT_DIR" || error_exit "Cannot change to script directory"
    
    # Check if env file exists
    if [[ ! -f "$env_file" ]]; then
        error_exit "Environment file not found: $env_file"
    fi
    
    # Check if compose file exists
    if [[ ! -f "$compose_file" ]]; then
        error_exit "Docker Compose file not found: $compose_file"
    fi
    
    # Run docker-compose with proper env file
    log "TRACE" "Running: docker compose --env-file '$env_file' -f '$compose_file' $*"
    docker compose --env-file "$env_file" -f "$compose_file" "$@"
}

# Test docker-compose configuration
test_docker_compose_config() {
    log "DEBUG" "Testing Docker Compose configuration..."
    
    if run_docker_compose config --quiet; then
        log "SUCCESS" "Docker Compose configuration is valid"
        return 0
    else
        log "ERROR" "Docker Compose configuration is invalid"
        return 1
    fi
}

# =============================================================================
# Service Management Functions
# =============================================================================

# Start all services with Docker Compose
start_services() {
    log "STEP" "Starting Milou services..."
    
    # Test configuration first
    if ! test_docker_compose_config; then
        error_exit "Docker Compose configuration is invalid"
    fi
    
    log "INFO" "Starting services with Docker Compose..."
    if run_docker_compose up -d --remove-orphans; then
        log "SUCCESS" "Services started successfully"
        
        # Wait for services to be ready
        log "INFO" "Waiting for services to be ready..."
        if wait_for_services; then
            log "SUCCESS" "All services are healthy and ready"
            return 0
        else
            log "ERROR" "Some services failed to become healthy"
            return 1
        fi
    else
        error_exit "Failed to start services"
    fi
}

# Stop all services
stop_services() {
    log "STEP" "Stopping Milou services..."
    
    cd "$SCRIPT_DIR" || error_exit "Cannot change to script directory"
    
    if run_docker_compose down --remove-orphans; then
        log "SUCCESS" "Services stopped successfully"
    else
        log "ERROR" "Failed to stop some services"
        return 1
    fi
}

# Restart all services
restart_services() {
    log "STEP" "Restarting Milou services..."
    
    if stop_services; then
        sleep 2
        if start_services; then
            log "SUCCESS" "Services restarted successfully"
        else
            error_exit "Failed to restart services"
        fi
    else
        error_exit "Failed to stop services for restart"
    fi
}

# =============================================================================
# Service Status and Health Monitoring
# =============================================================================

# Show comprehensive service status
show_service_status() {
    log "INFO" "Service Status Overview:"
    echo
    
    local compose_file="static/docker-compose.yml"
    
    if ! docker compose -f "$compose_file" ps; then
        log "ERROR" "Failed to get service status"
        return 1
    fi
    
    echo
    
    # Additional status information
    local total_services
    total_services=$(docker compose -f "$compose_file" ps --services | wc -l)
    local running_services
    running_services=$(docker compose -f "$compose_file" ps --services --filter "status=running" 2>/dev/null | wc -l || echo "0")
    
    log "INFO" "Services running: $running_services/$total_services"
    
    # Show resource usage if available
    if command -v docker >/dev/null 2>&1; then
        echo
        log "INFO" "Resource Usage:"
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" $(docker compose -f "$compose_file" ps -q 2>/dev/null) 2>/dev/null || log "DEBUG" "Could not retrieve resource usage"
    fi
}

# Check if services are currently running
check_services_running() {
    local compose_file="static/docker-compose.yml"
    
    cd "$SCRIPT_DIR" || {
        log "ERROR" "Cannot change to script directory"
        return 1
    }
    
    if [[ ! -f "$compose_file" ]]; then
        log "DEBUG" "Docker Compose file not found: $compose_file"
        return 1
    fi
    
    # Check if any containers are running
    local running_containers
    running_containers=$(docker compose -f "$compose_file" ps --services --filter "status=running" 2>/dev/null | wc -l)
    
    if [[ "$running_containers" -gt 0 ]]; then
        return 0  # Services are running
    else
        return 1  # No services running
    fi
}

# Check the status of all services
check_service_status() {
    log "INFO" "Service Status:"
    
    cd "$SCRIPT_DIR" || {
        log "ERROR" "Cannot change to script directory"
        return 1
    }
    
    local compose_file="static/docker-compose.yml"
    
    if [[ ! -f "$compose_file" ]]; then
        log "ERROR" "Docker Compose file not found: $compose_file"
        return 1
    fi
    
    if ! docker compose -f "$compose_file" ps; then
        log "ERROR" "Failed to get service status"
        return 1
    fi
    
    return 0
}

# View logs for services
view_logs() {
    local service="$1"
    local compose_file="static/docker-compose.yml"
    
    cd "$SCRIPT_DIR" || error_exit "Cannot change to script directory"
    
    if [[ -n "$service" ]]; then
        log "INFO" "Viewing logs for service: $service"
        docker compose -f "$compose_file" logs --tail=100 -f "$service"
    else
        log "INFO" "Viewing logs for all services"
        docker compose -f "$compose_file" logs --tail=100 -f
    fi
}

# Get a shell in a running container
get_shell() {
    local service="$1"
    
    if [ -z "$service" ]; then
        echo "Error: Service name is required."
        echo "Usage: get_shell SERVICE_NAME"
        return 1
    fi
    
    cd "${SCRIPT_DIR}" || {
        echo "Error: Cannot change to script directory"
        return 1
    }
    
    # Check if the service is running
    if ! docker compose -f static/docker-compose.yml ps --format "table {{.Service}}\t{{.Status}}" | grep "$service" | grep -q "Up"; then
        echo "Error: Service $service is not running."
        return 1
    fi
    
    # Get a shell in the container
    if ! docker compose -f static/docker-compose.yml exec "$service" /bin/bash; then
        # Try with sh if bash is not available
        if ! docker compose -f static/docker-compose.yml exec "$service" /bin/sh; then
            echo "Error: Failed to get shell in $service."
            return 1
        fi
    fi
    
    return 0
}

# =============================================================================
# Service Readiness and Health Checks
# =============================================================================

# Enhanced service readiness check
wait_for_services_ready() {
    local timeout=300  # 5 minutes
    local interval=10
    local elapsed=0
    
    local -a services=("db" "redis" "rabbitmq" "backend" "frontend" "engine" "nginx")
    
    while [ $elapsed -lt $timeout ]; do
        local ready_count=0
        
        for service in "${services[@]}"; do
            if check_service_health "$service"; then
                ((ready_count++))
            fi
        done
        
        local ready_percentage=$((ready_count * 100 / ${#services[@]}))
        
        if [[ $ready_count -eq ${#services[@]} ]]; then
            log "SUCCESS" "All services are healthy (${ready_count}/${#services[@]})"
            return 0
        fi
        
        log "INFO" "Services ready: ${ready_count}/${#services[@]} (${ready_percentage}%) - waiting..."
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log "WARN" "Timeout waiting for all services to be ready"
    return 1
}

# Check individual service health
check_service_health() {
    local service="$1"
    local compose_file="static/docker-compose.yml"
    
    # Check if container is running
    if ! docker compose -f "$compose_file" ps --format "table {{.Service}}\t{{.Status}}" 2>/dev/null | grep -q "^${service}.*Up"; then
        return 1
    fi
    
    # Check health status if available
    local health_status
    health_status=$(docker compose -f "$compose_file" ps --format "json" 2>/dev/null | jq -r ".[] | select(.Service == \"$service\") | .Health" 2>/dev/null || echo "")
    
    if [[ -n "$health_status" ]]; then
        case "$health_status" in
            "healthy") return 0 ;;
            "unhealthy") return 1 ;;
            "starting") return 1 ;;
            *) return 1 ;;
        esac
    fi
    
    # If no health check available, assume healthy if running
    return 0
}

# =============================================================================
# Docker Environment Management
# =============================================================================

# Check if Docker daemon is accessible
check_docker_access() {
    if ! docker info >/dev/null 2>&1; then
        log "ERROR" "Cannot access Docker daemon"
        log "INFO" "Please ensure:"
        log "INFO" "  1. Docker is installed and running"
        log "INFO" "  2. Current user has Docker permissions"
        log "INFO" "  3. Try: sudo usermod -aG docker \$USER && newgrp docker"
        return 1
    fi
    return 0
}

# Create Docker networks if they don't exist
create_networks() {
    log "DEBUG" "Creating Docker networks..."
    
    local -a networks=("milou_network" "proxy")
    
    for network in "${networks[@]}"; do
        if ! docker network inspect "$network" >/dev/null 2>&1; then
            log "DEBUG" "Creating network: $network"
            if ! docker network create "$network" >/dev/null 2>&1; then
                log "WARN" "Failed to create network: $network"
            fi
        fi
    done
}

# Clean up Docker resources
cleanup_docker_resources() {
    log "STEP" "Cleaning up Docker resources..."
    
    # Remove unused images
    if docker image prune -f >/dev/null 2>&1; then
        log "INFO" "Removed unused Docker images"
    fi
    
    # Remove unused volumes (with confirmation)
    if [[ "$FORCE" == true ]] || confirm "Remove unused Docker volumes? (This may delete persistent data)"; then
        if docker volume prune -f >/dev/null 2>&1; then
            log "INFO" "Removed unused Docker volumes"
        fi
    fi
    
    # Remove unused networks
    if docker network prune -f >/dev/null 2>&1; then
        log "INFO" "Removed unused Docker networks"
    fi
    
    log "SUCCESS" "Docker cleanup completed"
}

# Ensure all required Docker networks exist
ensure_docker_networks() {
    log "DEBUG" "Ensuring required Docker networks exist..."
    
    local -a required_networks=("proxy")
    
    for network in "${required_networks[@]}"; do
        if ! docker network inspect "$network" >/dev/null 2>&1; then
            log "INFO" "Creating required network: $network"
            if docker network create "$network" >/dev/null 2>&1; then
                log "DEBUG" "Network $network created successfully"
            else
                log "WARN" "Failed to create network: $network"
            fi
        else
            log "DEBUG" "Network $network already exists"
        fi
    done
}

# =============================================================================
# Service Startup with Pre-flight Checks
# =============================================================================

# Enhanced service startup with pre-flight checks
start_services_with_checks() {
    local setup_mode="${1:-false}"
    
    log "STEP" "Starting Milou services with pre-flight checks..."
    
    # Check SSL certificates
    local ssl_path
    ssl_path=$(get_config_value "SSL_CERT_PATH" "./ssl")
    
    if [[ -n "$ssl_path" ]]; then
        log "INFO" "Checking SSL certificates..."
        if [[ -f "$ssl_path/milou.crt" && -f "$ssl_path/milou.key" ]]; then
            if check_ssl_expiration "$ssl_path"; then
                log "SUCCESS" "SSL certificates are valid"
            else
                log "WARN" "SSL certificate issues detected"
            fi
        else
            log "WARN" "SSL certificates not found at $ssl_path"
            log "INFO" "💡 Run: $0 ssl --domain YOUR_DOMAIN"
        fi
    fi
    
    # Ensure networks exist
    log "INFO" "Creating required network: proxy"
    ensure_docker_networks
    
    # Enhanced existing installation handling with setup mode awareness
    # First, check if this is a truly fresh installation (no need for conflict checking)
    local is_fresh_install=false
    local existing_containers_count=0
    local existing_volumes_count=0
    local has_config=false
    
    # Count existing containers
    local all_containers
    all_containers=$(docker ps -a --filter "name=static-" --format "{{.Names}}" 2>/dev/null || true)
    if [[ -n "$all_containers" ]]; then
        existing_containers_count=$(echo "$all_containers" | wc -l)
    fi
    
    # Count existing volumes
    local existing_volumes
    existing_volumes=$(docker volume ls --filter "name=static_" --format "{{.Name}}" 2>/dev/null || true)
    if [[ -n "$existing_volumes" ]]; then
        existing_volumes_count=$(echo "$existing_volumes" | wc -l)
    fi
    
    # Check for configuration
    if [[ -f "$ENV_FILE" ]]; then
        has_config=true
    fi
    
    # Determine if this is a fresh install
    if [[ $existing_containers_count -eq 0 && $existing_volumes_count -eq 0 && "$has_config" == false ]]; then
        is_fresh_install=true
        log "DEBUG" "Fresh installation detected - skipping conflict checks"
    elif [[ "$setup_mode" == "true" && $existing_containers_count -eq 0 ]]; then
        # Even if we have old config/volumes, if no containers are running during setup, treat as fresh
        is_fresh_install=true
        log "DEBUG" "Setup mode with no running containers - treating as fresh install"
    fi
    
    # Skip all conflict checking for fresh installations
    if [[ "$is_fresh_install" == "true" ]]; then
        log "DEBUG" "Fresh installation - proceeding directly to service startup"
    else
        # Check for running containers that might conflict
        local running_containers
        running_containers=$(docker ps --filter "name=static-" --format "{{.Names}}" 2>/dev/null || true)
        
        local needs_conflict_handling=false
        local conflict_reason=""
        
        if [[ -n "$running_containers" ]]; then
            needs_conflict_handling=true
            conflict_reason="running containers"
            log "WARN" "Found running Milou containers that may conflict:"
            while IFS= read -r container; do
                [[ -n "$container" ]] && log "WARN" "  🐳 $container"
            done <<< "$running_containers"
        fi
        
        # Check for port conflicts
        local conflicting_ports=()
        local -a ports_to_check=("80" "443" "5432" "6379" "5672" "9999")
        
        for port in "${ports_to_check[@]}"; do
            if command -v netstat >/dev/null 2>&1; then
                local port_in_use
                port_in_use=$(netstat -tlnp 2>/dev/null | grep ":$port " | awk '{print $7}' | head -1)
                if [[ -n "$port_in_use" && ! "$port_in_use" =~ static- ]]; then
                    conflicting_ports+=("$port ($port_in_use)")
                fi
            fi
        done
        
        if [[ ${#conflicting_ports[@]} -gt 0 ]]; then
            for port_info in "${conflicting_ports[@]}"; do
                log "WARN" "  ⚠️  Port $port_info is in use by: "
            done
        fi
        
        # Handle conflicts if needed
        if [[ "$needs_conflict_handling" == "true" ]]; then
            local handle_conflict=false
            
            if [[ "$FORCE" == true ]]; then
                log "WARN" "Force mode enabled - stopping existing services first"
                handle_conflict=true
            elif [[ "$setup_mode" == "true" ]]; then
                # During setup, be more permissive about existing installations
                log "INFO" "Setup mode detected - handling $conflict_reason..."
                
                if [[ "${INTERACTIVE:-true}" == "true" ]]; then
                    echo "During setup, we need to handle existing containers."
                    echo "Options:"
                    echo "  1. Stop existing containers and proceed (recommended)"
                    echo "  2. Force restart (stop and remove containers)"
                    echo "  3. Cancel setup"
                    echo
                    
                    while true; do
                        read -p "Choose option (1-3): " choice
                        case "$choice" in
                            1)
                                log "INFO" "Stopping existing containers..."
                                handle_conflict=true
                                break
                                ;;
                            2)
                                log "INFO" "Force restarting - will remove existing containers..."
                                export FORCE=true
                                handle_conflict=true
                                break
                                ;;
                            3)
                                log "INFO" "Setup cancelled by user"
                                return 1
                                ;;
                            *)
                                echo "Invalid choice. Please enter 1-3."
                                ;;
                        esac
                    done
                else
                    # Non-interactive setup mode
                    log "INFO" "Non-interactive setup - stopping existing containers"
                    handle_conflict=true
                fi
            else
                # Normal start operation with conflicts
                log "ERROR" "Cannot start services due to conflicts"
                log "INFO" "💡 Solutions:"
                log "INFO" "  • Use --force flag to stop existing services"
                log "INFO" "  • Run: $0 stop (to stop Milou services)"
                log "INFO" "  • Run: $0 restart (to restart services)"
                return 1
            fi
            
            if [[ "$handle_conflict" == "true" ]]; then
                if [[ "$FORCE" == true ]]; then
                    log "INFO" "Force mode - stopping and removing existing containers..."
                    if ! stop_services; then
                        log "WARN" "Failed to stop some services, continuing anyway..."
                    fi
                else
                    log "INFO" "Stopping existing containers..."
                    if ! stop_services; then
                        log "ERROR" "Failed to stop existing services"
                        return 1
                    fi
                fi
                
                # Wait for services to fully stop
                log "INFO" "Waiting for services to fully stop..."
                sleep 3
            fi
        fi
        
        # Handle database migration for existing installations
        if [[ "$setup_mode" == "true" && "${MILOU_EXISTING_VOLUMES:-false}" == "true" ]]; then
            if ! handle_database_migration "true"; then
                log "ERROR" "Database migration failed"
                if [[ "${FORCE:-false}" != "true" ]]; then
                    return 1
                fi
            fi
        fi
    fi
    
    # Start services
    if start_services; then
        log "SUCCESS" "Services started successfully with all checks passed"
        return 0
    else
        log "ERROR" "Failed to start services"
        return 1
    fi
}

# Wait for services to be ready (alias for backward compatibility)
wait_for_services() {
    wait_for_services_ready
}

# =============================================================================
# Diagnostic and Troubleshooting Functions
# =============================================================================

# Comprehensive Docker environment diagnosis
diagnose_docker_environment() {
    log "STEP" "Running comprehensive Docker environment diagnosis..."
    echo
    
    local issues=0
    local warnings=0
    
    # Check Docker daemon
    log "INFO" "1. Docker Daemon Status:"
    if docker info >/dev/null 2>&1; then
        log "SUCCESS" "  ✅ Docker daemon is accessible"
        
        # Get Docker version
        local docker_version
        docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
        log "INFO" "  📦 Docker version: $docker_version"
        
        # Check Docker Compose
        local compose_version
        compose_version=$(docker compose version --short 2>/dev/null || echo "unknown")
        log "INFO" "  📦 Docker Compose version: $compose_version"
    else
        log "ERROR" "  ❌ Cannot access Docker daemon"
        ((issues++))
        log "INFO" "    💡 Try: sudo systemctl start docker"
        log "INFO" "    💡 Verify user permissions: sudo usermod -aG docker \$USER"
    fi
    echo
    
    # Check authentication
    log "INFO" "2. Registry Authentication:"
    if docker system info --format '{{.RegistryConfig}}' 2>/dev/null | grep -q "ghcr.io"; then
        log "SUCCESS" "  ✅ GitHub Container Registry authentication configured"
    else
        log "WARN" "  ⚠️  No authentication found for GitHub Container Registry"
        ((warnings++))
    fi
    echo
    
    # Check required images
    log "INFO" "3. Required Docker Images:"
    local -a required_images=(
        "ghcr.io/milou-sh/milou/backend:latest"
        "ghcr.io/milou-sh/milou/frontend:latest"
        "ghcr.io/milou-sh/milou/engine:latest"
        "ghcr.io/milou-sh/milou/nginx:latest"
        "ghcr.io/milou-sh/milou/database:latest"
    )
    
    for image in "${required_images[@]}"; do
        if docker image inspect "$image" >/dev/null 2>&1; then
            log "SUCCESS" "  ✅ $image"
        else
            log "ERROR" "  ❌ $image (not found locally)"
            ((issues++))
        fi
    done
    echo
    
    # Check Docker Compose configuration
    log "INFO" "4. Docker Compose Configuration:"
    local compose_file="static/docker-compose.yml"
    if [[ -f "$compose_file" ]]; then
        log "SUCCESS" "  ✅ Compose file exists: $compose_file"
        
        if docker compose -f "$compose_file" config >/dev/null 2>&1; then
            log "SUCCESS" "  ✅ Compose configuration is valid"
        else
            log "ERROR" "  ❌ Compose configuration is invalid"
            ((issues++))
            log "DEBUG" "  Run 'docker compose -f $compose_file config' for details"
        fi
    else
        log "ERROR" "  ❌ Compose file not found: $compose_file"
        ((issues++))
    fi
    echo
    
    # Check environment variables
    log "INFO" "5. Environment Configuration:"
    local env_file="${SCRIPT_DIR}/.env"
    if [[ -f "$env_file" ]]; then
        log "SUCCESS" "  ✅ Environment file exists: $env_file"
        
        # Check file permissions
        local permissions
        permissions=$(stat -c %a "$env_file" 2>/dev/null || echo "unknown")
        if [[ "$permissions" == "600" ]]; then
            log "SUCCESS" "  ✅ Environment file has secure permissions ($permissions)"
        else
            log "WARN" "  ⚠️  Environment file permissions could be more secure ($permissions)"
            ((warnings++))
            log "INFO" "    💡 Run: chmod 600 $env_file"
        fi
    else
        log "ERROR" "  ❌ Environment file not found: $env_file"
        ((issues++))
        log "INFO" "    💡 Run setup first: ./milou.sh setup"
    fi
    echo
    
    # Check networks
    log "INFO" "6. Docker Networks:"
    local -a required_networks=("milou_network" "proxy")
    for network in "${required_networks[@]}"; do
        if docker network inspect "$network" >/dev/null 2>&1; then
            log "SUCCESS" "  ✅ Network exists: $network"
        else
            log "WARN" "  ⚠️  Network missing: $network"
            ((warnings++))
            log "INFO" "    💡 Will be created automatically during startup"
        fi
    done
    echo
    
    # Check system resources
    log "INFO" "7. System Resources:"
    local disk_space
    disk_space=$(df -h . | awk 'NR==2 {print $4}')
    log "INFO" "  💾 Available disk space: $disk_space"
    
    local memory
    memory=$(free -h | awk 'NR==2{print $7}')
    log "INFO" "  🧠 Available memory: $memory"
    echo
    
    # Check running services
    log "INFO" "8. Current Service Status:"
    if docker compose -f "$compose_file" ps --format "table {{.Service}}\t{{.Status}}" 2>/dev/null; then
        log "SUCCESS" "  ✅ Service status retrieved successfully"
    else
        log "WARN" "  ⚠️  Could not retrieve service status"
        ((warnings++))
    fi
    echo
    
    # Summary
    log "INFO" "Diagnosis Summary:"
    log "INFO" "  🔴 Critical Issues: $issues"
    log "INFO" "  🟡 Warnings: $warnings"
    
    if [[ $issues -eq 0 ]]; then
        log "SUCCESS" "🎉 No critical issues found! System appears healthy."
        return 0
    else
        log "ERROR" "⚠️  Found $issues critical issue(s) that need attention."
        return 1
    fi
}

# Quick health check for running services
quick_health_check() {
    log "INFO" "Running quick health check..."
    
    local compose_file="static/docker-compose.yml"
    local healthy_services=0
    local total_services=0
    
    # Check if compose file exists
    if [[ ! -f "$compose_file" ]]; then
        log "ERROR" "Docker Compose file not found"
        return 1
    fi
    
    # Get list of services
    local services
    services=$(docker compose -f "$compose_file" ps --services 2>/dev/null)
    
    if [[ -z "$services" ]]; then
        log "WARN" "No services found or not running"
        return 1
    fi
    
    echo "Service Health Status:"
    while IFS= read -r service; do
        ((total_services++))
        if check_service_health "$service"; then
            echo "  ✅ $service: Healthy"
            ((healthy_services++))
        else
            echo "  ❌ $service: Unhealthy or not running"
        fi
    done <<< "$services"
    
    echo
    log "INFO" "Health Summary: $healthy_services/$total_services services healthy"
    
    if [[ $healthy_services -eq $total_services ]]; then
        log "SUCCESS" "All services are healthy!"
        return 0
    else
        log "WARN" "Some services are not healthy"
        return 1
    fi
}

# =============================================================================
# Database User Synchronization Functions
# =============================================================================

# Synchronize database users with current configuration
sync_database_users() {
    local env_file="${SCRIPT_DIR}/.env"
    
    if [[ ! -f "$env_file" ]]; then
        log "ERROR" "Configuration file not found: $env_file"
        return 1
    fi
    
    log "STEP" "Synchronizing database users with configuration..."
    
    # Get current configuration values
    local db_user db_password postgres_user postgres_password db_name
    db_user=$(get_config_value "DB_USER" "")
    db_password=$(get_config_value "DB_PASSWORD" "")
    postgres_user=$(get_config_value "POSTGRES_USER" "")
    postgres_password=$(get_config_value "POSTGRES_PASSWORD" "")
    db_name=$(get_config_value "DB_NAME" "milou")
    
    if [[ -z "$db_user" || -z "$db_password" ]]; then
        log "ERROR" "Database credentials not found in configuration"
        return 1
    fi
    
    log "INFO" "Target database user: $db_user"
    log "INFO" "Target database: $db_name"
    
    # Check if database container is running
    if ! docker ps --filter "name=static-db-1" --format "{{.Names}}" | grep -q "static-db-1"; then
        log "WARN" "Database container is not running - user sync will be performed on next startup"
        return 0
    fi
    
    # Wait for database to be ready
    log "INFO" "Waiting for database to be ready..."
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if docker exec static-db-1 pg_isready -U "$postgres_user" -d "$db_name" >/dev/null 2>&1; then
            break
        fi
        ((attempt++))
        if [[ $attempt -eq $max_attempts ]]; then
            log "ERROR" "Database did not become ready within $max_attempts seconds"
            return 1
        fi
        sleep 1
    done
    
    log "SUCCESS" "Database is ready"
    
    # Check if the target user already exists
    local user_exists
    user_exists=$(docker exec static-db-1 psql -U "$postgres_user" -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='$db_user'" 2>/dev/null || echo "")
    
    if [[ "$user_exists" == "1" ]]; then
        log "INFO" "User '$db_user' already exists - updating password and permissions"
        
        # Update password
        if docker exec static-db-1 psql -U "$postgres_user" -d postgres -c "ALTER USER \"$db_user\" WITH PASSWORD '$db_password';" >/dev/null 2>&1; then
            log "SUCCESS" "Updated password for user '$db_user'"
        else
            log "ERROR" "Failed to update password for user '$db_user'"
            return 1
        fi
    else
        log "INFO" "Creating new user '$db_user'"
        
        # Create the user
        if docker exec static-db-1 psql -U "$postgres_user" -d postgres -c "CREATE USER \"$db_user\" WITH PASSWORD '$db_password';" >/dev/null 2>&1; then
            log "SUCCESS" "Created user '$db_user'"
        else
            log "ERROR" "Failed to create user '$db_user'"
            return 1
        fi
    fi
    
    # Grant necessary permissions
    log "INFO" "Granting permissions to user '$db_user'"
    
    # Create database if it doesn't exist
    local db_exists
    db_exists=$(docker exec static-db-1 psql -U "$postgres_user" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$db_name'" 2>/dev/null || echo "")
    
    if [[ "$db_exists" != "1" ]]; then
        log "INFO" "Creating database '$db_name'"
        if docker exec static-db-1 psql -U "$postgres_user" -d postgres -c "CREATE DATABASE \"$db_name\" WITH OWNER \"$db_user\";" >/dev/null 2>&1; then
            log "SUCCESS" "Created database '$db_name'"
        else
            log "ERROR" "Failed to create database '$db_name'"
            return 1
        fi
    fi
    
    # Grant all privileges on the database
    if docker exec static-db-1 psql -U "$postgres_user" -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE \"$db_name\" TO \"$db_user\";" >/dev/null 2>&1; then
        log "SUCCESS" "Granted database privileges to '$db_user'"
    else
        log "WARN" "Failed to grant database privileges - may already be granted"
    fi
    
    # Grant schema permissions
    if docker exec static-db-1 psql -U "$postgres_user" -d "$db_name" -c "GRANT ALL ON SCHEMA public TO \"$db_user\"; GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO \"$db_user\"; GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO \"$db_user\";" >/dev/null 2>&1; then
        log "SUCCESS" "Granted schema privileges to '$db_user'"
    else
        log "WARN" "Failed to grant schema privileges - may not be necessary yet"
    fi
    
    # Test the connection
    log "INFO" "Testing database connection with new credentials..."
    if docker exec static-db-1 psql -U "$db_user" -d "$db_name" -c "SELECT 1;" >/dev/null 2>&1; then
        log "SUCCESS" "✅ Database user synchronization completed successfully"
        return 0
    else
        log "ERROR" "❌ Database connection test failed - user synchronization may have issues"
        return 1
    fi
}

# Handle database migration for existing installations
handle_database_migration() {
    local preserve_data="${1:-true}"
    
    log "STEP" "Handling database migration for existing installation..."
    
    # Check if we have preserved credentials
    if [[ "${MILOU_PRESERVED_CREDENTIALS:-false}" == "true" ]]; then
        log "INFO" "Using preserved credentials - synchronizing database users"
        if sync_database_users; then
            log "SUCCESS" "Database migration completed with preserved credentials"
            return 0
        else
            log "WARN" "Database user synchronization failed"
            if [[ "${FORCE:-false}" != "true" ]]; then
                return 1
            fi
        fi
    else
        log "INFO" "New credentials generated - database will be reinitialized"
        if [[ "$preserve_data" == "true" ]]; then
            log "WARN" "⚠️  Data preservation requested but credentials changed"
            log "INFO" "💡 Consider using preserved credentials to maintain data compatibility"
            
            if [[ "${INTERACTIVE:-true}" == "true" ]]; then
                echo
                echo "Database credentials have changed, which may cause data loss."
                echo "Options:"
                echo "  1. Continue with new credentials (may lose existing data)"
                echo "  2. Cancel and regenerate config with preserved credentials"
                echo "  3. Force continue anyway"
                echo
                
                while true; do
                    read -p "Choose option (1-3): " choice
                    case "$choice" in
                        1)
                            log "WARN" "Continuing with new credentials"
                            break
                            ;;
                        2)
                            log "INFO" "Please regenerate configuration with preserved credentials"
                            log "INFO" "💡 Hint: Run setup again and choose to preserve existing configuration"
                            return 1
                            ;;
                        3)
                            log "WARN" "Force continuing with new credentials"
                            break
                            ;;
                        *)
                            echo "Invalid choice. Please enter 1-3."
                            ;;
                    esac
                done
            fi
        fi
    fi
    
    return 0
}

# =============================================================================
# Enhanced Service Startup Functions
# =============================================================================

# Enhanced start_services_with_checks to handle existing installations
start_services_with_checks() {
    local setup_mode="${1:-false}"
    
    log "STEP" "Starting Milou services with pre-flight checks..."
    
    # Check SSL certificates
    local ssl_path
    ssl_path=$(get_config_value "SSL_CERT_PATH" "./ssl")
    
    if [[ -n "$ssl_path" ]]; then
        log "INFO" "Checking SSL certificates..."
        if [[ -f "$ssl_path/milou.crt" && -f "$ssl_path/milou.key" ]]; then
            if check_ssl_expiration "$ssl_path"; then
                log "SUCCESS" "SSL certificates are valid"
            else
                log "WARN" "SSL certificate issues detected"
            fi
        else
            log "WARN" "SSL certificates not found at $ssl_path"
            log "INFO" "💡 Run: $0 ssl --domain YOUR_DOMAIN"
        fi
    fi
    
    # Ensure networks exist
    log "INFO" "Creating required network: proxy"
    ensure_docker_networks
    
    # Enhanced existing installation handling with setup mode awareness
    # First, check if this is a truly fresh installation (no need for conflict checking)
    local is_fresh_install=false
    local existing_containers_count=0
    local existing_volumes_count=0
    local has_config=false
    
    # Count existing containers
    local all_containers
    all_containers=$(docker ps -a --filter "name=static-" --format "{{.Names}}" 2>/dev/null || true)
    if [[ -n "$all_containers" ]]; then
        existing_containers_count=$(echo "$all_containers" | wc -l)
    fi
    
    # Count existing volumes
    local existing_volumes
    existing_volumes=$(docker volume ls --filter "name=static_" --format "{{.Name}}" 2>/dev/null || true)
    if [[ -n "$existing_volumes" ]]; then
        existing_volumes_count=$(echo "$existing_volumes" | wc -l)
    fi
    
    # Check for configuration
    if [[ -f "$ENV_FILE" ]]; then
        has_config=true
    fi
    
    # Determine if this is a fresh install
    if [[ $existing_containers_count -eq 0 && $existing_volumes_count -eq 0 && "$has_config" == false ]]; then
        is_fresh_install=true
        log "DEBUG" "Fresh installation detected - skipping conflict checks"
    elif [[ "$setup_mode" == "true" && $existing_containers_count -eq 0 ]]; then
        # Even if we have old config/volumes, if no containers are running during setup, treat as fresh
        is_fresh_install=true
        log "DEBUG" "Setup mode with no running containers - treating as fresh install"
    fi
    
    # Skip all conflict checking for fresh installations
    if [[ "$is_fresh_install" == "true" ]]; then
        log "DEBUG" "Fresh installation - proceeding directly to service startup"
    else
        # Check for running containers that might conflict
        local running_containers
        running_containers=$(docker ps --filter "name=static-" --format "{{.Names}}" 2>/dev/null || true)
        
        local needs_conflict_handling=false
        local conflict_reason=""
        
        if [[ -n "$running_containers" ]]; then
            needs_conflict_handling=true
            conflict_reason="running containers"
            log "WARN" "Found running Milou containers that may conflict:"
            while IFS= read -r container; do
                [[ -n "$container" ]] && log "WARN" "  🐳 $container"
            done <<< "$running_containers"
        fi
        
        # Check for port conflicts
        local conflicting_ports=()
        local -a ports_to_check=("80" "443" "5432" "6379" "5672" "9999")
        
        for port in "${ports_to_check[@]}"; do
            if command -v netstat >/dev/null 2>&1; then
                local port_in_use
                port_in_use=$(netstat -tlnp 2>/dev/null | grep ":$port " | awk '{print $7}' | head -1)
                if [[ -n "$port_in_use" && ! "$port_in_use" =~ static- ]]; then
                    conflicting_ports+=("$port ($port_in_use)")
                fi
            fi
        done
        
        if [[ ${#conflicting_ports[@]} -gt 0 ]]; then
            for port_info in "${conflicting_ports[@]}"; do
                log "WARN" "  ⚠️  Port $port_info is in use by: "
            done
        fi
        
        # Handle conflicts if needed
        if [[ "$needs_conflict_handling" == "true" ]]; then
            local handle_conflict=false
            
            if [[ "$FORCE" == true ]]; then
                log "WARN" "Force mode enabled - stopping existing services first"
                handle_conflict=true
            elif [[ "$setup_mode" == "true" ]]; then
                # During setup, be more permissive about existing installations
                log "INFO" "Setup mode detected - handling $conflict_reason..."
                
                if [[ "${INTERACTIVE:-true}" == "true" ]]; then
                    echo "During setup, we need to handle existing containers."
                    echo "Options:"
                    echo "  1. Stop existing containers and proceed (recommended)"
                    echo "  2. Force restart (stop and remove containers)"
                    echo "  3. Cancel setup"
                    echo
                    
                    while true; do
                        read -p "Choose option (1-3): " choice
                        case "$choice" in
                            1)
                                log "INFO" "Stopping existing containers..."
                                handle_conflict=true
                                break
                                ;;
                            2)
                                log "INFO" "Force restarting - will remove existing containers..."
                                export FORCE=true
                                handle_conflict=true
                                break
                                ;;
                            3)
                                log "INFO" "Setup cancelled by user"
                                return 1
                                ;;
                            *)
                                echo "Invalid choice. Please enter 1-3."
                                ;;
                        esac
                    done
                else
                    # Non-interactive setup mode
                    log "INFO" "Non-interactive setup - stopping existing containers"
                    handle_conflict=true
                fi
            else
                # Normal start operation with conflicts
                log "ERROR" "Cannot start services due to conflicts"
                log "INFO" "💡 Solutions:"
                log "INFO" "  • Use --force flag to stop existing services"
                log "INFO" "  • Run: $0 stop (to stop Milou services)"
                log "INFO" "  • Run: $0 restart (to restart services)"
                return 1
            fi
            
            if [[ "$handle_conflict" == "true" ]]; then
                if [[ "$FORCE" == true ]]; then
                    log "INFO" "Force mode - stopping and removing existing containers..."
                    if ! stop_services; then
                        log "WARN" "Failed to stop some services, continuing anyway..."
                    fi
                else
                    log "INFO" "Stopping existing containers..."
                    if ! stop_services; then
                        log "ERROR" "Failed to stop existing services"
                        return 1
                    fi
                fi
                
                # Wait for services to fully stop
                log "INFO" "Waiting for services to fully stop..."
                sleep 3
            fi
        fi
        
        # Handle database migration for existing installations
        if [[ "$setup_mode" == "true" && "${MILOU_EXISTING_VOLUMES:-false}" == "true" ]]; then
            if ! handle_database_migration "true"; then
                log "ERROR" "Database migration failed"
                if [[ "${FORCE:-false}" != "true" ]]; then
                    return 1
                fi
            fi
        fi
    fi
    
    # Start services
    if start_services; then
        log "SUCCESS" "Services started successfully with all checks passed"
        return 0
    else
        log "ERROR" "Failed to start services"
        return 1
    fi
}

# Wait for services to be ready (alias for backward compatibility)
wait_for_services() {
    wait_for_services_ready
}

# =============================================================================
# Diagnostic and Troubleshooting Functions
# =============================================================================

# Comprehensive Docker environment diagnosis
diagnose_docker_environment() {
    log "STEP" "Running comprehensive Docker environment diagnosis..."
    echo
    
    local issues=0
    local warnings=0
    
    # Check Docker daemon
    log "INFO" "1. Docker Daemon Status:"
    if docker info >/dev/null 2>&1; then
        log "SUCCESS" "  ✅ Docker daemon is accessible"
        
        # Get Docker version
        local docker_version
        docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
        log "INFO" "  📦 Docker version: $docker_version"
        
        # Check Docker Compose
        local compose_version
        compose_version=$(docker compose version --short 2>/dev/null || echo "unknown")
        log "INFO" "  📦 Docker Compose version: $compose_version"
    else
        log "ERROR" "  ❌ Cannot access Docker daemon"
        ((issues++))
        log "INFO" "    💡 Try: sudo systemctl start docker"
        log "INFO" "    💡 Verify user permissions: sudo usermod -aG docker \$USER"
    fi
    echo
    
    # Check authentication
    log "INFO" "2. Registry Authentication:"
    if docker system info --format '{{.RegistryConfig}}' 2>/dev/null | grep -q "ghcr.io"; then
        log "SUCCESS" "  ✅ GitHub Container Registry authentication configured"
    else
        log "WARN" "  ⚠️  No authentication found for GitHub Container Registry"
        ((warnings++))
    fi
    echo
    
    # Check required images
    log "INFO" "3. Required Docker Images:"
    local -a required_images=(
        "ghcr.io/milou-sh/milou/backend:latest"
        "ghcr.io/milou-sh/milou/frontend:latest"
        "ghcr.io/milou-sh/milou/engine:latest"
        "ghcr.io/milou-sh/milou/nginx:latest"
        "ghcr.io/milou-sh/milou/database:latest"
    )
    
    for image in "${required_images[@]}"; do
        if docker image inspect "$image" >/dev/null 2>&1; then
            log "SUCCESS" "  ✅ $image"
        else
            log "ERROR" "  ❌ $image (not found locally)"
            ((issues++))
        fi
    done
    echo
    
    # Check Docker Compose configuration
    log "INFO" "4. Docker Compose Configuration:"
    local compose_file="static/docker-compose.yml"
    if [[ -f "$compose_file" ]]; then
        log "SUCCESS" "  ✅ Compose file exists: $compose_file"
        
        if docker compose -f "$compose_file" config >/dev/null 2>&1; then
            log "SUCCESS" "  ✅ Compose configuration is valid"
        else
            log "ERROR" "  ❌ Compose configuration is invalid"
            ((issues++))
            log "DEBUG" "  Run 'docker compose -f $compose_file config' for details"
        fi
    else
        log "ERROR" "  ❌ Compose file not found: $compose_file"
        ((issues++))
    fi
    echo
    
    # Check environment variables
    log "INFO" "5. Environment Configuration:"
    local env_file="${SCRIPT_DIR}/.env"
    if [[ -f "$env_file" ]]; then
        log "SUCCESS" "  ✅ Environment file exists: $env_file"
        
        # Check file permissions
        local permissions
        permissions=$(stat -c %a "$env_file" 2>/dev/null || echo "unknown")
        if [[ "$permissions" == "600" ]]; then
            log "SUCCESS" "  ✅ Environment file has secure permissions ($permissions)"
        else
            log "WARN" "  ⚠️  Environment file permissions could be more secure ($permissions)"
            ((warnings++))
            log "INFO" "    💡 Run: chmod 600 $env_file"
        fi
    else
        log "ERROR" "  ❌ Environment file not found: $env_file"
        ((issues++))
        log "INFO" "    💡 Run setup first: ./milou.sh setup"
    fi
    echo
    
    # Check networks
    log "INFO" "6. Docker Networks:"
    local -a required_networks=("milou_network" "proxy")
    for network in "${required_networks[@]}"; do
        if docker network inspect "$network" >/dev/null 2>&1; then
            log "SUCCESS" "  ✅ Network exists: $network"
        else
            log "WARN" "  ⚠️  Network missing: $network"
            ((warnings++))
            log "INFO" "    💡 Will be created automatically during startup"
        fi
    done
    echo
    
    # Check system resources
    log "INFO" "7. System Resources:"
    local disk_space
    disk_space=$(df -h . | awk 'NR==2 {print $4}')
    log "INFO" "  💾 Available disk space: $disk_space"
    
    local memory
    memory=$(free -h | awk 'NR==2{print $7}')
    log "INFO" "  🧠 Available memory: $memory"
    echo
    
    # Check running services
    log "INFO" "8. Current Service Status:"
    if docker compose -f "$compose_file" ps --format "table {{.Service}}\t{{.Status}}" 2>/dev/null; then
        log "SUCCESS" "  ✅ Service status retrieved successfully"
    else
        log "WARN" "  ⚠️  Could not retrieve service status"
        ((warnings++))
    fi
    echo
    
    # Summary
    log "INFO" "Diagnosis Summary:"
    log "INFO" "  🔴 Critical Issues: $issues"
    log "INFO" "  🟡 Warnings: $warnings"
    
    if [[ $issues -eq 0 ]]; then
        log "SUCCESS" "🎉 No critical issues found! System appears healthy."
        return 0
    else
        log "ERROR" "⚠️  Found $issues critical issue(s) that need attention."
        return 1
    fi
}

# Quick health check for running services
quick_health_check() {
    log "INFO" "Running quick health check..."
    
    local compose_file="static/docker-compose.yml"
    local healthy_services=0
    local total_services=0
    
    # Check if compose file exists
    if [[ ! -f "$compose_file" ]]; then
        log "ERROR" "Docker Compose file not found"
        return 1
    fi
    
    # Get list of services
    local services
    services=$(docker compose -f "$compose_file" ps --services 2>/dev/null)
    
    if [[ -z "$services" ]]; then
        log "WARN" "No services found or not running"
        return 1
    fi
    
    echo "Service Health Status:"
    while IFS= read -r service; do
        ((total_services++))
        if check_service_health "$service"; then
            echo "  ✅ $service: Healthy"
            ((healthy_services++))
        else
            echo "  ❌ $service: Unhealthy or not running"
        fi
    done <<< "$services"
    
    echo
    log "INFO" "Health Summary: $healthy_services/$total_services services healthy"
    
    if [[ $healthy_services -eq $total_services ]]; then
        log "SUCCESS" "All services are healthy!"
        return 0
    else
        log "WARN" "Some services are not healthy"
        return 1
    fi
} 