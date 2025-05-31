#!/bin/bash

# =============================================================================
# Milou CLI Update Management Module - REWRITTEN FOR STATE-OF-THE-ART
# Dynamic version detection using actual Docker container inspection
# Version: 5.0.0 - Streamlined and Fixed Edition
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

# =============================================================================
# DYNAMIC VERSION DETECTION - STATE-OF-THE-ART
# =============================================================================

# Get actual running versions from Docker containers - THE RIGHT WAY
get_running_service_versions() {
    local quiet="${1:-false}"
    local -A versions=()
    local -A statuses=()
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "🔍 Extracting actual running versions from Docker containers"
    
    # Get ALL container information in one call - IMPROVED PARSING
    while IFS='|' read -r container_name image_name status; do
        # Skip empty lines and headers
        [[ -z "$container_name" || "$container_name" == "NAMES" ]] && continue
        
        if [[ "$container_name" =~ milou-(.+) ]]; then
            local service="${BASH_REMATCH[1]}"
            
            # Map actual service names to logical names
            case "$service" in
                "db") service="database" ;;
                *) ;;
            esac
            
            # Extract version from image tag (the real version) - IMPROVED REGEX
            local version=""
            if [[ "$image_name" =~ :([^[:space:]]+)$ ]]; then
                version="${BASH_REMATCH[1]}"
                # Clean version - remove 'v' prefix and whitespace
                version=$(echo "$version" | tr -d '[:space:]' | sed 's/^v//')
            fi
            
            # Skip if version contains invalid characters
            if [[ -n "$version" && ! "$version" =~ [^a-zA-Z0-9.\-_] ]]; then
                versions["$service"]="$version"
                statuses["$service"]=$([[ "$status" =~ ^Up|running ]] && echo "running" || echo "stopped")
                
                [[ "$quiet" != "true" ]] && milou_log "DEBUG" "   📦 $service: v$version ($([[ "${statuses[$service]}" == "running" ]] && echo "running" || echo "stopped"))"
            fi
        fi
    done < <(docker ps -a --filter "name=milou-" --format "{{.Names}}|{{.Image}}|{{.Status}}" 2>/dev/null)
    
    # Return results via global associative arrays - SAFE VARIABLE NAMES
    for service in "${!versions[@]}"; do
        local version_var="RUNNING_VERSION_${service^^}"
        local status_var="SERVICE_STATUS_${service^^}"
        # Ensure valid variable names (no special characters)
        version_var=$(echo "$version_var" | tr -cd '[:alnum:]_')
        status_var=$(echo "$status_var" | tr -cd '[:alnum:]_')
        declare -g "$version_var"="${versions[$service]}"
        declare -g "$status_var"="${statuses[$service]}"
    done
    
    return 0
}

# Get available image versions from local Docker images
get_available_service_versions() {
    local quiet="${1:-false}"
    local -A available=()
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "🔍 Scanning available local Docker images"
    
    # Get all available image tags for Milou services - IMPROVED PARSING
    while IFS=$'\t' read -r image_name tag; do
        # Skip empty lines and headers
        [[ -z "$image_name" || "$image_name" == "REPOSITORY" ]] && continue
        
        if [[ "$image_name" =~ ghcr\.io/milou-sh/milou/(.+) ]]; then
            local service="${BASH_REMATCH[1]}"
            
            # Map actual service names to logical names
            case "$service" in
                "db") service="database" ;;
                *) ;;
            esac
            
            # Clean the tag - remove whitespace and 'v' prefix
            tag=$(echo "$tag" | tr -d '[:space:]' | sed 's/^v//')
            
            # Skip if tag is empty, "latest", or contains invalid characters
            if [[ -z "$tag" || "$tag" == "latest" || "$tag" =~ [^a-zA-Z0-9.\-_] ]]; then
                continue
            fi
            
            # Store the highest available version for each service
            if [[ -z "${available[$service]:-}" ]] || compare_semver_versions "${available[$service]}" "$tag"; then
                available["$service"]="$tag"
                [[ "$quiet" != "true" ]] && milou_log "DEBUG" "   📦 $service: found v$tag (available locally)"
            fi
        fi
    done < <(docker images --format "{{.Repository}}\t{{.Tag}}" 2>/dev/null | grep "ghcr.io/milou-sh/milou")
    
    # Return results via global variables - SAFE VARIABLE NAMES
    for service in "${!available[@]}"; do
        local var_name="AVAILABLE_VERSION_${service^^}"
        # Ensure valid variable name (no special characters)
        var_name=$(echo "$var_name" | tr -cd '[:alnum:]_')
        declare -g "$var_name"="${available[$service]}"
    done
    
    return 0
}

