#!/bin/bash

# =============================================================================
# Configuration Utility Functions for Milou CLI - State-of-the-Art Edition
# Enhanced with comprehensive configuration management and security
# =============================================================================

# Load all configuration sub-modules
source "${BASH_SOURCE%/*}/config/validation.sh" 2>/dev/null || true
source "${BASH_SOURCE%/*}/config/core.sh" 2>/dev/null || true
source "${BASH_SOURCE%/*}/config/backup.sh" 2>/dev/null || true
source "${BASH_SOURCE%/*}/config/preservation.sh" 2>/dev/null || true
source "${BASH_SOURCE%/*}/config/migration.sh" 2>/dev/null || true

# =============================================================================
# Configuration Generation Functions
# =============================================================================

# Generate a secure random string using enhanced utils
generate_random_string() {
    local length=${1:-32}
    local charset="${2:-alphanumeric}"
    
    # Use the enhanced secure random function from utils.sh
    generate_secure_random "$length" "$charset" true
}

# Validate configuration inputs with enhanced validation
validate_config_inputs() {
    local domain="$1"
    local ssl_path="$2"
    local admin_email="${3:-}"
    
    milou_log "TRACE" "Validating configuration inputs"
    
    # Validate domain using enhanced validation
    if ! validate_input "$domain" "domain" true; then
        return 1
    fi
    
    # Validate SSL path - create if doesn't exist
    if [[ -n "$ssl_path" ]]; then
        local ssl_dir=$(dirname "$ssl_path")
        if [[ ! -d "$ssl_dir" ]]; then
            milou_log "DEBUG" "Creating SSL directory: $ssl_dir"
            if ! mkdir -p "$ssl_dir"; then
                milou_log "ERROR" "Failed to create SSL directory: $ssl_dir"
                return 1
            fi
        fi
    fi
    
    # Validate admin email if provided
    if [[ -n "$admin_email" ]]; then
        if ! validate_input "$admin_email" "email" false; then
            return 1
        fi
    fi
    
    milou_log "TRACE" "Configuration inputs validation passed"
    return 0
}

# Generate a comprehensive configuration file with all required environment variables
generate_config() {
    local domain=${1:-localhost}
    local ssl_path=${2:-./ssl}
    local admin_email="${3:-}"
    
    # Check if this is an existing installation
    # detect_existing_installation returns 0 for fresh install, 1 for existing
    if detect_existing_installation; then
        # Existing installation detected - preserve credentials
        milou_log "DEBUG" "Existing installation detected - preserving credentials where possible"
        generate_config_with_preservation "$domain" "$ssl_path" "$admin_email" "auto"
    else
        # Fresh installation - use new credentials
        milou_log "DEBUG" "Fresh installation detected - generating new credentials"
        generate_config_with_preservation "$domain" "$ssl_path" "$admin_email" "never"
    fi
}

# =============================================================================
# Configuration Management Functions
# =============================================================================

# Update a specific configuration value with enhanced error handling
update_config_value() {
    local key="$1"
    local value="$2"
    local env_file="${SCRIPT_DIR}/.env"
    
    if [[ -z "$key" ]]; then
        milou_log "ERROR" "Configuration key is required"
        return 1
    fi
    
    if [[ ! -f "$env_file" ]]; then
        milou_log "ERROR" "Configuration file does not exist: $env_file"
        return 1
    fi
    
    # Create backup before modification
    local backup_file
    backup_file=$(create_timestamped_backup "$env_file" "${CONFIG_DIR}/backups" "pre_update_")
    if [[ -z "$backup_file" ]]; then
        milou_log "WARN" "Could not create backup before configuration update"
    fi
    
    milou_log "DEBUG" "Updating configuration key: $key"
    
    # Check if the key exists
    if grep -q "^${key}=" "$env_file"; then
        # Replace the existing value (handle special characters in sed)
        local escaped_value
        escaped_value=$(printf '%s\n' "$value" | sed 's/[[\.*^$()+?{|]/\\&/g')
        if sed -i "s|^${key}=.*|${key}=${escaped_value}|" "$env_file"; then
            milou_log "INFO" "Updated configuration: ${key}"
        else
            milou_log "ERROR" "Failed to update configuration key: $key"
            return 1
        fi
    else
        # Add the key-value pair at the end
        if echo "${key}=${value}" >> "$env_file"; then
            milou_log "INFO" "Added configuration: ${key}"
        else
            milou_log "ERROR" "Failed to add configuration key: $key"
            return 1
        fi
    fi
    
    # Ensure file permissions remain secure
    chmod 600 "$env_file" 2>/dev/null
    
    return 0
}

