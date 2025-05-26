#!/bin/bash

# =============================================================================
# Milou CLI - Consolidated Configuration Management Module
# All configuration functionality in one organized module (500 lines max)
# =============================================================================

# Module guard to prevent multiple loading
if [[ "${MILOU_CONFIG_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_CONFIG_LOADED="true"

# Ensure logging is available
if ! command -v log >/dev/null 2>&1; then
    source "${BASH_SOURCE%/*}/utils.sh" 2>/dev/null || {
        echo "ERROR: Cannot load utilities module" >&2
        return 1
    }
fi

# =============================================================================
# Configuration Variables and Defaults (Lines 1-50)
# =============================================================================

# Default configuration paths
DEFAULT_CONFIG_DIR="${HOME}/.milou"
DEFAULT_ENV_FILE=".env"
DEFAULT_CONFIG_FILE="milou.conf"

# Configuration state
declare -g CONFIG_LOADED=false
declare -g CONFIG_FILE=""
declare -g ENV_FILE=""
declare -g CONFIG_DIR=""

# Required environment variables
REQUIRED_ENV_VARS=(
    "DOMAIN"
    "EMAIL"
    "GITHUB_TOKEN"
)

# Optional environment variables with defaults
declare -A DEFAULT_ENV_VALUES=(
    ["COMPOSE_PROJECT_NAME"]="static"
    ["DOCKER_REGISTRY"]="ghcr.io"
    ["SSL_PROVIDER"]="letsencrypt"
    ["BACKUP_ENABLED"]="true"
    ["LOG_LEVEL"]="INFO"
    ["INTERACTIVE"]="true"
)

# Configuration validation patterns
DOMAIN_PATTERN="^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$"
EMAIL_PATTERN="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
TOKEN_PATTERN="^ghp_[A-Za-z0-9]{36}$"

# Initialize configuration management
config_init() {
    log "DEBUG" "Initializing configuration management..."
    
    # Set default paths - only if not already set
    if [[ -z "${CONFIG_DIR:-}" ]]; then
        CONFIG_DIR="$DEFAULT_CONFIG_DIR"
    fi
    
    # Ensure config directory exists
    if [[ ! -d "$CONFIG_DIR" ]]; then
        safe_mkdir "$CONFIG_DIR" 700 || {
            log "WARN" "Cannot create config directory: $CONFIG_DIR"
            CONFIG_DIR="/tmp/milou-config-$$"
            safe_mkdir "$CONFIG_DIR" 700
        }
    fi
    
    log "DEBUG" "Configuration management initialized"
    log "DEBUG" "Config directory: $CONFIG_DIR"
    return 0
}

# =============================================================================
# Environment File Discovery and Loading (Lines 51-150)
# =============================================================================

# Find environment file in common locations
find_env_file() {
    local search_dir="${1:-$(pwd)}"
    
    log "DEBUG" "Searching for environment file starting from: $search_dir"
    
    # Search paths in order of preference
    local search_paths=(
        "$search_dir/.env"
        "$search_dir/.env.local"
        "$search_dir/.env.production"
        "$(pwd)/.env"
        "$HOME/.milou/.env"
        "/opt/milou-cli/.env"
        "/usr/local/milou-cli/.env"
    )
    
    for env_path in "${search_paths[@]}"; do
        if [[ -f "$env_path" && -r "$env_path" ]]; then
            log "DEBUG" "Found environment file: $env_path"
            echo "$env_path"
            return 0
        fi
    done
    
    log "DEBUG" "No environment file found"
    return 1
}

# Load environment file
load_env_file() {
    local env_file="${1:-}"
    
    # Auto-discover if not provided
    if [[ -z "$env_file" ]]; then
        env_file=$(find_env_file) || {
            log "ERROR" "No environment file found"
            return 1
        }
    fi
    
    if [[ ! -f "$env_file" ]]; then
        log "ERROR" "Environment file not found: $env_file"
        return 1
    fi
    
    if [[ ! -r "$env_file" ]]; then
        log "ERROR" "Environment file not readable: $env_file"
        return 1
    fi
    
    log "DEBUG" "Loading environment file: $env_file"
    
    # Validate file before loading
    if ! validate_env_file "$env_file"; then
        log "ERROR" "Environment file validation failed: $env_file"
        return 1
    fi
    
    # Load environment variables
    local loaded_vars=0
    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Extract variable assignment
        if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local var_value="${BASH_REMATCH[2]}"
            
            # Remove quotes if present
            var_value="${var_value#\"}"
            var_value="${var_value%\"}"
            var_value="${var_value#\'}"
            var_value="${var_value%\'}"
            
            # Export variable
            export "$var_name=$var_value"
            ((loaded_vars++))
            
            log "TRACE" "Loaded: $var_name"
        fi
    done < "$env_file"
    
    ENV_FILE="$env_file"
    log "SUCCESS" "Environment loaded: $loaded_vars variables from $env_file"
    return 0
}

# Validate environment file format
validate_env_file() {
    local env_file="$1"
    
    if [[ ! -f "$env_file" ]]; then
        log "ERROR" "Environment file does not exist: $env_file"
        return 1
    fi
    
    log "DEBUG" "Validating environment file: $env_file"
    
    local line_num=0
    local errors=0
    
    while IFS= read -r line; do
        ((line_num++))
        
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Check for valid variable assignment
        if [[ ! "$line" =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=.*$ ]]; then
            log "ERROR" "Invalid line $line_num in $env_file: $line"
            ((errors++))
        fi
        
        # Check for dangerous patterns
        if echo "$line" | grep -qE '\$\(|`|;[[:space:]]*rm|;[[:space:]]*sudo'; then
            log "ERROR" "Potentially dangerous content at line $line_num: $line"
            ((errors++))
        fi
    done < "$env_file"
    
    if [[ $errors -gt 0 ]]; then
        log "ERROR" "Environment file validation failed: $errors errors"
        return 1
    fi
    
    log "DEBUG" "Environment file validation passed"
    return 0
}

# =============================================================================
# Configuration Validation and Management (Lines 151-250)
# =============================================================================

# Validate required environment variables
validate_required_env() {
    log "DEBUG" "Validating required environment variables..."
    
    local missing_vars=()
    local invalid_vars=()
    
    for var in "${REQUIRED_ENV_VARS[@]}"; do
        local value="${!var:-}"
        
        if [[ -z "$value" ]]; then
            missing_vars+=("$var")
            continue
        fi
        
        # Validate specific variable formats
        case "$var" in
            "DOMAIN")
                if ! validate_domain "$value"; then
                    invalid_vars+=("$var: invalid domain format")
                fi
                ;;
            "EMAIL")
                if ! validate_email "$value"; then
                    invalid_vars+=("$var: invalid email format")
                fi
                ;;
            "GITHUB_TOKEN")
                if [[ ! "$value" =~ $TOKEN_PATTERN ]]; then
                    invalid_vars+=("$var: invalid token format")
                fi
                ;;
        esac
    done
    
    # Report missing variables
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log "ERROR" "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
    fi
    
    # Report invalid variables
    if [[ ${#invalid_vars[@]} -gt 0 ]]; then
        log "ERROR" "Invalid environment variables:"
        for var in "${invalid_vars[@]}"; do
            echo "  - $var"
        done
    fi
    
    if [[ ${#missing_vars[@]} -gt 0 || ${#invalid_vars[@]} -gt 0 ]]; then
        return 1
    fi
    
    log "SUCCESS" "All required environment variables are valid"
    return 0
}

# Set default values for optional variables
set_default_env_values() {
    log "DEBUG" "Setting default values for optional environment variables..."
    
    local defaults_set=0
    
    for var in "${!DEFAULT_ENV_VALUES[@]}"; do
        local current_value="${!var:-}"
        local default_value="${DEFAULT_ENV_VALUES[$var]}"
        
        if [[ -z "$current_value" ]]; then
            export "$var=$default_value"
            log "DEBUG" "Set default: $var=$default_value"
            ((defaults_set++))
        fi
    done
    
    if [[ $defaults_set -gt 0 ]]; then
        log "DEBUG" "Set $defaults_set default values"
    fi
    
    return 0
}

# Generate configuration template
generate_config_template() {
    local output_file="${1:-$DEFAULT_ENV_FILE}"
    
    log "STEP" "Generating configuration template: $output_file"
    
    if [[ -f "$output_file" ]]; then
        if ! ask_yes_no "Configuration file exists. Overwrite?"; then
            log "INFO" "Template generation cancelled"
            return 0
        fi
        
        # Create backup
        backup_file "$output_file" || {
            log "WARN" "Failed to create backup"
        }
    fi
    
    cat > "$output_file" << 'EOF'
# Milou CLI Configuration
# Generated template - customize for your environment

# Required Configuration
DOMAIN=your-domain.com
EMAIL=your-email@domain.com
GITHUB_TOKEN=ghp_your_github_token_here

# Optional Configuration (with defaults)
COMPOSE_PROJECT_NAME=static
DOCKER_REGISTRY=ghcr.io
SSL_PROVIDER=letsencrypt
BACKUP_ENABLED=true
LOG_LEVEL=INFO
INTERACTIVE=true

# Advanced Configuration
# DEV_MODE=false
# FORCE_RECREATE=false
# SKIP_SSL=false
# CUSTOM_DOMAIN_SUFFIX=
# BACKUP_RETENTION_DAYS=30

# Docker Configuration
# DOCKER_REGISTRY_USERNAME=
# DOCKER_REGISTRY_PASSWORD=

# SSL Configuration
# SSL_EMAIL=${EMAIL}
# SSL_STAGING=false
# SSL_KEY_SIZE=4096

# Logging Configuration
# LOG_TO_FILE=true
# LOG_FILE=${HOME}/.milou/milou.log
# VERBOSE=false
# DEBUG=false
# QUIET=false
EOF
    
    chmod 600 "$output_file"
    log "SUCCESS" "Configuration template generated: $output_file"
    log "INFO" "Please edit the file and set your actual values"
    
    return 0
}

# =============================================================================
# Configuration File Management (Lines 251-350)
# =============================================================================

# Load configuration file
load_config_file() {
    local config_file="${1:-}"
    
    # Auto-discover if not provided
    if [[ -z "$config_file" ]]; then
        local search_paths=(
            "$CONFIG_DIR/$DEFAULT_CONFIG_FILE"
            "$(pwd)/$DEFAULT_CONFIG_FILE"
            "$HOME/$DEFAULT_CONFIG_FILE"
        )
        
        for path in "${search_paths[@]}"; do
            if [[ -f "$path" ]]; then
                config_file="$path"
                break
            fi
        done
    fi
    
    if [[ -z "$config_file" || ! -f "$config_file" ]]; then
        log "DEBUG" "No configuration file found, using defaults"
        return 0
    fi
    
    log "DEBUG" "Loading configuration file: $config_file"
    
    # Source the configuration file
    if source "$config_file" 2>/dev/null; then
        CONFIG_FILE="$config_file"
        log "DEBUG" "Configuration file loaded successfully"
        return 0
    else
        log "ERROR" "Failed to load configuration file: $config_file"
        return 1
    fi
}

# Save current configuration
save_config() {
    local config_file="${1:-$CONFIG_DIR/$DEFAULT_CONFIG_FILE}"
    
    log "STEP" "Saving configuration to: $config_file"
    
    # Create backup if file exists
    if [[ -f "$config_file" ]]; then
        backup_file "$config_file" || {
            log "WARN" "Failed to create backup"
        }
    fi
    
    # Ensure directory exists
    safe_mkdir "$(dirname "$config_file")" || return 1
    
    # Write configuration
    cat > "$config_file" << EOF
# Milou CLI Configuration
# Generated on $(date)

# Core Settings
MILOU_USER=${MILOU_USER:-milou}
MILOU_GROUP=${MILOU_GROUP:-milou}
CONFIG_DIR=${CONFIG_DIR}

# Environment Settings
$(env | grep -E '^(DOMAIN|EMAIL|GITHUB_TOKEN|COMPOSE_PROJECT_NAME|DOCKER_REGISTRY|SSL_PROVIDER|BACKUP_ENABLED|LOG_LEVEL|INTERACTIVE)=' | sort)

# Paths
ENV_FILE=${ENV_FILE:-}
SCRIPT_DIR=${SCRIPT_DIR:-}

# Runtime Settings
CONFIG_LOADED=true
EOF
    
    chmod 600 "$config_file"
    CONFIG_FILE="$config_file"
    
    log "SUCCESS" "Configuration saved: $config_file"
    return 0
}

# Show current configuration
show_config() {
    log "INFO" "Current Configuration:"
    
    echo "  Configuration Status:"
    echo "    Loaded: ${CONFIG_LOADED}"
    echo "    Config File: ${CONFIG_FILE:-none}"
    echo "    Environment File: ${ENV_FILE:-none}"
    echo "    Config Directory: ${CONFIG_DIR:-none}"
    
    echo
    echo "  Required Variables:"
    for var in "${REQUIRED_ENV_VARS[@]}"; do
        local value="${!var:-}"
        if [[ -n "$value" ]]; then
            # Mask sensitive values
            if [[ "$var" == "GITHUB_TOKEN" ]]; then
                echo "    $var: ${value:0:8}..."
            else
                echo "    $var: $value"
            fi
        else
            echo "    $var: ❌ NOT SET"
        fi
    done
    
    echo
    echo "  Optional Variables:"
    for var in "${!DEFAULT_ENV_VALUES[@]}"; do
        local value="${!var:-}"
        local default="${DEFAULT_ENV_VALUES[$var]}"
        
        if [[ -n "$value" ]]; then
            if [[ "$value" == "$default" ]]; then
                echo "    $var: $value (default)"
            else
                echo "    $var: $value"
            fi
        else
            echo "    $var: $default (default)"
        fi
    done
    
    return 0
}

# =============================================================================
# Configuration Validation and Testing (Lines 351-450)
# =============================================================================

# Test configuration
test_config() {
    log "STEP" "Testing configuration..."
    
    local errors=0
    
    # Test environment variables
    if ! validate_required_env; then
        ((errors++))
    fi
    
    # Test file accessibility
    if [[ -n "$ENV_FILE" && ! -r "$ENV_FILE" ]]; then
        log "ERROR" "Environment file not readable: $ENV_FILE"
        ((errors++))
    fi
    
    if [[ -n "$CONFIG_FILE" && ! -r "$CONFIG_FILE" ]]; then
        log "ERROR" "Configuration file not readable: $CONFIG_FILE"
        ((errors++))
    fi
    
    # Test directory permissions
    if [[ ! -w "$CONFIG_DIR" ]]; then
        log "ERROR" "Configuration directory not writable: $CONFIG_DIR"
        ((errors++))
    fi
    
    # Test domain connectivity (if domain is set)
    if [[ -n "${DOMAIN:-}" ]]; then
        if command_exists dig; then
            if ! dig +short "$DOMAIN" >/dev/null 2>&1; then
                log "WARN" "Domain may not be properly configured: $DOMAIN"
            else
                log "DEBUG" "Domain resolves correctly: $DOMAIN"
            fi
        fi
    fi
    
    # Test GitHub token (if set)
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        if command_exists curl; then
            if curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user >/dev/null 2>&1; then
                log "DEBUG" "GitHub token is valid"
            else
                log "WARN" "GitHub token may be invalid or expired"
            fi
        fi
    fi
    
    if [[ $errors -eq 0 ]]; then
        log "SUCCESS" "Configuration test passed"
        return 0
    else
        log "ERROR" "Configuration test failed with $errors errors"
        return 1
    fi
}

# Reset configuration
reset_config() {
    local force="${1:-false}"
    
    if [[ "$force" != "true" ]]; then
        log "WARN" "This will reset all configuration to defaults"
        if ! ask_yes_no "Continue with configuration reset?"; then
            log "INFO" "Configuration reset cancelled"
            return 0
        fi
    fi
    
    log "STEP" "Resetting configuration..."
    
    # Backup current configuration
    if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
        backup_file "$CONFIG_FILE" || {
            log "WARN" "Failed to backup configuration file"
        }
    fi
    
    if [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
        backup_file "$ENV_FILE" || {
            log "WARN" "Failed to backup environment file"
        }
    fi
    
    # Reset variables
    CONFIG_LOADED=false
    CONFIG_FILE=""
    ENV_FILE=""
    
    # Unset environment variables
    for var in "${REQUIRED_ENV_VARS[@]}"; do
        unset "$var"
    done
    
    for var in "${!DEFAULT_ENV_VALUES[@]}"; do
        unset "$var"
    done
    
    log "SUCCESS" "Configuration reset completed"
    return 0
}

# =============================================================================
# Configuration Import/Export and Migration (Lines 451-500)
# =============================================================================

# Export configuration
export_config() {
    local output_file="${1:-$CONFIG_DIR/milou-config-export-$(date +%Y%m%d-%H%M%S).tar.gz}"
    
    log "STEP" "Exporting configuration to: $output_file"
    
    local temp_dir="/tmp/milou-config-export-$$"
    safe_mkdir "$temp_dir" || return 1
    
    # Copy configuration files
    if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
        cp "$CONFIG_FILE" "$temp_dir/milou.conf" || {
            log "ERROR" "Failed to copy configuration file"
            return 1
        }
    fi
    
    if [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
        cp "$ENV_FILE" "$temp_dir/.env" || {
            log "ERROR" "Failed to copy environment file"
            return 1
        }
    fi
    
    # Create metadata file
    cat > "$temp_dir/export-metadata.txt" << EOF
Export Date: $(date)
Milou CLI Version: ${MILOU_VERSION:-unknown}
System: $(uname -a)
User: $(whoami)
Config Directory: $CONFIG_DIR
EOF
    
    # Create archive
    (cd "$temp_dir" && tar -czf "$output_file" .) || {
        log "ERROR" "Failed to create configuration archive"
        rm -rf "$temp_dir"
        return 1
    }
    
    # Cleanup
    rm -rf "$temp_dir"
    
    log "SUCCESS" "Configuration exported: $output_file"
    return 0
}

# Import configuration
import_config() {
    local import_file="$1"
    
    if [[ ! -f "$import_file" ]]; then
        log "ERROR" "Import file not found: $import_file"
        return 1
    fi
    
    log "STEP" "Importing configuration from: $import_file"
    
    local temp_dir="/tmp/milou-config-import-$$"
    safe_mkdir "$temp_dir" || return 1
    
    # Extract archive
    if ! tar -xzf "$import_file" -C "$temp_dir" 2>/dev/null; then
        log "ERROR" "Failed to extract configuration archive"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Validate extracted files
    local imported_files=0
    
    if [[ -f "$temp_dir/milou.conf" ]]; then
        cp "$temp_dir/milou.conf" "$CONFIG_DIR/" || {
            log "WARN" "Failed to import configuration file"
        }
        ((imported_files++))
    fi
    
    if [[ -f "$temp_dir/.env" ]]; then
        cp "$temp_dir/.env" "$(pwd)/" || {
            log "WARN" "Failed to import environment file"
        }
        ((imported_files++))
    fi
    
    # Show metadata if available
    if [[ -f "$temp_dir/export-metadata.txt" ]]; then
        log "INFO" "Import metadata:"
        cat "$temp_dir/export-metadata.txt" | sed 's/^/  /'
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
    
    if [[ $imported_files -gt 0 ]]; then
        log "SUCCESS" "Configuration imported: $imported_files files"
        log "INFO" "Please reload configuration to apply changes"
        return 0
    else
        log "ERROR" "No configuration files found in archive"
        return 1
    fi
}

# Initialize configuration management
config_init

# Export main functions for external use
export -f find_env_file load_env_file validate_env_file
export -f validate_required_env set_default_env_values generate_config_template
export -f load_config_file save_config show_config
export -f test_config reset_config export_config import_config 