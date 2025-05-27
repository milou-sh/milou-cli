#!/bin/bash

# =============================================================================
# User and Security Management Command Handlers for Milou CLI
# Simplified and standardized command handlers
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Modules are loaded centrally by milou_load_command_modules() in main script

# User status command handler
handle_user_status() {
    milou_log "INFO" "👤 Checking user and permission status..."
    
    if command -v show_user_status >/dev/null 2>&1; then
        show_user_status "$@"
    elif command -v get_current_user_info >/dev/null 2>&1; then
        get_current_user_info "$@"
    else
        milou_log "ERROR" "User status function not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize user management"
        return 1
    fi
}

# Create user command handler
handle_create_user() {
    milou_log "INFO" "👥 Creating dedicated milou user..."
    
    if command -v create_milou_user >/dev/null 2>&1; then
        create_milou_user "$@"
    else
        milou_log "ERROR" "Create user function not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize user management"
        return 1
    fi
}

# Migrate user command handler
handle_migrate_user() {
    milou_log "INFO" "🔄 Migrating existing installation to milou user..."
    
    if command -v migrate_to_milou_user >/dev/null 2>&1; then
        migrate_to_milou_user "$@"
    else
        milou_log "ERROR" "Migrate user function not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize user management"
        return 1
    fi
}

# Security check command handler
handle_security_check() {
    milou_log "INFO" "🔒 Running comprehensive security assessment..."
    
    if command -v security_assessment >/dev/null 2>&1; then
        security_assessment "$@"
    elif command -v quick_security_check >/dev/null 2>&1; then
        quick_security_check "$@"
    else
        milou_log "ERROR" "Security check function not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize security modules"
        return 1
    fi
}

# Security harden command handler
handle_security_harden() {
    milou_log "INFO" "🛡️ Applying security hardening measures..."
    
    if command -v harden_milou_user >/dev/null 2>&1; then
        harden_milou_user "$@"
    else
        milou_log "ERROR" "Security hardening function not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize security modules"
        return 1
    fi
}

# Security report command handler
handle_security_report() {
    milou_log "INFO" "📊 Generating detailed security report..."
    
    if command -v generate_security_report >/dev/null 2>&1; then
        generate_security_report "$@"
    else
        milou_log "ERROR" "Security report function not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize security modules"
        return 1
    fi
}

# Export all functions
export -f handle_user_status handle_create_user handle_migrate_user
export -f handle_security_check handle_security_harden handle_security_report
