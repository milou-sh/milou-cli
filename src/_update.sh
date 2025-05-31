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
readonly MILOU_CLI_REPO="milou-sh/milou"
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

# Display comprehensive current system version information - SERVICE-SPECIFIC ENHANCED
display_current_versions_enhanced() {
    local quiet="${1:-false}"
    local -n target_versions_ref=$2
    
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
                "db") service="database" ;;
                *) ;;
            esac
            
            local version=""
            if [[ "$image_name" =~ :([^[:space:]]+)$ ]]; then
                version="${BASH_REMATCH[1]}"
                # If it's latest, try to get the actual version using our service-specific detection
                if [[ "$version" == "latest" ]]; then
                    local actual_version
                    actual_version=$(detect_latest_version_for_service "$service" "${GITHUB_TOKEN:-}" 2>/dev/null || echo "")
                    if [[ -n "$actual_version" && "$actual_version" != "latest" ]]; then
                        version="$actual_version"
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
    
    # Display service versions with enhanced comparison
    local services=("database" "backend" "frontend" "engine" "nginx")
    for service in "${services[@]}"; do
        local current_version="${running_versions[$service]:-}"
        local configured_version="${configured_versions[$service]:-}"
        local status="${container_status[$service]:-}"
        local target_version="${target_versions_ref[$service]:-latest}"
        
        # Clean up version strings
        current_version="${current_version#v}"
        configured_version="${configured_version#v}"
        target_version="${target_version#v}"
        
        if [[ -n "$current_version" && "$current_version" != "unknown" && "$current_version" != "latest" ]]; then
            local display_current=$(_format_version_for_display "$current_version")
            if [[ "$status" == "running" ]]; then
                # Compare with target version
                if [[ -n "$target_version" && "$target_version" != "unknown" && "$target_version" != "latest" ]]; then
                    if compare_semver_versions "$current_version" "$target_version"; then
                        echo -e "   ${BOLD}├─ ${service}:${NC}      ${YELLOW}$display_current${NC} ${DIM}(update to v$target_version available)${NC}"
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
            # Handle case where service is not running but might be installed
            local display_version=$(_format_version_for_display "$configured_version")
            
            # Check if image exists locally (FIXES "NEW INSTALLATION" issue)
            local image_exists=false
            if docker image inspect "ghcr.io/milou-sh/milou/${SERVICE_NAME_MAP[$service]:-$service}:$configured_version" >/dev/null 2>&1 || \
               docker image inspect "ghcr.io/milou-sh/milou/${SERVICE_NAME_MAP[$service]:-$service}:latest" >/dev/null 2>&1; then
                image_exists=true
            fi
            
            if [[ "$image_exists" == "true" ]]; then
                if [[ -n "$target_version" && "$target_version" != "unknown" && "$target_version" != "latest" ]]; then
                    echo -e "   ${BOLD}├─ ${service}:${NC}      ${YELLOW}$display_version${NC} ${DIM}(installed but not running, target: v$target_version)${NC}"
                else
                    echo -e "   ${BOLD}├─ ${service}:${NC}      ${YELLOW}$display_version${NC} ${DIM}(installed but not running)${NC}"
                fi
            else
                if [[ -n "$target_version" && "$target_version" != "unknown" && "$target_version" != "latest" ]]; then
                    echo -e "   ${BOLD}├─ ${service}:${NC}      ${RED}not installed${NC} ${DIM}(new installation → v$target_version)${NC}"
                else
                    echo -e "   ${BOLD}├─ ${service}:${NC}      ${RED}not installed${NC} ${DIM}(new installation needed)${NC}"
                fi
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