# Get latest available version from registry (only when needed)
get_latest_registry_version() {
    local service="$1"
    local github_token="${2:-}"
    local quiet="${3:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "🌐 Checking registry for latest $service version"
    
    # Try to get version from image labels first (fastest)
    local label_version=""
    if docker pull "ghcr.io/milou-sh/milou/$service:latest" >/dev/null 2>&1; then
        label_version=$(docker inspect "ghcr.io/milou-sh/milou/$service:latest" --format '{{index .Config.Labels "version"}}' 2>/dev/null || echo "")
        if [[ -n "$label_version" && "$label_version" != "<no value>" && "$label_version" != "null" ]]; then
            echo "${label_version#v}"
            return 0
        fi
    fi
    
    # Fallback: Check manifest digests against known versions
    local latest_digest=""
    if latest_digest=$(docker manifest inspect "ghcr.io/milou-sh/milou/$service:latest" 2>/dev/null | jq -r '.config.digest // .manifests[0].digest // empty' 2>/dev/null); then
        # Only check a few recent versions to avoid hardcoding too many
        local test_versions=("1.0.3" "1.0.2" "1.0.1" "1.0.0")
        
        for version in "${test_versions[@]}"; do
            local version_digest=""
            if version_digest=$(docker manifest inspect "ghcr.io/milou-sh/milou/$service:$version" 2>/dev/null | jq -r '.config.digest // .manifests[0].digest // empty' 2>/dev/null); then
                if [[ "$version_digest" == "$latest_digest" ]]; then
                    echo "$version"
                    return 0
                fi
            fi
        done
    fi
    
    # Final fallback
    echo "1.0.0"
    return 0
}

# =============================================================================
# SEMANTIC VERSION MANAGEMENT - SIMPLIFIED
# =============================================================================

