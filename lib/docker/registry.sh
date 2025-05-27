#!/bin/bash

# =============================================================================
# Docker Registry Utilities for Milou CLI - Modular Edition
# Handles GitHub Container Registry authentication and image management
# =============================================================================

# Module guard to prevent multiple loading
if [[ "${MILOU_DOCKER_REGISTRY_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_DOCKER_REGISTRY_LOADED="true"

# Load modular registry components
source "${BASH_SOURCE%/*}/registry/auth.sh" 2>/dev/null || true
source "${BASH_SOURCE%/*}/registry/images.sh" 2>/dev/null || true
source "${BASH_SOURCE%/*}/registry/access.sh" 2>/dev/null || true

# Ensure logging is available
if ! command -v milou_log >/dev/null 2>&1; then
    source "${SCRIPT_DIR}/lib/core/logging.sh" 2>/dev/null || {
        echo "ERROR: Cannot load logging module" >&2
        exit 1
    }
fi

# Constants (use defaults if not already set)
GITHUB_REGISTRY="${GITHUB_REGISTRY:-ghcr.io/milou-sh/milou}"
GITHUB_API_BASE="${GITHUB_API_BASE:-https://api.github.com}"

# =============================================================================
# Main Registry Orchestration Functions
# =============================================================================

# Complete registry setup and validation
setup_docker_registry() {
    local token="$1"
    local validate_images="${2:-true}"
    shift 2
    local images=("$@")
    
    milou_log "STEP" "Setting up Docker registry access..."
    
    # Step 1: Verify Docker access
    if ! verify_docker_access; then
        milou_log "ERROR" "Docker access verification failed"
        return 1
    fi
    
    # Step 2: Test GitHub authentication
    if ! test_github_authentication "$token"; then
        milou_log "ERROR" "GitHub authentication failed"
        return 1
    fi
    
    # Step 3: Ensure Docker credentials
    if ! ensure_docker_credentials "$token"; then
        milou_log "ERROR" "Docker credential setup failed"
        return 1
    fi
    
    # Step 4: Validate images if requested
    if [[ "$validate_images" == "true" && ${#images[@]} -gt 0 ]]; then
        if ! validate_images_exist "$token" "${images[@]}"; then
            milou_log "ERROR" "Image validation failed"
            return 1
        fi
    fi
    
    milou_log "SUCCESS" "✅ Docker registry setup completed successfully"
    return 0
}

# Interactive registry setup with user guidance
setup_docker_registry_interactive() {
    local token="$1"
    
    milou_log "STEP" "Interactive Docker Registry Setup"
    echo
    
    # Get token if not provided
    if [[ -z "$token" ]]; then
        echo "GitHub Personal Access Token is required for Docker registry access."
        echo "The token needs the following scopes:"
        echo "  • read:packages"
        echo "  • write:packages (if you plan to push images)"
        echo
        echo -n "Enter your GitHub token: "
        read -rs token
        echo
        
        if [[ -z "$token" ]]; then
            milou_log "ERROR" "No token provided"
            return 1
        fi
    fi
    
    # Validate token format (using consolidated function)
    if ! milou_validate_github_token "$token"; then
        milou_log "ERROR" "Invalid GitHub token format"
        milou_log "INFO" "Expected format: ghp_[40_character_token]"
        return 1
    fi
    
    # Test authentication
    echo
    milou_log "INFO" "Testing GitHub authentication..."
    if ! test_github_authentication "$token"; then
        milou_log "ERROR" "Authentication test failed"
        return 1
    fi
    
    # Setup Docker credentials
    echo
    milou_log "INFO" "Setting up Docker registry credentials..."
    if ! ensure_docker_credentials "$token"; then
        milou_log "ERROR" "Docker credential setup failed"
        return 1
    fi
    
    # Ask about image validation
    echo
    echo -n "Would you like to validate available images? [Y/n]: "
    read -r validate_choice
    
    if [[ "$validate_choice" =~ ^[Nn]$ ]]; then
        milou_log "INFO" "Skipping image validation"
    else
        milou_log "INFO" "Checking available images..."
        
        # Get available images for common components
        local common_images=("frontend" "backend" "api" "worker")
        local available_images=()
        
        for image in "${common_images[@]}"; do
            if get_available_image_tags "$image" "$token" >/dev/null 2>&1; then
                available_images+=("$image")
            fi
        done
        
        if [[ ${#available_images[@]} -gt 0 ]]; then
            milou_log "SUCCESS" "Available images found:"
            for image in "${available_images[@]}"; do
                local latest_tag
                latest_tag=$(get_latest_image_tag "$image" "$token")
                milou_log "INFO" "  • $image:${latest_tag:-latest}"
            done
        else
            milou_log "INFO" "No common images found in registry"
        fi
    fi
    
    echo
    milou_log "SUCCESS" "🎉 Docker registry setup completed successfully!"
    milou_log "INFO" "You can now pull images from: $GITHUB_REGISTRY"
    
    return 0
}

# Comprehensive registry health check
check_registry_health() {
    local token="$1"
    local detailed="${2:-false}"
    
    milou_log "STEP" "Checking Docker registry health..."
    
    local issues=()
    local warnings=()
    
    # Check Docker access
    if ! verify_docker_access >/dev/null 2>&1; then
        issues+=("Docker access verification failed")
    fi
    
    # Check GitHub authentication
    if [[ -n "$token" ]]; then
        if ! test_github_authentication "$token" >/dev/null 2>&1; then
            issues+=("GitHub authentication failed")
        fi
    else
        warnings+=("No GitHub token provided for authentication test")
    fi
    
    # Check registry connectivity
    if ! test_registry_connectivity "ghcr.io" >/dev/null 2>&1; then
        issues+=("GitHub Container Registry connectivity failed")
    fi
    
    # Check Docker credentials
    if [[ -n "$token" ]]; then
        if ! ensure_docker_credentials "$token" >/dev/null 2>&1; then
            issues+=("Docker credential setup failed")
        fi
    fi
    
    # Report results
    echo
    milou_log "INFO" "🏥 Registry Health Check Results:"
    
    if [[ ${#issues[@]} -eq 0 ]]; then
        milou_log "SUCCESS" "✅ All checks passed - registry is healthy"
    else
        milou_log "ERROR" "❌ Issues found:"
        for issue in "${issues[@]}"; do
            milou_log "ERROR" "  • $issue"
        done
    fi
    
    if [[ ${#warnings[@]} -gt 0 ]]; then
        milou_log "WARN" "⚠️  Warnings:"
        for warning in "${warnings[@]}"; do
            milou_log "WARN" "  • $warning"
        done
    fi
    
    # Detailed diagnostics if requested
    if [[ "$detailed" == "true" ]]; then
        echo
        debug_docker_images
        check_docker_resources
    fi
    
    # Return appropriate exit code
    if [[ ${#issues[@]} -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Batch image operations
batch_image_operations() {
    local operation="$1"
    local token="$2"
    shift 2
    local images=("$@")
    
    case "$operation" in
        "validate")
            validate_images_exist "$token" "${images[@]}"
            ;;
        "pull")
            pull_images "$token" "${images[@]}"
            ;;
        "check")
            milou_log "STEP" "Checking images..."
            local failed=0
            for image_spec in "${images[@]}"; do
                local image_name tag
                if [[ "$image_spec" == *":"* ]]; then
                    image_name="${image_spec%:*}"
                    tag="${image_spec#*:}"
                else
                    image_name="$image_spec"
                    tag=$(get_latest_image_tag "$image_name" "$token")
                fi
                
                if enhanced_image_check "$image_name" "$tag" "$token"; then
                    milou_log "SUCCESS" "✅ $image_name:$tag"
                else
                    milou_log "ERROR" "❌ $image_name:$tag"
                    ((failed++))
                fi
            done
            
            if [[ $failed -eq 0 ]]; then
                milou_log "SUCCESS" "All image checks passed"
                return 0
            else
                milou_log "ERROR" "$failed image(s) failed checks"
                return 1
            fi
            ;;
        "list")
            milou_log "STEP" "Listing available tags for images..."
            for image in "${images[@]}"; do
                milou_log "INFO" "📦 Available tags for $image:"
                local tags
                tags=$(get_available_image_tags "$image" "$token")
                if [[ -n "$tags" ]]; then
                    echo "$tags" | head -10 | while read -r tag; do
                        milou_log "INFO" "  • $tag"
                    done
                    if [[ $(echo "$tags" | wc -l) -gt 10 ]]; then
                        milou_log "INFO" "  ... and $(($(echo "$tags" | wc -l) - 10)) more"
                    fi
                else
                    milou_log "INFO" "  No tags found"
                fi
                echo
            done
            ;;
        *)
            milou_log "ERROR" "Unknown operation: $operation"
            milou_log "INFO" "Available operations: validate, pull, check, list"
            return 1
            ;;
    esac
}

# =============================================================================
# Registry Module Complete
# =============================================================================
# All registry functions are now available through the loaded sub-modules:
# - registry/auth.sh - GitHub authentication and token validation
# - registry/images.sh - Image discovery, validation, and pulling
# - registry/access.sh - Docker access verification and credential management
# =============================================================================

milou_log "DEBUG" "Docker registry utilities module loaded successfully" 