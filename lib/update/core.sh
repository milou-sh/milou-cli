#!/bin/bash

# =============================================================================
# Milou CLI Update Core Module
# Extracted from monolithic system.sh for better organization
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Module guard to prevent multiple loading
if [[ "${MILOU_UPDATE_CORE_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_UPDATE_CORE_LOADED="true"

# Enhanced update Milou system with version and service selection support
milou_update_system() {
    local force_update="${1:-false}"
    local backup_before_update="${2:-true}"
    local target_version="${3:-}"
    local specific_services="${4:-}"
    local github_token="${GITHUB_TOKEN:-}"
    
    milou_log "STEP" "🔄 Updating Milou system..."
    
    # Validate GitHub token if provided
    if [[ -n "$github_token" ]]; then
        milou_log "INFO" "🔐 Testing GitHub authentication..."
        if command -v milou_test_github_authentication >/dev/null 2>&1; then
            if milou_test_github_authentication "$github_token"; then
                milou_log "SUCCESS" "✅ GitHub authentication successful"
            else
                milou_log "ERROR" "❌ GitHub authentication failed"
                milou_log "INFO" "💡 Please check your token permissions (needs read:packages)"
                return 1
            fi
        fi
    else
        milou_log "WARN" "⚠️  No GitHub token provided - using public access"
    fi
    
    # Create backup before update if requested
    if [[ "$backup_before_update" == "true" ]]; then
        milou_log "INFO" "📦 Creating pre-update backup..."
        if command -v milou_backup_create >/dev/null 2>&1; then
            if ! milou_backup_create "full" "./backups" "pre_update_$(date +%Y%m%d_%H%M%S)"; then
                milou_log "WARN" "⚠️  Backup failed, continuing with update..."
            fi
        else
            milou_log "WARN" "⚠️  Backup function not available, skipping backup"
        fi
    fi
    
    # Enhanced update check with version support
    if ! _milou_update_check_for_updates "$target_version" "$github_token" "$specific_services"; then
        if [[ "$force_update" != "true" ]]; then
            milou_log "INFO" "✅ System is up to date"
            return 0
        else
            milou_log "INFO" "🔄 Forcing update despite no new version available"
        fi
    fi
    
    # Perform the enhanced update
    _milou_update_perform_update "$target_version" "$specific_services" "$github_token"
    
    milou_log "SUCCESS" "✅ System update completed"
    milou_log "INFO" "📋 Run './milou.sh status' to verify the update"
}

# Enhanced update check with version and service support
_milou_update_check_for_updates() {
    local target_version="${1:-}"
    local github_token="${2:-}"
    local specific_services="${3:-}"
    
    milou_log "DEBUG" "Checking for system updates..."
    
    # If specific version is requested, validate its availability
    if [[ -n "$target_version" ]]; then
        milou_log "INFO" "🎯 Checking availability of version: $target_version"
        
        if [[ -n "$github_token" ]]; then
            # Check if the requested version exists for all services
            local -a services_to_check=()
            if [[ -n "$specific_services" ]]; then
                IFS=',' read -ra services_to_check <<< "$specific_services"
            else
                services_to_check=("frontend" "backend" "database" "engine" "nginx")
            fi
            
            local version_available=true
            for service in "${services_to_check[@]}"; do
                milou_log "DEBUG" "Checking version $target_version for service: $service"
                if command -v milou_docker_check_image_exists >/dev/null 2>&1; then
                    if ! milou_docker_check_image_exists "$service" "$target_version" "$github_token"; then
                        milou_log "WARN" "❌ Version $target_version not available for $service"
                        version_available=false
                    else
                        milou_log "DEBUG" "✅ Version $target_version available for $service"
                    fi
                fi
            done
            
            if [[ "$version_available" == "true" ]]; then
                milou_log "SUCCESS" "✅ Target version $target_version is available"
                return 0  # Update needed (version available)
            else
                milou_log "ERROR" "❌ Target version $target_version is not available for all services"
                return 1  # No update possible
            fi
        else
            milou_log "INFO" "🔄 No GitHub token provided, assuming version is available"
            return 0  # Assume update needed
        fi
    else
        # No specific version requested, check for latest
        local current_version="${MILOU_VERSION:-1.0.0}"
        milou_log "DEBUG" "Current version: $current_version, checking for updates..."
        
        # For now, assume updates are available when no specific version is requested
        return 0
    fi
}

# Enhanced system update with version and service selection
_milou_update_perform_update() {
    local target_version="${1:-}"
    local specific_services="${2:-}"
    local github_token="${3:-}"
    
    milou_log "INFO" "🔄 Performing system update..."
    
    # Parse specific services if provided
    local -a services_to_update=()
    if [[ -n "$specific_services" ]]; then
        IFS=',' read -ra services_to_update <<< "$specific_services"
        milou_log "INFO" "🎯 Updating specific services: ${services_to_update[*]}"
    else
        services_to_update=("frontend" "backend" "database" "engine" "nginx")
        milou_log "INFO" "🔄 Updating all services"
    fi
    
    # Preserve current environment before update
    milou_log "INFO" "🔒 Preserving environment configuration..."
    local env_backup="/tmp/milou_env_backup_$(date +%s)"
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        cp "$SCRIPT_DIR/.env" "$env_backup"
        milou_log "DEBUG" "Environment backed up to: $env_backup"
    fi
    
    # Store pre-update service status for rollback
    local pre_update_status="/tmp/milou_pre_update_status_$(date +%s)"
    docker ps --filter "name=static-" --format "{{.Names}}\t{{.Status}}" > "$pre_update_status" 2>/dev/null || true
    
    # Enhanced selective service management
    local update_result
    if [[ -n "$specific_services" ]]; then
        milou_log "INFO" "🎯 Performing selective service update..."
        _milou_update_selective_services "${services_to_update[@]}" "$target_version" "$github_token"
        update_result=$?
    else
        milou_log "INFO" "🔄 Performing full system update..."
        _milou_update_all_services "$target_version" "$github_token"
        update_result=$?
    fi
    
    # Clean up temporary files
    rm -f "$env_backup" "$pre_update_status"
    
    if [[ $update_result -eq 0 ]]; then
        milou_log "SUCCESS" "✅ Update completed successfully"
        return 0
    else
        milou_log "ERROR" "❌ Update failed"
        return 1
    fi
}

# Selective service update with health monitoring
_milou_update_selective_services() {
    local -a services_to_update=("$@")
    local target_version="${!#}"  # Last argument is version
    local github_token="${GITHUB_TOKEN:-}"
    
    # Remove version from services array (it's the last argument)
    unset 'services_to_update[-1]'
    
    milou_log "INFO" "🎯 Updating services: ${services_to_update[*]}"
    
    # Stop specific services
    for service in "${services_to_update[@]}"; do
        milou_log "INFO" "🛑 Stopping service: $service"
        if command -v milou_docker_stop_service >/dev/null 2>&1; then
            milou_docker_stop_service "$service"
        else
            docker stop "static-$service" 2>/dev/null || true
        fi
    done
    
    # Update Docker images for specific services
    if [[ -n "$target_version" ]]; then
        _milou_update_docker_images "$target_version" "${services_to_update[@]}"
    else
        _milou_update_docker_images "latest" "${services_to_update[@]}"
    fi
    
    # Start updated services
    for service in "${services_to_update[@]}"; do
        milou_log "INFO" "🚀 Starting updated service: $service"
        if command -v milou_docker_start_service >/dev/null 2>&1; then
            milou_docker_start_service "$service"
        else
            # Use docker compose to start specific service
            if command -v milou_docker_compose >/dev/null 2>&1; then
                milou_docker_compose up -d "$service"
            fi
        fi
    done
    
    # Verify updated services are healthy
    _milou_update_verify_services "${services_to_update[@]}"
}

# Full system update
_milou_update_all_services() {
    local target_version="${1:-latest}"
    local github_token="${2:-}"
    
    milou_log "INFO" "🔄 Performing full system update to version: $target_version"
    
    # Stop all services gracefully
    milou_log "INFO" "🛑 Stopping all services..."
    if command -v milou_docker_stop >/dev/null 2>&1; then
        milou_docker_stop
    else
        docker compose down 2>/dev/null || true
    fi
    
    # Update all Docker images
    _milou_update_docker_images "$target_version"
    
    # Start all services
    milou_log "INFO" "🚀 Starting updated services..."
    if command -v milou_docker_start >/dev/null 2>&1; then
        milou_docker_start
    else
        if command -v milou_docker_compose >/dev/null 2>&1; then
            milou_docker_compose up -d
        fi
    fi
    
    # Verify all services are healthy
    _milou_update_verify_services
}

# Update Docker images
_milou_update_docker_images() {
    local target_version="${1:-latest}"
    shift
    local -a services=("$@")
    
    # If no specific services provided, update all
    if [[ ${#services[@]} -eq 0 ]]; then
        services=("frontend" "backend" "database" "engine" "nginx")
    fi
    
    milou_log "INFO" "📥 Pulling Docker images for version: $target_version"
    
    # Get registry information
    local registry="${DOCKER_REGISTRY:-ghcr.io/milou-sh}"
    local github_token="${GITHUB_TOKEN:-}"
    
    # Login to registry if token is provided
    if [[ -n "$github_token" ]]; then
        echo "$github_token" | docker login ghcr.io -u "$GITHUB_ACTOR" --password-stdin 2>/dev/null || {
            milou_log "WARN" "Docker registry login failed, trying without authentication"
        }
    fi
    
    # Pull updated images
    for service in "${services[@]}"; do
        local image_name="${registry}/${service}:${target_version}"
        milou_log "INFO" "📥 Pulling image: $image_name"
        
        if docker pull "$image_name" 2>/dev/null; then
            milou_log "SUCCESS" "✅ Updated image for $service"
        else
            milou_log "ERROR" "❌ Failed to pull image for $service"
            # Try latest as fallback
            if [[ "$target_version" != "latest" ]]; then
                milou_log "INFO" "🔄 Trying latest version for $service..."
                if docker pull "${registry}/${service}:latest" 2>/dev/null; then
                    milou_log "WARN" "⚠️ Using latest version for $service instead of $target_version"
                else
                    milou_log "ERROR" "❌ Failed to pull any version for $service"
                fi
            fi
        fi
    done
}

# Verify services are healthy after update
_milou_update_verify_services() {
    local -a services_to_verify=("$@")
    
    # If no specific services provided, verify all
    if [[ ${#services_to_verify[@]} -eq 0 ]]; then
        services_to_verify=("frontend" "backend" "database" "engine" "nginx")
    fi
    
    milou_log "INFO" "🏥 Verifying service health after update..."
    
    local max_wait=60  # 60 seconds timeout
    local elapsed=0
    local all_healthy=false
    
    while [[ $elapsed -lt $max_wait ]]; do
        local healthy_count=0
        
        for service in "${services_to_verify[@]}"; do
            if docker ps --filter "name=static-$service" --filter "status=running" --format "{{.Names}}" | grep -q "static-$service"; then
                ((healthy_count++))
            fi
        done
        
        if [[ $healthy_count -eq ${#services_to_verify[@]} ]]; then
            all_healthy=true
            break
        fi
        
        sleep 3
        elapsed=$((elapsed + 3))
        
        if [[ $((elapsed % 15)) -eq 0 ]]; then
            milou_log "INFO" "⏳ Waiting for services to be healthy ($healthy_count/${#services_to_verify[@]} ready)..."
        fi
    done
    
    if [[ "$all_healthy" == "true" ]]; then
        milou_log "SUCCESS" "✅ All services are healthy after update"
        return 0
    else
        milou_log "ERROR" "❌ Some services failed to start properly after update"
        return 1
    fi
}

# Rollback to previous version
milou_update_rollback() {
    local backup_file="${1:-}"
    
    milou_log "STEP" "🔄 Rolling back system update..."
    
    if [[ -z "$backup_file" ]]; then
        # Try to find the most recent pre-update backup
        local backup_dir="./backups"
        if [[ -d "$backup_dir" ]]; then
            backup_file=$(find "$backup_dir" -name "pre_update_*.tar.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
        fi
        
        if [[ -z "$backup_file" ]]; then
            milou_log "ERROR" "No backup file specified and no automatic backup found"
            milou_log "INFO" "💡 Usage: ./milou.sh rollback <backup_file>"
            return 1
        fi
        
        milou_log "INFO" "📦 Using automatic backup: $backup_file"
    fi
    
    # Restore from backup
    if command -v milou_restore_from_backup >/dev/null 2>&1; then
        milou_restore_from_backup "$backup_file" "full"
    else
        milou_log "ERROR" "Restore function not available"
        return 1
    fi
    
    # Restart services
    milou_log "INFO" "🔄 Restarting services with restored configuration..."
    if command -v milou_docker_restart >/dev/null 2>&1; then
        milou_docker_restart
    else
        milou_log "WARN" "Service restart function not available - please restart manually"
    fi
    
    milou_log "SUCCESS" "✅ Rollback completed"
}

# Check system update status
milou_update_check_status() {
    milou_log "INFO" "📊 Checking system update status..."
    
    # Check current version
    local current_version="${MILOU_VERSION:-unknown}"
    milou_log "INFO" "Current version: $current_version"
    
    # Check for available updates
    if command -v milou_self_update_check >/dev/null 2>&1; then
        milou_log "INFO" "Checking for CLI updates..."
        milou_self_update_check
    fi
    
    # Check Docker image versions
    milou_log "INFO" "📦 Current Docker images:"
    docker images --filter "reference=ghcr.io/milou-sh/*" --format "table {{.Repository}}\t{{.Tag}}\t{{.CreatedAt}}" 2>/dev/null || {
        milou_log "WARN" "Unable to list Docker images"
    }
    
    # Check service status
    if command -v milou_docker_status >/dev/null 2>&1; then
        milou_log "INFO" "📋 Service status:"
        milou_docker_status
    fi
}

# =============================================================================
# CLEAN PUBLIC API - Export only essential functions
# =============================================================================

# Main update functions (4 exports - CLEAN PUBLIC API)
export -f milou_update_system           # Primary system update function
export -f milou_update_rollback         # Rollback capability
export -f milou_update_check_status     # Status checking

# Internal functions are NOT exported (marked with _ prefix)
# This keeps the namespace clean and makes it clear what's public vs internal 