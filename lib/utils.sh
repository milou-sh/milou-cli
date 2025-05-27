#!/bin/bash

# =============================================================================
# Milou CLI - Consolidated Utilities Module
# All utility functions, logging, validation, and helpers (500 lines max)
# =============================================================================

# Module guard to prevent multiple loading
if [[ "${MILOU_UTILS_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_UTILS_LOADED="true"

# =============================================================================
# Core Variables and Configuration (Lines 1-50)
# =============================================================================

# Colors and Formatting
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
export FOLDER_EMOJI="📁"
export WRENCH_EMOJI="🔧"

# Global Configuration
declare -g VERBOSE=${VERBOSE:-false}
declare -g QUIET=${QUIET:-false}
declare -g DEBUG=${DEBUG:-false}
declare -g LOG_TO_FILE=${LOG_TO_FILE:-true}
declare -g INTERACTIVE=${INTERACTIVE:-true}

# Paths and Files - Only set if not already defined
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
CONFIG_DIR="${CONFIG_DIR:-${HOME}/.milou}"
LOG_FILE="${LOG_FILE:-${CONFIG_DIR}/milou.log}"

# Initialize logging
utils_init() {
    # Ensure config directory exists
    if [[ ! -d "$CONFIG_DIR" ]]; then
        mkdir -p "$CONFIG_DIR" 2>/dev/null || {
            LOG_TO_FILE=false
            echo "Warning: Cannot create config directory $CONFIG_DIR - file logging disabled" >&2
        }
    fi
}

# =============================================================================
# Logging and Output Functions (Lines 51-150)
# =============================================================================

# Enhanced logging with levels, formatting, and multiple outputs
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local caller="${FUNCNAME[2]:-main}"
    local prefix=""
    local color=""
    local emoji=""
    
    # Skip if quiet mode and not error/warn
    if [[ "$QUIET" == true ]] && [[ "$level" != "ERROR" && "$level" != "WARN" ]]; then
        _log_to_file "[$timestamp] [$level] [$caller] $message"
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
            color="$BLUE"
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
                _log_to_file "[$timestamp] [$level] [$caller] $message"
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
                _log_to_file "[$timestamp] [$level] [$caller] $message"
                return 0
            fi
            ;;
        *)
            color="$NC"
            emoji=""
            prefix="[$level]"
            ;;
    esac
    
    # Output to console
    if [[ "$level" == "ERROR" || "$level" == "WARN" ]]; then
        echo -e "${color}${emoji} ${prefix}${NC} $message" >&2
    else
        echo -e "${color}${emoji} ${prefix}${NC} $message"
    fi
    
    # Output to log file if enabled
    _log_to_file "[$timestamp] [$level] [$caller] $message"
}

