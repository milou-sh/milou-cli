#!/bin/bash

# =============================================================================
# Docker Permissions Management for Milou CLI
# Handles Docker access validation, group management, and diagnostics
# =============================================================================

# Source utility functions
source "${BASH_SOURCE%/*}/utils.sh" 2>/dev/null || true
source "${BASH_SOURCE%/*}/user-core.sh" 2>/dev/null || true

# =============================================================================
# Docker Access Detection
# =============================================================================

# Check if current user is milou or has docker permissions
has_docker_permissions() {
    local current_user
    current_user=$(whoami)
    
    # Check if user is in docker group
    if groups "$current_user" 2>/dev/null | grep -q docker; then
        return 0
    fi
    
    # Check if user can run docker commands
    if docker info >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

# =============================================================================
# Docker Group Management
# =============================================================================

# Fix Docker permissions for milou user
fix_docker_permissions() {
    log "DEBUG" "Ensuring proper Docker permissions for $MILOU_USER..."
    
    # Ensure docker group exists
    if ! getent group docker >/dev/null 2>&1; then
        log "INFO" "Creating docker group..."
        if ! groupadd docker; then
            log "ERROR" "Failed to create docker group"
            return 1
        fi
    fi
    
    # Add milou user to docker group if not already
    if ! groups "$MILOU_USER" 2>/dev/null | grep -q docker; then
        log "DEBUG" "Adding $MILOU_USER to docker group..."
        if usermod -aG docker "$MILOU_USER"; then
            log "SUCCESS" "User $MILOU_USER added to docker group"
        else
            log "ERROR" "Failed to add $MILOU_USER to docker group"
            return 1
        fi
    else
        log "DEBUG" "User $MILOU_USER is already in docker group"
    fi
    
    # Fix permissions on Docker socket if needed and it exists
    if [[ -S /var/run/docker.sock ]]; then
        local socket_group socket_perms
        socket_group=$(stat -c %G /var/run/docker.sock 2>/dev/null || echo "root")
        socket_perms=$(stat -c %a /var/run/docker.sock 2>/dev/null || echo "000")
        
        log "DEBUG" "Docker socket permissions: $socket_perms, group: $socket_group"
        
        if [[ "$socket_group" != "docker" ]]; then
            log "DEBUG" "Fixing Docker socket group ownership..."
            if chgrp docker /var/run/docker.sock 2>/dev/null; then
                log "SUCCESS" "Docker socket group fixed"
            else
                log "WARN" "Could not change Docker socket group (may require root)"
            fi
        fi
        
        # Ensure socket is group writable
        if [[ ! "$socket_perms" =~ ^[0-9]*[2367][0-9]*$ ]]; then  # Check if group has write permission
            log "DEBUG" "Fixing Docker socket permissions..."
            if chmod g+w /var/run/docker.sock 2>/dev/null; then
                log "SUCCESS" "Docker socket permissions fixed"
            else
                log "WARN" "Could not fix Docker socket permissions (may require root)"
            fi
        fi
    else
        log "WARN" "Docker socket not found at /var/run/docker.sock"
    fi
    
    # Test Docker access for milou user
    if sudo -u "$MILOU_USER" docker info >/dev/null 2>&1; then
        log "SUCCESS" "Docker access verified for $MILOU_USER user"
        return 0
    else
        log "WARN" "Docker access test failed for $MILOU_USER user"
        log "INFO" "💡 This might be resolved by logging out and back in, or running: newgrp docker"
        return 1
    fi
}

# Ensure Docker credentials are copied to milou user
copy_docker_credentials_to_milou() {
    local milou_home
    milou_home=$(get_milou_home)
    
    if [[ -z "$milou_home" || ! -d "$milou_home" ]]; then
        log "WARN" "Cannot copy Docker credentials: milou home directory not found"
        return 1
    fi
    
    log "DEBUG" "Ensuring Docker credentials are available to milou user..."
    local root_docker_config="/root/.docker/config.json"
    local current_user_docker_config="$HOME/.docker/config.json"
    local milou_docker_dir="$milou_home/.docker"
    local milou_docker_config="$milou_docker_dir/config.json"
    
    # Create the docker directory for milou user
    mkdir -p "$milou_docker_dir"
    chown "$MILOU_USER:$MILOU_GROUP" "$milou_docker_dir"
    chmod 700 "$milou_docker_dir"
    
    # Try to copy from current user first, then root
    local source_config=""
    if [[ -f "$current_user_docker_config" ]]; then
        source_config="$current_user_docker_config"
        log "DEBUG" "Found Docker config for current user: $current_user_docker_config"
    elif [[ -f "$root_docker_config" ]]; then
        source_config="$root_docker_config"
        log "DEBUG" "Found Docker config for root user: $root_docker_config"
    fi
    
    if [[ -n "$source_config" ]]; then
        if cp "$source_config" "$milou_docker_config" 2>/dev/null; then
            chown "$MILOU_USER:$MILOU_GROUP" "$milou_docker_config"
            chmod 600 "$milou_docker_config"
            log "SUCCESS" "Docker credentials copied to milou user"
            
            # Verify the config contains GitHub container registry auth
            if grep -q "ghcr.io" "$milou_docker_config" 2>/dev/null; then
                log "DEBUG" "GitHub Container Registry credentials found in Docker config"
            else
                log "WARN" "No GitHub Container Registry credentials found in Docker config"
            fi
            
            return 0
        else
            log "WARN" "Failed to copy Docker credentials file"
        fi
    else
        log "DEBUG" "No Docker credentials found to copy"
    fi
    
    # If we have a GitHub token, try to authenticate directly
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        log "DEBUG" "Attempting Docker login with GitHub token for milou user..."
        if sudo -u "$MILOU_USER" bash -c "echo '$GITHUB_TOKEN' | docker login ghcr.io -u \$(echo '$GITHUB_TOKEN' | base64 -d 2>/dev/null | jq -r '.actor // \"token\"' 2>/dev/null || echo 'token') --password-stdin" >/dev/null 2>&1; then
            log "SUCCESS" "Docker login successful for milou user with GitHub token"
            return 0
        else
            log "WARN" "Docker login failed for milou user with GitHub token"
        fi
    fi
    
    return 1
}

# =============================================================================
# Docker Access Diagnostics
# =============================================================================

# Comprehensive Docker access diagnostic
diagnose_docker_access() {
    local target_user="${1:-$(whoami)}"
    
    log "STEP" "Diagnosing Docker access for user: $target_user"
    echo
    
    local issues=0
    local warnings=0
    
    # Check if user exists
    if ! id "$target_user" >/dev/null 2>&1; then
        log "ERROR" "User '$target_user' does not exist"
        return 1
    fi
    
    # Check Docker installation
    log "INFO" "1. Docker Installation:"
    if command -v docker >/dev/null 2>&1; then
        local docker_version
        docker_version=$(docker --version 2>/dev/null | head -1 || echo "unknown")
        log "SUCCESS" "  ✅ Docker installed: $docker_version"
    else
        log "ERROR" "  ❌ Docker not installed"
        ((issues++))
    fi
    echo
    
    # Check Docker service
    log "INFO" "2. Docker Service Status:"
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active docker >/dev/null 2>&1; then
            log "SUCCESS" "  ✅ Docker service is active"
            if systemctl is-enabled docker >/dev/null 2>&1; then
                log "SUCCESS" "  ✅ Docker service is enabled (auto-start)"
            else
                log "WARN" "  ⚠️  Docker service not enabled for auto-start"
                ((warnings++))
            fi
        else
            log "ERROR" "  ❌ Docker service is not running"
            log "INFO" "     💡 Try: sudo systemctl start docker"
            ((issues++))
        fi
    else
        log "WARN" "  ⚠️  Cannot check service status (systemctl not available)"
        ((warnings++))
    fi
    echo
    
    # Check Docker group and user membership
    log "INFO" "3. Docker Group and User Membership:"
    if getent group docker >/dev/null 2>&1; then
        log "SUCCESS" "  ✅ Docker group exists"
        
        # Check if target user is in docker group
        if groups "$target_user" 2>/dev/null | grep -q docker; then
            log "SUCCESS" "  ✅ User '$target_user' is in docker group"
            
            # Check if group membership is active in current session
            if [[ "$target_user" == "$(whoami)" ]]; then
                if groups | grep -q docker; then
                    log "SUCCESS" "  ✅ Docker group membership is active in current session"
                else
                    log "WARN" "  ⚠️  Docker group membership not active in current session"
                    log "INFO" "     💡 Try: newgrp docker"
                    ((warnings++))
                fi
            fi
        else
            log "ERROR" "  ❌ User '$target_user' is not in docker group"
            log "INFO" "     💡 Try: sudo usermod -aG docker $target_user"
            ((issues++))
        fi
    else
        log "ERROR" "  ❌ Docker group does not exist"
        log "INFO" "     💡 Try: sudo groupadd docker"
        ((issues++))
    fi
    echo
    
    # Check Docker socket
    log "INFO" "4. Docker Socket:"
    if [[ -S /var/run/docker.sock ]]; then
        local socket_perms socket_owner socket_group
        socket_perms=$(stat -c %a /var/run/docker.sock 2>/dev/null || echo "unknown")
        socket_owner=$(stat -c %U /var/run/docker.sock 2>/dev/null || echo "unknown")
        socket_group=$(stat -c %G /var/run/docker.sock 2>/dev/null || echo "unknown")
        
        log "SUCCESS" "  ✅ Docker socket exists: /var/run/docker.sock"
        log "INFO" "     Permissions: $socket_perms"
        log "INFO" "     Owner: $socket_owner"
        log "INFO" "     Group: $socket_group"
        
        if [[ "$socket_group" == "docker" ]]; then
            log "SUCCESS" "  ✅ Socket group is correct (docker)"
        else
            log "ERROR" "  ❌ Socket group should be 'docker', but is '$socket_group'"
            log "INFO" "     💡 Try: sudo chgrp docker /var/run/docker.sock"
            ((issues++))
        fi
        
        # Check if socket is group writable
        if [[ "$socket_perms" =~ ^[0-9]*[2367][0-9]*$ ]]; then
            log "SUCCESS" "  ✅ Socket is group writable"
        else
            log "WARN" "  ⚠️  Socket may not be group writable"
            log "INFO" "     💡 Try: sudo chmod g+w /var/run/docker.sock"
            ((warnings++))
        fi
    else
        log "ERROR" "  ❌ Docker socket not found at /var/run/docker.sock"
        ((issues++))
    fi
    echo
    
    # Test Docker access
    log "INFO" "5. Docker Access Test:"
    if [[ "$target_user" == "$(whoami)" ]]; then
        # Test directly
        if docker info >/dev/null 2>&1; then
            log "SUCCESS" "  ✅ Docker access test passed for current user"
        else
            log "ERROR" "  ❌ Docker access test failed for current user"
            ((issues++))
        fi
    else
        # Test via sudo
        if sudo -u "$target_user" docker info >/dev/null 2>&1; then
            log "SUCCESS" "  ✅ Docker access test passed for user '$target_user'"
        else
            log "ERROR" "  ❌ Docker access test failed for user '$target_user'"
            ((issues++))
            
            # Try with newgrp
            if sudo -u "$target_user" bash -c "newgrp docker -c 'docker info'" >/dev/null 2>&1; then
                log "SUCCESS" "  ✅ Docker access works with 'newgrp docker' for user '$target_user'"
                log "INFO" "     💡 Group membership activation needed"
            else
                log "ERROR" "  ❌ Docker access still fails even with 'newgrp docker'"
            fi
        fi
    fi
    echo
    
    # Summary
    log "INFO" "Diagnosis Summary:"
    log "INFO" "  Critical Issues: $issues"
    log "INFO" "  Warnings: $warnings"
    echo
    
    if [[ $issues -eq 0 ]]; then
        log "SUCCESS" "🎉 Docker access should work correctly!"
        return 0
    else
        log "ERROR" "❌ Docker access issues detected ($issues critical issues)"
        return 1
    fi
}

# Export functions for use in other scripts
export -f has_docker_permissions
export -f fix_docker_permissions
export -f copy_docker_credentials_to_milou
export -f diagnose_docker_access 