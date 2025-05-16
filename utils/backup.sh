#!/bin/bash

# Backup and restore utility functions

# Create a backup of the application data
create_backup() {
    echo "Creating a backup of Milou data..."
    
    local timestamp=$(date +%Y%m%d%H%M%S)
    local backup_dir="${BACKUP_DIR}"
    local backup_file="${backup_dir}/milou_backup_${timestamp}.tar.gz"
    local temp_dir="/tmp/milou_backup_${timestamp}"
    
    # Create temporary directory
    mkdir -p "${temp_dir}" || {
        echo "Error: Failed to create temporary directory."
        return 1
    }
    
    # Check if services are running
    if docker compose -f "${SCRIPT_DIR}/static/docker-compose.yml" ps | grep "Up" &>/dev/null; then
        echo "Services are running. Backing up database..."
        
        # Backup PostgreSQL database
        echo "Backing up PostgreSQL database..."
        docker compose -f "${SCRIPT_DIR}/static/docker-compose.yml" exec -T db pg_dumpall -c -U postgres > "${temp_dir}/database.sql" || {
            echo "Error: Failed to back up database."
            rm -rf "${temp_dir}"
            return 1
        }
    else
        echo "Warning: Services are not running. Database backup will not be included."
    fi
    
    # Backup configuration files
    echo "Backing up configuration files..."
    cp "${SCRIPT_DIR}/.env" "${temp_dir}/" || {
        echo "Warning: Failed to back up .env file."
    }
    
    # Backup SSL certificates
    local ssl_path=$(get_config_value "SSL_CERT_PATH")
    if [ -n "$ssl_path" ] && [ -d "$ssl_path" ]; then
        echo "Backing up SSL certificates..."
        mkdir -p "${temp_dir}/ssl"
        
        # Only copy .crt and .key files
        if [ -f "${ssl_path}/milou.crt" ]; then
            cp "${ssl_path}/milou.crt" "${temp_dir}/ssl/" || {
                echo "Warning: Failed to back up SSL certificate."
            }
        fi
        
        if [ -f "${ssl_path}/milou.key" ]; then
            cp "${ssl_path}/milou.key" "${temp_dir}/ssl/" || {
                echo "Warning: Failed to back up SSL key."
            }
        fi
    fi
    
    # Backup persistent volumes data (if needed)
    # This is a placeholder, as backing up Docker volumes is complex
    # and varies based on the specific requirements.
    echo "Note: Docker volumes are not included in this backup."
    
    # Create compressed archive
    echo "Creating backup archive..."
    tar -czf "${backup_file}" -C "/tmp" "milou_backup_${timestamp}" || {
        echo "Error: Failed to create backup archive."
        rm -rf "${temp_dir}"
        return 1
    }
    
    # Clean up
    rm -rf "${temp_dir}"
    
    echo "Backup created successfully: ${backup_file}"
    echo "Backup size: $(du -h "${backup_file}" | cut -f1)"
    
    return 0
}

