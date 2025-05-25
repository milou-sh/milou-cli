#!/bin/bash

# =============================================================================
# System Tools Installation Module for Prerequisites
# Handles installation of required tools and basic security configuration
# =============================================================================

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
            log "ERROR" "Unsupported package manager for automatic tool installation"
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
        log "SUCCESS" "All required tools installed successfully"
        return 0
    else
        log "ERROR" "Failed to install tools: ${failed_tools[*]}"
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

export -f install_required_tools
export -f configure_basic_firewall
export -f check_prerequisites_quick 