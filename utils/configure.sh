#!/bin/bash

# Configuration utility functions

# Generate a secure random string of specified length
generate_random_string() {
    local length=${1:-32}
    
    # Use openssl if available for better entropy
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 "$((length * 3 / 4))" | tr -d "=+/" | cut -c1-"$length"
    else
        # Fallback to /dev/urandom with base64 encoding
        head -c "$length" /dev/urandom | base64 | tr -d "=+/" | cut -c1-"$length"
    fi
}

# Validate configuration inputs
validate_config_inputs() {
    local domain="$1"
    local ssl_path="$2"
    
    # Validate domain
    if [[ -n "$domain" ]] && [[ "$domain" != "localhost" ]]; then
        if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
            echo "Error: Invalid domain name format: $domain"
            return 1
        fi
    fi
    
    # Validate SSL path
    if [[ -n "$ssl_path" ]]; then
        local ssl_dir=$(dirname "$ssl_path")
        if [[ ! -d "$ssl_dir" ]]; then
            echo "Error: SSL path directory does not exist: $ssl_dir"
            return 1
        fi
    fi
    
    return 0
}

# Generate a configuration file with all required environment variables
generate_config() {
    local domain=${1:-localhost}
    local ssl_path=${2:-./ssl}
    
    echo "Generating .env configuration file..."
    
    # Validate inputs
    if ! validate_config_inputs "$domain" "$ssl_path"; then
        return 1
    fi
    
    # Database credentials
    local DB_USER="milou_$(generate_random_string 8)"
    local DB_PASSWORD="$(generate_random_string 32)"
    local DB_NAME="milou"
    local POSTGRES_USER="${DB_USER}"
    local POSTGRES_PASSWORD="${DB_PASSWORD}"
    local POSTGRES_DB="${DB_NAME}"
    
    # Redis credentials
    local REDIS_PASSWORD="$(generate_random_string 32)"
    
    # RabbitMQ credentials
    local RABBITMQ_USER="guest"
    local RABBITMQ_PASSWORD="guest"
    
    # Session and encryption
    local SESSION_SECRET="$(generate_random_string 64)"
    local ENCRYPTION_KEY="$(generate_random_string 32)"
    
    # Save to .env file
    cat > "${SCRIPT_DIR}/.env" << EOF
# Milou Application Environment Configuration
# Generated on $(date)
# Version: ${VERSION:-1.1.0}
# ========================================

# Nginx configuration
# ----------------------------------------
SERVER_NAME=${domain}
CUSTOMER_DOMAIN_NAME=${domain}
SSL_PORT=443
SSL_CERT_PATH=${ssl_path}
CORS_ORIGIN=https://${domain}

# Database Configuration
# ----------------------------------------
DB_HOST=db
DB_PORT=5432
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_NAME=${DB_NAME}
DATABASE_URI=postgresql+psycopg2://${DB_USER}:${DB_PASSWORD}@db:5432/${DB_NAME}
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB}

# Redis Configuration
# ----------------------------------------
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_SESSION_TTL=3600
REDIS_MAX_RETRIES=3
REDIS_CONNECT_TIMEOUT=10000
REDIS_CLEANUP_ENABLED=true
REDIS_CLEANUP_INTERVAL=3600

# RabbitMQ Configuration
# ----------------------------------------
RABBITMQ_URL=amqp://${RABBITMQ_USER}:${RABBITMQ_PASSWORD}@rabbitmq:5672
RABBITMQ_USER=${RABBITMQ_USER}
RABBITMQ_PASSWORD=${RABBITMQ_PASSWORD}

# Session Configuration
# ----------------------------------------
SESSION_SECRET=${SESSION_SECRET}

# Security
# ----------------------------------------
ENCRYPTION_KEY=${ENCRYPTION_KEY}

# API
PORT=9999

# Environment
NODE_ENV=production

# SECURITY NOTE: GitHub token should NOT be stored here
# Pass it as command line argument: --token YOUR_TOKEN
EOF

    echo "Configuration file created at ${SCRIPT_DIR}/.env"
    
    # Set secure permissions
    chmod 600 "${SCRIPT_DIR}/.env" || {
        echo "Warning: Could not set secure permissions on .env file"
    }
    
    # Save a backup of the configuration
    mkdir -p "${CONFIG_DIR}"
    cp "${SCRIPT_DIR}/.env" "${CONFIG_DIR}/env_$(date +%Y%m%d%H%M%S).backup" || {
        echo "Warning: Could not create configuration backup"
    }
    
    return 0
}

