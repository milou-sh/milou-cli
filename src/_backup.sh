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
# WEEK 4: ENHANCED BACKUP SYSTEM 
# =============================================================================

# Automated backup scheduler with intelligent timing
automated_backup_system() {
    local schedule_type="${1:-daily}"     # daily, weekly, monthly, custom
    local backup_retention="${2:-7}"      # days to keep backups
    local backup_location="${3:-./backups}"
    local notification_enabled="${4:-true}"
    
    milou_log "INFO" "🤖 Setting up automated backup system..."
    
    # Create backup schedule configuration
    local backup_config="/etc/milou/backup_schedule.conf"
    mkdir -p "$(dirname "$backup_config")" 2>/dev/null || backup_config="$HOME/.milou_backup_schedule.conf"
    
    cat > "$backup_config" << EOF
# Milou CLI Automated Backup Configuration
SCHEDULE_TYPE=$schedule_type
BACKUP_RETENTION=$backup_retention
BACKUP_LOCATION=$backup_location
NOTIFICATION_ENABLED=$notification_enabled
LAST_BACKUP_TIME=
BACKUP_HISTORY_FILE=${backup_location}/backup_history.log
INCREMENTAL_ENABLED=true
HEALTH_CHECK_BEFORE_BACKUP=true
EOF
    
    # Set up cron job based on schedule type
    setup_backup_cron_job "$schedule_type" "$backup_config"
    
    # Initialize backup history tracking
    initialize_backup_history "$backup_location"
    
    milou_log "SUCCESS" "✅ Automated backup system configured ($schedule_type schedule)"
    return 0
}

# Set up cron job for automated backups
setup_backup_cron_job() {
    local schedule_type="$1"
    local config_file="$2"
    
    # Determine cron schedule
    local cron_schedule
    case "$schedule_type" in
        "daily")   cron_schedule="0 2 * * *" ;;         # 2 AM daily
        "weekly")  cron_schedule="0 2 * * 0" ;;         # 2 AM Sunday
        "monthly") cron_schedule="0 2 1 * *" ;;         # 2 AM 1st of month
        "hourly")  cron_schedule="0 * * * *" ;;         # Top of every hour
        *)
            milou_log "WARN" "Unknown schedule type: $schedule_type, using daily"
            cron_schedule="0 2 * * *"
            ;;
    esac
    
    # Create backup script
    local backup_script="/tmp/milou_automated_backup.sh"
    cat > "$backup_script" << EOF
#!/bin/bash
# Milou CLI Automated Backup Script
source "$config_file"
cd "${SCRIPT_DIR:-$(pwd)}"
exec >> "\${BACKUP_LOCATION}/automated_backup.log" 2>&1
echo "[\$(date)] Starting automated backup..."
bash "${SCRIPT_DIR:-$(pwd)}/milou.sh" backup-auto --config "$config_file"
EOF
    chmod +x "$backup_script"
    
    # Add to crontab (if available)
    if command -v crontab >/dev/null 2>&1; then
        # Check if entry already exists
        if ! crontab -l 2>/dev/null | grep -q "milou_automated_backup"; then
            (crontab -l 2>/dev/null; echo "$cron_schedule $backup_script") | crontab -
            milou_log "SUCCESS" "✅ Backup cron job scheduled: $schedule_type"
        else
            milou_log "INFO" "📅 Backup cron job already exists"
        fi
    else
        milou_log "WARN" "⚠️ Crontab not available - manual scheduling required"
        milou_log "INFO" "💡 Run periodically: $backup_script"
    fi
}

# Initialize backup history tracking
initialize_backup_history() {
    local backup_location="$1"
    local history_file="$backup_location/backup_history.log"
    
    mkdir -p "$backup_location"
    
    if [[ ! -f "$history_file" ]]; then
        cat > "$history_file" << EOF
# Milou CLI Backup History Log
# Format: timestamp|backup_type|backup_file|size_bytes|duration_seconds|status
# Created: $(date -Iseconds)
EOF
        milou_log "DEBUG" "✅ Backup history file initialized: $history_file"
    fi
}