# Detect latest available version for a specific service - SERVICE-SPECIFIC
detect_latest_version_for_service() {
    local service="${1:-frontend}"
    local github_token="${2:-}"
    
    milou_log "DEBUG" "Detecting latest version for service: $service"
    
    # Use provided token or environment variable
    if [[ -z "$github_token" ]]; then
        github_token="${GITHUB_TOKEN:-}"
        if [[ -f "${SCRIPT_DIR}/.env" ]]; then
            source "${SCRIPT_DIR}/.env" 2>/dev/null || true
            github_token="${GITHUB_TOKEN:-$github_token}"
        fi
    fi
    
    # Ensure we're authenticated with GHCR
    if [[ -n "$github_token" && "${GITHUB_AUTHENTICATED:-}" != "true" ]]; then
        if docker_login_github "$github_token" "true" "false"; then
            export GITHUB_AUTHENTICATED="true"
        fi
    fi
    
    # Strategy 1: Check what version this service's 'latest' tag corresponds to by comparing digests
    local latest_digest=""
    local actual_latest_version=""
    
    # Get the digest for the 'latest' tag for this specific service
    if latest_digest=$(docker manifest inspect "ghcr.io/milou-sh/milou/$service:latest" 2>/dev/null | jq -r '.manifests[0].digest // .config.digest // empty' 2>/dev/null); then
        milou_log "DEBUG" "Service $service latest tag digest: $latest_digest"
        
        # Check known versions to see which one matches the latest digest for this service
        local versions_to_check=("1.4.0" "1.3.0" "1.2.0" "1.1.0" "1.0.3" "1.0.2" "1.0.1" "1.0.0")
        
        for version in "${versions_to_check[@]}"; do
            local version_digest=""
            if version_digest=$(docker manifest inspect "ghcr.io/milou-sh/milou/$service:$version" 2>/dev/null | jq -r '.manifests[0].digest // .config.digest // empty' 2>/dev/null); then
                if [[ "$version_digest" == "$latest_digest" ]]; then
                    actual_latest_version="$version"
                    milou_log "DEBUG" "Service $service: latest tag corresponds to version $version"
                    break
                fi
            fi
        done
    fi
    
    # Strategy 2: If we found the version that matches latest, use it
    if [[ -n "$actual_latest_version" ]]; then
        echo "$actual_latest_version"
        return 0
    fi
    
    # Strategy 3: Try to get version from image labels for this service
    local label_version=""
    if command -v docker >/dev/null 2>&1; then
        # Pull latest if not available locally
        docker pull "ghcr.io/milou-sh/milou/$service:latest" >/dev/null 2>&1 || true
        
        # Try to get version from image labels
        label_version=$(docker inspect "ghcr.io/milou-sh/milou/$service:latest" --format '{{index .Config.Labels "version"}}' 2>/dev/null || echo "")
        if [[ -n "$label_version" && "$label_version" != "<no value>" && "$label_version" != "null" ]]; then
            milou_log "DEBUG" "Service $service: found version from image label: $label_version"
            echo "${label_version#v}"
            return 0
        fi
    fi
    
    # Strategy 4: Check what versions are actually available for this service
    milou_log "DEBUG" "Testing for available versions for service: $service"
    local highest_version=""
    local test_versions=("1.4.0" "1.3.0" "1.2.0" "1.1.0" "1.0.3" "1.0.2" "1.0.1" "1.0.0")
    
    for version in "${test_versions[@]}"; do
        if docker manifest inspect "ghcr.io/milou-sh/milou/$service:$version" >/dev/null 2>&1; then
            milou_log "DEBUG" "Service $service: found available version $version"
            if [[ -z "$highest_version" ]]; then
                highest_version="$version"
            fi
        fi
    done
    
    if [[ -n "$highest_version" ]]; then
        echo "$highest_version"
        return 0
    fi
    
    # Fallback: Default to a known working version
    milou_log "DEBUG" "Service $service: Could not detect latest version, falling back to 1.0.0"
    echo "1.0.0"
    return 0
}

# Legacy function for backward compatibility - now service-aware
detect_latest_version() {
    local github_token="${1:-}"
    # For backward compatibility, default to frontend service
    detect_latest_version_for_service "frontend" "$github_token"
}

# =============================================================================
# SYSTEM UPDATE CORE FUNCTIONS - ENHANCED
# =============================================================================

