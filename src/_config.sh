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
    local domain="$1"
    local admin_email="$2"
    local ssl_mode="${3:-generate}"
    local use_latest_images="${4:-true}"
    local preserve_credentials="${5:-auto}"
    local quiet="${6:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Generating configuration with credential preservation"
    
    # Detect installation type
    local installation_type
    installation_type=$(config_detect_installation_type "$quiet")
    
    # Handle credential preservation logic
    local should_preserve="false"
    
    if [[ "$preserve_credentials" == "auto" ]]; then
        # Auto-detect: preserve for updates, generate new for fresh installs
        if [[ "$installation_type" == "update" ]]; then
            should_preserve="true"
        else
            should_preserve="false"
        fi
    elif [[ "$preserve_credentials" == "true" ]]; then
        should_preserve="true"
    elif [[ "$preserve_credentials" == "false" ]]; then
        should_preserve="false"
        # Warn user if this is an update with existing data
        if [[ "$installation_type" == "update" ]]; then
            if ! config_warn_credential_impact "$installation_type" "true"; then
                return 1
            fi
        fi
    fi
    
    # Show credential preservation status
    config_warn_credential_impact "$installation_type" "$([[ "$should_preserve" == "false" ]] && echo "true" || echo "false")"
    
    # Preserve existing credentials if needed
    if [[ "$should_preserve" == "true" ]]; then
        config_preserve_existing_credentials "${SCRIPT_DIR:-$(pwd)}/.env" "$quiet"
    fi
    
    # Generate credentials (using preserved ones where available)
    local credentials
    if [[ "$should_preserve" == "true" && "${CREDENTIALS_PRESERVED:-false}" == "true" ]]; then
        credentials=$(config_generate_credentials_with_preservation "$quiet")
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Generated configuration preserving existing credentials"
    else
        credentials=$(config_generate_credentials "$quiet")
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Generated configuration with new credentials"
    fi
    
    # Create environment file
    if config_create_env_file "$domain" "$admin_email" "$ssl_mode" "$use_latest_images" "$credentials" "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Configuration file created successfully"
        
        # Show credential preservation summary
        if [[ "$should_preserve" == "true" ]]; then
            echo ""
            echo "🔐 CREDENTIAL PRESERVATION SUMMARY"
            echo "================================="
            echo "✅ Existing credentials preserved - your data remains accessible"
            echo "✅ Services will start with existing database connections"
            echo "✅ Users can continue to log in with existing accounts"
            echo "✅ API integrations will continue to work"
            echo ""
        fi
        
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Configuration file creation failed"
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
RABBITMQ_DEFAULT_USER=$rabbitmq_user
RABBITMQ_DEFAULT_PASS=$rabbitmq_password
SESSION_SECRET=$session_secret
ENCRYPTION_KEY=$encryption_key
JWT_SECRET=$jwt_secret
ADMIN_PASSWORD=$admin_password
API_KEY=$api_key
EOF
}

# Find available port automatically
config_find_available_port() {
    local start_port="${1:-5433}"
    local max_attempts="${2:-50}"
    
    local port=$start_port
    local attempts=0
    
    while [[ $attempts -lt $max_attempts ]]; do
        # Check if port is available
        if ! ss -tlnp | grep -q ":$port "; then
            echo "$port"
            return 0
        fi
        ((port++))
        ((attempts++))
    done
    
    # Fallback to original port if no available port found
    echo "$start_port"
    return 1
}

