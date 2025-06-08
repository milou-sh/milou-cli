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
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Detecting installation state..." >&2
    
    local state="$STATE_UNKNOWN"
    
    # Check for configuration file
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Checking for configuration files..." >&2
    local has_config=false
    if [[ -f "${SCRIPT_DIR:-$(pwd)}/.env" ]]; then
        has_config=true
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Found configuration file" >&2
    fi
    
    # Check for Docker containers (with proper error handling)
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Checking for Docker containers..." >&2
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
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Found $container_count Milou containers" >&2
            
            # Count running containers
            local running_output
            if running_output=$(docker ps --filter "name=milou-" --format "{{.Names}}" 2>/dev/null); then
                running_containers=$(echo "$running_output" | grep -c . 2>/dev/null || echo "0")
                running_containers=${running_containers//[^0-9]/}
                [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Found $running_containers running containers" >&2
            fi
        else
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "No Milou containers found" >&2
        fi
    else
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Docker not available for container checking" >&2
    fi
    
    # Check for data volumes (with proper error handling)
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Checking for Docker volumes..." >&2
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
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Found $volume_count Milou volumes" >&2
        else
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "No Milou volumes found" >&2
        fi
    else
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Docker not available for volume checking" >&2
    fi
    
    # Determine state based on component presence
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Analyzing installation state based on components found..." >&2
    if [[ "$has_config" == "true" && "$has_containers" == "true" && $running_containers -gt 0 ]]; then
        # Has config, containers, and running services
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Found: config + containers + running services, validating health..." >&2
        if _validate_running_installation "$quiet"; then
            state="$STATE_RUNNING"
        else
            state="$STATE_BROKEN"
        fi
    elif [[ "$has_config" == "true" && "$has_containers" == "true" && $running_containers -eq 0 ]]; then
        # Has config and containers but nothing running
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Found: config + containers but no running services" >&2
        state="$STATE_INSTALLED_STOPPED"
    elif [[ "$has_config" == "true" && "$has_containers" == "false" ]]; then
        # Has config but no containers - could be partial failed setup
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Found: config only, no containers" >&2
        if _is_config_complete "$quiet"; then
            state="$STATE_INCOMPLETE"
        else
            state="$STATE_BROKEN"
        fi
    elif [[ "$has_config" == "false" && "$has_containers" == "true" && $running_containers -gt 0 ]]; then
        # Has running containers but no config - unusual state
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Found: running containers but no config file" >&2
        state="$STATE_BROKEN"
    elif [[ "$has_config" == "false" && "$has_containers" == "true" && $running_containers -eq 0 ]]; then
        # Has stopped containers but no config
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Found: stopped containers but no config file" >&2
        state="$STATE_BROKEN"
    elif [[ "$has_config" == "false" && "$has_containers" == "false" && "$has_volumes" == "true" ]]; then
        # Only has volumes (partial cleanup) - BUT this might just be leftover from previous install
        # Check if these volumes actually have meaningful data before calling it "broken"
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Checking if volumes contain meaningful data..." >&2
        local volume_has_data=false
        
        # Get Milou-related volumes and check if they contain significant data
        local milou_volumes
        if milou_volumes=$(docker volume ls --format "{{.Name}}" 2>/dev/null | grep -E "(milou|static)" 2>/dev/null); then
            for volume in $milou_volumes; do
                # Use a faster method to check volume data - just check if volume has any files
                local file_count
                if file_count=$(docker run --rm -v "$volume:/data" alpine sh -c "find /data -type f 2>/dev/null | wc -l" 2>/dev/null); then
                    if [[ "${file_count//[^0-9]/}" -gt 0 ]]; then
                        volume_has_data=true
                        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Volume $volume contains data ($file_count files)" >&2
                        break
                    fi
                fi
            done
        fi
        
        if [[ "$volume_has_data" == "true" ]]; then
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Volumes contain data - classified as broken installation" >&2
            state="$STATE_BROKEN"
        else
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Volumes are empty - classified as fresh installation" >&2
            state="$STATE_FRESH"
        fi
    else
        # No Milou components found
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "No Milou components found" >&2
        state="$STATE_FRESH"
    fi
    
    # Cache the result
    _STATE_CACHE="$state"
    _STATE_CACHE_TIME=$(date +%s)
    
    [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "System analysis complete - detected state: $state" >&2
    echo "$state"
    return 0
}

# Helper function to check if a running installation is healthy
_validate_running_installation() {
    local quiet="${1:-false}"
    
    # Check if all critical services are running
    local critical_services=("nginx" "dashboard")
    
    for service in "${critical_services[@]}"; do
        if ! docker_compose ps --services --filter "status=running" 2>/dev/null | grep -q "^${service}$"; then
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Critical service not running: $service" >&2
            return 1
        fi
    done
    
    return 0
}

# Helper function to check if configuration is complete
_is_config_complete() {
    local quiet="${1:-false}"
    
    # Check if .env file exists
    if [[ ! -f "${SCRIPT_DIR:-$(pwd)}/.env" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "No .env file found" >&2
        return 1
    fi
    
    # Check for essential configuration variables
    local env_file="${SCRIPT_DIR:-$(pwd)}/.env"
    local required_vars=("GITHUB_TOKEN" "MILOU_DOMAIN" "DATABASE_URI")
    
    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" "$env_file" 2>/dev/null; then
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Missing required variable: $var" >&2
            return 1
        fi
        
        # Check if variable has a value (not just empty)
        local value
        value=$(grep "^${var}=" "$env_file" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
        if [[ -z "$value" ]]; then
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Empty value for required variable: $var" >&2
            return 1
        fi
    done
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Configuration file is complete" >&2
    return 0
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

# Determine appropriate setup mode based on current state
smart_setup_mode() {
    local current_state="$1"
    local force_mode="${2:-false}"
    local quiet="${3:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Determining setup mode for state: $current_state" >&2
    
    local mode=""
    
    case "$current_state" in
        "$STATE_FRESH")
            mode="install"
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Fresh installation detected - using install mode" >&2
            ;;
        "$STATE_INSTALLED_STOPPED")
            mode="start"
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Stopped installation detected - using start mode" >&2
            ;;
        "$STATE_RUNNING")
            if [[ "$force_mode" == "true" ]]; then
                mode="reinstall"
                [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Running installation detected with force - using reinstall mode" >&2
            else
                mode="running"
                [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Installation already running - using running mode" >&2
            fi
            ;;
        "$STATE_BROKEN"|"$STATE_INCOMPLETE"|"$STATE_PARTIAL_FAILED")
            mode="repair"
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Broken/incomplete installation detected - using repair mode" >&2
            ;;
        "$STATE_UNKNOWN"|*)
            # Unknown state - default to fresh install
            mode="install"
            [[ "$quiet" != "true" ]] && milou_log "WARN" "Unknown state '$current_state' - defaulting to fresh install" >&2
            ;;
    esac
    
    [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "Selected setup mode: $mode" >&2
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