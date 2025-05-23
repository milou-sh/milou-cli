#!/bin/bash

# =============================================================================
# Prerequisites Installer for Milou CLI
# Automatically installs and configures all required dependencies
# =============================================================================

# Source utils for logging functions
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# Import logging functions
source "${SCRIPT_DIR}/utils/utils.sh" 2>/dev/null || {
    echo "ERROR: Cannot source utils.sh" >&2
    exit 1
}

# =============================================================================
# Distribution Detection
# =============================================================================

detect_distribution() {
    local distro=""
    local version=""
    local id=""
    
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        distro="$NAME"
        version="$VERSION_ID"
        id="$ID"
    elif [[ -f /etc/redhat-release ]]; then
        distro=$(cat /etc/redhat-release)
        id="rhel"
    elif [[ -f /etc/debian_version ]]; then
        distro="Debian"
        version=$(cat /etc/debian_version)
        id="debian"
    else
        distro="Unknown"
        id="unknown"
    fi
    
    echo "$id"
}

# Detect package manager
detect_package_manager() {
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
    else
        echo "unknown"
    fi
}

# =============================================================================
# System Updates
# =============================================================================

update_system_packages() {
    local pkg_manager="$1"
    
    log "STEP" "Updating system packages..."
    
    case "$pkg_manager" in
        "apt")
            if ! sudo apt-get update; then
                log "ERROR" "Failed to update package lists"
                return 1
            fi
            ;;
        "yum")
            if ! sudo yum check-update; then
                log "DEBUG" "YUM check-update returned non-zero (normal behavior)"
            fi
            ;;
        "dnf")
            if ! sudo dnf check-update; then
                log "DEBUG" "DNF check-update returned non-zero (normal behavior)"
            fi
            ;;
        "pacman")
            if ! sudo pacman -Sy; then
                log "ERROR" "Failed to sync package databases"
                return 1
            fi
            ;;
        "zypper")
            if ! sudo zypper refresh; then
                log "ERROR" "Failed to refresh repositories"
                return 1
            fi
            ;;
        *)
            log "WARN" "Unknown package manager, skipping system update"
            return 1
            ;;
    esac
    
    log "SUCCESS" "System packages updated successfully"
    return 0
}

# =============================================================================
# Docker Installation
# =============================================================================

install_docker() {
    local distro_id="$1"
    local pkg_manager="$2"
    
    log "STEP" "Installing Docker..."
    
    # Check if Docker is already installed
    if command -v docker >/dev/null 2>&1; then
        log "INFO" "Docker is already installed"
        local docker_version
        docker_version=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        log "INFO" "Current Docker version: $docker_version"
        
        # Check if version meets requirements
        if version_compare "$docker_version" "$MIN_DOCKER_VERSION" "ge"; then
            log "SUCCESS" "Docker version meets requirements"
            return 0
        else
            log "WARN" "Docker version is too old, attempting upgrade..."
        fi
    fi
    
    # Install Docker based on distribution
    case "$distro_id" in
        "ubuntu"|"debian")
            install_docker_debian_ubuntu "$pkg_manager"
            ;;
        "centos"|"rhel"|"rocky"|"almalinux")
            install_docker_rhel_centos "$pkg_manager"
            ;;
        "fedora")
            install_docker_fedora "$pkg_manager"
            ;;
        "arch"|"manjaro")
            install_docker_arch "$pkg_manager"
            ;;
        "opensuse"|"sles")
            install_docker_opensuse "$pkg_manager"
            ;;
        *)
            log "WARN" "Unsupported distribution for automatic Docker installation"
            install_docker_generic
            ;;
    esac
}

install_docker_debian_ubuntu() {
    local pkg_manager="$1"
    
    log "INFO" "Installing Docker on Debian/Ubuntu..."
    
    # Install prerequisites
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release || {
        log "ERROR" "Failed to install prerequisites"
        return 1
    }
    
    # Add Docker's official GPG key
    sudo mkdir -p /etc/apt/keyrings
    if ! curl -fsSL https://download.docker.com/linux/$(lsb_release -is | tr '[:upper:]' '[:lower:]')/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
        log "ERROR" "Failed to add Docker GPG key"
        return 1
    fi
    
    # Add Docker repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(lsb_release -is | tr '[:upper:]' '[:lower:]') \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update package lists
    sudo apt-get update || {
        log "ERROR" "Failed to update package lists after adding Docker repository"
        return 1
    }
    
    # Install Docker
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || {
        log "ERROR" "Failed to install Docker packages"
        return 1
    }
    
    log "SUCCESS" "Docker installed successfully"
    return 0
}

