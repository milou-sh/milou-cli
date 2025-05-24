#!/bin/bash

# =============================================================================
# Core Utility Functions for Milou CLI - State-of-the-Art Edition
# Enhanced with comprehensive functionality and robust error handling
# =============================================================================

# Version and Constants (avoid conflicts with main script)
readonly MIN_DOCKER_VERSION="20.10.0"
readonly MIN_DOCKER_COMPOSE_VERSION="2.0.0"
readonly MIN_DISK_SPACE_GB=2
readonly MIN_RAM_MB=2048

# Colors and Formatting (Enhanced with more options)
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly UNDERLINE='\033[4m'
readonly BLINK='\033[5m'
readonly REVERSE='\033[7m'
readonly NC='\033[0m'

# Enhanced Emoji Set for Better UX
readonly SUCCESS_EMOJI="✅"
readonly ERROR_EMOJI="❌"
readonly WARNING_EMOJI="⚠️"
readonly INFO_EMOJI="ℹ️"
readonly ROCKET_EMOJI="🚀"
readonly GEAR_EMOJI="⚙️"
readonly LOCK_EMOJI="🔒"
readonly KEY_EMOJI="🔑"
readonly FIRE_EMOJI="🔥"
readonly SPARKLES_EMOJI="✨"
readonly FOLDER_EMOJI="📁"
readonly FILE_EMOJI="📄"
readonly NETWORK_EMOJI="🌐"
readonly DATABASE_EMOJI="🗄️"
readonly DOCKER_EMOJI="🐳"
readonly SHIELD_EMOJI="🛡️"
readonly WRENCH_EMOJI="🔧"
readonly MAGNIFYING_GLASS_EMOJI="🔍"
readonly CLOCK_EMOJI="⏰"
readonly CHECKMARK_EMOJI="✓"
readonly CROSS_EMOJI="✗"

# Global State with Enhanced Options
declare -g VERBOSE=false
declare -g FORCE=false
declare -g DRY_RUN=false
declare -g QUIET=false
declare -g DEBUG=false
declare -g LOG_TO_FILE=true
declare -g INTERACTIVE=true

# =============================================================================
# Enhanced Logging System with Multiple Levels and Outputs
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
        # Still log to file if enabled and log file path exists
        if [[ "$LOG_TO_FILE" == true ]] && [[ -n "${LOG_FILE:-}" ]]; then
            # Ensure log directory exists before writing
            if mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null; then
                echo "[$timestamp] [$level] [$caller] $message" >> "$LOG_FILE" 2>/dev/null || true
            fi
        fi
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
                if [[ "$LOG_TO_FILE" == true ]] && [[ -n "${LOG_FILE:-}" ]]; then
                    # Ensure log directory exists before writing
                    if mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null; then
                        echo "[$timestamp] [$level] [$caller] $message" >> "$LOG_FILE" 2>/dev/null || true
                    fi
                fi
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
                if [[ "$LOG_TO_FILE" == true ]] && [[ -n "${LOG_FILE:-}" ]]; then
                    # Ensure log directory exists before writing
                    if mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null; then
                        echo "[$timestamp] [$level] [$caller] $message" >> "$LOG_FILE" 2>/dev/null || true
                    fi
                fi
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
    if [[ "$LOG_TO_FILE" == true ]] && [[ -n "${LOG_FILE:-}" ]]; then
        # Ensure log directory exists before writing
        if mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null; then
            echo "[$timestamp] [$level] [$caller] $message" >> "$LOG_FILE" 2>/dev/null || true
        fi
    fi
}

