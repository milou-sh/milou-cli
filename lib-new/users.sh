#!/bin/bash

# =============================================================================
# Milou CLI - Consolidated User Management Module
# All user management functionality in one organized module (500 lines max)
# =============================================================================

# Module guard to prevent multiple loading
if [[ "${MILOU_USERS_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_USERS_LOADED="true"

# Ensure logging is available
if ! command -v log >/dev/null 2>&1; then
    source "${BASH_SOURCE%/*}/utils.sh" 2>/dev/null || {
        echo "ERROR: Cannot load utilities module" >&2
        return 1
    }
fi

# =============================================================================
# User Configuration and Variables (Lines 1-50)
# =============================================================================

# Default user configuration
MILOU_USER="${MILOU_USER:-milou}"
MILOU_GROUP="${MILOU_GROUP:-milou}"
MILOU_HOME="${MILOU_HOME:-/home/$MILOU_USER}"
MILOU_SHELL="${MILOU_SHELL:-/bin/bash}"

# User switching protection
USER_SWITCH_IN_PROGRESS="${USER_SWITCH_IN_PROGRESS:-false}"

# User validation patterns
USERNAME_PATTERN="^[a-z_][a-z0-9_-]*$"
MIN_USERNAME_LENGTH=3
MAX_USERNAME_LENGTH=32

# Initialize user management
users_init() {
    log "DEBUG" "Initializing user management..."
    
    # Validate current environment
    if ! validate_user_environment; then
        log "WARN" "User environment validation failed"
        return 1
    fi
    
    log "DEBUG" "User management initialized"
    return 0
}

# Validate user environment
validate_user_environment() {
    # Check if we have necessary commands
    local required_commands=("id" "whoami" "getent")
    
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            log "ERROR" "Required command not found: $cmd"
            return 1
        fi
    done
    
    return 0
}

# =============================================================================
# User Validation and Checking Functions (Lines 51-150)
# =============================================================================

# Check if user exists
user_exists() {
    local username="${1:-$MILOU_USER}"
    
    if [[ -z "$username" ]]; then
        log "ERROR" "Username not provided"
        return 1
    fi
    
    id "$username" >/dev/null 2>&1
}

# Check if milou user exists
milou_user_exists() {
    user_exists "$MILOU_USER"
}

# Check if running as root
is_running_as_root() {
    [[ $EUID -eq 0 ]]
}

# Check if running as milou user
is_running_as_milou() {
    [[ "$(whoami)" == "$MILOU_USER" ]]
}

# Validate username format
validate_username() {
    local username="$1"
    
    if [[ -z "$username" ]]; then
        log "ERROR" "Username cannot be empty"
        return 1
    fi
    
    if [[ ${#username} -lt $MIN_USERNAME_LENGTH ]]; then
        log "ERROR" "Username too short (minimum $MIN_USERNAME_LENGTH characters)"
        return 1
    fi
    
    if [[ ${#username} -gt $MAX_USERNAME_LENGTH ]]; then
        log "ERROR" "Username too long (maximum $MAX_USERNAME_LENGTH characters)"
        return 1
    fi
    
    if [[ ! "$username" =~ $USERNAME_PATTERN ]]; then
        log "ERROR" "Invalid username format. Use only lowercase letters, numbers, underscore, and hyphen"
        return 1
    fi
    
    return 0
}

# Get user home directory
get_user_home() {
    local username="${1:-$MILOU_USER}"
    
    if ! user_exists "$username"; then
        log "ERROR" "User does not exist: $username"
        return 1
    fi
    
    getent passwd "$username" | cut -d: -f6
}

# Get milou user home directory
get_milou_home() {
    get_user_home "$MILOU_USER"
}

# Check if user has sudo privileges
user_has_sudo() {
    local username="${1:-$(whoami)}"
    
    # Check if user is in sudo group
    if groups "$username" 2>/dev/null | grep -q '\bsudo\b'; then
        return 0
    fi
    
    # Check if user is in wheel group (some distributions)
    if groups "$username" 2>/dev/null | grep -q '\bwheel\b'; then
        return 0
    fi
    
    # Check sudoers file (basic check)
    if [[ -f /etc/sudoers ]] && sudo -l -U "$username" >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

# Get user shell
get_user_shell() {
    local username="${1:-$MILOU_USER}"
    
    if ! user_exists "$username"; then
        log "ERROR" "User does not exist: $username"
        return 1
    fi
    
    getent passwd "$username" | cut -d: -f7
}

# Check if user is in group
user_in_group() {
    local username="$1"
    local groupname="$2"
    
    if [[ -z "$username" || -z "$groupname" ]]; then
        log "ERROR" "Username and groupname required"
        return 1
    fi
    
    groups "$username" 2>/dev/null | grep -q "\b$groupname\b"
}

# =============================================================================
# User Creation and Management (Lines 151-250)
# =============================================================================

# Create milou user
create_milou_user() {
    if ! is_running_as_root; then
        log "ERROR" "Root privileges required to create user"
        return 1
    fi
    
    if user_exists "$MILOU_USER"; then
        log "INFO" "User $MILOU_USER already exists"
        return 0
    fi
    
    log "STEP" "Creating user: $MILOU_USER"
    
    # Validate username
    if ! validate_username "$MILOU_USER"; then
        return 1
    fi
    
    # Create group first
    if ! getent group "$MILOU_GROUP" >/dev/null 2>&1; then
        groupadd "$MILOU_GROUP" || {
            log "ERROR" "Failed to create group: $MILOU_GROUP"
            return 1
        }
        log "DEBUG" "Created group: $MILOU_GROUP"
    fi
    
    # Create user
    useradd -m -g "$MILOU_GROUP" -s "$MILOU_SHELL" -d "$MILOU_HOME" "$MILOU_USER" || {
        log "ERROR" "Failed to create user: $MILOU_USER"
        return 1
    }
    
    # Add user to docker group if it exists
    if getent group docker >/dev/null 2>&1; then
        usermod -aG docker "$MILOU_USER" || {
            log "WARN" "Failed to add user to docker group"
        }
        log "DEBUG" "Added user to docker group"
    fi
    
    # Set up user directory permissions
    chown -R "$MILOU_USER:$MILOU_GROUP" "$MILOU_HOME"
    chmod 755 "$MILOU_HOME"
    
    # Create .milou config directory
    local config_dir="$MILOU_HOME/.milou"
    mkdir -p "$config_dir"
    chown "$MILOU_USER:$MILOU_GROUP" "$config_dir"
    chmod 700 "$config_dir"
    
    log "SUCCESS" "User created successfully: $MILOU_USER"
    return 0
}

# Delete milou user
delete_milou_user() {
    local force="${1:-false}"
    
    if ! is_running_as_root; then
        log "ERROR" "Root privileges required to delete user"
        return 1
    fi
    
    if ! user_exists "$MILOU_USER"; then
        log "INFO" "User $MILOU_USER does not exist"
        return 0
    fi
    
    if [[ "$force" != "true" ]]; then
        log "WARN" "This will permanently delete user $MILOU_USER and all their data"
        if ! ask_yes_no "Continue with user deletion?"; then
            log "INFO" "User deletion cancelled"
            return 0
        fi
    fi
    
    log "STEP" "Deleting user: $MILOU_USER"
    
    # Kill any processes owned by the user
    pkill -u "$MILOU_USER" 2>/dev/null || true
    sleep 2
    
    # Force kill if necessary
    pkill -9 -u "$MILOU_USER" 2>/dev/null || true
    
    # Delete user and home directory
    userdel -r "$MILOU_USER" 2>/dev/null || {
        log "WARN" "Failed to delete user with home directory, trying without"
        userdel "$MILOU_USER" || {
            log "ERROR" "Failed to delete user: $MILOU_USER"
            return 1
        }
    }
    
    # Delete group if it exists and is empty
    if getent group "$MILOU_GROUP" >/dev/null 2>&1; then
        groupdel "$MILOU_GROUP" 2>/dev/null || {
            log "DEBUG" "Group $MILOU_GROUP not deleted (may have other members)"
        }
    fi
    
    log "SUCCESS" "User deleted successfully: $MILOU_USER"
    return 0
}

# Reset milou user (delete and recreate)
reset_milou_user() {
    log "STEP" "Resetting user: $MILOU_USER"
    
    if user_exists "$MILOU_USER"; then
        delete_milou_user "true" || return 1
    fi
    
    create_milou_user || return 1
    
    log "SUCCESS" "User reset completed: $MILOU_USER"
    return 0
}

# =============================================================================
# User Switching and Environment Transfer (Lines 251-350)
# =============================================================================

# Switch to milou user
switch_to_milou_user() {
    local current_user
    current_user=$(whoami)
    
    if [[ "$current_user" == "$MILOU_USER" ]]; then
        log "DEBUG" "Already running as $MILOU_USER user"
        return 0
    fi
    
    # Check for infinite loop protection
    if [[ "$USER_SWITCH_IN_PROGRESS" == "true" ]]; then
        log "ERROR" "User switch already in progress - configuration issue detected"
        return 1
    fi
    
    if ! milou_user_exists; then
        if is_running_as_root; then
            log "INFO" "Creating $MILOU_USER user for secure operations..."
            create_milou_user || return 1
        else
            log "ERROR" "User $MILOU_USER does not exist. Run with sudo to create it automatically."
            return 1
        fi
    fi
    
    log "INFO" "Switching to $MILOU_USER user for secure operations..."
    
    # Find script path
    local script_path script_dir
    
    if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/milou.sh" ]]; then
        script_dir="$SCRIPT_DIR"
        script_path="$SCRIPT_DIR/milou.sh"
    else
        # Try to find milou.sh in common locations
        local search_paths=(
            "$(pwd)/milou.sh"
            "$(dirname "${BASH_SOURCE[0]}")/../milou.sh"
            "/opt/milou-cli/milou.sh"
            "/usr/local/bin/milou.sh"
        )
        
        for path in "${search_paths[@]}"; do
            if [[ -f "$path" ]]; then
                script_path="$path"
                script_dir="$(dirname "$path")"
                break
            fi
        done
    fi
    
    if [[ -z "$script_path" || ! -f "$script_path" ]]; then
        log "ERROR" "Cannot find milou.sh script for user switching"
        return 1
    fi
    
    # Prepare environment for transfer
    prepare_user_environment || {
        log "WARN" "Failed to prepare user environment"
    }
    
    # Build command to run as milou user
    local switch_cmd="cd '$script_dir' && USER_SWITCH_IN_PROGRESS=true '$script_path'"
    
    # Add original arguments if available
    if [[ -n "${ORIGINAL_ARGS:-}" ]]; then
        switch_cmd="$switch_cmd $ORIGINAL_ARGS"
    elif [[ $# -gt 0 ]]; then
        switch_cmd="$switch_cmd $(printf '%q ' "$@")"
    fi
    
    log "DEBUG" "Executing as $MILOU_USER: $switch_cmd"
    
    # Execute as milou user
    exec sudo -u "$MILOU_USER" -H bash -c "$switch_cmd"
}

# Prepare environment for user transfer
prepare_user_environment() {
    log "DEBUG" "Preparing environment for user transfer..."
    
    # Copy GitHub credentials if available
    copy_github_credentials_to_milou || {
        log "DEBUG" "GitHub credentials transfer failed"
    }
    
    # Copy Docker credentials if available
    copy_docker_credentials_to_milou || {
        log "DEBUG" "Docker credentials transfer failed"
    }
    
    # Ensure milou user can access necessary directories
    ensure_milou_access || {
        log "WARN" "Failed to ensure milou user access"
    }
    
    return 0
}

# Copy GitHub credentials to milou user
copy_github_credentials_to_milou() {
    local milou_home
    milou_home=$(get_milou_home) || return 1
    
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        log "DEBUG" "No GitHub token to transfer"
        return 1
    fi
    
    log "DEBUG" "Transferring GitHub credentials to milou user..."
    
    # Create secure config directory
    local config_dir="$milou_home/.milou"
    mkdir -p "$config_dir"
    chown "$MILOU_USER:$MILOU_GROUP" "$config_dir"
    chmod 700 "$config_dir"
    
    # Create temporary environment file
    local temp_env_file="$config_dir/.env.token.tmp"
    echo "GITHUB_TOKEN=${GITHUB_TOKEN}" > "$temp_env_file"
    chown "$MILOU_USER:$MILOU_GROUP" "$temp_env_file"
    chmod 600 "$temp_env_file"
    
    log "DEBUG" "GitHub token prepared for milou user"
    return 0
}

# Copy Docker credentials to milou user
copy_docker_credentials_to_milou() {
    local milou_home
    milou_home=$(get_milou_home) || return 1
    
    local current_user
    current_user=$(whoami)
    
    # Copy Docker config if it exists
    if [[ -f "$HOME/.docker/config.json" ]]; then
        log "DEBUG" "Copying Docker credentials to milou user..."
        
        local milou_docker_dir="$milou_home/.docker"
        mkdir -p "$milou_docker_dir"
        
        cp "$HOME/.docker/config.json" "$milou_docker_dir/" 2>/dev/null || {
            log "DEBUG" "Failed to copy Docker config"
            return 1
        }
        
        chown -R "$MILOU_USER:$MILOU_GROUP" "$milou_docker_dir"
        chmod 700 "$milou_docker_dir"
        chmod 600 "$milou_docker_dir/config.json"
        
        log "DEBUG" "Docker credentials copied successfully"
        return 0
    fi
    
    return 1
}

# Ensure milou user has access to necessary resources
ensure_milou_access() {
    local milou_home
    milou_home=$(get_milou_home) || return 1
    
    # Ensure milou user can access current directory
    local current_dir
    current_dir=$(pwd)
    
    # Check if current directory is accessible
    if ! sudo -u "$MILOU_USER" test -r "$current_dir"; then
        log "WARN" "Milou user cannot access current directory: $current_dir"
        
        # Try to make it accessible (if we have permission)
        if [[ -w "$current_dir" ]]; then
            chmod o+rx "$current_dir" 2>/dev/null || true
        fi
    fi
    
    return 0
}

# =============================================================================
# User Information and Status (Lines 351-450)
# =============================================================================

# Show user information
show_user_info() {
    local username="${1:-$(whoami)}"
    
    if ! user_exists "$username"; then
        log "ERROR" "User does not exist: $username"
        return 1
    fi
    
    log "INFO" "User Information: $username"
    
    # Basic user info
    local user_info
    user_info=$(getent passwd "$username")
    local uid gid home shell
    uid=$(echo "$user_info" | cut -d: -f3)
    gid=$(echo "$user_info" | cut -d: -f4)
    home=$(echo "$user_info" | cut -d: -f6)
    shell=$(echo "$user_info" | cut -d: -f7)
    
    echo "  UID: $uid"
    echo "  GID: $gid"
    echo "  Home: $home"
    echo "  Shell: $shell"
    
    # Group memberships
    local groups_list
    groups_list=$(groups "$username" 2>/dev/null | cut -d: -f2- | xargs)
    echo "  Groups: $groups_list"
    
    # Check special permissions
    if user_has_sudo "$username"; then
        echo "  Sudo: Yes"
    else
        echo "  Sudo: No"
    fi
    
    # Check if user is in docker group
    if user_in_group "$username" "docker"; then
        echo "  Docker: Yes"
    else
        echo "  Docker: No"
    fi
    
    # Home directory status
    if [[ -d "$home" ]]; then
        local home_size
        home_size=$(du -sh "$home" 2>/dev/null | cut -f1 || echo "unknown")
        echo "  Home size: $home_size"
        echo "  Home permissions: $(stat -c %A "$home" 2>/dev/null || echo "unknown")"
    else
        echo "  Home directory: Missing"
    fi
    
    return 0
}

# Show milou user status
show_milou_status() {
    log "INFO" "Milou User Status"
    
    if milou_user_exists; then
        show_user_info "$MILOU_USER"
        
        # Check milou-specific directories
        local milou_home
        milou_home=$(get_milou_home)
        
        if [[ -d "$milou_home/.milou" ]]; then
            echo "  Config directory: Exists"
            local config_size
            config_size=$(du -sh "$milou_home/.milou" 2>/dev/null | cut -f1 || echo "unknown")
            echo "  Config size: $config_size"
        else
            echo "  Config directory: Missing"
        fi
        
        # Check for credentials
        if [[ -f "$milou_home/.milou/.env.token.tmp" ]]; then
            echo "  GitHub token: Available"
        else
            echo "  GitHub token: Not found"
        fi
        
        if [[ -f "$milou_home/.docker/config.json" ]]; then
            echo "  Docker credentials: Available"
        else
            echo "  Docker credentials: Not found"
        fi
    else
        echo "  Status: User does not exist"
        echo "  Action: Run 'create_milou_user' to create"
    fi
    
    return 0
}

# List all users on system
list_system_users() {
    log "INFO" "System Users:"
    
    # Get all users with UID >= 1000 (regular users)
    while IFS=: read -r username _ uid gid _ home shell; do
        if [[ $uid -ge 1000 && $uid -lt 65534 ]]; then
            local status="active"
            if [[ ! -d "$home" ]]; then
                status="no-home"
            elif [[ "$shell" == "/usr/sbin/nologin" || "$shell" == "/bin/false" ]]; then
                status="no-login"
            fi
            
            printf "  %-20s UID:%-6s Home:%-25s Status:%s\n" "$username" "$uid" "$home" "$status"
        fi
    done < /etc/passwd
    
    return 0
}

# =============================================================================
# User Cleanup and Maintenance (Lines 451-500)
# =============================================================================

# Clean up user temporary files
cleanup_user_temp() {
    local username="${1:-$MILOU_USER}"
    
    if ! user_exists "$username"; then
        log "ERROR" "User does not exist: $username"
        return 1
    fi
    
    local user_home
    user_home=$(get_user_home "$username") || return 1
    
    log "STEP" "Cleaning temporary files for user: $username"
    
    # Clean common temporary locations
    local temp_dirs=(
        "$user_home/.milou"
        "$user_home/.cache"
        "$user_home/.tmp"
        "/tmp/milou-$username"
    )
    
    for temp_dir in "${temp_dirs[@]}"; do
        if [[ -d "$temp_dir" ]]; then
            log "DEBUG" "Cleaning directory: $temp_dir"
            
            # Remove temporary files older than 1 day
            find "$temp_dir" -type f -name "*.tmp" -mtime +1 -delete 2>/dev/null || true
            find "$temp_dir" -type f -name "*.temp" -mtime +1 -delete 2>/dev/null || true
            find "$temp_dir" -type f -name ".env.token.tmp" -delete 2>/dev/null || true
        fi
    done
    
    log "SUCCESS" "Temporary files cleaned for user: $username"
    return 0
}

# Validate user environment and fix common issues
validate_and_fix_user() {
    local username="${1:-$MILOU_USER}"
    
    if ! user_exists "$username"; then
        log "ERROR" "User does not exist: $username"
        return 1
    fi
    
    log "STEP" "Validating and fixing user environment: $username"
    
    local user_home
    user_home=$(get_user_home "$username") || return 1
    
    local issues_fixed=0
    
    # Check home directory permissions
    if [[ -d "$user_home" ]]; then
        local current_owner
        current_owner=$(stat -c %U "$user_home" 2>/dev/null)
        
        if [[ "$current_owner" != "$username" ]]; then
            log "INFO" "Fixing home directory ownership"
            chown -R "$username:$username" "$user_home" 2>/dev/null || {
                log "WARN" "Failed to fix home directory ownership"
            }
            ((issues_fixed++))
        fi
    else
        log "WARN" "Home directory missing: $user_home"
    fi
    
    # Check shell validity
    local user_shell
    user_shell=$(get_user_shell "$username")
    
    if [[ ! -x "$user_shell" ]]; then
        log "INFO" "Fixing invalid shell: $user_shell -> $MILOU_SHELL"
        usermod -s "$MILOU_SHELL" "$username" 2>/dev/null || {
            log "WARN" "Failed to fix user shell"
        }
        ((issues_fixed++))
    fi
    
    # Ensure user is in docker group if docker is available
    if command_exists docker && ! user_in_group "$username" "docker"; then
        if getent group docker >/dev/null 2>&1; then
            log "INFO" "Adding user to docker group"
            usermod -aG docker "$username" 2>/dev/null || {
                log "WARN" "Failed to add user to docker group"
            }
            ((issues_fixed++))
        fi
    fi
    
    if [[ $issues_fixed -gt 0 ]]; then
        log "SUCCESS" "Fixed $issues_fixed issues for user: $username"
    else
        log "SUCCESS" "User environment is valid: $username"
    fi
    
    return 0
}

# Initialize user management
users_init

# Export main functions for external use
export -f user_exists milou_user_exists is_running_as_root is_running_as_milou
export -f validate_username get_user_home get_milou_home user_has_sudo
export -f create_milou_user delete_milou_user reset_milou_user
export -f switch_to_milou_user prepare_user_environment
export -f show_user_info show_milou_status list_system_users
export -f cleanup_user_temp validate_and_fix_user 