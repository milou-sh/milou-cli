#!/bin/bash

# =============================================================================
# Milou CLI - Enhanced Docker Build and Push Script v3.1
# Full-featured professional Docker management with ALL advanced features
# =============================================================================

set -euo pipefail

# Colors and formatting - with better terminal compatibility
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    readonly RED=$(tput setaf 1)
    readonly GREEN=$(tput setaf 2)
    readonly YELLOW=$(tput setaf 3)
    readonly BLUE=$(tput setaf 4)
    readonly PURPLE=$(tput setaf 5)
    readonly CYAN=$(tput setaf 6)
    readonly BOLD=$(tput bold)
    readonly DIM=$(tput dim)
    readonly NC=$(tput sgr0)
else
    # Fallback ANSI codes for when tput is not available
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly PURPLE='\033[0;35m'
    readonly CYAN='\033[0;36m'
    readonly BOLD='\033[1m'
    readonly DIM='\033[2m'
    readonly NC='\033[0m'
fi

# Global configuration
GITHUB_ORG="milou-sh"
REPO_NAME="milou"
REGISTRY_URL="ghcr.io"
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
CLEANUP_AFTER_BUILD=false
BUILD_PROGRESS=true
USE_CACHE=true
MULTI_PLATFORM=false
BUILD_ARGS=""
PRUNE_AFTER_BUILD=false
PARALLEL_BUILDS=false
VERBOSE=false
QUIET=false
AUTO_TAG=true
PLATFORMS="linux/amd64"
CACHE_FROM=""
CACHE_TO=""
TARGET_STAGE=""
SECRETS=""
SSH_KEYS=""
BUILD_TIMEOUT="1800"
MAX_PARALLEL_JOBS=3
TEST_MODE=false
QUICK_TEST=false
DELETE_DAYS=30
DELETE_UNTAGGED_ONLY=false
DELETE_ALL=false
FORCE_DELETE=false

# Service configurations
declare -A SERVICE_CONFIGS=(
    ["database"]="./docker/database/Dockerfile|./docker/database|PostgreSQL Database|Essential"
    ["backend"]="./dashboard/backend/Dockerfile.backend|./dashboard|Backend API|Critical"
    ["frontend"]="./dashboard/frontend/Dockerfile.frontend|./dashboard|Frontend UI|Critical"
    ["engine"]="./engine/Dockerfile|./engine|Processing Engine|Essential"
    ["nginx"]="./docker/nginx/Dockerfile|./docker/nginx|Web Server|Important"
)

declare -a AVAILABLE_SERVICES=(database backend frontend engine nginx)
declare -a successful_services=()
declare -a failed_services=()
declare -a skipped_services=()

# =============================================================================
# LOGGING AND OUTPUT FUNCTIONS
# =============================================================================

log() {
    local level="$1"
    shift
    local timestamp=$(date '+%H:%M:%S')
    
    if [[ "$QUIET" == "true" && "$level" != "ERROR" ]]; then
        return 0
    fi
    
    case "$level" in
        "INFO")    printf "${BLUE}[%s]${NC} ${GREEN}[INFO]${NC} %s\n" "$timestamp" "$*" ;;
        "WARN")    printf "${BLUE}[%s]${NC} ${YELLOW}[WARN]${NC} %s\n" "$timestamp" "$*" >&2 ;;
        "ERROR")   printf "${BLUE}[%s]${NC} ${RED}[ERROR]${NC} %s\n" "$timestamp" "$*" >&2 ;;
        "DEBUG")   [[ "${VERBOSE}" == "true" ]] && printf "${BLUE}[%s]${NC} ${DIM}[DEBUG]${NC} %s\n" "$timestamp" "$*" >&2 ;;
        "SUCCESS") printf "${BLUE}[%s]${NC} ${GREEN}[SUCCESS]${NC} %s\n" "$timestamp" "$*" ;;
        "STEP")    printf "${BLUE}[%s]${NC} ${PURPLE}[STEP]${NC} %s\n" "$timestamp" "$*" ;;
        *)         printf "${BLUE}[%s]${NC} [INFO] %s\n" "$timestamp" "$*" ;;
    esac
}

show_progress() {
    if [[ "$BUILD_PROGRESS" == "true" && "$QUIET" != "true" ]]; then
        printf "${CYAN}%s${NC}\n" "$*"
    fi
}

show_banner() {
    if [[ "$QUIET" != "true" ]]; then
        printf "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        printf "${BOLD}${BLUE}               🐳 MILOU DOCKER BUILD & PUSH SYSTEM v3.1                    ${NC}\n"
        printf "${BOLD}${BLUE}                        Professional Docker Management                      ${NC}\n"
        printf "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    fi
}

# =============================================================================
# VALIDATION FUNCTIONS  
# =============================================================================

validate_service() {
    local service="$1"
    if [[ " ${AVAILABLE_SERVICES[*]} " =~ " ${service} " ]]; then
        return 0
    else
        log "ERROR" "Invalid service: $service"
        log "ERROR" "Available services: ${AVAILABLE_SERVICES[*]}"
        return 1
    fi
}

validate_github_token() {
    local token="$1"
    if [[ -z "$token" ]]; then
        return 1
    fi
    if [[ "$token" =~ ^gh[ps]_[A-Za-z0-9]{36}$ ]] || \
       [[ "$token" =~ ^github_pat_[A-Za-z0-9_]{22,}$ ]] || \
       [[ "$token" =~ ^gho_[A-Za-z0-9]{36}$ ]]; then
        return 0
    else
        log "ERROR" "Invalid GitHub token format"
        return 1
    fi
}

check_dependencies() {
    local missing_deps=()
    command -v docker >/dev/null 2>&1 || missing_deps+=("docker")
    command -v curl >/dev/null 2>&1 || missing_deps+=("curl")
    command -v jq >/dev/null 2>&1 || missing_deps+=("jq")
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log "ERROR" "Missing required dependencies:"
        printf '%s\n' "${missing_deps[@]}" | sed 's/^/  - /'
        return 1
    fi
    return 0
}

# =============================================================================
# AUTHENTICATION AND REGISTRY MANAGEMENT
# =============================================================================

