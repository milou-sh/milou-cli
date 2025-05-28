#!/bin/bash

# =============================================================================
# Milou CLI Self-Update Module
# Based on PlexTrac's excellent self-updating mechanism
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Self-update configuration
readonly MILOU_CLI_REPO="milou-sh/milou-cli"
readonly GITHUB_API_BASE="https://api.github.com/repos"
readonly RELEASE_API_URL="${GITHUB_API_BASE}/${MILOU_CLI_REPO}/releases"

# Check for new CLI release
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

# Perform CLI self-update
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

# Update command handler with self-update option
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
# CLEAN PUBLIC API - Export only essential functions  
# =============================================================================

# Main CLI update functions (2 exports - CLEAN PUBLIC API)
export -f milou_self_update_check       # Check for CLI updates
export -f milou_update_cli              # Update CLI (main entry point)

# Internal functions are NOT exported (marked with _ prefix)
# This keeps the namespace clean and makes it clear what's public vs internal 