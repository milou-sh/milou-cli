#!/bin/bash

set -euo pipefail

# =============================================================================
# Build Local Milou Images Script
# Builds all Milou Docker images locally for testing with smart rebuild logic
# Location: scripts/dev/build-local-images.sh
# =============================================================================

# Global flags
declare -g FORCE_BUILD=false
declare -g VERBOSE=false

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Enhanced log function that uses milou_log if available
# Enhanced log function that uses milou_log if available
log() {
    if command -v milou_log >/dev/null 2>&1; then
        milou_log "$@"
    else
        # Fallback for standalone script execution
        local level="$1"
        shift
        local message="$*"
        case "$level" in
            "ERROR") echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
            "WARN") echo -e "${YELLOW}[WARN]${NC} $message" >&2 ;;
            "INFO") echo -e "${GREEN}[INFO]${NC} $message" ;;
            "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
            "DEBUG") [[ "${VERBOSE:-false}" == "true" ]] && echo -e "${BLUE}[DEBUG]${NC} $message" ;;
            *) echo "[INFO] $message" ;;
        esac
    fi
}

# Show help
show_help() {
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo
    echo "Build Milou Docker images locally for development"
    echo
    echo "OPTIONS:"
    echo "  --force    Force rebuild all images even if they exist and are recent"
    echo "  --verbose  Enable verbose output"
    echo "  --help     Show this help message"
    echo
    echo "The script will automatically skip building images that:"
    echo "  - Already exist with the 'latest' tag"
    echo "  - Were built less than 1 hour ago"
    echo "  - Have source files that haven't changed since the image was built"
    echo
    echo "Use --force to rebuild everything regardless of timestamps."
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                FORCE_BUILD=true
                shift
                ;;
            --verbose)
                VERBOSE=true
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
}

