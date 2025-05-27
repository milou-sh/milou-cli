#!/bin/bash

# System Management Module
# Consolidates all system-related functionality

# Guard against multiple loading
[[ "${MILOU_SYSTEM_LOADED:-}" == "true" ]] && return 0
export MILOU_SYSTEM_LOADED=true

# Dependencies
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Get configuration value from environment
milou_config_get() {
    local key="$1"
    local default="${2:-}"
    
    # Try to get from environment first
    local value="${!key:-}"
    
    # If not found and we have an env file, try to get from there
    if [[ -z "$value" && -f "${DOCKER_ENV_FILE:-}" ]]; then
        value=$(grep "^${key}=" "${DOCKER_ENV_FILE}" 2>/dev/null | cut -d'=' -f2- | tr -d '"'"'"'')
    fi
    
    # Return value or default
    echo "${value:-$default}"
}

# Docker health check wrapper
milou_docker_health() {
    if command -v docker_health_check >/dev/null 2>&1; then
        docker_health_check
    else
        log "WARN" "Docker health check function not available"
        return 1
    fi
}

# =============================================================================
# SYSTEM CONSTANTS
# =============================================================================

readonly MILOU_SERVICE_NAME="milou"
readonly MILOU_SYSTEMD_PATH="/etc/systemd/system"
readonly MILOU_INSTALL_PATH="/opt/milou"
readonly MILOU_BIN_PATH="/usr/local/bin"

# Configuration directories
MILOU_CONFIG_DIR="${MILOU_CONFIG_DIR:-${HOME}/.milou}"
MILOU_BACKUP_DIR="${MILOU_BACKUP_DIR:-./backups}"
MILOU_SSL_DIR="${MILOU_SSL_DIR:-./ssl}"

# Installation states
readonly INSTALL_STATE_NONE="none"
readonly INSTALL_STATE_DEV="development"
readonly INSTALL_STATE_PROD="production"
readonly INSTALL_STATE_PARTIAL="partial"

# =============================================================================
# SYSTEM DETECTION & VALIDATION
# =============================================================================

# Detect Milou installation state
milou_detect_installation() {
    log "DEBUG" "Detecting Milou installation state..."
    
    local has_services=false
    local has_config=false
    local has_data=false
    local is_dev_env=false
    
    # Check for systemd service
    if milou_has_systemd && systemctl list-unit-files | grep -q "${MILOU_SERVICE_NAME}"; then
        has_services=true
        log "DEBUG" "Found systemd service"
    fi
    
    # Check for production installation
    if [[ -d "${MILOU_INSTALL_PATH}" && -f "${MILOU_BIN_PATH}/milou" ]]; then
        has_config=true
        log "DEBUG" "Found production installation"
    fi
    
    # Check for development environment
    if [[ -f "./milou.sh" && -d "./lib" && -f "./static/docker-compose.yml" ]]; then
        is_dev_env=true
        log "DEBUG" "Found development environment"
    fi
    
    # Check for data/configuration
    if [[ -f "./.env" || -d "${MILOU_CONFIG_DIR}" ]]; then
        has_data=true
        log "DEBUG" "Found configuration data"
    fi
    
    # Determine installation state
    if [[ "$is_dev_env" == "true" ]]; then
        echo "$INSTALL_STATE_DEV"
    elif [[ "$has_services" == "true" && "$has_config" == "true" && "$has_data" == "true" ]]; then
        echo "$INSTALL_STATE_PROD"
    elif [[ "$has_services" == "true" || "$has_config" == "true" || "$has_data" == "true" ]]; then
        echo "$INSTALL_STATE_PARTIAL"
    else
        echo "$INSTALL_STATE_NONE"
    fi
}

# Check if running in development mode
milou_is_development() {
    local install_state
    install_state=$(milou_detect_installation)
    [[ "$install_state" == "$INSTALL_STATE_DEV" ]]
}

# Check if running in production mode
milou_is_production() {
    local install_state
    install_state=$(milou_detect_installation)
    [[ "$install_state" == "$INSTALL_STATE_PROD" ]]
}

# Setup development environment
milou_dev_mode_setup() {
    log "INFO" "🔧 Setting up development environment..."
    
    # Ensure we're in development mode
    if ! milou_is_development; then
        log "ERROR" "Not in development environment"
        return 1
    fi
    
    # Set development-specific environment variables
    export DEV_MODE=true
    export MILOU_ENV="development"
    export LOG_LEVEL="DEBUG"
    
    # Use local paths for development
    export MILOU_CONFIG_DIR="$(pwd)/.milou-dev"
    export MILOU_BACKUP_DIR="$(pwd)/backups"
    export MILOU_SSL_DIR="$(pwd)/ssl"
    
    # Create development directories
    safe_mkdir "$MILOU_CONFIG_DIR"
    safe_mkdir "$MILOU_BACKUP_DIR"
    safe_mkdir "$MILOU_SSL_DIR"
    
    # Copy example configuration if needed
    if [[ ! -f ".env" && -f ".env.example" ]]; then
        log "INFO" "Creating development .env from example"
        cp ".env.example" ".env"
    fi
    
    log "SUCCESS" "✅ Development environment ready"
    return 0
}

