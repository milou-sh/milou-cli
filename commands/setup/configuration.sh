#!/bin/bash

# =============================================================================
# Setup Module: Configuration Wizard
# Extracted from monolithic handle_setup() function
# =============================================================================

# Ensure logging and utilities are available
if ! command -v milou_log >/dev/null 2>&1; then
    if [[ -n "${SCRIPT_DIR:-}" ]] && [[ -f "${SCRIPT_DIR}/lib/core/logging.sh" ]]; then
        source "${SCRIPT_DIR}/lib/core/logging.sh" 2>/dev/null || {
            echo "ERROR: Cannot load logging module" >&2
            exit 1
        }
    else
        echo "ERROR: milou_log function not available" >&2
        exit 1
    fi
fi

# Ensure utilities are available (for secure random generation)
if ! command -v milou_generate_secure_random >/dev/null 2>&1; then
    if [[ -n "${SCRIPT_DIR:-}" ]] && [[ -f "${SCRIPT_DIR}/lib/core/utilities.sh" ]]; then
        source "${SCRIPT_DIR}/lib/core/utilities.sh" 2>/dev/null || {
            milou_log "ERROR" "Cannot load utilities module"
            exit 1
        }
    else
        milou_log "ERROR" "milou_generate_secure_random function not available"
        exit 1
    fi
fi

# =============================================================================
# Configuration Wizard Functions
# =============================================================================

# Main configuration wizard coordinator
setup_run_configuration_wizard() {
    local setup_mode="${1:-interactive}"
    
    milou_log "STEP" "Step 6: Configuration Wizard"
    echo
    
    case "$setup_mode" in
        interactive)
            _run_interactive_configuration_wizard
            ;;
        non-interactive)
            _run_non_interactive_configuration
            ;;
        auto)
            _run_automatic_configuration
            ;;
        *)
            milou_log "ERROR" "Unknown setup mode: $setup_mode"
            return 1
            ;;
    esac
}

# Interactive configuration wizard
_run_interactive_configuration_wizard() {
    milou_log "INFO" "🧙 Starting interactive configuration wizard"
    echo
    
    # Check if configuration already exists
    if [[ -f "${ENV_FILE:-}" ]]; then
        milou_log "INFO" "Found existing configuration: ${ENV_FILE}"
        
        if [[ "${FORCE:-false}" != "true" ]]; then
            if ! milou_confirm "Configuration file exists. Overwrite with new configuration?" "N"; then
                milou_log "INFO" "Using existing configuration"
                return 0
            fi
        fi
        
        # Backup existing configuration
        local backup_file="${ENV_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "${ENV_FILE}" "$backup_file"
        milou_log "INFO" "✅ Backed up existing configuration to: $backup_file"
    fi
    
    # Step-by-step configuration collection
    _collect_basic_configuration || return 1
    _collect_domain_configuration || return 1
    _collect_ssl_configuration || return 1
    _collect_admin_configuration || return 1
    _collect_security_configuration || return 1
    
    # Validate and save configuration
    _validate_collected_configuration || return 1
    _save_configuration_to_env || return 1
    
    echo
    milou_log "SUCCESS" "✅ Interactive configuration completed"
    return 0
}

# Non-interactive configuration (use environment variables)
_run_non_interactive_configuration() {
    milou_log "INFO" "🤖 Running non-interactive configuration"
    echo
    
    # Check required environment variables
    local required_vars=(
        "DOMAIN"
        "ADMIN_EMAIL"
        "GITHUB_TOKEN"
    )
    
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        milou_log "ERROR" "Non-interactive mode requires environment variables:"
        printf '  • %s\n' "${missing_vars[@]}"
        milou_log "INFO" "💡 Set variables or use interactive mode: $0 setup"
        return 1
    fi
    
    # Use environment variables to create configuration
    _create_env_from_environment || return 1
    
    milou_log "SUCCESS" "✅ Non-interactive configuration completed"
    return 0
}

