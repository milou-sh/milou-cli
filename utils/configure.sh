#!/bin/bash

# =============================================================================
# Configuration Utility Functions for Milou CLI - State-of-the-Art Edition
# Enhanced with comprehensive configuration management and security
# =============================================================================

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
    if detect_existing_installation; then
        # Fresh installation - use new credentials
        log "DEBUG" "Fresh installation detected - generating new credentials"
        generate_config_with_preservation "$domain" "$ssl_path" "$admin_email" "never"
    else
        # Existing installation - preserve credentials
        log "DEBUG" "Existing installation detected - preserving credentials where possible"
        generate_config_with_preservation "$domain" "$ssl_path" "$admin_email" "auto"
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
    
    log "STEP" "Validating configuration..."
    
    # Check if the file exists
    if [[ ! -f "$env_file" ]]; then
        log "ERROR" "Configuration file not found: $env_file"
        return 1
    fi
    
    local errors=0
    local warnings=0
    
    # Check required variables
    local -a required_vars=(
        "SERVER_NAME"
        "DB_PASSWORD"
        "REDIS_PASSWORD"
        "SESSION_SECRET"
        "ENCRYPTION_KEY"
        "DB_USER"
        "DB_NAME"
        "SSL_CERT_PATH"
        "JWT_SECRET"
    )
    
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" "$env_file"; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log "ERROR" "Missing required configuration variables:"
        printf '  %s\n' "${missing_vars[@]}"
        ((errors++))
    else
        log "SUCCESS" "All required configuration variables are present"
    fi
    
    # Check file permissions
    local file_perms
    file_perms=$(stat -c "%a" "$env_file" 2>/dev/null || stat -f "%A" "$env_file" 2>/dev/null || echo "unknown")
    
    if [[ "$file_perms" != "600" ]]; then
        log "WARN" "Configuration file has insecure permissions: $file_perms"
        log "INFO" "Setting secure permissions..."
        if chmod 600 "$env_file"; then
            log "SUCCESS" "Fixed file permissions to 600"
        else
            log "ERROR" "Failed to set secure permissions"
            ((errors++))
        fi
    else
        log "SUCCESS" "Configuration file has secure permissions (600)"
    fi
    
    # Validate specific configuration values
    local server_name
    server_name=$(get_config_value "SERVER_NAME")
    if [[ -n "$server_name" ]]; then
        if ! validate_input "$server_name" "domain" true; then
            log "ERROR" "Invalid SERVER_NAME in configuration: $server_name"
            ((errors++))
        else
            log "SUCCESS" "SERVER_NAME validation passed: $server_name"
        fi
    fi
    
    # Check SSL configuration
    local ssl_cert_path
    ssl_cert_path=$(get_config_value "SSL_CERT_PATH")
    if [[ -n "$ssl_cert_path" ]]; then
        if [[ ! -d "$ssl_cert_path" ]]; then
            log "WARN" "SSL certificate path does not exist: $ssl_cert_path"
            ((warnings++))
        else
            log "SUCCESS" "SSL certificate path exists: $ssl_cert_path"
        fi
    fi
    
    # Validate password strength (check minimum entropy)
    local db_password
    db_password=$(get_config_value "DB_PASSWORD")
    if [[ -n "$db_password" && ${#db_password} -lt 20 ]]; then
        log "WARN" "Database password might be too short (recommended: 32+ characters)"
        ((warnings++))
    fi
    
    # Check for dangerous default values
    local session_secret
    session_secret=$(get_config_value "SESSION_SECRET")
    if [[ "$session_secret" == "changeme" || "$session_secret" == "secret" ]]; then
        log "ERROR" "Session secret is using default/weak value"
        ((errors++))
    fi
    
    # Validate email if provided
    local admin_email
    admin_email=$(get_config_value "MILOU_ADMIN_EMAIL")
    if [[ -n "$admin_email" ]]; then
        if ! validate_input "$admin_email" "email" false; then
            log "WARN" "Invalid admin email format: $admin_email"
            ((warnings++))
        else
            log "SUCCESS" "Admin email validation passed: $admin_email"
        fi
    fi
    
    # Summary
    echo
    log "INFO" "Configuration validation summary:"
    log "INFO" "  ${CHECKMARK_EMOJI} Errors: $errors"
    log "INFO" "  ${WARNING_EMOJI} Warnings: $warnings"
    
    if [[ $errors -gt 0 ]]; then
        log "ERROR" "Configuration validation failed ($errors errors, $warnings warnings)"
        return 1
    elif [[ $warnings -gt 0 ]]; then
        log "WARN" "Configuration validation completed with warnings ($warnings warnings)"
        return 0
    else
        log "SUCCESS" "Configuration validation passed successfully"
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
        log "INFO" "  ${FILE_EMOJI} Size: $file_size bytes"
        log "INFO" "  ${LOCK_EMOJI} Permissions: $file_perms"
        log "INFO" "  ${CLOCK_EMOJI} Last modified: $mod_time"
        
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

# =============================================================================
# Configuration Backup and Restore Functions
# =============================================================================

# Create a configuration backup with enhanced metadata
backup_config() {
    local env_file="${SCRIPT_DIR}/.env"
    local backup_name="${1:-config_$(date +%Y%m%d_%H%M%S)}"
    local comment="${2:-Manual backup}"
    
    if [[ ! -f "$env_file" ]]; then
        log "ERROR" "Configuration file not found: $env_file"
        return 1
    fi
    
    local backup_dir="${CONFIG_DIR}/backups"
    mkdir -p "$backup_dir"
    
    local backup_path="${backup_dir}/${backup_name}.env"
    local metadata_path="${backup_dir}/${backup_name}.meta"
    
    # Create backup
    if cp "$env_file" "$backup_path"; then
        chmod 600 "$backup_path"
        
        # Create metadata file
        cat > "$metadata_path" << EOF
# Milou Configuration Backup Metadata
BACKUP_NAME=$backup_name
BACKUP_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BACKUP_COMMENT=$comment
ORIGINAL_FILE=$env_file
CLI_VERSION=${SCRIPT_VERSION:-3.0.0}
BACKUP_SIZE=$(stat -c%s "$backup_path" 2>/dev/null || stat -f%z "$backup_path" 2>/dev/null || echo "unknown")
BACKUP_CHECKSUM=$(sha256sum "$backup_path" 2>/dev/null | cut -d' ' -f1 || echo "unknown")
EOF
        chmod 600 "$metadata_path"
        
        log "SUCCESS" "Configuration backed up to: $backup_path"
        log "DEBUG" "Backup metadata saved to: $metadata_path"
        return 0
    else
        log "ERROR" "Failed to create configuration backup"
        return 1
    fi
}

# Restore configuration from backup with validation
restore_config() {
    local backup_file="$1"
    local env_file="${SCRIPT_DIR}/.env"
    
    if [[ -z "$backup_file" ]]; then
        log "ERROR" "Backup file path is required"
        return 1
    fi
    
    if [[ ! -f "$backup_file" ]]; then
        log "ERROR" "Backup file not found: $backup_file"
        return 1
    fi
    
    # Validate backup file integrity if metadata exists
    local backup_name backup_meta
    backup_name=$(basename "$backup_file" .env)
    backup_meta="$(dirname "$backup_file")/${backup_name}.meta"
    
    if [[ -f "$backup_meta" ]]; then
        log "DEBUG" "Found backup metadata, validating integrity..."
        local stored_checksum current_checksum
        stored_checksum=$(grep "^BACKUP_CHECKSUM=" "$backup_meta" | cut -d'=' -f2)
        current_checksum=$(sha256sum "$backup_file" 2>/dev/null | cut -d' ' -f1 || echo "unknown")
        
        if [[ "$stored_checksum" != "unknown" && "$current_checksum" != "unknown" ]]; then
            if [[ "$stored_checksum" == "$current_checksum" ]]; then
                log "SUCCESS" "Backup integrity validation passed"
            else
                log "ERROR" "Backup integrity validation failed - file may be corrupted"
                if [[ "$FORCE" != true ]]; then
                    if ! confirm "Continue with potentially corrupted backup?" "N"; then
                        return 1
                    fi
                fi
            fi
        fi
    fi
    
    # Create a backup of current config first
    if [[ -f "$env_file" ]]; then
        backup_config "pre_restore_$(date +%Y%m%d_%H%M%S)" "Automatic backup before restore"
    fi
    
    # Restore the configuration
    if cp "$backup_file" "$env_file"; then
        chmod 600 "$env_file"
        log "SUCCESS" "Configuration restored from: $backup_file"
        
        # Validate the restored configuration
        if validate_config; then
            log "SUCCESS" "Restored configuration passed validation"
            return 0
        else
            log "WARN" "Restored configuration has validation issues"
            return 1
        fi
    else
        log "ERROR" "Failed to restore configuration from: $backup_file"
        return 1
    fi
}

# List available configuration backups with enhanced information
list_config_backups() {
    local backup_dir="${CONFIG_DIR}/backups"
    
    if [[ ! -d "$backup_dir" ]]; then
        log "INFO" "No backup directory found"
        return 0
    fi
    
    local backups=($(find "$backup_dir" -name "*.env" -type f 2>/dev/null | sort -r))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        log "INFO" "No configuration backups found"
        return 0
    fi
    
    log "INFO" "Available configuration backups:"
    echo
    
    for backup in "${backups[@]}"; do
        local basename backup_meta
        basename=$(basename "$backup" .env)
        backup_meta="$(dirname "$backup")/${basename}.meta"
        
        local size mod_time comment
        size=$(stat -c%s "$backup" 2>/dev/null || stat -f%z "$backup" 2>/dev/null || echo "?")
        mod_time=$(stat -c "%y" "$backup" 2>/dev/null | cut -d'.' -f1 || stat -f "%Sm" "$backup" 2>/dev/null || echo "unknown")
        
        # Try to get comment from metadata
        if [[ -f "$backup_meta" ]]; then
            comment=$(grep "^BACKUP_COMMENT=" "$backup_meta" 2>/dev/null | cut -d'=' -f2- || echo "No comment")
        else
            comment="No metadata"
        fi
        
        echo "  📄 $basename"
        echo "     ${CLOCK_EMOJI} Date: $mod_time"
        echo "     ${FILE_EMOJI} Size: $size bytes"
        echo "     📝 Comment: $comment"
        echo "     📁 Path: $backup"
        echo
    done
}

# Clean old configuration backups
clean_old_backups() {
    local retention_days="${1:-30}"
    local backup_dir="${CONFIG_DIR}/backups"
    
    if [[ ! -d "$backup_dir" ]]; then
        log "INFO" "No backup directory found"
        return 0
    fi
    
    log "STEP" "Cleaning backups older than $retention_days days..."
    
    local old_backups
    old_backups=$(find "$backup_dir" -name "*.env" -type f -mtime +${retention_days} 2>/dev/null)
    
    if [[ -z "$old_backups" ]]; then
        log "INFO" "No old backups found"
        return 0
    fi
    
    local count=0
    while IFS= read -r backup; do
        local basename
        basename=$(basename "$backup" .env)
        
        # Remove backup and metadata
        rm -f "$backup"
        rm -f "$(dirname "$backup")/${basename}.meta"
        
        log "DEBUG" "Removed old backup: $basename"
        ((count++))
    done <<< "$old_backups"
    
    log "SUCCESS" "Cleaned $count old backup(s)"
}

# =============================================================================
# Configuration Migration and Upgrade Functions
# =============================================================================

# Migrate configuration to new format with enhanced features
migrate_config() {
    local env_file="${SCRIPT_DIR}/.env"
    
    if [[ ! -f "$env_file" ]]; then
        log "ERROR" "Configuration file not found: $env_file"
        return 1
    fi
    
    # Create backup before migration
    backup_config "pre_migration_$(date +%Y%m%d_%H%M%S)" "Automatic backup before migration"
    
    log "STEP" "Migrating configuration to enhanced format..."
    
    # Check current format version
    local current_version
    current_version=$(get_config_value "MILOU_VERSION" "1.0.0")
    
    log "DEBUG" "Current configuration version: $current_version"
    log "DEBUG" "Target configuration version: ${SCRIPT_VERSION:-3.0.0}"
    
    # Add missing variables if they don't exist
    local -A default_values=(
        ["MILOU_VERSION"]="${SCRIPT_VERSION:-3.0.0}"
        ["MILOU_GENERATED_AT"]="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        ["JWT_SECRET"]="$(generate_secure_random 64 "safe")"
        ["JWT_ALGORITHM"]="HS256"
        ["JWT_EXPIRATION"]="24h"
        ["BCRYPT_ROUNDS"]="12"
        ["SSL_PROTOCOLS"]="TLSv1.2,TLSv1.3"
        ["LOG_LEVEL"]="info"
        ["ENABLE_MONITORING"]="true"
        ["HEALTH_CHECK_INTERVAL"]="30"
        ["API_RATE_LIMIT"]="1000"
        ["SESSION_SECURE_COOKIES"]="true"
        ["HSTS_ENABLED"]="true"
        ["CSP_ENABLED"]="true"
        ["BACKUP_ENABLED"]="true"
    )
    
    local added_count=0
    for key in "${!default_values[@]}"; do
        if ! grep -q "^${key}=" "$env_file"; then
            update_config_value "$key" "${default_values[$key]}"
            ((added_count++))
        fi
    done
    
    # Update version
    update_config_value "MILOU_VERSION" "${SCRIPT_VERSION:-3.0.0}"
    
    if [[ $added_count -gt 0 ]]; then
        log "SUCCESS" "Migration completed: $added_count new variables added"
    else
        log "INFO" "Configuration is already up to date"
    fi
    
    # Validate after migration
    if validate_config; then
        log "SUCCESS" "Migrated configuration passed validation"
    else
        log "WARN" "Migrated configuration has validation issues"
    fi
    
    return 0
}

# Enhanced validate_configuration function for backward compatibility
validate_configuration() {
    validate_config
}

# =============================================================================
# Configuration Preservation and Migration Functions
# =============================================================================

# Detect existing Milou installation and configuration
detect_existing_installation() {
    local env_file="${SCRIPT_DIR}/.env"
    local has_config=false
    local has_containers=false
    local has_volumes=false
    local config_age_days=0
    
    # Check for configuration file
    if [[ -f "$env_file" ]]; then
        has_config=true
        # Calculate age in days
        if command -v stat >/dev/null 2>&1; then
            local file_modified
            file_modified=$(stat -c %Y "$env_file" 2>/dev/null || stat -f %m "$env_file" 2>/dev/null || echo "0")
            local current_time=$(date +%s)
            config_age_days=$(( (current_time - file_modified) / 86400 ))
        fi
    fi
    
    # Check for existing containers
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        local container_count
        container_count=$(docker ps -a --filter "name=static-" --format "{{.Names}}" 2>/dev/null | wc -l || echo "0")
        if [[ $container_count -gt 0 ]]; then
            has_containers=true
        fi
        
        # Check for existing volumes
        local volume_count
        volume_count=$(docker volume ls --filter "name=static_" --format "{{.Name}}" 2>/dev/null | wc -l || echo "0")
        if [[ $volume_count -gt 0 ]]; then
            has_volumes=true
        fi
    fi
    
    # Set global detection results
    export MILOU_EXISTING_CONFIG="$has_config"
    export MILOU_EXISTING_CONTAINERS="$has_containers"
    export MILOU_EXISTING_VOLUMES="$has_volumes"
    export MILOU_CONFIG_AGE_DAYS="$config_age_days"
    
    # Return codes: 0 = fresh install, 1 = existing installation
    if [[ "$has_config" == "true" || "$has_containers" == "true" || "$has_volumes" == "true" ]]; then
        return 1  # Existing installation detected
    else
        return 0  # Fresh installation
    fi
}

# Show existing installation summary
show_existing_installation_summary() {
    local env_file="${SCRIPT_DIR}/.env"
    
    echo
    log "INFO" "📋 Existing Installation Summary:"
    
    if [[ "${MILOU_EXISTING_CONFIG:-false}" == "true" ]]; then
        log "INFO" "  • Configuration file: Found (${MILOU_CONFIG_AGE_DAYS:-0} days old)"
        
        # Show key configuration details
        if [[ -f "$env_file" ]]; then
            local domain ssl_path
            domain=$(get_config_value "SERVER_NAME" "unknown")
            ssl_path=$(get_config_value "SSL_CERT_PATH" "unknown")
            log "INFO" "    - Domain: $domain"
            log "INFO" "    - SSL Path: $ssl_path"
        fi
    else
        log "INFO" "  • Configuration file: Not found"
    fi
    
    if [[ "${MILOU_EXISTING_CONTAINERS:-false}" == "true" ]]; then
        log "INFO" "  • Docker containers: Found"
        # Show running containers
        if command -v docker >/dev/null 2>&1; then
            local running_containers
            running_containers=$(docker ps --filter "name=static-" --format "{{.Names}} ({{.Status}})" 2>/dev/null || echo "")
            if [[ -n "$running_containers" ]]; then
                log "INFO" "    Running services:"
                while IFS= read -r container; do
                    [[ -n "$container" ]] && log "INFO" "      🐳 $container"
                done <<< "$running_containers"
            fi
        fi
    else
        log "INFO" "  • Docker containers: None found"
    fi
    
    if [[ "${MILOU_EXISTING_VOLUMES:-false}" == "true" ]]; then
        log "INFO" "  • Data volumes: Found"
        if command -v docker >/dev/null 2>&1; then
            local volumes
            volumes=$(docker volume ls --filter "name=static_" --format "{{.Name}}" 2>/dev/null || echo "")
            if [[ -n "$volumes" ]]; then
                log "INFO" "    Data volumes:"
                while IFS= read -r volume; do
                    [[ -n "$volume" ]] && log "INFO" "      💾 $volume"
                done <<< "$volumes"
            fi
        fi
    else
        log "INFO" "  • Data volumes: None found"
    fi
    
    echo
}

# Preserve existing database credentials from current configuration
preserve_database_credentials() {
    local env_file="${SCRIPT_DIR}/.env"
    local preserved_vars=()
    
    if [[ ! -f "$env_file" ]]; then
        log "DEBUG" "No existing configuration to preserve"
        return 1
    fi
    
    log "DEBUG" "Preserving database credentials from existing configuration..."
    
    # Database credentials to preserve
    local -a db_vars=(
        "DB_USER"
        "DB_PASSWORD" 
        "POSTGRES_USER"
        "POSTGRES_PASSWORD"
        "DATABASE_URI"
        "DATABASE_URL"
    )
    
    # Redis credentials
    local -a redis_vars=(
        "REDIS_PASSWORD"
        "REDIS_URL"
    )
    
    # RabbitMQ credentials  
    local -a rabbitmq_vars=(
        "RABBITMQ_USER"
        "RABBITMQ_PASSWORD"
        "RABBITMQ_URL"
    )
    
    # Security keys and secrets
    local -a security_vars=(
        "SESSION_SECRET"
        "ENCRYPTION_KEY"
        "JWT_SECRET"
        "API_KEY"
    )
    
    # Store all preserved variables in global associative array
    declare -gA PRESERVED_CONFIG=()
    
    for var in "${db_vars[@]}" "${redis_vars[@]}" "${rabbitmq_vars[@]}" "${security_vars[@]}"; do
        local value
        value=$(get_config_value "$var" "")
        if [[ -n "$value" ]]; then
            PRESERVED_CONFIG["$var"]="$value"
            preserved_vars+=("$var")
            log "DEBUG" "Preserved $var"
        fi
    done
    
    if [[ ${#preserved_vars[@]} -gt 0 ]]; then
        log "SUCCESS" "Preserved ${#preserved_vars[@]} configuration values"
        log "DEBUG" "Preserved variables: ${preserved_vars[*]}"
        return 0
    else
        log "WARN" "No configuration values found to preserve"
        return 1
    fi
}

# Generate configuration with preserved credentials
generate_config_with_preservation() {
    local domain=${1:-localhost}
    local ssl_path=${2:-./ssl}
    local admin_email="${3:-}"
    local preserve_mode="${4:-auto}"  # auto, force, never
    
    log "STEP" "Generating configuration with credential preservation..."
    
    # First try to preserve existing credentials
    local has_preserved=false
    if [[ "$preserve_mode" == "auto" || "$preserve_mode" == "force" ]]; then
        if preserve_database_credentials; then
            has_preserved=true
            log "INFO" "✅ Existing credentials preserved"
        elif [[ "$preserve_mode" == "force" ]]; then
            log "ERROR" "Failed to preserve credentials in force mode"
            return 1
        fi
    fi
    
    # Validate inputs first
    if ! validate_config_inputs "$domain" "$ssl_path" "$admin_email"; then
        error_exit "Configuration input validation failed"
    fi
    
    # Generate new credentials only for missing ones
    log "DEBUG" "Generating secure credentials (preserving existing when available)..."
    
    local db_user db_password redis_password session_secret encryption_key
    local jwt_secret rabbitmq_user rabbitmq_password api_key
    
    if [[ "$has_preserved" == "true" ]]; then
        # Use preserved values or generate new ones
        db_user="${PRESERVED_CONFIG[DB_USER]:-milou_$(generate_secure_random 8 "alphanumeric")}"
        db_password="${PRESERVED_CONFIG[DB_PASSWORD]:-$(generate_secure_random 32 "safe")}"
        redis_password="${PRESERVED_CONFIG[REDIS_PASSWORD]:-$(generate_secure_random 32 "safe")}"
        session_secret="${PRESERVED_CONFIG[SESSION_SECRET]:-$(generate_secure_random 64 "safe")}"
        encryption_key="${PRESERVED_CONFIG[ENCRYPTION_KEY]:-$(generate_secure_random 32 "hex")}"
        jwt_secret="${PRESERVED_CONFIG[JWT_SECRET]:-$(generate_secure_random 64 "safe")}"
        rabbitmq_user="${PRESERVED_CONFIG[RABBITMQ_USER]:-milou_$(generate_secure_random 6 "alphanumeric")}"
        rabbitmq_password="${PRESERVED_CONFIG[RABBITMQ_PASSWORD]:-$(generate_secure_random 32 "safe")}"
        api_key="${PRESERVED_CONFIG[API_KEY]:-$(generate_secure_random 40 "safe")}"
        
        log "INFO" "🔄 Using preserved database user: $db_user"
        log "INFO" "🔄 Using preserved RabbitMQ user: $rabbitmq_user"
        log "DEBUG" "Preserved secrets will maintain compatibility with existing data"
    else
        # Generate all new credentials
        db_user="milou_$(generate_secure_random 8 "alphanumeric")"
        db_password=$(generate_secure_random 32 "safe")
        redis_password=$(generate_secure_random 32 "safe")
        session_secret=$(generate_secure_random 64 "safe")
        encryption_key=$(generate_secure_random 32 "hex")
        jwt_secret=$(generate_secure_random 64 "safe")
        rabbitmq_user="milou_$(generate_secure_random 6 "alphanumeric")"
        rabbitmq_password=$(generate_secure_random 32 "safe")
        api_key=$(generate_secure_random 40 "safe")
        
        log "INFO" "🆕 Generated new database user: $db_user"
        log "INFO" "🆕 Generated new RabbitMQ user: $rabbitmq_user"
    fi
    
    # Continue with rest of the existing generate_config function...
    # [The rest remains the same as the original generate_config function]
    
    # Determine ports with conflict checking
    local ssl_port="443"
    local api_port="9999"
    local http_port="80"
    
    # Check for port conflicts and suggest alternatives
    if command_exists netstat true && netstat -tlnp 2>/dev/null | grep -q ":443 "; then
        log "WARN" "Port 443 is already in use, SSL might have conflicts"
    fi
    
    # Set environment based on domain
    local node_env="production"
    if [[ "$domain" == "localhost" ]]; then
        node_env="development"
    fi
    
    # Create comprehensive configuration with enhanced security
    log "DEBUG" "Creating comprehensive configuration file..."
    
    cat > "${SCRIPT_DIR}/.env" << EOF
# =============================================================================
# Milou Application Environment Configuration - Enhanced Edition
# Generated on $(date)
# CLI Version: ${SCRIPT_VERSION:-3.0.0}
# Domain: $domain
# Preservation Mode: $preserve_mode
# =============================================================================

# =============================================================================
# METADATA AND VERSIONING
# =============================================================================
MILOU_VERSION=${SCRIPT_VERSION:-3.0.0}
MILOU_GENERATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
MILOU_DOMAIN=$domain
MILOU_SSL_PATH=$ssl_path
MILOU_ADMIN_EMAIL=$admin_email
MILOU_ENVIRONMENT=$node_env
MILOU_PRESERVE_MODE=$preserve_mode
MILOU_PRESERVED_CREDENTIALS=$has_preserved

# =============================================================================
# SERVER CONFIGURATION
# =============================================================================
SERVER_NAME=$domain
CUSTOMER_DOMAIN_NAME=$domain
DOMAIN=$domain
SSL_PORT=$ssl_port
HTTP_PORT=$http_port
SSL_CERT_PATH=$ssl_path
CORS_ORIGIN=https://$domain
NODE_ENV=$node_env

# =============================================================================
# API CONFIGURATION
# =============================================================================
PORT=$api_port
API_PORT=$api_port
API_URL=https://$domain/api
API_BASE_URL=https://$domain/api
VITE_API_URL=/api
API_KEY=$api_key
API_VERSION=v1

# =============================================================================
# DATABASE CONFIGURATION (PostgreSQL)
# =============================================================================
DB_HOST=db
DB_PORT=5432
DB_USER=$db_user
DB_PASSWORD=$db_password
DB_NAME=milou
DB_CHARSET=utf8
DB_COLLATION=utf8_unicode_ci
DATABASE_URI=postgresql+psycopg2://$db_user:$db_password@db:5432/milou
DATABASE_URL=postgresql://$db_user:$db_password@db:5432/milou

# PostgreSQL specific settings
POSTGRES_USER=$db_user
POSTGRES_PASSWORD=$db_password
POSTGRES_DB=milou
POSTGRES_HOST=db
POSTGRES_PORT=5432

# Connection pool settings
DB_POOL_SIZE=20
DB_POOL_MAX_OVERFLOW=30
DB_POOL_TIMEOUT=30
DB_POOL_RECYCLE=3600

# =============================================================================
# REDIS CONFIGURATION
# =============================================================================
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=$redis_password
REDIS_DB=0
REDIS_SESSION_TTL=3600
REDIS_MAX_RETRIES=3
REDIS_CONNECT_TIMEOUT=10000
REDIS_COMMAND_TIMEOUT=5000
REDIS_CLEANUP_ENABLED=true
REDIS_CLEANUP_INTERVAL=3600
REDIS_URL=redis://:$redis_password@redis:6379/0

# Redis cluster settings (for future scaling)
REDIS_CLUSTER_ENABLED=false
REDIS_SENTINEL_ENABLED=false

# =============================================================================
# RABBITMQ CONFIGURATION
# =============================================================================
RABBITMQ_HOST=rabbitmq
RABBITMQ_PORT=5672
RABBITMQ_USER=$rabbitmq_user
RABBITMQ_PASSWORD=$rabbitmq_password
RABBITMQ_VHOST=/
RABBITMQ_URL=amqp://$rabbitmq_user:$rabbitmq_password@rabbitmq:5672/
RABBITMQ_MANAGEMENT_PORT=15672

# Message queue settings
RABBITMQ_EXCHANGE=milou_exchange
RABBITMQ_QUEUE_PREFIX=milou_
RABBITMQ_PREFETCH_COUNT=10
RABBITMQ_HEARTBEAT=60

# =============================================================================
# SECURITY CONFIGURATION (Enhanced)
# =============================================================================
SESSION_SECRET=$session_secret
ENCRYPTION_KEY=$encryption_key
JWT_SECRET=$jwt_secret
JWT_ALGORITHM=HS256
JWT_EXPIRATION=24h
JWT_REFRESH_EXPIRATION=7d
BCRYPT_ROUNDS=12
HASH_ALGORITHM=sha256

# API Security
API_RATE_LIMIT=1000
API_RATE_WINDOW=3600
API_MAX_REQUESTS_PER_IP=100

# Password policy
PASSWORD_MIN_LENGTH=8
PASSWORD_REQUIRE_UPPERCASE=true
PASSWORD_REQUIRE_LOWERCASE=true
PASSWORD_REQUIRE_NUMBERS=true
PASSWORD_REQUIRE_SYMBOLS=true

# Session security
SESSION_SECURE_COOKIES=true
SESSION_HTTP_ONLY=true
SESSION_SAME_SITE=strict
SESSION_TIMEOUT=3600

# =============================================================================
# SSL/TLS CONFIGURATION (Enhanced)
# =============================================================================
SSL_ENABLED=true
SSL_CERT_FILE=milou.crt
SSL_KEY_FILE=milou.key
SSL_PROTOCOLS=TLSv1.2,TLSv1.3
SSL_CIPHERS=ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20:!aNULL:!MD5:!DSS
SSL_PREFER_SERVER_CIPHERS=on
SSL_SESSION_CACHE=shared:SSL:10m
SSL_SESSION_TIMEOUT=10m

# HSTS (HTTP Strict Transport Security)
HSTS_ENABLED=true
HSTS_MAX_AGE=31536000
HSTS_INCLUDE_SUBDOMAINS=true
HSTS_PRELOAD=true

# =============================================================================
# LOGGING CONFIGURATION (Enhanced)
# =============================================================================
LOG_LEVEL=info
LOG_FORMAT=combined
LOG_TO_FILE=true
LOG_TO_CONSOLE=true
LOG_ROTATION=daily
LOG_MAX_SIZE=100MB
LOG_MAX_FILES=30

# Component-specific logging
BACKEND_LOG_LEVEL=info
FRONTEND_LOG_LEVEL=warn
ENGINE_LOG_LEVEL=info
NGINX_LOG_LEVEL=warn

# Debug logging (for development)
DEBUG_SQL_QUERIES=false
DEBUG_HTTP_REQUESTS=false
DEBUG_WEBSOCKETS=false

# =============================================================================
# SECURITY HEADERS AND CSP
# =============================================================================
CSP_ENABLED=true
CSP_DEFAULT_SRC="'self'"
CSP_SCRIPT_SRC="'self' 'unsafe-inline' 'unsafe-eval'"
CSP_STYLE_SRC="'self' 'unsafe-inline'"
CSP_IMG_SRC="'self' data: https:"
CSP_FONT_SRC="'self'"
CSP_CONNECT_SRC="'self'"
CSP_FRAME_ANCESTORS="'none'"

# =============================================================================
# FEATURE FLAGS AND TOGGLES
# =============================================================================
ENABLE_ANALYTICS=true
ENABLE_MONITORING=true
ENABLE_RATE_LIMITING=true
ENABLE_COMPRESSION=true
ENABLE_CACHING=true
ENABLE_DEBUG_MODE=false
ENABLE_MAINTENANCE_MODE=false

# API Features
ENABLE_API_VERSIONING=true
ENABLE_API_DOCUMENTATION=true
ENABLE_API_RATE_LIMITING=true

# =============================================================================
# MONITORING AND HEALTH CHECKS (Enhanced)
# =============================================================================
HEALTH_CHECK_INTERVAL=30
HEALTH_CHECK_TIMEOUT=10
HEALTH_CHECK_PATH=/health
METRICS_ENABLED=true
METRICS_PORT=8080
METRICS_PATH=/metrics

# Application monitoring
APM_ENABLED=false
APM_SERVICE_NAME=milou
APM_ENVIRONMENT=$node_env

# Alerting
ALERT_EMAIL_ENABLED=false
ALERT_EMAIL_RECIPIENTS=$admin_email
ALERT_WEBHOOK_ENABLED=false

# =============================================================================
# BACKUP AND MAINTENANCE (Enhanced)
# =============================================================================
BACKUP_ENABLED=true
BACKUP_SCHEDULE="0 2 * * *"
BACKUP_RETENTION_DAYS=30
BACKUP_COMPRESSION=true
BACKUP_ENCRYPTION=true

# Maintenance windows
MAINTENANCE_WINDOW_START="02:00"
MAINTENANCE_WINDOW_END="04:00"
MAINTENANCE_TIMEZONE=UTC

# =============================================================================
# EXTERNAL INTEGRATIONS
# =============================================================================
# Email configuration (if needed)
SMTP_HOST=localhost
SMTP_PORT=587
SMTP_SECURE=true
SMTP_USER=
SMTP_PASSWORD=
EMAIL_FROM=$admin_email

# Storage configuration
STORAGE_TYPE=local
STORAGE_PATH=/app/storage
AWS_S3_BUCKET=
AWS_S3_REGION=
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=

# =============================================================================
# DEVELOPMENT AND DEBUGGING
# =============================================================================
DEBUG=$([[ "$node_env" == "development" ]] && echo "true" || echo "false")
VERBOSE_LOGGING=$([[ "$node_env" == "development" ]] && echo "true" || echo "false")
PROFILING_ENABLED=false
HOT_RELOAD_ENABLED=$([[ "$node_env" == "development" ]] && echo "true" || echo "false")

# Testing
TEST_DATABASE_URL=postgresql://$db_user:$db_password@db:5432/milou_test
TEST_REDIS_URL=redis://:$redis_password@redis:6379/1

# =============================================================================
# DOCKER AND CONTAINER SETTINGS
# =============================================================================
COMPOSE_PROJECT_NAME=static
COMPOSE_HTTP_TIMEOUT=120
DOCKER_BUILDKIT=1
COMPOSE_DOCKER_CLI_BUILD=1

# Resource limits
MEMORY_LIMIT=2g
CPU_LIMIT=2
SWAP_LIMIT=1g

# =============================================================================
# TIMEZONE AND LOCALIZATION
# =============================================================================
TZ=UTC
LOCALE=en_US.UTF-8
LANGUAGE=en_US
LC_ALL=en_US.UTF-8

# =============================================================================
# SECURITY WARNING AND INSTRUCTIONS
# =============================================================================
# This file contains sensitive information including passwords and secrets.
# 
# SECURITY GUIDELINES:
# • NEVER commit this file to version control!
# • NEVER share this file via insecure channels!
# • Store backups in encrypted form only!
# • Rotate secrets regularly!
# • Use different secrets for different environments!
# 
# File permissions are automatically set to 600 (owner read/write only).
# =============================================================================
EOF

    # Set secure file permissions immediately
    if ! chmod 600 "${SCRIPT_DIR}/.env"; then
        log "WARN" "Could not set secure permissions on .env file"
    else
        log "DEBUG" "Set secure permissions (600) on .env file"
    fi
    
    # Verify configuration was created successfully
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        local config_size=$(wc -c < "${SCRIPT_DIR}/.env")
        log "SUCCESS" "Configuration generated successfully (${config_size} bytes)"
        log "INFO" "Configuration saved to: ${SCRIPT_DIR}/.env"
        log "INFO" "${LOCK_EMOJI} File permissions set to 600 (secure)"
        
        if [[ "$has_preserved" == "true" ]]; then
            log "SUCCESS" "✅ Preserved existing credentials for seamless upgrade"
        fi
        
        # Create a backup of the configuration
        if ! mkdir -p "${CONFIG_DIR}/backups"; then
            log "WARN" "Could not create backup directory"
        else
            local backup_file="${CONFIG_DIR}/backups/env_$(date +%Y%m%d%H%M%S).backup"
            if cp "${SCRIPT_DIR}/.env" "$backup_file" 2>/dev/null; then
                chmod 600 "$backup_file" 2>/dev/null
                log "DEBUG" "Configuration backup created: $backup_file"
            else
                log "WARN" "Could not create configuration backup"
            fi
        fi
        
        # Validate the generated configuration
        if validate_config; then
            log "SUCCESS" "Generated configuration passed validation"
        else
            log "WARN" "Generated configuration has validation warnings"
        fi
    else
        error_exit "Failed to create configuration file"
    fi
    
    return 0
}
