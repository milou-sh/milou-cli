#!/bin/bash

# =============================================================================
# Setup Module: User Management
# Extracted from monolithic handle_setup() function
# =============================================================================

# Ensure logging is available
if ! command -v milou_log >/dev/null 2>&1; then
    if [[ -n "${SCRIPT_DIR:-}" ]] && [[ -f "${SCRIPT_DIR}/lib/core/logging.sh" ]]; then
        source "${SCRIPT_DIR}/lib/core/logging.sh" 2>/dev/null || {
            echo "ERROR: Cannot load logging module" >&2
            exit 1
        }
    else
        echo "ERROR: milou_log function not available" >&2
        exit 1
    fi
fi

# =============================================================================
# User Management Functions
# =============================================================================

# Handle milou user management
setup_manage_user() {
    local needs_user="$1"
    local setup_mode="$2"
    
    milou_log "STEP" "Step 5: User Management"
    echo
    
    # Check if user management is needed
    if [[ "$needs_user" != "true" ]]; then
        if _validate_existing_user; then
            milou_log "SUCCESS" "✅ Milou user properly configured"
            return 0
        else
            milou_log "WARN" "Existing milou user has configuration issues"
            needs_user="true"
        fi
    fi
    
    # Check permissions for user management
    if [[ $EUID -ne 0 ]]; then
        milou_log "ERROR" "User management requires root privileges"
        milou_log "INFO" "💡 Run with sudo to manage milou user"
        return 1
    fi
    
    # Handle user creation/configuration based on mode
    case "$setup_mode" in
        interactive)
            _setup_user_interactive
            ;;
        non-interactive)
            _setup_user_automated
            ;;
        smart)
            _setup_user_smart
            ;;
        *)
            milou_log "ERROR" "Unknown setup mode: $setup_mode"
            return 1
            ;;
    esac
    
    # Validate user setup
    _validate_user_setup
    
    echo
    return $?
}

# Interactive user setup
_setup_user_interactive() {
    milou_log "INFO" "👤 Interactive user management"
    
    # Confirm user creation
    if ! _confirm_user_creation; then
        milou_log "WARN" "User creation skipped by user"
        return 1
    fi
    
    # Create or update user
    _create_milou_user || return 1
    
    # Configure user environment
    _configure_user_environment || return 1
    
    # Setup user security
    _setup_user_security || return 1
    
    return 0
}

# Automated user setup
_setup_user_automated() {
    milou_log "INFO" "🤖 Automated user management"
    
    # Create user with defaults
    _create_milou_user || return 1
    
    # Configure environment automatically
    _configure_user_environment || return 1
    
    # Setup security with defaults
    _setup_user_security || return 1
    
    return 0
}

# Smart user setup
_setup_user_smart() {
    milou_log "INFO" "🧠 Smart user management"
    
    # Check if user exists but needs configuration
    if _user_exists "milou"; then
        milou_log "INFO" "Milou user exists, checking configuration..."
        _configure_user_environment || return 1
        _setup_user_security || return 1
    else
        milou_log "INFO" "Creating milou user with smart defaults..."
        _create_milou_user || return 1
        _configure_user_environment || return 1
        _setup_user_security || return 1
    fi
    
    return 0
}

# Create milou user
_create_milou_user() {
    local milou_user="${MILOU_USER:-milou}"
    local milou_group="${MILOU_GROUP:-milou}"
    
    milou_log "INFO" "Creating milou user: $milou_user"
    
    # Check if user already exists
    if _user_exists "$milou_user"; then
        milou_log "INFO" "User $milou_user already exists, updating configuration..."
        return 0
    fi
    
    # Create group first
    if ! _group_exists "$milou_group"; then
        groupadd "$milou_group" || {
            milou_log "ERROR" "Failed to create group: $milou_group"
            return 1
        }
        milou_log "SUCCESS" "Created group: $milou_group"
    fi
    
    # Create user with home directory
    local user_home="/home/$milou_user"
    
    useradd \
        --create-home \
        --home-dir "$user_home" \
        --shell /bin/bash \
        --gid "$milou_group" \
        --comment "Milou CLI Service User" \
        "$milou_user" || {
        milou_log "ERROR" "Failed to create user: $milou_user"
        return 1
    }
    
    milou_log "SUCCESS" "Created user: $milou_user"
    
    # Add user to docker group if it exists
    if _group_exists "docker"; then
        usermod -aG docker "$milou_user" || {
            milou_log "WARN" "Failed to add $milou_user to docker group"
        }
        milou_log "SUCCESS" "Added $milou_user to docker group"
    fi
    
    # Set up home directory permissions
    chown -R "$milou_user:$milou_group" "$user_home"
    chmod 750 "$user_home"
    
    return 0
}

# Configure user environment
_configure_user_environment() {
    local milou_user="${MILOU_USER:-milou}"
    
    milou_log "INFO" "Configuring user environment for $milou_user"
    
    # Use user environment module if available
    if command -v setup_milou_user_environment >/dev/null 2>&1; then
        setup_milou_user_environment || {
            milou_log "ERROR" "Failed to setup user environment using module"
            return 1
        }
        milou_log "SUCCESS" "User environment configured using module"
        return 0
    fi
    
    # Fallback basic environment setup
    _setup_basic_user_environment "$milou_user"
    
    return $?
}

