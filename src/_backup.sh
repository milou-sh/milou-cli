#!/bin/bash

# =============================================================================
# Simple Backup Module for Milou CLI
# Clean, minimal backup system using tar archives
# =============================================================================

# Module guard to prevent multiple loading
if [[ "${MILOU_BACKUP_MODULE_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_BACKUP_MODULE_LOADED="true"

# Load dependencies
source "${BASH_SOURCE[0]%/*}/_core.sh" || return 1

# =============================================================================
# Simple Backup Functions
# =============================================================================

# Create a complete backup of all Milou data
milou_backup_create() {
    local backup_name="${1:-milou_backup_$(date +%Y%m%d_%H%M%S)}"
    local backup_dir="${2:-./backups}"
    
    milou_log "STEP" "📦 Creating Milou backup: $backup_name"
    
    # Create backup directory
    mkdir -p "$backup_dir"
    # Make backup file path absolute to avoid issues with cd
    local backup_file="$(cd "$backup_dir" && pwd)/${backup_name}.tar.gz"
    
    # Create temporary directory for staging
    local temp_dir
    temp_dir=$(mktemp -d)
    local staging_dir="$temp_dir/milou_backup"
    mkdir -p "$staging_dir"
    
    # Backup configuration files
    _backup_config "$staging_dir" || { rm -rf "$temp_dir"; return 1; }
    
    # Backup Docker volumes
    _backup_volumes "$staging_dir" || { rm -rf "$temp_dir"; return 1; }
    
    # Create manifest
    _create_backup_manifest "$staging_dir"
    
    # Create final tar archive
    milou_log "INFO" "📦 Creating backup archive..."
    if (cd "$temp_dir" && tar -czf "$backup_file" milou_backup/); then
        rm -rf "$temp_dir"
        milou_log "SUCCESS" "✅ Backup created: $backup_file"
        echo "$backup_file"
        return 0
    else
        rm -rf "$temp_dir"
        milou_log "ERROR" "Failed to create backup archive"
        return 1
    fi
}

# Restore from backup
milou_backup_restore() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        milou_log "ERROR" "Backup file not found: $backup_file"
        return 1
    fi
    
    milou_log "STEP" "📥 Restoring from backup: $(basename "$backup_file")"
    
    # Create temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Extract backup
    milou_log "INFO" "📦 Extracting backup archive..."
    if tar -xzf "$backup_file" -C "$temp_dir"; then
        local restore_dir="$temp_dir/milou_backup"
        
        # Stop services before restore
        milou_log "INFO" "⏹️ Stopping services for restore..."
        docker compose down 2>/dev/null || true
        
        # Restore configuration
        _restore_config "$restore_dir" || { rm -rf "$temp_dir"; return 1; }
        
        # Restore volumes
        _restore_volumes "$restore_dir" || { rm -rf "$temp_dir"; return 1; }
        
        rm -rf "$temp_dir"
        milou_log "SUCCESS" "✅ Restore completed successfully"
        milou_log "INFO" "💡 Run 'milou start' to start services"
        return 0
    else
        rm -rf "$temp_dir"
        milou_log "ERROR" "Failed to extract backup archive"
        return 1
    fi
}

# List available backups
milou_backup_list() {
    local backup_dir="${1:-./backups}"
    
    if [[ ! -d "$backup_dir" ]]; then
        milou_log "INFO" "No backup directory found: $backup_dir"
        return 0
    fi
    
    milou_log "INFO" "📋 Available backups in $backup_dir:"
    
    local found_backups=false
    while IFS= read -r -d '' backup_file; do
        found_backups=true
        local filename=$(basename "$backup_file")
        local size=$(du -h "$backup_file" | cut -f1)
        local date=$(date -r "$backup_file" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
        
        milou_log "INFO" "  📦 $filename ($size) - $date"
    done < <(find "$backup_dir" -name "*.tar.gz" -type f -print0 2>/dev/null | sort -z)
    
    if [[ "$found_backups" == "false" ]]; then
        milou_log "INFO" "  No backups found"
    fi
}

# =============================================================================
# Internal Helper Functions
# =============================================================================

# Backup configuration files
_backup_config() {
    local staging_dir="$1"
    
    milou_log "INFO" "📋 Backing up configuration..."
    
    local config_dir="$staging_dir/config"
    mkdir -p "$config_dir"
    
    # Backup .env file
    if [[ -f ".env" ]]; then
        cp ".env" "$config_dir/"
        milou_log "DEBUG" "✅ Environment file backed up"
    fi
    
    # Backup docker-compose files
    if [[ -d "static" ]]; then
        cp -r "static" "$config_dir/"
        milou_log "DEBUG" "✅ Docker compose files backed up"
    fi
    
    # Backup SSL certificates
    if [[ -d "ssl" ]] && [[ -n "$(ls -A ssl 2>/dev/null)" ]]; then
        cp -r "ssl" "$config_dir/"
        milou_log "DEBUG" "✅ SSL certificates backed up"
    fi
    
    milou_log "SUCCESS" "✅ Configuration backup completed"
    return 0
}

# Backup all Docker volumes using a clever tar method
_backup_volumes() {
    local staging_dir="$1"
    
    milou_log "INFO" "🐳 Backing up Docker volumes..."
    
    # Check if Docker is available
    if ! command -v docker >/dev/null 2>&1; then
        milou_log "WARN" "⚠️ Docker not available - skipping volume backup"
        return 0
    fi
    
    local volumes_dir="$staging_dir/volumes"
    mkdir -p "$volumes_dir"
    
    # Get all Milou-related volumes using project label
    local volumes
    if volumes=$(docker volume ls --filter "label=project=milou" --format "{{.Name}}" 2>/dev/null); then
        if [[ -n "$volumes" ]]; then
            for volume in $volumes; do
                milou_log "DEBUG" "📦 Backing up volume: $volume"
                
                # Use a temporary alpine container to create tar archive
                # Mount volumes_dir as absolute path to avoid path issues
                local abs_volumes_dir="$(cd "$(dirname "$volumes_dir")" && pwd)/$(basename "$volumes_dir")"
                if docker run --rm \
                    -v "$volume:/source:ro" \
                    -v "$abs_volumes_dir:/backup" \
                    alpine:latest \
                    sh -c "cd /source && tar -czf /backup/${volume}.tar.gz ." 2>/dev/null; then
                    milou_log "DEBUG" "✅ Volume backed up: $volume"
                else
                    milou_log "WARN" "⚠️ Failed to backup volume: $volume"
                fi
            done
            milou_log "SUCCESS" "✅ Docker volumes backup completed"
        else
            milou_log "INFO" "ℹ️ No Milou volumes found to backup"
        fi
    else
        milou_log "WARN" "⚠️ Could not list Docker volumes"
    fi
    
    return 0
}

# Create backup manifest with metadata
_create_backup_manifest() {
    local staging_dir="$1"
    
    cat > "$staging_dir/BACKUP_INFO" << EOF
# Milou Backup Information
# Generated on $(date)

BACKUP_VERSION=1.0
BACKUP_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
MILOU_VERSION=$(cat VERSION 2>/dev/null || echo "unknown")
SYSTEM_INFO=$(uname -a)

# Contents:
$(find "$staging_dir" -type f | sort | sed 's|'"$staging_dir"'/||')
EOF
    
    milou_log "DEBUG" "✅ Backup manifest created"
}

# Restore configuration files
_restore_config() {
    local restore_dir="$1"
    
    milou_log "INFO" "📋 Restoring configuration..."
    
    local config_dir="$restore_dir/config"
    
    # Restore .env file
    if [[ -f "$config_dir/.env" ]]; then
        cp "$config_dir/.env" "./"
        milou_log "DEBUG" "✅ Environment file restored"
    fi
    
    # Restore docker-compose files
    if [[ -d "$config_dir/static" ]]; then
        rm -rf "static"
        cp -r "$config_dir/static" "./"
        milou_log "DEBUG" "✅ Docker compose files restored"
    fi
    
    # Restore SSL certificates
    if [[ -d "$config_dir/ssl" ]]; then
        rm -rf "ssl"
        cp -r "$config_dir/ssl" "./"
        milou_log "DEBUG" "✅ SSL certificates restored"
    fi
    
    milou_log "SUCCESS" "✅ Configuration restore completed"
    return 0
}

# Restore Docker volumes
_restore_volumes() {
    local restore_dir="$1"
    
    milou_log "INFO" "🐳 Restoring Docker volumes..."
    
    local volumes_dir="$restore_dir/volumes"
    
    if [[ ! -d "$volumes_dir" ]]; then
        milou_log "INFO" "ℹ️ No volumes to restore"
        return 0
    fi
    
    # Find all volume archives
    for volume_archive in "$volumes_dir"/*.tar.gz; do
        if [[ -f "$volume_archive" ]]; then
            local volume_name=$(basename "$volume_archive" .tar.gz)
            
            milou_log "DEBUG" "📦 Restoring volume: $volume_name"
            
            # Create volume if it doesn't exist
            docker volume create "$volume_name" >/dev/null 2>&1
            
            # Restore volume content using temporary container
            if docker run --rm \
                -v "$volume_name:/target" \
                -v "$(pwd):/backup" \
                alpine:latest \
                sh -c "cd /target && tar -xzf /backup/$volume_archive" 2>/dev/null; then
                milou_log "DEBUG" "✅ Volume restored: $volume_name"
            else
                milou_log "WARN" "⚠️ Failed to restore volume: $volume_name"
            fi
        fi
    done
    
    milou_log "SUCCESS" "✅ Docker volumes restore completed"
    return 0
}

# Export functions
export -f milou_backup_create
export -f milou_backup_restore  
export -f milou_backup_list

# =============================================================================
# CLI Command Handlers (Expected by main CLI)
# =============================================================================

# Main backup command handler
handle_backup() {
    local subcommand="${1:-create}"
    shift || true
    
    case "$subcommand" in
        create|backup)
            milou_backup_create "$@"
            ;;
        list|--list)
            milou_backup_list "$@"
            ;;
        --help|-h|help)
            show_backup_help
            ;;
        *)
            # Default to create with the subcommand as backup name
            milou_backup_create "$subcommand" "$@"
            ;;
    esac
}

# Main restore command handler  
handle_restore() {
    local backup_file="$1"
    
    if [[ -z "$backup_file" ]]; then
        milou_log "ERROR" "Please specify a backup file to restore"
        milou_log "INFO" "Usage: milou restore <backup_file>"
        milou_log "INFO" "Available backups:"
        milou_backup_list
        return 1
    fi
    
    milou_backup_restore "$backup_file"
}

# Show backup help
show_backup_help() {
    echo "📦 Backup System"
    echo "================"
    echo ""
    echo "BACKUP COMMANDS:"
    echo "  milou backup                Create backup with auto-generated name"
    echo "  milou backup <name>         Create backup with custom name"  
    echo "  milou backup list           List available backups"
    echo ""
    echo "RESTORE COMMANDS:"
    echo "  milou restore <file>        Restore from backup file"
    echo ""
    echo "Examples:"
    echo "  milou backup"
    echo "  milou backup my_important_backup"
    echo "  milou backup list"
    echo "  milou restore backups/milou_backup_20241201_143022.tar.gz"
    echo ""
    echo "Backups include:"
    echo "  • Configuration files (.env, docker-compose files)"
    echo "  • SSL certificates"
    echo "  • Docker volumes with application data"
}

# Export command handlers
export -f handle_backup
export -f handle_restore
export -f show_backup_help

milou_log "DEBUG" "📦 Simple backup module loaded" 