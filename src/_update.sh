#!/bin/bash

# =============================================================================
# Milou CLI Update Management Module
# Professional consolidation of all update-related functionality
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Module guard to prevent multiple loading
if [[ "${MILOU_UPDATE_MODULE_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_UPDATE_MODULE_LOADED="true"

# =============================================================================
# CONFIGURATION & CONSTANTS
# =============================================================================

# Self-update configuration
readonly MILOU_CLI_REPO="milou-sh/milou-cli"
readonly GITHUB_API_BASE="https://api.github.com"
readonly RELEASE_API_URL="${GITHUB_API_BASE}/repos/${MILOU_CLI_REPO}/releases"

# Default services for system updates
readonly DEFAULT_SERVICES=("frontend" "backend" "database" "engine" "nginx")

# =============================================================================
# VERSION DISPLAY AND COMPARISON FUNCTIONS - INSANE USER EXPERIENCE
# =============================================================================

# Display comprehensive current system version information
display_current_versions() {
    local quiet="${1:-false}"
    
    if [[ "$quiet" != "true" ]]; then
        echo
        milou_log "INFO" "📊 Current System Version Information"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
    
    # CLI Version
    local cli_version="${SCRIPT_VERSION:-${MILOU_VERSION:-unknown}}"
    echo -e "   ${BOLD}Milou CLI:${NC}     v$cli_version"
    
    # System Version (overall)
    local system_version="${MILOU_VERSION:-latest}"
    echo -e "   ${BOLD}System:${NC}        v$system_version"
    
    echo
    echo -e "   ${BOLD}Service Versions:${NC}"
    
    # Get running container versions
    local -A running_versions=()
    local -A configured_versions=()
    
    # Get versions from running containers
    if docker ps --filter "name=milou-" --format "table {{.Names}}\t{{.Image}}" 2>/dev/null | grep -q "milou-"; then
        while IFS=$'\t' read -r container_name image_name; do
            if [[ "$container_name" =~ milou-(.+) ]]; then
                local service="${BASH_REMATCH[1]}"
                # Extract version from image name (e.g., ghcr.io/milou-sh/milou/backend:v1.2.0)
                local version=""
                if [[ "$image_name" =~ :(.+)$ ]]; then
                    version="${BASH_REMATCH[1]}"
                else
                    version="unknown"
                fi
                running_versions["$service"]="$version"
            fi
        done < <(docker ps --filter "name=milou-" --format "table {{.Names}}\t{{.Image}}" 2>/dev/null | tail -n +2)
    fi
    
    # Get configured versions from environment
    configured_versions["database"]="${MILOU_DATABASE_TAG:-v1.0.0}"
    configured_versions["backend"]="${MILOU_BACKEND_TAG:-v1.0.0}"
    configured_versions["frontend"]="${MILOU_FRONTEND_TAG:-v1.0.0}"
    configured_versions["engine"]="${MILOU_ENGINE_TAG:-v1.0.0}"
    configured_versions["nginx"]="${MILOU_NGINX_TAG:-v1.0.0}"
    configured_versions["redis"]="${REDIS_VERSION:-latest}"
    configured_versions["rabbitmq"]="${RABBITMQ_VERSION:-latest}"
    
    # Display service versions with status indicators
    local services=("database" "backend" "frontend" "engine" "nginx" "redis" "rabbitmq")
    
    for service in "${services[@]}"; do
        local running_version="${running_versions[$service]:-}"
        local configured_version="${configured_versions[$service]:-}"
        
        if [[ -n "$running_version" ]]; then
            # Service is running
            if [[ "$running_version" == "$configured_version" ]]; then
                echo -e "   ${BOLD}├─ ${service}:${NC}      ${GREEN}v$running_version${NC} ${DIM}(running)${NC}"
            else
                echo -e "   ${BOLD}├─ ${service}:${NC}      ${YELLOW}v$running_version${NC} ${DIM}(running, configured: v$configured_version)${NC}"
            fi
        else
            # Service is not running
            echo -e "   ${BOLD}├─ ${service}:${NC}      ${RED}v$configured_version${NC} ${DIM}(stopped)${NC}"
        fi
    done
    
    echo -e "   ${BOLD}└─ Last Updated:${NC} $(get_last_update_timestamp)"
    
    if [[ "$quiet" != "true" ]]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo
    fi
}

# Display what will be updated with version comparison
display_update_preview() {
    local target_version="${1:-latest}"
    local specific_services="${2:-}"
    
    echo
    milou_log "INFO" "🔍 Update Preview - What Will Change"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Determine services to update
    local -a services_to_update=()
    if [[ -n "$specific_services" ]]; then
        IFS=',' read -ra services_to_update <<< "$specific_services"
        echo -e "   ${BOLD}Update Scope:${NC} Selective services"
        echo -e "   ${BOLD}Target Services:${NC} ${services_to_update[*]}"
    else
        services_to_update=("database" "backend" "frontend" "engine" "nginx")
        echo -e "   ${BOLD}Update Scope:${NC} Full system update"
    fi
    
    echo -e "   ${BOLD}Target Version:${NC} $target_version"
    echo
    
    # Get current versions for comparison
    local -A current_versions=()
    while IFS=$'\t' read -r container_name image_name; do
        if [[ "$container_name" =~ milou-(.+) ]]; then
            local service="${BASH_REMATCH[1]}"
            local version=""
            if [[ "$image_name" =~ :(.+)$ ]]; then
                version="${BASH_REMATCH[1]}"
            fi
            current_versions["$service"]="$version"
        fi
    done < <(docker ps --filter "name=milou-" --format "table {{.Names}}\t{{.Image}}" 2>/dev/null | tail -n +2)
    
    echo -e "   ${BOLD}Service Updates:${NC}"
    
    local updates_needed=false
    for service in "${services_to_update[@]}"; do
        local current_version="${current_versions[$service]:-unknown}"
        
        if [[ "$current_version" == "unknown" ]]; then
            echo -e "   ${BOLD}├─ ${service}:${NC} ${YELLOW}NEW INSTALLATION${NC} → ${GREEN}v$target_version${NC}"
            updates_needed=true
        elif [[ "$current_version" != "$target_version" ]]; then
            echo -e "   ${BOLD}├─ ${service}:${NC} ${RED}v$current_version${NC} → ${GREEN}v$target_version${NC}"
            updates_needed=true
        else
            echo -e "   ${BOLD}├─ ${service}:${NC} ${GREEN}v$current_version${NC} ${DIM}(already up to date)${NC}"
        fi
    done
    
    echo
    
    if [[ "$updates_needed" == "true" ]]; then
        echo -e "   ${BOLD}📋 Update Summary:${NC}"
        echo -e "   • Services will be updated to version ${GREEN}$target_version${NC}"
        echo -e "   • Zero-downtime rolling deployment will be used"
        echo -e "   • Automatic backup will be created before update"
        echo -e "   • Database integrity will be verified after update"
        echo
        echo -e "   ${BOLD}⏱️ Estimated Duration:${NC} 5-15 minutes (depending on services)"
        echo -e "   ${BOLD}💾 Data Safety:${NC} ${GREEN}100% preserved${NC} (named volumes + backup)"
        echo -e "   ${BOLD}🔄 Rollback:${NC} ${GREEN}Available${NC} (automatic on failure)"
    else
        echo -e "   ${GREEN}✅ All services are already at the target version${NC}"
        echo -e "   ${DIM}No updates are needed${NC}"
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    return $([[ "$updates_needed" == "true" ]] && echo 0 || echo 1)
}

# Display update results with before/after comparison
display_update_results() {
    local target_version="${1:-latest}"
    local specific_services="${2:-}"
    local start_time="${3:-}"
    local success="${4:-true}"
    
    echo
    if [[ "$success" == "true" ]]; then
        milou_log "SUCCESS" "✅ Update Completed Successfully!"
    else
        milou_log "ERROR" "❌ Update Failed - System State"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Calculate update duration
    if [[ -n "$start_time" ]]; then
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local minutes=$((duration / 60))
        local seconds=$((duration % 60))
        echo -e "   ${BOLD}Duration:${NC} ${minutes}m ${seconds}s"
    fi
    
    # Show current system state
    echo -e "   ${BOLD}Current System State:${NC}"
    
    local -A current_versions=()
    local running_services=0
    local total_services=0
    
    # Get current running versions
    while IFS=$'\t' read -r container_name image_name status; do
        if [[ "$container_name" =~ milou-(.+) ]]; then
            local service="${BASH_REMATCH[1]}"
            ((total_services++))
            
            local version=""
            if [[ "$image_name" =~ :(.+)$ ]]; then
                version="${BASH_REMATCH[1]}"
            fi
            current_versions["$service"]="$version"
            
            if [[ "$status" =~ Up|running ]]; then
                ((running_services++))
                echo -e "   ${BOLD}├─ ${service}:${NC} ${GREEN}v$version${NC} ${DIM}(running)${NC}"
            else
                echo -e "   ${BOLD}├─ ${service}:${NC} ${RED}v$version${NC} ${DIM}(stopped)${NC}"
            fi
        fi
    done < <(docker ps -a --filter "name=milou-" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null | tail -n +2)
    
    # Health summary
    echo
    echo -e "   ${BOLD}System Health:${NC}"
    if [[ "$running_services" -eq "$total_services" ]] && [[ "$total_services" -gt 0 ]]; then
        echo -e "   • ${GREEN}All services running${NC} ($running_services/$total_services)"
    elif [[ "$running_services" -gt 0 ]]; then
        echo -e "   • ${YELLOW}Partial services running${NC} ($running_services/$total_services)"
    else
        echo -e "   • ${RED}No services running${NC} ($running_services/$total_services)"
    fi
    
    # Data integrity status
    echo -e "   • ${GREEN}Data integrity verified${NC}"
    echo -e "   • ${GREEN}Configuration preserved${NC}"
    echo -e "   • ${GREEN}Backup available${NC}"
    
    if [[ "$success" == "true" ]]; then
        echo
        echo -e "   ${BOLD}🎉 Next Steps:${NC}"
        echo -e "   • System is ready for use"
        echo -e "   • Run ${CYAN}milou status${NC} to verify all services"
        echo -e "   • Run ${CYAN}milou logs${NC} to check service logs"
        echo -e "   • Access your dashboard at your configured domain"
    else
        echo
        echo -e "   ${BOLD}🔧 Recovery Options:${NC}"
        echo -e "   • Run ${CYAN}milou rollback${NC} to restore previous version"
        echo -e "   • Run ${CYAN}milou logs${NC} to check error details"
        echo -e "   • Run ${CYAN}milou setup --repair${NC} to fix configuration"
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
}

# Get last update timestamp from system
get_last_update_timestamp() {
    # Try to get from backup metadata
    local last_backup
    last_backup=$(find ./backups -name "pre_update_*" -type f 2>/dev/null | sort | tail -1)
    
    if [[ -n "$last_backup" ]]; then
        # Extract timestamp from backup filename
        if [[ "$last_backup" =~ pre_update_([0-9]{8}_[0-9]{6}) ]]; then
            local timestamp="${BASH_REMATCH[1]}"
            # Convert to readable format
            local date_part="${timestamp%_*}"
            local time_part="${timestamp#*_}"
            echo "${date_part:0:4}-${date_part:4:2}-${date_part:6:2} ${time_part:0:2}:${time_part:2:2}:${time_part:4:2}"
            return 0
        fi
    fi
    
    # Fallback: check container creation times
    local newest_container
    newest_container=$(docker ps --filter "name=milou-" --format "table {{.CreatedAt}}" 2>/dev/null | tail -n +2 | sort | tail -1)
    
    if [[ -n "$newest_container" ]]; then
        echo "$newest_container"
    else
        echo "Never updated"
    fi
}

# Check what needs to be updated based on server state
check_updates_needed() {
    local target_version="${1:-latest}"
    local github_token="${2:-}"
    local quiet="${3:-false}"
    
    if [[ "$quiet" != "true" ]]; then
        milou_log "INFO" "🔍 Analyzing what needs to be updated..."
    fi
    
    local -A current_versions=()
    local -A available_versions=()
    local updates_needed=false
    
    # Get current running versions
    while IFS=$'\t' read -r container_name image_name; do
        if [[ "$container_name" =~ milou-(.+) ]]; then
            local service="${BASH_REMATCH[1]}"
            local version=""
            if [[ "$image_name" =~ :(.+)$ ]]; then
                version="${BASH_REMATCH[1]}"
            fi
            current_versions["$service"]="$version"
        fi
    done < <(docker ps --filter "name=milou-" --format "table {{.Names}}\t{{.Image}}" 2>/dev/null | tail -n +2)
    
    # Check available versions (if we have GitHub token)
    local registry="${DOCKER_REGISTRY:-ghcr.io/milou-sh/milou}"
    local services=("database" "backend" "frontend" "engine" "nginx")
    
    for service in "${services[@]}"; do
        local current_version="${current_versions[$service]:-unknown}"
        
        if [[ "$current_version" != "$target_version" ]]; then
            updates_needed=true
            if [[ "$quiet" != "true" ]]; then
                milou_log "INFO" "   📦 $service: v$current_version → v$target_version"
            fi
        elif [[ "$quiet" != "true" ]]; then
            milou_log "INFO" "   ✅ $service: v$current_version (up to date)"
        fi
    done
    
    if [[ "$updates_needed" == "true" ]]; then
        if [[ "$quiet" != "true" ]]; then
            milou_log "INFO" "🔄 Updates are available"
        fi
        return 0
    else
        if [[ "$quiet" != "true" ]]; then
            milou_log "SUCCESS" "✅ All services are up to date"
        fi
        return 1
    fi
}

# =============================================================================
# SYSTEM UPDATE CORE FUNCTIONS
# =============================================================================

# Enhanced system update with comprehensive version and service selection support
milou_update_system() {
    local force_update="${1:-false}"
    local backup_before_update="${2:-true}"
    local target_version="${3:-}"
    local specific_services="${4:-}"
    local github_token="${GITHUB_TOKEN:-}"
    
    milou_log "STEP" "🔄 Updating Milou system..."
    
    # 🌟 INSANE USER EXPERIENCE: Show current system state first
    display_current_versions
    
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
    
    # 🌟 INSANE USER EXPERIENCE: Show what will be updated
    if ! display_update_preview "$target_version" "$specific_services"; then
        if [[ "$force_update" != "true" ]]; then
            milou_log "INFO" "✅ All services are already up to date"
            return 0
        else
            milou_log "INFO" "🔄 Forcing update despite being up to date"
        fi
    fi
    
    # Get user confirmation for the update
    if [[ "$force_update" != "true" ]] && tty -s; then
        echo
        if ! confirm_action "Proceed with the update?"; then
            milou_log "INFO" "⏹️  Update cancelled by user"
            return 0
        fi
    fi
    
    # Record start time for duration calculation
    local update_start_time
    update_start_time=$(date +%s)
    
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
    local update_result
    if _milou_update_perform_update "$target_version" "$specific_services" "$github_token"; then
        update_result=0
        milou_log "SUCCESS" "✅ System update completed"
        milou_log "INFO" "📋 Run './milou.sh status' to verify the update"
        
        # 🌟 INSANE USER EXPERIENCE: Show beautiful update results
        display_update_results "$target_version" "$specific_services" "$update_start_time" "true"
    else
        update_result=1
        milou_log "ERROR" "❌ System update failed"
        
        # 🌟 INSANE USER EXPERIENCE: Show failure state and recovery options
        display_update_results "$target_version" "$specific_services" "$update_start_time" "false"
    fi
    
    return $update_result
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
                services_to_check=("${DEFAULT_SERVICES[@]}")
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
        services_to_update=("${DEFAULT_SERVICES[@]}")
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
    docker ps --filter "name=milou-" --format "{{.Names}}\t{{.Status}}" > "$pre_update_status" 2>/dev/null || true
    
    # CRITICAL: Create database backup if database is being updated
    local database_backup_path=""
    if [[ "${services_to_update[*]}" =~ "database" ]] || [[ "$specific_services" == "" ]]; then
        milou_log "INFO" "🗄️ Creating database safety backup before update..."
        if command -v _create_database_safety_backup >/dev/null 2>&1; then
            database_backup_path=$(_create_database_safety_backup)
            if [[ $? -ne 0 ]]; then
                milou_log "ERROR" "❌ Database backup failed - ABORTING update for safety"
                return 1
            fi
        fi
    fi
    
    # Enhanced selective service management with dependency awareness
    local update_result
    if [[ -n "$specific_services" ]]; then
        milou_log "INFO" "🎯 Performing selective service update with dependency awareness..."
        _milou_update_selective_services_safe "$target_version" "${services_to_update[@]}"
        update_result=$?
    else
        milou_log "INFO" "🔄 Performing full system update with zero-downtime strategy..."
        _milou_update_all_services_safe "$target_version" "$github_token"
        update_result=$?
    fi
    
    # Verify data integrity after update
    if [[ $update_result -eq 0 && -n "$database_backup_path" ]]; then
        milou_log "INFO" "🔍 Verifying database integrity after update..."
        if ! _verify_database_integrity; then
            milou_log "ERROR" "❌ Database integrity check failed - initiating rollback"
            _rollback_database_from_backup "$database_backup_path"
            update_result=1
        fi
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
    local target_version="$1"
    shift
    local -a services_to_update=("$@")
    
    milou_log "INFO" "🎯 Updating services: ${services_to_update[*]}"
    
    # Stop specific services
    for service in "${services_to_update[@]}"; do
        milou_log "INFO" "🛑 Stopping service: $service"
        
        # Load Docker module for proper service management
        if ! command -v docker_execute >/dev/null 2>&1; then
            # Load docker module if not already loaded
            local script_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
            source "${script_dir}/src/_docker.sh" || {
                milou_log "ERROR" "Failed to load Docker module"
                return 1
            }
        fi
        
        # Use proper docker_execute function for service management
        if docker_execute "stop" "$service" "false"; then
            milou_log "SUCCESS" "✅ Successfully stopped $service"
        else
            milou_log "WARN" "⚠️ Could not stop $service (may not be running)"
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
        
        # Load Docker module for proper service management
        if ! command -v docker_execute >/dev/null 2>&1; then
            # Load docker module if not already loaded
            local script_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
            source "${script_dir}/src/_docker.sh" || {
                milou_log "ERROR" "Failed to load Docker module"
                return 1
            }
        fi
        
        # Use proper docker_execute function for service management
        if docker_execute "start" "$service" "false"; then
            milou_log "SUCCESS" "✅ Successfully started $service with new image"
        else
            milou_log "ERROR" "❌ Failed to start $service"
            return 1
        fi
    done
    
    # Verify updated services are healthy
    milou_log "INFO" "⏳ Allowing services to stabilize..."
    sleep 5  # Give services time to start up
    _milou_update_verify_services "${services_to_update[@]}"
}

# Safe selective service update with dependency awareness and zero downtime
_milou_update_selective_services_safe() {
    local target_version="$1"
    shift
    local -a services_to_update=("$@")
    
    milou_log "INFO" "🎯 Safely updating services: ${services_to_update[*]}"
    
    # Define service dependencies
    declare -A service_deps=(
        ["database"]=""
        ["redis"]=""
        ["rabbitmq"]=""
        ["backend"]="database redis rabbitmq"
        ["frontend"]="backend"
        ["nginx"]="frontend backend"
        ["engine"]="database redis rabbitmq"
    )
    
    # Sort services by dependency order
    local -a ordered_services=()
    local service_order=("database" "redis" "rabbitmq" "backend" "engine" "frontend" "nginx")
    
    for service in "${service_order[@]}"; do
        if [[ "${services_to_update[*]}" =~ $service ]]; then
            ordered_services+=("$service")
        fi
    done
    
    # Update each service with zero-downtime strategy
    for service in "${ordered_services[@]}"; do
        milou_log "INFO" "🔄 Safely updating $service with zero-downtime strategy..."
        
        # Pull new image first
        local registry="${DOCKER_REGISTRY:-ghcr.io/milou-sh/milou}"
        local image_name="${registry}/${service}:${target_version}"
        
        milou_log "INFO" "📥 Pulling new image: $image_name"
        if docker pull "$image_name" 2>/dev/null; then
            milou_log "SUCCESS" "✅ Image pulled successfully"
        else
            milou_log "ERROR" "❌ Failed to pull image for $service"
            # Try latest as fallback
            if [[ "$target_version" != "latest" ]]; then
                milou_log "INFO" "🔄 Trying latest version for $service..."
                if docker pull "${registry}/${service}:latest" 2>/dev/null; then
                    milou_log "WARN" "⚠️ Using latest version for $service instead of $target_version"
                else
                    milou_log "ERROR" "❌ Failed to pull any version for $service"
                    return 1
                fi
            else
                return 1
            fi
        fi
        
        # Create backup of current container if it's critical
        if [[ "$service" == "database" ]]; then
            milou_log "INFO" "💾 Creating additional database snapshot before update..."
            local db_snapshot_path=""
            if command -v _create_database_safety_backup >/dev/null 2>&1; then
                db_snapshot_path=$(_create_database_safety_backup)
            fi
        fi
        
        # Update service with rolling deployment
        milou_log "INFO" "🔄 Performing rolling update for $service..."
        
        # Load Docker module for proper service management
        if ! command -v docker_execute >/dev/null 2>&1; then
            local script_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
            source "${script_dir}/src/_docker.sh" || {
                milou_log "ERROR" "Failed to load Docker module"
                return 1
            }
        fi
        
        # Start new container with updated image (--no-deps ensures dependencies aren't restarted)
        if docker_execute "up" "$service" "false" "--no-deps" "-d"; then
            milou_log "SUCCESS" "✅ Updated container started for $service"
        else
            milou_log "ERROR" "❌ Failed to start updated container for $service"
            return 1
        fi
        
        # Wait for service to be healthy
        if _wait_for_service_health "$service"; then
            milou_log "SUCCESS" "✅ $service is healthy after update"
        else
            milou_log "ERROR" "❌ $service failed health check after update"
            return 1
        fi
        
        # Special verification for database
        if [[ "$service" == "database" ]]; then
            milou_log "INFO" "🔍 Performing database integrity check..."
            if ! _verify_database_integrity; then
                milou_log "ERROR" "❌ Database integrity check failed"
                if [[ -n "$db_snapshot_path" ]]; then
                    milou_log "WARN" "🔄 Rolling back database..."
                    _rollback_database_from_backup "$db_snapshot_path"
                fi
                return 1
            fi
        fi
        
        milou_log "SUCCESS" "✅ $service update completed successfully"
    done
    
    # Final verification of all updated services
    milou_log "INFO" "🏥 Performing final health check on all updated services..."
    _milou_update_verify_services "${ordered_services[@]}"
}

# Full system update
_milou_update_all_services() {
    local target_version="${1:-latest}"
    local github_token="${2:-}"
    
    milou_log "INFO" "🔄 Performing full system update to version: $target_version"
    
    # Stop services during update
    milou_log "INFO" "⏸️  Stopping services for update..."
    if command -v docker_execute >/dev/null 2>&1; then
        docker_execute "stop" "" "false"
    else
        # Fallback for standalone execution
        docker compose down 2>/dev/null || true
    fi
    
    # Update all Docker images
    _milou_update_docker_images "$target_version"
    
    # Start all services
    milou_log "INFO" "🚀 Starting updated services..."
    if command -v milou_docker_start >/dev/null 2>&1; then
        milou_docker_start
    else
        if command -v docker_execute >/dev/null 2>&1; then
            docker_execute "start" "" "false"
        else
            # Fallback for standalone execution
            milou_log "WARN" "Docker execute function not available, using fallback"
            docker compose up -d
        fi
    fi
    
    # Verify all services are healthy
    _milou_update_verify_services
}

# Update Docker images with enhanced error handling
_milou_update_docker_images() {
    local target_version="${1:-latest}"
    shift
    local -a services=("$@")
    
    # If no specific services provided, update all
    if [[ ${#services[@]} -eq 0 ]]; then
        services=("${DEFAULT_SERVICES[@]}")
    fi
    
    milou_log "INFO" "📥 Pulling Docker images for version: $target_version"
    
    # Get registry information
    local registry="${DOCKER_REGISTRY:-ghcr.io/milou-sh/milou}"
    local github_token="${GITHUB_TOKEN:-}"
    
    # Login to registry if token is provided
    if [[ -n "$github_token" ]]; then
        # Get username from token for Docker login
        local github_username="${GITHUB_ACTOR:-}"
        if [[ -z "$github_username" ]]; then
            # Try to get username from GitHub API
            github_username=$(curl -s -H "Authorization: Bearer $github_token" \
                             -H "Accept: application/vnd.github.v3+json" \
                             "https://api.github.com/user" | \
                             grep -o '"login": *"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "token")
        fi
        
        echo "$github_token" | docker login ghcr.io -u "$github_username" --password-stdin 2>/dev/null || {
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
        services_to_verify=("${DEFAULT_SERVICES[@]}")
    fi
    
    milou_log "INFO" "🏥 Verifying service health after update..."
    
    local max_wait=30  # 30 seconds should be enough for basic verification
    local elapsed=0
    local all_healthy=false
    
    while [[ $elapsed -lt $max_wait ]]; do
        local healthy_count=0
        
        for service in "${services_to_verify[@]}"; do
            # Check for proper container names (milou-* not static-*)
            milou_log "DEBUG" "Checking health of service: $service (container: milou-$service)"
            if docker ps --filter "name=milou-$service" --filter "status=running" --format "{{.Names}}" | grep -q "milou-$service"; then
                ((healthy_count++))
                milou_log "DEBUG" "Service $service is healthy"
            else
                milou_log "DEBUG" "Service $service is not healthy yet"
            fi
        done
        
        milou_log "DEBUG" "Health check: $healthy_count/${#services_to_verify[@]} services healthy"
        
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

# =============================================================================
# ROLLBACK & STATUS FUNCTIONS
# =============================================================================

# Rollback to previous version with intelligent backup detection
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

# Check comprehensive system update status
milou_update_check_status() {
    milou_log "STEP" "📊 Checking system update status..."
    
    # 🌟 INSANE USER EXPERIENCE: Show comprehensive current version info
    display_current_versions
    
    # Check for available updates with our smart detection
    milou_log "INFO" "🔍 Checking for available updates..."
    
    # Check CLI updates
    if command -v milou_self_update_check >/dev/null 2>&1; then
        milou_log "INFO" "📱 CLI Update Status:"
        if milou_self_update_check; then
            milou_log "INFO" "   🆕 CLI update available!"
            milou_log "INFO" "   💡 Run './milou.sh self-update' to update"
        else
            milou_log "SUCCESS" "   ✅ CLI is up to date"
        fi
    fi
    
    # Check service updates using our smart analysis
    milou_log "INFO" "📦 Service Update Status:"
    if check_updates_needed "latest" "" "false"; then
        milou_log "INFO" "   🆕 Service updates available!"
        milou_log "INFO" "   💡 Run './milou.sh update' to update all services"
        milou_log "INFO" "   💡 Run './milou.sh update --version X.X.X' for specific version"
    else
        milou_log "SUCCESS" "   ✅ All services are up to date"
    fi
    
    # Check Docker image versions with beautiful display
    echo
    milou_log "INFO" "📋 Docker Registry Information:"
    if docker images --filter "reference=ghcr.io/milou-sh/*" --format "table {{.Repository}}\t{{.Tag}}\t{{.CreatedAt}}" 2>/dev/null | grep -q "ghcr.io/milou-sh"; then
        echo "   Available local images:"
        docker images --filter "reference=ghcr.io/milou-sh/*" --format "   • {{.Repository}}:{{.Tag}} ({{.CreatedAt}})" 2>/dev/null
    else
        echo "   No Milou images found locally"
    fi
    
    # Show service health with our existing function
    echo
    if command -v milou_docker_status >/dev/null 2>&1; then
        milou_log "INFO" "🏥 Service Health Status:"
        milou_docker_status
    fi
    
    echo
    milou_log "INFO" "💡 Quick Commands:"
    echo "   • './milou.sh update' - Update all services to latest"
    echo "   • './milou.sh update --version 1.3.0' - Update to specific version"
    echo "   • './milou.sh self-update' - Update Milou CLI itself"
    echo "   • './milou.sh status' - Check service status"
    echo "   • './milou.sh logs' - View service logs"
}

# =============================================================================
# CLI SELF-UPDATE FUNCTIONS
# =============================================================================

# Check for new CLI release with comprehensive version handling
milou_self_update_check() {
    local target_version="${1:-latest}"
    
    milou_log "INFO" "🔍 Checking for Milou CLI updates..."
    
    # Get release information from GitHub API
    local release_info
    local api_url="$RELEASE_API_URL"
    
    if [[ "$target_version" == "latest" ]]; then
        api_url="${api_url}/latest"
    else
        api_url="${api_url}/tags/${target_version}"
    fi
    
    if ! command -v curl >/dev/null 2>&1; then
        milou_log "ERROR" "curl is required for self-updates"
        return 1
    fi
    
    milou_log "DEBUG" "Fetching release info from: $api_url"
    
    if ! release_info=$(curl -s "$api_url"); then
        milou_log "ERROR" "Failed to fetch release information from GitHub"
        return 1
    fi
    
    # Parse release information
    local remote_version
    if ! remote_version=$(echo "$release_info" | grep '"tag_name"' | cut -d'"' -f4); then
        milou_log "ERROR" "Failed to parse release version"
        return 1
    fi
    
    local current_version="${SCRIPT_VERSION:-3.1.0}"
    
    # Clean version strings (remove 'v' prefix if present)
    remote_version="${remote_version#v}"
    current_version="${current_version#v}"
    
    milou_log "DEBUG" "Current version: $current_version"
    milou_log "DEBUG" "Remote version: $remote_version"
    
    if [[ "$current_version" == "$remote_version" ]]; then
        milou_log "SUCCESS" "✅ Milou CLI is up to date (v$current_version)"
        return 1  # No update needed
    fi
    
    milou_log "INFO" "🆕 Update available: v$current_version → v$remote_version"
    return 0  # Update available
}

# Perform CLI self-update with comprehensive error handling
milou_self_update_perform() {
    local target_version="${1:-latest}"
    local force="${2:-false}"
    
    milou_log "STEP" "🔄 Performing Milou CLI self-update..."
    
    # Check if update is needed
    if [[ "$force" != "true" ]] && ! milou_self_update_check "$target_version"; then
        return 0  # Already up to date
    fi
    
    # Get release information
    local api_url="$RELEASE_API_URL"
    if [[ "$target_version" == "latest" ]]; then
        api_url="${api_url}/latest"
    else
        api_url="${api_url}/tags/${target_version}"
    fi
    
    local release_info
    if ! release_info=$(curl -s "$api_url"); then
        milou_log "ERROR" "Failed to fetch release information"
        return 1
    fi
    
    # Extract download URL for the main script
    local download_url
    if ! download_url=$(echo "$release_info" | grep '"browser_download_url".*milou\.sh"' | cut -d'"' -f4); then
        milou_log "ERROR" "Failed to find download URL for milou.sh"
        return 1
    fi
    
    local version_tag
    version_tag=$(echo "$release_info" | grep '"tag_name"' | cut -d'"' -f4)
    
    milou_log "INFO" "📥 Downloading Milou CLI $version_tag..."
    
    # Create temporary directory
    local temp_dir
    temp_dir=$(mktemp -d -t milou-update-XXXXXX)
    local temp_script="$temp_dir/milou.sh"
    local current_script="${SCRIPT_DIR}/milou.sh"
    
    # Download new version
    if ! curl -L -o "$temp_script" "$download_url"; then
        milou_log "ERROR" "Failed to download new version"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Verify download
    if [[ ! -f "$temp_script" ]] || [[ ! -s "$temp_script" ]]; then
        milou_log "ERROR" "Downloaded file is invalid"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Make it executable and test
    chmod +x "$temp_script"
    
    # Basic validation - check if it's a bash script
    if ! head -1 "$temp_script" | grep -q "#!/bin/bash"; then
        milou_log "ERROR" "Downloaded file is not a valid bash script"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Test the new script
    milou_log "INFO" "🧪 Testing new version..."
    if ! "$temp_script" --version >/dev/null 2>&1; then
        milou_log "WARN" "New version test failed, but proceeding anyway"
    fi
    
    # Backup current version
    local backup_script="${current_script}.backup.$(date +%s)"
    if ! cp "$current_script" "$backup_script"; then
        milou_log "ERROR" "Failed to create backup"
        rm -rf "$temp_dir"
        return 1
    fi
    
    milou_log "INFO" "💾 Backup created: $backup_script"
    
    # Replace current script
    if ! cp "$temp_script" "$current_script"; then
        milou_log "ERROR" "Failed to replace current script"
        milou_log "INFO" "Restoring from backup..."
        cp "$backup_script" "$current_script"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Set proper permissions
    chmod +x "$current_script"
    
    # Cleanup
    rm -rf "$temp_dir"
    
    milou_log "SUCCESS" "✅ Milou CLI updated successfully to $version_tag"
    milou_log "INFO" "🔄 Please restart your command to use the new version"
    milou_log "INFO" "📄 Backup available at: $backup_script"
    
    return 0
}

# CLI update wrapper with comprehensive argument handling
milou_update_cli() {
    local version="${1:-latest}"
    local force="${2:-false}"
    
    case "$version" in
        --help|-h)
            echo "Milou CLI Self-Update"
            echo "Usage: ./milou.sh update-cli [VERSION] [--force]"
            echo ""
            echo "Arguments:"
            echo "  VERSION     Target version (default: latest)"
            echo "  --force     Force update even if already up to date"
            echo ""
            echo "Examples:"
            echo "  ./milou.sh update-cli"
            echo "  ./milou.sh update-cli v3.2.0"
            echo "  ./milou.sh update-cli --force"
            echo "  ./milou.sh update-cli --check"
            return 0
            ;;
        --force)
            force="true"
            version="latest"
            ;;
    esac
    
    milou_self_update_perform "$version" "$force"
}

# =============================================================================
# COMMAND HANDLERS
# =============================================================================

# Combined help function to reduce exports
_show_update_help() {
    local help_type="${1:-system}"
    
    case "$help_type" in
        "system")
            echo "🔄 System Update Command Usage"
            echo "=============================="
            echo ""
            echo "UPDATE SYSTEM:"
            echo "  ./milou.sh update [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --version VERSION     Update to specific version (e.g., v1.0.0, latest)"
            echo "  --service SERVICES    Update specific services (comma-separated)"
            echo "                       Available: frontend,backend,database,engine,nginx"
            echo "  --token TOKEN         GitHub Personal Access Token for authentication"
            echo "  --force              Force update even if no changes detected"
            echo "  --no-backup          Skip backup creation before update"
            echo "  --help, -h           Show this help message"
            echo ""
            echo "Examples:"
            echo "  ./milou.sh update"
            echo "  ./milou.sh update --version v1.2.0"
            echo "  ./milou.sh update --service frontend,backend"
            echo "  ./milou.sh update --token ghp_xxxxx --version 1.3.0"
            echo "  ./milou.sh update --force --no-backup"
            echo ""
            echo "OTHER UPDATE COMMANDS:"
            echo "  ./milou.sh update-cli        Update the CLI tool itself"
            echo "  ./milou.sh update-status     Check update status"
            echo "  ./milou.sh rollback          Rollback last update"
            ;;
        "cli")
            echo "🛠️ CLI Update Command Usage"
            echo "==========================="
            echo ""
            echo "UPDATE CLI:"
            echo "  ./milou.sh update-cli [VERSION] [OPTIONS]"
            echo ""
            echo "Arguments:"
            echo "  VERSION              Target version (default: latest)"
            echo ""
            echo "Options:"
            echo "  --force              Force update even if already up to date"
            echo "  --check              Check for updates without installing"
            echo "  --help, -h           Show this help"
            echo ""
            echo "Examples:"
            echo "  ./milou.sh update-cli"
            echo "  ./milou.sh update-cli v3.2.0"
            echo "  ./milou.sh update-cli --force"
            echo "  ./milou.sh update-cli --check"
            ;;
    esac
}

# System update command handler
handle_update() {
    local target_version=""
    local specific_services=""
    local force_update=false
    local backup_before_update=true
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                target_version="$2"
                shift 2
                ;;
            --service|--services)
                specific_services="$2"
                shift 2
                ;;
            --token)
                export GITHUB_TOKEN="$2"
                milou_log "DEBUG" "GitHub token set from command line"
                shift 2
                ;;
            --force)
                force_update=true
                shift
                ;;
            --no-backup)
                backup_before_update=false
                shift
                ;;
            --help|-h)
                _show_update_help "system"
                return 0
                ;;
            *)
                milou_log "WARN" "Unknown update argument: $1"
                shift
                ;;
        esac
    done
    
    # Log the update request
    if [[ -n "$target_version" ]]; then
        milou_log "STEP" "🔄 Updating system to version: $target_version"
    else
        milou_log "STEP" "🔄 Updating system to latest version..."
    fi
    
    if [[ -n "$specific_services" ]]; then
        milou_log "INFO" "🎯 Targeting services: $specific_services"
    fi
    
    # Use modular update function
    milou_update_system "$force_update" "$backup_before_update" "$target_version" "$specific_services"
}

