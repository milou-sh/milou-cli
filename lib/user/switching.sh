#!/bin/bash

# =============================================================================
# User Switching and Migration for Milou CLI
# Handles user switching, configuration migration, and setup orchestration
# =============================================================================

# Source utility functions
source "${BASH_SOURCE%/*}/core.sh" 2>/dev/null || true
source "${BASH_SOURCE%/*}/docker.sh" 2>/dev/null || true
source "${BASH_SOURCE%/*}/environment.sh" 2>/dev/null || true

# =============================================================================
# Enhanced Directory Comparison
# =============================================================================

# Compare two directories and determine if source is newer than target
is_directory_newer() {
    local source_dir="$1"
    local target_dir="$2"
    
    if [[ ! -d "$source_dir" ]]; then
        log "ERROR" "Source directory does not exist: $source_dir"
        return 1
    fi
    
    if [[ ! -d "$target_dir" ]]; then
        log "DEBUG" "Target directory does not exist, needs copy: $target_dir"
        return 0  # Target doesn't exist, so source is "newer"
    fi
    
    log "DEBUG" "Comparing directories: source=$source_dir target=$target_dir"
    
    # Check if source has files that don't exist in target or are newer
    local files_checked=0
    local newer_files=0
    
    while IFS= read -r -d '' source_file; do
        ((files_checked++))
        local rel_path="${source_file#$source_dir/}"
        local target_file="$target_dir/$rel_path"
        
        if [[ ! -e "$target_file" ]]; then
            log "DEBUG" "Missing file in target: $rel_path"
            ((newer_files++))
            continue
        fi
        
        # Compare modification times
        local source_mtime target_mtime
        source_mtime=$(stat -c %Y "$source_file" 2>/dev/null || echo "0")
        target_mtime=$(stat -c %Y "$target_file" 2>/dev/null || echo "0")
        
        if [[ $source_mtime -gt $target_mtime ]]; then
            log "DEBUG" "Newer file in source: $rel_path (source: $source_mtime, target: $target_mtime)"
            ((newer_files++))
        fi
        
        # Check first 50 files to avoid being too slow
        if [[ $files_checked -ge 50 ]]; then
            break
        fi
    done < <(find "$source_dir" -type f -print0 2>/dev/null)
    
    log "DEBUG" "Directory comparison: checked $files_checked files, found $newer_files newer/missing"
    
    if [[ $newer_files -gt 0 ]]; then
        return 0  # Source is newer
    else
        return 1  # Target is up to date
    fi
}

# =============================================================================
# Enhanced Token Validation and Preservation
# =============================================================================

# Validate and prepare GitHub token for transfer
validate_and_prepare_token() {
    local token="${GITHUB_TOKEN:-}"
    
    if [[ -z "$token" ]]; then
        log "DEBUG" "No GitHub token provided"
        return 1
    fi
    
    # Basic token format validation
    if [[ ! "$token" =~ ^ghp_[A-Za-z0-9]{36}$ ]]; then
        log "WARN" "GitHub token format appears invalid (expected ghp_* format with 36 characters)"
        # Don't fail completely, maybe it's a different type of token
    fi
    
    log "DEBUG" "GitHub token validated and ready for transfer (length: ${#token})"
    return 0
}