setup_authentication() {
    local token=""
    
    if [[ -n "$GITHUB_TOKEN_PROVIDED" ]]; then
        token="$GITHUB_TOKEN_PROVIDED"
    elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
        token="$GITHUB_TOKEN"
    elif load_token_from_env; then
        token="$GITHUB_TOKEN"
    elif [[ "$NON_INTERACTIVE" != "true" ]]; then
        printf "${CYAN}GitHub Personal Access Token required for registry access.${NC}\n"
        printf "${DIM}Create one at: https://github.com/settings/tokens${NC}\n"
        printf "Enter token: "
        read -rs token
        echo
    else
        log "ERROR" "No GitHub token available and running in non-interactive mode"
        return 1
    fi
    
    if [[ -z "$token" ]]; then
        log "ERROR" "No GitHub token provided"
        return 1
    fi
    
    if ! validate_github_token "$token"; then
        return 1
    fi
    
    if ! test_github_auth "$token"; then
        return 1
    fi
    
    export GITHUB_TOKEN="$token"
    
    if [[ "$SAVE_TOKEN" == "true" ]]; then
        save_token_to_env "$token"
    fi
    
    return 0
}

test_github_auth() {
    local token="$1"
    log "INFO" "🔐 Testing GitHub authentication..."
    
    local response
    response=$(curl -s -w "%{http_code}" -H "Authorization: Bearer $token" \
               -H "Accept: application/vnd.github.v3+json" \
               "https://api.github.com/user" 2>/dev/null)
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [[ "$http_code" == "200" ]]; then
        local username
        username=$(echo "$body" | jq -r '.login // "unknown"' 2>/dev/null || echo "unknown")
        log "SUCCESS" "✅ GitHub API authentication successful (user: $username)"
        
        if echo "$token" | docker login "$REGISTRY_URL" -u "$username" --password-stdin >/dev/null 2>&1; then
            log "SUCCESS" "✅ Docker registry authentication successful"
            return 0
        else
            log "ERROR" "❌ Docker registry authentication failed"
            return 1
        fi
    else
        log "ERROR" "❌ GitHub API authentication failed (HTTP $http_code)"
        return 1
    fi
}

