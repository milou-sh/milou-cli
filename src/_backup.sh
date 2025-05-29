#!/bin/bash

# =============================================================================
# Backup & Restore Module for Milou CLI
# Consolidated from lib/backup/core.sh, lib/restore/core.sh, commands/backup.sh
# =============================================================================

# Module guard to prevent multiple loading
if [[ "${MILOU_BACKUP_MODULE_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_BACKUP_MODULE_LOADED="true"

# Load dependencies
if [[ -f "${BASH_SOURCE[0]%/*}/_core.sh" ]]; then
    source "${BASH_SOURCE[0]%/*}/_core.sh" || return 1
fi

if [[ -f "${BASH_SOURCE[0]%/*}/_docker.sh" ]]; then
    source "${BASH_SOURCE[0]%/*}/_docker.sh" || return 1
fi

# =============================================================================
# Backup Core Functions (from lib/backup/core.sh)
# =============================================================================

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
    
    # Execute backup based on type
    case "$backup_type" in
        "full")
            _milou_backup_configuration "$backup_path" || return 1
            _milou_backup_ssl_certificates "$backup_path" || return 1
            _milou_backup_docker_data "$backup_path" || return 1
            _milou_backup_database "$backup_path" || return 1
            ;;
        "config")
            _milou_backup_configuration "$backup_path" || return 1
            ;;
        "data")
            _milou_backup_docker_data "$backup_path" || return 1
            _milou_backup_database "$backup_path" || return 1
            ;;
        "ssl")
            _milou_backup_ssl_certificates "$backup_path" || return 1
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
        rm -rf "$backup_path"
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
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        cp "${SCRIPT_DIR}/.env" "$config_dir/"
        milou_log "DEBUG" "Environment file backed up"
    fi
    
    # Backup Docker Compose files
    if [[ -d "${SCRIPT_DIR}/static" ]]; then
        cp -r "${SCRIPT_DIR}/static" "$config_dir/"
        milou_log "DEBUG" "Docker Compose files backed up"
    fi
    
    # Backup SSL configuration
    if [[ -f "${SCRIPT_DIR}/ssl/.ssl_info" ]]; then
        mkdir -p "$config_dir/ssl"
        cp "${SCRIPT_DIR}/ssl/.ssl_info" "$config_dir/ssl/"
        milou_log "DEBUG" "SSL configuration backed up"
    fi
    
    # Backup version information
    if [[ -f "${SCRIPT_DIR}/VERSION" ]]; then
        cp "${SCRIPT_DIR}/VERSION" "$config_dir/"
        milou_log "DEBUG" "Version information backed up"
    fi
    
    milou_log "SUCCESS" "✅ Configuration backed up"
    return 0
}