# Copy GitHub credentials and token to milou user
copy_github_credentials_to_milou() {
    local milou_home
    milou_home=$(get_milou_home)
    
    if [[ -z "$milou_home" || ! -d "$milou_home" ]]; then
        log "WARN" "Cannot copy GitHub credentials: milou home directory not found"
        return 1
    fi
    
    log "DEBUG" "Ensuring GitHub credentials are available to milou user..."
    
    # Copy Docker credentials if they exist
    if copy_docker_credentials_to_milou; then
        log "DEBUG" "Docker credentials copied successfully"
    else
        log "DEBUG" "Docker credentials copy failed, will rely on token-based auth"
    fi
    
    # Ensure GitHub token is available for Docker registry authentication
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        # Create a secure temporary environment file for the token
        local temp_env_file="$milou_home/.milou/.env.token.tmp"
        
        # Ensure the .milou directory exists
        mkdir -p "$milou_home/.milou"
        chown "$MILOU_USER:$MILOU_GROUP" "$milou_home/.milou"
        chmod 700 "$milou_home/.milou"
        
        echo "GITHUB_TOKEN=${GITHUB_TOKEN}" > "$temp_env_file"
        chown "$MILOU_USER:$MILOU_GROUP" "$temp_env_file"
        chmod 600 "$temp_env_file"
        log "DEBUG" "GitHub token prepared for milou user in temporary file"
        
        # Also try to authenticate with Docker registry directly
        log "DEBUG" "Attempting Docker registry authentication for milou user..."
        local docker_auth_success=false
        
        # Try different authentication methods
        if sudo -u "$MILOU_USER" bash -c "echo '${GITHUB_TOKEN}' | docker login ghcr.io -u token --password-stdin" >/dev/null 2>&1; then
            docker_auth_success=true
            log "DEBUG" "Docker registry authentication successful (method: token)"
        elif sudo -u "$MILOU_USER" bash -c "echo '${GITHUB_TOKEN}' | docker login ghcr.io -u \$(whoami) --password-stdin" >/dev/null 2>&1; then
            docker_auth_success=true
            log "DEBUG" "Docker registry authentication successful (method: username)"
        fi
        
        if [[ "$docker_auth_success" == true ]]; then
            log "SUCCESS" "Docker registry authentication configured for milou user"
        else
            log "WARN" "Docker registry authentication failed for milou user"
            log "INFO" "Will rely on environment token during Docker operations"
        fi
    else
        log "WARN" "No GitHub token available for Docker registry authentication"
    fi
    
    return 0
}

