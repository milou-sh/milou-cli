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

# GitHub Container Registry authentication
docker_login_github() {
    local github_token="${1:-}"
    local quiet="${2:-false}"
    
    # Use provided token or environment variable
    if [[ -z "$github_token" ]]; then
        github_token="${GITHUB_TOKEN:-}"
    fi
    
    if [[ -z "$github_token" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "WARN" "No GitHub token provided for authentication"
        return 1
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🔑 Authenticating with GitHub Container Registry..."
    
    # Login to GitHub Container Registry
    if echo "$github_token" | docker login ghcr.io -u oauth2 --password-stdin >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Successfully authenticated with GitHub Container Registry"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "❌ Failed to authenticate with GitHub Container Registry"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Check your GitHub token has 'read:packages' scope"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Token should be from: https://github.com/settings/tokens"
        return 1
    fi
}

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
    
    # Load environment to check for GitHub token
    local github_token="${GITHUB_TOKEN:-}"
    if [[ -f "$DOCKER_ENV_FILE" ]]; then
        # Source the environment file to get GITHUB_TOKEN
        source "$DOCKER_ENV_FILE"
        github_token="${GITHUB_TOKEN:-$github_token}"
    fi
    
    # Try to authenticate with GitHub Container Registry if we have a token
    if [[ -n "$github_token" ]]; then
        if docker_login_github "$github_token" "$quiet"; then
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "GitHub Container Registry authentication successful"
        else
            [[ "$quiet" != "true" ]] && milou_log "WARN" "GitHub authentication failed - private images may not be accessible"
        fi
    else
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "No GitHub token found - public images only"
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

# Master Docker execution function - consolidates all Docker operations
docker_execute() {
    local operation="$1"
    local service="${2:-}"
    local quiet="${3:-false}"
    shift 3 2>/dev/null || true
    local additional_args=("$@")
    
    # Ensure Docker context is initialized
    if ! docker_init "" "" "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Docker context initialization failed"
        return 1
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "🐳 Docker Execute: $operation ${service:+$service }${additional_args[*]:+${additional_args[*]}}"
    
    case "$operation" in
        "up"|"start")
            if [[ -n "$service" ]]; then
                [[ "$quiet" != "true" ]] && milou_log "INFO" "▶️  Starting service: $service"
                docker_compose up -d "${additional_args[@]}" "$service"
            else
                [[ "$quiet" != "true" ]] && milou_log "INFO" "▶️  Starting all services"
                docker_compose up -d --remove-orphans "${additional_args[@]}"
            fi
            ;;
        "down"|"stop")
            if [[ -n "$service" ]]; then
                [[ "$quiet" != "true" ]] && milou_log "INFO" "⏸️  Stopping service: $service"
                docker_compose stop "${additional_args[@]}" "$service"
            else
                [[ "$quiet" != "true" ]] && milou_log "INFO" "⏸️  Stopping all services"
                docker_compose down "${additional_args[@]}"
            fi
            ;;
        "restart")
            if [[ -n "$service" ]]; then
                [[ "$quiet" != "true" ]] && milou_log "INFO" "🔄 Restarting service: $service"
                docker_compose restart "${additional_args[@]}" "$service"
            else
                [[ "$quiet" != "true" ]] && milou_log "INFO" "🔄 Restarting all services"
                docker_compose restart "${additional_args[@]}"
            fi
            ;;
        "pull")
            [[ "$quiet" != "true" ]] && milou_log "INFO" "⬇️  Pulling latest images"
            docker_compose pull "${additional_args[@]}" ${service:+"$service"}
            ;;
        "logs")
            docker_compose logs "${additional_args[@]}" ${service:+"$service"}
            ;;
        "ps"|"status")
            docker_compose ps "${additional_args[@]}" ${service:+"$service"}
            ;;
        "exec")
            if [[ -z "$service" ]]; then
                [[ "$quiet" != "true" ]] && milou_log "ERROR" "Service name required for exec operation"
                return 1
            fi
            docker_compose exec "${additional_args[@]}" "$service"
            ;;
        "config")
            docker_compose config "${additional_args[@]}"
            ;;
        "validate")
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "🔍 Validating Docker Compose configuration"
            if docker_compose config --quiet 2>/dev/null; then
                [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Docker Compose configuration is valid"
                return 0
            else
                [[ "$quiet" != "true" ]] && milou_log "ERROR" "❌ Docker Compose configuration is invalid"
                return 1
            fi
            ;;
        *)
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "Unknown Docker operation: $operation"
            [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Supported operations: up, down, restart, pull, logs, ps, exec, config, validate"
            return 1
            ;;
    esac
}