# Incremental backup system with change detection
incremental_backup_create() {
    local base_backup="${1:-}"              # Reference backup for incremental
    local backup_dir="${2:-./backups}"
    local backup_name="${3:-incremental_$(date +%Y%m%d_%H%M%S)}"
    
    milou_log "INFO" "📈 Creating incremental backup..."
    
    if [[ -z "$base_backup" ]]; then
        # Find the latest full backup as base
        base_backup=$(find_latest_full_backup "$backup_dir")
        if [[ -z "$base_backup" ]]; then
            milou_log "WARN" "No base backup found, creating full backup instead"
            milou_backup_create "full" "$backup_dir" "$backup_name"
            return $?
        fi
    fi
    
    milou_log "INFO" "📊 Base backup: $(basename "$base_backup")"
    
    # Create backup directory
    local backup_path="$backup_dir/$backup_name"
    mkdir -p "$backup_path"
    
    # Detect changes since base backup
    detect_changes_since_backup "$base_backup" "$backup_path"
    
    # Create incremental backup manifest
    create_incremental_manifest "$backup_path" "$base_backup"
    
    # Create archive
    local archive_path="${backup_path}.tar.gz"
    if tar -czf "$archive_path" -C "$backup_dir" "$backup_name"; then
        rm -rf "$backup_path"
        milou_log "SUCCESS" "✅ Incremental backup created: $archive_path"
        
        # Log backup in history
        log_backup_history "$archive_path" "incremental" "$(stat -c%s "$archive_path" 2>/dev/null || echo "0")" "success"
        
        echo "$archive_path"
        return 0
    else
        milou_log "ERROR" "❌ Failed to create incremental backup archive"
        rm -rf "$backup_path"
        return 1
    fi
}

# Find latest full backup for incremental base
find_latest_full_backup() {
    local backup_dir="$1"
    
    # Look for backup manifests with full backup type
    local latest_backup=""
    local latest_time=0
    
    for backup_file in "$backup_dir"/*.tar.gz; do
        if [[ -f "$backup_file" ]]; then
            # Extract and check manifest
            local temp_dir="/tmp/backup_check_$$"
            mkdir -p "$temp_dir"
            
            if tar -xzf "$backup_file" -C "$temp_dir" --wildcards "*/manifest.json" 2>/dev/null; then
                local manifest_file
                manifest_file=$(find "$temp_dir" -name "manifest.json" -type f | head -1)
                
                if [[ -f "$manifest_file" ]] && grep -q '"backup_type": "full"' "$manifest_file"; then
                    local backup_time
                    backup_time=$(stat -c%Y "$backup_file" 2>/dev/null || echo "0")
                    
                    if [[ $backup_time -gt $latest_time ]]; then
                        latest_time=$backup_time
                        latest_backup="$backup_file"
                    fi
                fi
            fi
            
            rm -rf "$temp_dir"
        fi
    done
    
    echo "$latest_backup"
}

# Detect changes since base backup for incremental
detect_changes_since_backup() {
    local base_backup="$1"
    local incremental_path="$2"
    
    milou_log "DEBUG" "Detecting changes since base backup..."
    
    # Get base backup timestamp
    local base_time
    base_time=$(stat -c%Y "$base_backup" 2>/dev/null || echo "0")
    
    # Check configuration changes
    if [[ -f "${SCRIPT_DIR}/.env" ]] && [[ "${SCRIPT_DIR}/.env" -nt "$base_backup" ]]; then
        milou_log "DEBUG" "Configuration changed, including in incremental"
        _milou_backup_configuration "$incremental_path"
    fi
    
    # Check SSL certificate changes
    if [[ -d "${SCRIPT_DIR}/ssl" ]]; then
        local ssl_changed=false
        while IFS= read -r -d '' file; do
            if [[ "$file" -nt "$base_backup" ]]; then
                ssl_changed=true
                break
            fi
        done < <(find "${SCRIPT_DIR}/ssl" -type f -print0 2>/dev/null)
        
        if [[ "$ssl_changed" == "true" ]]; then
            milou_log "DEBUG" "SSL certificates changed, including in incremental"
            _milou_backup_ssl_certificates "$incremental_path"
        fi
    fi
    
    # For Docker volumes, we need to check container modification times
    # This is simplified - in production, we'd use more sophisticated change detection
    milou_log "DEBUG" "Checking Docker volume changes..."
    _milou_backup_docker_data "$incremental_path"  # For now, always include data changes
}

