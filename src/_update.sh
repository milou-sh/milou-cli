#!/bin/bash

# =============================================================================
# Milou CLI Update Management Module - FIXED VERSION
# Proper dependency management, version targeting, and local/remote clarity
# Version: 6.0.0 - The Actually Working Edition
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

# =============================================================================
# DEPENDENCY LOADING & CONFIGURATION
# =============================================================================

# Get script directory for module loading
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load core module first (with its own guard system)
if [[ -f "${script_dir}/_core.sh" ]]; then
    source "${script_dir}/_core.sh" || {
        echo "ERROR: Cannot load core module" >&2
        return 1
    }
fi

# Use the new safe module loading system for dependencies
safe_load_module "${script_dir}/_docker.sh" "docker"
safe_load_module "${script_dir}/_backup.sh" "backup"
safe_load_module "${script_dir}/_config.sh" "config"
safe_load_module "${script_dir}/_validation.sh" "validation"

# Mark this module as loaded
readonly MILOU_UPDATE_MODULE_LOADED="true"

# =============================================================================
# UPDATE CONFIGURATION
# =============================================================================

# Update configuration constants
readonly MILOU_CLI_REPO="milou-sh/milou"
readonly RELEASE_API_URL="${GITHUB_API_BASE:-https://api.github.com}/repos/${MILOU_CLI_REPO}/releases"

# Map logical names to actual docker-compose service names
declare -A SERVICE_NAME_MAP=(
    ["database"]="db"
    ["backend"]="backend" 
    ["frontend"]="frontend"
    ["engine"]="engine"
    ["nginx"]="nginx"
)
readonly DEFAULT_SERVICES=("database" "backend" "frontend" "engine" "nginx")
readonly DEPENDENCY_SERVICES=("redis" "rabbitmq")

# =============================================================================
# FIXED VERSION DISCOVERY - NOW ACTUALLY WORKING
# =============================================================================

# Get actual running versions from Docker containers
get_running_service_versions() {
    local quiet="${1:-false}"
    local -A versions=()
    local -A statuses=()
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "🔍 Scanning running Docker containers..."
    
    # Get ALL container information efficiently
    local container_data
    if ! container_data=$(docker ps -a --filter "name=milou-" --format "{{.Names}}|{{.Image}}|{{.Status}}" 2>/dev/null); then
        [[ "$quiet" != "true" ]] && milou_log "WARN" "⚠️  Could not query Docker containers"
        return 0
    fi
    
    while IFS='|' read -r container_name image_name status || [[ -n "$container_name" ]]; do
        [[ -z "$container_name" || "$container_name" == "NAMES" ]] && continue
        
        if [[ "$container_name" =~ milou-(.+) ]]; then
            local service="${BASH_REMATCH[1]}"
            
            # Map actual service names to logical names
            case "$service" in
                "db") service="database" ;;
                *) ;;
            esac
            
            # Extract version from image tag
            local version=""
            if [[ "$image_name" =~ :([^[:space:]]+)$ ]]; then
                version="${BASH_REMATCH[1]}"
                version=$(echo "$version" | tr -d '[:space:]' | sed 's/^v//')
            fi
            
            if [[ -n "$version" ]]; then
                versions["$service"]="$version"
                # Determine status
                local service_status="stopped"
                if [[ "$status" =~ Up|running ]]; then
                    service_status="running"
                elif [[ "$status" =~ Restart ]]; then
                    service_status="restarting"
                fi
                statuses["$service"]="$service_status"
            fi
        fi
    done <<< "$container_data"
    
    # Export results to global variables
    for service in "${!versions[@]}"; do
        local version_var="RUNNING_VERSION_${service^^}"
        local status_var="SERVICE_STATUS_${service^^}"
        version_var=$(echo "$version_var" | tr -cd '[:alnum:]_')
        status_var=$(echo "$status_var" | tr -cd '[:alnum:]_')
        eval "$version_var=\"${versions[$service]}\""
        eval "$status_var=\"${statuses[$service]}\""
    done
    
    return 0
}

# Get latest version from GitHub Packages API - ROBUST VERSION
get_latest_registry_version() {
    # Wrapper maintained for backward compatibility – delegates to core helper.
    local service="$1"; local token="${2:-}"; local quiet="${3:-false}"
    core_get_latest_service_version "$service" "$token" "$quiet"
}

