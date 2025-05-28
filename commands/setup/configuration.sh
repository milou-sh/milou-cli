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

# Ensure user interface functions are available (for prompts and confirmations)
if ! command -v milou_prompt_user >/dev/null 2>&1; then
    if [[ -n "${SCRIPT_DIR:-}" ]] && [[ -f "${SCRIPT_DIR}/lib/core/user-interface.sh" ]]; then
        source "${SCRIPT_DIR}/lib/core/user-interface.sh" 2>/dev/null || {
            milou_log "ERROR" "Cannot load user-interface module"
            exit 1
        }
    else
        milou_log "ERROR" "milou_prompt_user function not available"
        exit 1
    fi
fi

# Ensure validation functions are available (for GitHub token validation)
if ! command -v milou_validate_github_token >/dev/null 2>&1; then
    if [[ -n "${SCRIPT_DIR:-}" ]] && [[ -f "${SCRIPT_DIR}/lib/core/validation.sh" ]]; then
        source "${SCRIPT_DIR}/lib/core/validation.sh" 2>/dev/null || {
            milou_log "ERROR" "Cannot load validation module"
            exit 1
        }
    else
        milou_log "ERROR" "milou_validate_github_token function not available"
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
    
    if [[ "$setup_mode" == "interactive" ]]; then
        milou_log "INFO" "🧙 Starting interactive configuration wizard"
        echo
        
        # Use the proper modular configuration collection functions
        _collect_basic_configuration || return 1
        _collect_domain_configuration || return 1
        _collect_ssl_configuration || return 1
        _collect_admin_configuration || return 1
        _collect_security_configuration || return 1
        _collect_docker_version_configuration || return 1
        
        # Validate collected configuration
        _validate_collected_configuration || return 1
        
        # CRITICAL FIX: Pass USE_LATEST_IMAGES to configuration generation
        local use_latest_param="${USE_LATEST_IMAGES:-true}"
        milou_log "DEBUG" "Using image versioning: latest=$use_latest_param"
        
        # Save configuration with proper parameters
        if _save_configuration_to_env; then
            milou_log "SUCCESS" "✅ Interactive configuration completed"
        else
            milou_log "ERROR" "Failed to save configuration"
            return 1
        fi
        
    else
        # Non-interactive mode
        milou_log "INFO" "🤖 Running in non-interactive mode with defaults"
        
        local domain="${DOMAIN:-localhost}"
        local admin_email="${ADMIN_EMAIL:-admin@localhost}"
        local ssl_path="${SSL_PATH:-./ssl}"
        local use_latest_param="${USE_LATEST_IMAGES:-true}"
        
        milou_log "INFO" "Domain: $domain"
        milou_log "INFO" "Admin Email: $admin_email"
        milou_log "INFO" "SSL Path: $ssl_path"
        milou_log "INFO" "Use Latest Images: $use_latest_param"
        
        # Set variables for non-interactive configuration
        DOMAIN="$domain"
        ADMIN_EMAIL="$admin_email"
        SSL_MODE="${SSL_MODE:-generate}"
        SSL_CERT_PATH="$ssl_path"
        HTTP_PORT="${HTTP_PORT:-80}"
        HTTPS_PORT="${HTTPS_PORT:-443}"
        
        # Generate configuration
        if _create_env_from_environment; then
            milou_log "SUCCESS" "✅ Non-interactive configuration completed"
        else
            milou_log "ERROR" "Failed to generate configuration"
            return 1
        fi
    fi
    
    return 0
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
    _collect_docker_version_configuration || return 1
    
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
        local domain
        milou_prompt_user "Enter domain name" "${DOMAIN:-localhost}" "domain" "false" 3
        DOMAIN="$domain"
    fi
    
    # Admin email configuration
    if [[ -z "${ADMIN_EMAIL:-}" ]]; then
        local email
        milou_prompt_user "Enter admin email" "${ADMIN_EMAIL:-admin@localhost}" "email" "false" 3
        ADMIN_EMAIL="$email"
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
        local port
        milou_prompt_user "HTTP port" "80" "port" "false" 3
        HTTP_PORT="$port"
    fi
    
    if [[ -z "${HTTPS_PORT:-}" ]]; then
        local port
        milou_prompt_user "HTTPS port" "443" "port" "false" 3
        HTTPS_PORT="$port"
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
    
    # Enhanced SSL mode selection with better explanations
    echo "SSL Configuration Options:"
    echo
    echo "  1. 🔒 Generate self-signed certificates (Recommended for development)"
    echo "     • Automatically creates SSL certificates for your domain"
    echo "     • Works immediately, no external setup needed"
    echo "     • Valid for: ${DOMAIN}, localhost, 127.0.0.1"
    echo
    echo "  2. 📁 Use existing SSL certificates (For production)"
    echo "     • Provide your own SSL certificate files"
    echo "     • Requires valid certificate and private key files"
    echo "     • Best for production with real domain certificates"
    echo
    echo "  3. ⚠️  HTTP only (No SSL - not recommended for production)"
    echo "     • Disables SSL completely"
    echo "     • All traffic will be unencrypted"
    echo "     • Only use for testing or development"
    echo
    
    local choice
    milou_prompt_user "Select SSL option [1-3]" "1" "choice" "false" 3
    local ssl_choice="$choice"
    
    case "$ssl_choice" in
        1)
            SSL_MODE="generate"
            # Set SSL directory path (not file paths) for Docker mounting
                                      SSL_CERT_DIR="./ssl"
            SSL_CERT_PATH="./ssl"  # Directory for Docker volume mount (relative to compose context)
            SSL_KEY_PATH="./ssl"   # Directory for Docker volume mount
            
            milou_log "SUCCESS" "✅ Will generate self-signed certificates"
            milou_log "INFO" "📂 Certificates will be stored in: $SSL_CERT_DIR/"
            milou_log "INFO" "🌐 Valid for domains: ${DOMAIN}, localhost, 127.0.0.1"
            milou_log "INFO" "📅 Validity: 365 days"
            ;;
        2)
            SSL_MODE="existing"
            milou_log "INFO" "📁 Using existing SSL certificates"
            echo
            milou_log "INFO" "💡 You can provide either:"
            echo "  • Individual certificate files (.crt and .key)"
            echo "  • A directory containing 'milou.crt' and 'milou.key'"
            echo
            
            local cert_input
            milou_prompt_user "Certificate path (file or directory)" "" "cert_input" "false" 3
            
            # Determine if input is file or directory
            if [[ -f "$cert_input" ]]; then
                # It's a certificate file
                SSL_CERT_FILE="$cert_input"
                local cert_dir
                cert_dir=$(dirname "$cert_input")
                
                # Ask for private key
                local key_input
                milou_prompt_user "Private key path" "${cert_dir}/milou.key" "key_input" "false" 3
                
                if [[ ! -f "$key_input" ]]; then
                    milou_log "ERROR" "Private key file not found: $key_input"
                    return 1
                fi
                
                SSL_KEY_FILE="$key_input"
                
                # For Docker, we need to mount the directory, not individual files
                SSL_CERT_PATH="$cert_dir"
                SSL_KEY_PATH="$cert_dir"
                
                milou_log "SUCCESS" "✅ Using certificate: $SSL_CERT_FILE"
                milou_log "INFO" "🔑 Using private key: $SSL_KEY_FILE"
                
            elif [[ -d "$cert_input" ]]; then
                # It's a directory
                SSL_CERT_DIR="$cert_input"
                SSL_CERT_PATH="$cert_input"
                SSL_KEY_PATH="$cert_input"
                
                # Check for expected files
                if [[ ! -f "$cert_input/milou.crt" ]]; then
                    milou_log "ERROR" "Certificate file not found: $cert_input/milou.crt"
                    milou_log "INFO" "💡 Expected file names: milou.crt and milou.key"
                    return 1
                fi
                if [[ ! -f "$cert_input/milou.key" ]]; then
                    milou_log "ERROR" "Private key file not found: $cert_input/milou.key"
                    milou_log "INFO" "💡 Expected file names: milou.crt and milou.key"
                    return 1
                fi
                
                SSL_CERT_FILE="$cert_input/milou.crt"
                SSL_KEY_FILE="$cert_input/milou.key"
                
                milou_log "SUCCESS" "✅ Using SSL directory: $SSL_CERT_DIR"
                milou_log "INFO" "📄 Certificate: $SSL_CERT_FILE"
                milou_log "INFO" "🔑 Private key: $SSL_KEY_FILE"
                
            else
                milou_log "ERROR" "Path not found: $cert_input"
                milou_log "INFO" "💡 Please provide either:"
                milou_log "INFO" "  • Path to certificate file (.crt)"
                milou_log "INFO" "  • Path to directory containing milou.crt and milou.key"
                return 1
            fi
            ;;
        3)
            SSL_MODE="none"
            milou_log "WARN" "⚠️  SSL disabled - HTTP only mode"
            
            if [[ "${DOMAIN}" != "localhost" ]]; then
                milou_log "WARN" "🚨 SECURITY WARNING: Using HTTP-only for domain '${DOMAIN}'"
                milou_log "WARN" "   • All data will be transmitted unencrypted"
                milou_log "WARN" "   • Passwords and sensitive data will be visible"
                milou_log "WARN" "   • Not suitable for production use"
                echo
                if ! milou_confirm "Continue with HTTP-only mode?" "N"; then
                    milou_log "INFO" "SSL configuration cancelled - please choose a different option"
                    return 1
                fi
            fi
            
            # Clear SSL paths for HTTP-only mode
            SSL_CERT_PATH=""
            SSL_KEY_PATH=""
            ;;
        *)
            milou_log "ERROR" "Invalid SSL option: $ssl_choice"
            milou_log "INFO" "💡 Please enter 1, 2, or 3"
            return 1
            ;;
    esac
    
    milou_log "DEBUG" "SSL config collected: mode=$SSL_MODE, cert_path=$SSL_CERT_PATH"
    return 0
}

