#!/bin/bash

# =============================================================================
# Milou CLI - Docker Build and Push Script
# Builds and pushes Docker images to GitHub Container Registry (GHCR)
# Supports versioning, smart rebuilds, selective building, and image management
# =============================================================================

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Global variables
GITHUB_ORG="milou-sh"
REPO_NAME="milou"
VERSION=""
SERVICE=""
PUSH_TO_REGISTRY=false
FORCE_BUILD=false
DRY_RUN=false
CHECK_DIFF=true
BUILD_ALL=false
DELETE_IMAGES=false
LIST_IMAGES=false
GITHUB_TOKEN_PROVIDED=""
SAVE_TOKEN=false
NON_INTERACTIVE=false

# Available services and their configurations
declare -A SERVICES=(
    ["database"]="./docker/database/Dockerfile|./docker/database"
    ["backend"]="./dashboard/backend/Dockerfile.backend|./dashboard"
    ["frontend"]="./dashboard/frontend/Dockerfile.frontend|./dashboard"
    ["engine"]="./engine/Dockerfile|./engine"
    ["nginx"]="./docker/nginx/Dockerfile|./docker/nginx"
)

# Logging functions
milou_log() {
    local level="$1"
    shift
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $*" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $*" >&2 ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $*" >&2 ;;
        "DEBUG") [[ "${DEBUG:-}" == "true" ]] && echo -e "${BLUE}[DEBUG]${NC} $*" >&2 ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $*" ;;
        "STEP") echo -e "${BLUE}[STEP]${NC} $*" ;;
        "TRACE") [[ "${DEBUG:-}" == "true" ]] && echo -e "${BLUE}[TRACE]${NC} $*" >&2 ;;
    esac
}

# Source validation functions from main Milou CLI if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MILOU_CLI_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$MILOU_CLI_DIR/src/_validation.sh" ]]; then
    source "$MILOU_CLI_DIR/src/_validation.sh"
fi

# Enhanced GitHub token validation (fallback if not available from main CLI)
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

# Test GitHub authentication with API and Docker registry (fallback if not available)
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
        
        # Set the username for later use
        export GITHUB_USERNAME="$username"
        
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

# Show help
show_help() {
    echo -e "${BOLD}Milou Docker Build and Push Script${NC}"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --service SERVICE     Build specific service (database, backend, frontend, engine, nginx)"
    echo "  --version VERSION     Tag with version number (e.g., 1.0.0)"
    echo "  --all                 Build all services"
    echo "  --push                Push to GHCR after building"
    echo "  --force               Force rebuild even if image exists and is recent"
    echo "  --no-diff-check       Skip checking for source code differences"
    echo "  --list-images         List all images in GHCR with tags"
    echo "  --delete-images       Delete images from GHCR (interactive)"
    echo "  --token TOKEN         GitHub Personal Access Token"
    echo "  --save-token          Save provided token to .env file"
    echo "  --non-interactive     Run in non-interactive mode (fail if no token)"
    echo "  --org ORG             GitHub organization (default: milou-sh)"
    echo "  --repo REPO           Repository name (default: milou)"
    echo "  --dry-run             Show what would be done without executing"
    echo "  --debug               Enable debug logging"
    echo "  --help, -h            Show this help"
    echo
    echo "Token Authentication:"
    echo "  The script needs a GitHub Personal Access Token with these scopes:"
    echo "  • read:packages (to pull Docker images)"
    echo "  • write:packages (to push Docker images)"
    echo "  • delete:packages (to delete images, if needed)"
    echo
    echo "  You can provide the token via:"
    echo "  1. --token TOKEN                  (command line argument)"
    echo "  2. GITHUB_TOKEN=token ./script    (environment variable)"
    echo "  3. Interactive prompt             (if neither above is provided)"
    echo "  4. .env file in project root      (GITHUB_TOKEN=token)"
    echo
    echo "Examples:"
    echo "  $0 --service backend --version 1.0.0 --push --token ghp_...    # Build and push backend v1.0.0"
    echo "  $0 --all --version 1.2.0 --push --save-token                   # Build all, save token to .env"
    echo "  $0 --service frontend --push                                    # Build and push frontend with latest tag"
    echo "  $0 --all --force --push --non-interactive                      # Force rebuild all and push (CI mode)"
    echo "  $0 --list-images                                               # List all images with tags"
    echo "  $0 --delete-images --service backend                           # Delete backend images"
    echo
    echo "Available services: ${!SERVICES[*]}"
    echo
    echo "Token Creation:"
    echo "  Create a token at: https://github.com/settings/tokens"
    echo "  For classic tokens: Select 'repo' and 'write:packages' scopes"
    echo "  For fine-grained tokens: Select repository access and package permissions"
    echo
    echo "Tag Management:"
    echo "  • When you push with --version 1.2.0, both tags are created: 1.2.0 and latest"
    echo "  • The 'latest' tag automatically moves to the newest version"
    echo "  • Previous versions keep their specific version tags (1.1.0, 1.0.0, etc.)"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --service)
                SERVICE="$2"
                if [[ ! "${SERVICES[$SERVICE]:-}" ]]; then
                    milou_log "ERROR" "Invalid service: $SERVICE"
                    milou_log "ERROR" "Available services: ${!SERVICES[*]}"
                    exit 1
                fi
                shift 2
                ;;
            --version)
                VERSION="$2"
                if [[ ! $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    milou_log "ERROR" "Version must be in format x.y.z (e.g., 1.0.0)"
                    exit 1
                fi
                shift 2
                ;;
            --token)
                GITHUB_TOKEN_PROVIDED="$2"
                shift 2
                ;;
            --save-token)
                SAVE_TOKEN=true
                shift
                ;;
            --non-interactive)
                NON_INTERACTIVE=true
                shift
                ;;
            --all)
                BUILD_ALL=true
                shift
                ;;
            --push)
                PUSH_TO_REGISTRY=true
                shift
                ;;
            --force)
                FORCE_BUILD=true
                shift
                ;;
            --no-diff-check)
                CHECK_DIFF=false
                shift
                ;;
            --list-images)
                LIST_IMAGES=true
                shift
                ;;
            --delete-images)
                DELETE_IMAGES=true
                shift
                ;;
            --org)
                GITHUB_ORG="$2"
                shift 2
                ;;
            --repo)
                REPO_NAME="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --debug)
                export DEBUG=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                milou_log "ERROR" "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Validate arguments for build operations
    if [[ "$LIST_IMAGES" == "false" && "$DELETE_IMAGES" == "false" ]]; then
        if [[ "$BUILD_ALL" == "false" && -z "$SERVICE" ]]; then
            milou_log "ERROR" "Either specify --service or use --all"
            show_help
            exit 1
        fi
        
        if [[ "$BUILD_ALL" == "true" && -n "$SERVICE" ]]; then
            milou_log "ERROR" "Cannot use both --service and --all"
            exit 1
        fi
    fi
}