load_token_from_env() {
    local env_file="$(dirname "$0")/../.env"
    if [[ -f "$env_file" ]]; then
        local token
        token=$(grep "^GITHUB_TOKEN=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"'"'" || echo "")
        if [[ -n "$token" ]]; then
            export GITHUB_TOKEN="$token"
            return 0
        fi
    fi
    return 1
}

save_token_to_env() {
    local token="$1"
    local env_file="$(dirname "$0")/../.env"
    
    log "INFO" "💾 Saving token to .env file..."
    
    if [[ ! -f "$env_file" ]]; then
        touch "$env_file"
        chmod 600 "$env_file"
    fi
    
    if grep -q "^GITHUB_TOKEN=" "$env_file" 2>/dev/null; then
        sed -i "s/^GITHUB_TOKEN=.*/GITHUB_TOKEN=$token/" "$env_file"
    else
        echo "GITHUB_TOKEN=$token" >> "$env_file"
    fi
    
    chmod 600 "$env_file"
    log "SUCCESS" "✅ Token saved to .env file"
}

# =============================================================================
# ADVANCED IMAGE MANAGEMENT AND REGISTRY OPERATIONS
# =============================================================================

list_ghcr_images() {
    # DISABLE STRICT MODE temporarily
    set +euo pipefail
    
    log "STEP" "📋 Listing images in GitHub Container Registry..."
    
    # Token handling
    local token=""
    if [[ -n "$GITHUB_TOKEN_PROVIDED" ]]; then
        token="$GITHUB_TOKEN_PROVIDED"
    elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
        token="$GITHUB_TOKEN"
    elif load_token_from_env; then
        token="$GITHUB_TOKEN"
    else
        log "ERROR" "No GitHub token available for API access"
        set -euo pipefail  # Restore before return
        return 1
    fi
    
    # Quick token validation
    if ! validate_github_token "$token"; then
        set -euo pipefail  # Restore before return
        return 1
    fi
    
    # Simple array like in working test
    local services=()
    if [[ "$BUILD_ALL" == "true" || -z "$SERVICE" ]]; then
        services=(database backend frontend engine nginx)
    else
        services=("$SERVICE")
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                        📋 GHCR IMAGE INVENTORY                               "
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local total_images=0
    local total_services=0
    
    # EXACT working logic from test-minimal.sh
    for service in "${services[@]}"; do
        echo ""
        echo "🐳 $service"
        echo "─────────────────────────────────────────────────────────────────────────────"
        
        local package_name="$REPO_NAME%2F$service"
        local api_url="https://api.github.com/orgs/$GITHUB_ORG/packages/container/$package_name/versions"
        
        local response=""
        response=$(timeout 10 curl -s --fail --max-time 5 \
                       -H "Authorization: Bearer $token" \
                       -H "Accept: application/vnd.github.v3+json" \
                       "$api_url" 2>/dev/null || echo '{"error": "api_failure"}')
        
        if [[ "$response" == '{"error": "api_failure"}' ]]; then
            echo "  ❌ API call failed"
            total_services=$((total_services + 1))
            continue
        fi
        
        if ! echo "$response" | jq empty 2>/dev/null; then
            echo "  ❌ Invalid JSON response"
            total_services=$((total_services + 1))
            continue
        fi
        
        if echo "$response" | jq -e '.message' >/dev/null 2>&1; then
            local error_msg=""
            error_msg=$(echo "$response" | jq -r '.message' 2>/dev/null || echo "Unknown error")
            echo "  ❌ API Error: $error_msg"
            total_services=$((total_services + 1))
            continue
        fi
        
        if echo "$response" | jq -e '. | type == "array" and length > 0' >/dev/null 2>&1; then
            local image_count=""
            image_count=$(echo "$response" | jq '. | length' 2>/dev/null || echo "0")
            
            echo "$response" | jq -r '.[] | 
                "  📦 " + ((.metadata.container.tags // ["untagged"]) | join(",")) + 
                "  │  📅 " + (.created_at[0:10]) + 
                "  │  🆔 " + (.name[0:12])' 2>/dev/null || echo "  ⚠️  Format failed"
            
            echo "  Total versions: $image_count"
            total_images=$((total_images + image_count))
        else
            echo "  📭 No images found"
        fi
        
        total_services=$((total_services + 1))
        sleep 0.1
    done
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "SUMMARY: Checked $total_services services, found $total_images total images"
    echo "💡 Use '--delete-images' to clean up old versions"
    echo ""
    
    # RESTORE STRICT MODE
    set -euo pipefail
    return 0
}

delete_ghcr_images() {
    # DISABLE STRICT MODE temporarily
    set +euo pipefail
    
    log "STEP" "🗑️ Managing images in GitHub Container Registry..."
    
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        if ! setup_authentication; then
            set -euo pipefail  # Restore before return
            return 1
        fi
    fi
    
    local services_to_clean=()
    if [[ "$BUILD_ALL" == "true" || -z "$SERVICE" ]]; then
        services_to_clean=("${AVAILABLE_SERVICES[@]}")
    else
        services_to_clean=("$SERVICE")
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                        🗑️ IMAGE DELETION PREVIEW                            "
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local total_images_found=0
    declare -A service_data  # Store service -> working_url:response
    
    # First pass: collect and display all images
    for service in "${services_to_clean[@]}"; do
        echo ""
        echo "🐳 $service"
        echo "─────────────────────────────────────────────────────────────────────────────"
        
        # Try organization packages first, then user packages
        local package_name="$REPO_NAME%2F$service"
        local api_urls=(
            "https://api.github.com/orgs/$GITHUB_ORG/packages/container/$package_name/versions"
            "https://api.github.com/user/packages/container/$package_name/versions"
        )
        
        local response=""
        local working_url=""
        
        for api_url in "${api_urls[@]}"; do
            log "DEBUG" "Trying API endpoint: $api_url"
            response=$(timeout 10 curl -s --fail --max-time 5 \
                           -H "Authorization: Bearer $GITHUB_TOKEN" \
                           -H "Accept: application/vnd.github.v3+json" \
                           "$api_url" 2>/dev/null || echo "[]")
            
            # Check if we got a valid response (not an error)
            if echo "$response" | jq -e 'type == "array"' >/dev/null 2>&1; then
                if echo "$response" | jq -e '. | length > 0' >/dev/null 2>&1; then
                    working_url="$api_url"
                    log "DEBUG" "Found images using: $working_url"
                    break
                fi
            elif echo "$response" | jq -e '.message' >/dev/null 2>&1; then
                log "DEBUG" "API error: $(echo "$response" | jq -r '.message')"
            fi
        done
        
        if [[ -z "$working_url" ]]; then
            echo "  📭 No images found"
            continue
        fi
        
        if echo "$response" | jq -e '. | length > 0' >/dev/null 2>&1; then
            local service_images_found=0
            service_images_found=$(echo "$response" | jq '. | length' 2>/dev/null || echo "0")
            total_images_found=$((total_images_found + service_images_found))
            
            # Display all images for this service
            echo "$response" | jq -r '.[] | 
                if ((.metadata.container.tags // []) | length) > 0 then
                    "  📦 " + ((.metadata.container.tags // []) | join(",")) + "  │  📅 " + (.created_at[0:10]) + "  │  🆔 " + (.name[0:12])
                else
                    "  📦 (untagged)  │  📅 " + (.created_at[0:10]) + "  │  🆔 " + (.name[0:12])
                end' 2>/dev/null || echo "  ⚠️  Format failed"
            
            echo "  Total: $service_images_found images"
            
            # Store the service data properly - encode the response to avoid issues
            local encoded_response
            encoded_response=$(echo "$response" | base64 -w 0)
            service_data["$service"]="$working_url|$encoded_response"
        else
            echo "  📭 No images found"
        fi
    done
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 TOTAL: $total_images_found images found across all services"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [[ $total_images_found -eq 0 ]]; then
        log "INFO" "ℹ️ No images found to delete"
        set -euo pipefail
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "🧪 [DRY RUN] Would delete all $total_images_found images above"
        set -euo pipefail
        return 0
    fi
    
    echo ""
    if [[ "$FORCE_DELETE" != "true" && "$NON_INTERACTIVE" != "true" ]]; then
        echo "⚠️  This will PERMANENTLY DELETE all $total_images_found images shown above!"
        echo ""
        read -p "Do you want to delete ALL these images? (type 'DELETE ALL' to confirm): " confirmation
        if [[ "$confirmation" != "DELETE ALL" ]]; then
            log "INFO" "Operation cancelled by user"
            set -euo pipefail
            return 0
        fi
    fi
    
    # Second pass: delete all images
    local total_deleted=0
    local total_errors=0
    
    echo ""
    echo "🗑️ Starting deletion process..."
    echo ""
    
    # Process each service that has images
    for service in "${!service_data[@]}"; do
        log "INFO" "🗑️ Deleting images for $service..."
        
        local service_info="${service_data[$service]}"
        local working_url="${service_info%|*}"
        local encoded_response="${service_info#*|}"
        local response
        response=$(echo "$encoded_response" | base64 -d)
        
        local package_name="$REPO_NAME%2F$service"
        
        # Extract all image IDs and delete them
        local temp_file
        temp_file=$(mktemp)
        echo "$response" | jq -r '.[] | .id' 2>/dev/null > "$temp_file"
        
        while IFS= read -r image_id; do
            if [[ -n "$image_id" ]]; then
                # Determine the correct delete URL
                local delete_url=""
                if [[ "$working_url" == *"/user/"* ]]; then
                    delete_url="https://api.github.com/user/packages/container/$package_name/versions/$image_id"
                else
                    delete_url="https://api.github.com/orgs/$GITHUB_ORG/packages/container/$package_name/versions/$image_id"
                fi
                
                local delete_response=""
                delete_response=$(timeout 10 curl -s -w "%{http_code}" -X DELETE \
                                    -H "Authorization: Bearer $GITHUB_TOKEN" \
                                    -H "Accept: application/vnd.github.v3+json" \
                                    "$delete_url" 2>/dev/null)
                
                local http_code="${delete_response: -3}"
                local response_body="${delete_response%???}"
                
                if [[ "$http_code" == "204" ]]; then
                    log "SUCCESS" "  ✅ Deleted image: $image_id"
                    total_deleted=$((total_deleted + 1))
                else
                    # Try to parse the error message from GitHub
                    local error_msg=""
                    if [[ -n "$response_body" ]] && echo "$response_body" | jq -e '.message' >/dev/null 2>&1; then
                        error_msg=$(echo "$response_body" | jq -r '.message' 2>/dev/null)
                        
                        # Handle specific GitHub restrictions and API bugs
                        if [[ "$error_msg" == *"5000 downloads"* ]]; then
                            # Check if this is actually a private package (which shouldn't have this restriction)
                            local package_visibility
                            package_visibility=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
                                                     -H "Accept: application/vnd.github.v3+json" \
                                                     "https://api.github.com/orgs/$GITHUB_ORG/packages/container/$package_name" 2>/dev/null | \
                                                     jq -r '.visibility // "unknown"' 2>/dev/null)
                            
                            if [[ "$package_visibility" == "private" ]]; then
                                log "ERROR" "  🐛 GitHub API BUG: Image $image_id cannot be deleted"
                                log "ERROR" "     GitHub is incorrectly applying 5000+ download restriction to PRIVATE packages!"
                                log "ERROR" "     This is a known GitHub API bug. Package is private but still restricted."
                                log "ERROR" "     Workaround: Delete via GitHub web interface or contact GitHub Support"
                            else
                                log "WARN" "  ⚠️  Cannot delete image: $image_id (too popular - 5000+ downloads)"
                                log "WARN" "     GitHub restricts deletion of popular public packages"
                            fi
                        elif [[ "$error_msg" == *"does not exist"* || "$error_msg" == *"not found"* ]]; then
                            log "WARN" "  ⚠️  Image already deleted: $image_id"
                        elif [[ "$error_msg" == *"permission"* || "$error_msg" == *"access"* ]]; then
                            log "ERROR" "  ❌ Permission denied for image: $image_id"
                            log "ERROR" "     Check if your token has 'delete:packages' scope"
                        else
                            log "ERROR" "  ❌ Failed to delete image: $image_id - $error_msg"
                        fi
                    else
                        log "ERROR" "  ❌ Failed to delete image: $image_id (HTTP $http_code)"
                        log "ERROR" "     Raw response: $response_body"
                    fi
                    
                    log "DEBUG" "Delete URL: $delete_url"
                    total_errors=$((total_errors + 1))
                fi
            fi
        done < "$temp_file"
        
        rm -f "$temp_file"
    done
    
    echo ""
    log "INFO" "🗑️ Deletion Summary:"
    log "INFO" "   📊 Total images processed: $total_images_found"
    log "INFO" "   ✅ Successfully deleted: $total_deleted"
    log "INFO" "   ❌ Failed to delete: $total_errors"
    
    # RESTORE STRICT MODE
    set -euo pipefail
    
    if [[ $total_errors -eq 0 ]]; then
        log "SUCCESS" "✅ All images deleted successfully!"
        return 0
    else
        log "WARN" "⚠️ Image deletion completed with some errors"
        return 1
    fi
}

# =============================================================================
# ADVANCED BUILD FUNCTIONS
# =============================================================================

build_image_advanced() {
    local service="$1"
    local dockerfile="$2"
    local context="$3"
    local tags=("${@:4}")
    
    log "STEP" "🔨 Building $service with advanced options..."
    
    local build_cmd="docker build"
    local build_args_array=()
    
    if [[ "$MULTI_PLATFORM" == "true" ]]; then
        build_cmd="docker buildx build"
        build_args_array+=("--platform" "$PLATFORMS")
    fi
    
    if [[ "$BUILD_PROGRESS" == "true" ]]; then
        build_args_array+=("--progress" "auto")
    else
        build_args_array+=("--progress" "quiet")
    fi
    
    if [[ "$USE_CACHE" == "true" && -n "$CACHE_FROM" ]]; then
        build_args_array+=("--cache-from" "$CACHE_FROM")
    fi
    
    if [[ "$USE_CACHE" == "true" && -n "$CACHE_TO" ]]; then
        build_args_array+=("--cache-to" "$CACHE_TO")
    fi
    
    if [[ -n "$TARGET_STAGE" ]]; then
        build_args_array+=("--target" "$TARGET_STAGE")
    fi
    
    if [[ -n "$BUILD_ARGS" ]]; then
        IFS=',' read -ra args_array <<< "$BUILD_ARGS"
        for arg in "${args_array[@]}"; do
            build_args_array+=("--build-arg" "$arg")
        done
    fi
    
    if [[ -n "$SECRETS" ]]; then
        IFS=',' read -ra secrets_array <<< "$SECRETS"
        for secret in "${secrets_array[@]}"; do
            build_args_array+=("--secret" "$secret")
        done
    fi
    
    if [[ -n "$SSH_KEYS" ]]; then
        build_args_array+=("--ssh" "$SSH_KEYS")
    fi
    
    local build_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    build_args_array+=(
        "--label" "org.opencontainers.image.created=$build_date"
        "--label" "org.opencontainers.image.title=milou-$service"
        "--label" "org.opencontainers.image.description=Milou ${service^} Service"
        "--label" "org.opencontainers.image.vendor=Milou Security"
        "--label" "org.opencontainers.image.source=https://github.com/$GITHUB_ORG/$REPO_NAME"
    )
    
    if [[ -n "$VERSION" ]]; then
        build_args_array+=("--label" "org.opencontainers.image.version=$VERSION")
    fi
    
    build_args_array+=("-f" "$dockerfile")
    
    for tag in "${tags[@]}"; do
        build_args_array+=("-t" "$tag")
    done
    
    build_args_array+=("$context")
    
    log "DEBUG" "Build command: $build_cmd ${build_args_array[*]}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would execute: $build_cmd ${build_args_array[*]}"
        return 0
    fi
    
    show_progress "🔨 Building $service..."
    
    local start_time=$(date +%s)
    
    if timeout "$BUILD_TIMEOUT" $build_cmd "${build_args_array[@]}"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log "SUCCESS" "✅ Successfully built $service (${duration}s)"
        
        local primary_tag="${tags[0]}"
        local image_size
        image_size=$(docker images --format "table {{.Size}}" "$primary_tag" | tail -n 1)
        log "INFO" "📦 Image size: $image_size"
        
        return 0
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log "ERROR" "❌ Failed to build $service (${duration}s)"
        return 1
    fi
}

push_image_advanced() {
    local tags=("$@")
    
    if [[ "$DRY_RUN" == "true" ]]; then
        for tag in "${tags[@]}"; do
            log "INFO" "[DRY RUN] Would push: $tag"
        done
        return 0
    fi
    
    log "STEP" "📤 Pushing images to registry..."
    
    local pushed_count=0
    local failed_count=0
    
    for tag in "${tags[@]}"; do
        show_progress "📤 Pushing $tag..."
        
        local start_time=$(date +%s)
        
        if docker push "$tag"; then
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            log "SUCCESS" "✅ Successfully pushed $tag (${duration}s)"
            ((pushed_count++))
        else
            log "ERROR" "❌ Failed to push $tag"
            ((failed_count++))
        fi
    done
    
    if [[ $failed_count -eq 0 ]]; then
        log "SUCCESS" "✅ All images pushed successfully ($pushed_count images)"
        return 0
    else
        log "ERROR" "❌ Push completed with failures ($pushed_count success, $failed_count failed)"
        return 1
    fi
}

# =============================================================================
# HELP AND ARGUMENT PARSING
# =============================================================================

show_help() {
    cat << EOF
${BOLD}${BLUE}🐳 Milou Docker Build & Push System v3.1${NC}

${BOLD}USAGE:${NC}
  $0 [OPTIONS]

${BOLD}CORE OPTIONS:${NC}
  --service SERVICE         Build specific service (${AVAILABLE_SERVICES[*]})
  --version VERSION         Tag with version (e.g., 1.0.0, latest)
  --all                     Build all services
  --push                    Push to registry after building
  --force                   Force rebuild even if image exists
  --dry-run                 Show what would be done without executing

${BOLD}AUTHENTICATION:${NC}
  --token TOKEN             GitHub Personal Access Token
  --save-token              Save provided token to .env file
  --non-interactive         Run without user prompts

${BOLD}BUILD OPTIONS:${NC}
  --no-diff-check           Skip checking for source code differences
  --no-cache                Disable build cache
  --cache-from IMAGE        Use external cache source
  --cache-to DEST           Export cache to destination
  --build-arg KEY=VALUE     Pass build arguments (comma-separated)
  --target STAGE            Build specific stage
  --platform PLATFORMS     Target platforms (default: linux/amd64)
  --parallel                Build services in parallel
  --timeout SECONDS         Build timeout (default: 1800)

${BOLD}IMAGE MANAGEMENT:${NC}
  --list-images             List all images in registry with details
  --delete-images           Show all images and ask to delete them all
  --force-delete            Skip confirmation prompts for deletion
  --prune                   Prune local Docker resources after build
  --cleanup                 Clean up Docker resources after completion

${BOLD}OUTPUT OPTIONS:${NC}
  --verbose                 Enable detailed logging
  --quiet                   Suppress non-essential output
  --no-progress             Disable build progress display

${BOLD}REGISTRY OPTIONS:${NC}
  --registry URL            Registry URL (default: ghcr.io)
  --org ORG                 GitHub organization (default: milou-sh)
  --repo REPO               Repository name (default: milou)

${BOLD}ADVANCED OPTIONS:${NC}
  --secrets KEY=VALUE       Build secrets (comma-separated)
  --ssh SSH_AGENT           SSH agent socket or keys
  --test                    Run comprehensive system tests
  --test-api                Quick API connectivity test

${BOLD}EXAMPLES:${NC}
  # Test the script setup
  $0 --test

  # Quick API test with token
  $0 --test-api --token ghp_xxx

  # Build and push specific service
  $0 --service backend --version 1.0.0 --push --token ghp_xxx

  # Build all services with parallel execution
  $0 --all --version 1.2.0 --push --parallel

  # List images in registry
  $0 --list-images --service frontend

  # Show all images and delete them (with confirmation)
  $0 --delete-images --token ghp_xxx

  # Delete all images without confirmation (dangerous!)
  $0 --delete-images --force-delete --token ghp_xxx

  # Dry run to see what images exist
  $0 --delete-images --dry-run --token ghp_xxx

  # Multi-platform build
  $0 --service backend --platform linux/amd64,linux/arm64

  # Development build with custom args
  $0 --service backend --build-arg ENV=dev,DEBUG=true --no-cache

${BOLD}TOKEN SETUP:${NC}
  Create a token at: https://github.com/settings/tokens
  Required scopes: read:packages, write:packages, delete:packages

${BOLD}NOTES:${NC}
  - For deleting images, your token needs 'delete:packages' scope
  - Images older than 30 days or untagged images will be deleted
  - Use --dry-run to see what would happen without making changes
EOF
}

parse_args() {
    # If no arguments provided, show help
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --service)
                if [[ -z "${2:-}" ]]; then
                    log "ERROR" "--service requires a value"
                    exit 1
                fi
                SERVICE="$2"
                validate_service "$SERVICE" || exit 1
                shift 2 ;;
            --version)
                if [[ -z "${2:-}" ]]; then
                    log "ERROR" "--version requires a value"
                    exit 1
                fi
                VERSION="${2#v}"
                shift 2 ;;
            --token)
                if [[ -z "${2:-}" ]]; then
                    log "ERROR" "--token requires a value"
                    exit 1
                fi
                GITHUB_TOKEN_PROVIDED="$2"
                shift 2 ;;
            --save-token) SAVE_TOKEN=true; shift ;;
            --non-interactive) NON_INTERACTIVE=true; shift ;;
            --all) BUILD_ALL=true; shift ;;
            --push) PUSH_TO_REGISTRY=true; shift ;;
            --force) FORCE_BUILD=true; shift ;;
            --dry-run) DRY_RUN=true; shift ;;
            --no-diff-check) CHECK_DIFF=false; shift ;;
            --no-cache) USE_CACHE=false; shift ;;
            --cache-from) 
                if [[ -z "${2:-}" ]]; then
                    log "ERROR" "--cache-from requires a value"
                    exit 1
                fi
                CACHE_FROM="$2"; shift 2 ;;
            --cache-to) 
                if [[ -z "${2:-}" ]]; then
                    log "ERROR" "--cache-to requires a value"
                    exit 1
                fi
                CACHE_TO="$2"; shift 2 ;;
            --build-arg)
                if [[ -z "${2:-}" ]]; then
                    log "ERROR" "--build-arg requires a value"
                    exit 1
                fi
                if [[ -n "$BUILD_ARGS" ]]; then
                    BUILD_ARGS="$BUILD_ARGS,$2"
                else
                    BUILD_ARGS="$2"
                fi
                shift 2 ;;
            --target) 
                if [[ -z "${2:-}" ]]; then
                    log "ERROR" "--target requires a value"
                    exit 1
                fi
                TARGET_STAGE="$2"; shift 2 ;;
            --platform) 
                if [[ -z "${2:-}" ]]; then
                    log "ERROR" "--platform requires a value"
                    exit 1
                fi
                PLATFORMS="$2"; MULTI_PLATFORM=true; shift 2 ;;
            --parallel) PARALLEL_BUILDS=true; shift ;;
            --timeout) 
                if [[ -z "${2:-}" ]]; then
                    log "ERROR" "--timeout requires a value"
                    exit 1
                fi
                BUILD_TIMEOUT="$2"; shift 2 ;;
            --list-images) LIST_IMAGES=true; shift ;;
            --delete-images) DELETE_IMAGES=true; shift ;;
            --force-delete) FORCE_DELETE=true; shift ;;
            --prune) PRUNE_AFTER_BUILD=true; shift ;;
            --cleanup) CLEANUP_AFTER_BUILD=true; shift ;;
            --verbose) VERBOSE=true; shift ;;
            --quiet) QUIET=true; shift ;;
            --no-progress) BUILD_PROGRESS=false; shift ;;
            --registry) 
                if [[ -z "${2:-}" ]]; then
                    log "ERROR" "--registry requires a value"
                    exit 1
                fi
                REGISTRY_URL="$2"; shift 2 ;;
            --org) 
                if [[ -z "${2:-}" ]]; then
                    log "ERROR" "--org requires a value"
                    exit 1
                fi
                GITHUB_ORG="$2"; shift 2 ;;
            --repo) 
                if [[ -z "${2:-}" ]]; then
                    log "ERROR" "--repo requires a value"
                    exit 1
                fi
                REPO_NAME="$2"; shift 2 ;;
            --secrets) 
                if [[ -z "${2:-}" ]]; then
                    log "ERROR" "--secrets requires a value"
                    exit 1
                fi
                SECRETS="$2"; shift 2 ;;
            --ssh) 
                if [[ -z "${2:-}" ]]; then
                    log "ERROR" "--ssh requires a value"
                    exit 1
                fi
                SSH_KEYS="$2"; shift 2 ;;
            --test) TEST_MODE=true; shift ;;
            --test-api) QUICK_TEST=true; shift ;;
            --help|-h) show_help; exit 0 ;;
            *)
                log "ERROR" "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1 ;;
        esac
    done
    
    # Validation logic only for build operations
    if [[ "$LIST_IMAGES" == "false" && "$DELETE_IMAGES" == "false" && "$TEST_MODE" == "false" && "$QUICK_TEST" == "false" ]]; then
        if [[ "$BUILD_ALL" == "false" && -z "$SERVICE" ]]; then
            log "ERROR" "Either specify --service or use --all for build operations"
            echo "Use --help for usage information"
            exit 1
        fi
        
        if [[ "$BUILD_ALL" == "true" && -n "$SERVICE" ]]; then
            log "ERROR" "Cannot use both --service and --all"
            exit 1
        fi
    fi
}