# Enhanced error handling with context and suggestions
error_exit() {
    local message="$1"
    local exit_code="${2:-1}"
    local caller="${FUNCNAME[1]:-unknown}"
    local suggestion="${3:-}"
    
    log "ERROR" "Function '$caller' failed: $message"
    
    # Provide contextual suggestions if not provided
    if [[ -z "$suggestion" ]]; then
        case "$message" in
            *"Docker"*|*"docker"*)
                log "INFO" "💡 Suggestion: Check if Docker is running with 'docker info'"
                log "INFO" "💡 Try: sudo systemctl start docker"
                ;;
            *"token"*|*"authentication"*|*"auth"*)
                log "INFO" "💡 Suggestion: Verify your GitHub token has the correct permissions"
                log "INFO" "💡 Required scopes: read:packages, write:packages"
                log "INFO" "💡 Create token at: https://github.com/settings/tokens"
                ;;
            *"network"*|*"connection"*|*"timeout"*)
                log "INFO" "💡 Suggestion: Check your network connection and firewall settings"
                log "INFO" "💡 Try: curl -I https://ghcr.io/"
                ;;
            *"permission"*|*"access"*)
                log "INFO" "💡 Suggestion: Check file permissions and user access"
                log "INFO" "💡 Try: sudo usermod -aG docker \$USER && newgrp docker"
                ;;
            *"port"*|*"bind"*)
                log "INFO" "💡 Suggestion: Check for port conflicts with: netstat -tulpn"
                ;;
        esac
    else
        log "INFO" "💡 Suggestion: $suggestion"
    fi
    
    exit "$exit_code"
}

# =============================================================================
# Enhanced User Interface Functions
# =============================================================================

# Enhanced confirmation prompt with timeout and default handling
confirm() {
    local prompt="$1"
    local default="${2:-N}"
    local timeout="${3:-0}"
    
    # Force mode bypasses confirmation
    if [[ "$FORCE" == true ]]; then
        log "DEBUG" "Force mode: auto-confirming '$prompt'"
        return 0
    fi
    
    # Non-interactive mode uses default
    if [[ "$INTERACTIVE" == false ]]; then
        log "DEBUG" "Non-interactive mode: using default '$default' for '$prompt'"
        [[ "$default" == "Y" ]] && return 0 || return 1
    fi
    
    local prompt_text=""
    if [[ "$default" == "Y" ]]; then
        prompt_text="${CYAN}$prompt [Y/n]: ${NC}"
    else
        prompt_text="${CYAN}$prompt [y/N]: ${NC}"
    fi
    
    # Add timeout if specified
    if [[ $timeout -gt 0 ]]; then
        prompt_text="${CYAN}$prompt [Y/n] (${timeout}s timeout): ${NC}"
    fi
    
    while true; do
        echo -ne "$prompt_text"
        
        local response=""
        if [[ $timeout -gt 0 ]]; then
            read -t "$timeout" response || {
                echo
                log "DEBUG" "Timeout reached, using default: $default"
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

# Enhanced progress indicator with customizable animation
show_progress() {
    local message="$1"
    local steps="${2:-3}"
    local delay="${3:-0.5}"
    local animation="${4:-dots}"
    
    case "$animation" in
        "dots")
            echo -n "$message"
            for ((i=0; i<steps; i++)); do
                echo -n "."
                sleep "$delay"
            done
            echo " Done! ${SUCCESS_EMOJI}"
            ;;
        "spinner")
            local chars="/-\|"
            echo -n "$message "
            for ((i=0; i<steps*4; i++)); do
                printf "\r$message %s" "${chars:$((i%4)):1}"
                sleep "$delay"
            done
            printf "\r$message Done! ${SUCCESS_EMOJI}\n"
            ;;
        "bar")
            echo -n "$message ["
            for ((i=0; i<steps; i++)); do
                echo -n "="
                sleep "$delay"
            done
            echo "] Done! ${SUCCESS_EMOJI}"
            ;;
    esac
}

# Enhanced user input with validation and masking
prompt_user() {
    local prompt="$1"
    local default="$2"
    local validation_type="${3:-}"
    local is_sensitive="${4:-false}"
    local max_attempts="${5:-3}"
    
    local attempts=0
    while [[ $attempts -lt $max_attempts ]]; do
        echo -ne "${CYAN}$prompt${NC}"
        [[ -n "$default" ]] && echo -ne " ${DIM}(default: $([[ "$is_sensitive" == true ]] && echo "*****" || echo "$default"))${NC}"
        echo -ne ": "
        
        local user_input=""
        if [[ "$is_sensitive" == true ]]; then
            read -rs user_input
            echo
        else
            read user_input
        fi
        
        # Use default if no input provided
        if [[ -z "$user_input" && -n "$default" ]]; then
            user_input="$default"
        fi
        
        # Validate input if validation type is specified
        if [[ -n "$validation_type" ]]; then
            if validate_input "$user_input" "$validation_type" true; then
                echo "$user_input"
                return 0
            else
                ((attempts++))
                log "WARN" "Invalid input. Attempt $attempts/$max_attempts"
                continue
            fi
        else
            echo "$user_input"
            return 0
        fi
    done
    
    log "ERROR" "Maximum attempts reached for input validation"
    return 1
}

