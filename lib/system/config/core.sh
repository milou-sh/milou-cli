#!/bin/bash

# =============================================================================
# Core Configuration Functions for Milou CLI
# Extracted from configuration.sh for better maintainability
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

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
    
    log "TRACE" "Validating configuration inputs"
    
    # Validate domain using enhanced validation
    if ! validate_input "$domain" "domain" true; then
        return 1
    fi
    
    # Validate SSL path - create if doesn't exist
    if [[ -n "$ssl_path" ]]; then
        local ssl_dir=$(dirname "$ssl_path")
        if [[ ! -d "$ssl_dir" ]]; then
            log "DEBUG" "Creating SSL directory: $ssl_dir"
            if ! mkdir -p "$ssl_dir"; then
                log "ERROR" "Failed to create SSL directory: $ssl_dir"
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
    
    log "TRACE" "Configuration inputs validation passed"
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
        log "DEBUG" "Existing installation detected - preserving credentials where possible"
        generate_config_with_preservation "$domain" "$ssl_path" "$admin_email" "auto"
    else
        # Fresh installation - use new credentials
        log "DEBUG" "Fresh installation detected - generating new credentials"
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
        log "ERROR" "Configuration key is required"
        return 1
    fi
    
    if [[ ! -f "$env_file" ]]; then
        log "ERROR" "Configuration file does not exist: $env_file"
        return 1
    fi
    
    # Create backup before modification
    local backup_file
    backup_file=$(create_timestamped_backup "$env_file" "${CONFIG_DIR}/backups" "pre_update_")
    if [[ -z "$backup_file" ]]; then
        log "WARN" "Could not create backup before configuration update"
    fi
    
    log "DEBUG" "Updating configuration key: $key"
    
    # Check if the key exists
    if grep -q "^${key}=" "$env_file"; then
        # Replace the existing value (handle special characters in sed)
        local escaped_value
        escaped_value=$(printf '%s\n' "$value" | sed 's/[[\.*^$()+?{|]/\\&/g')
        if sed -i "s|^${key}=.*|${key}=${escaped_value}|" "$env_file"; then
            log "INFO" "Updated configuration: ${key}"
        else
            log "ERROR" "Failed to update configuration key: $key"
            return 1
        fi
    else
        # Add the key-value pair at the end
        if echo "${key}=${value}" >> "$env_file"; then
            log "INFO" "Added configuration: ${key}"
        else
            log "ERROR" "Failed to add configuration key: $key"
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
        log "ERROR" "Configuration key is required"
        return 1
    fi
    
    # Check if the file exists
    if [[ ! -f "$env_file" ]]; then
        if [[ -n "$default_value" ]]; then
            echo "$default_value"
            return 0
        else
            log "DEBUG" "Configuration file not found: $env_file"
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
        log "DEBUG" "Configuration key not found: $key"
        return 1
    fi
}

# Validate the configuration comprehensively
validate_config() {
    local env_file="${SCRIPT_DIR}/.env"
    
    # Use centralized validation system
    if command -v validate_environment_production >/dev/null 2>&1; then
        validate_environment_production "$env_file"
    else
        # Fallback to basic validation if centralized system not available
        log "WARN" "Centralized validation not available, using fallback"
        
        if [[ ! -f "$env_file" ]]; then
            log "ERROR" "Configuration file not found: $env_file"
            return 1
        fi
        
        log "STEP" "Validating configuration..."
        
        # Basic file checks
        local file_perms
        file_perms=$(stat -c "%a" "$env_file" 2>/dev/null || stat -f "%A" "$env_file" 2>/dev/null || echo "unknown")
        
        if [[ "$file_perms" != "600" ]]; then
            log "WARN" "Configuration file has insecure permissions: $file_perms"
            log "INFO" "Setting secure permissions..."
            if chmod 600 "$env_file"; then
                log "SUCCESS" "Fixed file permissions to 600"
            else
                log "ERROR" "Failed to set secure permissions"
                return 1
            fi
        else
            log "SUCCESS" "Configuration file has secure permissions (600)"
        fi
        
        log "SUCCESS" "Basic configuration validation passed"
        return 0
    fi
}

# Show configuration with sensitive values hidden and enhanced formatting
show_config() {
    local env_file="${SCRIPT_DIR}/.env"
    
    if [[ ! -f "$env_file" ]]; then
        log "ERROR" "Configuration file not found: $env_file"
        return 1
    fi
    
    log "INFO" "Current configuration (sensitive values hidden):"
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
    log "INFO" "Configuration file: $env_file"
    
    # Show enhanced file info
    if command_exists stat true; then
        local file_size file_perms mod_time
        file_size=$(stat -c%s "$env_file" 2>/dev/null || stat -f%z "$env_file" 2>/dev/null || echo "unknown")
        file_perms=$(stat -c "%a" "$env_file" 2>/dev/null || stat -f "%A" "$env_file" 2>/dev/null || echo "unknown")
        mod_time=$(stat -c "%y" "$env_file" 2>/dev/null | cut -d'.' -f1 || stat -f "%Sm" "$env_file" 2>/dev/null || echo "unknown")
        
        echo
        log "INFO" "File information:"
        log "INFO" "  📄 Size: $file_size bytes"
        log "INFO" "  🔒 Permissions: $file_perms"
        log "INFO" "  🕒 Last modified: $mod_time"
        
        # Show configuration statistics
        local total_lines config_lines comment_lines empty_lines
        total_lines=$(wc -l < "$env_file")
        config_lines=$(grep -c "^[A-Z_][A-Z0-9_]*=" "$env_file" 2>/dev/null || echo "0")
        comment_lines=$(grep -c "^#" "$env_file" 2>/dev/null || echo "0")
        empty_lines=$(grep -c "^$" "$env_file" 2>/dev/null || echo "0")
        
        log "INFO" "  📊 Total lines: $total_lines"
        log "INFO" "  ⚙️ Configuration entries: $config_lines"
        log "INFO" "  📝 Comment lines: $comment_lines"
        log "INFO" "  📄 Empty lines: $empty_lines"
    fi
}

# Enhanced validate_configuration function for backward compatibility
validate_configuration() {
    validate_config
}

# =============================================================================
# Export Functions
# =============================================================================

export -f generate_random_string
export -f validate_config_inputs
export -f generate_config
export -f update_config_value
export -f get_config_value
export -f validate_config
export -f show_config
export -f validate_configuration 