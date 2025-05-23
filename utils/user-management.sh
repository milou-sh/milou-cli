#!/bin/bash

# =============================================================================
# User Management Utility Functions for Milou CLI
# Handles user creation, permissions, and security best practices
# =============================================================================

# Source utility functions
source "${BASH_SOURCE%/*}/utils.sh" 2>/dev/null || true

# Constants
readonly MILOU_USER="milou"
readonly MILOU_GROUP="milou"
readonly MILOU_HOME="/home/$MILOU_USER"
readonly MILOU_UID="${MILOU_UID:-1001}"
readonly MILOU_GID="${MILOU_GID:-1001}"

# =============================================================================
# User Detection and Creation
# =============================================================================

# Check if we're running as root
is_running_as_root() {
    [[ $EUID -eq 0 ]]
}

# Check if the milou user exists
milou_user_exists() {
    id "$MILOU_USER" >/dev/null 2>&1
}

# Check if current user is milou or has docker permissions
has_docker_permissions() {
    local current_user
    current_user=$(whoami)
    
    # Check if user is in docker group
    if groups "$current_user" 2>/dev/null | grep -q docker; then
        return 0
    fi
    
    # Check if user can run docker commands
    if docker info >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

# Get current user information
get_current_user_info() {
    local current_user
    current_user=$(whoami)
    local current_uid
    current_uid=$(id -u)
    local current_gid
    current_gid=$(id -g)
    local current_groups
    current_groups=$(groups "$current_user" 2>/dev/null | cut -d: -f2)
    
    echo "Current user: $current_user (UID: $current_uid, GID: $current_gid)"
    echo "Groups: $current_groups"
}

# Create milou user with proper configuration
create_milou_user() {
    log "STEP" "Creating milou user for secure operations..."
    
    if ! is_running_as_root; then
        error_exit "Root privileges required to create user. Please run with sudo."
    fi
    
    if milou_user_exists; then
        log "INFO" "User $MILOU_USER already exists"
        return 0
    fi
    
    # Create group first
    if ! getent group "$MILOU_GROUP" >/dev/null 2>&1; then
        log "DEBUG" "Creating group: $MILOU_GROUP (GID: $MILOU_GID)"
        if ! groupadd -g "$MILOU_GID" "$MILOU_GROUP" 2>/dev/null; then
            # If GID is taken, let system assign one
            log "DEBUG" "GID $MILOU_GID taken, letting system assign one"
            if ! groupadd "$MILOU_GROUP"; then
                error_exit "Failed to create group $MILOU_GROUP"
            fi
        fi
    fi
    
    # Ensure docker group exists BEFORE creating user
    if ! getent group docker >/dev/null 2>&1; then
        log "DEBUG" "Creating docker group"
        if ! groupadd docker; then
            log "WARN" "Failed to create docker group, user will be created without docker access"
            # Continue without docker group - we'll try to add it later
        fi
    fi
    
    # Create user with home directory
    log "DEBUG" "Creating user: $MILOU_USER (UID: $MILOU_UID)"
    local useradd_cmd=(
        useradd
        -m                    # Create home directory
        -s /bin/bash         # Set shell
        -g "$MILOU_GROUP"    # Primary group
        -c "Milou Service User"  # Comment
    )
    
    # Add docker group to user creation if it exists
    if getent group docker >/dev/null 2>&1; then
        useradd_cmd+=(-G docker)
        log "DEBUG" "Adding user to docker group during creation"
    fi
    
    # Try with specific UID first
    if ! "${useradd_cmd[@]}" -u "$MILOU_UID" "$MILOU_USER" 2>/dev/null; then
        # If UID is taken, let system assign one
        log "DEBUG" "UID $MILOU_UID taken, letting system assign one"
        if ! "${useradd_cmd[@]}" "$MILOU_USER"; then
            error_exit "Failed to create user $MILOU_USER"
        fi
    fi
    
    # Add user to docker group if not already done and group exists
    if getent group docker >/dev/null 2>&1; then
        if ! groups "$MILOU_USER" 2>/dev/null | grep -q docker; then
            log "DEBUG" "Adding $MILOU_USER to docker group"
            if ! usermod -aG docker "$MILOU_USER"; then
                log "WARN" "Failed to add $MILOU_USER to docker group"
            fi
        fi
    else
        log "WARN" "Docker group does not exist, user created without docker access"
        log "INFO" "💡 Install Docker first, then run: sudo usermod -aG docker $MILOU_USER"
    fi
    
    # Set up user environment
    setup_milou_user_environment
    
    log "SUCCESS" "User $MILOU_USER created successfully"
    log "INFO" "Home directory: $MILOU_HOME"
    log "INFO" "UID: $(id -u "$MILOU_USER"), GID: $(id -g "$MILOU_USER")"
    
    # Verify Docker access for the new user
    log "DEBUG" "Verifying Docker access for newly created user..."
    if command -v docker >/dev/null 2>&1; then
        # Quick verification that the user can access Docker
        if sudo -u "$MILOU_USER" bash -c "newgrp docker -c 'docker info'" >/dev/null 2>&1; then
            log "SUCCESS" "✅ Docker access verified for $MILOU_USER user"
        else
            log "WARN" "⚠️  Docker access verification failed for $MILOU_USER user"
            log "INFO" "💡 This may resolve after the first login or with 'newgrp docker'"
            
            # Run a quick diagnostic in debug mode
            if [[ "${VERBOSE:-false}" == "true" ]]; then
                log "DEBUG" "Running Docker diagnostic for troubleshooting..."
                diagnose_docker_access "$MILOU_USER" >/dev/null 2>&1 || true
            fi
        fi
    else
        log "WARN" "Docker not available for verification"
    fi
}

# Setup milou user environment
setup_milou_user_environment() {
    local milou_home
    milou_home=$(getent passwd "$MILOU_USER" | cut -d: -f6)
    
    if [[ -z "$milou_home" || ! -d "$milou_home" ]]; then
        log "WARN" "Milou user home directory not found, using /home/$MILOU_USER"
        milou_home="/home/$MILOU_USER"
        mkdir -p "$milou_home"
        chown "$MILOU_USER:$MILOU_GROUP" "$milou_home"
    fi
    
    log "DEBUG" "Setting up environment for $MILOU_USER in $milou_home"
    
    # Create necessary directories with proper structure
    local -a dirs=(
        "$milou_home/.milou"
        "$milou_home/.milou/backups"
        "$milou_home/.milou/cache"
        "$milou_home/.milou/logs"
        "$milou_home/.milou/ssl"
        "$milou_home/.milou/config"
        "$milou_home/bin"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            chown "$MILOU_USER:$MILOU_GROUP" "$dir"
            chmod 750 "$dir"
            log "DEBUG" "Created directory: $dir"
        fi
    done
    
    # Create or update .bashrc with enhanced configuration
    local bashrc_file="$milou_home/.bashrc"
    log "DEBUG" "Setting up bashrc: $bashrc_file"
    
    # Backup existing bashrc
    if [[ -f "$bashrc_file" ]]; then
        cp "$bashrc_file" "$bashrc_file.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    fi
    
    cat > "$bashrc_file" << 'EOF'
# .bashrc for milou user - Enhanced Milou CLI Environment

# Source system bashrc
[[ -f /etc/bashrc ]] && source /etc/bashrc
[[ -f ~/.bash_profile ]] && source ~/.bash_profile

# Milou-specific environment variables
export MILOU_HOME="$HOME"
export MILOU_CONFIG="$HOME/.milou"
export MILOU_USER="milou"

# Detect Milou CLI location
if [[ -d "$HOME/milou-cli" ]]; then
    export MILOU_CLI_HOME="$HOME/milou-cli"
elif [[ -d "/opt/milou-cli" ]]; then
    export MILOU_CLI_HOME="/opt/milou-cli"
elif [[ -d "/usr/local/milou-cli" ]]; then
    export MILOU_CLI_HOME="/usr/local/milou-cli"
else
    # Try to find it in common locations
    for location in "$HOME"/* "/opt"/* "/usr/local"/*; do
        if [[ -d "$location" && -f "$location/milou.sh" ]]; then
            export MILOU_CLI_HOME="$location"
            break
        fi
    done
fi

# Add Milou CLI to PATH
if [[ -n "$MILOU_CLI_HOME" && -d "$MILOU_CLI_HOME" ]]; then
    export PATH="$MILOU_CLI_HOME:$PATH"
else
    echo "⚠️  Warning: Milou CLI location not found"
fi

# Add user bin directory to PATH
[[ -d "$HOME/bin" ]] && export PATH="$HOME/bin:$PATH"

# Docker environment optimization
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1
export DOCKER_CLI_HINTS=false

# General environment improvements
export PATH="$PATH:/usr/local/bin:/usr/local/sbin"
export EDITOR="${EDITOR:-nano}"
export PAGER="${PAGER:-less}"

# Shell options for better experience
set -o vi 2>/dev/null || true  # Enable vi mode if available
shopt -s histappend 2>/dev/null || true  # Append to history
shopt -s checkwinsize 2>/dev/null || true  # Check window size after commands

# History configuration
export HISTCONTROL=ignoreboth
export HISTSIZE=10000
export HISTFILESIZE=20000

# Colorful output
export CLICOLOR=1
export LS_COLORS="di=1;34:ln=1;36:so=1;35:pi=1;33:ex=1;32:bd=1;33:cd=1;33:su=1;31:sg=1;31:tw=1;34:ow=1;34"

# Enhanced aliases
alias ll='ls -la --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias ls='ls --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'

# Milou-specific aliases and functions
if [[ -n "$MILOU_CLI_HOME" && -f "$MILOU_CLI_HOME/milou.sh" ]]; then
    alias milou='$MILOU_CLI_HOME/milou.sh'
    alias mstart='milou start'
    alias mstop='milou stop'
    alias mrestart='milou restart'
    alias mstatus='milou status'
    alias mlogs='milou logs'
    alias mhealth='milou health'
    alias mconfig='milou config'
    alias mbackup='milou backup'
    alias mssl='milou ssl'
    alias msecurity='milou security-check'
    
    # Helpful functions
    mcd() {
        cd "$MILOU_CLI_HOME" || return 1
    }
    
    mlog() {
        tail -f "$MILOU_CONFIG/milou.log"
    }
    
    mseclog() {
        tail -f "$MILOU_CONFIG/security.log"
    }
else
    echo "⚠️  Milou CLI not found - aliases not set"
fi

# Docker helper functions
dps() {
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

dlogs() {
    if [[ $# -eq 0 ]]; then
        docker compose logs -f
    else
        docker compose logs -f "$@"
    fi
}

dexec() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: dexec <container> [command]"
        return 1
    fi
    local container="$1"
    shift
    local cmd="${*:-/bin/bash}"
    docker exec -it "$container" $cmd
}

# Welcome message
if [[ $- == *i* ]]; then  # Only in interactive shells
    echo "🚀 Welcome to Milou CLI Environment!"
    echo "📁 Home: $MILOU_HOME"
    echo "⚙️  Config: $MILOU_CONFIG"
    if [[ -n "$MILOU_CLI_HOME" ]]; then
        echo "🔧 CLI: $MILOU_CLI_HOME"
        echo "💡 Use 'milou --help' for available commands"
        echo "📖 Quick commands: mstart, mstop, mstatus, mlogs"
    fi
    echo
fi
EOF

    # Set proper ownership and permissions for bashrc
    chown "$MILOU_USER:$MILOU_GROUP" "$bashrc_file"
    chmod 644 "$bashrc_file"
    
    # Create a profile file for non-interactive shells
    local profile_file="$milou_home/.profile"
    cat > "$profile_file" << EOF
# .profile for milou user
# This file is sourced by non-interactive shells

# Milou environment
export MILOU_HOME="$milou_home"
export MILOU_CONFIG="$milou_home/.milou"
export MILOU_USER="milou"

# Add Milou CLI to PATH if it exists
if [[ -d "$milou_home/milou-cli" ]]; then
    export MILOU_CLI_HOME="$milou_home/milou-cli"
    export PATH="$milou_home/milou-cli:\$PATH"
fi

# Add user bin to PATH
[[ -d "$milou_home/bin" ]] && export PATH="$milou_home/bin:\$PATH"

# Docker environment
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1
EOF
    
    chown "$MILOU_USER:$MILOU_GROUP" "$profile_file"
    chmod 644 "$profile_file"
    
    # Create a helpful milou command symlink in bin directory
    local bin_symlink="$milou_home/bin/milou"
    if [[ -d "$milou_home/milou-cli" && -f "$milou_home/milou-cli/milou.sh" ]]; then
        ln -sf "$milou_home/milou-cli/milou.sh" "$bin_symlink" 2>/dev/null || true
        chown -h "$MILOU_USER:$MILOU_GROUP" "$bin_symlink" 2>/dev/null || true
    fi
    
    # Create initial configuration file template
    local config_template="$milou_home/.milou/config/milou.conf"
    if [[ ! -f "$config_template" ]]; then
        cat > "$config_template" << EOF
# Milou CLI Configuration
# This file contains default settings for the milou user

# Logging
LOG_LEVEL=INFO
LOG_TO_FILE=true

# Security
AUTO_SECURITY_CHECKS=true
SECURITY_HARDENING=false

# Docker
DOCKER_CLEANUP_ON_STOP=false
DOCKER_PRUNE_FREQUENCY=weekly

# Backup
AUTO_BACKUP=false
BACKUP_RETENTION_DAYS=30

# SSL
SSL_AUTO_RENEWAL=true
SSL_CHECK_FREQUENCY=daily

# Updates
AUTO_UPDATE_CHECK=true
UPDATE_CHECK_FREQUENCY=daily
EOF
        chown "$MILOU_USER:$MILOU_GROUP" "$config_template"
        chmod 640 "$config_template"
    fi
    
    # Set proper ownership for home directory
    chown -R "$MILOU_USER:$MILOU_GROUP" "$milou_home"
    
    # Secure sensitive directories
    chmod 700 "$milou_home/.milou"
    
    log "SUCCESS" "Environment setup completed for $MILOU_USER"
    log "INFO" "Configuration directory: $milou_home/.milou"
    log "INFO" "CLI location will be auto-detected on login"
}

# =============================================================================
# User Migration and Switching
# =============================================================================

# Switch to milou user if not already running as milou
switch_to_milou_user() {
    local current_user
    current_user=$(whoami)
    
    if [[ "$current_user" == "$MILOU_USER" ]]; then
        log "DEBUG" "Already running as $MILOU_USER user"
        return 0
    fi
    
    # Check for infinite loop protection
    if [[ "${USER_SWITCH_IN_PROGRESS:-false}" == "true" ]]; then
        log "ERROR" "User switch already in progress - this indicates a configuration issue"
        return 1
    fi
    
    if ! milou_user_exists; then
        if is_running_as_root; then
            log "INFO" "Creating $MILOU_USER user for secure operations..."
            create_milou_user
        else
            error_exit "User $MILOU_USER does not exist. Please run with sudo to create it automatically."
        fi
    fi
    
    log "INFO" "Switching to $MILOU_USER user for secure operations..."
    
    # Enhanced script path detection - find the main script directory
    local script_path script_dir original_script_path
    
    # First, try to determine if we have SCRIPT_DIR from the main script
    if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/milou.sh" ]]; then
        script_dir="$SCRIPT_DIR"
        script_path="$SCRIPT_DIR/milou.sh"
        log "DEBUG" "Using SCRIPT_DIR from main script: $script_dir"
    else
        # Fallback: detect from current script location
        script_path="${BASH_SOURCE[0]}"
        
        # Handle symlinks and relative paths
        if [[ -L "$script_path" ]]; then
            original_script_path=$(readlink -f "$script_path")
            log "DEBUG" "Script is a symlink: $script_path -> $original_script_path"
            script_path="$original_script_path"
        else
            script_path=$(readlink -f "$script_path")
        fi
        
        # If we're in utils directory, go up one level
        script_dir=$(dirname "$script_path")
        if [[ "$(basename "$script_dir")" == "utils" ]]; then
            script_dir=$(dirname "$script_dir")
            log "DEBUG" "Detected utils directory, using parent: $script_dir"
        fi
        
        # Verify we found the main script
        if [[ ! -f "$script_dir/milou.sh" ]]; then
            # Try to find milou.sh in common locations
            local -a search_paths=(
                "$(pwd)"
                "$(dirname "$(pwd)")"
                "/opt/milou-cli"
                "/usr/local/milou-cli"
                "$HOME/milou-cli"
            )
            
            for search_path in "${search_paths[@]}"; do
                if [[ -f "$search_path/milou.sh" ]]; then
                    script_dir="$search_path"
                    break
                fi
            done
        fi
        
        script_path="$script_dir/milou.sh"
    fi
    
    log "DEBUG" "Detected script directory: $script_dir"
    log "DEBUG" "Main script path: $script_path"
    
    # Validate script directory
    if [[ ! -f "$script_path" ]]; then
        error_exit "Cannot locate main script: $script_path"
    fi
    
    if [[ ! -d "$script_dir/utils" ]]; then
        error_exit "Cannot locate utils directory: $script_dir/utils"
    fi
    
    # Ensure milou user has access to the script directory
    if is_running_as_root; then
        local milou_home target_dir
        milou_home=$(getent passwd "$MILOU_USER" | cut -d: -f6)
        
        # Enhanced home directory handling with automatic creation/repair
        if [[ -z "$milou_home" ]]; then
            log "WARN" "Milou user has no home directory configured, using /home/$MILOU_USER"
            milou_home="/home/$MILOU_USER"
            # Update the user's home directory in passwd
            usermod -d "$milou_home" "$MILOU_USER" 2>/dev/null || log "WARN" "Could not update user home directory"
        fi
        
        if [[ ! -d "$milou_home" ]]; then
            log "INFO" "Creating missing home directory for migration: $milou_home"
            if ! mkdir -p "$milou_home"; then
                error_exit "Failed to create home directory: $milou_home"
            fi
            
            # Set proper ownership and permissions
            chown "$MILOU_USER:$MILOU_GROUP" "$milou_home"
            chmod 750 "$milou_home"
            
            log "SUCCESS" "Home directory created for migration: $milou_home"
        elif [[ ! -w "$milou_home" ]]; then
            log "INFO" "Fixing permissions for home directory during migration: $milou_home"
            
            # Try to fix ownership and permissions
            chown "$MILOU_USER:$MILOU_GROUP" "$milou_home" || log "WARN" "Could not fix ownership for $milou_home"
            chmod 750 "$milou_home" || log "WARN" "Could not fix permissions for $milou_home"
        fi
        
        target_dir="$milou_home/milou-cli"
        
        # Smart copying strategy
        local needs_copy=false
        local needs_update=false
        
        if [[ ! -d "$target_dir" ]]; then
            log "INFO" "Copying Milou CLI to $MILOU_USER home directory..."
            needs_copy=true
        else
            # Check if update is needed by comparing modification times
            local source_mtime target_mtime
            source_mtime=$(stat -c %Y "$script_path" 2>/dev/null || echo "0")
            target_mtime=$(stat -c %Y "$target_dir/milou.sh" 2>/dev/null || echo "0")
            
            if [[ $source_mtime -gt $target_mtime ]]; then
                log "INFO" "Updating Milou CLI in $MILOU_USER home directory (source is newer)..."
                needs_update=true
            else
                log "DEBUG" "Milou CLI in $MILOU_USER directory is up-to-date"
            fi
        fi
        
        # Perform copy or update
        if [[ "$needs_copy" == true || "$needs_update" == true ]]; then
            # Create backup if updating
            if [[ "$needs_update" == true && -d "$target_dir" ]]; then
                local backup_dir="${target_dir}.backup.$(date +%Y%m%d_%H%M%S)"
                log "DEBUG" "Creating backup: $backup_dir"
                mv "$target_dir" "$backup_dir" || log "WARN" "Failed to create backup"
            fi
            
            # Copy the CLI
            if ! cp -r "$script_dir" "$milou_home/"; then
                error_exit "Failed to copy Milou CLI to $milou_home"
            fi
            
            # Set proper ownership and permissions
            if ! chown -R "$MILOU_USER:$MILOU_GROUP" "$target_dir"; then
                error_exit "Failed to set ownership for $target_dir"
            fi
            
            # Make scripts executable
            find "$target_dir" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || log "WARN" "Some scripts may not be executable"
            
            # Secure sensitive files
            find "$target_dir" -name "*.env" -o -name "*.key" -o -name "*.pem" | xargs chmod 600 2>/dev/null || true
            
            log "SUCCESS" "Milou CLI ready in $target_dir"
        fi
        
        # Enhanced environment variable preservation
        local -a env_vars=(
            "VERBOSE=$VERBOSE"
            "FORCE=$FORCE" 
            "DRY_RUN=$DRY_RUN"
            "INTERACTIVE=$INTERACTIVE"
            "AUTO_CREATE_USER=$AUTO_CREATE_USER"
            "SKIP_USER_CHECK=$SKIP_USER_CHECK"
            "USE_LATEST_IMAGES=$USE_LATEST_IMAGES"
            "USER_SWITCH_IN_PROGRESS=true"
        )
        
        # Add GitHub token if provided (but don't log it)
        if [[ -n "${GITHUB_TOKEN:-}" ]]; then
            env_vars+=("GITHUB_TOKEN=$GITHUB_TOKEN")
            log "DEBUG" "Preserving GitHub token in environment"
        fi
        
        # Add domain and SSL path if provided
        if [[ -n "${DOMAIN:-}" ]]; then
            env_vars+=("DOMAIN=$DOMAIN")
        fi
        if [[ -n "${SSL_PATH:-}" ]]; then
            env_vars+=("SSL_PATH=$SSL_PATH")
        fi
        if [[ -n "${ADMIN_EMAIL:-}" ]]; then
            env_vars+=("ADMIN_EMAIL=$ADMIN_EMAIL")
        fi
        
        # Preserve original command if set by enhanced main function
        if [[ -n "${ORIGINAL_COMMAND:-}" ]]; then
            env_vars+=("ORIGINAL_COMMAND=$ORIGINAL_COMMAND")
        fi
        
        # Build the execution command with enhanced state preservation
        local exec_cmd="cd '$target_dir' && env ${env_vars[*]} '$target_dir/milou.sh'"
        
        # CRITICAL FIX: Properly handle command preservation
        if [[ -n "${ORIGINAL_COMMAND:-}" ]]; then
            # Use the preserved original command
            exec_cmd+=" $ORIGINAL_COMMAND"
            
            # Add preserved original arguments if they exist
            if [[ -n "${ORIGINAL_ARGUMENTS_STR:-}" ]]; then
                # Use the pre-formatted string of arguments
                exec_cmd+=" $ORIGINAL_ARGUMENTS_STR"
                log "DEBUG" "Using preserved command: $ORIGINAL_COMMAND with arguments: $ORIGINAL_ARGUMENTS_STR"
            elif [[ -n "${ORIGINAL_ARGUMENTS:-}" ]]; then
                # Fallback to handling ORIGINAL_ARGUMENTS if it exists
                if declare -p ORIGINAL_ARGUMENTS 2>/dev/null | grep -q "declare -a"; then
                    # It's an array
                    for arg in "${ORIGINAL_ARGUMENTS[@]}"; do
                        exec_cmd+=" $(printf '%q' "$arg")"
                    done
                else
                    # It's a string, split it properly
                    exec_cmd+=" $ORIGINAL_ARGUMENTS"
                fi
                log "DEBUG" "Using preserved command: $ORIGINAL_COMMAND with fallback arguments"
            else
                log "DEBUG" "Using preserved command: $ORIGINAL_COMMAND (no arguments)"
            fi
        elif [[ $# -gt 0 ]]; then
            # Fallback: Use current arguments but we need to figure out the original command
            # The first argument should be the command that was passed to the original call
            local first_arg="$1"
            shift
            
            # Check if first argument looks like a command
            case "$first_arg" in
                setup|start|stop|restart|status|logs|health|config|validate|backup|restore|update|ssl|cleanup|shell|debug-images|diagnose|user-status|create-user|migrate-user|security-check|security-harden|security-report)
                    exec_cmd+=" $first_arg"
                    for arg in "$@"; do
                        exec_cmd+=" $(printf '%q' "$arg")"
                    done
                    log "DEBUG" "Detected command from arguments: $first_arg"
                    ;;
                *)
                    # Not a recognized command, treat all as arguments to some unknown command
                    exec_cmd+=" $(printf '%q' "$first_arg")"
                    for arg in "$@"; do
                        exec_cmd+=" $(printf '%q' "$arg")"
                    done
                    log "DEBUG" "Using all arguments as-is: $first_arg $*"
                    ;;
            esac
        else
            # No arguments provided - this might be an issue, but let's continue
            log "WARN" "No command or arguments provided during user switch"
        fi
        
        # CRITICAL FIX: Ensure docker group membership is active in the new session
        # Use newgrp docker to activate the docker group for the milou user
        local enhanced_exec_cmd="newgrp docker -c \"$exec_cmd\""
        
        log "DEBUG" "Executing as $MILOU_USER in directory: $target_dir"
        log "DEBUG" "Enhanced command with docker group activation: $enhanced_exec_cmd"
        
        # Try with newgrp first, but have fallback if it fails
        if ! sudo -u "$MILOU_USER" -H bash -c "newgrp docker -c 'echo test'" >/dev/null 2>&1; then
            log "WARN" "newgrp docker failed, trying alternative approach..."
            # Alternative: use sg (set group) command if available
            if command -v sg >/dev/null 2>&1; then
                enhanced_exec_cmd="sg docker -c \"$exec_cmd\""
                log "DEBUG" "Using sg command for docker group activation"
            else
                log "WARN" "Neither newgrp nor sg available, running without explicit docker group activation"
                enhanced_exec_cmd="$exec_cmd"
            fi
        fi
        
        # Execute with proper environment and working directory
        exec sudo -u "$MILOU_USER" -H bash -c "$enhanced_exec_cmd"
        
    else
        error_exit "Cannot switch to $MILOU_USER user without root privileges"
    fi
}

# Enhanced migration with better error handling and validation
migrate_to_milou_user() {
    log "STEP" "Migrating existing installation to $MILOU_USER user..."
    
    if ! is_running_as_root; then
        error_exit "Root privileges required for migration. Please run with sudo."
    fi
    
    if ! milou_user_exists; then
        create_milou_user
    fi
    
    local milou_home
    milou_home=$(getent passwd "$MILOU_USER" | cut -d: -f6)
    
    if [[ -z "$milou_home" || ! -d "$milou_home" ]]; then
        if [[ -z "$milou_home" ]]; then
            log "WARN" "Milou user has no home directory configured, using /home/$MILOU_USER"
            milou_home="/home/$MILOU_USER"
            # Update the user's home directory in passwd
            usermod -d "$milou_home" "$MILOU_USER" 2>/dev/null || log "WARN" "Could not update user home directory"
        fi
        
        if [[ ! -d "$milou_home" ]]; then
            log "INFO" "Creating missing home directory for migration: $milou_home"
            if ! mkdir -p "$milou_home"; then
                error_exit "Failed to create home directory: $milou_home"
            fi
            
            # Set proper ownership and permissions
            chown "$MILOU_USER:$MILOU_GROUP" "$milou_home"
            chmod 750 "$milou_home"
            
            log "SUCCESS" "Home directory created for migration: $milou_home"
        fi
    elif [[ ! -w "$milou_home" ]]; then
        log "INFO" "Fixing permissions for home directory during migration: $milou_home"
        
        # Try to fix ownership and permissions
        chown "$MILOU_USER:$MILOU_GROUP" "$milou_home" || log "WARN" "Could not fix ownership for $milou_home"
        chmod 750 "$milou_home" || log "WARN" "Could not fix permissions for $milou_home"
    fi
    
    # Create target directories
    local target_config_dir="$milou_home/.milou"
    mkdir -p "$target_config_dir"/{backups,cache,logs,ssl}
    
    # Migrate configuration files with validation
    local migrated_files=0
    
    if [[ -f "$ENV_FILE" ]]; then
        log "INFO" "Migrating configuration file: $ENV_FILE"
        if cp "$ENV_FILE" "$target_config_dir/" && chmod 600 "$target_config_dir/.env"; then
            ((migrated_files++))
            log "SUCCESS" "Configuration file migrated"
        else
            log "WARN" "Failed to migrate configuration file"
        fi
    fi
    
    # Migrate configuration directory contents
    if [[ -d "$CONFIG_DIR" && "$CONFIG_DIR" != "$target_config_dir" ]]; then
        log "INFO" "Migrating configuration directory contents..."
        local config_count=0
        
        for item in "$CONFIG_DIR"/*; do
            [[ -e "$item" ]] || continue
            local basename=$(basename "$item")
            
            # Skip if it's the target directory itself
            [[ "$item" -ef "$target_config_dir" ]] && continue
            
            if cp -r "$item" "$target_config_dir/"; then
                ((config_count++))
                log "DEBUG" "Migrated: $basename"
            else
                log "WARN" "Failed to migrate: $basename"
            fi
        done
        
        if [[ $config_count -gt 0 ]]; then
            ((migrated_files++))
            log "SUCCESS" "Migrated $config_count configuration items"
        fi
    fi
    
    # Migrate SSL certificates with validation
    if [[ -d "./ssl" ]]; then
        log "INFO" "Migrating SSL certificates..."
        local ssl_target="$milou_home/ssl"
        
        if cp -r "./ssl" "$milou_home/" && chown -R "$MILOU_USER:$MILOU_GROUP" "$ssl_target"; then
            chmod -R 750 "$ssl_target"
            find "$ssl_target" -name "*.key" -exec chmod 600 {} \; 2>/dev/null || true
            ((migrated_files++))
            log "SUCCESS" "SSL certificates migrated to $ssl_target"
        else
            log "WARN" "Failed to migrate SSL certificates"
        fi
    fi
    
    # Migrate backups if they exist
    if [[ -d "$BACKUP_DIR" && "$BACKUP_DIR" != "$target_config_dir/backups" ]]; then
        log "INFO" "Migrating backup files..."
        local backup_count=0
        
        for backup in "$BACKUP_DIR"/*; do
            [[ -e "$backup" ]] || continue
            if cp "$backup" "$target_config_dir/backups/"; then
                ((backup_count++))
            fi
        done
        
        if [[ $backup_count -gt 0 ]]; then
            log "SUCCESS" "Migrated $backup_count backup files"
        fi
    fi
    
    # Set final ownership and permissions
    chown -R "$MILOU_USER:$MILOU_GROUP" "$target_config_dir"
    chmod -R 750 "$target_config_dir"
    
    # Secure sensitive files
    find "$target_config_dir" -name "*.env" -o -name "*.key" -o -name "*.pem" | xargs chmod 600 2>/dev/null || true
    
    # Ensure Docker permissions are correct
    fix_docker_permissions
    
    # Update milou user's bashrc to point to the right directories
    local milou_bashrc="$milou_home/.bashrc"
    if [[ -f "$milou_bashrc" ]]; then
        # Update paths in bashrc
        sed -i "s|export MILOU_CONFIG=.*|export MILOU_CONFIG=\"$target_config_dir\"|" "$milou_bashrc"
        chown "$MILOU_USER:$MILOU_GROUP" "$milou_bashrc"
    fi
    
    log "SUCCESS" "Migration to $MILOU_USER user completed"
    log "INFO" "Migrated $migrated_files categories of files"
    log "INFO" "Configuration directory: $target_config_dir"
    
    return 0
}

# Fix Docker permissions for milou user
fix_docker_permissions() {
    log "DEBUG" "Ensuring proper Docker permissions for $MILOU_USER..."
    
    # Ensure docker group exists
    if ! getent group docker >/dev/null 2>&1; then
        log "INFO" "Creating docker group..."
        if ! groupadd docker; then
            log "ERROR" "Failed to create docker group"
            return 1
        fi
    fi
    
    # Add milou user to docker group if not already
    if ! groups "$MILOU_USER" 2>/dev/null | grep -q docker; then
        log "DEBUG" "Adding $MILOU_USER to docker group..."
        if usermod -aG docker "$MILOU_USER"; then
            log "SUCCESS" "User $MILOU_USER added to docker group"
        else
            log "ERROR" "Failed to add $MILOU_USER to docker group"
            return 1
        fi
    else
        log "DEBUG" "User $MILOU_USER is already in docker group"
    fi
    
    # Fix permissions on Docker socket if needed and it exists
    if [[ -S /var/run/docker.sock ]]; then
        local socket_group socket_perms
        socket_group=$(stat -c %G /var/run/docker.sock 2>/dev/null || echo "root")
        socket_perms=$(stat -c %a /var/run/docker.sock 2>/dev/null || echo "000")
        
        log "DEBUG" "Docker socket permissions: $socket_perms, group: $socket_group"
        
        if [[ "$socket_group" != "docker" ]]; then
            log "DEBUG" "Fixing Docker socket group ownership..."
            if chgrp docker /var/run/docker.sock 2>/dev/null; then
                log "SUCCESS" "Docker socket group fixed"
            else
                log "WARN" "Could not change Docker socket group (may require root)"
            fi
        fi
        
        # Ensure socket is group writable
        if [[ ! "$socket_perms" =~ ^[0-9]*[2367][0-9]*$ ]]; then  # Check if group has write permission
            log "DEBUG" "Fixing Docker socket permissions..."
            if chmod g+w /var/run/docker.sock 2>/dev/null; then
                log "SUCCESS" "Docker socket permissions fixed"
            else
                log "WARN" "Could not fix Docker socket permissions (may require root)"
            fi
        fi
    else
        log "WARN" "Docker socket not found at /var/run/docker.sock"
    fi
    
    # Test Docker access for milou user
    if sudo -u "$MILOU_USER" docker info >/dev/null 2>&1; then
        log "SUCCESS" "Docker access verified for $MILOU_USER user"
        return 0
    else
        log "WARN" "Docker access test failed for $MILOU_USER user"
        log "INFO" "💡 This might be resolved by logging out and back in, or running: newgrp docker"
        return 1
    fi
}

# =============================================================================
# Security Validation
# =============================================================================

# Validate current user has appropriate permissions
validate_user_permissions() {
    log "DEBUG" "Validating user permissions..."
    
    local current_user
    current_user=$(whoami)
    local issues=0
    
    # Check if running as root (not recommended)
    if is_running_as_root; then
        log "WARN" "Running as root user - not recommended for security"
        log "INFO" "💡 Consider creating and using the $MILOU_USER user instead"
        ((issues++))
    fi
    
    # Check Docker access
    if ! has_docker_permissions; then
        log "ERROR" "Current user ($current_user) does not have Docker permissions"
        log "INFO" "💡 Add user to docker group: sudo usermod -aG docker $current_user"
        log "INFO" "💡 Or switch to $MILOU_USER user: sudo -u $MILOU_USER"
        ((issues++))
    else
        log "SUCCESS" "Docker permissions verified for user: $current_user"
    fi
    
    # Check file permissions on critical paths
    local -a critical_paths=("$SCRIPT_DIR" "$ENV_FILE" "$CONFIG_DIR")
    for path in "${critical_paths[@]}"; do
        if [[ -e "$path" ]]; then
            if [[ ! -r "$path" ]]; then
                log "ERROR" "No read permission for: $path"
                ((issues++))
            fi
            if [[ -d "$path" && ! -w "$path" ]]; then
                log "ERROR" "No write permission for directory: $path"
                ((issues++))
            fi
        fi
    done
    
    return $issues
}

# Security hardening for milou user
harden_milou_user() {
    log "STEP" "Applying security hardening for $MILOU_USER user..."
    
    if ! is_running_as_root; then
        log "WARN" "Root privileges required for security hardening"
        return 1
    fi
    
    if ! milou_user_exists; then
        log "ERROR" "User $MILOU_USER does not exist"
        return 1
    fi
    
    local milou_home
    milou_home=$(getent passwd "$MILOU_USER" | cut -d: -f6)
    
    # Disable password login (use key-based auth only)
    if command -v passwd >/dev/null 2>&1; then
        passwd -l "$MILOU_USER" >/dev/null 2>&1 || log "WARN" "Could not lock password for $MILOU_USER"
    fi
    
    # Set restrictive permissions on home directory
    chmod 750 "$milou_home"
    
    # Secure configuration directory
    if [[ -d "$milou_home/.milou" ]]; then
        chmod -R 750 "$milou_home/.milou"
        # Make sensitive files even more restrictive
        find "$milou_home/.milou" -name "*.env" -o -name "*.key" -o -name "*.pem" | xargs chmod 600 2>/dev/null || true
    fi
    
    # Create sudoers entry for limited privileges if needed
    local sudoers_file="/etc/sudoers.d/milou"
    if [[ ! -f "$sudoers_file" ]]; then
        cat > "$sudoers_file" << EOF
# Milou user sudo privileges
# Allow milou user to manage Docker and systemd services
$MILOU_USER ALL=(root) NOPASSWD: /usr/bin/docker, /bin/systemctl start docker, /bin/systemctl stop docker, /bin/systemctl restart docker, /bin/systemctl status docker
EOF
        chmod 440 "$sudoers_file"
        log "INFO" "Created sudoers configuration for $MILOU_USER"
    fi
    
    log "SUCCESS" "Security hardening applied for $MILOU_USER user"
}

# =============================================================================
# User Environment Validation
# =============================================================================

# Validate milou user environment and CLI accessibility
validate_milou_user_environment() {
    log "DEBUG" "Validating milou user environment..."
    
    if ! milou_user_exists; then
        log "ERROR" "Milou user does not exist"
        return 1
    fi
    
    local milou_home issues=0
    milou_home=$(getent passwd "$MILOU_USER" | cut -d: -f6)
    
    if [[ -z "$milou_home" || ! -d "$milou_home" ]]; then
        if [[ -z "$milou_home" ]]; then
            log "ERROR" "Milou user has no home directory configured"
            log "INFO" "💡 Try: sudo usermod -d /home/$MILOU_USER $MILOU_USER"
        else
            log "ERROR" "Milou user home directory not found: $milou_home"
            log "INFO" "💡 Try: sudo mkdir -p $milou_home && sudo chown $MILOU_USER:$MILOU_GROUP $milou_home"
        fi
        ((issues++))
        # Set a fallback home directory for subsequent checks
        milou_home="/home/$MILOU_USER"
    fi
    
    # Check CLI accessibility
    local cli_locations=(
        "$milou_home/milou-cli/milou.sh"
        "$milou_home/bin/milou"
        "/opt/milou-cli/milou.sh"
        "/usr/local/milou-cli/milou.sh"
    )
    
    local cli_found=false
    for cli_path in "${cli_locations[@]}"; do
        if [[ -f "$cli_path" && -x "$cli_path" ]]; then
            log "SUCCESS" "Milou CLI found at: $cli_path"
            cli_found=true
            break
        fi
    done
    
    if [[ "$cli_found" != true ]]; then
        log "ERROR" "Milou CLI not found in expected locations"
        log "INFO" "💡 Checked: ${cli_locations[*]}"
        ((issues++))
    fi
    
    # Check configuration directory
    local config_dir="$milou_home/.milou"
    if [[ ! -d "$config_dir" ]]; then
        log "WARN" "Configuration directory missing: $config_dir"
        ((issues++))
    else
        log "SUCCESS" "Configuration directory exists: $config_dir"
        
        # Check subdirectories
        local -a required_dirs=("backups" "cache" "logs" "ssl" "config")
        for dir in "${required_dirs[@]}"; do
            if [[ ! -d "$config_dir/$dir" ]]; then
                log "WARN" "Missing configuration subdirectory: $config_dir/$dir"
            fi
        done
    fi
    
    # Check Docker permissions
    if ! sudo -u "$MILOU_USER" groups 2>/dev/null | grep -q docker; then
        log "WARN" "Milou user not in docker group"
        ((issues++))
    else
        log "SUCCESS" "Milou user has docker group membership"
    fi
    
    # Test Docker access
    if ! sudo -u "$MILOU_USER" docker info >/dev/null 2>&1; then
        log "WARN" "Milou user cannot access Docker daemon"
        ((issues++))
    else
        log "SUCCESS" "Milou user can access Docker daemon"
    fi
    
    # Check environment files
    local -a env_files=("$milou_home/.bashrc" "$milou_home/.profile")
    for env_file in "${env_files[@]}"; do
        if [[ -f "$env_file" ]]; then
            if grep -q "MILOU_" "$env_file"; then
                log "SUCCESS" "Milou environment configured in: $(basename "$env_file")"
            else
                log "WARN" "Milou environment not found in: $(basename "$env_file")"
            fi
        else
            log "WARN" "Environment file missing: $(basename "$env_file")"
        fi
    done
    
    if [[ $issues -eq 0 ]]; then
        log "SUCCESS" "Milou user environment validation passed"
        return 0
    else
        log "WARN" "Milou user environment validation found $issues issues"
        return 1
    fi
}

# Test milou user CLI functionality
test_milou_user_cli() {
    log "INFO" "Testing Milou CLI functionality as $MILOU_USER user..."
    
    if ! milou_user_exists; then
        log "ERROR" "Milou user does not exist"
        return 1
    fi
    
    local milou_home
    milou_home=$(getent passwd "$MILOU_USER" | cut -d: -f6)
    
    # Find CLI location
    local cli_script=""
    local -a possible_locations=(
        "$milou_home/milou-cli/milou.sh"
        "$milou_home/bin/milou"
        "/opt/milou-cli/milou.sh"
        "/usr/local/milou-cli/milou.sh"
    )
    
    for location in "${possible_locations[@]}"; do
        if [[ -f "$location" && -x "$location" ]]; then
            cli_script="$location"
            break
        fi
    done
    
    if [[ -z "$cli_script" ]]; then
        log "ERROR" "Cannot find executable Milou CLI script"
        return 1
    fi
    
    log "DEBUG" "Testing CLI at: $cli_script"
    
    # Test basic help command
    if sudo -u "$MILOU_USER" -H bash -c "cd '$milou_home' && '$cli_script' --help" >/dev/null 2>&1; then
        log "SUCCESS" "Milou CLI help command works"
    else
        log "ERROR" "Milou CLI help command failed"
        return 1
    fi
    
    # Test user status command
    if sudo -u "$MILOU_USER" -H bash -c "cd '$milou_home' && '$cli_script' user-status" >/dev/null 2>&1; then
        log "SUCCESS" "Milou CLI user-status command works"
    else
        log "WARN" "Milou CLI user-status command failed"
    fi
    
    log "SUCCESS" "Milou CLI functionality test completed"
    return 0
}

# =============================================================================
# User Management Interface (Enhanced)
# =============================================================================

# Interactive user setup
interactive_user_setup() {
    echo
    echo -e "${BOLD}${CYAN}🔐 User Management Setup${NC}"
    echo "For security reasons, Milou should not run as root."
    echo
    
    local current_user
    current_user=$(whoami)
    
    if is_running_as_root; then
        echo -e "${YELLOW}⚠️  Currently running as root user${NC}"
        echo
        echo "Recommended options:"
        echo "1) Create dedicated $MILOU_USER user (recommended)"
        echo "2) Continue as root (not recommended)"
        echo "3) Exit and run as non-root user"
        echo
        
        while true; do
            read -p "Choose option (1-3): " choice
            case $choice in
                1)
                    if ! milou_user_exists; then
                        create_milou_user
                    fi
                    if confirm "Switch to $MILOU_USER user now?" "Y"; then
                        switch_to_milou_user "$@"
                    fi
                    break
                    ;;
                2)
                    log "WARN" "Continuing as root - this is not recommended for production"
                    if ! confirm "Are you sure you want to continue as root?" "N"; then
                        exit 1
                    fi
                    break
                    ;;
                3)
                    log "INFO" "Please create a non-root user and run the script again"
                    exit 0
                    ;;
                *)
                    echo "Please enter 1, 2, or 3"
                    ;;
            esac
        done
    else
        if ! has_docker_permissions; then
            echo -e "${YELLOW}⚠️  Current user ($current_user) does not have Docker permissions${NC}"
            echo
            echo "Available options:"
            echo "1) Add current user to docker group (requires sudo)"
            echo "2) Create and switch to $MILOU_USER user (requires sudo)"
            echo "3) Continue without Docker permissions (will likely fail)"
            echo
            
            while true; do
                read -p "Choose option (1-3): " choice
                case $choice in
                    1)
                        log "INFO" "Adding $current_user to docker group..."
                        if sudo usermod -aG docker "$current_user"; then
                            log "SUCCESS" "User added to docker group"
                            log "INFO" "Please log out and log back in for changes to take effect"
                            log "INFO" "Or run: newgrp docker"
                        else
                            log "ERROR" "Failed to add user to docker group"
                        fi
                        break
                        ;;
                    2)
                        if ! milou_user_exists; then
                            sudo -E bash -c "$(declare -f create_milou_user); create_milou_user"
                        fi
                        if confirm "Switch to $MILOU_USER user now?" "Y"; then
                            switch_to_milou_user "$@"
                        fi
                        break
                        ;;
                    3)
                        log "WARN" "Continuing without Docker permissions - this will likely fail"
                        break
                        ;;
                    *)
                        echo "Please enter 1, 2, or 3"
                        ;;
                esac
            done
        else
            log "SUCCESS" "User $current_user has proper Docker permissions"
        fi
    fi
}

# Show user status information
show_user_status() {
    echo -e "${BOLD}👤 User Status Information${NC}"
    echo "=============================="
    echo
    
    # Current user info
    local current_user
    current_user=$(whoami)
    echo -e "${CYAN}Current User:${NC}"
    echo "  User: $current_user"
    echo "  UID: $(id -u), GID: $(id -g)"
    echo "  Groups: $(groups | cut -d: -f2 | tr ' ' ', ')"
    echo "  Running as root: $(is_running_as_root && echo "Yes" || echo "No")"
    echo "  Home directory: $HOME"
    echo
    
    # Milou user info
    echo -e "${CYAN}Milou User:${NC}"
    if milou_user_exists; then
        local milou_home
        milou_home=$(getent passwd "$MILOU_USER" | cut -d: -f6)
        
        echo "  Status: $MILOU_USER exists ✅"
        echo "  UID: $(id -u "$MILOU_USER"), GID: $(id -g "$MILOU_USER")"
        echo "  Home: $milou_home"
        echo "  Groups: $(groups "$MILOU_USER" 2>/dev/null | cut -d: -f2 | tr ' ' ', ' || echo "unknown")"
        
        # Check if milou user environment is set up
        if [[ -d "$milou_home/.milou" ]]; then
            echo "  Environment: Configured ✅"
        else
            echo "  Environment: Not configured ⚠️"
        fi
        
        # Check CLI accessibility
        local cli_accessible=false
        local cli_location=""
        local -a cli_paths=(
            "$milou_home/milou-cli/milou.sh"
            "$milou_home/bin/milou"
            "/opt/milou-cli/milou.sh"
            "/usr/local/milou-cli/milou.sh"
        )
        
        for path in "${cli_paths[@]}"; do
            if [[ -f "$path" && -x "$path" ]]; then
                cli_accessible=true
                cli_location="$path"
                break
            fi
        done
        
        if [[ "$cli_accessible" == true ]]; then
            echo "  CLI Access: Available ✅ ($cli_location)"
        else
            echo "  CLI Access: Not available ❌"
        fi
    else
        echo "  Status: $MILOU_USER does not exist ❌"
        echo "  💡 Run: sudo $0 create-user"
    fi
    echo
    
    # Docker access info
    echo -e "${CYAN}Docker Access:${NC}"
    echo "  Current user access: $(has_docker_permissions && echo "Yes ✅" || echo "No ❌")"
    
    if milou_user_exists; then
        local milou_docker_access=false
        local current_user
        current_user=$(whoami)
        
        echo "DEBUG: Checking Docker access for milou user. Current user: $current_user, Milou user: $MILOU_USER"
        
        if [[ "$current_user" == "$MILOU_USER" ]]; then
            # We're already running as milou user, use has_docker_permissions function
            echo "DEBUG: Running as milou user, checking permissions directly"
            if has_docker_permissions; then
                echo "DEBUG: has_docker_permissions returned true"
                milou_docker_access=true
            else
                echo "DEBUG: has_docker_permissions returned false"
            fi
        else
            # We're running as a different user, use sudo to check
            echo "DEBUG: Running as different user, using sudo to check"
            if sudo -u "$MILOU_USER" groups 2>/dev/null | grep -q docker; then
                if sudo -u "$MILOU_USER" docker info >/dev/null 2>&1; then
                    milou_docker_access=true
                fi
            fi
        fi
        
        echo "DEBUG: Final milou_docker_access value: $milou_docker_access"
        echo "  Milou user access: $([ "$milou_docker_access" == true ] && echo "Yes ✅" || echo "No ❌")"
    fi
    
    if command -v docker >/dev/null 2>&1; then
        local docker_version
        docker_version=$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',' || echo "unknown")
        echo "  Docker version: $docker_version"
        echo "  Docker daemon: $(docker info >/dev/null 2>&1 && echo "accessible ✅" || echo "not accessible ❌")"
        
        # Show running containers if accessible
        if docker info >/dev/null 2>&1; then
            local running_containers
            running_containers=$(docker ps --format "{{.Names}}" 2>/dev/null | wc -l)
            echo "  Running containers: $running_containers"
        fi
    else
        echo "  Docker: not installed ❌"
    fi
    echo
    
    # Environment and configuration info
    echo -e "${CYAN}Environment:${NC}"
    echo "  Script directory: $SCRIPT_DIR"
    echo "  Config directory: $CONFIG_DIR"
    
    if [[ -f "$ENV_FILE" ]]; then
        echo "  Configuration file: exists ✅"
        local config_perms
        config_perms=$(stat -c %a "$ENV_FILE" 2>/dev/null || stat -f %A "$ENV_FILE" 2>/dev/null)
        echo "  Config permissions: $config_perms $([ "$config_perms" -le 600 ] && echo "✅" || echo "⚠️")"
    else
        echo "  Configuration file: missing ❌"
    fi
    
    if [[ -d "./ssl" ]]; then
        echo "  SSL directory: exists ✅"
        local ssl_files
        ssl_files=$(find "./ssl" -name "*.crt" -o -name "*.key" 2>/dev/null | wc -l)
        echo "  SSL files: $ssl_files found"
    else
        echo "  SSL directory: missing ⚠️"
    fi
    echo
    
    # Security status
    echo -e "${CYAN}Security Status:${NC}"
    
    # File permissions check
    local security_issues=0
    
    if [[ -f "$ENV_FILE" ]]; then
        local env_perms
        env_perms=$(stat -c %a "$ENV_FILE" 2>/dev/null || stat -f %A "$ENV_FILE" 2>/dev/null)
        if [[ "$env_perms" -gt 600 ]]; then
            echo "  Config file security: Insecure permissions ($env_perms) ⚠️"
            ((security_issues++))
        else
            echo "  Config file security: Secure permissions ✅"
        fi
    fi
    
    # Check for running as root
    if is_running_as_root; then
        echo "  Root usage: Running as root (not recommended) ⚠️"
        ((security_issues++))
    else
        echo "  Root usage: Running as non-root user ✅"
    fi
    
    # Check Docker socket permissions
    if [[ -S /var/run/docker.sock ]]; then
        local socket_perms
        socket_perms=$(stat -c %a /var/run/docker.sock 2>/dev/null || echo "unknown")
        if [[ "$socket_perms" == "666" ]]; then
            echo "  Docker socket: Too permissive ($socket_perms) ⚠️"
            ((security_issues++))
        else
            echo "  Docker socket: Secure permissions ✅"
        fi
    fi
    
    echo "  Security issues found: $security_issues"
    echo
    
    # Recommendations
    if [[ $security_issues -gt 0 ]] || ! milou_user_exists || is_running_as_root; then
        echo -e "${CYAN}Recommendations:${NC}"
        
        if ! milou_user_exists; then
            echo "  • Create dedicated milou user: sudo $0 create-user"
        fi
        
        if is_running_as_root && milou_user_exists; then
            echo "  • Switch to milou user: sudo -u milou $0 [command]"
        fi
        
        if [[ $security_issues -gt 0 ]]; then
            echo "  • Run security assessment: $0 security-check"
            echo "  • Apply security hardening: sudo $0 security-harden"
        fi
        
        if ! has_docker_permissions && [[ "$current_user" != "root" ]]; then
            echo "  • Add Docker permissions: sudo usermod -aG docker $current_user"
        fi
        
        echo
    fi
    
    # Quick validation
    if milou_user_exists; then
        echo -e "${CYAN}Environment Validation:${NC}"
        if validate_milou_user_environment >/dev/null 2>&1; then
            echo "  Milou user environment: Valid ✅"
        else
            echo "  Milou user environment: Issues found ⚠️"
            echo "  💡 Run with --verbose for details"
        fi
    fi
}

# =============================================================================
# Utility Functions
# =============================================================================

# Ensure user management is properly set up
ensure_proper_user_setup() {
    log "DEBUG" "Ensuring proper user setup..."
    
    # If running as root, prioritize switching to milou user
    if is_running_as_root; then
        log "WARN" "Running as root - consider using dedicated user"
        
        # Check if auto-create-user flag is set
        if [[ "${AUTO_CREATE_USER:-false}" == "true" ]]; then
            log "INFO" "Auto-create-user mode enabled"
            
            if ! milou_user_exists; then
                log "INFO" "Automatically creating $MILOU_USER user"
                create_milou_user
            fi
            
            log "INFO" "Automatically switching to $MILOU_USER user for better security"
            switch_to_milou_user "$@"
            return $?  # This should never be reached due to exec, but just in case
        fi
        
        # Check if milou user exists and decide on automatic switch behavior
        if milou_user_exists; then
            # Interactive mode - ask user (but with better default)
            if [[ "${INTERACTIVE:-true}" == "true" ]]; then
                echo
                echo -e "${CYAN}💡 For better security, it's recommended to run Milou as the dedicated user.${NC}"
                if confirm "Switch to $MILOU_USER user for this operation?" "Y"; then
                    switch_to_milou_user "$@"
                    return $?  # This should never be reached due to exec, but just in case
                else
                    log "INFO" "Continuing as root (not recommended for production)"
                fi
            else
                # Non-interactive mode - auto switch
                log "INFO" "Non-interactive mode: automatically switching to $MILOU_USER user"
                switch_to_milou_user "$@"
                return $?  # This should never be reached due to exec, but just in case
            fi
        else
            # Milou user doesn't exist - offer to create it
            if [[ "${INTERACTIVE:-true}" == "true" ]]; then
                echo
                echo -e "${CYAN}🔐 No dedicated milou user found.${NC}"
                echo -e "${CYAN}For security and best practices, Milou should run as a dedicated user.${NC}"
                echo
                if confirm "Create and switch to $MILOU_USER user?" "Y"; then
                    create_milou_user
                    switch_to_milou_user "$@"
                    return $?  # This should never be reached due to exec, but just in case
                else
                    log "INFO" "Continuing as root (not recommended for production)"
                fi
            else
                # Non-interactive mode without auto-create-user flag
                log "WARN" "Non-interactive mode: milou user doesn't exist"
                log "INFO" "💡 Use --auto-create-user flag to automatically create milou user"
                log "INFO" "💡 Or create manually: sudo $0 create-user"
            fi
        fi
    fi
    
    # Validate permissions only if we're not switching users
    if ! validate_user_permissions_for_setup; then
        if [[ "${INTERACTIVE:-true}" == "true" ]]; then
            interactive_user_setup "$@"
        else
            # In non-interactive mode, provide clear guidance but don't fail hard
            log "WARN" "User permissions validation found issues"
            log "INFO" "💡 Consider running: sudo -u milou $0 [command]"
            log "INFO" "💡 Or create milou user: sudo $0 create-user"
            # Don't exit - let the operation continue with warnings
        fi
    fi
}

# Validate user permissions specifically for setup (more lenient than general validation)
validate_user_permissions_for_setup() {
    log "DEBUG" "Validating user permissions for setup..."
    
    local current_user
    current_user=$(whoami)
    local critical_issues=0
    
    # Check Docker access - this is critical
    if ! has_docker_permissions; then
        log "ERROR" "Current user ($current_user) does not have Docker permissions"
        log "INFO" "💡 Add user to docker group: sudo usermod -aG docker $current_user"
        log "INFO" "💡 Or switch to $MILOU_USER user: sudo -u $MILOU_USER"
        ((critical_issues++))
    else
        log "SUCCESS" "Docker permissions verified for user: $current_user"
    fi
    
    # Check file permissions on critical paths - only fail if we can't read/write
    local -a critical_paths=("$SCRIPT_DIR")
    for path in "${critical_paths[@]}"; do
        if [[ -e "$path" ]]; then
            if [[ ! -r "$path" ]]; then
                log "ERROR" "No read permission for: $path"
                ((critical_issues++))
            fi
            if [[ -d "$path" && ! -w "$path" ]]; then
                log "ERROR" "No write permission for directory: $path"
                ((critical_issues++))
            fi
        fi
    done
    
    # For setup purposes, being root is acceptable (just warn, don't count as critical issue)
    if is_running_as_root; then
        log "WARN" "Running as root user - not recommended for security"
        log "INFO" "💡 Consider creating and using the $MILOU_USER user instead"
        # Don't increment critical_issues for root - just warn
    fi
    
    return $critical_issues
}

# Clean up user management resources
cleanup_user_management() {
    log "DEBUG" "Cleaning up user management resources..."
    
    # Clean up temporary files
    local -a temp_patterns=(
        "/tmp/milou_user_*"
        "/tmp/milou_setup_*"
    )
    
    for pattern in "${temp_patterns[@]}"; do
        if compgen -G "$pattern" >/dev/null 2>&1; then
            rm -f $pattern 2>/dev/null || true
        fi
    done
}

# Export functions for use in other scripts
export -f is_running_as_root
export -f milou_user_exists
export -f has_docker_permissions
export -f create_milou_user
export -f switch_to_milou_user
export -f validate_user_permissions

# Comprehensive Docker access diagnostic
diagnose_docker_access() {
    local target_user="${1:-$(whoami)}"
    
    log "STEP" "Diagnosing Docker access for user: $target_user"
    echo
    
    local issues=0
    local warnings=0
    
    # Check if user exists
    if ! id "$target_user" >/dev/null 2>&1; then
        log "ERROR" "User '$target_user' does not exist"
        return 1
    fi
    
    # Check Docker installation
    log "INFO" "1. Docker Installation:"
    if command -v docker >/dev/null 2>&1; then
        local docker_version
        docker_version=$(docker --version 2>/dev/null | head -1 || echo "unknown")
        log "SUCCESS" "  ✅ Docker installed: $docker_version"
    else
        log "ERROR" "  ❌ Docker not installed"
        ((issues++))
    fi
    echo
    
    # Check Docker service
    log "INFO" "2. Docker Service Status:"
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active docker >/dev/null 2>&1; then
            log "SUCCESS" "  ✅ Docker service is active"
            if systemctl is-enabled docker >/dev/null 2>&1; then
                log "SUCCESS" "  ✅ Docker service is enabled (auto-start)"
            else
                log "WARN" "  ⚠️  Docker service not enabled for auto-start"
                ((warnings++))
            fi
        else
            log "ERROR" "  ❌ Docker service is not running"
            log "INFO" "     💡 Try: sudo systemctl start docker"
            ((issues++))
        fi
    else
        log "WARN" "  ⚠️  Cannot check service status (systemctl not available)"
        ((warnings++))
    fi
    echo
    
    # Check Docker group and user membership
    log "INFO" "3. Docker Group and User Membership:"
    if getent group docker >/dev/null 2>&1; then
        log "SUCCESS" "  ✅ Docker group exists"
        
        # Check if target user is in docker group
        if groups "$target_user" 2>/dev/null | grep -q docker; then
            log "SUCCESS" "  ✅ User '$target_user' is in docker group"
            
            # Check if group membership is active in current session
            if [[ "$target_user" == "$(whoami)" ]]; then
                if groups | grep -q docker; then
                    log "SUCCESS" "  ✅ Docker group membership is active in current session"
                else
                    log "WARN" "  ⚠️  Docker group membership not active in current session"
                    log "INFO" "     💡 Try: newgrp docker"
                    ((warnings++))
                fi
            fi
        else
            log "ERROR" "  ❌ User '$target_user' is not in docker group"
            log "INFO" "     💡 Try: sudo usermod -aG docker $target_user"
            ((issues++))
        fi
    else
        log "ERROR" "  ❌ Docker group does not exist"
        log "INFO" "     💡 Try: sudo groupadd docker"
        ((issues++))
    fi
    echo
    
    # Check Docker socket
    log "INFO" "4. Docker Socket:"
    if [[ -S /var/run/docker.sock ]]; then
        local socket_perms socket_owner socket_group
        socket_perms=$(stat -c %a /var/run/docker.sock 2>/dev/null || echo "unknown")
        socket_owner=$(stat -c %U /var/run/docker.sock 2>/dev/null || echo "unknown")
        socket_group=$(stat -c %G /var/run/docker.sock 2>/dev/null || echo "unknown")
        
        log "SUCCESS" "  ✅ Docker socket exists: /var/run/docker.sock"
        log "INFO" "     Permissions: $socket_perms"
        log "INFO" "     Owner: $socket_owner"
        log "INFO" "     Group: $socket_group"
        
        if [[ "$socket_group" == "docker" ]]; then
            log "SUCCESS" "  ✅ Socket group is correct (docker)"
        else
            log "ERROR" "  ❌ Socket group should be 'docker', but is '$socket_group'"
            log "INFO" "     💡 Try: sudo chgrp docker /var/run/docker.sock"
            ((issues++))
        fi
        
        # Check if socket is group writable
        if [[ "$socket_perms" =~ ^[0-9]*[2367][0-9]*$ ]]; then
            log "SUCCESS" "  ✅ Socket is group writable"
        else
            log "WARN" "  ⚠️  Socket may not be group writable"
            log "INFO" "     💡 Try: sudo chmod g+w /var/run/docker.sock"
            ((warnings++))
        fi
    else
        log "ERROR" "  ❌ Docker socket not found at /var/run/docker.sock"
        ((issues++))
    fi
    echo
    
    # Test Docker access
    log "INFO" "5. Docker Access Test:"
    local docker_test_result
    if [[ "$target_user" == "$(whoami)" ]]; then
        # Test directly
        if docker info >/dev/null 2>&1; then
            log "SUCCESS" "  ✅ Docker access test passed for current user"
        else
            log "ERROR" "  ❌ Docker access test failed for current user"
            ((issues++))
        fi
    else
        # Test via sudo
        if sudo -u "$target_user" docker info >/dev/null 2>&1; then
            log "SUCCESS" "  ✅ Docker access test passed for user '$target_user'"
        else
            log "ERROR" "  ❌ Docker access test failed for user '$target_user'"
            ((issues++))
            
            # Try with newgrp
            if sudo -u "$target_user" bash -c "newgrp docker -c 'docker info'" >/dev/null 2>&1; then
                log "SUCCESS" "  ✅ Docker access works with 'newgrp docker' for user '$target_user'"
                log "INFO" "     💡 Group membership activation needed"
            else
                log "ERROR" "  ❌ Docker access still fails even with 'newgrp docker'"
            fi
        fi
    fi
    echo
    
    # Summary
    log "INFO" "Diagnosis Summary:"
    log "INFO" "  Critical Issues: $issues"
    log "INFO" "  Warnings: $warnings"
    echo
    
    if [[ $issues -eq 0 ]]; then
        log "SUCCESS" "🎉 Docker access should work correctly!"
        return 0
    else
        log "ERROR" "❌ Docker access issues detected ($issues critical issues)"
        return 1
    fi
} 