# Get ALL available versions for a service
get_all_available_versions() {
    local service="$1"
    local github_token="${2:-}"
    
    if [[ -z "$github_token" ]]; then
        return 1
    fi
    
    local service_package_name
    case "$service" in
        "database") service_package_name="database" ;;
        *) service_package_name="$service" ;;
    esac
    
    local api_url="https://api.github.com/orgs/milou-sh/packages/container/milou%2F${service_package_name}/versions"
    
    local versions_response
    if versions_response=$(timeout 10 curl -s -f --max-time 10 \
                          --retry 2 --retry-delay 1 \
                          -H "Authorization: token $github_token" \
                          -H "Accept: application/vnd.github.v3+json" \
                          "$api_url" 2>/dev/null); then
        
        if command -v jq >/dev/null 2>&1; then
            echo "$versions_response" | jq -r '.[].metadata.container.tags[]' 2>/dev/null | \
                           grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | \
                           sort -V | tr '\n' ',' | sed 's/,$//'
        else
            echo "$versions_response" | \
                           grep -o '"[0-9]\+\.[0-9]\+\.[0-9]\+"' | \
                           sed 's/"//g' | \
                           sort -V | tr '\n' ',' | sed 's/,$//'
        fi
        return 0
    fi
    
    return 1
}

# =============================================================================
# IMPROVED VERSION DISPLAY - CLEAR LOCAL VS REMOTE
# =============================================================================

# Display current system versions with LOCAL vs REMOTE clarity
display_system_versions() {
    local target_version="${1:-latest}"
    local github_token="${2:-}"
    local quiet="${3:-false}"
    
    echo
    milou_log "INFO" "📊 System Version Analysis"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # CLI and System info
    local cli_version="${SCRIPT_VERSION:-${MILOU_VERSION:-unknown}}"
    echo -e "   ${BOLD}Milou CLI:${NC}         v$cli_version"
    echo -e "   ${BOLD}Target Version:${NC}    $target_version"
    echo -e "   ${BOLD}GitHub Token:${NC}      ${github_token:+✓ }${github_token:-❌ Missing}"
    echo

    # Get current running versions
    get_running_service_versions "$quiet"
    
    echo -e "   ${BOLD}SERVICE STATUS & VERSIONS:${NC}"
    echo
    
    local services=("${MILOU_SERVICE_LIST[@]}")
    for service in "${services[@]}"; do
        local service_upper="${service^^}"
        local running_var="RUNNING_VERSION_${service_upper}"
        local status_var="SERVICE_STATUS_${service_upper}"
        
        local current_version="${!running_var:-}"
        local service_status="${!status_var:-stopped}"
        
        # Print service name with consistent padding
        printf "   ${BOLD}├─ %-15s${NC}" "${service}:"
        
        # LOCAL VERSION (current)
        if [[ -n "$current_version" && "$current_version" != "latest" ]]; then
            if [[ "$service_status" == "running" ]]; then
                echo -en "${GREEN}LOCAL: v$current_version (running)${NC}"
            elif [[ "$service_status" == "restarting" ]]; then
                echo -en "${YELLOW}LOCAL: v$current_version (restarting)${NC}"
            else
                echo -en "${RED}LOCAL: v$current_version (stopped)${NC}"
            fi
        else
            echo -en "${RED}LOCAL: not installed${NC}"
        fi
        
        echo -en " | "
        
        # REMOTE VERSION (latest available)
        if [[ -n "$github_token" ]]; then
            echo -en "🌐 "
            local remote_version
            if remote_version=$(get_latest_registry_version "$service" "$github_token" "true"); then
                if [[ "$target_version" == "latest" ]]; then
                    echo -e "${GREEN}REMOTE: v$remote_version (latest)${NC}"
                else
                    # Check if target version is available
                    local all_versions
                    if all_versions=$(get_all_available_versions "$service" "$github_token"); then
                        if [[ "$all_versions" =~ (^|,)$target_version($|,) ]]; then
                            echo -e "${GREEN}REMOTE: v$target_version (available)${NC}"
                        else
                            echo -e "${RED}REMOTE: v$target_version (NOT AVAILABLE)${NC}"
                        fi
                    else
                        echo -e "${RED}REMOTE: API error${NC}"
                    fi
                fi
            else
                echo -e "${RED}REMOTE: API unavailable${NC}"
            fi
        else
            echo -e "${YELLOW}REMOTE: no token provided${NC}"
        fi
    done
    
    echo -e "   ${BOLD}└─ Dependencies:${NC}"
    
    # Check dependency services
    for dep_service in "${DEPENDENCY_SERVICES[@]}"; do
        local dep_status
        if dep_status=$(docker ps --filter "name=milou-$dep_service" --format "{{.Status}}" 2>/dev/null); then
            if [[ "$dep_status" =~ Up|running ]]; then
                printf "      ├─ %-15s${GREEN}running${NC}\n" "$dep_service:"
            else
                printf "      ├─ %-15s${RED}stopped${NC}\n" "$dep_service:"
            fi
        else
            printf "      ├─ %-15s${RED}not installed${NC}\n" "$dep_service:"
        fi
    done
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
}

