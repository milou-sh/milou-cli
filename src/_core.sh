#!/bin/bash

# =============================================================================
# Milou CLI - Core Utilities Module
# Consolidated utilities to eliminate code duplication
# Version: 3.1.0 - Refactored Edition
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Module guard to prevent multiple loading
if [[ "${MILOU_CORE_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_CORE_LOADED="true"

# =============================================================================
# ENHANCED UI/UX LOGGING UTILITIES
# Version: 3.1.1 - Enhanced User Experience Edition  
# =============================================================================

# Color codes for enhanced UI (safe declarations to avoid readonly conflicts)
if [[ -z "${RED:-}" ]]; then
    readonly RED='\033[0;31m'
fi
if [[ -z "${GREEN:-}" ]]; then
    readonly GREEN='\033[0;32m'
fi
if [[ -z "${YELLOW:-}" ]]; then
    readonly YELLOW='\033[1;33m'
fi
if [[ -z "${BLUE:-}" ]]; then
    readonly BLUE='\033[0;34m'
fi
if [[ -z "${CYAN:-}" ]]; then
    readonly CYAN='\033[0;36m'
fi
if [[ -z "${PURPLE:-}" ]]; then
    readonly PURPLE='\033[0;35m'
fi
if [[ -z "${BOLD:-}" ]]; then
    readonly BOLD='\033[1m'
fi
if [[ -z "${DIM:-}" ]]; then
    readonly DIM='\033[2m'
fi
if [[ -z "${UNDERLINE:-}" ]]; then
    readonly UNDERLINE='\033[4m'
fi
if [[ -z "${NC:-}" ]]; then
    readonly NC='\033[0m' # No Color
fi

# Enhanced UI elements
readonly CHECKMARK="✓"
readonly CROSSMARK="✗"
readonly ARROW="→"
readonly BULLET="•"
readonly STAR="⭐"
readonly ROCKET="🚀"
readonly WRENCH="🔧"
readonly SHIELD="🛡️"
readonly SPARKLES="✨"

# Progress indicators
readonly PROGRESS_DOTS=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

# Log levels with enhanced UX focus
readonly LOG_TRACE=0
readonly LOG_DEBUG=1
readonly LOG_INFO=2
readonly LOG_WARN=3
readonly LOG_ERROR=4
readonly LOG_SUCCESS=5
readonly LOG_STEP=6
readonly LOG_HEADER=7
readonly LOG_HIGHLIGHT=8

# Current log level (can be overridden by environment)
MILOU_LOG_LEVEL="${MILOU_LOG_LEVEL:-${LOG_INFO}}"

# Enhanced main logging function with better UX
milou_log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_level_num
    
    case "$level" in
        TRACE) log_level_num=$LOG_TRACE ;;
        DEBUG) log_level_num=$LOG_DEBUG ;;
        INFO)  log_level_num=$LOG_INFO ;;
        WARN)  log_level_num=$LOG_WARN ;;
        ERROR) log_level_num=$LOG_ERROR ;;
        SUCCESS) log_level_num=$LOG_SUCCESS ;;
        STEP)  log_level_num=$LOG_STEP ;;
        HEADER) log_level_num=$LOG_HEADER ;;
        HIGHLIGHT) log_level_num=$LOG_HIGHLIGHT ;;
        *) log_level_num=$LOG_INFO; level="INFO" ;;
    esac
    
    # Skip if log level is below threshold
    if [[ $log_level_num -lt $MILOU_LOG_LEVEL ]]; then
        return 0
    fi
    
    # Enhanced formatting with better visual hierarchy
    case "$level" in
        ERROR)   
            echo -e "${RED}${BOLD}❌ ERROR${NC} ${message}" >&2 
            ;;
        WARN)    
            echo -e "${YELLOW}${BOLD}⚠️  WARNING${NC} ${message}" >&2 
            ;;
        SUCCESS) 
            echo -e "${GREEN}${BOLD}${CHECKMARK} SUCCESS${NC} ${message}" 
            ;;
        STEP)    
            echo -e "${BLUE}${BOLD}${ROCKET} STEP${NC} ${message}" 
            ;;
        HEADER)  
            echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════════════════${NC}"
            echo -e "${BOLD}${CYAN}${message}${NC}"
            echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${NC}\n"
            ;;
        HIGHLIGHT)
            echo -e "${BOLD}${YELLOW}${STAR} ${message}${NC}"
            ;;
        DEBUG)   
            echo -e "${DIM}${BULLET} DEBUG${NC} ${DIM}${message}${NC}" 
            ;;
        TRACE)   
            echo -e "${DIM}${BULLET} TRACE${NC} ${DIM}${message}${NC}" 
            ;;
        *)       
            echo -e "${CYAN}${BULLET} INFO${NC} ${message}" 
            ;;
    esac
}

