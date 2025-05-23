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
    local setup_mode="${1:-false}"  # New parameter to indicate if called from setup
    
    log "STEP" "Starting Milou services with pre-flight checks..."
    
    # Check if configuration exists first
    if [[ ! -f "$ENV_FILE" ]]; then
        log "WARN" "No configuration file found. You need to run setup first."
        if [[ "${INTERACTIVE:-true}" == "true" ]] && confirm "Would you like to run the interactive setup now?" "Y"; then
            interactive_setup_wizard
            return $?
        else
            log "INFO" "Please run: $0 setup"
            return 1
        fi
    fi
    
    # Check Docker access
    if ! check_docker_access; then
        return 1
    fi
    
    # Check SSL certificates before starting services
    log "INFO" "Checking SSL certificates..."
    local ssl_path="${DEFAULT_SSL_PATH:-./ssl}"
    if [[ -f "$ENV_FILE" ]]; then
        # Try to get SSL path from config
        ssl_path=$(grep "^SSL_CERT_PATH=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 || echo "$ssl_path")
    fi
    
    if [[ ! -f "$ssl_path/milou.crt" || ! -f "$ssl_path/milou.key" ]]; then
        log "ERROR" "SSL certificate files are missing:"
        log "ERROR" "  Expected: $ssl_path/milou.crt"
        log "ERROR" "  Expected: $ssl_path/milou.key"
        log "INFO" "💡 Run SSL setup: $0 ssl --domain your-domain.com"
        log "INFO" "💡 Or run full setup: $0 setup"
        return 1
    fi
    
    # Validate SSL certificates
    if command -v openssl >/dev/null 2>&1; then
        if ! openssl x509 -in "$ssl_path/milou.crt" -noout >/dev/null 2>&1; then
            log "ERROR" "SSL certificate file is invalid: $ssl_path/milou.crt"
            return 1
        fi
        if ! openssl rsa -in "$ssl_path/milou.key" -check -noout >/dev/null 2>&1; then
            log "ERROR" "SSL private key file is invalid: $ssl_path/milou.key"
            return 1
        fi
        log "SUCCESS" "SSL certificates are valid"
    else
        log "WARN" "OpenSSL not available - skipping SSL certificate validation"
    fi
    
    # Ensure networks exist
    log "INFO" "Creating required network: proxy"
    ensure_docker_networks
    
    # Enhanced existing installation handling with setup mode awareness
    if ! check_existing_installation >/dev/null 2>&1; then
        # Existing installation found
        local handle_conflict=false
        
        if [[ "$FORCE" == true ]]; then
            log "WARN" "Force mode enabled - stopping existing services first"
            handle_conflict=true
        elif [[ "$setup_mode" == "true" ]]; then
            # During setup, be more permissive about existing installations
            log "INFO" "Setup mode detected - checking for actual conflicts..."
            
            # Check if services are actually running and conflicting
            local running_containers
            running_containers=$(docker ps --filter "name=static-" --format "{{.Names}}" 2>/dev/null || true)
            
            if [[ -n "$running_containers" ]]; then
                log "WARN" "Found running containers that may conflict:"
                echo "$running_containers" | sed 's/^/  🐳 /'
                echo
                
                if [[ "${INTERACTIVE:-true}" == "true" ]]; then
                    echo "During setup, we need to handle existing containers."
                    echo "Options:"
                    echo "  1. Stop existing containers and proceed (recommended)"
                    echo "  2. Force restart (stop and remove containers)"
                    echo "  3. Cancel setup"
                    echo
                    
                    while true; do
                        echo -ne "${CYAN}Choose option (1-3): ${NC}"
                        read -r choice
                        case "$choice" in
                            1)
                                log "INFO" "Stopping existing containers..."
                                handle_conflict=true
                                break
                                ;;
                            2)
                                log "INFO" "Force restarting - will remove existing containers..."
                                handle_conflict=true
                                FORCE=true
                                export FORCE
                                break
                                ;;
                            3)
                                log "INFO" "Setup cancelled by user"
                                return 1
                                ;;
                            *)
                                echo "Invalid choice. Please enter 1, 2, or 3."
                                ;;
                        esac
                    done
                else
                    # Non-interactive setup mode - auto-handle conflicts
                    log "INFO" "Non-interactive setup mode - automatically stopping existing containers"
                    handle_conflict=true
                fi
            else
                # No running containers - just old artifacts, safe to proceed
                log "INFO" "Found old installation artifacts but no running services - proceeding..."
                handle_conflict=false
            fi
        else
            # Normal start command - be more strict
            log "WARN" "Existing installation detected. Use --force to override or stop services manually."
            log "INFO" "Available options:"
            log "INFO" "  • Run with --force to automatically stop conflicting services"
            log "INFO" "  • Run '$0 stop' to stop current services first"
            log "INFO" "  • Run '$0 cleanup --complete' to remove everything and start fresh"
            return 1
        fi
        
        # Handle the conflict if needed
        if [[ "$handle_conflict" == "true" ]]; then
            if [[ "$FORCE" == "true" ]]; then
                log "INFO" "Force mode - stopping and removing existing containers..."
                stop_services || true
                # Also remove containers to ensure clean state
                local existing_containers
                existing_containers=$(docker ps -a --filter "name=static-" --format "{{.Names}}" 2>/dev/null || true)
                if [[ -n "$existing_containers" ]]; then
                    echo "$existing_containers" | xargs docker rm -f 2>/dev/null || true
                    log "INFO" "Removed existing containers for clean restart"
                fi
            else
                log "INFO" "Stopping existing services gracefully..."
                if ! stop_services; then
                    log "WARN" "Failed to stop some services, but continuing anyway..."
                fi
            fi
            
            # Brief pause to let services fully stop
            log "INFO" "Waiting for services to fully stop..."
            sleep 3
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