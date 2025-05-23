#!/bin/bash

# =============================================================================
# Docker Registry Utilities for Milou CLI
# Handles GitHub Container Registry authentication and image management
# =============================================================================

# Constants (use defaults if not already set)
GITHUB_REGISTRY="${GITHUB_REGISTRY:-ghcr.io/milou-sh/milou}"
GITHUB_API_BASE="${GITHUB_API_BASE:-https://api.github.com}"

# =============================================================================
# GitHub Authentication Functions
# =============================================================================

# Validate GitHub token format
validate_github_token() {
    local token="$1"
    if [[ ! "$token" =~ ^gh[pousr]_[A-Za-z0-9_]{36,251}$ ]]; then
        return 1
    fi
    return 0
}

# Test GitHub token authentication
test_github_authentication() {
    local token="$1"
    
    log "STEP" "Testing GitHub authentication..."
    
    # Validate token format first
    if ! validate_input "$token" "github_token"; then
        return 1
    fi
    
    # Test authentication with GitHub API
    local response
    if ! response=$(curl -s -H "Authorization: Bearer $token" \
                   -H "Accept: application/vnd.github.v3+json" \
                   "$GITHUB_API_BASE/user" 2>/dev/null); then
        log "ERROR" "Failed to connect to GitHub API"
        return 1
    fi
    
    # Check if authentication was successful
    if echo "$response" | grep -q '"login"'; then
        local username
        username=$(echo "$response" | grep -o '"login": *"[^"]*"' | cut -d'"' -f4)
        log "SUCCESS" "GitHub authentication successful (user: $username)"
        
        # Test Docker registry authentication
        log "DEBUG" "Testing Docker registry authentication..."
        if echo "$token" | docker login ghcr.io -u "$username" --password-stdin >/dev/null 2>&1; then
            log "SUCCESS" "Docker registry authentication successful"
            return 0
        else
            log "ERROR" "Docker registry authentication failed"
            log "INFO" "💡 Ensure your token has 'read:packages' and 'write:packages' scopes"
            return 1
        fi
    else
        log "ERROR" "GitHub authentication failed"
        log "DEBUG" "API Response: $response"
        
        # Check for specific error messages
        if echo "$response" | grep -q "Bad credentials"; then
            log "INFO" "💡 The provided token is invalid or expired"
        elif echo "$response" | grep -q "rate limit"; then
            log "INFO" "💡 GitHub API rate limit exceeded, try again later"
        fi
        
        return 1
    fi
}

# =============================================================================
# Image Tag Management
# =============================================================================