# Enhanced user-friendly logging shortcuts
log_welcome() {
    local message="$1"
    echo -e "\n${BOLD}${PURPLE}${SPARKLES} Welcome!${NC} ${message}\n"
}

log_progress() {
    local step="$1"
    local total="$2"
    local description="$3"
    local percentage=$((step * 100 / total))
    local filled=$((step * 20 / total))
    local empty=$((20 - filled))
    
    printf "\r${BLUE}${BOLD}Progress:${NC} ["
    printf "%*s" $filled | tr ' ' '█'
    printf "%*s" $empty | tr ' ' '░'
    printf "] %d%% ${CYAN}(%d/%d)${NC} %s" $percentage $step $total "$description"
    
    if [[ $step -eq $total ]]; then
        echo -e "\n${GREEN}${BOLD}${CHECKMARK} Complete!${NC}"
    fi
}

log_section() {
    local title="$1"
    local subtitle="${2:-}"
    echo -e "\n${BOLD}${BLUE}▼ ${title}${NC}"
    if [[ -n "$subtitle" ]]; then
        echo -e "${DIM}  ${subtitle}${NC}"
    fi
    echo
}

log_user_action() {
    local action="$1"
    echo -e "${YELLOW}${BOLD}👤 User Action Required:${NC} ${action}"
}

log_system_status() {
    local status="$1"
    local details="$2"
    case "$status" in
        "healthy")
            echo -e "${GREEN}${CHECKMARK} System Status:${NC} ${GREEN}Healthy${NC} - ${details}"
            ;;
        "warning")
            echo -e "${YELLOW}⚠️  System Status:${NC} ${YELLOW}Warning${NC} - ${details}"
            ;;
        "error")
            echo -e "${RED}${CROSSMARK} System Status:${NC} ${RED}Error${NC} - ${details}"
            ;;
        *)
            echo -e "${BLUE}${BULLET} System Status:${NC} ${status} - ${details}"
            ;;
    esac
}

log_tip() {
    local tip="$1"
    echo -e "${CYAN}${BOLD}💡 Tip:${NC} ${tip}"
}

log_next_steps() {
    local steps=("$@")
    echo -e "\n${BOLD}${GREEN}🎯 Next Steps:${NC}"
    for i in "${!steps[@]}"; do
        echo -e "   ${BLUE}$((i+1)).${NC} ${steps[$i]}"
    done
    echo
}

# =============================================================================
# SECURE RANDOM GENERATION (Consolidated from 3+ implementations)
# =============================================================================