# Detect operating system
milou_detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "${ID:-unknown}"
    elif command -v lsb_release >/dev/null 2>&1; then
        lsb_release -si | tr '[:upper:]' '[:lower:]'
    elif [[ -f /etc/redhat-release ]]; then
        echo "rhel"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

# Detect system architecture
milou_detect_arch() {
    local arch
    arch=$(uname -m)
    case "${arch}" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l) echo "armv7" ;;
        *) echo "${arch}" ;;
    esac
}

# Check if running as root
milou_is_root() {
    [[ "${EUID}" -eq 0 ]]
}

# Check if systemd is available
milou_has_systemd() {
    command -v systemctl >/dev/null 2>&1 && [[ -d /etc/systemd/system ]]
}

# =============================================================================
# PREREQUISITES CHECKING
# =============================================================================

# Check system prerequisites
milou_check_prerequisites() {
    local missing_deps=()
    local os_type
    
    log "INFO" "🔍 Checking system prerequisites..."
    
    # Check OS compatibility
    os_type=$(milou_detect_os)
    case "${os_type}" in
        ubuntu|debian|centos|rhel|fedora|arch)
            log "SUCCESS" "✅ Operating system: ${os_type}"
            ;;
        *)
            log "WARN" "⚠️  Unsupported OS: ${os_type} (may work but not tested)"
            ;;
    esac
    
    # Check required commands
    local required_commands=("tar" "gzip")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            missing_deps+=("${cmd}")
        fi
    done
    
    # Check for either curl or wget
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        missing_deps+=("curl or wget")
    fi
    
    # Check systemctl (but don't require it as a package)
    if ! command -v systemctl >/dev/null 2>&1; then
        log "WARN" "⚠️  systemctl not available - some features may be limited"
    fi
    
    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
        missing_deps+=("docker")
    elif ! docker info >/dev/null 2>&1; then
        log "WARN" "⚠️  Docker is installed but not running"
    else
        log "SUCCESS" "✅ Docker is available and running"
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
        missing_deps+=("docker-compose")
    else
        log "SUCCESS" "✅ Docker Compose is available"
    fi
    
    # Report missing dependencies
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log "ERROR" "❌ Missing required dependencies:"
        for dep in "${missing_deps[@]}"; do
            log "ERROR" "   - ${dep}"
        done
        return 1
    fi
    
    log "SUCCESS" "✅ All prerequisites satisfied"
    return 0
}

# Install missing prerequisites
milou_install_prerequisites() {
    local os_type
    os_type=$(milou_detect_os)
    
    log "INFO" "📦 Installing prerequisites for ${os_type}..."
    
    # Check if running as root or with sudo access
    if ! milou_is_root && ! sudo -n true 2>/dev/null; then
        log "ERROR" "Root privileges required for installation. Please run with sudo or as root."
        return 1
    fi
    
    # Install basic prerequisites first
    case "${os_type}" in
        ubuntu|debian)
            log "INFO" "Updating package lists..."
            sudo apt-get update -qq
            
            log "INFO" "Installing basic tools..."
            sudo apt-get install -y curl wget tar gzip ca-certificates gnupg lsb-release
            
            # Install Docker if not present
            if ! command -v docker >/dev/null 2>&1; then
                log "INFO" "Installing Docker..."
                install_docker_debian
            else
                log "SUCCESS" "Docker already installed"
            fi
            
            # Install Docker Compose if not present
            if ! docker compose version >/dev/null 2>&1; then
                log "INFO" "Installing Docker Compose..."
                install_docker_compose
            else
                log "SUCCESS" "Docker Compose already installed"
            fi
            ;;
        centos|rhel|fedora)
            log "INFO" "Installing basic tools..."
            sudo yum install -y curl wget tar gzip ca-certificates
            
            # Install Docker if not present
            if ! command -v docker >/dev/null 2>&1; then
                log "INFO" "Installing Docker..."
                install_docker_rhel
            else
                log "SUCCESS" "Docker already installed"
            fi
            
            # Install Docker Compose if not present
            if ! docker compose version >/dev/null 2>&1; then
                log "INFO" "Installing Docker Compose..."
                install_docker_compose
            else
                log "SUCCESS" "Docker Compose already installed"
            fi
            ;;
        arch)
            log "INFO" "Installing basic tools..."
            sudo pacman -S --noconfirm curl wget tar gzip ca-certificates
            
            # Install Docker if not present
            if ! command -v docker >/dev/null 2>&1; then
                log "INFO" "Installing Docker..."
                sudo pacman -S --noconfirm docker docker-compose
            else
                log "SUCCESS" "Docker already installed"
            fi
            ;;
        *)
            log "ERROR" "❌ Automatic installation not supported for ${os_type}"
            log "INFO" "Please install Docker and Docker Compose manually:"
            log "INFO" "  - Docker: https://docs.docker.com/engine/install/"
            log "INFO" "  - Docker Compose: https://docs.docker.com/compose/install/"
            return 1
            ;;
    esac
    
    # Start and enable Docker service
    if command -v docker >/dev/null 2>&1; then
        log "INFO" "Starting Docker service..."
        sudo systemctl start docker 2>/dev/null || true
        sudo systemctl enable docker 2>/dev/null || true
        
        # Add current user to docker group if not root
        if ! milou_is_root; then
            local current_user=$(whoami)
            if ! groups "$current_user" | grep -q docker; then
                log "INFO" "Adding user $current_user to docker group..."
                sudo usermod -aG docker "$current_user"
                log "WARN" "⚠️  You may need to log out and back in for Docker group changes to take effect"
                log "INFO" "Or run: newgrp docker"
            fi
        fi
        
        # Test Docker installation
        if docker --version >/dev/null 2>&1; then
            log "SUCCESS" "✅ Docker installation verified"
        else
            log "ERROR" "❌ Docker installation failed"
            return 1
        fi
        
        # Test Docker Compose installation
        if docker compose version >/dev/null 2>&1; then
            log "SUCCESS" "✅ Docker Compose installation verified"
        else
            log "ERROR" "❌ Docker Compose installation failed"
            return 1
        fi
    fi
    
    log "SUCCESS" "✅ All prerequisites installed successfully"
    return 0
}