# Detect and resolve port conflicts automatically
config_resolve_port_conflicts() {
    local quiet="${1:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Detecting and resolving port conflicts"
    
    # Check common ports and find alternatives
    local http_port=80
    local https_port=443
    local db_external_port=5432
    local redis_external_port=6379
    local rabbitmq_external_port=5672
    local prometheus_port=9090
    
    # Check and resolve HTTP port conflict
    if ss -tlnp | grep -q ":$http_port "; then
        [[ "$quiet" != "true" ]] && milou_log "WARN" "Port $http_port (HTTP) is in use, using default (will handle via Docker networking)"
    fi
    
    # Check and resolve HTTPS port conflict  
    if ss -tlnp | grep -q ":$https_port "; then
        [[ "$quiet" != "true" ]] && milou_log "WARN" "Port $https_port (HTTPS) is in use, using default (will handle via Docker networking)"
    fi
    
    # Check and resolve database port conflict
    if ss -tlnp | grep -q ":$db_external_port "; then
        db_external_port=$(config_find_available_port 5433)
        [[ "$quiet" != "true" ]] && milou_log "INFO" "Port 5432 (PostgreSQL) is in use, using port $db_external_port instead"
    fi
    
    # Check and resolve Redis port conflict
    if ss -tlnp | grep -q ":$redis_external_port "; then
        redis_external_port=$(config_find_available_port 6380)
        [[ "$quiet" != "true" ]] && milou_log "INFO" "Port 6379 (Redis) is in use, using port $redis_external_port instead"
    fi
    
    # Check and resolve RabbitMQ port conflict
    if ss -tlnp | grep -q ":$rabbitmq_external_port "; then
        rabbitmq_external_port=$(config_find_available_port 5673)
        [[ "$quiet" != "true" ]] && milou_log "INFO" "Port 5672 (RabbitMQ) is in use, using port $rabbitmq_external_port instead"
    fi
    
    # Check and resolve Prometheus port conflict
    if ss -tlnp | grep -q ":$prometheus_port "; then
        prometheus_port=$(config_find_available_port 9091)
        [[ "$quiet" != "true" ]] && milou_log "INFO" "Port 9090 (Prometheus) is in use, using port $prometheus_port instead"
    fi
    
    # Return port configuration
    cat << EOF
HTTP_PORT=$http_port
HTTPS_PORT=$https_port
DB_EXTERNAL_PORT=$db_external_port
REDIS_EXTERNAL_PORT=$redis_external_port
RABBITMQ_EXTERNAL_PORT=$rabbitmq_external_port
PROMETHEUS_PORT=$prometheus_port
EOF
}

# Create environment file with all configuration - SINGLE AUTHORITATIVE IMPLEMENTATION
config_create_env_file() {
    local domain="$1"
    local admin_email="$2"
    local ssl_mode="$3"
    local use_latest_images="${4:-true}"
    local credentials="$5"
    local quiet="${6:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Creating environment file with domain: $domain"
    
    # Parse credentials safely
    local postgres_user postgres_password postgres_db redis_password
    local rabbitmq_user rabbitmq_password session_secret encryption_key jwt_secret admin_password api_key
    
    # Extract credential values from the credentials string
    while IFS= read -r line; do
        if [[ "$line" =~ ^POSTGRES_USER= ]]; then
            postgres_user="${line#POSTGRES_USER=}"
        elif [[ "$line" =~ ^POSTGRES_PASSWORD= ]]; then
            postgres_password="${line#POSTGRES_PASSWORD=}"
        elif [[ "$line" =~ ^POSTGRES_DB= ]]; then
            postgres_db="${line#POSTGRES_DB=}"
        elif [[ "$line" =~ ^REDIS_PASSWORD= ]]; then
            redis_password="${line#REDIS_PASSWORD=}"
        elif [[ "$line" =~ ^RABBITMQ_DEFAULT_USER= ]]; then
            rabbitmq_user="${line#RABBITMQ_DEFAULT_USER=}"
        elif [[ "$line" =~ ^RABBITMQ_DEFAULT_PASS= ]]; then
            rabbitmq_password="${line#RABBITMQ_DEFAULT_PASS=}"
        elif [[ "$line" =~ ^SESSION_SECRET= ]]; then
            session_secret="${line#SESSION_SECRET=}"
        elif [[ "$line" =~ ^ENCRYPTION_KEY= ]]; then
            encryption_key="${line#ENCRYPTION_KEY=}"
        elif [[ "$line" =~ ^JWT_SECRET= ]]; then
            jwt_secret="${line#JWT_SECRET=}"
        elif [[ "$line" =~ ^ADMIN_PASSWORD= ]]; then
            admin_password="${line#ADMIN_PASSWORD=}"
        elif [[ "$line" =~ ^API_KEY= ]]; then
            api_key="${line#API_KEY=}"
        fi
    done <<< "$credentials"
    
    # Resolve port conflicts
    local port_config
    port_config=$(config_resolve_port_conflicts "$quiet")
    
    # Parse port configuration
    local http_port https_port db_external_port redis_external_port rabbitmq_external_port prometheus_port
    while IFS='=' read -r key value; do
        case "$key" in
            HTTP_PORT) http_port="$value" ;;
            HTTPS_PORT) https_port="$value" ;;
            DB_EXTERNAL_PORT) db_external_port="$value" ;;
            REDIS_EXTERNAL_PORT) redis_external_port="$value" ;;
            RABBITMQ_EXTERNAL_PORT) rabbitmq_external_port="$value" ;;
            PROMETHEUS_PORT) prometheus_port="$value" ;;
        esac
    done <<< "$port_config"
    
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
SSL_PORT=$https_port
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
DB_HOST=milou-database
DB_PORT=5432
DB_USER=$postgres_user
DB_PASSWORD=$postgres_password
DB_NAME=$postgres_db
DB_CONNECTION_TIMEOUT=30
DATABASE_URL=postgresql://$postgres_user:$postgres_password@milou-database:5432/$postgres_db
DATABASE_URI=postgresql://$postgres_user:$postgres_password@milou-database:5432/$postgres_db

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
RABBITMQ_DEFAULT_USER=$rabbitmq_user
RABBITMQ_DEFAULT_PASS=$rabbitmq_password
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
SSO_CONFIG_ENCRYPTION_KEY=$encryption_key
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
GITHUB_TOKEN=