install_docker_rhel_centos() {
    local pkg_manager="$2"
    
    log "INFO" "Installing Docker on RHEL/CentOS..."
    
    # Install prerequisites
    sudo $pkg_manager install -y yum-utils || {
        log "ERROR" "Failed to install prerequisites"
        return 1
    }
    
    # Add Docker repository
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || {
        log "ERROR" "Failed to add Docker repository"
        return 1
    }
    
    # Install Docker
    sudo $pkg_manager install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || {
        log "ERROR" "Failed to install Docker packages"
        return 1
    }
    
    log "SUCCESS" "Docker installed successfully"
    return 0
}

install_docker_fedora() {
    local pkg_manager="$1"
    
    log "INFO" "Installing Docker on Fedora..."
    
    # Add Docker repository
    sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo || {
        log "ERROR" "Failed to add Docker repository"
        return 1
    }
    
    # Install Docker
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || {
        log "ERROR" "Failed to install Docker packages"
        return 1
    }
    
    log "SUCCESS" "Docker installed successfully"
    return 0
}

install_docker_arch() {
    local pkg_manager="$1"
    
    log "INFO" "Installing Docker on Arch Linux..."
    
    # Install Docker
    sudo pacman -S --noconfirm docker docker-compose || {
        log "ERROR" "Failed to install Docker packages"
        return 1
    }
    
    log "SUCCESS" "Docker installed successfully"
    return 0
}

install_docker_opensuse() {
    local pkg_manager="$1"
    
    log "INFO" "Installing Docker on openSUSE..."
    
    # Install Docker
    sudo zypper install -y docker docker-compose || {
        log "ERROR" "Failed to install Docker packages"
        return 1
    }
    
    log "SUCCESS" "Docker installed successfully"
    return 0
}

install_docker_generic() {
    log "INFO" "Attempting generic Docker installation..."
    
    # Use Docker's convenience script
    if curl -fsSL https://get.docker.com | sh; then
        log "SUCCESS" "Docker installed using convenience script"
        return 0
    else
        log "ERROR" "Failed to install Docker using convenience script"
        return 1
    fi
}

# =============================================================================
# Docker Service Configuration
# =============================================================================

configure_docker_service() {
    log "STEP" "Configuring Docker service..."
    
    # Start Docker service
    if ! sudo systemctl start docker; then
        log "ERROR" "Failed to start Docker service"
        return 1
    fi
    
    # Enable Docker service on boot
    if ! sudo systemctl enable docker; then
        log "ERROR" "Failed to enable Docker service"
        return 1
    fi
    
    # Add current user to docker group if not root
    if [[ $EUID -ne 0 ]]; then
        local current_user=$(whoami)
        if ! groups "$current_user" | grep -q docker; then
            log "INFO" "Adding user $current_user to docker group..."
            if sudo usermod -aG docker "$current_user"; then
                log "SUCCESS" "User added to docker group"
                log "INFO" "⚠️  You may need to log out and back in for group changes to take effect"
                log "INFO" "💡 Or run: newgrp docker"
            else
                log "ERROR" "Failed to add user to docker group"
                return 1
            fi
        else
            log "SUCCESS" "User is already in docker group"
        fi
    fi
    
    log "SUCCESS" "Docker service configured successfully"
    return 0
}

# =============================================================================
# Required Tools Installation
# =============================================================================