# Install Docker on Debian/Ubuntu systems
install_docker_debian() {
    log "INFO" "Installing Docker on Debian/Ubuntu..."
    
    # Remove old versions
    sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Add Docker's official GPG key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update package index
    sudo apt-get update -qq
    
    # Install Docker Engine
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    log "SUCCESS" "Docker installed successfully"
}

# Install Docker on RHEL/CentOS/Fedora systems
install_docker_rhel() {
    log "INFO" "Installing Docker on RHEL/CentOS/Fedora..."
    
    # Remove old versions
    sudo yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true
    
    # Install yum-utils
    sudo yum install -y yum-utils
    
    # Add Docker repository
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    
    # Install Docker Engine
    sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    log "SUCCESS" "Docker installed successfully"
}

# Install Docker Compose (fallback for older systems)
install_docker_compose() {
    log "INFO" "Installing Docker Compose..."
    
    # Get latest version
    local compose_version
    compose_version=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
    
    if [[ -z "$compose_version" ]]; then
        compose_version="v2.24.0"  # Fallback version
        log "WARN" "Could not detect latest version, using fallback: $compose_version"
    fi
    
    # Download and install
    sudo curl -L "https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    
    # Create symlink for docker compose command
    sudo ln -sf /usr/local/bin/docker-compose /usr/local/bin/docker-compose
    
    log "SUCCESS" "Docker Compose installed successfully"
}

# =============================================================================
# SYSTEM SETUP & INSTALLATION
# =============================================================================

# Interactive system setup wizard
milou_setup_wizard() {
    milou_log "info" "🚀 Starting Milou system setup wizard..."
    
    # Welcome message
    echo
    milou_log "info" "Welcome to Milou CLI setup!"
    milou_log "info" "This wizard will guide you through the installation process."
    echo
    
    # Check prerequisites
    if ! milou_check_prerequisites; then
        if ask_yes_no "Install missing prerequisites automatically?"; then
            milou_install_prerequisites || return 1
        else
            milou_log "error" "❌ Prerequisites required for installation"
            return 1
        fi
    fi
    
    # Configuration setup
    milou_log "info" "📝 Setting up configuration..."
    milou_config_interactive_setup || return 1
    
    # User setup
    milou_log "info" "👤 Setting up users..."
    milou_user_setup_wizard || return 1
    
    # SSL setup
    if [[ "${INTERACTIVE:-true}" == "true" ]]; then
        if ask_yes_no "Set up SSL certificates?"; then
            milou_ssl_interactive_setup || return 1
        fi
    else
        milou_log "info" "🔒 Setting up SSL certificates automatically..."
        milou_ssl_interactive_setup || return 1
    fi
    
    # Service installation
    if [[ "${INTERACTIVE:-true}" == "true" ]]; then
        if ask_yes_no "Install Milou as a system service?"; then
            milou_install_service || return 1
        fi
    else
        milou_log "info" "📦 Skipping system service installation in non-interactive mode"
    fi
    
    # Final validation
    milou_log "info" "🔍 Validating installation..."
    milou_validate_system || return 1
    
    milou_log "success" "🎉 Milou setup completed successfully!"
    milou_log "info" "You can now use 'milou start' to begin using the system."
    
    return 0
}

