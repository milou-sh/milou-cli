#!/bin/bash

# =============================================================================
# Milou CLI - Error Recovery and Rollback System
# Enterprise-grade error recovery with automatic rollback capabilities
# Version: 4.0.0 - Critical Safety Implementation
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Module guard to prevent multiple loading
if [[ "${MILOU_ERROR_RECOVERY_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_ERROR_RECOVERY_LOADED="true"

# Ensure core modules are loaded
if [[ "${MILOU_CORE_LOADED:-}" != "true" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/_core.sh" || {
        echo "ERROR: Cannot load core module" >&2
        return 1
    }
fi

# =============================================================================
# ERROR RECOVERY CONFIGURATION
# =============================================================================

# Global recovery state
declare -g RECOVERY_ENABLED="${RECOVERY_ENABLED:-true}"
declare -g RECOVERY_SNAPSHOT_DIR="${SCRIPT_DIR:-$(pwd)}/backups/snapshots"
declare -g RECOVERY_LOG_DIR="${SCRIPT_DIR:-$(pwd)}/logs/recovery"
declare -g RECOVERY_MAX_SNAPSHOTS="${RECOVERY_MAX_SNAPSHOTS:-10}"

# Current operation tracking
declare -g RECOVERY_CURRENT_OPERATION=""
declare -g RECOVERY_SNAPSHOT_ID=""
declare -g RECOVERY_ROLLBACK_ACTIONS=()

# =============================================================================
# SYSTEM STATE MANAGEMENT
# =============================================================================

# Create complete system snapshot
create_system_snapshot() {
    local operation_name="$1"
    local quiet="${2:-false}"
    
    if [[ "$RECOVERY_ENABLED" != "true" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Recovery disabled, skipping snapshot"
        return 0
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🔄 Creating system snapshot for: $operation_name"
    
    # Create snapshot directory structure
    ensure_directory "$RECOVERY_SNAPSHOT_DIR" "755"
    ensure_directory "$RECOVERY_LOG_DIR" "755"
    
    # Generate unique snapshot ID
    local snapshot_id="snapshot_$(date +%Y%m%d_%H%M%S)_${operation_name// /_}"
    local snapshot_path="$RECOVERY_SNAPSHOT_DIR/$snapshot_id"
    
    # Create snapshot directory
    if ! mkdir -p "$snapshot_path"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to create snapshot directory"
        return 1
    fi
    
    # Save current environment
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "📝 Saving configuration state..."
    
    # Backup .env file
    if [[ -f "${SCRIPT_DIR:-$(pwd)}/.env" ]]; then
        cp "${SCRIPT_DIR:-$(pwd)}/.env" "$snapshot_path/env.backup" 2>/dev/null || true
    fi
    
    # Backup docker-compose files
    if [[ -f "${SCRIPT_DIR:-$(pwd)}/static/docker-compose.yml" ]]; then
        cp "${SCRIPT_DIR:-$(pwd)}/static/docker-compose.yml" "$snapshot_path/docker-compose.backup" 2>/dev/null || true
    fi
    
    # Save Docker state
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "🐳 Saving Docker state..."
    
    # List running containers
    docker ps --format "{{.Names}}" > "$snapshot_path/running_containers.list" 2>/dev/null || echo "" > "$snapshot_path/running_containers.list"
    
    # List all containers
    docker ps -a --format "{{.Names}}" > "$snapshot_path/all_containers.list" 2>/dev/null || echo "" > "$snapshot_path/all_containers.list"
    
    # List volumes
    docker volume ls --format "{{.Name}}" > "$snapshot_path/volumes.list" 2>/dev/null || echo "" > "$snapshot_path/volumes.list"
    
    # List networks
    docker network ls --format "{{.Name}}" > "$snapshot_path/networks.list" 2>/dev/null || echo "" > "$snapshot_path/networks.list"
    
    # Save system information
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "📊 Saving system information..."
    
    {
        echo "# Milou System Snapshot"
        echo "# Created: $(date)"
        echo "# Operation: $operation_name"
        echo "# Snapshot ID: $snapshot_id"
        echo ""
        echo "## System Info"
        echo "USER=$(whoami)"
        echo "PWD=$(pwd)"
        echo "SCRIPT_DIR=${SCRIPT_DIR:-$(pwd)}"
        echo "DOCKER_VERSION=$(docker --version 2>/dev/null || echo 'N/A')"
        echo "COMPOSE_VERSION=$(docker compose version 2>/dev/null || echo 'N/A')"
        echo ""
        echo "## Process Info"
        echo "PID=$$"
        echo "PPID=$PPID"
        echo "SHELL=$SHELL"
    } > "$snapshot_path/system_info.txt"
    
    # Save current working directory contents
    ls -la "${SCRIPT_DIR:-$(pwd)}" > "$snapshot_path/directory_listing.txt" 2>/dev/null || true
    
    # Create snapshot metadata
    {
        echo "SNAPSHOT_ID=$snapshot_id"
        echo "OPERATION=$operation_name"
        echo "TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "CREATED_BY=$(whoami)"
        echo "MILOU_VERSION=${VERSION:-unknown}"
    } > "$snapshot_path/metadata.env"
    
    # Set secure permissions
    chmod 600 "$snapshot_path"/* 2>/dev/null || true
    chmod 700 "$snapshot_path"
    
    # Export for global use (both ways to handle subshell issues)
    export RECOVERY_SNAPSHOT_ID="$snapshot_id"
    export RECOVERY_CURRENT_OPERATION="$operation_name"
    
    # Also write to a temporary file that can be sourced if needed
    {
        echo "export RECOVERY_SNAPSHOT_ID=\"$snapshot_id\""
        echo "export RECOVERY_CURRENT_OPERATION=\"$operation_name\""
    } > "$RECOVERY_SNAPSHOT_DIR/.last_snapshot_vars" 2>/dev/null || true
    
    [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ System snapshot created: $snapshot_id"
    
    # Cleanup old snapshots
    cleanup_old_snapshots "$quiet"
    
    echo "$snapshot_id"
    return 0
}

# Restore system from snapshot
restore_system_snapshot() {
    local snapshot_id="${1:-$RECOVERY_SNAPSHOT_ID}"
    local force="${2:-false}"
    local quiet="${3:-false}"
    
    if [[ -z "$snapshot_id" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "No snapshot ID provided for restoration"
        return 1
    fi
    
    local snapshot_path="$RECOVERY_SNAPSHOT_DIR/$snapshot_id"
    
    if [[ ! -d "$snapshot_path" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Snapshot not found: $snapshot_id"
        return 1
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "WARN" "🔄 Restoring system from snapshot: $snapshot_id"
    
    # Confirm unless forced
    if [[ "$force" != "true" && "${RECOVERY_AUTO_RESTORE:-false}" != "true" ]]; then
        if ! confirm "This will restore your system to a previous state. Continue?" "N"; then
            [[ "$quiet" != "true" ]] && milou_log "INFO" "Restoration cancelled by user"
            return 1
        fi
    fi
    
    # Stop services before restoration
    [[ "$quiet" != "true" ]] && milou_log "INFO" "⏹️  Stopping services for restoration..."
    if command -v docker_execute >/dev/null 2>&1; then
        docker_execute "stop" "" "true" 2>/dev/null || true
    else
        # Fallback for standalone execution
        docker compose down 2>/dev/null || true
    fi
    
    # Restore configuration files
    [[ "$quiet" != "true" ]] && milou_log "INFO" "📝 Restoring configuration files..."
    
    if [[ -f "$snapshot_path/env.backup" ]]; then
        cp "$snapshot_path/env.backup" "${SCRIPT_DIR:-$(pwd)}/.env" 2>/dev/null || true
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Restored .env file"
    fi
    
    if [[ -f "$snapshot_path/docker-compose.backup" ]]; then
        cp "$snapshot_path/docker-compose.backup" "${SCRIPT_DIR:-$(pwd)}/static/docker-compose.yml" 2>/dev/null || true
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Restored docker-compose.yml"
    fi
    
    # Note: We don't restore Docker containers/volumes automatically as that could cause data loss
    # Instead, we log what was there for manual recovery if needed
    
    [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ System configuration restored from snapshot"
    [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Docker containers and volumes were not automatically restored"
    [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Check $snapshot_path for container/volume lists if manual restoration needed"
    
    return 0
}

# Validate system state integrity
validate_system_state() {
    local quiet="${1:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "🔍 Validating system state integrity..."
    
    local errors=0
    
    # Check essential files exist
    local essential_files=(
        "${SCRIPT_DIR:-$(pwd)}/.env"
        "${SCRIPT_DIR:-$(pwd)}/static/docker-compose.yml"
        "${SCRIPT_DIR:-$(pwd)}/milou.sh"
    )
    
    for file in "${essential_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "Essential file missing: $file"
            ((errors++))
        fi
    done
    
    # Check Docker access
    if ! docker info >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Docker access failed"
        ((errors++))
    fi
    
    # Check configuration validity
    if [[ -f "${SCRIPT_DIR:-$(pwd)}/.env" ]]; then
        if command -v config_validate >/dev/null 2>&1; then
            if ! config_validate "${SCRIPT_DIR:-$(pwd)}/.env" "minimal" "true"; then
                [[ "$quiet" != "true" ]] && milou_log "ERROR" "Configuration validation failed"
                ((errors++))
            fi
        fi
    fi
    
    if [[ $errors -eq 0 ]]; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ System state validation passed"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "System state validation failed ($errors errors)"
        return 1
    fi
}

# Clean up partial operations
cleanup_failed_operations() {
    local quiet="${1:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "🧹 Cleaning up failed operations..."
    
    # Stop any hanging containers
    local hanging_containers
    hanging_containers=$(docker ps --filter "status=created" --filter "status=restarting" --format "{{.Names}}" 2>/dev/null || true)
    
    if [[ -n "$hanging_containers" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "INFO" "Cleaning up hanging containers..."
        echo "$hanging_containers" | xargs -r docker rm -f 2>/dev/null || true
    fi
    
    # Remove orphaned containers
    if docker ps -a --filter "label=milou" --filter "status=exited" --format "{{.Names}}" 2>/dev/null | grep -q .; then
        [[ "$quiet" != "true" ]] && milou_log "INFO" "Removing orphaned containers..."
        docker ps -a --filter "label=milou" --filter "status=exited" --format "{{.Names}}" | xargs -r docker rm 2>/dev/null || true
    fi
    
    # Clean up dangling images
    if docker images --filter "dangling=true" --format "{{.ID}}" 2>/dev/null | grep -q .; then
        [[ "$quiet" != "true" ]] && milou_log "INFO" "Cleaning up dangling images..."
        docker image prune -f 2>/dev/null || true
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Cleanup completed"
    return 0
}

# Clean up old snapshots
cleanup_old_snapshots() {
    local quiet="${1:-false}"
    
    if [[ ! -d "$RECOVERY_SNAPSHOT_DIR" ]]; then
        return 0
    fi
    
    # Count snapshots
    local snapshot_count
    snapshot_count=$(find "$RECOVERY_SNAPSHOT_DIR" -maxdepth 1 -type d -name "snapshot_*" | wc -l)
    
    if [[ $snapshot_count -le $RECOVERY_MAX_SNAPSHOTS ]]; then
        return 0
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "🧹 Cleaning up old snapshots (keeping $RECOVERY_MAX_SNAPSHOTS most recent)"
    
    # Remove oldest snapshots, keeping the most recent ones
    find "$RECOVERY_SNAPSHOT_DIR" -maxdepth 1 -type d -name "snapshot_*" -printf '%T@ %p\n' | \
        sort -n | \
        head -n -"$RECOVERY_MAX_SNAPSHOTS" | \
        cut -d' ' -f2- | \
        xargs -r rm -rf
    
    return 0
}

# =============================================================================
# AUTOMATIC ROLLBACK FRAMEWORK
# =============================================================================

# Safe operation wrapper with automatic rollback
safe_operation() {
    local operation_name="$1"
    local operation_function="$2"
    shift 2
    local operation_args=("$@")
    
    milou_log "INFO" "🛡️  Starting safe operation: $operation_name"
    
    # Create snapshot before operation
    local snapshot_id
    snapshot_id=$(create_system_snapshot "$operation_name" "true" 2>/dev/null)
    
    if [[ -z "$snapshot_id" ]]; then
        milou_log "ERROR" "Failed to create snapshot - aborting operation for safety"
        return 1
    fi
    
    # Clean the snapshot ID (remove any log output that might have leaked through)
    snapshot_id=$(echo "$snapshot_id" | tail -n 1 | grep -o "snapshot_[0-9_a-zA-Z]*" || echo "$snapshot_id")
    
    milou_log "DEBUG" "Created snapshot: $snapshot_id"
    
    # Clear rollback actions
    RECOVERY_ROLLBACK_ACTIONS=()
    
    # Execute operation with error handling
    local operation_result=0
    
    if "$operation_function" "${operation_args[@]}"; then
        milou_log "SUCCESS" "✅ Safe operation completed: $operation_name"
        
        # Validate system state after operation
        if validate_system_state "true"; then
            milou_log "DEBUG" "System state validation passed after operation"
        else
            milou_log "WARN" "System state validation failed - consider manual verification"
        fi
        
        operation_result=0
    else
        operation_result=$?
        milou_log "ERROR" "❌ Operation failed: $operation_name (exit code: $operation_result)"
        
        # Automatic rollback on failure
        milou_log "WARN" "🔄 Initiating automatic rollback..."
        
        if rollback_on_failure "$snapshot_id" "true"; then
            milou_log "SUCCESS" "✅ Automatic rollback completed successfully"
        else
            milou_log "ERROR" "❌ Automatic rollback failed - manual intervention required"
            milou_log "ERROR" "💡 Snapshot available for manual recovery: $snapshot_id"
        fi
    fi
    
    return $operation_result
}

# Register rollback action
register_rollback_action() {
    local action_description="$1"
    local action_command="$2"
    
    RECOVERY_ROLLBACK_ACTIONS+=("$action_description|$action_command")
    milou_log "DEBUG" "Registered rollback action: $action_description"
}

# Execute with safety wrapper
execute_with_safety() {
    local command="$1"
    local description="${2:-$command}"
    shift 2
    
    milou_log "DEBUG" "🛡️  Executing safely: $description"
    
    # Execute command and capture result
    if eval "$command" "$@"; then
        milou_log "DEBUG" "Safe execution successful: $description"
        return 0
    else
        local exit_code=$?
        milou_log "ERROR" "Safe execution failed: $description (exit code: $exit_code)"
        return $exit_code
    fi
}

# Rollback on failure
rollback_on_failure() {
    local snapshot_id="$1"
    local auto_mode="${2:-false}"
    
    milou_log "WARN" "🔄 Executing rollback procedure..."
    
    # Execute registered rollback actions first
    if [[ ${#RECOVERY_ROLLBACK_ACTIONS[@]} -gt 0 ]]; then
        milou_log "INFO" "Executing registered rollback actions..."
        
        for action in "${RECOVERY_ROLLBACK_ACTIONS[@]}"; do
            local description="${action%|*}"
            local command="${action#*|}"
            
            milou_log "DEBUG" "Rollback action: $description"
            
            if eval "$command" 2>/dev/null; then
                milou_log "DEBUG" "✅ Rollback action completed: $description"
            else
                milou_log "WARN" "⚠️ Rollback action failed: $description"
            fi
        done
    fi
    
    # Restore from snapshot
    if [[ -n "$snapshot_id" ]]; then
        if restore_system_snapshot "$snapshot_id" "$auto_mode" "false"; then
            milou_log "SUCCESS" "✅ System restored from snapshot"
            
            # Clean up failed operations
            cleanup_failed_operations "false"
            
            return 0
        else
            milou_log "ERROR" "❌ Snapshot restoration failed"
            return 1
        fi
    else
        milou_log "ERROR" "No snapshot available for rollback"
        return 1
    fi
}

# NEW FUNCTION: Report logs for unhealthy containers
report_unhealthy_services() {
    local services_to_check="$1"
    local quiet="$2"

    local unhealthy_containers
    unhealthy_containers=$(docker_get_unhealthy_containers "$services_to_check" "$quiet")

    if [[ -n "$unhealthy_containers" ]]; then
        [[ "$quiet" != "true" ]] && echo
        milou_log "ERROR" "Diagnostics for Unhealthy Containers"
        for container in $unhealthy_containers; do
            [[ "$quiet" != "true" ]] && echo -e "${YELLOW}--------------------------------------------------${NC}"
            milou_log "WARN" "Logs for failed container: $container"
            [[ "$quiet" != "true" ]] && echo -e "${YELLOW}--------------------------------------------------${NC}"
            
            # Grab and display logs
            docker logs "$container" --tail 50 2>&1 | sed 's/^/    /' || milou_log "WARN" "Could not retrieve logs for $container."
            
            [[ "$quiet" != "true" ]] && echo -e "${YELLOW}--------------------------------------------------${NC}"
            [[ "$quiet" != "true" ]] && echo
        done
        milou_log "INFO" "The logs above may indicate a problem within the application running inside the container (e.g., a coding bug or configuration error), not necessarily a problem with the CLI tool itself."
    fi
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

# Export core recovery functions
export -f safe_operation
export -f create_system_snapshot
export -f restore_system_snapshot
export -f cleanup_old_snapshots
export -f cleanup_failed_operations
export -f validate_system_state
export -f report_unhealthy_services

milou_log "DEBUG" "Error recovery module loaded successfully" 