# =============================================================================
# Enhanced Version and Validation Functions
# =============================================================================

# Enhanced version comparison with better error handling
version_compare() {
    local version1="$1"
    local version2="$2"
    local operator="${3:-ge}"
    
    # Input validation
    if [[ -z "$version1" || -z "$version2" ]]; then
        log "ERROR" "Version comparison requires two version strings"
        return 2
    fi
    
    # Normalize versions (handle v prefix and clean up)
    version1="${version1#v}"
    version2="${version2#v}"
    version1="${version1//[^0-9.]/}"
    version2="${version2//[^0-9.]/}"
    
    log "TRACE" "Comparing versions: '$version1' $operator '$version2'"
    
    case "$operator" in
        "ge"|">=") 
            printf '%s\n%s\n' "$version2" "$version1" | sort -V -C
            ;;
        "gt"|">")  
            [[ "$version1" != "$version2" ]] && printf '%s\n%s\n' "$version2" "$version1" | sort -V -C
            ;;
        "le"|"<=") 
            printf '%s\n%s\n' "$version1" "$version2" | sort -V -C
            ;;
        "lt"|"<")  
            [[ "$version1" != "$version2" ]] && printf '%s\n%s\n' "$version1" "$version2" | sort -V -C
            ;;
        "eq"|"==") 
            [[ "$version1" == "$version2" ]]
            ;;
        *) 
            log "ERROR" "Invalid operator: $operator (use: ge, gt, le, lt, eq)"
            return 2
            ;;
    esac
}

