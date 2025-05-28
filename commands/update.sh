#!/bin/bash

# =============================================================================
# Milou CLI Update Command Module
# Focused command handlers for update operations
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Module guard to prevent multiple loading
if [[ "${MILOU_UPDATE_COMMANDS_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_UPDATE_COMMANDS_LOADED="true"

# Combined help function to reduce exports
_show_update_help() {
    local help_type="${1:-system}"
    
    case "$help_type" in
        "system")
            echo "🔄 System Update Command Usage"
            echo "=============================="
            echo ""
            echo "UPDATE SYSTEM:"
            echo "  ./milou.sh update [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --version VERSION     Update to specific version (e.g., v1.0.0, latest)"
            echo "  --service SERVICES    Update specific services (comma-separated)"
            echo "                       Available: frontend,backend,database,engine,nginx"
            echo "  --force              Force update even if no changes detected"
            echo "  --no-backup          Skip backup creation before update"
            echo "  --help, -h           Show this help message"
            echo ""
            echo "Examples:"
            echo "  ./milou.sh update"
            echo "  ./milou.sh update --version v1.2.0"
            echo "  ./milou.sh update --service frontend,backend"
            echo "  ./milou.sh update --force --no-backup"
            echo ""
            echo "OTHER UPDATE COMMANDS:"
            echo "  ./milou.sh update-cli        Update the CLI tool itself"
            echo "  ./milou.sh update-status     Check update status"
            echo "  ./milou.sh rollback          Rollback last update"
            ;;
        "cli")
            echo "🛠️ CLI Update Command Usage"
            echo "==========================="
            echo ""
            echo "UPDATE CLI:"
            echo "  ./milou.sh update-cli [VERSION] [OPTIONS]"
            echo ""
            echo "Arguments:"
            echo "  VERSION              Target version (default: latest)"
            echo ""
            echo "Options:"
            echo "  --force              Force update even if already up to date"
            echo "  --check              Check for updates without installing"
            echo "  --help, -h           Show this help"
            echo ""
            echo "Examples:"
            echo "  ./milou.sh update-cli"
            echo "  ./milou.sh update-cli v3.2.0"
            echo "  ./milou.sh update-cli --force"
            echo "  ./milou.sh update-cli --check"
            ;;
    esac
}

# System update command handler
handle_update() {
    local target_version=""
    local specific_services=""
    local force_update=false
    local backup_before_update=true
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                target_version="$2"
                shift 2
                ;;
            --service|--services)
                specific_services="$2"
                shift 2
                ;;
            --force)
                force_update=true
                shift
                ;;
            --no-backup)
                backup_before_update=false
                shift
                ;;
            --help|-h)
                _show_update_help "system"
                return 0
                ;;
            *)
                milou_log "WARN" "Unknown update argument: $1"
                shift
                ;;
        esac
    done
    
    # Log the update request
    if [[ -n "$target_version" ]]; then
        milou_log "STEP" "🔄 Updating system to version: $target_version"
    else
        milou_log "STEP" "🔄 Updating system to latest version..."
    fi
    
    if [[ -n "$specific_services" ]]; then
        milou_log "INFO" "🎯 Targeting services: $specific_services"
    fi
    
    # Use modular update function
    if command -v milou_update_system >/dev/null 2>&1; then
        milou_update_system "$force_update" "$backup_before_update" "$target_version" "$specific_services"
    else
        milou_log "ERROR" "Update module not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize update modules"
        return 1
    fi
}

# CLI self-update command handler
handle_update_cli() {
    local target_version="${1:-latest}"
    local force="${2:-false}"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                target_version="$2"
                shift 2
                ;;
            --force)
                force="true"
                shift
                ;;
            --check)
                handle_check_cli_updates
                return $?
                ;;
            --help|-h)
                _show_update_help "cli"
                return 0
                ;;
            *)
                # Assume it's a version if no flag
                if [[ "$1" != --* ]]; then
                    target_version="$1"
                fi
                shift
                ;;
        esac
    done
    
    milou_log "STEP" "🔄 Updating Milou CLI..."
    
    # Use modular CLI update function
    if command -v milou_update_cli >/dev/null 2>&1; then
        milou_update_cli "$target_version" "$force"
    else
        milou_log "ERROR" "CLI update module not available"
        milou_log "INFO" "💡 Self-update functionality requires the update module"
        return 1
    fi
}

# Check for CLI updates
handle_check_cli_updates() {
    milou_log "INFO" "🔍 Checking for Milou CLI updates..."
    
    if command -v milou_self_update_check >/dev/null 2>&1; then
        if milou_self_update_check; then
            milou_log "INFO" "🆕 CLI update available!"
            milou_log "INFO" "💡 Run './milou.sh update-cli' to update"
        else
            milou_log "SUCCESS" "✅ CLI is up to date"
        fi
    else
        milou_log "ERROR" "CLI update check module not available"
        return 1
    fi
}

# Update status check
handle_update_status() {
    milou_log "STEP" "📊 Checking system update status..."
    
    if command -v milou_update_check_status >/dev/null 2>&1; then
        milou_update_check_status
    else
        milou_log "ERROR" "Update status module not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize update modules"
        return 1
    fi
}

# Rollback system update
handle_rollback() {
    local backup_file="${1:-}"
    
    milou_log "STEP" "🔄 Rolling back system update..."
    
    if command -v milou_update_rollback >/dev/null 2>&1; then
        milou_update_rollback "$backup_file"
    else
        milou_log "ERROR" "Rollback module not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize update modules"
        return 1
    fi
}

# =============================================================================
# CLEAN PUBLIC API - Export only essential functions
# =============================================================================

# Main command handlers (5 exports - CLEAN PUBLIC API)
export -f handle_update                 # System update handler
export -f handle_update_cli             # CLI update handler
export -f handle_check_cli_updates      # CLI update check
export -f handle_update_status          # Update status check
export -f handle_rollback               # Rollback handler

# Internal functions are NOT exported (marked with _ prefix)
# This keeps the namespace clean and makes it clear what's public vs internal 