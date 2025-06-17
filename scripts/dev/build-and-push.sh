#!/bin/bash

# =============================================================================
# Milou CLI - Enhanced Docker Build and Push Script v3.2
#   • Allows custom project path (instead of hard-coded ../milou_fresh)
#   • Parallel builds enabled by default (up to MAX_PARALLEL_JOBS simultaneous)
#   • Adds --no-parallel to disable parallelism
# =============================================================================

set -euo pipefail
IFS=$'\n\t'  # Prevent word-splitting and globbing surprises

# ----------------------------------------
# COLORS AND FORMATTING
# ----------------------------------------
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

# =============================================================================
# GLOBAL CONFIGURATION
# =============================================================================
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

### CHANGED: Default parallel builds to true
PARALLEL_BUILDS=true                            # was false
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

### ADDED: New variable for custom project path
PROJECT_PATH=""                                  # Will be set via --path or default to ../milou_fresh

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
# MODULE DEPENDENCIES
# =============================================================================
# Source validation module for GitHub token validation
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATION_MODULE="${SCRIPT_DIR}/../../src/_validation.sh"

if [[ -f "$VALIDATION_MODULE" ]]; then
    source "$VALIDATION_MODULE" || {
        log "ERROR" "Failed to load validation module: $VALIDATION_MODULE"
        exit 1
    }
else
    log "WARN" "Validation module not found: $VALIDATION_MODULE"
    log "WARN" "Using fallback token validation"
    
    # Fallback validation function if module not available
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
fi

