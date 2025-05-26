#!/bin/bash

# Enhanced backup utility functions for Milou CLI

# Create a comprehensive backup
create_backup() {
    local backup_type="${1:-full}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="milou_backup_${backup_type}_${timestamp}"
    local backup_path="${BACKUP_DIR}/${backup_name}"
    
    log "INFO" "Creating ${backup_type} backup..."
    
    # Create backup directory
    mkdir -p "$backup_path" || {
        log "ERROR" "Failed to create backup directory: $backup_path"
        return 1
    }
    
    # Backup configuration files
    log "INFO" "Backing up configuration files..."
    if ! backup_system_config "$backup_path"; then
        log "ERROR" "Failed to backup configuration"
        return 1
    fi
    
    # Backup SSL certificates
    log "INFO" "Backing up SSL certificates..."
    if ! backup_ssl "$backup_path"; then
        log "WARN" "Failed to backup SSL certificates (may not exist)"
    fi
    
    # Backup Docker volumes if services are running
    if [[ "$backup_type" == "full" ]]; then
        log "INFO" "Backing up Docker volumes..."
        if ! backup_docker_volumes "$backup_path"; then
            log "WARN" "Failed to backup Docker volumes"
        fi
        
        # Backup Docker Compose configuration
        log "INFO" "Backing up Docker Compose configuration..."
        if ! backup_docker_compose "$backup_path"; then
            log "WARN" "Failed to backup Docker Compose configuration"
        fi
    fi
    
    # Create backup metadata
    create_backup_metadata "$backup_path" "$backup_type" "$timestamp"
    
    # Compress the backup
    log "INFO" "Compressing backup..."
    local compressed_backup="${backup_path}.tar.gz"
    if tar -czf "$compressed_backup" -C "${BACKUP_DIR}" "$backup_name" 2>/dev/null; then
        rm -rf "$backup_path"
        log "INFO" "Backup created successfully: $compressed_backup"
        
        # Show backup information
        local backup_size=$(ls -lh "$compressed_backup" | awk '{print $5}')
        log "INFO" "Backup size: $backup_size"
        
        echo "$compressed_backup"
        return 0
    else
        log "ERROR" "Failed to compress backup"
        return 1
    fi
}

# Backup configuration files for system backup
backup_system_config() {
    local backup_path="$1"
    local config_backup_dir="${backup_path}/config"
    
    mkdir -p "$config_backup_dir"
    
    # Backup .env file
    if [[ -f "${ENV_FILE}" ]]; then
        cp "${ENV_FILE}" "${config_backup_dir}/" || return 1
    fi
    
    # Backup any additional configuration files
    if [[ -f "${SCRIPT_DIR}/.env.example" ]]; then
        cp "${SCRIPT_DIR}/.env.example" "${config_backup_dir}/" || true
    fi
    
    # Backup library modules
    if [[ -d "${SCRIPT_DIR}/lib" ]]; then
        cp -r "${SCRIPT_DIR}/lib" "${config_backup_dir}/" || true
    fi
    
    return 0
}

