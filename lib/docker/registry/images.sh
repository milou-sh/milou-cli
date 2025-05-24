#!/bin/bash

# =============================================================================
# Docker Registry Image Management for Milou CLI
# Handles image tag discovery, validation, and pulling operations
# =============================================================================

# Module guard to prevent multiple loading
if [[ "${MILOU_DOCKER_REGISTRY_IMAGES_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_DOCKER_REGISTRY_IMAGES_LOADED="true"

# Ensure logging is available
if ! command -v milou_log >/dev/null 2>&1; then
    source "${SCRIPT_DIR}/lib/core/logging.sh" 2>/dev/null || {
        echo "ERROR: Cannot load logging module" >&2
        exit 1
    }
fi

# Constants
GITHUB_REGISTRY="${GITHUB_REGISTRY:-ghcr.io/milou-sh/milou}"
GITHUB_API_BASE="${GITHUB_API_BASE:-https://api.github.com}"

# =============================================================================
# Image Tag Discovery Functions
# =============================================================================

# Get available image tags from GitHub Container Registry
get_available_image_tags() {
    local image_name="$1"
    local token="$2"
    
    milou_log "DEBUG" "Fetching available tags for $image_name..."
    
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
            milou_log "DEBUG" "Trying API endpoint: $api_url"
            
            local response
            if response=$(curl -s -w "\n%{http_code}" \
                         -H "Authorization: Bearer $token" \
                         -H "Accept: application/vnd.github.v3+json" \
                         -H "X-GitHub-Api-Version: 2022-11-28" \
                         "$api_url" 2>/dev/null); then
                
                local http_code=$(echo "$response" | tail -n1)
                local body=$(echo "$response" | head -n -1)
                
                milou_log "DEBUG" "HTTP response code: $http_code for pattern: $pattern"
                
                if [[ "$http_code" == "200" ]]; then
                    milou_log "DEBUG" "Successfully fetched package data from: $api_url"
                    
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
                        milou_log "DEBUG" "Found tags via API: $(echo "$tags" | head -10 | tr '\n' ' ')$([ $(echo "$tags" | wc -l) -gt 10 ] && echo "...")"
                        echo "$tags"
                        return 0
                    else
                        milou_log "DEBUG" "API returned data but no tags were extracted"
                        milou_log "DEBUG" "Response sample: $(echo "$body" | head -c 200)..."
                    fi
                elif [[ "$http_code" == "401" ]]; then
                    milou_log "DEBUG" "Authentication failed for: $api_url"
                elif [[ "$http_code" == "403" ]]; then
                    milou_log "DEBUG" "Access forbidden for: $api_url (token may lack permissions)"
                elif [[ "$http_code" == "404" ]]; then
                    milou_log "DEBUG" "Package not found at: $api_url (pattern: $pattern)"
                else
                    milou_log "DEBUG" "Unexpected response ($http_code) from: $api_url"
                fi
            else
                milou_log "DEBUG" "Failed to fetch from: $api_url"
            fi
        done
    done
    
    # Fallback: try Docker registry API directly
    milou_log "DEBUG" "API methods failed, trying Docker registry API fallback..."
    
    local registry_url="https://ghcr.io/v2/milou-sh/milou/${image_name}/tags/list"
    milou_log "DEBUG" "Trying registry API: $registry_url"
    
    local registry_response
    if registry_response=$(curl -s -H "Authorization: Bearer $token" "$registry_url" 2>/dev/null); then
        if command -v jq >/dev/null 2>&1; then
            local registry_tags
            registry_tags=$(echo "$registry_response" | jq -r '.tags[]?' 2>/dev/null | sort -V || echo "")
            if [[ -n "$registry_tags" ]]; then
                milou_log "DEBUG" "Found tags via registry API: $(echo "$registry_tags" | head -5 | tr '\n' ' ')..."
                echo "$registry_tags"
                return 0
            fi
        fi
    fi
    
    milou_log "DEBUG" "No tags found for $image_name"
    return 1
}

# Get the latest stable image tag
get_latest_image_tag() {
    local image_name="$1"
    local token="$2"
    local prefer_stable="${3:-true}"
    
    milou_log "DEBUG" "Getting latest tag for $image_name (prefer_stable: $prefer_stable)"
    
    local available_tags
    available_tags=$(get_available_image_tags "$image_name" "$token")
    
    if [[ -z "$available_tags" ]]; then
        milou_log "DEBUG" "No tags available for $image_name"
        return 1
    fi
    
    milou_log "DEBUG" "Available tags: $(echo "$available_tags" | head -5 | tr '\n' ' ')..."
    
    # Filter and prioritize tags
    local latest_tag=""
    
    if [[ "$prefer_stable" == "true" ]]; then
        # Look for stable version tags first (semantic versioning)
        latest_tag=$(echo "$available_tags" | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
        
        # If no semantic version found, look for release tags
        if [[ -z "$latest_tag" ]]; then
            latest_tag=$(echo "$available_tags" | grep -E '^(release|stable|prod)' | sort -V | tail -1)
        fi
        
        # If still no stable tag, look for latest tag
        if [[ -z "$latest_tag" ]]; then
            latest_tag=$(echo "$available_tags" | grep -E '^latest$' | head -1)
        fi
    fi
    
    # If no stable tag found or prefer_stable is false, get the most recent tag
    if [[ -z "$latest_tag" ]]; then
        # Exclude development/test tags
        latest_tag=$(echo "$available_tags" | grep -vE '(dev|test|debug|alpha|beta|rc|snapshot|nightly)' | sort -V | tail -1)
    fi
    
    # Last resort: just get the latest tag regardless
    if [[ -z "$latest_tag" ]]; then
        latest_tag=$(echo "$available_tags" | sort -V | tail -1)
    fi
    
    if [[ -n "$latest_tag" ]]; then
        milou_log "DEBUG" "Selected latest tag: $latest_tag"
        echo "$latest_tag"
        return 0
    else
        milou_log "DEBUG" "Could not determine latest tag for $image_name"
        return 1
    fi
}

# =============================================================================
# Image Validation Functions
# =============================================================================

# Check if a specific image exists in the registry
check_image_exists() {
    local image_name="$1"
    local tag="$2"
    local token="$3"
    
    milou_log "DEBUG" "Checking if image exists: $image_name:$tag"
    
    # Try to get the manifest for the specific tag
    local manifest_url="https://ghcr.io/v2/milou-sh/milou/${image_name}/manifests/${tag}"
    
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" \
               -H "Authorization: Bearer $token" \
               -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
               "$manifest_url" 2>/dev/null)
    
    if [[ "$response" == "200" ]]; then
        milou_log "DEBUG" "Image exists: $image_name:$tag"
        return 0
    else
        milou_log "DEBUG" "Image not found: $image_name:$tag (HTTP: $response)"
        return 1
    fi
}

# Validate that all required images exist
validate_images_exist() {
    local token="$1"
    shift
    local images=("$@")
    
    milou_log "STEP" "Validating image availability..."
    
    local missing_images=()
    local validated_images=()
    
    for image_spec in "${images[@]}"; do
        # Parse image specification (name:tag or just name)
        local image_name tag
        if [[ "$image_spec" == *":"* ]]; then
            image_name="${image_spec%:*}"
            tag="${image_spec#*:}"
        else
            image_name="$image_spec"
            # Try to get latest tag
            tag=$(get_latest_image_tag "$image_name" "$token")
            if [[ -z "$tag" ]]; then
                tag="latest"
            fi
        fi
        
        milou_log "DEBUG" "Validating: $image_name:$tag"
        
        if check_image_exists "$image_name" "$tag" "$token"; then
            validated_images+=("$image_name:$tag")
            milou_log "SUCCESS" "✅ $image_name:$tag"
        else
            missing_images+=("$image_name:$tag")
            milou_log "ERROR" "❌ $image_name:$tag"
        fi
    done
    
    if [[ ${#missing_images[@]} -eq 0 ]]; then
        milou_log "SUCCESS" "All images are available"
        return 0
    else
        milou_log "ERROR" "Missing images: ${missing_images[*]}"
        
        # Suggest available alternatives
        for missing in "${missing_images[@]}"; do
            local missing_name="${missing%:*}"
            milou_log "INFO" "Available tags for $missing_name:"
            local available_tags
            available_tags=$(get_available_image_tags "$missing_name" "$token")
            if [[ -n "$available_tags" ]]; then
                echo "$available_tags" | head -5 | while read -r tag; do
                    milou_log "INFO" "  • $missing_name:$tag"
                done
                if [[ $(echo "$available_tags" | wc -l) -gt 5 ]]; then
                    milou_log "INFO" "  ... and $(($(echo "$available_tags" | wc -l) - 5)) more"
                fi
            else
                milou_log "INFO" "  No tags found"
            fi
        done
        
        return 1
    fi
}

# Enhanced image check with detailed information
enhanced_image_check() {
    local image_name="$1"
    local tag="$2"
    local token="$3"
    
    milou_log "DEBUG" "Enhanced check for: $image_name:$tag"
    
    # Get manifest information
    local manifest_url="https://ghcr.io/v2/milou-sh/milou/${image_name}/manifests/${tag}"
    
    local manifest_response
    manifest_response=$(curl -s -w "\n%{http_code}" \
                       -H "Authorization: Bearer $token" \
                       -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
                       "$manifest_url" 2>/dev/null)
    
    local http_code=$(echo "$manifest_response" | tail -n1)
    local manifest_body=$(echo "$manifest_response" | head -n -1)
    
    if [[ "$http_code" == "200" ]]; then
        milou_log "DEBUG" "Manifest retrieved successfully"
        
        # Extract image information
        local image_size=""
        local created_date=""
        local architecture=""
        
        if command -v jq >/dev/null 2>&1; then
            # Get total size
            image_size=$(echo "$manifest_body" | jq -r '.config.size // empty' 2>/dev/null)
            
            # Get architecture
            architecture=$(echo "$manifest_body" | jq -r '.architecture // empty' 2>/dev/null)
        fi
        
        milou_log "INFO" "📦 Image Details: $image_name:$tag"
        [[ -n "$architecture" ]] && milou_log "INFO" "  Architecture: $architecture"
        [[ -n "$image_size" ]] && milou_log "INFO" "  Config Size: $image_size bytes"
        
        return 0
    else
        milou_log "DEBUG" "Enhanced check failed: HTTP $http_code"
        return 1
    fi
}

# =============================================================================
# Image Pulling Functions
# =============================================================================

# Pull images with comprehensive error handling and progress tracking
pull_images() {
    local token="$1"
    shift
    local images=("$@")
    
    milou_log "STEP" "Pulling Docker images..."
    
    # Validate Docker is available
    if ! command -v docker >/dev/null 2>&1; then
        milou_log "ERROR" "Docker is not installed or not in PATH"
        return 1
    fi
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        milou_log "ERROR" "Docker daemon is not running"
        return 1
    fi
    
    local failed_pulls=()
    local successful_pulls=()
    
    for image_spec in "${images[@]}"; do
        # Parse image specification
        local image_name tag full_image_name
        if [[ "$image_spec" == *":"* ]]; then
            image_name="${image_spec%:*}"
            tag="${image_spec#*:}"
        else
            image_name="$image_spec"
            tag=$(get_latest_image_tag "$image_name" "$token")
            if [[ -z "$tag" ]]; then
                tag="latest"
            fi
        fi
        
        full_image_name="$GITHUB_REGISTRY/$image_name:$tag"
        
        milou_log "INFO" "Pulling: $full_image_name"
        
        # Try to pull the image
        if try_pull_with_fallback "$full_image_name" "$token"; then
            successful_pulls+=("$full_image_name")
            milou_log "SUCCESS" "✅ Successfully pulled: $full_image_name"
        else
            failed_pulls+=("$full_image_name")
            milou_log "ERROR" "❌ Failed to pull: $full_image_name"
        fi
    done
    
    # Summary
    echo
    milou_log "INFO" "📊 Pull Summary:"
    milou_log "INFO" "  ✅ Successful: ${#successful_pulls[@]}"
    milou_log "INFO" "  ❌ Failed: ${#failed_pulls[@]}"
    
    if [[ ${#successful_pulls[@]} -gt 0 ]]; then
        milou_log "INFO" "Successfully pulled images:"
        for image in "${successful_pulls[@]}"; do
            milou_log "INFO" "  • $image"
        done
    fi
    
    if [[ ${#failed_pulls[@]} -gt 0 ]]; then
        milou_log "ERROR" "Failed to pull images:"
        for image in "${failed_pulls[@]}"; do
            milou_log "ERROR" "  • $image"
        done
        return 1
    fi
    
    return 0
}

# Try to pull image with fallback strategies
try_pull_with_fallback() {
    local full_image_name="$1"
    local token="$2"
    
    milou_log "DEBUG" "Attempting to pull: $full_image_name"
    
    # Strategy 1: Direct pull (if already authenticated)
    if docker pull "$full_image_name" >/dev/null 2>&1; then
        milou_log "DEBUG" "Direct pull successful"
        return 0
    fi
    
    # Strategy 2: Authenticate and pull
    milou_log "DEBUG" "Direct pull failed, trying with authentication..."
    
    # Extract username from token (if possible)
    local username=""
    if [[ -n "$token" ]]; then
        # Try to get username from GitHub API
        local user_response
        user_response=$(curl -s -H "Authorization: Bearer $token" \
                       -H "Accept: application/vnd.github.v3+json" \
                       "$GITHUB_API_BASE/user" 2>/dev/null)
        
        if echo "$user_response" | grep -q '"login"'; then
            username=$(echo "$user_response" | grep -o '"login": *"[^"]*"' | cut -d'"' -f4)
            milou_log "DEBUG" "Detected username: $username"
        fi
    fi
    
    # Use a default username if we couldn't detect one
    if [[ -z "$username" ]]; then
        username="token"
        milou_log "DEBUG" "Using default username: $username"
    fi
    
    # Authenticate with Docker registry
    if echo "$token" | docker login ghcr.io -u "$username" --password-stdin >/dev/null 2>&1; then
        milou_log "DEBUG" "Docker authentication successful"
        
        # Try pull again
        if docker pull "$full_image_name" >/dev/null 2>&1; then
            milou_log "DEBUG" "Authenticated pull successful"
            return 0
        else
            milou_log "DEBUG" "Authenticated pull failed"
        fi
    else
        milou_log "DEBUG" "Docker authentication failed"
    fi
    
    # Strategy 3: Try alternative image names
    milou_log "DEBUG" "Trying alternative image names..."
    
    local base_name="${full_image_name##*/}"  # Remove registry prefix
    local alt_names=(
        "ghcr.io/milou-sh/$base_name"
        "ghcr.io/milou/$base_name"
        "$base_name"
    )
    
    for alt_name in "${alt_names[@]}"; do
        if [[ "$alt_name" != "$full_image_name" ]]; then
            milou_log "DEBUG" "Trying alternative: $alt_name"
            if docker pull "$alt_name" >/dev/null 2>&1; then
                milou_log "DEBUG" "Alternative pull successful: $alt_name"
                # Tag it with the expected name
                docker tag "$alt_name" "$full_image_name" >/dev/null 2>&1
                return 0
            fi
        fi
    done
    
    milou_log "DEBUG" "All pull strategies failed for: $full_image_name"
    return 1
}

milou_log "DEBUG" "Docker registry image management module loaded successfully" 