# Enhanced system update with comprehensive integration - FIXED AUTHENTICATION
milou_update_system() {
    local force_update="${1:-false}"
    local backup_before_update="${2:-true}"
    local target_version="${3:-latest}"
    local specific_services="${4:-}"
    local github_token="${GITHUB_TOKEN:-}"
    
    milou_log "STEP" "🔄 Updating Milou system..."
    
    # SINGLE POINT OF AUTHENTICATION - Authenticate ONCE at the start
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
    
    # SERVICE-SPECIFIC VERSION RESOLUTION: If target is "latest", resolve per service
    local -A service_target_versions=()
    if [[ "$target_version" == "latest" ]]; then
        milou_log "INFO" "🔍 Resolving latest versions for each service..."
        for service in "${services_to_update[@]}"; do
            local resolved_version
            resolved_version=$(detect_latest_version_for_service "$service" "$github_token")
            if [[ $? -eq 0 && -n "$resolved_version" ]]; then
                service_target_versions["$service"]="$resolved_version"
                milou_log "INFO" "   📦 $service: latest = v$resolved_version"
            else
                service_target_versions["$service"]="1.0.0"
                milou_log "WARN" "   ⚠️  $service: could not resolve latest, using v1.0.0"
            fi
        done
    else
        # Use the same target version for all services
        for service in "${services_to_update[@]}"; do
            service_target_versions["$service"]="$target_version"
        done
        milou_log "INFO" "🎯 Using target version v$target_version for all services"
    fi
    
    # Display current system state with service-specific target versions
    display_current_versions_enhanced "false" service_target_versions
    
    # Check if update is needed with service-specific logic
    if ! check_updates_needed_enhanced service_target_versions "$github_token" "false"; then
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
    
    # Perform the update with service-specific versions
    local update_start_time
    update_start_time=$(date +%s)
    
    local update_result
    if _perform_system_update_enhanced service_target_versions "$specific_services" "$github_token"; then
        update_result=0
        milou_log "SUCCESS" "✅ System update completed"
        _display_update_results_enhanced service_target_versions "$specific_services" "$update_start_time" "true"
    else
        update_result=1
        milou_log "ERROR" "❌ System update failed"
        _display_update_results_enhanced service_target_versions "$specific_services" "$update_start_time" "false"
    fi
    
    return $update_result
}