# Load token from .env file
load_token_from_env() {
    local env_file="$MILOU_CLI_DIR/.env"
    
    if [[ -f "$env_file" ]]; then
        milou_log "DEBUG" "Loading environment from: $env_file"
        # Only source GITHUB_TOKEN to avoid conflicts
        local token
        token=$(grep "^GITHUB_TOKEN=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"'"'" || echo "")
        if [[ -n "$token" ]]; then
            export GITHUB_TOKEN="$token"
            milou_log "DEBUG" "Loaded GITHUB_TOKEN from .env file"
            return 0
        fi
    fi
    
    return 1
}

# Save token to .env file
save_token_to_env() {
    local token="$1"
    local env_file="$MILOU_CLI_DIR/.env"
    
    if [[ -z "$token" ]]; then
        milou_log "ERROR" "No token to save"
        return 1
    fi
    
    milou_log "INFO" "💾 Saving token to .env file..."
    
    # Create .env file if it doesn't exist
    if [[ ! -f "$env_file" ]]; then
        touch "$env_file"
        chmod 600 "$env_file"  # Secure permissions
    fi
    
    # Update or add GITHUB_TOKEN
    if grep -q "^GITHUB_TOKEN=" "$env_file" 2>/dev/null; then
        # Update existing line
        sed -i "s/^GITHUB_TOKEN=.*/GITHUB_TOKEN=$token/" "$env_file"
        milou_log "SUCCESS" "✅ Updated GITHUB_TOKEN in $env_file"
    else
        # Add new line
        echo "GITHUB_TOKEN=$token" >> "$env_file"
        milou_log "SUCCESS" "✅ Added GITHUB_TOKEN to $env_file"
    fi
    
    # Ensure secure permissions
    chmod 600 "$env_file"
    milou_log "INFO" "🔒 Set secure permissions on .env file"
}

# Interactive authentication with enhanced UX
interactive_authentication() {
    milou_log "INFO" "🔐 GitHub Authentication Required"
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  To push/manage Docker images, you need a GitHub Personal Access Token"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "📋 Required Token Scopes:"
    echo "   • read:packages    (to pull Docker images)"
    echo "   • write:packages   (to push Docker images)"
    echo "   • delete:packages  (to delete images, if needed)"
    echo
    echo "🌐 Create a token at: ${BLUE}https://github.com/settings/tokens${NC}"
    echo
    echo "💡 Token Types:"
    echo "   • Classic tokens: Select 'repo' and 'write:packages' scopes"
    echo "   • Fine-grained: Select repository access and package permissions"
    echo
    
    # Check if we're in non-interactive mode
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        milou_log "ERROR" "Non-interactive mode enabled but no token provided"
        milou_log "INFO" "Provide token via: --token TOKEN or GITHUB_TOKEN environment variable"
        exit 1
    fi
    
    # Ask if user wants to proceed
    echo -n "Do you have a GitHub Personal Access Token ready? (y/N): "
    read -r response
    echo
    
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        milou_log "INFO" "Please create a token and run the script again with:"
        milou_log "INFO" "  $0 --token YOUR_TOKEN [other options]"
        milou_log "INFO" "Or set environment variable: export GITHUB_TOKEN=YOUR_TOKEN"
        exit 0
    fi
    
    # Get the token
    echo "🔑 Enter your GitHub Personal Access Token:"
    echo -n "Token (input will be hidden): "
    read -rs github_token
    echo
    echo
    
    if [[ -z "$github_token" ]]; then
        milou_log "ERROR" "Token is required"
        exit 1
    fi
    
    # Validate token format
    if ! validate_github_token "$github_token"; then
        milou_log "ERROR" "Token format validation failed"
        exit 1
    fi
    
    # Test token authentication
    milou_log "INFO" "🧪 Testing token authentication..."
    if ! test_github_authentication "$github_token" "false" "true"; then
        milou_log "ERROR" "Token authentication failed"
        milou_log "INFO" "Please check your token and ensure it has the required scopes"
        exit 1
    fi
    
    # Set token for this session
    export GITHUB_TOKEN="$github_token"
    milou_log "SUCCESS" "✅ Token authenticated successfully"
    
    # Ask if user wants to save the token
    if [[ "$SAVE_TOKEN" == "true" ]] || [[ "$SAVE_TOKEN" == "false" && -t 0 ]]; then
        echo
        echo -n "Do you want to save this token to .env file for future use? (y/N): "
        read -r save_response
        
        if [[ "$save_response" =~ ^[Yy]$ ]]; then
            save_token_to_env "$github_token"
        else
            milou_log "INFO" "Token not saved. You can save it later with --save-token option"
        fi
    elif [[ "$SAVE_TOKEN" == "true" ]]; then
        save_token_to_env "$github_token"
    fi
    
    echo
}

# Enhanced login to GHCR with better error handling
login_to_ghcr() {
    if [[ "$DRY_RUN" == "true" ]]; then
        milou_log "INFO" "[DRY RUN] Would login to GHCR"
        return 0
    fi
    
    milou_log "DEBUG" "Preparing GHCR authentication..."
    
    # Determine token source and set it up
    local token=""
    
    # Priority order: command line -> environment -> .env file -> interactive
    if [[ -n "$GITHUB_TOKEN_PROVIDED" ]]; then
        milou_log "DEBUG" "Using token from command line argument"
        token="$GITHUB_TOKEN_PROVIDED"
        export GITHUB_TOKEN="$token"
    elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
        milou_log "DEBUG" "Using token from environment variable"
        token="$GITHUB_TOKEN"
    elif load_token_from_env; then
        milou_log "DEBUG" "Using token from .env file"
        token="$GITHUB_TOKEN"
    else
        milou_log "DEBUG" "No token found, starting interactive authentication"
        interactive_authentication
        token="$GITHUB_TOKEN"
    fi
    
    # Final validation
    if [[ -z "$token" ]]; then
        milou_log "ERROR" "No GitHub token available after authentication setup"
        exit 1
    fi
    
    # Validate and test the token
    if ! validate_github_token "$token"; then
        milou_log "ERROR" "Token format validation failed"
        exit 1
    fi
    
    # Test authentication
    milou_log "INFO" "🔐 Authenticating with GitHub Container Registry..."
    if ! test_github_authentication "$token" "false" "true"; then
        milou_log "ERROR" "❌ GitHub authentication failed"
        milou_log "ERROR" "Please check your token and ensure it has the required scopes:"
        milou_log "ERROR" "  • read:packages"
        milou_log "ERROR" "  • write:packages"
        milou_log "ERROR" "  • delete:packages (for image deletion)"
        exit 1
    fi
    
    # Perform Docker login
    local username="${GITHUB_USERNAME:-$GITHUB_ORG}"
    milou_log "DEBUG" "Logging in to GHCR as user: $username"
    
    if echo "$token" | docker login ghcr.io -u "$username" --password-stdin >/dev/null 2>&1; then
        milou_log "SUCCESS" "✅ Successfully authenticated with GitHub Container Registry"
        
        # Save token if requested and not already saved
        if [[ "$SAVE_TOKEN" == "true" && "$GITHUB_TOKEN_PROVIDED" == "$token" ]]; then
            save_token_to_env "$token"
        fi
        
        return 0
    else
        milou_log "ERROR" "❌ Docker login to GHCR failed"
        milou_log "ERROR" "Token authentication succeeded but Docker login failed"
        milou_log "INFO" "This might be a temporary Docker/network issue. Try again in a moment."
        exit 1
    fi
}

# Calculate build context hash for better diff detection
calculate_context_hash() {
    local context_path="$1"
    local dockerfile_path="$2"
    
    milou_log "DEBUG" "Calculating context hash for $context_path"
    
    # Create a hash of the Dockerfile and key source files
    local context_hash=""
    if [[ -d "$context_path" ]]; then
        # Hash Dockerfile content
        local dockerfile_hash=""
        if [[ -f "$dockerfile_path" ]]; then
            dockerfile_hash=$(sha256sum "$dockerfile_path" | cut -d' ' -f1)
        fi
        
        # Hash key source files (limited depth for performance)
        local source_hash=""
        source_hash=$(find "$context_path" -maxdepth 3 -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.java" -o -name "package.json" -o -name "requirements.txt" -o -name "go.mod" \) -exec sha256sum {} + 2>/dev/null | sort | sha256sum | cut -d' ' -f1 || echo "")
        
        # Combine hashes
        context_hash=$(echo "${dockerfile_hash}${source_hash}" | sha256sum | cut -d' ' -f1)
    fi
    
    echo "$context_hash"
}

# Get image digest using proper SHA256 comparison
get_image_digest() {
    local image_name="$1"
    local location="$2"  # "local" or "remote"
    
    milou_log "DEBUG" "Getting $location digest for $image_name"
    
    local digest=""
    case "$location" in
        "local")
            if docker image inspect "$image_name" >/dev/null 2>&1; then
                digest=$(docker image inspect "$image_name" --format '{{index .RepoDigests 0}}' 2>/dev/null | cut -d'@' -f2 || echo "")
                # Fallback to image ID if no repo digest
                if [[ -z "$digest" ]]; then
                    digest=$(docker image inspect "$image_name" --format '{{.Id}}' 2>/dev/null || echo "")
                fi
            fi
            ;;
        "remote")
            # Use docker manifest inspect for remote digest
            if docker manifest inspect "$image_name" >/dev/null 2>&1; then
                digest=$(docker manifest inspect "$image_name" --verbose 2>/dev/null | jq -r '.Descriptor.digest // empty' 2>/dev/null || echo "")
                # Fallback method
                if [[ -z "$digest" ]]; then
                    digest=$(docker manifest inspect "$image_name" 2>/dev/null | jq -r '.config.digest // empty' 2>/dev/null || echo "")
                fi
            fi
            ;;
    esac
    
    echo "$digest"
}

