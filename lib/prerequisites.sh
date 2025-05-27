#!/bin/bash

# =============================================================================
# Prerequisites Module for Milou CLI
# Consolidated system prerequisites detection, Docker setup, and tools installation
# =============================================================================

# Module guard to prevent multiple loading
if [[ "${MILOU_PREREQUISITES_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_PREREQUISITES_LOADED="true"

# Ensure logging is available
if ! command -v milou_log >/dev/null 2>&1; then
    local script_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    if [[ -f "${script_dir}/lib/core/logging.sh" ]]; then
        source "${script_dir}/lib/core/logging.sh"
    else
        echo "ERROR: Logging module not available" >&2
        return 1
    fi
fi

# =============================================================================
# System Detection Functions (from detection.sh)
# =============================================================================

# Detect operating system
milou_prereq_detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "$ID"
    elif [[ -f /etc/redhat-release ]]; then
        echo "rhel"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

# Detect package manager
milou_prereq_detect_package_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    elif command -v zypper >/dev/null 2>&1; then
        echo "zypper"
    elif command -v brew >/dev/null 2>&1; then
        echo "brew"
    else
        echo "unknown"
    fi
}

# Check if running as root
milou_prereq_is_root() {
    [[ $EUID -eq 0 ]]
}

# Check if user has sudo access
milou_prereq_has_sudo() {
    sudo -n true 2>/dev/null
}

# Get system architecture
milou_prereq_get_architecture() {
    uname -m
}

# =============================================================================
# Docker Prerequisites Functions (from docker.sh)
# =============================================================================

# Check if Docker is installed
milou_prereq_check_docker_installed() {
    command -v docker >/dev/null 2>&1
}

# Check if Docker daemon is running
milou_prereq_check_docker_running() {
    docker info >/dev/null 2>&1
}

# Check if Docker Compose is available
milou_prereq_check_docker_compose() {
    docker compose version >/dev/null 2>&1
}

# Install Docker using official installation script
milou_prereq_install_docker() {
    local auto_install="${1:-true}"
    local pkg_manager="${2:-$(milou_prereq_detect_package_manager)}"
    
    milou_log "STEP" "Installing Docker..."
    
    if milou_prereq_check_docker_installed; then
        milou_log "SUCCESS" "Docker is already installed"
        return 0
    fi
    
    if [[ "$auto_install" != "true" ]]; then
        milou_log "INFO" "Manual Docker installation required"
        milou_prereq_show_docker_manual_instructions "$pkg_manager"
        return 1
    fi
    
    # Install Docker using official script
    milou_log "INFO" "Downloading and running Docker installation script..."
    
    if curl -fsSL https://get.docker.com -o get-docker.sh && \
       chmod +x get-docker.sh && \
       sudo sh get-docker.sh; then
        
        rm -f get-docker.sh
        
        # Add current user to docker group if not root
        if ! milou_prereq_is_root && [[ -n "${USER:-}" ]]; then
            milou_log "INFO" "Adding user $USER to docker group..."
            sudo usermod -aG docker "$USER"
            milou_log "WARN" "Please log out and back in for Docker group changes to take effect"
        fi
        
        # Start and enable Docker service
        if command -v systemctl >/dev/null 2>&1; then
            sudo systemctl start docker
            sudo systemctl enable docker
        fi
        
        milou_log "SUCCESS" "Docker installed successfully"
        return 0
    else
        milou_log "ERROR" "Failed to install Docker"
        rm -f get-docker.sh
        return 1
    fi
}

# Show manual Docker installation instructions
milou_prereq_show_docker_manual_instructions() {
    local pkg_manager="$1"
    
    echo
    milou_log "INFO" "Manual Docker Installation Instructions"
    echo "========================================"
    echo
    
    case "$pkg_manager" in
        "apt")
            echo "For Ubuntu/Debian:"
            echo "  sudo apt-get update"
            echo "  sudo apt-get install -y docker.io docker-compose-plugin"
            echo "  sudo systemctl start docker"
            echo "  sudo systemctl enable docker"
            echo "  sudo usermod -aG docker \$USER"
            ;;
        "yum"|"dnf")
            echo "For RHEL/CentOS/Fedora:"
            echo "  sudo $pkg_manager install -y docker docker-compose-plugin"
            echo "  sudo systemctl start docker"
            echo "  sudo systemctl enable docker"
            echo "  sudo usermod -aG docker \$USER"
            ;;
        "pacman")
            echo "For Arch Linux:"
            echo "  sudo pacman -S docker docker-compose"
            echo "  sudo systemctl start docker"
            echo "  sudo systemctl enable docker"
            echo "  sudo usermod -aG docker \$USER"
            ;;
        *)
            echo "Please install Docker manually from: https://docs.docker.com/get-docker/"
            ;;
    esac
    
    echo
    echo "After installation:"
    echo "  1. Log out and back in (for group changes)"
    echo "  2. Test with: docker --version"
    echo "  3. Test with: docker compose version"
}