# Check what needs to be updated - SERVICE-SPECIFIC ENHANCED
check_updates_needed_enhanced() {
    local -n target_versions_ref=$1
    local github_token="${2:-}"
    local quiet="${3:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🔍 Analyzing what needs to be updated..."
    
    local -A running_versions=()
    local -A installed_images=()
    local -A configured_versions=()
    local updates_needed=false
    
    # Get configured versions from .env file
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        source "${SCRIPT_DIR}/.env" 2>/dev/null || true
        configured_versions["database"]="${MILOU_DATABASE_TAG:-1.0.0}"
        configured_versions["backend"]="${MILOU_BACKEND_TAG:-1.0.0}"
        configured_versions["frontend"]="${MILOU_FRONTEND_TAG:-1.0.0}"
        configured_versions["engine"]="${MILOU_ENGINE_TAG:-1.0.0}"
        configured_versions["nginx"]="${MILOU_NGINX_TAG:-1.0.0}"
    fi
    
    # Get current running container versions
    while IFS=$'\t' read -r container_name image_name; do
        if [[ "$container_name" =~ milou-(.+) ]]; then
            local actual_service="${BASH_REMATCH[1]}"
            local logical_service="$actual_service"
            case "$actual_service" in
                "db") logical_service="database" ;;
                *) ;;
            esac
            
            local version=""
            if [[ "$image_name" =~ :(.+)$ ]]; then
                version="${BASH_REMATCH[1]#v}"
                # If it's latest, try to resolve the actual version
                if [[ "$version" == "latest" ]]; then
                    local actual_version
                    actual_version=$(detect_latest_version_for_service "$logical_service" "$github_token" 2>/dev/null || echo "")
                    if [[ -n "$actual_version" && "$actual_version" != "latest" ]]; then
                        version="$actual_version"
                    fi
                fi
            fi
            running_versions["$logical_service"]="$version"
        fi
    done < <(docker ps -a --filter "name=milou-" --format "table {{.Names}}\t{{.Image}}" 2>/dev/null | tail -n +2)
    
    # Get available installed images (not just running containers)
    while IFS=$'\t' read -r image_name tag; do
        if [[ "$image_name" =~ ghcr\.io/milou-sh/milou/(.+) ]]; then
            local service="${BASH_REMATCH[1]}"
            # Convert service names
            case "$service" in
                "db") service="database" ;;
                *) ;;
            esac
            
            local clean_tag="${tag#v}"
            # Store the highest version for each service
            if [[ -z "${installed_images[$service]:-}" ]] || compare_semver_versions "${installed_images[$service]}" "$clean_tag"; then
                installed_images["$service"]="$clean_tag"
            fi
        fi
    done < <(docker images --format "table {{.Repository}}\t{{.Tag}}" | grep "ghcr.io/milou-sh/milou" | tail -n +2)
    
    # Check if any service needs updating with service-specific target versions
    local services=("database" "backend" "frontend" "engine" "nginx")
    for service in "${services[@]}"; do
        local running_version="${running_versions[$service]:-}"
        local installed_version="${installed_images[$service]:-}"
        local configured_version="${configured_versions[$service]:-}"
        local target_version="${target_versions_ref[$service]:-1.0.0}"
        
        # Clean versions for comparison
        local clean_running="${running_version#v}"
        local clean_installed="${installed_version#v}"
        local clean_configured="${configured_version#v}"
        local clean_target="${target_version#v}"
        
        # Determine current state and what needs updating
        local needs_update=false
        local status_message=""
        
        if [[ -n "$running_version" && "$running_version" != "latest" ]]; then
            # Service is running
            if [[ "$clean_running" != "$clean_target" ]]; then
                needs_update=true
                status_message="RUNNING UPDATE: v$clean_running → v$clean_target"
            fi
        elif [[ -n "$installed_version" && "$installed_version" != "latest" ]]; then
            # Service installed but not running
            if [[ "$clean_installed" != "$clean_target" ]]; then
                needs_update=true
                status_message="RESTART WITH UPDATE: v$clean_installed → v$clean_target"
            else
                needs_update=true
                status_message="RESTART: v$clean_installed (installed but not running)"
            fi
        else
            # Service not installed
            needs_update=true
            status_message="NEW INSTALLATION → v$clean_target"
        fi
        
        if [[ "$needs_update" == "true" ]]; then
            updates_needed=true
            if [[ "$quiet" != "true" ]]; then
                milou_log "INFO" "   📦 $service: $status_message"
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