# Backup SSL certificates
_milou_backup_ssl_certificates() {
    local backup_path="$1"
    
    milou_log "INFO" "🔐 Backing up SSL certificates..."
    
    local ssl_backup_dir="$backup_path/ssl"
    mkdir -p "$ssl_backup_dir"
    
    local ssl_found=false
    
    # Backup from multiple possible locations
    for ssl_dir in "${SCRIPT_DIR}/ssl" "./ssl" "/etc/ssl/milou"; do
        if [[ -d "$ssl_dir" ]] && [[ -n "$(ls -A "$ssl_dir" 2>/dev/null)" ]]; then
            cp -r "$ssl_dir"/* "$ssl_backup_dir/" 2>/dev/null || true
            ssl_found=true
            milou_log "DEBUG" "SSL certificates backed up from: $ssl_dir"
        fi
    done
    
    if [[ "$ssl_found" == "true" ]]; then
        milou_log "SUCCESS" "✅ SSL certificates backed up"
    else
        milou_log "WARN" "⚠️ No SSL certificates found to backup"
    fi
    
    return 0
}

# Backup Docker data and volumes
_milou_backup_docker_data() {
    local backup_path="$1"
    
    milou_log "INFO" "🐳 Backing up Docker volumes..."
    
    local volumes_dir="$backup_path/volumes"
    mkdir -p "$volumes_dir"
    
    # Check Docker availability
    if ! command -v docker >/dev/null 2>&1; then
        milou_log "WARN" "⚠️ Docker not available - skipping volume backup"
        return 0
    fi
    
    # Get list of Milou volumes with multiple naming patterns
    local volume_patterns=("static_" "milou-static_" "milou_")
    local volumes_found=false
    
    for pattern in "${volume_patterns[@]}"; do
        local volumes
        if volumes=$(docker volume ls --filter "name=${pattern}" --format "{{.Name}}" 2>/dev/null); then
            for volume in $volumes; do
                milou_log "DEBUG" "Backing up volume: $volume"
                volumes_found=true
                
                # Create volume backup using a temporary container
                if docker run --rm \
                    -v "$volume:/source:ro" \
                    -v "$(realpath "$volumes_dir"):/backup" \
                    alpine:latest \
                    tar -czf "/backup/${volume}.tar.gz" -C /source . 2>/dev/null; then
                    milou_log "DEBUG" "✅ Volume backed up: $volume"
                else
                    milou_log "WARN" "Failed to backup volume: $volume"
                fi
            done
        fi
    done
    
    if [[ "$volumes_found" == "true" ]]; then
        milou_log "SUCCESS" "✅ Docker volumes backed up"
    else
        milou_log "WARN" "⚠️ No Docker volumes found to backup"
    fi
    
    return 0
}

# Backup database
_milou_backup_database() {
    local backup_path="$1"
    
    milou_log "INFO" "🗄️ Backing up database..."
    
    local db_dir="$backup_path/database"
    mkdir -p "$db_dir"
    
    # Check Docker availability
    if ! command -v docker >/dev/null 2>&1; then
        milou_log "WARN" "⚠️ Docker not available - skipping database backup"
        return 0
    fi
    
    # Check multiple possible database container names
    local db_containers=("milou-database" "static-database" "milou-static-database")
    local db_container=""
    
    for container in "${db_containers[@]}"; do
        if docker ps --filter "name=$container" --format "{{.Names}}" | grep -q "$container"; then
            db_container="$container"
            break
        fi
    done
    
    if [[ -z "$db_container" ]]; then
        milou_log "WARN" "⚠️ Database container not running, skipping database backup"
        return 0
    fi
    
    # Get database credentials from environment
    local db_name="${POSTGRES_DB:-milou_database}"
    local db_user="${POSTGRES_USER:-milou_user}"
    local db_password="${POSTGRES_PASSWORD:-}"
    
    if [[ -n "$db_password" ]]; then
        # Create database dump
        if docker exec "$db_container" pg_dump -U "$db_user" -d "$db_name" > "$db_dir/database_dump.sql" 2>/dev/null; then
            milou_log "SUCCESS" "✅ Database backed up"
        else
            milou_log "WARN" "⚠️ Failed to backup database"
        fi
    else
        milou_log "WARN" "⚠️ Database password not available for backup"
    fi
    
    return 0
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
        "script_path": "${SCRIPT_DIR:-$(pwd)}"
    },
    "contents": {
        "configuration": $([ -d "$backup_path/config" ] && echo "true" || echo "false"),
        "ssl_certificates": $([ -d "$backup_path/ssl" ] && echo "true" || echo "false"),
        "docker_volumes": $([ -d "$backup_path/volumes" ] && echo "true" || echo "false"),
        "database_dump": $([ -f "$backup_path/database/database_dump.sql" ] && echo "true" || echo "false")
    },
    "environment": {
        "domain": "${DOMAIN:-unknown}",
        "ssl_mode": "${SSL_MODE:-unknown}",
        "docker_project": "${COMPOSE_PROJECT_NAME:-unknown}"
    },
    "restore_instructions": {
        "command": "./milou.sh restore ${backup_path##*/}.tar.gz",
        "requirements": ["Docker", "Docker Compose", "Bash"]
    }
}
EOF

    milou_log "DEBUG" "Backup manifest created"
    return 0
}

# List available backups
milou_backup_list() {
    local backup_dir="${1:-./backups}"
    
    milou_log "INFO" "📋 Available backups in: $backup_dir"
    
    if [[ ! -d "$backup_dir" ]]; then
        milou_log "WARN" "⚠️ Backup directory does not exist: $backup_dir"
        return 1
    fi
    
    local backups
    backups=$(find "$backup_dir" -name "*.tar.gz" -type f 2>/dev/null | sort -r)
    
    if [[ -z "$backups" ]]; then
        milou_log "INFO" "No backups found in $backup_dir"
        return 0
    fi
    
    echo
    printf "%-30s %-15s %-10s\n" "BACKUP NAME" "DATE" "SIZE"
    printf "%-30s %-15s %-10s\n" "$(printf '%*s' 30 '' | tr ' ' '-')" "$(printf '%*s' 15 '' | tr ' ' '-')" "$(printf '%*s' 10 '' | tr ' ' '-')"
    
    while IFS= read -r backup_file; do
        local basename=$(basename "$backup_file")
        local date_str=$(stat -c %y "$backup_file" 2>/dev/null | cut -d' ' -f1)
        local size=$(du -h "$backup_file" 2>/dev/null | cut -f1)
        
        printf "%-30s %-15s %-10s\n" "${basename}" "${date_str}" "${size}"
    done <<< "$backups"
    
    echo
    milou_log "INFO" "💡 Restore with: ./milou.sh restore <backup_name>"
    return 0
}

