#!/bin/bash

# =============================================================================
# Milou CLI Backup Core Module
# Extracted from monolithic system.sh for better organization
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Create comprehensive system backup
milou_backup_create() {
    local backup_type="${1:-full}"
    local backup_dir="${2:-./backups}"
    local backup_name="${3:-milou_backup_$(date +%Y%m%d_%H%M%S)}"
    
    milou_log "STEP" "📦 Creating $backup_type backup: $backup_name"
    
    # Create backup directory
    mkdir -p "$backup_dir"
    local backup_path="$backup_dir/$backup_name"
    mkdir -p "$backup_path"
    
    case "$backup_type" in
        "full")
            _milou_backup_configuration "$backup_path"
            _milou_backup_ssl_certificates "$backup_path"  
            _milou_backup_docker_data "$backup_path"
            _milou_backup_database "$backup_path"
            ;;
        "config")
            _milou_backup_configuration "$backup_path"
            ;;
        "data")
            _milou_backup_docker_data "$backup_path"
            _milou_backup_database "$backup_path"
            ;;
        "ssl")
            _milou_backup_ssl_certificates "$backup_path"
            ;;
        *)
            milou_log "ERROR" "Invalid backup type: $backup_type"
            return 1
            ;;
    esac
    
    # Create backup manifest
    _milou_backup_create_manifest "$backup_path" "$backup_type"
    
    # Create archive
    local archive_path="${backup_path}.tar.gz"
    if tar -czf "$archive_path" -C "$backup_dir" "$backup_name"; then
        rm -rf "$backup_path"
        milou_log "SUCCESS" "✅ Backup created: $archive_path"
        echo "$archive_path"
        return 0
    else
        milou_log "ERROR" "Failed to create backup archive"
        return 1
    fi
}

# Backup configuration files
_milou_backup_configuration() {
    local backup_path="$1"
    
    milou_log "INFO" "📋 Backing up configuration..."
    
    local config_dir="$backup_path/config"
    mkdir -p "$config_dir"
    
    # Backup environment files
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        cp "$SCRIPT_DIR/.env" "$config_dir/"
    fi
    
    # Backup Docker Compose files
    if [[ -d "$SCRIPT_DIR/static" ]]; then
        cp -r "$SCRIPT_DIR/static" "$config_dir/"
    fi
    
    # Backup SSL configuration
    if [[ -f "$SCRIPT_DIR/ssl/.ssl_info" ]]; then
        mkdir -p "$config_dir/ssl"
        cp "$SCRIPT_DIR/ssl/.ssl_info" "$config_dir/ssl/"
    fi
    
    milou_log "SUCCESS" "✅ Configuration backed up"
}