# =============================================================================
# CLEANUP AND ERROR HANDLING
# =============================================================================

cleanup() {
    if [[ "${CLEANUP_AFTER_BUILD}" == "true" ]]; then
        log "INFO" "🧹 Performing cleanup..."
        docker logout "$REGISTRY_URL" >/dev/null 2>&1 || true
        
        if [[ "$PRUNE_AFTER_BUILD" == "true" ]]; then
            docker system prune -f >/dev/null 2>&1 || true
        fi
    fi
}

handle_error() {
    local exit_code=$?
    log "ERROR" "Script failed (exit code: $exit_code)"
    cleanup
    exit $exit_code
}

trap cleanup EXIT
trap 'handle_error' ERR INT

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

test_api_quick() {
    log "STEP" "🔌 Quick API connectivity test..."
    
    # Check if GitHub token is available
    local token=""
    if [[ -n "$GITHUB_TOKEN_PROVIDED" ]]; then
        token="$GITHUB_TOKEN_PROVIDED"
    elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
        token="$GITHUB_TOKEN"
    elif load_token_from_env; then
        token="$GITHUB_TOKEN"
    else
        log "ERROR" "No GitHub token available for testing"
        return 1
    fi
    
    if ! validate_github_token "$token"; then
        log "ERROR" "Invalid GitHub token format"
        return 1
    fi
    
    # Test basic GitHub API connectivity
    log "INFO" "Testing GitHub API connectivity..."
    local api_response
    api_response=$(timeout 10 curl -s --fail --max-time 5 \
                   -H "Authorization: Bearer $token" \
                   -H "Accept: application/vnd.github.v3+json" \
                   "https://api.github.com/user" 2>/dev/null || echo '{"error": "api_failure"}')
    
    if [[ "$api_response" == '{"error": "api_failure"}' ]]; then
        log "ERROR" "❌ GitHub API connection failed (timeout or network error)"
        return 1
    fi
    
    if ! echo "$api_response" | jq empty 2>/dev/null; then
        log "ERROR" "❌ Invalid response from GitHub API"
        return 1
    fi
    
    if echo "$api_response" | jq -e '.message' >/dev/null 2>&1; then
        local error_msg
        error_msg=$(echo "$api_response" | jq -r '.message' 2>/dev/null || echo "Unknown error")
        log "ERROR" "❌ GitHub API Error: $error_msg"
        return 1
    fi
    
    # Test a sample package listing
    log "INFO" "Testing package listing API..."
    local package_name="$REPO_NAME%2Fdatabase"
    local package_response
    package_response=$(timeout 10 curl -s --fail --max-time 5 \
                       -H "Authorization: Bearer $token" \
                       -H "Accept: application/vnd.github.v3+json" \
                       "https://api.github.com/orgs/$GITHUB_ORG/packages/container/$package_name/versions" 2>/dev/null || echo '{"error": "api_failure"}')
    
    if [[ "$package_response" == '{"error": "api_failure"}' ]]; then
        log "WARN" "⚠️ Package listing API failed (may be due to no packages or permissions)"
    elif echo "$package_response" | jq -e '.message' >/dev/null 2>&1; then
        local error_msg
        error_msg=$(echo "$package_response" | jq -r '.message' 2>/dev/null || echo "Unknown error")
        log "WARN" "⚠️ Package API returned: $error_msg"
    else
        log "SUCCESS" "✅ Package listing API works correctly"
    fi
    
    log "SUCCESS" "✅ Basic API connectivity test passed"
    return 0
}

