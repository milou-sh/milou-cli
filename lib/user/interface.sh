#!/bin/bash

# =============================================================================
# User Interface and Status Display for Milou CLI
# Handles interactive user setup, status display, and user management interface
# =============================================================================

# Note: Dependencies are loaded automatically by the module loader

# =============================================================================
# Interactive User Setup
# =============================================================================

# Interactive user setup
interactive_user_setup() {
    echo
    echo -e "${BOLD}${CYAN}🔐 User Management Setup${NC}"
    echo "For security reasons, Milou should not run as root."
    echo
    
    local current_user
    current_user=$(whoami)
    
    if is_running_as_root; then
        echo -e "${YELLOW}⚠️  Currently running as root user${NC}"
        echo
        echo "Recommended options:"
        echo "1) Create dedicated $MILOU_USER user (recommended)"
        echo "2) Continue as root (not recommended)"
        echo "3) Exit and run as non-root user"
        echo
        
        while true; do
            read -p "Choose option (1-3): " choice
            case $choice in
                1)
                    if ! milou_user_exists; then
                        create_milou_user
                    fi
                    if confirm "Switch to $MILOU_USER user now?" "Y"; then
                        switch_to_milou_user "$@"
                    fi
                    break
                    ;;
                2)
                    log "WARN" "Continuing as root - this is not recommended for production"
                    if ! confirm "Are you sure you want to continue as root?" "N"; then
                        exit 1
                    fi
                    break
                    ;;
                3)
                    log "INFO" "Please create a non-root user and run the script again"
                    exit 0
                    ;;
                *)
                    echo "Please enter 1, 2, or 3"
                    ;;
            esac
        done
    else
        if ! has_docker_permissions; then
            echo -e "${YELLOW}⚠️  Current user ($current_user) does not have Docker permissions${NC}"
            echo
            echo "Available options:"
            echo "1) Add current user to docker group (requires sudo)"
            echo "2) Create and switch to $MILOU_USER user (requires sudo)"
            echo "3) Continue without Docker permissions (will likely fail)"
            echo
            
            while true; do
                read -p "Choose option (1-3): " choice
                case $choice in
                    1)
                        log "INFO" "Adding $current_user to docker group..."
                        if sudo usermod -aG docker "$current_user"; then
                            log "SUCCESS" "User added to docker group"
                            log "INFO" "Please log out and log back in for changes to take effect"
                            log "INFO" "Or run: newgrp docker"
                        else
                            log "ERROR" "Failed to add user to docker group"
                        fi
                        break
                        ;;
                    2)
                        if ! milou_user_exists; then
                            sudo -E bash -c "$(declare -f create_milou_user); create_milou_user"
                        fi
                        if confirm "Switch to $MILOU_USER user now?" "Y"; then
                            switch_to_milou_user "$@"
                        fi
                        break
                        ;;
                    3)
                        log "WARN" "Continuing without Docker permissions - this will likely fail"
                        break
                        ;;
                    *)
                        echo "Please enter 1, 2, or 3"
                        ;;
                esac
            done
        else
            log "SUCCESS" "User $current_user has proper Docker permissions"
        fi
    fi
}

# =============================================================================
# Status Display
# =============================================================================