# Enhanced image rebuild check with proper state-of-the-art comparison
image_needs_rebuild() {
    local service_name="$1"
    local image_name="$2"
    local dockerfile_path="$3"
    local context_path="$4"
    
    milou_log "DEBUG" "Checking if $service_name needs rebuild..."
    
    # If force build is enabled, always rebuild
    if [[ "$FORCE_BUILD" == "true" ]]; then
        milou_log "DEBUG" "Force build enabled, rebuilding $service_name"
        return 0  # needs rebuild
    fi
    
    # If diff checking is disabled, check if the specific image exists
    if [[ "$CHECK_DIFF" == "false" ]]; then
        if docker image inspect "$image_name" >/dev/null 2>&1; then
            milou_log "DEBUG" "Diff checking disabled, image $image_name exists, skipping rebuild"
            return 1  # doesn't need rebuild
        else
            milou_log "DEBUG" "Diff checking disabled, image $image_name doesn't exist, needs build"
            return 0  # needs rebuild
        fi
    fi
    
    # Smart rebuild detection: Check for any existing image of this service
    # Look for images with the base name (any tag)
    local base_image="ghcr.io/$GITHUB_ORG/$REPO_NAME/$service_name"
    local existing_image=""
    
    # Try to find any existing image for this service (latest, or any version)
    for tag in "latest" $(docker images --format "table {{.Repository}}:{{.Tag}}" | grep "^$base_image:" | cut -d':' -f2 | grep -v "latest" | head -5); do
        local candidate_image="$base_image:$tag"
        if docker image inspect "$candidate_image" >/dev/null 2>&1; then
            existing_image="$candidate_image"
            milou_log "DEBUG" "Found existing image for comparison: $existing_image"
            break
        fi
    done
    
    # If no existing image found locally, try to pull the latest from remote
    if [[ -z "$existing_image" ]]; then
        milou_log "DEBUG" "No local image found for $service_name, trying to pull latest from remote"
        local remote_latest="$base_image:latest"
        
        if [[ "$DRY_RUN" != "true" ]]; then
            # Try to pull the latest image quietly for comparison
            if docker pull "$remote_latest" >/dev/null 2>&1; then
                existing_image="$remote_latest"
                milou_log "DEBUG" "Pulled remote image for comparison: $existing_image"
            else
                milou_log "DEBUG" "Could not pull remote image $remote_latest"
            fi
        else
            milou_log "DEBUG" "[DRY RUN] Would try to pull $remote_latest for comparison"
            # In dry-run, assume we can pull it if we're doing smart comparison
            existing_image="$remote_latest"
            milou_log "DEBUG" "[DRY RUN] Assuming we can pull remote image: $existing_image"
        fi
    fi
    
    # If still no existing image found, we need to build
    if [[ -z "$existing_image" ]]; then
        milou_log "DEBUG" "No existing image found locally or remotely for $service_name, needs build"
        return 0  # needs rebuild
    fi
    
    # State-of-the-art comparison: Use build context hash + image digests
    milou_log "DEBUG" "Performing enhanced diff analysis using existing image: $existing_image"
    
    # 1. Calculate current build context hash
    local current_context_hash
    current_context_hash=$(calculate_context_hash "$context_path" "$dockerfile_path")
    
    # 2. Get image creation time for timestamp comparison
    local image_created
    image_created=$(docker image inspect "$existing_image" --format '{{.Created}}' 2>/dev/null)
    if [[ -z "$image_created" ]]; then
        milou_log "DEBUG" "Cannot get image creation time for $existing_image, rebuilding"
        return 0  # needs rebuild
    fi
    
    # 3. Check if Dockerfile is newer than the existing image
    if [[ -f "$dockerfile_path" ]]; then
        local dockerfile_timestamp
        local image_timestamp
        dockerfile_timestamp=$(date -r "$dockerfile_path" +%s 2>/dev/null || echo "0")
        image_timestamp=$(date -d "$image_created" +%s 2>/dev/null || echo "0")
        
        if [[ $dockerfile_timestamp -gt $image_timestamp ]]; then
            milou_log "DEBUG" "Dockerfile $dockerfile_path is newer than existing image $existing_image"
            return 0  # needs rebuild
        fi
    fi
    
    # 4. Compare build context hash with stored label (if available)
    local stored_context_hash
    stored_context_hash=$(docker image inspect "$existing_image" --format '{{index .Config.Labels "milou.context.hash"}}' 2>/dev/null || echo "")
    
    if [[ -n "$stored_context_hash" && -n "$current_context_hash" ]]; then
        if [[ "$current_context_hash" != "$stored_context_hash" ]]; then
            milou_log "DEBUG" "Build context hash changed for $service_name"
            milou_log "DEBUG" "  Stored: $stored_context_hash"
            milou_log "DEBUG" "  Current: $current_context_hash"
            return 0  # needs rebuild
        else
            milou_log "DEBUG" "Build context hash unchanged for $service_name"
        fi
    else
        milou_log "DEBUG" "Cannot compare context hashes (stored: $stored_context_hash, current: $current_context_hash)"
    fi
    
    # 5. Check for source files newer than the existing image (fallback)
    if [[ -d "$context_path" ]]; then
        local newer_files
        newer_files=$(find "$context_path" -maxdepth 3 -type f -newer <(date -d "$image_created" '+%Y-%m-%d %H:%M:%S') 2>/dev/null | head -3)
        if [[ -n "$newer_files" ]]; then
            milou_log "DEBUG" "Source files newer than existing image $existing_image found:"
            echo "$newer_files" | while read -r file; do
                milou_log "DEBUG" "  - $file"
            done
            return 0  # needs rebuild
        fi
    fi
    
    # If we get here, no changes detected
    milou_log "INFO" "🎯 No source changes detected for $service_name, reusing existing build"
    
    # Check if we need to tag the existing image with the new version
    if [[ "$existing_image" != "$image_name" ]]; then
        milou_log "INFO" "📋 Tagging existing image $existing_image as $image_name"
        if [[ "$DRY_RUN" != "true" ]]; then
            docker tag "$existing_image" "$image_name" || {
                milou_log "ERROR" "Failed to tag existing image"
                return 0  # needs rebuild as fallback
            }
        else
            milou_log "INFO" "[DRY RUN] Would tag: $existing_image -> $image_name"
        fi
    fi
    
    return 1  # doesn't need rebuild
}