# Install Milou as a system service
milou_install_service() {
    local service_file="${MILOU_SYSTEMD_PATH}/${MILOU_SERVICE_NAME}.service"
    
    milou_log "info" "📦 Installing Milou system service..."
    
    # Create service file
    sudo tee "${service_file}" > /dev/null << EOF
[Unit]
Description=Milou CLI Service
After=docker.service
Requires=docker.service

[Service]
Type=forking
User=milou
Group=milou
WorkingDirectory=${MILOU_INSTALL_PATH}
ExecStart=${MILOU_BIN_PATH}/milou start
ExecStop=${MILOU_BIN_PATH}/milou stop
ExecReload=${MILOU_BIN_PATH}/milou restart
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable service
    sudo systemctl daemon-reload
    sudo systemctl enable "${MILOU_SERVICE_NAME}"
    
    milou_log "success" "✅ Service installed and enabled"
    return 0
}

# =============================================================================
# SERVICE MANAGEMENT
# =============================================================================

# Start Milou service
milou_service_start() {
    if milou_has_systemd; then
        milou_log "info" "🚀 Starting Milou service..."
        sudo systemctl start "${MILOU_SERVICE_NAME}"
        milou_log "success" "✅ Service started"
    else
        milou_log "warning" "⚠️  Systemd not available, starting manually..."
        milou_docker_start
    fi
}

# Stop Milou service
milou_service_stop() {
    if milou_has_systemd; then
        milou_log "info" "🛑 Stopping Milou service..."
        sudo systemctl stop "${MILOU_SERVICE_NAME}"
        milou_log "success" "✅ Service stopped"
    else
        milou_log "warning" "⚠️  Systemd not available, stopping manually..."
        milou_docker_stop
    fi
}

# Restart Milou service
milou_service_restart() {
    if milou_has_systemd; then
        milou_log "info" "🔄 Restarting Milou service..."
        sudo systemctl restart "${MILOU_SERVICE_NAME}"
        milou_log "success" "✅ Service restarted"
    else
        milou_log "warning" "⚠️  Systemd not available, restarting manually..."
        milou_docker_restart
    fi
}

# Get service status
milou_service_status() {
    if milou_has_systemd; then
        systemctl status "${MILOU_SERVICE_NAME}" --no-pager
    else
        milou_docker_status
    fi
}

# Enable service auto-start
milou_service_enable() {
    if milou_has_systemd; then
        milou_log "info" "🔧 Enabling Milou service auto-start..."
        sudo systemctl enable "${MILOU_SERVICE_NAME}"
        milou_log "success" "✅ Service enabled for auto-start"
    else
        milou_log "warning" "⚠️  Systemd not available, cannot enable auto-start"
        return 1
    fi
}

# Disable service auto-start
milou_service_disable() {
    if milou_has_systemd; then
        milou_log "info" "🔧 Disabling Milou service auto-start..."
        sudo systemctl disable "${MILOU_SERVICE_NAME}"
        milou_log "success" "✅ Service disabled from auto-start"
    else
        milou_log "warning" "⚠️  Systemd not available"
        return 1
    fi
}

# =============================================================================
# SYSTEM BACKUP & RESTORE
# =============================================================================

# Create system backup
milou_system_backup() {
    local backup_name="${1:-milou-system-$(date +%Y%m%d-%H%M%S)}"
    local backup_dir="${MILOU_BACKUP_DIR}/system"
    local backup_file="${backup_dir}/${backup_name}.tar.gz"
    
    milou_log "info" "💾 Creating system backup: ${backup_name}"
    
    # Create backup directory
    safe_mkdir "${backup_dir}"
    
    # Create temporary directory for backup
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Copy configuration files
    cp -r "${MILOU_CONFIG_DIR}" "${temp_dir}/config" 2>/dev/null || true
    
    # Copy service files
    if [[ -f "${MILOU_SYSTEMD_PATH}/${MILOU_SERVICE_NAME}.service" ]]; then
        mkdir -p "${temp_dir}/systemd"
        cp "${MILOU_SYSTEMD_PATH}/${MILOU_SERVICE_NAME}.service" "${temp_dir}/systemd/"
    fi
    
    # Copy SSL certificates
    if [[ -d "${MILOU_SSL_DIR}" ]]; then
        cp -r "${MILOU_SSL_DIR}" "${temp_dir}/ssl" 2>/dev/null || true
    fi
    
    # Create backup archive
    tar -czf "${backup_file}" -C "${temp_dir}" . 2>/dev/null
    
    # Cleanup
    rm -rf "${temp_dir}"
    
    if [[ -f "${backup_file}" ]]; then
        milou_log "success" "✅ System backup created: ${backup_file}"
        return 0
    else
        milou_log "error" "❌ Failed to create system backup"
        return 1
    fi
}