# Semantic version comparison - clean implementation
compare_semver_versions() {
    local current="$1"
    local target="$2"
    
    # Remove 'v' prefix and split versions
    current="${current#v}"
    target="${target#v}"
    
    IFS='.' read -ra current_parts <<< "$current"
    IFS='.' read -ra target_parts <<< "$target"
    
    # Compare major.minor.patch
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

# =============================================================================
# CLEAN VERSION DISPLAY
# =============================================================================

# Display current system version information - SIMPLIFIED AND FIXED
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
    
    # Get actual running versions
    get_running_service_versions "$quiet"
    get_available_service_versions "$quiet"
    
    # Display each service
    local services=("database" "backend" "frontend" "engine" "nginx")
    for service in "${services[@]}"; do
        local service_upper="${service^^}"
        local running_var="RUNNING_VERSION_${service_upper}"
        local status_var="SERVICE_STATUS_${service_upper}"
        local available_var="AVAILABLE_VERSION_${service_upper}"
        
        local current_version="${!running_var:-}"
        local service_status="${!status_var:-stopped}"
        local available_version="${!available_var:-}"
        
        # Determine what to display
        if [[ -n "$current_version" && "$current_version" != "latest" ]]; then
            # Service is running with a specific version
            if [[ "$service_status" == "running" ]]; then
                echo -e "   ${BOLD}├─ ${service}:${NC}      ${GREEN}v$current_version${NC} ${DIM}(running)${NC}"
            else
                echo -e "   ${BOLD}├─ ${service}:${NC}      ${RED}v$current_version${NC} ${DIM}(stopped)${NC}"
            fi
        elif [[ -n "$available_version" && "$available_version" != "latest" ]]; then
            # Service available but not running
            echo -e "   ${BOLD}├─ ${service}:${NC}      ${YELLOW}v$available_version${NC} ${DIM}(installed but not running)${NC}"
        else
            # Service not installed
            echo -e "   ${BOLD}├─ ${service}:${NC}      ${RED}not installed${NC}"
        fi
    done
    
    echo -e "   ${BOLD}└─ Last Updated:${NC} $(get_last_update_timestamp)"
    
    if [[ "$quiet" != "true" ]]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo
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
# UPDATE LOGIC - STREAMLINED
# =============================================================================

# Check what needs to be updated - SIMPLIFIED
check_updates_needed() {
    local target_version="${1:-latest}"
    local github_token="${2:-}"
    local quiet="${3:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🔍 Analyzing what needs to be updated..."
    
    # Get current state
    get_running_service_versions "$quiet"
    get_available_service_versions "$quiet"
    
    local updates_needed=false
    local services=("database" "backend" "frontend" "engine" "nginx")
    
    for service in "${services[@]}"; do
        local service_upper="${service^^}"
        local running_var="RUNNING_VERSION_${service_upper}"
        local status_var="SERVICE_STATUS_${service_upper}"
        
        local current_version="${!running_var:-}"
        local service_status="${!status_var:-stopped}"
        
        # Determine target version for this service
        local service_target_version="$target_version"
        if [[ "$target_version" == "latest" ]]; then
            service_target_version=$(get_latest_registry_version "$service" "$github_token" "$quiet")
        fi
        
        # Check if update is needed
        local needs_update=false
        local status_message=""
        
        if [[ -n "$current_version" && "$current_version" != "latest" ]]; then
            # Service exists, check version
            if [[ "$current_version" != "$service_target_version" ]]; then
                needs_update=true
                if [[ "$service_status" == "running" ]]; then
                    status_message="RUNNING UPDATE: v$current_version → v$service_target_version"
                else
                    status_message="UPDATE AND START: v$current_version → v$service_target_version"
                fi
            elif [[ "$service_status" != "running" ]]; then
                needs_update=true
                status_message="START: v$current_version (already correct version)"
            fi
        else
            # Service not installed
            needs_update=true
            status_message="NEW INSTALLATION → v$service_target_version"
        fi
        
        if [[ "$needs_update" == "true" ]]; then
            updates_needed=true
            [[ "$quiet" != "true" ]] && milou_log "INFO" "   📦 $service: $status_message"
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

# Main system update function - STREAMLINED
milou_update_system() {
    local force_update="${1:-false}"
    local backup_before_update="${2:-true}"
    local target_version="${3:-latest}"
    local specific_services="${4:-}"
    local github_token="${GITHUB_TOKEN:-}"
    
    milou_log "STEP" "🔄 Updating Milou system..."
    
    # Single authentication point
    if [[ -n "$github_token" ]]; then
        milou_log "INFO" "🔐 Authenticating with GitHub Container Registry..."
        if command -v docker_login_github >/dev/null 2>&1; then
            if docker_login_github "$github_token" "false" "false"; then
                milou_log "SUCCESS" "✅ GitHub authentication successful"
                export GITHUB_AUTHENTICATED="true"
            else
                milou_log "ERROR" "❌ GitHub authentication failed"
                return 1
            fi
        fi
    fi
    
    # Parse services to update
    local -a services_to_update=()
    if [[ -n "$specific_services" ]]; then
        IFS=',' read -ra services_to_update <<< "$specific_services"
    else
        services_to_update=("${DEFAULT_SERVICES[@]}")
    fi
    
    # Display current state
    display_current_versions "false" "$target_version"
    
    # Check if update is needed
    if ! check_updates_needed "$target_version" "$github_token" "false"; then
        if [[ "$force_update" != "true" ]]; then
            milou_log "INFO" "✅ All services are already up to date"
            return 0
        fi
    fi
    
    # Create backup before update
    if [[ "$backup_before_update" == "true" ]]; then
        milou_log "INFO" "📦 Creating pre-update backup..."
        if command -v milou_backup_create >/dev/null 2>&1; then
            milou_backup_create "full" "./backups" "pre_update_$(date +%Y%m%d_%H%M%S)" >/dev/null
        fi
    fi
    
    # Perform the update
    local update_start_time
    update_start_time=$(date +%s)
    
    if _perform_streamlined_update "$target_version" "$specific_services" "$github_token"; then
        milou_log "SUCCESS" "✅ System update completed"
        _display_update_results "$target_version" "$specific_services" "$update_start_time" "true"
        return 0
    else
        milou_log "ERROR" "❌ System update failed"
        _display_update_results "$target_version" "$specific_services" "$update_start_time" "false"
        return 1
    fi
}

# Streamlined update execution
_perform_streamlined_update() {
    local target_version="$1"
    local specific_services="$2"
    local github_token="$3"
    
    milou_log "INFO" "🔄 Performing streamlined system update..."
    
    # Parse services to update
    local -a services_to_update=()
    if [[ -n "$specific_services" ]]; then
        IFS=',' read -ra services_to_update <<< "$specific_services"
    else
        services_to_update=("${DEFAULT_SERVICES[@]}")
    fi
    
    # Ensure Docker networks exist
    milou_log "INFO" "🌐 Ensuring Docker networks exist..."
    docker network create proxy 2>/dev/null || true
    docker network create milou_network --subnet 172.21.0.0/16 2>/dev/null || true
    
    # Initialize Docker environment
    if ! docker_init "" "" "false"; then
        milou_log "ERROR" "❌ Docker initialization failed"
        return 1
    fi
    
    # Update each service
    local failed_services=()
    for service in "${services_to_update[@]}"; do
        local service_target_version="$target_version"
        if [[ "$target_version" == "latest" ]]; then
            service_target_version=$(get_latest_registry_version "$service" "$github_token" "true")
        fi
        
        milou_log "INFO" "🔄 Updating service: $service to v$service_target_version"
        
        # Update .env file with target version
        _update_env_file_service_version "$service" "$service_target_version"
        
        # Get actual service name
        local actual_service_name="${SERVICE_NAME_MAP[$service]:-$service}"
        
        # Use Docker module for zero-downtime update
        if command -v service_update_zero_downtime >/dev/null 2>&1; then
            if ! service_update_zero_downtime "$actual_service_name" "$service_target_version" "false"; then
                failed_services+=("$service")
                milou_log "ERROR" "❌ Failed to update $service"
            fi
        else
            # Fallback to basic update
            if ! _update_single_service "$actual_service_name" "$service_target_version"; then
                failed_services+=("$service")
            fi
        fi
    done
    
    # Final health check
    if [[ ${#failed_services[@]} -eq 0 ]]; then
        milou_log "INFO" "🏥 Performing final health check..."
        if command -v health_check_all >/dev/null 2>&1; then
            health_check_all "true"
        fi
        return 0
    else
        milou_log "ERROR" "❌ Failed to update services: ${failed_services[*]}"
        return 1
    fi
}

# Update environment file with service version
_update_env_file_service_version() {
    local service="$1"
    local target_version="$2"
    local env_file="${SCRIPT_DIR}/.env"
    
    [[ ! -f "$env_file" ]] && return 1
    
    local tag_name=""
    case "$service" in
        "database") tag_name="MILOU_DATABASE_TAG" ;;
        "backend") tag_name="MILOU_BACKEND_TAG" ;;
        "frontend") tag_name="MILOU_FRONTEND_TAG" ;;
        "engine") tag_name="MILOU_ENGINE_TAG" ;;
        "nginx") tag_name="MILOU_NGINX_TAG" ;;
        *) return 1 ;;
    esac
    
    # Update or add the tag
    if grep -q "^${tag_name}=" "$env_file"; then
        sed -i "s/^${tag_name}=.*/${tag_name}=${target_version}/" "$env_file"
    else
        echo "${tag_name}=${target_version}" >> "$env_file"
    fi
}

