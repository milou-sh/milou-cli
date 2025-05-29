#!/bin/bash

# =============================================================================
# Milou CLI - Configuration Management Module
# Consolidated configuration operations to eliminate code duplication
# Version: 3.1.0 - Refactored Edition
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Module guard to prevent multiple loading
if [[ "${MILOU_CONFIG_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_CONFIG_LOADED="true"

# Ensure core modules are loaded
if [[ "${MILOU_CORE_LOADED:-}" != "true" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/_core.sh" || {
        echo "ERROR: Cannot load core module" >&2
        return 1
    }
fi

if [[ "${MILOU_VALIDATION_LOADED:-}" != "true" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/_validation.sh" || {
        echo "ERROR: Cannot load validation module" >&2
        return 1
    }
fi

# =============================================================================
# CONFIGURATION CONSTANTS AND DEFAULTS
# =============================================================================

# Configuration file paths and settings
declare -g MILOU_CONFIG_FILE="${SCRIPT_DIR:-$(pwd)}/.env"
declare -g MILOU_CONFIG_TEMPLATE="${SCRIPT_DIR:-$(pwd)}/.env.example"
declare -g MILOU_CONFIG_BACKUP_DIR="${SCRIPT_DIR:-$(pwd)}/backups"

# Configuration defaults
declare -g MILOU_DEFAULT_DOMAIN="localhost"
declare -g MILOU_DEFAULT_EMAIL="admin@localhost"
declare -g MILOU_DEFAULT_USERNAME="admin"
declare -g MILOU_DEFAULT_HTTP_PORT="80"
declare -g MILOU_DEFAULT_HTTPS_PORT="443"

# Preservation state for credential management
declare -gA PRESERVED_CONFIG=()

# =============================================================================
# CONFIGURATION GENERATION FUNCTIONS
# =============================================================================

# Main configuration generation function - SINGLE AUTHORITATIVE IMPLEMENTATION
config_generate() {
    local domain="${1:-$MILOU_DEFAULT_DOMAIN}"
    local admin_email="${2:-$MILOU_DEFAULT_EMAIL}"
    local preserve_existing="${3:-auto}"  # auto, force, never
    local use_latest_images="${4:-true}"
    local ssl_mode="${5:-generate}"
    local quiet="${6:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "STEP" "🔧 Generating Milou configuration"
    [[ "$quiet" != "true" ]] && milou_log "INFO" "Domain: $domain | Email: $admin_email | SSL: $ssl_mode"
    
    # Validate inputs
    if ! config_validate_inputs "$domain" "$admin_email" "$ssl_mode" "$quiet"; then
        return 1
    fi
    
    # Handle existing configuration preservation
    local has_preserved=false
    if [[ "$preserve_existing" == "auto" || "$preserve_existing" == "force" ]]; then
        if config_preserve_existing_credentials "$quiet"; then
            has_preserved=true
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "🔒 Existing credentials preserved"
        fi
    fi
    
    # Generate new credentials if needed
    local credentials
    if [[ "$has_preserved" != "true" ]]; then
        credentials=$(config_generate_credentials "$quiet")
        [[ "$quiet" != "true" ]] && milou_log "INFO" "🆕 Generated new secure credentials"
    else
        credentials=$(config_get_preserved_credentials "$quiet")
        [[ "$quiet" != "true" ]] && milou_log "INFO" "🔒 Using preserved credentials"
    fi
    
    # Create configuration file
    if config_create_env_file "$domain" "$admin_email" "$ssl_mode" "$use_latest_images" "$credentials" "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Configuration generated successfully"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "📁 Configuration saved to: $MILOU_CONFIG_FILE"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to generate configuration"
        return 1
    fi
}

# Generate secure credentials set - SINGLE AUTHORITATIVE IMPLEMENTATION
config_generate_credentials() {
    local quiet="${1:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Generating secure credential set"
    
    # Use centralized random generation from core module
    local postgres_user="milou_user_$(generate_secure_random 8 "alphanumeric")"
    local postgres_password="$(generate_secure_random 32 "safe")"
    local postgres_db="milou_database"
    local redis_password="$(generate_secure_random 32 "safe")"
    local rabbitmq_user="milou_rabbit_$(generate_secure_random 6 "alphanumeric")"
    local rabbitmq_password="$(generate_secure_random 32 "safe")"
    local session_secret="$(generate_secure_random 64 "safe")"
    local encryption_key="$(generate_secure_random 64 "hex")"
    local jwt_secret="$(generate_secure_random 32 "safe")"
    local admin_password="$(generate_secure_random 16 "safe")"
    local api_key="$(generate_secure_random 40 "safe")"
    
    # Return credentials as associative array data
    cat << EOF
POSTGRES_USER=$postgres_user
POSTGRES_PASSWORD=$postgres_password
POSTGRES_DB=$postgres_db
REDIS_PASSWORD=$redis_password
RABBITMQ_USER=$rabbitmq_user
RABBITMQ_PASSWORD=$rabbitmq_password
SESSION_SECRET=$session_secret
ENCRYPTION_KEY=$encryption_key
JWT_SECRET=$jwt_secret
ADMIN_PASSWORD=$admin_password
API_KEY=$api_key
EOF
}

# Create environment file with all configuration - SINGLE AUTHORITATIVE IMPLEMENTATION
config_create_env_file() {
    local domain="$1"
    local admin_email="$2"
    local ssl_mode="$3"
    local use_latest_images="$4"
    local credentials="$5"
    local quiet="$6"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Creating environment configuration file"
    
    # Parse credentials
    local postgres_user postgres_password postgres_db redis_password
    local rabbitmq_user rabbitmq_password session_secret encryption_key
    local jwt_secret admin_password api_key
    
    while IFS='=' read -r key value; do
        case "$key" in
            POSTGRES_USER) postgres_user="$value" ;;
            POSTGRES_PASSWORD) postgres_password="$value" ;;
            POSTGRES_DB) postgres_db="$value" ;;
            REDIS_PASSWORD) redis_password="$value" ;;
            RABBITMQ_USER) rabbitmq_user="$value" ;;
            RABBITMQ_PASSWORD) rabbitmq_password="$value" ;;
            SESSION_SECRET) session_secret="$value" ;;
            ENCRYPTION_KEY) encryption_key="$value" ;;
            JWT_SECRET) jwt_secret="$value" ;;
            ADMIN_PASSWORD) admin_password="$value" ;;
            API_KEY) api_key="$value" ;;
        esac
    done <<< "$credentials"
    
    # Backup existing file if it exists
    if [[ -f "$MILOU_CONFIG_FILE" ]]; then
        config_backup_single "$MILOU_CONFIG_FILE" "$quiet"
    fi
    
    # Determine Docker image tags
    local image_tag="latest"
    if [[ "$use_latest_images" != "true" ]]; then
        image_tag="v1.0.0"  # Default stable version
    fi
    
    # Create comprehensive configuration file
    cat > "$MILOU_CONFIG_FILE" << EOF