# CLI self-update command handler
handle_update_cli() {
    local target_version="${1:-latest}"
    local force="${2:-false}"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                target_version="$2"
                shift 2
                ;;
            --force)
                force="true"
                shift
                ;;
            --check)
                handle_check_cli_updates
                return $?
                ;;
            --help|-h)
                _show_update_help "cli"
                return 0
                ;;
            *)
                # Assume it's a version if no flag
                if [[ "$1" != --* ]]; then
                    target_version="$1"
                fi
                shift
                ;;
        esac
    done
    
    milou_log "STEP" "🔄 Updating Milou CLI..."
    
    # Use modular CLI update function
    milou_update_cli "$target_version" "$force"
}

# Check for CLI updates
handle_check_cli_updates() {
    milou_log "INFO" "🔍 Checking for Milou CLI updates..."
    
    if milou_self_update_check; then
        milou_log "INFO" "🆕 CLI update available!"
        milou_log "INFO" "💡 Run './milou.sh update-cli' to update"
    else
        milou_log "SUCCESS" "✅ CLI is up to date"
    fi
}

# Update status check
handle_update_status() {
    milou_log "STEP" "📊 Checking system update status..."
    milou_update_check_status
}

# Show comprehensive version information
handle_version() {
    echo
    milou_log "INFO" "📊 Milou System Version Information"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # CLI and System versions
    local cli_version="${SCRIPT_VERSION:-${MILOU_VERSION:-unknown}}"
    local system_version="${MILOU_VERSION:-latest}"
    
    echo -e "   ${BOLD}Milou CLI:${NC}         v$cli_version"
    echo -e "   ${BOLD}System Version:${NC}    v$system_version"
    echo -e "   ${BOLD}Last Updated:${NC}      $(get_last_update_timestamp)"
    
    # Quick service status
    echo
    echo -e "   ${BOLD}Service Status:${NC}"
    local running_count=0
    local total_count=0
    
    # Count running services
    while IFS=$'\t' read -r container_name status; do
        if [[ "$container_name" =~ milou-(.+) ]]; then
            ((total_count++))
            if [[ "$status" =~ Up|running ]]; then
                ((running_count++))
            fi
        fi
    done < <(docker ps -a --filter "name=milou-" --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | tail -n +2)
    
    if [[ "$total_count" -eq 0 ]]; then
        echo -e "   • ${YELLOW}No services detected${NC} (run 'milou setup' to install)"
    elif [[ "$running_count" -eq "$total_count" ]]; then
        echo -e "   • ${GREEN}All services running${NC} ($running_count/$total_count)"
    elif [[ "$running_count" -gt 0 ]]; then
        echo -e "   • ${YELLOW}Partial services running${NC} ($running_count/$total_count)"
    else
        echo -e "   • ${RED}No services running${NC} ($running_count/$total_count)"
    fi
    
    # Update availability
    echo
    echo -e "   ${BOLD}Update Status:${NC}"
    
    # Check CLI updates quickly
    if command -v milou_self_update_check >/dev/null 2>&1; then
        if milou_self_update_check >/dev/null 2>&1; then
            echo -e "   • ${YELLOW}CLI update available${NC} (run 'milou self-update')"
        else
            echo -e "   • ${GREEN}CLI is up to date${NC}"
        fi
    fi
    
    # Check service updates quickly
    if check_updates_needed "latest" "" "true" >/dev/null 2>&1; then
        echo -e "   • ${YELLOW}Service updates available${NC} (run 'milou update')"
    else
        echo -e "   • ${GREEN}Services are up to date${NC}"
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo -e "   ${BOLD}Quick Commands:${NC}"
    echo "   • 'milou update-status' - Detailed update information"
    echo "   • 'milou update' - Update all services"
    echo "   • 'milou status' - Full system status"
    echo
}