# =============================================================================
# Restore Core Functions (from lib/restore/core.sh)
# =============================================================================

# Restore from backup
milou_restore_from_backup() {
    local backup_file="${1:-}"
    local restore_type="${2:-full}"
    local verify_only="${3:-false}"
    
    if [[ -z "$backup_file" ]]; then
        milou_log "ERROR" "Backup file is required"
        return 1
    fi
    
    if [[ ! -f "$backup_file" ]]; then
        milou_log "ERROR" "Backup file not found: $backup_file"
        return 1
    fi
    
    milou_log "STEP" "📁 Restoring from backup: $(basename "$backup_file")"
    
    # Extract backup to temporary directory
    local temp_dir="/tmp/milou_restore_$$"
    mkdir -p "$temp_dir"
    
    milou_log "INFO" "📦 Extracting backup..."
    if ! tar -xzf "$backup_file" -C "$temp_dir"; then
        milou_log "ERROR" "Failed to extract backup file"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Find backup directory (should be only one)
    local backup_dir
    backup_dir=$(find "$temp_dir" -maxdepth 1 -type d ! -path "$temp_dir" | head -1)
    
    if [[ -z "$backup_dir" ]]; then
        milou_log "ERROR" "No backup directory found in archive"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Validate backup structure
    if ! _milou_restore_validate_backup "$backup_dir"; then
        milou_log "ERROR" "Backup validation failed"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # If verify-only mode, exit after validation
    if [[ "$verify_only" == "true" ]]; then
        milou_log "SUCCESS" "✅ Backup verification completed successfully"
        rm -rf "$temp_dir"
        return 0
    fi
    
    # Perform restore based on type
    case "$restore_type" in
        "full")
            _milou_restore_configuration "$backup_dir" || return 1
            _milou_restore_ssl_certificates "$backup_dir" || return 1
            _milou_restore_docker_data "$backup_dir" || return 1
            ;;
        "config")
            _milou_restore_configuration "$backup_dir" || return 1
            ;;
        "ssl")
            _milou_restore_ssl_certificates "$backup_dir" || return 1
            ;;
        "data")
            _milou_restore_docker_data "$backup_dir" || return 1
            ;;
        *)
            milou_log "ERROR" "Invalid restore type: $restore_type"
            rm -rf "$temp_dir"
            return 1
            ;;
    esac
    
    # Cleanup
    rm -rf "$temp_dir"
    
    milou_log "SUCCESS" "✅ Restore completed successfully"
    milou_log "INFO" "💡 You may need to restart services: ./milou.sh restart"
    
    return 0
}

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
    if [[ -f "$backup_dir/config/.env" ]]; then
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
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        cp "${SCRIPT_DIR}/.env" "${SCRIPT_DIR}/.env.backup.$(date +%s)"
        milou_log "DEBUG" "Current configuration backed up"
    fi
    
    # Restore main environment file
    if [[ -f "$backup_dir/config/.env" ]]; then
        cp "$backup_dir/config/.env" "${SCRIPT_DIR}/.env"
        chmod 600 "${SCRIPT_DIR}/.env"
        milou_log "DEBUG" "Main environment file restored"
    fi
    
    # Restore Docker Compose files
    if [[ -d "$backup_dir/config/static" ]]; then
        mkdir -p "${SCRIPT_DIR}/static"
        cp -r "$backup_dir/config/static"/* "${SCRIPT_DIR}/static/" 2>/dev/null || true
        milou_log "DEBUG" "Docker Compose files restored"
    fi
    
    # Restore SSL configuration
    if [[ -f "$backup_dir/config/ssl/.ssl_info" ]]; then
        mkdir -p "${SCRIPT_DIR}/ssl"
        cp "$backup_dir/config/ssl/.ssl_info" "${SCRIPT_DIR}/ssl/"
        milou_log "DEBUG" "SSL configuration restored"
    fi
    
    # Restore version information
    if [[ -f "$backup_dir/config/VERSION" ]]; then
        cp "$backup_dir/config/VERSION" "${SCRIPT_DIR}/"
        milou_log "DEBUG" "Version information restored"
    fi
    
    milou_log "SUCCESS" "✅ Configuration restored"
    return 0
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
    if [[ -d "${SCRIPT_DIR}/ssl" ]] && [[ -n "$(ls -A "${SCRIPT_DIR}/ssl" 2>/dev/null)" ]]; then
        local ssl_backup_dir="${SCRIPT_DIR}/ssl.backup.$(date +%s)"
        cp -r "${SCRIPT_DIR}/ssl" "$ssl_backup_dir"
        milou_log "DEBUG" "Current SSL certificates backed up to: $ssl_backup_dir"
    fi
    
    # Restore SSL certificates
    mkdir -p "${SCRIPT_DIR}/ssl"
    cp -r "$backup_dir/ssl"/* "${SCRIPT_DIR}/ssl/"
    
    # Update permissions
    chmod 600 "${SCRIPT_DIR}/ssl"/*.key 2>/dev/null || true
    chmod 644 "${SCRIPT_DIR}/ssl"/*.crt 2>/dev/null || true
    
    milou_log "SUCCESS" "✅ SSL certificates restored"
    return 0
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
    
    # Restore database first
    if [[ -f "$backup_dir/database/database_dump.sql" ]]; then
        _milou_restore_database "$backup_dir" || return 1
    fi
    
    # Restore Docker volumes
    if [[ -d "$backup_dir/volumes" ]] && [[ -n "$(ls -A "$backup_dir/volumes" 2>/dev/null)" ]]; then
        _milou_restore_volumes "$backup_dir" || return 1
    fi
    
    milou_log "SUCCESS" "✅ Docker data restored"
    return 0
}

# Restore database from backup
_milou_restore_database() {
    local backup_dir="$1"
    local dump_file="$backup_dir/database/database_dump.sql"
    
    milou_log "INFO" "🗄️ Restoring database..."
    
    # Check multiple possible database container names
    local db_containers=("milou-database" "static-database" "milou-static-database")
    local db_container=""
    
    for container in "${db_containers[@]}"; do
        if docker ps --filter "name=$container" --format "{{.Names}}" | grep -q "$container"; then
            db_container="$container"
            break
        fi
    done
    
    if [[ -z "$db_container" ]]; then
        milou_log "WARN" "Database container not running - attempting to start services"
        
        # Try to start services first
        if command -v docker_start >/dev/null 2>&1; then
            docker_start "database" >/dev/null 2>&1
            sleep 10  # Give database time to start
            
            # Check again
            for container in "${db_containers[@]}"; do
                if docker ps --filter "name=$container" --format "{{.Names}}" | grep -q "$container"; then
                    db_container="$container"
                    break
                fi
            done
        fi
        
        if [[ -z "$db_container" ]]; then
            milou_log "ERROR" "Cannot restore database - no running database container found"
            return 1
        fi
    fi
    
    # Get database credentials from restored environment
    local db_name="${POSTGRES_DB:-milou_database}"
    local db_user="${POSTGRES_USER:-milou_user}"
    
    # Restore database
    if docker exec -i "$db_container" psql -U "$db_user" -d "$db_name" < "$dump_file" 2>/dev/null; then
        milou_log "SUCCESS" "✅ Database restored"
    else
        milou_log "WARN" "⚠️ Database restore failed or partially completed"
    fi
    
    return 0
}

# Restore Docker volumes
_milou_restore_volumes() {
    local backup_dir="$1"
    
    milou_log "INFO" "📦 Restoring Docker volumes..."
    
    # Restore each volume backup
    for volume_backup in "$backup_dir/volumes"/*.tar.gz; do
        if [[ ! -f "$volume_backup" ]]; then
            continue
        fi
        
        local volume_name
        volume_name=$(basename "$volume_backup" .tar.gz)
        
        milou_log "DEBUG" "Restoring volume: $volume_name"
        
        # Remove existing volume if it exists
        docker volume rm "$volume_name" 2>/dev/null || true
        
        # Create new volume
        docker volume create "$volume_name" >/dev/null 2>&1
        
        # Restore volume data
        if docker run --rm \
            -v "$volume_name:/target" \
            -v "$(realpath "$(dirname "$volume_backup")"):/backup" \
            alpine:latest \
            tar -xzf "/backup/$(basename "$volume_backup")" -C /target 2>/dev/null; then
            milou_log "DEBUG" "✅ Volume restored: $volume_name"
        else
            milou_log "WARN" "Failed to restore volume: $volume_name"
        fi
    done
    
    milou_log "SUCCESS" "✅ Docker volumes restored"
    return 0
}

# =============================================================================
# Command Handler Functions (from commands/backup.sh)
# =============================================================================

# Show backup and restore help
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
    
    # Parse additional arguments
    shift 3 2>/dev/null || true
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
    
    milou_backup_create "$backup_type" "$backup_dir" "$backup_name"
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
    shift 3 2>/dev/null || true
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
    
    milou_restore_from_backup "$backup_file" "$restore_type" "$verify_only"
}

# List backups command handler
handle_list_backups() {
    local backup_dir="${1:-./backups}"
    milou_backup_list "$backup_dir"
}

# =============================================================================
# Module Exports
# =============================================================================

# Core backup functions
export -f milou_backup_create milou_backup_list

# Core restore functions
export -f milou_restore_from_backup

# Command handlers
export -f handle_backup handle_restore handle_list_backups

# Help function
export -f _show_backup_restore_help

milou_log "DEBUG" "Backup & restore module loaded successfully" 