#!/bin/bash

# =============================================================================
# Milou CLI Update Management Module
# Professional consolidation of all update-related functionality
# Version: 4.0.0 - Refactored and Optimized Edition
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
# DEPENDENCY LOADING & CONFIGURATION
# =============================================================================

# Ensure core modules are loaded
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for module in "_core.sh" "_docker.sh" "_backup.sh" "_config.sh" "_validation.sh"; do
    if [[ -f "${script_dir}/${module}" ]]; then
        source "${script_dir}/${module}" || {
            echo "ERROR: Cannot load required module: $module" >&2
            return 1
        }
    fi
done

# Update configuration constants - FIXED SERVICE NAMES
readonly MILOU_CLI_REPO="milou-sh/milou-cli"
readonly RELEASE_API_URL="${GITHUB_API_BASE:-https://api.github.com}/repos/${MILOU_CLI_REPO}/releases"
# CRITICAL FIX: Map logical names to actual docker-compose service names
declare -A SERVICE_NAME_MAP=(
    ["database"]="db"
    ["backend"]="backend" 
    ["frontend"]="frontend"
    ["engine"]="engine"
    ["nginx"]="nginx"
)
readonly DEFAULT_SERVICES=("database" "backend" "frontend" "engine" "nginx")

# =============================================================================
# VERSION DISPLAY AND MANAGEMENT - CONSOLIDATED
# =============================================================================

