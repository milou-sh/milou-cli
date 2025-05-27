#!/bin/bash

# =============================================================================
# Centralized Environment Validation for Milou CLI
# Single source of truth for environment requirements
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# =============================================================================
# AUTHORITATIVE ENVIRONMENT REQUIREMENTS
# =============================================================================

# Single source of truth for ALL required environment variables
# This is the ONLY place where required variables should be defined
milou_config_get_required_environment_variables() {
    local context="${1:-all}"  # all, minimal, production
    local -a required_vars=()
    
    case "$context" in
        "minimal")
            # Minimal requirements for basic functionality
            required_vars=(
                "SERVER_NAME"
                "DATABASE_URI"
                "POSTGRES_USER"
                "POSTGRES_PASSWORD"
                "REDIS_URL"
                "REDIS_PASSWORD"
                "JWT_SECRET"
                "SESSION_SECRET"
            )
            ;;
        "production")
            # Production deployment requirements  
            required_vars=(
                "SERVER_NAME"
                "CUSTOMER_DOMAIN_NAME"
                "SSL_CERT_PATH"
                "DATABASE_URI"
                "POSTGRES_USER"
                "POSTGRES_PASSWORD"
                "POSTGRES_DB"
                "REDIS_URL"
                "REDIS_PASSWORD"
                "RABBITMQ_URL"
                "RABBITMQ_USER"
                "RABBITMQ_PASSWORD"
                "JWT_SECRET"
                "SESSION_SECRET"
                "ENCRYPTION_KEY"
                "DB_USER"
                "DB_PASSWORD"
                "DB_NAME"
                "PORT"
                "NODE_ENV"
            )
            ;;
        "all"|*)
            # Complete requirements for full functionality
            required_vars=(
                # Server Configuration
                "SERVER_NAME"
                "CUSTOMER_DOMAIN_NAME"
                "SSL_PORT"
                "SSL_CERT_PATH"
                "CORS_ORIGIN"
                
                # Database Configuration (PostgreSQL)
                "DATABASE_URI"
                "POSTGRES_USER"
                "POSTGRES_PASSWORD"
                "POSTGRES_DB"
                "DB_HOST"
                "DB_PORT"
                "DB_USER"
                "DB_PASSWORD"
                "DB_NAME"
                
                # Redis Configuration
                "REDIS_URL"
                "REDIS_HOST"
                "REDIS_PORT"
                "REDIS_PASSWORD"
                "REDIS_SESSION_TTL"
                
                # RabbitMQ Configuration
                "RABBITMQ_URL"
                "RABBITMQ_USER" 
                "RABBITMQ_PASSWORD"
                
                # Security Configuration
                "JWT_SECRET"
                "SESSION_SECRET"
                "ENCRYPTION_KEY"
                
                # API Configuration
                "PORT"
                
                # Environment
                "NODE_ENV"
            )
            ;;
    esac
    
    printf '%s\n' "${required_vars[@]}"
}