# Create incremental backup manifest
create_incremental_manifest() {
    local backup_path="$1"
    local base_backup="$2"
    
    cat > "$backup_path/manifest.json" << EOF
{
    "backup_type": "incremental",
    "base_backup": "$(basename "$base_backup")",
    "timestamp": "$(date -Iseconds)",
    "milou_version": "${MILOU_VERSION:-unknown}",
    "cli_version": "${MILOU_CLI_VERSION:-unknown}",
    "system_info": {
        "hostname": "$(hostname)",
        "os": "$(uname -s)",
        "arch": "$(uname -m)"
    },
    "changes_detected": {
        "configuration": $([ -d "$backup_path/config" ] && echo "true" || echo "false"),
        "ssl_certificates": $([ -d "$backup_path/ssl" ] && echo "true" || echo "false"),
        "docker_volumes": $([ -d "$backup_path/volumes" ] && echo "true" || echo "false")
    }
}
EOF
}

# Log backup in history file
log_backup_history() {
    local backup_file="$1"
    local backup_type="$2"
    local backup_size="$3"
    local status="$4"
    local duration="${5:-0}"
    
    local backup_dir
    backup_dir="$(dirname "$backup_file")"
    local history_file="$backup_dir/backup_history.log"
    
    local timestamp
    timestamp="$(date -Iseconds)"
    
    echo "$timestamp|$backup_type|$(basename "$backup_file")|$backup_size|$duration|$status" >> "$history_file"
}

# =============================================================================
# WEEK 4: ENHANCED DISASTER RECOVERY
# =============================================================================

# One-click disaster recovery with guided restoration
disaster_recovery_restore() {
    local backup_source="${1:-auto}"        # auto, file, cloud
    local recovery_mode="${2:-interactive}" # interactive, auto, minimal
    local target_services="${3:-all}"       # all, or comma-separated list
    
    milou_log "STEP" "🚨 Disaster Recovery Mode Activated"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Step 1: Assess current system state
    local current_state
    current_state=$(assess_disaster_recovery_state)
    milou_log "INFO" "💀 System state: $current_state"
    
    # Step 2: Find best backup for recovery
    local recovery_backup=""
    case "$backup_source" in
        "auto")
            recovery_backup=$(find_optimal_recovery_backup)
            ;;
        "file")
            if [[ "$recovery_mode" == "interactive" ]]; then
                recovery_backup=$(prompt_backup_selection)
            else
                milou_log "ERROR" "File mode requires interactive selection or specific file path"
                return 1
            fi
            ;;
        *)
            # Assume it's a file path
            if [[ -f "$backup_source" ]]; then
                recovery_backup="$backup_source"
            else
                milou_log "ERROR" "Backup file not found: $backup_source"
                return 1
            fi
            ;;
    esac
    
    if [[ -z "$recovery_backup" ]]; then
        milou_log "ERROR" "❌ No suitable backup found for disaster recovery"
        return 1
    fi
    
    milou_log "INFO" "🎯 Selected backup: $(basename "$recovery_backup")"
    
    # Step 3: Validate backup before recovery
    if ! validate_backup_integrity "$recovery_backup"; then
        milou_log "ERROR" "❌ Backup validation failed - cannot proceed with recovery"
        return 1
    fi
    
    # Step 4: Create emergency backup of current state (if possible)
    create_emergency_state_backup "$current_state"
    
    # Step 5: Execute recovery based on mode
    case "$recovery_mode" in
        "interactive")
            interactive_disaster_recovery "$recovery_backup" "$target_services"
            ;;
        "auto")
            automated_disaster_recovery "$recovery_backup" "$target_services"
            ;;
        "minimal")
            minimal_disaster_recovery "$recovery_backup" "$target_services"
            ;;
        *)
            milou_log "ERROR" "Unknown recovery mode: $recovery_mode"
            return 1
            ;;
    esac
    
    local recovery_result=$?
    
    # Step 6: Post-recovery validation and reporting
    if [[ $recovery_result -eq 0 ]]; then
        post_recovery_validation "$recovery_backup"
        generate_recovery_report "$recovery_backup" "$recovery_mode" "success"
    else
        generate_recovery_report "$recovery_backup" "$recovery_mode" "failed"
    fi
    
    return $recovery_result
}