# Display comprehensive current system version information - ENHANCED
display_current_versions() {
    local quiet="${1:-false}"
    local target_version="${2:-latest}"
    
    if [[ "$quiet" != "true" ]]; then
        echo
        milou_log "INFO" "📊 Current System Version Information"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
    
    # CLI and System Version
    local cli_version="${SCRIPT_VERSION:-${MILOU_VERSION:-unknown}}"
    local system_version="${MILOU_VERSION:-latest}"
    echo -e "   ${BOLD}Milou CLI:${NC}     v$cli_version"
    echo -e "   ${BOLD}System:${NC}        v$system_version"
    
    echo
    echo -e "   ${BOLD}Service Versions:${NC}"
    
    # Get running container versions with ACTUAL version tags
    local -A running_versions=()
    local -A container_status=()
    
    # Enhanced Docker inspection to get real version tags
    while IFS='|' read -r container_name image_name status; do
        [[ -z "$container_name" || "$container_name" == "NAMES" ]] && continue
        
        if [[ "$container_name" =~ milou-(.+) ]]; then
            local service="${BASH_REMATCH[1]}"
            # Map actual service names back to logical names
            case "$service" in
                "database") service="database" ;;
                *) ;;
            esac
            
            local version=""
            if [[ "$image_name" =~ :([^[:space:]]+)$ ]]; then
                version="${BASH_REMATCH[1]}"
                # If it's latest, try to get the actual digest-based version
                if [[ "$version" == "latest" ]]; then
                    local image_id
                    image_id=$(docker images --format "table {{.Repository}}:{{.Tag}}\t{{.ID}}" | grep "$image_name" | head -1 | awk '{print $2}')
                    if [[ -n "$image_id" ]]; then
                        # Try to get version from image labels
                        local label_version
                        label_version=$(docker inspect "$image_id" --format '{{index .Config.Labels "version"}}' 2>/dev/null || echo "")
                        [[ -n "$label_version" && "$label_version" != "<no value>" ]] && version="$label_version"
                    fi
                fi
                version="${version#v}"  # Remove 'v' prefix if present
            fi
            running_versions["$service"]="$version"
            container_status["$service"]=$([[ "$status" =~ ^Up|running ]] && echo "running" || echo "stopped")
        fi
    done < <(docker ps -a --filter "name=milou-" --format "{{.Names}}|{{.Image}}|{{.Status}}" 2>/dev/null)
    
    # Get configured versions from environment using Config module
    local -A configured_versions=()
    if command -v config_get_env_variable >/dev/null 2>&1; then
        local env_file="${SCRIPT_DIR}/.env"
        if [[ -f "$env_file" ]]; then
            configured_versions["database"]=$(config_get_env_variable "$env_file" "MILOU_DATABASE_TAG" "1.0.0")
            configured_versions["backend"]=$(config_get_env_variable "$env_file" "MILOU_BACKEND_TAG" "1.0.0")
            configured_versions["frontend"]=$(config_get_env_variable "$env_file" "MILOU_FRONTEND_TAG" "1.0.0")
            configured_versions["engine"]=$(config_get_env_variable "$env_file" "MILOU_ENGINE_TAG" "1.0.0")
            configured_versions["nginx"]=$(config_get_env_variable "$env_file" "MILOU_NGINX_TAG" "1.0.0")
        fi
    else
        # Fallback to manual parsing
        source "${SCRIPT_DIR}/.env" 2>/dev/null || true
        configured_versions["database"]="${MILOU_DATABASE_TAG:-1.0.0}"
        configured_versions["backend"]="${MILOU_BACKEND_TAG:-1.0.0}"
        configured_versions["frontend"]="${MILOU_FRONTEND_TAG:-1.0.0}"
        configured_versions["engine"]="${MILOU_ENGINE_TAG:-1.0.0}"
        configured_versions["nginx"]="${MILOU_NGINX_TAG:-1.0.0}"
    fi
    
    # Get latest available version for comparison
    local latest_available=""
    if [[ "$target_version" == "latest" ]]; then
        latest_available=$(detect_latest_version "" 2>/dev/null || echo "unknown")
    else
        latest_available="$target_version"
    fi
    
    # Display service versions with enhanced comparison
    local services=("database" "backend" "frontend" "engine" "nginx")
    for service in "${services[@]}"; do
        local current_version="${running_versions[$service]:-}"
        local configured_version="${configured_versions[$service]:-}"
        local status="${container_status[$service]:-}"
        
        # Clean up version strings
        current_version="${current_version#v}"
        configured_version="${configured_version#v}"
        latest_available="${latest_available#v}"
        
        if [[ -n "$current_version" && "$current_version" != "unknown" && "$current_version" != "latest" ]]; then
            local display_current=$(_format_version_for_display "$current_version")
            if [[ "$status" == "running" ]]; then
                # Compare with latest available
                if [[ -n "$latest_available" && "$latest_available" != "unknown" ]]; then
                    if compare_semver_versions "$current_version" "$latest_available"; then
                        echo -e "   ${BOLD}├─ ${service}:${NC}      ${YELLOW}$display_current${NC} ${DIM}(update to v$latest_available available)${NC}"
                    else
                        echo -e "   ${BOLD}├─ ${service}:${NC}      ${GREEN}$display_current${NC} ${DIM}(running, up to date)${NC}"
                    fi
                else
                    echo -e "   ${BOLD}├─ ${service}:${NC}      ${GREEN}$display_current${NC} ${DIM}(running)${NC}"
                fi
            else
                echo -e "   ${BOLD}├─ ${service}:${NC}      ${RED}$display_current${NC} ${DIM}(stopped)${NC}"
            fi
        else
            local display_version=$(_format_version_for_display "$configured_version")
            if [[ -n "$latest_available" && "$latest_available" != "unknown" ]]; then
                echo -e "   ${BOLD}├─ ${service}:${NC}      ${RED}$display_version${NC} ${DIM}(not running, latest: v$latest_available)${NC}"
            else
                echo -e "   ${BOLD}├─ ${service}:${NC}      ${RED}$display_version${NC} ${DIM}(not running)${NC}"
            fi
        fi
    done
    
    echo -e "   ${BOLD}└─ Last Updated:${NC} $(get_last_update_timestamp)"
    
    if [[ "$quiet" != "true" ]]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo
    fi
}