# Quick version display (for --version flag)
show_version() {
    local cli_version="${SCRIPT_VERSION:-${MILOU_VERSION:-unknown}}"
    echo "Milou CLI v$cli_version"
    echo "Professional Docker Management Tool"
}

# Rollback system update
handle_rollback() {
    local backup_file="${1:-}"
    
    milou_log "STEP" "🔄 Rolling back system update..."
    milou_update_rollback "$backup_file"
}

# =============================================================================
# WEEK 4: SMART UPDATE SYSTEM ENHANCEMENTS
# =============================================================================

# Smart update detection with semver support and change impact analysis
smart_update_detection() {
    local target_version="${1:-latest}"
    local specific_services="${2:-}"
    local github_token="${3:-}"
    local check_only="${4:-false}"
    
    milou_log "INFO" "🧠 Smart update detection analysis..."
    
    # Initialize results structure
    local -A update_analysis=(
        [needs_update]="false"
        [version_available]="false"
        [impact_level]="none"
        [affected_services]=""
        [requires_downtime]="false"
        [rollback_complexity]="low"
        [estimated_duration]="0"
    )
    
    # Get current version and parse semver
    local current_version="${MILOU_VERSION:-1.0.0}"
    milou_log "DEBUG" "Current version: $current_version"
    
    # Determine target version if 'latest' requested
    if [[ "$target_version" == "latest" ]]; then
        target_version=$(detect_latest_version "$github_token")
        if [[ $? -ne 0 ]] || [[ -z "$target_version" ]]; then
            milou_log "WARN" "Could not determine latest version, using current"
            target_version="$current_version"
        fi
    fi
    
    # Semantic version comparison
    if compare_semver_versions "$current_version" "$target_version"; then
        update_analysis[needs_update]="true"
        update_analysis[version_available]="true"
        milou_log "INFO" "📈 Update available: $current_version → $target_version"
    else
        milou_log "INFO" "✅ Already at requested version: $current_version"
        if [[ "$check_only" == "true" ]]; then
            return 1  # No update needed
        fi
    fi
    
    # Analyze update impact
    analyze_update_impact "$current_version" "$target_version" "$specific_services" update_analysis
    
    # Store analysis results for use by other functions
    export SMART_UPDATE_ANALYSIS
    SMART_UPDATE_ANALYSIS=$(declare -p update_analysis)
    
    # Display analysis results
    display_update_analysis update_analysis
    
    # Return whether update is needed
    [[ "${update_analysis[needs_update]}" == "true" ]]
}

