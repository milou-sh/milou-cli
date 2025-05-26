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
# SYSTEM CONSTANTS
# =============================================================================

readonly MILOU_SERVICE_NAME="milou"
readonly MILOU_SYSTEMD_PATH="/etc/systemd/system"
readonly MILOU_INSTALL_PATH="/opt/milou"
readonly MILOU_BIN_PATH="/usr/local/bin"

# =============================================================================
# SYSTEM DETECTION & VALIDATION
# =============================================================================

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
    
    milou_log "info" "🔍 Checking system prerequisites..."
    
    # Check OS compatibility
    os_type=$(milou_detect_os)
    case "${os_type}" in
        ubuntu|debian|centos|rhel|fedora|arch)
            milou_log "success" "✅ Operating system: ${os_type}"
            ;;
        *)
            milou_log "warning" "⚠️  Unsupported OS: ${os_type} (may work but not tested)"
            ;;
    esac
    
    # Check required commands
    local required_commands=("curl" "wget" "tar" "gzip" "systemctl")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            missing_deps+=("${cmd}")
        fi
    done
    
    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
        missing_deps+=("docker")
    elif ! docker info >/dev/null 2>&1; then
        milou_log "warning" "⚠️  Docker is installed but not running"
    else
        milou_log "success" "✅ Docker is available and running"
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
        missing_deps+=("docker-compose")
    else
        milou_log "success" "✅ Docker Compose is available"
    fi
    
    # Report missing dependencies
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        milou_log "error" "❌ Missing required dependencies:"
        for dep in "${missing_deps[@]}"; do
            milou_log "error" "   - ${dep}"
        done
        return 1
    fi
    
    milou_log "success" "✅ All prerequisites satisfied"
    return 0
}

# Install missing prerequisites
milou_install_prerequisites() {
    local os_type
    os_type=$(milou_detect_os)
    
    milou_log "info" "📦 Installing prerequisites for ${os_type}..."
    
    case "${os_type}" in
        ubuntu|debian)
            sudo apt-get update
            sudo apt-get install -y curl wget tar gzip systemctl
            ;;
        centos|rhel|fedora)
            sudo yum install -y curl wget tar gzip systemd
            ;;
        arch)
            sudo pacman -S --noconfirm curl wget tar gzip systemd
            ;;
        *)
            milou_log "error" "❌ Automatic installation not supported for ${os_type}"
            return 1
            ;;
    esac
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
        if milou_prompt_yes_no "Install missing prerequisites automatically?"; then
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
    if milou_prompt_yes_no "Set up SSL certificates?"; then
        milou_ssl_interactive_setup || return 1
    fi
    
    # Service installation
    if milou_prompt_yes_no "Install Milou as a system service?"; then
        milou_install_service || return 1
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
    milou_safe_mkdir "${backup_dir}"
    
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

# Update Milou system
milou_system_update() {
    local version="${1:-latest}"
    
    milou_log "info" "🔄 Updating Milou system to version: ${version}"
    
    # Create backup before update
    milou_system_backup "pre-update-$(date +%Y%m%d-%H%M%S)" || {
        milou_log "warning" "⚠️  Failed to create backup, continuing anyway..."
    }
    
    # Stop services
    milou_service_stop
    
    # Update Docker images
    milou_docker_update || {
        milou_log "error" "❌ Failed to update Docker images"
        return 1
    }
    
    # Restart services
    milou_service_start
    
    # Validate update
    milou_validate_system || {
        milou_log "error" "❌ System validation failed after update"
        return 1
    }
    
    milou_log "success" "✅ System updated successfully"
    return 0
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
    if ! milou_docker_validate; then
        milou_log "error" "❌ Docker validation failed"
        ((errors++))
    fi
    
    # Check SSL if configured
    if milou_config_get "SSL_ENABLED" | grep -q "true"; then
        if ! milou_ssl_validate; then
            milou_log "error" "❌ SSL validation failed"
            ((errors++))
        fi
    fi
    
    # Check users
    if ! milou_user_validate; then
        milou_log "error" "❌ User validation failed"
        ((errors++))
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
        if milou_ssl_check_expiry; then
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
export -f milou_install_service milou_service_start milou_service_stop milou_service_restart
export -f milou_service_status milou_service_enable milou_service_disable
export -f milou_system_backup milou_system_restore milou_system_update
export -f milou_validate_system milou_system_health milou_system_info 