# Helper function to format version for display
_format_version_for_display() {
    local version="$1"
    
    if [[ -z "$version" ]]; then
        echo "unknown"
    elif [[ "$version" == "latest" ]]; then
        echo "latest"
    else
        version="${version#v}"
        if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
            echo "v$version"
        else
            echo "$version"
        fi
    fi
}

# Get last update timestamp from system
get_last_update_timestamp() {
    local last_backup
    last_backup=$(find ./backups -name "pre_update_*" -type f 2>/dev/null | sort | tail -1)
    
    if [[ -n "$last_backup" && "$last_backup" =~ pre_update_([0-9]{8}_[0-9]{6}) ]]; then
        local timestamp="${BASH_REMATCH[1]}"
        local date_part="${timestamp%_*}"
        local time_part="${timestamp#*_}"
        echo "${date_part:0:4}-${date_part:4:2}-${date_part:6:2} ${time_part:0:2}:${time_part:2:2}:${time_part:4:2}"
    else
        local newest_container
        newest_container=$(docker ps --filter "name=milou-" --format "table {{.CreatedAt}}" 2>/dev/null | tail -n +2 | sort | tail -1)
        echo "${newest_container:-Never updated}"
    fi
}

# =============================================================================
# SEMANTIC VERSION MANAGEMENT - CONSOLIDATED
# =============================================================================