# Automatic configuration with smart defaults
_run_automatic_configuration() {
    milou_log "INFO" "⚡ Running automatic configuration with smart defaults"
    echo
    
    # Generate secure defaults
    _generate_automatic_configuration || return 1
    
    milou_log "SUCCESS" "✅ Automatic configuration completed"
    return 0
}

# Collect basic configuration
_collect_basic_configuration() {
    milou_log "INFO" "📋 Basic Configuration"
    
    # Domain configuration
    if [[ -z "${DOMAIN:-}" ]]; then
        milou_prompt_user "Enter domain name" "${DOMAIN:-localhost}" "domain" "false" 3
        DOMAIN="$REPLY"
    fi
    
    # Admin email configuration
    if [[ -z "${ADMIN_EMAIL:-}" ]]; then
        milou_prompt_user "Enter admin email" "${ADMIN_EMAIL:-admin@localhost}" "email" "false" 3
        ADMIN_EMAIL="$REPLY"
    fi
    
    milou_log "DEBUG" "Basic config collected: domain=$DOMAIN, email=$ADMIN_EMAIL"
    return 0
}

# Collect domain and networking configuration
_collect_domain_configuration() {
    milou_log "INFO" "🌐 Domain and Networking Configuration"
    
    # Validate domain
    if ! milou_validate_domain "$DOMAIN" "true"; then
        milou_log "ERROR" "Invalid domain: $DOMAIN"
        return 1
    fi
    
    # Port configuration
    if [[ -z "${HTTP_PORT:-}" ]]; then
        milou_prompt_user "HTTP port" "80" "port" "false" 3
        HTTP_PORT="$REPLY"
    fi
    
    if [[ -z "${HTTPS_PORT:-}" ]]; then
        milou_prompt_user "HTTPS port" "443" "port" "false" 3
        HTTPS_PORT="$REPLY"
    fi
    
    # Check port availability
    if ! milou_check_port_availability "$HTTP_PORT" "localhost" "true"; then
        milou_log "WARN" "⚠️  Port $HTTP_PORT is already in use"
        if milou_confirm "Continue anyway? (May cause conflicts)" "Y"; then
            milou_log "INFO" "Proceeding with potentially conflicting port"
        else
            return 1
        fi
    fi
    
    milou_log "DEBUG" "Domain config collected: domain=$DOMAIN, http=$HTTP_PORT, https=$HTTPS_PORT"
    return 0
}

# Collect SSL configuration
_collect_ssl_configuration() {
    milou_log "INFO" "🔒 SSL Configuration"
    
    # Show domain that will be used for certificates
    milou_log "INFO" "🌐 Domain for SSL: ${DOMAIN}"
    echo
    
    # SSL mode selection
    echo "SSL Configuration Options:"
    echo "  1. Generate self-signed certificates for '${DOMAIN}' (development/testing)"
    echo "  2. Use existing certificates (production)"
    echo "  3. Skip SSL setup (HTTP only - not recommended)"
    echo
    
    milou_prompt_user "Select SSL option [1-3]" "1" "choice" "false" 3
    local ssl_choice="$REPLY"
    
    case "$ssl_choice" in
        1)
            SSL_MODE="generate"
            milou_log "INFO" "✅ Will generate self-signed certificates for domain: ${DOMAIN}"
            milou_log "INFO" "💡 Certificate will be valid for: ${DOMAIN}, localhost, 127.0.0.1"
            ;;
        2)
            SSL_MODE="existing"
            milou_log "INFO" "📁 Using existing SSL certificates"
            milou_prompt_user "Path to certificate file (.crt)" "" "path" "false" 3
            SSL_CERT_PATH="$REPLY"
            milou_prompt_user "Path to private key file (.key)" "" "path" "false" 3
            SSL_KEY_PATH="$REPLY"
            
            # Validate paths
            if [[ ! -f "$SSL_CERT_PATH" ]]; then
                milou_log "ERROR" "Certificate file not found: $SSL_CERT_PATH"
                return 1
            fi
            if [[ ! -f "$SSL_KEY_PATH" ]]; then
                milou_log "ERROR" "Private key file not found: $SSL_KEY_PATH"
                return 1
            fi
            ;;
        3)
            SSL_MODE="none"
            milou_log "WARN" "⚠️  SSL disabled - HTTP only mode (not recommended for production)"
            if [[ "${DOMAIN}" != "localhost" ]]; then
                milou_log "WARN" "⚠️  WARNING: Using HTTP-only for domain '${DOMAIN}' - data will be unencrypted!"
                if ! milou_confirm "Continue with HTTP-only mode?" "N"; then
                    milou_log "INFO" "SSL configuration cancelled - please choose a different option"
                    return 1
                fi
            fi
            ;;
        *)
            milou_log "ERROR" "Invalid SSL option: $ssl_choice"
            return 1
            ;;
    esac
    
    milou_log "DEBUG" "SSL config collected: mode=$SSL_MODE, domain=$DOMAIN"
    return 0
}

