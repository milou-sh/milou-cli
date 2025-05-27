#!/bin/bash

# =============================================================================
# Modular Setup Main Function
# Replaces the monolithic 423-line handle_setup() function
# =============================================================================

# Load setup modules
setup_load_modules() {
    local script_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    local setup_modules=(
        "$script_dir/commands/setup/analysis.sh"
        "$script_dir/commands/setup/prerequisites.sh"
        "$script_dir/commands/setup/mode.sh"
        "$script_dir/commands/setup/dependencies.sh"
        "$script_dir/commands/setup/user.sh"
        "$script_dir/commands/setup/configuration.sh"
        "$script_dir/commands/setup/validation.sh"
    )
    
    for module in "${setup_modules[@]}"; do
        if [[ -f "$module" ]]; then
            source "$module" || {
                milou_log "ERROR" "Failed to load setup module: $module"
                return 1
            }
        else
            milou_log "WARN" "Setup module not found: $module (will be created)"
        fi
    done
}

# New modular handle_setup function (replaces 423-line version)
handle_setup_modular() {
    # Load setup modules
    if ! setup_load_modules; then
        milou_log "ERROR" "Failed to load setup modules"
        return 1
    fi
    
    echo
    echo -e "${BOLD}${PURPLE}🚀 Milou Setup - State-of-the-Art CLI v${SCRIPT_VERSION}${NC}"
    echo -e "${BOLD}${PURPLE}═══════════════════════════════════════════════════${NC}"
    echo
    
    # CRITICAL: Check for existing installation FIRST
    setup_check_existing_installation || {
        local exit_code=$?
        if [[ $exit_code -eq 2 ]]; then
            # User chose to cancel
            milou_log "INFO" "Setup cancelled by user"
            return 0
        elif [[ $exit_code -eq 3 ]]; then
            # Handled existing installation, continue
            milou_log "DEBUG" "Existing installation handled, continuing setup"
        else
            # Error occurred
            return 1
        fi
    }
    
    # Development Mode Setup (if requested)
    if [[ "${DEV_MODE:-false}" == "true" ]]; then
        setup_handle_dev_mode || return 1
    fi
    
    # Setup state variables
    local is_fresh_server=false
    local needs_deps_install=false
    local needs_user_management=false
    local setup_mode="interactive"
    
    # Step 1: System Analysis and Detection
    setup_analyze_system is_fresh_server needs_deps_install needs_user_management || return 1
    
    # Step 2: Prerequisites Assessment
    setup_assess_prerequisites needs_deps_install || return 1
    
    # Step 3: Setup Mode Selection
    if command -v setup_select_mode >/dev/null 2>&1; then
        setup_select_mode "$is_fresh_server" setup_mode || return 1
    else
        milou_log "WARN" "Mode selection module not available, using default interactive mode"
        setup_mode="interactive"
    fi
    
    # Step 4: Dependencies Installation
    if [[ "$needs_deps_install" == "true" ]]; then
        if command -v setup_install_dependencies >/dev/null 2>&1; then
            setup_install_dependencies "$needs_deps_install" "$setup_mode" || return 1
        else
            milou_log "ERROR" "Dependencies installation required but module not available"
            return 1
        fi
    else
        milou_log "INFO" "✅ Dependencies check passed - no installation needed"
    fi
    
    # Step 5: User Management
    if [[ "$needs_user_management" == "true" ]]; then
        if command -v setup_manage_user >/dev/null 2>&1; then
            setup_manage_user "$needs_user_management" "$setup_mode" || return 1
        else
            milou_log "ERROR" "User management required but module not available"
            return 1
        fi
    else
        milou_log "INFO" "✅ User management check passed - no user creation needed"
    fi
    
    # Step 6: Configuration Wizard
    if command -v setup_run_configuration_wizard >/dev/null 2>&1; then
        setup_run_configuration_wizard "$setup_mode" || return 1
    else
        milou_log "WARN" "Configuration wizard module not available, skipping"
    fi
    
    # Step 7: Final Validation and Service Startup
    if command -v setup_final_validation >/dev/null 2>&1; then
        setup_final_validation || return 1
    else
        milou_log "WARN" "Final validation module not available, skipping"
    fi
    
    milou_log "SUCCESS" "🎉 Modular setup completed successfully!"
    echo
    milou_log "INFO" "💡 Next steps:"
    milou_log "INFO" "  • Your Milou instance should now be running"
    milou_log "INFO" "  • Access the web interface at your configured domain"
    milou_log "INFO" "  • Check service status with: $0 status"
    
    return 0
}

# Development mode handler
setup_handle_dev_mode() {
    milou_log "STEP" "Development Mode Setup"
    echo
    
    # Load development module
    if [[ -f "${SCRIPT_DIR}/lib/docker/development.sh" ]]; then
        source "${SCRIPT_DIR}/lib/docker/development.sh"
        if command -v milou_auto_setup_dev_mode >/dev/null 2>&1; then
            if ! milou_auto_setup_dev_mode; then
                milou_log "ERROR" "Failed to setup development mode"
                return 1
            fi
        else
            milou_log "ERROR" "Development module functions not available"
            return 1
        fi
    else
        milou_log "ERROR" "Development module not found"
        return 1
    fi
    
    echo
    return 0
}