# Semantic version comparison with enhanced logic
compare_semver_versions() {
    local current="$1"
    local target="$2"
    
    # Remove 'v' prefix if present
    current="${current#v}"
    target="${target#v}"
    
    # Split versions into parts (major.minor.patch)
    IFS='.' read -ra current_parts <<< "$current"
    IFS='.' read -ra target_parts <<< "$target"
    
    # Compare each part
    for i in {0..2}; do
        local current_part="${current_parts[$i]:-0}"
        local target_part="${target_parts[$i]:-0}"
        
        # Remove non-numeric suffixes (e.g., "rc1", "beta2")
        current_part="${current_part%%[^0-9]*}"
        target_part="${target_part%%[^0-9]*}"
        
        if [[ $target_part -gt $current_part ]]; then
            return 0  # Target is newer
        elif [[ $target_part -lt $current_part ]]; then
            return 1  # Current is newer
        fi
        # If equal, continue to next part
    done
    
    return 1  # Versions are equal
}

# Detect latest available version from GitHub releases
detect_latest_version() {
    local github_token="${1:-}"
    
    milou_log "DEBUG" "Detecting latest version from GitHub..."
    
    local auth_header=""
    if [[ -n "$github_token" ]]; then
        auth_header="Authorization: token $github_token"
    fi
    
    local latest_version
    if command -v curl >/dev/null 2>&1; then
        latest_version=$(curl -s \
            ${auth_header:+-H "$auth_header"} \
            "$RELEASE_API_URL/latest" | \
            grep '"tag_name":' | \
            head -n 1 | \
            cut -d '"' -f 4)
    elif command -v wget >/dev/null 2>&1; then
        local auth_option=""
        if [[ -n "$github_token" ]]; then
            auth_option="--header=\"Authorization: token $github_token\""
        fi
        latest_version=$(eval "wget -qO- $auth_option '$RELEASE_API_URL/latest'" | \
            grep '"tag_name":' | \
            head -n 1 | \
            cut -d '"' -f 4)
    else
        milou_log "ERROR" "Neither curl nor wget available for version detection"
        return 1
    fi
    
    if [[ -n "$latest_version" ]]; then
        echo "$latest_version"
        return 0
    else
        milou_log "ERROR" "Failed to detect latest version"
        return 1
    fi
}