# Build Docker image with enhanced labeling
build_image() {
    local service_name="$1"
    local dockerfile="$2"
    local context="$3"
    local tags=("${@:4}")  # All remaining arguments are tags
    
    milou_log "INFO" "🔨 Building $service_name..."
    milou_log "DEBUG" "Dockerfile: $dockerfile, Context: $context"
    milou_log "DEBUG" "Tags: ${tags[*]}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        milou_log "INFO" "[DRY RUN] Would build: docker build -f $dockerfile $context"
        for tag in "${tags[@]}"; do
            milou_log "INFO" "[DRY RUN] Would tag: $tag"
        done
        return 0
    fi
    
    # Calculate context hash for labeling
    local context_hash
    context_hash=$(calculate_context_hash "$context" "$dockerfile")
    
    # Build image with primary tag and enhanced labels
    local primary_tag="${tags[0]}"
    if docker build -t "$primary_tag" -f "$dockerfile" "$context" \
        --label "org.opencontainers.image.source=https://github.com/$GITHUB_ORG/$REPO_NAME" \
        --label "org.opencontainers.image.description=Milou $service_name service" \
        --label "org.opencontainers.image.licenses=MIT" \
        --label "milou.service.name=$service_name" \
        --label "milou.context.hash=$context_hash" \
        --label "milou.build.timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)"; then
        
        milou_log "INFO" "✅ Successfully built $primary_tag"
        
        # Tag with additional tags
        for tag in "${tags[@]:1}"; do
            if docker tag "$primary_tag" "$tag"; then
                milou_log "DEBUG" "Tagged: $tag"
            else
                milou_log "ERROR" "Failed to tag: $tag"
                return 1
            fi
        done
        
        return 0
    else
        milou_log "ERROR" "❌ Failed to build $service_name"
        return 1
    fi
}