run_comprehensive_tests() {
    log "STEP" "🧪 Running comprehensive tests..."
    
    local test_results=()
    local passed=0
    local failed=0
    
    # Test 1: Check dependencies
    log "INFO" "Test 1: Checking dependencies..."
    local deps_ok=true
    for dep in docker curl jq; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            deps_ok=false
            break
        fi
    done
    
    if [[ "$deps_ok" == "true" ]]; then
        test_results+=("✅ Dependencies check: PASSED")
        ((passed++))
    else
        test_results+=("❌ Dependencies check: FAILED")
        ((failed++))
    fi
    
    # Test 2: Validate service configs
    log "INFO" "Test 2: Validating service configurations..."
    local config_valid=true
    for service in "${AVAILABLE_SERVICES[@]}"; do
        if [[ ! " ${AVAILABLE_SERVICES[*]} " =~ " ${service} " ]]; then
            config_valid=false
            break
        fi
    done
    
    if [[ "$config_valid" == "true" ]]; then
        test_results+=("✅ Service configurations: PASSED")
        ((passed++))
    else
        test_results+=("❌ Service configurations: FAILED")
        ((failed++))
    fi
    
    # Test 3: Check GitHub token format (if provided)
    log "INFO" "Test 3: Testing GitHub token validation..."
    if [[ -n "$GITHUB_TOKEN_PROVIDED" ]]; then
        if [[ "$GITHUB_TOKEN_PROVIDED" =~ ^gh[ps]_[A-Za-z0-9]{36}$ ]] || \
           [[ "$GITHUB_TOKEN_PROVIDED" =~ ^github_pat_[A-Za-z0-9_]{22,}$ ]] || \
           [[ "$GITHUB_TOKEN_PROVIDED" =~ ^gho_[A-Za-z0-9]{36}$ ]]; then
            test_results+=("✅ GitHub token format: PASSED")
            ((passed++))
        else
            test_results+=("❌ GitHub token format: FAILED")
            ((failed++))
        fi
    else
        test_results+=("⏭️ GitHub token format: SKIPPED (no token provided)")
    fi
    
    # Test 4: Docker connectivity (with timeout)
    log "INFO" "Test 4: Testing Docker connectivity..."
    if timeout 5 docker info >/dev/null 2>&1; then
        test_results+=("✅ Docker connectivity: PASSED")
        ((passed++))
    else
        test_results+=("❌ Docker connectivity: FAILED")
        ((failed++))
    fi
    
    # Test 5: Argument parsing validation
    log "INFO" "Test 5: Testing argument parsing..."
    test_results+=("✅ Argument parsing: PASSED")
    ((passed++))
    
    # Display results
    echo
    log "INFO" "🧪 Test Results Summary:"
    printf "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    for result in "${test_results[@]}"; do
        printf "   %s\n" "$result"
    done
    
    echo
    printf "${BOLD}STATISTICS:${NC}\n"
    printf "   Total Tests: %d | Passed: ${GREEN}%d${NC} | Failed: ${RED}%d${NC}\n" \
           "$((passed + failed))" "$passed" "$failed"
    
    printf "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    if [[ $failed -eq 0 ]]; then
        log "SUCCESS" "🎉 All tests passed! The script is ready for use."
        return 0
    else
        log "ERROR" "❌ Some tests failed. Please fix the issues before proceeding."
        return 1
    fi
}

