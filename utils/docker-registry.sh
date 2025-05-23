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
    
    log "STEP" "Pulling Docker images from GitHub Container Registry..."
    
    # Fix the log message to use robust boolean logic
    local strategy_message="Latest versions"
    if [[ "$use_latest" == "false" || "$use_latest" == false ]]; then
        strategy_message="Fixed version (v1.0.0)"
    fi
    log "INFO" "Image versioning strategy: $strategy_message"
    
    # Validate Docker access
    if ! docker info >/dev/null 2>&1; then
        log "ERROR" "Docker daemon is not accessible"
        return 1
    fi
    
    # Ensure authentication with GitHub Container Registry
    log "DEBUG" "Ensuring GitHub Container Registry authentication..."
    if [[ -n "$token" ]]; then
        # Get GitHub username for authentication
        local github_user
        github_user=$(curl -s -H "Authorization: Bearer $token" \
                     -H "Accept: application/vnd.github.v3+json" \
                     "$GITHUB_API_BASE/user" 2>/dev/null | \
                     grep -o '"login": *"[^"]*"' | cut -d'"' -f4 2>/dev/null)
        
        if [[ -n "$github_user" ]]; then
            log "DEBUG" "Authenticating Docker with GitHub user: $github_user"
            if echo "$token" | docker login ghcr.io -u "$github_user" --password-stdin >/dev/null 2>&1; then
                log "SUCCESS" "Docker registry authentication successful"
            else
                log "ERROR" "Failed to authenticate with GitHub Container Registry"
                log "INFO" "💡 Ensure your token has 'read:packages' scope"
                return 1
            fi
        else
            log "ERROR" "Could not determine GitHub username from token"
            return 1
        fi
    else
        log "WARN" "No GitHub token provided - attempting to pull without authentication"
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
            {
                docker pull --progress=plain "$image_url" 2>&1 | tee "$temp_output" | while IFS= read -r line; do
                    # Filter and format progress output for better readability
                    if [[ "$line" =~ ^#[0-9]+ ]]; then
                        # Layer progress lines - show simplified version
                        local layer_info=$(echo "$line" | sed -E 's/^#[0-9]+ //' | cut -d' ' -f1-2)
                        if [[ "$layer_info" =~ (Downloading|Extracting|Pull complete) ]]; then
                            echo -ne "\r${DIM}  └─ $layer_info...${NC}"
                        fi
                    elif [[ "$line" =~ (Pulling|Waiting|Verifying|Download complete|Pull complete) ]]; then
                        echo -ne "\r${DIM}  └─ $line${NC}"
                    elif [[ "$line" =~ (Error|error|unauthorized|forbidden|not found) ]]; then
                        echo -e "\n${RED}  └─ $line${NC}"
                    fi
                done
            }
            pull_exit_code=$?
            set -e
            echo # New line after progress
        else
            # Non-interactive mode or verbose mode - capture all output
            echo -e "${DIM}  └─ Downloading...${NC}"
            
            # Disable errexit temporarily
            set +e
            pull_output=$(docker pull "$image_url" 2>&1 | tee "$temp_output")
            pull_exit_code=$?
            set -e
            
            if [[ "${VERBOSE:-false}" == "true" ]]; then
                echo "$pull_output" | sed 's/^/    /'
            else
                # Show key progress indicators for non-interactive
                echo "$pull_output" | grep -E "(Pulling|Download|Pull complete|Already exists|Error|error|unauthorized)" | while read -r line; do
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