# Generate secure random strings - SINGLE AUTHORITATIVE IMPLEMENTATION
generate_secure_random() {
    local length="${1:-32}"
    local format="${2:-safe}"  # safe, alphanumeric, hex, numeric
    local exclude_ambiguous="${3:-true}"
    
    local chars=""
    case "$format" in
        safe)
            # Safe characters for passwords (excluding ambiguous ones)
            if [[ "$exclude_ambiguous" == "true" ]]; then
                chars="ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#$%^&*()_+-="
            else
                chars="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()_+-="
            fi
            ;;
        alphanumeric)
            # Only letters and numbers
            if [[ "$exclude_ambiguous" == "true" ]]; then
                chars="ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789"
            else
                chars="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
            fi
            ;;
        hex)
            # Hexadecimal characters
            chars="0123456789abcdef"
            ;;
        numeric)
            # Only numbers
            if [[ "$exclude_ambiguous" == "true" ]]; then
                chars="23456789"
            else
                chars="0123456789"
            fi
            ;;
        alpha)
            # Only letters
            chars="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
            ;;
        *)
            milou_log "ERROR" "Unknown format: $format. Use: safe, alphanumeric, hex, numeric, alpha"
            return 1
            ;;
    esac
    
    local result=""
    
    # Method 1: Try OpenSSL first (most secure)
    if command -v openssl >/dev/null 2>&1; then
        case "$format" in
            hex) 
                result=$(openssl rand -hex "$((length / 2))" 2>/dev/null | cut -c1-"$length")
                ;;
            *)
                # For non-hex formats, generate base64 and filter
                local base64_length=$((length * 3))  # Generate extra to account for filtering
                local base64_output
                base64_output=$(openssl rand -base64 "$base64_length" 2>/dev/null | tr -d "=+/\n")
                if [[ -n "$base64_output" ]]; then
                    result=""
                    for ((i=0; i<${#base64_output} && ${#result}<length; i++)); do
                        local char="${base64_output:$i:1}"
                        if [[ "$chars" == *"$char"* ]]; then
                            result+="$char"
                        fi
                    done
                fi
                ;;
        esac
    fi
    
    # Method 2: Try /dev/urandom if OpenSSL failed
    if [[ -z "$result" && -c /dev/urandom ]]; then
        if command -v tr >/dev/null 2>&1; then
            local random_bytes
            random_bytes=$(head -c "$((length * 4))" /dev/urandom 2>/dev/null | tr -dc "$chars" | head -c "$length")
            if [[ ${#random_bytes} -eq $length ]]; then
                result="$random_bytes"
            fi
        fi
    fi
    
    # Method 3: Fallback to BASH $RANDOM (less secure but always available)
    if [[ -z "$result" ]]; then
        milou_log "DEBUG" "Using fallback random generation method"
        result=""
        for ((i=0; i<length; i++)); do
            result+="${chars:$((RANDOM % ${#chars})):1}"
        done
    fi
    
    # Validate result length
    if [[ ${#result} -ne $length ]]; then
        # Ensure exact length by padding or truncating
        if [[ ${#result} -lt $length ]]; then
            # Pad with additional characters
            while [[ ${#result} -lt $length ]]; do
                result+="${chars:$((RANDOM % ${#chars})):1}"
            done
        fi
        result="${result:0:$length}"
    fi
    
    echo "$result"
}

# Legacy alias for backwards compatibility (will be removed after refactoring)
milou_generate_secure_random() {
    generate_secure_random "$@"
}

# Generate UUID
generate_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    elif [[ -f /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        # Fallback UUID generation
        printf '%08x-%04x-%04x-%04x-%012x\n' \
            $((RANDOM * RANDOM)) \
            $((RANDOM)) \
            $((RANDOM | 0x4000)) \
            $((RANDOM | 0x8000)) \
            $((RANDOM * RANDOM * RANDOM))
    fi
}

# =============================================================================
# INPUT VALIDATION (Consolidated from multiple files)
# =============================================================================

# Validate email address
validate_email() {
    local email="$1"
    local allow_localhost="${2:-false}"
    
    if [[ -z "$email" ]]; then
        return 1
    fi
    
    # Allow localhost emails for development
    if [[ "$allow_localhost" == "true" ]]; then
        # More flexible pattern for local development: allows localhost and local hostnames
        if [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+$ ]]; then
            return 0
        fi
    else
        # Standard email validation requiring proper TLD
        if [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            return 0
        fi
    fi
    
    return 1
}

# Validate domain name
validate_domain() {
    local domain="$1"
    local allow_localhost="${2:-true}"
    
    if [[ -z "$domain" ]]; then
        return 1
    fi
    
    # Allow localhost if specified
    if [[ "$allow_localhost" == "true" && "$domain" == "localhost" ]]; then
        return 0
    fi
    
    # Allow IP addresses
    if [[ "$domain" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    fi
    
    # Validate FQDN
    if [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        # Additional checks
        if [[ ${#domain} -le 253 ]]; then
            return 0
        fi
    fi
    
    return 1
}

# Validate port number
validate_port() {
    local port="$1"
    
    if [[ "$port" =~ ^[0-9]+$ ]] && [[ "$port" -ge 1 ]] && [[ "$port" -le 65535 ]]; then
        return 0
    fi
    
    return 1
}

# Validate file path
validate_path() {
    local path="$1"
    local type="${2:-any}"  # any, file, directory, executable
    local create_if_missing="${3:-false}"
    
    case "$type" in
        file)
            [[ -f "$path" ]]
            ;;
        directory)
            if [[ -d "$path" ]]; then
                return 0
            elif [[ "$create_if_missing" == "true" ]]; then
                mkdir -p "$path"
            else
                return 1
            fi
            ;;
        executable)
            [[ -x "$path" ]]
            ;;
        any)
            [[ -e "$path" ]]
            ;;
        *)
            return 1
            ;;
    esac
}

# Generic input validation dispatcher
validate_input() {
    local input="$1"
    local type="$2"
    local quiet="${3:-false}"
    
    case "$type" in
        email|mail)
            if validate_email "$input" "true"; then
                return 0
            else
                [[ "$quiet" != "true" ]] && milou_log "ERROR" "Invalid email format: $input"
                return 1
            fi
            ;;
        domain|hostname)
            if validate_domain "$input" "true"; then
                return 0
            else
                [[ "$quiet" != "true" ]] && milou_log "ERROR" "Invalid domain format: $input"
                return 1
            fi
            ;;
        port)
            if validate_port "$input"; then
                return 0
            else
                [[ "$quiet" != "true" ]] && milou_log "ERROR" "Invalid port number: $input (must be 1-65535)"
                return 1
            fi
            ;;
        *)
            # No validation for unknown types
            return 0
            ;;
    esac
}

# =============================================================================
# USER INTERFACE UTILITIES (Consolidated from lib/core/user-interface.sh)
# =============================================================================

# Colors for UI prompts
readonly CYAN_PROMPT='\033[0;36m'
readonly YELLOW_PROMPT='\033[1;33m'
readonly NC_PROMPT='\033[0m'
readonly DIM_PROMPT='\033[2m'

# Global UI state
declare -g MILOU_FORCE=${FORCE:-false}
declare -g MILOU_INTERACTIVE=${INTERACTIVE:-true}

# Enhanced user input with validation and variable assignment
prompt_user() {
    local prompt_text="$1"
    local default_value="${2:-}"
    local validation_type="${3:-}"
    local is_sensitive="${4:-false}"
    local max_attempts="${5:-3}"
    
    local attempts=0
    
    while [[ $attempts -lt $max_attempts ]]; do
        # Display prompt
        echo -ne "${CYAN_PROMPT}${prompt_text}${NC_PROMPT}"
        
        # Show default value (masked if sensitive)
        if [[ -n "$default_value" ]]; then
            if [[ "$is_sensitive" == "true" ]]; then
                echo -ne " ${DIM_PROMPT}(default: *****)${NC_PROMPT}"
            else
                echo -ne " ${DIM_PROMPT}(default: $default_value)${NC_PROMPT}"
            fi
        fi
        echo -ne ": "
        
        # Read user input
        local user_input=""
        if [[ "$is_sensitive" == "true" ]]; then
            read -rs user_input
            echo  # New line after hidden input
        else
            read -r user_input
        fi
        
        # Use default if no input provided
        if [[ -z "$user_input" && -n "$default_value" ]]; then
            user_input="$default_value"
        fi
        
        # Validate input if validation type is specified
        if [[ -n "$validation_type" ]]; then
            if validate_input "$user_input" "$validation_type" "true"; then
                echo "$user_input"
                return 0
            else
                ((attempts++))
                milou_log "WARN" "Invalid input. Attempt $attempts/$max_attempts"
                if [[ $attempts -ge $max_attempts ]]; then
                    milou_log "ERROR" "Maximum attempts reached for input validation"
                    return 1
                fi
                continue
            fi
        else
            echo "$user_input"
            return 0
        fi
    done
    
    return 1
}

# Legacy alias for backwards compatibility
milou_prompt_user() {
    prompt_user "$@"
}

# Enhanced confirmation prompt
confirm() {
    local prompt="$1"
    local default="${2:-N}"
    local timeout="${3:-0}"
    
    # Debug logging to help diagnose interactivity issues
    milou_log "DEBUG" "confirm() called with prompt: '$prompt', default: '$default', timeout: '$timeout'"
    milou_log "DEBUG" "MILOU_FORCE: '${MILOU_FORCE:-unset}', MILOU_INTERACTIVE: '${MILOU_INTERACTIVE:-unset}'"
    milou_log "DEBUG" "Terminal check: stdin=$(test -t 0 && echo 'tty' || echo 'not-tty'), stdout=$(test -t 1 && echo 'tty' || echo 'not-tty')"
    
    # Force mode bypasses confirmation
    if [[ "$MILOU_FORCE" == "true" ]]; then
        milou_log "DEBUG" "Force mode: auto-confirming '$prompt'"
        return 0
    fi
    
    # Non-interactive mode uses default
    if [[ "$MILOU_INTERACTIVE" == "false" ]]; then
        milou_log "DEBUG" "Non-interactive mode: using default '$default' for '$prompt'"
        [[ "$default" == "Y" ]] && return 0 || return 1
    fi
    
    # Prepare prompt text
    local prompt_text=""
    if [[ "$default" == "Y" ]]; then
        prompt_text="${CYAN_PROMPT}$prompt [Y/n]: ${NC_PROMPT}"
    else
        prompt_text="${CYAN_PROMPT}$prompt [y/N]: ${NC_PROMPT}"
    fi
    
    # Add timeout if specified
    if [[ $timeout -gt 0 ]]; then
        prompt_text="${CYAN_PROMPT}$prompt (${timeout}s timeout) [Y/n]: ${NC_PROMPT}"
    fi
    
    while true; do
        echo -ne "$prompt_text"
        
        local response=""
        if [[ $timeout -gt 0 ]]; then
            read -t "$timeout" response || {
                echo
                milou_log "DEBUG" "Timeout reached, using default: $default"
                [[ "$default" == "Y" ]] && return 0 || return 1
            }
        else
            read response
        fi
        
        case "$response" in
            [Yy]|[Yy][Ee][Ss]) 
                return 0 
                ;;
            [Nn]|[Nn][Oo]) 
                return 1 
                ;;
            "") 
                [[ "$default" == "Y" ]] && return 0 || return 1
                ;;
            *) 
                echo "Please answer yes or no."
                ;;
        esac
    done
}

# Legacy alias for backwards compatibility
milou_confirm() {
    confirm "$@"
}

# =============================================================================
# FILE SYSTEM UTILITIES
# =============================================================================

# Ensure directory exists with proper permissions
ensure_directory() {
    local dir_path="$1"
    local permissions="${2:-755}"
    local owner="${3:-}"
    
    if [[ ! -d "$dir_path" ]]; then
        if mkdir -p "$dir_path"; then
            milou_log "DEBUG" "Created directory: $dir_path"
        else
            milou_log "ERROR" "Failed to create directory: $dir_path"
            return 1
        fi
    fi
    
    # Set permissions
    if chmod "$permissions" "$dir_path"; then
        milou_log "DEBUG" "Set permissions $permissions on $dir_path"
    else
        milou_log "WARN" "Failed to set permissions on $dir_path"
    fi
    
    # Set ownership if specified and running as root
    if [[ -n "$owner" && $EUID -eq 0 ]]; then
        if chown "$owner" "$dir_path"; then
            milou_log "DEBUG" "Set ownership $owner on $dir_path"
        else
            milou_log "WARN" "Failed to set ownership on $dir_path"
        fi
    fi
    
    return 0
}

# Create backup of file with timestamp
backup_file() {
    local file_path="$1"
    local backup_dir="${2:-$(dirname "$file_path")}"
    
    if [[ ! -f "$file_path" ]]; then
        milou_log "ERROR" "File does not exist: $file_path"
        return 1
    fi
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local filename=$(basename "$file_path")
    local backup_path="${backup_dir}/${filename}.backup.${timestamp}"
    
    if cp "$file_path" "$backup_path"; then
        milou_log "INFO" "Created backup: $backup_path"
        echo "$backup_path"
        return 0
    else
        milou_log "ERROR" "Failed to create backup of $file_path"
        return 1
    fi
}

# =============================================================================
# NETWORK UTILITIES
# =============================================================================

# Check if port is in use
check_port_in_use() {
    local port="$1"
    local protocol="${2:-tcp}"
    
    if command -v ss >/dev/null 2>&1; then
        ss -tlnp 2>/dev/null | grep -q ":${port} "
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tlnp 2>/dev/null | grep -q ":${port} "
    else
        # Fallback: try to connect to the port
        if timeout 1 bash -c "echo >/dev/$protocol/localhost/$port" 2>/dev/null; then
            return 0  # Port is in use
        else
            return 1  # Port is free
        fi
    fi
}

# Get available port starting from a given port
get_available_port() {
    local start_port="${1:-8080}"
    local max_attempts="${2:-100}"
    
    for ((i=0; i<max_attempts; i++)); do
        local port=$((start_port + i))
        if ! check_port_in_use "$port"; then
            echo "$port"
            return 0
        fi
    done
    
    milou_log "ERROR" "Could not find available port starting from $start_port"
    return 1
}

# =============================================================================
# STRING UTILITIES
# =============================================================================

# Sanitize string for use in filenames
sanitize_filename() {
    local input="$1"
    echo "$input" | tr -cd '[:alnum:]._-' | head -c 200
}

# Convert string to lowercase
to_lowercase() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

# Convert string to uppercase
to_uppercase() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

# Trim whitespace from string
trim_whitespace() {
    local input="$1"
    echo "$input" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# =============================================================================
# COMMAND UTILITIES
# =============================================================================

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Run command with timeout
run_with_timeout() {
    local timeout_duration="$1"
    shift
    timeout "$timeout_duration" "$@"
}

# =============================================================================
# EXPORT ALL FUNCTIONS
# =============================================================================

# Export functions safely - only if they exist
_safe_export() {
    local func_name="$1"
    if declare -f "$func_name" >/dev/null 2>&1; then
        export -f "$func_name" 2>/dev/null || true
    fi
}

# Core logging
_safe_export milou_log

# Random generation (consolidated)
_safe_export generate_secure_random
_safe_export milou_generate_secure_random
_safe_export generate_uuid

# Validation (consolidated)
_safe_export validate_email
_safe_export validate_domain
_safe_export validate_port
_safe_export validate_path
_safe_export validate_input

# User interface (consolidated)
_safe_export prompt_user
_safe_export milou_prompt_user
_safe_export confirm
_safe_export milou_confirm

# File system utilities
_safe_export ensure_directory
_safe_export backup_file

# Network utilities
_safe_export check_port_in_use
_safe_export get_available_port

# String utilities
_safe_export sanitize_filename
_safe_export to_lowercase
_safe_export to_uppercase
_safe_export trim_whitespace

# Command utilities
_safe_export command_exists
_safe_export run_with_timeout

milou_log "DEBUG" "Core utilities module loaded successfully" 