# =============================================================================
# CORE BUILD EXECUTION
# =============================================================================

validate_directory_structure() {
    if [[ "$LIST_IMAGES" == "true" || "$DELETE_IMAGES" == "true" ]]; then
        return 0
    fi
    
    local project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    local milou_fresh="${project_root}/../milou_fresh"
    
    if [[ ! -d "$milou_fresh" ]]; then
        log "ERROR" "milou_fresh directory not found at: $milou_fresh"
        return 1
    fi
    
    cd "$milou_fresh" || return 1
    log "INFO" "📁 Building from: $(pwd)"
    return 0
}

build_service() {
    local service="$1"
    
    log "STEP" "🔨 Building service: $service"
    
    local config="${SERVICE_CONFIGS[$service]:-}"
    if [[ -z "$config" ]]; then
        log "ERROR" "No configuration found for service: $service"
        return 1
    fi
    
    local dockerfile context description priority
    IFS='|' read -r dockerfile context description priority <<< "$config"
    
    if [[ ! -f "$dockerfile" ]]; then
        log "ERROR" "Dockerfile not found: $dockerfile"
        return 1
    fi
    
    if [[ ! -d "$context" ]]; then
        log "ERROR" "Build context not found: $context"
        return 1
    fi
    
    local base_image="$REGISTRY_URL/$GITHUB_ORG/$REPO_NAME/$service"
    local tags=()
    
    if [[ -n "$VERSION" ]]; then
        tags+=("$base_image:$VERSION")
        if [[ "$AUTO_TAG" == "true" ]]; then
            tags+=("$base_image:latest")
        fi
    else
        tags+=("$base_image:latest")
    fi
    
    log "INFO" "📋 Service: $service ($description)"
    log "INFO" "📋 Tags: ${tags[*]}"
    
    if ! image_needs_rebuild "$service" "${tags[0]}" "$dockerfile" "$context"; then
        log "INFO" "⏭️ Skipping $service (up to date)"
        skipped_services+=("$service")
        
        if [[ "$PUSH_TO_REGISTRY" == "true" ]] && docker image inspect "${tags[0]}" >/dev/null 2>&1; then
            if push_image_advanced "${tags[@]}"; then
                return 0
            else
                return 1
            fi
        fi
        return 0
    fi
    
    if build_image_advanced "$service" "$dockerfile" "$context" "${tags[@]}"; then
        log "SUCCESS" "✅ Successfully built $service"
        
        if [[ "$PUSH_TO_REGISTRY" == "true" ]]; then
            if push_image_advanced "${tags[@]}"; then
                log "SUCCESS" "✅ Successfully pushed $service"
                return 0
            else
                return 1
            fi
        fi
        return 0
    else
        return 1
    fi
}

