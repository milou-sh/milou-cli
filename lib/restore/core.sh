#!/bin/bash

# =============================================================================
# Milou CLI Restore Core Module
# Extracted from monolithic system.sh for better organization
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Module guard to prevent multiple loading
if [[ "${MILOU_RESTORE_CORE_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_RESTORE_CORE_LOADED="true"

# Validate backup before restore
_milou_restore_validate_backup() {
    local backup_dir="$1"
    
    milou_log "INFO" "🔍 Validating backup structure..."
    
    # Check for manifest file
    local manifest_file="$backup_dir/backup_manifest.json"
    if [[ ! -f "$manifest_file" ]]; then
        # Try old format
        manifest_file="$backup_dir/backup_manifest.txt"
        if [[ ! -f "$manifest_file" ]]; then
            milou_log "WARN" "No backup manifest found - proceeding without validation"
            return 0
        fi
    fi
    
    # Basic validation - check key directories exist based on backup type
    if [[ -f "$backup_dir/config/milou.env" || -f "$backup_dir/config/.env" ]]; then
        milou_log "DEBUG" "Configuration backup detected"
    fi
    
    if [[ -d "$backup_dir/ssl" ]] && [[ -n "$(ls -A "$backup_dir/ssl" 2>/dev/null)" ]]; then
        milou_log "DEBUG" "SSL certificates backup detected"
    fi
    
    if [[ -d "$backup_dir/volumes" ]] && [[ -n "$(ls -A "$backup_dir/volumes" 2>/dev/null)" ]]; then
        milou_log "DEBUG" "Docker volumes backup detected"
    fi
    
    if [[ -f "$backup_dir/database/database_dump.sql" ]]; then
        milou_log "DEBUG" "Database backup detected"
    fi
    
    milou_log "SUCCESS" "✅ Backup validation passed"
    return 0
}

# Restore configuration files
_milou_restore_configuration() {
    local backup_dir="$1"
    
    milou_log "INFO" "📋 Restoring configuration..."
    
    # Backup current configuration before restore
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        cp "$SCRIPT_DIR/.env" "$SCRIPT_DIR/.env.backup.$(date +%s)"
        milou_log "DEBUG" "Current configuration backed up"
    fi
    
    # Restore main environment file
    if [[ -f "$backup_dir/config/milou.env" ]]; then
        cp "$backup_dir/config/milou.env" "$SCRIPT_DIR/.env"
        milou_log "DEBUG" "Main environment file restored"
    elif [[ -f "$backup_dir/config/.env" ]]; then
        cp "$backup_dir/config/.env" "$SCRIPT_DIR/.env"
        milou_log "DEBUG" "Main environment file restored (alternative path)"
    fi
    
    # Restore Docker Compose files
    if [[ -d "$backup_dir/config/static" ]]; then
        cp -r "$backup_dir/config/static"/* "$SCRIPT_DIR/static/" 2>/dev/null || true
        milou_log "DEBUG" "Docker Compose files restored"
    fi
    
    # Restore SSL configuration
    if [[ -f "$backup_dir/config/ssl/.ssl_info" ]]; then
        mkdir -p "$SCRIPT_DIR/ssl"
        cp "$backup_dir/config/ssl/.ssl_info" "$SCRIPT_DIR/ssl/"
        milou_log "DEBUG" "SSL configuration restored"
    fi
    
    milou_log "SUCCESS" "✅ Configuration restored"
}

# Restore SSL certificates
_milou_restore_ssl_certificates() {
    local backup_dir="$1"
    
    milou_log "INFO" "🔐 Restoring SSL certificates..."
    
    if [[ ! -d "$backup_dir/ssl" ]] || [[ -z "$(ls -A "$backup_dir/ssl" 2>/dev/null)" ]]; then
        milou_log "WARN" "No SSL certificates found in backup"
        return 0
    fi
    
    # Backup current certificates
    if [[ -d "$SCRIPT_DIR/ssl" ]] && [[ -n "$(ls -A "$SCRIPT_DIR/ssl" 2>/dev/null)" ]]; then
        local ssl_backup_dir="$SCRIPT_DIR/ssl.backup.$(date +%s)"
        cp -r "$SCRIPT_DIR/ssl" "$ssl_backup_dir"
        milou_log "DEBUG" "Current SSL certificates backed up to: $ssl_backup_dir"
    fi
    
    # Restore SSL certificates
    mkdir -p "$SCRIPT_DIR/ssl"
    cp -r "$backup_dir/ssl"/* "$SCRIPT_DIR/ssl/"
    
    # Update permissions
    chmod 600 "$SCRIPT_DIR/ssl"/*.key 2>/dev/null || true
    chmod 644 "$SCRIPT_DIR/ssl"/*.crt 2>/dev/null || true
    
    milou_log "SUCCESS" "✅ SSL certificates restored"
}

# Restore Docker data and volumes
_milou_restore_docker_data() {
    local backup_dir="$1"
    
    milou_log "INFO" "🐳 Restoring Docker data..."
    
    # Check if Docker is available
    if ! command -v docker >/dev/null 2>&1; then
        milou_log "WARN" "Docker not available - skipping data restore"
        return 0
    fi
    
    # Restore database
    if [[ -f "$backup_dir/database/database_dump.sql" ]]; then
        _milou_restore_database "$backup_dir"
    fi
    
    # Restore Docker volumes
    if [[ -d "$backup_dir/volumes" ]] && [[ -n "$(ls -A "$backup_dir/volumes" 2>/dev/null)" ]]; then
        _milou_restore_volumes "$backup_dir"
    fi
    
    milou_log "SUCCESS" "✅ Docker data restored"
}

# Restore database from backup
_milou_restore_database() {
    local backup_dir="$1"
    local dump_file="$backup_dir/database/database_dump.sql"
    
    milou_log "INFO" "🗄️ Restoring database..."
    
    # Check if database container is running
    if ! docker ps --filter "name=static-database" --format "{{.Names}}" | grep -q "static-database"; then
        milou_log "WARN" "Database container not running - starting it for restore"
        
        # Try to start the database container
        if command -v milou_docker_start >/dev/null 2>&1; then
            milou_docker_start database
        else
            milou_log "ERROR" "Cannot start database container for restore"
            return 1
        fi
        
        # Wait for database to be ready
        local wait_time=30
        local elapsed=0
        while [[ $elapsed -lt $wait_time ]]; do
            if docker ps --filter "name=static-database" --format "{{.Names}}" | grep -q "static-database"; then
                sleep 5  # Give it a moment to fully initialize
                break
            fi
            sleep 2
            elapsed=$((elapsed + 2))
        done
    fi
    
    # Get database credentials from restored environment
    local db_name="${POSTGRES_DB:-milou_database}"
    local db_user="${POSTGRES_USER:-milou_user}"
    
    # Restore database
    if docker exec -i static-database psql -U "$db_user" -d "$db_name" < "$dump_file" 2>/dev/null; then
        milou_log "SUCCESS" "✅ Database restored"
    else
        milou_log "WARN" "⚠️ Database restore failed or partially completed"
    fi
}

# Restore Docker volumes
_milou_restore_volumes() {
    local backup_dir="$1"
    
    milou_log "INFO" "📦 Restoring Docker volumes..."
    
    # Restore each volume backup
    for volume_backup in "$backup_dir/volumes"/*.tar.gz; do
        if [[ -f "$volume_backup" ]]; then
            local volume_name
            volume_name=$(basename "$volume_backup" .tar.gz)
            
            milou_log "DEBUG" "Restoring volume: $volume_name"
            
            # Create the volume if it doesn't exist
            docker volume create "$volume_name" >/dev/null 2>&1
            
            # Restore volume data
            docker run --rm \
                -v "$volume_name:/target" \
                -v "$(realpath "$backup_dir/volumes"):/backup:ro" \
                alpine:latest \
                sh -c "cd /target && tar -xzf /backup/$(basename "$volume_backup")" 2>/dev/null || {
                milou_log "WARN" "Failed to restore volume: $volume_name"
            }
        fi
    done
    
    milou_log "SUCCESS" "✅ Docker volumes restored"
}

# Restore system from backup
milou_restore_from_backup() {
    local backup_file="$1"
    local restore_type="${2:-full}"
    local verify_only="${3:-false}"
    
    milou_log "STEP" "📁 Restoring system from backup: $backup_file"
    
    # Validate backup file
    if [[ ! -f "$backup_file" ]]; then
        milou_log "ERROR" "Backup file not found: $backup_file"
        return 1
    fi
    
    # Create temporary restore directory
    local restore_dir="/tmp/milou_restore_$(date +%s)"
    mkdir -p "$restore_dir"
    
    # Extract backup
    milou_log "INFO" "📦 Extracting backup archive..."
    if ! tar -xzf "$backup_file" -C "$restore_dir"; then
        milou_log "ERROR" "Failed to extract backup archive"
        rm -rf "$restore_dir"
        return 1
    fi
    
    # Find the backup directory (should be only one)
    local backup_content_dir
    backup_content_dir=$(find "$restore_dir" -mindepth 1 -maxdepth 1 -type d | head -1)
    
    if [[ ! -d "$backup_content_dir" ]]; then
        milou_log "ERROR" "Invalid backup structure"
        rm -rf "$restore_dir"
        return 1
    fi
    
    # Validate backup manifest
    if ! _milou_restore_validate_backup "$backup_content_dir"; then
        milou_log "ERROR" "Backup validation failed"
        rm -rf "$restore_dir"
        return 1
    fi
    
    # If verification only, exit here
    if [[ "$verify_only" == "true" ]]; then
        milou_log "SUCCESS" "✅ Backup validation passed"
        rm -rf "$restore_dir"
        return 0
    fi
    
    # Perform restore based on type
    case "$restore_type" in
        "full")
            _milou_restore_configuration "$backup_content_dir"
            _milou_restore_ssl_certificates "$backup_content_dir"
            _milou_restore_docker_data "$backup_content_dir"
            ;;
        "config")
            _milou_restore_configuration "$backup_content_dir"
            ;;
        "data")
            _milou_restore_docker_data "$backup_content_dir"
            ;;
        "ssl")
            _milou_restore_ssl_certificates "$backup_content_dir"
            ;;
        *)
            milou_log "ERROR" "Invalid restore type: $restore_type"
            rm -rf "$restore_dir"
            return 1
            ;;
    esac
    
    # Cleanup
    rm -rf "$restore_dir"
    
    milou_log "SUCCESS" "✅ System restore completed"
    milou_log "INFO" "🔄 Please restart services to apply restored configuration"
    
    return 0
}

# List available restore points
milou_restore_list_backups() {
    local backup_dir="${1:-./backups}"
    
    if [[ ! -d "$backup_dir" ]]; then
        milou_log "WARN" "No backup directory found: $backup_dir"
        return 1
    fi
    
    milou_log "INFO" "📋 Available restore points in $backup_dir:"
    
    local found_backups=false
    for backup_file in "$backup_dir"/*.tar.gz; do
        if [[ -f "$backup_file" ]]; then
            found_backups=true
            local filename=$(basename "$backup_file")
            local size=$(ls -lh "$backup_file" | awk '{print $5}')
            local date=$(ls -l "$backup_file" | awk '{print $6, $7, $8}')
            
            echo "  📦 $filename ($size) - $date"
            
            # Try to extract backup type from manifest if possible
            local temp_dir="/tmp/milou_restore_check_$$"
            if mkdir -p "$temp_dir" && tar -xzf "$backup_file" -C "$temp_dir" 2>/dev/null; then
                local backup_content_dir
                backup_content_dir=$(find "$temp_dir" -mindepth 1 -maxdepth 1 -type d | head -1)
                if [[ -f "$backup_content_dir/backup_manifest.json" ]]; then
                    local backup_type
                    backup_type=$(grep '"type"' "$backup_content_dir/backup_manifest.json" 2>/dev/null | cut -d'"' -f4 || echo "unknown")
                    echo "    Type: $backup_type"
                fi
                rm -rf "$temp_dir"
            fi
        fi
    done
    
    if [[ "$found_backups" == "false" ]]; then
        milou_log "INFO" "No backup files found"
    fi
}

# =============================================================================
# CLEAN PUBLIC API - Export only essential functions
# =============================================================================

# Main restore functions (2 exports - CLEAN PUBLIC API)
export -f milou_restore_from_backup    # Primary restore function
export -f milou_restore_list_backups   # List restore points (alias for backup list)

# Internal functions are NOT exported (marked with _ prefix)
# This keeps the namespace clean and makes it clear what's public vs internal 