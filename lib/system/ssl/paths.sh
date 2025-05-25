#!/bin/bash

# =============================================================================
# SSL Path Resolution Module for Milou CLI
# Handles SSL path resolution and Docker compatibility
# =============================================================================

# Module guard to prevent multiple loading
if [[ "${MILOU_SSL_PATHS_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_SSL_PATHS_LOADED="true"

# Ensure logging is available
if ! command -v milou_log >/dev/null 2>&1; then
    source "${SCRIPT_DIR}/lib/core/logging.sh" 2>/dev/null || {
        echo "ERROR: Cannot load logging module" >&2
        exit 1
    }
fi

# =============================================================================
# SSL Path Resolution Functions
# =============================================================================

# Resolve SSL path properly to avoid static folder conflicts
resolve_ssl_path() {
    local provided_path="$1"
    local working_dir="${2:-$(pwd)}"
    
    # If path is absolute, use as-is
    if [[ "$provided_path" = "/"* ]]; then
        echo "$provided_path"
        return 0
    fi
    
    # Resolve relative path relative to working directory
    local resolved_path
    resolved_path="$(cd "$working_dir" && cd "$provided_path" 2>/dev/null && pwd)" || {
        # If the path doesn't exist yet, create it and resolve
        mkdir -p "$working_dir/$provided_path"
        resolved_path="$(cd "$working_dir" && cd "$provided_path" && pwd)"
    }
    
    echo "$resolved_path"
}

# Get the appropriate SSL path based on environment
get_appropriate_ssl_path() {
    local default_path="${1:-./ssl}"
    local working_dir="${2:-$(pwd)}"
    
    # CENTRALIZED SSL LOCATION: Always use static/ssl for milou-cli environment
    if [[ "$(basename "$working_dir")" == "milou-cli" ]] && [[ -d "$working_dir/static" ]]; then
        # We're in milou-cli directory - SSL is ALWAYS in static/ssl for Docker compatibility
        local static_ssl_path="$working_dir/static/ssl"
        milou_log "DEBUG" "Using centralized SSL path: $static_ssl_path" >&2
        echo "$static_ssl_path"
    elif [[ "$(basename "$working_dir")" == "static" ]]; then
        # We're in static directory - use ssl subdirectory
        local static_ssl_path="$working_dir/ssl"
        milou_log "DEBUG" "Using static-relative SSL path: $static_ssl_path" >&2
        echo "$static_ssl_path"
    else
        # Other environments - resolve path normally
        resolve_ssl_path "$default_path" "$working_dir"
    fi
}

# Ensure SSL certificates exist in the correct location for Docker mounting
ensure_docker_compatible_ssl() {
    local ssl_path="$1"
    local working_dir="${2:-$(pwd)}"
    
    # For milou-cli environment, we always use static/ssl (centralized location)
    if [[ "$(basename "$working_dir")" == "milou-cli" ]] && [[ -d "$working_dir/static" ]]; then
        local static_ssl_dir="$working_dir/static/ssl"
        
        # Create static SSL directory if it doesn't exist
        mkdir -p "$static_ssl_dir"
        
        # If the provided path is not our centralized location, migrate certificates
        if [[ "$ssl_path" != "$static_ssl_dir" ]] && [[ -f "$ssl_path/milou.crt" && -f "$ssl_path/milou.key" ]]; then
            milou_log "INFO" "Migrating SSL certificates to centralized location: $static_ssl_dir"
            cp "$ssl_path/milou.crt" "$static_ssl_dir/milou.crt"
            cp "$ssl_path/milou.key" "$static_ssl_dir/milou.key"
            chmod 644 "$static_ssl_dir/milou.crt"
            chmod 600 "$static_ssl_dir/milou.key"
            milou_log "SUCCESS" "SSL certificates migrated to centralized location"
        fi
        
        # Always return the centralized path
        echo "$static_ssl_dir"
    else
        # For other environments, return the original path
        echo "$ssl_path"
    fi
}

# Normalize SSL path for consistent usage
normalize_ssl_path() {
    local ssl_path="$1"
    local working_dir="${2:-$(pwd)}"
    
    # Remove trailing slashes
    ssl_path="${ssl_path%/}"
    
    # If it's a relative path, make it absolute
    if [[ "$ssl_path" != "/"* ]]; then
        ssl_path="$working_dir/$ssl_path"
    fi
    
    # Resolve any .. or . in the path
    ssl_path=$(cd "$(dirname "$ssl_path")" && pwd)/$(basename "$ssl_path")
    
    echo "$ssl_path"
}

# Get SSL path relative to a specific directory
get_relative_ssl_path() {
    local ssl_path="$1"
    local base_dir="${2:-$(pwd)}"
    
    # Normalize both paths
    ssl_path=$(normalize_ssl_path "$ssl_path")
    base_dir=$(cd "$base_dir" && pwd)
    
    # Calculate relative path
    local relative_path
    relative_path=$(realpath --relative-to="$base_dir" "$ssl_path" 2>/dev/null || {
        # Fallback for systems without realpath
        python3 -c "import os.path; print(os.path.relpath('$ssl_path', '$base_dir'))" 2>/dev/null || {
            # Last resort - simple calculation
            echo "${ssl_path#$base_dir/}"
        }
    })
    
    echo "$relative_path"
}

# =============================================================================
# Docker Compatibility Functions
# =============================================================================

# Check if SSL path is Docker-compatible
is_docker_compatible_path() {
    local ssl_path="$1"
    local working_dir="${2:-$(pwd)}"
    
    # If we're in milou-cli directory, SSL should be in static/ssl
    if [[ "$(basename "$working_dir")" == "milou-cli" ]]; then
        local expected_path="$working_dir/static/ssl"
        if [[ "$ssl_path" == "$expected_path" ]]; then
            return 0
        else
            milou_log "DEBUG" "SSL path not Docker-compatible: $ssl_path (expected: $expected_path)"
            return 1
        fi
    fi
    
    # For other environments, any accessible path is fine
    return 0
}

# Prepare SSL path for Docker usage
prepare_ssl_for_docker() {
    local ssl_path="$1"
    local working_dir="${2:-$(pwd)}"
    
    milou_log "DEBUG" "Preparing SSL path for Docker: $ssl_path"
    
    # Ensure the path exists
    mkdir -p "$ssl_path"
    
    # Get Docker-compatible path
    local docker_ssl_path
    docker_ssl_path=$(ensure_docker_compatible_ssl "$ssl_path" "$working_dir")
    
    # Validate Docker compatibility
    if is_docker_compatible_path "$docker_ssl_path" "$working_dir"; then
        milou_log "SUCCESS" "SSL path prepared for Docker: $docker_ssl_path"
        echo "$docker_ssl_path"
        return 0
    else
        milou_log "WARN" "SSL path may not be fully Docker-compatible: $docker_ssl_path"
        echo "$docker_ssl_path"
        return 1
    fi
}

# Get Docker mount path for SSL
get_docker_mount_path() {
    local ssl_path="$1"
    local working_dir="${2:-$(pwd)}"
    
    # For milou-cli environment, Docker mounts static/ssl as /ssl
    if [[ "$(basename "$working_dir")" == "milou-cli" ]]; then
        echo "/ssl"
    else
        # For other environments, use the relative path
        local relative_path
        relative_path=$(get_relative_ssl_path "$ssl_path" "$working_dir")
        echo "/$relative_path"
    fi
}

# Get SSL path for environment file generation (relative to docker-compose.yml location)
get_ssl_path_for_env() {
    local working_dir="${1:-$(pwd)}"
    
    # For milou-cli environment, docker-compose.yml is in static/ directory
    # So SSL path should be relative to that directory
    if [[ "$(basename "$working_dir")" == "milou-cli" ]] && [[ -d "$working_dir/static" ]]; then
        # SSL certificates are in static/ssl, but docker-compose.yml is also in static/
        # So the relative path from static/ to static/ssl is just "./ssl"
        milou_log "DEBUG" "Environment SSL path: ./ssl (relative to static/ directory)" >&2
        echo "./ssl"
    else
        # For other environments, use default
        echo "./ssl"
    fi
}

# =============================================================================
# SSL Path Validation Functions
# =============================================================================

# Validate SSL path accessibility
validate_ssl_path_access() {
    local ssl_path="$1"
    
    milou_log "DEBUG" "Validating SSL path accessibility: $ssl_path"
    
    # Check if directory exists
    if [[ ! -d "$ssl_path" ]]; then
        milou_log "DEBUG" "SSL directory does not exist, attempting to create: $ssl_path"
        if ! mkdir -p "$ssl_path"; then
            milou_log "ERROR" "Cannot create SSL directory: $ssl_path"
            return 1
        fi
    fi
    
    # Check write permissions
    if [[ ! -w "$ssl_path" ]]; then
        milou_log "ERROR" "SSL directory is not writable: $ssl_path"
        return 1
    fi
    
    # Check if we can create files
    local test_file="$ssl_path/.test_write_$$"
    if ! touch "$test_file" 2>/dev/null; then
        milou_log "ERROR" "Cannot create files in SSL directory: $ssl_path"
        return 1
    fi
    rm -f "$test_file"
    
    milou_log "DEBUG" "SSL path accessibility validation passed: $ssl_path"
    return 0
}

# Check SSL path security
check_ssl_path_security() {
    local ssl_path="$1"
    
    milou_log "DEBUG" "Checking SSL path security: $ssl_path"
    
    # Check directory permissions
    local dir_perms
    dir_perms=$(stat -c "%a" "$ssl_path" 2>/dev/null || echo "unknown")
    
    if [[ "$dir_perms" != "755" && "$dir_perms" != "750" ]]; then
        milou_log "WARN" "SSL directory permissions may be too permissive: $dir_perms"
    fi
    
    # Check if directory is world-writable
    if [[ -w "$ssl_path" ]] && [[ $(stat -c "%a" "$ssl_path" | cut -c3) -ge 2 ]]; then
        milou_log "WARN" "SSL directory is world-writable - security risk"
        return 1
    fi
    
    # Check parent directory security
    local parent_dir
    parent_dir=$(dirname "$ssl_path")
    if [[ -w "$parent_dir" ]] && [[ $(stat -c "%a" "$parent_dir" | cut -c3) -ge 2 ]]; then
        milou_log "WARN" "SSL parent directory is world-writable - potential security risk"
    fi
    
    milou_log "DEBUG" "SSL path security check completed: $ssl_path"
    return 0
}

# =============================================================================
# SSL Path Migration Functions
# =============================================================================

# Migrate SSL certificates to new path
migrate_ssl_path() {
    local old_path="$1"
    local new_path="$2"
    local backup="${3:-true}"
    
    milou_log "INFO" "Migrating SSL certificates from $old_path to $new_path"
    
    # Validate source path
    if [[ ! -d "$old_path" ]]; then
        milou_log "ERROR" "Source SSL path does not exist: $old_path"
        return 1
    fi
    
    # Check if certificates exist in source
    if [[ ! -f "$old_path/milou.crt" || ! -f "$old_path/milou.key" ]]; then
        milou_log "ERROR" "SSL certificates not found in source path: $old_path"
        return 1
    fi
    
    # Create destination directory
    mkdir -p "$new_path"
    
    # Validate destination path
    if ! validate_ssl_path_access "$new_path"; then
        milou_log "ERROR" "Destination SSL path is not accessible: $new_path"
        return 1
    fi
    
    # Backup existing certificates in destination if they exist
    if [[ "$backup" == "true" ]] && [[ -f "$new_path/milou.crt" ]]; then
        local backup_name="ssl_migration_backup_$(date +%s)"
        milou_log "INFO" "Backing up existing certificates in destination"
        backup_ssl_certificates "$new_path" "$new_path/backups" "$backup_name"
    fi
    
    # Copy certificates
    if cp "$old_path/milou.crt" "$new_path/milou.crt" && cp "$old_path/milou.key" "$new_path/milou.key"; then
        # Set appropriate permissions
        chmod 644 "$new_path/milou.crt"
        chmod 600 "$new_path/milou.key"
        
        milou_log "SUCCESS" "SSL certificates migrated successfully"
        milou_log "INFO" "  From: $old_path"
        milou_log "INFO" "  To: $new_path"
        
        # Validate migrated certificates
        if validate_ssl_certificates "$new_path/milou.crt" "$new_path/milou.key"; then
            milou_log "SUCCESS" "Migrated certificates validation passed"
            return 0
        else
            milou_log "ERROR" "Migrated certificates validation failed"
            return 1
        fi
    else
        milou_log "ERROR" "Failed to copy SSL certificates to new path"
        return 1
    fi
}

# Find SSL certificates in common locations
find_ssl_certificates() {
    local search_base="${1:-$(pwd)}"
    
    milou_log "DEBUG" "Searching for SSL certificates starting from: $search_base"
    
    # Common SSL certificate locations relative to search base
    local -a search_paths=(
        "$search_base/ssl"
        "$search_base/static/ssl"
        "$search_base/../ssl"
        "$search_base/certs"
        "$search_base/certificates"
        "/etc/ssl/certs"
        "/etc/nginx/ssl"
        "/etc/apache2/ssl"
        "/opt/ssl"
        "$HOME/ssl"
    )
    
    local found_paths=()
    
    # Search for certificates
    for search_path in "${search_paths[@]}"; do
        if [[ -f "$search_path/milou.crt" && -f "$search_path/milou.key" ]]; then
            milou_log "DEBUG" "Found SSL certificates at: $search_path"
            found_paths+=("$search_path")
        fi
    done
    
    # Return found paths
    if [[ ${#found_paths[@]} -gt 0 ]]; then
        printf '%s\n' "${found_paths[@]}"
        return 0
    else
        milou_log "DEBUG" "No SSL certificates found in common locations"
        return 1
    fi
}

milou_log "DEBUG" "SSL path resolution module loaded successfully" 