# Show user status information
show_user_status() {
    echo -e "${BOLD}👤 User Status Information${NC}"
    echo "=============================="
    echo
    
    # Current user info
    local current_user
    current_user=$(whoami)
    echo -e "${CYAN}Current User:${NC}"
    echo "  User: $current_user"
    echo "  UID: $(id -u), GID: $(id -g)"
    echo "  Groups: $(groups | cut -d: -f2 | tr ' ' ', ')"
    echo "  Running as root: $(is_running_as_root && echo "Yes" || echo "No")"
    echo "  Home directory: $HOME"
    echo
    
    # Milou user info
    echo -e "${CYAN}Milou User:${NC}"
    if milou_user_exists; then
        local milou_home
        milou_home=$(get_milou_home)
        
        echo "  Status: $MILOU_USER exists ✅"
        echo "  UID: $(id -u "$MILOU_USER"), GID: $(id -g "$MILOU_USER")"
        echo "  Home: $milou_home"
        echo "  Groups: $(groups "$MILOU_USER" 2>/dev/null | cut -d: -f2 | tr ' ' ', ' || echo "unknown")"
        
        # Check if milou user environment is set up
        if [[ -d "$milou_home/.milou" ]]; then
            echo "  Environment: Configured ✅"
        else
            echo "  Environment: Not configured ⚠️"
        fi
        
        # Check CLI accessibility
        local cli_accessible=false
        local cli_location=""
        local -a cli_paths=(
            "$milou_home/milou-cli/milou.sh"
            "$milou_home/bin/milou"
            "/opt/milou-cli/milou.sh"
            "/usr/local/milou-cli/milou.sh"
        )
        
        for path in "${cli_paths[@]}"; do
            if [[ -f "$path" && -x "$path" ]]; then
                cli_accessible=true
                cli_location="$path"
                break
            fi
        done
        
        if [[ "$cli_accessible" == true ]]; then
            echo "  CLI Access: Available ✅ ($cli_location)"
        else
            echo "  CLI Access: Not available ❌"
        fi
    else
        echo "  Status: $MILOU_USER does not exist ❌"
        echo "  💡 Run: sudo $0 create-user"
    fi
    echo
    
    # Docker access info
    echo -e "${CYAN}Docker Access:${NC}"
    echo "  Current user access: $(has_docker_permissions && echo "Yes ✅" || echo "No ❌")"
    
    if milou_user_exists; then
        local milou_docker_access=false
        local current_user
        current_user=$(whoami)
        
        if [[ "$current_user" == "$MILOU_USER" ]]; then
            # We're already running as milou user, use has_docker_permissions function
            if has_docker_permissions; then
                milou_docker_access=true
            fi
        else
            # We're running as a different user, use sudo to check
            if sudo -u "$MILOU_USER" groups 2>/dev/null | grep -q docker; then
                if sudo -u "$MILOU_USER" docker info >/dev/null 2>&1; then
                    milou_docker_access=true
                fi
            fi
        fi
        
        echo "  Milou user access: $([ "$milou_docker_access" == true ] && echo "Yes ✅" || echo "No ❌")"
    fi
    
    if command -v docker >/dev/null 2>&1; then
        local docker_version
        docker_version=$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',' || echo "unknown")
        echo "  Docker version: $docker_version"
        echo "  Docker daemon: $(docker info >/dev/null 2>&1 && echo "accessible ✅" || echo "not accessible ❌")"
        
        # Show running containers if accessible
        if docker info >/dev/null 2>&1; then
            local running_containers
            running_containers=$(docker ps --format "{{.Names}}" 2>/dev/null | wc -l)
            echo "  Running containers: $running_containers"
        fi
    else
        echo "  Docker: not installed ❌"
    fi
    echo
    
    # Environment and configuration info
    echo -e "${CYAN}Environment:${NC}"
    echo "  Script directory: $SCRIPT_DIR"
    echo "  Config directory: $CONFIG_DIR"
    
    if [[ -f "$ENV_FILE" ]]; then
        echo "  Configuration file: exists ✅"
        local config_perms
        config_perms=$(stat -c %a "$ENV_FILE" 2>/dev/null || stat -f %A "$ENV_FILE" 2>/dev/null)
        echo "  Config permissions: $config_perms $([ "$config_perms" -le 600 ] && echo "✅" || echo "⚠️")"
    else
        echo "  Configuration file: missing ❌"
    fi
    
    if [[ -d "./ssl" ]]; then
        echo "  SSL directory: exists ✅"
        local ssl_files
        ssl_files=$(find "./ssl" -name "*.crt" -o -name "*.key" 2>/dev/null | wc -l)
        echo "  SSL files: $ssl_files found"
    else
        echo "  SSL directory: missing ⚠️"
    fi
    echo
    
    # Security status
    echo -e "${CYAN}Security Status:${NC}"
    
    # File permissions check
    local security_issues=0
    
    if [[ -f "$ENV_FILE" ]]; then
        local env_perms
        env_perms=$(stat -c %a "$ENV_FILE" 2>/dev/null || stat -f %A "$ENV_FILE" 2>/dev/null)
        if [[ "$env_perms" -gt 600 ]]; then
            echo "  Config file security: Insecure permissions ($env_perms) ⚠️"
            ((security_issues++))
        else
            echo "  Config file security: Secure permissions ✅"
        fi
    fi
    
    # Check for running as root
    if is_running_as_root; then
        echo "  Root usage: Running as root (not recommended) ⚠️"
        ((security_issues++))
    else
        echo "  Root usage: Running as non-root user ✅"
    fi
    
    # Check Docker socket permissions
    if [[ -S /var/run/docker.sock ]]; then
        local socket_perms
        socket_perms=$(stat -c %a /var/run/docker.sock 2>/dev/null || echo "unknown")
        if [[ "$socket_perms" == "666" ]]; then
            echo "  Docker socket: Too permissive ($socket_perms) ⚠️"
            ((security_issues++))
        else
            echo "  Docker socket: Secure permissions ✅"
        fi
    fi
    
    echo "  Security issues found: $security_issues"
    echo
    
    # Recommendations
    if [[ $security_issues -gt 0 ]] || ! milou_user_exists || is_running_as_root; then
        echo -e "${CYAN}Recommendations:${NC}"
        
        if ! milou_user_exists; then
            echo "  • Create dedicated milou user: sudo $0 create-user"
        fi
        
        if is_running_as_root && milou_user_exists; then
            echo "  • Switch to milou user: sudo -u milou $0 [command]"
        fi
        
        if [[ $security_issues -gt 0 ]]; then
            echo "  • Run security assessment: $0 security-check"
            echo "  • Apply security hardening: sudo $0 security-harden"
        fi
        
        if ! has_docker_permissions && [[ "$current_user" != "root" ]]; then
            echo "  • Add Docker permissions: sudo usermod -aG docker $current_user"
        fi
        
        echo
    fi
    
    # Quick validation
    if milou_user_exists; then
        echo -e "${CYAN}Environment Validation:${NC}"
        if validate_milou_user_environment >/dev/null 2>&1; then
            echo "  Milou user environment: Valid ✅"
        else
            echo "  Milou user environment: Issues found ⚠️"
            echo "  💡 Run with --verbose for details"
        fi
    fi
}