# Safe file logging function
_log_to_file() {
    if [[ "$LOG_TO_FILE" == true && -n "$LOG_FILE" && -w "$(dirname "$LOG_FILE")" ]]; then
        echo "$1" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# Backward compatibility aliases
milou_log() { log "$@"; }

# Error handling functions
error_exit() {
    log "ERROR" "$1"
    exit "${2:-1}"
}

warn_continue() {
    log "WARN" "$1"
    if [[ "$INTERACTIVE" == true ]]; then
        echo -n "Continue anyway? (y/N): "
        read -r continue_choice
        if [[ ! "$continue_choice" =~ ^[Yy] ]]; then
            log "INFO" "Operation cancelled by user"
            exit 1
        fi
    fi
}

# Progress indicators
show_progress() {
    local message="$1"
    local current="${2:-0}"
    local total="${3:-100}"
    
    if [[ "$QUIET" != true ]]; then
        local percent=$((current * 100 / total))
        printf "\r${GEAR_EMOJI} %s [%d%%]" "$message" "$percent"
        if [[ "$current" -eq "$total" ]]; then
            echo
        fi
    fi
}

# Spinner for long operations
show_spinner() {
    local pid=$1
    local message="${2:-Processing...}"
    local delay=0.1
    local spinstr='|/-\'
    
    if [[ "$QUIET" == true ]]; then
        wait $pid
        return $?
    fi
    
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf "\r${GEAR_EMOJI} %s %c" "$message" "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done
    printf "\r"
    wait $pid
    return $?
}

# =============================================================================
# Validation and Sanitization Functions (Lines 151-250)
# =============================================================================

# Domain validation
validate_domain() {
    local domain="$1"
    
    # Basic domain regex
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi
    
    # Check length
    if [[ ${#domain} -gt 253 ]]; then
        return 1
    fi
    
    return 0
}

# Email validation
validate_email() {
    local email="$1"
    
    # Allow localhost for development
    if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@localhost$ ]]; then
        return 0
    fi
    
    # Standard email validation
    if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    fi
    
    return 1
}

# Port validation
validate_port() {
    local port="$1"
    
    if [[ "$port" =~ ^[0-9]+$ ]] && [[ "$port" -ge 1 ]] && [[ "$port" -le 65535 ]]; then
        return 0
    fi
    
    return 1
}

# IP address validation
validate_ip() {
    local ip="$1"
    
    # IPv4 validation
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        local IFS='.'
        local -a octets=($ip)
        for octet in "${octets[@]}"; do
            if [[ "$octet" -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    fi
    
    return 1
}

# Path validation and sanitization
validate_path() {
    local path="$1"
    local allow_relative="${2:-true}"
    
    # Remove dangerous characters
    if [[ "$path" =~ (\.\./|/\.\.|^\.\./) ]]; then
        if [[ "$allow_relative" != true ]]; then
            return 1
        fi
    fi
    
    # Check for null bytes and other dangerous characters
    if [[ "$path" =~ ($'\0'|$'\r'|$'\n') ]]; then
        return 1
    fi
    
    return 0
}

# Input sanitization
sanitize_input() {
    local input="$1"
    local max_length="${2:-1024}"
    
    # Truncate if too long
    if [[ ${#input} -gt $max_length ]]; then
        input="${input:0:$max_length}"
    fi
    
    # Remove dangerous characters
    input="${input//[$'\0\r\n']/}"
    
    echo "$input"
}

# Check if running as root
is_root() {
    [[ $EUID -eq 0 ]]
}

# Check if user exists
user_exists() {
    local username="$1"
    id "$username" >/dev/null 2>&1
}

# Check if command exists
command_exists() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1
}

# Check if port is available
port_available() {
    local port="$1"
    local host="${2:-127.0.0.1}"
    
    if command_exists netstat; then
        ! netstat -tlnp 2>/dev/null | grep -q ":$port "
    elif command_exists ss; then
        ! ss -tlnp 2>/dev/null | grep -q ":$port "
    else
        # Fallback: try to bind to the port
        (echo >/dev/tcp/$host/$port) 2>/dev/null && return 1 || return 0
    fi
}

# =============================================================================
# File Operations and Path Handling (Lines 251-350)
# =============================================================================

# Safe file operations
safe_copy() {
    local src="$1"
    local dest="$2"
    local backup="${3:-true}"
    
    if [[ ! -f "$src" ]]; then
        log "ERROR" "Source file does not exist: $src"
        return 1
    fi
    
    # Validate paths
    if ! validate_path "$src" || ! validate_path "$dest"; then
        log "ERROR" "Invalid file paths"
        return 1
    fi
    
    # Create backup if destination exists
    if [[ -f "$dest" && "$backup" == true ]]; then
        local backup_file="${dest}.backup.$(date +%s)"
        cp "$dest" "$backup_file" || {
            log "ERROR" "Failed to create backup: $backup_file"
            return 1
        }
        log "INFO" "Created backup: $backup_file"
    fi
    
    # Copy file
    cp "$src" "$dest" || {
        log "ERROR" "Failed to copy $src to $dest"
        return 1
    }
    
    log "SUCCESS" "File copied: $src -> $dest"
    return 0
}

# Safe directory creation
safe_mkdir() {
    local dir="$1"
    local mode="${2:-755}"
    
    if ! validate_path "$dir"; then
        log "ERROR" "Invalid directory path: $dir"
        return 1
    fi
    
    if [[ -d "$dir" ]]; then
        log "DEBUG" "Directory already exists: $dir"
        return 0
    fi
    
    mkdir -p "$dir" || {
        log "ERROR" "Failed to create directory: $dir"
        return 1
    }
    
    chmod "$mode" "$dir" || {
        log "WARN" "Failed to set permissions on directory: $dir"
    }
    
    log "DEBUG" "Created directory: $dir"
    return 0
}

# Get absolute path
get_absolute_path() {
    local path="$1"
    
    if [[ -d "$path" ]]; then
        (cd "$path" && pwd)
    elif [[ -f "$path" ]]; then
        local dir_path file_name
        dir_path="$(cd "$(dirname "$path")" && pwd)"
        file_name="$(basename "$path")"
        echo "${dir_path}/${file_name}"
    else
        # Path doesn't exist, resolve relative to current directory
        if [[ "$path" = /* ]]; then
            echo "$path"
        else
            echo "$(pwd)/$path"
        fi
    fi
}

# Check disk space
check_disk_space() {
    local path="${1:-.}"
    local required_mb="${2:-100}"
    
    if ! command_exists df; then
        log "WARN" "Cannot check disk space - df command not available"
        return 0
    fi
    
    local available_kb
    available_kb=$(df "$path" | awk 'NR==2 {print $4}')
    local available_mb=$((available_kb / 1024))
    
    if [[ $available_mb -lt $required_mb ]]; then
        log "ERROR" "Insufficient disk space. Required: ${required_mb}MB, Available: ${available_mb}MB"
        return 1
    fi
    
    log "DEBUG" "Disk space check passed. Available: ${available_mb}MB"
    return 0
}

# File backup with rotation
backup_file() {
    local file="$1"
    local max_backups="${2:-5}"
    
    if [[ ! -f "$file" ]]; then
        log "WARN" "File does not exist for backup: $file"
        return 1
    fi
    
    local backup_dir="$(dirname "$file")/backups"
    safe_mkdir "$backup_dir"
    
    local basename="$(basename "$file")"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="$backup_dir/${basename}.backup.$timestamp"
    
    # Copy file to backup
    cp "$file" "$backup_file" || {
        log "ERROR" "Failed to create backup: $backup_file"
        return 1
    }
    
    # Rotate old backups
    local backup_count
    backup_count=$(find "$backup_dir" -name "${basename}.backup.*" | wc -l)
    
    if [[ $backup_count -gt $max_backups ]]; then
        find "$backup_dir" -name "${basename}.backup.*" -type f -printf '%T@ %p\n' | \
            sort -n | head -n $((backup_count - max_backups)) | \
            cut -d' ' -f2- | xargs rm -f
        log "DEBUG" "Rotated old backups for: $basename"
    fi
    
    log "SUCCESS" "File backed up: $backup_file"
    return 0
}

# =============================================================================
# Error Handling and Reporting (Lines 351-450)
# =============================================================================

# Enhanced error handling with context
handle_error() {
    local exit_code=$?
    local line_number="${1:-$LINENO}"
    local function_name="${2:-${FUNCNAME[1]}}"
    local command="${3:-unknown}"
    
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR" "Command failed in function '$function_name' at line $line_number"
        log "ERROR" "Command: $command"
        log "ERROR" "Exit code: $exit_code"
        
        # Show stack trace if debug mode
        if [[ "$DEBUG" == true ]]; then
            log "DEBUG" "Call stack:"
            local i=1
            while [[ -n "${FUNCNAME[$i]:-}" ]]; do
                log "DEBUG" "  $i: ${FUNCNAME[$i]} (${BASH_SOURCE[$i]}:${BASH_LINENO[$i-1]})"
                ((i++))
            done
        fi
    fi
    
    return $exit_code
}

# Trap handler for errors
error_trap() {
    handle_error "$LINENO" "${FUNCNAME[1]}" "$BASH_COMMAND"
}

# Set up error trapping
setup_error_handling() {
    set -eE  # Exit on error, inherit ERR trap
    trap error_trap ERR
}

# Cleanup function
cleanup() {
    local exit_code=$?
    
    log "DEBUG" "Cleanup function called with exit code: $exit_code"
    
    # Kill any background processes
    local jobs_count
    jobs_count=$(jobs -r | wc -l)
    if [[ $jobs_count -gt 0 ]]; then
        log "DEBUG" "Killing $jobs_count background jobs"
        kill $(jobs -p) 2>/dev/null || true
    fi
    
    # Remove temporary files
    if [[ -n "${TEMP_FILES:-}" ]]; then
        for temp_file in $TEMP_FILES; do
            if [[ -f "$temp_file" ]]; then
                rm -f "$temp_file"
                log "DEBUG" "Removed temporary file: $temp_file"
            fi
        done
    fi
    
    exit $exit_code
}

# Set up cleanup trap
setup_cleanup() {
    trap cleanup EXIT INT TERM
}

# Retry mechanism
retry() {
    local max_attempts="$1"
    local delay="$2"
    shift 2
    local command=("$@")
    
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        log "DEBUG" "Attempt $attempt/$max_attempts: ${command[*]}"
        
        if "${command[@]}"; then
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            log "WARN" "Command failed, retrying in ${delay}s..."
            sleep "$delay"
        fi
        
        ((attempt++))
    done
    
    log "ERROR" "Command failed after $max_attempts attempts: ${command[*]}"
    return 1
}

# =============================================================================
# Common Utilities and Helpers (Lines 451-500)
# =============================================================================

# System information
get_system_info() {
    log "INFO" "System Information:"
    echo "  OS: $(uname -s)"
    echo "  Kernel: $(uname -r)"
    echo "  Architecture: $(uname -m)"
    
    if [[ -f /etc/os-release ]]; then
        local os_name
        os_name=$(grep '^NAME=' /etc/os-release | cut -d'"' -f2)
        echo "  Distribution: $os_name"
    fi
    
    if command_exists docker; then
        local docker_version
        docker_version=$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',')
        echo "  Docker: $docker_version"
    fi
    
    if command_exists docker && docker compose version >/dev/null 2>&1; then
        local compose_version
        compose_version=$(docker compose version --short 2>/dev/null)
        echo "  Docker Compose: $compose_version"
    fi
}

# Check prerequisites
check_prerequisites() {
    local required_commands=("$@")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log "ERROR" "Missing required commands: ${missing_commands[*]}"
        return 1
    fi
    
    log "SUCCESS" "All prerequisites satisfied"
    return 0
}

# Generate random string
generate_random_string() {
    local length="${1:-32}"
    local charset="${2:-a-zA-Z0-9}"
    
    if command_exists openssl; then
        openssl rand -base64 $((length * 3 / 4)) | tr -d '=+/' | cut -c1-$length
    else
        # Fallback using /dev/urandom
        tr -dc "$charset" < /dev/urandom | head -c $length
    fi
}

# URL encoding
url_encode() {
    local string="$1"
    local encoded=""
    local char
    
    for (( i=0; i<${#string}; i++ )); do
        char="${string:$i:1}"
        case "$char" in
            [a-zA-Z0-9.~_-])
                encoded+="$char"
                ;;
            *)
                encoded+=$(printf '%%%02X' "'$char")
                ;;
        esac
    done
    
    echo "$encoded"
}

# Ask yes/no question
ask_yes_no() {
    local question="$1"
    local default="${2:-n}"
    local response
    
    if [[ "$INTERACTIVE" != true ]]; then
        echo "$default"
        return 0
    fi
    
    while true; do
        if [[ "$default" == "y" ]]; then
            echo -n "$question (Y/n): "
        else
            echo -n "$question (y/N): "
        fi
        
        read -r response
        response="${response:-$default}"
        
        case "$response" in
            [Yy]|[Yy][Ee][Ss])
                echo "y"
                return 0
                ;;
            [Nn]|[Nn][Oo])
                echo "n"
                return 1
                ;;
            *)
                log "WARN" "Please answer yes or no"
                ;;
        esac
    done
}

# =============================================================================
# File System Utilities (Lines 501-550)
# =============================================================================

# Safe directory creation
safe_mkdir() {
    local dir_path="$1"
    local permissions="${2:-755}"
    
    if [[ -z "$dir_path" ]]; then
        log "ERROR" "Directory path required"
        return 1
    fi
    
    if [[ -d "$dir_path" ]]; then
        log "DEBUG" "Directory already exists: $dir_path"
        return 0
    fi
    
    if mkdir -p "$dir_path" 2>/dev/null; then
        chmod "$permissions" "$dir_path"
        log "DEBUG" "Created directory: $dir_path"
        return 0
    else
        log "ERROR" "Failed to create directory: $dir_path"
        return 1
    fi
}

# Safe file copy
safe_copy() {
    local source="$1"
    local destination="$2"
    local backup="${3:-true}"
    
    if [[ ! -f "$source" ]]; then
        log "ERROR" "Source file does not exist: $source"
        return 1
    fi
    
    # Create destination directory if needed
    local dest_dir
    dest_dir=$(dirname "$destination")
    safe_mkdir "$dest_dir"
    
    # Backup existing file if requested
    if [[ "$backup" == "true" && -f "$destination" ]]; then
        local backup_file="${destination}.backup.$(date +%Y%m%d-%H%M%S)"
        cp "$destination" "$backup_file"
        log "DEBUG" "Backed up existing file: $backup_file"
    fi
    
    # Copy file
    if cp "$source" "$destination" 2>/dev/null; then
        log "DEBUG" "Copied file: $source -> $destination"
        return 0
    else
        log "ERROR" "Failed to copy file: $source -> $destination"
        return 1
    fi
}

# Get absolute path
get_absolute_path() {
    local path="$1"
    
    if [[ -z "$path" ]]; then
        echo ""
        return 1
    fi
    
    # Use realpath if available
    if command_exists realpath; then
        realpath "$path" 2>/dev/null || echo "$path"
    else
        # Fallback method
        cd "$(dirname "$path")" && pwd -P
    fi
}

# Check disk space
check_disk_space() {
    local path="${1:-.}"
    local required_mb="${2:-1024}"  # Default 1GB
    
    local available_kb
    available_kb=$(df "$path" | awk 'NR==2 {print $4}')
    local available_mb=$((available_kb / 1024))
    
    if [[ $available_mb -lt $required_mb ]]; then
        log "ERROR" "Insufficient disk space: ${available_mb}MB available, ${required_mb}MB required"
        return 1
    fi
    
    log "DEBUG" "Disk space check passed: ${available_mb}MB available"
    return 0
}

# Backup file with timestamp
backup_file() {
    local file_path="$1"
    local backup_dir="${2:-./backups}"
    
    if [[ ! -f "$file_path" ]]; then
        log "ERROR" "File does not exist: $file_path"
        return 1
    fi
    
    safe_mkdir "$backup_dir"
    
    local filename
    filename=$(basename "$file_path")
    local backup_path="${backup_dir}/${filename}.backup.$(date +%Y%m%d-%H%M%S)"
    
    if safe_copy "$file_path" "$backup_path" false; then
        log "INFO" "File backed up: $backup_path"
        echo "$backup_path"
        return 0
    else
        log "ERROR" "Failed to backup file: $file_path"
        return 1
    fi
}

# Initialize utilities
utils_init

# Export main functions for external use
export -f log milou_log error_exit warn_continue show_progress show_spinner
export -f validate_domain validate_email validate_port validate_ip validate_path
export -f safe_copy safe_mkdir get_absolute_path check_disk_space backup_file
export -f handle_error setup_error_handling setup_cleanup retry
export -f get_system_info check_prerequisites generate_random_string url_encode ask_yes_no 