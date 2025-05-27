#!/bin/bash

# =============================================================================
# Docker Registry Authentication for Milou CLI
# Extracted from registry.sh for better maintainability
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Constants (use defaults if not already set)
GITHUB_REGISTRY="${GITHUB_REGISTRY:-ghcr.io/milou-sh/milou}"
GITHUB_API_BASE="${GITHUB_API_BASE:-https://api.github.com}"

# =============================================================================
# GitHub Authentication Functions
# =============================================================================

# REMOVED: validate_github_token() - now consolidated in lib/core/validation.sh
# Use milou_validate_github_token() instead

# Test GitHub token authentication
test_github_authentication() {
    local token="$1"
    
    milou_log "STEP" "Testing GitHub authentication..."
    milou_log "DEBUG" "Token validation: length=${#token}, preview=${token:0:10}..."
    
    # Validate token format first (using consolidated function)
    if ! milou_validate_github_token "$token" "true"; then
    milou_log "DEBUG" "Token format validation failed"
        return 1
    fi
    
    milou_log "DEBUG" "Token format validation passed"
    
    # Test authentication with GitHub API
    milou_log "DEBUG" "Testing API call to: $GITHUB_API_BASE/user"
    milou_log "DEBUG" "Current user: $(whoami)"
    milou_log "DEBUG" "Current working directory: $(pwd)"
    milou_log "DEBUG" "PATH: $PATH"
    milou_log "DEBUG" "curl version: $(curl --version 2>/dev/null | head -1 || echo 'curl not found')"
    
    # Test basic curl functionality first
    milou_log "DEBUG" "Testing basic curl to httpbin.org..."
    local test_response
    test_response=$(curl -s --connect-timeout 5 --max-time 10 "https://httpbin.org/get" 2>/dev/null)
    local test_exit_code=$?
    milou_log "DEBUG" "Basic curl test - exit code: $test_exit_code, response length: ${#test_response}"
    
    local response
    local curl_error
    curl_error=$(mktemp)
    
    # Disable errexit temporarily to capture curl errors properly
    set +e
    response=$(curl -s -H "Authorization: Bearer $token" \
               -H "Accept: application/vnd.github.v3+json" \
               "$GITHUB_API_BASE/user" 2>"$curl_error")
    local curl_exit_code=$?
    set -e
    
    if [[ $curl_exit_code -ne 0 ]]; then
    milou_log "ERROR" "Failed to connect to GitHub API"
    milou_log "DEBUG" "curl command failed with exit code: $curl_exit_code"
    milou_log "DEBUG" "curl stderr: $(cat "$curl_error" 2>/dev/null || echo 'no error output')"
        rm -f "$curl_error"
        return 1
    fi
    
    rm -f "$curl_error"
    
    milou_log "DEBUG" "API call succeeded, response length: ${#response}"
    
    # Check if authentication was successful
    if echo "$response" | grep -q '"login"'; then
        local username
        username=$(echo "$response" | grep -o '"login": *"[^"]*"' | cut -d'"' -f4)
    milou_log "SUCCESS" "GitHub authentication successful (user: $username)"
        
        # Test Docker registry authentication
    milou_log "DEBUG" "Testing Docker registry authentication..."
        if echo "$token" | docker login ghcr.io -u "$username" --password-stdin >/dev/null 2>&1; then
    milou_log "SUCCESS" "Docker registry authentication successful"
            return 0
        else
    milou_log "ERROR" "Docker registry authentication failed"
    milou_log "INFO" "💡 Ensure your token has 'read:packages' and 'write:packages' scopes"
            return 1
        fi
    else
    milou_log "ERROR" "GitHub authentication failed"
    milou_log "DEBUG" "API Response: $response"
        
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
# Image Tag Management
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
    
    milou_log "DEBUG" "No tags found for $image_name from any GitHub Packages API endpoint"
    return 1
}

# =============================================================================
# Export Functions
# =============================================================================

# validate_github_token removed - use milou_validate_github_token from core/validation.sh
export -f test_github_authentication
export -f get_available_image_tags 