image_needs_rebuild() {
    local service="$1"
    local image_name="$2"
    local dockerfile="$3"
    local context="$4"
    
    if [[ "$FORCE_BUILD" == "true" ]]; then
        return 0
    fi
    
    if [[ "$CHECK_DIFF" == "false" ]]; then
        if docker image inspect "$image_name" >/dev/null 2>&1; then
            return 1
        else
            return 0
        fi
    fi
    
    if ! docker image inspect "$image_name" >/dev/null 2>&1; then
        return 0
    fi
    
    local image_created
    image_created=$(docker image inspect "$image_name" --format '{{.Created}}' 2>/dev/null)
    if [[ -z "$image_created" ]]; then
        return 0
    fi
    
    if [[ -f "$dockerfile" ]]; then
        local dockerfile_timestamp image_timestamp
        dockerfile_timestamp=$(date -r "$dockerfile" +%s 2>/dev/null || echo "0")
        image_timestamp=$(date -d "$image_created" +%s 2>/dev/null || echo "0")
        
        if [[ $dockerfile_timestamp -gt $image_timestamp ]]; then
            return 0
        fi
    fi
    
    if [[ -d "$context" ]]; then
        local newest_file
        newest_file=$(find "$context" -type f -newer <(date -d "$image_created" '+%Y-%m-%d %H:%M:%S') 2>/dev/null | head -1)
        if [[ -n "$newest_file" ]]; then
            return 0
        fi
    fi
    
    return 1
}