# =============================================================================
# NETWORK CONFIGURATION
# =============================================================================
HTTP_PORT=$http_port
HTTPS_PORT=$https_port
FRONTEND_URL=https://$domain
BACKEND_URL=https://$domain/api

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

# =============================================================================
# DATABASE EXTERNAL ACCESS (Comment out if not needed)
# =============================================================================
DB_EXTERNAL_PORT=$db_external_port

# =============================================================================
# EXTERNAL SERVICE PORTS (For development and monitoring)
# =============================================================================
REDIS_EXTERNAL_PORT=$redis_external_port
RABBITMQ_EXTERNAL_PORT=$rabbitmq_external_port
PROMETHEUS_PORT=$prometheus_port
EOF
    
    # Set secure permissions
    chmod 600 "$MILOU_CONFIG_FILE"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Environment file created with secure permissions (600)"
    [[ "$quiet" != "true" ]] && milou_log "INFO" "✅ Port conflicts automatically resolved:"
    [[ "$quiet" != "true" ]] && milou_log "INFO" "   🐘 Database: External port $db_external_port"
    [[ "$quiet" != "true" ]] && milou_log "INFO" "   📦 Redis: External port $redis_external_port" 
    [[ "$quiet" != "true" ]] && milou_log "INFO" "   🐰 RabbitMQ: External port $rabbitmq_external_port"
    [[ "$quiet" != "true" ]] && milou_log "INFO" "   🌐 HTTP: Port $http_port, HTTPS: Port $https_port"
    
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

# Detect if this is an update vs fresh install
config_detect_installation_type() {
    local quiet="${1:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Detecting installation type"
    
    local has_env_file=false
    local has_containers=false
    local has_volumes=false
    local has_ssl_certs=false
    
    # Check for existing .env file
    if [[ -f "${SCRIPT_DIR:-$(pwd)}/.env" ]]; then
        has_env_file=true
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Found existing .env file"
    fi
    
    # Check for existing containers
    if docker ps -a --filter "name=milou-" --format "{{.Names}}" 2>/dev/null | grep -q milou; then
        has_containers=true
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Found existing containers"
    fi
    
    # Check for existing volumes with data
    if docker volume ls --format "{{.Name}}" 2>/dev/null | grep -E "(milou|static)" | head -1 | xargs -I {} docker volume inspect {} 2>/dev/null | grep -q "CreatedAt"; then
        has_volumes=true
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Found existing data volumes"
    fi
    
    # Check for SSL certificates
    if [[ -d "${SCRIPT_DIR:-$(pwd)}/ssl" ]] && [[ -n "$(ls -A "${SCRIPT_DIR:-$(pwd)}/ssl" 2>/dev/null)" ]]; then
        has_ssl_certs=true
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Found existing SSL certificates"
    fi
    
    # Determine installation type
    if [[ "$has_env_file" == "true" || "$has_containers" == "true" || "$has_volumes" == "true" ]]; then
        echo "update"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "🔄 Detected: EXISTING INSTALLATION (Update Mode)"
    else
        echo "fresh"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "✨ Detected: FRESH INSTALLATION (New Setup)"
    fi
}