# Collect admin configuration
_collect_admin_configuration() {
    milou_log "INFO" "👤 Admin Account Configuration"
    
    # Admin username
    if [[ -z "${ADMIN_USERNAME:-}" ]]; then
        local username
        milou_prompt_user "Admin username" "admin" "username" "false" 3
        ADMIN_USERNAME="$username"
    fi
    
    # Admin password
    if [[ -z "${ADMIN_PASSWORD:-}" ]]; then
        milou_log "INFO" "💡 Leave empty to generate a secure password"
        local password
        milou_prompt_user "Admin password" "" "password" "true" 3
        if [[ -n "$password" ]]; then
            ADMIN_PASSWORD="$password"
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
    milou_log "INFO" "🔒 Security Configuration"
    
    # GitHub token (optional but recommended)
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        milou_log "INFO" "GitHub token enables access to private container images"
        milou_log "INFO" "You can skip this and add it later if needed"
        
        local token
        milou_prompt_user "Enter GitHub token (optional)" "" "token" "true" 3
        if [[ -n "$token" ]]; then
            GITHUB_TOKEN="$token"
            
            # Validate the token
            if command -v milou_validate_github_token >/dev/null 2>&1; then
                if ! milou_validate_github_token "$GITHUB_TOKEN" "false"; then
                    milou_log "WARN" "⚠️  GitHub token validation failed, but continuing..."
                fi
            fi
        fi
    fi
    
    milou_log "DEBUG" "Security config collected"
    return 0
}