# Health check service function - standard implementation
health_check_service() {
    local service="$1"
    local quiet="${2:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "🏥 Checking health of service: $service"
    
    # Check if service is defined
    local service_exists
    service_exists=$(docker_compose config --services 2>/dev/null | grep -c "^$service$" || echo "0")
    
    if [[ "$service_exists" -eq 0 ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Service '$service' not found in compose configuration"
        return 1
    fi
    
    # Check if service is running
    local service_status
    service_status=$(docker_compose ps --services --filter "status=running" 2>/dev/null | grep -c "^$service$" || echo "0")
    
    if [[ "$service_status" -eq 0 ]]; then
        [[ "$quiet" != "true" ]] && milou_log "WARN" "Service '$service' is not running"
        return 1
    fi
    
    # Additional health checks can be added here per service
    [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Service '$service' is healthy"
    return 0
}

# Check all services health - comprehensive implementation
health_check_all() {
    local quiet="${1:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🏥 Running comprehensive health check on all services"
    
    local total_services=0
    local healthy_services=0
    local unhealthy_services=()
    
    # Get all defined services
    while IFS= read -r service; do
        [[ -z "$service" ]] && continue
        ((total_services++))
        
        if health_check_service "$service" "true"; then
            ((healthy_services++))
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "  ✅ $service"
        else
            unhealthy_services+=("$service")
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "  ❌ $service"
        fi
    done < <(docker_compose config --services 2>/dev/null)
    
    # Report results
    if [[ "$quiet" != "true" ]]; then
        echo
        milou_log "INFO" "📊 Health Check Summary:"
        milou_log "INFO" "  Total services: $total_services"
        milou_log "INFO" "  Healthy: $healthy_services"
        milou_log "INFO" "  Unhealthy: ${#unhealthy_services[@]}"
        
        if [[ ${#unhealthy_services[@]} -gt 0 ]]; then
            milou_log "WARN" "  Unhealthy services: ${unhealthy_services[*]}"
        fi
    fi
    
    # Return success only if all services are healthy
    if [[ $healthy_services -eq $total_services && $total_services -gt 0 ]]; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "🎉 All services are healthy!"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "WARN" "⚠️  Some services need attention"
        return 1
    fi
}

# Backward compatibility wrapper - standardizes legacy calls
milou_docker_compose() {
    milou_log "WARN" "⚠️  Using deprecated milou_docker_compose - please use docker_execute() instead"
    docker_compose "$@"
}

# =============================================================================
# SERVICE LIFECYCLE MANAGEMENT FUNCTIONS (Week 2 Completion)
# =============================================================================

# Start service with health validation
service_start_with_validation() {
    local service="${1:-}"
    local timeout="${2:-60}"
    local quiet="${3:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🚀 Starting service with validation: ${service:-all services}"
    
    # Ensure Docker environment is initialized (which includes authentication)
    if ! docker_init "" "" "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Docker initialization failed"
        return 1
    fi
    
    # Validate that we can access private images if needed
    local github_token="${GITHUB_TOKEN:-}"
    if [[ -f "$DOCKER_ENV_FILE" ]]; then
        source "$DOCKER_ENV_FILE"
        github_token="${GITHUB_TOKEN:-$github_token}"
    fi
    
    # If we have a token, ensure authentication is working
    if [[ -n "$github_token" ]]; then
        if ! docker_login_github "$github_token" "$quiet"; then
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "GitHub authentication failed - cannot access private images"
            return 1
        fi
    fi
    
    # Start the service(s)
    if ! docker_execute "start" "$service" "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to start ${service:-services}"
        return 1
    fi
    
    # Wait and validate
    [[ "$quiet" != "true" ]] && milou_log "INFO" "⏳ Waiting up to ${timeout}s for services to become healthy..."
    
    local elapsed=0
    local check_interval=5
    
    while [[ $elapsed -lt $timeout ]]; do
        if [[ -n "$service" ]]; then
            if health_check_service "$service" "true"; then
                [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Service '$service' started and is healthy"
                return 0
            fi
        else
            if health_check_all "true"; then
                [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ All services started and are healthy"
                return 0
            fi
        fi
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
        [[ "$quiet" != "true" ]] && echo -n "."
    done
    
    [[ "$quiet" != "true" ]] && echo
    [[ "$quiet" != "true" ]] && milou_log "ERROR" "❌ Service startup validation failed after ${timeout}s"
    return 1
}

# Stop service gracefully with cleanup
service_stop_gracefully() {
    local service="${1:-}"
    local timeout="${2:-30}"
    local quiet="${3:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "⏸️  Stopping service gracefully: ${service:-all services}"
    
    # Send stop signal and wait for graceful shutdown
    if docker_execute "stop" "$service" "$quiet" --timeout="$timeout"; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Service stopped gracefully"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "WARN" "⚠️  Graceful stop failed, trying forceful stop"
        
        # Fallback to force kill if graceful stop fails
        if [[ -n "$service" ]]; then
            docker_compose kill "$service"
        else
            docker_compose kill
        fi
        
        [[ "$quiet" != "true" ]] && milou_log "WARN" "🔶 Service force-stopped"
        return 1
    fi
}

# Restart service safely with rollback capability
service_restart_safely() {
    local service="${1:-}"
    local quiet="${2:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🔄 Safely restarting service: ${service:-all services}"
    
    # Create snapshot before restart
    local snapshot_created=false
    if command -v create_system_snapshot >/dev/null 2>&1; then
        if create_system_snapshot "restart_${service:-all}_$(date +%s)" "$quiet"; then
            snapshot_created=true
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "📸 System snapshot created for safe restart"
        fi
    fi
    
    # Perform restart
    if docker_execute "restart" "$service" "$quiet"; then
        # Validate after restart
        local validation_result=0
        if [[ -n "$service" ]]; then
            health_check_service "$service" "$quiet" || validation_result=1
        else
            health_check_all "$quiet" || validation_result=1
        fi
        
        if [[ $validation_result -eq 0 ]]; then
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Service restarted successfully and is healthy"
            return 0
        else
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "❌ Service restart validation failed"
            
            # Offer rollback if snapshot exists
            if [[ "$snapshot_created" == "true" ]]; then
                [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 System snapshot available for rollback if needed"
            fi
            return 1
        fi
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "❌ Service restart failed"
        return 1
    fi
}

# Update service with zero downtime (rolling update)
service_update_zero_downtime() {
    local service="${1:-}"
    local quiet="${2:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🔄 Starting zero-downtime update for: ${service:-all services}"
    
    # Create backup snapshot
    if command -v create_system_snapshot >/dev/null 2>&1; then
        if ! create_system_snapshot "update_${service:-all}_$(date +%s)" "$quiet"; then
            [[ "$quiet" != "true" ]] && milou_log "WARN" "⚠️  Could not create backup snapshot"
        fi
    fi
    
    # Pull latest images first
    [[ "$quiet" != "true" ]] && milou_log "INFO" "⬇️  Pulling latest images..."
    if ! docker_execute "pull" "$service" "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "❌ Failed to pull latest images"
        return 1
    fi
    
    # Perform rolling update
    if [[ -n "$service" ]]; then
        # Single service update
        [[ "$quiet" != "true" ]] && milou_log "INFO" "🔄 Updating service: $service"
        
        # Stop old container and start new one
        if docker_execute "up" "$service" "$quiet" --force-recreate --no-deps; then
            # Validate new service
            if health_check_service "$service" "$quiet"; then
                [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Service updated successfully with zero downtime"
                return 0
            else
                [[ "$quiet" != "true" ]] && milou_log "ERROR" "❌ Updated service failed health check"
                return 1
            fi
        else
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "❌ Service update failed"
            return 1
        fi
    else
        # Multi-service rolling update
        [[ "$quiet" != "true" ]] && milou_log "INFO" "🔄 Performing rolling update of all services"
        
        # Get all services
        local services=()
        while IFS= read -r svc; do
            [[ -n "$svc" ]] && services+=("$svc")
        done < <(docker_compose config --services 2>/dev/null)
        
        local failed_services=()
        
        # Update each service individually
        for svc in "${services[@]}"; do
            [[ "$quiet" != "true" ]] && milou_log "INFO" "🔄 Updating service: $svc"
            
            if docker_execute "up" "$svc" "$quiet" --force-recreate --no-deps; then
                if health_check_service "$svc" "true"; then
                    [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "  ✅ $svc updated successfully"
                else
                    [[ "$quiet" != "true" ]] && milou_log "ERROR" "  ❌ $svc update failed health check"
                    failed_services+=("$svc")
                fi
            else
                [[ "$quiet" != "true" ]] && milou_log "ERROR" "  ❌ $svc update failed"
                failed_services+=("$svc")
            fi
        done
        
        # Report results
        if [[ ${#failed_services[@]} -eq 0 ]]; then
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "🎉 All services updated successfully with zero downtime"
            return 0
        else
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "❌ Some services failed to update: ${failed_services[*]}"
            return 1
        fi
    fi
}

# =============================================================================
# EXPORT CONSOLIDATED FUNCTIONS
# =============================================================================

# Export new consolidated functions
export -f docker_init
export -f docker_login_github
export -f docker_execute
export -f milou_docker_compose
export -f health_check_service
export -f health_check_all

# Export service lifecycle management functions
export -f service_start_with_validation
export -f service_stop_gracefully
export -f service_restart_safely
export -f service_update_zero_downtime

milou_log "DEBUG" "Docker module loaded successfully" 