# =============================================================================
# LOGGING AND OUTPUT FUNCTIONS
# =============================================================================
log() {
    local level="$1"
    shift
    local timestamp
    timestamp=$(date '+%H:%M:%S')

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
        printf "${BOLD}${BLUE}               🐳 MILOU DOCKER BUILD & PUSH SYSTEM v3.2                    ${NC}\n"
        printf "${BOLD}${BLUE}                        Professional Docker Management                      ${NC}\n"
        printf "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    fi
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================
validate_service() {
    local service_to_validate="$1"
    for service in "${AVAILABLE_SERVICES[@]}"; do
        if [[ "$service" == "$service_to_validate" ]]; then
            return 0
        fi
    done

    log "ERROR" "Invalid service: $service_to_validate"
    log "ERROR" "Available services: ${AVAILABLE_SERVICES[*]}"
    return 1
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
    local env_file
    env_file="$(dirname "$0")/../.env"
    if [[ -f "$env_file" ]]; then
        local token
        token=$(grep "^GITHUB_TOKEN=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || echo "")
        if [[ -n "$token" ]]; then
            export GITHUB_TOKEN="$token"
            return 0
        fi
    fi
    return 1
}

save_token_to_env() {
    local token="$1"
    local env_file
    env_file="$(dirname "$0")/../.env"

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
# HELPER: GITHUB API BUG LOGGING FOR PRIVATE PACKAGES
# =============================================================================
log_github_bug_for_private_package() {
    local service="$1"
    local image_id="$2"
    local package_name_url_encoded="$3" # e.g., myrepo%2Fmyservice
    local token="$4"
    local org="$5"

    local package_visibility="unknown"
    # Check org endpoint first
    local visibility_url_org="https://api.github.com/orgs/$org/packages/container/$package_name_url_encoded"
    local visibility_response_org
    visibility_response_org=$(timeout 10 curl -s -H "Authorization: Bearer $token" \
                               -H "Accept: application/vnd.github.v3+json" \
                               "$visibility_url_org" 2>/dev/null)
    package_visibility=$(echo "$visibility_response_org" | jq -r '.visibility // "unknown"' 2>/dev/null)

    if [[ "$package_visibility" == "unknown" || "$package_visibility" == "null" ]]; then
        # Check user endpoint if org failed or gave no visibility
        local visibility_url_user="https://api.github.com/user/packages/container/$package_name_url_encoded"
        local visibility_response_user
        visibility_response_user=$(timeout 10 curl -s -H "Authorization: Bearer $token" \
                                   -H "Accept: application/vnd.github.v3+json" \
                                   "$visibility_url_user" 2>/dev/null)
        package_visibility=$(echo "$visibility_response_user" | jq -r '.visibility // "unknown"' 2>/dev/null)
    fi

    if [[ "$package_visibility" == "private" ]]; then
        log "WARN" "  ⚠️  Encountered a known GitHub API bug on private package '$service' (version $image_id)."
        log "WARN" "     The API is blocking the deletion of this version with a false error."
        log "WARN" "     To resolve this, the entire package will be deleted instead."
        return 0 # Success, indicates it's the private package bug
    else
        log "ERROR" "  ❌ Cannot delete image version $image_id for $service. It is a public package with over 5000 downloads."
        log "ERROR" "     Visibility determined as: $package_visibility"
        return 1 # Failure, it's a legitimate public package restriction
    fi
}

# =============================================================================
# HELPER: DELETE ENTIRE GHCR PACKAGE
# =============================================================================
delete_ghcr_package() {
    local service="$1"
    local token="$2"
    local org="$3"
    local repo="$4"

    log "INFO" "  Attempting to delete ENTIRE PACKAGE: $repo/$service for org $org (or user if org fails)"

    local package_name_url_encoded="$repo%2F$service"
    local delete_urls=(
        "https://api.github.com/orgs/$org/packages/container/$package_name_url_encoded"
        "https://api.github.com/user/packages/container/$package_name_url_encoded"
    )
    local deleted_successfully=false

    for delete_url in "${delete_urls[@]}"; do
        log "DEBUG" "    Trying package delete URL: $delete_url"
        local delete_response
        delete_response=$(timeout 30 curl -s -w "%{http_code}" -X DELETE \
                            -H "Authorization: Bearer $token" \
                            -H "Accept: application/vnd.github.v3+json" \
                            "$delete_url" 2>/dev/null)
        
        local http_code="${delete_response: -3}"
        local response_body="${delete_response%???}"

        if [[ "$http_code" == "204" ]]; then
            log "SUCCESS" "      ✅ Package $repo/$service deleted successfully via $delete_url"
            deleted_successfully=true
            break
        elif [[ "$http_code" == "404" ]]; then
            log "DEBUG" "    Package not found at $delete_url (HTTP $http_code). This may be normal if trying org vs user path."
        elif [[ "$http_code" == "403" ]]; then
            local error_msg_pkg
            error_msg_pkg=$(echo "$response_body" | jq -r '.message // "Permission denied - no message"')
            log "ERROR" "    ❌ Permission denied for package $repo/$service via $delete_url (HTTP $http_code): $error_msg_pkg"
            log "ERROR" "       Ensure token has 'delete:packages' scope and necessary org/repo permissions."
            # This is a hard failure for this attempt, but loop might try user endpoint.
        else # Other errors
            local error_msg_pkg
            error_msg_pkg=$(echo "$response_body" | jq -r '.message // "Unknown error"')
            log "ERROR" "    ❌ Failed to delete package $repo/$service via $delete_url (HTTP $http_code): $error_msg_pkg"
        fi
    done

    if [[ "$deleted_successfully" == "true" ]]; then
        return 0
    else
        log "ERROR" "  Failed to delete ENTIRE PACKAGE $repo/$service from all attempted endpoints."
        return 1
    fi
}

# =============================================================================
# ADVANCED IMAGE MANAGEMENT AND REGISTRY OPERATIONS
# =============================================================================
list_ghcr_images() {
    set +euo pipefail

    log "STEP" "📋 Listing images in GitHub Container Registry..."

    local token=""
    if [[ -n "$GITHUB_TOKEN_PROVIDED" ]]; then
        token="$GITHUB_TOKEN_PROVIDED"
    elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
        token="$GITHUB_TOKEN"
    elif load_token_from_env; then
        token="$GITHUB_TOKEN"
    else
        log "ERROR" "No GitHub token available for API access"
        set -euo pipefail
        return 1
    fi

    if ! validate_github_token "$token"; then
        set -euo pipefail
        return 1
    fi

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

    for service in "${services[@]}"; do
        echo ""
        echo "🐳 $service"
        echo "─────────────────────────────────────────────────────────────────────────────"

        local package_name="$REPO_NAME%2F$service"
        local api_url="https://api.github.com/orgs/$GITHUB_ORG/packages/container/$package_name/versions"

        local response
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
            local error_msg
            error_msg=$(echo "$response" | jq -r '.message' 2>/dev/null || echo "Unknown error")
            echo "  ❌ API Error: $error_msg"
            total_services=$((total_services + 1))
            continue
        fi

        if echo "$response" | jq -e '. | type == "array" and length > 0' >/dev/null 2>&1; then
            local image_count
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

    set -euo pipefail
    return 0
}

delete_ghcr_images() {
    set +euo pipefail

    log "STEP" "🗑️ Managing images in GitHub Container Registry..."

    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        if ! setup_authentication; then
            set -euo pipefail
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

    local total_images_found_preview=0
    declare -A service_data # Stores API URL and base64 encoded response
    declare -A service_initial_image_counts # Stores initial image count for each service

    # First pass: collect and display all images
    for service in "${services_to_clean[@]}"; do
        echo ""
        echo "🐳 $service"
        echo "─────────────────────────────────────────────────────────────────────────────"

        local package_name="$REPO_NAME%2F$service"
        local api_urls=(
            "https://api.github.com/orgs/$GITHUB_ORG/packages/container/$package_name/versions"
            "https://api.github.com/user/packages/container/$package_name/versions"
        )

        local response
        local working_url=""

        for api_url in "${api_urls[@]}"; do
            log "DEBUG" "Trying API endpoint: $api_url"
            response=$(timeout 10 curl -s --fail --max-time 5 \
                           -H "Authorization: Bearer $GITHUB_TOKEN" \
                           -H "Accept: application/vnd.github.v3+json" \
                           "$api_url" 2>/dev/null || echo "[]")

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
            local service_images_found
            service_images_found=$(echo "$response" | jq '. | length' 2>/dev/null || echo "0")
            total_images_found_preview=$((total_images_found_preview + service_images_found))
            service_initial_image_counts["$service"]="$service_images_found"

            echo "$response" | jq -r '.[] |
                if ((.metadata.container.tags // []) | length) > 0 then
                    "  📦 " + ((.metadata.container.tags // []) | join(",")) +
                    "  │  📅 " + (.created_at[0:10]) +
                    "  │  🆔 " + (.name[0:12])
                else
                    "  📦 (untagged)  │  📅 " + (.created_at[0:10]) +
                    "  │  🆔 " + (.name[0:12])
                end' 2>/dev/null || echo "  ⚠️  Format failed"

            echo "  Total: $service_images_found images"

            local encoded_response
            encoded_response=$(echo "$response" | base64 -w 0)
            service_data["$service"]="$working_url|$encoded_response"
        else
            echo "  📭 No images found"
            service_initial_image_counts["$service"]="0"
        fi
    done

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 TOTAL: $total_images_found_preview images found across all services for preview"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [[ $total_images_found_preview -eq 0 ]]; then
        log "INFO" "ℹ️ No images found to delete"
        set -euo pipefail
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "🧪 [DRY RUN] Would proceed with deletion process for $total_images_found_preview images."
        set -euo pipefail
        return 0
    fi

    echo ""
    if [[ "$FORCE_DELETE" != "true" && "$NON_INTERACTIVE" != "true" ]]; then
        echo "⚠️  This will PERMANENTLY DELETE images shown above!"
        echo "    If a service has only tagged versions remaining, the script will attempt to delete the ENTIRE PACKAGE for that service."
        echo ""
        read -p "Do you want to delete these images (and potentially packages)? (type 'DELETE ALL' to confirm): " confirmation
        if [[ "$confirmation" != "DELETE ALL" ]]; then
            log "INFO" "Operation cancelled by user"
            set -euo pipefail
            return 0
        fi
    fi

    echo ""
    if [[ "$NON_INTERACTIVE" != "true" ]]; then
        echo "🗑️ Starting deletion process..."
        echo ""
    fi

    local total_versions_deleted_successfully=0
    local total_versions_failed_individual_deletion=0
    local total_packages_attempted_deletion=0
    local total_packages_deleted_successfully=0
    local total_package_deletion_failures=0
    
    declare -A service_needs_package_delete # service_name -> true
    declare -A images_in_service_encountering_last_tag_error # service_name -> count

    for service in "${!service_data[@]}"; do
        log "INFO" "🗑️ Processing image versions for service: $service..."
        local service_info="${service_data[$service]}"
        local working_url="${service_info%|*}"
        local encoded_response="${service_info#*|}"
        local response
        response=$(echo "$encoded_response" | base64 -d)

        local package_name_url_encoded="$REPO_NAME%2F$service" # For bug logger and package deleter
        local temp_file
        temp_file=$(mktemp)
        echo "$response" | jq -r '.[] | .id' 2>/dev/null > "$temp_file"

        local versions_deleted_this_service=0
        local versions_failed_this_service=0 # Individual failures for this service before package attempt
        local last_tag_errors_this_service=0

        while IFS= read -r image_id; do
            if [[ -n "$image_id" ]]; then
                local delete_url=""
                if [[ "$working_url" == *"/user/"* ]]; then
                    delete_url="https://api.github.com/user/packages/container/$package_name_url_encoded/versions/$image_id"
                else
                    delete_url="https://api.github.com/orgs/$GITHUB_ORG/packages/container/$package_name_url_encoded/versions/$image_id"
                fi

                local delete_response
                delete_response=$(timeout 10 curl -s -w "%{http_code}" -X DELETE \
                                    -H "Authorization: Bearer $GITHUB_TOKEN" \
                                    -H "Accept: application/vnd.github.v3+json" \
                                    "$delete_url" 2>/dev/null)

                local http_code="${delete_response: -3}"
                local response_body="${delete_response%???}"

                if [[ "$http_code" == "204" ]]; then
                    log "SUCCESS" "  ✅ Deleted image version: $image_id for $service"
                    versions_deleted_this_service=$((versions_deleted_this_service + 1))
                else
                    local error_msg=""
                    if [[ -n "$response_body" ]] && echo "$response_body" | jq -e '.message' >/dev/null 2>&1; then
                        error_msg=$(echo "$response_body" | jq -r '.message' 2>/dev/null)
                        if [[ "$error_msg" == *"You cannot delete the last tagged version"* ]]; then
                            log "WARN" "  ⚠️ Image version $image_id for $service is a last tagged version. Marking $service for potential package deletion."
                            service_needs_package_delete["$service"]=true
                            last_tag_errors_this_service=$((last_tag_errors_this_service + 1))
                            # This is not counted as an immediate version failure for overall stats yet
                        elif [[ "$error_msg" == *"5000 downloads"* ]]; then
                            if log_github_bug_for_private_package "$service" "$image_id" "$package_name_url_encoded" "$GITHUB_TOKEN" "$GITHUB_ORG"; then
                                # The function already logged the explanation. Now, mark for package deletion.
                                service_needs_package_delete["$service"]=true
                                last_tag_errors_this_service=$((last_tag_errors_this_service + 1))
                            else
                                # It's a public package, which is a genuine failure.
                                versions_failed_this_service=$((versions_failed_this_service + 1))
                            fi
                        elif [[ "$error_msg" == *"does not exist"* || "$error_msg" == *"not found"* ]]; then
                            log "WARN" "  ⚠️  Image version already deleted or not found: $image_id for $service"
                        elif [[ "$error_msg" == *"permission"* || "$error_msg" == *"access"* ]]; then
                            log "ERROR" "  ❌ Permission denied for image version: $image_id for $service"
                            log "ERROR" "     Check if your token has 'delete:packages' scope. Message: $error_msg"
                            versions_failed_this_service=$((versions_failed_this_service + 1))
                        else
                            log "ERROR" "  ❌ Failed to delete image version: $image_id for $service - $error_msg"
                            versions_failed_this_service=$((versions_failed_this_service + 1))
                        fi
                    else
                        log "ERROR" "  ❌ Failed to delete image version: $image_id for $service (HTTP $http_code)"
                        log "ERROR" "     Raw response: $response_body"
                        versions_failed_this_service=$((versions_failed_this_service + 1))
                    fi
                    log "DEBUG" "Delete URL: $delete_url"
                fi
            fi
        done < "$temp_file"

        rm -f "$temp_file"
        total_versions_deleted_successfully=$((total_versions_deleted_successfully + versions_deleted_this_service))
        total_versions_failed_individual_deletion=$((total_versions_failed_individual_deletion + versions_failed_this_service))
        if [[ -n "${service_needs_package_delete[$service]}" ]]; then
            images_in_service_encountering_last_tag_error["$service"]=$last_tag_errors_this_service
        fi
    done

    # Second phase: Attempt package deletions if needed
    if [[ ${#service_needs_package_delete[@]} -gt 0 ]]; then
        log "INFO" ""
        log "INFO" "🔄 Some services require package deletion due to 'last tagged version' errors."
        for service_to_delete_pkg_for in "${!service_needs_package_delete[@]}"; do
            total_packages_attempted_deletion=$((total_packages_attempted_deletion + 1))
            log "INFO" "Attempting to delete ENTIRE PACKAGE for service '$service_to_delete_pkg_for'..."
            if delete_ghcr_package "$service_to_delete_pkg_for" "$GITHUB_TOKEN" "$GITHUB_ORG" "$REPO_NAME"; then
                log "SUCCESS" "✅ Successfully deleted ENTIRE PACKAGE for service: $service_to_delete_pkg_for"
                total_packages_deleted_successfully=$((total_packages_deleted_successfully + 1))
                # Note: Versions previously failed for this service due to "last tag" are now resolved.
                # Other individual failures might also be resolved if the package is gone.
                # For simplicity, we won't try to adjust total_versions_failed_individual_deletion downwards here,
                # but the user should understand package deletion supersedes earlier individual errors for that package.
            else
                log "ERROR" "❌ Failed to delete ENTIRE PACKAGE for service: $service_to_delete_pkg_for"
                total_package_deletion_failures=$((total_package_deletion_failures + 1))
                # The 'last_tag_errors_this_service' for this service are now confirmed *unresolved* failures.
                # Add them to the individual failure count as these versions remain.
                local unresolved_last_tag_errors=${images_in_service_encountering_last_tag_error[$service_to_delete_pkg_for]:-0}
                if [[ $unresolved_last_tag_errors -gt 0 ]]; then
                    log "INFO" "  $unresolved_last_tag_errors image versions for $service_to_delete_pkg_for remain due to failed package deletion after 'last tag' error."
                    total_versions_failed_individual_deletion=$((total_versions_failed_individual_deletion + unresolved_last_tag_errors))
                fi
            fi
        done
    fi

    echo ""
    log "INFO" "🗑️ Deletion Summary:"
    log "INFO" "   📊 Total distinct image versions found initially: $total_images_found_preview"
    log "INFO" "   ✅ Successfully deleted individual image versions: $total_versions_deleted_successfully"
    if [[ $total_packages_attempted_deletion -gt 0 ]]; then
        log "INFO" "   📦 Attempted to delete $total_packages_attempted_deletion entire package(s)."
        log "INFO" "     ✅ Successfully deleted $total_packages_deleted_successfully entire package(s)."
        if [[ $total_package_deletion_failures -gt 0 ]]; then
            log "INFO" "     ❌ Failed to delete $total_package_deletion_failures entire package(s)."
        fi
    fi
    log "INFO" "   ❌ Unresolved failed image version deletions: $total_versions_failed_individual_deletion"
    log "INFO" "      (This includes versions that couldn't be individually deleted and whose package also failed deletion if attempted)"

    set -euo pipefail

    local final_unresolved_errors=$((total_versions_failed_individual_deletion + total_package_deletion_failures))

    if [[ $final_unresolved_errors -eq 0 ]]; then
        # Check if all initially found images are accounted for by individual deletions or package deletions
        # This is complex to perfectly reconcile here, so we focus on errors.
        log "SUCCESS" "✅ All deletion operations attempted. Please verify registry for final state."
        if [[ $total_versions_deleted_successfully -gt 0 || $total_packages_deleted_successfully -gt 0 ]]; then
             return 0 # Success if any deletion happened and no unresolved errors
        elif [[ $total_images_found_preview -eq 0 ]]; then
             return 0 # Success if there was nothing to delete
        else
             # No deletions and no errors, but images were there? Could be dry run or all skipped.
             # This path should ideally not be hit if images were present and not dry_run.
             log "WARN" "No items were deleted, but no errors reported. Check logs."
             return 0 # Consider it non-failure if no errors.
        fi
    else
        log "WARN" "⚠️ Deletion process completed with $final_unresolved_errors unresolved error(s)."
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
    shift 3
    local tags=("$@")

    log "STEP" "🔨 Building $service..."

    local -a build_cmd=(docker build)
    local build_args_array=()

    if [[ "$MULTI_PLATFORM" == "true" ]]; then
        build_cmd=(docker buildx build)
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

    local build_date
    build_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
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

    log "DEBUG" "Build command: ${build_cmd[*]} ${build_args_array[*]}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would execute: ${build_cmd[*]} ${build_args_array[*]}"
        return 0
    fi

    show_progress "🔨 Building $service..."

    local start_time
    start_time=$(date +%s)

    if timeout "$BUILD_TIMEOUT" "${build_cmd[@]}" "${build_args_array[@]}"; then
        local end_time duration
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        log "SUCCESS" "✅ Successfully built $service (${duration}s)"

        local primary_tag="${tags[0]}"
        local image_size
        image_size=$(docker images --format "table {{.Size}}" "$primary_tag" | tail -n 1)
        log "INFO" "📦 Image size: $image_size"

        return 0
    else
        local end_time duration
        end_time=$(date +%s)
        duration=$((end_time - start_time))
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

        local start_time
        start_time=$(date +%s)

        if docker push "$tag"; then
            local end_time duration
            end_time=$(date +%s)
            duration=$((end_time - start_time))
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
${BOLD}${BLUE}🐳 Milou Docker Build & Push System v3.2${NC}

${BOLD}${BLUE}USAGE:${NC}
  $0 [OPTIONS]

${BOLD}${BLUE}CORE OPTIONS:${NC}
  ${CYAN}--service SERVICE${NC}         Build specific service (${AVAILABLE_SERVICES[*]})
  ${CYAN}--version VERSION${NC}         Tag with version (e.g., 1.0.0, latest)
  ${CYAN}--all${NC}                     Build all services
  ${CYAN}--push${NC}                    Push to registry after building
  ${CYAN}--force${NC}                   Force rebuild even if image exists
  ${CYAN}--dry-run${NC}                 Show what would be done without executing

${BOLD}${BLUE}AUTHENTICATION:${NC}
  ${CYAN}--token TOKEN${NC}             GitHub Personal Access Token
  ${CYAN}--save-token${NC}              Save provided token to .env file
  ${CYAN}--non-interactive${NC}         Run without user prompts

${BOLD}${BLUE}BUILD OPTIONS:${NC}
  ${CYAN}--no-diff-check${NC}           Skip checking for source code differences
  ${CYAN}--no-cache${NC}                Disable build cache
  ${CYAN}--cache-from IMAGE${NC}        Use external cache source
  ${CYAN}--cache-to DEST${NC}           Export cache to destination
  ${CYAN}--build-arg KEY=VALUE${NC}     Pass build arguments (comma-separated)
  ${CYAN}--target STAGE${NC}            Build specific stage
  ${CYAN}--platform PLATFORMS${NC}      Target platforms (default: linux/amd64)
  ${CYAN}--no-parallel${NC}             Disable parallel builds (by default, parallel is ON)
  ${CYAN}--timeout SECONDS${NC}         Build timeout (default: 1800)

${BOLD}${BLUE}IMAGE MANAGEMENT:${NC}
  ${CYAN}--list-images${NC}             List all images in registry with details
  ${CYAN}--delete-images${NC}           Show all images and ask to delete them all
  ${CYAN}--force-delete${NC}            Skip confirmation prompts for deletion
  ${CYAN}--prune${NC}                   Prune local Docker resources after build
  ${CYAN}--cleanup${NC}                 Clean up Docker resources after completion

${BOLD}${BLUE}OUTPUT OPTIONS:${NC}
  ${CYAN}--verbose${NC}                 Enable detailed logging
  ${CYAN}--quiet${NC}                   Suppress non-essential output
  ${CYAN}--no-progress${NC}             Disable build progress display

${BOLD}${BLUE}REGISTRY OPTIONS:${NC}
  ${CYAN}--registry URL${NC}            Registry URL (default: ghcr.io)
  ${CYAN}--org ORG${NC}                 GitHub organization (default: milou-sh)
  ${CYAN}--repo REPO${NC}               Repository name (default: milou)

${BOLD}${BLUE}ADVANCED OPTIONS:${NC}
  ${CYAN}--secrets KEY=VALUE${NC}       Build secrets (comma-separated)
  ${CYAN}--ssh SSH_AGENT${NC}           SSH agent socket or keys
  ${CYAN}--test${NC}                    Run comprehensive system tests
  ${CYAN}--test-api${NC}                Quick API connectivity test

${BOLD}${BLUE}PROJECT PATH OPTIONS:${NC}
  ${CYAN}--path PATH${NC}               Location of the 'milou_fresh' directory (default: ../milou_fresh)

${BOLD}${BLUE}EXAMPLES:${NC}
  ${GREEN}# Test the script setup${NC}
  $0 ${CYAN}--test${NC}

  ${GREEN}# Quick API test with token${NC}
  $0 ${CYAN}--test-api --token ghp_xxx${NC}

  ${GREEN}# Build and push specific service${NC}
  $0 ${CYAN}--service backend --version 1.0.0 --push --token ghp_xxx${NC}

  ${GREEN}# Build all services with parallel execution (default)${NC}
  $0 ${CYAN}--all --version 1.2.0 --push --parallel${NC}

  ${GREEN}# Build on a custom project path${NC}
  $0 ${CYAN}--all --path /home/user/repos/milou_fresh --version 2.0.0${NC}

  ${GREEN}# List images in registry${NC}
  $0 ${CYAN}--list-images --service frontend${NC}

  ${GREEN}# Show all images and delete them (with confirmation)${NC}
  $0 ${CYAN}--delete-images --token ghp_xxx${NC}

  ${GREEN}# Disable parallel builds (force serial)${NC}
  $0 ${CYAN}--all --no-parallel --version 1.3.0 --push --token ghp_xxx${NC}

${BOLD}${BLUE}TOKEN SETUP:${NC}
  Create a token at: https://github.com/settings/tokens
  Required scopes: read:packages, write:packages, delete:packages

${BOLD}${BLUE}NOTES:${NC}
  - For deleting images, your token needs 'delete:packages' scope
  - Images older than 30 days or untagged images will be deleted
  - Use --dry-run to see what would happen without making changes
EOF
}

parse_args() {
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
                shift 2
                ;;
            --version)
                if [[ -z "${2:-}" ]]; then
                    log "ERROR" "--version requires a value"
                    exit 1
                fi
                VERSION="${2#v}"
                shift 2
                ;;
            --token)
                if [[ -z "${2:-}" ]]; then
                    log "ERROR" "--token requires a value"
                    exit 1
                fi
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
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --no-diff-check)
                CHECK_DIFF=false
                shift
                ;;
            --no-cache)
                USE_CACHE=false
                shift
                ;;
            --cache-from)
                if [[ -z "${2:-}" ]]; then
                    log "ERROR" "--cache-from requires a value"
                    exit 1
                fi
                CACHE_FROM="$2"
                shift 2
                ;;
            --cache-to)
                if [[ -z "${2:-}" ]]; then
                    log "ERROR" "--cache-to requires a value"
                    exit 1
                fi
                CACHE_TO="$2"
                shift 2
                ;;
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
                shift 2
                ;;
            --target)
                if [[ -z "${2:-}" ]]; then
                    log "ERROR" "--target requires a value"
                    exit 1
                fi
                TARGET_STAGE="$2"
                shift 2
                ;;
            --platform)
                if [[ -z "${2:-}" ]]; then
                    log "ERROR" "--platform requires a value"
                    exit 1
                fi
                PLATFORMS="$2"
                MULTI_PLATFORM=true
                shift 2
                ;;
            --no-parallel)
                PARALLEL_BUILDS=false
                shift
                ;;
            --parallel)
                PARALLEL_BUILDS=true
                shift
                ;;
            --timeout)
                if [[ -z "${2:-}" ]]; then
                    log "ERROR" "--timeout requires a value"
                    exit 1
                fi
                BUILD_TIMEOUT="$2"
                shift 2
                ;;
            --list-images)
                LIST_IMAGES=true
                shift
                ;;
            --delete-images)
                DELETE_IMAGES=true
                shift
                ;;
            --force-delete)
                FORCE_DELETE=true
                shift
                ;;
            --prune)
                PRUNE_AFTER_BUILD=true
                shift
                ;;
            --cleanup)
                CLEANUP_AFTER_BUILD=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --quiet)
                QUIET=true
                shift
                ;;
            --no-progress)
                BUILD_PROGRESS=false
                shift
                ;;
            --registry)
                if [[ -z "${2:-}" ]]; then
                    log "ERROR" "--registry requires a value"
                    exit 1
                fi
                REGISTRY_URL="$2"
                shift 2
                ;;
            --org)
                if [[ -z "${2:-}" ]]; then
                    log "ERROR" "--org requires a value"
                    exit 1
                fi
                GITHUB_ORG="$2"
                shift 2
                ;;
            --repo)
                if [[ -z "${2:-}" ]]; then
                    log "ERROR" "--repo requires a value"
                    exit 1
                fi
                REPO_NAME="$2"
                shift 2
                ;;
            --secrets)
                if [[ -z "${2:-}" ]]; then
                    log "ERROR" "--secrets requires a value"
                    exit 1
                fi
                SECRETS="$2"
                shift 2
                ;;
            --ssh)
                if [[ -z "${2:-}" ]]; then
                    log "ERROR" "--ssh requires a value"
                    exit 1
                fi
                SSH_KEYS="$2"
                shift 2
                ;;
            --test)
                TEST_MODE=true
                shift
                ;;
            --test-api)
                QUICK_TEST=true
                shift
                ;;
            --path)
                if [[ -z "${2:-}" ]]; then
                    log "ERROR" "--path requires a value"
                    exit 1
                fi
                PROJECT_PATH="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # For build operations, ensure either --service or --all is provided
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

    # If PROJECT_PATH was not set explicitly, default to ../milou_fresh relative to script
    if [[ -z "$PROJECT_PATH" ]]; then
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        PROJECT_PATH="$script_dir/../milou_fresh"
    fi
}