# Configure Docker for non-root user
milou_prereq_configure_docker_user() {
    local username="${1:-$USER}"
    
    if [[ -z "$username" ]]; then
        milou_log "ERROR" "Username is required"
        return 1
    fi
    
    milou_log "INFO" "Configuring Docker for user: $username"
    
    # Add user to docker group
    if sudo usermod -aG docker "$username"; then
        milou_log "SUCCESS" "User $username added to docker group"
        milou_log "WARN" "Please log out and back in for changes to take effect"
        return 0
    else
        milou_log "ERROR" "Failed to add user to docker group"
        return 1
    fi
}

# =============================================================================
# System Tools Installation Functions (from tools.sh)
# =============================================================================

# Install required system tools
milou_prereq_install_required_tools() {
    local pkg_manager="$1"
    
    milou_log "STEP" "Installing required system tools..."
    
    local -a required_packages=()
    local -a missing_tools=()
    
    # Check for missing tools
    local -a tools_to_check=("curl" "wget" "jq" "openssl" "git" "date" "sed" "grep" "awk" "timeout")
    
    for tool in "${tools_to_check[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -eq 0 ]]; then
        milou_log "SUCCESS" "All required tools are already installed"
        return 0
    fi
    
    milou_log "INFO" "Missing tools: ${missing_tools[*]}"
    
    # Map tools to packages based on distribution
    case "$pkg_manager" in
        "apt")
            for tool in "${missing_tools[@]}"; do
                case "$tool" in
                    "curl") required_packages+=("curl") ;;
                    "wget") required_packages+=("wget") ;;
                    "jq") required_packages+=("jq") ;;
                    "openssl") required_packages+=("openssl") ;;
                    "git") required_packages+=("git") ;;
                    "date"|"sed"|"grep"|"awk"|"timeout") required_packages+=("coreutils") ;;
                esac
            done
            apt-get install -y "${required_packages[@]}"
            ;;
        "yum"|"dnf")
            for tool in "${missing_tools[@]}"; do
                case "$tool" in
                    "curl") required_packages+=("curl") ;;
                    "wget") required_packages+=("wget") ;;
                    "jq") required_packages+=("jq") ;;
                    "openssl") required_packages+=("openssl") ;;
                    "git") required_packages+=("git") ;;
                    "date"|"sed"|"grep"|"awk"|"timeout") required_packages+=("coreutils") ;;
                esac
            done
            $pkg_manager install -y "${required_packages[@]}"
            ;;
        "pacman")
            for tool in "${missing_tools[@]}"; do
                case "$tool" in
                    "curl") required_packages+=("curl") ;;
                    "wget") required_packages+=("wget") ;;
                    "jq") required_packages+=("jq") ;;
                    "openssl") required_packages+=("openssl") ;;
                    "git") required_packages+=("git") ;;
                    "date"|"sed"|"grep"|"awk"|"timeout") required_packages+=("coreutils") ;;
                esac
            done
            pacman -S --noconfirm "${required_packages[@]}"
            ;;
        "zypper")
            for tool in "${missing_tools[@]}"; do
                case "$tool" in
                    "curl") required_packages+=("curl") ;;
                    "wget") required_packages+=("wget") ;;
                    "jq") required_packages+=("jq") ;;
                    "openssl") required_packages+=("openssl") ;;
                    "git") required_packages+=("git") ;;
                    "date"|"sed"|"grep"|"awk"|"timeout") required_packages+=("coreutils") ;;
                esac
            done
            zypper install -y "${required_packages[@]}"
            ;;
        *)
            milou_log "ERROR" "Unsupported package manager for automatic tool installation"
            return 1
            ;;
    esac
    
    # Verify installation
    local failed_tools=()
    for tool in "${missing_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            failed_tools+=("$tool")
        fi
    done
    
    if [[ ${#failed_tools[@]} -eq 0 ]]; then
        milou_log "SUCCESS" "All required tools installed successfully"
        return 0
    else
        milou_log "ERROR" "Failed to install tools: ${failed_tools[*]}"
        return 1
    fi
}

# Configure basic firewall (optional)
milou_prereq_configure_basic_firewall() {
    local enable_firewall="${1:-false}"
    
    if [[ "$enable_firewall" != "true" ]]; then
        milou_log "DEBUG" "Firewall configuration skipped"
        return 0
    fi
    
    milou_log "STEP" "Configuring basic firewall rules..."
    
    # Check if UFW is available (Ubuntu/Debian)
    if command -v ufw >/dev/null 2>&1; then
        milou_log "INFO" "Configuring UFW firewall..."
        
        # Enable UFW if not already enabled
        if ! ufw status | grep -q "Status: active"; then
            sudo ufw --force enable
        fi
        
        # Allow SSH (be careful not to lock ourselves out)
        sudo ufw allow ssh
        
        # Allow HTTP and HTTPS
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        
        # Allow Milou API port
        sudo ufw allow 9999/tcp
        
        milou_log "SUCCESS" "UFW firewall configured"
        
    # Check if firewalld is available (RHEL/CentOS/Fedora)
    elif command -v firewall-cmd >/dev/null 2>&1; then
        milou_log "INFO" "Configuring firewalld..."
        
        # Start and enable firewalld
        sudo systemctl start firewalld
        sudo systemctl enable firewalld
        
        # Allow HTTP and HTTPS
        sudo firewall-cmd --permanent --add-service=http
        sudo firewall-cmd --permanent --add-service=https
        
        # Allow Milou API port
        sudo firewall-cmd --permanent --add-port=9999/tcp
        
        # Reload firewall
        sudo firewall-cmd --reload
        
        milou_log "SUCCESS" "Firewalld configured"
    else
        milou_log "WARN" "No supported firewall found (UFW or firewalld)"
        milou_log "INFO" "💡 Consider manually configuring your firewall to allow ports 80, 443, and 9999"
    fi
}

# =============================================================================
# Comprehensive Prerequisites Functions
# =============================================================================

# Quick prerequisites check
milou_prereq_check_quick() {
    local missing_deps=()
    local warnings=()
    
    # Check Docker
    if ! milou_prereq_check_docker_installed; then
        missing_deps+=("Docker")
    elif ! milou_prereq_check_docker_running; then
        warnings+=("Docker daemon not accessible")
    fi
    
    # Check Docker Compose
    if ! milou_prereq_check_docker_compose; then
        missing_deps+=("Docker Compose")
    fi
    
    # Check required tools
    local -a required_tools=("curl" "wget" "jq" "openssl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_deps+=("$tool")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        return 1  # Missing dependencies
    elif [[ ${#warnings[@]} -gt 0 ]]; then
        return 2  # Warnings only
    else
        return 0  # All good
    fi
}

# Comprehensive prerequisites installation
milou_prereq_install_all() {
    local auto_install="${1:-true}"
    local enable_firewall="${2:-false}"
    local skip_confirmation="${3:-false}"
    
    milou_log "STEP" "🔧 Installing Milou prerequisites..."
    
    # Detect system information
    local os_type pkg_manager arch
    os_type=$(milou_prereq_detect_os)
    pkg_manager=$(milou_prereq_detect_package_manager)
    arch=$(milou_prereq_get_architecture)
    
    milou_log "INFO" "System Information:"
    milou_log "INFO" "  OS: $os_type"
    milou_log "INFO" "  Package Manager: $pkg_manager"
    milou_log "INFO" "  Architecture: $arch"
    echo
    
    # Check if we can proceed
    if [[ "$pkg_manager" == "unknown" ]]; then
        milou_log "ERROR" "Unsupported package manager"
        return 1
    fi
    
    # Install required tools
    if ! milou_prereq_install_required_tools "$pkg_manager"; then
        milou_log "ERROR" "Failed to install required tools"
        return 1
    fi
    
    # Install Docker
    if ! milou_prereq_install_docker "$auto_install" "$pkg_manager"; then
        milou_log "ERROR" "Failed to install Docker"
        return 1
    fi
    
    # Configure firewall if requested
    if [[ "$enable_firewall" == "true" ]]; then
        milou_prereq_configure_basic_firewall "true"
    fi
    
    milou_log "SUCCESS" "✅ Prerequisites installation completed"
    
    # Final verification
    if milou_prereq_check_quick; then
        milou_log "SUCCESS" "✅ All prerequisites are ready"
        return 0
    else
        milou_log "WARN" "⚠️  Some prerequisites may need manual configuration"
        return 2
    fi
}

# =============================================================================
# Module Exports
# =============================================================================

# System detection functions
export -f milou_prereq_detect_os
export -f milou_prereq_detect_package_manager
export -f milou_prereq_is_root
export -f milou_prereq_has_sudo
export -f milou_prereq_get_architecture

# Docker functions
export -f milou_prereq_check_docker_installed
export -f milou_prereq_check_docker_running
export -f milou_prereq_check_docker_compose
export -f milou_prereq_install_docker
export -f milou_prereq_show_docker_manual_instructions
export -f milou_prereq_configure_docker_user

# Tools installation functions
export -f milou_prereq_install_required_tools
export -f milou_prereq_configure_basic_firewall

# Comprehensive functions
export -f milou_prereq_check_quick
export -f milou_prereq_install_all 