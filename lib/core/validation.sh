#!/bin/bash

# =============================================================================
# Centralized Validation Module for Milou CLI
# Consolidates all validation functions from across the codebase
# =============================================================================

# Ensure logging is available
if ! command -v milou_log >/dev/null 2>&1; then
    source "${SCRIPT_DIR}/lib/core/logging.sh" 2>/dev/null || {
        echo "ERROR: Cannot load logging module" >&2
        exit 1
    }
fi

# =============================================================================
# GitHub Token Validation (consolidates 3 implementations)
# =============================================================================

# Validate GitHub token format (enhanced version)
milou_validate_github_token() {
    local token="$1"
    local strict="${2:-true}"
    
    if [[ -z "$token" ]]; then
        milou_log "ERROR" "GitHub token is required"
        return 1
    fi
    
    # Enhanced GitHub token patterns including fine-grained tokens
    if [[ ! "$token" =~ ^gh[pousr]_[A-Za-z0-9_]{36,251}$ ]]; then
        milou_log "ERROR" "Invalid GitHub token format"
        milou_log "INFO" "Expected patterns: ghp_*, gho_*, ghu_*, ghs_*, ghr_*"
        milou_log "INFO" "Token should be 40+ characters long"
        
        if [[ "$strict" == "true" ]]; then
            return 1
        else
            milou_log "WARN" "Token format validation failed but continuing in non-strict mode"
        fi
    fi
    
    milou_log "TRACE" "GitHub token format validation passed"
    return 0
}

