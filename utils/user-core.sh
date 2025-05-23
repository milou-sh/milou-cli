#!/bin/bash

# =============================================================================
# Core User Operations for Milou CLI
# Handles basic user detection, creation, and fundamental operations
# =============================================================================

# Source utility functions
source "${BASH_SOURCE%/*}/utils.sh" 2>/dev/null || true

# Constants
readonly MILOU_USER="milou"
readonly MILOU_GROUP="milou"
readonly MILOU_HOME="/home/$MILOU_USER"
readonly MILOU_UID="${MILOU_UID:-1001}"
readonly MILOU_GID="${MILOU_GID:-1001}"

# =============================================================================
# Basic User Detection
# =============================================================================

# Check if we're running as root
is_running_as_root() {
    [[ $EUID -eq 0 ]]
}

# Check if the milou user exists
milou_user_exists() {
    id "$MILOU_USER" >/dev/null 2>&1
}

# Get current user information
get_current_user_info() {
    local current_user
    current_user=$(whoami)
    local current_uid
    current_uid=$(id -u)
    local current_gid
    current_gid=$(id -g)
    local current_groups
    current_groups=$(groups "$current_user" 2>/dev/null | cut -d: -f2)
    
    echo "Current user: $current_user (UID: $current_uid, GID: $current_gid)"
    echo "Groups: $current_groups"
}

# =============================================================================
# User Creation
# =============================================================================

# Create milou user with proper configuration
create_milou_user() {
    log "STEP" "Creating milou user for secure operations..."
    
    if ! is_running_as_root; then
        error_exit "Root privileges required to create user. Please run with sudo."
    fi
    
    if milou_user_exists; then
        log "INFO" "User $MILOU_USER already exists"
        return 0
    fi
    
    # Create group first
    if ! getent group "$MILOU_GROUP" >/dev/null 2>&1; then
        log "DEBUG" "Creating group: $MILOU_GROUP (GID: $MILOU_GID)"
        if ! groupadd -g "$MILOU_GID" "$MILOU_GROUP" 2>/dev/null; then
            # If GID is taken, let system assign one
            log "DEBUG" "GID $MILOU_GID taken, letting system assign one"
            if ! groupadd "$MILOU_GROUP"; then
                error_exit "Failed to create group $MILOU_GROUP"
            fi
        fi
    fi
    
    # Ensure docker group exists BEFORE creating user
    if ! getent group docker >/dev/null 2>&1; then
        log "DEBUG" "Creating docker group"
        if ! groupadd docker; then
            log "WARN" "Failed to create docker group, user will be created without docker access"
            # Continue without docker group - we'll try to add it later
        fi
    fi
    
    # Create user with home directory
    log "DEBUG" "Creating user: $MILOU_USER (UID: $MILOU_UID)"
    local useradd_cmd=(
        useradd
        -m                    # Create home directory
        -s /bin/bash         # Set shell
        -g "$MILOU_GROUP"    # Primary group
        -c "Milou Service User"  # Comment
    )
    
    # Add docker group to user creation if it exists
    if getent group docker >/dev/null 2>&1; then
        useradd_cmd+=(-G docker)
        log "DEBUG" "Adding user to docker group during creation"
    fi
    
    # Try with specific UID first
    if ! "${useradd_cmd[@]}" -u "$MILOU_UID" "$MILOU_USER" 2>/dev/null; then
        # If UID is taken, let system assign one
        log "DEBUG" "UID $MILOU_UID taken, letting system assign one"
        if ! "${useradd_cmd[@]}" "$MILOU_USER"; then
            error_exit "Failed to create user $MILOU_USER"
        fi
    fi
    
    # Add user to docker group if not already done and group exists
    if getent group docker >/dev/null 2>&1; then
        if ! groups "$MILOU_USER" 2>/dev/null | grep -q docker; then
            log "DEBUG" "Adding $MILOU_USER to docker group"
            if ! usermod -aG docker "$MILOU_USER"; then
                log "WARN" "Failed to add $MILOU_USER to docker group"
            fi
        fi
    else
        log "WARN" "Docker group does not exist, user created without docker access"
        log "INFO" "💡 Install Docker first, then run: sudo usermod -aG docker $MILOU_USER"
    fi
    
    # Set up user environment
    source "${BASH_SOURCE%/*}/user-environment.sh"
    setup_milou_user_environment
    
    log "SUCCESS" "User $MILOU_USER created successfully"
    log "INFO" "Home directory: $MILOU_HOME"
    log "INFO" "UID: $(id -u "$MILOU_USER"), GID: $(id -g "$MILOU_USER")"
    
    # Verify Docker access for the new user
    log "DEBUG" "Verifying Docker access for newly created user..."
    if command -v docker >/dev/null 2>&1; then
        # Quick verification that the user can access Docker
        # Use a more reliable method than newgrp which can hang
        if sudo -u "$MILOU_USER" -g docker docker info >/dev/null 2>&1; then
            log "SUCCESS" "✅ Docker access verified for $MILOU_USER user"
        else
            log "WARN" "⚠️  Docker access verification failed for $MILOU_USER user"
            log "INFO" "💡 This may resolve after the first login or with proper group activation"
            
            # Run a quick diagnostic in debug mode
            if [[ "${VERBOSE:-false}" == "true" ]]; then
                source "${BASH_SOURCE%/*}/user-docker.sh"
                diagnose_docker_access "$MILOU_USER" >/dev/null 2>&1 || true
            fi
        fi
    else
        log "WARN" "Docker not available for verification"
    fi
}

# =============================================================================
# User Information Utilities
# =============================================================================

# Get milou user home directory
get_milou_home() {
    if milou_user_exists; then
        getent passwd "$MILOU_USER" | cut -d: -f6
    else
        echo "/home/$MILOU_USER"
    fi
}

# Check if milou user has a properly configured home directory
validate_milou_home() {
    local milou_home
    milou_home=$(get_milou_home)
    
    if [[ -z "$milou_home" ]]; then
        log "ERROR" "Could not determine milou user home directory"
        return 1
    fi
    
    if [[ ! -d "$milou_home" ]]; then
        log "WARN" "Milou user home directory does not exist: $milou_home"
        return 1
    fi
    
    if [[ ! -w "$milou_home" ]] && [[ "$(whoami)" == "$MILOU_USER" ]]; then
        log "WARN" "Milou user cannot write to home directory: $milou_home"
        return 1
    fi
    
    return 0
}

# Export functions for use in other scripts
export -f is_running_as_root
export -f milou_user_exists
export -f get_current_user_info
export -f create_milou_user
export -f get_milou_home
export -f validate_milou_home 