# =============================================================================
# Milou CLI Configuration - Production Environment
# Generated on: $(date)
# =============================================================================

# =============================================================================
# METADATA AND VERSIONING
# =============================================================================
MILOU_VERSION=${SCRIPT_VERSION:-latest}
MILOU_GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
NODE_ENV=production

# =============================================================================
# SERVER CONFIGURATION
# =============================================================================
SERVER_NAME=$domain
CUSTOMER_DOMAIN_NAME=$domain
DOMAIN=$domain
PORT=9999
CORS_ORIGIN=https://$domain

# =============================================================================
# SSL CONFIGURATION  
# =============================================================================
SSL_MODE=$ssl_mode
SSL_PORT=$MILOU_DEFAULT_HTTPS_PORT
SSL_CERT_PATH=${SCRIPT_DIR}/ssl
SSL_KEY_PATH=${SCRIPT_DIR}/ssl
SSL_CERT_FILE=${SCRIPT_DIR}/ssl/milou.crt
SSL_KEY_FILE=${SCRIPT_DIR}/ssl/milou.key

# =============================================================================
# DATABASE CONFIGURATION (PostgreSQL)
# =============================================================================
POSTGRES_USER=$postgres_user
POSTGRES_PASSWORD=$postgres_password
POSTGRES_DB=$postgres_db
DATABASE_URI=postgresql://$postgres_user:$postgres_password@db:5432/$postgres_db
DB_HOST=db
DB_PORT=5432
DB_USER=$postgres_user
DB_PASSWORD=$postgres_password
DB_NAME=$postgres_db

