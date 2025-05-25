#!/bin/bash

# =============================================================================
# System Detection Module for Prerequisites
# Detects distribution and package manager for automatic installation
# =============================================================================

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
    log "DEBUG" "Package manager: $pkg_manager"
    
    case "$pkg_manager" in
        "apt")
            log "DEBUG" "Running: apt-get update"
            if ! apt-get update; then
                log "ERROR" "Failed to update package lists"
                return 1
            fi
            ;;
        "yum")
            log "DEBUG" "Running: yum check-update"
            if ! yum check-update; then
                log "DEBUG" "YUM check-update returned non-zero (normal behavior)"
            fi
            ;;
        "dnf")
            log "DEBUG" "Running: dnf check-update"
            if ! dnf check-update; then
                log "DEBUG" "DNF check-update returned non-zero (normal behavior)"
            fi
            ;;
        "pacman")
            log "DEBUG" "Running: pacman -Sy"
            if ! pacman -Sy; then
                log "ERROR" "Failed to sync package databases"
                return 1
            fi
            ;;
        "zypper")
            log "DEBUG" "Running: zypper refresh"
            if ! zypper refresh; then
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
# Export Functions
# =============================================================================

export -f detect_distribution
export -f detect_package_manager
export -f update_system_packages 