# Collect Docker image version configuration (NEW)
_collect_docker_version_configuration() {
    milou_log "INFO" "🐳 Docker Image Version Configuration"
    echo
    
    milou_log "INFO" "Choose which version of Milou Docker images to use:"
    echo "  1. 📦 latest (recommended for most users - newest features)"
    echo "  2. 🏷️  specific version (e.g., v1.0.0, v1.2.3)"
    echo "  3. 🔧 custom tag (for development or specific needs)"
    echo
    
    local version_choice
    milou_prompt_user "Select image version option [1-3]" "1" "version_choice" "false" 3
    
    case "$version_choice" in
        1)
            USE_LATEST_IMAGES=true
            MILOU_IMAGE_TAG="latest"
            milou_log "INFO" "✅ Using latest images"
            ;;
        2)
            USE_LATEST_IMAGES=false
            milou_log "INFO" "Available stable versions: v1.0.0, v1.1.0, v1.2.0"
            milou_log "INFO" "💡 Check GitHub releases for latest stable versions"
            
            local version_tag
            milou_prompt_user "Enter version tag (e.g., v1.0.0)" "v1.0.0" "version_tag" "false" 3
            MILOU_IMAGE_TAG="$version_tag"
            milou_log "INFO" "✅ Using version: $version_tag"
            ;;
        3)
            USE_LATEST_IMAGES=false
            milou_log "INFO" "💡 Custom tags might be: dev, staging, feature-branch-name"
            
            local custom_tag
            milou_prompt_user "Enter custom tag" "dev" "custom_tag" "false" 3
            MILOU_IMAGE_TAG="$custom_tag"
            milou_log "INFO" "✅ Using custom tag: $custom_tag"
            ;;
        *)
            milou_log "WARN" "Invalid choice, defaulting to latest"
            USE_LATEST_IMAGES=true
            MILOU_IMAGE_TAG="latest"
            ;;
    esac
    
    # Export for use in configuration generation
    export USE_LATEST_IMAGES
    export MILOU_IMAGE_TAG
    
    milou_log "DEBUG" "Docker version config: USE_LATEST_IMAGES=$USE_LATEST_IMAGES, MILOU_IMAGE_TAG=$MILOU_IMAGE_TAG"
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
    
    # Validate email (allow localhost for development)
    if [[ ! "$ADMIN_EMAIL" =~ ^[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,}|localhost)$ ]]; then
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
    
    # CRITICAL: Check for existing installation and preserve existing credentials
    local postgres_user postgres_password postgres_db redis_password rabbitmq_user rabbitmq_password session_secret encryption_key
    local is_fresh_install=true
    local preserve_existing_credentials=false
    
    # Check if this is an existing installation
    if [[ -f "$env_file" ]]; then
        milou_log "INFO" "🔍 Existing configuration detected - analyzing installation state"
        
        # Load existing credentials
        local existing_postgres_user existing_postgres_password existing_postgres_db
        local existing_redis_password existing_rabbitmq_user existing_rabbitmq_password
        local existing_session_secret existing_encryption_key
        
        # Extract existing credentials from environment file
        existing_postgres_user=$(grep "^POSTGRES_USER=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "")
        existing_postgres_password=$(grep "^POSTGRES_PASSWORD=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "")
        existing_postgres_db=$(grep "^POSTGRES_DB=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "")
        existing_redis_password=$(grep "^REDIS_PASSWORD=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "")
        existing_rabbitmq_user=$(grep "^RABBITMQ_USER=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "")
        existing_rabbitmq_password=$(grep "^RABBITMQ_PASSWORD=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "")
        existing_session_secret=$(grep "^SESSION_SECRET=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "")
        existing_encryption_key=$(grep "^ENCRYPTION_KEY=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "")
        
        # Check for existing Docker volumes (indicates data exists)
        local has_database_volume=false
        local has_redis_volume=false
        local has_rabbitmq_volume=false
        local has_substantial_data=false
        
        # Check for volumes with better detection logic
        if docker volume inspect "${DOCKER_PROJECT_NAME:-static}_pgdata" >/dev/null 2>&1 || \
           docker volume inspect "static_pgdata" >/dev/null 2>&1 || \
           docker volume inspect "milou-static_pgdata" >/dev/null 2>&1; then
            has_database_volume=true
            milou_log "DEBUG" "Found existing database volume"
            
            # Check if volume has substantial data (not just initialization)
            local volume_name
            for vol in "${DOCKER_PROJECT_NAME:-static}_pgdata" "static_pgdata" "milou-static_pgdata"; do
                if docker volume inspect "$vol" >/dev/null 2>&1; then
                    volume_name="$vol"
                    break
                fi
            done
            
            if [[ -n "$volume_name" ]]; then
                local volume_size
                volume_size=$(docker run --rm -v "$volume_name:/data" alpine sh -c 'du -s /data 2>/dev/null | cut -f1' 2>/dev/null || echo "0")
                if [[ "$volume_size" -gt 10240 ]]; then  # More than 10MB suggests real data
                    has_substantial_data=true
                    milou_log "DEBUG" "Database volume contains substantial data (${volume_size}KB)"
                fi
            fi
        fi
        
        if docker volume inspect "${DOCKER_PROJECT_NAME:-static}_redis_data" >/dev/null 2>&1 || \
           docker volume inspect "static_redis_data" >/dev/null 2>&1 || \
           docker volume inspect "milou-static_redis_data" >/dev/null 2>&1; then
            has_redis_volume=true
            milou_log "DEBUG" "Found existing Redis volume"
        fi
        
        if docker volume inspect "${DOCKER_PROJECT_NAME:-static}_rabbitmq_data" >/dev/null 2>&1 || \
           docker volume inspect "static_rabbitmq_data" >/dev/null 2>&1 || \
           docker volume inspect "milou-static_rabbitmq_data" >/dev/null 2>&1; then
            has_rabbitmq_volume=true
            milou_log "DEBUG" "Found existing RabbitMQ volume"
        fi
        
        # IMPROVED: Determine if we should preserve credentials based on multiple factors
        local credentials_exist=$([[ -n "$existing_postgres_user" && -n "$existing_postgres_password" ]] && echo "true" || echo "false")
        local volumes_exist=$([[ "$has_database_volume" == "true" || "$has_redis_volume" == "true" || "$has_rabbitmq_volume" == "true" ]] && echo "true" || echo "false")
        
        if [[ "$credentials_exist" == "true" && "$volumes_exist" == "true" ]]; then
            preserve_existing_credentials=true
            is_fresh_install=false
            
            milou_log "INFO" "🔄 Existing installation detected with data volumes"
            milou_log "INFO" "   • Database volume: $([ "$has_database_volume" == "true" ] && echo "✅ Found" || echo "❌ Missing")"
            milou_log "INFO" "   • Redis volume: $([ "$has_redis_volume" == "true" ] && echo "✅ Found" || echo "❌ Missing")"
            milou_log "INFO" "   • RabbitMQ volume: $([ "$has_rabbitmq_volume" == "true" ] && echo "✅ Found" || echo "❌ Missing")"
            milou_log "INFO" "   • Substantial data: $([ "$has_substantial_data" == "true" ] && echo "✅ Yes" || echo "❌ No")"
            
            # Default to preserving credentials unless explicitly overridden
            if [[ "${FORCE:-false}" != "true" && "${CLEAN_INSTALL:-false}" != "true" ]]; then
                milou_log "SUCCESS" "🔒 Preserving existing credentials to maintain data integrity"
                
                # Use existing credentials
                postgres_user="$existing_postgres_user"
                postgres_password="$existing_postgres_password"
                postgres_db="${existing_postgres_db:-milou_database}"
                redis_password="$existing_redis_password"
                rabbitmq_user="$existing_rabbitmq_user"
                rabbitmq_password="$existing_rabbitmq_password"
                session_secret="$existing_session_secret"
                encryption_key="$existing_encryption_key"
            else
                milou_log "WARN" "🚨 FORCE/CLEAN mode enabled - will generate new credentials"
                preserve_existing_credentials=false
            fi
            
        elif [[ "${FORCE:-false}" == "true" ]]; then
            milou_log "WARN" "🚨 FORCE mode enabled - generating new credentials despite existing installation"
            milou_log "WARN" "   ⚠️  This may cause data access issues if volumes contain existing data"
            milou_log "WARN" "   💡 Consider using '--clean' option for a completely fresh installation"
            preserve_existing_credentials=false
            is_fresh_install=false
        elif [[ "${CLEAN_INSTALL:-false}" == "true" ]]; then
            milou_log "INFO" "🧹 Clean installation requested via --clean option"
            if command -v _perform_clean_installation >/dev/null 2>&1; then
                _perform_clean_installation || return 1
            else
                milou_log "ERROR" "Clean installation function not available"
                return 1
            fi
            preserve_existing_credentials=false
            is_fresh_install=true
        else
            # Found env file but no substantial volumes or credentials - treat as partial installation
            milou_log "INFO" "📋 Found configuration file but no substantial data volumes - updating configuration"
            preserve_existing_credentials=false
            is_fresh_install=false
        fi
        
        # Offer user choice for credential handling (only in interactive mode and when we have real data)
        if [[ "${SETUP_MODE:-interactive}" == "interactive" && "$has_substantial_data" == "true" && "$preserve_existing_credentials" == "true" ]]; then
            echo
            milou_log "INFO" "🤔 Credential Management Options:"
            echo "  1. 🔒 Preserve existing credentials (Recommended - maintains data access)"
            echo "  2. 🔄 Generate new credentials (⚠️  May cause data access issues)"
            echo "  3. 🗑️  Clean installation (Removes all existing data and starts fresh)"
            echo
            
            local choice
            milou_prompt_user "Select credential management option [1-3]" "1" "choice" "false" 3
            
            case "$choice" in
                1)
                    milou_log "INFO" "✅ Keeping existing credentials"
                    # preserve_existing_credentials already set to true
                    ;;
                2)
                    milou_log "WARN" "⚠️  Generating new credentials - this may break access to existing data"
                    if milou_confirm "Are you sure? This may make existing data inaccessible." "N"; then
                        preserve_existing_credentials=false
                        milou_log "INFO" "🔄 Will generate new credentials"
                    else
                        milou_log "INFO" "✅ Keeping existing credentials"
                    fi
                    ;;
                3)
                    milou_log "WARN" "🗑️  Clean installation requested"
                    if milou_confirm "This will DELETE all existing data. Are you absolutely sure?" "N"; then
                        _perform_clean_installation || return 1
                        preserve_existing_credentials=false
                        is_fresh_install=true
                        milou_log "INFO" "🧹 Clean installation completed - will generate fresh credentials"
                    else
                        milou_log "INFO" "✅ Keeping existing credentials"
                    fi
                    ;;
                *)
                    milou_log "ERROR" "Invalid choice: $choice"
                    return 1
                    ;;
            esac
        fi
    fi
    
    # Generate credentials if needed (fresh install or forced new credentials)
    if [[ "$preserve_existing_credentials" != "true" ]]; then
        if [[ "$is_fresh_install" == "true" ]]; then
            milou_log "INFO" "🆕 Fresh installation - generating new secure credentials"
        else
            milou_log "INFO" "🔄 Generating new credentials (existing installation)"
        fi
        
        postgres_user="milou_user_$(milou_generate_secure_random 8 "alphanumeric")"
        postgres_password="$(milou_generate_secure_random 32 "safe")"
        postgres_db="milou_database"
        redis_password="$(milou_generate_secure_random 32 "safe")"
        rabbitmq_user="milou_rabbit_$(milou_generate_secure_random 6 "alphanumeric")"
        rabbitmq_password="$(milou_generate_secure_random 32 "safe")"
        session_secret="$(milou_generate_secure_random 64 "safe")"
        encryption_key="$(milou_generate_secure_random 64 "hex")"
    fi
    
    # Generate comprehensive environment file based on centralized validation requirements
    cat > "$env_file" << EOF
# =============================================================================
# Milou CLI Configuration - Complete Production Environment
# Generated on: $(date)
# Installation Type: $([ "$is_fresh_install" == "true" ] && echo "Fresh Install" || echo "Existing Installation Update")
# Credentials: $([ "$preserve_existing_credentials" == "true" ] && echo "Preserved" || echo "Newly Generated")
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
SSL_CERT_PATH=${SSL_CERT_PATH:-./ssl}
SSL_KEY_PATH=${SSL_KEY_PATH:-./ssl}
SSL_CERT_FILE=${SSL_CERT_FILE:-./ssl/milou.crt}
SSL_KEY_FILE=${SSL_KEY_FILE:-./ssl/milou.key}

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
RABBITMQ_HOST=rabbitmq
RABBITMQ_PORT=5672
RABBITMQ_VHOST=/
RABBITMQ_ERLANG_COOKIE=milou-cookie

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

# =============================================================================
# DOCKER IMAGE CONFIGURATION
# =============================================================================
EOF

    # DYNAMIC: Add Docker image tags based on user selection during configuration
    local image_tag="${MILOU_IMAGE_TAG:-latest}"
    local use_latest="${USE_LATEST_IMAGES:-true}"

    # If no specific tag was chosen during interactive setup, fall back to use_latest flag
    if [[ "$image_tag" == "latest" && "$use_latest" != "true" ]]; then
        image_tag="v1.0.0"  # Default stable version for non-latest preference
    fi

    milou_log "DEBUG" "Generating image tags with MILOU_IMAGE_TAG=$image_tag, USE_LATEST_IMAGES=$use_latest"

    # Generate image configuration with dynamic tag
    cat >> "$env_file" << EOF
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
    chmod 600 "$env_file"
    
    milou_log "SUCCESS" "✅ Configuration saved successfully"
    milou_log "INFO" "📍 Configuration file: $env_file"
    milou_log "WARN" "🔒 File permissions set to 600 for security"
    
    # Log credential management summary
    if [[ "$preserve_existing_credentials" == "true" ]]; then
        milou_log "SUCCESS" "🔒 Existing credentials preserved - data integrity maintained"
    else
        milou_log "INFO" "🆕 New credentials generated"
        if [[ "$is_fresh_install" != "true" ]]; then
            milou_log "WARN" "⚠️  If you have existing data, it may become inaccessible"
        fi
    fi
    
    return 0
}

# Perform clean installation (remove all existing data)
_perform_clean_installation() {
    milou_log "STEP" "🧹 Performing Clean Installation"
    
    # Stop all running containers
    milou_log "INFO" "🛑 Stopping all Milou containers..."
    if command -v docker >/dev/null 2>&1; then
        # Try multiple project naming conventions
        local project_names=("static" "milou-static" "milou")
        for project in "${project_names[@]}"; do
            docker compose -p "$project" down --remove-orphans 2>/dev/null || true
        done
        
        # Force stop any remaining containers
        docker ps -a --filter "name=milou" --format "{{.Names}}" | xargs -r docker stop 2>/dev/null || true
        docker ps -a --filter "name=static" --format "{{.Names}}" | xargs -r docker stop 2>/dev/null || true
    fi
    
    # Remove all volumes
    milou_log "INFO" "🗑️  Removing all data volumes..."
    local volumes_removed=0
    
    # Standard volume names
    local -a volume_patterns=(
        "static_pgdata"
        "static_redis_data" 
        "static_rabbitmq_data"
        "static_rabbitmq_logs"
        "static_backend_logs"
        "static_engine_logs"
        "static_engine_cache"
        "static_engine_models"
        "static_uploads"
        "static_nginx_logs"
        "static_nginx_cache"
        "static_prometheus_data"
        "milou-static_pgdata"
        "milou-static_redis_data"
        "milou-static_rabbitmq_data"
        "milou_pgdata"
        "milou_redis_data"
        "milou_rabbitmq_data"
    )
    
    for volume in "${volume_patterns[@]}"; do
        if docker volume inspect "$volume" >/dev/null 2>&1; then
            if docker volume rm "$volume" 2>/dev/null; then
                milou_log "DEBUG" "Removed volume: $volume"
                ((volumes_removed++))
            else
                milou_log "WARN" "Failed to remove volume: $volume"
            fi
        fi
    done
    
    # Remove any additional volumes with milou/static in the name
    local additional_volumes
    additional_volumes=$(docker volume ls --filter "name=milou" --format "{{.Name}}" 2>/dev/null || true)
    additional_volumes+=" $(docker volume ls --filter "name=static" --format "{{.Name}}" 2>/dev/null || true)"
    
    for volume in $additional_volumes; do
        if [[ -n "$volume" ]] && docker volume inspect "$volume" >/dev/null 2>&1; then
            if docker volume rm "$volume" 2>/dev/null; then
                milou_log "DEBUG" "Removed additional volume: $volume"
                ((volumes_removed++))
            fi
        fi
    done
    
    # Remove containers
    milou_log "INFO" "🗑️  Removing all containers..."
    local containers_removed=0
    
    local containers
    containers=$(docker ps -a --filter "name=milou" --filter "name=static" --format "{{.Names}}" 2>/dev/null || true)
    
    if [[ -n "$containers" ]]; then
        echo "$containers" | while IFS= read -r container; do
            if [[ -n "$container" ]]; then
                if docker rm -f "$container" 2>/dev/null; then
                    milou_log "DEBUG" "Removed container: $container"
                    ((containers_removed++))
                fi
            fi
        done
    fi
    
    # Remove networks
    milou_log "INFO" "🗑️  Removing Milou networks..."
    local networks
    networks=$(docker network ls --filter "name=milou" --filter "name=static" --format "{{.Name}}" 2>/dev/null || true)
    
    if [[ -n "$networks" ]]; then
        echo "$networks" | while IFS= read -r network; do
            if [[ -n "$network" && "$network" != "bridge" && "$network" != "host" && "$network" != "none" ]]; then
                docker network rm "$network" 2>/dev/null || true
            fi
        done
    fi
    
    # Remove SSL certificates if requested
    if [[ -d "./ssl" ]]; then
        if milou_confirm "Also remove SSL certificates? (You can regenerate them)" "Y"; then
            rm -rf "./ssl"
            milou_log "INFO" "🗑️  SSL certificates removed"
        fi
    fi
    
    milou_log "SUCCESS" "🧹 Clean installation completed"
    milou_log "INFO" "   • Volumes removed: $volumes_removed"
    milou_log "INFO" "   • System ready for fresh installation"
    
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
    
    # Generate PostgreSQL credentials (critical for database setup)
    local config_postgres_user="${POSTGRES_USER:-milou_user_$(milou_generate_secure_random 8 "alphanumeric")}"
    local config_postgres_password="${POSTGRES_PASSWORD:-$(milou_generate_secure_random 32 "safe")}"
    local config_postgres_db="${POSTGRES_DB:-milou_database}"
    
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
    
    # Set PostgreSQL credentials
    POSTGRES_USER="$config_postgres_user"
    POSTGRES_PASSWORD="$config_postgres_password"
    POSTGRES_DB="$config_postgres_db"
    
    # Set Docker version variables for non-interactive mode
    USE_LATEST_IMAGES="${USE_LATEST_IMAGES:-true}"
    MILOU_IMAGE_TAG="${MILOU_IMAGE_TAG:-latest}"
    
    # Save to file
    _save_configuration_to_env
}

# Smart configuration with prompts only when needed
_run_smart_configuration() {
    milou_log "INFO" "🧠 Running smart configuration (automated with targeted prompts)"
    echo
    
    # Use environment variables if available, otherwise use smart defaults
    DOMAIN="${DOMAIN:-localhost}"
    ADMIN_EMAIL="${ADMIN_EMAIL:-admin@localhost}"
    ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
    
    # Only prompt for essential missing information
    local need_prompts=false
    
    # Check if we need admin password
    if [[ -z "${ADMIN_PASSWORD:-}" ]]; then
        ADMIN_PASSWORD=$(milou_generate_secure_random 16)
        milou_log "INFO" "🔑 Generated secure admin password: $ADMIN_PASSWORD"
        milou_log "WARN" "⚠️  Save this password securely!"
        need_prompts=true
    fi
    
    # Generate secure defaults for missing items
    JWT_SECRET="${JWT_SECRET:-$(milou_generate_secure_random 32)}"
    DB_PASSWORD="${DB_PASSWORD:-$(milou_generate_secure_random 16)}"
    SSL_MODE="${SSL_MODE:-generate}"
    HTTP_PORT="${HTTP_PORT:-80}"
    HTTPS_PORT="${HTTPS_PORT:-443}"
    
    # Validate smart configuration
    if ! _validate_collected_configuration; then
        milou_log "ERROR" "Smart configuration validation failed"
        return 1
    fi
    
    # Save configuration
    _save_configuration_to_env || return 1
    
    if [[ "$need_prompts" == "true" ]]; then
        milou_log "SUCCESS" "✅ Smart configuration completed (some values auto-generated)"
    else
        milou_log "SUCCESS" "✅ Smart configuration completed (using provided values)"
    fi
    
    return 0
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
export -f _run_smart_configuration
export -f _perform_clean_installation
export -f _collect_docker_version_configuration 