# Backup SSL certificates
backup_ssl() {
    local backup_path="$1"
    local ssl_backup_dir="${backup_path}/ssl"
    
    # Check if SSL directory exists
    local ssl_path=$(get_config_value "SSL_CERT_PATH" || echo "./ssl")
    if [[ -d "$ssl_path" ]]; then
        mkdir -p "$ssl_backup_dir"
        cp -r "$ssl_path"/* "$ssl_backup_dir/" 2>/dev/null || return 1
        return 0
    fi
    
    return 1
}

# Backup Docker volumes
backup_docker_volumes() {
    local backup_path="$1"
    local volumes_backup_dir="${backup_path}/volumes"
    
    mkdir -p "$volumes_backup_dir"
    
    # Check if Docker is accessible
    if ! docker info >/dev/null 2>&1; then
        log "WARN" "Docker not accessible, skipping volume backup"
        return 1
    fi
    
    # Get list of Docker volumes for the project
    local project_name="static"  # From docker-compose.yml
    local volumes
    
    if volumes=$(docker volume ls --filter "name=${project_name}" --format "{{.Name}}" 2>/dev/null); then
        if [[ -n "$volumes" ]]; then
            log "INFO" "Found volumes to backup: $(echo $volumes | tr '\n' ' ')"
            
            # Backup each volume
            while read -r volume; do
                if [[ -n "$volume" ]]; then
                    log "INFO" "Backing up volume: $volume"
                    backup_single_volume "$volume" "$volumes_backup_dir" || {
                        log "WARN" "Failed to backup volume: $volume"
                    }
                fi
            done <<< "$volumes"
        else
            log "INFO" "No project volumes found"
        fi
    else
        log "WARN" "Could not list Docker volumes"
        return 1
    fi
    
    return 0
}

# Backup a single Docker volume
backup_single_volume() {
    local volume_name="$1"
    local backup_dir="$2"
    local volume_backup_file="${backup_dir}/${volume_name}.tar"
    
    # Create a temporary container to access the volume
    if docker run --rm -v "${volume_name}:/volume" -v "${backup_dir}:/backup" alpine tar -cf "/backup/$(basename "$volume_backup_file")" -C /volume . 2>/dev/null; then
        log "INFO" "Volume $volume_name backed up successfully"
        return 0
    else
        log "ERROR" "Failed to backup volume: $volume_name"
        return 1
    fi
}

# Backup Docker Compose configuration
backup_docker_compose() {
    local backup_path="$1"
    local compose_backup_dir="${backup_path}/compose"
    
    mkdir -p "$compose_backup_dir"
    
    # Backup docker-compose.yml
    if [[ -f "${SCRIPT_DIR}/static/docker-compose.yml" ]]; then
        cp "${SCRIPT_DIR}/static/docker-compose.yml" "${compose_backup_dir}/" || return 1
    fi
    
    # Backup any other compose files
    find "${SCRIPT_DIR}" -name "docker-compose*.yml" -exec cp {} "${compose_backup_dir}/" \; 2>/dev/null || true
    
    return 0
}

# Create backup metadata
create_backup_metadata() {
    local backup_path="$1"
    local backup_type="$2"
    local timestamp="$3"
    local metadata_file="${backup_path}/backup_metadata.json"
    
    cat > "$metadata_file" << EOF
{
    "backup_info": {
        "version": "${VERSION:-1.1.0}",
        "type": "$backup_type",
        "timestamp": "$timestamp",
        "date_human": "$(date)",
        "hostname": "$(hostname)",
        "user": "$(whoami)"
    },
    "system_info": {
        "os": "$(uname -s)",
        "arch": "$(uname -m)",
        "kernel": "$(uname -r)"
    },
    "docker_info": {
        "docker_version": "$(docker --version 2>/dev/null || echo 'Not available')",
        "compose_version": "$(docker compose version --short 2>/dev/null || echo 'Not available')"
    },
    "backup_contents": {
        "config_files": true,
        "ssl_certificates": $([ -d "$(get_config_value "SSL_CERT_PATH" || echo "./ssl")" ] && echo "true" || echo "false"),
        "docker_volumes": $([ "$backup_type" = "full" ] && echo "true" || echo "false"),
        "compose_files": $([ "$backup_type" = "full" ] && echo "true" || echo "false")
    }
}
EOF
}

# List available backups
list_backups() {
    log "INFO" "Available backups in ${BACKUP_DIR}:"
    
    if [[ ! -d "${BACKUP_DIR}" ]]; then
        log "WARN" "Backup directory does not exist: ${BACKUP_DIR}"
        return 1
    fi
    
    local backups
    if backups=$(find "${BACKUP_DIR}" -name "milou_backup_*.tar.gz" -type f 2>/dev/null | sort -r); then
        if [[ -n "$backups" ]]; then
            printf "%-40s %-10s %-20s\n" "Backup File" "Size" "Date"
            printf "%-40s %-10s %-20s\n" "----------------------------------------" "----------" "--------------------"
            
            while read -r backup_file; do
                if [[ -n "$backup_file" ]]; then
                    local basename=$(basename "$backup_file")
                    local size=$(ls -lh "$backup_file" | awk '{print $5}')
                    local date=$(ls -l "$backup_file" | awk '{print $6, $7, $8}')
                    printf "%-40s %-10s %-20s\n" "$basename" "$size" "$date"
                fi
            done <<< "$backups"
        else
            log "INFO" "No backups found"
        fi
    else
        log "ERROR" "Failed to list backups"
        return 1
    fi
    
    return 0
}

# Restore from backup
restore_backup() {
    local backup_file="$1"
    local restore_options="${2:-config}"  # config, ssl, volumes, all
    
    if [[ ! -f "$backup_file" ]]; then
        log "ERROR" "Backup file not found: $backup_file"
        return 1
    fi
    
    log "INFO" "Restoring from backup: $(basename "$backup_file")"
    
    # Create temporary extraction directory
    local temp_dir="/tmp/milou_restore_$$"
    mkdir -p "$temp_dir" || {
        log "ERROR" "Failed to create temporary directory"
        return 1
    }
    
    # Extract backup
    log "INFO" "Extracting backup..."
    if ! tar -xzf "$backup_file" -C "$temp_dir" 2>/dev/null; then
        log "ERROR" "Failed to extract backup"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Find the extracted backup directory
    local backup_dir
    backup_dir=$(find "$temp_dir" -type d -name "milou_backup_*" | head -1)
    
    if [[ ! -d "$backup_dir" ]]; then
        log "ERROR" "Invalid backup structure"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Show backup metadata
    if [[ -f "$backup_dir/backup_metadata.json" ]]; then
        log "INFO" "Backup metadata:"
        cat "$backup_dir/backup_metadata.json" | grep -E '"(version|type|date_human)"' | sed 's/^[[:space:]]*/    /'
    fi
    
    # Confirm restore
    if ! confirm "Proceed with restore? This will overwrite existing configuration."; then
        log "INFO" "Restore cancelled"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Restore components based on options
    local restore_success=true
    
    if [[ "$restore_options" =~ (config|all) ]]; then
        restore_config "$backup_dir" || restore_success=false
    fi
    
    if [[ "$restore_options" =~ (ssl|all) ]]; then
        restore_ssl "$backup_dir" || log "WARN" "SSL restore failed or not available"
    fi
    
    if [[ "$restore_options" =~ (volumes|all) ]]; then
        restore_docker_volumes "$backup_dir" || log "WARN" "Volume restore failed or not available"
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
    
    if [[ "$restore_success" == "true" ]]; then
        log "INFO" "Restore completed successfully"
        log "INFO" "You may need to restart services: ./milou.sh restart"
        return 0
    else
        log "ERROR" "Restore completed with errors"
        return 1
    fi
}

