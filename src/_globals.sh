#!/bin/bash

# =============================================================================
# Milou CLI - Global State Management Module
# Centralized management of all global variables and paths
# Version: 1.0.0 - Clean Architecture
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Module guard to prevent multiple loading
if [[ "${MILOU_GLOBALS_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_GLOBALS_LOADED="true"

# =============================================================================
# GLOBAL CONSTANTS
# =============================================================================

# Version information
readonly MILOU_VERSION="4.0.0"
readonly MILOU_API_VERSION="1.0"

# =============================================================================
# PATH DETECTION AND INITIALIZATION
# =============================================================================

# Detect script directory with multiple fallback methods
detect_script_directory() {
    local detected_dir=""
    
    # Method 1: Use pre-exported SCRIPT_DIR if valid
    if [[ -n "${SCRIPT_DIR:-}" ]] && [[ -f "${SCRIPT_DIR}/milou.sh" ]]; then
        detected_dir="$SCRIPT_DIR"
    
    # Method 2: Detect from current script location
    elif [[ -n "${BASH_SOURCE[0]:-}" ]]; then
        detected_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
        
        # Validate detection
        if [[ ! -f "$detected_dir/milou.sh" ]]; then
            # Try alternative paths
            local alt_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            if [[ -f "$alt_dir/milou.sh" ]]; then
                detected_dir="$alt_dir"
            else
                detected_dir=""
            fi
        fi
    fi
    
    # Method 3: Search from current working directory
    if [[ -z "$detected_dir" ]]; then
        local search_dir="$(pwd)"
        while [[ "$search_dir" != "/" ]]; do
            if [[ -f "$search_dir/milou.sh" ]]; then
                detected_dir="$search_dir"
                break
            fi
            search_dir="$(dirname "$search_dir")"
        done
    fi
    
    # Method 4: Final fallback to current directory
    if [[ -z "$detected_dir" ]]; then
        detected_dir="$(pwd)"
    fi
    
    echo "$detected_dir"
}

# Initialize all global paths
initialize_globals() {
    # Core directory detection
    if [[ -z "${SCRIPT_DIR:-}" ]]; then
        SCRIPT_DIR="$(detect_script_directory)"
        export SCRIPT_DIR
    fi
    
    # Validate core directory
    if [[ ! -d "$SCRIPT_DIR" ]]; then
        echo "ERROR: Invalid script directory: $SCRIPT_DIR" >&2
        return 1
    fi
    
    # Source directory
    if [[ -z "${SRC_DIR:-}" ]]; then
        SRC_DIR="$SCRIPT_DIR/src"
        export SRC_DIR
    fi
    
    # Configuration paths
    export MILOU_ENV_FILE="${SCRIPT_DIR}/.env"
    export MILOU_BACKUP_DIR="${SCRIPT_DIR}/backups"
    export MILOU_SSL_DIR="${SCRIPT_DIR}/ssl"
    export MILOU_LOGS_DIR="${SCRIPT_DIR}/logs"
    export MILOU_STATIC_DIR="${SCRIPT_DIR}/static"
    
    # Compose configuration
    export MILOU_COMPOSE_FILE="${MILOU_STATIC_DIR}/docker-compose.yml"
    
    # User configuration
    if [[ $EUID -eq 0 ]] && command -v getent >/dev/null 2>&1 && getent passwd milou >/dev/null 2>&1; then
        local milou_home
        milou_home=$(getent passwd milou | cut -d: -f6)
        export MILOU_USER_CONFIG_DIR="${milou_home}/.milou"
    else
        export MILOU_USER_CONFIG_DIR="${HOME}/.milou"
    fi
    
    # Runtime directories
    export MILOU_USER_BACKUP_DIR="${MILOU_USER_CONFIG_DIR}/backups"
    export MILOU_USER_LOG_FILE="${MILOU_USER_CONFIG_DIR}/milou.log"
    
    return 0
}

# Create required directories
create_required_directories() {
    local dirs=(
        "$MILOU_BACKUP_DIR"
        "$MILOU_SSL_DIR"
        "$MILOU_LOGS_DIR"
        "$MILOU_USER_CONFIG_DIR"
        "$MILOU_USER_BACKUP_DIR"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir" 2>/dev/null || true
        fi
    done
    
    # Create log file
    touch "$MILOU_USER_LOG_FILE" 2>/dev/null || true
    
    # Set ownership if running as root with milou user
    if [[ $EUID -eq 0 ]] && [[ "$MILOU_USER_CONFIG_DIR" == */milou/.milou ]]; then
        chown -R milou:milou "$MILOU_USER_CONFIG_DIR" 2>/dev/null || true
    fi
}

# =============================================================================
# OPERATIONAL STATE VARIABLES
# =============================================================================

# Initialize operational flags
initialize_operational_state() {
    # Verbosity and debug flags
    export VERBOSE=${VERBOSE:-false}
    export DEBUG=${DEBUG:-false}
    export QUIET=${QUIET:-false}
    
    # Interactive mode detection
    if [[ "${MILOU_INTERACTIVE:-}" == "true" ]] || [[ "${INTERACTIVE:-}" == "true" ]]; then
        export INTERACTIVE=true
    elif [[ -t 0 && -t 1 ]]; then
        export INTERACTIVE=true
    else
        export INTERACTIVE=false
    fi
    
    # Force and assume yes flags
    export FORCE=${FORCE:-false}
    export ASSUME_YES=${ASSUME_YES:-false}
    
    # Safety flags
    export PRESERVE_DATA=${PRESERVE_DATA:-auto}
    export BACKUP_BEFORE_CHANGES=${BACKUP_BEFORE_CHANGES:-true}
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

# Validate global state
validate_globals() {
    local errors=0
    
    # Check required directories exist
    if [[ ! -d "$SCRIPT_DIR" ]]; then
        echo "ERROR: Script directory not found: $SCRIPT_DIR" >&2
        ((errors++))
    fi
    
    if [[ ! -d "$SRC_DIR" ]]; then
        echo "ERROR: Source directory not found: $SRC_DIR" >&2
        ((errors++))
    fi
    
    # Check required files exist
    if [[ ! -f "$SCRIPT_DIR/milou.sh" ]]; then
        echo "ERROR: Main script not found: $SCRIPT_DIR/milou.sh" >&2
        ((errors++))
    fi
    
    return $errors
}

# Get standardized paths (replaces inconsistent path usage)
get_env_file_path() {
    echo "$MILOU_ENV_FILE"
}

get_compose_file_path() {
    echo "$MILOU_COMPOSE_FILE"
}

get_ssl_dir_path() {
    echo "$MILOU_SSL_DIR"
}

get_backup_dir_path() {
    echo "$MILOU_BACKUP_DIR"
}

# =============================================================================
# INITIALIZATION FUNCTION
# =============================================================================

# Main initialization function
milou_initialize_globals() {
    if ! initialize_globals; then
        echo "ERROR: Failed to initialize global paths" >&2
        return 1
    fi
    
    initialize_operational_state
    create_required_directories
    
    if ! validate_globals; then
        echo "ERROR: Global state validation failed" >&2
        return 1
    fi
    
    return 0
}

# =============================================================================
# EXPORTS
# =============================================================================

# Export path functions
export -f get_env_file_path
export -f get_compose_file_path
export -f get_ssl_dir_path
export -f get_backup_dir_path
export -f milou_initialize_globals
export -f validate_globals

# Auto-initialize when sourced
milou_initialize_globals 