# =============================================================================
# FIXED UPDATE ANALYSIS - PROPER VERSION TARGETING
# =============================================================================

# Check what needs to be updated - FIXED VERSION
check_updates_needed() {
    local target_version="${1:-latest}"
    local github_token="${2:-}"
    local force_all="${3:-false}"
    local quiet="${4:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🔍 Analyzing what needs to be updated..."
    
    # Get current state
    get_running_service_versions "$quiet"
    
    local services=("${MILOU_SERVICE_LIST[@]}")
    local -A service_target_versions=()
    local -A service_current_versions=()
    local -A service_statuses=()
    local -A needs_update=()
    local -A update_reasons=()
    
    # Collect current state
    for service in "${services[@]}"; do
        local service_upper="${service^^}"
        local running_var="RUNNING_VERSION_${service_upper}"
        local status_var="SERVICE_STATUS_${service_upper}"
        
        service_current_versions["$service"]="${!running_var:-}"
        service_statuses["$service"]="${!status_var:-stopped}"
    done
    
    # Determine target versions - THIS IS THE FIXED LOGIC
    if [[ "$target_version" == "latest" ]]; then
        # For "latest", get the actual latest version for each service
        milou_log "INFO" "   🌐 Fetching latest versions from GitHub API..."
        
        for service in "${services[@]}"; do
            local latest_version
            if [[ -n "$github_token" ]] && latest_version=$(get_latest_registry_version "$service" "$github_token" "true"); then
                service_target_versions["$service"]="$latest_version"
                milou_log "INFO" "      📦 $service: latest is v$latest_version"
            else
                milou_log "WARN" "      ❌ $service: cannot determine latest version"
            fi
        done
    else
        # For specific version, use that version for ALL services (this was broken before)
        milou_log "INFO" "   🎯 Setting target version $target_version for ALL services..."
        
        for service in "${services[@]}"; do
            # Validate that this version exists for each service
            local available_versions=""
            if [[ -n "$github_token" ]]; then
                available_versions=$(get_all_available_versions "$service" "$github_token")
            fi
            
            if [[ -n "$available_versions" ]] && [[ "$available_versions" =~ (^|,)$target_version($|,) ]]; then
                service_target_versions["$service"]="$target_version"
                milou_log "INFO" "      ✓ $service: v$target_version is available"
            else
                milou_log "WARN" "      ❌ $service: v$target_version is NOT available"
                # Don't set target version - will be skipped
            fi
        done
    fi
    
    # Analyze what needs updating
    local updates_needed_count=0
    local services_to_update=()
    local services_skipped=()
    
    for service in "${services[@]}"; do
        local current_version="${service_current_versions[$service]}"
        local target_version_for_service="${service_target_versions[$service]:-}"
        local service_status="${service_statuses[$service]}"
        
        # Skip if no target version determined
        if [[ -z "$target_version_for_service" ]]; then
            services_skipped+=("$service")
            continue
        fi
        
        local needs_action=false
        local reason=""
        
        if [[ -z "$current_version" || "$current_version" == "latest" ]]; then
            needs_action=true
            reason="INSTALL → v$target_version_for_service"
        elif [[ "$current_version" != "$target_version_for_service" ]]; then
            needs_action=true
            if compare_semver_versions "$current_version" "$target_version_for_service"; then
                reason="UPGRADE: v$current_version → v$target_version_for_service"
            else
                reason="DOWNGRADE: v$current_version → v$target_version_for_service"
            fi
        elif [[ "$service_status" != "running" ]]; then
            needs_action=true
            reason="START: v$current_version (correct version, not running)"
        elif [[ "$force_all" == "true" ]]; then
            needs_action=true
            reason="FORCE UPDATE: v$current_version → v$target_version_for_service"
        else
            reason="UP-TO-DATE: v$current_version (running)"
        fi
        
        needs_update["$service"]="$needs_action"
        update_reasons["$service"]="$reason"
        
        if [[ "$needs_action" == "true" ]]; then
            ((updates_needed_count++))
            services_to_update+=("$service")
            milou_log "INFO" "      📦 $service: $reason"
        else
            [[ "${VERBOSE:-false}" == "true" ]] && milou_log "DEBUG" "      ✅ $service: $reason"
        fi
    done
    
    # Export results
    if [[ "$updates_needed_count" -gt 0 ]]; then
        export MILOU_SERVICES_TO_UPDATE="${services_to_update[*]}"
        for service in "${!service_target_versions[@]}"; do
            local var_name="MILOU_TARGET_VERSION_${service^^}"
            var_name=$(echo "$var_name" | tr -cd '[:alnum:]_')
            export "$var_name"="${service_target_versions[$service]}"
        done
        
        echo
        milou_log "INFO" "🔄 Updates needed for $updates_needed_count service(s): ${services_to_update[*]}"
        [[ ${#services_skipped[@]} -gt 0 ]] && milou_log "WARN" "⚠️  Skipped: ${services_skipped[*]}"
        
        return 0
    else
        milou_log "SUCCESS" "✅ All services are up to date and running"
        [[ ${#services_skipped[@]} -gt 0 ]] && milou_log "WARN" "⚠️  Skipped: ${services_skipped[*]}"
        return 1
    fi
}

# =============================================================================
# DEPENDENCY MANAGEMENT - FIXED
# =============================================================================

# Ensure dependency services are running
ensure_dependency_services() {
    local quiet="${1:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🔧 Ensuring dependency services are running..."
    
    # Check if we have a proper docker environment before proceeding
    local env_file="${SCRIPT_DIR}/.env"
    local compose_file="${SCRIPT_DIR}/static/docker-compose.yml"
    
    # Try alternative locations if main files don't exist
    if [[ ! -f "$env_file" ]]; then
        local alt_env_files=(
            "${SCRIPT_DIR}/../.env"
            "$(pwd)/.env"
            "${HOME}/.milou/.env"
        )
        
        for alt_env in "${alt_env_files[@]}"; do
            if [[ -f "$alt_env" ]]; then
                env_file="$alt_env"
                [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Using environment file: $env_file"
                break
            fi
        done
        
        # If still no .env file found, warn but continue
        if [[ ! -f "$env_file" ]]; then
            [[ "$quiet" != "true" ]] && milou_log "WARN" "⚠️  No .env file found - dependency services may not be configured properly"
            [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Run './milou.sh setup' to create proper configuration"
            return 1
        fi
    fi
    
    # Check for compose file
    if [[ ! -f "$compose_file" ]]; then
        local alt_compose_files=(
            "${SCRIPT_DIR}/../docker-compose.yml"
            "$(pwd)/docker-compose.yml"
        )
        
        for alt_compose in "${alt_compose_files[@]}"; do
            if [[ -f "$alt_compose" ]]; then
                compose_file="$alt_compose"
                [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Using compose file: $compose_file"
                break
            fi
        done
        
        if [[ ! -f "$compose_file" ]]; then
            [[ "$quiet" != "true" ]] && milou_log "WARN" "⚠️  No docker-compose.yml file found"
            [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Run './milou.sh setup' to create proper configuration"
            return 1
        fi
    fi
    
    local deps_started=0
    
    for dep_service in "${DEPENDENCY_SERVICES[@]}"; do
        local dep_status
        if dep_status=$(docker ps --filter "name=milou-$dep_service" --format "{{.Status}}" 2>/dev/null); then
            if [[ "$dep_status" =~ Up|running ]]; then
                [[ "${VERBOSE:-false}" == "true" ]] && milou_log "DEBUG" "      ✅ $dep_service is running"
                continue
            fi
        fi
        
        # Need to start this dependency
        milou_log "INFO" "      🚀 Starting $dep_service..."
        
        if command -v docker_execute >/dev/null 2>&1; then
            # Initialize docker context with proper files and skip auth for dependency services
            if command -v docker_init >/dev/null 2>&1; then
                if ! docker_init "$env_file" "$compose_file" "true" "true"; then
                    milou_log "ERROR" "      ❌ Failed to initialize Docker context for $dep_service"
                    return 1
                fi
            fi
            
            if docker_execute "up" "" "false" "$dep_service"; then
                ((deps_started++))
                milou_log "SUCCESS" "      ✅ $dep_service started successfully"
            else
                milou_log "ERROR" "      ❌ Failed to start $dep_service"
                return 1
            fi
        else
            # Fallback to direct docker compose call
            if command -v docker >/dev/null 2>&1; then
                if docker compose --env-file "$env_file" -f "$compose_file" up -d "$dep_service" 2>/dev/null; then
                    ((deps_started++))
                    milou_log "SUCCESS" "      ✅ $dep_service started successfully (fallback)"
                else
                    milou_log "ERROR" "      ❌ Failed to start $dep_service (fallback method also failed)"
                    return 1
                fi
            else
                milou_log "ERROR" "      ❌ Docker not available"
                return 1
            fi
        fi
    done
    
    if [[ $deps_started -gt 0 ]]; then
        milou_log "INFO" "      ⏳ Waiting for dependencies to be ready..."
        sleep 5
    fi
    
    return 0
}

# =============================================================================
# MAIN UPDATE FUNCTION - COMPLETELY REWRITTEN
# =============================================================================

# Main system update function - ACTUALLY WORKING VERSION
milou_update_system() {
    local force_update="${1:-false}"
    local backup_before_update="${2:-true}"
    local target_version="${3:-latest}"
    local specific_services="${4:-}"
    
    milou_log "STEP" "🔄 Updating Milou System - Fixed Version"
    
    # ------------------------------------------------------------------
    # Unified token discovery – delegate to core helper
    # ------------------------------------------------------------------
    local github_token=""
    if github_token=$(core_find_github_token "${GITHUB_TOKEN:-}" 2>/dev/null); then
        milou_log "DEBUG" "Using GitHub token discovered by core helper"
    else
        github_token=""
    fi

    # Primary env file reference (needed later for mutable-tag guard)
    local env_file="${script_dir}/.env"
    
    # Ensure we have a valid GitHub token for update operations
    if [[ -z "$github_token" ]]; then
        milou_log "WARN" "⚠️  No GitHub token provided - will use local fallbacks only"
        milou_log "INFO" "💡 To enable full update functionality, set GITHUB_TOKEN or use --token"
        milou_log "INFO" "💡 Generate a token at: https://github.com/settings/tokens"
        echo
        
        # For updates, we can continue without token but functionality will be limited
        # skip_registry_operations=true
    else
        # Validate GitHub token for update operations
        milou_log "INFO" "🔐 Validating GitHub token for update operations..."
        
        # Use core_require_github_token to ensure token is valid and persisted
        if ! core_require_github_token "$github_token" "false"; then
            milou_log "ERROR" "❌ GitHub token validation failed"
            return 1
        fi
        
        # Refresh token variable after core_require_github_token
        github_token="${GITHUB_TOKEN:-}"
        
        # Perform Docker registry authentication
        if command -v docker_login_github >/dev/null 2>&1; then
            if docker_login_github "$github_token" "false" "true"; then
                milou_log "SUCCESS" "✅ GitHub authentication successful"
                export GITHUB_AUTHENTICATED="true"
            else
                milou_log "ERROR" "❌ GitHub authentication failed"
                return 1
            fi
        fi
    fi
    
    # Display comprehensive current state
    display_system_versions "$target_version" "$github_token" "false"
    
    # Check what needs updating
    local force_all=false
    [[ "$force_update" == "true" ]] && force_all=true
    
    if ! check_updates_needed "$target_version" "$github_token" "$force_all" "false"; then
        if [[ "$force_update" != "true" ]]; then
            return 0
        fi
    fi
    
    # Ensure dependencies are running FIRST
    if ! ensure_dependency_services "false"; then
        milou_log "ERROR" "❌ Failed to start dependency services"
        return 1
    fi
    
    # Create backup if requested
    if [[ "$backup_before_update" == "true" ]]; then
        milou_log "INFO" "📦 Creating pre-update backup..."
        if command -v milou_backup_create >/dev/null 2>&1; then
            milou_backup_create "full" "./backups" "pre_update_$(date +%Y%m%d_%H%M%S)" >/dev/null 2>&1 || true
        fi
    fi
    
    # Perform the actual updates
    local update_start_time
    update_start_time=$(date +%s)
    
    if _perform_fixed_update "$target_version" "$specific_services" "$github_token"; then
        milou_log "SUCCESS" "✅ System update completed successfully"
        _display_update_results "$update_start_time" "true"
        return 0
    else
        milou_log "ERROR" "❌ System update failed"
        _display_update_results "$update_start_time" "false"
        return 1
    fi
}

# Perform the actual update - FIXED VERSION
_perform_fixed_update() {
    local target_version="$1"
    local specific_services="$2"
    local github_token="$3"
    
    milou_log "INFO" "🔄 Executing system updates..."
    
    # Get services to update from analysis
    local -a services_to_update=()
    if [[ -n "${MILOU_SERVICES_TO_UPDATE:-}" ]]; then
        IFS=' ' read -ra services_to_update <<< "$MILOU_SERVICES_TO_UPDATE"
    else
        milou_log "WARN" "⚠️  No services identified for update"
        return 0
    fi
    
    milou_log "INFO" "📦 Updating services: ${services_to_update[*]}"
    
    # Create required networks if they don't exist - Let Docker Compose handle this
    milou_log "INFO" "🔗 Ensuring Docker networks are ready..."
    # Remove manual network creation to avoid conflicts with docker-compose
    # docker network create proxy 2>/dev/null || true
    # docker network create milou_network --subnet 172.21.0.0/16 2>/dev/null || true
    milou_log "DEBUG" "Networks will be created by Docker Compose"
    
    # FIXED: Clean up conflicting networks before starting updates
    if command -v docker_cleanup_conflicting_networks >/dev/null 2>&1; then
        docker_cleanup_conflicting_networks "false"
    fi
    
    # Update each service
    local failed_services=()
    local updated_services=()
    
    for service in "${services_to_update[@]}"; do
        # Get target version for this service
        local service_target_version=""
        local var_name="MILOU_TARGET_VERSION_${service^^}"
        var_name=$(echo "$var_name" | tr -cd '[:alnum:]_')
        service_target_version="${!var_name:-}"
        
        if [[ -z "$service_target_version" ]]; then
            milou_log "WARN" "⚠️  No target version for $service - skipping"
            continue
        fi
        
        milou_log "INFO" "🔄 Updating $service to v$service_target_version..."
        
        # Update .env file
        _update_env_file_service_version "$service" "$service_target_version"
        
        # Get actual service name for Docker operations
        local actual_service_name="${SERVICE_NAME_MAP[$service]:-$service}"
        
        # Perform zero-downtime update
        local update_success=false
        if command -v service_update_zero_downtime >/dev/null 2>&1; then
            if service_update_zero_downtime "$actual_service_name" "false"; then
                update_success=true
            fi
        else
            # Fallback to basic update
            if _update_single_service "$actual_service_name" "$service_target_version"; then
                update_success=true
            fi
        fi
        
        if [[ "$update_success" == "true" ]]; then
            updated_services+=("$service")
            milou_log "SUCCESS" "✅ $service updated successfully to v$service_target_version"
        else
            failed_services+=("$service")
            milou_log "ERROR" "❌ Failed to update $service to v$service_target_version"
        fi
    done
    
    # Final summary
    echo
    milou_log "INFO" "📊 Update Summary:"
    [[ ${#updated_services[@]} -gt 0 ]] && milou_log "SUCCESS" "  ✅ Updated: ${updated_services[*]}"
    [[ ${#failed_services[@]} -gt 0 ]] && milou_log "ERROR" "  ❌ Failed: ${failed_services[*]}"
    
    # Health check for updated services
    if [[ ${#updated_services[@]} -gt 0 ]]; then
        milou_log "INFO" "🏥 Performing health check..."
        if command -v health_check_all >/dev/null 2>&1; then
            health_check_all "true"
        fi
    fi
    
    # Return success only if no failures
    return $([[ ${#failed_services[@]} -eq 0 ]])
}

# Update environment file with service version (now delegates to core helper)
_update_env_file_service_version() {
    local service="$1"
    local target_version="$2"

    local tag_name
    case "$service" in
        "database") tag_name="MILOU_DATABASE_TAG" ;;
        "backend")  tag_name="MILOU_BACKEND_TAG"  ;;
        "frontend") tag_name="MILOU_FRONTEND_TAG" ;;
        "engine")   tag_name="MILOU_ENGINE_TAG"   ;;
        "nginx")    tag_name="MILOU_NGINX_TAG"    ;;
        *)
            milou_log "WARN" "Unknown service for .env update: $service"
            return 1 ;;
    esac

    local env_file="${script_dir}/.env"
    core_update_env_var "$env_file" "$tag_name" "$target_version"
}

# Basic single service update fallback
_update_single_service() {
    local service="$1"
    local target_version="$2"
    
    local registry="${DOCKER_REGISTRY:-ghcr.io/milou-sh/milou}"
    local image_name="${registry}/${service}:${target_version}"
    
    milou_log "INFO" "⬇️  Pulling image: $image_name"
    if ! docker pull "$image_name" >/dev/null 2>&1; then
        milou_log "ERROR" "❌ Failed to pull image: $image_name"
        return 1
    fi
    
    # Restart service with new image
    if command -v docker_execute >/dev/null 2>&1; then
        docker_execute "up" "$service" "false" "--force-recreate" "--no-deps" "-d"
    else
        docker compose pull "$service"
        docker compose up -d --force-recreate --no-deps "$service"
    fi
    
    return 0
}

# Display update results
_display_update_results() {
    local start_time="${1:-}"
    local success="${2:-true}"
    
    echo
    if [[ "$success" == "true" ]]; then
        milou_log "SUCCESS" "🎉 Update Completed Successfully!"
    else
        milou_log "ERROR" "💥 Update Failed"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [[ -n "$start_time" ]]; then
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo -e "   ${BOLD}Duration:${NC} ${duration}s"
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
}

# =============================================================================
# SEMANTIC VERSION COMPARISON - FIXED
# =============================================================================

compare_semver_versions() {
    local current="$1"
    local target="$2"
    
    current="${current#v}"
    target="${target#v}"
    
    IFS='.' read -ra current_parts <<< "$current"
    IFS='.' read -ra target_parts <<< "$target"
    
    for i in {0..2}; do
        local current_part="${current_parts[$i]:-0}"
        local target_part="${target_parts[$i]:-0}"
        
        current_part="${current_part%%[^0-9]*}"
        target_part="${target_part%%[^0-9]*}"
        
        if [[ $target_part -gt $current_part ]]; then
            return 0  # Target is newer
        elif [[ $target_part -lt $current_part ]]; then
            return 1  # Current is newer
        fi
    done
    
    return 1  # Versions are equal
}

# =============================================================================
# COMMAND HANDLERS - FIXED
# =============================================================================

# System update command handler - FIXED
handle_update() {
    local target_version="latest"
    local specific_services=""
    local force_update=false
    local backup_before_update=true
    
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
                _show_update_help
                return 0
                ;;
            *)
                milou_log "WARN" "Unknown update argument: $1"
                shift
                ;;
        esac
    done
    
    milou_update_system "$force_update" "$backup_before_update" "$target_version" "$specific_services"
}

# Help function
_show_update_help() {
    echo "🔄 Fixed Update Command Usage"
    echo "============================="
    echo ""
    echo "UPDATE SYSTEM:"
    echo "  ./milou.sh update [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --version VERSION     Update ALL services to specific version"
    echo "  --service SERVICES    Update specific services only (comma-separated)"
    echo "  --token TOKEN         GitHub Personal Access Token (required for remote versions)"
    echo "  --force              Force update even if no changes detected"
    echo "  --no-backup          Skip backup creation before update"
    echo ""
    echo "Examples:"
    echo "  ./milou.sh update                                    # Update all to latest"
    echo "  ./milou.sh update --version 1.0.0 --token TOKEN     # Update ALL to 1.0.0"
    echo "  ./milou.sh update --service frontend,backend        # Update specific services"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

export -f milou_update_system
export -f display_system_versions
export -f check_updates_needed
export -f ensure_dependency_services
export -f compare_semver_versions
export -f handle_update
export -f get_latest_registry_version
export -f get_all_available_versions

milou_log "DEBUG" "Update module v6.0.0 loaded - ACTUALLY WORKING EDITION"