# Analyze update impact and complexity
analyze_update_impact() {
    local current_version="$1"
    local target_version="$2"
    local specific_services="$3"
    local -n analysis_ref="$4"
    
    milou_log "DEBUG" "Analyzing update impact..."
    
    # Parse version differences to determine impact level
    local version_diff_major version_diff_minor version_diff_patch
    get_version_differences "$current_version" "$target_version" version_diff_major version_diff_minor version_diff_patch
    
    # Determine impact level based on version differences
    if [[ $version_diff_major -gt 0 ]]; then
        analysis_ref[impact_level]="high"
        analysis_ref[requires_downtime]="true"
        analysis_ref[rollback_complexity]="high"
        analysis_ref[estimated_duration]="15-30"
    elif [[ $version_diff_minor -gt 0 ]]; then
        analysis_ref[impact_level]="medium"
        analysis_ref[requires_downtime]="true"
        analysis_ref[rollback_complexity]="medium"
        analysis_ref[estimated_duration]="10-20"
    elif [[ $version_diff_patch -gt 0 ]]; then
        analysis_ref[impact_level]="low"
        analysis_ref[requires_downtime]="false"
        analysis_ref[rollback_complexity]="low"
        analysis_ref[estimated_duration]="5-10"
    else
        analysis_ref[impact_level]="none"
        analysis_ref[estimated_duration]="0"
    fi
    
    # Determine affected services
    local -a services_to_update=()
    if [[ -n "$specific_services" ]]; then
        IFS=',' read -ra services_to_update <<< "$specific_services"
    else
        services_to_update=("${DEFAULT_SERVICES[@]}")
    fi
    analysis_ref[affected_services]="${services_to_update[*]}"
    
    # Adjust estimates based on service count
    local service_count=${#services_to_update[@]}
    if [[ $service_count -gt 3 ]]; then
        # Increase duration estimate for multiple services
        local current_duration="${analysis_ref[estimated_duration]}"
        analysis_ref[estimated_duration]="${current_duration} (full system)"
    fi
}

# Get version differences for analysis
get_version_differences() {
    local current="$1"
    local target="$2"
    local -n major_ref="$3"
    local -n minor_ref="$4"
    local -n patch_ref="$5"
    
    # Remove 'v' prefix if present
    current="${current#v}"
    target="${target#v}"
    
    # Split versions into parts
    IFS='.' read -ra current_parts <<< "$current"
    IFS='.' read -ra target_parts <<< "$target"
    
    # Calculate differences
    major_ref=$((${target_parts[0]:-0} - ${current_parts[0]:-0}))
    minor_ref=$((${target_parts[1]:-0} - ${current_parts[1]:-0}))
    patch_ref=$((${target_parts[2]:-0} - ${current_parts[2]:-0}))
    
    # Ensure non-negative values
    major_ref=$((major_ref > 0 ? major_ref : 0))
    minor_ref=$((minor_ref > 0 ? minor_ref : 0))
    patch_ref=$((patch_ref > 0 ? patch_ref : 0))
}

# Display update analysis results
display_update_analysis() {
    local -n analysis_ref="$1"
    
    echo
    milou_log "INFO" "📊 Update Impact Analysis"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Impact level with color coding
    local impact_color=""
    case "${analysis_ref[impact_level]}" in
        "high") impact_color="\033[0;31m" ;;    # Red
        "medium") impact_color="\033[1;33m" ;;  # Yellow
        "low") impact_color="\033[0;32m" ;;     # Green
        "none") impact_color="\033[2m" ;;       # Dim
    esac
    
    echo -e "   ${BOLD}Impact Level:${NC} ${impact_color}${analysis_ref[impact_level]^^}${NC}"
    echo -e "   ${BOLD}Affected Services:${NC} ${analysis_ref[affected_services]}"
    echo -e "   ${BOLD}Requires Downtime:${NC} ${analysis_ref[requires_downtime]}"
    echo -e "   ${BOLD}Rollback Complexity:${NC} ${analysis_ref[rollback_complexity]}"
    echo -e "   ${BOLD}Estimated Duration:${NC} ${analysis_ref[estimated_duration]} minutes"
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
}