# Collect admin configuration
_collect_admin_configuration() {
    milou_log "INFO" "👤 Admin Account Configuration"
    
    # Admin username
    if [[ -z "${ADMIN_USERNAME:-}" ]]; then
        milou_prompt_user "Admin username" "admin" "username" "false" 3
        ADMIN_USERNAME="$REPLY"
    fi
    
    # Admin password
    if [[ -z "${ADMIN_PASSWORD:-}" ]]; then
        milou_log "INFO" "💡 Leave empty to generate a secure password"
        milou_prompt_user "Admin password" "" "password" "true" 3
        if [[ -n "$REPLY" ]]; then
            ADMIN_PASSWORD="$REPLY"
        else
            ADMIN_PASSWORD=$(milou_generate_secure_random 16)
            milou_log "INFO" "Generated secure password: $ADMIN_PASSWORD"
            milou_log "WARN" "⚠️  Save this password securely!"
        fi
    fi
    
    milou_log "DEBUG" "Admin config collected: username=$ADMIN_USERNAME"
    return 0
}

# Collect security configuration
_collect_security_configuration() {
    milou_log "INFO" "🔐 Security Configuration"
    
    # GitHub token for private registries
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        milou_log "INFO" "GitHub token is required for accessing private container images"
        milou_prompt_user "GitHub Personal Access Token" "" "token" "false" 3
        GITHUB_TOKEN="$REPLY"
        
        # Validate GitHub token
        if ! milou_validate_github_token "$GITHUB_TOKEN"; then
            milou_log "ERROR" "Invalid GitHub token format"
            return 1
        fi
    fi
    
    # JWT secret
    if [[ -z "${JWT_SECRET:-}" ]]; then
        JWT_SECRET=$(milou_generate_secure_random 32)
        milou_log "DEBUG" "Generated JWT secret"
    fi
    
    # Database passwords
    if [[ -z "${DB_PASSWORD:-}" ]]; then
        DB_PASSWORD=$(milou_generate_secure_random 16)
        milou_log "DEBUG" "Generated database password"
    fi
    
    milou_log "DEBUG" "Security config collected and generated"
    return 0
}