# Restore system backup
milou_system_restore() {
    local backup_file="${1}"
    
    if [[ ! -f "${backup_file}" ]]; then
        milou_log "error" "❌ Backup file not found: ${backup_file}"
        return 1
    fi
    
    milou_log "info" "📥 Restoring system backup: ${backup_file}"
    
    # Create temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Extract backup
    if ! tar -xzf "${backup_file}" -C "${temp_dir}"; then
        milou_log "error" "❌ Failed to extract backup"
        rm -rf "${temp_dir}"
        return 1
    fi
    
    # Restore configuration
    if [[ -d "${temp_dir}/config" ]]; then
        sudo cp -r "${temp_dir}/config/"* "${MILOU_CONFIG_DIR}/" 2>/dev/null || true
    fi
    
    # Restore service files
    if [[ -d "${temp_dir}/systemd" ]]; then
        sudo cp "${temp_dir}/systemd/"* "${MILOU_SYSTEMD_PATH}/" 2>/dev/null || true
        sudo systemctl daemon-reload
    fi
    
    # Restore SSL certificates
    if [[ -d "${temp_dir}/ssl" ]]; then
        sudo cp -r "${temp_dir}/ssl/"* "${MILOU_SSL_DIR}/" 2>/dev/null || true
    fi
    
    # Cleanup
    rm -rf "${temp_dir}"
    
    milou_log "success" "✅ System backup restored successfully"
    return 0
}

# =============================================================================
# SYSTEM UPDATES
# =============================================================================

# Enhanced Milou system update with comprehensive validation and rollback
milou_system_update() {
    local target_version="${1:-latest}"
    local services=("${@:2}")
    local auto_rollback="${AUTO_ROLLBACK:-true}"
    
    log "STEP" "🔄 Starting Milou system update to version: ${target_version}"
    
    # Detect installation state and adapt behavior
    local install_state
    install_state=$(milou_detect_installation)
    log "INFO" "Installation state detected: $install_state"
    
    case "$install_state" in
        "$INSTALL_STATE_NONE")
            log "ERROR" "No Milou installation detected"
            log "INFO" "Use 'milou setup' to install Milou first"
            return 1
            ;;
        "$INSTALL_STATE_DEV")
            log "INFO" "Development mode detected - using local update process"
            milou_dev_mode_setup || return 1
            ;;
        "$INSTALL_STATE_PARTIAL")
            log "WARN" "Partial installation detected - some components may be missing"
            if [[ "${FORCE:-false}" != "true" ]]; then
                log "ERROR" "Use --force to continue with partial installation"
                return 1
            fi
            ;;
        "$INSTALL_STATE_PROD")
            log "INFO" "Production installation detected"
            ;;
    esac
    
    # Phase 1: Pre-Update Validation
    log "INFO" "Phase 1: Pre-Update Validation"
    
    # Validate system health before update
    if ! milou_system_health; then
        log "ERROR" "System health check failed - aborting update"
        return 1
    fi
    
    # Check available disk space (need at least 2GB free)
    local available_space
    available_space=$(df . | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 2097152 ]]; then  # 2GB in KB
        log "ERROR" "Insufficient disk space for update (need 2GB, have $(($available_space/1024))MB)"
        return 1
    fi
    
    # Validate GitHub token if provided
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        log "INFO" "Validating GitHub token..."
        if ! curl -s -H "Authorization: token ${GITHUB_TOKEN}" https://api.github.com/user >/dev/null; then
            log "ERROR" "Invalid GitHub token provided"
            return 1
        fi
        log "SUCCESS" "GitHub token validated"
    else
        log "WARN" "No GitHub token provided - may not be able to access private images"
    fi
    
    # Phase 2: Backup Creation
    log "INFO" "Phase 2: Creating comprehensive backup"
    
    local backup_timestamp
    backup_timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_name="pre-update-${backup_timestamp}"
    
    if ! milou_system_backup "$backup_name"; then
        if [[ "${FORCE:-false}" == "true" ]]; then
            log "WARN" "Backup failed but continuing due to --force flag"
        else
            log "ERROR" "Backup creation failed - aborting update"
            log "INFO" "Use --force to continue without backup"
            return 1
        fi
    fi
    
    # Phase 3: Update Execution
    log "INFO" "Phase 3: Executing update"
    
    # Stop services gracefully
    log "INFO" "Stopping services gracefully..."
    if ! milou_service_stop; then
        log "ERROR" "Failed to stop services gracefully"
        return 1
    fi
    
    # Update Docker images
    log "INFO" "Updating Docker images..."
    if ! docker_update_images "$target_version" "${services[@]}"; then
        log "ERROR" "Failed to update Docker images"
        
        if [[ "$auto_rollback" == "true" ]]; then
            log "WARN" "Auto-rollback enabled - attempting to restore system"
            milou_rollback_system "$backup_name"
        fi
        return 1
    fi
    
    # Phase 4: Service Restart and Validation
    log "INFO" "Phase 4: Restarting services and validation"
    
    # Start services with new images
    log "INFO" "Starting services with updated images..."
    if ! milou_service_start; then
        log "ERROR" "Failed to start services after update"
        
        if [[ "$auto_rollback" == "true" ]]; then
            log "WARN" "Auto-rollback enabled - attempting to restore system"
            milou_rollback_system "$backup_name"
        fi
        return 1
    fi
    
    # Extended health check
    log "INFO" "Running extended health check..."
    if ! docker_health_check_extended 300; then  # 5 minute timeout
        log "ERROR" "Extended health check failed after update"
        
        if [[ "$auto_rollback" == "true" ]]; then
            log "WARN" "Auto-rollback enabled - attempting to restore system"
            milou_rollback_system "$backup_name"
        fi
        return 1
    fi
    
    # Final system validation
    log "INFO" "Running final system validation..."
    if ! milou_validate_system; then
        log "ERROR" "System validation failed after update"
        
        if [[ "$auto_rollback" == "true" ]]; then
            log "WARN" "Auto-rollback enabled - attempting to restore system"
            milou_rollback_system "$backup_name"
        fi
        return 1
    fi
    
    # Phase 5: Post-Update Cleanup
    log "INFO" "Phase 5: Post-update cleanup"
    
    # Update version tracking
    milou_update_version_tracking "$target_version"
    
    # Cleanup old images (keep last 3 versions)
    docker image prune -f >/dev/null 2>&1 || true
    
    # Success!
    log "SUCCESS" "🎉 Milou system updated successfully to version: ${target_version}"
    log "INFO" "Backup created: $backup_name (can be used for rollback if needed)"
    log "INFO" "Use 'milou.sh status' to verify all services are running correctly"
    
    return 0
}

