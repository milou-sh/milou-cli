#!/bin/bash

# =============================================================================
# Configuration Backup and Restore Functions for Milou CLI
# Extracted from configuration.sh for better maintainability  
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# =============================================================================
# Configuration Backup and Restore Functions
# =============================================================================

# Create a configuration backup with enhanced metadata
backup_environment_config() {
    local env_file="${SCRIPT_DIR}/.env"
    local backup_name="${1:-config_$(date +%Y%m%d_%H%M%S)}"
    local comment="${2:-Manual backup}"
    
    if [[ ! -f "$env_file" ]]; then
        log "ERROR" "Configuration file not found: $env_file"
        return 1
    fi
    
    local backup_dir="${CONFIG_DIR}/backups"
    mkdir -p "$backup_dir"
    
    local backup_path="${backup_dir}/${backup_name}.env"
    local metadata_path="${backup_dir}/${backup_name}.meta"
    
    # Create backup
    if cp "$env_file" "$backup_path"; then
        chmod 600 "$backup_path"
        
        # Create metadata file
        cat > "$metadata_path" << EOF
# Milou Configuration Backup Metadata
BACKUP_NAME=$backup_name
BACKUP_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BACKUP_COMMENT=$comment
ORIGINAL_FILE=$env_file
CLI_VERSION=${SCRIPT_VERSION:-3.0.0}
BACKUP_SIZE=$(stat -c%s "$backup_path" 2>/dev/null || stat -f%z "$backup_path" 2>/dev/null || echo "unknown")
BACKUP_CHECKSUM=$(sha256sum "$backup_path" 2>/dev/null | cut -d' ' -f1 || echo "unknown")
EOF
        chmod 600 "$metadata_path"
        
        log "SUCCESS" "Configuration backed up to: $backup_path"
        log "DEBUG" "Backup metadata saved to: $metadata_path"
        return 0
    else
        log "ERROR" "Failed to create configuration backup"
        return 1
    fi
}

# Restore configuration from backup with validation
restore_environment_config() {
    local backup_file="$1"
    local env_file="${SCRIPT_DIR}/.env"
    
    if [[ -z "$backup_file" ]]; then
        log "ERROR" "Backup file path is required"
        return 1
    fi
    
    if [[ ! -f "$backup_file" ]]; then
        log "ERROR" "Backup file not found: $backup_file"
        return 1
    fi
    
    # Validate backup file integrity if metadata exists
    local backup_name backup_meta
    backup_name=$(basename "$backup_file" .env)
    backup_meta="$(dirname "$backup_file")/${backup_name}.meta"
    
    if [[ -f "$backup_meta" ]]; then
        log "DEBUG" "Found backup metadata, validating integrity..."
        local stored_checksum current_checksum
        stored_checksum=$(grep "^BACKUP_CHECKSUM=" "$backup_meta" | cut -d'=' -f2)
        current_checksum=$(sha256sum "$backup_file" 2>/dev/null | cut -d' ' -f1 || echo "unknown")
        
        if [[ "$stored_checksum" != "unknown" && "$current_checksum" != "unknown" ]]; then
            if [[ "$stored_checksum" == "$current_checksum" ]]; then
                log "SUCCESS" "Backup integrity validation passed"
            else
                log "ERROR" "Backup integrity validation failed - file may be corrupted"
                if [[ "$FORCE" != true ]]; then
                    if ! confirm "Continue with potentially corrupted backup?" "N"; then
                        return 1
                    fi
                fi
            fi
        fi
    fi
    
    # Create a backup of current config first
    if [[ -f "$env_file" ]]; then
        backup_environment_config "pre_restore_$(date +%Y%m%d_%H%M%S)" "Automatic backup before restore"
    fi
    
    # Restore the configuration
    if cp "$backup_file" "$env_file"; then
        chmod 600 "$env_file"
        log "SUCCESS" "Configuration restored from: $backup_file"
        
        # Validate the restored configuration using centralized validation
        if command -v validate_environment_production >/dev/null 2>&1; then
            if validate_environment_production "$env_file"; then
                log "SUCCESS" "Restored configuration passed validation"
                return 0
            else
                log "WARN" "Restored configuration has validation issues"
                return 1
            fi
        else
            log "SUCCESS" "Configuration restored (validation not available)"
            return 0
        fi
    else
        log "ERROR" "Failed to restore configuration from: $backup_file"
        return 1
    fi
}

# List available configuration backups with enhanced information
list_environment_config_backups() {
    local backup_dir="${CONFIG_DIR}/backups"
    
    if [[ ! -d "$backup_dir" ]]; then
        log "INFO" "No backup directory found"
        return 0
    fi
    
    local backups=($(find "$backup_dir" -name "*.env" -type f 2>/dev/null | sort -r))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        log "INFO" "No configuration backups found"
        return 0
    fi
    
    log "INFO" "Available configuration backups:"
    echo
    
    for backup in "${backups[@]}"; do
        local basename backup_meta
        basename=$(basename "$backup" .env)
        backup_meta="$(dirname "$backup")/${basename}.meta"
        
        local size mod_time comment
        size=$(stat -c%s "$backup" 2>/dev/null || stat -f%z "$backup" 2>/dev/null || echo "?")
        mod_time=$(stat -c "%y" "$backup" 2>/dev/null | cut -d'.' -f1 || stat -f "%Sm" "$backup" 2>/dev/null || echo "unknown")
        
        # Try to get comment from metadata
        if [[ -f "$backup_meta" ]]; then
            comment=$(grep "^BACKUP_COMMENT=" "$backup_meta" 2>/dev/null | cut -d'=' -f2- || echo "No comment")
        else
            comment="No metadata"
        fi
        
        echo "  📄 $basename"
        echo "     🕒 Date: $mod_time"
        echo "     📄 Size: $size bytes"
        echo "     📝 Comment: $comment"
        echo "     📁 Path: $backup"
        echo
    done
}

# Clean old configuration backups
clean_old_environment_config_backups() {
    local retention_days="${1:-30}"
    local backup_dir="${CONFIG_DIR}/backups"
    
    if [[ ! -d "$backup_dir" ]]; then
        log "INFO" "No backup directory found"
        return 0
    fi
    
    log "STEP" "Cleaning backups older than $retention_days days..."
    
    local old_backups
    old_backups=$(find "$backup_dir" -name "*.env" -type f -mtime +${retention_days} 2>/dev/null)
    
    if [[ -z "$old_backups" ]]; then
        log "INFO" "No old backups found"
        return 0
    fi
    
    local count=0
    while IFS= read -r backup; do
        local basename
        basename=$(basename "$backup" .env)
        
        # Remove backup and metadata
        rm -f "$backup"
        rm -f "$(dirname "$backup")/${basename}.meta"
        
        log "DEBUG" "Removed old backup: $basename"
        ((count++))
    done <<< "$old_backups"
    
    log "SUCCESS" "Cleaned $count old backup(s)"
}

# =============================================================================
# Export Functions
# =============================================================================

# Backward compatibility aliases
backup_config() {
    backup_environment_config "$@"
}

restore_config() {
    restore_environment_config "$@"
}

list_config_backups() {
    list_environment_config_backups "$@"
}

clean_old_backups() {
    clean_old_environment_config_backups "$@"
}

export -f backup_environment_config
export -f restore_environment_config
export -f list_environment_config_backups
export -f clean_old_environment_config_backups
export -f backup_config
export -f restore_config
export -f list_config_backups
export -f clean_old_backups 