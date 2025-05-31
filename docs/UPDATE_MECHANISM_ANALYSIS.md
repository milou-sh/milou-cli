# Milou CLI Update Mechanism Analysis

## Overview

This document analyzes the current update mechanism in Milou CLI and provides recommendations for improvements.

## Current Update Architecture

### 1. Update Module (`src/_update.sh`)

The update system is implemented in a comprehensive module with the following key components:

#### Core Functions:
- **Version Display**: Shows current system and service versions
- **Update Preview**: Displays what will be updated with version comparison
- **Rolling Updates**: Zero-downtime deployment mechanism
- **Backup Integration**: Automatic backup before updates
- **Self-Update**: CLI tool self-update capability

#### Key Features:
- **Smart Version Detection**: Reads versions from Docker containers and environment variables
- **Service Status Monitoring**: Shows running/stopped status for each service
- **Update Scope Control**: Supports selective service updates
- **Version Comparison**: Intelligent diff detection between current and target versions

### 2. Release Preparation (`scripts/prepare-release.sh`)

Handles repository preparation for GitHub releases:
- URL substitution for custom deployments
- Template customization for different organizations
- Backup creation during URL updates

### 3. Build and Push System (`scripts/build-and-push.sh`)

Current implementation has several issues and complexities.

## Issues Identified

### 1. Build Script Problems

#### **Inconsistent Logging**
- Mixed logging function calls (`milou_log` vs `log`)
- Inconsistent error handling patterns
- Some functions assume `milou_log` exists globally

#### **Complexity Issues**
- Over 1200 lines in a single script
- Multiple responsibilities mixed together
- Hard to maintain and debug

#### **Authentication Flow**
- Complex token validation with fallback patterns
- Multiple authentication sources handled inconsistently
- Error messages not always helpful

#### **Directory Structure Dependencies**
- Hard-coded assumptions about project layout
- Fragile path resolution
- Fails if directory structure changes

### 2. Update Mechanism Issues

#### **Version Management Complexity**
```bash
# Complex version extraction from containers
while IFS=$'\t' read -r container_name image_name; do
    if [[ "$container_name" =~ milou-(.+) ]]; then
        local service="${BASH_REMATCH[1]}"
        # Extract version from image name
        if [[ "$image_name" =~ :(.+)$ ]]; then
            version="${BASH_REMATCH[1]#v}"
        fi
    fi
done < <(docker ps -a --filter "name=milou-" --format "table {{.Names}}\t{{.Image}}" 2>/dev/null | tail -n +2)
```

#### **State Management**
- No centralized state management
- Version information scattered across different sources
- Difficult to track update history

#### **Error Recovery**
- Limited rollback capabilities
- No atomic update transactions
- Partial update failures can leave system in inconsistent state

## Recommended Improvements

### 1. Build Script Improvements (Implemented)

Created `build-and-push-improved.sh` with:

#### **Simplified Architecture**
- Consistent logging functions throughout
- Better error handling with context
- Modular function design
- Cleanup mechanisms

#### **Enhanced Error Handling**
```bash
handle_error() {
    local exit_code=$?
    local line_number=${1:-$LINENO}
    local function_name=${FUNCNAME[1]:-main}
    
    log "ERROR" "Script failed in function '$function_name' at line $line_number (exit code: $exit_code)"
    
    if [[ -n "${CLEANUP_REQUIRED:-}" ]]; then
        log "INFO" "Performing cleanup..."
        cleanup_on_exit
    fi
    
    exit $exit_code
}
```

#### **Improved Token Management**
- Clearer token validation
- Better error messages
- Consistent authentication flow

### 2. Update Mechanism Improvements

#### **Centralized State Management**

```bash
# Proposed state file structure
# ~/.milou/state.json
{
  "installation": {
    "version": "1.4.0",
    "install_date": "2025-01-30T10:30:00Z",
    "last_update": "2025-01-30T15:45:00Z",
    "update_channel": "stable"
  },
  "services": {
    "backend": {
      "version": "1.4.0",
      "image": "ghcr.io/milou-sh/milou/backend:1.4.0",
      "status": "running",
      "last_updated": "2025-01-30T15:45:00Z"
    },
    "frontend": {
      "version": "1.4.0", 
      "image": "ghcr.io/milou-sh/milou/frontend:1.4.0",
      "status": "running",
      "last_updated": "2025-01-30T15:45:00Z"
    }
  },
  "update_history": [
    {
      "from_version": "1.3.0",
      "to_version": "1.4.0",
      "timestamp": "2025-01-30T15:45:00Z",
      "success": true,
      "services_updated": ["backend", "frontend", "database"]
    }
  ]
}
```

#### **Atomic Updates with Rollback**

```bash
# Proposed update transaction system
perform_atomic_update() {
    local target_version="$1"
    local services=("${@:2}")
    
    # Create update transaction
    local transaction_id
    transaction_id=$(create_update_transaction "$target_version" "${services[@]}")
    
    # Pre-update validation
    if ! validate_update_preconditions "$target_version" "${services[@]}"; then
        rollback_transaction "$transaction_id"
        return 1
    fi
    
    # Create backup
    local backup_id
    backup_id=$(create_pre_update_backup "$transaction_id")
    
    # Perform update with rollback on failure
    if ! execute_update_transaction "$transaction_id"; then
        log "ERROR" "Update failed, initiating rollback..."
        rollback_transaction "$transaction_id"
        restore_from_backup "$backup_id"
        return 1
    fi
    
    # Validate post-update state
    if ! validate_post_update_state "$target_version" "${services[@]}"; then
        log "ERROR" "Post-update validation failed, rolling back..."
        rollback_transaction "$transaction_id"
        restore_from_backup "$backup_id"
        return 1
    fi
    
    # Commit transaction
    commit_transaction "$transaction_id"
    cleanup_backup "$backup_id"
    
    log "SUCCESS" "Update completed successfully"
    return 0
}
```