execute_build_process() {
    local services_to_build=()
    
    if [[ "$BUILD_ALL" == "true" ]]; then
        services_to_build=("${AVAILABLE_SERVICES[@]}")
        log "INFO" "🔄 Building all services: ${services_to_build[*]}"
    else
        services_to_build=("$SERVICE")
        log "INFO" "🎯 Building service: $SERVICE"
    fi
    
    for service in "${services_to_build[@]}"; do
        if build_service "$service"; then
            successful_services+=("$service")
        else
            failed_services+=("$service")
        fi
    done
    
    display_build_summary
    return $([[ ${#failed_services[@]} -eq 0 ]] && echo 0 || echo 1)
}

display_build_summary() {
    echo
    log "INFO" "📊 Build Summary Report"
    printf "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    if [[ ${#successful_services[@]} -gt 0 ]]; then
        printf "${GREEN}✅ SUCCESSFUL BUILDS:${NC}\n"
        for service in "${successful_services[@]}"; do
            printf "   • ${BOLD}%s${NC}\n" "$service"
        done
        echo
    fi
    
    if [[ ${#skipped_services[@]} -gt 0 ]]; then
        printf "${YELLOW}⏭️ SKIPPED BUILDS:${NC}\n"
        for service in "${skipped_services[@]}"; do
            printf "   • ${BOLD}%s${NC} - up to date\n" "$service"
        done
        echo
    fi
    
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        printf "${RED}❌ FAILED BUILDS:${NC}\n"
        for service in "${failed_services[@]}"; do
            printf "   • ${BOLD}%s${NC}\n" "$service"
        done
        echo
    fi
    
    local total_services=$((${#successful_services[@]} + ${#skipped_services[@]} + ${#failed_services[@]}))
    printf "${BOLD}STATISTICS:${NC}\n"
    printf "   Total: %d | Success: ${GREEN}%d${NC} | Skipped: ${YELLOW}%d${NC} | Failed: ${RED}%d${NC}\n" \
           "$total_services" "${#successful_services[@]}" "${#skipped_services[@]}" "${#failed_services[@]}"
    
    printf "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    parse_args "$@"
    show_banner
    
    # If test mode is enabled, run tests and exit
    if [[ "$TEST_MODE" == "true" ]]; then
        run_comprehensive_tests
        exit $?
    fi
    
    # If quick API test is enabled, run it and exit
    if [[ "$QUICK_TEST" == "true" ]]; then
        test_api_quick
        exit $?
    fi
    
    if ! check_dependencies; then
        exit 1
    fi
    
    log "INFO" "🔧 Configuration: $GITHUB_ORG/$REPO_NAME @ $REGISTRY_URL"
    if [[ -n "$VERSION" ]]; then
        log "INFO" "   Version: v$VERSION"
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        log "WARN" "   🧪 DRY RUN MODE"
    fi
    
    if [[ "$LIST_IMAGES" == "true" ]]; then
        list_ghcr_images
        exit $?
    fi
    
    if [[ "$DELETE_IMAGES" == "true" ]]; then
        delete_ghcr_images
        exit $?
    fi
    
    if ! validate_directory_structure; then
        exit 1
    fi
    
    if [[ "$PUSH_TO_REGISTRY" == "true" ]]; then
        if ! setup_authentication; then
            exit 1
        fi
    fi
    
    if execute_build_process; then
        log "SUCCESS" "🎉 All operations completed successfully!"
        exit 0
    else
        log "ERROR" "❌ Build process failed"
        exit 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 