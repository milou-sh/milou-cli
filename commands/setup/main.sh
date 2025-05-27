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
        setup_select_mode setup_mode || return 1
    else
        milou_log "WARN" "Mode selection module not available, using default interactive mode"
    fi
    
    # Step 4: Dependencies Installation
    if [[ "$needs_deps_install" == "true" ]]; then
        if command -v setup_install_dependencies >/dev/null 2>&1; then
            setup_install_dependencies || return 1
        else
            milou_log "ERROR" "Dependencies installation required but module not available"
            return 1
        fi
    else
        milou_log "INFO" "✅ Dependencies check passed - no installation needed"
    fi
    
    # Step 5: User Management
    if [[ "$needs_user_management" == "true" ]]; then
        if command -v setup_manage_users >/dev/null 2>&1; then
            setup_manage_users || return 1
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

# Export the new modular function
export -f handle_setup_modular
export -f setup_load_modules
export -f setup_handle_dev_mode
