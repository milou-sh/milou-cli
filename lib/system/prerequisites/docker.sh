#!/bin/bash

# =============================================================================
# Docker Installation Module for Prerequisites
# Handles Docker installation across different distributions
# =============================================================================

# =============================================================================
# Docker Installation
# =============================================================================

install_docker() {
    local distro_id="$1"
    local pkg_manager="$2"
    
    milou_log "STEP" "Installing Docker..."
    
    # Check if Docker is already installed
    if command -v docker >/dev/null 2>&1; then
        milou_log "INFO" "Docker is already installed"
        local docker_version
        docker_version=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        milou_log "INFO" "Current Docker version: $docker_version"
        
        # Check if version meets requirements
        if version_compare "$docker_version" "${MIN_DOCKER_VERSION:-20.10.0}" "ge"; then
            milou_log "SUCCESS" "Docker version meets requirements"
            return 0
        else
            milou_log "WARN" "Docker version is too old, attempting upgrade..."
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
            milou_log "WARN" "Unsupported distribution for automatic Docker installation"
            install_docker_generic
            ;;
    esac
}

install_docker_debian_ubuntu() {
    local pkg_manager="$1"
    
    milou_log "INFO" "Installing Docker on Debian/Ubuntu..."
    
    # Install prerequisites
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release || {
        milou_log "ERROR" "Failed to install prerequisites"
        return 1
    }
    
    # Add Docker's official GPG key
    sudo mkdir -p /etc/apt/keyrings
    if ! curl -fsSL https://download.docker.com/linux/$(lsb_release -is | tr '[:upper:]' '[:lower:]')/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
        milou_log "ERROR" "Failed to add Docker GPG key"
        return 1
    fi
    
    # Add Docker repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(lsb_release -is | tr '[:upper:]' '[:lower:]') \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update package lists
    sudo apt-get update || {
        milou_log "ERROR" "Failed to update package lists after adding Docker repository"
        return 1
    }
    
    # Install Docker
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || {
        milou_log "ERROR" "Failed to install Docker packages"
        return 1
    }
    
    milou_log "SUCCESS" "Docker installed successfully"
    return 0
}

install_docker_rhel_centos() {
    local pkg_manager="$1"
    
    milou_log "INFO" "Installing Docker on RHEL/CentOS..."
    
    # Install prerequisites
    sudo $pkg_manager install -y yum-utils || {
        milou_log "ERROR" "Failed to install prerequisites"
        return 1
    }
    
    # Add Docker repository
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || {
        milou_log "ERROR" "Failed to add Docker repository"
        return 1
    }
    
    # Install Docker
    sudo $pkg_manager install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || {
        milou_log "ERROR" "Failed to install Docker packages"
        return 1
    }
    
    milou_log "SUCCESS" "Docker installed successfully"
    return 0
}

install_docker_fedora() {
    local pkg_manager="$1"
    
    milou_log "INFO" "Installing Docker on Fedora..."
    
    # Add Docker repository
    sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo || {
        milou_log "ERROR" "Failed to add Docker repository"
        return 1
    }
    
    # Install Docker
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || {
        milou_log "ERROR" "Failed to install Docker packages"
        return 1
    }
    
    milou_log "SUCCESS" "Docker installed successfully"
    return 0
}

install_docker_arch() {
    local pkg_manager="$1"
    
    milou_log "INFO" "Installing Docker on Arch Linux..."
    
    # Install Docker
    sudo pacman -S --noconfirm docker docker-compose || {
        milou_log "ERROR" "Failed to install Docker packages"
        return 1
    }
    
    milou_log "SUCCESS" "Docker installed successfully"
    return 0
}

install_docker_opensuse() {
    local pkg_manager="$1"
    
    milou_log "INFO" "Installing Docker on openSUSE..."
    
    # Install Docker
    sudo zypper install -y docker docker-compose || {
        milou_log "ERROR" "Failed to install Docker packages"
        return 1
    }
    
    milou_log "SUCCESS" "Docker installed successfully"
    return 0
}

install_docker_generic() {
    milou_log "INFO" "Attempting generic Docker installation..."
    
    # Use Docker's convenience script
    if curl -fsSL https://get.docker.com | sh; then
        milou_log "SUCCESS" "Docker installed using convenience script"
        return 0
    else
        milou_log "ERROR" "Failed to install Docker using convenience script"
        return 1
    fi
}

# =============================================================================
# Docker Service Configuration
# =============================================================================

configure_docker_service() {
    milou_log "STEP" "Configuring Docker service..."
    
    # Start Docker service
    if ! sudo systemctl start docker; then
        milou_log "ERROR" "Failed to start Docker service"
        return 1
    fi
    
    # Enable Docker service on boot
    if ! sudo systemctl enable docker; then
        milou_log "ERROR" "Failed to enable Docker service"
        return 1
    fi
    
    # Add current user to docker group if not root
    if [[ $EUID -ne 0 ]]; then
        local current_user=$(whoami)
        if ! groups "$current_user" | grep -q docker; then
            milou_log "INFO" "Adding user $current_user to docker group..."
            if sudo usermod -aG docker "$current_user"; then
                milou_log "SUCCESS" "User added to docker group"
                milou_log "INFO" "⚠️  You may need to log out and back in for group changes to take effect"
                milou_log "INFO" "💡 Or run: newgrp docker"
            else
                milou_log "ERROR" "Failed to add user to docker group"
                return 1
            fi
        else
            milou_log "SUCCESS" "User is already in docker group"
        fi
    fi
    
    milou_log "SUCCESS" "Docker service configured successfully"
    return 0
}

# =============================================================================
# Docker Compose Verification
# =============================================================================

verify_docker_compose() {
    milou_log "STEP" "Verifying Docker Compose..."
    
    # Check for Docker Compose plugin (modern approach)
    if docker compose version >/dev/null 2>&1; then
        local compose_version
        compose_version=$(docker compose version --short 2>/dev/null | head -1)
        milou_log "SUCCESS" "Docker Compose plugin found: $compose_version"
        
        # Check version compatibility
        if version_compare "$compose_version" "${MIN_DOCKER_COMPOSE_VERSION:-2.0.0}" "ge"; then
            milou_log "SUCCESS" "Docker Compose version meets requirements"
            return 0
        else
            milou_log "WARN" "Docker Compose version might be too old (recommended: ${MIN_DOCKER_COMPOSE_VERSION:-2.0.0}+)"
            return 0  # Don't fail, just warn
        fi
    else
        milou_log "ERROR" "Docker Compose plugin not found"
        milou_log "INFO" "💡 Docker Compose should be installed automatically with modern Docker installations"
        milou_log "INFO" "💡 Try upgrading Docker or installing Docker Compose manually"
        return 1
    fi
}

# =============================================================================
# Export Functions
# =============================================================================

export -f install_docker
export -f install_docker_debian_ubuntu
export -f install_docker_rhel_centos
export -f install_docker_fedora
export -f install_docker_arch
export -f install_docker_opensuse
export -f install_docker_generic
export -f configure_docker_service
export -f verify_docker_compose 