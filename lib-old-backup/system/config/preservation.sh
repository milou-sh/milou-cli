#!/bin/bash

# =============================================================================
# Configuration Preservation Module for Milou CLI
# Handles detection and preservation of existing configurations during upgrades
# =============================================================================

# Module guard to prevent multiple loading
if [[ "${MILOU_CONFIG_PRESERVATION_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_CONFIG_PRESERVATION_LOADED="true"

# Ensure logging is available
if ! command -v milou_log >/dev/null 2>&1; then
    source "${SCRIPT_DIR}/lib/core/logging.sh" 2>/dev/null || {
        echo "ERROR: Cannot load logging module" >&2
        exit 1
    }
fi

# Global associative array for preserved configurations
declare -gA PRESERVED_CONFIG=()

# =============================================================================
# Installation Detection Functions
# =============================================================================

# Detect existing Milou installation and configuration
detect_existing_installation() {
    local env_file=""
    local has_config=false
    local has_containers=false
    local has_volumes=false
    local config_age_days=0
    local is_real_installation=false
    
    # Enhanced env file detection that works after user switching
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        env_file="${SCRIPT_DIR}/.env"
    elif [[ -f "$(pwd)/.env" ]]; then
        env_file="$(pwd)/.env"
    else
        # Try to find .env in milou user home directory if we switched users
        if [[ "$(whoami)" == "milou" && -f "$HOME/milou-cli/.env" ]]; then
            env_file="$HOME/milou-cli/.env"
        else
            # Search in common locations
            local -a search_paths=(
                "${SCRIPT_DIR}/.env"
                "/home/milou/milou-cli/.env"
                "/opt/milou-cli/.env"
                "/usr/local/milou-cli/.env"
                "./.env"
            )
            
            for path in "${search_paths[@]}"; do
                if [[ -f "$path" ]]; then
                    env_file="$path"
                    break
                fi
            done
        fi
    fi
    
    # Check for configuration file and validate if it's a real installation
    if [[ -f "$env_file" ]]; then
        # Calculate age in days
        if command -v stat >/dev/null 2>&1; then
            local file_modified
            file_modified=$(stat -c %Y "$env_file" 2>/dev/null || stat -f %m "$env_file" 2>/dev/null || echo "0")
            local current_time=$(date +%s)
            config_age_days=$(( (current_time - file_modified) / 86400 ))
        fi
        
        # Check if this looks like a real installation vs test data
        local server_name
        server_name=$(grep "^SERVER_NAME=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "")
        
        # Consider it a real installation if:
        # 1. It has a non-test domain name, OR
        # 2. It's older than 1 day, OR  
        # 3. There are corresponding containers/volumes
        if [[ -n "$server_name" && ! "$server_name" =~ ^(test\.|localhost|127\.|example\.com|test\.example\.com)$ ]] ||
           [[ $config_age_days -gt 1 ]]; then
            has_config=true
            is_real_installation=true
            milou_log "DEBUG" "Found real configuration: $env_file (${config_age_days} days old, domain: $server_name)"
        else
            milou_log "DEBUG" "Found test/temporary configuration: $env_file (domain: $server_name, age: ${config_age_days} days)"
        fi
    else
        milou_log "DEBUG" "No existing configuration found"
    fi
    
    # Check for existing containers
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        local container_count
        container_count=$(docker ps -a --filter "name=static-" --format "{{.Names}}" 2>/dev/null | wc -l || echo "0")
        if [[ $container_count -gt 0 ]]; then
            has_containers=true
            is_real_installation=true
            milou_log "DEBUG" "Found $container_count existing Milou containers"
        fi
        
        # Check for existing volumes
        local volume_count
        volume_count=$(docker volume ls --filter "name=static_" --format "{{.Name}}" 2>/dev/null | wc -l || echo "0")
        if [[ $volume_count -gt 0 ]]; then
            has_volumes=true
            is_real_installation=true
            milou_log "DEBUG" "Found $volume_count existing Milou volumes"
        fi
    fi
    
    # Set global detection results
    export MILOU_EXISTING_CONFIG="$has_config"
    export MILOU_EXISTING_CONTAINERS="$has_containers"
    export MILOU_EXISTING_VOLUMES="$has_volumes"
    export MILOU_CONFIG_AGE_DAYS="$config_age_days"
    export MILOU_EXISTING_ENV_FILE="$env_file"  # Store the actual path found
    export MILOU_IS_REAL_INSTALLATION="$is_real_installation"
    
    # Return codes: 0 = fresh install, 1 = existing installation
    # Only return 1 (existing) if we found evidence of a real installation
    if [[ "$is_real_installation" == "true" ]]; then
        milou_log "DEBUG" "Real installation detected (config: $has_config, containers: $has_containers, volumes: $has_volumes)"
        return 1  # Existing installation detected
    else
        milou_log "DEBUG" "Fresh installation detected (test files ignored)"
        return 0  # Fresh installation
    fi
}

# Show existing installation summary
show_existing_installation_summary() {
    local env_file="${MILOU_EXISTING_ENV_FILE:-${SCRIPT_DIR}/.env}"
    
    echo
    milou_log "INFO" "📋 Existing Installation Summary:"
    
    if [[ "${MILOU_EXISTING_CONFIG:-false}" == "true" ]]; then
        milou_log "INFO" "  • Configuration file: Found (${MILOU_CONFIG_AGE_DAYS:-0} days old)"
        milou_log "INFO" "    Path: $env_file"
        
        # Show key configuration details
        if [[ -f "$env_file" ]]; then
            local domain ssl_path
            domain=$(grep "^SERVER_NAME=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "unknown")
            ssl_path=$(grep "^SSL_CERT_PATH=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "unknown")
            milou_log "INFO" "    - Domain: $domain"
            milou_log "INFO" "    - SSL Path: $ssl_path"
        fi
    else
        milou_log "INFO" "  • Configuration file: Not found"
    fi
    
    if [[ "${MILOU_EXISTING_CONTAINERS:-false}" == "true" ]]; then
        milou_log "INFO" "  • Docker containers: Found"
        # Show running containers
        if command -v docker >/dev/null 2>&1; then
            local running_containers
            running_containers=$(docker ps --filter "name=static-" --format "{{.Names}} ({{.Status}})" 2>/dev/null || echo "")
            if [[ -n "$running_containers" ]]; then
                milou_log "INFO" "    Running services:"
                while IFS= read -r container; do
                    [[ -n "$container" ]] && milou_log "INFO" "      🐳 $container"
                done <<< "$running_containers"
            fi
        fi
    else
        milou_log "INFO" "  • Docker containers: None found"
    fi
    
    if [[ "${MILOU_EXISTING_VOLUMES:-false}" == "true" ]]; then
        milou_log "INFO" "  • Data volumes: Found"
        if command -v docker >/dev/null 2>&1; then
            local volumes
            volumes=$(docker volume ls --filter "name=static_" --format "{{.Name}}" 2>/dev/null || echo "")
            if [[ -n "$volumes" ]]; then
                milou_log "INFO" "    Data volumes:"
                while IFS= read -r volume; do
                    [[ -n "$volume" ]] && milou_log "INFO" "      💾 $volume"
                done <<< "$volumes"
            fi
        fi
    else
        milou_log "INFO" "  • Data volumes: None found"
    fi
    
    echo
}

# =============================================================================
# Credential Preservation Functions
# =============================================================================

# Preserve existing database credentials from current configuration
preserve_database_credentials() {
    # Use the detected env file path or fall back to default
    local env_file="${MILOU_EXISTING_ENV_FILE:-${SCRIPT_DIR}/.env}"
    local preserved_vars=()
    
    if [[ ! -f "$env_file" ]]; then
        milou_log "DEBUG" "No existing configuration to preserve at: $env_file"
        return 1
    fi
    
    milou_log "DEBUG" "Preserving database credentials from: $env_file"
    
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
    
    # Clear any existing preserved config
    PRESERVED_CONFIG=()
    
    # Admin credentials
    local -a admin_vars=(
        "ADMIN_EMAIL"
        "ADMIN_PASSWORD"
    )
    
    for var in "${db_vars[@]}" "${redis_vars[@]}" "${rabbitmq_vars[@]}" "${security_vars[@]}" "${admin_vars[@]}"; do
        local value
        # Use the env file directly for reading values
        value=$(grep "^${var}=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "")
        if [[ -n "$value" ]]; then
            PRESERVED_CONFIG["$var"]="$value"
            preserved_vars+=("$var")
            milou_log "DEBUG" "Preserved $var"
        fi
    done
    
    if [[ ${#preserved_vars[@]} -gt 0 ]]; then
        milou_log "SUCCESS" "Preserved ${#preserved_vars[@]} configuration values from: $env_file"
        milou_log "DEBUG" "Preserved variables: ${preserved_vars[*]}"
        return 0
    else
        milou_log "WARN" "No configuration values found to preserve in: $env_file"
        return 1
    fi
}

# Get a preserved configuration value
get_preserved_config() {
    local key="$1"
    local default_value="${2:-}"
    
    if [[ -n "${PRESERVED_CONFIG[$key]:-}" ]]; then
        echo "${PRESERVED_CONFIG[$key]}"
        return 0
    elif [[ -n "$default_value" ]]; then
        echo "$default_value"
        return 0
    else
        return 1
    fi
}

# Check if configuration has been preserved
has_preserved_config() {
    [[ ${#PRESERVED_CONFIG[@]} -gt 0 ]]
}

# List all preserved configuration keys
list_preserved_config() {
    if has_preserved_config; then
        milou_log "INFO" "Preserved configuration keys:"
        for key in "${!PRESERVED_CONFIG[@]}"; do
            milou_log "INFO" "  • $key"
        done
    else
        milou_log "INFO" "No configuration values have been preserved"
    fi
}

# Clear preserved configuration
clear_preserved_config() {
    PRESERVED_CONFIG=()
    milou_log "DEBUG" "Cleared preserved configuration"
}

# =============================================================================
# Migration Support Functions
# =============================================================================

# Check if migration from old configuration is needed
needs_configuration_migration() {
    local env_file="${MILOU_EXISTING_ENV_FILE:-${SCRIPT_DIR}/.env}"
    
    if [[ ! -f "$env_file" ]]; then
        return 1  # No migration needed if no config exists
    fi
    
    # Check for old version indicators
    local has_old_format=false
    
    # Check for missing new metadata fields
    if ! grep -q "^MILOU_VERSION=" "$env_file" 2>/dev/null; then
        has_old_format=true
    fi
    
    # Check for deprecated variables
    if grep -q "^OLD_VAR_NAME=" "$env_file" 2>/dev/null; then
        has_old_format=true
    fi
    
    if [[ "$has_old_format" == "true" ]]; then
        milou_log "DEBUG" "Configuration migration needed for: $env_file"
        return 0  # Migration needed
    else
        milou_log "DEBUG" "Configuration is up-to-date: $env_file"
        return 1  # No migration needed
    fi
}

# Get configuration format version
get_config_version() {
    local env_file="${MILOU_EXISTING_ENV_FILE:-${SCRIPT_DIR}/.env}"
    
    if [[ -f "$env_file" ]]; then
        grep "^MILOU_VERSION=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "unknown"
    else
        echo "none"
    fi
}

# Export preserved configuration to environment
export_preserved_config() {
    if has_preserved_config; then
        for key in "${!PRESERVED_CONFIG[@]}"; do
            export "$key=${PRESERVED_CONFIG[$key]}"
            milou_log "DEBUG" "Exported preserved config: $key"
        done
        milou_log "INFO" "Exported ${#PRESERVED_CONFIG[@]} preserved configuration values to environment"
    else
        milou_log "DEBUG" "No preserved configuration to export"
    fi
}

milou_log "DEBUG" "Configuration preservation module loaded successfully" 