# Setup basic user environment (fallback)
_setup_basic_user_environment() {
    local milou_user="$1"
    local user_home="/home/$milou_user"
    
    # Create basic directories
    local -a dirs=("$user_home/.milou" "$user_home/bin")
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        chown "$milou_user:$milou_user" "$dir"
        chmod 750 "$dir"
    done
    
    # Create basic .bashrc if it doesn't exist
    if [[ ! -f "$user_home/.bashrc" ]]; then
        cat > "$user_home/.bashrc" << 'EOF'
# .bashrc for milou user

# Source system bashrc
[[ -f /etc/bashrc ]] && source /etc/bashrc

# Milou environment
export MILOU_USER="milou"
export MILOU_HOME="$HOME"

# Add Milou CLI to PATH if it exists
[[ -d "$HOME/milou-cli" ]] && export PATH="$HOME/milou-cli:$PATH"
[[ -d "$HOME/bin" ]] && export PATH="$HOME/bin:$PATH"

# Docker environment
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

# Aliases
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'
EOF
        chown "$milou_user:$milou_user" "$user_home/.bashrc"
        chmod 644 "$user_home/.bashrc"
    fi
    
    milou_log "SUCCESS" "Basic user environment configured"
    return 0
}

# Setup user security
_setup_user_security() {
    local milou_user="${MILOU_USER:-milou}"
    
    milou_log "INFO" "Setting up user security for $milou_user"
    
    # Use user security module if available
    if command -v milou_setup_user_security >/dev/null 2>&1; then
        milou_setup_user_security "$milou_user" || {
            milou_log "WARN" "User security module setup had issues"
        }
    fi
    
    # Basic security setup
    _setup_basic_user_security "$milou_user"
    
    return 0
}

# Setup basic user security
_setup_basic_user_security() {
    local milou_user="$1"
    local user_home="/home/$milou_user"
    
    # Secure home directory
    chmod 750 "$user_home"
    
    # Secure .milou directory if it exists
    if [[ -d "$user_home/.milou" ]]; then
        chmod 700 "$user_home/.milou"
        chown -R "$milou_user:$milou_user" "$user_home/.milou"
    fi
    
    # Setup sudo permissions for specific commands (optional)
    if [[ -d "/etc/sudoers.d" ]]; then
        cat > "/etc/sudoers.d/milou-cli" << EOF
# Milou CLI sudo permissions
$milou_user ALL=(ALL) NOPASSWD: /usr/bin/docker, /usr/local/bin/docker-compose, /bin/systemctl restart docker
EOF
        chmod 440 "/etc/sudoers.d/milou-cli"
        milou_log "INFO" "Created sudo permissions for $milou_user"
    fi
    
    milou_log "SUCCESS" "Basic user security configured"
    return 0
}

# Validate existing user
_validate_existing_user() {
    local milou_user="${MILOU_USER:-milou}"
    
    if ! _user_exists "$milou_user"; then
        return 1
    fi
    
    local user_home="/home/$milou_user"
    
    # Check home directory
    if [[ ! -d "$user_home" ]]; then
        milou_log "WARN" "User $milou_user missing home directory"
        return 1
    fi
    
    # Check if user is in docker group
    if _group_exists "docker" && ! groups "$milou_user" | grep -q docker; then
        milou_log "WARN" "User $milou_user not in docker group"
        return 1
    fi
    
    return 0
}

# Validate user setup
_validate_user_setup() {
    local milou_user="${MILOU_USER:-milou}"
    
    milou_log "INFO" "🔍 Validating user setup..."
    
    local validation_failed=false
    
    # Check user exists
    if _user_exists "$milou_user"; then
        milou_log "SUCCESS" "✅ User $milou_user exists"
    else
        milou_log "ERROR" "❌ User $milou_user not found"
        validation_failed=true
    fi
    
    # Check home directory
    local user_home="/home/$milou_user"
    if [[ -d "$user_home" ]]; then
        milou_log "SUCCESS" "✅ Home directory exists: $user_home"
    else
        milou_log "ERROR" "❌ Home directory missing: $user_home"
        validation_failed=true
    fi
    
    # Check docker group membership
    if _group_exists "docker"; then
        if groups "$milou_user" 2>/dev/null | grep -q docker; then
            milou_log "SUCCESS" "✅ User in docker group"
        else
            milou_log "WARN" "⚠️  User not in docker group"
        fi
    fi
    
    # Test user environment
    if command -v validate_milou_user_environment >/dev/null 2>&1; then
        if validate_milou_user_environment; then
            milou_log "SUCCESS" "✅ User environment validated"
        else
            milou_log "WARN" "⚠️  User environment validation had issues"
        fi
    fi
    
    if [[ "$validation_failed" == "true" ]]; then
        milou_log "ERROR" "User setup validation failed"
        return 1
    else
        milou_log "SUCCESS" "✅ User setup validated"
        return 0
    fi
}

# Helper functions
_user_exists() {
    local username="$1"
    id "$username" >/dev/null 2>&1
}

_group_exists() {
    local groupname="$1"
    getent group "$groupname" >/dev/null 2>&1
}

_confirm_user_creation() {
    local milou_user="${MILOU_USER:-milou}"
    
    echo "Milou CLI User Setup:"
    echo "  • User: $milou_user"
    echo "  • Home: /home/$milou_user"
    echo "  • Groups: $milou_user, docker (if available)"
    echo "  • Purpose: Dedicated user for Milou CLI operations"
    echo
    
    if command -v milou_confirm >/dev/null 2>&1; then
        milou_confirm "Create/configure milou user?" "Y"
    else
        echo -n "Create/configure milou user? [Y/n]: "
        read -r response
        [[ "${response,,}" != "n" && "${response,,}" != "no" ]]
    fi
}

# Export functions
export -f setup_manage_user
export -f _setup_user_interactive
export -f _setup_user_automated
export -f _setup_user_smart
export -f _create_milou_user
export -f _configure_user_environment
export -f _setup_user_security
export -f _validate_user_setup 