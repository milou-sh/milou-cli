#!/bin/bash

# =============================================================================
# Configuration Migration Module for Milou CLI
# Handles migration of configuration formats between versions
# =============================================================================

# Module guard to prevent multiple loading
if [[ "${MILOU_CONFIG_MIGRATION_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_CONFIG_MIGRATION_LOADED="true"

# Ensure logging is available
if ! command -v milou_log >/dev/null 2>&1; then
    source "${SCRIPT_DIR}/lib/core/logging.sh" 2>/dev/null || {
        echo "ERROR: Cannot load logging module" >&2
        exit 1
    }
fi

# Load preservation module if available
if [[ -f "${SCRIPT_DIR}/lib/system/config/preservation.sh" ]]; then
    source "${SCRIPT_DIR}/lib/system/config/preservation.sh"
fi

# =============================================================================
# Configuration Migration Functions
# =============================================================================

# Generate configuration with preserved credentials
generate_config_with_preservation() {
    local domain=${1:-localhost}
    local ssl_path=${2:-./ssl}
    local admin_email="${3:-}"
    local preserve_mode="${4:-auto}"  # auto, force, never
    
    milou_log "STEP" "Generating configuration with credential preservation..."
    
    # First try to preserve existing credentials
    local has_preserved=false
    if [[ "$preserve_mode" == "auto" || "$preserve_mode" == "force" ]]; then
        if preserve_database_credentials; then
            has_preserved=true
            milou_log "INFO" "✅ Existing credentials preserved"
        elif [[ "$preserve_mode" == "force" ]]; then
            milou_log "ERROR" "Failed to preserve credentials in force mode"
            return 1
        fi
    fi
    
    # Validate inputs first
    if ! validate_config_inputs "$domain" "$ssl_path" "$admin_email"; then
        milou_log "ERROR" "Configuration input validation failed"
        return 1
    fi
    
    # Generate new credentials only for missing ones
    milou_log "DEBUG" "Generating secure credentials (preserving existing when available)..."
    
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
        
        milou_log "INFO" "🔄 Using preserved database user: $db_user"
        milou_log "INFO" "🔄 Using preserved RabbitMQ user: $rabbitmq_user"
        milou_log "DEBUG" "Preserved secrets will maintain compatibility with existing data"
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
        
        milou_log "INFO" "🆕 Generated new database user: $db_user"
        milou_log "INFO" "🆕 Generated new RabbitMQ user: $rabbitmq_user"
    fi
    
    # Determine ports with conflict checking
    local ssl_port="443"
    local api_port="9999"
    local http_port="80"
    
    # Check for port conflicts and suggest alternatives
    if command -v netstat >/dev/null 2>&1 && netstat -tlnp 2>/dev/null | grep -q ":443 "; then
        milou_log "WARN" "Port 443 is already in use, SSL might have conflicts"
    fi
    
    # Set environment based on domain
    local node_env="production"
    if [[ "$domain" == "localhost" ]]; then
        node_env="development"
    fi
    
    # Create comprehensive configuration with enhanced security
    milou_log "DEBUG" "Creating comprehensive configuration file..."
    
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
REDIS_SESSION_TTL=3600
REDIS_MAX_RETRIES=3
REDIS_CONNECT_TIMEOUT=10000
REDIS_CLEANUP_ENABLED=true
REDIS_CLEANUP_INTERVAL=3600
REDIS_URL=redis://:$redis_password@redis:6379/0

# =============================================================================
# RABBITMQ CONFIGURATION
# =============================================================================
RABBITMQ_URL=amqp://$rabbitmq_user:$rabbitmq_password@rabbitmq:5672
RABBITMQ_USER=$rabbitmq_user
RABBITMQ_PASSWORD=$rabbitmq_password
RABBITMQ_HOST=rabbitmq
RABBITMQ_PORT=5672
RABBITMQ_VHOST=/
RABBITMQ_MANAGEMENT_PORT=15672

# =============================================================================
# SESSION CONFIGURATION
# =============================================================================
SESSION_SECRET=$session_secret
SESSION_SECURE=true
SESSION_HTTP_ONLY=true
SESSION_SAME_SITE=strict
SESSION_MAX_AGE=86400

# =============================================================================
# SECURITY CONFIGURATION
# =============================================================================
ENCRYPTION_KEY=$encryption_key
JWT_SECRET=$jwt_secret
JWT_EXPIRATION=24h
JWT_REFRESH_EXPIRATION=7d
BCRYPT_ROUNDS=12
RATE_LIMIT_WINDOW=900000
RATE_LIMIT_MAX=100

# =============================================================================
# LOGGING CONFIGURATION
# =============================================================================
LOG_LEVEL=info
LOG_FORMAT=json
LOG_DATE_FORMAT=YYYY-MM-DD HH:mm:ss.SSS
LOG_MAX_SIZE=10m
LOG_MAX_FILES=5
LOG_COMPRESS=true

# =============================================================================
# DEVELOPMENT CONFIGURATION
# =============================================================================
DEBUG=false
VERBOSE_LOGGING=false
PROFILING_ENABLED=false
HOT_RELOAD=false

# =============================================================================
# FEATURE FLAGS
# =============================================================================
FEATURE_USER_REGISTRATION=true
FEATURE_EMAIL_VERIFICATION=true
FEATURE_TWO_FACTOR_AUTH=false
FEATURE_API_RATE_LIMITING=true
FEATURE_AUDIT_LOGGING=true

EOF

    # Set secure permissions
    chmod 600 "${SCRIPT_DIR}/.env"
    
    # Log success with preservation information
    if [[ "$has_preserved" == "true" ]]; then
        milou_log "SUCCESS" "✅ Configuration generated with preserved credentials"
        milou_log "SUCCESS" "✅ Preserved existing credentials for seamless upgrade"
    else
        milou_log "SUCCESS" "✅ Configuration generated with new credentials"
    fi
    
    milou_log "INFO" "Configuration saved to: ${SCRIPT_DIR}/.env"
    return 0
}

# Migrate configuration from an older format
migrate_configuration() {
    local source_env="${1:-${SCRIPT_DIR}/.env}"
    local target_version="${2:-${SCRIPT_VERSION:-3.0.0}}"
    
    if [[ ! -f "$source_env" ]]; then
        milou_log "ERROR" "Source configuration file not found: $source_env"
        return 1
    fi
    
    # Determine current version
    local current_version
    current_version=$(get_config_version)
    
    milou_log "INFO" "Migrating configuration from version '$current_version' to '$target_version'"
    
    # Backup original configuration
    local backup_file="${source_env}.migration.backup.$(date +%s)"
    if cp "$source_env" "$backup_file"; then
        milou_log "INFO" "Original configuration backed up to: $backup_file"
        chmod 600 "$backup_file"
    else
        milou_log "ERROR" "Failed to backup original configuration"
        return 1
    fi
    
    # Preserve existing credentials
    if ! preserve_database_credentials; then
        milou_log "WARN" "No credentials found to preserve during migration"
    fi
    
    # Extract key settings from old config
    local domain ssl_path admin_email
    domain=$(grep "^SERVER_NAME=" "$source_env" | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "localhost")
    ssl_path=$(grep "^SSL_CERT_PATH=" "$source_env" | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "./ssl")
    admin_email=$(grep "^MILOU_ADMIN_EMAIL=" "$source_env" | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "")
    
    # Generate new configuration with preserved credentials
    if generate_config_with_preservation "$domain" "$ssl_path" "$admin_email" "force"; then
        milou_log "SUCCESS" "Configuration migration completed successfully"
        milou_log "INFO" "Migrated from: $current_version → $target_version"
        return 0
    else
        milou_log "ERROR" "Configuration migration failed"
        # Restore backup on failure
        if [[ -f "$backup_file" ]]; then
            cp "$backup_file" "$source_env"
            milou_log "INFO" "Restored original configuration from backup"
        fi
        return 1
    fi
}

# Check if configuration is compatible with current version
is_config_compatible() {
    local env_file="${1:-${SCRIPT_DIR}/.env}"
    local required_version="${2:-${SCRIPT_VERSION:-3.0.0}}"
    
    if [[ ! -f "$env_file" ]]; then
        return 1  # No config file = not compatible
    fi
    
    local config_version
    config_version=$(get_config_version)
    
    if [[ "$config_version" == "unknown" || "$config_version" == "none" ]]; then
        milou_log "DEBUG" "Configuration version unknown - assuming incompatible"
        return 1
    fi
    
    # Simple version comparison (assuming semantic versioning)
    if [[ "$config_version" == "$required_version" ]]; then
        milou_log "DEBUG" "Configuration version matches: $config_version"
        return 0
    else
        milou_log "DEBUG" "Configuration version mismatch: $config_version != $required_version"
        return 1
    fi
}

# Update configuration to add missing modern fields
modernize_configuration() {
    local env_file="${1:-${SCRIPT_DIR}/.env}"
    
    if [[ ! -f "$env_file" ]]; then
        milou_log "ERROR" "Configuration file not found: $env_file"
        return 1
    fi
    
    milou_log "INFO" "Modernizing configuration file: $env_file"
    
    # Backup before modernization
    local backup_file="${env_file}.modernize.backup.$(date +%s)"
    cp "$env_file" "$backup_file"
    chmod 600 "$backup_file"
    
    # Add modern fields if missing
    local -a modern_fields=(
        "MILOU_VERSION=${SCRIPT_VERSION:-3.0.0}"
        "MILOU_GENERATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        "API_VERSION=v1"
        "LOG_LEVEL=info"
        "SESSION_SECURE=true"
        "SESSION_HTTP_ONLY=true"
        "BCRYPT_ROUNDS=12"
        "FEATURE_API_RATE_LIMITING=true"
        "FEATURE_AUDIT_LOGGING=true"
    )
    
    local added_count=0
    for field in "${modern_fields[@]}"; do
        local key="${field%%=*}"
        if ! grep -q "^${key}=" "$env_file"; then
            echo "$field" >> "$env_file"
            ((added_count++))
            milou_log "DEBUG" "Added modern field: $key"
        fi
    done
    
    if [[ $added_count -gt 0 ]]; then
        milou_log "SUCCESS" "Added $added_count modern configuration fields"
        milou_log "INFO" "Configuration modernization completed"
        return 0
    else
        milou_log "INFO" "Configuration already modern - no changes needed"
        rm -f "$backup_file"  # Remove unnecessary backup
        return 0
    fi
}

# Validate configuration after migration
validate_migrated_config() {
    local env_file="${1:-${SCRIPT_DIR}/.env}"
    
    if [[ ! -f "$env_file" ]]; then
        milou_log "ERROR" "Migrated configuration file not found: $env_file"
        return 1
    fi
    
    milou_log "INFO" "Validating migrated configuration..."
    
    # Check for required fields
    local -a required_fields=(
        "MILOU_VERSION"
        "SERVER_NAME"
        "DB_USER"
        "DB_PASSWORD"
        "REDIS_PASSWORD"
        "SESSION_SECRET"
        "ENCRYPTION_KEY"
        "JWT_SECRET"
    )
    
    local missing_fields=()
    for field in "${required_fields[@]}"; do
        if ! grep -q "^${field}=" "$env_file"; then
            missing_fields+=("$field")
        fi
    done
    
    if [[ ${#missing_fields[@]} -gt 0 ]]; then
        milou_log "ERROR" "Migration validation failed - missing required fields:"
        for field in "${missing_fields[@]}"; do
            milou_log "ERROR" "  • $field"
        done
        return 1
    fi
    
    # Check file permissions
    local perms
    perms=$(stat -c "%a" "$env_file" 2>/dev/null || echo "unknown")
    if [[ "$perms" != "600" ]]; then
        milou_log "WARN" "Configuration file permissions are not secure: $perms"
        chmod 600 "$env_file"
        milou_log "INFO" "Fixed configuration file permissions to 600"
    fi
    
    milou_log "SUCCESS" "Migration validation passed - configuration is valid"
    return 0
}

milou_log "DEBUG" "Configuration migration module loaded successfully" 