#!/bin/bash

# =============================================================================
# User Management and Security Command Handlers for Milou CLI
# Extracted from milou.sh to improve maintainability
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# User status command handler
handle_user_status() {
    log "INFO" "👤 Checking user and permission status..."
    
    if command -v show_user_status >/dev/null 2>&1; then
        show_user_status "$@"
    else
        log "ERROR" "User status function not available"
        return 1
    fi
}

# Create user command handler
handle_create_user() {
    log "INFO" "👤 Creating dedicated milou user..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "User creation requires root privileges"
        log "INFO" "Please run with sudo: sudo ./milou.sh create-user"
        return 1
    fi
    
    if command -v create_milou_user >/dev/null 2>&1; then
        create_milou_user "$@"
    else
        log "ERROR" "User creation function not available"
        return 1
    fi
}

# Migrate user command handler
handle_migrate_user() {
    log "INFO" "🔄 Migrating existing installation to milou user..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "User migration requires root privileges"
        log "INFO" "Please run with sudo: sudo ./milou.sh migrate-user"
        return 1
    fi
    
    if command -v migrate_to_milou_user >/dev/null 2>&1; then
        migrate_to_milou_user "$@"
    else
        log "ERROR" "User migration function not available"
        return 1
    fi
}

# Security check command handler
handle_security_check() {
    log "INFO" "🔒 Running comprehensive security assessment..."
    
    if command -v run_comprehensive_security_assessment >/dev/null 2>&1; then
        run_comprehensive_security_assessment "$@"
    else
        log "ERROR" "Security assessment function not available"
        return 1
    fi
}

# Security hardening command handler
handle_security_harden() {
    log "INFO" "🛡️ Applying security hardening measures..."
    
    # Check if running as root for system-level hardening
    if [[ $EUID -ne 0 ]]; then
        log "WARN" "Security hardening is more effective when run as root"
        log "INFO" "Some hardening measures may be skipped"
    fi
    
    if command -v apply_security_hardening_measures >/dev/null 2>&1; then
        apply_security_hardening_measures "$@"
    else
        log "ERROR" "Security hardening function not available"
        return 1
    fi
}

# Security report command handler
handle_security_report() {
    log "INFO" "📊 Generating detailed security report..."
    
    if command -v generate_detailed_security_report >/dev/null 2>&1; then
        generate_detailed_security_report "$@"
    else
        log "ERROR" "Security report function not available"
        return 1
    fi
}

# Install dependencies command handler
handle_install_deps() {
    log "INFO" "📦 Installing system dependencies..."
    
    # Check if running as root for system package installation
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "Dependency installation requires root privileges"
        log "INFO" "Please run with sudo: sudo ./milou.sh install-deps"
        return 1
    fi
    
    if command -v install_system_dependencies >/dev/null 2>&1; then
        install_system_dependencies "$@"
    else
        log "ERROR" "Dependency installation function not available"
        return 1
    fi
}

# Export all functions
export -f handle_user_status handle_create_user handle_migrate_user
export -f handle_security_check handle_security_harden handle_security_report
export -f handle_install_deps 