# =============================================================================
# REDIS CONFIGURATION
# =============================================================================
REDIS_PASSWORD=$redis_password
REDIS_URL=redis://:$redis_password@redis:6379/0
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_SESSION_TTL=86400

# =============================================================================
# RABBITMQ CONFIGURATION
# =============================================================================
RABBITMQ_USER=$rabbitmq_user
RABBITMQ_PASSWORD=$rabbitmq_password
RABBITMQ_URL=amqp://$rabbitmq_user:$rabbitmq_password@rabbitmq:5672/
RABBITMQ_HOST=rabbitmq
RABBITMQ_PORT=5672
RABBITMQ_VHOST=/
RABBITMQ_ERLANG_COOKIE=milou-cookie

# =============================================================================
# SECURITY CONFIGURATION
# =============================================================================
JWT_SECRET=$jwt_secret
SESSION_SECRET=$session_secret
ENCRYPTION_KEY=$encryption_key
API_KEY=$api_key

# =============================================================================
# ADMIN CONFIGURATION
# =============================================================================
ADMIN_EMAIL=$admin_email
ADMIN_USERNAME=${MILOU_DEFAULT_USERNAME}
ADMIN_PASSWORD=$admin_password

# =============================================================================
# GITHUB TOKEN (Optional)
# =============================================================================
GITHUB_TOKEN=${GITHUB_TOKEN:-}

# =============================================================================
# NETWORK CONFIGURATION
# =============================================================================
HTTP_PORT=$MILOU_DEFAULT_HTTP_PORT
HTTPS_PORT=$MILOU_DEFAULT_HTTPS_PORT
FRONTEND_URL=https://$domain
BACKEND_URL=https://$domain/api

# =============================================================================
# SSO CONFIGURATION
# =============================================================================
SSO_CONFIG_ENCRYPTION_KEY=$encryption_key

# =============================================================================
# DOCKER CONFIGURATION
# =============================================================================
COMPOSE_PROJECT_NAME=milou-static
DOCKER_BUILDKIT=1

# =============================================================================
# DOCKER IMAGE CONFIGURATION
# =============================================================================
MILOU_DATABASE_TAG=$image_tag
MILOU_BACKEND_TAG=$image_tag
MILOU_FRONTEND_TAG=$image_tag
MILOU_ENGINE_TAG=$image_tag
MILOU_NGINX_TAG=$image_tag

# Third-party service versions
REDIS_VERSION=7-alpine
RABBITMQ_VERSION=3-alpine
PROMETHEUS_VERSION=latest
EOF
    
    # Set secure permissions
    chmod 600 "$MILOU_CONFIG_FILE"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Environment file created with secure permissions (600)"
    return 0
}

# =============================================================================
# CONFIGURATION VALIDATION FUNCTIONS
# =============================================================================

