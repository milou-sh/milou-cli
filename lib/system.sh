#!/bin/bash

# =============================================================================
# System Management Module for Milou CLI
# Consolidated system operations: backup, environment management, and updates
# =============================================================================

# Module guard to prevent multiple loading
if [[ "${MILOU_SYSTEM_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_SYSTEM_LOADED="true"

# Ensure logging is available
if ! command -v milou_log >/dev/null 2>&1; then
    local script_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    if [[ -f "${script_dir}/lib/core/logging.sh" ]]; then
        source "${script_dir}/lib/core/logging.sh"
    else
        echo "ERROR: Logging module not available" >&2
        return 1
    fi
fi

# =============================================================================
# CLEAN PUBLIC API - Export only essential functions
# =============================================================================

# Essential system environment functions (4 exports - CLEAN PUBLIC API)
export -f milou_system_load_environment      # Load system environment
export -f milou_system_setup_environment     # Setup system environment  
export -f milou_system_cleanup_environment   # Cleanup system environment
export -f milou_system_validate_environment  # Validate system environment

# Note: Backup functions are now handled by lib/backup/core.sh and lib/restore/core.sh
# Note: Update functions are now handled by lib/update/core.sh
# Legacy functions remain in this file for backward compatibility but are NOT exported
# This prevents namespace pollution while maintaining compatibility
# Internal functions are marked with _ prefix and NOT exported

# =============================================================================
# System Backup Functions (from backup.sh)
# =============================================================================

# Create comprehensive system backup
milou_system_create_backup() {
    local backup_type="${1:-full}"  # full, config-only, data-only
    local backup_dir="${2:-./backups}"
    local backup_name="${3:-system_backup_$(date +%Y%m%d_%H%M%S)}"
    
    milou_log "STEP" "Creating system backup..."
    milou_log "INFO" "Backup type: $backup_type"
    milou_log "INFO" "Backup directory: $backup_dir"
    
    # Create backup directory structure
    mkdir -p "$backup_dir"
    local backup_path="$backup_dir/$backup_name"
    mkdir -p "$backup_path"
    
    # Backup configuration files
    if [[ "$backup_type" == "full" || "$backup_type" == "config-only" ]]; then
        milou_system_backup_configuration "$backup_path"
    fi
    
    # Backup SSL certificates
    if [[ "$backup_type" == "full" || "$backup_type" == "config-only" ]]; then
        milou_system_backup_ssl_certificates "$backup_path"
    fi
    
    # Backup Docker volumes and data
    if [[ "$backup_type" == "full" || "$backup_type" == "data-only" ]]; then
        milou_system_backup_docker_data "$backup_path"
    fi
    
    # Create backup manifest
    milou_system_create_backup_manifest "$backup_path" "$backup_type"
    
    # Compress backup
    local archive_path="${backup_dir}/${backup_name}.tar.gz"
    if tar -czf "$archive_path" -C "$backup_dir" "$backup_name"; then
        rm -rf "$backup_path"  # Remove uncompressed backup
        milou_log "SUCCESS" "✅ System backup created: $archive_path"
        return 0
    else
        milou_log "ERROR" "❌ Failed to create backup archive"
        return 1
    fi
}

# Backup configuration files
milou_system_backup_configuration() {
    local backup_path="$1"
    
    milou_log "DEBUG" "Backing up configuration files..."
    
    # Backup main configuration
    local env_file="${SCRIPT_DIR}/.env"
    if [[ -f "$env_file" ]]; then
        cp "$env_file" "$backup_path/milou.env"
        milou_log "DEBUG" "Backed up main configuration"
    fi
    
    # Backup Docker compose files
    local static_dir="${SCRIPT_DIR}/static"
    if [[ -d "$static_dir" ]]; then
        mkdir -p "$backup_path/docker"
        find "$static_dir" -name "docker-compose*.yml" -exec cp {} "$backup_path/docker/" \;
        milou_log "DEBUG" "Backed up Docker compose files"
    fi
    
    return 0
}

# Backup SSL certificates
milou_system_backup_ssl_certificates() {
    local backup_path="$1"
    
    milou_log "DEBUG" "Backing up SSL certificates..."
    
    local ssl_dir="${SCRIPT_DIR}/static/ssl"
    if [[ -d "$ssl_dir" && -f "$ssl_dir/milou.crt" ]]; then
        mkdir -p "$backup_path/ssl"
        cp -r "$ssl_dir"/* "$backup_path/ssl/"
        milou_log "DEBUG" "Backed up SSL certificates"
    else
        milou_log "DEBUG" "No SSL certificates found to backup"
    fi
    
    return 0
}

# Backup Docker volumes and data
milou_system_backup_docker_data() {
    local backup_path="$1"
    
    milou_log "DEBUG" "Backing up Docker volumes and data..."
    
    # Check if Docker services are running
    if ! docker ps --filter "name=milou" --format "{{.Names}}" | grep -q "milou"; then
        milou_log "WARN" "Docker services not running - skipping data backup"
        return 0
    fi
    
    # Backup database
    milou_system_backup_database "$backup_path"
    
    # Backup uploaded files and data volumes
    milou_system_backup_volumes "$backup_path"
    
    return 0
}

# Backup database
milou_system_backup_database() {
    local backup_path="$1"
    
    milou_log "DEBUG" "Backing up database..."
    
    # Get database credentials from environment
    local db_user db_name db_password
    local env_file="${SCRIPT_DIR}/.env"
    
    if [[ -f "$env_file" ]]; then
        db_user=$(grep "^DB_USER=" "$env_file" | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
        db_name=$(grep "^DB_NAME=" "$env_file" | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
        db_password=$(grep "^DB_PASSWORD=" "$env_file" | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    fi
    
    # Use defaults if not found
    db_user="${db_user:-milou}"
    db_name="${db_name:-milou}"
    
    # Create database backup
    local db_backup_file="$backup_path/database_backup.sql"
    if docker exec milou-database pg_dump -U "$db_user" -d "$db_name" > "$db_backup_file" 2>/dev/null; then
        milou_log "DEBUG" "Database backup created: $db_backup_file"
        return 0
    else
        milou_log "WARN" "Failed to backup database - continuing without it"
        return 1
    fi
}

# Backup Docker volumes
milou_system_backup_volumes() {
    local backup_path="$1"
    
    milou_log "DEBUG" "Backing up Docker volumes..."
    
    # Create volumes backup directory
    mkdir -p "$backup_path/volumes"
    
    # Get list of Milou-related volumes
    local volumes
    volumes=$(docker volume ls --filter "name=milou" --format "{{.Name}}")
    
    if [[ -n "$volumes" ]]; then
        while IFS= read -r volume; do
            if [[ -n "$volume" ]]; then
                milou_log "DEBUG" "Backing up volume: $volume"
                docker run --rm -v "$volume:/source" -v "$backup_path/volumes:/backup" alpine tar czf "/backup/${volume}.tar.gz" -C /source . 2>/dev/null
            fi
        done <<< "$volumes"
    else
        milou_log "DEBUG" "No Milou volumes found to backup"
    fi
    
    return 0
}

# Create backup manifest
milou_system_create_backup_manifest() {
    local backup_path="$1"
    local backup_type="$2"
    
    cat > "$backup_path/backup_manifest.txt" << EOF
Milou System Backup
==================
Created: $(date)
Backup Type: $backup_type
Backup Path: $backup_path
System: $(uname -a)

Contents:
- milou.env (Main configuration)
- docker/ (Docker compose files)
- ssl/ (SSL certificates)
- database_backup.sql (Database dump)
- volumes/ (Docker volumes)

Restore Instructions:
1. Extract this backup archive
2. Run: ./milou.sh restore "$backup_path"
3. Follow any additional restore prompts

Notes:
- This backup was created while services were $(docker ps --filter "name=milou" --format "{{.Names}}" | wc -l > 0 && echo "running" || echo "stopped")
- Restore on compatible system architecture
- Verify Docker and dependencies before restore
EOF

    milou_log "DEBUG" "Backup manifest created"
}

# Restore system from backup
milou_system_restore_backup() {
    local backup_path="$1"
    local force_restore="${2:-false}"
    
    if [[ ! -d "$backup_path" ]]; then
        # Try to extract if it's an archive
        if [[ -f "$backup_path" && "$backup_path" == *.tar.gz ]]; then
            local extract_dir=$(dirname "$backup_path")
            if tar -xzf "$backup_path" -C "$extract_dir"; then
                backup_path="${extract_dir}/$(basename "$backup_path" .tar.gz)"
                milou_log "INFO" "Extracted backup archive to: $backup_path"
            else
                milou_log "ERROR" "Failed to extract backup archive"
                return 1
            fi
        else
            milou_log "ERROR" "Backup path not found: $backup_path"
            return 1
        fi
    fi
    
    milou_log "STEP" "Restoring system from backup..."
    milou_log "INFO" "Backup path: $backup_path"
    
    # Check backup manifest
    if [[ -f "$backup_path/backup_manifest.txt" ]]; then
        milou_log "INFO" "📋 Backup Information:"
        head -10 "$backup_path/backup_manifest.txt"
        echo
    fi
    
    # Confirm restore operation
    if [[ "$force_restore" != "true" ]]; then
        echo "⚠️  WARNING: This will overwrite current configuration and data"
        echo "Continue with restore? (y/N): "
        read -r confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            milou_log "INFO" "Restore cancelled by user"
            return 0
        fi
    fi
    
    # Stop services if running
    if docker ps --filter "name=milou" --format "{{.Names}}" | grep -q "milou"; then
        milou_log "INFO" "Stopping services for restore..."
        if command -v milou_docker_stop >/dev/null 2>&1; then
            milou_docker_stop
        fi
    fi
    
    # Restore configuration
    milou_system_restore_configuration "$backup_path"
    
    # Restore SSL certificates
    milou_system_restore_ssl_certificates "$backup_path"
    
    # Restore database and volumes
    milou_system_restore_data "$backup_path"
    
    milou_log "SUCCESS" "✅ System restore completed"
    milou_log "INFO" "Start services with: ./milou.sh start"
}

# Restore configuration files
milou_system_restore_configuration() {
    local backup_path="$1"
    
    milou_log "DEBUG" "Restoring configuration files..."
    
    # Restore main configuration
    if [[ -f "$backup_path/milou.env" ]]; then
        cp "$backup_path/milou.env" "${SCRIPT_DIR}/.env"
        chmod 600 "${SCRIPT_DIR}/.env"
        milou_log "DEBUG" "Main configuration restored"
    fi
    
    # Restore Docker compose files
    if [[ -d "$backup_path/docker" ]]; then
        local static_dir="${SCRIPT_DIR}/static"
        mkdir -p "$static_dir"
        cp "$backup_path/docker"/* "$static_dir/" 2>/dev/null || true
        milou_log "DEBUG" "Docker compose files restored"
    fi
}

# Restore SSL certificates
milou_system_restore_ssl_certificates() {
    local backup_path="$1"
    
    milou_log "DEBUG" "Restoring SSL certificates..."
    
    if [[ -d "$backup_path/ssl" ]]; then
        local ssl_dir="${SCRIPT_DIR}/static/ssl"
        mkdir -p "$ssl_dir"
        cp -r "$backup_path/ssl"/* "$ssl_dir/"
        chmod 644 "$ssl_dir"/*.crt 2>/dev/null || true
        chmod 600 "$ssl_dir"/*.key 2>/dev/null || true
        milou_log "DEBUG" "SSL certificates restored"
    fi
}

# Restore database and volumes
milou_system_restore_data() {
    local backup_path="$1"
    
    milou_log "DEBUG" "Restoring database and volumes..."
    
    # Start database service if needed
    if ! docker ps --filter "name=milou-database" --format "{{.Names}}" | grep -q "milou-database"; then
        milou_log "INFO" "Starting database service for restore..."
        # Start only database service
        docker compose -f "${SCRIPT_DIR}/static/docker-compose.yml" up -d database
        sleep 10
    fi
    
    # Restore database
    if [[ -f "$backup_path/database_backup.sql" ]]; then
        local env_file="${SCRIPT_DIR}/.env"
        local db_user db_name
        
        if [[ -f "$env_file" ]]; then
            db_user=$(grep "^DB_USER=" "$env_file" | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
            db_name=$(grep "^DB_NAME=" "$env_file" | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
        fi
        
        db_user="${db_user:-milou}"
        db_name="${db_name:-milou}"
        
        if docker exec -i milou-database psql -U "$db_user" -d "$db_name" < "$backup_path/database_backup.sql" >/dev/null 2>&1; then
            milou_log "DEBUG" "Database restored successfully"
        else
            milou_log "WARN" "Failed to restore database"
        fi
    fi
    
    # Restore volumes
    if [[ -d "$backup_path/volumes" ]]; then
        for volume_backup in "$backup_path/volumes"/*.tar.gz; do
            if [[ -f "$volume_backup" ]]; then
                local volume_name=$(basename "$volume_backup" .tar.gz)
                milou_log "DEBUG" "Restoring volume: $volume_name"
                
                # Create volume if it doesn't exist
                docker volume create "$volume_name" >/dev/null 2>&1 || true
                
                # Restore volume data
                docker run --rm -v "$volume_name:/target" -v "$backup_path/volumes:/backup" alpine tar xzf "/backup/${volume_name}.tar.gz" -C /target 2>/dev/null
            fi
        done
    fi
}

# =============================================================================
# Environment Management Functions (from environment.sh)
# =============================================================================

# Load environment variables from file
milou_system_load_environment() {
    local env_file="${1:-${SCRIPT_DIR}/.env}"
    
    if [[ ! -f "$env_file" ]]; then
        milou_log "WARN" "Environment file not found: $env_file"
        return 1
    fi
    
    milou_log "DEBUG" "Loading environment from: $env_file"
    
    # Load environment variables, skipping comments and empty lines
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "$line" ]]; then
            continue
        fi
        
        # Export the variable
        if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
            export "$line"
        fi
    done < "$env_file"
    
    milou_log "DEBUG" "Environment variables loaded"
    return 0
}

# Set up system environment for Milou
milou_system_setup_environment() {
    local script_dir="${SCRIPT_DIR:-$(pwd)}"
    
    milou_log "INFO" "Setting up system environment..."
    
    # Set essential environment variables
    export SCRIPT_DIR="$script_dir"
    export MILOU_HOME="$script_dir"
    export COMPOSE_PROJECT_NAME="milou"
    export COMPOSE_FILE="$script_dir/static/docker-compose.yml"
    
    # Load environment from .env file if available
    milou_system_load_environment "$script_dir/.env"
    
    # Set reasonable defaults for missing variables
    export SERVER_NAME="${SERVER_NAME:-localhost}"
    export DOMAIN="${DOMAIN:-$SERVER_NAME}"
    export SSL_PATH="${SSL_PATH:-$script_dir/static/ssl}"
    export NODE_ENV="${NODE_ENV:-production}"
    
    milou_log "DEBUG" "System environment configured"
    milou_log "DEBUG" "SCRIPT_DIR: $SCRIPT_DIR"
    milou_log "DEBUG" "SERVER_NAME: $SERVER_NAME"
    milou_log "DEBUG" "DOMAIN: $DOMAIN"
    
    return 0
}

# Clean up environment variables
milou_system_cleanup_environment() {
    local cleanup_all="${1:-false}"
    
    milou_log "DEBUG" "Cleaning up environment variables..."
    
    # List of Milou-specific environment variables to clean
    local -a milou_vars=(
        "MILOU_HOME"
        "MILOU_VERSION"
        "MILOU_DEBUG"
        "MILOU_LOG_LEVEL"
        "MILOU_ADMIN_EMAIL"
        "MILOU_ADMIN_PASSWORD"
    )
    
    # Clean up Milou-specific variables
    for var in "${milou_vars[@]}"; do
        unset "$var"
    done
    
    # If cleanup_all is true, clean up all Docker and application variables
    if [[ "$cleanup_all" == "true" ]]; then
        local -a all_vars=(
            "COMPOSE_PROJECT_NAME"
            "COMPOSE_FILE"
            "DATABASE_URI"
            "POSTGRES_USER"
            "POSTGRES_PASSWORD"
            "POSTGRES_DB"
            "REDIS_URL"
            "REDIS_PASSWORD"
            "JWT_SECRET"
            "SESSION_SECRET"
            "ENCRYPTION_KEY"
            "SSL_CERT_PATH"
            "NODE_ENV"
            "DEBUG"
            "PORT"
        )
        
        for var in "${all_vars[@]}"; do
            unset "$var"
        done
    fi
    
    milou_log "DEBUG" "Environment cleanup completed"
}

# Validate environment setup
milou_system_validate_environment() {
    milou_log "DEBUG" "Validating environment setup..."
    
    local errors=0
    
    # Check essential directories
    if [[ ! -d "$SCRIPT_DIR" ]]; then
        milou_log "ERROR" "SCRIPT_DIR not found: $SCRIPT_DIR"
        ((errors++))
    fi
    
    # Check for environment file
    if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
        milou_log "WARN" "Environment file not found: $SCRIPT_DIR/.env"
    fi
    
    # Check for Docker compose file
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        milou_log "ERROR" "Docker compose file not found: $COMPOSE_FILE"
        ((errors++))
    fi
    
    # Check essential environment variables
    local -a required_vars=("SCRIPT_DIR" "SERVER_NAME" "DOMAIN")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            milou_log "ERROR" "Required environment variable not set: $var"
            ((errors++))
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        milou_log "DEBUG" "Environment validation passed"
        return 0
    else
        milou_log "ERROR" "Environment validation failed ($errors errors)"
        return 1
    fi
}

# =============================================================================
# System Update Functions (Enhanced)
# =============================================================================

# Enhanced update Milou system with version and service selection support
milou_system_update() {
    local force_update="${1:-false}"
    local backup_before_update="${2:-true}"
    local target_version="${3:-}"
    local specific_services="${4:-}"
    local github_token="${GITHUB_TOKEN:-}"
    
    milou_log "STEP" "🔄 Updating Milou system..."
    
    # Validate GitHub token if provided
    if [[ -n "$github_token" ]]; then
        milou_log "INFO" "🔐 Testing GitHub authentication..."
        if command -v test_github_authentication >/dev/null 2>&1; then
            if test_github_authentication "$github_token"; then
                milou_log "SUCCESS" "✅ GitHub authentication successful"
            else
                milou_log "ERROR" "❌ GitHub authentication failed"
                milou_log "INFO" "💡 Please check your token permissions (needs read:packages)"
                return 1
            fi
        fi
    else
        milou_log "WARN" "⚠️  No GitHub token provided - using public access"
    fi
    
    # Create backup before update if requested
    if [[ "$backup_before_update" == "true" ]]; then
        milou_log "INFO" "📦 Creating pre-update backup..."
        if ! milou_system_create_backup "full" "./backups" "pre_update_$(date +%Y%m%d_%H%M%S)"; then
            milou_log "WARN" "⚠️  Backup failed, continuing with update..."
        fi
    fi
    
    # Enhanced update check with version support
    if ! milou_system_check_for_updates "$target_version" "$github_token" "$specific_services"; then
        if [[ "$force_update" != "true" ]]; then
            milou_log "INFO" "✅ System is up to date"
            return 0
        else
            milou_log "INFO" "🔄 Forcing update despite no new version available"
        fi
    fi
    
    # Perform the enhanced update
    milou_system_perform_update "$target_version" "$specific_services" "$github_token"
    
    milou_log "SUCCESS" "✅ System update completed"
    milou_log "INFO" "📋 Run './milou.sh status' to verify the update"
}

# Enhanced update check with version and service support
milou_system_check_for_updates() {
    local target_version="${1:-}"
    local github_token="${2:-}"
    local specific_services="${3:-}"
    
    milou_log "DEBUG" "Checking for system updates..."
    
    # If specific version is requested, validate its availability
    if [[ -n "$target_version" ]]; then
        milou_log "INFO" "🎯 Checking availability of version: $target_version"
        
        if [[ -n "$github_token" ]]; then
            # Check if the requested version exists for all services
            local -a services_to_check=()
            if [[ -n "$specific_services" ]]; then
                IFS=',' read -ra services_to_check <<< "$specific_services"
            else
                services_to_check=("frontend" "backend" "database" "engine" "nginx")
            fi
            
            local version_available=true
            for service in "${services_to_check[@]}"; do
                milou_log "DEBUG" "Checking version $target_version for service: $service"
                if command -v check_image_exists >/dev/null 2>&1; then
                    if ! check_image_exists "$service" "$target_version" "$github_token"; then
                        milou_log "WARN" "❌ Version $target_version not available for $service"
                        version_available=false
                    else
                        milou_log "DEBUG" "✅ Version $target_version available for $service"
                    fi
                fi
            done
            
            if [[ "$version_available" == "true" ]]; then
                milou_log "SUCCESS" "✅ Target version $target_version is available"
                return 0  # Update needed (version available)
            else
                milou_log "ERROR" "❌ Target version $target_version is not available for all services"
                return 1  # No update possible
            fi
        else
            milou_log "INFO" "🔄 No GitHub token provided, assuming version is available"
            return 0  # Assume update needed
        fi
    else
        # No specific version requested, check for latest
        local current_version="${MILOU_VERSION:-1.0.0}"
        milou_log "DEBUG" "Current version: $current_version, checking for updates..."
        
        # For now, assume updates are available when no specific version is requested
        return 0
    fi
}

# Enhanced system update with version and service selection
milou_system_perform_update() {
    local target_version="${1:-}"
    local specific_services="${2:-}"
    local github_token="${3:-}"
    
    milou_log "INFO" "🔄 Performing system update..."
    
    # Parse specific services if provided
    local -a services_to_update=()
    if [[ -n "$specific_services" ]]; then
        IFS=',' read -ra services_to_update <<< "$specific_services"
        milou_log "INFO" "🎯 Updating specific services: ${services_to_update[*]}"
    else
        services_to_update=("frontend" "backend" "database" "engine" "nginx")
        milou_log "INFO" "🔄 Updating all services"
    fi
    
    # Preserve current environment before update
    milou_log "INFO" "🔒 Preserving environment configuration..."
    local env_backup="/tmp/milou_env_backup_$(date +%s)"
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        cp "$SCRIPT_DIR/.env" "$env_backup"
        milou_log "DEBUG" "Environment backed up to: $env_backup"
    fi
    
    # Store pre-update service status for rollback
    local pre_update_status="/tmp/milou_pre_update_status_$(date +%s)"
    docker ps --filter "name=milou-" --format "{{.Names}}\t{{.Status}}" > "$pre_update_status" 2>/dev/null || true
    
    # Enhanced selective service management
    if [[ -n "$specific_services" ]]; then
        milou_log "INFO" "🎯 Performing selective service update..."
        milou_system_selective_service_update "${services_to_update[@]}" "$target_version" "$github_token"
        local update_result=$?
    else
        milou_log "INFO" "🔄 Performing full system update..."
        milou_system_full_service_update "$target_version" "$github_token"
        local update_result=$?
    fi
    
    # Clean up temporary files
    rm -f "$env_backup" "$pre_update_status"
    
    if [[ $update_result -eq 0 ]]; then
        milou_log "SUCCESS" "✅ Update completed successfully"
        return 0
    else
        milou_log "ERROR" "❌ Update failed"
        return 1
    fi
}

# Selective service update with health monitoring
milou_system_selective_service_update() {
    local -a services_to_update=("$@")
    local github_token="${!#}"  # Last argument
    local target_version="${@: -2:1}"  # Second to last argument
    
    # Remove the last two arguments (version and token) from services array
    unset 'services_to_update[-1]'
    unset 'services_to_update[-1]'
    
    milou_log "INFO" "🎯 Selective update: ${services_to_update[*]} → $target_version"
    
    # Step 1: Update Docker images first
    milou_log "INFO" "📥 Updating Docker images..."
    # Convert services array to comma-separated string for compatibility
    local services_string
    services_string=$(IFS=','; echo "${services_to_update[*]}")
    if ! milou_system_update_docker_images "$target_version" "$services_string" "$github_token"; then
        milou_log "ERROR" "Failed to update Docker images"
        return 1
    fi
    
    # Step 2: Update environment tags
    milou_log "INFO" "🏷️ Updating image tags in environment..."
    milou_system_update_image_tags "$target_version" "$services_string"
    
    # Step 3: Restart services in dependency order with health monitoring
    milou_log "INFO" "🔄 Restarting updated services..."
    local -a restart_order=()
    local -a dependent_services=()
    
    # Determine restart order based on dependencies
    for service in "${services_to_update[@]}"; do
        case "$service" in
            "database"|"redis"|"rabbitmq")
                # Infrastructure services restart first
                restart_order+=("$service")
                ;;
            "backend"|"engine")
                # Backend services need infrastructure
                dependent_services+=("$service")
                ;;
            "frontend"|"nginx")
                # Frontend services restart last
                dependent_services+=("$service")
                ;;
        esac
    done
    
    # Combine in proper order
    restart_order+=("${dependent_services[@]}")
    
    # Restart services one by one with health checking
    local failed_services=()
    for service in "${restart_order[@]}"; do
        milou_log "INFO" "🔄 Restarting service: $service"
        
        # Stop the service
        if command -v milou_docker_stop_service >/dev/null 2>&1; then
            milou_docker_stop_service "$service" || true
        fi
        
        # Wait a moment
        sleep 2
        
        # Start the service
        if command -v milou_docker_start_service >/dev/null 2>&1; then
            if milou_docker_start_service "$service"; then
                # Wait for service to stabilize and check health
                milou_log "INFO" "⏳ Waiting for $service to stabilize..."
                if milou_system_wait_for_service_health "$service" 60; then
                    milou_log "SUCCESS" "✅ Service $service restarted successfully"
                else
                    milou_log "WARN" "⚠️ Service $service started but health check failed"
                    failed_services+=("$service")
                fi
            else
                milou_log "ERROR" "❌ Failed to start service: $service"
                failed_services+=("$service")
            fi
        fi
    done
    
    # Report results
    if [[ ${#failed_services[@]} -eq 0 ]]; then
        milou_log "SUCCESS" "✅ All services updated and restarted successfully"
        return 0
    else
        milou_log "WARN" "⚠️ Update completed with issues in: ${failed_services[*]}"
        milou_log "INFO" "💡 Consider running './milou.sh restart' to fix remaining issues"
        return 0  # Don't fail completely for partial success
    fi
}

# Full system update (existing logic with improvements)
milou_system_full_service_update() {
    local target_version="$1"
    local github_token="$2"
    
    # Stop all services
    milou_log "INFO" "⏸️ Stopping all services..."
    if command -v milou_docker_stop >/dev/null 2>&1; then
        milou_docker_stop
    fi
    
    # Update Docker images with version and authentication support
    milou_log "INFO" "📥 Updating Docker images..."
    milou_system_update_docker_images "$target_version" "" "$github_token"
    
    # Update environment tags
    if [[ -n "$target_version" ]]; then
        milou_log "DEBUG" "Updating image tags to: $target_version"
        milou_system_update_image_tags "$target_version" ""
    fi
    
    # Apply any configuration migrations
    milou_log "INFO" "🔧 Applying configuration updates..."
    milou_system_apply_config_updates
    
    # Restart all services
    milou_log "INFO" "▶️ Restarting all services..."
    if command -v milou_docker_start >/dev/null 2>&1; then
        milou_docker_start
        return $?
    else
        milou_log "ERROR" "Start function not available"
        return 1
    fi
}

# Wait for a specific service to become healthy
milou_system_wait_for_service_health() {
    local service="$1"
    local timeout="${2:-30}"
    local container_name="milou-${service}"
    
    milou_log "DEBUG" "Waiting for $service to become healthy (timeout: ${timeout}s)"
    
    local elapsed=0
    local check_interval=2
    
    while [[ $elapsed -lt $timeout ]]; do
        # Check container status
        local container_status
        container_status=$(docker inspect --format='{{.State.Status}}' "$container_name" 2>/dev/null || echo "not_found")
        
        case "$container_status" in
            "running")
                # Check health status if health checks are configured
                local health_status
                health_status=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no_healthcheck{{end}}' "$container_name" 2>/dev/null || echo "unknown")
                
                case "$health_status" in
                    "healthy"|"no_healthcheck")
                        milou_log "DEBUG" "✅ Service $service is healthy"
                        return 0
                        ;;
                    "starting")
                        milou_log "DEBUG" "⏳ Service $service health check starting..."
                        ;;
                    "unhealthy")
                        if [[ $elapsed -gt 20 ]]; then
                            milou_log "WARN" "⚠️ Service $service is unhealthy after ${elapsed}s"
                            return 1
                        fi
                        ;;
                esac
                ;;
            "not_found")
                milou_log "DEBUG" "⏳ Container $container_name not found yet..."
                ;;
            "exited")
                milou_log "ERROR" "❌ Container $container_name exited"
                return 1
                ;;
        esac
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    milou_log "WARN" "⚠️ Health check timeout for service $service after ${timeout}s"
    return 1
}

# Enhanced Docker image update with authentication and version support
milou_system_update_docker_images() {
    local target_version="${1:-latest}"
    local specific_services="${2:-}"
    local github_token="${3:-}"
    local compose_file="${COMPOSE_FILE:-${SCRIPT_DIR}/static/docker-compose.yml}"
    
    if [[ ! -f "$compose_file" ]]; then
        milou_log "ERROR" "Docker compose file not found: $compose_file"
        return 1
    fi
    
    milou_log "DEBUG" "Updating Docker images (version: $target_version)"
    
    # If GitHub token is provided, use enhanced image pulling
    if [[ -n "$github_token" ]] && command -v pull_images >/dev/null 2>&1; then
        milou_log "INFO" "🔐 Using authenticated GitHub Container Registry access"
        
        # Build list of images to pull
        local -a images_to_pull=()
        if [[ -n "$specific_services" ]]; then
            IFS=',' read -ra services <<< "$specific_services"
            for service in "${services[@]}"; do
                images_to_pull+=("$service:$target_version")
            done
        else
            # Get all Milou images
            images_to_pull=("frontend:$target_version" "backend:$target_version" "database:$target_version" "engine:$target_version" "nginx:$target_version")
        fi
        
        milou_log "INFO" "📥 Pulling images: ${images_to_pull[*]}"
        if pull_images "$github_token" "${images_to_pull[@]}"; then
            milou_log "SUCCESS" "✅ Images pulled successfully with authentication"
        else
            milou_log "WARN" "⚠️  Authenticated pull failed, falling back to docker compose pull"
            # Fall back to standard docker compose pull
            docker compose -f "$compose_file" pull
        fi
    else
        # Standard docker compose pull
        milou_log "DEBUG" "Using standard docker compose pull"
        if docker compose -f "$compose_file" pull; then
            milou_log "SUCCESS" "Docker images updated"
            return 0
        else
            milou_log "ERROR" "Failed to update Docker images"
            return 1
        fi
    fi
}

# Update image tags in environment file
milou_system_update_image_tags() {
    local target_version="$1"
    local specific_services="${2:-}"
    local env_file="${SCRIPT_DIR}/.env"
    
    if [[ ! -f "$env_file" ]]; then
        milou_log "ERROR" "Environment file not found: $env_file"
        return 1
    fi
    
    milou_log "DEBUG" "Updating image tags to: $target_version"
    
    # Create backup
    cp "$env_file" "${env_file}.tag_update.$(date +%s)"
    
    # Update image tags
    if [[ -n "$specific_services" ]]; then
        IFS=',' read -ra services <<< "$specific_services"
        for service in "${services[@]}"; do
            local tag_var="MILOU_${service^^}_TAG"
            milou_log "DEBUG" "Updating $tag_var to $target_version"
            sed -i "s/^${tag_var}=.*/${tag_var}=${target_version}/" "$env_file"
        done
    else
        # Update all service tags
        sed -i "s/^MILOU_DATABASE_TAG=.*/MILOU_DATABASE_TAG=${target_version}/" "$env_file"
        sed -i "s/^MILOU_BACKEND_TAG=.*/MILOU_BACKEND_TAG=${target_version}/" "$env_file"
        sed -i "s/^MILOU_FRONTEND_TAG=.*/MILOU_FRONTEND_TAG=${target_version}/" "$env_file"
        sed -i "s/^MILOU_ENGINE_TAG=.*/MILOU_ENGINE_TAG=${target_version}/" "$env_file"
        sed -i "s/^MILOU_NGINX_TAG=.*/MILOU_NGINX_TAG=${target_version}/" "$env_file"
    fi
    
    milou_log "SUCCESS" "✅ Image tags updated to $target_version"
}

# Apply configuration updates
milou_system_apply_config_updates() {
    milou_log "DEBUG" "Applying configuration updates..."
    
    # This would handle any configuration schema changes
    # For now, it's a placeholder
    
    local env_file="${SCRIPT_DIR}/.env"
    if [[ -f "$env_file" ]]; then
        # Check for any required configuration updates
        milou_log "DEBUG" "Configuration file exists, checking for updates..."
        
        # Example: Add new required variables if missing
        if ! grep -q "^MILOU_VERSION=" "$env_file"; then
            echo "MILOU_VERSION=1.0.0" >> "$env_file"
            milou_log "DEBUG" "Added MILOU_VERSION to configuration"
        fi
    fi
    
    milou_log "DEBUG" "Configuration updates applied"
}

# Rollback to previous state if update fails
milou_system_rollback_update() {
    local backup_status_file="$1"
    local env_backup_file="$2"
    
    milou_log "WARN" "🔄 Attempting to rollback to previous state..."
    
    if [[ -f "$env_backup_file" ]]; then
        milou_log "INFO" "📝 Restoring previous environment configuration..."
        cp "$env_backup_file" "$SCRIPT_DIR/.env"
        milou_log "SUCCESS" "✅ Environment restored"
    fi
    
    if [[ -f "$backup_status_file" ]]; then
        milou_log "INFO" "🐳 Attempting to restore previous container states..."
        
        # Stop all current containers
        docker ps --filter "name=milou-" --format "{{.Names}}" | while read -r container; do
            if [[ -n "$container" ]]; then
                milou_log "DEBUG" "Stopping $container"
                docker stop "$container" >/dev/null 2>&1 || true
            fi
        done
        
        # Try to start services normally (they should use the restored environment)
        milou_log "INFO" "🔄 Restarting services with restored configuration..."
        if command -v milou_docker_start >/dev/null 2>&1; then
            milou_docker_start
        fi
    fi
    
    milou_log "INFO" "🔍 Rollback attempt completed - check service status"
}

# Enhanced update with better error handling and rollback capability
milou_system_update_with_rollback() {
    local force_update="${1:-false}"
    local backup_before_update="${2:-true}"
    local target_version="${3:-}"
    local specific_services="${4:-}"
    local github_token="${GITHUB_TOKEN:-}"
    
    milou_log "STEP" "🔄 Enhanced system update with rollback protection..."
    
    # Create comprehensive backup and state tracking
    local env_backup="/tmp/milou_env_backup_$(date +%s)"
    local status_backup="/tmp/milou_status_backup_$(date +%s)"
    
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        cp "$SCRIPT_DIR/.env" "$env_backup"
    fi
    
    docker ps --filter "name=milou-" --format "{{.Names}}\t{{.Status}}" > "$status_backup" 2>/dev/null || true
    
    # Perform the update with enhanced error handling
    if milou_system_update "$force_update" "$backup_before_update" "$target_version" "$specific_services"; then
        milou_log "SUCCESS" "✅ Update completed successfully"
        rm -f "$env_backup" "$status_backup"
        return 0
    else
        milou_log "ERROR" "❌ Update failed - initiating rollback..."
        milou_system_rollback_update "$status_backup" "$env_backup"
        rm -f "$env_backup" "$status_backup"
        return 1
    fi
} 