# Backup SSL certificates
_milou_backup_ssl_certificates() {
    local backup_path="$1"
    
    milou_log "INFO" "🔐 Backing up SSL certificates..."
    
    local ssl_backup_dir="$backup_path/ssl"
    mkdir -p "$ssl_backup_dir"
    
    # Backup from multiple possible locations
    for ssl_dir in "$SCRIPT_DIR/ssl" "./ssl" "/etc/ssl/milou"; do
        if [[ -d "$ssl_dir" ]] && [[ -n "$(ls -A "$ssl_dir" 2>/dev/null)" ]]; then
            cp -r "$ssl_dir"/* "$ssl_backup_dir/" 2>/dev/null || true
        fi
    done
    
    if [[ -n "$(ls -A "$ssl_backup_dir" 2>/dev/null)" ]]; then
        milou_log "SUCCESS" "✅ SSL certificates backed up"
    else
        milou_log "WARN" "⚠️ No SSL certificates found to backup"
    fi
}

# Backup Docker data and volumes
_milou_backup_docker_data() {
    local backup_path="$1"
    
    milou_log "INFO" "🐳 Backing up Docker volumes..."
    
    local volumes_dir="$backup_path/volumes"
    mkdir -p "$volumes_dir"
    
    # Get list of Milou volumes
    local volumes
    if volumes=$(docker volume ls --filter "name=static_" --format "{{.Name}}" 2>/dev/null); then
        for volume in $volumes; do
            milou_log "DEBUG" "Backing up volume: $volume"
            
            # Create volume backup using a temporary container
            docker run --rm \
                -v "$volume:/source:ro" \
                -v "$(realpath "$volumes_dir"):/backup" \
                alpine:latest \
                tar -czf "/backup/${volume}.tar.gz" -C /source . 2>/dev/null || {
                milou_log "WARN" "Failed to backup volume: $volume"
            }
        done
        milou_log "SUCCESS" "✅ Docker volumes backed up"
    else
        milou_log "WARN" "⚠️ No Docker volumes found to backup"
    fi
}

# Backup database
_milou_backup_database() {
    local backup_path="$1"
    
    milou_log "INFO" "🗄️ Backing up database..."
    
    local db_dir="$backup_path/database"
    mkdir -p "$db_dir"
    
    # Check if database container is running
    if docker ps --filter "name=static-database" --format "{{.Names}}" | grep -q "static-database"; then
        # Get database credentials from environment
        local db_name="${POSTGRES_DB:-milou_database}"
        local db_user="${POSTGRES_USER:-milou_user}"
        local db_password="${POSTGRES_PASSWORD:-}"
        
        if [[ -n "$db_password" ]]; then
            # Create database dump
            if docker exec static-database pg_dump -U "$db_user" -d "$db_name" > "$db_dir/database_dump.sql" 2>/dev/null; then
                milou_log "SUCCESS" "✅ Database backed up"
            else
                milou_log "WARN" "⚠️ Failed to backup database"
            fi
        else
            milou_log "WARN" "⚠️ Database password not available for backup"
        fi
    else
        milou_log "WARN" "⚠️ Database container not running, skipping database backup"
    fi
}

# Create backup manifest
_milou_backup_create_manifest() {
    local backup_path="$1"
    local backup_type="$2"
    
    local manifest_file="$backup_path/backup_manifest.json"
    
    cat > "$manifest_file" << EOF
{
    "backup_info": {
        "type": "$backup_type",
        "created_at": "$(date -Iseconds)",
        "created_by": "Milou CLI v${SCRIPT_VERSION:-unknown}",
        "hostname": "$(hostname)",
        "script_path": "$SCRIPT_DIR"
    },
    "contents": {
        "configuration": $([ -d "$backup_path/config" ] && echo "true" || echo "false"),
        "ssl_certificates": $([ -d "$backup_path/ssl" ] && echo "true" || echo "false"),
        "docker_volumes": $([ -d "$backup_path/volumes" ] && echo "true" || echo "false"),
        "database_dump": $([ -f "$backup_path/database/database_dump.sql" ] && echo "true" || echo "false")
    },
    "environment": {
        "docker_version": "$(docker --version 2>/dev/null || echo 'not available')",
        "compose_version": "$(docker compose version 2>/dev/null || echo 'not available')"
    }
}
EOF
    
    milou_log "DEBUG" "Backup manifest created"
}

# List available backups
milou_backup_list() {
    local backup_dir="${1:-./backups}"
    
    if [[ ! -d "$backup_dir" ]]; then
        milou_log "WARN" "No backup directory found: $backup_dir"
        return 1
    fi
    
    milou_log "INFO" "📋 Available backups in $backup_dir:"
    
    local found_backups=false
    for backup_file in "$backup_dir"/*.tar.gz; do
        if [[ -f "$backup_file" ]]; then
            found_backups=true
            local filename=$(basename "$backup_file")
            local size=$(ls -lh "$backup_file" | awk '{print $5}')
            local date=$(ls -l "$backup_file" | awk '{print $6, $7, $8}')
            
            echo "  📦 $filename ($size) - $date"
        fi
    done
    
    if [[ "$found_backups" == "false" ]]; then
        milou_log "INFO" "No backup files found"
    fi
}

# =============================================================================
# CLEAN PUBLIC API - Export only essential functions
# =============================================================================

# Main backup functions (2 exports - CLEAN PUBLIC API)
export -f milou_backup_create      # Primary backup function
export -f milou_backup_list        # List backups

# Internal functions are NOT exported (marked with _ prefix)
# This keeps the namespace clean and makes it clear what's public vs internal 