# =============================================================================
# User Management Commands
# =============================================================================

# Create user command interface
create_user_command() {
    echo -e "${BOLD}${CYAN}🔐 Creating Milou User${NC}"
    echo
    
    if milou_user_exists; then
        log "INFO" "User $MILOU_USER already exists"
        if confirm "Do you want to recreate the user environment?" "N"; then
            setup_milou_user_environment
        fi
        return 0
    fi
    
    if ! is_running_as_root; then
        log "ERROR" "Root privileges required to create user"
        log "INFO" "💡 Run: sudo $0 create-user"
        return 1
    fi
    
    create_milou_user
    
    echo
    log "SUCCESS" "User $MILOU_USER created successfully!"
    echo
    echo "Next steps:"
    echo "  • Switch to milou user: sudo -u milou $0 [command]"
    echo "  • Or run commands as milou: sudo -u milou bash"
    echo "  • Test the setup: sudo -u milou $0 user-status"
}

# Test user command interface
test_user_command() {
    echo -e "${BOLD}${CYAN}🧪 Testing User Setup${NC}"
    echo
    
    if ! milou_user_exists; then
        log "ERROR" "Milou user does not exist"
        log "INFO" "💡 Create user first: sudo $0 create-user"
        return 1
    fi
    
    # Test environment
    log "INFO" "Testing milou user environment..."
    if validate_milou_user_environment; then
        log "SUCCESS" "Environment validation passed"
    else
        log "WARN" "Environment validation found issues"
    fi
    
    # Test CLI functionality
    log "INFO" "Testing CLI functionality..."
    if test_milou_user_cli; then
        log "SUCCESS" "CLI functionality test passed"
    else
        log "WARN" "CLI functionality test failed"
    fi
    
    # Test Docker access
    log "INFO" "Testing Docker access..."
    if sudo -u "$MILOU_USER" docker info >/dev/null 2>&1; then
        log "SUCCESS" "Docker access test passed"
    else
        log "WARN" "Docker access test failed"
        log "INFO" "💡 Run Docker diagnostic: $0 diagnose-docker milou"
    fi
    
    echo
    log "SUCCESS" "User testing completed"
}

# Migrate user command interface
migrate_user_command() {
    echo -e "${BOLD}${CYAN}📦 Migrating to Milou User${NC}"
    echo
    
    if ! is_running_as_root; then
        log "ERROR" "Root privileges required for migration"
        log "INFO" "💡 Run: sudo $0 migrate-user"
        return 1
    fi
    
    migrate_to_milou_user
    
    echo
    log "SUCCESS" "Migration completed successfully!"
    echo
    echo "Next steps:"
    echo "  • Switch to milou user: sudo -u milou $0 [command]"
    echo "  • Verify migration: sudo -u milou $0 user-status"
}

# Export functions for use in other scripts
export -f interactive_user_setup
export -f show_user_status
export -f create_user_command
export -f test_user_command
export -f migrate_user_command 