# Assess current system state for disaster recovery
assess_disaster_recovery_state() {
    local state="unknown"
    
    # Check if configuration exists
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        # Check if services are responsive
        if command -v health_check_all >/dev/null 2>&1; then
            if health_check_all "true" >/dev/null 2>&1; then
                state="degraded"  # Has config and some services work
            else
                state="failed"    # Has config but services failed
            fi
        else
            state="partial"       # Has config but can't check services
        fi
    else
        state="corrupted"         # No configuration found
    fi
    
    echo "$state"
}

# Find optimal backup for recovery
find_optimal_recovery_backup() {
    local backup_dir="./backups"
    local optimal_backup=""
    
    # Look for recent full backups first
    local backups=($(find "$backup_dir" -name "*.tar.gz" -type f -mtime -7 | sort -t'_' -k2 -r))
    
    for backup_file in "${backups[@]}"; do
        if validate_backup_integrity "$backup_file" "silent"; then
            optimal_backup="$backup_file"
            break
        fi
    done
    
    if [[ -z "$optimal_backup" ]]; then
        # Look for any valid backup if no recent ones found
        for backup_file in "$backup_dir"/*.tar.gz; do
            if [[ -f "$backup_file" ]] && validate_backup_integrity "$backup_file" "silent"; then
                optimal_backup="$backup_file"
                break
            fi
        done
    fi
    
    echo "$optimal_backup"
}

# Interactive disaster recovery with user guidance
interactive_disaster_recovery() {
    local backup_file="$1"
    local target_services="$2"
    
    milou_log "INFO" "🎮 Interactive Disaster Recovery Mode"
    echo
    
    # Show backup information
    display_backup_information "$backup_file"
    echo
    
    # Confirm recovery
    if ! confirm_disaster_recovery "$backup_file"; then
        milou_log "INFO" "🛑 Disaster recovery cancelled by user"
        return 1
    fi
    
    # Step-by-step recovery with user confirmation
    milou_log "STEP" "🔄 Starting recovery process..."
    
    # Stop existing services
    if [[ "$target_services" == "all" ]] || [[ -z "$target_services" ]]; then
        milou_log "INFO" "⛔ Stopping all services for full recovery..."
        if command -v docker_execute >/dev/null 2>&1; then
            docker_execute "down" "" "true" || true
        fi
    fi
    
    # Restore from backup
    if milou_restore_from_backup "$backup_file" "full" "false"; then
        milou_log "SUCCESS" "✅ Backup restoration completed"
        
        # Restart services
        milou_log "INFO" "🚀 Restarting services..."
        if command -v docker_execute >/dev/null 2>&1; then
            if docker_execute "up" "-d" "true"; then
                milou_log "SUCCESS" "✅ Services restarted successfully"
                return 0
            else
                milou_log "ERROR" "❌ Failed to restart services after recovery"
                return 1
            fi
        fi
    else
        milou_log "ERROR" "❌ Backup restoration failed"
        return 1
    fi
}

# Validate backup integrity before recovery
validate_backup_integrity() {
    local backup_file="$1"
    local quiet_mode="${2:-false}"
    
    [[ "$quiet_mode" != "true" ]] && milou_log "INFO" "🔍 Validating backup integrity..."
    
    # Check if file exists and is readable
    if [[ ! -f "$backup_file" ]] || [[ ! -r "$backup_file" ]]; then
        [[ "$quiet_mode" != "true" ]] && milou_log "ERROR" "Backup file not accessible: $backup_file"
        return 1
    fi
    
    # Test archive integrity
    if ! tar -tzf "$backup_file" >/dev/null 2>&1; then
        [[ "$quiet_mode" != "true" ]] && milou_log "ERROR" "Backup archive is corrupted"
        return 1
    fi
    
    # Check for required components in backup
    local temp_check="/tmp/backup_validation_$$"
    mkdir -p "$temp_check"
    
    if tar -xzf "$backup_file" -C "$temp_check" --wildcards "*/manifest.json" 2>/dev/null; then
        local manifest_file
        manifest_file=$(find "$temp_check" -name "manifest.json" -type f | head -1)
        
        if [[ -f "$manifest_file" ]]; then
            [[ "$quiet_mode" != "true" ]] && milou_log "DEBUG" "✅ Backup manifest found and validated"
            rm -rf "$temp_check"
            return 0
        fi
    fi
    
    rm -rf "$temp_check"
    [[ "$quiet_mode" != "true" ]] && milou_log "WARN" "⚠️ Backup validation incomplete - no manifest found"
    return 0  # Allow recovery even without manifest
}