# Preserve existing credentials from .env file
config_preserve_existing_credentials() {
    local env_file="${1:-${SCRIPT_DIR:-$(pwd)}/.env}"
    local quiet="${2:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Preserving existing credentials from $env_file"
    
    if [[ ! -f "$env_file" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "No existing .env file to preserve credentials from"
        return 1
    fi
    
    # Extract all credential-related variables
    declare -A preserved_creds
    
    # Database credentials
    preserved_creds[POSTGRES_USER]=$(grep "^POSTGRES_USER=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    preserved_creds[POSTGRES_PASSWORD]=$(grep "^POSTGRES_PASSWORD=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    preserved_creds[POSTGRES_DB]=$(grep "^POSTGRES_DB=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    preserved_creds[DB_USER]=$(grep "^DB_USER=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    preserved_creds[DB_PASSWORD]=$(grep "^DB_PASSWORD=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    preserved_creds[DB_NAME]=$(grep "^DB_NAME=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    
    # Application secrets
    preserved_creds[SESSION_SECRET]=$(grep "^SESSION_SECRET=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    preserved_creds[JWT_SECRET]=$(grep "^JWT_SECRET=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    preserved_creds[ENCRYPTION_KEY]=$(grep "^ENCRYPTION_KEY=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    
    # RabbitMQ credentials
    preserved_creds[RABBITMQ_DEFAULT_USER]=$(grep "^RABBITMQ_DEFAULT_USER=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    preserved_creds[RABBITMQ_DEFAULT_PASS]=$(grep "^RABBITMQ_DEFAULT_PASS=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    
    # Redis credentials
    preserved_creds[REDIS_PASSWORD]=$(grep "^REDIS_PASSWORD=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    
    # Admin credentials
    preserved_creds[ADMIN_USERNAME]=$(grep "^ADMIN_USERNAME=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    preserved_creds[ADMIN_PASSWORD]=$(grep "^ADMIN_PASSWORD=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    preserved_creds[ADMIN_EMAIL]=$(grep "^ADMIN_EMAIL=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    
    # API keys
    preserved_creds[API_KEY]=$(grep "^API_KEY=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    
    # Count preserved credentials
    local preserved_count=0
    for key in "${!preserved_creds[@]}"; do
        if [[ -n "${preserved_creds[$key]}" ]]; then
            ((preserved_count++))
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Preserved $key"
            
            # Export for use in other functions
            export "PRESERVED_${key}=${preserved_creds[$key]}"
        fi
    done
    
    if [[ $preserved_count -gt 0 ]]; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Preserved $preserved_count existing credentials"
        export CREDENTIALS_PRESERVED="true"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "WARN" "No credentials found to preserve"
        export CREDENTIALS_PRESERVED="false"
        return 1
    fi
}

# Warn user about credential impact on data
config_warn_credential_impact() {
    local installation_type="$1"
    local force_new_creds="${2:-false}"
    
    if [[ "$installation_type" == "update" && "$force_new_creds" == "true" ]]; then
        echo ""
        echo "⚠️  🚨 CRITICAL WARNING: CREDENTIAL CHANGE WILL AFFECT EXISTING DATA! 🚨"
        echo "=================================================================="
        echo ""
        echo "You are about to CHANGE CREDENTIALS on an EXISTING installation!"
        echo ""
        echo "📊 IMPACT ON YOUR DATA:"
        echo "  🗄️  Database: Existing data may become INACCESSIBLE"
        echo "  🔐 Encrypted data: May become permanently UNREADABLE"
        echo "  👥 Users: Will need to re-authenticate with new credentials" 
        echo "  🔑 API integrations: Will break and need credential updates"
        echo ""
        echo "💾 RECOMMENDED ACTIONS:"
        echo "  1. CREATE A FULL BACKUP before proceeding"
        echo "  2. Export important data if possible"
        echo "  3. Coordinate with users about the credential change"
        echo "  4. Update all API integrations with new credentials"
        echo ""
        echo "🎯 ALTERNATIVE: Use './milou.sh setup --preserve-creds' to keep existing credentials"
        echo ""
        
        if ! milou_confirm "Do you understand the risks and want to proceed with NEW credentials?" "N"; then
            echo ""
            echo "✅ Smart choice! Run one of these instead:"
            echo "   • './milou.sh setup --preserve-creds' (recommended for updates)"
            echo "   • './milou.sh backup' (to backup before changing credentials)"
            echo ""
            return 1
        fi
        
        echo ""
        echo "⚠️  Proceeding with credential changes - your data may be affected!"
        echo ""
        
    elif [[ "$installation_type" == "update" ]]; then
        echo ""
        echo "🔄 UPDATE MODE DETECTED"
        echo "======================"
        echo ""
        echo "✅ PRESERVING EXISTING CREDENTIALS"
        echo "  🗄️  Database credentials: PRESERVED (data will remain accessible)"
        echo "  🔐 Application secrets: PRESERVED (encrypted data remains readable)"
        echo "  👥 User credentials: PRESERVED (users can continue to log in)"
        echo "  🔑 API keys: PRESERVED (integrations will continue to work)"
        echo ""
        echo "💡 This is the SAFE option for updates - your data will be protected!"
        echo ""
    fi
}

# Check if credentials exist in preserved variables or current env
config_has_preserved_credentials() {
    local key="$1"
    
    # Check preserved variables first
    local preserved_var="PRESERVED_${key}"
    if [[ -n "${!preserved_var:-}" ]]; then
        return 0
    fi
    
    # Check current environment
    if [[ -n "${!key:-}" ]]; then
        return 0
    fi
    
    return 1
}

# Get credential value (preserved or current)
config_get_credential() {
    local key="$1"
    local default_value="${2:-}"
    
    # Check preserved variables first  
    local preserved_var="PRESERVED_${key}"
    if [[ -n "${!preserved_var:-}" ]]; then
        echo "${!preserved_var}"
        return 0
    fi
    
    # Check current environment
    if [[ -n "${!key:-}" ]]; then
        echo "${!key}"
        return 0
    fi
    
    # Return default
    echo "$default_value"
}

# Generate credentials using preserved values where available
config_generate_credentials_with_preservation() {
    local quiet="${1:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Generating credentials with preservation of existing values"
    
    # Use preserved credentials or generate new ones
    local postgres_user
    postgres_user=$(config_get_credential "POSTGRES_USER" "milou_user_$(generate_secure_random 8 "alphanumeric")")
    
    local postgres_password  
    postgres_password=$(config_get_credential "POSTGRES_PASSWORD" "$(generate_secure_random 32 "safe")")
    
    local postgres_db
    postgres_db=$(config_get_credential "POSTGRES_DB" "milou_database")
    
    local redis_password
    redis_password=$(config_get_credential "REDIS_PASSWORD" "$(generate_secure_random 32 "safe")")
    
    local rabbitmq_user
    rabbitmq_user=$(config_get_credential "RABBITMQ_DEFAULT_USER" "milou_rabbit_$(generate_secure_random 6 "alphanumeric")")
    
    local rabbitmq_password
    rabbitmq_password=$(config_get_credential "RABBITMQ_DEFAULT_PASS" "$(generate_secure_random 32 "safe")")
    
    local session_secret
    session_secret=$(config_get_credential "SESSION_SECRET" "$(generate_secure_random 64 "safe")")
    
    local encryption_key
    encryption_key=$(config_get_credential "ENCRYPTION_KEY" "$(generate_secure_random 64 "safe")")
    
    local jwt_secret
    jwt_secret=$(config_get_credential "JWT_SECRET" "$(generate_secure_random 32 "safe")")
    
    local admin_password
    admin_password=$(config_get_credential "ADMIN_PASSWORD" "$(generate_secure_random 16 "safe")")
    
    local api_key
    api_key=$(config_get_credential "API_KEY" "$(generate_secure_random 32 "safe")")
    
    # Output credentials in expected format
    cat << EOF
POSTGRES_USER=$postgres_user
POSTGRES_PASSWORD=$postgres_password
POSTGRES_DB=$postgres_db
REDIS_PASSWORD=$redis_password
RABBITMQ_DEFAULT_USER=$rabbitmq_user
RABBITMQ_DEFAULT_PASS=$rabbitmq_password
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
export -f config_find_available_port
export -f config_resolve_port_conflicts

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

# Installation type and credential management
export -f config_detect_installation_type
export -f config_warn_credential_impact
export -f config_has_preserved_credentials
export -f config_get_credential

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