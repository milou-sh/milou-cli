#!/bin/bash

# =============================================================================
# Core Utilities Module for Milou CLI
# Contains unique utility functions not covered by other modules
# =============================================================================

# Ensure logging is available
if ! command -v milou_log >/dev/null 2>&1; then
    source "${SCRIPT_DIR}/lib/core/logging.sh" 2>/dev/null || {
        echo "ERROR: Cannot load logging module" >&2
        exit 1
    }
fi

# Constants
readonly MIN_DOCKER_VERSION="20.10.0"
readonly MIN_DOCKER_COMPOSE_VERSION="2.0.0"
readonly MIN_DISK_SPACE_GB=2
readonly MIN_RAM_MB=2048

# =============================================================================
# Secure Random Generation
# =============================================================================

# Generate secure random strings with multiple methods
milou_generate_secure_random() {
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
    
    milou_log "TRACE" "Generating secure random string: length=$length, charset=$charset"
    
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
        milou_log "WARN" "Using fallback random generation method (less secure)"
        result=""
        for ((i=0; i<length; i++)); do
            result+="${chars:$((RANDOM % ${#chars})):1}"
        done
    fi
    
    # Ensure we have the requested length
    if [[ ${#result} -lt $length ]]; then
        milou_log "WARN" "Generated string shorter than requested, padding with additional entropy"
        while [[ ${#result} -lt $length ]]; do
            result+="${chars:$((RANDOM % ${#chars})):1}"
        done
    fi
    
    # Trim to exact length
    result="${result:0:$length}"
    
    milou_log "TRACE" "Generated secure random string of length ${#result}"
    echo "$result"
}

# =============================================================================
# System Requirements and Health Checks
# =============================================================================

# Check system requirements comprehensively
milou_check_system_requirements() {
    milou_log "STEP" "Checking system requirements..."
    
    local errors=0
    local warnings=0
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        milou_log "WARN" "Running as root - not recommended for security reasons"
        milou_log "INFO" "💡 Consider using dedicated user for better security"
        
        # If user management is available, offer to create milou user
        if command -v milou_user_exists >/dev/null 2>&1; then
            if ! milou_user_exists; then
                milou_log "INFO" "💡 Run: $0 create-user to create dedicated milou user"
            else
                milou_log "INFO" "💡 Run: sudo -u milou $0 [command] to use existing milou user"
            fi
        else
            milou_log "INFO" "💡 Create a non-root user: sudo adduser milou && sudo usermod -aG docker milou"
        fi
        
        ((warnings++))
    else
        milou_log "SUCCESS" "Running as non-root user: $(whoami)"
    fi
    
    # Check operating system compatibility
    local os_info=""
    if [[ -f /etc/os-release ]]; then
        os_info=$(. /etc/os-release && echo "$NAME $VERSION")
        milou_log "DEBUG" "Operating System: $os_info"
    fi
    
    # Check Docker installation and version
    if ! command -v docker >/dev/null 2>&1; then
        milou_log "ERROR" "Docker is not installed"
        milou_log "INFO" "💡 Install automatically: $0 setup --auto-install-deps"
        milou_log "INFO" "💡 Install Docker: https://docs.docker.com/get-docker/"
        milou_log "INFO" "💡 Quick install: curl -fsSL https://get.docker.com | sh"
        ((errors++))
    else
        local docker_version
        docker_version=$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        if [[ -n "$docker_version" ]]; then
            milou_log "DEBUG" "Found Docker version: $docker_version"
            
            if command -v milou_version_compare >/dev/null 2>&1; then
                if ! milou_version_compare "$docker_version" "$MIN_DOCKER_VERSION" "ge"; then
                    milou_log "ERROR" "Docker version $docker_version is too old (minimum: $MIN_DOCKER_VERSION)"
                    milou_log "INFO" "💡 Update Docker: https://docs.docker.com/engine/install/"
                    ((errors++))
                else
                    milou_log "SUCCESS" "Docker version $docker_version meets requirements"
                fi
            else
                milou_log "SUCCESS" "Docker version $docker_version found"
            fi
        else
            milou_log "WARN" "Could not determine Docker version"
            ((warnings++))
        fi
    fi
    
    # Check Docker Compose
    if ! docker compose version >/dev/null 2>&1; then
        milou_log "ERROR" "Docker Compose plugin is not installed"
        milou_log "INFO" "💡 Install automatically: $0 setup --auto-install-deps"
        milou_log "INFO" "💡 Install Docker Compose: https://docs.docker.com/compose/install/"
        milou_log "INFO" "💡 Or update Docker to get the compose plugin"
        ((errors++))
    else
        local compose_version
        compose_version=$(docker compose version --short 2>/dev/null | head -1)
        if [[ -n "$compose_version" ]]; then
            milou_log "DEBUG" "Found Docker Compose version: $compose_version"
            
            if command -v milou_version_compare >/dev/null 2>&1; then
                if ! milou_version_compare "$compose_version" "$MIN_DOCKER_COMPOSE_VERSION" "ge"; then
                    milou_log "WARN" "Docker Compose version $compose_version might be too old (recommended: $MIN_DOCKER_COMPOSE_VERSION+)"
                    ((warnings++))
                else
                    milou_log "SUCCESS" "Docker Compose version $compose_version meets requirements"
                fi
            else
                milou_log "SUCCESS" "Docker Compose version $compose_version found"
            fi
        else
            milou_log "WARN" "Could not determine Docker Compose version"
            ((warnings++))
        fi
    fi
    
    # Check Docker daemon accessibility
    if ! docker info >/dev/null 2>&1; then
        milou_log "ERROR" "Cannot access Docker daemon"
        milou_log "INFO" "💡 Start Docker daemon: sudo systemctl start docker"
        milou_log "INFO" "💡 Add user to docker group: sudo usermod -aG docker \$USER && newgrp docker"
        ((errors++))
    else
        milou_log "SUCCESS" "Docker daemon is accessible"
    fi
    
    # Check available disk space
    local available_space_gb
    available_space_gb=$(df . | awk 'NR==2 {printf "%.1f", $4/1024/1024}')
    if [[ -n "$available_space_gb" ]]; then
        if (( $(echo "$available_space_gb < $MIN_DISK_SPACE_GB" | bc -l 2>/dev/null || echo "0") )); then
            milou_log "WARN" "Low disk space: ${available_space_gb}GB available (recommended: ${MIN_DISK_SPACE_GB}GB+)"
            ((warnings++))
        else
            milou_log "SUCCESS" "Sufficient disk space: ${available_space_gb}GB available"
        fi
    fi
    
    # Check available memory
    local available_ram_mb
    if [[ -f /proc/meminfo ]]; then
        available_ram_mb=$(awk '/MemAvailable/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null)
        if [[ -n "$available_ram_mb" && "$available_ram_mb" -gt 0 ]]; then
            if [[ "$available_ram_mb" -lt "$MIN_RAM_MB" ]]; then
                milou_log "WARN" "Low available memory: ${available_ram_mb}MB (recommended: ${MIN_RAM_MB}MB+)"
                ((warnings++))
            else
                milou_log "SUCCESS" "Sufficient memory: ${available_ram_mb}MB available"
            fi
        fi
    fi
    
    # Summary
    if [[ $errors -gt 0 ]]; then
        milou_log "ERROR" "System requirements check failed: $errors error(s), $warnings warning(s)"
        return 1
    elif [[ $warnings -gt 0 ]]; then
        milou_log "WARN" "System requirements check completed with warnings: $warnings warning(s)"
        return 0
    else
        milou_log "SUCCESS" "All system requirements met"
        return 0
    fi
}

# =============================================================================
# System Information
# =============================================================================

# Get comprehensive system information
milou_get_system_info() {
    local info_type="${1:-all}"
    
    case "$info_type" in
        "os"|"all")
            if [[ -f /etc/os-release ]]; then
                . /etc/os-release
                echo "OS: $NAME $VERSION"
            elif [[ -f /etc/redhat-release ]]; then
                echo "OS: $(cat /etc/redhat-release)"
            else
                echo "OS: $(uname -s) $(uname -r)"
            fi
            [[ "$info_type" != "all" ]] && return
            ;;
    esac
    
    case "$info_type" in
        "kernel"|"all")
            echo "Kernel: $(uname -r)"
            [[ "$info_type" != "all" ]] && return
            ;;
    esac
    
    case "$info_type" in
        "arch"|"all")
            echo "Architecture: $(uname -m)"
            [[ "$info_type" != "all" ]] && return
            ;;
    esac
    
    case "$info_type" in
        "memory"|"all")
            if [[ -f /proc/meminfo ]]; then
                local total_ram_gb
                total_ram_gb=$(awk '/MemTotal/ {printf "%.1f", $2/1024/1024}' /proc/meminfo)
                echo "Memory: ${total_ram_gb}GB"
            fi
            [[ "$info_type" != "all" ]] && return
            ;;
    esac
    
    case "$info_type" in
        "disk"|"all")
            local disk_space_gb
            disk_space_gb=$(df -h . | awk 'NR==2 {print $4}')
            echo "Available disk space: $disk_space_gb"
            [[ "$info_type" != "all" ]] && return
            ;;
    esac
}

# =============================================================================
# Cleanup and Maintenance
# =============================================================================

# Clean up temporary files
milou_cleanup_temp() {
    local temp_patterns=(
        "/tmp/milou_*"
        "/tmp/.milou_*"
        "${TMPDIR:-/tmp}/milou_*"
        "${CONFIG_DIR:-$HOME/.milou}/tmp/*"
    )
    
    milou_log "DEBUG" "Cleaning up temporary files..."
    
    local cleaned_count=0
    for pattern in "${temp_patterns[@]}"; do
        # Use find to safely handle patterns
        if find "$(dirname "$pattern")" -maxdepth 1 -name "$(basename "$pattern")" -type f -mtime +1 2>/dev/null | while read -r file; do
            if rm -f "$file" 2>/dev/null; then
                ((cleaned_count++))
                milou_log "TRACE" "Removed temporary file: $file"
            fi
        done; then
            continue
        fi
    done
    
    if [[ $cleaned_count -gt 0 ]]; then
        milou_log "DEBUG" "Cleaned up $cleaned_count temporary files"
    else
        milou_log "TRACE" "No temporary files to clean up"
    fi
}

# Create timestamped backup
milou_create_timestamped_backup() {
    local source_file="$1"
    local backup_dir="${2:-$(dirname "$source_file")}"
    local prefix="${3:-backup_}"
    
    if [[ ! -f "$source_file" ]]; then
        milou_log "ERROR" "Source file does not exist: $source_file"
        return 1
    fi
    
    # Create backup directory if it doesn't exist
    if ! mkdir -p "$backup_dir" 2>/dev/null; then
        milou_log "ERROR" "Cannot create backup directory: $backup_dir"
        return 1
    fi
    
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local filename
    filename=$(basename "$source_file")
    local backup_file="${backup_dir}/${prefix}${filename}.${timestamp}"
    
    if cp "$source_file" "$backup_file" 2>/dev/null; then
        milou_log "DEBUG" "Created backup: $backup_file"
        echo "$backup_file"
        return 0
    else
        milou_log "ERROR" "Failed to create backup of: $source_file"
        return 1
    fi
}

# =============================================================================
# Backward Compatibility Aliases
# =============================================================================

# Maintain backward compatibility with existing function names
generate_secure_random() { milou_generate_secure_random "$@"; }
check_system_requirements() { milou_check_system_requirements "$@"; }
get_system_info() { milou_get_system_info "$@"; }
cleanup_temp() { milou_cleanup_temp "$@"; }
create_timestamped_backup() { milou_create_timestamped_backup "$@"; }

# Export functions for external use
export -f milou_generate_secure_random milou_check_system_requirements
export -f milou_get_system_info milou_cleanup_temp milou_create_timestamped_backup

# Export backward compatibility functions
export -f generate_secure_random check_system_requirements get_system_info
export -f cleanup_temp create_timestamped_backup 