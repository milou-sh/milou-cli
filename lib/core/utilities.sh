#!/bin/bash

# =============================================================================
# Milou CLI Core Utilities - Consolidated Edition
# Centralized utility functions to eliminate code duplication
# =============================================================================

# Ensure this script is sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
        exit 1
fi

# =============================================================================
# RANDOM GENERATION UTILITIES (Consolidated from multiple files)
# =============================================================================

# Generate secure random string with specified format
generate_secure_random() {
    local length="${1:-32}"
    local format="${2:-safe}"  # safe, alphanumeric, hex, numeric
    
    case "$format" in
        safe)
            # Safe characters for passwords (excluding ambiguous ones)
            LC_ALL=C tr -dc 'A-HJ-NP-Za-km-z2-9!@#$%^&*()_+-=' </dev/urandom | head -c "$length"
            ;;
        alphanumeric)
            # Only letters and numbers
            LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$length"
            ;;
        hex)
            # Hexadecimal characters
            LC_ALL=C tr -dc 'a-f0-9' </dev/urandom | head -c "$length"
            ;;
        numeric)
            # Only numbers
            LC_ALL=C tr -dc '0-9' </dev/urandom | head -c "$length"
            ;;
        *)
            milou_log "ERROR" "Unknown format: $format"
            return 1
            ;;
    esac
}

# Milou-prefixed alias for compatibility
milou_generate_secure_random() {
    generate_secure_random "$@"
}

# Generate UUID (consolidated from multiple implementations)
generate_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    elif [[ -f /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        # Fallback UUID generation
        printf '%08x-%04x-%04x-%04x-%012x' \
            $((RANDOM * RANDOM)) \
            $((RANDOM)) \
            $((RANDOM | 0x4000)) \
            $((RANDOM | 0x8000)) \
            $((RANDOM * RANDOM * RANDOM))
    fi
}

# =============================================================================
# VALIDATION UTILITIES (Consolidated)
# =============================================================================

# Validate email address
validate_email() {
    local email="$1"
    if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Validate domain name
validate_domain() {
    local domain="$1"
    # Allow localhost and IP addresses for development
    if [[ "$domain" == "localhost" ]] || [[ "$domain" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    fi
    # Validate FQDN
    if [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    else
        return 1
    fi
}

# Validate port number
validate_port() {
    local port="$1"
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    else
        return 1
    fi
}

# Milou-prefixed aliases for compatibility
milou_validate_email() {
    validate_email "$@"
}

milou_validate_domain() {
    validate_domain "$@"
}

milou_validate_port() {
    validate_port "$@"
}

# =============================================================================
# DOCKER UTILITIES (Consolidated)
# =============================================================================

# Check if Docker is available and running
check_docker_available() {
    if ! command -v docker >/dev/null 2>&1; then
        milou_log "ERROR" "Docker is not installed"
        return 1
    fi
    
    if ! docker version >/dev/null 2>&1; then
        milou_log "ERROR" "Docker is not running or not accessible"
        return 1
    fi
    
    return 0
}

# Check if Docker Compose is available
check_docker_compose_available() {
    if docker compose version >/dev/null 2>&1; then
        return 0
    elif command -v docker-compose >/dev/null 2>&1; then
        return 0
    else
        milou_log "ERROR" "Docker Compose is not available"
        return 1
    fi
}

# Get Docker Compose command (handles both 'docker compose' and 'docker-compose')
get_docker_compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        echo "docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        echo "docker-compose"
    else
        echo ""
        return 1
    fi
}

# Pull Docker image with retry logic
pull_docker_image_with_retry() {
    local image="$1"
    local max_retries="${2:-3}"
    local delay="${3:-5}"
    
    for ((i=1; i<=max_retries; i++)); do
        milou_log "INFO" "Pulling $image (attempt $i/$max_retries)"
        if docker pull "$image"; then
            milou_log "SUCCESS" "Successfully pulled $image"
            return 0
        else
            if [[ $i -lt $max_retries ]]; then
                milou_log "WARN" "Failed to pull $image, retrying in ${delay}s..."
                sleep "$delay"
            else
                milou_log "ERROR" "Failed to pull $image after $max_retries attempts"
                return 1
            fi
        fi
    done
}

# =============================================================================
# FILE SYSTEM UTILITIES (Consolidated)
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

# Check if file exists and is readable
check_file_readable() {
    local file_path="$1"
    if [[ -f "$file_path" && -r "$file_path" ]]; then
        return 0
    else
        return 1
    fi
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
# NETWORK UTILITIES (Consolidated)
# =============================================================================

# Check if port is in use
check_port_in_use() {
    local port="$1"
    local protocol="${2:-tcp}"
    
    if command -v netstat >/dev/null 2>&1; then
        netstat -tlnp 2>/dev/null | grep -q ":${port} "
    elif command -v ss >/dev/null 2>&1; then
        ss -tlnp 2>/dev/null | grep -q ":${port} "
    else
        # Fallback: try to bind to the port
        if timeout 1 bash -c "echo >/dev/tcp/localhost/$port" 2>/dev/null; then
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
# USER INTERFACE UTILITIES (Consolidated)
# =============================================================================

# Prompt user for confirmation with timeout
prompt_confirmation() {
    local message="$1"
    local default="${2:-y}"
    local timeout="${3:-30}"
    
    local prompt_suffix
    if [[ "$default" == "y" ]]; then
        prompt_suffix="[Y/n]"
    else
        prompt_suffix="[y/N]"
    fi
    
    echo -n "$message $prompt_suffix: "
    
    if [[ "${INTERACTIVE:-true}" != "true" ]]; then
        echo "$default"
        return 0
    fi
    
    local response
    if read -t "$timeout" -r response; then
        case "${response,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            "") [[ "$default" == "y" ]] && return 0 || return 1 ;;
            *) return 1 ;;
        esac
    else
        echo
        milou_log "WARN" "No response received within ${timeout}s, using default: $default"
        [[ "$default" == "y" ]] && return 0 || return 1
    fi
}

# Display progress bar
display_progress() {
    local current="$1"
    local total="$2"
    local message="${3:-Processing}"
    local width=50
    
    local percentage=$((current * 100 / total))
    local filled=$((width * current / total))
    local empty=$((width - filled))
    
    printf "\r%s [" "$message"
    printf "%*s" "$filled" | tr ' ' '='
    printf "%*s" "$empty" | tr ' ' '-'
    printf "] %d%%" "$percentage"
    
    if [[ $current -eq $total ]]; then
        echo
    fi
}

# =============================================================================
# STRING UTILITIES (Consolidated)
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
# EXPORT FUNCTIONS
# =============================================================================

# Export all utility functions
export -f generate_secure_random generate_uuid milou_generate_secure_random
export -f validate_email validate_domain validate_port
export -f milou_validate_email milou_validate_domain milou_validate_port
export -f check_docker_available check_docker_compose_available get_docker_compose_cmd
export -f pull_docker_image_with_retry
export -f ensure_directory check_file_readable backup_file
export -f check_port_in_use get_available_port
export -f prompt_confirmation display_progress
export -f sanitize_filename to_lowercase to_uppercase trim_whitespace 