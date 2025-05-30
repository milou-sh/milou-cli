#!/bin/bash

# =============================================================================
# Milou CLI - Unified Validation Module
# Consolidated validation system to eliminate code duplication
# Version: 4.0.0 - State-Based Architecture
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Module guard to prevent multiple loading
if [[ "${MILOU_VALIDATION_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_VALIDATION_LOADED="true"

# Ensure core modules are loaded
if [[ "${MILOU_CORE_LOADED:-}" != "true" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/_core.sh" || {
        echo "ERROR: Cannot load core module" >&2
        return 1
    }
fi

# =============================================================================
# UNIFIED SYSTEM VALIDATION
# =============================================================================

# Master validation function - consolidates all duplicate logic
validate_system_dependencies() {
    local mode="${1:-basic}"           # basic, install, update, resume
    local installation_state="${2:-unknown}"
    local quiet="${3:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Running system validation (mode: $mode, state: $installation_state)"
    
    local errors=0
    local warnings=0
    
    # Mode-specific validation
    case "$mode" in
        "basic")
            # Just check if Docker is accessible
            if ! _validate_docker_basic "$quiet"; then
                ((errors++))
            fi
            ;;
        "install")
            # Full validation for fresh installation
            if ! _validate_docker_complete "$quiet"; then
                ((errors++))
            fi
            if ! _validate_system_tools "$quiet"; then
                ((warnings++))  # System tools are warnings, not errors
            fi
            ;;
        "update"|"resume")
            # Check Docker + existing installation components
            if ! _validate_docker_basic "$quiet"; then
                ((errors++))
            fi
            if [[ "$installation_state" == *"configured"* ]] || [[ "$installation_state" == *"running"* ]]; then
                if ! _validate_existing_installation "$quiet"; then
                    ((warnings++))
                fi
            fi
            ;;
        "repair")
            # Comprehensive validation for repair mode
            if ! _validate_docker_complete "$quiet"; then
                ((errors++))
            fi
            if ! _validate_existing_installation "$quiet"; then
                ((warnings++))  # Existing installation issues are expected in repair
            fi
            ;;
        *)
            [[ "$quiet" != "true" ]] && milou_log "WARN" "Unknown validation mode: $mode"
            if ! _validate_docker_basic "$quiet"; then
                ((errors++))
            fi
            ;;
    esac
    
    # Report results
    if [[ $errors -eq 0 ]]; then
        if [[ $warnings -eq 0 ]]; then
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "System validation passed"
        else
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "System validation passed with $warnings warning(s)"
        fi
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "System validation failed with $errors error(s)"
        return 1
    fi
}

# =============================================================================
# INTERNAL VALIDATION FUNCTIONS
# =============================================================================

# Basic Docker validation - minimal requirements
_validate_docker_basic() {
    local quiet="${1:-false}"
    
    # Check if Docker command exists
    if ! command -v docker >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Docker is not installed"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Install Docker: https://docs.docker.com/get-docker/"
        return 1
    fi
    
    # Check daemon access
    if ! docker info >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Cannot access Docker daemon"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Try: sudo systemctl start docker"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Try: sudo usermod -aG docker \$USER && newgrp docker"
        return 1
    fi
    
    # Check Docker Compose
    if ! docker compose version >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Docker Compose not available"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Update Docker to get the compose plugin"
        return 1
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "TRACE" "Docker basic validation passed"
    return 0
}