# Get all tags for an image from GHCR
get_image_tags() {
    local service="$1"
    
    milou_log "DEBUG" "Getting tags for $service"
    
    local api_url="https://api.github.com/orgs/$GITHUB_ORG/packages/container/milou%2F$service/versions"
    local response
    
    response=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
                   -H "Accept: application/vnd.github.v3+json" \
                   "$api_url" 2>/dev/null || echo "[]")
    
    echo "$response"
}

# List images in GHCR with proper tag information
list_ghcr_images() {
    milou_log "INFO" "📋 Listing images in GHCR with tags..."
    
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        # Use the enhanced authentication flow
        if [[ -n "$GITHUB_TOKEN_PROVIDED" ]]; then
            export GITHUB_TOKEN="$GITHUB_TOKEN_PROVIDED"
        elif ! load_token_from_env; then
            interactive_authentication
        fi
    fi
    
    local services_to_check=()
    if [[ "$BUILD_ALL" == "true" ]]; then
        services_to_check=(${!SERVICES[@]})
    elif [[ -n "$SERVICE" ]]; then
        services_to_check=("$SERVICE")
    else
        services_to_check=(${!SERVICES[@]})
    fi
    
    for service in "${services_to_check[@]}"; do
        milou_log "INFO" "📦 $service images:"
        
        local response
        response=$(get_image_tags "$service")
        
        if echo "$response" | jq -e '. | length > 0' >/dev/null 2>&1; then
            # Parse and display image information with tags
            # The GitHub API returns tags in metadata.container.tags array
            local found_tags=false
            
            # Try to extract tags from the response
            echo "$response" | jq -r '.[] | 
                select(.metadata.container.tags != null) |
                .metadata.container.tags[] as $tag |
                "  • Tag: \($tag) (created: \(.created_at | strptime("%Y-%m-%dT%H:%M:%SZ") | strftime("%Y-%m-%d %H:%M")))"' 2>/dev/null | while read -r line; do
                if [[ -n "$line" ]]; then
                    echo "$line"
                    found_tags=true
                fi
            done
            
            # If no tags found in that format, try alternative parsing
            local tag_count
            tag_count=$(echo "$response" | jq -r '.[] | select(.metadata.container.tags != null) | .metadata.container.tags[]' 2>/dev/null | wc -l)
            
            if [[ "$tag_count" -eq 0 ]]; then
                # Fallback: try to get tags from the name field or show digest info
                echo "$response" | jq -r '.[] | 
                    if .metadata.container.tags then
                        .metadata.container.tags[] | "  • Tag: \(.) (created: \(.created_at // "unknown"))"
                    else
                        "  • Digest: \(.name) (created: \(.created_at | strptime("%Y-%m-%dT%H:%M:%SZ") | strftime("%Y-%m-%d %H:%M")))"
                    end' 2>/dev/null || {
                    # Final fallback
                    echo "$response" | jq -r '.[] | "  • \(.name) (created: \(.created_at | strptime("%Y-%m-%dT%H:%M:%SZ") | strftime("%Y-%m-%d %H:%M")))"' 2>/dev/null || {
                        milou_log "WARN" "  Could not parse API response for $service"
                    }
                }
            fi
        else
            milou_log "INFO" "  No images found for $service"
        fi
        echo
    done
    
    milou_log "INFO" "💡 Tag Management Notes:"
    milou_log "INFO" "  • 'latest' tag automatically moves to the newest pushed version"
    milou_log "INFO" "  • Specific version tags (1.0.0, 1.1.0) remain permanently"
    milou_log "INFO" "  • Only one image can have the 'latest' tag at a time"
}