# Perform system update using service-specific versions - ENHANCED
_perform_system_update_enhanced() {
    local -n target_versions_ref=$1
    local specific_services="$2"
    local github_token="$3"
    
    milou_log "INFO" "🔄 Performing system update with service-specific versions..."
    
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
    
    # Don't create milou_network if it already exists to avoid conflicts
    if ! docker network ls --format "{{.Name}}" | grep -q "^milou_network$"; then
        milou_log "INFO" "📡 Creating milou_network..."
        if docker network create milou_network --subnet 172.21.0.0/16 2>/dev/null; then
            milou_log "SUCCESS" "✅ Milou network created"
        else
            milou_log "WARN" "⚠️  Milou network may already exist or conflict"
        fi
    else
        milou_log "DEBUG" "✅ Milou network already exists"
    fi
    
    # Initialize Docker environment using Docker module
    if ! docker_init "" "" "false"; then
        milou_log "ERROR" "❌ Docker initialization failed"
        return 1
    fi
    
    # Skip authentication if already done at the system level
    if [[ -n "$github_token" && "${GITHUB_AUTHENTICATED:-}" != "true" ]]; then
        milou_log "WARN" "⚠️  Authentication not completed at system level, attempting now..."
        if command -v docker_login_github >/dev/null 2>&1; then
            docker_login_github "$github_token" "false" "false"
        fi
    fi
    
    # Update services using service-specific versions
    local failed_services=()
    for service in "${services_to_update[@]}"; do
        local target_version="${target_versions_ref[$service]:-1.0.0}"
        milou_log "INFO" "🔄 Updating service: $service to v$target_version"
        
        # Update .env file with this service's target version
        _update_env_file_service_version "$service" "$target_version"
        
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
            if ! _update_single_service_enhanced "$actual_service_name" "$target_version"; then
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

# Update environment file with service-specific version
_update_env_file_service_version() {
    local service="$1"
    local target_version="$2"
    local env_file="${SCRIPT_DIR}/.env"
    
    if [[ ! -f "$env_file" ]]; then
        milou_log "ERROR" "❌ Environment file not found: $env_file"
        return 1
    fi
    
    # Map service name to environment variable
    local tag_name=""
    case "$service" in
        "database") tag_name="MILOU_DATABASE_TAG" ;;
        "backend") tag_name="MILOU_BACKEND_TAG" ;;
        "frontend") tag_name="MILOU_FRONTEND_TAG" ;;
        "engine") tag_name="MILOU_ENGINE_TAG" ;;
        "nginx") tag_name="MILOU_NGINX_TAG" ;;
        *) 
            milou_log "WARN" "Unknown service for env update: $service"
            return 1
            ;;
    esac
    
    milou_log "DEBUG" "📝 Updating $tag_name to $target_version in .env file"
    
    # Update or add the tag
    if grep -q "^${tag_name}=" "$env_file"; then
        sed -i "s/^${tag_name}=.*/${tag_name}=${target_version}/" "$env_file"
    else
        echo "${tag_name}=${target_version}" >> "$env_file"
    fi
    
    return 0
}

# Enhanced single service update with specific version
_update_single_service_enhanced() {
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

# Display update results with service-specific versions
_display_update_results_enhanced() {
    local -n target_versions_ref=$1
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
    
    # Show current system state using enhanced function
    echo -e "   ${BOLD}Updated System State:${NC}"
    display_current_versions_enhanced "true" target_versions_ref
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
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
export -f detect_latest_version_for_service
export -f get_last_update_timestamp

# Command Handlers
export -f handle_update
export -f handle_update_cli
export -f handle_rollback
export -f handle_version

# Status and Checking
export -f check_updates_needed

# Legacy compatibility wrapper for display_current_versions
display_current_versions() {
    local quiet="${1:-false}"
    local target_version="${2:-latest}"
    
    # Convert single target version to service-specific versions array
    local -A legacy_target_versions=()
    local services=("database" "backend" "frontend" "engine" "nginx")
    
    if [[ "$target_version" == "latest" ]]; then
        # Resolve latest for each service
        for service in "${services[@]}"; do
            local resolved_version
            resolved_version=$(detect_latest_version_for_service "$service" "${GITHUB_TOKEN:-}" 2>/dev/null || echo "1.0.0")
            legacy_target_versions["$service"]="$resolved_version"
        done
    else
        # Use same version for all services
        for service in "${services[@]}"; do
            legacy_target_versions["$service"]="$target_version"
        done
    fi
    
    # Call the enhanced version
    display_current_versions_enhanced "$quiet" legacy_target_versions
}

# Legacy compatibility wrapper for check_updates_needed  
check_updates_needed() {
    local target_version="${1:-latest}"
    local github_token="${2:-}"
    local quiet="${3:-false}"
    
    # Convert single target version to service-specific versions array
    local -A legacy_target_versions=()
    local services=("database" "backend" "frontend" "engine" "nginx")
    
    if [[ "$target_version" == "latest" ]]; then
        # Resolve latest for each service
        for service in "${services[@]}"; do
            local resolved_version
            resolved_version=$(detect_latest_version_for_service "$service" "$github_token" 2>/dev/null || echo "1.0.0")
            legacy_target_versions["$service"]="$resolved_version"
        done
    else
        # Use same version for all services
        for service in "${services[@]}"; do
            legacy_target_versions["$service"]="$target_version"
        done
    fi
    
    # Call the enhanced version
    check_updates_needed_enhanced legacy_target_versions "$github_token" "$quiet"
}

milou_log "DEBUG" "Update module loaded successfully"