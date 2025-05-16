#!/bin/bash

# Miscellaneous utility functions

# Prompt user for confirmation
confirm() {
    local message="$1"
    local default="${2:-y}"
    
    local prompt
    if [ "$default" = "y" ]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi
    
    local answer
    read -p "${message} ${prompt} " answer
    
    if [ -z "$answer" ]; then
        answer="$default"
    fi
    
    case "$answer" in
        [Yy]*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Check system requirements
check_system_requirements() {
    echo "Checking system requirements..."
    
    # Check Docker
    if ! command_exists docker; then
        echo "Error: Docker is not installed. Please install Docker before proceeding."
        return 1
    fi
    
    # Check Docker Compose plugin
    if ! docker compose version &> /dev/null; then
        echo "Error: Docker Compose plugin is not installed. Please install the Docker Compose plugin."
        return 1
    fi
    
    # Check OpenSSL (for certificate generation)
    if ! command_exists openssl; then
        echo "Warning: OpenSSL is not installed. Self-signed certificate generation will not be available."
    fi
    
    # Check system resources
    echo "Checking system resources..."
    
    # Get available RAM
    local ram=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$ram" -lt 4000 ]; then
        echo "Warning: Less than 4GB of RAM available (${ram}MB). The application may run slowly."
    fi
    
    # Get available disk space
    local disk=$(df -m . | awk 'NR==2 {print $4}')
    if [ "$disk" -lt 10000 ]; then
        echo "Warning: Less than 10GB of disk space available (${disk}MB). You may run out of space."
    fi
    
    echo "System requirements check completed."
    return 0
}

# Print a divider line
print_divider() {
    echo "-----------------------------------------------------"
}

# Print a header
print_header() {
    local text="$1"
    print_divider
    echo "  $text"
    print_divider
}

# Print system information
print_system_info() {
    print_header "System Information"
    echo "Operating System: $(uname -s) $(uname -r)"
    echo "Hostname: $(hostname)"
    echo "IP Address: $(hostname -I | cut -d' ' -f1)"
    echo "Docker Version: $(docker --version)"
    echo "Docker Compose Version: $(docker compose version | head -n 1)"
    echo "Disk Space: $(df -h . | awk 'NR==2 {print $4}') available"
    echo "Memory: $(free -h | awk '/^Mem:/{print $2}') total, $(free -h | awk '/^Mem:/{print $4}') available"
    print_divider
}

# Create a log entry
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    
    # Ensure log directory exists
    mkdir -p "${CONFIG_DIR}/logs"
    
    # Write to log file
    echo "[${timestamp}] [${level}] ${message}" >> "${CONFIG_DIR}/logs/milou.log"
    
    # If level is ERROR, also print to stderr
    if [ "$level" = "ERROR" ]; then
        echo "[${timestamp}] [${level}] ${message}" >&2
    fi
}

# Clean up temporary files
cleanup() {
    # Remove temporary files
    rm -rf /tmp/milou_*
    
    # Log cleanup
    log "INFO" "Cleaned up temporary files"
}

# Print a colored message
# Usage: print_colored "message" "color"
# Colors: red, green, yellow, blue
print_colored() {
    local message="$1"
    local color="$2"
    
    case "$color" in
        red)
            echo -e "\033[0;31m${message}\033[0m"
            ;;
        green)
            echo -e "\033[0;32m${message}\033[0m"
            ;;
        yellow)
            echo -e "\033[0;33m${message}\033[0m"
            ;;
        blue)
            echo -e "\033[0;34m${message}\033[0m"
            ;;
        *)
            echo "$message"
            ;;
    esac
}

# Register a trap to clean up on exit
trap cleanup EXIT 