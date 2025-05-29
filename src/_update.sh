#!/bin/bash

# =============================================================================
# Milou CLI Update Management Module
# Professional consolidation of all update-related functionality
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Module guard to prevent multiple loading
if [[ "${MILOU_UPDATE_MODULE_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_UPDATE_MODULE_LOADED="true"

# =============================================================================
# CONFIGURATION & CONSTANTS
# =============================================================================

# Self-update configuration
readonly MILOU_CLI_REPO="milou-sh/milou-cli"
readonly GITHUB_API_BASE="https://api.github.com/repos"
readonly RELEASE_API_URL="${GITHUB_API_BASE}/${MILOU_CLI_REPO}/releases"

# Default services for system updates
readonly DEFAULT_SERVICES=("frontend" "backend" "database" "engine" "nginx")

# =============================================================================
# SYSTEM UPDATE CORE FUNCTIONS
# =============================================================================

# Enhanced system update with comprehensive version and service selection support
milou_update_system() {
    local force_update="${1:-false}"
    local backup_before_update="${2:-true}"
    local target_version="${3:-}"
    local specific_services="${4:-}"
    local github_token="${GITHUB_TOKEN:-}"
    
    milou_log "STEP" "🔄 Updating Milou system..."
    
    # Validate GitHub token if provided
    if [[ -n "$github_token" ]]; then
        milou_log "INFO" "🔐 Testing GitHub authentication..."
        if command -v milou_test_github_authentication >/dev/null 2>&1; then
            if milou_test_github_authentication "$github_token"; then
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
        if command -v milou_backup_create >/dev/null 2>&1; then
            if ! milou_backup_create "full" "./backups" "pre_update_$(date +%Y%m%d_%H%M%S)"; then
                milou_log "WARN" "⚠️  Backup failed, continuing with update..."
            fi
        else
            milou_log "WARN" "⚠️  Backup function not available, skipping backup"
        fi
    fi
    
    # Enhanced update check with version support
    if ! _milou_update_check_for_updates "$target_version" "$github_token" "$specific_services"; then
        if [[ "$force_update" != "true" ]]; then
            milou_log "INFO" "✅ System is up to date"
            return 0
        else
            milou_log "INFO" "🔄 Forcing update despite no new version available"
        fi
    fi
    
    # Perform the enhanced update
    _milou_update_perform_update "$target_version" "$specific_services" "$github_token"
    
    milou_log "SUCCESS" "✅ System update completed"
    milou_log "INFO" "📋 Run './milou.sh status' to verify the update"
}

# Enhanced update check with version and service support
_milou_update_check_for_updates() {
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
                services_to_check=("${DEFAULT_SERVICES[@]}")
            fi
            
            local version_available=true
            for service in "${services_to_check[@]}"; do
                milou_log "DEBUG" "Checking version $target_version for service: $service"
                if command -v milou_docker_check_image_exists >/dev/null 2>&1; then
                    if ! milou_docker_check_image_exists "$service" "$target_version" "$github_token"; then
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
_milou_update_perform_update() {
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
        services_to_update=("${DEFAULT_SERVICES[@]}")
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
    docker ps --filter "name=static-" --format "{{.Names}}\t{{.Status}}" > "$pre_update_status" 2>/dev/null || true
    
    # Enhanced selective service management
    local update_result
    if [[ -n "$specific_services" ]]; then
        milou_log "INFO" "🎯 Performing selective service update..."
        _milou_update_selective_services "${services_to_update[@]}" "$target_version" "$github_token"
        update_result=$?
    else
        milou_log "INFO" "🔄 Performing full system update..."
        _milou_update_all_services "$target_version" "$github_token"
        update_result=$?
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
_milou_update_selective_services() {
    local -a services_to_update=("$@")
    local target_version="${!#}"  # Last argument is version
    local github_token="${GITHUB_TOKEN:-}"
    
    # Remove version from services array (it's the last argument)
    unset 'services_to_update[-1]'
    
    milou_log "INFO" "🎯 Updating services: ${services_to_update[*]}"
    
    # Stop specific services
    for service in "${services_to_update[@]}"; do
        milou_log "INFO" "🛑 Stopping service: $service"
        if command -v milou_docker_stop_service >/dev/null 2>&1; then
            milou_docker_stop_service "$service"
        else
            docker stop "static-$service" 2>/dev/null || true
        fi
    done
    
    # Update Docker images for specific services
    if [[ -n "$target_version" ]]; then
        _milou_update_docker_images "$target_version" "${services_to_update[@]}"
    else
        _milou_update_docker_images "latest" "${services_to_update[@]}"
    fi
    
    # Start updated services
    for service in "${services_to_update[@]}"; do
        milou_log "INFO" "🚀 Starting updated service: $service"
        if command -v milou_docker_start_service >/dev/null 2>&1; then
            milou_docker_start_service "$service"
        else
            # Use docker compose to start specific service
            if command -v milou_docker_compose >/dev/null 2>&1; then
                milou_docker_compose up -d "$service"
            fi
        fi
    done
    
    # Verify updated services are healthy
    _milou_update_verify_services "${services_to_update[@]}"
}

# Full system update
_milou_update_all_services() {
    local target_version="${1:-latest}"
    local github_token="${2:-}"
    
    milou_log "INFO" "🔄 Performing full system update to version: $target_version"
    
    # Stop all services gracefully
    milou_log "INFO" "🛑 Stopping all services..."
    if command -v milou_docker_stop >/dev/null 2>&1; then
        milou_docker_stop
    else
        docker compose down 2>/dev/null || true
    fi
    
    # Update all Docker images
    _milou_update_docker_images "$target_version"
    
    # Start all services
    milou_log "INFO" "🚀 Starting updated services..."
    if command -v milou_docker_start >/dev/null 2>&1; then
        milou_docker_start
    else
        if command -v milou_docker_compose >/dev/null 2>&1; then
            milou_docker_compose up -d
        fi
    fi
    
    # Verify all services are healthy
    _milou_update_verify_services
}

# Update Docker images with enhanced error handling
_milou_update_docker_images() {
    local target_version="${1:-latest}"
    shift
    local -a services=("$@")
    
    # If no specific services provided, update all
    if [[ ${#services[@]} -eq 0 ]]; then
        services=("${DEFAULT_SERVICES[@]}")
    fi
    
    milou_log "INFO" "📥 Pulling Docker images for version: $target_version"
    
    # Get registry information
    local registry="${DOCKER_REGISTRY:-ghcr.io/milou-sh}"
    local github_token="${GITHUB_TOKEN:-}"
    
    # Login to registry if token is provided
    if [[ -n "$github_token" ]]; then
        echo "$github_token" | docker login ghcr.io -u "$GITHUB_ACTOR" --password-stdin 2>/dev/null || {
            milou_log "WARN" "Docker registry login failed, trying without authentication"
        }
    fi
    
    # Pull updated images
    for service in "${services[@]}"; do
        local image_name="${registry}/${service}:${target_version}"
        milou_log "INFO" "📥 Pulling image: $image_name"
        
        if docker pull "$image_name" 2>/dev/null; then
            milou_log "SUCCESS" "✅ Updated image for $service"
        else
            milou_log "ERROR" "❌ Failed to pull image for $service"
            # Try latest as fallback
            if [[ "$target_version" != "latest" ]]; then
                milou_log "INFO" "🔄 Trying latest version for $service..."
                if docker pull "${registry}/${service}:latest" 2>/dev/null; then
                    milou_log "WARN" "⚠️ Using latest version for $service instead of $target_version"
                else
                    milou_log "ERROR" "❌ Failed to pull any version for $service"
                fi
            fi
        fi
    done
}

# Verify services are healthy after update
_milou_update_verify_services() {
    local -a services_to_verify=("$@")
    
    # If no specific services provided, verify all
    if [[ ${#services_to_verify[@]} -eq 0 ]]; then
        services_to_verify=("${DEFAULT_SERVICES[@]}")
    fi
    
    milou_log "INFO" "🏥 Verifying service health after update..."
    
    local max_wait=60  # 60 seconds timeout
    local elapsed=0
    local all_healthy=false
    
    while [[ $elapsed -lt $max_wait ]]; do
        local healthy_count=0
        
        for service in "${services_to_verify[@]}"; do
            if docker ps --filter "name=static-$service" --filter "status=running" --format "{{.Names}}" | grep -q "static-$service"; then
                ((healthy_count++))
            fi
        done
        
        if [[ $healthy_count -eq ${#services_to_verify[@]} ]]; then
            all_healthy=true
            break
        fi
        
        sleep 3
        elapsed=$((elapsed + 3))
        
        if [[ $((elapsed % 15)) -eq 0 ]]; then
            milou_log "INFO" "⏳ Waiting for services to be healthy ($healthy_count/${#services_to_verify[@]} ready)..."
        fi
    done
    
    if [[ "$all_healthy" == "true" ]]; then
        milou_log "SUCCESS" "✅ All services are healthy after update"
        return 0
    else
        milou_log "ERROR" "❌ Some services failed to start properly after update"
        return 1
    fi
}

# =============================================================================
# ROLLBACK & STATUS FUNCTIONS
# =============================================================================

# Rollback to previous version with intelligent backup detection
milou_update_rollback() {
    local backup_file="${1:-}"
    
    milou_log "STEP" "🔄 Rolling back system update..."
    
    if [[ -z "$backup_file" ]]; then
        # Try to find the most recent pre-update backup
        local backup_dir="./backups"
        if [[ -d "$backup_dir" ]]; then
            backup_file=$(find "$backup_dir" -name "pre_update_*.tar.gz" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
        fi
        
        if [[ -z "$backup_file" ]]; then
            milou_log "ERROR" "No backup file specified and no automatic backup found"
            milou_log "INFO" "💡 Usage: ./milou.sh rollback <backup_file>"
            return 1
        fi
        
        milou_log "INFO" "📦 Using automatic backup: $backup_file"
    fi
    
    # Restore from backup
    if command -v milou_restore_from_backup >/dev/null 2>&1; then
        milou_restore_from_backup "$backup_file" "full"
    else
        milou_log "ERROR" "Restore function not available"
        return 1
    fi
    
    # Restart services
    milou_log "INFO" "🔄 Restarting services with restored configuration..."
    if command -v milou_docker_restart >/dev/null 2>&1; then
        milou_docker_restart
    else
        milou_log "WARN" "Service restart function not available - please restart manually"
    fi
    
    milou_log "SUCCESS" "✅ Rollback completed"
}

# Check comprehensive system update status
milou_update_check_status() {
    milou_log "INFO" "📊 Checking system update status..."
    
    # Check current version
    local current_version="${MILOU_VERSION:-unknown}"
    milou_log "INFO" "Current version: $current_version"
    
    # Check for available updates
    if command -v milou_self_update_check >/dev/null 2>&1; then
        milou_log "INFO" "Checking for CLI updates..."
        milou_self_update_check
    fi
    
    # Check Docker image versions
    milou_log "INFO" "📦 Current Docker images:"
    docker images --filter "reference=ghcr.io/milou-sh/*" --format "table {{.Repository}}\t{{.Tag}}\t{{.CreatedAt}}" 2>/dev/null || {
        milou_log "WARN" "Unable to list Docker images"
    }
    
    # Check service status
    if command -v milou_docker_status >/dev/null 2>&1; then
        milou_log "INFO" "📋 Service status:"
        milou_docker_status
    fi
}

# =============================================================================
# CLI SELF-UPDATE FUNCTIONS
# =============================================================================

# Check for new CLI release with comprehensive version handling
milou_self_update_check() {
    local target_version="${1:-latest}"
    
    milou_log "INFO" "🔍 Checking for Milou CLI updates..."
    
    # Get release information from GitHub API
    local release_info
    local api_url="$RELEASE_API_URL"
    
    if [[ "$target_version" == "latest" ]]; then
        api_url="${api_url}/latest"
    else
        api_url="${api_url}/tags/${target_version}"
    fi
    
    if ! command -v curl >/dev/null 2>&1; then
        milou_log "ERROR" "curl is required for self-updates"
        return 1
    fi
    
    milou_log "DEBUG" "Fetching release info from: $api_url"
    
    if ! release_info=$(curl -s "$api_url"); then
        milou_log "ERROR" "Failed to fetch release information from GitHub"
        return 1
    fi
    
    # Parse release information
    local remote_version
    if ! remote_version=$(echo "$release_info" | grep '"tag_name"' | cut -d'"' -f4); then
        milou_log "ERROR" "Failed to parse release version"
        return 1
    fi
    
    local current_version="${SCRIPT_VERSION:-3.1.0}"
    
    # Clean version strings (remove 'v' prefix if present)
    remote_version="${remote_version#v}"
    current_version="${current_version#v}"
    
    milou_log "DEBUG" "Current version: $current_version"
    milou_log "DEBUG" "Remote version: $remote_version"
    
    if [[ "$current_version" == "$remote_version" ]]; then
        milou_log "SUCCESS" "✅ Milou CLI is up to date (v$current_version)"
        return 1  # No update needed
    fi
    
    milou_log "INFO" "🆕 Update available: v$current_version → v$remote_version"
    return 0  # Update available
}

# Perform CLI self-update with comprehensive error handling
milou_self_update_perform() {
    local target_version="${1:-latest}"
    local force="${2:-false}"
    
    milou_log "STEP" "🔄 Performing Milou CLI self-update..."
    
    # Check if update is needed
    if [[ "$force" != "true" ]] && ! milou_self_update_check "$target_version"; then
        return 0  # Already up to date
    fi
    
    # Get release information
    local api_url="$RELEASE_API_URL"
    if [[ "$target_version" == "latest" ]]; then
        api_url="${api_url}/latest"
    else
        api_url="${api_url}/tags/${target_version}"
    fi
    
    local release_info
    if ! release_info=$(curl -s "$api_url"); then
        milou_log "ERROR" "Failed to fetch release information"
        return 1
    fi
    
    # Extract download URL for the main script
    local download_url
    if ! download_url=$(echo "$release_info" | grep '"browser_download_url".*milou\.sh"' | cut -d'"' -f4); then
        milou_log "ERROR" "Failed to find download URL for milou.sh"
        return 1
    fi
    
    local version_tag
    version_tag=$(echo "$release_info" | grep '"tag_name"' | cut -d'"' -f4)
    
    milou_log "INFO" "📥 Downloading Milou CLI $version_tag..."
    
    # Create temporary directory
    local temp_dir
    temp_dir=$(mktemp -d -t milou-update-XXXXXX)
    local temp_script="$temp_dir/milou.sh"
    local current_script="${SCRIPT_DIR}/milou.sh"
    
    # Download new version
    if ! curl -L -o "$temp_script" "$download_url"; then
        milou_log "ERROR" "Failed to download new version"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Verify download
    if [[ ! -f "$temp_script" ]] || [[ ! -s "$temp_script" ]]; then
        milou_log "ERROR" "Downloaded file is invalid"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Make it executable and test
    chmod +x "$temp_script"
    
    # Basic validation - check if it's a bash script
    if ! head -1 "$temp_script" | grep -q "#!/bin/bash"; then
        milou_log "ERROR" "Downloaded file is not a valid bash script"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Test the new script
    milou_log "INFO" "🧪 Testing new version..."
    if ! "$temp_script" --version >/dev/null 2>&1; then
        milou_log "WARN" "New version test failed, but proceeding anyway"
    fi
    
    # Backup current version
    local backup_script="${current_script}.backup.$(date +%s)"
    if ! cp "$current_script" "$backup_script"; then
        milou_log "ERROR" "Failed to create backup"
        rm -rf "$temp_dir"
        return 1
    fi
    
    milou_log "INFO" "💾 Backup created: $backup_script"
    
    # Replace current script
    if ! cp "$temp_script" "$current_script"; then
        milou_log "ERROR" "Failed to replace current script"
        milou_log "INFO" "Restoring from backup..."
        cp "$backup_script" "$current_script"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Set proper permissions
    chmod +x "$current_script"
    
    # Cleanup
    rm -rf "$temp_dir"
    
    milou_log "SUCCESS" "✅ Milou CLI updated successfully to $version_tag"
    milou_log "INFO" "🔄 Please restart your command to use the new version"
    milou_log "INFO" "📄 Backup available at: $backup_script"
    
    return 0
}

# CLI update wrapper with comprehensive argument handling
milou_update_cli() {
    local version="${1:-latest}"
    local force="${2:-false}"
    
    case "$version" in
        --help|-h)
            echo "Milou CLI Self-Update"
            echo "Usage: ./milou.sh update-cli [VERSION] [--force]"
            echo ""
            echo "Arguments:"
            echo "  VERSION     Target version (default: latest)"
            echo "  --force     Force update even if already up to date"
            echo ""
            echo "Examples:"
            echo "  ./milou.sh update-cli"
            echo "  ./milou.sh update-cli v3.2.0"
            echo "  ./milou.sh update-cli --force"
            return 0
            ;;
        --force)
            force="true"
            version="latest"
            ;;
    esac
    
    milou_self_update_perform "$version" "$force"
}

# =============================================================================
# COMMAND HANDLERS
# =============================================================================

# Combined help function to reduce exports
_show_update_help() {
    local help_type="${1:-system}"
    
    case "$help_type" in
        "system")
            echo "🔄 System Update Command Usage"
            echo "=============================="
            echo ""
            echo "UPDATE SYSTEM:"
            echo "  ./milou.sh update [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --version VERSION     Update to specific version (e.g., v1.0.0, latest)"
            echo "  --service SERVICES    Update specific services (comma-separated)"
            echo "                       Available: frontend,backend,database,engine,nginx"
            echo "  --force              Force update even if no changes detected"
            echo "  --no-backup          Skip backup creation before update"
            echo "  --help, -h           Show this help message"
            echo ""
            echo "Examples:"
            echo "  ./milou.sh update"
            echo "  ./milou.sh update --version v1.2.0"
            echo "  ./milou.sh update --service frontend,backend"
            echo "  ./milou.sh update --force --no-backup"
            echo ""
            echo "OTHER UPDATE COMMANDS:"
            echo "  ./milou.sh update-cli        Update the CLI tool itself"
            echo "  ./milou.sh update-status     Check update status"
            echo "  ./milou.sh rollback          Rollback last update"
            ;;
        "cli")
            echo "🛠️ CLI Update Command Usage"
            echo "==========================="
            echo ""
            echo "UPDATE CLI:"
            echo "  ./milou.sh update-cli [VERSION] [OPTIONS]"
            echo ""
            echo "Arguments:"
            echo "  VERSION              Target version (default: latest)"
            echo ""
            echo "Options:"
            echo "  --force              Force update even if already up to date"
            echo "  --check              Check for updates without installing"
            echo "  --help, -h           Show this help"
            echo ""
            echo "Examples:"
            echo "  ./milou.sh update-cli"
            echo "  ./milou.sh update-cli v3.2.0"
            echo "  ./milou.sh update-cli --force"
            echo "  ./milou.sh update-cli --check"
            ;;
    esac
}

# System update command handler
handle_update() {
    local target_version=""
    local specific_services=""
    local force_update=false
    local backup_before_update=true
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                target_version="$2"
                shift 2
                ;;
            --service|--services)
                specific_services="$2"
                shift 2
                ;;
            --force)
                force_update=true
                shift
                ;;
            --no-backup)
                backup_before_update=false
                shift
                ;;
            --help|-h)
                _show_update_help "system"
                return 0
                ;;
            *)
                milou_log "WARN" "Unknown update argument: $1"
                shift
                ;;
        esac
    done
    
    # Log the update request
    if [[ -n "$target_version" ]]; then
        milou_log "STEP" "🔄 Updating system to version: $target_version"
    else
        milou_log "STEP" "🔄 Updating system to latest version..."
    fi
    
    if [[ -n "$specific_services" ]]; then
        milou_log "INFO" "🎯 Targeting services: $specific_services"
    fi
    
    # Use modular update function
    milou_update_system "$force_update" "$backup_before_update" "$target_version" "$specific_services"
}

# CLI self-update command handler
handle_update_cli() {
    local target_version="${1:-latest}"
    local force="${2:-false}"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                target_version="$2"
                shift 2
                ;;
            --force)
                force="true"
                shift
                ;;
            --check)
                handle_check_cli_updates
                return $?
                ;;
            --help|-h)
                _show_update_help "cli"
                return 0
                ;;
            *)
                # Assume it's a version if no flag
                if [[ "$1" != --* ]]; then
                    target_version="$1"
                fi
                shift
                ;;
        esac
    done
    
    milou_log "STEP" "🔄 Updating Milou CLI..."
    
    # Use modular CLI update function
    milou_update_cli "$target_version" "$force"
}

# Check for CLI updates
handle_check_cli_updates() {
    milou_log "INFO" "🔍 Checking for Milou CLI updates..."
    
    if milou_self_update_check; then
        milou_log "INFO" "🆕 CLI update available!"
        milou_log "INFO" "💡 Run './milou.sh update-cli' to update"
    else
        milou_log "SUCCESS" "✅ CLI is up to date"
    fi
}

# Update status check
handle_update_status() {
    milou_log "STEP" "📊 Checking system update status..."
    milou_update_check_status
}

# Rollback system update
handle_rollback() {
    local backup_file="${1:-}"
    
    milou_log "STEP" "🔄 Rolling back system update..."
    milou_update_rollback "$backup_file"
}

# =============================================================================
# CLEAN PUBLIC API - Export only essential functions
# =============================================================================

# System Update Functions (4 exports)
export -f milou_update_system           # Primary system update function
export -f milou_update_rollback         # Rollback capability  
export -f milou_update_check_status     # Status checking
export -f milou_update_cli              # CLI self-update

# CLI Self-Update Functions (2 exports)
export -f milou_self_update_check       # Check for CLI updates
export -f milou_self_update_perform     # Perform CLI update

# Command Handlers (5 exports)
export -f handle_update                 # System update handler
export -f handle_update_cli             # CLI update handler
export -f handle_check_cli_updates      # CLI update check
export -f handle_update_status          # Update status check
export -f handle_rollback               # Rollback handler

# Internal functions are NOT exported (marked with _ prefix)
# This keeps the namespace clean and makes it clear what's public vs internal 