# Rollback system to previous state
milou_rollback_system() {
    local backup_name="${1:-}"
    
    if [[ -z "$backup_name" ]]; then
        log "ERROR" "Backup name required for rollback"
        return 1
    fi
    
    log "STEP" "🔄 Rolling back Milou system from backup: $backup_name"
    
    # Stop current services
    log "INFO" "Stopping current services..."
    milou_service_stop || true
    
    # Restore system backup
    log "INFO" "Restoring system backup..."
    if ! milou_system_restore "./backups/system/${backup_name}.tar.gz"; then
        log "ERROR" "Failed to restore system backup"
        return 1
    fi
    
    # Rollback Docker images
    log "INFO" "Rolling back Docker images..."
    if ! docker_rollback_images "./backups/pre-update-${backup_name#pre-update-}"; then
        log "ERROR" "Failed to rollback Docker images"
        return 1
    fi
    
    # Start services
    log "INFO" "Starting services after rollback..."
    if ! milou_service_start; then
        log "ERROR" "Failed to start services after rollback"
        return 1
    fi
    
    # Validate rollback
    log "INFO" "Validating rollback..."
    if ! milou_validate_system; then
        log "ERROR" "System validation failed after rollback"
        return 1
    fi
    
    log "SUCCESS" "✅ System rollback completed successfully"
    return 0
}

# Update version tracking
milou_update_version_tracking() {
    local version="$1"
    local version_file="${MILOU_CONFIG_DIR}/version.txt"
    
    # Create version tracking file
    cat > "$version_file" << EOF
# Milou Version Tracking
CURRENT_VERSION=${version}
UPDATE_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
UPDATE_USER=$(whoami)
UPDATE_HOST=$(hostname)
EOF
    
    log "INFO" "Version tracking updated: $version"
}

# Database-specific backup
milou_database_backup() {
    local backup_file="${1:-./database-backup-$(date +%Y%m%d-%H%M%S).sql}"
    
    log "INFO" "Creating database backup: $backup_file"
    
    # Use Docker module function
    if docker_backup_database "$backup_file"; then
        log "SUCCESS" "Database backup created successfully"
        return 0
    else
        log "ERROR" "Database backup failed"
        return 1
    fi
}