# Get optional environment variables (for documentation/validation)
milou_config_get_optional_environment_variables() {
    local -a optional_vars=(
        # Extended Database Configuration
        "DB_CHARSET"
        "DB_COLLATION"
        "DB_POOL_SIZE"
        "DB_POOL_MAX_OVERFLOW"
        "DB_POOL_TIMEOUT"
        "DB_POOL_RECYCLE"
        
        # Extended Redis Configuration
        "REDIS_DB"
        "REDIS_MAX_RETRIES"
        "REDIS_CONNECT_TIMEOUT"
        "REDIS_COMMAND_TIMEOUT"
        "REDIS_CLEANUP_ENABLED"
        "REDIS_CLEANUP_INTERVAL"
        
        # Extended RabbitMQ Configuration
        "RABBITMQ_HOST"
        "RABBITMQ_PORT"
        "RABBITMQ_VHOST"
        "RABBITMQ_MANAGEMENT_PORT"
        "RABBITMQ_EXCHANGE"
        "RABBITMQ_QUEUE_PREFIX"
        
        # Extended Security Configuration
        "JWT_ALGORITHM"
        "JWT_EXPIRATION"
        "JWT_REFRESH_EXPIRATION"
        "BCRYPT_ROUNDS"
        "API_RATE_LIMIT"
        "SESSION_SECURE_COOKIES"
        "SESSION_HTTP_ONLY"
        "SESSION_SAME_SITE"
        "SESSION_TIMEOUT"
        
        # SSL/TLS Configuration
        "SSL_ENABLED"
        "SSL_CERT_FILE"
        "SSL_KEY_FILE"
        "SSL_PROTOCOLS"
        "SSL_CIPHERS"
        "HSTS_ENABLED"
        "HSTS_MAX_AGE"
        
        # Monitoring and Logging
        "LOG_LEVEL"
        "LOG_FORMAT"
        "ENABLE_MONITORING"
        "HEALTH_CHECK_INTERVAL"
        "METRICS_ENABLED"
        
        # Admin Configuration
        "MILOU_ADMIN_EMAIL"
        "MILOU_VERSION"
        "MILOU_GENERATED_AT"
        
        # Feature Flags
        "ENABLE_ANALYTICS"
        "ENABLE_RATE_LIMITING"
        "ENABLE_COMPRESSION"
        "ENABLE_CACHING"
        "ENABLE_DEBUG_MODE"
        "ENABLE_MAINTENANCE_MODE"
    )
    
    printf '%s\n' "${optional_vars[@]}"
}

# =============================================================================
# CENTRALIZED VALIDATION FUNCTIONS
# =============================================================================

# Validate environment file against requirements
milou_config_validate_environment_comprehensive() {
    local env_file="${1:-${SCRIPT_DIR}/.env}"
    local context="${2:-production}"  # minimal, production, all
    local strict="${3:-true}"         # true = fail on missing, false = warn only
    
    if [[ ! -f "$env_file" ]]; then
    milou_log "ERROR" "Environment file not found: $env_file"
        return 1
    fi
    
    if [[ ! -r "$env_file" ]]; then
    milou_log "ERROR" "Environment file not readable: $env_file"
        return 1
    fi
    
    if [[ ! -s "$env_file" ]]; then
    milou_log "ERROR" "Environment file is empty: $env_file"
        return 1
    fi
    
    milou_log "STEP" "Validating environment file for $context deployment"
    milou_log "DEBUG" "Environment file: $env_file"
    milou_log "DEBUG" "Validation mode: ${strict:-false}"
    
    local errors=0
    local warnings=0
    
    # Get required variables for the specified context
    local -a required_vars
    readarray -t required_vars < <(milou_config_get_required_environment_variables "$context")
    
    milou_log "DEBUG" "Checking ${#required_vars[@]} required variables for $context context"
    
    # Check for missing required variables
    local missing_vars=()
    local present_vars=()
    
    for var in "${required_vars[@]}"; do
        if grep -q "^${var}=" "$env_file" 2>/dev/null; then
            present_vars+=("$var")
    milou_log "TRACE" "✓ Found: $var"
        else
            missing_vars+=("$var")
    milou_log "TRACE" "✗ Missing: $var"
        fi
    done
    
    # Report results
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        if [[ "$strict" == "true" ]]; then
    milou_log "ERROR" "Missing required environment variables for $context deployment:"
            printf '  %s\n' "${missing_vars[@]}"
            ((errors++))
        else
    milou_log "WARN" "Missing recommended environment variables for $context deployment:"
            printf '  %s\n' "${missing_vars[@]}"
            ((warnings++))
        fi
    else
    milou_log "SUCCESS" "All required environment variables are present for $context deployment"
    fi
    
    milou_log "INFO" "Environment validation summary:"
    milou_log "INFO" "  ✅ Present: ${#present_vars[@]}/${#required_vars[@]} required variables"
    milou_log "INFO" "  ❌ Missing: ${#missing_vars[@]} variables"
    milou_log "INFO" "  🚨 Errors: $errors"
    milou_log "INFO" "  ⚠️ Warnings: $warnings"
    
    # Check file permissions
    local file_perms
    file_perms=$(stat -c "%a" "$env_file" 2>/dev/null || stat -f "%A" "$env_file" 2>/dev/null || echo "unknown")
    
    if [[ "$file_perms" != "600" ]]; then
    milou_log "WARN" "Environment file has insecure permissions: $file_perms"
    milou_log "INFO" "Setting secure permissions..."
        if chmod 600 "$env_file"; then
    milou_log "SUCCESS" "Fixed file permissions to 600"
        else
    milou_log "ERROR" "Failed to set secure permissions"
            ((errors++))
        fi
    else
    milou_log "SUCCESS" "Environment file has secure permissions (600)"
    fi
    
    # Validate syntax
    if ! env -i bash -n "$env_file" 2>/dev/null; then
    milou_log "ERROR" "Environment file has syntax errors"
        ((errors++))
    else
    milou_log "SUCCESS" "Environment file syntax is valid"
    fi
    
    # Return appropriate exit code
    if [[ $errors -gt 0 ]]; then
    milou_log "ERROR" "Environment validation failed ($errors errors, $warnings warnings)"
        return 1
    elif [[ $warnings -gt 0 ]]; then
    milou_log "WARN" "Environment validation completed with warnings ($warnings warnings)"
        return 0
    else
    milou_log "SUCCESS" "Environment validation passed successfully"
        return 0
    fi
}