#### **Enhanced Version Management**

```bash
# Simplified version tracking
get_service_version() {
    local service="$1"
    
    # Check state file first
    if [[ -f "$MILOU_STATE_FILE" ]]; then
        jq -r ".services.${service}.version // \"unknown\"" "$MILOU_STATE_FILE" 2>/dev/null
    else
        # Fallback to container inspection
        docker inspect "milou-${service}" --format '{{index .Config.Labels "milou.version"}}' 2>/dev/null || echo "unknown"
    fi
}

update_service_state() {
    local service="$1"
    local version="$2"
    local status="$3"
    
    # Update state file atomically
    local temp_file
    temp_file=$(mktemp)
    
    jq --arg service "$service" \
       --arg version "$version" \
       --arg status "$status" \
       --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.services[$service] = {
         "version": $version,
         "status": $status,
         "last_updated": $timestamp
       }' "$MILOU_STATE_FILE" > "$temp_file"
    
    mv "$temp_file" "$MILOU_STATE_FILE"
}
```

### 3. Self-Update Improvements

#### **Progressive Update Strategy**
```bash
# Check for CLI updates separately from service updates
check_cli_updates() {
    local current_version="${SCRIPT_VERSION:-unknown}"
    local latest_version
    
    # Get latest release from GitHub
    latest_version=$(curl -s "https://api.github.com/repos/milou-sh/milou-cli/releases/latest" | \
                    jq -r '.tag_name // "unknown"' 2>/dev/null)
    
    if [[ "$latest_version" != "unknown" && "$latest_version" != "$current_version" ]]; then
        log "INFO" "📦 CLI update available: $current_version → $latest_version"
        return 0  # Update available
    fi
    
    return 1  # No update needed
}

perform_cli_self_update() {
    local target_version="$1"
    
    log "INFO" "🔄 Updating Milou CLI to version $target_version"
    
    # Download new version
    local temp_dir
    temp_dir=$(mktemp -d)
    
    if ! download_cli_release "$target_version" "$temp_dir"; then
        log "ERROR" "Failed to download CLI update"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Backup current installation
    local backup_path
    backup_path=$(create_cli_backup)
    
    # Install new version
    if ! install_cli_update "$temp_dir"; then
        log "ERROR" "Failed to install CLI update, restoring backup"
        restore_cli_backup "$backup_path"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Validate new installation
    if ! validate_cli_installation; then
        log "ERROR" "CLI update validation failed, restoring backup"
        restore_cli_backup "$backup_path"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
    rm -rf "$backup_path"
    
    log "SUCCESS" "✅ CLI updated successfully to version $target_version"
    return 0
}
```

### 4. Enhanced Update Commands

#### **New Update Commands**
```bash
# Enhanced update interface
milou update --check                    # Check for available updates
milou update --cli                      # Update only CLI
milou update --services                 # Update only services  
milou update --all                      # Update CLI and services
milou update --to-version 1.5.0         # Update to specific version
milou update --dry-run                  # Preview what would be updated
milou update --rollback                 # Rollback last update
milou update --history                  # Show update history
milou update --channel beta             # Switch update channel
```

#### **Update Channel Support**
```bash
# Support for different update channels
set_update_channel() {
    local channel="$1"  # stable, beta, alpha
    
    case "$channel" in
        "stable"|"beta"|"alpha")
            update_state_file ".installation.update_channel" "$channel"
            log "SUCCESS" "Update channel set to: $channel"
            ;;
        *)
            log "ERROR" "Invalid update channel: $channel"
            log "INFO" "Valid channels: stable, beta, alpha"
            return 1
            ;;
    esac
}
```

## Implementation Priority

### Phase 1: Critical Fixes (Immediate)
1. ✅ **Fix build script** - Implemented `build-and-push-improved.sh`
2. **Add state management** - Implement centralized state file
3. **Improve error handling** - Add atomic update transactions

### Phase 2: Enhanced Features (Next Sprint)
1. **Update channel support** - Stable/Beta/Alpha channels
2. **Rollback mechanism** - Safe rollback to previous versions
3. **Update history tracking** - Keep track of all updates

### Phase 3: Advanced Features (Future)
1. **Differential updates** - Only update changed components
2. **Background updates** - Non-disruptive update scheduling
3. **Health monitoring** - Post-update validation and monitoring

## Migration Strategy

### Existing Installations
1. **Detect current state** from Docker containers and configuration
2. **Create initial state file** with current versions
3. **Preserve existing functionality** during transition
4. **Gradual feature rollout** to avoid breaking changes

### Testing Strategy
1. **Unit tests** for update logic
2. **Integration tests** for full update workflows
3. **Rollback tests** to ensure recovery mechanisms work
4. **Performance tests** for large deployments

## Conclusion

The current update mechanism is functional but has complexity and reliability issues. The proposed improvements focus on:

1. **Simplification** - Cleaner, more maintainable code
2. **Reliability** - Atomic updates with rollback capabilities
3. **User Experience** - Better feedback, preview, and control
4. **State Management** - Centralized tracking of system state

The improved build script is ready for immediate use, and the update mechanism improvements can be implemented progressively without breaking existing functionality. 