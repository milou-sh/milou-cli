#!/bin/bash

# =============================================================================
# Milou CLI - Smart Installation State Detection Module
# Professional state detection system for intelligent setup decisions
# Version: 4.0.0 - State-Based Architecture
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Module guard to prevent multiple loading
if [[ "${MILOU_STATE_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_STATE_LOADED="true"

# Ensure core modules are loaded
if [[ "${MILOU_CORE_LOADED:-}" != "true" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/_core.sh" || {
        echo "ERROR: Cannot load core module" >&2
        return 1
    }
fi

# =============================================================================
# STATE DETECTION CONSTANTS
# =============================================================================

# Installation states
declare -gr STATE_FRESH="fresh"                    # No Milou installation detected
declare -gr STATE_RUNNING="running"                # Milou is running and healthy
declare -gr STATE_INSTALLED_STOPPED="installed_stopped"  # Installed but not running
declare -gr STATE_CONFIGURED_ONLY="configured_only"      # Has config but no containers
declare -gr STATE_CONTAINERS_ONLY="containers_only"      # Has containers but no config
declare -gr STATE_BROKEN="broken"                  # Installation exists but is broken
declare -gr STATE_PARTIAL_FAILED="partial_failed"         # Failed setup with partial configuration
declare -gr STATE_UNKNOWN="unknown"                # Cannot determine state

# Setup modes based on detected state
declare -gr MODE_INSTALL="install"                 # Fresh installation
declare -gr MODE_UPDATE_CHECK="update_check"       # Check for updates
declare -gr MODE_RESUME="resume"                   # Start stopped services
declare -gr MODE_RECONFIGURE="reconfigure"         # Fix configuration
declare -gr MODE_REPAIR="repair"                   # Fix broken installation
declare -gr MODE_REINSTALL="reinstall"             # Force clean reinstall

# State cache for performance
declare -g _STATE_CACHE=""
declare -g _STATE_CACHE_TIME=0
declare -g _STATE_CACHE_TTL=30  # Cache for 30 seconds

# =============================================================================
# CORE STATE DETECTION FUNCTIONS
# =============================================================================

# Master state detection function - single source of truth
detect_installation_state() {
    local force_refresh="${1:-false}"
    local quiet="${2:-false}"
    
    # Use cache if available and not expired
    if [[ "$force_refresh" != "true" ]] && [[ -n "$_STATE_CACHE" ]]; then
        local current_time=$(date +%s)
        if [[ $((current_time - _STATE_CACHE_TIME)) -lt $_STATE_CACHE_TTL ]]; then
            [[ "$quiet" != "true" ]] && milou_log "TRACE" "Using cached state: $_STATE_CACHE"
            echo "$_STATE_CACHE"
            return 0
        fi
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Detecting installation state..."
    
    local state="$STATE_UNKNOWN"
    
    # Check for configuration file
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Checking for configuration files..."
    local has_config=false
    if [[ -f "${SCRIPT_DIR:-$(pwd)}/.env" ]]; then
        has_config=true
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Found configuration file"
    fi
    
    # Check for Docker containers (with proper error handling)
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Checking for Docker containers..."
    local has_containers=false
    local running_containers=0
    
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        local container_count=0
        
        # Use safer command execution
        local containers_output
        if containers_output=$(docker ps -a --filter "name=milou-" --format "{{.Names}}" 2>/dev/null); then
            local filtered_containers
            if filtered_containers=$(echo "$containers_output" | grep -v "^$" 2>/dev/null); then
                container_count=$(echo "$filtered_containers" | grep -c . 2>/dev/null || echo "0")
                container_count=${container_count//[^0-9]/}  # Remove any non-numeric characters
            fi
        fi
        
        if [[ $container_count -gt 0 ]]; then
            has_containers=true
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Found $container_count Milou containers"
            
            # Count running containers
            local running_output
            if running_output=$(docker ps --filter "name=milou-" --format "{{.Names}}" 2>/dev/null); then
                local filtered_running
                if filtered_running=$(echo "$running_output" | grep -v "^$" 2>/dev/null); then
                    running_containers=$(echo "$filtered_running" | grep -c . 2>/dev/null || echo "0")
                    running_containers=${running_containers//[^0-9]/}  # Remove any non-numeric characters
                fi
            fi
            
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Found $running_containers running containers"
        fi
    else
        [[ "$quiet" != "true" ]] && milou_log "TRACE" "Docker command not available"
    fi
    
    # Check for data volumes (with proper error handling)
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Checking for Docker volumes..."
    local has_volumes=false
    
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        local volume_count=0
        
        # Use safer command execution
        local volumes_output
        if volumes_output=$(docker volume ls --format "{{.Name}}" 2>/dev/null); then
            local filtered_volumes
            if filtered_volumes=$(echo "$volumes_output" | grep -E "(milou|static)" 2>/dev/null); then
                volume_count=$(echo "$filtered_volumes" | grep -c . 2>/dev/null || echo "0")
                volume_count=${volume_count//[^0-9]/}  # Remove any non-numeric characters
            fi
        fi
        
        if [[ $volume_count -gt 0 ]]; then
            has_volumes=true
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Found $volume_count data volumes"
        fi
    fi
    
    # Determine state based on component presence
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Analyzing installation state based on components found..."
    if [[ "$has_config" == "true" && "$has_containers" == "true" && $running_containers -gt 0 ]]; then
        # Has config, containers, and running services
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Found: config + containers + running services, validating health..."
        if _validate_running_installation "$quiet"; then
            state="$STATE_RUNNING"
        else
            state="$STATE_BROKEN"
        fi
    elif [[ "$has_config" == "true" && "$has_containers" == "true" && $running_containers -eq 0 ]]; then
        # Has config and containers but nothing running
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Found: config + containers but no running services"
        state="$STATE_INSTALLED_STOPPED"
    elif [[ "$has_config" == "true" && "$has_containers" == "false" ]]; then
        # Has config but no containers - could be partial failed setup
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Found: config only, checking for partial setup..."
        if _is_partial_failed_setup "$quiet"; then
            state="$STATE_PARTIAL_FAILED"
        else
            state="$STATE_CONFIGURED_ONLY"
        fi
    elif [[ "$has_config" == "false" && "$has_containers" == "true" ]]; then
        # Has containers but no config
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Found: containers only, no config"
        state="$STATE_CONTAINERS_ONLY"
    elif [[ "$has_config" == "false" && "$has_containers" == "false" && "$has_volumes" == "true" ]]; then
        # Only has volumes (partial cleanup) - BUT this might just be leftover from previous install
        # Check if these volumes actually have meaningful data before calling it "broken"
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Checking if volumes contain meaningful data..."
        local volume_has_data=false
        
        # Get Milou-related volumes and check if they contain significant data
        local milou_volumes
        if milou_volumes=$(docker volume ls --format "{{.Name}}" 2>/dev/null | grep -E "(milou|static)" 2>/dev/null); then
            for volume in $milou_volumes; do
                # Use much faster docker volume inspect instead of spawning containers
                local volume_info
                if volume_info=$(docker volume inspect "$volume" --format "{{.CreatedAt}}" 2>/dev/null); then
                    # Check if volume was created recently (within last 7 days)
                    local created_date
                    if created_date=$(date -d "${volume_info%.*}" +%s 2>/dev/null); then
                        local current_date=$(date +%s)
                        local days_old=$(( (current_date - created_date) / 86400 ))
                        
                        # If volume is older than 1 day, assume it has meaningful data
                        if [[ $days_old -gt 1 ]]; then
                            volume_has_data=true
                            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Volume $volume is ${days_old} days old, treating as containing data"
                            break
                        else
                            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Volume $volume is recent (${days_old} days old), checking if empty..."
                        fi
                    else
                        # Fallback: assume volume has data if we can't parse date
                        volume_has_data=true
                        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Volume $volume date unparseable, assuming contains data"
                        break
                    fi
                fi
            done
        fi
        
        if [[ "$volume_has_data" == "true" ]]; then
            # Volumes contain data - this is a broken installation that should be repaired
            state="$STATE_BROKEN"
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Found volumes with data, state = broken"
        else
            # Volumes are empty or contain no meaningful data - treat as fresh
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Found empty/recent volumes, treating as fresh installation"
            state="$STATE_FRESH"
        fi
    else
        # No Milou components found
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "No Milou components found"
        state="$STATE_FRESH"
    fi
    
    # Cache the result
    _STATE_CACHE="$state"
    _STATE_CACHE_TIME=$(date +%s)
    
    [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "System analysis complete - detected state: $state"
    echo "$state"
    return 0
}

# Validate a running installation for health
_validate_running_installation() {
    local quiet="${1:-false}"
    
    # Check if Docker Compose is working
    if [[ ! -f "${SCRIPT_DIR:-$(pwd)}/static/docker-compose.yml" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "TRACE" "Missing docker-compose.yml"
        return 1
    fi
    
    # Use consolidated validation if available
    if command -v docker_execute >/dev/null 2>&1; then
        # Initialize docker context
        if command -v initialize_docker_context >/dev/null 2>&1; then
            if ! initialize_docker_context "${SCRIPT_DIR:-$(pwd)}/.env" "${SCRIPT_DIR:-$(pwd)}/static/docker-compose.yml" "true"; then
                [[ "$quiet" != "true" ]] && milou_log "TRACE" "Docker context initialization failed"
                return 1
            fi
        fi
        
        # Validate configuration
        if ! docker_execute "validate" "" "true"; then
            [[ "$quiet" != "true" ]] && milou_log "TRACE" "Docker Compose configuration invalid"
            return 1
        fi
        
        # Get service status using consolidated function
        if ! compose_status=$(docker_execute "ps" "" "true" 2>/dev/null); then
            [[ "$quiet" != "true" ]] && milou_log "TRACE" "Failed to get service status"
            return 1
        fi
    else
        # Fallback to direct validation
        if ! compose_status=$(docker compose --env-file "${SCRIPT_DIR:-$(pwd)}/.env" \
                             -f "${SCRIPT_DIR:-$(pwd)}/static/docker-compose.yml" \
                             ps 2>/dev/null); then
            [[ "$quiet" != "true" ]] && milou_log "TRACE" "Docker Compose configuration invalid"
            return 1
        fi
    fi
    
    # Check if critical services are healthy (with proper error handling)
    local unhealthy_services=0
    local services_output
    
    if command -v docker_execute >/dev/null 2>&1; then
        # Use consolidated function for service status
        if services_output=$(docker_execute "ps" "" "true" --format "{{.Name}}\t{{.Status}}" 2>/dev/null); then
            while IFS=$'\t' read -r name status; do
                if [[ -n "$name" && ! "$status" =~ (running|Up) ]]; then
                    ((unhealthy_services++))
                fi
            done <<< "$services_output"
        fi
    else
        # Fallback to direct docker compose call
        if services_output=$(docker compose --env-file "${SCRIPT_DIR:-$(pwd)}/.env" \
                            -f "${SCRIPT_DIR:-$(pwd)}/static/docker-compose.yml" \
                            ps --format "{{.Name}}\t{{.Status}}" 2>/dev/null); then
            while IFS=$'\t' read -r name status; do
                if [[ -n "$name" && ! "$status" =~ (running|Up) ]]; then
                    ((unhealthy_services++))
                fi
            done <<< "$services_output"
        fi
    fi
    
    if [[ $unhealthy_services -eq 0 ]]; then
        [[ "$quiet" != "true" ]] && milou_log "TRACE" "All services are healthy"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "TRACE" "$unhealthy_services services are unhealthy"
        return 1
    fi
}

# Check if this is a partial failed setup
_is_partial_failed_setup() {
    local quiet="${1:-false}"
    
    # Look for indicators of a failed setup
    local failed_indicators=0
    
    # Check for failed config backups
    if ls "${SCRIPT_DIR:-$(pwd)}/.env.failed."* >/dev/null 2>&1; then
        ((failed_indicators++))
        [[ "$quiet" != "true" ]] && milou_log "TRACE" "Found failed config backups"
    fi
    
    # Check for failed SSL backups
    if ls "${SCRIPT_DIR:-$(pwd)}/ssl.failed."* >/dev/null 2>&1; then
        ((failed_indicators++))
        [[ "$quiet" != "true" ]] && milou_log "TRACE" "Found failed SSL backups"
    fi
    
    # Check if SSL directory exists but is empty or has incomplete certificates
    if [[ -d "${SCRIPT_DIR:-$(pwd)}/ssl" ]]; then
        local ssl_files_count=$(ls "${SCRIPT_DIR:-$(pwd)}/ssl"/*.{crt,key,pem} 2>/dev/null | wc -l || echo "0")
        if [[ $ssl_files_count -lt 2 ]]; then
            ((failed_indicators++))
            [[ "$quiet" != "true" ]] && milou_log "TRACE" "SSL directory incomplete"
        fi
    fi
    
    # Check if docker-compose.yml is missing (should exist after configuration)
    if [[ ! -f "${SCRIPT_DIR:-$(pwd)}/static/docker-compose.yml" ]]; then
        ((failed_indicators++))
        [[ "$quiet" != "true" ]] && milou_log "TRACE" "Missing docker-compose.yml after configuration"
    fi
    
    # Check configuration file for completeness
    if [[ -f "${SCRIPT_DIR:-$(pwd)}/.env" ]]; then
        local required_vars=("DOMAIN" "ADMIN_EMAIL" "POSTGRES_PASSWORD" "JWT_SECRET")
        local missing_vars=0
        
        for var in "${required_vars[@]}"; do
            if ! grep -q "^${var}=" "${SCRIPT_DIR:-$(pwd)}/.env" 2>/dev/null; then
                ((missing_vars++))
            fi
        done
        
        if [[ $missing_vars -gt 0 ]]; then
            ((failed_indicators++))
            [[ "$quiet" != "true" ]] && milou_log "TRACE" "Configuration appears incomplete ($missing_vars missing vars)"
        fi
    fi
    
    # If we have multiple indicators, this is likely a failed setup
    if [[ $failed_indicators -ge 2 ]]; then
        [[ "$quiet" != "true" ]] && milou_log "TRACE" "Detected partial failed setup ($failed_indicators indicators)"
        return 0
    else
        return 1
    fi
}

# =============================================================================
# SMART SETUP MODE SELECTION
# =============================================================================

# Determine appropriate setup mode based on state
smart_setup_mode() {
    local installation_state="$1"
    local force="${2:-false}"
    local quiet="${3:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Determining setup mode for state: $installation_state"
    
    local mode="$MODE_INSTALL"
    
    case "$installation_state" in
        "$STATE_FRESH")
            mode="$MODE_INSTALL"
            [[ "$quiet" != "true" ]] && milou_log "INFO" "Fresh system detected - will perform clean installation"
            ;;
        "$STATE_RUNNING")
            if [[ "$force" == "true" ]]; then
                mode="$MODE_REINSTALL"
                [[ "$quiet" != "true" ]] && milou_log "WARN" "Force flag detected - will reinstall over running system"
            else
                mode="$MODE_UPDATE_CHECK"
                [[ "$quiet" != "true" ]] && milou_log "INFO" "Running system detected - will check for updates"
            fi
            ;;
        "$STATE_INSTALLED_STOPPED")
            mode="$MODE_RESUME"
            [[ "$quiet" != "true" ]] && milou_log "INFO" "Stopped system detected - will resume services"
            ;;
        "$STATE_CONFIGURED_ONLY")
            mode="$MODE_RESUME"
            [[ "$quiet" != "true" ]] && milou_log "INFO" "Configuration without containers - will create and start services"
            ;;
        "$STATE_PARTIAL_FAILED")
            mode="$MODE_INSTALL"
            [[ "$quiet" != "true" ]] && milou_log "INFO" "Partial failed setup detected - will restart fresh installation"
            ;;
        "$STATE_CONTAINERS_ONLY")
            mode="$MODE_RECONFIGURE"
            [[ "$quiet" != "true" ]] && milou_log "INFO" "Containers without configuration - will reconfigure system"
            ;;
        "$STATE_BROKEN")
            mode="$MODE_REPAIR"
            [[ "$quiet" != "true" ]] && milou_log "WARN" "Broken installation detected - will attempt repair"
            ;;
        *)
            mode="$MODE_INSTALL"
            [[ "$quiet" != "true" ]] && milou_log "WARN" "Unknown state '$installation_state' - defaulting to fresh install"
            ;;
    esac
    
    [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "Selected setup mode: $mode"
    echo "$mode"
    return 0
}

# =============================================================================
# STATE-BASED OPERATION VALIDATION
# =============================================================================

# Check if an operation is safe for the current state
validate_operation_safety() {
    local operation="$1"          # setup, update, backup, etc.
    local installation_state="$2"
    local preserve_data="${3:-true}"
    local quiet="${4:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Validating operation '$operation' for state '$installation_state'"
    
    case "$operation" in
        "setup")
            case "$installation_state" in
                "$STATE_RUNNING")
                    if [[ "$preserve_data" != "true" ]]; then
                        [[ "$quiet" != "true" ]] && milou_log "WARN" "Setup on running system without data preservation is dangerous"
                        return 1
                    fi
                    ;;
                "$STATE_INSTALLED_STOPPED"|"$STATE_CONFIGURED_ONLY")
                    [[ "$quiet" != "true" ]] && milou_log "INFO" "Setup on stopped/configured system is safe"
                    ;;
                "$STATE_FRESH")
                    [[ "$quiet" != "true" ]] && milou_log "INFO" "Setup on fresh system is safe"
                    ;;
            esac
            ;;
        "update")
            case "$installation_state" in
                "$STATE_FRESH")
                    [[ "$quiet" != "true" ]] && milou_log "WARN" "Cannot update fresh installation"
                    return 1
                    ;;
                "$STATE_BROKEN")
                    [[ "$quiet" != "true" ]] && milou_log "WARN" "Cannot update broken installation - repair first"
                    return 1
                    ;;
            esac
            ;;
        "backup")
            case "$installation_state" in
                "$STATE_FRESH")
                    [[ "$quiet" != "true" ]] && milou_log "WARN" "Nothing to backup on fresh system"
                    return 1
                    ;;
            esac
            ;;
    esac
    
    [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "Operation '$operation' is safe for current state"
    return 0
}

# =============================================================================
# STATE TRANSITION HELPERS
# =============================================================================

# Get human-readable state description
describe_installation_state() {
    local state="$1"
    
    case "$state" in
        "$STATE_FRESH")
            echo "Fresh system with no Milou installation"
            ;;
        "$STATE_RUNNING")
            echo "Milou is installed and running normally"
            ;;
        "$STATE_INSTALLED_STOPPED")
            echo "Milou is installed but services are stopped"
            ;;
        "$STATE_CONFIGURED_ONLY")
            echo "Milou configuration exists but no containers"
            ;;
        "$STATE_PARTIAL_FAILED")
            echo "Previous setup failed with partial configuration"
            ;;
        "$STATE_CONTAINERS_ONLY")
            echo "Milou containers exist but no configuration"
            ;;
        "$STATE_BROKEN")
            echo "Milou installation exists but is broken or incomplete"
            ;;
        *)
            echo "Unknown installation state"
            ;;
    esac
}

# Get recommended actions for a state
get_recommended_actions() {
    local state="$1"
    
    case "$state" in
        "$STATE_FRESH")
            echo "Run: milou setup"
            ;;
        "$STATE_RUNNING")
            echo "Run: milou status, milou logs, or milou backup"
            ;;
        "$STATE_INSTALLED_STOPPED")
            echo "Run: milou start or milou logs (to diagnose why stopped)"
            ;;
        "$STATE_CONFIGURED_ONLY")
            echo "Run: milou start or milou setup --resume"
            ;;
        "$STATE_PARTIAL_FAILED")
            echo "Run: milou setup (will restart with fresh installation)"
            ;;
        "$STATE_CONTAINERS_ONLY")
            echo "Run: milou setup --reconfigure"
            ;;
        "$STATE_BROKEN")
            echo "Run: milou setup --repair or milou setup --force"
            ;;
        *)
            echo "Run: milou help"
            ;;
    esac
}

# =============================================================================
# INTEGRATION HELPERS
# =============================================================================

# Clear state cache (useful after operations that change state)
clear_state_cache() {
    _STATE_CACHE=""
    _STATE_CACHE_TIME=0
}

# Get current state with caching
get_current_state() {
    local quiet="${1:-false}"
    detect_installation_state "false" "$quiet"
}

# Force refresh state detection
refresh_state() {
    local quiet="${1:-false}"
    detect_installation_state "true" "$quiet"
} 