# =============================================================================
# CLEANUP AND ERROR HANDLING
# =============================================================================
cleanup() {
    if [[ "${CLEANUP_AFTER_BUILD}" == "true" ]]; then
        log "INFO" "🧹 Performing cleanup..."
        docker logout "$REGISTRY_URL" >/dev/null 2>&1 || true

        # Clear sensitive env var
        unset GITHUB_TOKEN

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
    # Skip when listing or deleting images
    if [[ "$LIST_IMAGES" == "true" || "$DELETE_IMAGES" == "true" ]]; then
        return 0
    fi

    if [[ ! -d "$PROJECT_PATH" ]]; then
        log "ERROR" "milou_fresh directory not found at: $PROJECT_PATH"
        return 1
    fi

    cd "$PROJECT_PATH" || return 1
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

### CHANGED: Execute build process with optional parallelism
execute_build_process() {
    local services_to_build=()

    if [[ "$BUILD_ALL" == "true" ]]; then
        services_to_build=("${AVAILABLE_SERVICES[@]}")
        log "INFO" "🔄 Building all services: ${services_to_build[*]}"
    else
        services_to_build=("$SERVICE")
        log "INFO" "🎯 Building service: $SERVICE"
    fi

    # If parallel builds is off, do a simple serial loop
    if [[ "$PARALLEL_BUILDS" != "true" ]]; then
        for service in "${services_to_build[@]}"; do
            if build_service "$service"; then
                successful_services+=("$service")
            else
                failed_services+=("$service")
            fi
        done
    else
        # Parallel mode with reliable result capture
        local RESULTS_FILE
        RESULTS_FILE=$(mktemp -t milou_build_results.XXXX)

        for service in "${services_to_build[@]}"; do
            # Respect MAX_PARALLEL_JOBS
            while (( $(jobs -r | wc -l) >= MAX_PARALLEL_JOBS )); do
                sleep 0.2
            done

            (
                if build_service "$service"; then
                    echo "SUCCESS::$service" >> "$RESULTS_FILE"
                else
                    echo "FAILED::$service" >> "$RESULTS_FILE"
                fi
            ) &
        done

        # Wait for all background jobs to finish
        wait

        # Parse results
        if [[ -f "$RESULTS_FILE" ]]; then
            while IFS= read -r line; do
                case "$line" in
                    SUCCESS::*)
                        successful_services+=("${line#SUCCESS::}")
                        ;;
                    FAILED::*)
                        failed_services+=("${line#FAILED::}")
                        ;;
                esac
            done < "$RESULTS_FILE"
            rm -f "$RESULTS_FILE"
        fi
    fi

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

    local total_services
    total_services=$((${#successful_services[@]} + ${#skipped_services[@]} + ${#failed_services[@]}))
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

    if [[ "$TEST_MODE" == "true" ]]; then
        run_comprehensive_tests
        exit $?
    fi

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
    log "INFO" "   Project path: $PROJECT_PATH"
    if [[ "$PARALLEL_BUILDS" == "true" ]]; then
        log "INFO" "   Parallel builds: ON (max $MAX_PARALLEL_JOBS)"
    else
        log "INFO" "   Parallel builds: OFF"
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

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
