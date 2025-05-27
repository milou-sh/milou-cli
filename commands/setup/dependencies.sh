#!/bin/bash

# =============================================================================
# Setup Module: Dependencies Installation
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

# Ensure prerequisites module is available
if ! command -v milou_prereq_install_docker >/dev/null 2>&1; then
    if [[ -n "${SCRIPT_DIR:-}" ]] && [[ -f "${SCRIPT_DIR}/lib/prerequisites.sh" ]]; then
        source "${SCRIPT_DIR}/lib/prerequisites.sh" 2>/dev/null || {
            milou_log "WARN" "Cannot load prerequisites module"
        }
    fi
fi

# =============================================================================
# Dependencies Installation Functions
# =============================================================================

# Install required dependencies
setup_install_dependencies() {
    local needs_deps="$1"
    local setup_mode="$2"
    
    if [[ "$needs_deps" != "true" ]]; then
        milou_log "INFO" "✅ All dependencies already satisfied"
        return 0
    fi
    
    milou_log "STEP" "Step 4: Dependencies Installation"
    echo
    
    # Check if we can install dependencies
    if [[ $EUID -ne 0 ]]; then
        milou_log "ERROR" "Dependencies installation requires root privileges"
        milou_log "INFO" "💡 Run with sudo or install dependencies manually:"
        _show_manual_installation_guide
        return 1
    fi
    
    # Install based on mode
    case "$setup_mode" in
        interactive)
            _install_dependencies_interactive
            ;;
        non-interactive)
            _install_dependencies_automated
            ;;
        smart)
            _install_dependencies_smart
            ;;
        *)
            milou_log "ERROR" "Unknown setup mode: $setup_mode"
            return 1
            ;;
    esac
    
    # Verify installation
    _verify_dependencies_installation
    
    echo
    return $?
}

# Interactive dependencies installation
_install_dependencies_interactive() {
    milou_log "INFO" "🔧 Interactive dependencies installation"
    
    # Confirm with user
    if ! _confirm_dependencies_installation; then
        milou_log "WARN" "Dependencies installation skipped by user"
        return 1
    fi
    
    # Install Docker
    if ! command -v docker >/dev/null 2>&1; then
        milou_log "INFO" "Installing Docker..."
        _install_docker || return 1
    fi
    
    # Install Docker Compose
    if ! docker compose version >/dev/null 2>&1; then
        milou_log "INFO" "Installing Docker Compose..."
        _install_docker_compose || return 1
    fi
    
    # Install system tools
    milou_log "INFO" "Installing system tools..."
    _install_system_tools || return 1
    
    return 0
}

# Automated dependencies installation
_install_dependencies_automated() {
    milou_log "INFO" "🤖 Automated dependencies installation"
    
    # Install everything without prompting
    local install_failed=false
    
    if ! command -v docker >/dev/null 2>&1; then
        milou_log "INFO" "Installing Docker..."
        if ! _install_docker; then
            install_failed=true
        fi
    fi
    
    if ! docker compose version >/dev/null 2>&1; then
        milou_log "INFO" "Installing Docker Compose..."
        if ! _install_docker_compose; then
            install_failed=true
        fi
    fi
    
    milou_log "INFO" "Installing system tools..."
    if ! _install_system_tools; then
        install_failed=true
    fi
    
    if [[ "$install_failed" == "true" ]]; then
        milou_log "ERROR" "Some dependencies failed to install"
        return 1
    fi
    
    return 0
}

