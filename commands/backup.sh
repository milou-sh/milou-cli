#!/bin/bash

# =============================================================================
# Milou CLI Backup Command Module
# Focused command handlers for backup operations
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Module guard to prevent multiple loading
if [[ "${MILOU_BACKUP_COMMANDS_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_BACKUP_COMMANDS_LOADED="true"

# Show backup and restore help (combined to reduce exports)
_show_backup_restore_help() {
    local help_type="${1:-backup}"
    
    case "$help_type" in
        "backup")
            echo "📦 Backup Command Usage"
            echo "======================="
            echo ""
            echo "CREATE BACKUP:"
            echo "  ./milou.sh backup [TYPE] [OPTIONS]"
            echo ""
            echo "Types:"
            echo "  full         Complete system backup (default)"
            echo "  config       Configuration files only"
            echo "  data         Data and volumes only"
            echo "  ssl          SSL certificates only"
            echo ""
            echo "Options:"
            echo "  --dir DIR           Backup directory (default: ./backups)"
            echo "  --name NAME         Custom backup name"
            echo "  --help, -h          Show this help"
            echo ""
            echo "Examples:"
            echo "  ./milou.sh backup full"
            echo "  ./milou.sh backup config --dir /opt/backups"
            echo "  ./milou.sh backup data --name pre_update_backup"
            ;;
        "restore")
            echo "📁 Restore Command Usage"
            echo "========================"
            echo ""
            echo "RESTORE FROM BACKUP:"
            echo "  ./milou.sh restore <backup_file> [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --type TYPE         Restore type (full, config, data, ssl)"
            echo "  --verify-only       Validate backup without restoring"
            echo "  --help, -h          Show this help"
            echo ""
            echo "Examples:"
            echo "  ./milou.sh restore backups/backup_20241201_143022.tar.gz"
            echo "  ./milou.sh restore backup.tar.gz --type config"
            echo "  ./milou.sh restore backup.tar.gz --verify-only"
            echo ""
            echo "LIST BACKUPS:"
            echo "  ./milou.sh list-backups [directory]"
            ;;
    esac
}

# Backup command handler
handle_backup() {
    local backup_type="${1:-full}"
    local backup_dir="${2:-./backups}"
    local backup_name="${3:-}"
    
    milou_log "STEP" "💾 Creating system backup..."
    
    # Parse additional arguments
    shift 3 || true
    while [[ $# -gt 0 ]]; do
        case $1 in
            --type)
                backup_type="$2"
                shift 2
                ;;
            --dir|--directory)
                backup_dir="$2"
                shift 2
                ;;
            --name)
                backup_name="$2"
                shift 2
                ;;
            --help|-h)
                _show_backup_restore_help "backup"
                return 0
                ;;
            *)
                milou_log "WARN" "Unknown backup argument: $1"
                shift
                ;;
        esac
    done
    
    # Use modular backup function
    if command -v milou_backup_create >/dev/null 2>&1; then
        milou_backup_create "$backup_type" "$backup_dir" "$backup_name"
    else
        milou_log "ERROR" "Backup module not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize backup modules"
        return 1
    fi
}

# Restore command handler  
handle_restore() {
    local backup_file="${1:-}"
    local restore_type="${2:-full}"
    local verify_only="${3:-false}"
    
    if [[ -z "$backup_file" ]]; then
        milou_log "ERROR" "Backup file is required for restore"
        _show_backup_restore_help "restore"
        return 1
    fi
    
    # Parse additional arguments
    shift 3 || true
    while [[ $# -gt 0 ]]; do
        case $1 in
            --type)
                restore_type="$2"
                shift 2
                ;;
            --verify-only)
                verify_only="true"
                shift
                ;;
            --help|-h)
                _show_backup_restore_help "restore"
                return 0
                ;;
            *)
                milou_log "WARN" "Unknown restore argument: $1"
                shift
                ;;
        esac
    done
    
    milou_log "STEP" "📁 Restoring from backup: $backup_file"
    
    # Use modular restore function
    if command -v milou_restore_from_backup >/dev/null 2>&1; then
        milou_restore_from_backup "$backup_file" "$restore_type" "$verify_only"
    else
        milou_log "ERROR" "Restore module not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize restore modules"
        return 1
    fi
}

# List backups command handler
handle_list_backups() {
    local backup_dir="${1:-./backups}"
    
    milou_log "STEP" "📋 Listing available backups..."
    
    # Use modular backup list function
    if command -v milou_backup_list >/dev/null 2>&1; then
        milou_backup_list "$backup_dir"
    else
        milou_log "ERROR" "Backup module not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize backup modules"
        return 1
    fi
}

# =============================================================================
# CLEAN PUBLIC API - Export only essential functions
# =============================================================================

# Main command handlers (3 exports - CLEAN PUBLIC API)
export -f handle_backup                 # Backup command handler
export -f handle_restore                # Restore command handler
export -f handle_list_backups           # List backups handler

# Internal functions are NOT exported (marked with _ prefix)
# This keeps the namespace clean and makes it clear what's public vs internal 