# Comprehensive input validation with enhanced patterns
validate_input() {
    local value="$1"
    local type="$2"
    local required="${3:-true}"
    
    # Handle empty values
    if [[ -z "$value" ]]; then
        if [[ "$required" == true ]]; then
            log "DEBUG" "Required field '$type' is empty"
            return 1
        else
            log "DEBUG" "Optional field '$type' is empty, skipping validation"
            return 0
        fi
    fi
    
    log "TRACE" "Validating input '$value' as type '$type'"
    
    case "$type" in
        "github_token")
            # Enhanced GitHub token patterns including fine-grained tokens
            if [[ ! "$value" =~ ^gh[pousr]_[A-Za-z0-9_]{36,251}$ ]]; then
                log "ERROR" "Invalid GitHub token format"
                log "INFO" "Expected patterns: ghp_*, gho_*, ghu_*, ghs_*, ghr_*"
                log "INFO" "Token should be 40+ characters long"
                return 1
            fi
            ;;
        "domain")
            # Enhanced domain validation with IDN support
            if [[ "$value" != "localhost" ]]; then
                # Basic domain validation
                if [[ ! "$value" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
                    log "ERROR" "Invalid domain format: $value"
                    return 1
                fi
                # Additional checks
                if [[ ${#value} -gt 253 ]]; then
                    log "ERROR" "Domain name too long (max 253 characters): ${#value}"
                    return 1
                fi
                # Check for invalid characters
                if [[ "$value" =~ [^a-zA-Z0-9.-] ]]; then
                    log "ERROR" "Domain contains invalid characters: $value"
                    return 1
                fi
            fi
            ;;
        "email")
            # Enhanced email validation
            if [[ ! "$value" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
                log "ERROR" "Invalid email format: $value"
                return 1
            fi
            # Additional email checks
            if [[ ${#value} -gt 254 ]]; then
                log "ERROR" "Email address too long (max 254 characters)"
                return 1
            fi
            ;;
        "path")
            if [[ ! -e "$value" ]]; then
                log "ERROR" "Path does not exist: $value"
                return 1
            fi
            ;;
        "directory")
            if [[ ! -d "$value" ]]; then
                log "ERROR" "Directory does not exist: $value"
                return 1
            fi
            ;;
        "file")
            if [[ ! -f "$value" ]]; then
                log "ERROR" "File does not exist: $value"
                return 1
            fi
            ;;
        "port")
            if [[ ! "$value" =~ ^[1-9][0-9]{0,4}$ ]] || [[ "$value" -gt 65535 ]]; then
                log "ERROR" "Invalid port number: $value (must be 1-65535)"
                return 1
            fi
            ;;
        "version")
            if [[ ! "$value" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?(\+[a-zA-Z0-9.-]+)?$ ]]; then
                log "ERROR" "Invalid version format: $value (expected: x.y.z or vx.y.z)"
                return 1
            fi
            ;;
        "url")
            if [[ ! "$value" =~ ^https?://[a-zA-Z0-9.-]+[a-zA-Z0-9.-/]*$ ]]; then
                log "ERROR" "Invalid URL format: $value"
                return 1
            fi
            ;;
        "ip")
            if [[ ! "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                log "ERROR" "Invalid IP address format: $value"
                return 1
            fi
            # Validate IP ranges
            local IFS='.'
            local -a ip_parts=($value)
            for part in "${ip_parts[@]}"; do
                if [[ $part -gt 255 ]]; then
                    log "ERROR" "Invalid IP address range: $value"
                    return 1
                fi
            done
            ;;
        "uuid")
            if [[ ! "$value" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
                log "ERROR" "Invalid UUID format: $value"
                return 1
            fi
            ;;
    esac
    
    log "TRACE" "Input validation passed for '$type': $value"
    return 0
}

# Secure random generation with enhanced entropy
generate_secure_random() {
    local length="${1:-32}"
    local charset="${2:-alphanumeric}"
    local exclude_ambiguous="${3:-true}"
    
    local chars=""
    case "$charset" in
        "alphanumeric")
            chars="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
            # Exclude ambiguous characters if requested
            if [[ "$exclude_ambiguous" == true ]]; then
                chars="abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
            fi
            ;;
        "alpha")
            chars="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
            if [[ "$exclude_ambiguous" == true ]]; then
                chars="abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ"
            fi
            ;;
        "numeric") 
            chars="0123456789"
            if [[ "$exclude_ambiguous" == true ]]; then
                chars="23456789"
            fi
            ;;
        "hex") 
            chars="0123456789abcdef"
            ;;
        "base64")
            chars="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
            ;;
        "safe")
            # URL-safe characters only
            chars="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
            ;;
    esac
    
    log "TRACE" "Generating secure random string: length=$length, charset=$charset"
    
    # Try multiple methods for secure randomness (in order of preference)
    local result=""
    
    # Method 1: OpenSSL (most secure)
    if command -v openssl >/dev/null 2>&1; then
        case "$charset" in
            "hex") 
                result=$(openssl rand -hex "$((length / 2))" 2>/dev/null | cut -c1-"$length")
                ;;
            "base64")
                result=$(openssl rand -base64 "$((length * 3 / 4))" 2>/dev/null | tr -d "=\n" | cut -c1-"$length")
                ;;
            *)
                local base64_output
                base64_output=$(openssl rand -base64 "$((length * 2))" 2>/dev/null | tr -d "=+/\n")
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
    
    # Method 2: /dev/urandom (good security)
    if [[ -z "$result" && -c /dev/urandom ]]; then
        local random_bytes
        random_bytes=$(head -c "$((length * 3))" /dev/urandom 2>/dev/null | base64 | tr -d "=+/\n")
        if [[ -n "$random_bytes" ]]; then
            result=""
            for ((i=0; i<${#random_bytes} && ${#result}<length; i++)); do
                local char="${random_bytes:$i:1}"
                if [[ "$chars" == *"$char"* ]]; then
                    result+="$char"
                fi
            done
        fi
    fi
    
    # Method 3: BASH RANDOM (fallback, less secure)
    if [[ -z "$result" ]]; then
        log "WARN" "Using fallback random generation method (less secure)"
        result=""
        for ((i=0; i<length; i++)); do
            result+="${chars:$((RANDOM % ${#chars})):1}"
        done
    fi
    
    # Ensure we have the requested length
    if [[ ${#result} -lt $length ]]; then
        log "WARN" "Generated string shorter than requested, padding with additional entropy"
        while [[ ${#result} -lt $length ]]; do
            result+="${chars:$((RANDOM % ${#chars})):1}"
        done
    fi
    
    # Trim to exact length
    result="${result:0:$length}"
    
    log "TRACE" "Generated secure random string of length ${#result}"
    echo "$result"
}

# =============================================================================
# System Requirements and Health Checks (Enhanced)
# =============================================================================

check_system_requirements() {
    log "STEP" "Checking system requirements..."
    
    local errors=0
    local warnings=0
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        log "WARN" "Running as root - not recommended for security reasons"
        log "INFO" "💡 Consider using dedicated user for better security"
        
        # If user management is available, offer to create milou user
        if command -v milou_user_exists >/dev/null 2>&1; then
            if ! milou_user_exists; then
                log "INFO" "💡 Run: $0 create-user to create dedicated milou user"
            else
                log "INFO" "💡 Run: sudo -u milou $0 [command] to use existing milou user"
            fi
        else
            log "INFO" "💡 Create a non-root user: sudo adduser milou && sudo usermod -aG docker milou"
        fi
        
        ((warnings++))
    else
        log "SUCCESS" "Running as non-root user: $(whoami)"
    fi
    
    # Check operating system compatibility
    local os_info=""
    if [[ -f /etc/os-release ]]; then
        os_info=$(. /etc/os-release && echo "$NAME $VERSION")
        log "DEBUG" "Operating System: $os_info"
    fi
    
    # Check Docker installation and version
    if ! command -v docker >/dev/null 2>&1; then
        log "ERROR" "Docker is not installed"
        log "INFO" "💡 Install automatically: $0 setup --auto-install-deps"
        log "INFO" "💡 Install Docker: https://docs.docker.com/get-docker/"
        log "INFO" "💡 Quick install: curl -fsSL https://get.docker.com | sh"
        ((errors++))
    else
        local docker_version
        docker_version=$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        if [[ -n "$docker_version" ]]; then
            log "DEBUG" "Found Docker version: $docker_version"
            
            if ! version_compare "$docker_version" "$MIN_DOCKER_VERSION" "ge"; then
                log "ERROR" "Docker version $docker_version is too old (minimum: $MIN_DOCKER_VERSION)"
                log "INFO" "💡 Update Docker: https://docs.docker.com/engine/install/"
                ((errors++))
            else
                log "SUCCESS" "Docker version $docker_version meets requirements"
            fi
        else
            log "WARN" "Could not determine Docker version"
            ((warnings++))
        fi
    fi
    
    # Check Docker Compose
    if ! docker compose version >/dev/null 2>&1; then
        log "ERROR" "Docker Compose plugin is not installed"
        log "INFO" "💡 Install automatically: $0 setup --auto-install-deps"
        log "INFO" "💡 Install Docker Compose: https://docs.docker.com/compose/install/"
        log "INFO" "💡 Or update Docker to get the compose plugin"
        ((errors++))
    else
        local compose_version
        compose_version=$(docker compose version --short 2>/dev/null | head -1)
        if [[ -n "$compose_version" ]]; then
            log "DEBUG" "Found Docker Compose version: $compose_version"
            
            if ! version_compare "$compose_version" "$MIN_DOCKER_COMPOSE_VERSION" "ge"; then
                log "WARN" "Docker Compose version $compose_version might be too old (recommended: $MIN_DOCKER_COMPOSE_VERSION+)"
                ((warnings++))
            else
                log "SUCCESS" "Docker Compose version $compose_version meets requirements"
            fi
        else
            log "WARN" "Could not determine Docker Compose version"
            ((warnings++))
        fi
    fi
    
    # Check Docker daemon accessibility
    if ! docker info >/dev/null 2>&1; then
        log "ERROR" "Cannot access Docker daemon"
        log "INFO" "💡 Start Docker daemon: sudo systemctl start docker"
        log "INFO" "💡 Add user to docker group: sudo usermod -aG docker \$USER && newgrp docker"
        log "INFO" "💡 Enable Docker on boot: sudo systemctl enable docker"
        log "INFO" "💡 Auto-configure: $0 setup --auto-install-deps"
        ((errors++))
    else
        log "SUCCESS" "Docker daemon is accessible"
        
        # Get additional Docker info
        local docker_info
        docker_info=$(docker info 2>/dev/null)
        if [[ -n "$docker_info" ]]; then
            local running_containers
            running_containers=$(echo "$docker_info" | grep "Containers:" | awk '{print $2}')
            log "DEBUG" "Docker containers running: ${running_containers:-unknown}"
        fi
    fi
    
    # Check available disk space
    local available_space_kb
    available_space_kb=$(df "$SCRIPT_DIR" 2>/dev/null | awk 'NR==2 {print $4}')
    if [[ -n "$available_space_kb" ]]; then
        local available_space_gb=$((available_space_kb / 1024 / 1024))
        log "DEBUG" "Available disk space: ${available_space_gb}GB"
        
        if [[ $available_space_gb -lt $MIN_DISK_SPACE_GB ]]; then
            log "WARN" "Low disk space: ${available_space_gb}GB available (recommended: ${MIN_DISK_SPACE_GB}GB+)"
            log "INFO" "💡 Clean up disk space: docker system prune -a"
            ((warnings++))
        else
            log "SUCCESS" "Sufficient disk space available: ${available_space_gb}GB"
        fi
    else
        log "WARN" "Could not determine available disk space"
        ((warnings++))
    fi
    
    # Check available RAM
    if command -v free >/dev/null 2>&1; then
        local total_ram_mb available_ram_mb
        total_ram_mb=$(free -m | awk 'NR==2{print $2}')
        available_ram_mb=$(free -m | awk 'NR==2{print $7}')
        
        if [[ -n "$total_ram_mb" && -n "$available_ram_mb" ]]; then
            log "DEBUG" "RAM - Total: ${total_ram_mb}MB, Available: ${available_ram_mb}MB"
            
            if [[ $available_ram_mb -lt $MIN_RAM_MB ]]; then
                log "WARN" "Low available RAM: ${available_ram_mb}MB (recommended: ${MIN_RAM_MB}MB+)"
                log "INFO" "💡 Consider closing other applications or adding more RAM"
                ((warnings++))
            else
                log "SUCCESS" "Sufficient RAM available: ${available_ram_mb}MB"
            fi
        fi
    else
        log "DEBUG" "RAM information not available (free command not found)"
    fi
    
    # Check network connectivity
    log "DEBUG" "Testing network connectivity..."
    local connectivity_test_result
    connectivity_test_result=$(curl -s --connect-timeout 5 --max-time 10 https://ghcr.io/v2/ 2>/dev/null)
    local curl_exit_code=$?
    
    log "DEBUG" "Network test - curl exit code: $curl_exit_code"
    log "DEBUG" "Network test - response length: ${#connectivity_test_result}"
    log "DEBUG" "Network test - response preview: ${connectivity_test_result:0:50}..."
    
    if [[ $curl_exit_code -eq 0 ]]; then
        # If curl succeeded, we have connectivity - response content doesn't matter
        log "SUCCESS" "Network connectivity to GitHub Container Registry confirmed"
        log "DEBUG" "Network test response: ${connectivity_test_result:0:100}..."
    else
        log "WARN" "Cannot reach GitHub Container Registry (network issue?)"
        log "DEBUG" "Network test failed - curl exit code: $curl_exit_code"
        log "INFO" "💡 Check network connection and firewall settings"
        log "INFO" "💡 Test manually: curl -I https://ghcr.io/"
        # Only count as warning if it's a real network failure (not 6=hostname resolution, not 7=connect failure)
        if [[ $curl_exit_code -ne 6 && $curl_exit_code -ne 7 ]]; then
            ((warnings++))
        else
            log "DEBUG" "Network connectivity appears functional (DNS/routing working)"
        fi
    fi
    
    # Check for required commands
    local -a required_commands=("curl" "grep" "awk" "sed" "cut" "sort")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log "WARN" "Missing required commands: ${missing_commands[*]}"
        log "INFO" "💡 Install automatically: $0 setup --auto-install-deps"
        log "INFO" "💡 Install missing commands with your package manager"
        ((warnings++))
    else
        log "SUCCESS" "All required commands are available"
    fi
    
    # Summary
    echo
    log "INFO" "System check summary:"
    log "INFO" "  ${CHECKMARK_EMOJI} Errors: $errors"
    log "INFO" "  ${WARNING_EMOJI} Warnings: $warnings"
    
    if [[ $errors -gt 0 ]]; then
        echo
        log "INFO" "🚀 Quick Fix Options:"
        log "INFO" "  • Run: $0 setup --auto-install-deps (automatic installation)"
        log "INFO" "  • Run: $0 setup --fresh-install (fresh server optimization)"
        log "INFO" "  • Install dependencies manually using the suggestions above"
        echo
        
        if [[ "$FORCE" == true ]]; then
            log "WARN" "Continuing with --force flag despite $errors errors"
            return 0
        else
            error_exit "System requirements check failed ($errors errors, $warnings warnings)"
        fi
    elif [[ $warnings -gt 0 ]]; then
        log "WARN" "System requirements check completed with warnings ($warnings warnings)"
        if [[ "$FORCE" == true ]]; then
            log "WARN" "Continuing with --force flag despite $warnings warnings"
        elif [[ "${INTERACTIVE:-true}" == false ]]; then
            log "INFO" "Non-interactive mode: continuing despite warnings (default: Y)"
        else
            if ! confirm "Continue despite warnings?" "Y"; then
                exit 1
            fi
        fi
    else
        log "SUCCESS" "System requirements check passed successfully"
    fi
}

# =============================================================================
# Enhanced Domain and Network Validation
# =============================================================================

# Validate domain name with enhanced checks
validate_domain() {
    local domain="$1"
    
    if [[ "$domain" == "localhost" ]]; then
        return 0
    fi
    
    # Basic format validation
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi
    
    # Length validation
    if [[ ${#domain} -gt 253 ]]; then
        return 1
    fi
    
    return 0
}

# Validate GitHub token format with enhanced patterns
validate_github_token() {
    local token="$1"
    
    # Support for different GitHub token types
    if [[ ! "$token" =~ ^gh[pousr]_[A-Za-z0-9_]{36,251}$ ]]; then
        return 1
    fi
    
    return 0
}

# =============================================================================
# Enhanced Utility Functions
# =============================================================================

# Check if command exists with enhanced output
command_exists() {
    local cmd="$1"
    local quiet="${2:-false}"
    
    if command -v "$cmd" >/dev/null 2>&1; then
        [[ "$quiet" != true ]] && log "TRACE" "Command '$cmd' is available"
        return 0
    else
        [[ "$quiet" != true ]] && log "TRACE" "Command '$cmd' is not available"
        return 1
    fi
}

# Enhanced system information gathering
get_system_info() {
    log "INFO" "System Information:"
    
    # Basic system info
    echo "  ${GEAR_EMOJI} OS: $(uname -s)"
    echo "  ${GEAR_EMOJI} Architecture: $(uname -m)"
    echo "  ${GEAR_EMOJI} Kernel: $(uname -r)"
    
    # Distribution info
    if [[ -f /etc/os-release ]]; then
        local distro
        distro=$(. /etc/os-release && echo "$NAME $VERSION")
        echo "  ${GEAR_EMOJI} Distribution: $distro"
    fi
    
    # Docker info
    if command_exists docker true; then
        local docker_version
        docker_version=$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',')
        echo "  ${DOCKER_EMOJI} Docker: ${docker_version:-Not available}"
    else
        echo "  ${DOCKER_EMOJI} Docker: Not installed"
    fi
    
    # Docker Compose info
    if command_exists "docker compose" true; then
        local compose_version
        compose_version=$(docker compose version --short 2>/dev/null)
        echo "  ${DOCKER_EMOJI} Docker Compose: ${compose_version:-Not available}"
    else
        echo "  ${DOCKER_EMOJI} Docker Compose: Not available"
    fi
    
    # Memory information
    if command_exists free true; then
        local total_ram_gb available_ram_gb
        total_ram_gb=$(free -g | awk 'NR==2{print $2}')
        available_ram_gb=$(free -g | awk 'NR==2{print $7}')
        echo "  ${DATABASE_EMOJI} RAM: ${available_ram_gb}GB available / ${total_ram_gb}GB total"
    fi
    
    # Disk space
    local available_space_kb
    available_space_kb=$(df "$SCRIPT_DIR" 2>/dev/null | awk 'NR==2 {print $4}')
    if [[ -n "$available_space_kb" ]]; then
        local available_space_gb=$((available_space_kb / 1024 / 1024))
        echo "  ${FOLDER_EMOJI} Disk space: ${available_space_gb}GB available"
    fi
    
    # Network info
    if command_exists ip true; then
        local ip_addr
        ip_addr=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
        echo "  ${NETWORK_EMOJI} IP Address: ${ip_addr:-Unknown}"
    fi
    
    # Load average
    if [[ -f /proc/loadavg ]]; then
        local load_avg
        load_avg=$(cut -d' ' -f1-3 /proc/loadavg)
        echo "  ${CLOCK_EMOJI} Load Average: $load_avg"
    fi
}

# Enhanced cleanup function for temporary files
cleanup_temp() {
    local temp_files=()
    
    # Collect temporary files
    local temp_patterns=(
        "/tmp/milou_*"
        "${CONFIG_DIR}/temp_*"
        "${SCRIPT_DIR}/.temp_*"
    )
    
    for pattern in "${temp_patterns[@]}"; do
        if compgen -G "$pattern" >/dev/null 2>&1; then
            temp_files+=($(compgen -G "$pattern"))
        fi
    done
    
    if [[ ${#temp_files[@]} -gt 0 ]]; then
        log "DEBUG" "Cleaning up ${#temp_files[@]} temporary files"
        for file in "${temp_files[@]}"; do
            if [[ -f "$file" ]]; then
                rm -f "$file"
                log "TRACE" "Removed temporary file: $file"
            fi
        done
    fi
}

# Enhanced backup creation with timestamp
create_timestamped_backup() {
    local source="$1"
    local backup_dir="${2:-${CONFIG_DIR}/backups}"
    local prefix="${3:-}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local basename=$(basename "$source")
    local backup_name="${prefix}${basename}_${timestamp}.backup"
    local backup_path="${backup_dir}/${backup_name}"
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    # Create backup
    if cp "$source" "$backup_path" 2>/dev/null; then
        chmod 600 "$backup_path" 2>/dev/null
        log "INFO" "Backup created: $backup_path"
        echo "$backup_path"
        return 0
    else
        log "ERROR" "Failed to create backup of $source"
        return 1
    fi
}

# Enhanced network connectivity check
check_connectivity() {
    local host="${1:-8.8.8.8}"
    local port="${2:-53}"
    local timeout="${3:-5}"
    
    log "TRACE" "Testing connectivity to $host:$port (timeout: ${timeout}s)"
    
    # Try multiple methods
    if command_exists nc true; then
        if timeout "$timeout" nc -z "$host" "$port" 2>/dev/null; then
            log "TRACE" "Connectivity check passed (nc)"
            return 0
        fi
    fi
    
    if command_exists curl true; then
        if curl -s --connect-timeout "$timeout" --max-time "$timeout" "http://$host:$port" >/dev/null 2>&1; then
            log "TRACE" "Connectivity check passed (curl)"
            return 0
        fi
    fi
    
    if command_exists telnet true; then
        if timeout "$timeout" bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
            log "TRACE" "Connectivity check passed (bash tcp)"
            return 0
        fi
    fi
    
    log "TRACE" "Connectivity check failed for $host:$port"
    return 1
}

# Enhanced argument parsing for global options
parse_global_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --debug)
                DEBUG=true
                VERBOSE=true
                shift
                ;;
            --force|-f)
                FORCE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --quiet|-q)
                QUIET=true
                shift
                ;;
            --no-log)
                LOG_TO_FILE=false
                shift
                ;;
            --non-interactive)
                INTERACTIVE=false
                shift
                ;;
            *)
                # Unknown option, skip for command-specific parsing
                break
                ;;
        esac
    done
}

# Trap cleanup on exit
trap cleanup_temp EXIT

# Export commonly used functions for use in other scripts
export -f log error_exit confirm show_progress validate_input generate_secure_random command_exists