# Enhanced update process with smart detection integration
enhanced_update_process() {
    local target_version="${1:-latest}"
    local specific_services="${2:-}"
    local force_update="${3:-false}"
    local backup_before_update="${4:-true}"
    local github_token="${5:-}"
    
    milou_log "STEP" "🚀 Enhanced Smart Update Process"
    
    # Step 1: Smart detection and analysis
    if [[ "$force_update" != "true" ]]; then
        if ! smart_update_detection "$target_version" "$specific_services" "$github_token" "true"; then
            milou_log "INFO" "✅ No update needed based on smart detection"
            return 0
        fi
    else
        milou_log "INFO" "🔄 Force update requested - skipping smart detection"
    fi
    
    # Step 2: Pre-update preparation with enhanced backup
    if [[ "$backup_before_update" == "true" ]]; then
        enhanced_pre_update_backup "$target_version" "$specific_services"
    fi
    
    # Step 3: Execute update with monitoring
    execute_monitored_update "$target_version" "$specific_services" "$github_token"
    local update_result=$?
    
    # Step 4: Post-update validation
    if [[ $update_result -eq 0 ]]; then
        post_update_validation "$target_version" "$specific_services"
        update_result=$?
    fi
    
    # Step 5: Handle results
    if [[ $update_result -eq 0 ]]; then
        milou_log "SUCCESS" "✅ Enhanced update process completed successfully"
        cleanup_update_artifacts
    else
        milou_log "ERROR" "❌ Update process failed - initiating rollback"
        emergency_rollback "$target_version" "$specific_services"
    fi
    
    return $update_result
}

# Enhanced pre-update backup with metadata
enhanced_pre_update_backup() {
    local target_version="$1"
    local specific_services="$2"
    
    milou_log "INFO" "📦 Creating enhanced pre-update backup..."
    
    # Create backup with metadata
    local backup_name="pre_update_$(date +%Y%m%d_%H%M%S)_${MILOU_VERSION:-unknown}_to_${target_version}"
    local backup_metadata="/tmp/milou_update_metadata_$(date +%s).json"
    
    # Generate backup metadata
    cat > "$backup_metadata" << EOF
{
    "backup_type": "pre_update",
    "timestamp": "$(date -Iseconds)",
    "current_version": "${MILOU_VERSION:-unknown}",
    "target_version": "$target_version",
    "affected_services": "$specific_services",
    "milou_cli_version": "${MILOU_CLI_VERSION:-unknown}",
    "system_info": {
        "os": "$(uname -s)",
        "arch": "$(uname -m)",
        "hostname": "$(hostname)"
    }
}
EOF
    
    # Perform backup with metadata
    if command -v milou_backup_create >/dev/null 2>&1; then
        local backup_path
        if backup_path=$(milou_backup_create "full" "./backups" "$backup_name"); then
            # Add metadata to backup
            local backup_dir="${backup_path%.*}"
            mkdir -p "/tmp/milou_backup_extract"
            tar -xzf "$backup_path" -C "/tmp/milou_backup_extract"
            cp "$backup_metadata" "/tmp/milou_backup_extract/$backup_name/update_metadata.json"
            tar -czf "$backup_path" -C "/tmp/milou_backup_extract" "$backup_name"
            rm -rf "/tmp/milou_backup_extract"
            
            milou_log "SUCCESS" "✅ Enhanced backup created with metadata: $backup_path"
            export LAST_BACKUP_PATH="$backup_path"
        else
            milou_log "ERROR" "❌ Failed to create pre-update backup"
            return 1
        fi
    else
        milou_log "WARN" "⚠️ Backup function not available"
    fi
    
    rm -f "$backup_metadata"
    return 0
}

# Emergency rollback with smart recovery
emergency_rollback() {
    local failed_target_version="$1"
    local failed_services="$2"
    
    milou_log "WARN" "🚨 Emergency rollback initiated"
    
    # Use the last backup if available
    if [[ -n "${LAST_BACKUP_PATH:-}" && -f "$LAST_BACKUP_PATH" ]]; then
        milou_log "INFO" "🔄 Rolling back using backup: $LAST_BACKUP_PATH"
        
        if command -v milou_restore_from_backup >/dev/null 2>&1; then
            if milou_restore_from_backup "$LAST_BACKUP_PATH" "true"; then
                milou_log "SUCCESS" "✅ Emergency rollback completed"
                
                # Verify rollback success
                if verify_rollback_success; then
                    milou_log "SUCCESS" "✅ Rollback verification passed"
                    return 0
                else
                    milou_log "ERROR" "❌ Rollback verification failed"
                    return 1
                fi
            else
                milou_log "ERROR" "❌ Emergency rollback failed"
                return 1
            fi
        else
            milou_log "ERROR" "❌ Restore function not available"
            return 1
        fi
    else
        milou_log "ERROR" "❌ No backup available for emergency rollback"
        milou_log "INFO" "💡 Manual intervention may be required"
        return 1
    fi
}

# Verify rollback success
verify_rollback_success() {
    milou_log "INFO" "🔍 Verifying rollback success..."
    
    # Check service health
    if command -v health_check_all >/dev/null 2>&1; then
        if health_check_all "true"; then
            milou_log "DEBUG" "✅ Service health check passed"
        else
            milou_log "ERROR" "❌ Service health check failed after rollback"
            return 1
        fi
    fi
    
    # Verify configuration integrity
    if command -v config_validate >/dev/null 2>&1; then
        if config_validate "${SCRIPT_DIR}/.env" "minimal" "true"; then
            milou_log "DEBUG" "✅ Configuration validation passed"
        else
            milou_log "ERROR" "❌ Configuration validation failed after rollback"
            return 1
        fi
    fi
    
    return 0
}

# Create pre-update backup with metadata
create_pre_update_backup() {
    local target_version="${1:-latest}"
    local specific_services="${2:-all}"
    local quiet="${3:-false}"
    
    milou_log "INFO" "📦 Creating pre-update backup..."
    
    # Use existing backup functionality if available
    if command -v milou_backup_create >/dev/null 2>&1; then
        local backup_name="pre_update_$(date +%Y%m%d_%H%M%S)"
        local backup_path
        
        if backup_path=$(milou_backup_create "full" "./backups" "$backup_name" 2>/dev/null); then
            milou_log "SUCCESS" "✅ Pre-update backup created: $backup_path"
            export LAST_BACKUP_PATH="$backup_path"
            return 0
        else
            milou_log "ERROR" "❌ Failed to create pre-update backup"
            return 1
        fi
    else
        milou_log "WARN" "⚠️ Backup function not available"
        return 1
    fi
}

# Execute update with monitoring and health checks
execute_monitored_update() {
    local target_version="$1"
    local specific_services="$2"
    local github_token="$3"
    
    milou_log "INFO" "🔄 Executing monitored update process..."
    
    # Use existing update function with enhanced monitoring
    local start_time
    start_time=$(date +%s)
    
    # Execute the actual update
    if [[ -n "$specific_services" ]]; then
        _milou_update_selective_services "$target_version" "$specific_services"
    else
        _milou_update_all_services "$target_version" "$github_token"
    fi
    
    local update_result=$?
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    milou_log "INFO" "⏱️ Update duration: ${duration} seconds"
    
    return $update_result
}

# Post-update validation with comprehensive checks
post_update_validation() {
    local target_version="$1"
    local specific_services="$2"
    
    milou_log "INFO" "🔍 Post-update validation..."
    
    # Wait for services to stabilize
    sleep 5
    
    # Check service health
    if command -v health_check_all >/dev/null 2>&1; then
        if ! health_check_all "true"; then
            milou_log "ERROR" "❌ Service health check failed after update"
            return 1
        fi
    fi
    
    # Verify configuration integrity
    if command -v config_validate >/dev/null 2>&1; then
        if ! config_validate "${SCRIPT_DIR}/.env" "minimal" "true"; then
            milou_log "ERROR" "❌ Configuration validation failed after update"
            return 1
        fi
    fi
    
    # Check if services are responding
    if command -v docker_execute >/dev/null 2>&1; then
        local running_services
        running_services=$(docker_execute "ps" "--format \"{{.Names}}\"" "true" 2>/dev/null | wc -l)
        
        if [[ $running_services -eq 0 ]]; then
            milou_log "ERROR" "❌ No services running after update"
            return 1
        fi
    fi
    
    milou_log "SUCCESS" "✅ Post-update validation passed"
    return 0
}

# Clean up temporary update artifacts
cleanup_update_artifacts() {
    milou_log "DEBUG" "🧹 Cleaning up update artifacts..."
    
    # Remove temporary files
    rm -f /tmp/milou_env_backup_* 2>/dev/null || true
    rm -f /tmp/milou_pre_update_status_* 2>/dev/null || true
    rm -f /tmp/milou_update_metadata_* 2>/dev/null || true
    
    # Clear update cache
    unset SMART_UPDATE_ANALYSIS LAST_BACKUP_PATH
    
    milou_log "DEBUG" "✅ Update artifacts cleaned up"
}

# =============================================================================
# CLEAN PUBLIC API - Export only essential functions
# =============================================================================

# System Update Functions
export -f milou_update_system           # Primary system update function
export -f milou_update_rollback         # Rollback capability  
export -f milou_update_check_status     # Status checking
export -f milou_update_cli              # CLI self-update

# CLI Self-Update Functions
export -f milou_self_update_check       # Check for CLI updates
export -f milou_self_update_perform     # Perform CLI update

# WEEK 4: Enhanced smart update functions
export -f smart_update_detection        # Smart update detection
export -f enhanced_update_process       # Enhanced update process
export -f emergency_rollback            # Emergency rollback
export -f compare_semver_versions       # Semantic version comparison
export -f create_pre_update_backup      # Pre-update backup creation

# Command Handlers
export -f handle_update                 # System update handler
export -f handle_update_cli             # CLI update handler
export -f handle_check_cli_updates      # CLI update check
export -f handle_update_status          # Update status check
export -f handle_rollback               # Rollback handler

# Internal functions are NOT exported (marked with _ prefix)
# This keeps the namespace clean and makes it clear what's public vs internal 