# Semantic version comparison - enhanced implementation
compare_semver_versions() {
    local current="$1"
    local target="$2"
    
    # Remove 'v' prefix if present
    current="${current#v}"
    target="${target#v}"
    
    # Split versions into parts
    IFS='.' read -ra current_parts <<< "$current"
    IFS='.' read -ra target_parts <<< "$target"
    
    # Compare each part
    for i in {0..2}; do
        local current_part="${current_parts[$i]:-0}"
        local target_part="${target_parts[$i]:-0}"
        
        # Remove non-numeric suffixes
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

# Detect latest available version using Config module
detect_latest_version() {
    local github_token="${1:-}"
    
    milou_log "DEBUG" "Detecting latest version..."
    
    # Use Config module's version detection if available
    if command -v config_detect_latest_version >/dev/null 2>&1; then
        local latest_version
        latest_version=$(config_detect_latest_version "$github_token" "false")
        if [[ -n "$latest_version" && "$latest_version" != "v1.0.0" ]]; then
            echo "${latest_version#v}"
            return 0
        fi
    fi
    
    # Fallback implementation
    local latest_version=""
    if command -v curl >/dev/null 2>&1; then
        local auth_header=""
        [[ -n "$github_token" ]] && auth_header="Authorization: Bearer $github_token"
        
        local response
        response=$(curl -s ${auth_header:+-H "$auth_header"} \
                   "https://api.github.com/repos/milou-sh/milou-cli/releases/latest" 2>/dev/null)
        
        if [[ -n "$response" ]]; then
            if command -v jq >/dev/null 2>&1; then
                latest_version=$(echo "$response" | jq -r '.tag_name // empty' 2>/dev/null)
            else
                latest_version=$(echo "$response" | grep '"tag_name":' | head -n 1 | cut -d'"' -f4)
            fi
        fi
    fi
    
    # Clean and return version
    latest_version="${latest_version#v}"
    echo "${latest_version:-1.0.1}"
    return 0
}

# =============================================================================
# SYSTEM UPDATE CORE FUNCTIONS - ENHANCED
# =============================================================================

# Enhanced system update with comprehensive integration
milou_update_system() {
    local force_update="${1:-false}"
    local backup_before_update="${2:-true}"
    local target_version="${3:-latest}"
    local specific_services="${4:-}"
    local github_token="${GITHUB_TOKEN:-}"
    
    milou_log "STEP" "🔄 Updating Milou system..."
    
    # Resolve target version if "latest" is specified
    if [[ "$target_version" == "latest" ]]; then
        local resolved_version
        resolved_version=$(detect_latest_version "$github_token")
        if [[ $? -eq 0 && -n "$resolved_version" ]]; then
            target_version="$resolved_version"
            milou_log "INFO" "✅ Latest version resolved to: $target_version"
        fi
    fi
    
    # Display current system state
    display_current_versions "false" "$target_version"
    
    # Validate GitHub token using Docker module
    if [[ -n "$github_token" ]]; then
        milou_log "INFO" "🔐 Testing GitHub authentication..."
        if command -v docker_login_github >/dev/null 2>&1; then
            if docker_login_github "$github_token" "true" "false"; then
                milou_log "SUCCESS" "✅ GitHub authentication successful"
            else
                milou_log "ERROR" "❌ GitHub authentication failed"
                return 1
            fi
        fi
    fi
    
    # Check if update is needed
    if ! check_updates_needed "$target_version" "$github_token" "false"; then
        if [[ "$force_update" != "true" ]]; then
            milou_log "INFO" "✅ All services are already up to date"
            return 0
        fi
    fi
    
    # Create backup before update using Backup module
    if [[ "$backup_before_update" == "true" ]]; then
        milou_log "INFO" "📦 Creating pre-update backup..."
        if command -v milou_backup_create >/dev/null 2>&1; then
            milou_backup_create "full" "./backups" "pre_update_$(date +%Y%m%d_%H%M%S)" >/dev/null
        fi
    fi
    
    # Perform the update
    local update_start_time
    update_start_time=$(date +%s)
    
    local update_result
    if _perform_system_update "$target_version" "$specific_services" "$github_token"; then
        update_result=0
        milou_log "SUCCESS" "✅ System update completed"
        _display_update_results "$target_version" "$specific_services" "$update_start_time" "true"
    else
        update_result=1
        milou_log "ERROR" "❌ System update failed"
        _display_update_results "$target_version" "$specific_services" "$update_start_time" "false"
    fi
    
    return $update_result
}

# Check what needs to be updated - ENHANCED
check_updates_needed() {
    local target_version="${1:-latest}"
    local github_token="${2:-}"
    local quiet="${3:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🔍 Analyzing what needs to be updated..."
    
    target_version="${target_version#v}"
    local -A current_versions=()
    local updates_needed=false
    
    # Get current versions from containers using actual service name mapping
    while IFS=$'\t' read -r container_name image_name; do
        if [[ "$container_name" =~ milou-(.+) ]]; then
            local actual_service="${BASH_REMATCH[1]}"
            # Map back to logical service name for consistency
            local logical_service="$actual_service"
            case "$actual_service" in
                "database") logical_service="database" ;;
                *) ;;
            esac
            
            local version=""
            if [[ "$image_name" =~ :(.+)$ ]]; then
                version="${BASH_REMATCH[1]#v}"
                # Handle latest tag by trying to get actual version
                if [[ "$version" == "latest" ]]; then
                    local image_id
                    image_id=$(docker images --format "table {{.Repository}}:{{.Tag}}\t{{.ID}}" | grep "$image_name" | head -1 | awk '{print $2}')
                    if [[ -n "$image_id" ]]; then
                        local label_version
                        label_version=$(docker inspect "$image_id" --format '{{index .Config.Labels "version"}}' 2>/dev/null || echo "")
                        [[ -n "$label_version" && "$label_version" != "<no value>" ]] && version="$label_version"
                    fi
                    version="${version#v}"
                fi
            fi
            current_versions["$logical_service"]="$version"
        fi
    done < <(docker ps -a --filter "name=milou-" --format "table {{.Names}}\t{{.Image}}" 2>/dev/null | tail -n +2)
    
    # Check if any service needs updating
    local services=("database" "backend" "frontend" "engine" "nginx")
    for service in "${services[@]}"; do
        local current_version="${current_versions[$service]:-unknown}"
        
        # Clean versions for comparison
        local clean_current="${current_version#v}"
        local clean_target="${target_version#v}"
        
        if [[ "$current_version" != "$target_version" && "$clean_current" != "$clean_target" ]]; then
            updates_needed=true
            if [[ "$quiet" != "true" ]]; then
                if [[ "$current_version" == "unknown" || "$current_version" == "" || "$current_version" == "latest" ]]; then
                    milou_log "INFO" "   📦 $service: NEW INSTALLATION → v$target_version"
                else
                    milou_log "INFO" "   📦 $service: v$current_version → v$target_version"
                fi
            fi
        fi
    done
    
    if [[ "$updates_needed" == "true" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "INFO" "🔄 Updates are available"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ All services are up to date"
        return 1
    fi
}

# Perform system update using consolidated functions - ENHANCED
_perform_system_update() {
    local target_version="$1"
    local specific_services="$2"
    local github_token="$3"
    
    milou_log "INFO" "🔄 Performing system update..."
    
    # Parse services to update
    local -a services_to_update=()
    if [[ -n "$specific_services" ]]; then
        IFS=',' read -ra services_to_update <<< "$specific_services"
    else
        services_to_update=("${DEFAULT_SERVICES[@]}")
    fi
    
    # CRITICAL: Ensure required Docker networks exist
    milou_log "INFO" "🌐 Ensuring Docker networks exist..."
    
    # Create proxy network if it doesn't exist
    if ! docker network ls --format "{{.Name}}" | grep -q "^proxy$"; then
        milou_log "INFO" "📡 Creating proxy network..."
        if docker network create proxy 2>/dev/null; then
            milou_log "SUCCESS" "✅ Proxy network created"
        else
            milou_log "WARN" "⚠️  Proxy network may already exist"
        fi
    else
        milou_log "DEBUG" "✅ Proxy network already exists"
    fi
    
    # Create milou_network if it doesn't exist  
    if ! docker network ls --format "{{.Name}}" | grep -q "^milou_network$"; then
        milou_log "INFO" "📡 Creating milou_network..."
        if docker network create milou_network --subnet 172.20.0.0/16 2>/dev/null; then
            milou_log "SUCCESS" "✅ Milou network created"
        else
            milou_log "WARN" "⚠️  Milou network may already exist"
        fi
    else
        milou_log "DEBUG" "✅ Milou network already exists"
    fi
    
    # Initialize Docker environment using Docker module
    if ! docker_init "" "" "false"; then
        milou_log "ERROR" "❌ Docker initialization failed"
        return 1
    fi
    
    # Authenticate if token available
    if [[ -n "$github_token" ]] && command -v docker_login_github >/dev/null 2>&1; then
        docker_login_github "$github_token" "false" "false"
    fi
    
    # Update .env file with target version tags BEFORE starting service updates
    milou_log "INFO" "📝 Updating configuration with target version..."
    _update_env_file_version_tags "$target_version"
    
    # Update services using service lifecycle management
    local failed_services=()
    for service in "${services_to_update[@]}"; do
        milou_log "INFO" "🔄 Updating service: $service"
        
        # Get actual service name from mapping
        local actual_service_name="${SERVICE_NAME_MAP[$service]:-$service}"
        
        # Use consolidated service update from Docker module
        if command -v service_update_zero_downtime >/dev/null 2>&1; then
            if ! service_update_zero_downtime "$actual_service_name" "$target_version" "false"; then
                failed_services+=("$service")
                milou_log "ERROR" "❌ Failed to update $service"
            fi
        else
            # Fallback to basic update with corrected service name
            if ! _update_single_service "$actual_service_name" "$target_version"; then
                failed_services+=("$service")
            fi
        fi
    done
    
    # Final health check using health_check_all from Docker module
    if [[ ${#failed_services[@]} -eq 0 ]]; then
        milou_log "INFO" "🏥 Performing final health check..."
        if command -v health_check_all >/dev/null 2>&1; then
            if health_check_all "true"; then
                milou_log "SUCCESS" "✅ All services updated and healthy"
                return 0
            fi
        fi
    fi
    
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        milou_log "ERROR" "❌ Failed to update services: ${failed_services[*]}"
        return 1
    fi
    
    return 0
}

# Update environment file with new version tags
_update_env_file_version_tags() {
    local target_version="$1"
    local env_file="${SCRIPT_DIR}/.env"
    
    if [[ ! -f "$env_file" ]]; then
        milou_log "ERROR" "❌ Environment file not found: $env_file"
        return 1
    fi
    
    milou_log "INFO" "📝 Updating environment file with version tags..."
    
    # Create backup of .env file
    cp "$env_file" "${env_file}.backup.$(date +%s)"
    
    # Update version tags in .env file
    local services=("DATABASE" "BACKEND" "FRONTEND" "ENGINE" "NGINX")
    for service in "${services[@]}"; do
        local tag_name="MILOU_${service}_TAG"
        
        # Update or add the tag
        if grep -q "^${tag_name}=" "$env_file"; then
            sed -i "s/^${tag_name}=.*/${tag_name}=${target_version}/" "$env_file"
        else
            echo "${tag_name}=${target_version}" >> "$env_file"
        fi
        
        milou_log "DEBUG" "✅ Updated $tag_name to $target_version"
    done
    
    milou_log "SUCCESS" "✅ Environment file updated with version tags"
    return 0
}

# Fallback single service update - ENHANCED
_update_single_service() {
    local service="$1"
    local target_version="$2"
    
    local registry="${DOCKER_REGISTRY:-ghcr.io/milou-sh/milou}"
    local image_name="${registry}/${service}:${target_version}"
    
    milou_log "INFO" "🔄 Updating service $service to version $target_version"
    
    # Pull new image with specific version tag
    milou_log "INFO" "⬇️  Pulling image: $image_name"
    if ! docker pull "$image_name" >/dev/null 2>&1; then
        milou_log "ERROR" "❌ Failed to pull image: $image_name"
        return 1
    fi
    
    # Update .env file with correct version tags
    _update_env_file_version_tags "$target_version"
    
    # Use Docker module for service restart with correct image
    if command -v docker_execute >/dev/null 2>&1; then
        docker_execute "up" "$service" "false" "--force-recreate" "--no-deps" "-d"
    else
        # Force pull the specific version and recreate
        docker compose pull "$service"
        docker compose up -d --force-recreate --no-deps "$service"
    fi
    
    # Verify service is running with correct version
    sleep 5
    local running_image
    running_image=$(docker ps --filter "name=milou-$service" --format "{{.Image}}" 2>/dev/null)
    if [[ "$running_image" == "$image_name" ]]; then
        milou_log "SUCCESS" "✅ Service $service updated to $target_version"
        return 0
    else
        milou_log "ERROR" "❌ Service $service not running with expected image $image_name (running: $running_image)"
        return 1
    fi
}

# =============================================================================
# CLI SELF-UPDATE FUNCTIONS - ENHANCED
# =============================================================================

# Check for new CLI release
milou_self_update_check() {
    local target_version="${1:-latest}"
    
    milou_log "INFO" "🔍 Checking for Milou CLI updates..."
    
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
    
    local release_info
    if ! release_info=$(curl -s -f "$api_url" 2>/dev/null); then
        milou_log "ERROR" "Failed to fetch release information from GitHub"
        return 1
    fi
    
    local remote_version
    remote_version=$(echo "$release_info" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
    
    if [[ -z "$remote_version" ]]; then
        milou_log "ERROR" "Failed to parse release version"
        return 1
    fi
    
    local current_version="${SCRIPT_VERSION:-3.1.0}"
    remote_version="${remote_version#v}"
    current_version="${current_version#v}"
    
    if [[ "$current_version" == "$remote_version" ]]; then
        milou_log "SUCCESS" "✅ Milou CLI is up to date (v$current_version)"
        return 1  # No update needed
    fi
    
    milou_log "INFO" "🆕 Update available: v$current_version → v$remote_version"
    return 0  # Update available
}

# Perform CLI self-update
milou_self_update_perform() {
    local target_version="${1:-latest}"
    local force="${2:-false}"
    
    milou_log "STEP" "🔄 Performing Milou CLI self-update..."
    
    if [[ "$force" != "true" ]] && ! milou_self_update_check "$target_version"; then
        return 0
    fi
    
    # Use standard GitHub release download logic
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
    
    local download_url
    download_url=$(echo "$release_info" | grep '"browser_download_url".*milou\.sh"' | cut -d'"' -f4)
    
    if [[ -z "$download_url" ]]; then
        milou_log "ERROR" "Failed to find download URL"
        return 1
    fi
    
    local temp_script="/tmp/milou_update_$(date +%s).sh"
    local current_script="${SCRIPT_DIR}/milou.sh"
    
    # Download and validate
    if ! curl -L -o "$temp_script" "$download_url"; then
        milou_log "ERROR" "Failed to download new version"
        return 1
    fi
    
    chmod +x "$temp_script"
    
    # Create backup
    local backup_script="${current_script}.backup.$(date +%s)"
    cp "$current_script" "$backup_script"
    
    # Replace current script
    if cp "$temp_script" "$current_script"; then
        chmod +x "$current_script"
        rm -f "$temp_script"
        milou_log "SUCCESS" "✅ Milou CLI updated successfully"
        return 0
    else
        milou_log "ERROR" "❌ Failed to replace current script"
        cp "$backup_script" "$current_script"
        rm -f "$temp_script"
        return 1
    fi
}

# =============================================================================
# UPDATE RESULTS AND STATUS - ENHANCED
# =============================================================================

# Display update results
_display_update_results() {
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
    
    # Calculate duration
    if [[ -n "$start_time" ]]; then
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local minutes=$((duration / 60))
        local seconds=$((duration % 60))
        echo -e "   ${BOLD}Duration:${NC} ${minutes}m ${seconds}s"
    fi
    
    # Show current system state using existing function
    echo -e "   ${BOLD}Updated System State:${NC}"
    display_current_versions "true" "$target_version"
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
}

# Check comprehensive system update status
milou_update_check_status() {
    milou_log "STEP" "📊 Checking system update status..."
    
    # Display current version info
    display_current_versions
    
    # Check for available updates
    milou_log "INFO" "🔍 Checking for available updates..."
    
    # Check CLI updates
    if milou_self_update_check >/dev/null 2>&1; then
        milou_log "INFO" "   🆕 CLI update available! Run 'milou self-update'"
    else
        milou_log "SUCCESS" "   ✅ CLI is up to date"
    fi
    
    # Check service updates
    if check_updates_needed "latest" "" "false"; then
        milou_log "INFO" "   🆕 Service updates available! Run 'milou update'"
    else
        milou_log "SUCCESS" "   ✅ All services are up to date"
    fi
    
    # Show service health using Docker module
    if command -v health_check_all >/dev/null 2>&1; then
        echo
        milou_log "INFO" "🏥 Current Service Health:"
        health_check_all "false"
    fi
}

# =============================================================================
# COMMAND HANDLERS - CONSOLIDATED
# =============================================================================

# System update command handler
handle_update() {
    local target_version=""
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

# CLI self-update command handler
handle_update_cli() {
    local target_version="latest"
    local force=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                target_version="$2"
                shift 2
                ;;
            --force)
                force=true
                shift
                ;;
            --check)
                milou_self_update_check
                return $?
                ;;
            --help|-h)
                _show_cli_update_help
                return 0
                ;;
            *)
                if [[ "$1" != --* ]]; then
                    target_version="$1"
                fi
                shift
                ;;
        esac
    done
    
    milou_self_update_perform "$target_version" "$force"
}

# Rollback system update using Backup module
handle_rollback() {
    local backup_file="${1:-}"
    
    milou_log "STEP" "🔄 Rolling back system update..."
    
    if [[ -z "$backup_file" ]]; then
        # Find most recent pre-update backup
        backup_file=$(find ./backups -name "pre_update_*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
        
        if [[ -z "$backup_file" ]]; then
            milou_log "ERROR" "No backup file specified and no automatic backup found"
            return 1
        fi
        
        milou_log "INFO" "📦 Using automatic backup: $backup_file"
    fi
    
    # Use Backup module for restore
    if command -v milou_restore_from_backup >/dev/null 2>&1; then
        milou_restore_from_backup "$backup_file" "full"
    else
        milou_log "ERROR" "Restore function not available"
        return 1
    fi
}

# Show version information
handle_version() {
    echo
    milou_log "INFO" "📊 Milou System Version Information"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local cli_version="${SCRIPT_VERSION:-${MILOU_VERSION:-unknown}}"
    local system_version="${MILOU_VERSION:-latest}"
    
    echo -e "   ${BOLD}Milou CLI:${NC}         v$cli_version"
    echo -e "   ${BOLD}System Version:${NC}    v$system_version"
    echo -e "   ${BOLD}Last Updated:${NC}      $(get_last_update_timestamp)"
    
    # Service status summary using Docker module
    echo
    echo -e "   ${BOLD}Service Status:${NC}"
    local running_count=0
    local total_count=0
    
    while IFS=$'\t' read -r container_name status; do
        if [[ "$container_name" =~ milou-(.+) ]]; then
            ((total_count++))
            [[ "$status" =~ Up|running ]] && ((running_count++))
        fi
    done < <(docker ps -a --filter "name=milou-" --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | tail -n +2)
    
    if [[ "$total_count" -eq 0 ]]; then
        echo -e "   • ${YELLOW}No services detected${NC} (run 'milou setup' to install)"
    elif [[ "$running_count" -eq "$total_count" ]]; then
        echo -e "   • ${GREEN}All services running${NC} ($running_count/$total_count)"
    else
        echo -e "   • ${YELLOW}Partial services running${NC} ($running_count/$total_count)"
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
}

# Help functions
_show_update_help() {
    echo "🔄 System Update Command Usage"
    echo "=============================="
    echo ""
    echo "UPDATE SYSTEM:"
    echo "  ./milou.sh update [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --version VERSION     Update to specific version"
    echo "  --service SERVICES    Update specific services (comma-separated)"
    echo "  --token TOKEN         GitHub Personal Access Token"
    echo "  --force              Force update even if no changes detected"
    echo "  --no-backup          Skip backup creation before update"
    echo ""
    echo "Examples:"
    echo "  ./milou.sh update"
    echo "  ./milou.sh update --version v1.2.0"
    echo "  ./milou.sh update --service frontend,backend"
}

_show_cli_update_help() {
    echo "🛠️ CLI Update Command Usage"
    echo "==========================="
    echo ""
    echo "UPDATE CLI:"
    echo "  ./milou.sh update-cli [VERSION] [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force              Force update even if already up to date"
    echo "  --check              Check for updates without installing"
    echo ""
    echo "Examples:"
    echo "  ./milou.sh update-cli"
    echo "  ./milou.sh update-cli v3.2.0"
    echo "  ./milou.sh update-cli --check"
}

# =============================================================================
# MODULE EXPORTS - CLEAN PUBLIC API
# =============================================================================

# Core Update Functions
export -f milou_update_system
export -f milou_update_check_status
export -f milou_self_update_check
export -f milou_self_update_perform

# Version Management
export -f display_current_versions
export -f compare_semver_versions
export -f detect_latest_version
export -f get_last_update_timestamp

# Command Handlers
export -f handle_update
export -f handle_update_cli
export -f handle_rollback
export -f handle_version

# Status and Checking
export -f check_updates_needed

milou_log "DEBUG" "Update module loaded successfully"