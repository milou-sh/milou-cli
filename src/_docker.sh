#!/bin/bash

# =============================================================================
# Milou CLI - Docker Management Module
# Consolidated Docker operations to eliminate code duplication
# Version: 3.1.0 - Refactored Edition
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Module guard to prevent multiple loading
if [[ "${MILOU_DOCKER_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_DOCKER_LOADED="true"

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

if [[ "${MILOU_CONFIG_LOADED:-}" != "true" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/_config.sh" || {
        echo "ERROR: Cannot load config module" >&2
        return 1
    }
fi

# =============================================================================
# DOCKER ENVIRONMENT CONFIGURATION
# =============================================================================

# Docker environment variables with defaults
declare -g DOCKER_ENV_FILE=""
declare -g DOCKER_COMPOSE_FILE=""
declare -g DOCKER_PROJECT_NAME="milou"
declare -g DOCKER_VOLUMES_CLEANED=false
declare -g GITHUB_REGISTRY="${GITHUB_REGISTRY:-ghcr.io/milou-sh/milou}"
declare -g GITHUB_API_BASE="${GITHUB_API_BASE:-https://api.github.com}"
declare -g REGISTRY_TIMEOUT="${REGISTRY_TIMEOUT:-30}"

# =============================================================================
# DOCKER ERROR HANDLING
# =============================================================================

# Handle Docker startup errors with specific guidance
docker_handle_startup_error() {
    local error_output="$1"
    local service="${2:-}"
    local quiet="${3:-false}"
    
    # Immediately report logs from any unhealthy containers to capture the root cause
    if command -v report_unhealthy_services >/dev/null 2>&1; then
        report_unhealthy_services "$service" "$quiet"
    fi

    [[ "$quiet" == "true" ]] && return 0
    
    # Check for authentication/credential errors first (most common after fresh setup)
    if echo "$error_output" | grep -q "password authentication failed\|authentication failed\|Access denied\|Invalid authentication"; then
        echo
        milou_log "ERROR" "❌ Database Authentication Failed"
        echo -e "${DIM}The backend service cannot connect to the database with current credentials.${NC}"
        echo
        echo -e "${YELLOW}${BOLD}🔍 ROOT CAUSE:${NC}"
        echo -e "   ${BLUE}•${NC} You likely deleted the milou-cli directory and set it up again"
        echo -e "   ${BLUE}•${NC} Fresh setup created NEW database credentials in .env"
        echo -e "   ${BLUE}•${NC} But old database volume still contains PREVIOUS credentials"
        echo -e "   ${BLUE}•${NC} New backend tries to connect with new creds to old database = FAIL"
        echo
        
        # Offer automatic resolution
        if detect_credential_mismatch "true"; then
            echo -e "${CYAN}${BOLD}🛠️  QUICK FIX:${NC}"
            echo -e "   Run: ${BOLD}./milou.sh setup --fix-credentials${NC}"
            echo -e "   Or we can fix it now..."
            echo
            
            # Try to resolve automatically
            if resolve_credential_mismatch "true" "$quiet"; then
                echo
                milou_log "SUCCESS" "🎉 Credential mismatch resolved! Try starting services again:"
                echo -e "   ${CYAN}./milou.sh start${NC}"
                echo
                return 0
            fi
        fi
        
        echo -e "${YELLOW}${BOLD}🔧 MANUAL FIX:${NC}"
        echo -e "   ${GREEN}✓${NC} Clean old volumes: ${CYAN}docker volume prune -f${NC}"
        echo -e "   ${GREEN}✓${NC} Or run full cleanup: ${CYAN}./milou.sh setup --fresh-install${NC}"
        echo -e "   ${GREEN}✓${NC} Then restart setup: ${CYAN}./milou.sh setup${NC}"
        echo
        return 0
    fi
    
    # Check for manifest unknown errors (image not found)
    if echo "$error_output" | grep -q "manifest unknown\|manifest not found\|pull access denied"; then
        echo
        milou_log "ERROR" "❌ Docker Image Not Found"
        echo -e "${DIM}The requested Docker image could not be found or accessed.${NC}"
        echo
        
        # Check for mixed versions and provide guidance
        if handle_mixed_versions "true"; then
            echo -e "${YELLOW}${BOLD}🔀 MIXED VERSIONS DETECTED:${NC}"
            echo -e "   ${BLUE}•${NC} Some services use different version tags"
            echo -e "   ${BLUE}•${NC} One or more images may not exist for specified versions"
            echo
            echo -e "${YELLOW}${BOLD}✅ SOLUTIONS:${NC}"
            echo -e "   ${GREEN}✓${NC} Use a consistent version: ${CYAN}./milou.sh setup${NC} and pick same version for all"
            echo -e "   ${GREEN}✓${NC} Or check available versions: ${CYAN}./milou.sh update --list-versions${NC}"
            echo -e "   ${GREEN}✓${NC} Update to latest: ${CYAN}./milou.sh update --version latest${NC}"
            echo
        else
            echo -e "${YELLOW}${BOLD}✓ Most Common Causes:${NC}"
            echo -e "   ${BLUE}1.${NC} Invalid version tag specified in .env"
            echo -e "   ${BLUE}2.${NC} Missing GitHub authentication for private images"
            echo -e "   ${BLUE}3.${NC} Network connectivity issues"
            echo -e "   ${BLUE}4.${NC} Version doesn't exist in registry"
            echo
            echo -e "${YELLOW}${BOLD}✓ How to Fix:${NC}"
            echo -e "   ${GREEN}✓${NC} Check version tags in .env file"
            echo -e "   ${GREEN}✓${NC} Ensure GITHUB_TOKEN is set with 'read:packages' scope"
            echo -e "   ${GREEN}✓${NC} Try with 'latest' version: ${CYAN}./milou.sh update --version latest${NC}"
            echo -e "   ${GREEN}✓${NC} Check available versions: ${CYAN}./milou.sh update --list-versions${NC}"
            echo
        fi
        return 0
    fi
    
    # Check for authentication errors (GitHub token issues)
    if echo "$error_output" | grep -q "unauthorized\|authentication.*required\|login.*required\|403.*Forbidden"; then
        echo
        milou_log "ERROR" "❌ GitHub Authentication Failed"
        echo -e "${DIM}Cannot authenticate with GitHub Container Registry.${NC}"
        echo
        echo -e "${YELLOW}${BOLD}✓ How to Fix:${NC}"
        echo -e "   ${GREEN}✓${NC} Get a GitHub token: ${CYAN}https://github.com/settings/tokens${NC}"
        echo -e "   ${GREEN}✓${NC} Required scope: ${BOLD}read:packages${NC}"
        echo -e "   ${GREEN}✓${NC} Add to .env file: ${CYAN}GITHUB_TOKEN=ghp_your_token_here${NC}"
        echo -e "   ${GREEN}✓${NC} Restart setup: ${CYAN}./milou.sh setup${NC}"
        echo
        return 0
    fi
    
    # Check for network errors
    if echo "$error_output" | grep -q "network\|connection\|timeout\|dns\|no route to host"; then
        echo
        milou_log "ERROR" "❌ Network Error"
        echo -e "${DIM}Network connection issues detected.${NC}"
        echo
        echo -e "${YELLOW}${BOLD}✓ How to Fix:${NC}"
        echo -e "   ${GREEN}✓${NC} Check internet connectivity"
        echo -e "   ${GREEN}✓${NC} Verify DNS resolution: ${CYAN}nslookup ghcr.io${NC}"
        echo -e "   ${GREEN}✓${NC} Check firewall settings"
        echo -e "   ${GREEN}✓${NC} Try again in a few minutes"
        echo
        return 0
    fi
    
    # Check for port conflicts
    if echo "$error_output" | grep -q "port.*already.*use\|address already in use\|bind.*address already in use"; then
        echo
        milou_log "ERROR" "❌ Port Conflict Detected"
        echo -e "${DIM}Required ports are already in use by other services.${NC}"
        echo
        echo -e "${YELLOW}${BOLD}✓ How to Fix:${NC}"
        echo -e "   ${GREEN}✓${NC} Stop conflicting services"
        echo -e "   ${GREEN}✓${NC} Check what's using ports: ${CYAN}netstat -tlnp | grep -E ':(80|443|5432|6379|5672)'${NC}"
        echo -e "   ${GREEN}✓${NC} Change ports in .env file if needed"
        echo -e "   ${GREEN}✓${NC} Run setup again: ${CYAN}./milou.sh setup${NC}"
        echo
        return 0
    fi
    
    # Check for disk space issues
    if echo "$error_output" | grep -q "no space\|disk.*full\|insufficient storage\|device.*space"; then
        echo
        milou_log "ERROR" "❌ Insufficient Disk Space"
        echo -e "${DIM}Not enough disk space to download and run Docker images.${NC}"
        echo
        echo -e "${YELLOW}${BOLD}✓ How to Fix:${NC}"
        echo -e "   ${GREEN}✓${NC} Free up disk space: ${CYAN}df -h${NC}"
        echo -e "   ${GREEN}✓${NC} Clean Docker: ${CYAN}docker system prune -f${NC}"
        echo -e "   ${GREEN}✓${NC} Remove old images: ${CYAN}docker image prune -a${NC}"
        echo -e "   ${GREEN}✓${NC} Clean old volumes: ${CYAN}docker volume prune -f${NC}"
        echo
        return 0
    fi
    
    # Generic error handling for other cases
    echo
    milou_log "ERROR" "❌ Service Startup Failed"
    if [[ -n "$service" ]]; then
        echo -e "${DIM}Service '$service' could not be started.${NC}"
    else
        echo -e "${DIM}One or more services could not be started.${NC}"
    fi
    echo
    echo -e "${YELLOW}${BOLD}✓ Troubleshooting Steps:${NC}"
    echo -e "   ${GREEN}✓${NC} Check for credential mismatch: ${CYAN}./milou.sh setup --fix-credentials${NC}"
    echo -e "   ${GREEN}✓${NC} Check logs: ${CYAN}./milou.sh logs${NC}"
    echo -e "   ${GREEN}✓${NC} Verify configuration: ${CYAN}docker compose config${NC}"
    echo -e "   ${GREEN}✓${NC} Fresh restart: ${CYAN}./milou.sh setup --fresh-install${NC}"
    echo
    
    # Show a snippet of the actual error for debugging
    if [[ ${#error_output} -gt 0 ]]; then
        echo -e "${DIM}${BOLD}Error Details:${NC}"
        echo -e "${DIM}$(echo "$error_output" | tail -5)${NC}"
        echo
    fi
}

# =============================================================================
# DOCKER INITIALIZATION AND SETUP
# =============================================================================

# GitHub Container Registry authentication
docker_login_github() {
    local github_token="${1:-}"
    local quiet="${2:-false}"
    local validate_token="${3:-true}"
    
    # Use provided token or environment variable
    if [[ -z "$github_token" ]]; then
        github_token="${GITHUB_TOKEN:-}"
    fi
    
    # If a token is present but clearly malformed, ignore it and proceed as if missing
    if [[ -n "$github_token" && "$validate_token" == "true" ]]; then
        if ! validate_github_token "$github_token" "false"; then
            [[ "$quiet" != "true" ]] && milou_log "WARN" "Detected invalid GitHub token format in environment – requesting a new one."
            github_token=""
        fi
    fi
    
    if [[ -z "$github_token" ]]; then
        if [[ "$quiet" != "true" && -t 0 && -t 1 && "${INTERACTIVE:-true}" == "true" ]]; then
            echo ""
            echo "🔑  A GitHub Personal Access Token is required to pull Milou images from GitHub Container Registry."
            echo "    Generate one at: https://github.com/settings/tokens  (scope: read:packages)"

            local attempts=0
            local max_attempts=3
            while [[ $attempts -lt $max_attempts ]]; do
                echo -n "Enter GitHub token (ghp_…): "
                read -r github_token
                github_token="${github_token//[[:space:]]/}"
                if validate_github_token "$github_token" "false"; then
                    break
                else
                    echo "⚠️  Invalid token format. Please try again."
                    github_token=""
                    attempts=$((attempts+1))
                fi
            done

            if [[ -z "$github_token" ]]; then
                milou_log "ERROR" "GitHub token is required but none was provided."
                return 1
            fi

            export GITHUB_TOKEN="$github_token"
            # Persist token to .env file if available so future commands don't ask again
            local env_file="${DOCKER_ENV_FILE:-${SCRIPT_DIR}/.env}"
            if [[ -f "$env_file" ]]; then
                if grep -q "^GITHUB_TOKEN=" "$env_file"; then
                    sed -i "s/^GITHUB_TOKEN=.*/GITHUB_TOKEN=$github_token/" "$env_file"
                else
                    echo "GITHUB_TOKEN=$github_token" >> "$env_file"
                fi
                milou_log "INFO" "✓ Token saved to $env_file"
            fi
        else
            [[ "$quiet" != "true" ]] && milou_log "WARN" "No GitHub token provided for authentication"
            return 1
        fi
    fi
    
    # Check if already authenticated with this token
    if [[ "${GITHUB_AUTHENTICATED:-}" == "true" && "${GITHUB_AUTHENTICATED_TOKEN:-}" == "$github_token" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Already authenticated with this GitHub token"
        return 0
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🔑 Authenticating with GitHub Container Registry..."
    
    # Validate token format first if requested
    if [[ "$validate_token" == "true" ]]; then
        if ! validate_github_token "$github_token" "false"; then
            [[ "$quiet" != "true" ]] && milou_log "WARN" "⚠️ Token format appears invalid, but attempting authentication anyway"
        fi
    fi
    
    # Attempt login with multiple username strategies
    local login_successful=false
    local login_error=""
    
    # Strategy 1: Use oauth2 as username (recommended for PATs)
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Attempting login with oauth2 username..."
    login_error=$(echo "$github_token" | docker login ghcr.io -u oauth2 --password-stdin 2>&1)
    local login_exit_code=$?
    
    if [[ $login_exit_code -eq 0 ]]; then
        login_successful=true
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Successfully authenticated with GitHub Container Registry"
    else
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "oauth2 login failed, trying token as username..."
        
        # Strategy 2: Use token as username (fallback)
        login_error=$(echo "$github_token" | docker login ghcr.io -u "$github_token" --password-stdin 2>&1)
        login_exit_code=$?
        
        if [[ $login_exit_code -eq 0 ]]; then
            login_successful=true
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Successfully authenticated with GitHub Container Registry (fallback method)"
        fi
    fi
    
    if [[ "$login_successful" != "true" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "❌ Failed to authenticate with GitHub Container Registry"
        
        # Provide specific guidance based on error type
        if echo "$login_error" | grep -qi "unauthorized\|invalid.*credentials"; then
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "🔑 Authentication failed - token is invalid or expired"
            [[ "$quiet" != "true" ]] && echo ""
            [[ "$quiet" != "true" ]] && echo "🔧 TROUBLESHOOTING:"
            [[ "$quiet" != "true" ]] && echo "   ✓ Check if your token has 'read:packages' scope"
            [[ "$quiet" != "true" ]] && echo "   ✓ Verify token hasn't expired"
            [[ "$quiet" != "true" ]] && echo "   ✓ Ensure you have access to milou-sh/milou repository"
            [[ "$quiet" != "true" ]] && echo "   ✓ Create new token: https://github.com/settings/tokens"
            [[ "$quiet" != "true" ]] && echo ""
        elif echo "$login_error" | grep -qi "network\|timeout\|connection"; then
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "🌐 Network error connecting to GitHub Container Registry"
            [[ "$quiet" != "true" ]] && echo ""
            [[ "$quiet" != "true" ]] && echo "🔧 TROUBLESHOOTING:"
            [[ "$quiet" != "true" ]] && echo "   ✓ Check internet connectivity"
            [[ "$quiet" != "true" ]] && echo "   ✓ Verify DNS resolution: nslookup ghcr.io"
            [[ "$quiet" != "true" ]] && echo "   ✓ Check firewall/proxy settings"
            [[ "$quiet" != "true" ]] && echo "   ✓ Try again in a few minutes"
            [[ "$quiet" != "true" ]] && echo ""
        elif echo "$login_error" | grep -qi "rate.*limit"; then
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "🚫 Rate limit exceeded for GitHub Container Registry"
            [[ "$quiet" != "true" ]] && echo ""
            [[ "$quiet" != "true" ]] && echo "🔧 TROUBLESHOOTING:"
            [[ "$quiet" != "true" ]] && echo "   ✓ Wait a few minutes before retrying"
            [[ "$quiet" != "true" ]] && echo "   ✓ Use a different GitHub token if available"
            [[ "$quiet" != "true" ]] && echo "   ✓ Check GitHub status: https://status.github.com"
            [[ "$quiet" != "true" ]] && echo ""
        else
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "🔧 Unexpected authentication error"
            [[ "$quiet" != "true" ]] && echo ""
            [[ "$quiet" != "true" ]] && echo "🔧 TROUBLESHOOTING:"
            [[ "$quiet" != "true" ]] && echo "   ✓ Try running: docker logout ghcr.io && docker login ghcr.io"
            [[ "$quiet" != "true" ]] && echo "   ✓ Restart Docker daemon if issues persist"
            [[ "$quiet" != "true" ]] && echo "   ✓ Check Docker logs for more details"
            [[ "$quiet" != "true" ]] && echo ""
        fi
        
        # Show error details in debug mode
        if [[ "${VERBOSE:-false}" == "true" && -n "$login_error" ]]; then
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Login error details: $login_error"
        fi
        
        return 1
    fi
    
    # Test access to a specific repository if authentication succeeded
    if [[ "$validate_token" == "true" && "$login_successful" == "true" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Testing repository access..."
        
        # Try to inspect a known image to verify we can access the registry
        local test_result
        test_result=$(docker manifest inspect "ghcr.io/milou-sh/milou/nginx:latest" 2>&1 || echo "")
        
        if echo "$test_result" | grep -q "manifest unknown\|not found"; then
            [[ "$quiet" != "true" ]] && milou_log "WARN" "⚠️ Authentication successful but cannot access milou-sh/milou repository"
            [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 You may need repository access permissions"
        elif echo "$test_result" | grep -q "unauthorized"; then
            [[ "$quiet" != "true" ]] && milou_log "WARN" "⚠️ Token authenticated but lacks repository permissions"
            [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Ensure token has 'read:packages' scope and repository access"
        else
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "🎉 Full GitHub Container Registry access verified"
        fi
    fi
    
    # Store authentication state with token to avoid re-authentication
    export GITHUB_AUTHENTICATED="true"
    export GITHUB_AUTHENTICATED_TOKEN="$github_token"
    
    return 0
}

# Initialize Docker environment - SINGLE AUTHORITATIVE IMPLEMENTATION
docker_init() {
    local env_file="${1:-${SCRIPT_DIR}/.env}"
    local compose_file="${2:-${SCRIPT_DIR}/static/docker-compose.yml}"
    local quiet="${3:-false}"
    local skip_auth="${4:-false}"  # Add parameter to skip authentication
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Initializing Docker environment (skip_auth=$skip_auth)..."
    
    # Check Docker access first
    if ! validate_docker_access "true" "false" "true" "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Docker access validation failed"
        return 1
    fi
    
    # Set global variables
    DOCKER_ENV_FILE="$env_file"
    DOCKER_COMPOSE_FILE="$compose_file"
    
    # Validate files exist with better error handling
    if [[ ! -f "$DOCKER_ENV_FILE" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "WARN" "Environment file not found: $DOCKER_ENV_FILE"
        
        # Try alternative locations for .env file
        local alt_env_files=(
            "${SCRIPT_DIR}/../.env"
            "$(pwd)/.env"
            "${HOME}/.milou/.env"
        )
        
        local found_env=false
        for alt_env in "${alt_env_files[@]}"; do
            if [[ -f "$alt_env" ]]; then
                DOCKER_ENV_FILE="$alt_env"
                [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Using alternative environment file: $DOCKER_ENV_FILE"
                found_env=true
                break
            fi
        done
        
        if [[ "$found_env" != "true" ]]; then
            [[ "$quiet" != "true" ]] && milou_log "WARN" "⚠️  No environment file found - proceeding with defaults"
            [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Run './milou.sh setup' to create proper configuration"
            # Don't fail hard - just continue with empty env
            DOCKER_ENV_FILE=""
        fi
    fi
    
    if [[ ! -f "$DOCKER_COMPOSE_FILE" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "WARN" "Compose file not found: $DOCKER_COMPOSE_FILE"
        
        # Try alternative locations for docker-compose file
        local alt_compose_files=(
            "${SCRIPT_DIR}/../docker-compose.yml"
            "${SCRIPT_DIR}/../static/docker-compose.yml"
            "$(pwd)/docker-compose.yml"
            "$(pwd)/static/docker-compose.yml"
        )
        
        local found_compose=false
        for alt_compose in "${alt_compose_files[@]}"; do
            if [[ -f "$alt_compose" ]]; then
                DOCKER_COMPOSE_FILE="$alt_compose"
                [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Using alternative compose file: $DOCKER_COMPOSE_FILE"
                found_compose=true
                break
            fi
        done
        
        if [[ "$found_compose" != "true" ]]; then
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "No docker-compose.yml file found"
            [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Run './milou.sh setup' to create proper configuration"
            return 1
        fi
    fi
    
    # Load environment to check for GitHub token (only if we have an env file)
    local github_token="${GITHUB_TOKEN:-}"
    if [[ -n "$DOCKER_ENV_FILE" && -f "$DOCKER_ENV_FILE" ]]; then
        # Source the environment file to get GITHUB_TOKEN
        source "$DOCKER_ENV_FILE" 2>/dev/null || true
        github_token="${GITHUB_TOKEN:-$github_token}"
    fi
    
    # Skip authentication if requested (e.g., for stop operations)
    if [[ "$skip_auth" == "true" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Skipping GitHub authentication as requested"
    else
        # Always attempt authentication when not already authenticated. This call
        # will itself handle prompting the user for a token if we don't yet have
        # one in the environment or .env file.
        if [[ "${GITHUB_AUTHENTICATED:-}" != "true" ]]; then
            if docker_login_github "$github_token" "$quiet"; then
                [[ "$quiet" != "true" ]] && milou_log "DEBUG" "GitHub Container Registry authentication successful"
                export GITHUB_AUTHENTICATED="true"
            else
                [[ "$quiet" != "true" ]] && milou_log "WARN" "GitHub authentication failed - private images may not be accessible"
            fi
        else
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "GitHub authentication already completed"
        fi
    fi
    
    # ------------------------------------------------------------------
    # After authentication we might have received a token via user prompt.
    # Refresh the local variable so we can use it for tag resolution.
    # ------------------------------------------------------------------
    github_token="${GITHUB_TOKEN:-$github_token}"

    # ------------------------------------------------------------------
    # Resolve any remaining MILOU_*_TAG entries that are still set to the
    # mutable values 'latest' or 'stable'. This converts them into
    # concrete SemVer tags so the running containers always reveal their
    # real version (no more ':latest' in `docker ps`).
    # ------------------------------------------------------------------
    if [[ -n "$github_token" && -n "$DOCKER_ENV_FILE" && -f "$DOCKER_ENV_FILE" ]]; then
        config_resolve_mutable_tags "$DOCKER_ENV_FILE" "$github_token" "$quiet"
    fi
    
    # Test Docker Compose configuration (only if we have both files)
    if [[ -n "$DOCKER_ENV_FILE" && -f "$DOCKER_COMPOSE_FILE" ]]; then
        local docker_compose_cmd="docker compose"
        [[ -n "$DOCKER_ENV_FILE" ]] && docker_compose_cmd="$docker_compose_cmd --env-file $DOCKER_ENV_FILE"
        docker_compose_cmd="$docker_compose_cmd -f $DOCKER_COMPOSE_FILE"
        
        if ! $docker_compose_cmd config --quiet 2>/dev/null; then
            [[ "$quiet" != "true" ]] && milou_log "WARN" "Docker Compose configuration validation failed"
            [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Check your environment file: $DOCKER_ENV_FILE"
            [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Check your compose file: $DOCKER_COMPOSE_FILE"
            # Don't fail hard for configuration issues in update context
            if [[ "$skip_auth" != "true" ]]; then
                return 1
            fi
        fi
    else
        [[ "$quiet" != "true" ]] && milou_log "WARN" "Skipping Docker Compose validation due to missing files"
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Docker environment initialized successfully"
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "  Environment file: ${DOCKER_ENV_FILE:-'none'}"
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "  Compose file: $DOCKER_COMPOSE_FILE"
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "  Project name: $DOCKER_PROJECT_NAME"
    
    return 0
}

# Docker Compose wrapper with proper environment - SINGLE AUTHORITATIVE IMPLEMENTATION
docker_compose() {
    if [[ -z "$DOCKER_COMPOSE_FILE" ]]; then
        milou_log "ERROR" "Docker environment not initialized. Call docker_init first."
        return 1
    fi
    
    # Execute docker compose with proper environment
    local docker_compose_cmd="docker compose"
    
    # Only add env file if it exists and is not empty
    if [[ -n "$DOCKER_ENV_FILE" && -f "$DOCKER_ENV_FILE" ]]; then
        docker_compose_cmd="$docker_compose_cmd --env-file $DOCKER_ENV_FILE"
    fi
    
    docker_compose_cmd="$docker_compose_cmd -f $DOCKER_COMPOSE_FILE"
    
    # Execute the command
    $docker_compose_cmd "$@"
}

# Master Docker execution function - consolidates all Docker operations
docker_execute() {
    local operation="$1"
    local service="${2:-}"
    local quiet="${3:-false}"
    shift 3 2>/dev/null || true
    local additional_args=("$@")
    
    # Determine if authentication should be skipped based on operation
    local skip_auth="false"
    case "$operation" in
        "down"|"stop")
            # Stop operations don't need authentication
            skip_auth="true"
            ;;
        "logs"|"ps"|"exec"|"config"|"validate")
            # Read-only operations don't need authentication
            skip_auth="true"
            ;;
        "up"|"start"|"pull"|"restart")
            # Operations that might pull images need authentication
            skip_auth="false"
            ;;
        *)
            # Default to requiring authentication for unknown operations
            skip_auth="false"
            ;;
    esac
    
    # Ensure Docker context is initialized
    if ! docker_init "" "" "$quiet" "$skip_auth"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Docker context initialization failed"
        return 1
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "🐳 Docker Execute: $operation ${service:+$service }${additional_args[*]:+${additional_args[*]}} (skip_auth=$skip_auth)"
    
    case "$operation" in
        "up"|"start")
            if [[ -n "$service" ]]; then
                [[ "$quiet" != "true" ]] && milou_log "INFO" "⬇️  Pulling image for service: $service"
                docker_compose pull "$service"
                [[ "$quiet" != "true" ]] && milou_log "INFO" "▶️  Starting service: $service"
                local result_output
                result_output=$(docker_compose up -d --remove-orphans "${additional_args[@]}" "$service" 2>&1)
                local exit_code=$?
                
                if [[ $exit_code -ne 0 ]]; then
                    [[ "$quiet" != "true" ]] && milou_log "ERROR" "❌ Failed to start service: $service"
                    docker_handle_startup_error "$result_output" "$service" "$quiet"
                    return $exit_code
                fi
            else
                [[ "$quiet" != "true" ]] && milou_log "INFO" "⬇️  Pulling all service images..."
                docker_compose pull
                [[ "$quiet" != "true" ]] && milou_log "INFO" "▶️  Starting all services"
                local result_output
                result_output=$(docker_compose up -d --remove-orphans "${additional_args[@]}" 2>&1)
                local exit_code=$?
                
                if [[ $exit_code -ne 0 ]]; then
                    [[ "$quiet" != "true" ]] && milou_log "ERROR" "❌ Failed to start services"
                    docker_handle_startup_error "$result_output" "" "$quiet"
                    return $exit_code
                fi
            fi
            ;;
        "down"|"stop")
            if [[ -n "$service" ]]; then
                [[ "$quiet" != "true" ]] && milou_log "INFO" "⏸️  Stopping service: $service"
                docker_compose stop "${additional_args[@]}" "$service"
            else
                [[ "$quiet" != "true" ]] && milou_log "INFO" "⏸️  Stopping all services"
                docker_compose down "${additional_args[@]}"
            fi
            ;;
        "restart")
            if [[ -n "$service" ]]; then
                [[ "$quiet" != "true" ]] && milou_log "INFO" "🔄 Restarting service: $service"
                docker_compose restart "${additional_args[@]}" "$service"
            else
                [[ "$quiet" != "true" ]] && milou_log "INFO" "🔄 Restarting all services"
                docker_compose restart "${additional_args[@]}"
            fi
            ;;
        "pull")
            [[ "$quiet" != "true" ]] && milou_log "INFO" "⬇️  Pulling latest images"
            docker_compose pull "${additional_args[@]}" ${service:+"$service"}
            ;;
        "logs")
            docker_compose logs "${additional_args[@]}" ${service:+"$service"}
            ;;
        "ps"|"status")
            docker_compose ps "${additional_args[@]}" ${service:+"$service"}
            ;;
        "exec")
            if [[ -z "$service" ]]; then
                [[ "$quiet" != "true" ]] && milou_log "ERROR" "Service name required for exec operation"
                return 1
            fi
            docker_compose exec "${additional_args[@]}" "$service"
            ;;
        "config")
            docker_compose config "${additional_args[@]}"
            ;;
        "validate")
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "🔍 Validating Docker Compose configuration"
            if docker_compose config --quiet 2>/dev/null; then
                [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Docker Compose configuration is valid"
                return 0
            else
                [[ "$quiet" != "true" ]] && milou_log "ERROR" "❌ Docker Compose configuration is invalid"
                return 1
            fi
            ;;
        *)
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "Unknown Docker operation: $operation"
            [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Supported operations: up, down, restart, pull, logs, ps, exec, config, validate"
            return 1
            ;;
    esac
}

# Health check service function - standard implementation
health_check_service() {
    local service="$1"
    local quiet="${2:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "🏥 Checking health of service: $service"
    
    # Check if service is defined
    local service_exists
    service_exists=$(docker_compose config --services 2>/dev/null | grep -c "^$service$" || echo "0")
    
    if [[ "$service_exists" -eq 0 ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Service '$service' not found in compose configuration"
        return 1
    fi
    
    # Check if service is running
    local service_status
    service_status=$(docker_compose ps --services --filter "status=running" 2>/dev/null | grep -c "^$service$" 2>/dev/null || echo "0")
    
    # Ensure service_status is a valid number
    if ! [[ "$service_status" =~ ^[0-9]+$ ]]; then
        service_status="0"
    fi
    
    if [[ "$service_status" -eq 0 ]]; then
        [[ "$quiet" != "true" ]] && milou_log "WARN" "Service '$service' is not running"
        return 1
    fi
    
    # Additional health checks can be added here per service
    [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Service '$service' is healthy"
    return 0
}

# Check all services health - comprehensive implementation
health_check_all() {
    local quiet="${1:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🏥 Running comprehensive health check on all services"
    
    local total_services=0
    local healthy_services=0
    local unhealthy_services=()
    
    # Get all defined services
    while IFS= read -r service; do
        [[ -z "$service" ]] && continue
        ((total_services++))
        
        if health_check_service "$service" "true"; then
            ((healthy_services++))
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "  ✅ $service"
        else
            unhealthy_services+=("$service")
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "  ❌ $service"
        fi
    done < <(docker_compose config --services 2>/dev/null)
    
    # Report results
    if [[ "$quiet" != "true" ]]; then
        echo
        milou_log "INFO" "📊 Health Check Summary:"
        milou_log "INFO" "  Total services: $total_services"
        milou_log "INFO" "  Healthy: $healthy_services"
        milou_log "INFO" "  Unhealthy: ${#unhealthy_services[@]}"
        
        if [[ ${#unhealthy_services[@]} -gt 0 ]]; then
            milou_log "WARN" "  Unhealthy services: ${unhealthy_services[*]}"
        fi
    fi
    
    # Return success only if all services are healthy
    if [[ $healthy_services -eq $total_services && $total_services -gt 0 ]]; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "🎉 All services are healthy!"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "WARN" "⚠️  Some services need attention"
        return 1
    fi
}

# Backward compatibility wrapper - standardizes legacy calls
milou_docker_compose() {
    milou_log "WARN" "⚠️  Using deprecated milou_docker_compose - please use docker_execute() instead"
    docker_compose "$@"
}

# =============================================================================
# SERVICE LIFECYCLE MANAGEMENT FUNCTIONS (Week 2 Completion)
# =============================================================================

# Start service with health validation
service_start_with_validation() {
    local service="${1:-}"
    local timeout="${2:-60}"
    local quiet="${3:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🚀 Starting service with validation: ${service:-all services}"
    
    # Check for credential mismatches before starting (prevents authentication failures)
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🔍 Checking for potential credential mismatches..."
    if detect_credential_mismatch "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "WARN" "🔧 Credential mismatch detected - offering automatic resolution"
        
        # Try to resolve automatically in interactive mode
        if resolve_credential_mismatch "true" "$quiet"; then
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Credential mismatch resolved - proceeding with startup"
        else
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "❌ Credential mismatch not resolved - startup may fail"
            [[ "$quiet" != "true" ]] && echo ""
            [[ "$quiet" != "true" ]] && echo "💡 MANUAL FIX: Run './milou.sh setup --fix-credentials' or clean volumes manually"
            [[ "$quiet" != "true" ]] && echo ""
            # Continue anyway - user might want to handle it manually
        fi
    fi
    
    # NETWORK CREATION: Ensure required networks exist (like in update process)
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🔗 Ensuring required networks exist..."
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Networks will be created by Docker Compose"
    
    # Load environment to check for GitHub token
    local github_token="${GITHUB_TOKEN:-}"
    if [[ -f "${DOCKER_ENV_FILE:-${SCRIPT_DIR}/.env}" ]]; then
        source "${DOCKER_ENV_FILE:-${SCRIPT_DIR}/.env}"
        github_token="${GITHUB_TOKEN:-$github_token}"
    fi

    # Ensure Docker environment is initialized (authentication will be handled based on operation)
    if ! docker_init "" "" "$quiet" "false"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Docker initialization failed"
        return 1
    fi

    # Start the service(s)
    if ! docker_execute "start" "$service" "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to start ${service:-services}"
        # Direct log capture for backend failure
        if docker ps -a --format '{{.Names}}' | grep -q "milou-backend"; then
            if docker ps -a --format '{{.Names}}\t{{.Status}}' | grep "milou-backend" | grep -q "unhealthy"; then
                 milou_log "ERROR" "Backend service is unhealthy. Displaying last 50 lines of logs:"
                 docker logs milou-backend --tail 50
            fi
        fi
        return 1
    fi
    
    # Wait and validate
    [[ "$quiet" != "true" ]] && milou_log "INFO" "⏳ Waiting up to ${timeout}s for services to become healthy..."
    
    local elapsed=0
    local check_interval=5
    
    while [[ $elapsed -lt $timeout ]]; do
        if [[ -n "$service" ]]; then
            if health_check_service "$service" "true"; then
                [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Service '$service' started and is healthy"
                return 0
            fi
        else
            if health_check_all "true"; then
                [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ All services started and are healthy"
                return 0
            fi
        fi
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
        [[ "$quiet" != "true" ]] && echo -n "."
    done
    
    [[ "$quiet" != "true" ]] && echo
    [[ "$quiet" != "true" ]] && milou_log "ERROR" "❌ Service startup validation failed after ${timeout}s"
    return 1
}

# Stop service gracefully with cleanup
service_stop_gracefully() {
    local service="${1:-}"
    local timeout="${2:-30}"
    local quiet="${3:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "⏸️  Stopping service gracefully: ${service:-all services}"
    
    # Send stop signal and wait for graceful shutdown
    if docker_execute "stop" "$service" "$quiet" --timeout="$timeout"; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Service stopped gracefully"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "WARN" "⚠️  Graceful stop failed, trying forceful stop"
        
        # Fallback to force kill if graceful stop fails
        if [[ -n "$service" ]]; then
            docker_compose kill "$service"
        else
            docker_compose kill
        fi
        
        [[ "$quiet" != "true" ]] && milou_log "WARN" "🔶 Service force-stopped"
        return 1
    fi
}

# Restart service safely with rollback capability
service_restart_safely() {
    local service="${1:-}"
    local quiet="${2:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🔄 Safely restarting service: ${service:-all services}"
    
    # Create snapshot before restart
    local snapshot_created=false
    if command -v create_system_snapshot >/dev/null 2>&1; then
        if create_system_snapshot "restart_${service:-all}_$(date +%s)" "$quiet"; then
            snapshot_created=true
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "📸 System snapshot created for safe restart"
        fi
    fi
    
    # Perform restart
    if docker_execute "restart" "$service" "$quiet"; then
        # Validate after restart
        local validation_result=0
        if [[ -n "$service" ]]; then
            health_check_service "$service" "$quiet" || validation_result=1
        else
            health_check_all "$quiet" || validation_result=1
        fi
        
        if [[ $validation_result -eq 0 ]]; then
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Service restarted successfully and is healthy"
            return 0
        else
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "❌ Service restart validation failed"
            
            # Offer rollback if snapshot exists
            if [[ "$snapshot_created" == "true" ]]; then
                [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 System snapshot available for rollback if needed"
            fi
            return 1
        fi
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "❌ Service restart failed"
        return 1
    fi
}

# Update service with zero downtime (rolling update)
service_update_zero_downtime() {
    local service="${1:-}"
    local quiet="${2:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🔄 Starting zero-downtime update for: ${service:-all services}"
    
    # Create backup snapshot
    if command -v create_system_snapshot >/dev/null 2>&1; then
        if ! create_system_snapshot "update_${service:-all}_$(date +%s)" "$quiet"; then
            [[ "$quiet" != "true" ]] && milou_log "WARN" "⚠️  Could not create backup snapshot"
        fi
    fi
    
    # Pull latest images first
    [[ "$quiet" != "true" ]] && milou_log "INFO" "⬇️  Pulling latest images..."
    if ! docker_execute "pull" "$service" "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "❌ Failed to pull latest images"
        return 1
    fi
    
    # Perform rolling update
    if [[ -n "$service" ]]; then
        # Single service update
        [[ "$quiet" != "true" ]] && milou_log "INFO" "🔄 Updating service: $service"
        
        # Stop old container and start new one
        if docker_execute "up" "$service" "$quiet" --force-recreate --no-deps; then
            # Validate new service
            if health_check_service "$service" "$quiet"; then
                [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Service updated successfully with zero downtime"
                return 0
            else
                [[ "$quiet" != "true" ]] && milou_log "ERROR" "❌ Updated service failed health check"
                return 1
            fi
        else
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "❌ Service update failed"
            return 1
        fi
    else
        # Multi-service rolling update
        [[ "$quiet" != "true" ]] && milou_log "INFO" "🔄 Performing rolling update of all services"
        
        # Get all services
        local services=()
        while IFS= read -r svc; do
            [[ -n "$svc" ]] && services+=("$svc")
        done < <(docker_compose config --services 2>/dev/null)
        
        local failed_services=()
        
        # Update each service individually
        for svc in "${services[@]}"; do
            [[ "$quiet" != "true" ]] && milou_log "INFO" "🔄 Updating service: $svc"
            
            if docker_execute "up" "$svc" "$quiet" --force-recreate --no-deps; then
                if health_check_service "$svc" "true"; then
                    [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "  ✅ $svc updated successfully"
                else
                    [[ "$quiet" != "true" ]] && milou_log "ERROR" "  ❌ $svc update failed health check"
                    failed_services+=("$svc")
                fi
            else
                [[ "$quiet" != "true" ]] && milou_log "ERROR" "  ❌ $svc update failed"
                failed_services+=("$svc")
            fi
        done
        
        # Report results
        if [[ ${#failed_services[@]} -eq 0 ]]; then
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "🎉 All services updated successfully with zero downtime"
            return 0
        else
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "❌ Some services failed to update: ${failed_services[*]}"
            return 1
        fi
    fi
}

# =============================================================================
# BUILD AND PUSH OPERATIONS WITH TOKEN VALIDATION
# =============================================================================

# Validate GitHub token permissions before build/push operations
validate_token_for_build_push() {
    local github_token="${1:-}"
    local quiet="${2:-false}"
    
    # Use provided token or environment variable
    if [[ -z "$github_token" ]]; then
        github_token="${GITHUB_TOKEN:-}"
    fi
    
    # If a token is present but clearly malformed, ignore it and proceed as if missing
    if [[ -n "$github_token" && "$validate_token" == "true" ]]; then
        if ! validate_github_token "$github_token" "false"; then
            [[ "$quiet" != "true" ]] && milou_log "WARN" "Detected invalid GitHub token format in environment – requesting a new one."
            github_token=""
        fi
    fi
    
    if [[ -z "$github_token" ]]; then
        if [[ "$quiet" != "true" && -t 0 && -t 1 && "${INTERACTIVE:-true}" == "true" ]]; then
            echo ""
            echo "🔑  A GitHub Personal Access Token is required to pull Milou images from GitHub Container Registry."
            echo "    Generate one at: https://github.com/settings/tokens  (scope: read:packages)"

            local attempts=0
            local max_attempts=3
            while [[ $attempts -lt $max_attempts ]]; do
                echo -n "Enter GitHub token (ghp_…): "
                read -r github_token
                github_token="${github_token//[[:space:]]/}"
                if validate_github_token "$github_token" "false"; then
                    break
                else
                    echo "⚠️  Invalid token format. Please try again."
                    github_token=""
                    attempts=$((attempts+1))
                fi
            done

            if [[ -z "$github_token" ]]; then
                milou_log "ERROR" "GitHub token is required but none was provided."
                return 1
            fi

            export GITHUB_TOKEN="$github_token"
            # Persist token to .env file if available so future commands don't ask again
            local env_file="${DOCKER_ENV_FILE:-${SCRIPT_DIR}/.env}"
            if [[ -f "$env_file" ]]; then
                if grep -q "^GITHUB_TOKEN=" "$env_file"; then
                    sed -i "s/^GITHUB_TOKEN=.*/GITHUB_TOKEN=$github_token/" "$env_file"
                else
                    echo "GITHUB_TOKEN=$github_token" >> "$env_file"
                fi
                milou_log "INFO" "✓ Token saved to $env_file"
            fi
        else
            [[ "$quiet" != "true" ]] && milou_log "WARN" "No GitHub token provided for authentication"
            return 1
        fi
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🔐 Validating GitHub token for build/push operations..."
    
    # Validate token format
    if ! validate_github_token "$github_token" "false"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "❌ Invalid GitHub token format"
        return 1
    fi
    
    # Test authentication and registry access
    if ! test_github_authentication "$github_token" "$quiet" "true"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "❌ GitHub token validation failed"
        [[ "$quiet" != "true" ]] && echo ""
        [[ "$quiet" != "true" ]] && echo "🔧 COMMON ISSUES:"
        [[ "$quiet" != "true" ]] && echo "   ✓ Token missing 'read:packages' and 'write:packages' scopes"
        [[ "$quiet" != "true" ]] && echo "   ✓ No access to milou-sh/milou repository"
        [[ "$quiet" != "true" ]] && echo "   ✓ Token has expired"
        [[ "$quiet" != "true" ]] && echo "   ✓ Network connectivity issues"
        [[ "$quiet" != "true" ]] && echo ""
        [[ "$quiet" != "true" ]] && echo "💡 Create a new token with proper scopes:"
        [[ "$quiet" != "true" ]] && echo "   https://github.com/settings/tokens"
        [[ "$quiet" != "true" ]] && echo ""
        return 1
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ GitHub token validated - ready for build/push operations"
    export GITHUB_TOKEN="$github_token"
    return 0
}

# =============================================================================
# DOCKER ENVIRONMENT MANAGEMENT FUNCTIONS
# =============================================================================

# Enhanced Docker environment cleanup with intelligent credential mismatch detection
docker_cleanup_environment() {
    local mode="${1:-safe}" # Modes: safe (containers/networks only), full (includes volumes), credential_fix (specific to credential issues)
    local quiet="${2:-false}"
    local reason="${3:-manual}"  # Reason: manual, credential_mismatch, fresh_install, etc.

    # Special handling for credential mismatch scenarios
    if [[ "$mode" == "credential_fix" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "INFO" "🔧 Performing targeted cleanup for credential mismatch resolution"
        mode="full"  # Credential fixes need volume cleanup
    fi

    # Check if we have proper environment file before using docker-compose
    local use_compose=false
    if [[ -n "$DOCKER_ENV_FILE" && -f "$DOCKER_ENV_FILE" && -n "$DOCKER_COMPOSE_FILE" && -f "$DOCKER_COMPOSE_FILE" ]]; then
        # Test if docker-compose config is valid before using it
        if docker compose --env-file "$DOCKER_ENV_FILE" -f "$DOCKER_COMPOSE_FILE" config --quiet 2>/dev/null; then
            use_compose=true
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Using Docker Compose for cleanup"
        else
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Docker Compose config invalid, using direct Docker commands"
        fi
    else
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "No valid environment file, using direct Docker commands for cleanup"
    fi

    if [[ "$use_compose" == "true" ]]; then
        # Use docker-compose for cleanup when we have valid configuration
        local down_args=("--remove-orphans")
        
        if [[ "$mode" == "full" ]]; then
            if [[ "$reason" == "credential_mismatch" ]]; then
                [[ "$quiet" != "true" ]] && milou_log "WARN" "Removing database volumes to resolve credential mismatch (data will be lost)"
            else
                [[ "$quiet" != "true" ]] && milou_log "WARN" "Performing full cleanup, which will delete service data volumes."
            fi
            down_args+=("--volumes")
        else
            [[ "$quiet" != "true" ]] && milou_log "INFO" "Performing safe cleanup of containers and networks. Data volumes will be preserved."
        fi
        
        if ! docker_execute "down" "" "$quiet" "${down_args[@]}"; then
            [[ "$quiet" != "true" ]] && milou_log "WARN" "Could not perform cleanup cleanly, but proceeding."
        fi
    else
        # Use direct Docker commands when no valid compose configuration
        if [[ "$reason" == "credential_mismatch" ]]; then
            [[ "$quiet" != "true" ]] && milou_log "INFO" "Performing direct Docker cleanup to resolve credential mismatch."
        else
            [[ "$quiet" != "true" ]] && milou_log "INFO" "Performing direct Docker cleanup of Milou resources."
        fi
        
        # Stop and remove containers by name pattern
        local containers
        if containers=$(docker ps -q --filter "name=milou-" 2>/dev/null) && [[ -n "$containers" ]]; then
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Stopping Milou containers..."
            docker stop $containers 2>/dev/null || true
        fi
        
        if containers=$(docker ps -aq --filter "name=milou-" 2>/dev/null) && [[ -n "$containers" ]]; then
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Removing Milou containers..."
            docker rm $containers 2>/dev/null || true
        fi
        
        # Remove networks (but be careful not to remove system networks)
        local networks
        if networks=$(docker network ls --filter "name=milou" --format "{{.Name}}" 2>/dev/null); then
            for network in $networks; do
                if [[ "$network" != "bridge" && "$network" != "host" && "$network" != "none" ]]; then
                    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Removing network: $network"
                    docker network rm "$network" 2>/dev/null || true
                fi
            done
        fi
        
        # Handle volumes based on mode
        if [[ "$mode" == "full" ]]; then
            if [[ "$reason" == "credential_mismatch" ]]; then
                [[ "$quiet" != "true" ]] && milou_log "WARN" "Removing database volumes to fix credential mismatch (this resolves authentication failures)"
            else
                [[ "$quiet" != "true" ]] && milou_log "WARN" "Removing Milou data volumes (this will delete all data!)"
            fi
            local volumes
            if volumes=$(docker volume ls --format "{{.Name}}" 2>/dev/null | grep -E "(milou|static)" 2>/dev/null); then
                for volume in $volumes; do
                    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Removing volume: $volume"
                    docker volume rm "$volume" 2>/dev/null || true
                done
            fi
        else
            [[ "$quiet" != "true" ]] && milou_log "INFO" "Preserving data volumes (safe mode)"
        fi
    fi
    
    if [[ "$reason" == "credential_mismatch" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Credential mismatch cleanup completed - fresh database will use new credentials"
    else
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "Docker environment cleanup completed."
    fi
    return 0
}

# New function to validate Docker environment
docker_validate_environment() {
    local quiet="${1:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Validating Docker environment..."
    
    # Check if Docker is available
    if ! command -v docker >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Docker is not installed or not available in PATH"
        return 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Docker daemon is not running"
        return 1
    fi
    
    # Check if Docker Compose is available
    if ! docker compose version >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Docker Compose is not available"
        return 1
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "Docker environment validation passed"
    return 0
}

# =============================================================================
# DATABASE CREDENTIAL MANAGEMENT
# =============================================================================

# Detect if database credentials in .env don't match existing database
detect_credential_mismatch() {
    local quiet="${1:-false}"
    
    # Ensure Docker environment is initialized before we start.
    # We skip auth because we only need to interact with the local db.
    if ! docker_init "" "" "$quiet" "true"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Docker init failed during mismatch check."
        return 0 # Assume mismatch if we can't even init
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "🔍 Checking for credential mismatches..."
    
    # Check if database container exists and has data
    local db_container_exists=false
    local db_volume_exists=false
    
    # Check for existing database container
    if docker ps -a --filter "name=milou-database" --format "{{.Names}}" | grep -q "milou-database"; then
        db_container_exists=true
    fi
    
    # Check for existing database volume (most important indicator)
    if docker volume ls --format "{{.Name}}" | grep -E "(milou.*pgdata|milou.*postgres|static.*pgdata)" >/dev/null 2>&1; then
        db_volume_exists=true
    fi
    
    # If no existing database artifacts, no mismatch possible
    if [[ "$db_container_exists" == "false" && "$db_volume_exists" == "false" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "✅ No existing database found - no credential mismatch possible"
        return 1  # No mismatch
    fi
    
    # Load current .env credentials
    local current_db_user=""
    local current_db_password=""
    
    if [[ -f "${DOCKER_ENV_FILE:-${SCRIPT_DIR}/.env}" ]]; then
        source "${DOCKER_ENV_FILE:-${SCRIPT_DIR}/.env}" 2>/dev/null || true
        current_db_user="${POSTGRES_USER:-${DB_USER:-}}"
        current_db_password="${POSTGRES_PASSWORD:-${DB_PASSWORD:-}}"
    fi
    
    # If we have database artifacts but no current credentials, likely a mismatch
    if [[ -z "$current_db_user" || -z "$current_db_password" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "WARN" "⚠️ Database artifacts found but no credentials in .env - possible mismatch"
        return 0  # Likely mismatch
    fi
    
    # Try to start database and test connection
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Testing database connection with current credentials..."
    
    # Temporarily start just the database container to test
    local test_result=0
    if docker_compose up -d db 2>/dev/null; then
        # Wait a few seconds for database to initialize
        sleep 5
        
        # Try to connect with current credentials
        if docker_compose exec -T db psql -U "$current_db_user" -d "${POSTGRES_DB:-${DB_NAME:-milou_database}}" -c "SELECT 1;" >/dev/null 2>&1; then
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "✅ Database connection successful - no credential mismatch"
            test_result=1  # No mismatch
        else
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "❌ Database connection failed - credential mismatch detected"
            test_result=0  # Mismatch detected
        fi
        
        # Stop the test database
        docker_compose stop db >/dev/null 2>&1 || true
    else
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Could not start database for testing - assuming mismatch"
        test_result=0  # Assume mismatch if can't start
    fi
    
    return $test_result
}

# Resolve credential mismatch by cleaning old volumes
resolve_credential_mismatch() {
    local interactive="${1:-true}"
    local quiet="${2:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "WARN" "🔧 Credential mismatch detected - database has old credentials"
    [[ "$quiet" != "true" ]] && echo ""
    [[ "$quiet" != "true" ]] && echo "🔍 WHAT HAPPENED:"
    [[ "$quiet" != "true" ]] && echo "   • Fresh setup created new database credentials in .env"
    [[ "$quiet" != "true" ]] && echo "   • But old database volume contains previous credentials"
    [[ "$quiet" != "true" ]] && echo "   • New backend can't connect to old database"
    [[ "$quiet" != "true" ]] && echo ""
    [[ "$quiet" != "true" ]] && echo "🛠️  SOLUTION:"
    [[ "$quiet" != "true" ]] && echo "   • Clean old database volume to use new credentials"
    [[ "$quiet" != "true" ]] && echo "   • This will remove old database data (if any)"
    [[ "$quiet" != "true" ]] && echo "   • Fresh database will be created with new credentials"
    [[ "$quiet" != "true" ]] && echo ""
    
    local should_clean=false
    
    if [[ "$interactive" == "true" ]]; then
        local choice
        echo -n "🤔 Clean old database volume and use new credentials? (Y/n): "
        read -r choice
        
        case "$choice" in
            [Yy]*|"")
                should_clean=true
                ;;
            *)
                [[ "$quiet" != "true" ]] && milou_log "INFO" "Operation cancelled by user"
                return 1
                ;;
        esac
    else
        # Non-interactive mode - clean automatically
        should_clean=true
        [[ "$quiet" != "true" ]] && milou_log "INFO" "Non-interactive mode - automatically cleaning old volumes"
    fi
    
    if [[ "$should_clean" == "true" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "INFO" "🧹 Cleaning old database volumes to resolve credential mismatch..."
        
        # Use the enhanced cleanup function with credential-specific mode
        if docker_cleanup_environment "credential_fix" "$quiet" "credential_mismatch"; then
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Old database volumes cleaned - new credentials will be used"
            return 0
        else
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "❌ Failed to clean old database volumes"
            return 1
        fi
    fi
    
    return 1
}

# Enhanced function to handle mixed version scenarios
handle_mixed_versions() {
    local quiet="${1:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "🔍 Checking for mixed version scenarios..."
    
    # Load current version settings
    local backend_version=""
    local frontend_version=""
    local database_version=""
    local engine_version=""
    local nginx_version=""
    
    if [[ -f "${DOCKER_ENV_FILE:-${SCRIPT_DIR}/.env}" ]]; then
        source "${DOCKER_ENV_FILE:-${SCRIPT_DIR}/.env}" 2>/dev/null || true
        backend_version="${MILOU_BACKEND_TAG:-${MILOU_VERSION:-latest}}"
        frontend_version="${MILOU_FRONTEND_TAG:-${MILOU_VERSION:-latest}}"
        database_version="${MILOU_DATABASE_TAG:-${MILOU_VERSION:-latest}}"
        engine_version="${MILOU_ENGINE_TAG:-${MILOU_VERSION:-latest}}"
        nginx_version="${MILOU_NGINX_TAG:-${MILOU_VERSION:-latest}}"
    fi
    
    # Check if versions are mixed
    local versions=("$backend_version" "$frontend_version" "$database_version" "$engine_version" "$nginx_version")
    local unique_versions=()
    
    for version in "${versions[@]}"; do
        if [[ ! " ${unique_versions[*]} " =~ " ${version} " ]]; then
            unique_versions+=("$version")
        fi
    done
    
    if [[ ${#unique_versions[@]} -gt 1 ]]; then
        [[ "$quiet" != "true" ]] && milou_log "INFO" "🔀 Mixed versions detected:"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "   Backend: $backend_version"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "   Frontend: $frontend_version"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "   Database: $database_version"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "   Engine: $engine_version"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "   Nginx: $nginx_version"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 This is normal and supported - services will use their respective versions"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "✅ All services using consistent version: ${unique_versions[0]}"
        return 1
    fi
}

# =============================================================================
# EXPORT CONSOLIDATED FUNCTIONS
# =============================================================================

# Export all key Docker functions for use by other modules
export -f docker_login_github
export -f docker_init
export -f docker_compose
export -f docker_execute
export -f docker_handle_startup_error
export -f docker_cleanup_environment
export -f docker_validate_environment
export -f health_check_service
export -f health_check_all
export -f service_start_with_validation
export -f service_stop_gracefully
export -f service_restart_safely
export -f service_update_zero_downtime
export -f validate_token_for_build_push

# New credential management functions
export -f detect_credential_mismatch
export -f resolve_credential_mismatch
export -f handle_mixed_versions

# Legacy compatibility
export -f milou_docker_compose

# NEW FUNCTION: Report logs for unhealthy containers
docker_report_unhealthy_services() {
    local services_to_check="$1"
    local quiet="$2"

    local unhealthy_containers
    unhealthy_containers=$(docker_get_unhealthy_containers "$services_to_check" "$quiet")

    if [[ -n "$unhealthy_containers" ]]; then
        [[ "$quiet" != "true" ]] && echo
        log_error "Diagnostics for Unhealthy Containers"
        for container in $unhealthy_containers; do
            [[ "$quiet" != "true" ]] && echo -e "${YELLOW}--------------------------------------------------${NC}"
            log_warning "Logs for failed container: $container"
            [[ "$quiet" != "true" ]] && echo -e "${YELLOW}--------------------------------------------------${NC}"
            
            # Grab and display logs
            docker logs "$container" --tail 50 2>&1 | sed 's/^/    /' || log_warning "Could not retrieve logs for $container."
            
            [[ "$quiet" != "true" ]] && echo -e "${YELLOW}--------------------------------------------------${NC}"
            [[ "$quiet" != "true" ]] && echo
        done
        log_info "The logs above may indicate a problem within the application running inside the container (e.g., a coding bug or configuration error), not necessarily a problem with the CLI tool itself."
    fi
}

# NEW FUNCTION: Get a list of unhealthy containers
docker_get_unhealthy_containers() {
    local services_to_check="$1"
    local quiet="$2"
    
    local project_name
    # Use COMPOSE_PROJECT_NAME from .env as it's more reliable
    project_name="${COMPOSE_PROJECT_NAME:-milou}"

    # List all containers for the project, filter for unhealthy status
    docker ps -a --format "{{.Names}}\t{{.Status}}" --filter "name=${project_name}-" 2>/dev/null | \
        grep -i 'unhealthy' | \
        cut -f1
}

milou_log "DEBUG" "Docker module loaded successfully" 