#!/bin/bash

# =============================================================================
# User Management Module for Milou CLI
# Consolidated from lib/user/* - Complete user lifecycle management
# =============================================================================

# Module guard to prevent multiple loading
if [[ "${MILOU_USER_MODULE_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_USER_MODULE_LOADED="true"

# Load dependencies
if [[ -f "${BASH_SOURCE[0]%/*}/_core.sh" ]]; then
    source "${BASH_SOURCE[0]%/*}/_core.sh" || return 1
fi

if [[ -f "${BASH_SOURCE[0]%/*}/_validation.sh" ]]; then
    source "${BASH_SOURCE[0]%/*}/_validation.sh" || return 1
fi

if [[ -f "${BASH_SOURCE[0]%/*}/_docker.sh" ]]; then
    source "${BASH_SOURCE[0]%/*}/_docker.sh" || return 1
fi

# =============================================================================
# User Core Functions (from lib/user/core.sh)
# =============================================================================

# Check if running as root
is_running_as_root() {
    [[ $EUID -eq 0 ]]
}

# Check if milou user exists
milou_user_exists() {
    id "milou" >/dev/null 2>&1
}

# Get current user information
get_current_user_info() {
    local username=$(whoami)
    local user_id=$(id -u)
    local groups=$(groups)
    local home_dir="$HOME"
    
    echo "Username: $username"
    echo "User ID: $user_id"
    echo "Groups: $groups"
    echo "Home Directory: $home_dir"
    
    return 0
}

# Create milou user with proper configuration
create_milou_user() {
    local interactive="${1:-true}"
    
    milou_log "INFO" "🧑 Creating milou user account"
    
    # Check if user already exists
    if milou_user_exists; then
        milou_log "INFO" "✅ User 'milou' already exists"
        return 0
    fi
    
    # Must be run as root
    if ! is_running_as_root; then
        milou_log "ERROR" "❌ Must be run as root to create user accounts"
        return 1
    fi
    
    # Create user with home directory
    if useradd -m -s /bin/bash milou; then
        milou_log "SUCCESS" "✅ Created user 'milou'"
    else
        milou_log "ERROR" "❌ Failed to create user 'milou'"
        return 1
    fi
    
    # Add to docker group if it exists
    if getent group docker >/dev/null 2>&1; then
        if usermod -aG docker milou; then
            milou_log "SUCCESS" "✅ Added milou to docker group"
        else
            milou_log "WARN" "⚠️  Failed to add milou to docker group"
        fi
    fi
    
    # Set up password if interactive
    if [[ "$interactive" == "true" && "${INTERACTIVE:-true}" == "true" ]]; then
        milou_log "INFO" "Setting password for milou user..."
        passwd milou
    fi
    
    milou_log "SUCCESS" "✅ User 'milou' created successfully"
    return 0
}

# Get milou user home directory
get_milou_home() {
    if milou_user_exists; then
        getent passwd milou | cut -d: -f6
    else
        echo "/home/milou"
    fi
}

# Validate milou home directory
validate_milou_home() {
    local milou_home
    milou_home=$(get_milou_home)
    
    if [[ -d "$milou_home" && -r "$milou_home" ]]; then
        echo "$milou_home"
        return 0
    else
        milou_log "ERROR" "❌ Milou home directory not accessible: $milou_home"
        return 1
    fi
}

# =============================================================================
# Docker Integration Functions (from lib/user/docker.sh)
# =============================================================================

# Check if user has Docker permissions
has_docker_permissions() {
    local username="${1:-$(whoami)}"
    
    # Check if user is in docker group
    if groups "$username" 2>/dev/null | grep -q docker; then
        return 0
    fi
    
    # Check if user can run docker commands
    if docker version >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

# Fix Docker permissions for user
fix_docker_permissions() {
    local username="${1:-milou}"
    local force="${2:-false}"
    
    milou_log "INFO" "🐳 Fixing Docker permissions for user: $username"
    
    # Check if user exists
    if ! id "$username" >/dev/null 2>&1; then
        milou_log "ERROR" "❌ User does not exist: $username"
        return 1
    fi
    
    # Check if docker group exists
    if ! getent group docker >/dev/null 2>&1; then
        milou_log "ERROR" "❌ Docker group does not exist"
        return 1
    fi
    
    # Add user to docker group
    if usermod -aG docker "$username"; then
        milou_log "SUCCESS" "✅ Added $username to docker group"
    else
        milou_log "ERROR" "❌ Failed to add $username to docker group"
        return 1
    fi
    
    # Restart Docker service if force is enabled
    if [[ "$force" == "true" ]]; then
        milou_log "INFO" "🔄 Restarting Docker service..."
        if systemctl restart docker; then
            milou_log "SUCCESS" "✅ Docker service restarted"
        else
            milou_log "WARN" "⚠️  Failed to restart Docker service"
        fi
    fi
    
    milou_log "INFO" "💡 User may need to log out and back in for changes to take effect"
    return 0
}

# Copy Docker credentials to milou user
copy_docker_credentials_to_milou() {
    local source_user="${1:-$(whoami)}"
    local milou_home
    milou_home=$(get_milou_home)
    
    milou_log "INFO" "🔑 Copying Docker credentials from $source_user to milou"
    
    local source_docker_config="$HOME/.docker"
    local target_docker_config="$milou_home/.docker"
    
    # Check if source config exists
    if [[ ! -d "$source_docker_config" ]]; then
        milou_log "INFO" "ℹ️  No Docker credentials found for $source_user"
        return 0
    fi
    
    # Create target directory
    mkdir -p "$target_docker_config"
    
    # Copy configuration
    if cp -r "$source_docker_config"/* "$target_docker_config/"; then
        chown -R milou:milou "$target_docker_config"
        milou_log "SUCCESS" "✅ Docker credentials copied successfully"
        return 0
    else
        milou_log "ERROR" "❌ Failed to copy Docker credentials"
        return 1
    fi
}

# Diagnose Docker access issues
diagnose_docker_access() {
    local username="${1:-$(whoami)}"
    
    milou_log "INFO" "🔍 Diagnosing Docker access for user: $username"
    
    # Check if Docker is installed
    if ! command -v docker >/dev/null 2>&1; then
        milou_log "ERROR" "❌ Docker is not installed"
        return 1
    fi
    
    # Check if Docker daemon is running
    if ! docker version >/dev/null 2>&1; then
        milou_log "ERROR" "❌ Docker daemon is not running"
        milou_log "INFO" "💡 Try: sudo systemctl start docker"
        return 1
    fi
    
    # Check group membership
    if ! groups "$username" 2>/dev/null | grep -q docker; then
        milou_log "WARN" "⚠️  User $username is not in docker group"
        milou_log "INFO" "💡 Try: sudo usermod -aG docker $username"
        return 1
    fi
    
    # Check socket permissions
    local docker_socket="/var/run/docker.sock"
    if [[ ! -w "$docker_socket" ]]; then
        milou_log "WARN" "⚠️  Docker socket is not writable: $docker_socket"
        return 1
    fi
    
    milou_log "SUCCESS" "✅ Docker access appears to be configured correctly"
    return 0
}

# =============================================================================
# User Environment Setup (from lib/user/environment.sh)
# =============================================================================

# Setup complete milou user environment
setup_milou_user_environment() {
    local milou_home
    milou_home=$(get_milou_home)
    
    milou_log "INFO" "🏠 Setting up milou user environment"
    
    # Create necessary directories
    create_milou_directories || return 1
    
    # Setup bash configuration
    setup_milou_bashrc || return 1
    
    # Setup user profile
    setup_milou_profile || return 1
    
    # Setup symlinks
    setup_milou_symlinks || return 1
    
    # Validate environment
    validate_milou_user_environment || return 1
    
    milou_log "SUCCESS" "✅ Milou user environment setup complete"
    return 0
}

# Create milou user directories
create_milou_directories() {
    local milou_home
    milou_home=$(get_milou_home)
    
    local directories=(
        "$milou_home/.config"
        "$milou_home/.local/bin"
        "$milou_home/backups"
        "$milou_home/logs"
    )
    
    for dir in "${directories[@]}"; do
        if mkdir -p "$dir"; then
            chown milou:milou "$dir"
            milou_log "DEBUG" "✅ Created directory: $dir"
        else
            milou_log "ERROR" "❌ Failed to create directory: $dir"
            return 1
        fi
    done
    
    return 0
}

# Setup milou bashrc with helper functions
setup_milou_bashrc() {
    local milou_home
    milou_home=$(get_milou_home)
    local bashrc="$milou_home/.bashrc"
    
    # Backup existing bashrc
    if [[ -f "$bashrc" ]]; then
        cp "$bashrc" "$bashrc.backup.$(date +%s)"
    fi
    
    # Create comprehensive bashrc
    cat > "$bashrc" << 'EOF'
# Milou CLI User Environment
# Generated by Milou CLI setup

# Standard bashrc content
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

# Milou CLI environment variables
export MILOU_HOME="/opt/milou-cli"
export PATH="$HOME/.local/bin:$MILOU_HOME:$PATH"

# Milou CLI aliases
alias milou='$MILOU_HOME/milou.sh'
alias mls='docker compose ps'
alias mlogs='docker compose logs'
alias mstatus='$MILOU_HOME/milou.sh status'
alias mstart='$MILOU_HOME/milou.sh start'
alias mstop='$MILOU_HOME/milou.sh stop'
alias mrestart='$MILOU_HOME/milou.sh restart'

# Docker aliases for Milou
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
alias dlogs='docker compose logs -f'
alias dexec='docker exec -it'

# Utility functions
milou_status() {
    echo "=== Milou Services Status ==="
    docker compose ps
    echo
    echo "=== Docker System Info ==="
    docker system df
}

milou_help() {
    echo "Milou CLI Helper Commands:"
    echo "  milou        - Run milou CLI"
    echo "  mls          - List services"
    echo "  mlogs        - View logs"
    echo "  mstatus      - Service status"
    echo "  mstart       - Start services"
    echo "  mstop        - Stop services"
    echo "  mrestart     - Restart services"
    echo "  milou_status - Detailed status"
    echo "  milou_help   - This help"
}

# Welcome message
echo "🚀 Milou CLI environment loaded"
echo "💡 Type 'milou_help' for available commands"
EOF

    chown milou:milou "$bashrc"
    milou_log "SUCCESS" "✅ Milou bashrc configured"
    return 0
}

# Setup milou user profile
setup_milou_profile() {
    local milou_home
    milou_home=$(get_milou_home)
    local profile="$milou_home/.profile"
    
    cat > "$profile" << 'EOF'
# Milou CLI User Profile
export MILOU_HOME="/opt/milou-cli"
export PATH="$HOME/.local/bin:$MILOU_HOME:$PATH"

# Load bashrc if running bash
if [ -n "$BASH_VERSION" ]; then
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi
EOF

    chown milou:milou "$profile"
    milou_log "DEBUG" "✅ Profile configured"
    return 0
}

# Setup milou CLI symlinks
setup_milou_symlinks() {
    local milou_home
    milou_home=$(get_milou_home)
    local milou_install_dir="/opt/milou-cli"
    
    # Link milou-cli directory to the standard installation location
    if [[ ! -L "$milou_home/milou-cli" ]]; then
        if ln -sf "$milou_install_dir" "$milou_home/milou-cli"; then
            milou_log "DEBUG" "✅ Created milou-cli symlink to $milou_install_dir"
        else
            milou_log "WARN" "⚠️  Failed to create milou-cli symlink"
        fi
    fi
    
    # Link milou command to local bin
    if [[ ! -L "$milou_home/.local/bin/milou" ]]; then
        if ln -sf "$milou_install_dir/milou.sh" "$milou_home/.local/bin/milou"; then
            milou_log "DEBUG" "✅ Created milou command symlink"
        else
            milou_log "WARN" "⚠️  Failed to create milou command symlink"
        fi
    fi
    
    return 0
}

# Validate milou user environment
validate_milou_user_environment() {
    local milou_home
    milou_home=$(get_milou_home)
    
    local validation_errors=0
    
    # Check essential directories
    local required_dirs=(
        "$milou_home"
        "$milou_home/.config"
        "$milou_home/.local/bin"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            milou_log "ERROR" "❌ Missing directory: $dir"
            ((validation_errors++))
        fi
    done
    
    # Check essential files
    local required_files=(
        "$milou_home/.bashrc"
        "$milou_home/.profile"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            milou_log "ERROR" "❌ Missing file: $file"
            ((validation_errors++))
        fi
    done
    
    if [[ $validation_errors -eq 0 ]]; then
        milou_log "SUCCESS" "✅ User environment validation passed"
        return 0
    else
        milou_log "ERROR" "❌ User environment validation failed ($validation_errors errors)"
        return 1
    fi
}

# Test milou user CLI access
test_milou_user_cli() {
    local milou_install_dir="/opt/milou-cli"
    
    milou_log "INFO" "🧪 Testing milou user CLI access"
    
    # Test as milou user
    if sudo -u milou bash -c "cd $milou_install_dir && ./milou.sh version" >/dev/null 2>&1; then
        milou_log "SUCCESS" "✅ Milou user can access CLI"
        return 0
    else
        milou_log "ERROR" "❌ Milou user cannot access CLI"
        return 1
    fi
}

# =============================================================================
# User Security Functions (from lib/user/security.sh)
# =============================================================================

# Validate user permissions comprehensively
validate_user_permissions() {
    local username="${1:-$(whoami)}"
    local context="${2:-standard}"  # standard, docker, admin
    
    milou_log "INFO" "🔐 Validating user permissions for: $username"
    
    local permission_errors=0
    
    # Basic user validation
    if ! id "$username" >/dev/null 2>&1; then
        milou_log "ERROR" "❌ User does not exist: $username"
        return 1
    fi
    
    # Context-specific permission checks
    case "$context" in
        "docker")
            if ! has_docker_permissions "$username"; then
                milou_log "ERROR" "❌ User lacks Docker permissions"
                ((permission_errors++))
            fi
            ;;
        "admin")
            if ! groups "$username" | grep -q sudo; then
                milou_log "ERROR" "❌ User lacks sudo permissions"
                ((permission_errors++))
            fi
            ;;
        "standard"|*)
            # Standard validation - basic access
            local user_home
            user_home=$(getent passwd "$username" | cut -d: -f6)
            if [[ ! -d "$user_home" ]]; then
                milou_log "ERROR" "❌ User home directory missing"
                ((permission_errors++))
            fi
            ;;
    esac
    
    if [[ $permission_errors -eq 0 ]]; then
        milou_log "SUCCESS" "✅ User permissions validated"
        return 0
    else
        milou_log "ERROR" "❌ User permission validation failed"
        return 1
    fi
}

# Harden milou user security
harden_milou_user() {
    local milou_home
    milou_home=$(get_milou_home)
    
    milou_log "INFO" "🔒 Hardening milou user security"
    
    # Set secure directory permissions
    chmod 750 "$milou_home"
    
    # Secure sensitive files
    if [[ -f "$milou_home/.bashrc" ]]; then
        chmod 644 "$milou_home/.bashrc"
    fi
    
    if [[ -f "$milou_home/.profile" ]]; then
        chmod 644 "$milou_home/.profile"
    fi
    
    # Secure milou-cli directory
    if [[ -d "$milou_home/milou-cli" ]]; then
        find "$milou_home/milou-cli" -type f -name "*.sh" -exec chmod 755 {} \;
        find "$milou_home/milou-cli" -type f -name ".env*" -exec chmod 600 {} \;
    fi
    
    milou_log "SUCCESS" "✅ Milou user security hardened"
    return 0
}

# Perform comprehensive security assessment
security_assessment() {
    local username="${1:-milou}"
    
    milou_log "INFO" "🔍 Performing security assessment for: $username"
    
    local security_score=100
    local issues=()
    
    # Check user existence
    if ! id "$username" >/dev/null 2>&1; then
        issues+=("User does not exist")
        security_score=$((security_score - 50))
    fi
    
    # Check home directory permissions
    local user_home
    user_home=$(getent passwd "$username" 2>/dev/null | cut -d: -f6)
    if [[ -d "$user_home" ]]; then
        local home_perms
        home_perms=$(stat -c "%a" "$user_home" 2>/dev/null)
        if [[ "$home_perms" != "750" && "$home_perms" != "700" ]]; then
            issues+=("Home directory has weak permissions: $home_perms")
            security_score=$((security_score - 10))
        fi
    fi
    
    # Check Docker permissions
    if ! has_docker_permissions "$username"; then
        issues+=("Missing Docker permissions")
        security_score=$((security_score - 20))
    fi
    
    # Check for password
    if ! sudo -l -U "$username" >/dev/null 2>&1; then
        issues+=("User may not have password set")
        security_score=$((security_score - 15))
    fi
    
    # Report results
    milou_log "INFO" "🏆 Security Score: $security_score/100"
    
    if [[ ${#issues[@]} -gt 0 ]]; then
        milou_log "WARN" "⚠️  Security Issues Found:"
        printf '  • %s\n' "${issues[@]}"
    else
        milou_log "SUCCESS" "✅ No security issues found"
    fi
    
    return 0
}

# Quick security check
quick_security_check() {
    local username="${1:-milou}"
    
    # Fast essential checks only
    if ! id "$username" >/dev/null 2>&1; then
        return 1
    fi
    
    if ! has_docker_permissions "$username"; then
        return 1
    fi
    
    return 0
}

# =============================================================================
# User Switching Functions (from lib/user/switching.sh)
# =============================================================================

# Check if directory is newer than another
is_directory_newer() {
    local source_dir="$1"
    local target_dir="$2"
    
    if [[ ! -d "$source_dir" ]]; then
        return 1
    fi
    
    if [[ ! -d "$target_dir" ]]; then
        return 0  # Source exists, target doesn't - source is newer
    fi
    
    # Compare modification times
    local source_time target_time
    source_time=$(stat -c %Y "$source_dir" 2>/dev/null || echo 0)
    target_time=$(stat -c %Y "$target_dir" 2>/dev/null || echo 0)
    
    [[ $source_time -gt $target_time ]]
}

# Switch to milou user with full environment
switch_to_milou_user() {
    local command="${1:-bash}"
    local preserve_env="${2:-false}"
    
    milou_log "INFO" "🔄 Switching to milou user"
    
    # Validate milou user exists
    if ! milou_user_exists; then
        milou_log "ERROR" "❌ Milou user does not exist"
        return 1
    fi
    
    # Validate environment
    if ! validate_milou_user_environment >/dev/null 2>&1; then
        milou_log "WARN" "⚠️  Milou user environment may have issues"
    fi
    
    # Switch user
    if [[ "$preserve_env" == "true" ]]; then
        sudo -u milou -E "$command"
    else
        sudo -u milou -i "$command"
    fi
}

# =============================================================================
# User Interface Functions (from lib/user/interface.sh)
# =============================================================================

# Interactive user setup wizard
interactive_user_setup() {
    milou_log "INFO" "🧙 Starting interactive user setup wizard"
    
    # Check current user
    if is_running_as_root; then
        milou_log "INFO" "Running as root - can create milou user"
    else
        milou_log "WARN" "⚠️  Not running as root - limited user operations available"
    fi
    
    # User creation
    if ! milou_user_exists; then
        if is_running_as_root; then
            if milou_confirm "Create milou user account?" "Y"; then
                create_milou_user "true" || return 1
            fi
        else
            milou_log "ERROR" "❌ Cannot create user - run as root"
            return 1
        fi
    fi
    
    # Environment setup
    if milou_confirm "Setup milou user environment?" "Y"; then
        setup_milou_user_environment || return 1
    fi
    
    # Docker permissions
    if milou_confirm "Configure Docker permissions?" "Y"; then
        fix_docker_permissions "milou" "false" || return 1
    fi
    
    # Security hardening
    if milou_confirm "Apply security hardening?" "Y"; then
        harden_milou_user || return 1
    fi
    
    milou_log "SUCCESS" "✅ Interactive user setup completed"
    return 0
}

# Show comprehensive user status
show_user_status() {
    local username="${1:-milou}"
    
    milou_log "INFO" "📊 User Status Report: $username"
    echo
    
    # Basic user info
    if id "$username" >/dev/null 2>&1; then
        echo "✅ User exists"
        get_current_user_info
    else
        echo "❌ User does not exist"
        return 1
    fi
    
    echo
    
    # Docker permissions
    if has_docker_permissions "$username"; then
        echo "✅ Docker permissions: OK"
    else
        echo "❌ Docker permissions: Missing"
    fi
    
    # Environment status
    if validate_milou_user_environment >/dev/null 2>&1; then
        echo "✅ User environment: Configured"
    else
        echo "❌ User environment: Issues detected"
    fi
    
    # Security assessment
    echo
    echo "🔐 Security Assessment:"
    security_assessment "$username"
    
    return 0
}

# =============================================================================
# User Management Functions (from lib/user/management.sh)
# =============================================================================

# Main user management interface
user_management_main() {
    local action="${1:-interactive}"
    
    case "$action" in
        "create")
            create_milou_user "false"
            ;;
        "setup")
            setup_milou_user_environment
            ;;
        "status")
            show_user_status
            ;;
        "security")
            security_assessment
            ;;
        "interactive"|*)
            interactive_user_setup
            ;;
    esac
}

# Show user management help
show_user_management_help() {
    cat << EOF
Milou User Management Commands:

  create     - Create milou user account
  setup      - Setup user environment
  status     - Show user status
  security   - Run security assessment
  help       - Show this help

Examples:
  ./milou.sh user create
  ./milou.sh user setup
  ./milou.sh user status
EOF
}

# =============================================================================
# Module Exports
# =============================================================================

# Core user functions
export -f is_running_as_root milou_user_exists get_current_user_info
export -f create_milou_user get_milou_home validate_milou_home

# Docker integration functions
export -f has_docker_permissions fix_docker_permissions
export -f copy_docker_credentials_to_milou diagnose_docker_access

# Environment functions
export -f setup_milou_user_environment create_milou_directories
export -f setup_milou_bashrc setup_milou_profile setup_milou_symlinks
export -f validate_milou_user_environment test_milou_user_cli

# Security functions
export -f validate_user_permissions harden_milou_user
export -f security_assessment quick_security_check

# Switching functions
export -f is_directory_newer switch_to_milou_user

# Interface functions
export -f interactive_user_setup show_user_status

# Management functions
export -f user_management_main show_user_management_help

milou_log "DEBUG" "User management module loaded successfully" 