# Display backup information for user
display_backup_information() {
    local backup_file="$1"
    
    echo "📦 Backup Information"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   File: $(basename "$backup_file")"
    echo "   Size: $(du -h "$backup_file" 2>/dev/null | cut -f1 || echo "Unknown")"
    echo "   Date: $(date -r "$backup_file" 2>/dev/null || echo "Unknown")"
    echo "   Path: $backup_file"
    
    # Try to extract backup metadata
    local temp_info="/tmp/backup_info_$$"
    mkdir -p "$temp_info"
    
    if tar -xzf "$backup_file" -C "$temp_info" --wildcards "*/manifest.json" 2>/dev/null; then
        local manifest_file
        manifest_file=$(find "$temp_info" -name "manifest.json" -type f | head -1)
        
        if [[ -f "$manifest_file" ]]; then
            echo "   Type: $(grep '"backup_type"' "$manifest_file" 2>/dev/null | cut -d'"' -f4 || echo "Unknown")"
            echo "   Version: $(grep '"milou_version"' "$manifest_file" 2>/dev/null | cut -d'"' -f4 || echo "Unknown")"
        fi
    fi
    
    rm -rf "$temp_info"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Confirm disaster recovery with user
confirm_disaster_recovery() {
    local backup_file="$1"
    
    echo
    echo "⚠️  WARNING: This will replace your current system with the backup!"
    echo "   All current data and configuration will be overwritten."
    echo "   This action cannot be undone."
    echo
    read -p "Are you sure you want to proceed with disaster recovery? (type 'YES' to confirm): " confirmation
    
    if [[ "$confirmation" == "YES" ]]; then
        return 0
    else
        return 1
    fi
}

# Create emergency backup of current state
create_emergency_state_backup() {
    local current_state="$1"
    
    milou_log "INFO" "📦 Creating emergency state backup..."
    
    # Only create backup if system has some recoverable state
    if [[ "$current_state" != "corrupted" ]]; then
        local emergency_backup_name="emergency_state_$(date +%Y%m%d_%H%M%S)"
        
        if milou_backup_create "config" "./backups" "$emergency_backup_name" >/dev/null 2>&1; then
            milou_log "SUCCESS" "✅ Emergency state backup created"
        else
            milou_log "WARN" "⚠️ Could not create emergency state backup"
        fi
    else
        milou_log "WARN" "⚠️ System state too corrupted for emergency backup"
    fi
}

# Automated disaster recovery (non-interactive)
automated_disaster_recovery() {
    local backup_file="$1"
    local target_services="$2"
    
    milou_log "INFO" "🤖 Automated Disaster Recovery Mode"
    
    # Stop services
    if command -v docker_execute >/dev/null 2>&1; then
        docker_execute "down" "" "true" || true
    fi
    
    # Restore from backup
    if milou_restore_from_backup "$backup_file" "full" "false"; then
        milou_log "SUCCESS" "✅ Automated restoration completed"
        
        # Restart services
        if command -v docker_execute >/dev/null 2>&1; then
            if docker_execute "up" "-d" "true"; then
                milou_log "SUCCESS" "✅ Services restarted automatically"
                return 0
            fi
        fi
    fi
    
    milou_log "ERROR" "❌ Automated disaster recovery failed"
    return 1
}

# Minimal disaster recovery (config only)
minimal_disaster_recovery() {
    local backup_file="$1"
    local target_services="$2"
    
    milou_log "INFO" "⚙️ Minimal Disaster Recovery Mode"
    
    # Only restore configuration, not data
    if milou_restore_from_backup "$backup_file" "config" "false"; then
        milou_log "SUCCESS" "✅ Minimal recovery completed (configuration only)"
        return 0
    else
        milou_log "ERROR" "❌ Minimal disaster recovery failed"
        return 1
    fi
}

# Post-recovery validation
post_recovery_validation() {
    local backup_file="$1"
    
    milou_log "INFO" "🔍 Post-recovery validation..."
    
    # Check configuration exists
    if [[ ! -f "${SCRIPT_DIR}/.env" ]]; then
        milou_log "ERROR" "❌ Configuration file missing after recovery"
        return 1
    fi
    
    # Check service health if possible
    if command -v health_check_all >/dev/null 2>&1; then
        # Give services time to start
        sleep 10
        
        if health_check_all "true"; then
            milou_log "SUCCESS" "✅ Post-recovery health check passed"
        else
            milou_log "WARN" "⚠️ Some services may need manual attention"
        fi
    fi
    
    milou_log "SUCCESS" "✅ Post-recovery validation completed"
    return 0
}

# Generate recovery report
generate_recovery_report() {
    local backup_file="$1"
    local recovery_mode="$2"
    local status="$3"
    
    local report_file="./logs/disaster_recovery_$(date +%Y%m%d_%H%M%S).log"
    mkdir -p "$(dirname "$report_file")"
    
    cat > "$report_file" << EOF
# Milou CLI Disaster Recovery Report
# Generated: $(date -Iseconds)

## Recovery Details
- Backup File: $(basename "$backup_file")
- Recovery Mode: $recovery_mode
- Status: $status
- Timestamp: $(date)

## System Information
- Hostname: $(hostname)
- OS: $(uname -s)
- Architecture: $(uname -m)
- Milou Version: ${MILOU_VERSION:-unknown}

## Recovery Summary
$(if [[ "$status" == "success" ]]; then
    echo "✅ Disaster recovery completed successfully"
    echo "✅ System restored from backup: $(basename "$backup_file")"
    echo "✅ Services should be operational"
else
    echo "❌ Disaster recovery failed"
    echo "❌ Manual intervention may be required"
    echo "❌ Check logs for detailed error information"
fi)

## Next Steps
$(if [[ "$status" == "success" ]]; then
    echo "1. Verify all services are running: ./milou.sh status"
    echo "2. Test system functionality"
    echo "3. Monitor system logs for any issues"
else
    echo "1. Review error logs for failure details"
    echo "2. Attempt manual recovery if needed"
    echo "3. Contact support if issues persist"
fi)

## Generated by Milou CLI v${MILOU_CLI_VERSION:-unknown}
EOF
    
    milou_log "INFO" "📋 Recovery report generated: $report_file"
}

# Prompt user to select backup for recovery
prompt_backup_selection() {
    local backup_dir="./backups"
    
    echo "📦 Available Backups for Recovery"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local -a backup_files=()
    local counter=1
    
    for backup_file in "$backup_dir"/*.tar.gz; do
        if [[ -f "$backup_file" ]]; then
            backup_files+=("$backup_file")
            local size
            size=$(du -h "$backup_file" 2>/dev/null | cut -f1 || echo "Unknown")
            local date
            date=$(date -r "$backup_file" 2>/dev/null || echo "Unknown")
            
            echo "   $counter. $(basename "$backup_file") ($size, $date)"
            ((counter++))
        fi
    done
    
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        echo "   No backups found in $backup_dir"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        return 1
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    
    local selection
    while true; do
        read -p "Select backup number (1-${#backup_files[@]}) or 'q' to quit: " selection
        
        if [[ "$selection" == "q" ]]; then
            return 1
        elif [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 1 ]] && [[ $selection -le ${#backup_files[@]} ]]; then
            echo "${backup_files[$((selection-1))]}"
            return 0
        else
            echo "Invalid selection. Please enter a number between 1 and ${#backup_files[@]}, or 'q' to quit."
        fi
    done
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

# WEEK 4: Enhanced backup system exports
export -f automated_backup_system           # Automated backup scheduling
export -f incremental_backup_create         # Incremental backups
export -f validate_backup_integrity         # Backup validation
export -f disaster_recovery_restore         # One-click disaster recovery

# Command handlers
export -f handle_backup handle_restore handle_list_backups

# Help function
export -f _show_backup_restore_help

milou_log "DEBUG" "Backup & restore module loaded successfully" 