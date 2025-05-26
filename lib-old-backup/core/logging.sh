#!/bin/bash

# =============================================================================
# Centralized Logging Module for Milou CLI
# Consolidates all logging functionality into a single, robust module
# =============================================================================

# Colors and Formatting - Export for use by other modules
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export WHITE='\033[1;37m'
export BOLD='\033[1m'
export DIM='\033[2m'
export NC='\033[0m'

# Emoji Set for Better UX
export SUCCESS_EMOJI="✅"
export ERROR_EMOJI="❌"
export WARNING_EMOJI="⚠️"
export INFO_EMOJI="ℹ️"
export ROCKET_EMOJI="🚀"
export GEAR_EMOJI="⚙️"
export LOCK_EMOJI="🔒"
export MAGNIFYING_GLASS_EMOJI="🔍"

# Global Logging Configuration
declare -g VERBOSE=${VERBOSE:-false}
declare -g QUIET=${QUIET:-false}
declare -g DEBUG=${DEBUG:-false}
declare -g LOG_TO_FILE=${LOG_TO_FILE:-true}

# Initialize logging configuration
milou_log_init() {
    local config_dir="${1:-${CONFIG_DIR:-${HOME}/.milou}}"
    
    # Set LOG_FILE if not already set
    if [[ -z "${LOG_FILE:-}" ]]; then
        export LOG_FILE="${config_dir}/milou.log"
    fi
    
    # Ensure log directory exists
    if [[ -n "${LOG_FILE:-}" ]]; then
        local log_dir
        log_dir="$(dirname "$LOG_FILE")"
        if ! mkdir -p "$log_dir" 2>/dev/null; then
            # If we can't create the log directory, disable file logging
            LOG_TO_FILE=false
            echo "Warning: Cannot create log directory $log_dir - file logging disabled" >&2
        fi
    fi
}

# Enhanced logging with levels, formatting, and multiple outputs
milou_log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local caller="${FUNCNAME[2]:-main}"
    local prefix=""
    local color=""
    local emoji=""
    
    # Safe file logging function to prevent hangs
    _safe_log_to_file() {
        # Skip file logging during critical operations to prevent hangs
        # We can re-enable this once the system is fully loaded
        return 0
    }
    
    # Skip if quiet mode and not error/warn
    if [[ "$QUIET" == true ]] && [[ "$level" != "ERROR" && "$level" != "WARN" ]]; then
        # Still log to file if enabled and log file path exists
        _safe_log_to_file "[$timestamp] [$level] [$caller] $message"
        return 0
    fi
    
    # Set color, emoji and prefix based on level
    case "$level" in
        "ERROR")
            color="$RED"
            emoji="$ERROR_EMOJI"
            prefix="[ERROR]"
            ;;
        "WARN")
            color="$YELLOW"
            emoji="$WARNING_EMOJI"
            prefix="[WARN]"
            ;;
        "INFO")
            color="$GREEN"
            emoji="$INFO_EMOJI"
            prefix="[INFO]"
            ;;
        "SUCCESS")
            color="$GREEN"
            emoji="$SUCCESS_EMOJI"
            prefix="[SUCCESS]"
            ;;
        "DEBUG")
            color="$BLUE"
            emoji="$MAGNIFYING_GLASS_EMOJI"
            prefix="[DEBUG]"
            # Only show debug messages if debug mode is enabled
            if [[ "$DEBUG" != true && "$VERBOSE" != true ]]; then
                # Still log to file if enabled and log file path exists
                _safe_log_to_file "[$timestamp] [$level] [$caller] $message"
                return 0
            fi
            ;;
        "STEP")
            color="$CYAN"
            emoji="$GEAR_EMOJI"
            prefix="[STEP]"
            ;;
        "TRACE")
            color="$DIM"
            emoji="$MAGNIFYING_GLASS_EMOJI"
            prefix="[TRACE]"
            # Only show trace messages if debug mode is enabled
            if [[ "$DEBUG" != true ]]; then
                # Still log to file if enabled and log file path exists
                _safe_log_to_file "[$timestamp] [$level] [$caller] $message"
                return 0
            fi
            ;;
    esac
    
    # Output to console
    if [[ "$level" == "ERROR" || "$level" == "WARN" ]]; then
        echo -e "${color}${emoji} ${prefix}${NC} $message" >&2
    else
        echo -e "${color}${emoji} ${prefix}${NC} $message"
    fi
    
    # Output to log file if enabled and log file path exists
    _safe_log_to_file "[$timestamp] [$level] [$caller] $message"
}

# Backward compatibility aliases
log() { milou_log "$@"; }
error_exit() { 
    milou_log "ERROR" "$1"
    exit "${2:-1}"
}

# Export functions for use by other modules
export -f milou_log_init milou_log log error_exit

# Export color variables for use by other modules
export RED GREEN YELLOW BLUE PURPLE CYAN WHITE BOLD DIM NC
export SUCCESS_EMOJI ERROR_EMOJI WARNING_EMOJI INFO_EMOJI ROCKET_EMOJI GEAR_EMOJI LOCK_EMOJI MAGNIFYING_GLASS_EMOJI 