# Comprehensive configuration validation - SINGLE AUTHORITATIVE IMPLEMENTATION
config_validate() {
    local config_file="${1:-$MILOU_CONFIG_FILE}"
    local validation_mode="${2:-production}"  # minimal, production, all
    local quiet="${3:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🔍 Validating configuration: $validation_mode mode"
    
    if [[ ! -f "$config_file" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Configuration file not found: $config_file"
        return 1
    fi
    
    local validation_errors=0
    
    # Core validation (always required)
    validation_errors=$((validation_errors + $(config_validate_core "$config_file" "$quiet")))
    
    # Conditional validation based on mode
    case "$validation_mode" in
        "minimal")
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Running minimal validation"
            ;;
        "production")
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Running production validation"
            validation_errors=$((validation_errors + $(config_validate_security "$config_file" "$quiet")))
            validation_errors=$((validation_errors + $(config_validate_database "$config_file" "$quiet")))
            ;;
        "all"|*)
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Running comprehensive validation"
            validation_errors=$((validation_errors + $(config_validate_security "$config_file" "$quiet")))
            validation_errors=$((validation_errors + $(config_validate_database "$config_file" "$quiet")))
            validation_errors=$((validation_errors + $(config_validate_network "$config_file" "$quiet")))
            validation_errors=$((validation_errors + $(config_validate_ssl "$config_file" "$quiet")))
            ;;
    esac
    
    if [[ $validation_errors -eq 0 ]]; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Configuration validation passed"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Configuration validation failed ($validation_errors errors)"
        return 1
    fi
}

# Validate core configuration requirements
config_validate_core() {
    local config_file="$1"
    local quiet="$2"
    local errors=0
    
    # Check required variables exist
    local required_vars=("DOMAIN" "ADMIN_EMAIL" "POSTGRES_USER" "POSTGRES_PASSWORD")
    
    for var in "${required_vars[@]}"; do
        if ! grep -q "^$var=" "$config_file" 2>/dev/null; then
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "Missing required variable: $var"
            ((errors++))
        fi
    done
    
    echo $errors
}

# Validate security configuration
config_validate_security() {
    local config_file="$1"
    local quiet="$2"
    local errors=0
    
    # Check security credentials exist and are reasonable length
    local security_vars=("JWT_SECRET" "SESSION_SECRET" "ENCRYPTION_KEY" "ADMIN_PASSWORD")
    
    for var in "${security_vars[@]}"; do
        local value
        value=$(config_get_env_variable "$config_file" "$var" "")
        
        if [[ -z "$value" ]]; then
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "Missing security variable: $var"
            ((errors++))
        elif [[ ${#value} -lt 16 ]]; then
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "Security variable too short: $var (${#value} chars, min 16)"
            ((errors++))
        fi
    done
    
    echo $errors
}

# Validate database configuration
config_validate_database() {
    local config_file="$1"
    local quiet="$2"
    local errors=0
    
    # Check database variables
    local db_vars=("POSTGRES_USER" "POSTGRES_PASSWORD" "POSTGRES_DB")
    
    for var in "${db_vars[@]}"; do
        local value
        value=$(config_get_env_variable "$config_file" "$var" "")
        
        if [[ -z "$value" ]]; then
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "Missing database variable: $var"
            ((errors++))
        fi
    done
    
    echo $errors
}

# Validate network configuration
config_validate_network() {
    local config_file="$1"
    local quiet="$2"
    local errors=0
    
    # Validate domain
    local domain
    domain=$(config_get_env_variable "$config_file" "DOMAIN" "")
    if [[ -n "$domain" ]]; then
        if ! validate_domain "$domain" "true"; then
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "Invalid domain format: $domain"
            ((errors++))
        fi
    fi
    
    # Validate email
    local email
    email=$(config_get_env_variable "$config_file" "ADMIN_EMAIL" "")
    if [[ -n "$email" ]]; then
        if ! validate_email "$email" "true"; then
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "Invalid email format: $email"
            ((errors++))
        fi
    fi
    
    # Validate ports
    local http_port https_port
    http_port=$(config_get_env_variable "$config_file" "HTTP_PORT" "80")
    https_port=$(config_get_env_variable "$config_file" "HTTPS_PORT" "443")
    
    if ! validate_port "$http_port" "true"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Invalid HTTP port: $http_port"
        ((errors++))
    fi
    
    if ! validate_port "$https_port" "true"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Invalid HTTPS port: $https_port"
        ((errors++))
    fi
    
    echo $errors
}

# Validate SSL configuration
config_validate_ssl() {
    local config_file="$1"
    local quiet="$2"
    local errors=0
    
    local ssl_mode
    ssl_mode=$(config_get_env_variable "$config_file" "SSL_MODE" "generate")
    
    case "$ssl_mode" in
        "none"|"disabled")
            [[ "$quiet" != "true" ]] && milou_log "TRACE" "SSL disabled - skipping SSL validation"
            ;;
        "existing")
            local cert_path key_path
            cert_path=$(config_get_env_variable "$config_file" "SSL_CERT_FILE" "")
            key_path=$(config_get_env_variable "$config_file" "SSL_KEY_FILE" "")
            
            if [[ ! -f "$cert_path" ]]; then
                [[ "$quiet" != "true" ]] && milou_log "ERROR" "SSL certificate file not found: $cert_path"
                ((errors++))
            fi
            
            if [[ ! -f "$key_path" ]]; then
                [[ "$quiet" != "true" ]] && milou_log "ERROR" "SSL key file not found: $key_path"
                ((errors++))
            fi
            ;;
        "generate"|"letsencrypt"|*)
            [[ "$quiet" != "true" ]] && milou_log "TRACE" "SSL mode '$ssl_mode' - certificates will be generated"
            ;;
    esac
    
    echo $errors
}