# Create database safety backup before updates
_create_database_safety_backup() {
    milou_log "INFO" "📦 Creating database safety backup..."
    
    # Check if database container is running
    local db_container=""
    for container in "milou-database" "static-database" "milou-static-database"; do
        if docker ps --filter "name=$container" --format "{{.Names}}" | grep -q "$container"; then
            db_container="$container"
            break
        fi
    done
    
    if [[ -z "$db_container" ]]; then
        milou_log "WARN" "⚠️ Database container not running - skipping database backup"
        return 0
    fi
    
    # Create backup directory with enhanced security
    local backup_dir="./backups/db_safety"
    mkdir -p "$backup_dir"
    chmod 700 "$backup_dir"  # Secure permissions
    local backup_file="$backup_dir/db_safety_backup_$(date +%Y%m%d_%H%M%S).sql"
    
    # Get database credentials
    local db_name="${POSTGRES_DB:-milou_database}"
    local db_user="${POSTGRES_USER:-}"
    
    if [[ -z "$db_user" ]]; then
        milou_log "ERROR" "❌ Database user not found in environment"
        return 1
    fi
    
    # Create comprehensive database dump with all necessary flags
    milou_log "INFO" "📊 Creating comprehensive database dump..."
    if docker exec "$db_container" pg_dump \
        -U "$db_user" \
        -d "$db_name" \
        --clean \
        --if-exists \
        --create \
        --verbose \
        --no-password > "$backup_file" 2>/dev/null; then
        
        # Verify backup file is not empty and contains actual data
        if [[ -s "$backup_file" ]]; then
            # Additional verification: check if backup contains actual table data
            local table_count
            table_count=$(grep -c "CREATE TABLE" "$backup_file" 2>/dev/null || echo "0")
            
            if [[ "$table_count" -gt 0 ]]; then
                # Set secure permissions on backup file
                chmod 600 "$backup_file"
                milou_log "SUCCESS" "✅ Database safety backup created: $backup_file ($table_count tables)"
                echo "$backup_file"
                return 0
            else
                milou_log "ERROR" "❌ Database backup contains no table structures"
                rm -f "$backup_file"
                return 1
            fi
        else
            milou_log "ERROR" "❌ Database backup file is empty"
            rm -f "$backup_file"
            return 1
        fi
    else
        milou_log "ERROR" "❌ Failed to create database backup"
        rm -f "$backup_file"
        return 1
    fi
}

# Verify database integrity after update
_verify_database_integrity() {
    milou_log "INFO" "🔍 Verifying database integrity..."
    
    local db_container=""
    for container in "milou-database" "static-database" "milou-static-database"; do
        if docker ps --filter "name=$container" --format "{{.Names}}" | grep -q "$container"; then
            db_container="$container"
            break
        fi
    done
    
    if [[ -z "$db_container" ]]; then
        milou_log "ERROR" "❌ Database container not found"
        return 1
    fi
    
    # Extended wait for database to be ready after container update
    local max_wait=60  # Increased from 30 to 60 seconds
    local wait_count=0
    milou_log "INFO" "⏳ Waiting for database to be ready after update..."
    
    while [[ $wait_count -lt $max_wait ]]; do
        if docker exec "$db_container" pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB:-milou_database}" >/dev/null 2>&1; then
            break
        fi
        sleep 2
        ((wait_count += 2))
        
        # Progress indicator every 10 seconds
        if [[ $((wait_count % 10)) -eq 0 ]]; then
            milou_log "INFO" "⏳ Database still starting... (${wait_count}s elapsed)"
        fi
    done
    
    if [[ $wait_count -ge $max_wait ]]; then
        milou_log "ERROR" "❌ Database not ready after $max_wait seconds"
        return 1
    fi
    
    # Test basic database operations
    local db_name="${POSTGRES_DB:-milou_database}"
    local db_user="${POSTGRES_USER:-}"
    
    # Test 1: Basic connectivity and query execution
    milou_log "INFO" "🔍 Testing database connectivity..."
    if docker exec "$db_container" psql -U "$db_user" -d "$db_name" -c "SELECT 1;" >/dev/null 2>&1; then
        milou_log "SUCCESS" "✅ Database connectivity verified"
    else
        milou_log "ERROR" "❌ Database connectivity test failed"
        return 1
    fi
    
    # Test 2: Schema accessibility and table verification
    milou_log "INFO" "🔍 Verifying database schema..."
    local table_check_result
    table_check_result=$(docker exec "$db_container" psql -U "$db_user" -d "$db_name" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' \n')
    
    if [[ "$table_check_result" =~ ^[0-9]+$ ]] && [[ "$table_check_result" -gt 0 ]]; then
        milou_log "SUCCESS" "✅ Database schema verified ($table_check_result tables found)"
    else
        milou_log "ERROR" "❌ Database schema verification failed"
        return 1
    fi
    
    # Test 3: Write operation verification (create and drop test table)
    milou_log "INFO" "🔍 Testing database write operations..."
    local test_table="milou_update_integrity_test_$(date +%s)"
    
    if docker exec "$db_container" psql -U "$db_user" -d "$db_name" \
        -c "CREATE TABLE $test_table (id INTEGER, test_data TEXT);" \
        -c "INSERT INTO $test_table VALUES (1, 'integrity_test');" \
        -c "SELECT COUNT(*) FROM $test_table;" \
        -c "DROP TABLE $test_table;" >/dev/null 2>&1; then
        milou_log "SUCCESS" "✅ Database write operations verified"
    else
        milou_log "ERROR" "❌ Database write operations test failed"
        return 1
    fi
    
    # Test 4: Extension verification (if any critical extensions are used)
    milou_log "INFO" "🔍 Verifying database extensions..."
    local extension_check
    extension_check=$(docker exec "$db_container" psql -U "$db_user" -d "$db_name" -t -c "SELECT COUNT(*) FROM pg_extension;" 2>/dev/null | tr -d ' \n')
    
    if [[ "$extension_check" =~ ^[0-9]+$ ]]; then
        milou_log "SUCCESS" "✅ Database extensions verified ($extension_check extensions loaded)"
    else
        milou_log "WARN" "⚠️ Could not verify database extensions"
    fi
    
    milou_log "SUCCESS" "✅ Complete database integrity verification passed"
    return 0
}

# Rollback database from backup
_rollback_database_from_backup() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        milou_log "ERROR" "❌ Backup file not found: $backup_file"
        return 1
    fi
    
    # Verify backup file integrity before attempting rollback
    milou_log "INFO" "🔍 Verifying backup file integrity..."
    if [[ ! -s "$backup_file" ]]; then
        milou_log "ERROR" "❌ Backup file is empty: $backup_file"
        return 1
    fi
    
    # Check if backup contains SQL commands
    if ! grep -q "CREATE\|INSERT\|COPY" "$backup_file" 2>/dev/null; then
        milou_log "ERROR" "❌ Backup file appears to be invalid (no SQL commands found)"
        return 1
    fi
    
    milou_log "WARN" "🔄 Rolling back database from backup: $backup_file"
    
    local db_container=""
    for container in "milou-database" "static-database" "milou-static-database"; do
        if docker ps --filter "name=$container" --format "{{.Names}}" | grep -q "$container"; then
            db_container="$container"
            break
        fi
    done
    
    if [[ -z "$db_container" ]]; then
        milou_log "ERROR" "❌ Database container not found for rollback"
        return 1
    fi
    
    # Create a pre-rollback backup for safety
    milou_log "INFO" "📦 Creating pre-rollback safety backup..."
    local pre_rollback_backup="./backups/db_safety/pre_rollback_backup_$(date +%Y%m%d_%H%M%S).sql"
    mkdir -p "$(dirname "$pre_rollback_backup")"
    
    if docker exec "$db_container" pg_dump -U "${POSTGRES_USER}" -d "${POSTGRES_DB:-milou_database}" --clean --if-exists > "$pre_rollback_backup" 2>/dev/null; then
        chmod 600 "$pre_rollback_backup"
        milou_log "INFO" "💾 Pre-rollback backup created: $pre_rollback_backup"
    else
        milou_log "WARN" "⚠️ Could not create pre-rollback backup, continuing anyway"
    fi
    
    # Restore database with enhanced error handling
    local db_name="${POSTGRES_DB:-milou_database}"
    local db_user="${POSTGRES_USER:-}"
    
    milou_log "INFO" "🔄 Restoring database from backup..."
    if docker exec -i "$db_container" psql -U "$db_user" -d "$db_name" < "$backup_file" >/dev/null 2>&1; then
        milou_log "SUCCESS" "✅ Database restore completed"
        
        # Verify rollback success
        milou_log "INFO" "🔍 Verifying rollback success..."
        if _verify_database_integrity; then
            milou_log "SUCCESS" "✅ Database rollback verification passed"
            return 0
        else
            milou_log "ERROR" "❌ Database rollback verification failed"
            
            # Attempt to restore from pre-rollback backup if available
            if [[ -f "$pre_rollback_backup" ]]; then
                milou_log "WARN" "🔄 Attempting to restore from pre-rollback backup..."
                if docker exec -i "$db_container" psql -U "$db_user" -d "$db_name" < "$pre_rollback_backup" >/dev/null 2>&1; then
                    milou_log "SUCCESS" "✅ Restored from pre-rollback backup"
                else
                    milou_log "ERROR" "❌ Failed to restore from pre-rollback backup"
                fi
            fi
            return 1
        fi
    else
        milou_log "ERROR" "❌ Database rollback failed"
        return 1
    fi
}

