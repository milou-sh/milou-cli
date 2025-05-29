#!/bin/bash

# =============================================================================
# Milou CLI - Docker Management Module
# Consolidated Docker operations to eliminate code duplication
# Version: 3.1.0 - Refactored Edition
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Module guard to prevent multiple loading
if [[ "${MILOU_DOCKER_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_DOCKER_LOADED="true"

# Ensure core modules are loaded
if [[ "${MILOU_CORE_LOADED:-}" != "true" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/_core.sh" || {
        echo "ERROR: Cannot load core module" >&2
        return 1
    }
fi

if [[ "${MILOU_VALIDATION_LOADED:-}" != "true" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/_validation.sh" || {
        echo "ERROR: Cannot load validation module" >&2
        return 1
    }
fi

# =============================================================================
# DOCKER ENVIRONMENT CONFIGURATION
# =============================================================================

# Docker environment variables with defaults
declare -g DOCKER_ENV_FILE=""
declare -g DOCKER_COMPOSE_FILE=""
declare -g DOCKER_PROJECT_NAME="milou"
declare -g DOCKER_VOLUMES_CLEANED=false
declare -g GITHUB_REGISTRY="${GITHUB_REGISTRY:-ghcr.io/milou-sh/milou}"
declare -g GITHUB_API_BASE="${GITHUB_API_BASE:-https://api.github.com}"
declare -g REGISTRY_TIMEOUT="${REGISTRY_TIMEOUT:-30}"

# =============================================================================
# DOCKER INITIALIZATION AND SETUP
# =============================================================================

# Initialize Docker environment - SINGLE AUTHORITATIVE IMPLEMENTATION
docker_init() {
    local env_file="${1:-${SCRIPT_DIR}/.env}"
    local compose_file="${2:-${SCRIPT_DIR}/static/docker-compose.yml}"
    local quiet="${3:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Initializing Docker environment..."
    
    # Check Docker access first
    if ! validate_docker_access "true" "false" "true" "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Docker access validation failed"
        return 1
    fi
    
    # Set global variables
    DOCKER_ENV_FILE="$env_file"
    DOCKER_COMPOSE_FILE="$compose_file"
    
    # Validate files exist
    if [[ ! -f "$DOCKER_ENV_FILE" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Environment file not found: $DOCKER_ENV_FILE"
        return 1
    fi
    
    if [[ ! -f "$DOCKER_COMPOSE_FILE" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Compose file not found: $DOCKER_COMPOSE_FILE"
        return 1
    fi
    
    # Test Docker Compose configuration
    if ! docker compose --env-file "$DOCKER_ENV_FILE" -f "$DOCKER_COMPOSE_FILE" config --quiet 2>/dev/null; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Docker Compose configuration is invalid"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Check your environment file: $DOCKER_ENV_FILE"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Check your compose file: $DOCKER_COMPOSE_FILE"
        return 1
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Docker environment initialized successfully"
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "  Environment file: $DOCKER_ENV_FILE"
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "  Compose file: $DOCKER_COMPOSE_FILE"
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "  Project name: $DOCKER_PROJECT_NAME"
    
    return 0
}

# Docker Compose wrapper with proper environment - SINGLE AUTHORITATIVE IMPLEMENTATION
docker_compose() {
    if [[ -z "$DOCKER_ENV_FILE" || -z "$DOCKER_COMPOSE_FILE" ]]; then
        milou_log "ERROR" "Docker environment not initialized. Call docker_init first."
        return 1
    fi
    
    # Execute docker compose with proper environment
    docker compose --env-file "$DOCKER_ENV_FILE" -f "$DOCKER_COMPOSE_FILE" "$@"
}

# Create Docker networks if they don't exist
docker_create_networks() {
    local quiet="${1:-false}"
    
    local network_name="${DOCKER_PROJECT_NAME}_default"
    
    # Create default project network
    if ! docker network inspect "$network_name" >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "INFO" "Creating Docker network: $network_name"
        if docker network create "$network_name" >/dev/null 2>&1; then
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "Created network: $network_name"
        else
            [[ "$quiet" != "true" ]] && milou_log "WARN" "Failed to create network: $network_name"
        fi
    else
        [[ "$quiet" != "true" ]] && milou_log "TRACE" "Network already exists: $network_name"
    fi
    
    # Create external proxy network if it doesn't exist
    if ! docker network inspect "proxy" >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "INFO" "Creating external proxy network: proxy"
        if docker network create "proxy" >/dev/null 2>&1; then
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "Created external network: proxy"
        else
            [[ "$quiet" != "true" ]] && milou_log "WARN" "Failed to create external network: proxy"
        fi
    else
        [[ "$quiet" != "true" ]] && milou_log "TRACE" "External proxy network already exists"
    fi
}

# =============================================================================
# DOCKER REGISTRY AUTHENTICATION
# =============================================================================

# Setup Docker registry authentication
docker_setup_registry_auth() {
    local github_token="$1"
    local quiet="${2:-false}"
    
    if [[ -z "$github_token" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "WARN" "No GitHub token provided - private registry images may fail to pull"
        return 0
    fi
    
    # Validate token format first
    if ! validate_github_token "$github_token" "false"; then
        [[ "$quiet" != "true" ]] && milou_log "WARN" "GitHub token validation failed, continuing without registry auth"
        return 0
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Setting up Docker registry authentication..."
    
    # Get username from GitHub API
    local username
    username=$(curl -s -H "Authorization: Bearer $github_token" \
               "https://api.github.com/user" 2>/dev/null | \
               grep -o '"login": *"[^"]*"' | cut -d'"' -f4 2>/dev/null)
    
    if [[ -z "$username" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "WARN" "Could not get GitHub username, using token as username"
        username="token"
    fi
    
    # Login to GitHub Container Registry
    if echo "$github_token" | docker login ghcr.io -u "$username" --password-stdin >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "Docker registry authentication successful"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Docker registry authentication failed"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Ensure your token has 'read:packages' and 'write:packages' scopes"
        return 1
    fi
}

# =============================================================================
# SERVICE MANAGEMENT OPERATIONS
# =============================================================================

# Start all services - SINGLE AUTHORITATIVE IMPLEMENTATION
docker_start() {
    local github_token="${1:-${GITHUB_TOKEN:-}}"
    local check_conflicts="${2:-true}"
    local quiet="${3:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "STEP" "Starting Milou services..."
    
    # Initialize Docker environment if needed
    if [[ -z "$DOCKER_ENV_FILE" ]]; then
        if ! docker_init "" "" "$quiet"; then
            return 1
        fi
    fi
    
    # Check for conflicting containers if requested
    if [[ "$check_conflicts" == "true" ]]; then
        local running_containers
        running_containers=$(docker ps --filter "name=milou-" --format "{{.Names}}" 2>/dev/null || true)
        if [[ -n "$running_containers" ]]; then
            [[ "$quiet" != "true" ]] && milou_log "WARN" "Found running Milou containers:"
            while IFS= read -r container; do
                [[ -n "$container" ]] && [[ "$quiet" != "true" ]] && milou_log "WARN" "  🐳 $container"
            done <<< "$running_containers"
            
            if [[ "${MILOU_FORCE:-false}" == "true" ]]; then
                [[ "$quiet" != "true" ]] && milou_log "WARN" "Force mode enabled - stopping existing services first"
                if ! docker_stop "" "$quiet"; then
                    [[ "$quiet" != "true" ]] && milou_log "WARN" "Failed to stop some services, continuing anyway..."
                fi
                sleep 3
            else
                [[ "$quiet" != "true" ]] && milou_log "ERROR" "Cannot start services due to conflicts"
                [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Solutions:"
                [[ "$quiet" != "true" ]] && milou_log "INFO" "  • Use --force flag to stop existing services"
                [[ "$quiet" != "true" ]] && milou_log "INFO" "  • Run: ./milou.sh stop (to stop Milou services)"
                [[ "$quiet" != "true" ]] && milou_log "INFO" "  • Run: ./milou.sh restart (to restart services)"
                return 1
            fi
        fi
    fi
    
    # Setup Docker registry authentication if token provided
    if [[ -n "$github_token" ]]; then
        docker_setup_registry_auth "$github_token" "$quiet"
    fi
    
    # Create networks
    docker_create_networks "$quiet"
    
    # Start services
    [[ "$quiet" != "true" ]] && milou_log "INFO" "Starting services with Docker Compose..."
    if docker_compose up -d --remove-orphans; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "Services started successfully"
        
        # Give services a moment to initialize
        sleep 5
        
        # Basic health check
        local healthy_services=0
        local total_services
        total_services=$(docker_compose config --services 2>/dev/null | wc -l || echo "0")
        
        if [[ "$total_services" -gt 0 ]]; then
            # Give services time to start
            local max_wait=30
            local wait_time=0
            
            while [[ $wait_time -lt $max_wait ]]; do
                healthy_services=$(docker_compose ps --services --filter "status=running" 2>/dev/null | wc -l || echo "0")
                
                if [[ "$healthy_services" -eq "$total_services" ]]; then
                    break
                fi
                
                sleep 2
                ((wait_time += 2))
            done
            
            [[ "$quiet" != "true" ]] && milou_log "INFO" "Services status: $healthy_services/$total_services running"
            
            if [[ "$healthy_services" -eq "$total_services" ]]; then
                [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "All services are running successfully"
            else
                [[ "$quiet" != "true" ]] && milou_log "WARN" "Some services may still be starting up"
                [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Check status with: ./milou.sh status"
            fi
        fi
        
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to start services"
        return 1
    fi
}

# Stop all services - SINGLE AUTHORITATIVE IMPLEMENTATION
docker_stop() {
    local remove_orphans="${1:-true}"
    local quiet="${2:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "STEP" "Stopping Milou services..."
    
    # Initialize Docker environment if needed
    if [[ -z "$DOCKER_ENV_FILE" ]]; then
        if ! docker_init "" "" "$quiet"; then
            return 1
        fi
    fi
    
    local compose_args=()
    if [[ "$remove_orphans" == "true" ]]; then
        compose_args+=("--remove-orphans")
    fi
    
    if docker_compose down "${compose_args[@]}"; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "Services stopped successfully"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to stop services"
        return 1
    fi
}

# Restart all services - SINGLE AUTHORITATIVE IMPLEMENTATION
docker_restart() {
    local github_token="${1:-${GITHUB_TOKEN:-}}"
    local quiet="${2:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "STEP" "Restarting Milou services..."
    
    if docker_stop "true" "$quiet" && sleep 2 && docker_start "$github_token" "false" "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "Services restarted successfully"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to restart services"
        return 1
    fi
}

# Start a specific service
docker_start_service() {
    local service="$1"
    local quiet="${2:-false}"
    
    if [[ -z "$service" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Service name is required"
        return 1
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Starting service: $service"
    
    # Initialize Docker environment if needed
    if [[ -z "$DOCKER_ENV_FILE" ]]; then
        if ! docker_init "" "" "$quiet"; then
            return 1
        fi
    fi
    
    if docker_compose up -d "$service"; then
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Service $service started successfully"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to start service: $service"
        return 1
    fi
}

# Stop a specific service
docker_stop_service() {
    local service="$1"
    local quiet="${2:-false}"
    
    if [[ -z "$service" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Service name is required"
        return 1
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Stopping service: $service"
    
    # Initialize Docker environment if needed
    if [[ -z "$DOCKER_ENV_FILE" ]]; then
        if ! docker_init "" "" "$quiet"; then
            return 1
        fi
    fi
    
    if docker_compose stop "$service"; then
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Service $service stopped successfully"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "WARN" "Failed to stop service: $service"
        return 1
    fi
}

# =============================================================================
# SERVICE STATUS AND MONITORING
# =============================================================================

# Get service status with detailed information - SINGLE AUTHORITATIVE IMPLEMENTATION
docker_status() {
    local show_header="${1:-true}"
    local detailed="${2:-false}"
    
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
    if ! docker_init "" "" "true"; then
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
    if ! compose_status=$(docker_compose ps 2>&1); then
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
    total_services=$(docker_compose config --services 2>/dev/null | wc -l || echo "0")
    
    # Count running services more accurately
    running_services=0
    stopped_services=0
    unhealthy_services=0
    
    if [[ "$total_services" -gt 0 ]]; then
        # Get detailed status of each service
        while IFS= read -r service; do
            if [[ -n "$service" ]]; then
                local container_name="milou-${service}"
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
        done < <(docker_compose config --services 2>/dev/null)
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
        milou_log "SUCCESS" "🌐 Network: $network_name (active)"
    else
        milou_log "WARN" "🌐 Network: $network_name (missing)"
    fi
    
    # Show additional information if detailed mode
    if [[ "$detailed" == "true" ]]; then
        echo
        milou_log "INFO" "🔧 Docker Environment Details:"
        milou_log "INFO" "   • Environment file: $(basename "$DOCKER_ENV_FILE")"
        milou_log "INFO" "   • Compose file: $(basename "$DOCKER_COMPOSE_FILE")"
        milou_log "INFO" "   • Project name: $DOCKER_PROJECT_NAME"
        
        # Show disk usage
        local disk_usage
        if disk_usage=$(docker system df 2>/dev/null); then
            echo
            milou_log "INFO" "💾 Docker Disk Usage:"
            echo "$disk_usage"
        fi
    fi
    
    # Show helpful commands if there are issues
    if [[ $running_services -lt $total_services ]]; then
        echo
        milou_log "INFO" "💡 Helpful commands:"
        milou_log "INFO" "   ./milou.sh start      # Start services"
        milou_log "INFO" "   ./milou.sh restart    # Restart services"
        milou_log "INFO" "   ./milou.sh logs       # View service logs"
        milou_log "INFO" "   ./milou.sh health     # Run health checks"
        milou_log "INFO" "   ./milou.sh shell <service>  # Access service shell"
    fi
    
    return 0
}

# =============================================================================
# SERVICE LOGS AND DEBUGGING
# =============================================================================

# Show service logs - SINGLE AUTHORITATIVE IMPLEMENTATION
docker_logs() {
    local service="${1:-}"
    local follow="${2:-false}"
    local tail_lines="${3:-50}"
    local quiet="${4:-false}"
    
    # Initialize Docker environment if needed
    if [[ -z "$DOCKER_ENV_FILE" ]]; then
        if ! docker_init "" "" "$quiet"; then
            return 1
        fi
    fi
    
    local compose_args=()
    
    if [[ "$follow" == "true" ]]; then
        compose_args+=("-f")
    fi
    
    if [[ -n "$tail_lines" ]]; then
        compose_args+=("--tail=$tail_lines")
    fi
    
    if [[ -n "$service" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "INFO" "📋 Showing logs for service: $service"
        docker_compose logs "${compose_args[@]}" "$service"
    else
        [[ "$quiet" != "true" ]] && milou_log "INFO" "📋 Showing logs for all services"
        docker_compose logs "${compose_args[@]}"
    fi
}

# Get shell access to a service - SINGLE AUTHORITATIVE IMPLEMENTATION  
docker_shell() {
    local service="$1"
    local shell="${2:-/bin/bash}"
    local quiet="${3:-false}"
    
    if [[ -z "$service" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Service name is required"
        return 1
    fi
    
    # Initialize Docker environment if needed
    if [[ -z "$DOCKER_ENV_FILE" ]]; then
        if ! docker_init "" "" "$quiet"; then
            return 1
        fi
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🐚 Opening shell in $service container..."
    
    # Try bash first, then sh as fallback
    if ! docker_compose exec "$service" "$shell"; then
        if [[ "$shell" == "/bin/bash" ]]; then
            [[ "$quiet" != "true" ]] && milou_log "INFO" "Bash not available, trying sh..."
            docker_compose exec "$service" /bin/sh
        else
            return 1
        fi
    fi
}

# =============================================================================
# HEALTH CHECKS AND DIAGNOSTICS
# =============================================================================

# Run quick health check
docker_health_check() {
    local quiet="${1:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "⚡ Running quick health check..."
    
    # Initialize Docker environment if needed
    if [[ -z "$DOCKER_ENV_FILE" ]]; then
        if ! docker_init "" "" "true"; then
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "Docker environment not available"
            return 1
        fi
    fi
    
    local running_services
    running_services=$(docker_compose ps --services --filter "status=running" 2>/dev/null | wc -l || echo "0")
    local total_services
    total_services=$(docker_compose config --services 2>/dev/null | wc -l || echo "0")
    
    if [[ "$running_services" -eq "$total_services" && "$total_services" -gt 0 ]]; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Quick check passed: All $total_services services running"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "WARN" "⚠️  Quick check: $running_services/$total_services services running"
        return 1
    fi
}

# Run comprehensive health checks
docker_health_comprehensive() {
    milou_log "STEP" "Running comprehensive health checks..."
    
    # Initialize if needed
    if [[ -z "$DOCKER_ENV_FILE" ]]; then
        if ! docker_init "" "" "true"; then
            milou_log "ERROR" "Failed to initialize Docker environment"
            return 1
        fi
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
    total_services=$(docker_compose config --services 2>/dev/null | wc -l || echo "0")
    running_services=$(docker_compose ps --services --filter "status=running" 2>/dev/null | wc -l || echo "0")
    
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
    
    # 4. Volume checks
    milou_log "INFO" "4️⃣  Volume Status"
    local volumes
    volumes=$(docker_compose config --volumes 2>/dev/null | wc -l || echo "0")
    if [[ "$volumes" -gt 0 ]]; then
        milou_log "SUCCESS" "   ✅ Found $volumes configured volumes"
    else
        milou_log "WARN" "   ⚠️  No volumes configured"
    fi
    
    # 5. Resource usage
    milou_log "INFO" "5️⃣  Resource Usage"
    if validate_docker_resources "true" "true" "false" "true"; then
        milou_log "SUCCESS" "   ✅ Resource usage is acceptable"
    else
        milou_log "WARN" "   ⚠️  Resource usage issues detected"
        ((issues_found++))
    fi
    
    echo
    if [[ $issues_found -eq 0 ]]; then
        milou_log "SUCCESS" "🎉 All health checks passed!"
    else
        milou_log "WARN" "⚠️  Health check completed with $issues_found issue(s) found."
    fi
    
    return $issues_found
}

# =============================================================================
# IMAGE MANAGEMENT
# =============================================================================

# Pull Docker images
docker_pull_images() {
    local quiet="${1:-false}"
    local specific_service="${2:-}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "📥 Pulling Docker images..."
    
    # Initialize Docker environment if needed
    if [[ -z "$DOCKER_ENV_FILE" ]]; then
        if ! docker_init "" "" "$quiet"; then
            return 1
        fi
    fi
    
    local pull_args=()
    
    # Add quiet flag if not running in a TTY or if quiet mode requested
    if [[ "$quiet" == "true" ]] || ! tty -s; then
        pull_args+=("-q")
    fi
    
    if [[ -n "$specific_service" ]]; then
        pull_args+=("$specific_service")
    fi
    
    if docker_compose pull "${pull_args[@]}"; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "Docker images pulled successfully"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to pull Docker images"
        return 1
    fi
}

# =============================================================================
# CLEANUP OPERATIONS
# =============================================================================

# Clean up Docker resources
docker_cleanup() {
    local include_images="${1:-false}"
    local include_volumes="${2:-false}"
    local include_networks="${3:-false}"
    local aggressive="${4:-false}"
    local quiet="${5:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "STEP" "Cleaning up Docker resources..."
    
    local cleaned_items=0
    
    # Clean containers first
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🗑️  Removing stopped containers..."
    if docker container prune -f >/dev/null 2>&1; then
        ((cleaned_items++))
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "Stopped containers removed"
    fi
    
    # Clean images if requested
    if [[ "$include_images" == "true" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "INFO" "🗑️  Removing unused images..."
        if [[ "$aggressive" == "true" ]]; then
            if docker image prune -a -f >/dev/null 2>&1; then
                ((cleaned_items++))
                [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "All unused images removed"
            fi
        else
            if docker image prune -f >/dev/null 2>&1; then
                ((cleaned_items++))
                [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "Dangling images removed"
            fi
        fi
    fi
    
    # Clean volumes if requested
    if [[ "$include_volumes" == "true" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "INFO" "🗑️  Removing unused volumes..."
        if docker volume prune -f >/dev/null 2>&1; then
            ((cleaned_items++))
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "Unused volumes removed"
        fi
    fi
    
    # Clean networks if requested
    if [[ "$include_networks" == "true" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "INFO" "🗑️  Removing unused networks..."
        if docker network prune -f >/dev/null 2>&1; then
            ((cleaned_items++))
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "Unused networks removed"
        fi
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "Cleanup completed ($cleaned_items operations)"
    return 0
}

# =============================================================================
# LEGACY ALIASES FOR BACKWARDS COMPATIBILITY
# =============================================================================

# Legacy aliases (will be removed after full refactoring)
milou_docker_init() { docker_init "$@"; }
milou_docker_compose() { docker_compose "$@"; }
milou_docker_start() { docker_start "$@"; }
milou_docker_stop() { docker_stop "$@"; }
milou_docker_restart() { docker_restart "$@"; }
milou_docker_status() { docker_status "$@"; }
milou_docker_logs() { docker_logs "$@"; }
milou_docker_shell() { docker_shell "$@"; }
milou_docker_start_service() { docker_start_service "$@"; }
milou_docker_stop_service() { docker_stop_service "$@"; }

# Legacy health check aliases
run_health_checks() { docker_health_comprehensive "$@"; }
quick_health_check() { docker_health_check "$@"; }

# =============================================================================
# EXPORT ALL FUNCTIONS
# =============================================================================

# Core Docker operations (new clean API)
export -f docker_init
export -f docker_compose
export -f docker_start
export -f docker_stop
export -f docker_restart
export -f docker_status
export -f docker_logs
export -f docker_shell
export -f docker_start_service
export -f docker_stop_service

# Docker management operations
export -f docker_setup_registry_auth
export -f docker_create_networks
export -f docker_pull_images
export -f docker_cleanup

# Health check operations  
export -f docker_health_check
export -f docker_health_comprehensive

# Legacy aliases (for backwards compatibility during transition)
export -f milou_docker_init
export -f milou_docker_compose
export -f milou_docker_start
export -f milou_docker_stop
export -f milou_docker_restart
export -f milou_docker_status
export -f milou_docker_logs
export -f milou_docker_shell
export -f milou_docker_start_service
export -f milou_docker_stop_service
export -f run_health_checks
export -f quick_health_check

milou_log "DEBUG" "Docker module loaded successfully" 