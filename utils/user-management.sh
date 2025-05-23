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
    
    # Create user with home directory
    log "DEBUG" "Creating user: $MILOU_USER (UID: $MILOU_UID)"
    local useradd_cmd=(
        useradd
        -m                    # Create home directory
        -s /bin/bash         # Set shell
        -g "$MILOU_GROUP"    # Primary group
        -G docker            # Add to docker group
        -c "Milou Service User"  # Comment
    )
    
    # Try with specific UID first
    if ! "${useradd_cmd[@]}" -u "$MILOU_UID" "$MILOU_USER" 2>/dev/null; then
        # If UID is taken, let system assign one
        log "DEBUG" "UID $MILOU_UID taken, letting system assign one"
        if ! "${useradd_cmd[@]}" "$MILOU_USER"; then
            error_exit "Failed to create user $MILOU_USER"
        fi
    fi
    
    # Ensure docker group exists and add user to it
    if ! getent group docker >/dev/null 2>&1; then
        log "DEBUG" "Creating docker group"
        groupadd docker || log "WARN" "Failed to create docker group"
    fi
    
    # Add user to docker group
    if ! usermod -aG docker "$MILOU_USER"; then
        log "WARN" "Failed to add $MILOU_USER to docker group"
    fi
    
    # Set up user environment
    setup_milou_user_environment
    
    log "SUCCESS" "User $MILOU_USER created successfully"
    log "INFO" "Home directory: $MILOU_HOME"
    log "INFO" "UID: $(id -u "$MILOU_USER"), GID: $(id -g "$MILOU_USER")"
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
    
    # Create necessary directories
    local -a dirs=(
        "$milou_home/.milou"
        "$milou_home/.milou/backups"
        "$milou_home/.milou/cache"
        "$milou_home/.milou/logs"
        "$milou_home/.milou/ssl"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            chown "$MILOU_USER:$MILOU_GROUP" "$dir"
            chmod 750 "$dir"
        fi
    done
    
    # Create a basic .bashrc if it doesn't exist
    if [[ ! -f "$milou_home/.bashrc" ]]; then
        cat > "$milou_home/.bashrc" << 'EOF'
# .bashrc for milou user

# Source system bashrc
[[ -f /etc/bashrc ]] && source /etc/bashrc

# Milou-specific environment
export MILOU_HOME="$HOME"
export MILOU_CONFIG="$HOME/.milou"
export PATH="$PATH:/usr/local/bin"

# Docker environment
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

# Aliases
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'

# Milou shortcuts
alias milou='$HOME/milou-cli/milou.sh'
alias mstart='milou start'
alias mstop='milou stop'
alias mstatus='milou status'
alias mlogs='milou logs'

echo "Welcome to Milou CLI environment!"
echo "Use 'milou --help' for available commands"
EOF
        chown "$MILOU_USER:$MILOU_GROUP" "$milou_home/.bashrc"
        chmod 644 "$milou_home/.bashrc"
    fi
    
    # Set proper ownership for home directory
    chown -R "$MILOU_USER:$MILOU_GROUP" "$milou_home"
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
    
    if ! milou_user_exists; then
        if is_running_as_root; then
            log "INFO" "Creating $MILOU_USER user for secure operations..."
            create_milou_user
        else
            error_exit "User $MILOU_USER does not exist. Please run with sudo to create it automatically."
        fi
    fi
    
    log "INFO" "Switching to $MILOU_USER user for secure operations..."
    
    # Copy current script arguments and environment
    local script_path
    script_path=$(readlink -f "${BASH_SOURCE[0]}")
    local script_dir
    script_dir=$(dirname "$script_path")
    
    # Ensure milou user has access to the script directory
    if is_running_as_root; then
        # Copy the entire milou-cli directory to milou user's home if needed
        local milou_home
        milou_home=$(getent passwd "$MILOU_USER" | cut -d: -f6)
        local target_dir="$milou_home/milou-cli"
        
        if [[ ! -d "$target_dir" ]]; then
            log "INFO" "Copying Milou CLI to $MILOU_USER home directory..."
            cp -r "$script_dir" "$milou_home/"
            chown -R "$MILOU_USER:$MILOU_GROUP" "$target_dir"
            chmod +x "$target_dir/milou.sh"
        fi
        
        # Switch to milou user and re-execute the script
        log "DEBUG" "Executing as $MILOU_USER: $target_dir/milou.sh $*"
        exec sudo -u "$MILOU_USER" -H "$target_dir/milou.sh" "$@"
    else
        error_exit "Cannot switch to $MILOU_USER user without root privileges"
    fi
}