# Update a specific configuration value
update_config_value() {
    local key="$1"
    local value="$2"
    local env_file="${SCRIPT_DIR}/.env"
    
    # Check if the key exists
    if grep -q "^${key}=" "${env_file}"; then
        # Replace the existing value
        sed -i "s|^${key}=.*|${key}=${value}|" "${env_file}"
    else
        # Add the key-value pair at the end
        echo "${key}=${value}" >> "${env_file}"
    fi
}

# Get a specific configuration value
get_config_value() {
    local key="$1"
    local env_file="${SCRIPT_DIR}/.env"
    
    # Check if the file exists
    if [ ! -f "${env_file}" ]; then
        echo ""
        return 1
    fi
    
    # Extract the value
    local value=$(grep "^${key}=" "${env_file}" | cut -d '=' -f 2-)
    echo "${value}"
}

# Validate the configuration
validate_config() {
    local env_file="${SCRIPT_DIR}/.env"
    
    # Check if the file exists
    if [ ! -f "${env_file}" ]; then
        echo "Error: Configuration file does not exist."
        return 1
    fi
    
    # Check for required variables
    local required_vars=(
        "SERVER_NAME"
        "SSL_CERT_PATH"
        "DB_USER"
        "DB_PASSWORD"
        "REDIS_PASSWORD"
        "SESSION_SECRET"
        "ENCRYPTION_KEY"
    )
    
    local missing=false
    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" "${env_file}"; then
            echo "Error: Missing required configuration variable: ${var}"
            missing=true
        fi
    done
    
    if [ "${missing}" = true ]; then
        return 1
    fi
    
    return 0
}

# Export the original generatedEnv variable for reference
generatedEnv="
# Milou Application Environment Configuration
# ========================================

# Nginx configuration
# ----------------------------------------
SERVER_NAME=${SERVER_NAME:-localhost}
SSL_PORT=${SSL_PORT:-443}
SSL_CERT_PATH=${SSL_CERT_PATH:-./ssl}
CORS_ORIGIN=${CORS_ORIGIN:-http://localhost}

# Database Configuration
# ----------------------------------------
DB_HOST=${DB_HOST:-your_db_host_here}
DB_PORT=${DB_PORT:-5432}
DB_USER=${DB_USER:-your_db_user_here}
DB_PASSWORD=${DB_PASSWORD:-your_db_password_here}
DB_NAME=${DB_NAME:-your_db_name_here}
DATABASE_URI=${DATABASE_URI:-postgresql+psycopg2://your_db_user_here:your_db_password_here@your_db_host_here:5432/your_db_name_here}

# Redis Configuration
# ----------------------------------------
REDIS_HOST=${REDIS_HOST:-your_redis_host_here}
REDIS_PORT=${REDIS_PORT:-6379}
REDIS_PASSWORD=${REDIS_PASSWORD:-your_redis_password_here}
REDIS_SESSION_TTL=${REDIS_SESSION_TTL:-3600}
REDIS_MAX_RETRIES=${REDIS_MAX_RETRIES:-3}
REDIS_CONNECT_TIMEOUT=${REDIS_CONNECT_TIMEOUT:-10000}
REDIS_CLEANUP_ENABLED=${REDIS_CLEANUP_ENABLED:-true}
REDIS_CLEANUP_INTERVAL=${REDIS_CLEANUP_INTERVAL:-3600}

# RabbitMQ Configuration
# ----------------------------------------
RABBITMQ_URL=${RABBITMQ_URL:-amqp://your_rabbitmq_user_here:your_rabbitmq_password_here@your_rabbitmq_host_here:5672}

# Session Configuration
# ----------------------------------------
SESSION_SECRET=${SESSION_SECRET:-your_session_secret_here}

# Security
# ----------------------------------------
ENCRYPTION_KEY=${ENCRYPTION_KEY:-your_encryption_key_here}

# API
PORT=${PORT:-9999}
"