# Validate configuration inputs
config_validate_inputs() {
    local domain="$1"
    local admin_email="$2"
    local ssl_mode="$3"
    local quiet="$4"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Validating configuration inputs"
    
    local errors=0
    
    # Validate domain
    if ! validate_domain "$domain" "true"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Invalid domain format: $domain"
        ((errors++))
    fi
    
    # Validate email
    if ! validate_email "$admin_email" "true"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Invalid email format: $admin_email"
        ((errors++))
    fi
    
    # Validate SSL mode
    case "$ssl_mode" in
        "generate"|"existing"|"letsencrypt"|"none"|"disabled")
            [[ "$quiet" != "true" ]] && milou_log "TRACE" "SSL mode '$ssl_mode' is valid"
            ;;
        *)
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "Invalid SSL mode: $ssl_mode"
            ((errors++))
            ;;
    esac
    
    if [[ $errors -eq 0 ]]; then
        [[ "$quiet" != "true" ]] && milou_log "TRACE" "Configuration input validation passed"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Configuration input validation failed ($errors errors)"
        return 1
    fi
}

# =============================================================================
# CONFIGURATION MANAGEMENT FUNCTIONS
# =============================================================================

# Get environment variable value - SINGLE AUTHORITATIVE IMPLEMENTATION
config_get_env_variable() {
    local config_file="$1"
    local var_name="$2"
    local default_value="${3:-}"
    
    if [[ ! -f "$config_file" ]]; then
        echo "$default_value"
        return 1
    fi
    
    local value
    value=$(grep "^${var_name}=" "$config_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    
    if [[ -n "$value" ]]; then
        echo "$value"
        return 0
    else
        echo "$default_value"
        return 1
    fi
}

# Update environment variable - SINGLE AUTHORITATIVE IMPLEMENTATION
config_update_env_variable() {
    local config_file="$1"
    local var_name="$2"
    local var_value="$3"
    local create_backup="${4:-true}"
    local quiet="${5:-false}"
    
    if [[ ! -f "$config_file" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Configuration file not found: $config_file"
        return 1
    fi
    
    # Create backup if requested
    if [[ "$create_backup" == "true" ]]; then
        config_backup_single "$config_file" "$quiet"
    fi
    
    # Check if variable exists
    if grep -q "^${var_name}=" "$config_file"; then
        # Update existing variable
        sed -i "s/^${var_name}=.*/${var_name}=${var_value}/" "$config_file"
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Updated ${var_name} in ${config_file}"
    else
        # Add new variable
        echo "${var_name}=${var_value}" >> "$config_file"
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Added ${var_name} to ${config_file}"
    fi
    
    return 0
}

# Show current configuration - SINGLE AUTHORITATIVE IMPLEMENTATION
config_show() {
    local config_file="${1:-$MILOU_CONFIG_FILE}"
    local show_secrets="${2:-false}"
    
    if [[ ! -f "$config_file" ]]; then
        milou_log "ERROR" "Configuration file not found: $config_file"
        return 1
    fi
    
    milou_log "INFO" "📋 Current Milou Configuration"
    echo "=============================================="
    echo
    
    # System Configuration
    echo "🖥️  System Configuration:"
    config_show_section "$config_file" "SERVER_NAME|DOMAIN|CORS_ORIGIN|NODE_ENV"
    echo
    
    # Database Configuration
    echo "🗄️  Database Configuration:"
    config_show_section "$config_file" "DB_HOST|DB_PORT|DB_NAME|DB_USER"
    echo
    
    # Security Configuration
    echo "🔐 Security Configuration:"
    if [[ "$show_secrets" == "true" ]]; then
        config_show_section "$config_file" "JWT_SECRET|ADMIN_PASSWORD|ADMIN_EMAIL"
    else
        echo "  JWT_SECRET: [Hidden]"
        echo "  ADMIN_PASSWORD: [Hidden]"
        config_show_section "$config_file" "ADMIN_EMAIL"
    fi
    echo
    
    # SSL Configuration
    echo "🔒 SSL Configuration:"
    config_show_section "$config_file" "SSL_MODE|SSL_PORT"
    echo
    
    # Network Configuration
    echo "🌐 Network Configuration:"
    config_show_section "$config_file" "HTTP_PORT|HTTPS_PORT|FRONTEND_URL|BACKEND_URL"
    
    echo "=============================================="
    return 0
}

# Helper function to show configuration sections
config_show_section() {
    local config_file="$1"
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
    done < "$config_file"
}

# =============================================================================
# CONFIGURATION BACKUP AND PRESERVATION
# =============================================================================

# Backup configuration file - SINGLE AUTHORITATIVE IMPLEMENTATION
config_backup_single() {
    local config_file="$1"
    local quiet="${2:-false}"
    
    if [[ ! -f "$config_file" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "WARN" "Configuration file not found for backup: $config_file"
        return 1
    fi
    
    # Ensure backup directory exists
    ensure_directory "$MILOU_CONFIG_BACKUP_DIR" "755" >/dev/null 2>&1
    
    # Create timestamped backup
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${MILOU_CONFIG_BACKUP_DIR}/$(basename "$config_file").backup.${timestamp}"
    
    if cp "$config_file" "$backup_file"; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Configuration backed up to: $(basename "$backup_file")"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to backup configuration"
        return 1
    fi
}

# Preserve existing credentials for migration - SINGLE AUTHORITATIVE IMPLEMENTATION
config_preserve_existing_credentials() {
    local quiet="${1:-false}"
    
    if [[ ! -f "$MILOU_CONFIG_FILE" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "No existing configuration to preserve"
        return 1
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Preserving existing credentials"
    
    # Clear previous preservation state
    PRESERVED_CONFIG=()
    
    # Preserve database credentials
    PRESERVED_CONFIG[POSTGRES_USER]=$(config_get_env_variable "$MILOU_CONFIG_FILE" "POSTGRES_USER" "")
    PRESERVED_CONFIG[POSTGRES_PASSWORD]=$(config_get_env_variable "$MILOU_CONFIG_FILE" "POSTGRES_PASSWORD" "")
    PRESERVED_CONFIG[POSTGRES_DB]=$(config_get_env_variable "$MILOU_CONFIG_FILE" "POSTGRES_DB" "")
    PRESERVED_CONFIG[DB_USER]=$(config_get_env_variable "$MILOU_CONFIG_FILE" "DB_USER" "")
    PRESERVED_CONFIG[DB_PASSWORD]=$(config_get_env_variable "$MILOU_CONFIG_FILE" "DB_PASSWORD" "")
    PRESERVED_CONFIG[DB_NAME]=$(config_get_env_variable "$MILOU_CONFIG_FILE" "DB_NAME" "")
    
    # Preserve security credentials
    PRESERVED_CONFIG[JWT_SECRET]=$(config_get_env_variable "$MILOU_CONFIG_FILE" "JWT_SECRET" "")
    PRESERVED_CONFIG[SESSION_SECRET]=$(config_get_env_variable "$MILOU_CONFIG_FILE" "SESSION_SECRET" "")
    PRESERVED_CONFIG[ENCRYPTION_KEY]=$(config_get_env_variable "$MILOU_CONFIG_FILE" "ENCRYPTION_KEY" "")
    PRESERVED_CONFIG[ADMIN_PASSWORD]=$(config_get_env_variable "$MILOU_CONFIG_FILE" "ADMIN_PASSWORD" "")
    PRESERVED_CONFIG[API_KEY]=$(config_get_env_variable "$MILOU_CONFIG_FILE" "API_KEY" "")
    
    # Preserve service credentials
    PRESERVED_CONFIG[REDIS_PASSWORD]=$(config_get_env_variable "$MILOU_CONFIG_FILE" "REDIS_PASSWORD" "")
    PRESERVED_CONFIG[RABBITMQ_USER]=$(config_get_env_variable "$MILOU_CONFIG_FILE" "RABBITMQ_USER" "")
    PRESERVED_CONFIG[RABBITMQ_PASSWORD]=$(config_get_env_variable "$MILOU_CONFIG_FILE" "RABBITMQ_PASSWORD" "")
    
    # Check if we found substantial credentials
    local preserved_count=0
    for key in "${!PRESERVED_CONFIG[@]}"; do
        if [[ -n "${PRESERVED_CONFIG[$key]}" ]]; then
            ((preserved_count++))
        fi
    done
    
    if [[ $preserved_count -gt 3 ]]; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "🔒 Preserved $preserved_count credential values"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Insufficient credentials found for preservation ($preserved_count items)"
        return 1
    fi
}

# Get preserved credentials as formatted output
config_get_preserved_credentials() {
    local quiet="${1:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Retrieving preserved credentials"
    
    # Generate credentials using preserved values with fallbacks
    local postgres_user="${PRESERVED_CONFIG[POSTGRES_USER]:-milou_user_$(generate_secure_random 8 "alphanumeric")}"
    local postgres_password="${PRESERVED_CONFIG[POSTGRES_PASSWORD]:-$(generate_secure_random 32 "safe")}"
    local postgres_db="${PRESERVED_CONFIG[POSTGRES_DB]:-milou_database}"
    local redis_password="${PRESERVED_CONFIG[REDIS_PASSWORD]:-$(generate_secure_random 32 "safe")}"
    local rabbitmq_user="${PRESERVED_CONFIG[RABBITMQ_USER]:-milou_rabbit_$(generate_secure_random 6 "alphanumeric")}"
    local rabbitmq_password="${PRESERVED_CONFIG[RABBITMQ_PASSWORD]:-$(generate_secure_random 32 "safe")}"
    local session_secret="${PRESERVED_CONFIG[SESSION_SECRET]:-$(generate_secure_random 64 "safe")}"
    local encryption_key="${PRESERVED_CONFIG[ENCRYPTION_KEY]:-$(generate_secure_random 64 "hex")}"
    local jwt_secret="${PRESERVED_CONFIG[JWT_SECRET]:-$(generate_secure_random 32 "safe")}"
    local admin_password="${PRESERVED_CONFIG[ADMIN_PASSWORD]:-$(generate_secure_random 16 "safe")}"
    local api_key="${PRESERVED_CONFIG[API_KEY]:-$(generate_secure_random 40 "safe")}"
    
    # Return formatted credentials
    cat << EOF
POSTGRES_USER=$postgres_user
POSTGRES_PASSWORD=$postgres_password
POSTGRES_DB=$postgres_db
REDIS_PASSWORD=$redis_password
RABBITMQ_USER=$rabbitmq_user
RABBITMQ_PASSWORD=$rabbitmq_password
SESSION_SECRET=$session_secret
ENCRYPTION_KEY=$encryption_key
JWT_SECRET=$jwt_secret
ADMIN_PASSWORD=$admin_password
API_KEY=$api_key
EOF
}

# =============================================================================
# CONFIGURATION MIGRATION FUNCTIONS
# =============================================================================

# Migrate configuration from older versions - SINGLE AUTHORITATIVE IMPLEMENTATION
config_migrate() {
    local source_config="${1:-$MILOU_CONFIG_FILE}"
    local target_version="${2:-latest}"
    local preserve_data="${3:-true}"
    local quiet="${4:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "STEP" "🔄 Migrating configuration to version: $target_version"
    
    if [[ ! -f "$source_config" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Source configuration not found: $source_config"
        return 1
    fi
    
    # Backup original before migration
    config_backup_single "$source_config" "$quiet"
    
    # Preserve existing credentials if requested
    local preserved_credentials=""
    if [[ "$preserve_data" == "true" ]]; then
        if config_preserve_existing_credentials "$quiet"; then
            preserved_credentials=$(config_get_preserved_credentials "$quiet")
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "🔒 Existing credentials preserved for migration"
        fi
    fi
    
    # Extract key configuration values
    local domain admin_email ssl_mode
    domain=$(config_get_env_variable "$source_config" "DOMAIN" "$MILOU_DEFAULT_DOMAIN")
    admin_email=$(config_get_env_variable "$source_config" "ADMIN_EMAIL" "$MILOU_DEFAULT_EMAIL")
    ssl_mode=$(config_get_env_variable "$source_config" "SSL_MODE" "generate")
    
    # Determine image versioning
    local use_latest_images="true"
    if [[ "$target_version" != "latest" ]]; then
        use_latest_images="false"
    fi
    
    # Generate new configuration with preserved credentials
    local credentials_to_use="$preserved_credentials"
    if [[ -z "$credentials_to_use" ]]; then
        credentials_to_use=$(config_generate_credentials "$quiet")
        [[ "$quiet" != "true" ]] && milou_log "INFO" "🆕 Generated new credentials for migration"
    fi
    
    # Create migrated configuration
    if config_create_env_file "$domain" "$admin_email" "$ssl_mode" "$use_latest_images" "$credentials_to_use" "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Configuration migration completed"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Configuration migration failed"
        return 1
    fi
}

# =============================================================================
# LEGACY ALIASES FOR BACKWARDS COMPATIBILITY
# =============================================================================

# Legacy aliases (will be removed after full refactoring)
milou_config_show() { config_show "$@"; }
milou_config_update_env_variable() { config_update_env_variable "$@"; }
milou_config_get_env_variable() { config_get_env_variable "$@"; }
milou_config_initialize() { config_generate "$@"; }
milou_config_backup_single() { config_backup_single "$@"; }
milou_config_validate() { config_validate "$@"; }
milou_config_migrate() { config_migrate "$@"; }

# Legacy migration functions
generate_config_with_preservation() { config_generate "$@"; }
preserve_database_credentials() { config_preserve_existing_credentials "$@"; }
validate_config_inputs() { config_validate_inputs "$@"; }

# =============================================================================
# EXPORT ALL FUNCTIONS
# =============================================================================

# Core configuration operations (new clean API)
export -f config_generate
export -f config_validate
export -f config_backup_single
export -f config_migrate
export -f config_show

# Configuration management operations
export -f config_get_env_variable
export -f config_update_env_variable
export -f config_preserve_existing_credentials
export -f config_generate_credentials
export -f config_create_env_file

# Configuration validation operations
export -f config_validate_inputs
export -f config_validate_core
export -f config_validate_security
export -f config_validate_database
export -f config_validate_network
export -f config_validate_ssl

# Configuration utility functions
export -f config_show_section
export -f config_get_preserved_credentials

# Legacy aliases (for backwards compatibility during transition)
export -f milou_config_show
export -f milou_config_update_env_variable
export -f milou_config_get_env_variable
export -f milou_config_initialize
export -f milou_config_backup_single
export -f milou_config_validate
export -f milou_config_migrate
export -f generate_config_with_preservation
export -f preserve_database_credentials
export -f validate_config_inputs

milou_log "DEBUG" "Configuration module loaded successfully" 