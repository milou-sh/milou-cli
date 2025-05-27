#!/bin/bash

# =============================================================================
# Milou CLI - Consolidated Configuration Management Module
# All configuration functionality in one organized module (500 lines max)
# =============================================================================

# Preserve PATH to prevent corruption during environment loading
if [[ -n "${SYSTEM_PATH:-}" ]]; then
    export PATH="$SYSTEM_PATH"
fi

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

# Generate complete environment file with all required variables
generate_complete_env_file() {
    local domain="$1"
    local email="$2"
    local github_token="$3"
    local output_file="${4:-.env}"
    
    log "STEP" "Generating complete environment configuration: $output_file"
    
    # Preserve existing secrets if file exists
    local existing_secrets=()
    if [[ -f "$output_file" ]]; then
        log "INFO" "Preserving existing secrets from $output_file"
        existing_secrets=($(extract_existing_secrets "$output_file"))
    fi
    
    # Calculate dynamic SSL certificate path
    local ssl_cert_path
    if [[ -n "${SCRIPT_DIR:-}" ]]; then
        ssl_cert_path="$SCRIPT_DIR/ssl"
    else
        ssl_cert_path="$(pwd)/ssl"
    fi
    
    # Use existing secrets or generate new ones
    local db_user db_password redis_password session_secret encryption_key jwt_secret sso_encryption_key
    
    if [[ ${#existing_secrets[@]} -gt 0 ]]; then
        # Extract existing secrets
        db_user=$(get_existing_secret "DB_USER" "${existing_secrets[@]}" || echo "milou_$(generate_random_string 8)")
        db_password=$(get_existing_secret "DB_PASSWORD" "${existing_secrets[@]}" || echo "$(generate_random_string 32)")
        redis_password=$(get_existing_secret "REDIS_PASSWORD" "${existing_secrets[@]}" || echo "$(generate_random_string 32)")
        session_secret=$(get_existing_secret "SESSION_SECRET" "${existing_secrets[@]}" || echo "$(generate_random_string 64)")
        encryption_key=$(get_existing_secret "ENCRYPTION_KEY" "${existing_secrets[@]}" || echo "$(generate_random_string 32)")
        jwt_secret=$(get_existing_secret "JWT_SECRET" "${existing_secrets[@]}" || echo "$(generate_random_string 64)")
        sso_encryption_key=$(get_existing_secret "SSO_CONFIG_ENCRYPTION_KEY" "${existing_secrets[@]}" || echo "$(generate_random_string 64)")
        log "SUCCESS" "Preserved existing secrets for database and security"
    else
        # Generate new secrets
        db_user="milou_$(generate_random_string 8)"
        db_password="$(generate_random_string 32)"
        redis_password="$(generate_random_string 32)"
        session_secret="$(generate_random_string 64)"
        encryption_key="$(generate_random_string 32)"
        jwt_secret="$(generate_random_string 64)"
        sso_encryption_key="$(generate_random_string 64)"
        log "INFO" "Generated new secrets for fresh installation"
    fi
    
    # Create backup if file exists
    if [[ -f "$output_file" ]]; then
        backup_file "$output_file" || {
            log "WARN" "Failed to create backup"
        }
    fi

    cat > "$output_file" << EOF
# Milou Application Environment Configuration
# Generated on $(date)
# ========================================

# Required Configuration Variables
# ----------------------------------------
DOMAIN=$domain
EMAIL=$email
GITHUB_TOKEN=$github_token

# Nginx configuration
# ----------------------------------------
SERVER_NAME=$domain
CUSTOMER_DOMAIN_NAME=$domain
SSL_PORT=443
SSL_CERT_PATH=$ssl_cert_path
CORS_ORIGIN=https://$domain

# Database Configuration
# ----------------------------------------
DB_HOST=db
DB_PORT=5432
DB_USER=$db_user
DB_PASSWORD=$db_password
DB_NAME=milou
DATABASE_URI=postgresql+psycopg2://$db_user:$db_password@db:5432/milou
POSTGRES_USER=$db_user
POSTGRES_PASSWORD=$db_password
POSTGRES_DB=milou

# Redis Configuration
# ----------------------------------------
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=$redis_password
REDIS_URL=redis://redis:6379
REDIS_SESSION_TTL=3600
REDIS_MAX_RETRIES=3
REDIS_CONNECT_TIMEOUT=10000
REDIS_CLEANUP_ENABLED=true
REDIS_CLEANUP_INTERVAL=3600

# RabbitMQ Configuration
# ----------------------------------------
RABBITMQ_URL=amqp://guest:guest@rabbitmq:5672
RABBITMQ_USER=guest
RABBITMQ_PASSWORD=guest

# Session Configuration
# ----------------------------------------
SESSION_SECRET=$session_secret

# Security
# ----------------------------------------
ENCRYPTION_KEY=$encryption_key
JWT_SECRET=$jwt_secret
SSO_CONFIG_ENCRYPTION_KEY=$sso_encryption_key

# API Configuration
# ----------------------------------------
PORT=9999
FRONTEND_URL=https://$domain
BACKEND_URL=https://$domain/api

# Admin Configuration
# ----------------------------------------
ADMIN_EMAIL=$email
ADMIN_PASSWORD=admin123

# Environment
# ----------------------------------------
NODE_ENV=production

# Docker Image Tags
# ----------------------------------------
MILOU_ENGINE_TAG=latest
MILOU_NGINX_TAG=latest
MILOU_DATABASE_TAG=latest
MILOU_FRONTEND_TAG=latest
MILOU_BACKEND_TAG=latest

# Optional Configuration (with defaults)
# ----------------------------------------
COMPOSE_PROJECT_NAME=static
DOCKER_REGISTRY=ghcr.io
SSL_PROVIDER=letsencrypt
BACKUP_ENABLED=true
LOG_LEVEL=INFO
INTERACTIVE=${INTERACTIVE:-true}
EOF
    
    chmod 600 "$output_file"
    log "SUCCESS" "Complete environment configuration generated: $output_file"
    
    # Also copy to user's .milou directory
    local user_env_file="$HOME/.milou/.env"
    mkdir -p "$(dirname "$user_env_file")"
    cp "$output_file" "$user_env_file"
    chmod 600 "$user_env_file"
    
    return 0
}

# Extract existing secrets from environment file
extract_existing_secrets() {
    local env_file="$1"
    local secrets=()
    
    if [[ ! -f "$env_file" ]]; then
        return 1
    fi
    
    # List of secret variables to preserve
    local secret_vars=(
        "DB_USER" "DB_PASSWORD" "POSTGRES_USER" "POSTGRES_PASSWORD"
        "REDIS_PASSWORD" "SESSION_SECRET" "ENCRYPTION_KEY" 
        "JWT_SECRET" "SSO_CONFIG_ENCRYPTION_KEY" "GITHUB_TOKEN"
        "ADMIN_PASSWORD"
    )
    
    for var in "${secret_vars[@]}"; do
        local value=$(grep "^${var}=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"'"'"'')
        if [[ -n "$value" ]]; then
            secrets+=("${var}=${value}")
        fi
    done
    
    printf '%s\n' "${secrets[@]}"
}

# Get existing secret value
get_existing_secret() {
    local var_name="$1"
    shift
    local secrets=("$@")
    
    for secret in "${secrets[@]}"; do
        if [[ "$secret" =~ ^${var_name}= ]]; then
            echo "${secret#*=}"
            return 0
        fi
    done
    
    return 1
}

# Update environment file preserving secrets
update_env_preserving_secrets() {
    local domain="$1"
    local email="$2"
    local github_token="$3"
    local output_file="${4:-.env}"
    
    log "STEP" "Updating environment configuration while preserving secrets: $output_file"
    
    if [[ ! -f "$output_file" ]]; then
        log "INFO" "No existing environment file, creating new one"
        generate_complete_env_file "$domain" "$email" "$github_token" "$output_file"
        return $?
    fi
    
    # Extract all existing secrets
    local existing_secrets
    existing_secrets=($(extract_existing_secrets "$output_file"))
    
    if [[ ${#existing_secrets[@]} -eq 0 ]]; then
        log "WARN" "No existing secrets found, generating new environment file"
        generate_complete_env_file "$domain" "$email" "$github_token" "$output_file"
        return $?
    fi
    
    log "INFO" "Found ${#existing_secrets[@]} existing secrets to preserve"
    
    # Create backup
    backup_file "$output_file" || {
        log "WARN" "Failed to create backup"
    }
    
    # Calculate dynamic SSL certificate path
    local ssl_cert_path
    if [[ -n "${SCRIPT_DIR:-}" ]]; then
        ssl_cert_path="$SCRIPT_DIR/ssl"
    else
        ssl_cert_path="$(pwd)/ssl"
    fi
    
    # Extract preserved values
    local db_user=$(get_existing_secret "DB_USER" "${existing_secrets[@]}")
    local db_password=$(get_existing_secret "DB_PASSWORD" "${existing_secrets[@]}")
    local redis_password=$(get_existing_secret "REDIS_PASSWORD" "${existing_secrets[@]}")
    local session_secret=$(get_existing_secret "SESSION_SECRET" "${existing_secrets[@]}")
    local encryption_key=$(get_existing_secret "ENCRYPTION_KEY" "${existing_secrets[@]}")
    local jwt_secret=$(get_existing_secret "JWT_SECRET" "${existing_secrets[@]}")
    local sso_encryption_key=$(get_existing_secret "SSO_CONFIG_ENCRYPTION_KEY" "${existing_secrets[@]}")
    local admin_password=$(get_existing_secret "ADMIN_PASSWORD" "${existing_secrets[@]}" || echo "admin123")
    
    # Use provided GitHub token or preserve existing one
    if [[ -z "$github_token" ]]; then
        github_token=$(get_existing_secret "GITHUB_TOKEN" "${existing_secrets[@]}")
    fi

    cat > "$output_file" << EOF
# Milou Application Environment Configuration
# Updated on $(date) - Secrets preserved from previous version
# ========================================

# Required Configuration Variables
# ----------------------------------------
DOMAIN=$domain
EMAIL=$email
GITHUB_TOKEN=$github_token

# Nginx configuration
# ----------------------------------------
SERVER_NAME=$domain
CUSTOMER_DOMAIN_NAME=$domain
SSL_PORT=443
SSL_CERT_PATH=$ssl_cert_path
CORS_ORIGIN=https://$domain

# Database Configuration (PRESERVED)
# ----------------------------------------
DB_HOST=db
DB_PORT=5432
DB_USER=$db_user
DB_PASSWORD=$db_password
DB_NAME=milou
DATABASE_URI=postgresql+psycopg2://$db_user:$db_password@db:5432/milou
POSTGRES_USER=$db_user
POSTGRES_PASSWORD=$db_password
POSTGRES_DB=milou

# Redis Configuration (PRESERVED)
# ----------------------------------------
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=$redis_password
REDIS_URL=redis://redis:6379
REDIS_SESSION_TTL=3600
REDIS_MAX_RETRIES=3
REDIS_CONNECT_TIMEOUT=10000
REDIS_CLEANUP_ENABLED=true
REDIS_CLEANUP_INTERVAL=3600

# RabbitMQ Configuration
# ----------------------------------------
RABBITMQ_URL=amqp://guest:guest@rabbitmq:5672
RABBITMQ_USER=guest
RABBITMQ_PASSWORD=guest

# Session Configuration (PRESERVED)
# ----------------------------------------
SESSION_SECRET=$session_secret

# Security (PRESERVED)
# ----------------------------------------
ENCRYPTION_KEY=$encryption_key
JWT_SECRET=$jwt_secret
SSO_CONFIG_ENCRYPTION_KEY=$sso_encryption_key

# API Configuration
# ----------------------------------------
PORT=9999
FRONTEND_URL=https://$domain
BACKEND_URL=https://$domain/api

# Admin Configuration (PRESERVED)
# ----------------------------------------
ADMIN_EMAIL=$email
ADMIN_PASSWORD=$admin_password

# Environment
# ----------------------------------------
NODE_ENV=production

# Docker Image Tags
# ----------------------------------------
MILOU_ENGINE_TAG=latest
MILOU_NGINX_TAG=latest
MILOU_DATABASE_TAG=latest
MILOU_FRONTEND_TAG=latest
MILOU_BACKEND_TAG=latest

# Optional Configuration (with defaults)
# ----------------------------------------
COMPOSE_PROJECT_NAME=static
DOCKER_REGISTRY=ghcr.io
SSL_PROVIDER=letsencrypt
BACKUP_ENABLED=true
LOG_LEVEL=INFO
INTERACTIVE=${INTERACTIVE:-true}
EOF
    
    chmod 600 "$output_file"
    log "SUCCESS" "Environment configuration updated with preserved secrets: $output_file"
    
    # Also copy to user's .milou directory
    local user_env_file="$HOME/.milou/.env"
    mkdir -p "$(dirname "$user_env_file")"
    cp "$output_file" "$user_env_file"
    chmod 600 "$user_env_file"
    
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
INTERACTIVE=${INTERACTIVE:-true}

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

# Smart environment configuration that handles all installation scenarios
smart_env_configuration() {
    local domain="$1"
    local email="$2"
    local github_token="$3"
    local output_file="${4:-.env}"
    
    log "STEP" "🧠 Smart environment configuration for all installation scenarios"
    
    # Detect installation state
    local install_state=$(detect_installation_state)
    log "INFO" "Installation state detected: $install_state"
    
    # Clean conflicting system environment variables first
    clean_system_env_vars
    
    # Detect port conflicts and system constraints
    local port_config=$(detect_port_configuration)
    log "INFO" "Port configuration: $port_config"
    
    # Handle different scenarios
    case "$install_state" in
        "fresh")
            log "INFO" "Fresh installation - generating new configuration"
            generate_fresh_env_config "$domain" "$email" "$github_token" "$output_file" "$port_config"
            ;;
        "partial")
            log "INFO" "Partial installation - preserving existing data and fixing issues"
            fix_partial_env_config "$domain" "$email" "$github_token" "$output_file" "$port_config"
            ;;
        "complete")
            log "INFO" "Complete installation - preserving all secrets and updating configuration"
            update_complete_env_config "$domain" "$email" "$github_token" "$output_file" "$port_config"
            ;;
        "corrupted")
            log "WARN" "Corrupted installation - attempting recovery"
            recover_corrupted_env_config "$domain" "$email" "$github_token" "$output_file" "$port_config"
            ;;
        *)
            log "ERROR" "Unknown installation state: $install_state"
            return 1
            ;;
    esac
    
    # Add port configuration if missing
    if ! validate_env_completeness "$output_file"; then
        log "INFO" "Adding missing port configuration"
        add_port_configuration "$output_file"
    fi
    
    # Sync environment files
    sync_env_files "$output_file" "static/.env"
    
    # Validate the final configuration
    if validate_smart_env_config "$output_file" && validate_env_completeness "$output_file"; then
        log "SUCCESS" "Smart environment configuration completed successfully"
        return 0
    else
        log "ERROR" "Smart environment configuration validation failed"
        return 1
    fi
}

# Detect installation state
detect_installation_state() {
    local has_env_file=false
    local has_secrets=false
    local has_docker_volumes=false
    local has_running_services=false
    local env_file_valid=false
    
    # Check for environment file
    if [[ -f ".env" ]]; then
        has_env_file=true
        if validate_env_file ".env" >/dev/null 2>&1; then
            env_file_valid=true
            # Check for secrets
            local secret_count=$(extract_existing_secrets ".env" 2>/dev/null | wc -l)
            if [[ $secret_count -gt 0 ]]; then
                has_secrets=true
            fi
        fi
    fi
    
    # Check for Docker volumes
    if docker volume ls 2>/dev/null | grep -q "static_"; then
        has_docker_volumes=true
    fi
    
    # Check for running services
    if docker ps 2>/dev/null | grep -q "milou-"; then
        has_running_services=true
    fi
    
    # Determine state
    if [[ "$has_env_file" == false && "$has_docker_volumes" == false ]]; then
        echo "fresh"
    elif [[ "$has_env_file" == true && "$env_file_valid" == true && "$has_secrets" == true ]]; then
        echo "complete"
    elif [[ "$has_env_file" == true && "$env_file_valid" == false ]]; then
        echo "corrupted"
    else
        echo "partial"
    fi
}

# Detect port configuration and conflicts
detect_port_configuration() {
    local config=""
    
    # Check common port conflicts
    local postgres_port=5432
    local redis_port=6379
    local http_port=80
    local https_port=443
    
    # Check PostgreSQL port
    if ss -tlnp 2>/dev/null | grep -q ":5432 " || netstat -tlnp 2>/dev/null | grep -q ":5432 "; then
        postgres_port=5433
        config="${config}DB_EXTERNAL_PORT=5433;"
        log "INFO" "PostgreSQL port conflict detected, using port 5433"
    fi
    
    # Check Redis port
    if ss -tlnp 2>/dev/null | grep -q ":6379 " || netstat -tlnp 2>/dev/null | grep -q ":6379 "; then
        redis_port=6380
        config="${config}REDIS_EXTERNAL_PORT=6380;"
        log "INFO" "Redis port conflict detected, using port 6380"
    fi
    
    # Check HTTP/HTTPS ports (need root for ports < 1024)
    if [[ $EUID -ne 0 ]]; then
        http_port=8080
        https_port=8443
        config="${config}HTTP_PORT=8080;HTTPS_PORT=8443;"
        log "INFO" "Non-root user detected, using ports 8080/8443 for HTTP/HTTPS"
    fi
    
    # Check if we're in a container or restricted environment
    if [[ -f "/.dockerenv" ]] || [[ -n "${CONTAINER:-}" ]]; then
        config="${config}CONTAINER_ENV=true;"
        log "INFO" "Container environment detected"
    fi
    
    echo "$config"
}

# Generate fresh environment configuration
generate_fresh_env_config() {
    local domain="$1"
    local email="$2"
    local github_token="$3"
    local output_file="$4"
    local port_config="$5"
    
    log "INFO" "Generating fresh environment configuration"
    
    # Parse port configuration
    local db_external_port=5432
    local redis_external_port=6379
    local http_port=80
    local https_port=443
    
    if [[ "$port_config" =~ DB_EXTERNAL_PORT=([0-9]+) ]]; then
        db_external_port="${BASH_REMATCH[1]}"
    fi
    if [[ "$port_config" =~ REDIS_EXTERNAL_PORT=([0-9]+) ]]; then
        redis_external_port="${BASH_REMATCH[1]}"
    fi
    if [[ "$port_config" =~ HTTP_PORT=([0-9]+) ]]; then
        http_port="${BASH_REMATCH[1]}"
    fi
    if [[ "$port_config" =~ HTTPS_PORT=([0-9]+) ]]; then
        https_port="${BASH_REMATCH[1]}"
    fi
    
    # Generate new secrets
    local db_user="milou_$(generate_random_string 8)"
    local db_password="$(generate_random_string 32)"
    local redis_password="$(generate_random_string 32)"
    local session_secret="$(generate_random_string 64)"
    local encryption_key="$(generate_random_string 32)"
    local jwt_secret="$(generate_random_string 64)"
    local sso_encryption_key="$(generate_random_string 64)"
    
    # Calculate SSL certificate path
    local ssl_cert_path
    if [[ -n "${SCRIPT_DIR:-}" ]]; then
        ssl_cert_path="$SCRIPT_DIR/ssl"
    else
        ssl_cert_path="$(pwd)/ssl"
    fi
    
    cat > "$output_file" << EOF
# Milou Application Environment Configuration
# Fresh installation generated on $(date)
# ========================================

# Required Configuration Variables
# ----------------------------------------
DOMAIN=$domain
EMAIL=$email
GITHUB_TOKEN=$github_token

# Nginx configuration
# ----------------------------------------
SERVER_NAME=$domain
CUSTOMER_DOMAIN_NAME=$domain
SSL_PORT=$https_port
SSL_CERT_PATH=$ssl_cert_path
CORS_ORIGIN=https://$domain

# Database Configuration
# ----------------------------------------
DB_HOST=db
DB_PORT=5432
DB_EXTERNAL_PORT=$db_external_port
DB_USER=$db_user
DB_PASSWORD=$db_password
DB_NAME=milou
DATABASE_URI=postgresql+psycopg2://$db_user:$db_password@db:5432/milou
POSTGRES_USER=$db_user
POSTGRES_PASSWORD=$db_password
POSTGRES_DB=milou

# Redis Configuration
# ----------------------------------------
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_EXTERNAL_PORT=$redis_external_port
REDIS_PASSWORD=$redis_password
REDIS_URL=redis://redis:6379
REDIS_SESSION_TTL=3600
REDIS_MAX_RETRIES=3
REDIS_CONNECT_TIMEOUT=10000
REDIS_CLEANUP_ENABLED=true
REDIS_CLEANUP_INTERVAL=3600

# RabbitMQ Configuration
# ----------------------------------------
RABBITMQ_URL=amqp://guest:guest@rabbitmq:5672
RABBITMQ_USER=guest
RABBITMQ_PASSWORD=guest

# Session Configuration
# ----------------------------------------
SESSION_SECRET=$session_secret

# Security
# ----------------------------------------
ENCRYPTION_KEY=$encryption_key
JWT_SECRET=$jwt_secret
SSO_CONFIG_ENCRYPTION_KEY=$sso_encryption_key

# API Configuration
# ----------------------------------------
PORT=9999
FRONTEND_URL=https://$domain
BACKEND_URL=https://$domain/api

# Admin Configuration
# ----------------------------------------
ADMIN_EMAIL=$email
ADMIN_PASSWORD=admin123

# Environment
# ----------------------------------------
NODE_ENV=production

# Network Configuration
# ----------------------------------------
HTTP_PORT=$http_port
HTTPS_PORT=$https_port

# Docker Image Tags
# ----------------------------------------
MILOU_ENGINE_TAG=latest
MILOU_NGINX_TAG=latest
MILOU_DATABASE_TAG=latest
MILOU_FRONTEND_TAG=latest
MILOU_BACKEND_TAG=latest

# Optional Configuration (with defaults)
# ----------------------------------------
COMPOSE_PROJECT_NAME=static
DOCKER_REGISTRY=ghcr.io
SSL_PROVIDER=letsencrypt
BACKUP_ENABLED=true
LOG_LEVEL=INFO
INTERACTIVE=${INTERACTIVE:-true}
EOF
    
    chmod 600 "$output_file"
    log "SUCCESS" "Fresh environment configuration generated"
}

# Fix partial environment configuration
fix_partial_env_config() {
    local domain="$1"
    local email="$2"
    local github_token="$3"
    local output_file="$4"
    local port_config="$5"
    
    log "INFO" "Fixing partial environment configuration"
    
    # Try to preserve existing secrets if possible
    local existing_secrets=()
    if [[ -f "$output_file" ]]; then
        existing_secrets=($(extract_existing_secrets "$output_file" 2>/dev/null || true))
    fi
    
    # Create backup
    if [[ -f "$output_file" ]]; then
        backup_file "$output_file" || log "WARN" "Failed to create backup"
    fi
    
    # If we have some secrets, try to preserve them
    if [[ ${#existing_secrets[@]} -gt 0 ]]; then
        log "INFO" "Preserving ${#existing_secrets[@]} existing secrets"
        update_env_preserving_secrets "$domain" "$email" "$github_token" "$output_file"
    else
        log "INFO" "No existing secrets found, generating fresh configuration"
        generate_fresh_env_config "$domain" "$email" "$github_token" "$output_file" "$port_config"
    fi
    
    # Add port configuration
    add_port_configuration "$output_file" "$port_config"
}

# Update complete environment configuration
update_complete_env_config() {
    local domain="$1"
    local email="$2"
    local github_token="$3"
    local output_file="$4"
    local port_config="$5"
    
    log "INFO" "Updating complete environment configuration"
    
    # Use the existing secret-preserving update
    update_env_preserving_secrets "$domain" "$email" "$github_token" "$output_file"
    
    # Add/update port configuration
    add_port_configuration "$output_file" "$port_config"
}

# Recover corrupted environment configuration
recover_corrupted_env_config() {
    local domain="$1"
    local email="$2"
    local github_token="$3"
    local output_file="$4"
    local port_config="$5"
    
    log "WARN" "Attempting to recover corrupted environment configuration"
    
    # Try to extract any salvageable secrets
    local salvaged_secrets=()
    if [[ -f "$output_file" ]]; then
        # Try to extract secrets even from corrupted file
        while IFS= read -r line; do
            if [[ "$line" =~ ^(DB_USER|DB_PASSWORD|REDIS_PASSWORD|SESSION_SECRET|ENCRYPTION_KEY|JWT_SECRET|SSO_CONFIG_ENCRYPTION_KEY|GITHUB_TOKEN|ADMIN_PASSWORD)=(.+)$ ]]; then
                salvaged_secrets+=("$line")
            fi
        done < "$output_file"
    fi
    
    # Create backup of corrupted file
    if [[ -f "$output_file" ]]; then
        cp "$output_file" "${output_file}.corrupted.$(date +%Y%m%d-%H%M%S)"
        log "INFO" "Corrupted file backed up"
    fi
    
    if [[ ${#salvaged_secrets[@]} -gt 0 ]]; then
        log "INFO" "Salvaged ${#salvaged_secrets[@]} secrets from corrupted configuration"
        
        # Generate fresh config first
        generate_fresh_env_config "$domain" "$email" "$github_token" "$output_file" "$port_config"
        
        # Then replace with salvaged secrets
        for secret in "${salvaged_secrets[@]}"; do
            local var_name="${secret%%=*}"
            local var_value="${secret#*=}"
            sed -i "s/^${var_name}=.*$/${var_name}=${var_value}/" "$output_file"
        done
        
        log "SUCCESS" "Configuration recovered with salvaged secrets"
    else
        log "WARN" "No secrets could be salvaged, generating fresh configuration"
        generate_fresh_env_config "$domain" "$email" "$github_token" "$output_file" "$port_config"
    fi
}

# Add port configuration to environment file
add_port_configuration() {
    local env_file="$1"
    
    log "DEBUG" "Adding port configuration to: $env_file"
    
    # Check if port configuration already exists
    if grep -q "^DB_EXTERNAL_PORT=" "$env_file" 2>/dev/null; then
        log "DEBUG" "Port configuration already exists in $env_file"
        return 0
    fi
    
    # Detect port conflicts and set appropriate ports
    local db_port=5432
    local redis_port=6379
    local http_port=80
    local https_port=443
    
    # Check for port conflicts and adjust
    if ! port_available 5432; then
        db_port=5433
        log "INFO" "Port 5432 in use, using 5433 for database external port"
    fi
    
    if ! port_available 6379; then
        redis_port=6380
        log "INFO" "Port 6379 in use, using 6380 for Redis external port"
    fi
    
    if ! port_available 80; then
        http_port=8080
        log "INFO" "Port 80 in use, using 8080 for HTTP"
    fi
    
    if ! port_available 443; then
        https_port=8443
        log "INFO" "Port 443 in use, using 8443 for HTTPS"
    fi
    
    # Add port configuration to the file
    {
        echo ""
        echo "# Port Configuration"
        echo "# ----------------------------------------"
        echo "DB_EXTERNAL_PORT=$db_port"
        echo "REDIS_EXTERNAL_PORT=$redis_port"
        echo "HTTP_PORT=$http_port"
        echo "HTTPS_PORT=$https_port"
    } >> "$env_file"
    
    log "SUCCESS" "Port configuration added to $env_file"
    log "INFO" "Database external port: $db_port"
    log "INFO" "Redis external port: $redis_port"
    log "INFO" "HTTP port: $http_port"
    log "INFO" "HTTPS port: $https_port"
    
    return 0
}

# Validate smart environment configuration
validate_smart_env_config() {
    local env_file="$1"
    
    log "DEBUG" "Validating smart environment configuration: $env_file"
    
    # Basic file validation
    if [[ ! -f "$env_file" ]]; then
        log "ERROR" "Environment file not found: $env_file"
        return 1
    fi
    
    # Load and validate environment
    if ! load_env_file "$env_file"; then
        log "ERROR" "Failed to load environment file: $env_file"
        return 1
    fi
    
    if ! validate_required_env; then
        log "ERROR" "Required environment variables validation failed"
        return 1
    fi
    
    # Check for port conflicts in final configuration
    local db_external_port=$(grep "^DB_EXTERNAL_PORT=" "$env_file" | cut -d'=' -f2 2>/dev/null || echo "5432")
    local redis_external_port=$(grep "^REDIS_EXTERNAL_PORT=" "$env_file" | cut -d'=' -f2 2>/dev/null || echo "6379")
    
    # Check if ports are used by non-Milou services
    if [[ "$db_external_port" != "5432" ]]; then
        # Check if port is used by Docker containers
        local docker_port_usage=$(docker ps --format "{{.Names}}" --filter "publish=$db_external_port" 2>/dev/null || true)
        if [[ -n "$docker_port_usage" ]]; then
            # Check if it's a Milou container
            if echo "$docker_port_usage" | grep -q "milou-"; then
                log "DEBUG" "Database external port $db_external_port is used by Milou container: $docker_port_usage"
            else
                log "ERROR" "Database external port $db_external_port is in use by non-Milou container: $docker_port_usage"
                return 1
            fi
        else
            # Check if port is used by system services
            if ss -tln 2>/dev/null | grep -q ":$db_external_port "; then
                log "ERROR" "Database external port $db_external_port is in use by system service"
                return 1
            else
                log "DEBUG" "Database external port $db_external_port is available"
            fi
        fi
    fi
    
    if [[ "$redis_external_port" != "6379" ]]; then
        # Check if port is used by Docker containers
        local docker_port_usage=$(docker ps --format "{{.Names}}" --filter "publish=$redis_external_port" 2>/dev/null || true)
        if [[ -n "$docker_port_usage" ]]; then
            # Check if it's a Milou container
            if echo "$docker_port_usage" | grep -q "milou-"; then
                log "DEBUG" "Redis external port $redis_external_port is used by Milou container: $docker_port_usage"
            else
                log "ERROR" "Redis external port $redis_external_port is in use by non-Milou container: $docker_port_usage"
                return 1
            fi
        else
            # Check if port is used by system services
            if ss -tln 2>/dev/null | grep -q ":$redis_external_port "; then
                log "ERROR" "Redis external port $redis_external_port is in use by system service"
                return 1
            else
                log "DEBUG" "Redis external port $redis_external_port is available"
            fi
        fi
    fi
    
    log "SUCCESS" "Smart environment configuration validation passed"
    return 0
}

# Initialize configuration management
config_init

# =============================================================================
# Interactive Configuration Setup
# =============================================================================

# Interactive configuration setup wizard
milou_config_interactive_setup() {
    log "INFO" "🔧 Starting interactive configuration setup..."
    
    # Check if we're in non-interactive mode
    if [[ "${INTERACTIVE:-true}" == "false" ]]; then
        log "INFO" "Non-interactive mode detected, using provided configuration"
        
        # Use command-line provided values or defaults
        local domain="${DOMAIN:-localhost}"
        local email="${EMAIL:-admin@example.com}"
        local github_token="${GITHUB_TOKEN:-}"
        
        # Use smart environment configuration
        smart_env_configuration "$domain" "$email" "$github_token"
        
        # Load the generated environment file
        load_env_file ".env" || return 1
        
        # Set defaults for missing values
        set_default_env_values
        
        # Validate configuration
        if validate_required_env; then
            log "SUCCESS" "Configuration validated successfully"
            return 0
        else
            log "ERROR" "Configuration validation failed in non-interactive mode"
            return 1
        fi
    fi
    
    # Interactive setup
    log "INFO" "Please provide the following configuration values:"
    echo
    
    # Domain configuration
    local domain="${DOMAIN:-localhost}"
    if [[ "${CUSTOMER_DOMAIN_NAME:-}" != "" ]]; then
        domain="${CUSTOMER_DOMAIN_NAME}"
    fi
    
    read -p "Domain name (default: $domain): " input_domain
    domain="${input_domain:-$domain}"
    export DOMAIN="$domain"
    export CUSTOMER_DOMAIN_NAME="$domain"
    export SERVER_NAME="$domain"
    
    # Email configuration
    local email="${EMAIL:-admin@$domain}"
    read -p "Admin email (default: $email): " input_email
    email="${input_email:-$email}"
    export EMAIL="$email"
    
    # GitHub token (if not already provided)
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        echo
        log "INFO" "GitHub token is required for downloading Docker images"
        read -p "GitHub personal access token: " github_token
        if [[ -n "$github_token" ]]; then
            export GITHUB_TOKEN="$github_token"
        fi
    else
        log "INFO" "Using provided GitHub token"
    fi
    
    # SSL configuration
    local ssl_provider="${SSL_PROVIDER:-letsencrypt}"
    echo
    log "INFO" "SSL Certificate Provider:"
    echo "  1) Let's Encrypt (automatic)"
    echo "  2) Self-signed (for development)"
    echo "  3) Custom certificates"
    read -p "Choose SSL provider (1-3, default: 1): " ssl_choice
    
    case "${ssl_choice:-1}" in
        1) ssl_provider="letsencrypt" ;;
        2) ssl_provider="selfsigned" ;;
        3) ssl_provider="custom" ;;
        *) ssl_provider="letsencrypt" ;;
    esac
    export SSL_PROVIDER="$ssl_provider"
    
    # Set other defaults
    set_default_env_values
    
    # Use smart environment configuration for all scenarios
    smart_env_configuration "$domain" "$email" "${GITHUB_TOKEN:-}"
    
    # Validate configuration
    if validate_required_env; then
        log "SUCCESS" "Configuration setup completed successfully"
        return 0
    else
        log "ERROR" "Configuration validation failed"
        return 1
    fi
}

# Display generated passwords and credentials after setup
display_setup_credentials() {
    local env_file="${1:-.env}"
    
    if [[ ! -f "$env_file" ]]; then
        log "ERROR" "Environment file not found: $env_file"
        return 1
    fi
    
    log "SUCCESS" "🎉 Milou setup completed successfully!"
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔐 IMPORTANT: Save these credentials securely!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    # Extract and display credentials
    local domain=$(grep "^DOMAIN=" "$env_file" | cut -d'=' -f2)
    local admin_email=$(grep "^ADMIN_EMAIL=" "$env_file" | cut -d'=' -f2)
    local admin_password=$(grep "^ADMIN_PASSWORD=" "$env_file" | cut -d'=' -f2)
    local db_user=$(grep "^DB_USER=" "$env_file" | cut -d'=' -f2)
    local db_password=$(grep "^DB_PASSWORD=" "$env_file" | cut -d'=' -f2)
    local redis_password=$(grep "^REDIS_PASSWORD=" "$env_file" | cut -d'=' -f2)
    
    # Application Access
    echo "🌐 APPLICATION ACCESS:"
    echo "   Domain: $domain"
    echo "   Admin Email: $admin_email"
    echo "   Admin Password: $admin_password"
    echo
    
    # Database Access
    echo "🗄️  DATABASE ACCESS:"
    echo "   Database User: $db_user"
    echo "   Database Password: $db_password"
    echo "   Database Name: milou"
    echo
    
    # Redis Access
    echo "🔴 REDIS ACCESS:"
    echo "   Redis Password: $redis_password"
    echo
    
    # Access URLs
    local http_port=$(grep "^HTTP_PORT=" "$env_file" | cut -d'=' -f2 2>/dev/null || echo "80")
    local https_port=$(grep "^HTTPS_PORT=" "$env_file" | cut -d'=' -f2 2>/dev/null || echo "443")
    local db_external_port=$(grep "^DB_EXTERNAL_PORT=" "$env_file" | cut -d'=' -f2 2>/dev/null || echo "5432")
    
    echo "🔗 ACCESS URLS:"
    if [[ "$http_port" != "80" ]]; then
        echo "   HTTP:  http://$domain:$http_port"
    else
        echo "   HTTP:  http://$domain"
    fi
    
    if [[ "$https_port" != "443" ]]; then
        echo "   HTTPS: https://$domain:$https_port"
    else
        echo "   HTTPS: https://$domain"
    fi
    
    echo "   Database: $domain:$db_external_port"
    echo
    
    # Security Notes
    echo "⚠️  SECURITY NOTES:"
    echo "   • Change the admin password after first login"
    echo "   • These credentials are stored in: $env_file"
    echo "   • Keep this file secure and backed up"
    echo "   • Never commit this file to version control"
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    return 0
}

# Run database seeder after setup
run_database_seeder() {
    log "STEP" "🌱 Running database seeder..."
    
    # Wait for database to be ready
    local max_wait=60
    local wait_time=0
    
    log "INFO" "Waiting for database to be ready..."
    while [[ $wait_time -lt $max_wait ]]; do
        if docker_compose exec -T db pg_isready -U "$(grep "^DB_USER=" .env | cut -d'=' -f2)" >/dev/null 2>&1; then
            log "SUCCESS" "Database is ready"
            break
        fi
        
        log "INFO" "Waiting for database... (${wait_time}s/${max_wait}s)"
        sleep 5
        ((wait_time += 5))
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        log "ERROR" "Database not ready after ${max_wait} seconds"
        return 1
    fi
    
    # Run seeder through backend container
    log "INFO" "Running database migrations and seeder..."
    
    # Wait for backend to be ready
    wait_time=0
    while [[ $wait_time -lt $max_wait ]]; do
        if docker_compose exec -T backend echo "ready" >/dev/null 2>&1; then
            log "SUCCESS" "Backend container is ready"
            break
        fi
        
        log "INFO" "Waiting for backend container... (${wait_time}s/${max_wait}s)"
        sleep 5
        ((wait_time += 5))
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        log "WARN" "Backend container not ready, skipping seeder"
        return 1
    fi
    
    # Run database migrations
    if docker_compose exec -T backend npm run migrate >/dev/null 2>&1; then
        log "SUCCESS" "Database migrations completed"
    else
        log "WARN" "Database migrations failed or not available"
    fi
    
    # Run seeder
    if docker_compose exec -T backend npm run seed >/dev/null 2>&1; then
        log "SUCCESS" "Database seeder completed"
        echo
        log "INFO" "✨ Sample data has been created:"
        echo "   • Demo users and roles"
        echo "   • Sample projects and findings"
        echo "   • Default templates and configurations"
        echo
    else
        log "WARN" "Database seeder failed or not available"
        log "INFO" "You can run the seeder manually later with: ./milou.sh seed"
    fi
    
    return 0
}

# Ask user to start services after setup
prompt_start_services() {
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🚀 Ready to start Milou services!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    if [[ "${INTERACTIVE:-true}" == "false" ]]; then
        log "INFO" "Non-interactive mode: Starting services automatically..."
        return 0  # Auto-start in non-interactive mode
    fi
    
    echo "Your Milou installation is configured and ready to start."
    echo
    echo "Would you like to start the services now?"
    echo "  • This will start all Docker containers"
    echo "  • Services will be available at the URLs shown above"
    echo "  • You can also start them later with: ./milou.sh start"
    echo
    
    if ask_yes_no "Start Milou services now?" "y"; then
        return 0  # User wants to start services
    else
        echo
        log "INFO" "Services not started. You can start them later with:"
        echo "  ./milou.sh start"
        echo
        log "INFO" "To check status: ./milou.sh status"
        log "INFO" "To view logs: ./milou.sh logs"
        echo
        return 1  # User doesn't want to start services
    fi
}

# Complete setup process with credentials display and service startup
complete_setup_process() {
    local env_file="${1:-.env}"
    
    # Display credentials
    display_setup_credentials "$env_file"
    
    # Ask to start services
    if prompt_start_services; then
        echo
        log "STEP" "🚀 Starting Milou services..."
        
        # Load the smart Docker startup
        if command -v smart_docker_start >/dev/null 2>&1; then
            if smart_docker_start; then
                echo
                log "SUCCESS" "🎉 Milou is now running!"
                
                # Run seeder after services are up
                run_database_seeder
                
                # Show final status
                echo
                log "INFO" "📊 Service Status:"
                docker_status 2>/dev/null || docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" --filter "name=milou-"
                
                echo
                log "SUCCESS" "✨ Setup complete! Milou is ready to use."
                
                # Show access information again
                local domain=$(grep "^DOMAIN=" "$env_file" | cut -d'=' -f2)
                local http_port=$(grep "^HTTP_PORT=" "$env_file" | cut -d'=' -f2 2>/dev/null || echo "80")
                local https_port=$(grep "^HTTPS_PORT=" "$env_file" | cut -d'=' -f2 2>/dev/null || echo "443")
                
                echo
                echo "🌐 Access your Milou installation:"
                if [[ "$http_port" != "80" ]]; then
                    echo "   http://$domain:$http_port"
                else
                    echo "   http://$domain"
                fi
                
                if [[ "$https_port" != "443" ]]; then
                    echo "   https://$domain:$https_port"
                else
                    echo "   https://$domain"
                fi
                
                return 0
            else
                log "ERROR" "Failed to start Milou services"
                echo
                log "INFO" "You can try starting manually with: ./milou.sh start"
                return 1
            fi
        else
            log "WARN" "Smart Docker startup not available, using basic startup"
            if docker_start 2>/dev/null; then
                log "SUCCESS" "Milou services started"
                run_database_seeder
                return 0
            else
                log "ERROR" "Failed to start services"
                return 1
            fi
        fi
    else
        echo
        log "SUCCESS" "Setup completed! Start services when ready with: ./milou.sh start"
        return 0
    fi
}

# Enhanced setup completion for interactive setup
milou_setup_completion() {
    local setup_success="$1"
    
    if [[ "$setup_success" == "0" ]]; then
        # Setup was successful, complete the process
        complete_setup_process ".env"
    else
        log "ERROR" "Setup failed. Please check the errors above and try again."
        echo
        log "INFO" "Common solutions:"
        echo "  • Check your GitHub token is valid"
        echo "  • Ensure Docker is running"
        echo "  • Verify domain and email are correct"
        echo "  • Check network connectivity"
        echo
        log "INFO" "For help: ./milou.sh --help"
        return 1
    fi
}

# Clean potentially conflicting system environment variables
clean_system_env_vars() {
    log "DEBUG" "Cleaning potentially conflicting system environment variables"
    
    # List of variables that might conflict with our .env file
    local conflicting_vars=(
        "DATABASE_URI"
        "DB_HOST"
        "DB_PORT"
        "DB_USER"
        "DB_PASSWORD"
        "DB_NAME"
        "REDIS_URL"
        "REDIS_HOST"
        "REDIS_PORT"
        "REDIS_PASSWORD"
        "RABBITMQ_URL"
        "RABBITMQ_HOST"
        "RABBITMQ_PORT"
        "RABBITMQ_USER"
        "RABBITMQ_PASSWORD"
        "ADMIN_EMAIL"
        "ADMIN_PASSWORD"
        "DOMAIN"
        "GITHUB_TOKEN"
    )
    
    local cleaned_count=0
    for var in "${conflicting_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            log "WARN" "Unsetting conflicting system environment variable: $var"
            unset "$var"
            ((cleaned_count++))
        fi
    done
    
    if [[ $cleaned_count -gt 0 ]]; then
        log "INFO" "Cleaned $cleaned_count conflicting environment variables"
    else
        log "DEBUG" "No conflicting environment variables found"
    fi
}

# Sync environment files between main and static directories
sync_env_files() {
    local main_env="${1:-.env}"
    local static_env="${2:-static/.env}"
    
    log "DEBUG" "Syncing environment files: $main_env -> $static_env"
    
    if [[ ! -f "$main_env" ]]; then
        log "ERROR" "Main environment file not found: $main_env"
        return 1
    fi
    
    # Ensure static directory exists
    local static_dir
    static_dir=$(dirname "$static_env")
    if [[ ! -d "$static_dir" ]]; then
        log "DEBUG" "Creating static directory: $static_dir"
        mkdir -p "$static_dir"
    fi
    
    # Copy main env to static env
    if cp "$main_env" "$static_env"; then
        log "DEBUG" "Environment file synced: $main_env -> $static_env"
        return 0
    else
        log "ERROR" "Failed to sync environment files"
        return 1
    fi
}

# Validate environment file completeness
validate_env_completeness() {
    local env_file="$1"
    
    log "DEBUG" "Validating environment file completeness: $env_file"
    
    # Required variables for proper operation
    local required_vars=(
        "DATABASE_URI"
        "DB_EXTERNAL_PORT"
        "REDIS_EXTERNAL_PORT"
        "HTTP_PORT"
        "HTTPS_PORT"
        "DOMAIN"
        "ADMIN_EMAIL"
        "GITHUB_TOKEN"
    )
    
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" "$env_file" 2>/dev/null; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log "WARN" "Missing environment variables: ${missing_vars[*]}"
        return 1
    fi
    
    log "SUCCESS" "Environment file validation passed"
    return 0
}

# Export main functions for external use
export -f find_env_file load_env_file validate_env_file
export -f validate_required_env set_default_env_values generate_config_template generate_complete_env_file
export -f extract_existing_secrets get_existing_secret update_env_preserving_secrets
export -f smart_env_configuration detect_installation_state detect_port_configuration
export -f generate_fresh_env_config fix_partial_env_config update_complete_env_config
export -f recover_corrupted_env_config add_port_configuration validate_smart_env_config
export -f clean_system_env_vars sync_env_files validate_env_completeness
export -f load_config_file save_config show_config
export -f test_config reset_config export_config import_config milou_config_interactive_setup
export -f display_setup_credentials run_database_seeder prompt_start_services
export -f complete_setup_process milou_setup_completion 