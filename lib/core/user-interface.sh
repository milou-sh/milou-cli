#!/bin/bash

# =============================================================================
# Centralized User Interface Module for Milou CLI
# Consolidates all UI functions with enhanced features and validation
# =============================================================================

# Ensure logging is available
if ! command -v milou_log >/dev/null 2>&1; then
    source "${SCRIPT_DIR}/lib/core/logging.sh" 2>/dev/null || {
        echo "ERROR: Cannot load logging module" >&2
        exit 1
    }
fi

# Colors for UI prompts (can be different from logging colors)
readonly CYAN_PROMPT='\033[0;36m'
readonly YELLOW_PROMPT='\033[1;33m'
readonly NC_PROMPT='\033[0m'
readonly DIM_PROMPT='\033[2m'

# Global UI state
declare -g MILOU_FORCE=${FORCE:-false}
declare -g MILOU_INTERACTIVE=${INTERACTIVE:-true}

# =============================================================================
# Enhanced User Input Functions
# =============================================================================

# Enhanced user input with validation, masking, and variable assignment
milou_prompt_user() {
    local prompt_text="$1"
    local default_value="${2:-}"
    local options="${3:-}"  # Can be: validation_type, variable_name, or options string
    local is_sensitive="${4:-false}"
    local max_attempts="${5:-3}"
    
    local validation_type=""
    local var_to_set=""
    local attempts=0
    
    # Parse options parameter
    if [[ "$options" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        # If options looks like a variable name, use it for assignment
        var_to_set="$options"
    else
        # Otherwise treat as validation type
        validation_type="$options"
    fi
    
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
            if milou_validate_input "$user_input" "$validation_type" true; then
                break
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
            break
        fi
    done
    
    # Set variable if specified
    if [[ -n "$var_to_set" ]]; then
        if printf -v "$var_to_set" '%s' "$user_input"; then
            milou_log "DEBUG" "Set variable $var_to_set successfully"
            return 0
        else
            milou_log "ERROR" "Failed to set variable '$var_to_set'"
            return 1
        fi
    else
        # Return the input value
        echo "$user_input"
        return 0
    fi
}

# Enhanced confirmation prompt with timeout and default handling
milou_confirm() {
    local prompt="$1"
    local default="${2:-N}"
    local timeout="${3:-0}"
    
    # Force mode bypasses confirmation
    if [[ "$MILOU_FORCE" == true ]]; then
        milou_log "DEBUG" "Force mode: auto-confirming '$prompt'"
        return 0
    fi
    
    # Non-interactive mode uses default
    if [[ "$MILOU_INTERACTIVE" == false ]]; then
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
        prompt_text="${CYAN_PROMPT}$prompt [Y/n] (${timeout}s timeout): ${NC_PROMPT}"
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

# Enhanced progress indicator with customizable animation
milou_show_progress() {
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
            echo " Done! ✅"
            ;;
        "spinner")
            local chars="/-\|"
            echo -n "$message "
            for ((i=0; i<steps*4; i++)); do
                printf "\r$message %s" "${chars:$((i%4)):1}"
                sleep "$delay"
            done
            printf "\r$message Done! ✅\n"
            ;;
        "bar")
            echo -n "$message ["
            for ((i=0; i<steps; i++)); do
                echo -n "="
                sleep "$delay"
            done
            echo "] Done! ✅"
            ;;
        "percentage")
            for ((i=0; i<=steps; i++)); do
                local percentage=$((i * 100 / steps))
                printf "\r$message %d%%" "$percentage"
                sleep "$delay"
            done
            printf "\r$message Done! ✅\n"
            ;;
    esac
}

# =============================================================================
# Input Validation Functions
# =============================================================================