# Restore configuration
restore_config() {
    local backup_dir="$1"
    local config_backup_dir="${backup_dir}/config"
    
    if [[ ! -d "$config_backup_dir" ]]; then
        log "ERROR" "No configuration backup found"
        return 1
    fi
    
    log "INFO" "Restoring configuration..."
    
    # Backup current configuration
    if [[ -f "${ENV_FILE}" ]]; then
        create_timestamped_backup "${ENV_FILE}" || log "WARN" "Could not backup current configuration"
    fi
    
    # Restore .env file
    if [[ -f "${config_backup_dir}/.env" ]]; then
        cp "${config_backup_dir}/.env" "${ENV_FILE}" || {
            log "ERROR" "Failed to restore .env file"
            return 1
        }
        chmod 600 "${ENV_FILE}"
        log "INFO" "Configuration restored successfully"
    else
        log "ERROR" "No .env file found in backup"
        return 1
    fi
    
    return 0
}

# Restore SSL certificates
restore_ssl() {
    local backup_dir="$1"
    local ssl_backup_dir="${backup_dir}/ssl"
    
    if [[ ! -d "$ssl_backup_dir" ]]; then
        log "WARN" "No SSL backup found"
        return 1
    fi
    
    local ssl_path=$(get_config_value "SSL_CERT_PATH" || echo "./ssl")
    
    log "INFO" "Restoring SSL certificates to $ssl_path..."
    
    # Create SSL directory
    mkdir -p "$ssl_path"
    
    # Restore SSL files
    cp -r "$ssl_backup_dir"/* "$ssl_path/" || {
        log "ERROR" "Failed to restore SSL certificates"
        return 1
    }
    
    # Set appropriate permissions
    chmod 600 "$ssl_path"/*.key 2>/dev/null || true
    chmod 644 "$ssl_path"/*.crt 2>/dev/null || true
    
    log "INFO" "SSL certificates restored successfully"
    return 0
}

# Restore Docker volumes
restore_docker_volumes() {
    local backup_dir="$1"
    local volumes_backup_dir="${backup_dir}/volumes"
    
    if [[ ! -d "$volumes_backup_dir" ]]; then
        log "WARN" "No volume backup found"
        return 1
    fi
    
    # Check if Docker is accessible
    if ! docker info >/dev/null 2>&1; then
        log "WARN" "Docker not accessible, skipping volume restore"
        return 1
    fi
    
    log "INFO" "Restoring Docker volumes..."
    
    # Stop services first
    log "INFO" "Stopping services for volume restore..."
    stop_services >/dev/null 2>&1 || true
    
    # Restore each volume
    find "$volumes_backup_dir" -name "*.tar" -type f | while read -r volume_backup; do
        local volume_name=$(basename "$volume_backup" .tar)
        log "INFO" "Restoring volume: $volume_name"
        restore_single_volume "$volume_name" "$volume_backup" || {
            log "WARN" "Failed to restore volume: $volume_name"
        }
    done
    
    log "INFO" "Volume restore completed"
    return 0
}

# Restore a single Docker volume
restore_single_volume() {
    local volume_name="$1"
    local volume_backup_file="$2"
    
    # Create volume if it doesn't exist
    docker volume create "$volume_name" >/dev/null 2>&1 || true
    
    # Restore volume contents
    if docker run --rm -v "${volume_name}:/volume" -v "$(dirname "$volume_backup_file"):/backup" alpine sh -c "cd /volume && tar -xf /backup/$(basename "$volume_backup_file")" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Clean old backups
clean_old_backups() {
    local days_to_keep="${1:-30}"
    
    log "INFO" "Cleaning backups older than $days_to_keep days..."
    
    if [[ -d "${BACKUP_DIR}" ]]; then
        local old_backups
        if old_backups=$(find "${BACKUP_DIR}" -name "milou_backup_*.tar.gz" -type f -mtime +$days_to_keep 2>/dev/null); then
            if [[ -n "$old_backups" ]]; then
                echo "$old_backups" | while read -r backup; do
                    if [[ -n "$backup" ]]; then
                        log "INFO" "Removing old backup: $(basename "$backup")"
                        rm -f "$backup"
                    fi
                done
                log "INFO" "Backup cleanup completed"
            else
                log "INFO" "No old backups to clean"
            fi
        fi
    fi
    
    return 0
} 