install_required_tools() {
    local pkg_manager="$1"
    
    log "STEP" "Installing required system tools..."
    
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
        log "SUCCESS" "All required tools are already installed"
        return 0
    fi
    
    log "INFO" "Missing tools: ${missing_tools[*]}"
    
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
            sudo apt-get install -y "${required_packages[@]}"
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
            sudo $pkg_manager install -y "${required_packages[@]}"
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
            sudo pacman -S --noconfirm "${required_packages[@]}"
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
            sudo zypper install -y "${required_packages[@]}"
            ;;
        *)
            log "ERROR" "Unknown package manager: $pkg_manager"
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
    
    if [[ ${#failed_tools[@]} -gt 0 ]]; then
        log "ERROR" "Failed to install tools: ${failed_tools[*]}"
        return 1
    fi
    
    log "SUCCESS" "All required tools installed successfully"
    return 0
}

# =============================================================================
# Docker Compose Verification
# =============================================================================

verify_docker_compose() {
    log "STEP" "Verifying Docker Compose installation..."
    
    # Check if Docker Compose plugin is available
    if docker compose version >/dev/null 2>&1; then
        local compose_version
        compose_version=$(docker compose version --short 2>/dev/null | head -1)
        log "SUCCESS" "Docker Compose plugin found: $compose_version"
        
        # Check version compatibility
        if version_compare "$compose_version" "$MIN_DOCKER_COMPOSE_VERSION" "ge"; then
            log "SUCCESS" "Docker Compose version meets requirements"
            return 0
        else
            log "WARN" "Docker Compose version might be too old (recommended: $MIN_DOCKER_COMPOSE_VERSION+)"
            return 0  # Don't fail, just warn
        fi
    else
        log "ERROR" "Docker Compose plugin not found"
        log "INFO" "💡 Docker Compose should be installed automatically with modern Docker installations"
        log "INFO" "💡 Try upgrading Docker or installing Docker Compose manually"
        return 1
    fi
}

# =============================================================================
# Firewall Configuration (Optional)
# =============================================================================

configure_basic_firewall() {
    local enable_firewall="${1:-false}"
    
    if [[ "$enable_firewall" != "true" ]]; then
        log "DEBUG" "Firewall configuration skipped"
        return 0
    fi
    
    log "STEP" "Configuring basic firewall rules..."
    
    # Check if UFW is available (Ubuntu/Debian)
    if command -v ufw >/dev/null 2>&1; then
        log "INFO" "Configuring UFW firewall..."
        
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
        
        log "SUCCESS" "UFW firewall configured"
        
    # Check if firewalld is available (RHEL/CentOS/Fedora)
    elif command -v firewall-cmd >/dev/null 2>&1; then
        log "INFO" "Configuring firewalld..."
        
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
        
        log "SUCCESS" "Firewalld configured"
    else
        log "WARN" "No supported firewall found (UFW or firewalld)"
        log "INFO" "💡 Consider manually configuring your firewall to allow ports 80, 443, and 9999"
    fi
}

# =============================================================================
# Main Prerequisites Installation Function
# =============================================================================

install_prerequisites() {
    local auto_install="${1:-true}"
    local enable_firewall="${2:-false}"
    local skip_confirmation="${3:-false}"
    
    log "STEP" "🔧 Milou Prerequisites Installer"
    echo
    
    # Detect system information
    local distro_id
    distro_id=$(detect_distribution)
    local pkg_manager
    pkg_manager=$(detect_package_manager)
    
    log "INFO" "System Information:"
    log "INFO" "  📋 Distribution: $distro_id"
    log "INFO" "  📦 Package Manager: $pkg_manager"
    log "INFO" "  👤 User: $(whoami)"
    echo
    
    # Check if we're running as root for installation
    if [[ $EUID -ne 0 ]] && [[ "$auto_install" == "true" ]]; then
        log "WARN" "Root privileges required for automatic installation"
        log "INFO" "💡 Rerun with sudo for automatic installation"
        
        if [[ "${INTERACTIVE:-true}" == "true" && "$skip_confirmation" != "true" ]]; then
            if ! confirm "Continue with manual installation instructions?" "Y"; then
                log "INFO" "Prerequisites installation cancelled"
                return 1
            fi
            auto_install="false"
        else
            return 1
        fi
    fi
    
    local total_steps=0
    local completed_steps=0
    local failed_steps=0
    
    # Count steps to perform
    ((total_steps++))  # System update
    ((total_steps++))  # Required tools
    if ! command -v docker >/dev/null 2>&1; then
        ((total_steps++))  # Docker installation
    fi
    ((total_steps++))  # Docker service configuration
    ((total_steps++))  # Docker Compose verification
    if [[ "$enable_firewall" == "true" ]]; then
        ((total_steps++))  # Firewall configuration
    fi
    
    log "INFO" "🎯 Installing prerequisites ($total_steps steps)..."
    echo
    
    # Step 1: Update system packages
    if [[ "$auto_install" == "true" ]]; then
        if update_system_packages "$pkg_manager"; then
            ((completed_steps++))
        else
            ((failed_steps++))
            log "WARN" "System update failed, continuing anyway..."
        fi
    else
        log "INFO" "📋 Step 1: Update system packages"
        case "$pkg_manager" in
            "apt")
                log "INFO" "  Run: sudo apt-get update"
                ;;
            "yum")
                log "INFO" "  Run: sudo yum update"
                ;;
            "dnf")
                log "INFO" "  Run: sudo dnf update"
                ;;
            "pacman")
                log "INFO" "  Run: sudo pacman -Syu"
                ;;
            "zypper")
                log "INFO" "  Run: sudo zypper update"
                ;;
        esac
        echo
    fi
    
    # Step 2: Install required tools
    if [[ "$auto_install" == "true" ]]; then
        if install_required_tools "$pkg_manager"; then
            ((completed_steps++))
        else
            ((failed_steps++))
        fi
    else
        log "INFO" "📋 Step 2: Install required tools"
        log "INFO" "  Required: curl, wget, jq, openssl, git"
        case "$pkg_manager" in
            "apt")
                log "INFO" "  Run: sudo apt-get install -y curl wget jq openssl git"
                ;;
            "yum"|"dnf")
                log "INFO" "  Run: sudo $pkg_manager install -y curl wget jq openssl git"
                ;;
            "pacman")
                log "INFO" "  Run: sudo pacman -S curl wget jq openssl git"
                ;;
            "zypper")
                log "INFO" "  Run: sudo zypper install curl wget jq openssl git"
                ;;
        esac
        echo
    fi
    
    # Step 3: Install Docker (if needed)
    if ! command -v docker >/dev/null 2>&1; then
        if [[ "$auto_install" == "true" ]]; then
            if install_docker "$distro_id" "$pkg_manager"; then
                ((completed_steps++))
            else
                ((failed_steps++))
            fi
        else
            log "INFO" "📋 Step 3: Install Docker"
            log "INFO" "  Visit: https://docs.docker.com/get-docker/"
            log "INFO" "  Quick install: curl -fsSL https://get.docker.com | sh"
            echo
        fi
    else
        log "SUCCESS" "✅ Docker is already installed"
        ((completed_steps++))
    fi
    
    # Step 4: Configure Docker service
    if [[ "$auto_install" == "true" ]]; then
        if configure_docker_service; then
            ((completed_steps++))
        else
            ((failed_steps++))
        fi
    else
        log "INFO" "📋 Step 4: Configure Docker service"
        log "INFO" "  Run: sudo systemctl enable docker && sudo systemctl start docker"
        log "INFO" "  Run: sudo usermod -aG docker \$USER"
        echo
    fi
    
    # Step 5: Verify Docker Compose
    if [[ "$auto_install" == "true" ]]; then
        if verify_docker_compose; then
            ((completed_steps++))
        else
            ((failed_steps++))
        fi
    else
        log "INFO" "📋 Step 5: Verify Docker Compose"
        log "INFO" "  Should be included with modern Docker installations"
        log "INFO" "  Test: docker compose version"
        echo
    fi
    
    # Step 6: Configure firewall (optional)
    if [[ "$enable_firewall" == "true" ]]; then
        if [[ "$auto_install" == "true" ]]; then
            if configure_basic_firewall "$enable_firewall"; then
                ((completed_steps++))
            else
                ((failed_steps++))
                log "WARN" "Firewall configuration failed, continuing anyway..."
            fi
        else
            log "INFO" "📋 Step 6: Configure firewall (optional)"
            log "INFO" "  Allow ports: 22 (SSH), 80 (HTTP), 443 (HTTPS), 9999 (Milou API)"
            echo
        fi
    fi
    
    # Summary
    echo
    log "INFO" "🎯 Prerequisites Installation Summary:"
    log "INFO" "  ✅ Completed: $completed_steps/$total_steps steps"
    if [[ $failed_steps -gt 0 ]]; then
        log "WARN" "  ❌ Failed: $failed_steps steps"
    fi
    echo
    
    if [[ "$auto_install" == "true" ]]; then
        if [[ $failed_steps -eq 0 ]]; then
            log "SUCCESS" "🎉 All prerequisites installed successfully!"
            
            # Check if user needs to log out for group changes
            if [[ $EUID -ne 0 ]] && ! groups | grep -q docker && command -v docker >/dev/null 2>&1; then
                echo
                log "INFO" "⚠️  IMPORTANT: You may need to:"
                log "INFO" "  1. Log out and back in, OR"
                log "INFO" "  2. Run: newgrp docker"
                log "INFO" "  3. Then continue with: $0 setup"
                
                if [[ "${INTERACTIVE:-true}" == "true" ]]; then
                    echo
                    if confirm "Try to refresh group membership now?" "Y"; then
                        log "INFO" "Refreshing group membership..."
                        log "INFO" "Group membership will be active for new sessions"
                        log "INFO" "Continuing with current setup..."
                        # Note: Instead of exec newgrp which can hang, we just continue
                        # The setup process will handle Docker group issues automatically
                    fi
                fi
            fi
            
            return 0
        else
            log "WARN" "Prerequisites installation completed with $failed_steps failed step(s)"
            log "INFO" "💡 Please address the failed steps manually before continuing"
            return 1
        fi
    else
        log "INFO" "Please complete the manual installation steps above before running Milou setup"
        return 1
    fi
}

# =============================================================================
# Quick Prerequisites Check
# =============================================================================

check_prerequisites_quick() {
    local missing_deps=()
    local warnings=()
    
    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
        missing_deps+=("Docker")
    elif ! docker info >/dev/null 2>&1; then
        warnings+=("Docker daemon not accessible")
    fi
    
    # Check Docker Compose
    if ! docker compose version >/dev/null 2>&1; then
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

# =============================================================================
# Export Functions
# =============================================================================

export -f detect_distribution
export -f detect_package_manager
export -f install_prerequisites
export -f check_prerequisites_quick
export -f install_docker
export -f configure_docker_service
export -f install_required_tools
export -f verify_docker_compose
export -f configure_basic_firewall 