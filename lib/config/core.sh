#!/bin/bash

# =============================================================================
# Configuration Core Module for Milou CLI
# Consolidated configuration management, backup, and preservation functions
# =============================================================================

# Module guard to prevent multiple loading
if [[ "${MILOU_CONFIG_CORE_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_CONFIG_CORE_LOADED="true"

# Ensure logging is available
if ! command -v milou_log >/dev/null 2>&1; then
    local script_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
    if [[ -f "${script_dir}/lib/core/logging.sh" ]]; then
        source "${script_dir}/lib/core/logging.sh"
    else
        echo "ERROR: Logging module not available" >&2
        return 1
    fi
fi

# =============================================================================
# Core Configuration Management Functions
# =============================================================================

# Show current configuration
milou_config_show() {
    local env_file="${1:-${SCRIPT_DIR}/.env}"
    
    if [[ ! -f "$env_file" ]]; then
        milou_log "ERROR" "Configuration file not found: $env_file"
        return 1
    fi
    
    milou_log "INFO" "📋 Current Milou Configuration"
    echo "=============================================="
    echo
    
    # System Configuration
    echo "🖥️  System Configuration:"
    _milou_config_show_section "$env_file" "SERVER_NAME|DOMAIN|API_URL|CORS_ORIGIN"
    echo
    
    # Database Configuration
    echo "🗄️  Database Configuration:"
    _milou_config_show_section "$env_file" "DB_HOST|DB_PORT|DB_NAME|DB_USER"
    echo
    
    # Security Configuration
    echo "🔐 Security Configuration:"
    echo "  JWT_SECRET: [Hidden]"
    echo "  ADMIN_PASSWORD: [Hidden]"
    _milou_config_show_section "$env_file" "ADMIN_EMAIL"
    echo
    
    # SSL Configuration
    echo "🔒 SSL Configuration:"
    _milou_config_show_section "$env_file" "SSL_ENABLED|SSL_PATH"
    echo
    
    # Development Configuration
    echo "🔧 Development Configuration:"
    _milou_config_show_section "$env_file" "NODE_ENV|DEBUG|DEV_MODE"
    echo "=============================================="
}

# Helper function to show configuration sections
_milou_config_show_section() {
    local env_file="$1"
    local pattern="$2"
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "$line" ]]; then
            continue
        fi
        
        local key value
        key=$(echo "$line" | cut -d'=' -f1)
        value=$(echo "$line" | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
        
        if echo "$key" | grep -qE "$pattern"; then
            printf "  %-20s: %s\n" "$key" "$value"
        fi
    done < "$env_file"
}

# Update environment variable
milou_config_update_env_variable() {
    local env_file="$1"
    local var_name="$2"
    local var_value="$3"
    local create_backup="${4:-true}"
    
    if [[ ! -f "$env_file" ]]; then
        milou_log "ERROR" "Environment file not found: $env_file"
        return 1
    fi
    
    # Create backup if requested
    if [[ "$create_backup" == "true" ]]; then
        cp "$env_file" "${env_file}.backup.$(date +%s)"
    fi
    
    # Check if variable exists
    if grep -q "^${var_name}=" "$env_file"; then
        # Update existing variable
        sed -i "s/^${var_name}=.*/${var_name}=${var_value}/" "$env_file"
        milou_log "DEBUG" "Updated ${var_name} in ${env_file}"
    else
        # Add new variable
        echo "${var_name}=${var_value}" >> "$env_file"
        milou_log "DEBUG" "Added ${var_name} to ${env_file}"
    fi
    
    return 0
}

# Get environment variable value
milou_config_get_env_variable() {
    local env_file="$1"
    local var_name="$2"
    local default_value="${3:-}"
    
    if [[ ! -f "$env_file" ]]; then
        echo "$default_value"
        return 1
    fi
    
    local value
    value=$(grep "^${var_name}=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    
    if [[ -n "$value" ]]; then
        echo "$value"
        return 0
    else
        echo "$default_value"
        return 1
    fi
}

# Initialize configuration file
milou_config_initialize() {
    local env_file="$1"
    local template_file="${2:-${SCRIPT_DIR}/.env.example}"
    
    milou_log "INFO" "🔧 Initializing configuration file: $env_file"
    
    if [[ -f "$env_file" ]]; then
        milou_log "WARN" "Configuration file already exists, backing up..."
        milou_config_backup_single "$env_file"
    fi
    
    # Copy from template if available
    if [[ -f "$template_file" ]]; then
        cp "$template_file" "$env_file"
        milou_log "SUCCESS" "Configuration initialized from template"
    else
        # Create minimal configuration
        cat > "$env_file" << EOF
# Milou Configuration
# Generated on $(date)

# System
SERVER_NAME=localhost
DOMAIN=localhost
API_URL=https://localhost/api
CORS_ORIGIN=https://localhost

# Database
DB_HOST=milou-database
DB_PORT=5432
DB_NAME=milou
DB_USER=milou
DB_PASSWORD=

# Security
JWT_SECRET=
ADMIN_EMAIL=admin@localhost
ADMIN_PASSWORD=

# SSL
SSL_ENABLED=true
SSL_PATH=./static/ssl

# Development
NODE_ENV=production
DEBUG=false
DEV_MODE=false
EOF
        milou_log "SUCCESS" "Minimal configuration created"
    fi
    
    return 0
}

# =============================================================================
# Configuration Backup Functions
# =============================================================================

# Create comprehensive configuration backup
milou_config_backup() {
    local backup_dir="${1:-./config_backups}"
    local backup_name="${2:-config_backup_$(date +%Y%m%d_%H%M%S)}"
    
    milou_log "INFO" "💾 Creating configuration backup..."
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    local backup_path="$backup_dir/$backup_name"
    mkdir -p "$backup_path"
    
    # Backup main configuration file
    local env_file="${SCRIPT_DIR}/.env"
    if [[ -f "$env_file" ]]; then
        cp "$env_file" "$backup_path/milou.env"
        milou_log "DEBUG" "Backed up main configuration: $env_file"
    fi
    
    # Backup SSL certificates
    local ssl_path="${SCRIPT_DIR}/static/ssl"
    if [[ -d "$ssl_path" && -f "$ssl_path/milou.crt" ]]; then
        mkdir -p "$backup_path/ssl"
        cp -r "$ssl_path"/* "$backup_path/ssl/"
        milou_log "DEBUG" "Backed up SSL certificates: $ssl_path"
    fi
    
    # Backup Docker compose files
    local static_path="${SCRIPT_DIR}/static"
    if [[ -d "$static_path" ]]; then
        mkdir -p "$backup_path/docker"
        find "$static_path" -name "docker-compose*.yml" -exec cp {} "$backup_path/docker/" \;
        milou_log "DEBUG" "Backed up Docker compose files: $static_path"
    fi
    
    # Create backup manifest
    cat > "$backup_path/backup_manifest.txt" << EOF
Milou Configuration Backup
Created: $(date)
Backup Name: $backup_name
Backup Path: $backup_path

Contents:
- milou.env (Main configuration)
- ssl/ (SSL certificates)
- docker/ (Docker compose files)

Restore with:
./milou.sh restore "$backup_path"
EOF
    
    # Create compressed archive
    local archive_path="${backup_dir}/${backup_name}.tar.gz"
    tar -czf "$archive_path" -C "$backup_dir" "$backup_name"
    
    if [[ -f "$archive_path" ]]; then
        rm -rf "$backup_path"  # Remove uncompressed backup
        milou_log "SUCCESS" "✅ Configuration backup created: $archive_path"
        return 0
    else
        milou_log "ERROR" "❌ Failed to create backup archive"
        return 1
    fi
}

# Backup single configuration file
milou_config_backup_single() {
    local config_file="$1"
    local backup_dir="${2:-$(dirname "$config_file")/backups}"
    
    if [[ ! -f "$config_file" ]]; then
        milou_log "ERROR" "Configuration file not found: $config_file"
        return 1
    fi
    
    mkdir -p "$backup_dir"
    
    local filename=$(basename "$config_file")
    local backup_file="$backup_dir/${filename}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if cp "$config_file" "$backup_file"; then
        milou_log "DEBUG" "Configuration backed up: $backup_file"
        return 0
    else
        milou_log "ERROR" "Failed to backup configuration: $config_file"
        return 1
    fi
}

# =============================================================================
# Configuration Preservation Functions
# =============================================================================

# Preserve user configuration during updates
milou_config_preserve_user_settings() {
    local env_file="${1:-${SCRIPT_DIR}/.env}"
    local preserve_file="${env_file}.preserve"
    
    if [[ ! -f "$env_file" ]]; then
        milou_log "WARN" "No configuration file to preserve: $env_file"
        return 1
    fi
    
    milou_log "INFO" "🔄 Preserving user configuration settings..."
    
    # Variables to preserve (user-customizable settings)
    local -a preserve_vars=(
        "SERVER_NAME"
        "DOMAIN" 
        "CUSTOMER_DOMAIN_NAME"
        "API_URL"
        "CORS_ORIGIN"
        "ADMIN_EMAIL"
        "ADMIN_PASSWORD"
        "DB_PASSWORD"
        "JWT_SECRET"
        "ENCRYPTION_KEY"
        "SSL_ENABLED"
        "SSL_PATH"
        "DEBUG"
        "DEV_MODE"
    )
    
    # Create preservation file
    echo "# Preserved user settings from $(date)" > "$preserve_file"
    echo "# Original file: $env_file" >> "$preserve_file"
    echo "" >> "$preserve_file"
    
    local preserved_count=0
    for var in "${preserve_vars[@]}"; do
        local value
        value=$(milou_config_get_env_variable "$env_file" "$var")
        if [[ -n "$value" ]]; then
            echo "${var}=${value}" >> "$preserve_file"
            ((preserved_count++))
        fi
    done
    
    milou_log "SUCCESS" "Preserved $preserved_count configuration variables to: $preserve_file"
    return 0
}

# Restore preserved user settings
milou_config_restore_preserved_settings() {
    local env_file="${1:-${SCRIPT_DIR}/.env}"
    local preserve_file="${env_file}.preserve"
    
    if [[ ! -f "$preserve_file" ]]; then
        milou_log "DEBUG" "No preserved settings file found: $preserve_file"
        return 0
    fi
    
    milou_log "INFO" "🔄 Restoring preserved user configuration..."
    
    local restored_count=0
    while IFS= read -r line; do
        # Skip comments and empty lines
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "$line" ]]; then
            continue
        fi
        
        local var_name var_value
        var_name=$(echo "$line" | cut -d'=' -f1)
        var_value=$(echo "$line" | cut -d'=' -f2-)
        
        if [[ -n "$var_name" && -n "$var_value" ]]; then
            milou_config_update_env_variable "$env_file" "$var_name" "$var_value" "false"
            ((restored_count++))
        fi
    done < "$preserve_file"
    
    milou_log "SUCCESS" "Restored $restored_count preserved settings to: $env_file"
    
    # Clean up preserve file
    rm -f "$preserve_file"
    
    return 0
}

# Merge configuration files
milou_config_merge() {
    local base_file="$1"
    local override_file="$2" 
    local output_file="$3"
    
    if [[ ! -f "$base_file" ]]; then
        milou_log "ERROR" "Base configuration file not found: $base_file"
        return 1
    fi
    
    if [[ ! -f "$override_file" ]]; then
        milou_log "ERROR" "Override configuration file not found: $override_file"
        return 1
    fi
    
    milou_log "INFO" "🔄 Merging configuration files..."
    milou_log "DEBUG" "Base: $base_file"
    milou_log "DEBUG" "Override: $override_file"
    milou_log "DEBUG" "Output: $output_file"
    
    # Start with base file
    cp "$base_file" "$output_file"
    
    # Apply overrides
    local merged_count=0
    while IFS= read -r line; do
        # Skip comments and empty lines
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "$line" ]]; then
            continue
        fi
        
        local var_name var_value
        var_name=$(echo "$line" | cut -d'=' -f1)
        var_value=$(echo "$line" | cut -d'=' -f2-)
        
        if [[ -n "$var_name" && -n "$var_value" ]]; then
            milou_config_update_env_variable "$output_file" "$var_name" "$var_value" "false"
            ((merged_count++))
        fi
    done < "$override_file"
    
    milou_log "SUCCESS" "Merged $merged_count variables into: $output_file"
    return 0
}

# =============================================================================
# Module Exports
# =============================================================================

# Core configuration functions
export -f milou_config_show
export -f milou_config_update_env_variable
export -f milou_config_get_env_variable
export -f milou_config_initialize

# Backup functions
export -f milou_config_backup
export -f milou_config_backup_single

# Preservation functions
export -f milou_config_preserve_user_settings
export -f milou_config_restore_preserved_settings
export -f milou_config_merge

# Helper functions
export -f _milou_config_show_section 