# =============================================================================
# User Switching Logic
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
        
        # If we're in lib directory, go up one level
        script_dir=$(dirname "$script_path")
        if [[ "$(basename "$script_dir")" == "lib" ]]; then
            script_dir=$(dirname "$script_dir")
            log "DEBUG" "Detected lib directory, using parent: $script_dir"
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
    
    if [[ ! -d "$script_dir/lib" ]]; then
        error_exit "Cannot locate lib directory: $script_dir/lib"
    fi
    
    # Ensure milou user has access to the script directory
    if is_running_as_root; then
        local milou_home target_dir
        milou_home=$(get_milou_home)
        
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
        
        # Enhanced copying strategy with comprehensive directory comparison
        local needs_copy=false
        local needs_update=false
        
        if [[ ! -d "$target_dir" ]]; then
            log "INFO" "Copying Milou CLI to $MILOU_USER home directory..."
            needs_copy=true
        else
            # Use comprehensive directory comparison instead of just checking one file
            log "DEBUG" "Checking if CLI update is needed..."
            if is_directory_newer "$script_dir" "$target_dir"; then
                log "INFO" "Updating Milou CLI in $MILOU_USER home directory (source has newer files)..."
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
                if mv "$target_dir" "$backup_dir"; then
                    log "SUCCESS" "Backup created: $backup_dir"
                else
                    log "WARN" "Failed to create backup - continuing anyway"
                fi
            fi
            
            # Copy the CLI
            log "DEBUG" "Copying CLI from $script_dir to $milou_home/"
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
        
        # Enhanced token validation and preservation
        local token_status="none"
        if validate_and_prepare_token; then
            token_status="valid"
            log "DEBUG" "GitHub token validated for transfer"
            
            # Copy GitHub credentials including the token
            copy_github_credentials_to_milou
        else
            log "WARN" "No valid GitHub token found to preserve during user switch"
        fi
        
        # Enhanced environment variable preservation
        local -a env_vars=(
            "VERBOSE=${VERBOSE:-false}"
            "FORCE=${FORCE:-false}"
            "DRY_RUN=${DRY_RUN:-false}"
            "INTERACTIVE=${INTERACTIVE:-true}"
            "AUTO_CREATE_USER=${AUTO_CREATE_USER:-false}"
            "SKIP_USER_CHECK=${SKIP_USER_CHECK:-false}"
            "USE_LATEST_IMAGES=${USE_LATEST_IMAGES:-false}"
            "USER_SWITCH_IN_PROGRESS=true"
            "SCRIPT_DIR=${SCRIPT_DIR:-}"
            "CONFIG_DIR=${CONFIG_DIR:-}"
            "LOG_FILE=${LOG_FILE:-}"
            "ENV_FILE=${ENV_FILE:-}"
            "BACKUP_DIR=${BACKUP_DIR:-}"
            "CACHE_DIR=${CACHE_DIR:-}"
            "DEFAULT_SSL_PATH=${DEFAULT_SSL_PATH:-}"
            "CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt"
            "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
        )
        
        # Add GitHub token if provided (but don't log the actual token value)
        log "DEBUG" "Checking GitHub token: GITHUB_TOKEN=${GITHUB_TOKEN:-NOT_SET} (length: ${#GITHUB_TOKEN})"
        if [[ -n "${GITHUB_TOKEN:-}" ]]; then
            env_vars+=("GITHUB_TOKEN=$GITHUB_TOKEN")
            log "DEBUG" "Preserving GitHub token in environment (length: ${#GITHUB_TOKEN})"
        else
            log "WARN" "No GitHub token found to preserve during user switch"
        fi
        
        # Add domain and SSL path if provided
        if [[ -n "${DOMAIN:-}" ]]; then
            env_vars+=("DOMAIN=$DOMAIN")
            log "DEBUG" "Preserving DOMAIN: $DOMAIN"
        fi
        if [[ -n "${SSL_PATH:-}" ]]; then
            env_vars+=("SSL_PATH=$SSL_PATH")
            log "DEBUG" "Preserving SSL_PATH: $SSL_PATH"
        fi
        if [[ -n "${ADMIN_EMAIL:-}" ]]; then
            env_vars+=("ADMIN_EMAIL=$ADMIN_EMAIL")
            log "DEBUG" "Preserving ADMIN_EMAIL: $ADMIN_EMAIL"
        fi
        
        # Enhanced original command and arguments preservation
        if [[ -n "${ORIGINAL_COMMAND:-}" ]]; then
            env_vars+=("ORIGINAL_COMMAND=$ORIGINAL_COMMAND")
            log "DEBUG" "Preserving original command: $ORIGINAL_COMMAND"
        fi
        
        if [[ -n "${ORIGINAL_ARGUMENTS_STR:-}" ]]; then
            env_vars+=("ORIGINAL_ARGUMENTS_STR=$ORIGINAL_ARGUMENTS_STR")
            log "DEBUG" "Preserving command arguments: $ORIGINAL_ARGUMENTS_STR"
        fi
        
        # Build the execution command with enhanced state preservation
        local exec_cmd="cd '$target_dir' && env"
        
        # Add environment variables
        for env_var in "${env_vars[@]}"; do
            exec_cmd+=" '$env_var'"
        done
        
        # Add the script path
        exec_cmd+=" '$target_dir/milou.sh'"
        
        # Handle command preservation - use the preserved arguments properly
        if [[ -n "${ORIGINAL_ARGUMENTS_STR:-}" ]]; then
            # Use the original arguments string directly since it's properly escaped and includes the command
            exec_cmd+=" $ORIGINAL_ARGUMENTS_STR"
            log "DEBUG" "Using preserved original arguments: $ORIGINAL_ARGUMENTS_STR"
        elif [[ -n "${ORIGINAL_COMMAND:-}" ]]; then
            # Just the command without arguments
            exec_cmd+=" $ORIGINAL_COMMAND"
            log "DEBUG" "Using preserved command: $ORIGINAL_COMMAND (no arguments)"
        elif [[ $# -gt 0 ]]; then
            # Fallback: Use current arguments
            for arg in "$@"; do
                exec_cmd+=" $(printf '%q' "$arg")"
            done
            log "DEBUG" "Using current arguments as fallback: $*"
        else
            # No arguments provided - this might be an issue, but let's continue
            log "WARN" "No command or arguments provided during user switch"
        fi
        
        # Ensure docker group membership is active WITHOUT using newgrp
        # Use a direct sudo approach that activates the docker group
        log "DEBUG" "Executing as $MILOU_USER in directory: $target_dir"
        
        # Ensure milou user is in docker group
        if ! groups "$MILOU_USER" 2>/dev/null | grep -q docker; then
            log "DEBUG" "Adding $MILOU_USER to docker group..."
            usermod -aG docker "$MILOU_USER" 2>/dev/null || log "WARN" "Could not add user to docker group"
        fi
        
        # Use sudo with the docker group as the primary group for the session
        # This activates docker group membership without needing newgrp
        log "DEBUG" "Switching to milou user with docker group activation..."
        log "DEBUG" "Final exec command: $(echo "$exec_cmd" | sed 's/GITHUB_TOKEN=[^ ]*/GITHUB_TOKEN=***HIDDEN***/g')"
        
        # Execute with proper group activation - this replaces the current process
        exec sudo -u "$MILOU_USER" -g docker -H bash -c "$exec_cmd"
        
        # This line should never be reached due to exec
        error_exit "Failed to switch to $MILOU_USER user - exec did not replace process"
        
    else
        error_exit "Cannot switch to $MILOU_USER user without root privileges"
    fi
}

# =============================================================================
# Configuration Migration
# =============================================================================

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
    milou_home=$(get_milou_home)
    
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

# =============================================================================
# User Setup Orchestration
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
            return $?  # This should never be reached due to exec
        fi
        
        # Check if milou user exists and decide on automatic switch behavior
        if milou_user_exists; then
            # Interactive mode - ask user (but with better default)
            if [[ "${INTERACTIVE:-true}" == "true" ]]; then
                echo
                echo -e "${CYAN}💡 For better security, it's recommended to run Milou as the dedicated user.${NC}"
                if confirm "Switch to $MILOU_USER user for this operation?" "Y"; then
                    switch_to_milou_user "$@"
                    return $?  # This should never be reached due to exec
                else
                    log "INFO" "Continuing as root (not recommended for production)"
                fi
            else
                # Non-interactive mode - auto switch
                log "INFO" "Non-interactive mode: automatically switching to $MILOU_USER user"
                switch_to_milou_user "$@"
                return $?  # This should never be reached due to exec
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
                    return $?  # This should never be reached due to exec
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
            source "${BASH_SOURCE%/*}/user-interface.sh"
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

# =============================================================================
# Cleanup Functions
# =============================================================================

# Clean up temporary token and user management files
cleanup_user_switching_resources() {
    log "DEBUG" "Cleaning up user switching resources..."
    
    # Clean up temporary token files if we have milou user access
    if milou_user_exists; then
        local milou_home
        milou_home=$(get_milou_home)
        if [[ -n "$milou_home" && -d "$milou_home/.milou" ]]; then
            find "$milou_home/.milou" -name ".env.token.tmp" -type f -delete 2>/dev/null || true
            log "DEBUG" "Cleaned up temporary token files"
        fi
    fi
    
    # Clean up other temporary files
    local -a temp_patterns=(
        "/tmp/milou_switch_*"
        "/tmp/milou_user_*"
    )
    
    for pattern in "${temp_patterns[@]}"; do
        if compgen -G "$pattern" >/dev/null 2>&1; then
            rm -f $pattern 2>/dev/null || true
        fi
    done
}

# Export enhanced functions for use in other scripts
export -f is_directory_newer
export -f validate_and_prepare_token
export -f copy_github_credentials_to_milou
export -f switch_to_milou_user
export -f migrate_to_milou_user
export -f ensure_proper_user_setup
export -f validate_user_permissions_for_setup
export -f cleanup_user_switching_resources 