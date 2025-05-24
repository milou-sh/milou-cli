#!/bin/bash

# =============================================================================
# User Environment Setup for Milou CLI
# Handles environment configuration, directories, and shell setup
# =============================================================================

# Source utility functions
source "${BASH_SOURCE%/*}/user-core.sh" 2>/dev/null || true

# =============================================================================
# Environment Setup
# =============================================================================

# Setup milou user environment
setup_milou_user_environment() {
    local milou_home
    milou_home=$(get_milou_home)
    
    if [[ -z "$milou_home" || ! -d "$milou_home" ]]; then
        if [[ -z "$milou_home" ]]; then
            log "WARN" "Milou user home directory not found, using /home/$MILOU_USER"
            milou_home="/home/$MILOU_USER"
        fi
        mkdir -p "$milou_home"
        chown "$MILOU_USER:$MILOU_GROUP" "$milou_home"
    fi
    
    log "DEBUG" "Setting up environment for $MILOU_USER in $milou_home"
    
    # Create necessary directories with proper structure
    create_milou_directories "$milou_home"
    
    # Create or update shell configuration
    setup_milou_bashrc "$milou_home"
    setup_milou_profile "$milou_home"
    
    # Create initial configuration files
    setup_milou_config "$milou_home"
    
    # Create helpful symlinks
    setup_milou_symlinks "$milou_home"
    
    # Set proper ownership for home directory
    chown -R "$MILOU_USER:$MILOU_GROUP" "$milou_home"
    
    # Secure sensitive directories
    chmod 700 "$milou_home/.milou"
    
    log "SUCCESS" "Environment setup completed for $MILOU_USER"
    log "INFO" "Configuration directory: $milou_home/.milou"
    log "INFO" "CLI location will be auto-detected on login"
}

# Create necessary directories for milou user
create_milou_directories() {
    local milou_home="$1"
    
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
}

# Setup enhanced bashrc for milou user
setup_milou_bashrc() {
    local milou_home="$1"
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
}

# Setup profile for non-interactive shells
setup_milou_profile() {
    local milou_home="$1"
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
}

# Setup initial configuration template
setup_milou_config() {
    local milou_home="$1"
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
}

# Setup helpful symlinks
setup_milou_symlinks() {
    local milou_home="$1"
    local bin_symlink="$milou_home/bin/milou"
    
    if [[ -d "$milou_home/milou-cli" && -f "$milou_home/milou-cli/milou.sh" ]]; then
        ln -sf "$milou_home/milou-cli/milou.sh" "$bin_symlink" 2>/dev/null || true
        chown -h "$MILOU_USER:$MILOU_GROUP" "$bin_symlink" 2>/dev/null || true
    fi
}

# =============================================================================
# Environment Validation
# =============================================================================

# Validate milou user environment and CLI accessibility
validate_milou_user_environment() {
    log "DEBUG" "Validating milou user environment..."
    
    if ! milou_user_exists; then
        log "ERROR" "Milou user does not exist"
        return 1
    fi
    
    local milou_home issues=0
    milou_home=$(get_milou_home)
    
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
    milou_home=$(get_milou_home)
    
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

# Export functions for use in other scripts
export -f setup_milou_user_environment
export -f create_milou_directories
export -f setup_milou_bashrc
export -f setup_milou_profile
export -f setup_milou_config
export -f setup_milou_symlinks
export -f validate_milou_user_environment
export -f test_milou_user_cli 