#!/bin/bash

# =============================================================================
# System Management Command Handlers for Milou CLI
# Extracted from milou.sh to improve maintainability
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Configuration display command handler
handle_config() {
    log "INFO" "📋 Displaying current configuration..."
    
    if command -v show_current_configuration >/dev/null 2>&1; then
        show_current_configuration "$@"
    else
        log "ERROR" "Configuration display function not available"
        return 1
    fi
}

# Configuration validation command handler
handle_validate() {
    log "INFO" "🔍 Validating configuration and environment..."
    
    if command -v validate_milou_configuration >/dev/null 2>&1; then
        validate_milou_configuration "$@"
    else
        log "ERROR" "Configuration validation function not available"
        return 1
    fi
}

# Backup command handler
handle_backup() {
    log "INFO" "💾 Creating system backup..."
    
    if command -v create_system_backup >/dev/null 2>&1; then
        create_system_backup "$@"
    else
        log "ERROR" "Backup function not available"
        return 1
    fi
}

# Restore command handler
handle_restore() {
    local backup_file="${1:-}"
    
    if [[ -z "$backup_file" ]]; then
        log "ERROR" "Backup file is required for restore"
        log "INFO" "Usage: ./milou.sh restore <backup_file>"
        return 1
    fi
    
    log "INFO" "📁 Restoring from backup: $backup_file"
    
    if command -v restore_from_backup >/dev/null 2>&1; then
        restore_from_backup "$backup_file"
    else
        log "ERROR" "Restore function not available"
        return 1
    fi
}

# Update command handler
handle_update() {
    log "INFO" "🔄 Updating to latest version..."
    
    if command -v update_milou_system >/dev/null 2>&1; then
        update_milou_system "$@"
    else
        log "ERROR" "Update function not available"
        return 1
    fi
}

# SSL management command handler
handle_ssl() {
    log "INFO" "🔒 Managing SSL certificates..."
    
    if command -v manage_ssl_certificates >/dev/null 2>&1; then
        manage_ssl_certificates "$@"
    else
        log "ERROR" "SSL management function not available"
        return 1
    fi
}

# Cleanup command handler
handle_cleanup() {
    local cleanup_type="${1:-docker}"
    
    case "$cleanup_type" in
        docker|--docker)
            log "INFO" "🧹 Cleaning up Docker resources..."
            if command -v cleanup_docker_resources >/dev/null 2>&1; then
                cleanup_docker_resources
            else
                log "ERROR" "Docker cleanup function not available"
                return 1
            fi
            ;;
        system|--system)
            log "INFO" "🧹 Cleaning up system resources..."
            if command -v cleanup_system_resources >/dev/null 2>&1; then
                cleanup_system_resources
            else
                log "ERROR" "System cleanup function not available"
                return 1
            fi
            ;;
        all|--all)
            log "INFO" "🧹 Performing complete system cleanup..."
            if command -v cleanup_docker_resources >/dev/null 2>&1; then
                cleanup_docker_resources
            fi
            if command -v cleanup_system_resources >/dev/null 2>&1; then
                cleanup_system_resources
            fi
            ;;
        --help|-h)
            echo "Cleanup command usage:"
            echo "  ./milou.sh cleanup [docker|system|all]"
            echo ""
            echo "Options:"
            echo "  docker    Clean Docker resources (default)"
            echo "  system    Clean system temporary files"
            echo "  all       Clean everything"
            ;;
        *)
            log "WARN" "Unknown cleanup type: $cleanup_type, defaulting to docker cleanup"
            if command -v cleanup_docker_resources >/dev/null 2>&1; then
                cleanup_docker_resources
            else
                log "ERROR" "Docker cleanup function not available"
                return 1
            fi
            ;;
    esac
}

# Debug images command handler
handle_debug_images() {
    log "INFO" "🔧 Debugging Docker image availability..."
    
    if command -v debug_docker_images >/dev/null 2>&1; then
        debug_docker_images "$@"
    else
        log "ERROR" "Debug images function not available"
        return 1
    fi
}

# System diagnosis command handler
handle_diagnose() {
    log "INFO" "🩺 Running comprehensive system diagnosis..."
    
    if command -v run_system_diagnosis >/dev/null 2>&1; then
        run_system_diagnosis "$@"
    else
        log "ERROR" "System diagnosis function not available"
        return 1
    fi
}

# Cleanup test files command handler
handle_cleanup_test_files() {
    log "INFO" "🧹 Cleaning up test configuration files..."
    
    if command -v cleanup_test_configuration_files >/dev/null 2>&1; then
        cleanup_test_configuration_files "$@"
    else
        log "ERROR" "Test cleanup function not available"
        return 1
    fi
}

# Export all functions
export -f handle_config handle_validate handle_backup handle_restore
export -f handle_update handle_ssl handle_cleanup handle_debug_images
export -f handle_diagnose handle_cleanup_test_files 