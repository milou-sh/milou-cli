#!/bin/bash

# =============================================================================
# Prerequisites Installer for Milou CLI - Main Orchestrator
# Coordinates all prerequisite installation sub-modules
# =============================================================================

# This module depends on logging and utilities being already loaded
# by the module loader system - no need to source anything manually

# Validation that required functions are available
if ! command -v log >/dev/null 2>&1; then
    echo "ERROR: Logging functions not available - ensure core modules are loaded" >&2
    return 1
fi

# Load prerequisite sub-modules on-demand to ensure dependencies are available
load_prerequisites_modules() {
    if [[ "${PREREQUISITES_MODULES_LOADED:-false}" != "true" ]]; then
        # Use MILOU_LIB_DIR from module loader or fallback to relative path
        local prereq_dir="${MILOU_LIB_DIR:-${SCRIPT_DIR}/lib}/system/prerequisites"
        
        source "${prereq_dir}/detection.sh" 2>/dev/null || {
            log "ERROR" "Failed to load detection module from ${prereq_dir}/detection.sh"
            return 1
        }
        source "${prereq_dir}/docker.sh" 2>/dev/null || {
            log "ERROR" "Failed to load docker module from ${prereq_dir}/docker.sh"
            return 1
        }
        source "${prereq_dir}/tools.sh" 2>/dev/null || {
            log "ERROR" "Failed to load tools module from ${prereq_dir}/tools.sh"
            return 1
        }
        PREREQUISITES_MODULES_LOADED="true"
        log "DEBUG" "Prerequisites sub-modules loaded successfully"
    fi
}

# =============================================================================
# Main Prerequisites Installation Function - Uses Sub-modules
# =============================================================================


# =============================================================================
# Main Prerequisites Installation Function
# =============================================================================

install_prerequisites() {
    local auto_install="${1:-true}"
    local enable_firewall="${2:-false}"
    local skip_confirmation="${3:-false}"
    
    # Load prerequisite sub-modules now that dependencies are available
    if ! load_prerequisites_modules; then
        log "ERROR" "Failed to load prerequisites modules"
        return 1
    fi
    
    log "STEP" "🔧 Milou Prerequisites Installer"
    echo
    
    # Detect system information
    log "DEBUG" "Detecting system distribution..."
    local distro_id
    distro_id=$(detect_distribution)
    log "DEBUG" "Distribution detected: $distro_id"
    
    log "DEBUG" "Detecting package manager..."
    local pkg_manager
    pkg_manager=$(detect_package_manager)
    log "DEBUG" "Package manager detected: $pkg_manager"
    
    log "INFO" "System Information:"
    log "INFO" "  📋 Distribution: $distro_id"
    log "INFO" "  📦 Package Manager: $pkg_manager"
    log "INFO" "  👤 User: $(whoami)"
    echo
    
    log "DEBUG" "Checking root privileges..."
    log "DEBUG" "EUID: $EUID, auto_install: $auto_install"
    
    # Check if we're running as root for installation
    if [[ $EUID -ne 0 ]] && [[ "$auto_install" == "true" ]]; then
        log "WARN" "Root privileges required for automatic installation"
        log "INFO" "💡 Rerun with sudo for automatic installation"
        
        if [[ "${INTERACTIVE:-true}" == "true" && "$skip_confirmation" != "true" ]]; then
            log "DEBUG" "Prompting user for manual installation"
            if ! confirm "Continue with manual installation instructions?" "Y"; then
                log "INFO" "Prerequisites installation cancelled"
                return 1
            fi
            auto_install="false"
        else
            log "DEBUG" "Non-interactive mode, returning error"
            return 1
        fi
    fi
    
    log "DEBUG" "Root privileges check passed, continuing..."
    
    log "DEBUG" "Initializing step counters..."
    local total_steps=0
    local completed_steps=0
    local failed_steps=0
    
    log "DEBUG" "Counting steps to perform..."
    log "DEBUG" "Initial total_steps value: $total_steps"
    # Count steps to perform
    total_steps=$((total_steps + 1))  # System update
    log "DEBUG" "Step 1 counted: System update (total: $total_steps)"
    total_steps=$((total_steps + 1))  # Required tools
    log "DEBUG" "Step 2 counted: Required tools (total: $total_steps)"
    if ! command -v docker >/dev/null 2>&1; then
        total_steps=$((total_steps + 1))  # Docker installation
        log "DEBUG" "Step 3 counted: Docker installation (total: $total_steps)"
    fi
    total_steps=$((total_steps + 1))  # Docker service configuration
    log "DEBUG" "Step counted: Docker service configuration (total: $total_steps)"
    total_steps=$((total_steps + 1))  # Docker Compose verification
    log "DEBUG" "Step counted: Docker Compose verification (total: $total_steps)"
    if [[ "$enable_firewall" == "true" ]]; then
        total_steps=$((total_steps + 1))  # Firewall configuration
        log "DEBUG" "Step counted: Firewall configuration (total: $total_steps)"
    fi
    log "DEBUG" "Step counting completed, total steps: $total_steps"
    
    log "INFO" "🎯 Installing prerequisites ($total_steps steps)..."
    echo
    
    # Step 1: Update system packages
    if [[ "$auto_install" == "true" ]]; then
        if update_system_packages "$pkg_manager"; then
            completed_steps=$((completed_steps + 1))
        else
            failed_steps=$((failed_steps + 1))
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
            completed_steps=$((completed_steps + 1))
        else
            failed_steps=$((failed_steps + 1))
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
                completed_steps=$((completed_steps + 1))
            else
                failed_steps=$((failed_steps + 1))
            fi
        else
            log "INFO" "📋 Step 3: Install Docker"
            log "INFO" "  Visit: https://docs.docker.com/get-docker/"
            log "INFO" "  Quick install: curl -fsSL https://get.docker.com | sh"
            echo
        fi
    else
        log "SUCCESS" "✅ Docker is already installed"
        completed_steps=$((completed_steps + 1))
    fi
    
    # Step 4: Configure Docker service
    if [[ "$auto_install" == "true" ]]; then
        if configure_docker_service; then
            completed_steps=$((completed_steps + 1))
        else
            failed_steps=$((failed_steps + 1))
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
            completed_steps=$((completed_steps + 1))
        else
            failed_steps=$((failed_steps + 1))
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
                completed_steps=$((completed_steps + 1))
            else
                failed_steps=$((failed_steps + 1))
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
                echo
            fi
            return 0
        else
            log "ERROR" "Prerequisites installation completed with errors"
            log "INFO" "💡 Review the errors above and install missing components manually"
            return 1
        fi
    else
        log "INFO" "📋 Manual installation instructions provided above"
        log "INFO" "💡 Run with --auto-install-deps for automatic installation"
        return 0
    fi
}

# =============================================================================
# Export Functions - Sub-modules already export their own functions
# =============================================================================

# Create alias for compatibility with setup script
install_system_dependencies() {
    install_prerequisites "$@"
}

export -f install_prerequisites
export -f install_system_dependencies