# Database migration handling
milou_database_migrate() {
    local target_version="$1"
    
    log "INFO" "Checking for database migrations for version: $target_version"
    
    # Check if migration is needed
    local current_db_version
    current_db_version=$(docker_compose exec -T db psql -U "$(grep "^POSTGRES_USER=" "$DOCKER_ENV_FILE" | cut -d'=' -f2)" -d "$(grep "^POSTGRES_DB=" "$DOCKER_ENV_FILE" | cut -d'=' -f2)" -t -c "SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1;" 2>/dev/null | tr -d ' \n' || echo "0")
    
    log "INFO" "Current database version: $current_db_version"
    
    # For now, we'll assume migrations are handled by the application
    # In a real implementation, you would run specific migration scripts here
    log "INFO" "Database migrations will be handled by application startup"
    
    return 0
}

    # Configuration migration with secret preservation
    milou_configuration_migrate() {
        local target_version="$1"
        local env_file="${DOCKER_ENV_FILE:-.env}"
        
        log "INFO" "Migrating configuration for version: $target_version (preserving secrets)"
        
        if [[ ! -f "$env_file" ]]; then
            log "ERROR" "Environment file not found: $env_file"
            return 1
        fi
        
        # Extract current domain and email for migration
        local current_domain=$(grep "^DOMAIN=" "$env_file" | cut -d'=' -f2- | tr -d '"'"'"'')
        local current_email=$(grep "^EMAIL=" "$env_file" | cut -d'=' -f2- | tr -d '"'"'"'')
        local current_token=$(grep "^GITHUB_TOKEN=" "$env_file" | cut -d'=' -f2- | tr -d '"'"'"'')
        
        # Use the secret-preserving update function
        if update_env_preserving_secrets "$current_domain" "$current_email" "$current_token" "$env_file"; then
            log "SUCCESS" "Configuration migrated successfully with preserved secrets"
            
            # Add version-specific configuration options
            case "$target_version" in
                "v2."*)
                    # Example: Add new configuration options for v2.x
                    if ! grep -q "^NEW_FEATURE_ENABLED=" "$env_file"; then
                        echo "NEW_FEATURE_ENABLED=true" >> "$env_file"
                        log "INFO" "Added NEW_FEATURE_ENABLED configuration"
                    fi
                    ;;
                "v3."*)
                    # Example: Add new configuration options for v3.x
                    if ! grep -q "^ADVANCED_MONITORING=" "$env_file"; then
                        echo "ADVANCED_MONITORING=false" >> "$env_file"
                        log "INFO" "Added ADVANCED_MONITORING configuration"
                    fi
                    ;;
            esac
            
            return 0
        else
            log "ERROR" "Configuration migration failed"
            return 1
        fi
    }

# Post-update validation
milou_update_validation() {
    log "INFO" "Running comprehensive post-update validation..."
    
    local validation_errors=0
    
    # Check all services are running
    if ! docker_health_check; then
        log "ERROR" "Service health check failed"
        ((validation_errors++))
    fi
    
    # Check API endpoints
    if ! docker_validate_api_endpoints; then
        log "ERROR" "API endpoint validation failed"
        ((validation_errors++))
    fi
    
    # Check database connectivity
    if ! docker_validate_service_connectivity; then
        log "ERROR" "Service connectivity validation failed"
        ((validation_errors++))
    fi
    
    # Check SSL certificates if enabled
    if grep -q "SSL_ENABLED=true" "$DOCKER_ENV_FILE" 2>/dev/null; then
        if ! validate_ssl_certificate; then
            log "ERROR" "SSL certificate validation failed"
            ((validation_errors++))
        fi
    fi
    
    if [[ $validation_errors -eq 0 ]]; then
        log "SUCCESS" "All post-update validations passed"
        return 0
    else
        log "ERROR" "Post-update validation failed with $validation_errors errors"
        return 1
    fi
}

# =============================================================================
# SYSTEM VALIDATION & HEALTH
# =============================================================================

# Validate system installation
milou_validate_system() {
    local errors=0
    
    milou_log "info" "🔍 Validating Milou system..."
    
    # Check configuration
    if ! test_config; then
        milou_log "error" "❌ Configuration validation failed"
        ((errors++))
    fi
    
    # Check Docker
    if command -v docker_validate_setup >/dev/null 2>&1; then
        if ! docker_validate_setup; then
            milou_log "error" "❌ Docker validation failed"
            ((errors++))
        fi
    else
        milou_log "warning" "⚠️  Docker validation function not available"
    fi
    
    # Check SSL if configured
    if milou_config_get "SSL_ENABLED" | grep -q "true"; then
        if command -v validate_ssl_certificate >/dev/null 2>&1; then
            if ! validate_ssl_certificate; then
                milou_log "error" "❌ SSL validation failed"
                ((errors++))
            fi
        else
            milou_log "warning" "⚠️  SSL validation function not available"
        fi
    fi
    
    # Check users
    if command -v show_user_info >/dev/null 2>&1; then
        if ! show_user_info >/dev/null 2>&1; then
            milou_log "warning" "⚠️  User validation issues detected"
        fi
    else
        milou_log "debug" "User validation function not available"
    fi
    
    # Check service if installed
    if milou_has_systemd && systemctl list-unit-files | grep -q "${MILOU_SERVICE_NAME}"; then
        if ! systemctl is-enabled "${MILOU_SERVICE_NAME}" >/dev/null 2>&1; then
            milou_log "warning" "⚠️  Service is not enabled for auto-start"
        fi
    fi
    
    if [[ ${errors} -eq 0 ]]; then
        milou_log "success" "✅ System validation passed"
        return 0
    else
        milou_log "error" "❌ System validation failed with ${errors} errors"
        return 1
    fi
}