# Migrate existing installation to milou user
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
    
    # Migrate configuration files
    if [[ -f "$ENV_FILE" ]]; then
        log "INFO" "Migrating configuration files..."
        local target_config_dir="$milou_home/.milou"
        mkdir -p "$target_config_dir"
        
        # Copy .env file
        cp "$ENV_FILE" "$target_config_dir/"
        
        # Migrate other config files
        local -a config_files=("$CONFIG_DIR"/* "$BACKUP_DIR"/* "$CACHE_DIR"/*)
        for file in "${config_files[@]}"; do
            [[ -f "$file" ]] && cp "$file" "$target_config_dir/"
        done
        
        # Set ownership
        chown -R "$MILOU_USER:$MILOU_GROUP" "$target_config_dir"
        chmod -R 750 "$target_config_dir"
        
        log "SUCCESS" "Configuration migrated to $target_config_dir"
    fi
    
    # Migrate SSL certificates
    if [[ -d "./ssl" ]]; then
        log "INFO" "Migrating SSL certificates..."
        cp -r "./ssl" "$milou_home/"
        chown -R "$MILOU_USER:$MILOU_GROUP" "$milou_home/ssl"
        chmod -R 750 "$milou_home/ssl"
        log "SUCCESS" "SSL certificates migrated to $milou_home/ssl"
    fi
    
    # Ensure Docker volumes have correct permissions
    fix_docker_permissions
    
    log "SUCCESS" "Migration to $MILOU_USER user completed"
}

# Fix Docker permissions for milou user
fix_docker_permissions() {
    log "DEBUG" "Ensuring proper Docker permissions for $MILOU_USER..."
    
    # Add milou user to docker group if not already
    if ! groups "$MILOU_USER" 2>/dev/null | grep -q docker; then
        log "DEBUG" "Adding $MILOU_USER to docker group..."
        usermod -aG docker "$MILOU_USER" || log "WARN" "Failed to add $MILOU_USER to docker group"
    fi
    
    # Fix permissions on Docker socket if needed
    if [[ -S /var/run/docker.sock ]]; then
        local socket_group
        socket_group=$(stat -c %G /var/run/docker.sock 2>/dev/null || echo "root")
        if [[ "$socket_group" != "docker" ]]; then
            log "DEBUG" "Fixing Docker socket permissions..."
            chgrp docker /var/run/docker.sock 2>/dev/null || log "WARN" "Could not change Docker socket group"
        fi
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
# User Management Interface
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
    echo
    
    # Current user info
    local current_user
    current_user=$(whoami)
    echo "Current user: $current_user"
    echo "UID: $(id -u), GID: $(id -g)"
    echo "Groups: $(groups | cut -d: -f2)"
    echo "Running as root: $(is_running_as_root && echo "Yes" || echo "No")"
    echo
    
    # Milou user info
    if milou_user_exists; then
        echo "Milou user: $MILOU_USER exists"
        echo "UID: $(id -u "$MILOU_USER"), GID: $(id -g "$MILOU_USER")"
        echo "Home: $(getent passwd "$MILOU_USER" | cut -d: -f6)"
        echo "Groups: $(groups "$MILOU_USER" 2>/dev/null | cut -d: -f2 || echo "unknown")"
    else
        echo "Milou user: $MILOU_USER does not exist"
    fi
    echo
    
    # Docker permissions
    echo "Docker access: $(has_docker_permissions && echo "Yes" || echo "No")"
    if command -v docker >/dev/null 2>&1; then
        echo "Docker version: $(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',' || echo "unknown")"
        echo "Docker daemon: $(docker info >/dev/null 2>&1 && echo "accessible" || echo "not accessible")"
    else
        echo "Docker: not installed"
    fi
}

# =============================================================================
# Utility Functions
# =============================================================================

# Ensure user management is properly set up
ensure_proper_user_setup() {
    log "DEBUG" "Ensuring proper user setup..."
    
    # If running as root, offer to create milou user
    if is_running_as_root; then
        log "WARN" "Running as root - consider using dedicated user"
        if [[ "${INTERACTIVE:-true}" == "true" ]]; then
            if confirm "Create and switch to $MILOU_USER user for better security?" "Y"; then
                if ! milou_user_exists; then
                    create_milou_user
                fi
                switch_to_milou_user "$@"
            fi
        elif [[ "${AUTO_CREATE_USER:-false}" == "true" ]]; then
            if ! milou_user_exists; then
                create_milou_user
            fi
            switch_to_milou_user "$@"
        fi
    fi
    
    # Validate permissions
    if ! validate_user_permissions; then
        if [[ "${INTERACTIVE:-true}" == "true" ]]; then
            interactive_user_setup "$@"
        else
            error_exit "User permissions validation failed"
        fi
    fi
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
export -f ensure_proper_user_setup 