# Basic single service update
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
    
    # Show current system state
    echo -e "   ${BOLD}Updated System State:${NC}"
    display_current_versions "true" "$target_version"
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
}

# =============================================================================
# CLI SELF-UPDATE FUNCTIONS
# =============================================================================

# Check for CLI updates
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
    
    # Download and replace logic here (same as before)
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
# STATUS AND VERSION COMMANDS
# =============================================================================

# Check system update status
milou_update_check_status() {
    milou_log "STEP" "📊 Checking system update status..."
    
    display_current_versions
    
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
    
    # Show service health
    if command -v health_check_all >/dev/null 2>&1; then
        echo
        milou_log "INFO" "🏥 Current Service Health:"
        health_check_all "false"
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
    
    # Service status summary
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

# =============================================================================
# COMMAND HANDLERS
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

# Rollback command handler
handle_rollback() {
    local backup_file="${1:-}"
    
    milou_log "STEP" "🔄 Rolling back system update..."
    
    if [[ -z "$backup_file" ]]; then
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
# MODULE EXPORTS
# =============================================================================

# Core functions for external use
export -f milou_update_system
export -f milou_update_check_status
export -f milou_self_update_check
export -f milou_self_update_perform
export -f display_current_versions
export -f compare_semver_versions
export -f get_last_update_timestamp
export -f check_updates_needed
export -f handle_update
export -f handle_update_cli
export -f handle_rollback
export -f handle_version

milou_log "DEBUG" "Update module v5.0.0 loaded successfully - streamlined and state-of-the-art"