# Quick validation for essential variables only
milou_config_validate_environment_essential() {
    local env_file="${1:-${SCRIPT_DIR}/.env}"
    milou_config_validate_environment_comprehensive "$env_file" "minimal" "true"
}

# Production validation with all requirements
milou_config_validate_environment_production() {
    local env_file="${1:-${SCRIPT_DIR}/.env}"
    milou_config_validate_environment_comprehensive "$env_file" "production" "true"
}

# Check if specific variable exists and is not empty
milou_config_check_environment_variable() {
    local var_name="$1"
    local env_file="${2:-${SCRIPT_DIR}/.env}"
    
    if [[ -z "$var_name" ]]; then
    milou_log "ERROR" "Variable name is required"
        return 1
    fi
    
    if [[ ! -f "$env_file" ]]; then
    milou_log "DEBUG" "Environment file not found: $env_file"
        return 1
    fi
    
    # Check if variable exists and has a value
    local value
    value=$(grep "^${var_name}=" "$env_file" 2>/dev/null | cut -d'=' -f2-)
    
    if [[ -n "$value" ]]; then
    milou_log "DEBUG" "Variable $var_name is set"
        return 0
    else
    milou_log "DEBUG" "Variable $var_name is missing or empty"
        return 1
    fi
}

# List missing variables for a specific context
milou_config_list_missing_variables() {
    local env_file="${1:-${SCRIPT_DIR}/.env}"
    local context="${2:-production}"
    
    if [[ ! -f "$env_file" ]]; then
    milou_log "ERROR" "Environment file not found: $env_file"
        return 1
    fi
    
    local -a required_vars missing_vars
    readarray -t required_vars < <(milou_config_get_required_environment_variables "$context")
    
    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" "$env_file" 2>/dev/null; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        printf '%s\n' "${missing_vars[@]}"
        return 1
    else
        return 0
    fi
}

# =============================================================================
# Export Functions
# =============================================================================

# Main functions with milou_config_ prefix
export -f milou_config_get_required_environment_variables
export -f milou_config_get_optional_environment_variables
export -f milou_config_validate_environment_comprehensive
export -f milou_config_validate_environment_essential
export -f milou_config_validate_environment_production
export -f milou_config_check_environment_variable
export -f milou_config_list_missing_variables