# Smart dependencies installation
_install_dependencies_smart() {
    milou_log "INFO" "🧠 Smart dependencies installation"
    
    # Only prompt for critical missing dependencies
    local critical_missing=()
    
    if ! command -v docker >/dev/null 2>&1; then
        critical_missing+=("Docker")
    fi
    
    if ! docker compose version >/dev/null 2>&1; then
        critical_missing+=("Docker Compose")
    fi
    
    if [[ ${#critical_missing[@]} -gt 0 ]]; then
        milou_log "WARN" "Critical dependencies missing: ${critical_missing[*]}"
        if _confirm_critical_installation "${critical_missing[*]}"; then
            _install_dependencies_automated
        else
            return 1
        fi
    else
        # Just install system tools silently
        _install_system_tools
    fi
    
    return 0
}

# Install Docker
_install_docker() {
    # Use proper prerequisites module function if available
    if command -v milou_prereq_install_docker >/dev/null 2>&1; then
        milou_prereq_install_docker "true"
        return $?
    fi
    
    # Fallback to official Docker installation script
    milou_log "INFO" "Installing Docker using official installation script..."
    
    # Download and run the official Docker installation script
    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL https://get.docker.com -o get-docker.sh; then
            chmod +x get-docker.sh
            if sh get-docker.sh; then
                rm -f get-docker.sh
                
                # Add current user to docker group if not root
                if [[ $EUID -ne 0 && -n "${USER:-}" ]]; then
                    milou_log "INFO" "Adding user $USER to docker group..."
                    usermod -aG docker "$USER" || true
                    milou_log "WARN" "Please log out and back in for Docker group changes to take effect"
                fi
                
                # Start and enable Docker service
                if command -v systemctl >/dev/null 2>&1; then
                    systemctl start docker && systemctl enable docker
                fi
                
                milou_log "SUCCESS" "Docker installed successfully"
                return 0
            else
                rm -f get-docker.sh
                milou_log "ERROR" "Docker installation script failed"
                return 1
            fi
        else
            milou_log "ERROR" "Failed to download Docker installation script"
            return 1
        fi
    else
        milou_log "ERROR" "curl is required for Docker installation"
        return 1
    fi
}

# Install Docker Compose
_install_docker_compose() {
    # Check if Docker Compose plugin is already available
    if docker compose version >/dev/null 2>&1; then
        milou_log "SUCCESS" "Docker Compose plugin already available"
        return 0
    fi
    
    # Try to install Docker Compose plugin via package manager first
    milou_log "INFO" "Installing Docker Compose plugin..."
    
    local pkg_manager
    if command -v apt-get >/dev/null 2>&1; then
        pkg_manager="apt"
    elif command -v yum >/dev/null 2>&1; then
        pkg_manager="yum"
    elif command -v dnf >/dev/null 2>&1; then
        pkg_manager="dnf"
    fi
    
    # Try package manager installation
    if [[ -n "$pkg_manager" ]]; then
        case "$pkg_manager" in
            "apt")
                if apt-get update && apt-get install -y docker-compose-plugin; then
                    milou_log "SUCCESS" "Docker Compose plugin installed via apt"
                    return 0
                fi
                ;;
            "yum")
                if yum install -y docker-compose-plugin; then
                    milou_log "SUCCESS" "Docker Compose plugin installed via yum"
                    return 0
                fi
                ;;
            "dnf")
                if dnf install -y docker-compose-plugin; then
                    milou_log "SUCCESS" "Docker Compose plugin installed via dnf"
                    return 0
                fi
                ;;
        esac
    fi
    
    # If package manager installation failed, try standalone installation
    milou_log "INFO" "Package manager installation failed, installing standalone Docker Compose..."
    
    local compose_url="https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"
    
    if command -v curl >/dev/null 2>&1; then
        if curl -L "$compose_url" -o /usr/local/bin/docker-compose; then
            chmod +x /usr/local/bin/docker-compose
            milou_log "SUCCESS" "Standalone Docker Compose installed"
            return 0
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget "$compose_url" -O /usr/local/bin/docker-compose; then
            chmod +x /usr/local/bin/docker-compose
            milou_log "SUCCESS" "Standalone Docker Compose installed"
            return 0
        fi
    fi
    
    milou_log "ERROR" "Failed to install Docker Compose"
    return 1
}

