#!/bin/bash

# =============================================================================
# Development Module for Milou CLI
# Handles local development with custom Docker images
# =============================================================================

# Module guard to prevent multiple loading
if [[ "${MILOU_DEVELOPMENT_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_DEVELOPMENT_LOADED="true"

# Ensure logging is available
if ! command -v milou_log >/dev/null 2>&1; then
    source "${SCRIPT_DIR}/lib/core/logging.sh" 2>/dev/null || {
        echo "ERROR: Cannot load logging module" >&2
        exit 1
    }
fi

# =============================================================================
# Development Mode Functions
# =============================================================================

# Enable development mode
milou_enable_dev_mode() {
    local compose_dir="${SCRIPT_DIR}/static"
    local override_source="${SCRIPT_DIR}/docker-compose.local.yml"
    local override_target="${compose_dir}/docker-compose.local.yml"
    
    milou_log "STEP" "Enabling development mode..."
    
    # Check if source override file exists
    if [[ ! -f "$override_source" ]]; then
        milou_log "ERROR" "Development override file not found: $override_source"
        return 1
    fi
    
    # Create target directory if needed
    if [[ ! -d "$compose_dir" ]]; then
        milou_log "ERROR" "Static directory not found: $compose_dir"
        return 1
    fi
    
    # Copy override file to static directory
    if cp "$override_source" "$override_target"; then
        milou_log "SUCCESS" "✅ Development mode enabled"
        milou_log "INFO" "Using local Docker images instead of registry images"
        milou_log "INFO" "Override file: $override_target"
        return 0
    else
        milou_log "ERROR" "Failed to copy development override file"
        return 1
    fi
}

# Disable development mode
milou_disable_dev_mode() {
    local compose_dir="${SCRIPT_DIR}/static"
    local override_target="${compose_dir}/docker-compose.local.yml"
    
    milou_log "STEP" "Disabling development mode..."
    
    if [[ -f "$override_target" ]]; then
        if rm -f "$override_target"; then
            milou_log "SUCCESS" "✅ Development mode disabled"
            milou_log "INFO" "Will use registry images from docker-compose.yml"
            return 0
        else
            milou_log "ERROR" "Failed to remove development override file"
            return 1
        fi
    else
        milou_log "INFO" "Development mode was not enabled"
        return 0
    fi
}

# Check if development mode is enabled
milou_is_dev_mode_enabled() {
    local compose_dir="${SCRIPT_DIR}/static"
    local override_target="${compose_dir}/docker-compose.local.yml"
    
    [[ -f "$override_target" ]]
}

# Show development mode status
milou_show_dev_mode_status() {
    local compose_dir="${SCRIPT_DIR}/static"
    local override_target="${compose_dir}/docker-compose.local.yml"
    
    if milou_is_dev_mode_enabled; then
        milou_log "INFO" "🚀 Development mode: ENABLED"
        milou_log "INFO" "   Using local Docker images"
        milou_log "INFO" "   Override file: $override_target"
        
        # Show which images are being used locally
        if command -v docker >/dev/null 2>&1; then
            milou_log "INFO" "   Local images available:"
            docker images | grep "ghcr.io/milou-sh/milou" | grep latest | while read -r line; do
                milou_log "INFO" "     📦 $line"
            done
        fi
    else
        milou_log "INFO" "📦 Development mode: DISABLED"
        milou_log "INFO" "   Using registry images from docker-compose.yml"
    fi
}

# Build local images for development
milou_build_dev_images() {
    milou_log "STEP" "Building local development images..."
    
    local build_script="${SCRIPT_DIR}/build-local-images.sh"
    
    if [[ ! -f "$build_script" ]]; then
        milou_log "ERROR" "Build script not found: $build_script"
        milou_log "INFO" "Please ensure build-local-images.sh exists in the milou-cli directory"
        return 1
    fi
    
    if [[ ! -x "$build_script" ]]; then
        milou_log "DEBUG" "Making build script executable"
        chmod +x "$build_script"
    fi
    
    milou_log "INFO" "Running build script: $build_script"
    if "$build_script"; then
        milou_log "SUCCESS" "✅ Development images built successfully"
        return 0
    else
        milou_log "ERROR" "❌ Failed to build development images"
        return 1
    fi
}

# Auto-setup development mode
milou_auto_setup_dev_mode() {
    if [[ "${DEV_MODE:-false}" == "true" ]]; then
        milou_log "INFO" "Development mode requested via --dev flag"
        
        # Check if local images exist
        local has_local_images=false
        if command -v docker >/dev/null 2>&1; then
            local image_count
            image_count=$(docker images | grep "ghcr.io/milou-sh/milou" | grep latest | wc -l)
            if [[ $image_count -gt 0 ]]; then
                has_local_images=true
                milou_log "INFO" "Found $image_count local Milou images"
            fi
        fi
        
        # Build images if they don't exist
        if [[ "$has_local_images" == "false" ]]; then
            milou_log "WARN" "No local Milou images found"
            if [[ "${INTERACTIVE:-true}" == "true" ]]; then
                echo -n "Would you like to build local images now? [y/N]: "
                read -r response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    if ! milou_build_dev_images; then
                        milou_log "ERROR" "Failed to build development images"
                        return 1
                    fi
                else
                    milou_log "WARN" "Continuing without building images (may cause errors)"
                fi
            else
                milou_log "INFO" "Non-interactive mode: attempting to build images automatically"
                if ! milou_build_dev_images; then
                    milou_log "ERROR" "Failed to build development images in non-interactive mode"
                    return 1
                fi
            fi
        fi
        
        # Enable development mode
        if ! milou_enable_dev_mode; then
            milou_log "ERROR" "Failed to enable development mode"
            return 1
        fi
        
        milou_show_dev_mode_status
    fi
    
    return 0
}

milou_log "DEBUG" "Development module loaded successfully" 