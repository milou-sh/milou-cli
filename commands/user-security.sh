#!/bin/bash

# =============================================================================
# User and Security Management Command Handlers for Milou CLI
# Extracted from milou.sh to improve maintainability
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Ensure user modules are loaded (using centralized loader)
ensure_user_modules() {
    # Use the centralized module loader function
    if command -v milou_load_user_modules >/dev/null 2>&1; then
        milou_load_user_modules
    else
        # Fallback if centralized loader not available
        if command -v milou_log >/dev/null 2>&1; then
            milou_log "WARN" "Centralized module loader not available, loading minimal modules"
        fi
        # Only load essential user modules as fallback
        if command -v milou_load_module >/dev/null 2>&1; then
            milou_load_module "user/core" 2>/dev/null || true
            milou_load_module "user/management" 2>/dev/null || true
            milou_load_module "system/prerequisites" 2>/dev/null || true
        fi
    fi
}

# User status command handler
handle_user_status() {
    log "INFO" "👤 Checking user and permission status..."
    
    # Ensure user modules are loaded
    ensure_user_modules
    
    if command -v show_user_status >/dev/null 2>&1; then
        show_user_status "$@"
    elif command -v get_current_user_info >/dev/null 2>&1; then
        get_current_user_info "$@"
    else
        log "ERROR" "User status function not available"
        log "DEBUG" "Available functions: $(compgen -A function | grep -E '(user|status)' | head -5 | tr '\n' ' ')"
        return 1
    fi
}

# Create user command handler
handle_create_user() {
    log "INFO" "👥 Creating dedicated milou user..."
    
    # Ensure user modules are loaded
    ensure_user_modules
    
    if command -v create_milou_user >/dev/null 2>&1; then
        create_milou_user "$@"
    elif command -v create_user_command >/dev/null 2>&1; then
        create_user_command "$@"
    else
        log "ERROR" "Create user function not available"
        log "DEBUG" "Available functions: $(compgen -A function | grep -E '(create|user)' | head -5 | tr '\n' ' ')"
        return 1
    fi
}

# Migrate user command handler
handle_migrate_user() {
    log "INFO" "🔄 Migrating existing installation to milou user..."
    
    # Ensure user modules are loaded
    ensure_user_modules
    
    if command -v migrate_to_milou_user >/dev/null 2>&1; then
        migrate_to_milou_user "$@"
    elif command -v migrate_user_command >/dev/null 2>&1; then
        migrate_user_command "$@"
    else
        log "ERROR" "Migrate user function not available"
        log "DEBUG" "Available functions: $(compgen -A function | grep -E '(migrate|user)' | head -5 | tr '\n' ' ')"
        return 1
    fi
}

# Security check command handler
handle_security_check() {
    log "INFO" "🔒 Running comprehensive security assessment..."
    
    # Ensure user modules are loaded
    ensure_user_modules
    
    if command -v security_assessment >/dev/null 2>&1; then
        security_assessment "$@"
    elif command -v quick_security_check >/dev/null 2>&1; then
        quick_security_check "$@"
    else
        log "ERROR" "Security check function not available"
        log "DEBUG" "Available functions: $(compgen -A function | grep -E '(security|check)' | head -5 | tr '\n' ' ')"
        return 1
    fi
}

# Security harden command handler
handle_security_harden() {
    log "INFO" "🛡️ Applying security hardening measures..."
    
    # Ensure user modules are loaded
    ensure_user_modules
    
    if command -v harden_milou_user >/dev/null 2>&1; then
        harden_milou_user "$@"
    else
        log "ERROR" "Security hardening function not available"
        log "DEBUG" "Available functions: $(compgen -A function | grep -E '(harden|security)' | head -5 | tr '\n' ' ')"
        return 1
    fi
}

# Security report command handler
handle_security_report() {
    log "INFO" "📊 Generating detailed security report..."
    
    # Ensure user modules are loaded
    ensure_user_modules
    
    if command -v generate_security_report >/dev/null 2>&1; then
        generate_security_report "$@"
    else
        log "ERROR" "Security report function not available"
        log "DEBUG" "Available functions: $(compgen -A function | grep -E '(report|security)' | head -5 | tr '\n' ' ')"
        return 1
    fi
}

# Export all functions
export -f handle_user_status handle_create_user handle_migrate_user
export -f handle_security_check handle_security_harden handle_security_report
export -f ensure_user_modules 