# Check if we're in the right directory structure
check_directory_structure() {
    # Get project root (two levels up from scripts/dev/)
    local project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    
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

# Check if image exists and is recent
image_needs_rebuild() {
    local image_name="$1"
    local context_path="$2"
    local dockerfile_path="$3"
    
    # If force build is enabled, always rebuild
    if [[ "$FORCE_BUILD" == "true" ]]; then
    milou_log "DEBUG" "Force build enabled, rebuilding $image_name"
        return 0  # needs rebuild
    fi
    
    # Check if image exists
    if ! docker image inspect "$image_name" >/dev/null 2>&1; then
    milou_log "DEBUG" "Image $image_name doesn't exist, needs build"
        return 0  # needs rebuild
    fi
    
    # Get image creation time (in seconds since epoch)
    local image_created
    image_created=$(docker image inspect "$image_name" --format '{{.Created}}' 2>/dev/null)
    if [[ -z "$image_created" ]]; then
    milou_log "DEBUG" "Cannot get image creation time for $image_name, rebuilding"
        return 0  # needs rebuild
    fi
    
    # Convert to timestamp
    local image_timestamp
    image_timestamp=$(date -d "$image_created" +%s 2>/dev/null || echo "0")
    
    # If image is older than 1 hour, suggest rebuild
    local one_hour_ago
    one_hour_ago=$(date -d "1 hour ago" +%s)
    if [[ $image_timestamp -lt $one_hour_ago ]]; then
    milou_log "DEBUG" "Image $image_name is older than 1 hour, needs rebuild"
        return 0  # needs rebuild
    fi
    
    # Check if source files are newer than the image
    local newest_source_file
    if [[ -d "$context_path" ]]; then
        # Find the newest file in the context directory
        newest_source_file=$(find "$context_path" -type f -newer <(date -d "$image_created" '+%Y-%m-%d %H:%M:%S') 2>/dev/null | head -1)
        if [[ -n "$newest_source_file" ]]; then
    milou_log "DEBUG" "Source files newer than image $image_name found: $newest_source_file"
            return 0  # needs rebuild
        fi
    fi
    
    # Check if dockerfile is newer than the image
    if [[ -f "$dockerfile_path" ]]; then
        local dockerfile_timestamp
        dockerfile_timestamp=$(date -r "$dockerfile_path" +%s 2>/dev/null || echo "0")
        if [[ $dockerfile_timestamp -gt $image_timestamp ]]; then
    milou_log "DEBUG" "Dockerfile $dockerfile_path is newer than image $image_name"
            return 0  # needs rebuild
        fi
    fi
    
    milou_log "DEBUG" "Image $image_name is up to date, skipping build"
    return 1  # doesn't need rebuild
}

# Build image with error handling and smart rebuild logic
build_image() {
    local image_name="$1"
    local dockerfile="$2"
    local context="$3"
    
    # Check if we need to rebuild this image
    if ! image_needs_rebuild "$image_name" "$context" "$dockerfile"; then
    milou_log "INFO" "⏭️  Skipping $image_name (up to date)"
        return 0
    fi
    
    milou_log "INFO" "🔨 Building $image_name..."
    milou_log "DEBUG" "Dockerfile: $dockerfile, Context: $context"
    
    if docker build -t "$image_name" -f "$dockerfile" "$context"; then
    milou_log "INFO" "✅ Successfully built $image_name"
        return 0
    else
    milou_log "ERROR" "❌ Failed to build $image_name"
        return 1
    fi
}

main() {
    # Parse command line arguments first
    parse_args "$@"
    
    # Show build mode
    if [[ "$FORCE_BUILD" == "true" ]]; then
    milou_log "INFO" "🚀 Force building all Milou Docker images"
    else
    milou_log "INFO" "🚀 Smart building Milou Docker images (skipping up-to-date images)"
    fi
    
    # Check directory structure and change to build directory
    check_directory_structure
    
    local failed_builds=()
    local skipped_builds=()
    local successful_builds=()
    
    # Define all images to build
    local -a images=(
        "database|ghcr.io/milou-sh/milou/database:latest|./docker/database/Dockerfile|./docker/database"
        "backend|ghcr.io/milou-sh/milou/backend:latest|./dashboard/backend/Dockerfile.backend|./dashboard"
        "frontend|ghcr.io/milou-sh/milou/frontend:latest|./dashboard/frontend/Dockerfile.frontend|./dashboard"
        "engine|ghcr.io/milou-sh/milou/engine:latest|./engine/Dockerfile|./engine"
        "nginx|ghcr.io/milou-sh/milou/nginx:latest|./docker/nginx/Dockerfile|./docker/nginx"
    )
    
    # Build each image
    for image_spec in "${images[@]}"; do
        # Parse image specification: service|image|dockerfile|context
        local service_name image_name dockerfile context
        service_name=$(echo "$image_spec" | cut -d'|' -f1)
        image_name=$(echo "$image_spec" | cut -d'|' -f2)
        dockerfile=$(echo "$image_spec" | cut -d'|' -f3)
        context=$(echo "$image_spec" | cut -d'|' -f4)
        
    milou_log "INFO" "📦 Processing $service_name image..."
        
        # Track whether the build was actually attempted
        local build_attempted=false
        local build_result
        
        # Check if we need to rebuild this image first
        if ! image_needs_rebuild "$image_name" "$context" "$dockerfile"; then
            skipped_builds+=("$service_name")
        else
            build_attempted=true
            if build_image "$image_name" "$dockerfile" "$context"; then
                successful_builds+=("$service_name")
            else
                failed_builds+=("$service_name")
            fi
        fi
    done
    
    echo
    
    # Summary
    milou_log "INFO" "📊 Build Summary:"
    if [[ ${#successful_builds[@]} -gt 0 ]]; then
    milou_log "INFO" "   ✅ Built: ${successful_builds[*]}"
    fi
    if [[ ${#skipped_builds[@]} -gt 0 ]]; then
    milou_log "INFO" "   ⏭️  Skipped: ${skipped_builds[*]} (up to date)"
    fi
    if [[ ${#failed_builds[@]} -gt 0 ]]; then
    milou_log "ERROR" "   ❌ Failed: ${failed_builds[*]}"
    fi
    
    if [[ ${#failed_builds[@]} -eq 0 ]]; then
    milou_log "INFO" "🎉 Image processing completed successfully!"
        if [[ ${#successful_builds[@]} -gt 0 ]]; then
    milou_log "INFO" "You can now run: ../../milou.sh setup --dev --fresh-install"
        else
    milou_log "INFO" "All images were up to date. Use --force to rebuild anyway."
        fi
    else
    milou_log "ERROR" "❌ Some images failed to build: ${failed_builds[*]}"
    milou_log "ERROR" "Please check the error messages above and fix any issues"
        exit 1
    fi
    
    # Show all available images
    echo
    milou_log "INFO" "📋 Available Milou images:"
    docker images | grep "ghcr.io/milou-sh/milou" | grep latest
}

main "$@"