# Test GitHub authentication (ENHANCED - consolidates multiple implementations)
milou_test_github_authentication() {
    local token="$1"
    local quiet="${2:-false}"
    local test_registry="${3:-true}"
    
    if ! milou_validate_github_token "$token"; then
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

# =============================================================================
# Domain and Network Validation
# =============================================================================

# Enhanced domain validation
milou_validate_domain() {
    local domain="$1"
    local allow_localhost="${2:-true}"
    
    if [[ -z "$domain" ]]; then
        milou_log "ERROR" "Domain is required"
        return 1
    fi
    
    # Allow localhost if specified
    if [[ "$allow_localhost" == "true" && "$domain" == "localhost" ]]; then
        return 0
    fi
    
    # Basic domain format validation
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        milou_log "ERROR" "Invalid domain format: $domain"
        return 1
    fi
    
    # Length validation
    if [[ ${#domain} -gt 253 ]]; then
        milou_log "ERROR" "Domain name too long (max 253 characters): ${#domain}"
        return 1
    fi
    
    # Check for invalid characters
    if [[ "$domain" =~ [^a-zA-Z0-9.-] ]]; then
        milou_log "ERROR" "Domain contains invalid characters: $domain"
        return 1
    fi
    
    milou_log "TRACE" "Domain validation passed: $domain"
    return 0
}

# Network connectivity check
milou_check_connectivity() {
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
    
    if command -v telnet >/dev/null 2>&1; then
        if timeout "$timeout" bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
            [[ "$quiet" != "true" ]] && milou_log "TRACE" "Connectivity check passed (bash tcp)"
            return 0
        fi
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "TRACE" "Connectivity check failed for $host:$port"
    return 1
}

# =============================================================================
# Docker Validation (consolidates 5+ implementations)
# =============================================================================

# Check Docker installation and accessibility (ENHANCED - consolidates 6+ implementations)
milou_check_docker_access() {
    local check_daemon="${1:-true}"
    local check_permissions="${2:-true}"
    local check_compose="${3:-true}"
    local quiet="${4:-false}"
    
    local errors=0
    
    # Check if Docker command exists
    if ! command -v docker >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Docker is not installed"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Install Docker: https://docs.docker.com/get-docker/"
        ((errors++))
    fi
    
    # Check daemon access
    if [[ "$check_daemon" == "true" ]]; then
        if ! docker info >/dev/null 2>&1; then
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "Cannot access Docker daemon"
            [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Try: sudo systemctl start docker"
            [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Try: sudo usermod -aG docker \$USER && newgrp docker"
            ((errors++))
        else
            [[ "$quiet" != "true" ]] && milou_log "TRACE" "Docker daemon accessible"
        fi
    fi
    
    # Check user permissions
    if [[ "$check_permissions" == "true" ]]; then
        if [[ $EUID -ne 0 ]] && ! groups | grep -q docker; then
            [[ "$quiet" != "true" ]] && milou_log "WARN" "User not in docker group"
            [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Add user to docker group: sudo usermod -aG docker \$USER"
            ((errors++))
        else
            [[ "$quiet" != "true" ]] && milou_log "TRACE" "Docker permissions OK"
        fi
    fi
    
    # Check Docker Compose
    if [[ "$check_compose" == "true" ]]; then
        if ! docker compose version >/dev/null 2>&1; then
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "Docker Compose not available"
            [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Update Docker to get the compose plugin"
            ((errors++))
        else
            [[ "$quiet" != "true" ]] && milou_log "TRACE" "Docker Compose available"
        fi
    fi
    
    if [[ $errors -eq 0 ]]; then
        [[ "$quiet" != "true" ]] && milou_log "TRACE" "Docker access validation passed"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Docker validation failed with $errors error(s)"
        return 1
    fi
}

# Check Docker Compose availability
milou_check_docker_compose() {
    local quiet="${1:-false}"
    
    if ! docker compose version >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Docker Compose plugin is not available"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Update Docker to get the compose plugin"
        return 1
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "TRACE" "Docker Compose validation passed"
    return 0
}

# Check Docker resource usage and system health (consolidates resource checking)
milou_check_docker_resources() {
    local check_disk="${1:-true}"
    local check_memory="${2:-true}"
    local check_connectivity="${3:-true}"
    local quiet="${4:-false}"
    
    local warnings=0
    
    if ! docker info >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Docker daemon not accessible for resource checking"
        return 1
    fi
    
    # Check disk usage
    if [[ "$check_disk" == "true" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Checking Docker disk usage..."
        if docker system df >/dev/null 2>&1; then
            local disk_usage
            disk_usage=$(docker system df 2>/dev/null)
            
            # Extract total size and check if cleanup is needed
            local total_size
            total_size=$(echo "$disk_usage" | grep "Total" | awk '{print $3}' | sed 's/[^0-9.]//g' 2>/dev/null || echo "0")
            if [[ -n "$total_size" ]] && command -v bc >/dev/null 2>&1; then
                if (( $(echo "$total_size > 10" | bc -l 2>/dev/null || echo "0") )); then
                    [[ "$quiet" != "true" ]] && milou_log "WARN" "Docker using significant disk space (${total_size}GB)"
                    [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Consider running: docker system prune -f"
                    ((warnings++))
                fi
            fi
        else
            [[ "$quiet" != "true" ]] && milou_log "WARN" "Cannot check Docker disk usage"
            ((warnings++))
        fi
    fi
    
    # Check memory usage of running containers
    if [[ "$check_memory" == "true" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Checking container memory usage..."
        local container_count
        container_count=$(docker ps --format "{{.Names}}" 2>/dev/null | wc -l || echo "0")
        
        if [[ "$container_count" -gt 0 ]]; then
            [[ "$quiet" != "true" ]] && milou_log "TRACE" "Found $container_count running containers"
            
            # Check for containers using excessive memory (basic check)
            if docker stats --no-stream --format "{{.MemUsage}}" >/dev/null 2>&1; then
                [[ "$quiet" != "true" ]] && milou_log "TRACE" "Container memory stats accessible"
            else
                [[ "$quiet" != "true" ]] && milou_log "WARN" "Cannot access container memory stats"
                ((warnings++))
            fi
        else
            [[ "$quiet" != "true" ]] && milou_log "TRACE" "No running containers found"
        fi
    fi
    
    # Check network connectivity to registries
    if [[ "$check_connectivity" == "true" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Checking registry connectivity..."
        if command -v curl >/dev/null 2>&1; then
            # Test GitHub Container Registry
            local ghcr_response
            ghcr_response=$(curl -s -o /dev/null -w "%{http_code}" "https://ghcr.io/v2/" 2>/dev/null || echo "000")
            if [[ "$ghcr_response" == "200" || "$ghcr_response" == "401" ]]; then
                [[ "$quiet" != "true" ]] && milou_log "TRACE" "GitHub Container Registry accessible"
            else
                [[ "$quiet" != "true" ]] && milou_log "WARN" "GitHub Container Registry not accessible (HTTP: $ghcr_response)"
                ((warnings++))
            fi
            
            # Test Docker Hub connectivity
            local dockerhub_response
            dockerhub_response=$(curl -s -o /dev/null -w "%{http_code}" "https://registry-1.docker.io/v2/" 2>/dev/null || echo "000")
            if [[ "$dockerhub_response" == "200" || "$dockerhub_response" == "401" ]]; then
                [[ "$quiet" != "true" ]] && milou_log "TRACE" "Docker Hub accessible"
            else
                [[ "$quiet" != "true" ]] && milou_log "WARN" "Docker Hub not accessible (HTTP: $dockerhub_response)"
                ((warnings++))
            fi
        else
            [[ "$quiet" != "true" ]] && milou_log "WARN" "curl not available for connectivity testing"
            ((warnings++))
        fi
    fi
    
    if [[ $warnings -eq 0 ]]; then
        [[ "$quiet" != "true" ]] && milou_log "TRACE" "Docker resource check passed"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "WARN" "Docker resource check completed with $warnings warning(s)"
        return 0  # Return 0 for warnings, 1 only for critical errors
    fi
}

# Validate Docker Compose configuration
milou_validate_docker_compose_config() {
    local env_file="$1"
    local compose_file="$2"
    local quiet="${3:-false}"
    
    if [[ ! -f "$env_file" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Environment file not found: $env_file"
        return 1
    fi
    
    if [[ ! -f "$compose_file" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Compose file not found: $compose_file"
        return 1
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Testing Docker Compose configuration..."
    
    if docker compose --env-file "$env_file" -f "$compose_file" config --quiet; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "Docker Compose configuration is valid"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Docker Compose configuration is invalid"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Check your environment file: $env_file"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Check your compose file: $compose_file"
        return 1
    fi
}

# =============================================================================
# System Validation (consolidates 8+ implementations)
# =============================================================================

# Check if command exists
milou_command_exists() {
    local cmd="$1"
    local quiet="${2:-true}"
    
    if command -v "$cmd" >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "TRACE" "Command '$cmd' is available"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "TRACE" "Command '$cmd' is not available"
        return 1
    fi
}

# Enhanced version comparison
milou_version_compare() {
    local version1="$1"
    local version2="$2"
    local operator="${3:-ge}"
    
    # Input validation
    if [[ -z "$version1" || -z "$version2" ]]; then
        milou_log "ERROR" "Version comparison requires two version strings"
        return 2
    fi
    
    # Normalize versions (handle v prefix and clean up)
    version1="${version1#v}"
    version2="${version2#v}"
    version1="${version1//[^0-9.]/}"
    version2="${version2//[^0-9.]/}"
    
    milou_log "TRACE" "Comparing versions: '$version1' $operator '$version2'"
    
    case "$operator" in
        "ge"|">=") 
            printf '%s\n%s\n' "$version2" "$version1" | sort -V -C
            ;;
        "gt"|">")  
            [[ "$version1" != "$version2" ]] && printf '%s\n%s\n' "$version2" "$version1" | sort -V -C
            ;;
        "le"|"<=") 
            printf '%s\n%s\n' "$version1" "$version2" | sort -V -C
            ;;
        "lt"|"<")  
            [[ "$version1" != "$version2" ]] && printf '%s\n%s\n' "$version1" "$version2" | sort -V -C
            ;;
        "eq"|"==") 
            [[ "$version1" == "$version2" ]]
            ;;
        *) 
            milou_log "ERROR" "Invalid operator: $operator (use: ge, gt, le, lt, eq)"
            return 2
            ;;
    esac
}

# Check port availability
milou_check_port_availability() {
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

# =============================================================================
# SSL Validation (consolidates 3+ implementations)
# =============================================================================

# Validate SSL certificates
milou_validate_ssl_certificates() {
    local ssl_path="$1"
    local domain="${2:-}"
    local quiet="${3:-false}"
    
    if [[ ! -d "$ssl_path" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "SSL directory does not exist: $ssl_path"
        return 1
    fi
    
    local cert_file="$ssl_path/milou.crt"
    local key_file="$ssl_path/milou.key"
    
    if [[ ! -f "$cert_file" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "SSL certificate not found: $cert_file"
        return 1
    fi
    
    if [[ ! -f "$key_file" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "SSL private key not found: $key_file"
        return 1
    fi
    
    # Validate certificate format
    if command -v openssl >/dev/null 2>&1; then
        if ! openssl x509 -in "$cert_file" -noout -text >/dev/null 2>&1; then
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "Invalid SSL certificate format"
            return 1
        fi
        
        if ! openssl rsa -in "$key_file" -check -noout >/dev/null 2>&1; then
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "Invalid SSL private key format"
            return 1
        fi
        
        # Check if certificate matches domain
        if [[ -n "$domain" && "$domain" != "localhost" ]]; then
            local cert_subject
            cert_subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | grep -o 'CN=[^,]*' | cut -d'=' -f2 | tr -d ' ')
            if [[ "$cert_subject" != "$domain" ]]; then
                [[ "$quiet" != "true" ]] && milou_log "WARN" "Certificate subject ($cert_subject) does not match domain ($domain)"
                # Don't fail for this, just warn
            fi
        fi
        
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "SSL certificates are valid"
    else
        [[ "$quiet" != "true" ]] && milou_log "WARN" "OpenSSL not available for certificate validation"
    fi
    
    return 0
}

# =============================================================================
# User and Permission Validation
# =============================================================================

# Check if running as root
milou_is_running_as_root() {
    [[ $EUID -eq 0 ]]
}

# Check if user exists
milou_user_exists() {
    local username="$1"
    getent passwd "$username" >/dev/null 2>&1
}

# Validate user permissions for Docker
milou_validate_docker_permissions() {
    local username="${1:-$(whoami)}"
    local quiet="${2:-false}"
    
    if milou_is_running_as_root; then
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Running as root - Docker permissions OK"
        return 0
    fi
    
    if groups "$username" | grep -q docker; then
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "User $username is in docker group"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "User $username is not in docker group"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Try: sudo usermod -aG docker $username && newgrp docker"
        return 1
    fi
}

# =============================================================================
# File and Path Validation
# =============================================================================

# Comprehensive path validation
milou_validate_path() {
    local path="$1"
    local type="${2:-any}"  # any, file, directory, executable
    local create_if_missing="${3:-false}"
    local quiet="${4:-false}"
    
    case "$type" in
        "file")
            if [[ ! -f "$path" ]]; then
                [[ "$quiet" != "true" ]] && milou_log "ERROR" "File does not exist: $path"
                return 1
            fi
            ;;
        "directory")
            if [[ ! -d "$path" ]]; then
                if [[ "$create_if_missing" == "true" ]]; then
                    [[ "$quiet" != "true" ]] && milou_log "INFO" "Creating directory: $path"
                    mkdir -p "$path" || {
                        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to create directory: $path"
                        return 1
                    }
                else
                    [[ "$quiet" != "true" ]] && milou_log "ERROR" "Directory does not exist: $path"
                    return 1
                fi
            fi
            ;;
        "executable")
            if [[ ! -x "$path" ]]; then
                [[ "$quiet" != "true" ]] && milou_log "ERROR" "File is not executable: $path"
                return 1
            fi
            ;;
        "any")
            if [[ ! -e "$path" ]]; then
                [[ "$quiet" != "true" ]] && milou_log "ERROR" "Path does not exist: $path"
                return 1
            fi
            ;;
    esac
    
    [[ "$quiet" != "true" ]] && milou_log "TRACE" "Path validation passed: $path"
    return 0
}

# =============================================================================
# Backward Compatibility Aliases
# =============================================================================

# Maintain backward compatibility
validate_github_token() { milou_validate_github_token "$@"; }
test_github_authentication() { milou_test_github_authentication "$@"; }
validate_domain() { milou_validate_domain "$@"; }
check_connectivity() { milou_check_connectivity "$@"; }
command_exists() { milou_command_exists "$@"; }
version_compare() { milou_version_compare "$@"; }
check_docker_access() { milou_check_docker_access "$@"; }
validate_ssl_certificates() { milou_validate_ssl_certificates "$@"; }

# Export all functions
export -f milou_validate_github_token milou_test_github_authentication
export -f milou_validate_domain milou_check_connectivity
export -f milou_check_docker_access milou_check_docker_resources milou_check_docker_compose milou_validate_docker_compose_config
export -f milou_command_exists milou_version_compare milou_check_port_availability
export -f milou_validate_ssl_certificates milou_is_running_as_root milou_user_exists
export -f milou_validate_docker_permissions milou_validate_path
export -f validate_github_token test_github_authentication validate_domain check_connectivity
export -f command_exists version_compare check_docker_access validate_ssl_certificates 