# Restore from a backup
restore_backup() {
    local backup_file="$1"
    
    # Check if the backup file exists
    if [ ! -f "$backup_file" ]; then
        echo "Error: Backup file does not exist: $backup_file"
        return 1
    fi
    
    echo "Restoring from backup: $backup_file"
    
    local temp_dir="/tmp/milou_restore_$(date +%Y%m%d%H%M%S)"
    
    # Create temporary directory
    mkdir -p "${temp_dir}" || {
        echo "Error: Failed to create temporary directory."
        return 1
    }
    
    # Extract backup archive
    echo "Extracting backup archive..."
    tar -xzf "$backup_file" -C "${temp_dir}" || {
        echo "Error: Failed to extract backup archive."
        rm -rf "${temp_dir}"
        return 1
    }
    
    # Find the backup directory within the extracted contents
    local backup_dir=$(find "${temp_dir}" -type d -name "milou_backup_*" | head -n 1)
    if [ -z "$backup_dir" ]; then
        echo "Error: Invalid backup format."
        rm -rf "${temp_dir}"
        return 1
    fi
    
    # Check if services are running and stop them
    if docker compose -f "${SCRIPT_DIR}/static/docker-compose.yml" ps | grep "Up" &>/dev/null; then
        echo "Stopping services..."
        stop_services
    fi
    
    # Restore configuration files
    if [ -f "${backup_dir}/.env" ]; then
        echo "Restoring configuration files..."
        cp "${backup_dir}/.env" "${SCRIPT_DIR}/.env" || {
            echo "Warning: Failed to restore .env file."
        }
    fi
    
    # Restore SSL certificates
    if [ -d "${backup_dir}/ssl" ]; then
        echo "Restoring SSL certificates..."
        local ssl_path=$(get_config_value "SSL_CERT_PATH")
        
        if [ -z "$ssl_path" ]; then
            ssl_path="./ssl"
            update_config_value "SSL_CERT_PATH" "${ssl_path}"
        fi
        
        # Create SSL directory if it doesn't exist
        mkdir -p "${ssl_path}" || {
            echo "Error: Failed to create SSL directory."
            rm -rf "${temp_dir}"
            return 1
        }
        
        # Restore certificate and key
        if [ -f "${backup_dir}/ssl/milou.crt" ]; then
            cp "${backup_dir}/ssl/milou.crt" "${ssl_path}/" || {
                echo "Warning: Failed to restore SSL certificate."
            }
        fi
        
        if [ -f "${backup_dir}/ssl/milou.key" ]; then
            cp "${backup_dir}/ssl/milou.key" "${ssl_path}/" || {
                echo "Warning: Failed to restore SSL key."
            }
        fi
    fi
    
    # Start services
    echo "Starting services..."
    start_services
    
    # Restore database if a dump exists
    if [ -f "${backup_dir}/database.sql" ]; then
        echo "Restoring database..."
        cat "${backup_dir}/database.sql" | docker compose -f "${SCRIPT_DIR}/static/docker-compose.yml" exec -T db psql -U postgres || {
            echo "Error: Failed to restore database."
            rm -rf "${temp_dir}"
            return 1
        }
    fi
    
    # Clean up
    rm -rf "${temp_dir}"
    
    echo "Restoration completed successfully."
    return 0
}

# Schedule automated backups
schedule_backup() {
    local frequency="$1"  # daily, weekly, monthly
    
    echo "Setting up scheduled backups (${frequency})..."
    
    # Create backup script
    cat > "${CONFIG_DIR}/scheduled_backup.sh" << EOF
#!/bin/bash

# Automated backup script for Milou
SCRIPT_DIR="${SCRIPT_DIR}"
CONFIG_DIR="${CONFIG_DIR}"
BACKUP_DIR="${BACKUP_DIR}"

# Source utility functions
source "\${SCRIPT_DIR}/utils/configure.sh"
source "\${SCRIPT_DIR}/utils/backup.sh"

# Create backup
create_backup

# Clean up old backups
find "\${BACKUP_DIR}" -name "milou_backup_*.tar.gz" -type f -mtime +30 -delete
EOF
    
    chmod +x "${CONFIG_DIR}/scheduled_backup.sh"
    
    # Set up cron job based on frequency
    case "$frequency" in
        daily)
            cron_time="0 2 * * *"  # 2 AM every day
            ;;
        weekly)
            cron_time="0 2 * * 0"  # 2 AM every Sunday
            ;;
        monthly)
            cron_time="0 2 1 * *"  # 2 AM on the 1st of each month
            ;;
        *)
            echo "Error: Invalid backup frequency. Valid options: daily, weekly, monthly."
            return 1
            ;;
    esac
    
    # Add cron job
    (crontab -l 2>/dev/null || echo "") | grep -v "${CONFIG_DIR}/scheduled_backup.sh" | \
    { cat; echo "${cron_time} ${CONFIG_DIR}/scheduled_backup.sh > ${CONFIG_DIR}/backup.log 2>&1"; } | \
    crontab -
    
    echo "Scheduled backups configured successfully (${frequency})."
    return 0
} 