# Comprehensive input validation with enhanced patterns
milou_validate_input() {
    local value="$1"
    local type="$2"
    local required="${3:-true}"
    
    # Handle empty values
    if [[ -z "$value" ]]; then
        if [[ "$required" == true ]]; then
            milou_log "DEBUG" "Required field '$type' is empty"
            return 1
        else
            milou_log "DEBUG" "Optional field '$type' is empty, skipping validation"
            return 0
        fi
    fi
    
    milou_log "TRACE" "Validating input '$value' as type '$type'"
    
    case "$type" in
        "github_token")
            if [[ ! "$value" =~ ^gh[pousr]_[A-Za-z0-9_]{36,251}$ ]]; then
                milou_log "ERROR" "Invalid GitHub token format"
                milou_log "INFO" "Expected patterns: ghp_*, gho_*, ghu_*, ghs_*, ghr_*"
                milou_log "INFO" "Token should be 40+ characters long"
                return 1
            fi
            ;;
        "domain")
            if [[ "$value" != "localhost" ]]; then
                if [[ ! "$value" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
                    milou_log "ERROR" "Invalid domain format: $value"
                    return 1
                fi
                if [[ ${#value} -gt 253 ]]; then
                    milou_log "ERROR" "Domain name too long (max 253 characters): ${#value}"
                    return 1
                fi
            fi
            ;;
        "email")
            if [[ ! "$value" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
                milou_log "ERROR" "Invalid email format: $value"
                return 1
            fi
            if [[ ${#value} -gt 254 ]]; then
                milou_log "ERROR" "Email address too long (max 254 characters)"
                return 1
            fi
            ;;
        "ssl_path")
            if [[ -n "$value" ]]; then
                local ssl_dir=$(dirname "$value")
                if [[ ! -d "$ssl_dir" ]]; then
                    milou_log "WARN" "SSL directory does not exist: $ssl_dir"
                    if milou_confirm "Create SSL directory?" "Y"; then
                        mkdir -p "$ssl_dir" || {
                            milou_log "ERROR" "Failed to create SSL directory"
                            return 1
                        }
                    else
                        return 1
                    fi
                fi
            fi
            ;;
        "path")
            if [[ ! -e "$value" ]]; then
                milou_log "ERROR" "Path does not exist: $value"
                return 1
            fi
            ;;
        "directory")
            if [[ ! -d "$value" ]]; then
                milou_log "ERROR" "Directory does not exist: $value"
                return 1
            fi
            ;;
        "file")
            if [[ ! -f "$value" ]]; then
                milou_log "ERROR" "File does not exist: $value"
                return 1
            fi
            ;;
        "port")
            if [[ ! "$value" =~ ^[1-9][0-9]{0,4}$ ]] || [[ "$value" -gt 65535 ]]; then
                milou_log "ERROR" "Invalid port number: $value (must be 1-65535)"
                return 1
            fi
            ;;
        "version")
            if [[ ! "$value" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?(\+[a-zA-Z0-9.-]+)?$ ]]; then
                milou_log "ERROR" "Invalid version format: $value (expected: x.y.z or vx.y.z)"
                return 1
            fi
            ;;
        "url")
            if [[ ! "$value" =~ ^https?://[a-zA-Z0-9.-]+[a-zA-Z0-9.-/]*$ ]]; then
                milou_log "ERROR" "Invalid URL format: $value"
                return 1
            fi
            ;;
        "ip")
            if [[ ! "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                milou_log "ERROR" "Invalid IP address format: $value"
                return 1
            fi
            # Validate IP ranges
            local IFS='.'
            local -a ip_parts=($value)
            for part in "${ip_parts[@]}"; do
                if [[ $part -gt 255 ]]; then
                    milou_log "ERROR" "Invalid IP address range: $value"
                    return 1
                fi
            done
            ;;
        "uuid")
            if [[ ! "$value" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
                milou_log "ERROR" "Invalid UUID format: $value"
                return 1
            fi
            ;;
    esac
    
    milou_log "TRACE" "Input validation passed for '$type': $value"
    return 0
}

# =============================================================================
# Menu and Selection Functions
# =============================================================================

# Interactive menu selection
milou_select_option() {
    local prompt="$1"
    shift
    local -a options=("$@")
    
    if [[ ${#options[@]} -eq 0 ]]; then
        milou_log "ERROR" "No options provided for selection"
        return 1
    fi
    
    echo "$prompt"
    for i in "${!options[@]}"; do
        echo "$((i+1))) ${options[i]}"
    done
    echo
    
    while true; do
        echo -ne "${CYAN_PROMPT}Enter your choice (1-${#options[@]}): ${NC_PROMPT}"
        read -r choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#options[@]} ]]; then
            echo "${options[$((choice-1))]}"
            return $((choice-1))
        else
            echo "Invalid choice. Please enter a number between 1 and ${#options[@]}."
        fi
    done
}

# =============================================================================
# Backward Compatibility Aliases
# =============================================================================

# Maintain backward compatibility with existing code
prompt_user() { milou_prompt_user "$@"; }
confirm() { milou_confirm "$@"; }
show_progress() { milou_show_progress "$@"; }
validate_input() { milou_validate_input "$@"; }

# Export all functions
export -f milou_prompt_user milou_confirm milou_show_progress milou_validate_input milou_select_option
export -f prompt_user confirm show_progress validate_input 