# Push image to registry with proper latest tag handling
push_image() {
    local tags=("$@")
    
    if [[ "$DRY_RUN" == "true" ]]; then
        for tag in "${tags[@]}"; do
            milou_log "INFO" "[DRY RUN] Would push: $tag"
        done
        milou_log "INFO" "[DRY RUN] Latest tag behavior: When pushing with version, both version and latest tags are pushed"
        milou_log "INFO" "[DRY RUN] The latest tag will automatically move from any previous image"
        return 0
    fi
    
    # Push tags in order: version first, then latest
    # This ensures proper latest tag behavior
    local version_tags=()
    local latest_tags=()
    
    for tag in "${tags[@]}"; do
        if [[ "$tag" == *":latest" ]]; then
            latest_tags+=("$tag")
        else
            version_tags+=("$tag")
        fi
    done
    
    # Push version tags first
    for tag in "${version_tags[@]}"; do
        milou_log "INFO" "📤 Pushing $tag..."
        if docker push "$tag"; then
            milou_log "INFO" "✅ Successfully pushed $tag"
        else
            milou_log "ERROR" "❌ Failed to push $tag"
            return 1
        fi
    done
    
    # Push latest tags (this will move the latest tag)
    for tag in "${latest_tags[@]}"; do
        milou_log "INFO" "📤 Pushing $tag (moving 'latest' tag)..."
        if docker push "$tag"; then
            milou_log "INFO" "✅ Successfully pushed $tag"
            milou_log "INFO" "🏷️  The 'latest' tag now points to this image"
        else
            milou_log "ERROR" "❌ Failed to push $tag"
            return 1
        fi
    done
    
    return 0
}