# Validate collected configuration
_validate_collected_configuration() {
    milou_log "INFO" "🔍 Validating configuration..."
    
    local validation_errors=0
    
    # Validate domain
    if ! milou_validate_domain "$DOMAIN" "true"; then
        milou_log "ERROR" "Invalid domain: $DOMAIN"
        ((validation_errors++))
    fi
    
    # Validate email
    if [[ ! "$ADMIN_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        milou_log "ERROR" "Invalid email format: $ADMIN_EMAIL"
        ((validation_errors++))
    fi
    
    # Validate GitHub token
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        if ! milou_validate_github_token "$GITHUB_TOKEN"; then
            milou_log "ERROR" "Invalid GitHub token"
            ((validation_errors++))
        fi
    fi
    
    # Validate SSL configuration
    if [[ "$SSL_MODE" == "existing" ]]; then
        if [[ ! -f "$SSL_CERT_PATH" ]]; then
            milou_log "ERROR" "SSL certificate file not found: $SSL_CERT_PATH"
            ((validation_errors++))
        fi
        if [[ ! -f "$SSL_KEY_PATH" ]]; then
            milou_log "ERROR" "SSL private key file not found: $SSL_KEY_PATH"
            ((validation_errors++))
        fi
    fi
    
    if [[ $validation_errors -gt 0 ]]; then
        milou_log "ERROR" "Configuration validation failed with $validation_errors error(s)"
        return 1
    fi
    
    milou_log "SUCCESS" "✅ Configuration validation passed"
    return 0
}

# Save configuration to environment file
_save_configuration_to_env() {
    # Set default env file if not provided
    local env_file="${ENV_FILE:-${SCRIPT_DIR}/.env}"
    
    milou_log "INFO" "💾 Saving configuration to: $env_file"
    
    # Create configuration directory if it doesn't exist
    local config_dir
    config_dir=$(dirname "$env_file")
    mkdir -p "$config_dir"
    
    # Generate secure database credentials first
    local postgres_user="milou_user_$(milou_generate_secure_random 8 "alphanumeric")"
    local postgres_password="$(milou_generate_secure_random 32 "safe")"
    local postgres_db="milou_database"
    local redis_password="$(milou_generate_secure_random 32 "safe")"
    local rabbitmq_user="milou_rabbit_$(milou_generate_secure_random 6 "alphanumeric")"
    local rabbitmq_password="$(milou_generate_secure_random 32 "safe")"
    local session_secret="$(milou_generate_secure_random 64 "safe")"
    local encryption_key="$(milou_generate_secure_random 64 "hex")"
    
    # Generate comprehensive environment file based on centralized validation requirements
    cat > "$env_file" << EOF
# =============================================================================
# Milou CLI Configuration - Complete Production Environment
# Generated on: $(date)
# =============================================================================

# =============================================================================
# METADATA AND VERSIONING
# =============================================================================
MILOU_VERSION=${SCRIPT_VERSION:-latest}
MILOU_GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
NODE_ENV=production

# =============================================================================
# SERVER CONFIGURATION (Required by centralized validation)
# =============================================================================
SERVER_NAME=${DOMAIN}
CUSTOMER_DOMAIN_NAME=${DOMAIN}
DOMAIN=${DOMAIN}
PORT=9999
CORS_ORIGIN=https://${DOMAIN}

# =============================================================================
# SSL CONFIGURATION
# =============================================================================
SSL_MODE=${SSL_MODE:-generate}
SSL_PORT=${HTTPS_PORT:-443}
SSL_CERT_PATH=${SSL_CERT_PATH:-./ssl/milou.crt}
SSL_KEY_PATH=${SSL_KEY_PATH:-./ssl/milou.key}

# =============================================================================
# DATABASE CONFIGURATION (PostgreSQL - Required)
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
# REDIS CONFIGURATION (Required)
# =============================================================================
REDIS_PASSWORD=$redis_password
REDIS_URL=redis://:$redis_password@redis:6379/0
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_SESSION_TTL=86400

# =============================================================================
# RABBITMQ CONFIGURATION (Required)
# =============================================================================
RABBITMQ_USER=$rabbitmq_user
RABBITMQ_PASSWORD=$rabbitmq_password
RABBITMQ_URL=amqp://$rabbitmq_user:$rabbitmq_password@rabbitmq:5672/

# =============================================================================
# SECURITY CONFIGURATION (Required)
# =============================================================================
JWT_SECRET=${JWT_SECRET}
SESSION_SECRET=$session_secret
ENCRYPTION_KEY=$encryption_key

# =============================================================================
# ADMIN CONFIGURATION
# =============================================================================
ADMIN_EMAIL=${ADMIN_EMAIL}
ADMIN_USERNAME=${ADMIN_USERNAME:-admin}
ADMIN_PASSWORD=${ADMIN_PASSWORD}

# =============================================================================
# GITHUB TOKEN (Optional but recommended)
# =============================================================================
GITHUB_TOKEN=${GITHUB_TOKEN:-}

# =============================================================================
# NETWORK CONFIGURATION
# =============================================================================
HTTP_PORT=${HTTP_PORT:-80}
HTTPS_PORT=${HTTPS_PORT:-443}
FRONTEND_URL=https://${DOMAIN}
BACKEND_URL=https://${DOMAIN}/api

# =============================================================================
# SSO CONFIGURATION (Optional)
# =============================================================================
SSO_CONFIG_ENCRYPTION_KEY=$encryption_key

# =============================================================================
# DOCKER CONFIGURATION
# =============================================================================
COMPOSE_PROJECT_NAME=milou-static
DOCKER_BUILDKIT=1
EOF
    
    # Set secure permissions
    chmod 600 "$env_file"
    
    milou_log "SUCCESS" "✅ Configuration saved successfully"
    milou_log "INFO" "📍 Configuration file: $env_file"
    milou_log "WARN" "🔒 File permissions set to 600 for security"
    
    return 0
}

# Create environment from existing environment variables
_create_env_from_environment() {
    milou_log "INFO" "Creating configuration from environment variables"
    
    # Use existing variables with fallbacks
    local config_domain="${DOMAIN:-localhost}"
    local config_email="${ADMIN_EMAIL:-admin@localhost}"
    local config_github_token="${GITHUB_TOKEN:-}"
    
    # Generate secure values for missing items
    local config_admin_password="${ADMIN_PASSWORD:-$(milou_generate_secure_random 16)}"
    local config_jwt_secret="${JWT_SECRET:-$(milou_generate_secure_random 32)}"
    local config_db_password="${DB_PASSWORD:-$(milou_generate_secure_random 16)}"
    
    # Set the variables for saving
    DOMAIN="$config_domain"
    ADMIN_EMAIL="$config_email"
    ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
    ADMIN_PASSWORD="$config_admin_password"
    GITHUB_TOKEN="$config_github_token"
    JWT_SECRET="$config_jwt_secret"
    DB_PASSWORD="$config_db_password"
    SSL_MODE="${SSL_MODE:-generate}"
    HTTP_PORT="${HTTP_PORT:-80}"
    HTTPS_PORT="${HTTPS_PORT:-443}"
    
    # Save to file
    _save_configuration_to_env
}

# Generate automatic configuration with smart defaults
_generate_automatic_configuration() {
    milou_log "INFO" "Generating automatic configuration with smart defaults"
    
    # Auto-detect or use sensible defaults
    DOMAIN="${DOMAIN:-localhost}"
    ADMIN_EMAIL="${ADMIN_EMAIL:-admin@localhost}"
    ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
    ADMIN_PASSWORD=$(milou_generate_secure_random 16)
    GITHUB_TOKEN="${GITHUB_TOKEN:-}"
    JWT_SECRET=$(milou_generate_secure_random 32)
    DB_PASSWORD=$(milou_generate_secure_random 16)
    SSL_MODE="generate"
    HTTP_PORT="80"
    HTTPS_PORT="443"
    
    milou_log "INFO" "Auto-generated admin password: $ADMIN_PASSWORD"
    milou_log "WARN" "⚠️  Save this password securely!"
    
    # Save configuration
    _save_configuration_to_env
}

# Export functions
export -f setup_run_configuration_wizard
export -f _run_interactive_configuration_wizard
export -f _run_non_interactive_configuration
export -f _run_automatic_configuration
export -f _collect_basic_configuration
export -f _collect_domain_configuration
export -f _collect_ssl_configuration
export -f _collect_admin_configuration
export -f _collect_security_configuration
export -f _validate_collected_configuration
export -f _save_configuration_to_env
export -f _create_env_from_environment
export -f _generate_automatic_configuration 