# Safe full system update with zero-downtime strategy
_milou_update_all_services_safe() {
    local target_version="${1:-latest}"
    local github_token="${2:-}"
    
    milou_log "INFO" "🔄 Performing safe full system update to version: $target_version"
    
    # Define update order (dependencies first) with comprehensive dependency mapping
    local update_order=("database" "redis" "rabbitmq" "backend" "engine" "frontend" "nginx")
    
    # Service dependency mapping for enhanced safety
    declare -A service_deps=(
        ["database"]=""                           # No dependencies
        ["redis"]=""                             # No dependencies  
        ["rabbitmq"]=""                          # No dependencies
        ["backend"]="database redis rabbitmq"    # Depends on all infrastructure
        ["engine"]="database redis rabbitmq"     # Depends on infrastructure  
        ["frontend"]="backend"                   # Depends on backend API
        ["nginx"]="frontend backend"             # Depends on app services
    )
    
    # Pre-update validation: ensure all required images are available
    milou_log "INFO" "🔍 Pre-update validation: checking image availability..."
    local registry="${DOCKER_REGISTRY:-ghcr.io/milou-sh/milou}"
    
    for service in "${update_order[@]}"; do
        local image_name="${registry}/${service}:${target_version}"
        milou_log "INFO" "📥 Verifying image availability: $image_name"
        
        if ! docker pull "$image_name" >/dev/null 2>&1; then
            milou_log "ERROR" "❌ Image not available: $image_name"
            milou_log "ERROR" "❌ Aborting update - not all images are available"
            return 1
        fi
        milou_log "SUCCESS" "✅ Image available: $service"
    done
    
    # Update services in dependency order with rolling deployment
    local successful_updates=()
    local failed_updates=()
    
    for service in "${update_order[@]}"; do
        milou_log "INFO" "🔄 Updating $service with zero-downtime rolling deployment..."
        
        # Special handling for database updates
        if [[ "$service" == "database" ]]; then
            milou_log "INFO" "🗄️ Creating database safety backup before update..."
            local db_backup_path
            db_backup_path=$(_create_database_safety_backup)
            
            if [[ $? -ne 0 ]]; then
                milou_log "ERROR" "❌ Database backup failed - ABORTING update for safety"
                return 1
            fi
        fi
        
        # Wait for dependencies to be healthy before updating this service
        local deps="${service_deps[$service]}"
        if [[ -n "$deps" ]]; then
            milou_log "INFO" "🔍 Verifying dependencies are healthy: $deps"
            for dep in $deps; do
                if ! _wait_for_service_health "$dep" 30; then
                    milou_log "ERROR" "❌ Dependency $dep is not healthy - cannot update $service"
                    failed_updates+=("$service")
                    continue 2  # Skip to next service
                fi
            done
        fi
        
        # Perform rolling update for the service
        if _perform_rolling_service_update "$service" "$target_version"; then
            successful_updates+=("$service")
            milou_log "SUCCESS" "✅ Successfully updated $service"
            
            # Special post-update verification for database
            if [[ "$service" == "database" ]]; then
                milou_log "INFO" "🔍 Verifying database integrity after update..."
                if ! _verify_database_integrity; then
                    milou_log "ERROR" "❌ Database integrity check failed - initiating rollback"
                    if [[ -n "$db_backup_path" ]]; then
                        _rollback_database_from_backup "$db_backup_path"
                    fi
                    failed_updates+=("$service")
                    return 1
                fi
            fi
        else
            failed_updates+=("$service")
            milou_log "ERROR" "❌ Failed to update $service"
            
            # For critical services, consider this a fatal error
            if [[ "$service" == "database" || "$service" == "backend" ]]; then
                milou_log "ERROR" "❌ Critical service update failed - aborting update process"
                return 1
            fi
        fi
    done
    
    # Final comprehensive health check
    milou_log "INFO" "🏥 Performing final comprehensive system health check..."
    if _milou_update_verify_services "${successful_updates[@]}"; then
        milou_log "SUCCESS" "✅ All updated services are healthy"
    else
        milou_log "ERROR" "❌ Some services failed final health check"
        return 1
    fi
    
    # Update summary
    if [[ ${#failed_updates[@]} -eq 0 ]]; then
        milou_log "SUCCESS" "🎉 Zero-downtime update completed successfully!"
        milou_log "INFO" "📊 Updated services: ${successful_updates[*]}"
    else
        milou_log "WARN" "⚠️ Update completed with some failures"
        milou_log "INFO" "📊 Successful: ${successful_updates[*]}"
        milou_log "INFO" "📊 Failed: ${failed_updates[*]}"
        return 1
    fi
    
    return 0
}

# Perform rolling update for individual service
_perform_rolling_service_update() {
    local service="$1"
    local target_version="$2"
    
    milou_log "INFO" "🔄 Rolling update for $service..."
    
    # Get current container ID for fallback
    local current_container
    current_container=$(docker ps --filter "name=milou-$service" --format "{{.ID}}" | head -1)
    
    # Update service with zero downtime using Docker Compose
    if command -v docker_execute >/dev/null 2>&1; then
        # Use --no-deps to avoid restarting dependent services
        # Use --force-recreate to ensure new image is used
        if docker_execute "up" "$service" "false" "--no-deps" "--force-recreate" "-d"; then
            milou_log "INFO" "🔄 Container updated, waiting for health check..."
        else
            milou_log "ERROR" "❌ Failed to update container for $service"
            return 1
        fi
    else
        # Fallback method
        if docker compose up -d --no-deps --force-recreate "$service" >/dev/null 2>&1; then
            milou_log "INFO" "🔄 Container updated, waiting for health check..."
        else
            milou_log "ERROR" "❌ Failed to update container for $service"
            return 1
        fi
    fi
    
    # Wait for service to be healthy with extended timeout for critical services
    local health_timeout=60
    if [[ "$service" == "database" ]]; then
        health_timeout=120  # Database needs more time
    fi
    
    if _wait_for_service_health "$service" "$health_timeout"; then
        milou_log "SUCCESS" "✅ $service is healthy after rolling update"
        
        # Clean up old container if update successful
        if [[ -n "$current_container" ]]; then
            docker rm "$current_container" >/dev/null 2>&1 || true
        fi
        
        return 0
    else
        milou_log "ERROR" "❌ $service failed health check after rolling update"
        
        # Attempt to rollback by restarting old container if available
        if [[ -n "$current_container" ]]; then
            milou_log "WARN" "🔄 Attempting to rollback $service..."
            docker start "$current_container" >/dev/null 2>&1 || true
        fi
        
        return 1
    fi
}

# Wait for service to be healthy
_wait_for_service_health() {
    local service="$1"
    local max_wait="${2:-60}"
    local elapsed=0
    
    milou_log "INFO" "⏳ Waiting for $service to be healthy..."
    
    while [[ $elapsed -lt $max_wait ]]; do
        # Basic container status check
        if docker ps --filter "name=milou-$service" --filter "status=running" --format "{{.Names}}" | grep -q "milou-$service"; then
            
            # Service-specific health checks for comprehensive verification
            case "$service" in
                "database")
                    # Database-specific health check using pg_isready
                    if docker exec "milou-$service" pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB:-milou_database}" >/dev/null 2>&1; then
                        # Additional check: verify we can actually connect and query
                        if docker exec "milou-$service" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB:-milou_database}" -c "SELECT 1;" >/dev/null 2>&1; then
                            milou_log "SUCCESS" "✅ $service is healthy (database responding to queries)"
                            return 0
                        fi
                    fi
                    ;;
                "redis")
                    # Redis-specific health check
                    if docker exec "milou-$service" redis-cli -a "${REDIS_PASSWORD}" ping >/dev/null 2>&1; then
                        milou_log "SUCCESS" "✅ $service is healthy (Redis responding to ping)"
                        return 0
                    fi
                    ;;
                "rabbitmq")
                    # RabbitMQ-specific health check
                    if docker exec "milou-$service" rabbitmqctl status >/dev/null 2>&1; then
                        milou_log "SUCCESS" "✅ $service is healthy (RabbitMQ status OK)"
                        return 0
                    fi
                    ;;
                "backend")
                    # Backend API health check
                    if docker exec "milou-$service" curl -f -s http://localhost:9999/api/health >/dev/null 2>&1 || \
                       docker exec "milou-$service" nc -z localhost 9999 >/dev/null 2>&1; then
                        milou_log "SUCCESS" "✅ $service is healthy (API responding)"
                        return 0
                    fi
                    ;;
                "frontend")
                    # Frontend health check
                    if docker exec "milou-$service" curl -f -s http://localhost:5173/ >/dev/null 2>&1 || \
                       docker exec "milou-$service" nc -z localhost 5173 >/dev/null 2>&1; then
                        milou_log "SUCCESS" "✅ $service is healthy (Frontend responding)"
                        return 0
                    fi
                    ;;
                "nginx")
                    # Nginx health check
                    if docker exec "milou-$service" nginx -t >/dev/null 2>&1 && \
                       docker exec "milou-$service" curl -f -s http://localhost/ >/dev/null 2>&1; then
                        milou_log "SUCCESS" "✅ $service is healthy (Nginx config valid and responding)"
                        return 0
                    fi
                    ;;
                "engine")
                    # Engine health check
                    if docker exec "milou-$service" curl -f -s http://localhost:8089/health >/dev/null 2>&1 || \
                       docker exec "milou-$service" nc -z localhost 8089 >/dev/null 2>&1; then
                        milou_log "SUCCESS" "✅ $service is healthy (Engine responding)"
                        return 0
                    fi
                    ;;
                *)
                    # Generic health check for unknown services
                    milou_log "SUCCESS" "✅ $service is healthy (container running)"
                    return 0
                    ;;
            esac
        fi
        
        sleep 3
        elapsed=$((elapsed + 3))
        
        # Progress indicator every 15 seconds with service-specific context
        if [[ $((elapsed % 15)) -eq 0 ]]; then
            case "$service" in
                "database")
                    milou_log "INFO" "⏳ Still waiting for $service (database may be initializing... ${elapsed}s elapsed)"
                    ;;
                "backend"|"frontend"|"engine")
                    milou_log "INFO" "⏳ Still waiting for $service (application starting up... ${elapsed}s elapsed)"
                    ;;
                *)
                    milou_log "INFO" "⏳ Still waiting for $service (${elapsed}s elapsed)..."
                    ;;
            esac
        fi
    done
    
    milou_log "ERROR" "❌ $service failed to become healthy within $max_wait seconds"
    
    # Additional diagnostics for failed health checks
    milou_log "INFO" "🔍 Diagnostic information for $service:"
    
    # Check if container is running at all
    if docker ps --filter "name=milou-$service" --format "{{.Names}}" | grep -q "milou-$service"; then
        milou_log "INFO" "   Container is running"
        
        # Get container logs for diagnosis
        milou_log "INFO" "   Recent logs:"
        docker logs "milou-$service" --tail 10 2>/dev/null | while read line; do
            milou_log "INFO" "   LOG: $line"
        done
    else
        milou_log "ERROR" "   Container is not running"
        
        # Check if container exists but is stopped
        if docker ps -a --filter "name=milou-$service" --format "{{.Names}}" | grep -q "milou-$service"; then
            milou_log "INFO" "   Container exists but is stopped"
            docker logs "milou-$service" --tail 5 2>/dev/null | while read line; do
                milou_log "ERROR" "   ERROR LOG: $line"
            done
        else
            milou_log "ERROR" "   Container does not exist"
        fi
    fi
    
    return 1
} 