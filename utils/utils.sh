#!/bin/bash

# Common utility functions for Milou CLI

# Confirmation prompt
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    
    while true; do
        if [[ "$default" == "y" ]]; then
            echo -ne "${CYAN_PROMPT:-\033[0;36m}${prompt} [Y/n]: ${NC:-\033[0m}"
        else
            echo -ne "${CYAN_PROMPT:-\033[0;36m}${prompt} [y/N]: ${NC:-\033[0m}"
        fi
        
        read -r response
        
        # Use default if no response
        if [[ -z "$response" ]]; then
            response="$default"
        fi
        
        case "$response" in
            [Yy]|[Yy][Ee][Ss])
                return 0
                ;;
            [Nn]|[Nn][Oo])
                return 1
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

# Progress indicator
show_progress() {
    local message="$1"
    local delay="${2:-0.1}"
    
    echo -ne "${BLUE:-\033[0;34m}[INFO]${NC:-\033[0m} $message"
    
    for i in {1..3}; do
        echo -n "."
        sleep "$delay"
    done
    echo
}

# Spinner for long operations
show_spinner() {
    local pid=$1
    local message="$2"
    local delay=0.1
    local spinstr='|/-\'
    
    echo -ne "${BLUE:-\033[0;34m}[INFO]${NC:-\033[0m} $message "
    
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
    echo " Done"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get system information
get_system_info() {
    echo "System Information:"
    echo "  OS: $(uname -s)"
    echo "  Architecture: $(uname -m)"
    echo "  Kernel: $(uname -r)"
    
    if command_exists docker; then
        echo "  Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"
    else
        echo "  Docker: Not installed"
    fi
    
    if command_exists docker && docker compose version >/dev/null 2>&1; then
        echo "  Docker Compose: $(docker compose version --short)"
    else
        echo "  Docker Compose: Not available"
    fi
}

# Format file size
format_size() {
    local bytes=$1
    local sizes=("B" "KB" "MB" "GB" "TB")
    local i=0
    
    while [[ $bytes -ge 1024 && $i -lt 4 ]]; do
        bytes=$((bytes / 1024))
        ((i++))
    done
    
    echo "${bytes}${sizes[$i]}"
}

# Check disk space
check_disk_space() {
    local path="${1:-.}"
    local required_mb="${2:-1000}"
    
    local available_kb=$(df "$path" | awk 'NR==2 {print $4}')
    local available_mb=$((available_kb / 1024))
    
    if [[ $available_mb -lt $required_mb ]]; then
        echo -e "${YELLOW:-\033[1;33m}[WARNING]${NC:-\033[0m} Low disk space: ${available_mb}MB available, ${required_mb}MB recommended"
        return 1
    fi
    
    echo -e "${GREEN:-\033[0;32m}[INFO]${NC:-\033[0m} Disk space OK: ${available_mb}MB available"
    return 0
}

# Cleanup function for temporary files
cleanup_temp() {
    local temp_files=()
    
    # Add any temporary files that need cleanup
    if [[ -f "/tmp/milou_setup.tmp" ]]; then
        temp_files+=("/tmp/milou_setup.tmp")
    fi
    
    if [[ ${#temp_files[@]} -gt 0 ]]; then
        echo -e "${BLUE:-\033[0;34m}[INFO]${NC:-\033[0m} Cleaning up temporary files"
        for file in "${temp_files[@]}"; do
            rm -f "$file"
        done
    fi
}

# Trap cleanup on exit
trap cleanup_temp EXIT

# Create a backup with timestamp
create_timestamped_backup() {
    local source="$1"
    local backup_dir="${2:-${CONFIG_DIR}/backups}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local basename=$(basename "$source")
    local backup_path="${backup_dir}/${basename}_${timestamp}.backup"
    
    mkdir -p "$backup_dir"
    
    if cp "$source" "$backup_path" 2>/dev/null; then
        echo "Backup created: $backup_path"
        return 0
    else
        echo "Failed to create backup of $source"
        return 1
    fi
}

# Wait for service to be ready
wait_for_service() {
    local service_name="$1"
    local timeout="${2:-60}"
    local interval="${3:-2}"
    local elapsed=0
    
    echo -e "${BLUE:-\033[0;34m}[INFO]${NC:-\033[0m} Waiting for $service_name to be ready..."
    
    while [[ $elapsed -lt $timeout ]]; do
        # Check if service is running (this would need to be customized per service)
        if docker compose ps "$service_name" 2>/dev/null | grep -q "Up"; then
            echo -e "${GREEN:-\033[0;32m}[SUCCESS]${NC:-\033[0m} $service_name is ready"
            return 0
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
        echo -ne "\rWaiting... ${elapsed}/${timeout}s"
    done
    
    echo -e "\n${YELLOW:-\033[1;33m}[WARNING]${NC:-\033[0m} Timeout waiting for $service_name"
    return 1
}

# Network connectivity check
check_connectivity() {
    local host="${1:-8.8.8.8}"
    local port="${2:-53}"
    
    if command_exists nc; then
        if nc -z "$host" "$port" 2>/dev/null; then
            return 0
        fi
    elif command_exists ping; then
        if ping -c 1 "$host" >/dev/null 2>&1; then
            return 0
        fi
    fi
    
    return 1
}

# Validate environment file
validate_env_file() {
    local env_file="$1"
    
    if [[ ! -f "$env_file" ]]; then
        echo -e "${RED:-\033[0;31m}[ERROR]${NC:-\033[0m} Environment file not found: $env_file"
        return 1
    fi
    
    # Check for required variables
    local required_vars=(
        "SERVER_NAME"
        "DB_USER"
        "DB_PASSWORD"
        "REDIS_PASSWORD"
        "SESSION_SECRET"
        "ENCRYPTION_KEY"
    )
    
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" "$env_file"; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        echo -e "${RED:-\033[0;31m}[ERROR]${NC:-\033[0m} Missing required environment variables:"
        printf '  %s\n' "${missing_vars[@]}"
        return 1
    fi
    
    echo -e "${GREEN:-\033[0;32m}[SUCCESS]${NC:-\033[0m} Environment file validation passed"
    return 0
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