# Check for existing installation and handle conflicts
setup_check_existing_installation() {
    milou_log "STEP" "Pre-Setup: Existing Installation Check"
    echo
    
    local has_containers=false
    local has_config=false
    local has_running_services=false
    local port_conflicts=()
    
    # Check for existing containers
    local existing_containers
    existing_containers=$(docker ps -a --filter "name=milou-" --format "{{.Names}}\t{{.Status}}" 2>/dev/null || true)
    
    if [[ -n "$existing_containers" ]]; then
        has_containers=true
        milou_log "INFO" "📦 Found existing Milou containers:"
        
        # Check running services without subshell
        while IFS=$'\t' read -r name status; do
            if [[ "$status" =~ Up|running ]]; then
                has_running_services=true
                echo "  🟢 $name - $status"
            else
                echo "  🔴 $name - $status"
            fi
        done <<< "$existing_containers"
        echo
    fi
    
    # Check for existing configuration
    if [[ -f "${ENV_FILE:-${SCRIPT_DIR}/.env}" ]]; then
        has_config=true
        milou_log "INFO" "⚙️  Found existing configuration file"
    fi
    
    # Check for port conflicts
    local critical_ports=("5432:PostgreSQL" "6379:Redis" "443:HTTPS" "80:HTTP" "9999:API")
    for port_info in "${critical_ports[@]}"; do
        local port="${port_info%:*}"
        local service="${port_info#*:}"
        
        if ! milou_check_port_availability "$port" "localhost" "true"; then
            port_conflicts+=("$port:$service")
        fi
    done
    
    # If no existing installation, proceed normally
    if [[ "$has_containers" == false && "$has_config" == false && ${#port_conflicts[@]} -eq 0 ]]; then
        milou_log "SUCCESS" "✅ No existing installation detected - proceeding with fresh setup"
        return 0
    fi
    
    # Handle existing installation
    milou_log "WARN" "⚠️  Existing Milou installation detected!"
    echo
    
    if [[ ${#port_conflicts[@]} -gt 0 ]]; then
        milou_log "WARN" "🔌 Port conflicts detected:"
        for port_conflict in "${port_conflicts[@]}"; do
            local port="${port_conflict%:*}"
            local service="${port_conflict#*:}"
            echo "  • Port $port ($service) is in use"
        done
        echo
    fi
    
    # Show options based on what's detected
    echo "How would you like to proceed?"
    echo
    if [[ "$has_running_services" == true ]]; then
        echo "  1) Stop existing services and reconfigure (recommended)"
        echo "  2) Update existing configuration only"
        echo "  3) Force restart all services (may cause data loss)"
        echo "  4) Cancel setup"
    else
        echo "  1) Update existing configuration"
        echo "  2) Clean install (remove all containers and data)"
        echo "  3) Cancel setup"
    fi
    echo
    
    # Get user choice
    local choice
    if [[ "${NON_INTERACTIVE:-false}" == "true" || "${FORCE:-false}" == "true" ]]; then
        choice="1"
        milou_log "INFO" "Non-interactive/force mode - choosing option 1"
    else
        if command -v milou_prompt_user >/dev/null 2>&1; then
            milou_prompt_user "Choose option" "1" "choice" "false" 3
            choice="${choice:-1}"
        else
            # Fallback prompt method
            echo -n "Choose option (default: 1): "
            read -r choice
            choice="${choice:-1}"
        fi
    fi
    
    case "$choice" in
        1)
            if [[ "$has_running_services" == true ]]; then
                milou_log "INFO" "🛑 Stopping existing Milou services..."
                if command -v milou_docker_stop >/dev/null 2>&1; then
                    milou_docker_stop || {
                        milou_log "ERROR" "Failed to stop existing services"
                        return 1
                    }
                else
                    docker ps --filter "name=milou-" --format "{{.Names}}" | xargs -r docker stop || {
                        milou_log "ERROR" "Failed to stop containers manually"
                        return 1
                    }
                fi
                milou_log "SUCCESS" "✅ Existing services stopped"
            else
                milou_log "INFO" "🔄 Updating existing configuration"
            fi
            return 3  # Continue with setup
            ;;
        2)
            if [[ "$has_running_services" == true ]]; then
                milou_log "INFO" "🔄 Updating configuration only (keeping services running)"
                export SKIP_SERVICE_START="true"
                return 3  # Continue with setup
            else
                milou_log "INFO" "🗑️ Performing clean installation..."
                # Remove all containers and volumes
                docker ps -a --filter "name=milou-" --format "{{.Names}}" | xargs -r docker rm -f >/dev/null 2>&1
                docker volume ls --filter "name=milou" --format "{{.Name}}" | xargs -r docker volume rm >/dev/null 2>&1
                milou_log "SUCCESS" "✅ Clean installation prepared"
                return 3  # Continue with setup
            fi
            ;;
        3)
            if [[ "$has_running_services" == true ]]; then
                milou_log "WARN" "🔥 Force restarting all services (potential data loss)"
                docker ps -a --filter "name=milou-" --format "{{.Names}}" | xargs -r docker rm -f >/dev/null 2>&1
                milou_log "SUCCESS" "✅ Force restart completed"
                return 3  # Continue with setup
            else
                milou_log "INFO" "Setup cancelled by user"
                return 2  # Cancel
            fi
            ;;
        4|*)
            milou_log "INFO" "Setup cancelled by user"
            return 2  # Cancel
            ;;
    esac
}

# Export the new modular function
export -f handle_setup_modular
export -f setup_load_modules
export -f setup_handle_dev_mode