# Get a specific configuration value with enhanced error handling
get_config_value() {
    local key="$1"
    local env_file="${SCRIPT_DIR}/.env"
    local default_value="${2:-}"
    
    if [[ -z "$key" ]]; then
        milou_log "ERROR" "Configuration key is required"
        return 1
    fi
    
    # Check if the file exists
    if [[ ! -f "$env_file" ]]; then
        if [[ -n "$default_value" ]]; then
            echo "$default_value"
            return 0
        else
            milou_log "DEBUG" "Configuration file not found: $env_file"
            return 1
        fi
    fi
    
    # Extract the value
    local value
    value=$(grep "^${key}=" "$env_file" 2>/dev/null | cut -d '=' -f 2-)
    
    if [[ -n "$value" ]]; then
        echo "$value"
        return 0
    elif [[ -n "$default_value" ]]; then
        echo "$default_value"
        return 0
    else
        milou_log "DEBUG" "Configuration key not found: $key"
        return 1
    fi
}

# Validate the configuration comprehensively (delegated to centralized validation)
validate_config() {
    # Use centralized validation system for consistency
    if command -v validate_environment_production >/dev/null 2>&1; then
        validate_environment_production "${SCRIPT_DIR}/.env"
    else
        milou_log "ERROR" "Centralized validation system not available"
        return 1
    fi
}

# Show configuration with sensitive values hidden and enhanced formatting
show_config() {
    local env_file="${SCRIPT_DIR}/.env"
    
    if [[ ! -f "$env_file" ]]; then
        milou_log "ERROR" "Configuration file not found: $env_file"
        return 1
    fi
    
    milou_log "INFO" "Current configuration (sensitive values hidden):"
    echo
    
    # Show configuration but hide sensitive values with better patterns
    sed \
        -e 's/=.*[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd].*/=***HIDDEN***/g' \
        -e 's/=.*[Ss][Ee][Cc][Rr][Ee][Tt].*/=***HIDDEN***/g' \
        -e 's/=.*[Kk][Ee][Yy].*/=***HIDDEN***/g' \
        -e 's/=.*[Tt][Oo][Kk][Ee][Nn].*/=***HIDDEN***/g' \
        -e 's/=.*[Aa][Pp][Ii]_[Kk][Ee][Yy].*/=***HIDDEN***/g' \
        -e 's/=.*JWT_.*/=***HIDDEN***/g' \
        -e 's/=.*ENCRYPTION_.*/=***HIDDEN***/g' \
        "$env_file"
    
    echo
    milou_log "INFO" "Configuration file: $env_file"
    
    # Show enhanced file info
    if command_exists stat true; then
        local file_size file_perms mod_time
        file_size=$(stat -c%s "$env_file" 2>/dev/null || stat -f%z "$env_file" 2>/dev/null || echo "unknown")
        file_perms=$(stat -c "%a" "$env_file" 2>/dev/null || stat -f "%A" "$env_file" 2>/dev/null || echo "unknown")
        mod_time=$(stat -c "%y" "$env_file" 2>/dev/null | cut -d'.' -f1 || stat -f "%Sm" "$env_file" 2>/dev/null || echo "unknown")
        
        echo
        milou_log "INFO" "File information:"
        milou_log "INFO" "  📄 Size: $file_size bytes"
        milou_log "INFO" "  🔒 Permissions: $file_perms"
        milou_log "INFO" "  🕒 Last modified: $mod_time"
        
        # Show configuration statistics
        local total_lines config_lines comment_lines empty_lines
        total_lines=$(wc -l < "$env_file")
        config_lines=$(grep -c "^[A-Z_][A-Z0-9_]*=" "$env_file" 2>/dev/null || echo "0")
        comment_lines=$(grep -c "^#" "$env_file" 2>/dev/null || echo "0")
        empty_lines=$(grep -c "^$" "$env_file" 2>/dev/null || echo "0")
        
        milou_log "INFO" "  📊 Total lines: $total_lines"
        milou_log "INFO" "  ⚙️ Configuration entries: $config_lines"
        milou_log "INFO" "  📝 Comment lines: $comment_lines"
        milou_log "INFO" "  📄 Empty lines: $empty_lines"
    fi
}

# Enhanced validate_configuration function for backward compatibility
validate_configuration() {
    validate_config
}

# =============================================================================
# Configuration Module Complete
# =============================================================================
# All preservation, migration, backup, and validation functions are now
# available through the loaded sub-modules:
# - config/validation.sh - Configuration validation functions
# - config/core.sh - Core configuration generation
# - config/backup.sh - Backup and restore functions  
# - config/preservation.sh - Installation detection and credential preservation
# - config/migration.sh - Configuration migration and modernization
# =============================================================================

# NOTE: detect_existing_installation() is now available from config/preservation.sh

# NOTE: show_existing_installation_summary() is now available from config/preservation.sh

# NOTE: preserve_database_credentials() is now available from config/preservation.sh

# NOTE: generate_config_with_preservation() is now available from config/migration.sh