# Install system tools
_install_system_tools() {
    local tools=("curl" "wget" "jq" "openssl")
    local missing_tools=()
    
    # Check which tools are missing
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -eq 0 ]]; then
        milou_log "SUCCESS" "All system tools already installed"
        return 0
    fi
    
    milou_log "INFO" "Installing missing tools: ${missing_tools[*]}"
    
    # Install using appropriate package manager
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y "${missing_tools[@]}"
    elif command -v yum >/dev/null 2>&1; then
        yum install -y "${missing_tools[@]}"
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y "${missing_tools[@]}"
    else
        milou_log "WARN" "Unsupported package manager, skipping system tools installation"
        return 1
    fi
    
    return $?
}

# Confirm dependencies installation
_confirm_dependencies_installation() {
    echo "The following dependencies will be installed:"
    echo "  • Docker (container runtime)"
    echo "  • Docker Compose (container orchestration)"
    echo "  • System tools (curl, wget, jq, openssl)"
    echo
    
    if command -v milou_confirm >/dev/null 2>&1; then
        milou_confirm "Proceed with dependencies installation?" "Y"
    else
        echo -n "Proceed with dependencies installation? [Y/n]: "
        read -r response
        [[ "${response,,}" != "n" && "${response,,}" != "no" ]]
    fi
}

# Confirm critical installation
_confirm_critical_installation() {
    local missing="$1"
    
    echo "Critical dependencies are missing: $missing"
    echo "Milou requires these components to function properly."
    echo
    
    if command -v milou_confirm >/dev/null 2>&1; then
        milou_confirm "Install critical dependencies now?" "Y"
    else
        echo -n "Install critical dependencies now? [Y/n]: "
        read -r response
        [[ "${response,,}" != "n" && "${response,,}" != "no" ]]
    fi
}

# Verify dependencies installation
_verify_dependencies_installation() {
    milou_log "INFO" "🔍 Verifying dependencies installation..."
    
    local verification_failed=false
    
    # Check Docker
    if command -v docker >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then
            milou_log "SUCCESS" "✅ Docker installed and accessible"
        else
            milou_log "WARN" "⚠️  Docker installed but daemon not accessible"
            milou_log "INFO" "💡 Try: sudo systemctl start docker"
        fi
    else
        milou_log "ERROR" "❌ Docker installation failed"
        verification_failed=true
    fi
    
    # Check Docker Compose
    if docker compose version >/dev/null 2>&1; then
        milou_log "SUCCESS" "✅ Docker Compose available"
    else
        milou_log "ERROR" "❌ Docker Compose not available"
        verification_failed=true
    fi
    
    # Check system tools
    local tools=("curl" "wget" "jq" "openssl")
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            milou_log "DEBUG" "✅ $tool available"
        else
            milou_log "WARN" "⚠️  $tool not available"
        fi
    done
    
    if [[ "$verification_failed" == "true" ]]; then
        milou_log "ERROR" "Dependencies verification failed"
        return 1
    else
        milou_log "SUCCESS" "✅ All dependencies verified"
        return 0
    fi
}

# Show manual installation guide
_show_manual_installation_guide() {
    echo
    echo "Manual Installation Guide:"
    echo "========================="
    echo
    echo "1. Install Docker:"
    echo "   curl -fsSL https://get.docker.com -o get-docker.sh"
    echo "   sudo sh get-docker.sh"
    echo
    echo "2. Install Docker Compose:"
    echo "   sudo apt-get install docker-compose-plugin  # Ubuntu/Debian"
    echo "   sudo yum install docker-compose-plugin      # RHEL/CentOS"
    echo
    echo "3. Install system tools:"
    echo "   sudo apt-get install curl wget jq openssl   # Ubuntu/Debian"
    echo "   sudo yum install curl wget jq openssl       # RHEL/CentOS"
    echo
    echo "4. Start Docker service:"
    echo "   sudo systemctl start docker"
    echo "   sudo systemctl enable docker"
    echo
}

# Export functions
export -f setup_install_dependencies
export -f _install_dependencies_interactive
export -f _install_dependencies_automated
export -f _install_dependencies_smart
export -f _install_docker
export -f _install_docker_compose
export -f _install_system_tools
export -f _verify_dependencies_installation 