# Complete Docker validation - includes permissions and resources
_validate_docker_complete() {
    local quiet="${1:-false}"
    
    # Run basic validation first
    if ! _validate_docker_basic "$quiet"; then
        return 1
    fi
    
    local warnings=0
    
    # Check user permissions
    if [[ $EUID -ne 0 ]] && ! groups | grep -q docker 2>/dev/null; then
        [[ "$quiet" != "true" ]] && milou_log "WARN" "User not in docker group"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Add user to docker group: sudo usermod -aG docker \$USER"
        ((warnings++))
    fi
    
    # Check basic connectivity
    if command -v curl >/dev/null 2>&1; then
        if ! curl -s --max-time 5 "https://ghcr.io/v2/" >/dev/null 2>&1; then
            [[ "$quiet" != "true" ]] && milou_log "WARN" "Container registry not accessible"
            [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Check network connectivity"
            ((warnings++))
        fi
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "TRACE" "Docker complete validation passed (warnings: $warnings)"
    return 0
}

# System tools validation - checks for useful but not critical tools
_validate_system_tools() {
    local quiet="${1:-false}"
    
    local missing_tools=()
    local recommended_tools=("curl" "wget" "jq" "openssl")
    
    for tool in "${recommended_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -eq 0 ]]; then
        [[ "$quiet" != "true" ]] && milou_log "TRACE" "All recommended tools available"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "WARN" "Missing recommended tools: ${missing_tools[*]}"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 These can be installed during setup if needed"
        return 1
    fi
}

# Existing installation validation
_validate_existing_installation() {
    local quiet="${1:-false}"
    
    local issues=()
    
    # Check for configuration file
    if [[ ! -f "${SCRIPT_DIR:-$(pwd)}/.env" ]]; then
        issues+=("missing .env file")
    fi
    
    # Check for Docker Compose file
    if [[ ! -f "${SCRIPT_DIR:-$(pwd)}/static/docker-compose.yml" ]]; then
        issues+=("missing docker-compose.yml")
    fi
    
    # Validate configuration using consolidated function
    if [[ -f "${SCRIPT_DIR:-$(pwd)}/.env" && -f "${SCRIPT_DIR:-$(pwd)}/static/docker-compose.yml" ]]; then
        if command -v docker_execute >/dev/null 2>&1; then
            # Initialize docker context to ensure proper validation
            if command -v initialize_docker_context >/dev/null 2>&1; then
                initialize_docker_context "${SCRIPT_DIR:-$(pwd)}/.env" "${SCRIPT_DIR:-$(pwd)}/static/docker-compose.yml" "true"
            fi
            
            if ! docker_execute "validate" "" "true"; then
                issues+=("invalid Docker Compose configuration")
            fi
        else
            # Fallback validation
            if ! docker compose --env-file "${SCRIPT_DIR:-$(pwd)}/.env" \
                               -f "${SCRIPT_DIR:-$(pwd)}/static/docker-compose.yml" \
                               config --quiet 2>/dev/null; then
                issues+=("invalid Docker Compose configuration")
            fi
        fi
    fi
    
    if [[ ${#issues[@]} -eq 0 ]]; then
        [[ "$quiet" != "true" ]] && milou_log "TRACE" "Existing installation validation passed"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "WARN" "Installation issues: ${issues[*]}"
        return 1
    fi
}

# =============================================================================
# LEGACY COMPATIBILITY FUNCTIONS - SIMPLIFIED
# =============================================================================

# Essential legacy functions (simplified versions)
validate_docker_access() {
    local check_daemon="${1:-true}"
    local check_permissions="${2:-true}"
    local check_compose="${3:-true}"
    local quiet="${4:-false}"
    
    if [[ "$check_permissions" == "true" ]]; then
        validate_system_dependencies "install" "unknown" "$quiet"
    else
        validate_system_dependencies "basic" "unknown" "$quiet"
    fi
}

validate_docker_resources() {
    local quiet="${1:-false}"
    validate_system_dependencies "basic" "unknown" "$quiet"
}

validate_docker_compose_config() {
    local env_file="${1:-${SCRIPT_DIR:-$(pwd)}/.env}"
    local compose_file="${2:-${SCRIPT_DIR:-$(pwd)}/static/docker-compose.yml}"
    local quiet="${3:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "🔍 Validating Docker Compose configuration"
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "  Environment: $env_file"
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "  Compose file: $compose_file"
    
    # Use consolidated validation if available
    if command -v docker_execute >/dev/null 2>&1; then
        # Initialize docker context with specific files
        if command -v initialize_docker_context >/dev/null 2>&1; then
            if initialize_docker_context "$env_file" "$compose_file" "$quiet"; then
                if docker_execute "validate" "" "$quiet"; then
                    [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Docker Compose configuration is valid"
                    return 0
                else
                    [[ "$quiet" != "true" ]] && milou_log "ERROR" "❌ Docker Compose configuration is invalid"
                    return 1
                fi
            else
                [[ "$quiet" != "true" ]] && milou_log "ERROR" "❌ Failed to initialize Docker context"
                return 1
            fi
        else
            [[ "$quiet" != "true" ]] && milou_log "WARN" "Docker context initialization not available, using direct validation"
        fi
    fi
    
    # Fallback to direct validation
    if docker compose --env-file "$env_file" -f "$compose_file" config --quiet 2>/dev/null; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Docker Compose configuration is valid"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "❌ Docker Compose configuration is invalid"
        return 1
    fi
}

# Legacy aliases (will be removed in future versions)
milou_check_docker_access() { validate_docker_access "$@"; }
milou_validate_docker_compose_config() { validate_docker_compose_config "$@"; }

# =============================================================================
# GITHUB TOKEN VALIDATION (Consolidated from 3+ implementations)
# =============================================================================

# Validate GitHub token format - SINGLE AUTHORITATIVE IMPLEMENTATION
validate_github_token() {
    local token="$1"
    local strict="${2:-true}"
    
    if [[ -z "$token" ]]; then
        milou_log "ERROR" "GitHub token is required"
        return 1
    fi
    
    # Enhanced GitHub token patterns for different types
    local token_valid=false
    
    # Personal Access Token (classic): ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx (40 chars total)
    if [[ "$token" =~ ^ghp_[A-Za-z0-9]{36}$ ]]; then
        token_valid=true
    # OAuth App token: gho_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx  
    elif [[ "$token" =~ ^gho_[A-Za-z0-9]{36}$ ]]; then
        token_valid=true
    # User access token: ghu_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    elif [[ "$token" =~ ^ghu_[A-Za-z0-9]{36}$ ]]; then
        token_valid=true
    # Server access token: ghs_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    elif [[ "$token" =~ ^ghs_[A-Za-z0-9]{36}$ ]]; then
        token_valid=true
    # Refresh token: ghr_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    elif [[ "$token" =~ ^ghr_[A-Za-z0-9]{36}$ ]]; then
        token_valid=true
    # Fine-grained personal access token: github_pat_xxxxxxxxxx (much longer)
    elif [[ "$token" =~ ^github_pat_[A-Za-z0-9_]{22,255}$ ]]; then
        token_valid=true
    fi
    
    if [[ "$token_valid" != "true" ]]; then
        milou_log "ERROR" "Invalid GitHub token format"
        milou_log "INFO" "Expected patterns:"
        milou_log "INFO" "  • Classic PAT: ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx (40 chars)"
        milou_log "INFO" "  • Fine-grained: github_pat_xxxxxxxxxxxxxxxxxxxx (longer)"
        milou_log "INFO" "  • OAuth: gho_*, User: ghu_*, Server: ghs_*, Refresh: ghr_*"
        
        if [[ "$strict" == "true" ]]; then
            return 1
        else
            milou_log "WARN" "Token format validation failed but continuing in non-strict mode"
        fi
    fi
    
    milou_log "TRACE" "GitHub token format validation passed"
    return 0
}

# Test GitHub authentication with API and Docker registry
test_github_authentication() {
    local token="$1"
    local quiet="${2:-false}"
    local test_registry="${3:-true}"
    
    if ! validate_github_token "$token"; then
        return 1
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "STEP" "Testing GitHub authentication..."
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Token validation: length=${#token}, preview=${token:0:10}..."
    
    # Test authentication with GitHub API first
    local api_base="${GITHUB_API_BASE:-https://api.github.com}"
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Testing API call to: $api_base/user"
    
    local response
    local curl_error
    curl_error=$(mktemp)
    
    # Disable errexit temporarily to capture curl errors properly
    set +e
    response=$(curl -s -H "Authorization: Bearer $token" \
               -H "Accept: application/vnd.github.v3+json" \
               "$api_base/user" 2>"$curl_error")
    local curl_exit_code=$?
    set -e
    
    if [[ $curl_exit_code -ne 0 ]]; then
        milou_log "ERROR" "Failed to connect to GitHub API"
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "curl command failed with exit code: $curl_exit_code"
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "curl stderr: $(cat "$curl_error" 2>/dev/null || echo 'no error output')"
        rm -f "$curl_error"
        return 1
    fi
    
    rm -f "$curl_error"
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "API call succeeded, response length: ${#response}"
    
    # Check if authentication was successful
    local username=""
    if echo "$response" | grep -q '"login"'; then
        username=$(echo "$response" | grep -o '"login": *"[^"]*"' | cut -d'"' -f4)
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "GitHub API authentication successful (user: $username)"
        
        # Test Docker registry authentication if requested
        if [[ "$test_registry" == "true" ]]; then
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Testing Docker registry authentication..."
            if echo "$token" | docker login ghcr.io -u "${username:-token}" --password-stdin >/dev/null 2>&1; then
                [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "Docker registry authentication successful"
                docker logout ghcr.io >/dev/null 2>&1
                return 0
            else
                milou_log "ERROR" "Docker registry authentication failed"
                milou_log "INFO" "💡 Ensure your token has 'read:packages' and 'write:packages' scopes"
                return 1
            fi
        else
            return 0
        fi
    else
        milou_log "ERROR" "GitHub API authentication failed"
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "API Response: $response"
        
        # Check for specific error messages
        if echo "$response" | grep -q "Bad credentials"; then
            milou_log "INFO" "💡 The provided token is invalid or expired"
        elif echo "$response" | grep -q "rate limit"; then
            milou_log "INFO" "💡 GitHub API rate limit exceeded, try again later"
        fi
        
        return 1
    fi
}

# Legacy aliases for backwards compatibility (will be removed after refactoring)
milou_validate_github_token() {
    validate_github_token "$@"
}

milou_test_github_authentication() {
    test_github_authentication "$@"
}

# =============================================================================
# ENVIRONMENT VALIDATION (Consolidated from lib/config/validation.sh)
# =============================================================================

# Get required environment variables for different contexts
get_required_environment_variables() {
    local context="${1:-production}"  # minimal, production, all
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

# Validate environment file against requirements
validate_environment() {
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
    readarray -t required_vars < <(get_required_environment_variables "$context")
    
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

# Legacy aliases for backwards compatibility (will be removed after refactoring)
milou_config_validate_environment_production() {
    validate_environment "$1" "production" "true"
}

milou_config_validate_environment_essential() {
    validate_environment "$1" "minimal" "true"
}

# =============================================================================
# NETWORK VALIDATION
# =============================================================================

# Check if port is available
validate_port_availability() {
    local port="$1"
    local host="${2:-localhost}"
    local quiet="${3:-false}"
    
    if [[ ! "$port" =~ ^[1-9][0-9]{0,4}$ ]] || [[ "$port" -gt 65535 ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Invalid port number: $port (must be 1-65535)"
        return 1
    fi
    
    if command -v ss >/dev/null 2>&1; then
        if ss -tuln | grep -q ":$port "; then
            [[ "$quiet" != "true" ]] && milou_log "WARN" "Port $port is already in use"
            return 1
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tuln | grep -q ":$port "; then
            [[ "$quiet" != "true" ]] && milou_log "WARN" "Port $port is already in use"
            return 1
        fi
    else
        # Fallback: try to connect
        if timeout 1 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
            [[ "$quiet" != "true" ]] && milou_log "WARN" "Port $port appears to be in use"
            return 1
        fi
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "TRACE" "Port $port is available"
    return 0
}

# Network connectivity check
test_connectivity() {
    local host="${1:-8.8.8.8}"
    local port="${2:-53}"
    local timeout="${3:-5}"
    local quiet="${4:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "TRACE" "Testing connectivity to $host:$port (timeout: ${timeout}s)"
    
    # Try multiple methods
    if command -v nc >/dev/null 2>&1; then
        if timeout "$timeout" nc -z "$host" "$port" 2>/dev/null; then
            [[ "$quiet" != "true" ]] && milou_log "TRACE" "Connectivity check passed (nc)"
            return 0
        fi
    fi
    
    if command -v curl >/dev/null 2>&1; then
        if curl -s --connect-timeout "$timeout" --max-time "$timeout" "http://$host:$port" >/dev/null 2>&1; then
            [[ "$quiet" != "true" ]] && milou_log "TRACE" "Connectivity check passed (curl)"
            return 0
        fi
    fi
    
    if timeout "$timeout" bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
        [[ "$quiet" != "true" ]] && milou_log "TRACE" "Connectivity check passed (bash tcp)"
        return 0
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "TRACE" "Connectivity check failed for $host:$port"
    return 1
}

# Legacy aliases for backwards compatibility (will be removed after refactoring)
milou_check_port_availability() {
    validate_port_availability "$@"
}

milou_check_connectivity() {
    test_connectivity "$@"
}

# =============================================================================
# EXPORT ESSENTIAL FUNCTIONS ONLY
# =============================================================================

# Core validation functions (no aliases needed)
export -f validate_system_dependencies
export -f validate_docker_access
export -f validate_docker_compose_config
export -f validate_github_token
export -f test_github_authentication
export -f validate_environment
export -f validate_port_availability
export -f test_connectivity

milou_log "DEBUG" "Validation module loaded successfully" 