# Delete images from GHCR with interactive confirmation
delete_ghcr_images() {
    milou_log "WARN" "⚠️  Image Deletion Mode"
    echo
    
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        # Use the enhanced authentication flow
        if [[ -n "$GITHUB_TOKEN_PROVIDED" ]]; then
            export GITHUB_TOKEN="$GITHUB_TOKEN_PROVIDED"
        elif ! load_token_from_env; then
            interactive_authentication
        fi
    fi
    
    local services_to_delete=()
    if [[ "$BUILD_ALL" == "true" ]]; then
        services_to_delete=(${!SERVICES[@]})
        milou_log "WARN" "You are about to delete ALL images for ALL services!"
    elif [[ -n "$SERVICE" ]]; then
        services_to_delete=("$SERVICE")
        milou_log "WARN" "You are about to delete ALL images for service: $SERVICE"
    else
        milou_log "ERROR" "Either specify --service or use --all with --delete-images"
        exit 1
    fi
    
    echo
    milou_log "WARN" "Services to delete: ${services_to_delete[*]}"
    echo
    
    # Show what will be deleted
    milou_log "INFO" "Images that will be deleted:"
    for service in "${services_to_delete[@]}"; do
        local response
        response=$(get_image_tags "$service")
        
        local count
        count=$(echo "$response" | jq '. | length' 2>/dev/null || echo "0")
        
        if [[ "$count" -gt 0 ]]; then
            milou_log "INFO" "  $service: $count images"
            # Show tags that will be deleted
            echo "$response" | jq -r '.[] | 
                (.metadata.container.tags // []) as $tags |
                if ($tags | length) > 0 then
                    $tags[] | "    - \(.)"
                else
                    "    - (untagged)"
                end' 2>/dev/null | head -10
        else
            milou_log "INFO" "  $service: No images found"
        fi
    done
    
    echo
    milou_log "ERROR" "⚠️  THIS ACTION CANNOT BE UNDONE! ⚠️"
    echo
    
    # Multiple confirmations for safety
    read -p "Are you sure you want to delete these images? Type 'yes' to continue: " -r
    if [[ "$REPLY" != "yes" ]]; then
        milou_log "INFO" "Deletion cancelled"
        exit 0
    fi
    
    read -p "This will permanently delete the images. Type 'DELETE' to confirm: " -r
    if [[ "$REPLY" != "DELETE" ]]; then
        milou_log "INFO" "Deletion cancelled"
        exit 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        milou_log "INFO" "[DRY RUN] Would delete images for: ${services_to_delete[*]}"
        return 0
    fi
    
    # Perform deletion
    local deleted_count=0
    local failed_count=0
    
    for service in "${services_to_delete[@]}"; do
        milou_log "INFO" "🗑️  Deleting images for $service..."
        
        local response
        response=$(get_image_tags "$service")
        
        # Delete each version
        echo "$response" | jq -r '.[].id' 2>/dev/null | while read -r version_id; do
            if [[ -n "$version_id" ]]; then
                local delete_url="https://api.github.com/orgs/$GITHUB_ORG/packages/container/milou%2F$service/versions/$version_id"
                
                if curl -s -X DELETE \
                       -H "Authorization: Bearer $GITHUB_TOKEN" \
                       -H "Accept: application/vnd.github.v3+json" \
                       "$delete_url" >/dev/null 2>&1; then
                    milou_log "INFO" "  ✅ Deleted version $version_id"
                    ((deleted_count++))
                else
                    milou_log "ERROR" "  ❌ Failed to delete version $version_id"
                    ((failed_count++))
                fi
            fi
        done
    done
    
    echo
    milou_log "INFO" "📊 Deletion Summary:"
    milou_log "INFO" "  ✅ Deleted: $deleted_count images"
    if [[ $failed_count -gt 0 ]]; then
        milou_log "ERROR" "  ❌ Failed: $failed_count images"
    fi
}

# Check if we're in the right directory structure
check_directory_structure() {
    # Skip directory check for image management operations
    if [[ "$LIST_IMAGES" == "true" || "$DELETE_IMAGES" == "true" ]]; then
        return 0
    fi
    
    # Get project root 
    local project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    local required_paths=(
        "${project_root}/../milou_fresh/dashboard"
        "${project_root}/../milou_fresh/engine"
        "${project_root}/../milou_fresh/docker"
    )
    
    for path in "${required_paths[@]}"; do
        if [[ ! -d "$path" ]]; then
            milou_log "ERROR" "Required directory not found: $path"
            milou_log "ERROR" "Please ensure milou_fresh is a sibling directory to milou-cli"
            exit 1
        fi
    done
    
    # Change to milou_fresh directory for building
    cd "${project_root}/../milou_fresh"
    milou_log "INFO" "Building from: $(pwd)"
}

# Build and optionally push a single service
build_service() {
    local service_name="$1"
    local config="${SERVICES[$service_name]}"
    local dockerfile context
    
    dockerfile=$(echo "$config" | cut -d'|' -f1)
    context=$(echo "$config" | cut -d'|' -f2)
    
    # Generate image names and tags
    local base_image="ghcr.io/$GITHUB_ORG/$REPO_NAME/$service_name"
    local tags=()
    
    if [[ -n "$VERSION" ]]; then
        # When versioning: push both version and latest tags
        # Version tag first, then latest (this ensures proper latest tag movement)
        tags+=("$base_image:$VERSION")
        tags+=("$base_image:latest")
        milou_log "INFO" "🏷️  Will create tags: $VERSION and latest"
    else
        # Only latest tag
        tags+=("$base_image:latest")
        milou_log "INFO" "🏷️  Will create tag: latest"
    fi
    
    milou_log "INFO" "📦 Processing $service_name..."
    
    # Check if rebuild is needed
    local primary_tag="${tags[0]}"
    if ! image_needs_rebuild "$service_name" "$primary_tag" "$dockerfile" "$context"; then
        milou_log "INFO" "⏭️  Skipping $service_name (up to date)"
        
        # If pushing and image exists locally, still push it
        if [[ "$PUSH_TO_REGISTRY" == "true" ]]; then
            if docker image inspect "$primary_tag" >/dev/null 2>&1; then
                milou_log "INFO" "Image exists locally, pushing anyway..."
                push_image "${tags[@]}" || return 1
            else
                milou_log "WARN" "No local image to push for $service_name"
            fi
        fi
        return 0
    fi
    
    # Build the image
    if build_image "$service_name" "$dockerfile" "$context" "${tags[@]}"; then
        # Push if requested
        if [[ "$PUSH_TO_REGISTRY" == "true" ]]; then
            milou_log "INFO" "🚀 Pushing to GHCR..."
            if [[ -n "$VERSION" ]]; then
                milou_log "INFO" "💡 Tag behavior: Latest tag will move to version $VERSION"
            fi
            push_image "${tags[@]}" || return 1
        fi
        return 0
    else
        return 1
    fi
}

# Main execution
main() {
    parse_args "$@"
    
    # Show configuration
    milou_log "INFO" "🚀 Milou Docker Build & Push"
    milou_log "INFO" "Organization: $GITHUB_ORG"
    milou_log "INFO" "Repository: $REPO_NAME"
    
    if [[ -n "$VERSION" ]]; then
        milou_log "INFO" "Version: $VERSION"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        milou_log "WARN" "DRY RUN MODE - No actual building or pushing"
    fi
    
    # Handle image management operations
    if [[ "$LIST_IMAGES" == "true" ]]; then
        list_ghcr_images
        exit 0
    fi
    
    if [[ "$DELETE_IMAGES" == "true" ]]; then
        delete_ghcr_images
        exit 0
    fi
    
    # Check directory structure and change to build directory
    check_directory_structure
    
    # Login to GHCR if pushing
    if [[ "$PUSH_TO_REGISTRY" == "true" ]]; then
        login_to_ghcr
    fi
    
    local failed_services=()
    local successful_services=()
    local skipped_services=()
    
    # Determine which services to build
    local services_to_build=()
    if [[ "$BUILD_ALL" == "true" ]]; then
        services_to_build=(${!SERVICES[@]})
    else
        services_to_build=("$SERVICE")
    fi
    
    # Build each service
    for service in "${services_to_build[@]}"; do
        if build_service "$service"; then
            successful_services+=("$service")
        else
            failed_services+=("$service")
        fi
    done
    
    echo
    
    # Summary
    milou_log "INFO" "📊 Build Summary:"
    if [[ ${#successful_services[@]} -gt 0 ]]; then
        milou_log "INFO" "   ✅ Success: ${successful_services[*]}"
    fi
    if [[ ${#skipped_services[@]} -gt 0 ]]; then
        milou_log "INFO" "   ⏭️  Skipped: ${skipped_services[*]}"
    fi
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        milou_log "ERROR" "   ❌ Failed: ${failed_services[*]}"
    fi
    
    if [[ ${#failed_services[@]} -eq 0 ]]; then
        milou_log "INFO" "🎉 All operations completed successfully!"
        
        if [[ "$PUSH_TO_REGISTRY" == "true" && ${#successful_services[@]} -gt 0 ]]; then
            echo
            milou_log "INFO" "📋 Published images:"
            for service in "${successful_services[@]}"; do
                local base_image="ghcr.io/$GITHUB_ORG/$REPO_NAME/$service"
                if [[ -n "$VERSION" ]]; then
                    milou_log "INFO" "   • $base_image:$VERSION"
                    milou_log "INFO" "   • $base_image:latest (moved to $VERSION)"
                else
                    milou_log "INFO" "   • $base_image:latest"
                fi
            done
            echo
            milou_log "INFO" "💡 Use --list-images to see all tags in the registry"
        fi
    else
        milou_log "ERROR" "❌ Some operations failed: ${failed_services[*]}"
        exit 1
    fi
}

# Run main function
main "$@" 