# Get available image tags from GitHub Container Registry
get_available_image_tags() {
    local image_name="$1"
    local token="$2"
    
    log "DEBUG" "Fetching available tags for $image_name..."
    
    # Use the GitHub Packages API to get package versions
    local -a api_patterns=(
        "milou%2F${image_name}"
        "milou-${image_name}"
        "${image_name}"
    )
    
    local -a api_base_urls=(
        "$GITHUB_API_BASE/orgs/milou-sh/packages/container"
        "$GITHUB_API_BASE/user/packages/container"
    )
    
    for api_base in "${api_base_urls[@]}"; do
        for pattern in "${api_patterns[@]}"; do
            local api_url="${api_base}/${pattern}/versions"
            log "DEBUG" "Trying API endpoint: $api_url"
            
            local response
            if response=$(curl -s -w "\n%{http_code}" \
                         -H "Authorization: Bearer $token" \
                         -H "Accept: application/vnd.github.v3+json" \
                         -H "X-GitHub-Api-Version: 2022-11-28" \
                         "$api_url" 2>/dev/null); then
                
                local http_code=$(echo "$response" | tail -n1)
                local body=$(echo "$response" | head -n -1)
                
                log "DEBUG" "HTTP response code: $http_code for pattern: $pattern"
                
                if [[ "$http_code" == "200" ]]; then
                    log "DEBUG" "Successfully fetched package data from: $api_url"
                    
                    # Try different ways to extract tags from the response
                    local tags=""
                    
                    # Method 1: Extract from metadata.container.tags
                    if command -v jq >/dev/null 2>&1; then
                        tags=$(echo "$body" | jq -r '
                            .[] | 
                            select(.metadata.container.tags != null) | 
                            .metadata.container.tags[] | 
                            select(. != null and . != "")
                        ' 2>/dev/null | sort -V || echo "")
                    fi
                    
                    # Method 2: Try to extract from name field if metadata method failed
                    if [[ -z "$tags" ]] && command -v jq >/dev/null 2>&1; then
                        tags=$(echo "$body" | jq -r '.[].name // empty' 2>/dev/null | sort -V || echo "")
                    fi
                    
                    # Method 3: Try simple grep if jq is not available or failed
                    if [[ -z "$tags" ]]; then
                        tags=$(echo "$body" | grep -o '"name": *"[^"]*"' | cut -d'"' -f4 | sort -V || echo "")
                    fi
                    
                    if [[ -n "$tags" ]]; then
                        log "DEBUG" "Found tags via API: $(echo "$tags" | head -10 | tr '\n' ' ')$([ $(echo "$tags" | wc -l) -gt 10 ] && echo "...")"
                        echo "$tags"
                        return 0
                    else
                        log "DEBUG" "API returned data but no tags were extracted"
                        log "DEBUG" "Response sample: $(echo "$body" | head -c 200)..."
                    fi
                elif [[ "$http_code" == "401" ]]; then
                    log "DEBUG" "Authentication failed for: $api_url"
                elif [[ "$http_code" == "403" ]]; then
                    log "DEBUG" "Access forbidden for: $api_url (token may lack permissions)"
                elif [[ "$http_code" == "404" ]]; then
                    log "DEBUG" "Package not found at: $api_url (pattern: $pattern)"
                else
                    log "DEBUG" "Unexpected response ($http_code) from: $api_url"
                fi
            else
                log "DEBUG" "Failed to fetch from: $api_url"
            fi
        done
    done
    
    log "DEBUG" "No tags found for $image_name from any GitHub Packages API endpoint"
    return 1
}

# Get latest tag with improved version detection
get_latest_image_tag() {
    local image_name="$1"
    local token="$2"
    
    log "DEBUG" "Getting latest tag for $image_name..." >&2
    
    # Strategy 1: Try "latest" tag first since it's most common
    log "DEBUG" "Strategy 1: Testing 'latest' tag directly..." >&2
    if curl -s -f -H "Authorization: Bearer $token" \
       -H "Accept: application/vnd.docker.distribution.manifest.v2+json, application/vnd.docker.distribution.manifest.list.v2+json" \
       "https://ghcr.io/v2/milou-sh/milou/$image_name/manifests/latest" >/dev/null 2>&1; then
        log "DEBUG" "Found 'latest' tag for $image_name" >&2
        echo "latest"
        return 0
    fi
    
    # Strategy 2: Try to get tags from GitHub Packages API
    log "DEBUG" "Strategy 2: Trying GitHub Packages API..." >&2
    local tags
    tags=$(get_available_image_tags "$image_name" "$token" 2>/dev/null)
    
    if [[ -n "$tags" ]]; then
        log "DEBUG" "Found tags for $image_name via API: $(echo "$tags" | head -5 | tr '\n' ' ')..." >&2
        
        # First priority: Check if 'latest' tag is available
        if echo "$tags" | grep -q "^latest$"; then
            log "DEBUG" "Found 'latest' tag in API response for $image_name" >&2
            echo "latest"
            return 0
        fi
        
        # Second priority: look for semantic version tags
        local semantic_tags
        semantic_tags=$(echo "$tags" | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?$' | sort -V)
        
        if [[ -n "$semantic_tags" ]]; then
            local latest_semantic
            latest_semantic=$(echo "$semantic_tags" | tail -1)
            log "DEBUG" "Selected latest semantic version tag: $latest_semantic" >&2
            echo "$latest_semantic"
            return 0
        fi
        
        # Third priority: try main/master tags
        if echo "$tags" | grep -q "^main$"; then
            log "DEBUG" "Found 'main' tag for $image_name" >&2
            echo "main"
            return 0
        fi
        
        if echo "$tags" | grep -q "^master$"; then
            log "DEBUG" "Found 'master' tag for $image_name" >&2
            echo "master"
            return 0
        fi
        
        # If we have any tags, use the most recent one
        local most_recent
        most_recent=$(echo "$tags" | tail -1)
        if [[ -n "$most_recent" ]]; then
            log "DEBUG" "Using most recent tag: $most_recent" >&2
            echo "$most_recent"
            return 0
        fi
    fi
    
    # Fallback with warning
    log "WARN" "Could not determine latest version for $image_name, using fallback 'latest'" >&2
    echo "latest"
}

# =============================================================================
# Image Validation Functions
# =============================================================================

# Check if a specific image exists in the registry (SIMPLIFIED VERSION)
check_image_exists() {
    local image_name="$1"
    local tag="$2"
    local token="$3"  # Not used in simplified version, docker handles auth
    
    local image_url="ghcr.io/milou-sh/milou/$image_name:$tag"
    
    log "DEBUG" "Checking if image exists: $image_url"
    
    # Simple check using docker manifest inspect
    if docker manifest inspect "$image_url" >/dev/null 2>&1; then
        log "DEBUG" "✅ Image exists: $image_name:$tag"
        return 0
    else
        log "DEBUG" "❌ Image not found: $image_name:$tag"
        return 1
    fi
}

# Validate all required images exist before pulling (SIMPLIFIED VERSION)
validate_images_exist() {
    local token="$1"
    local use_latest="${2:-false}"
    
    log "INFO" "Validating image availability in registry..."
    
    # Ensure authentication with GitHub Container Registry if token is provided
    if [[ -n "$token" ]]; then
        log "DEBUG" "Ensuring authentication for image validation..."
        local github_user
        github_user=$(curl -s -H "Authorization: Bearer $token" \
                     -H "Accept: application/vnd.github.v3+json" \
                     "$GITHUB_API_BASE/user" 2>/dev/null | \
                     grep -o '"login": *"[^"]*"' | cut -d'"' -f4 2>/dev/null)
        
        if [[ -n "$github_user" ]]; then
            if ! echo "$token" | docker login ghcr.io -u "$github_user" --password-stdin >/dev/null 2>&1; then
                log "WARN" "Failed to authenticate for validation - some checks may fail"
            fi
        fi
    fi
    
    local -A image_configs=(
        ["backend"]="backend"
        ["frontend"]="frontend" 
        ["engine"]="engine"
        ["nginx"]="nginx"
        ["database"]="database"
    )
    
    local -a missing_images=()
    local tag="latest"  # Default to latest for safety
    
    log "DEBUG" "validate_images_exist: use_latest parameter: '$use_latest'"
    
    # Handle both string "false" and boolean false
    if [[ "$use_latest" == "false" || "$use_latest" == false ]]; then
        tag="v1.0.0"
        log "DEBUG" "validate_images_exist: Using fixed version tag: $tag"
    else
        log "DEBUG" "validate_images_exist: Using latest tag: $tag"
    fi
    
    # Check each image quickly
    for image_key in "${!image_configs[@]}"; do
        local image_name="${image_configs[$image_key]}"
        
        log "DEBUG" "Checking $image_name:$tag..."
        if ! check_image_exists "$image_name" "$tag" "$token"; then
            missing_images+=("$image_name:$tag")
        fi
    done
    
    if [[ ${#missing_images[@]} -gt 0 ]]; then
        log "WARN" "Some images are not available in the registry:"
        for img in "${missing_images[@]}"; do
            echo "  ❌ $img"
        done
        log "INFO" "💡 This may be due to authentication issues or missing images"
        return 1
    else
        log "SUCCESS" "All required images are available in the registry"
        return 0
    fi
}

# =============================================================================
# Image Pulling Functions
# =============================================================================

# Enhanced Docker image pulling with progress feedback
pull_images() {
    local token="$1"
    local use_latest="${2:-false}"
    
    log "STEP" "Pulling Docker images from GitHub Container Registrys..."
    
    # Validate Docker access
    log "DEBUG" "Validating Docker access before pulling images..."
    if ! verify_docker_access; then
        log "ERROR" "Docker daemon is not accessible"
        
        # Provide specific diagnostics for common issues
        local current_user=$(whoami)
        log "INFO" "💡 Troubleshooting Docker access:"
        
        # Check if user is in docker group
        if ! groups "$current_user" 2>/dev/null | grep -q docker; then
            log "INFO" "   • User '$current_user' is not in docker group"
            log "INFO" "   • Solution: sudo usermod -aG docker $current_user"
            log "INFO" "   • Then logout/login or run: newgrp docker"
        else
            log "INFO" "   • User '$current_user' is in docker group"
            log "INFO" "   • Docker group membership may not be active in this session"
            log "INFO" "   • Try: newgrp docker"
        fi
        
        # Check Docker service status
        if command -v systemctl >/dev/null 2>&1; then
            if systemctl is-active docker >/dev/null 2>&1; then
                log "INFO" "   • Docker service is running"
            else
                log "INFO" "   • Docker service is not running"
                log "INFO" "   • Solution: sudo systemctl start docker"
            fi
        fi
        
        # Check Docker socket permissions
        if [[ -S "/var/run/docker.sock" ]]; then
            local socket_owner socket_group
            socket_owner=$(stat -c '%U' /var/run/docker.sock 2>/dev/null || echo "unknown")
            socket_group=$(stat -c '%G' /var/run/docker.sock 2>/dev/null || echo "unknown")
            log "INFO" "   • Docker socket owned by: $socket_owner:$socket_group"
            
            if [[ "$socket_group" != "docker" ]]; then
                log "INFO" "   • Socket group is not 'docker' - this may be the issue"
                log "INFO" "   • Solution: sudo chgrp docker /var/run/docker.sock"
            fi
        else
            log "INFO" "   • Docker socket not found at /var/run/docker.sock"
        fi
        
        return 1
    fi
    
    # Ensure Docker credentials are set up properly
    log "DEBUG" "Ensuring Docker credentials are properly configured..."
    if ! ensure_docker_credentials "$token" "false"; then
        log "WARN" "Failed to set up Docker credentials automatically"
        log "INFO" "💡 Attempting manual authentication..."
        return 1
    fi
    
    # Docker is accessible - log some basic info for debugging
    local docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
    local current_user=$(whoami)
    log "DEBUG" "Docker access successful:"
    log "DEBUG" "   • User: $current_user"
    log "DEBUG" "   • Docker version: $docker_version"
    log "DEBUG" "   • User groups: $(groups 2>/dev/null | tr ' ' ',' || echo 'unknown')"
    
    # Authenticate with GitHub Container Registry using token
    if [[ -n "$token" ]]; then
        log "DEBUG" "Authenticating with GitHub Container Registry..."
        
        # Get GitHub username from the token
        local github_user
        github_user=$(curl -s -H "Authorization: Bearer $token" \
                     -H "Accept: application/vnd.github.v3+json" \
                     "$GITHUB_API_BASE/user" 2>/dev/null | \
                     grep -o '"login": *"[^"]*"' | cut -d'"' -f4 2>/dev/null)
        
        if [[ -n "$github_user" ]]; then
            log "DEBUG" "Authenticating Docker with GitHub user: $github_user"
            
            # Force re-authentication to ensure it works after user switch
            docker logout ghcr.io >/dev/null 2>&1 || true
            
            # CRITICAL FIX: Try authentication multiple times with different approaches
            local auth_success=false
            local auth_attempts=0
            local max_auth_attempts=3
            
            while [[ $auth_attempts -lt $max_auth_attempts && "$auth_success" == false ]]; do
                ((auth_attempts++))
                log "DEBUG" "Authentication attempt $auth_attempts/$max_auth_attempts..."
                
                if echo "$token" | docker login ghcr.io -u "$github_user" --password-stdin >/dev/null 2>&1; then
                    log "DEBUG" "Docker login successful on attempt $auth_attempts"
                    
                    # Verify authentication actually works by testing a simple command
                    if docker manifest inspect ghcr.io/milou-sh/milou/backend:latest >/dev/null 2>&1; then
                        log "DEBUG" "Docker authentication verification successful"
                        auth_success=true
                    else
                        log "DEBUG" "Docker authentication verification failed, retrying..."
                        docker logout ghcr.io >/dev/null 2>&1 || true
                        sleep 1
                    fi
                else
                    log "DEBUG" "Docker login failed on attempt $auth_attempts"
                    sleep 1
                fi
            done
            
            if [[ "$auth_success" == true ]]; then
                log "SUCCESS" "Docker registry authentication successful"
            else
                log "ERROR" "Failed to authenticate with GitHub Container Registry after $max_auth_attempts attempts"
                log "INFO" "💡 Ensure your token has 'read:packages' scope"
                log "INFO" "💡 Token permissions: https://github.com/settings/tokens"
                
                # Debug information
                log "DEBUG" "Debugging authentication failure..."
                log "DEBUG" "GitHub user: $github_user"
                log "DEBUG" "Token format: $(echo "$token" | cut -c1-10)..."
                
                # Additional troubleshooting for user switching scenarios
                local current_user=$(whoami)
                log "DEBUG" "Current user: $current_user"
                log "DEBUG" "Docker config directory: $HOME/.docker"
                
                if [[ -d "$HOME/.docker" ]]; then
                    log "DEBUG" "Docker config exists, checking permissions..."
                    ls -la "$HOME/.docker" 2>/dev/null | head -5 | while read -r line; do
                        log "DEBUG" "  $line"
                    done
                else
                    log "DEBUG" "Docker config directory does not exist"
                fi
                
                return 1
            fi
        else
            log "ERROR" "Could not determine GitHub username from token"
            log "DEBUG" "GitHub API response was empty or invalid"
            return 1
        fi
    else
        log "WARN" "No GitHub token provided - attempting to pull without authentication"
        log "INFO" "💡 Private images will fail without authentication"
    fi
    
    # Define the images to pull
    local -A image_configs=(
        ["backend"]="backend"
        ["frontend"]="frontend" 
        ["engine"]="engine"
        ["nginx"]="nginx"
        ["database"]="database"
    )
    
    local -a failed_images=()
    local -a successful_images=()
    local -A pull_errors=()
    local total_images=${#image_configs[@]}
    local current=0
    
    # Determine tag to use with robust boolean handling
    local tag="latest"
    log "DEBUG" "use_latest parameter received: '$use_latest' (type: $(type -t use_latest 2>/dev/null || echo 'variable'))"
    
    # Handle both string "true" and boolean true, defaulting to latest for safety
    if [[ "$use_latest" == "false" || "$use_latest" == false ]]; then
        tag="v1.0.0"
        log "DEBUG" "Using fixed version tag: $tag"
    else
        log "DEBUG" "Using latest tag: $tag"
    fi
    
    echo
    log "INFO" "📥 Starting Docker image downloads..."
    echo
    
    # Pull all images with real-time progress feedback
    for image_key in "${!image_configs[@]}"; do
        ((current++))
        local image_name="${image_configs[$image_key]}"
        local image_url="ghcr.io/milou-sh/milou/$image_name:$tag"
        
        echo -e "${BOLD}${BLUE}📦 [$current/$total_images] Processing $image_name:$tag${NC}"
        echo -e "${DIM}Image: $image_url${NC}"
        echo
        
        # Check if image already exists locally
        if docker image inspect "$image_url" >/dev/null 2>&1; then
            echo -e "${GREEN}  ✅ Image already present locally: $image_name:$tag${NC}"
            echo -e "${DIM}  └─ Skipping download${NC}"
            successful_images+=("$image_url")
            echo
            continue
        fi
        
        # Initialize variables for pull operation
        local pull_output=""
        local pull_exit_code=0
        local temp_output
        temp_output=$(mktemp)
        
        # Enhanced error capture and progress display
        if [[ -t 1 && "${VERBOSE:-false}" != "true" ]]; then
            # Interactive mode with live progress but capture all output
            echo -e "${DIM}  └─ Downloading layers...${NC}"
            
            # Disable errexit temporarily and capture both stdout and stderr
            set +e
            docker pull --progress=plain "$image_url" > "$temp_output" 2>&1 &
            local pull_pid=$!
            
            # Show simplified progress while pull is running
            while kill -0 $pull_pid 2>/dev/null; do
                if [[ -f "$temp_output" ]]; then
                    tail -n 5 "$temp_output" 2>/dev/null | while IFS= read -r line; do
                        if [[ "$line" =~ ^#[0-9]+ ]]; then
                            local layer_info=$(echo "$line" | sed -E 's/^#[0-9]+ //' | cut -d' ' -f1-2)
                            if [[ "$layer_info" =~ (Downloading|Extracting|Pull complete) ]]; then
                                echo -ne "\r${DIM}  └─ $layer_info...${NC}"
                            fi
                        elif [[ "$line" =~ (Pulling|Waiting|Verifying|Download complete|Pull complete) ]]; then
                            echo -ne "\r${DIM}  └─ $line${NC}"
                        fi
                    done
                fi
                sleep 0.5
            done
            
            # Wait for the process to complete and get exit code
            wait $pull_pid
            pull_exit_code=$?
            set -e
            echo # New line after progress
        else
            # Non-interactive mode or verbose mode - capture all output
            echo -e "${DIM}  └─ Downloading...${NC}"
            
            # Disable errexit temporarily
            set +e
            docker pull "$image_url" > "$temp_output" 2>&1
            pull_exit_code=$?
            set -e
            
            if [[ "${VERBOSE:-false}" == "true" ]]; then
                cat "$temp_output" | sed 's/^/    /'
            else
                # Show key progress indicators for non-interactive
                cat "$temp_output" | grep -E "(Pulling|Download|Pull complete|Already exists|Error|error|unauthorized)" | while read -r line; do
                    if [[ "$line" =~ (Error|error|unauthorized|forbidden|not found) ]]; then
                        echo -e "${RED}  └─ $line${NC}"
                    else
                        echo -e "${DIM}  └─ $line${NC}"
                    fi
                done
            fi
        fi
        
        # Ensure we have the output for error reporting
        if [[ -f "$temp_output" ]]; then
            pull_output=$(cat "$temp_output" 2>/dev/null || echo "Failed to read output")
            rm -f "$temp_output"
        fi
        
        # Ensure pull_output is never empty to avoid unbound variable issues
        if [[ -z "$pull_output" ]]; then
            pull_output="No output captured from docker pull command"
        fi
        
        if [[ $pull_exit_code -eq 0 ]]; then
            echo -e "${GREEN}  ✅ Successfully pulled: $image_name:$tag${NC}"
            successful_images+=("$image_url")
        else
            echo -e "${RED}  ❌ Failed to pull: $image_name:$tag${NC}"
            
            # Enhanced error analysis and reporting
            local error_summary=""
            if echo "$pull_output" | grep -qi "unauthorized\|authentication required"; then
                error_summary="Authentication failed - check GitHub token permissions"
            elif echo "$pull_output" | grep -qi "forbidden\|access denied"; then
                error_summary="Access denied - insufficient token permissions"
            elif echo "$pull_output" | grep -qi "not found\|no such"; then
                error_summary="Image not found - check image name and tag"
            elif echo "$pull_output" | grep -qi "network\|timeout\|connection"; then
                error_summary="Network error - check connectivity"
            elif echo "$pull_output" | grep -qi "disk\|space"; then
                error_summary="Insufficient disk space"
            else
                error_summary="Unknown error - see details below"
            fi
            
            echo -e "${RED}    └─ $error_summary${NC}"
            pull_errors["$image_name"]="$pull_output"
            failed_images+=("$image_name:$tag")
            
            # Always show critical errors even in non-verbose mode
            if echo "$pull_output" | grep -qi "unauthorized\|forbidden\|not found"; then
                echo -e "${DIM}    └─ Error details: $(echo "$pull_output" | grep -i "error\|unauthorized\|forbidden\|not found" | head -1)${NC}"
            fi
        fi
        
        echo # Spacing between images
    done
    
    # Summary reporting
    echo
    echo -e "${BOLD}📊 Image Pull Summary:${NC}"
    echo -e "  ${GREEN}✅ Successful: ${#successful_images[@]}/$total_images${NC}"
    echo -e "  ${RED}❌ Failed: ${#failed_images[@]}/$total_images${NC}"
    echo
    
    if [[ ${#successful_images[@]} -gt 0 ]]; then
        echo -e "${BOLD}${GREEN}Successfully pulled images:${NC}"
        for img in "${successful_images[@]}"; do
            echo "  ✅ $img"
        done
        echo
    fi
    
    if [[ ${#failed_images[@]} -gt 0 ]]; then
        echo -e "${BOLD}${RED}Failed to pull images:${NC}"
        for img in "${failed_images[@]}"; do
            echo "  ❌ $img"
        done
        echo
        
        # Show detailed errors with enhanced formatting
        echo -e "${BOLD}${RED}Error Details:${NC}"
        for image_name in "${!pull_errors[@]}"; do
            echo -e "${BOLD}$image_name:${NC}"
            local error_text="${pull_errors[$image_name]}"
            
            # Show most relevant error lines first
            echo "$error_text" | grep -i "error\|unauthorized\|forbidden\|not found" | head -3 | sed 's/^/  /' || true
            
            if [[ "${VERBOSE:-false}" == "true" ]]; then
                echo -e "${DIM}Full output:${NC}"
                echo "$error_text" | sed 's/^/    /'
            fi
            echo
        done
        
        # Provide helpful troubleshooting suggestions
        echo -e "${BOLD}${YELLOW}💡 Troubleshooting Suggestions:${NC}"
        if grep -qi "unauthorized\|authentication" <<< "${pull_errors[*]}"; then
            echo "  🔑 Authentication issue detected:"
            echo "     • Verify GitHub token has 'read:packages' scope"
            echo "     • Check token expiration"
            echo "     • Try re-running: docker login ghcr.io"
        fi
        if grep -qi "forbidden\|access denied" <<< "${pull_errors[*]}"; then
            echo "  🚫 Access denied:"
            echo "     • Ensure token has access to milou-sh organization"
            echo "     • Verify repository visibility settings"
        fi
        if grep -qi "not found" <<< "${pull_errors[*]}"; then
            echo "  📦 Image not found:"
            echo "     • Check if images exist with the specified tag ($tag)"
            echo "     • Try with different tag (e.g., v1.0.0, main)"
        fi
        echo
        
        return 1
    else
        echo -e "${BOLD}${GREEN}🎉 All Docker images pulled successfully!${NC}"
        echo
        return 0
    fi
}

# =============================================================================
# Debug Functions
# =============================================================================

# Debug Docker image availability (SIMPLIFIED VERSION)
debug_docker_images() {
    local token="$1"
    
    if [[ -z "$token" ]]; then
        log "ERROR" "GitHub token is required for debugging"
        return 1
    fi
    
    log "STEP" "Debugging Docker image availability (simplified)..."
    echo
    
    # Test Docker daemon
    log "INFO" "1. Testing Docker daemon..."
    if docker info >/dev/null 2>&1; then
        log "SUCCESS" "✅ Docker daemon accessible"
    else
        log "ERROR" "❌ Docker daemon not accessible"
        return 1
    fi
    echo
    
    # Test simple image checks
    log "INFO" "2. Testing image availability..."
    local -A image_configs=(
        ["backend"]="backend"
        ["frontend"]="frontend" 
        ["engine"]="engine"
        ["nginx"]="nginx"
        ["database"]="database"
    )
    
    local all_good=true
    
    for image_name in "${image_configs[@]}"; do
        local image_url="ghcr.io/milou-sh/milou/$image_name:latest"
        log "INFO" "Testing $image_name:latest..."
        
        if docker manifest inspect "$image_url" >/dev/null 2>&1; then
            log "SUCCESS" "  ✅ Available: $image_name:latest"
        else
            log "ERROR" "  ❌ Not available: $image_name:latest"
            all_good=false
        fi
    done
    
    echo
    if [[ "$all_good" == true ]]; then
        log "SUCCESS" "All images are available! Setup should work."
    else
        log "ERROR" "Some images are missing. Check your GitHub token permissions."
    fi
    
    return $([[ "$all_good" == true ]] && echo 0 || echo 1)
}

# =============================================================================
# Enhanced Image Management Functions
# =============================================================================

# Try multiple image tags with fallback strategy
try_pull_with_fallback() {
    local image_name="$1"
    local primary_tag="$2"
    local token="$3"
    
    log "DEBUG" "Attempting to pull $image_name with fallback strategy..."
    
    # Define fallback tag order
    local -a tag_candidates=()
    
    if [[ "$primary_tag" == "latest" ]]; then
        tag_candidates=("latest" "main" "master" "v1.0.0" "stable")
    elif [[ "$primary_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        tag_candidates=("$primary_tag" "latest" "main" "master")
    else
        tag_candidates=("$primary_tag" "latest" "main")
    fi
    
    for tag in "${tag_candidates[@]}"; do
        local image_url="ghcr.io/milou-sh/milou/$image_name:$tag"
        log "DEBUG" "Trying $image_url..."
        
        # Check if image exists first
        if docker manifest inspect "$image_url" >/dev/null 2>&1; then
            log "DEBUG" "Found available tag: $tag for $image_name"
            
            # Try to pull the image
            if docker pull "$image_url" >/dev/null 2>&1; then
                log "SUCCESS" "Successfully pulled $image_name:$tag"
                return 0
            else
                log "DEBUG" "Pull failed for $image_name:$tag despite manifest existing"
            fi
        else
            log "DEBUG" "Tag $tag not available for $image_name"
        fi
    done
    
    log "ERROR" "Failed to pull $image_name with any available tag"
    return 1
}

# Enhanced image availability check with multiple strategies
enhanced_image_check() {
    local image_name="$1"
    local tag="$2"
    local token="$3"
    
    local image_url="ghcr.io/milou-sh/milou/$image_name:$tag"
    
    # Strategy 1: Simple manifest check
    if docker manifest inspect "$image_url" >/dev/null 2>&1; then
        return 0
    fi
    
    # Strategy 2: Try with authentication if token is available
    if [[ -n "$token" ]]; then
        local github_user
        github_user=$(curl -s -H "Authorization: Bearer $token" \
                     -H "Accept: application/vnd.github.v3+json" \
                     "$GITHUB_API_BASE/user" 2>/dev/null | \
                     grep -o '"login": *"[^"]*"' | cut -d'"' -f4 2>/dev/null)
        
        if [[ -n "$github_user" ]] && echo "$token" | docker login ghcr.io -u "$github_user" --password-stdin >/dev/null 2>&1; then
            if docker manifest inspect "$image_url" >/dev/null 2>&1; then
                return 0
            fi
        fi
    fi
    
    return 1
}

# =============================================================================
# Docker Access Verification Functions
# =============================================================================

# Verify Docker access with comprehensive troubleshooting
verify_docker_access() {
    local user="${1:-$(whoami)}"
    
    log "DEBUG" "Verifying Docker access for user: $user"
    
    # Test 1: Basic Docker daemon connectivity
    if ! docker info >/dev/null 2>&1; then
        log "DEBUG" "Docker daemon is not accessible"
        
        # Detailed diagnosis
        local current_user=$(whoami)
        log "DEBUG" "Current user: $current_user"
        
        # Check if user is in docker group
        if ! groups "$current_user" 2>/dev/null | grep -q docker; then
            log "DEBUG" "User '$current_user' is not in docker group"
            return 1
        fi
        
        # Check Docker socket permissions
        if [[ -S "/var/run/docker.sock" ]]; then
            local socket_perms
            socket_perms=$(ls -la /var/run/docker.sock 2>/dev/null || echo "unknown")
            log "DEBUG" "Docker socket permissions: $socket_perms"
        else
            log "DEBUG" "Docker socket not found at /var/run/docker.sock"
        fi
        
        # Check Docker service status
        if command -v systemctl >/dev/null 2>&1; then
            if systemctl is-active docker >/dev/null 2>&1; then
                log "DEBUG" "Docker service is active"
            else
                log "DEBUG" "Docker service is not active"
                return 1
            fi
        fi
        
        return 1
    fi
    
    # Test 2: Docker registry connectivity
    if ! docker search --limit 1 hello-world >/dev/null 2>&1; then
        log "DEBUG" "Docker registry connectivity test failed"
        # This is not critical, continue
    fi
    
    log "DEBUG" "Docker access verification successful for user: $user"
    return 0
}

# Ensure Docker credentials are properly configured for current user
ensure_docker_credentials() {
    local github_token="$1"
    local force_reauth="${2:-false}"
    
    if [[ -z "$github_token" ]]; then
        log "DEBUG" "No GitHub token provided for Docker authentication"
        return 0
    fi
    
    local current_user=$(whoami)
    log "DEBUG" "Ensuring Docker credentials for user: $current_user"
    
    # Check if Docker config directory exists
    local docker_config_dir="$HOME/.docker"
    if [[ ! -d "$docker_config_dir" ]]; then
        log "DEBUG" "Creating Docker config directory: $docker_config_dir"
        mkdir -p "$docker_config_dir"
        chmod 700 "$docker_config_dir"
    fi
    
    # Check if we already have valid credentials
    local config_file="$docker_config_dir/config.json"
    if [[ -f "$config_file" && "$force_reauth" != "true" ]]; then
        if grep -q "ghcr.io" "$config_file" 2>/dev/null; then
            log "DEBUG" "Docker credentials already exist for ghcr.io"
            
            # Quick test to see if they work
            if docker manifest inspect ghcr.io/milou-sh/milou/backend:latest >/dev/null 2>&1; then
                log "DEBUG" "Existing Docker credentials are functional"
                return 0
            else
                log "DEBUG" "Existing Docker credentials are not functional, re-authenticating..."
            fi
        fi
    fi
    
    # Authenticate with GitHub Container Registry
    log "DEBUG" "Authenticating Docker with GitHub Container Registry..."
    
    # Get GitHub username
    local github_user
    github_user=$(curl -s -H "Authorization: Bearer $github_token" \
                 -H "Accept: application/vnd.github.v3+json" \
                 "$GITHUB_API_BASE/user" 2>/dev/null | \
                 grep -o '"login": *"[^"]*"' | cut -d'"' -f4 2>/dev/null)
    
    if [[ -z "$github_user" ]]; then
        log "DEBUG" "Could not determine GitHub username from token"
        return 1
    fi
    
    # Perform authentication
    if echo "$github_token" | docker login ghcr.io -u "$github_user" --password-stdin >/dev/null 2>&1; then
        log "DEBUG" "Docker authentication successful for user: $github_user"
        
        # Verify it works
        if docker manifest inspect ghcr.io/milou-sh/milou/backend:latest >/dev/null 2>&1; then
            log "DEBUG" "Docker authentication verification successful"
            return 0
        else
            log "DEBUG" "Docker authentication verification failed"
            return 1
        fi
    else
        log "DEBUG" "Docker authentication failed"
        return 1
    fi
} 