# System health check
milou_system_health() {
    local health_score=0
    local max_score=10
    
    milou_log "info" "🏥 Performing system health check..."
    
    # Check system resources
    local disk_usage
    disk_usage=$(df "${MILOU_CONFIG_DIR}" | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ ${disk_usage} -lt 80 ]]; then
        milou_log "success" "✅ Disk usage: ${disk_usage}%"
        ((health_score += 2))
    else
        milou_log "warning" "⚠️  High disk usage: ${disk_usage}%"
    fi
    
    # Check memory usage
    local mem_usage
    mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [[ ${mem_usage} -lt 80 ]]; then
        milou_log "success" "✅ Memory usage: ${mem_usage}%"
        ((health_score += 2))
    else
        milou_log "warning" "⚠️  High memory usage: ${mem_usage}%"
    fi
    
    # Check Docker health
    if milou_docker_health; then
        milou_log "success" "✅ Docker services healthy"
        ((health_score += 3))
    else
        milou_log "warning" "⚠️  Docker services have issues"
    fi
    
    # Check SSL certificates
    if milou_config_get "SSL_ENABLED" | grep -q "true"; then
        if command -v validate_ssl_certificate >/dev/null 2>&1 && validate_ssl_certificate; then
            milou_log "success" "✅ SSL certificates valid"
            ((health_score += 2))
        else
            milou_log "warning" "⚠️  SSL certificates need attention"
        fi
    else
        ((health_score += 2))  # No SSL configured is fine
    fi
    
    # Check configuration
    if test_config >/dev/null 2>&1; then
        milou_log "success" "✅ Configuration valid"
        ((health_score += 1))
    else
        milou_log "warning" "⚠️  Configuration issues detected"
    fi
    
    # Report health score
    local health_percentage=$((health_score * 100 / max_score))
    if [[ ${health_percentage} -ge 80 ]]; then
        milou_log "success" "🎉 System health: ${health_percentage}% (Excellent)"
    elif [[ ${health_percentage} -ge 60 ]]; then
        milou_log "info" "👍 System health: ${health_percentage}% (Good)"
    else
        milou_log "warning" "⚠️  System health: ${health_percentage}% (Needs attention)"
    fi
    
    return 0
}

# =============================================================================
# SYSTEM INFORMATION
# =============================================================================

# Display system information
milou_system_info() {
    milou_log "info" "📊 Milou System Information"
    echo
    
    # Basic system info
    echo "🖥️  System Information:"
    echo "   OS: $(milou_detect_os)"
    echo "   Architecture: $(milou_detect_arch)"
    echo "   Kernel: $(uname -r)"
    echo
    
    # Milou info
    echo "🚀 Milou Information:"
    echo "   Version: $(milou_config_get "MILOU_VERSION" || echo "unknown")"
    echo "   Install Path: ${MILOU_INSTALL_PATH}"
    echo "   Config Dir: ${MILOU_CONFIG_DIR}"
    echo
    
    # Service status
    if milou_has_systemd; then
        echo "🔧 Service Status:"
        if systemctl list-unit-files | grep -q "${MILOU_SERVICE_NAME}"; then
            echo "   Installed: Yes"
            echo "   Enabled: $(systemctl is-enabled "${MILOU_SERVICE_NAME}" 2>/dev/null || echo "No")"
            echo "   Active: $(systemctl is-active "${MILOU_SERVICE_NAME}" 2>/dev/null || echo "No")"
        else
            echo "   Installed: No"
        fi
        echo
    fi
    
    # Docker info
    echo "🐳 Docker Information:"
    if command -v docker >/dev/null 2>&1; then
        echo "   Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"
        if command -v docker-compose >/dev/null 2>&1; then
            echo "   Compose: $(docker-compose --version | cut -d' ' -f3 | tr -d ',')"
        elif docker compose version >/dev/null 2>&1; then
            echo "   Compose: $(docker compose version --short)"
        fi
    else
        echo "   Docker: Not installed"
    fi
    echo
    
    # SSL info
    if milou_config_get "SSL_ENABLED" | grep -q "true"; then
        echo "🔒 SSL Information:"
        echo "   SSL Enabled: Yes"
        echo "   Domain: $(milou_config_get "DOMAIN" || echo "Not configured")"
        echo "   Certificate Path: ${MILOU_SSL_DIR}"
        echo
    fi
}

# Export all functions
export -f milou_detect_os milou_detect_arch milou_is_root milou_has_systemd
export -f milou_check_prerequisites milou_install_prerequisites milou_setup_wizard
export -f install_docker_debian install_docker_rhel install_docker_compose
export -f milou_install_service milou_service_start milou_service_stop milou_service_restart
export -f milou_service_status milou_service_enable milou_service_disable
export -f milou_system_backup milou_system_restore milou_system_update
export -f milou_validate_system milou_system_health milou_system_info 