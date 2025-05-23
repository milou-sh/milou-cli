#!/bin/bash

# =============================================================================
# Docker Utility Functions for Milou CLI - Main Module
# Enhanced with comprehensive image management and service control
# =============================================================================

# Source modular components
source "${BASH_SOURCE%/*}/docker-registry.sh" 2>/dev/null || true
source "${BASH_SOURCE%/*}/docker-services.sh" 2>/dev/null || true

# =============================================================================
# Constants and Configuration
# =============================================================================

GITHUB_REGISTRY="${GITHUB_REGISTRY:-ghcr.io/milou-sh/milou}"
GITHUB_API_BASE="${GITHUB_API_BASE:-https://api.github.com}"

# Constants (use defaults if not already set)
DEFAULT_IMAGE_TAG="${DEFAULT_IMAGE_TAG:-v1.0.0}"
DOCKER_COMPOSE_FILE="${DOCKER_COMPOSE_FILE:-docker-compose.yml}"
REGISTRY_TIMEOUT="${REGISTRY_TIMEOUT:-30}"

# =============================================================================
# Docker Environment Management
# =============================================================================

# Check if Docker daemon is accessible
check_docker_access() {
    if ! docker info >/dev/null 2>&1; then
        log "ERROR" "Cannot access Docker daemon"
        log "INFO" "Please ensure:"
        log "INFO" "  1. Docker is installed and running"
        log "INFO" "  2. Current user has Docker permissions"
        log "INFO" "  3. Try: sudo usermod -aG docker \$USER && newgrp docker"
        return 1
    fi
    return 0
}

# Create Docker networks if they don't exist
create_networks() {
    log "DEBUG" "Creating Docker networks..."
    
    local -a networks=("milou_network" "proxy")
    
    for network in "${networks[@]}"; do
        if ! docker network inspect "$network" >/dev/null 2>&1; then
            log "DEBUG" "Creating network: $network"
            if ! docker network create "$network" >/dev/null 2>&1; then
                log "WARN" "Failed to create network: $network"
            fi
        fi
    done
}

# Ensure all required Docker networks exist
ensure_docker_networks() {
    log "DEBUG" "Ensuring required Docker networks exist..."
    
    local -a required_networks=("proxy")
    
    for network in "${required_networks[@]}"; do
        if ! docker network inspect "$network" >/dev/null 2>&1; then
            log "INFO" "Creating required network: $network"
            if docker network create "$network" >/dev/null 2>&1; then
                log "DEBUG" "Network $network created successfully"
            else
                log "WARN" "Failed to create network: $network"
            fi
        else
            log "DEBUG" "Network $network already exists"
        fi
    done
}

# =============================================================================
# Docker Cleanup Functions
# =============================================================================

# Clean up Docker resources
cleanup_docker_resources() {
    log "STEP" "Cleaning up Docker resources..."
    
    # Remove unused images
    if docker image prune -f >/dev/null 2>&1; then
        log "INFO" "Removed unused Docker images"
    fi
    
    # Remove unused volumes (with confirmation)
    if [[ "$FORCE" == true ]] || confirm "Remove unused Docker volumes? (This may delete persistent data)"; then
        if docker volume prune -f >/dev/null 2>&1; then
            log "INFO" "Removed unused Docker volumes"
        fi
    fi
    
    # Remove unused networks
    if docker network prune -f >/dev/null 2>&1; then
        log "INFO" "Removed unused Docker networks"
    fi
    
    log "SUCCESS" "Docker cleanup completed"
}

# Complete cleanup of all Milou-related Docker resources
complete_cleanup_milou_resources() {
    log "STEP" "Performing complete cleanup of all Milou resources..."
    
    echo
    echo -e "${BOLD}${RED}⚠️  WARNING: DESTRUCTIVE OPERATION${NC}"
    echo "This will PERMANENTLY DELETE all Milou Docker resources including:"
    echo "  • All Milou containers (running and stopped)"
    echo "  • All Milou Docker images"
    echo "  • All Milou data volumes"
    echo "  • All Milou networks"
    echo "  • Configuration files"
    echo
    
    # In non-interactive mode with force flag, proceed automatically
    if [[ "${INTERACTIVE:-true}" == "false" && "$FORCE" == "true" ]]; then
        log "INFO" "Non-interactive mode with --force flag: proceeding with complete cleanup"
    elif [[ "${INTERACTIVE:-true}" == "false" ]]; then
        log "WARN" "Non-interactive mode detected but --force not specified"
        log "INFO" "To perform complete cleanup automatically, use: --force"
        log "INFO" "Cancelling cleanup to prevent accidental data loss"
        return 1
    elif ! confirm "Are you ABSOLUTELY SURE you want to delete ALL Milou data?" "N"; then
        log "INFO" "Complete cleanup cancelled"
        return 1
    fi
    
    if ! confirm "Last chance - this cannot be undone. Continue?" "N"; then
        log "INFO" "Complete cleanup cancelled"
        return 1
    fi
    
    # Stop and remove all Milou containers
    log "INFO" "🗑️ Removing all Milou containers..."
    local containers
    containers=$(docker ps -a --filter "name=static-" --format "{{.Names}}" 2>/dev/null || true)
    if [[ -n "$containers" ]]; then
        echo "$containers" | xargs docker stop 2>/dev/null || true
        echo "$containers" | xargs docker rm -f 2>/dev/null || true
        log "SUCCESS" "Removed containers: $(echo "$containers" | tr '\n' ' ')"
    else
        log "INFO" "No Milou containers found"
    fi
    
    # Remove all Milou-related images
    log "INFO" "🗑️ Removing all Milou Docker images..."
    local images
    images=$(docker images --filter "reference=ghcr.io/milou-sh/*" --format "{{.Repository}}:{{.Tag}}" 2>/dev/null || true)
    if [[ -n "$images" ]]; then
        echo "$images" | xargs docker rmi -f 2>/dev/null || true
        log "SUCCESS" "Removed images: $(echo "$images" | tr '\n' ' ')"
    else
        log "INFO" "No Milou images found"
    fi
    
    # Remove all Milou volumes
    log "INFO" "🗑️ Removing all Milou data volumes..."
    local volumes
    volumes=$(docker volume ls --filter "name=static_" --format "{{.Name}}" 2>/dev/null || true)
    if [[ -n "$volumes" ]]; then
        echo "$volumes" | xargs docker volume rm -f 2>/dev/null || true
        log "SUCCESS" "Removed volumes: $(echo "$volumes" | tr '\n' ' ')"
    else
        log "INFO" "No Milou volumes found"
    fi
    
    # Remove Milou networks (but keep standard Docker networks)
    log "INFO" "🗑️ Removing Milou networks..."
    local networks
    networks=$(docker network ls --filter "name=milou" --format "{{.Name}}" 2>/dev/null || true)
    if [[ -n "$networks" ]]; then
        echo "$networks" | xargs docker network rm 2>/dev/null || true
        log "SUCCESS" "Removed networks: $(echo "$networks" | tr '\n' ' ')"
    else
        log "INFO" "No Milou networks found"
    fi
    
    # Remove configuration files
    log "INFO" "🗑️ Removing configuration files..."
    if [[ -f "$ENV_FILE" ]]; then
        rm -f "$ENV_FILE"
        log "SUCCESS" "Removed configuration file: $ENV_FILE"
    fi
    
    # Remove SSL certificates if they exist
    if [[ -d "./ssl" ]]; then
        if [[ "$FORCE" == true ]] || confirm "Remove SSL certificates directory?" "N"; then
            rm -rf "./ssl"
            log "SUCCESS" "Removed SSL certificates directory"
        fi
    fi
    
    # Remove Docker Compose override files
    if [[ -f "./docker-compose.override.yml" ]]; then
        rm -f "./docker-compose.override.yml"
        log "SUCCESS" "Removed Docker Compose override file"
    fi
    
    # Clean up Docker system resources
    log "INFO" "🗑️ Cleaning up Docker system resources..."
    docker system prune -f >/dev/null 2>&1 || true
    
    log "SUCCESS" "🎉 Complete cleanup finished!"
    echo
    log "INFO" "💡 Next steps:"
    log "INFO" "  • Run '$0 setup' to create a fresh installation"
    log "INFO" "  • All data has been permanently removed"
    log "INFO" "  • You can now test the tool from scratch"
    
    return 0
}

# =============================================================================
# Installation State Management
# =============================================================================

# Check for existing Milou installation
check_existing_installation() {
    log "STEP" "Checking for existing Milou installation..."
    
    local has_existing=false
    local -a issues=()
    local -a running_containers=()
    local -a port_conflicts=()
    
    # Check for existing containers
    local existing_containers
    existing_containers=$(docker ps -a --filter "name=static-" --format "{{.Names}}\t{{.Status}}" 2>/dev/null || true)
    
    if [[ -n "$existing_containers" ]]; then
        has_existing=true
        log "INFO" "Found existing Milou containers:"
        echo "$existing_containers" | while IFS=$'\t' read -r name status; do
            echo "  🐳 $name - $status"
            if [[ "$status" =~ Up ]]; then
                running_containers+=("$name")
            fi
        done
        echo
    fi
    
    # Check for port conflicts
    local -a ports_to_check=("5432:PostgreSQL" "6379:Redis" "15672:RabbitMQ" "443:HTTPS" "80:HTTP")
    
    for port_info in "${ports_to_check[@]}"; do
        local port="${port_info%:*}"
        local service="${port_info#*:}"
        
        if ! check_port_availability "$port" "$service"; then
            has_existing=true
            port_conflicts+=("$port:$service")
            local process_info
            process_info=$(get_port_process "$port")
            issues+=("Port $port ($service) is in use by: $process_info")
        fi
    done
    
    # Check for existing .env file
    if [[ -f "$ENV_FILE" ]]; then
        has_existing=true
        local env_age
        env_age=$(stat -c %Y "$ENV_FILE" 2>/dev/null || stat -f %m "$ENV_FILE" 2>/dev/null || echo "0")
        local current_time=$(date +%s)
        local age_days=$(( (current_time - env_age) / 86400 ))
        
        log "INFO" "Found existing configuration file (${age_days} days old)"
    fi
    
    # Check for existing volumes
    local existing_volumes
    existing_volumes=$(docker volume ls --filter "name=static_" --format "{{.Name}}" 2>/dev/null || true)
    
    if [[ -n "$existing_volumes" ]]; then
        has_existing=true
        log "INFO" "Found existing data volumes:"
        echo "$existing_volumes" | sed 's/^/  💾 /'
        echo
    fi
    
    # Report findings
    if [[ "$has_existing" == true ]]; then
        log "WARN" "Existing Milou installation detected!"
        echo
        
        if [[ ${#issues[@]} -gt 0 ]]; then
            log "WARN" "Potential conflicts found:"
            printf '  ⚠️  %s\n' "${issues[@]}"
            echo
        fi
        
        return 1  # Existing installation found
    else
        log "SUCCESS" "No existing installation detected - proceeding with fresh install"
        return 0  # No existing installation
    fi
}

# =============================================================================
# Port and Process Management
# =============================================================================

# Check if ports are available
check_port_availability() {
    local port="$1"
    local service_name="$2"
    
    log "DEBUG" "Checking if port $port is available for $service_name..."
    
    if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
        return 1
    elif ss -tlnp 2>/dev/null | grep -q ":$port "; then
        return 1
    elif lsof -i ":$port" >/dev/null 2>&1; then
        return 1
    else
        return 0
    fi
}

# Get process using a port
get_port_process() {
    local port="$1"
    
    # Try different methods to find the process
    local process_info=""
    
    if command -v lsof >/dev/null 2>&1; then
        process_info=$(lsof -i ":$port" -t 2>/dev/null | head -1)
        if [[ -n "$process_info" ]]; then
            ps -p "$process_info" -o pid,ppid,comm 2>/dev/null || echo "PID: $process_info"
            return 0
        fi
    fi
    
    if command -v netstat >/dev/null 2>&1; then
        netstat -tlnp 2>/dev/null | grep ":$port " | awk '{print $7}' | head -1
        return 0
    fi
    
    if command -v ss >/dev/null 2>&1; then
        ss -tlnp 2>/dev/null | grep ":$port " | grep -o 'pid=[0-9]*' | head -1
        return 0
    fi
    
    echo "Unknown process"
}

# =============================================================================
# System Information and Diagnostics
# =============================================================================

# Show comprehensive system status
show_detailed_status() {
    log "STEP" "Comprehensive System Status Check"
    echo
    
    # Check installation state
    echo -e "${BOLD}📊 Installation Status${NC}"
    local installation_status=0
    if ! check_existing_installation >/dev/null 2>&1; then
        installation_status=1
    fi
    
    if [[ $installation_status -eq 0 ]]; then
        echo "  ✅ No existing installation detected"
    else
        echo "  ⚠️  Existing installation detected"
    fi
    echo
    
    # Docker status
    echo -e "${BOLD}🐳 Docker Status${NC}"
    if docker info >/dev/null 2>&1; then
        echo "  ✅ Docker daemon is running"
        local docker_version
        docker_version=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        echo "  📋 Docker version: $docker_version"
    else
        echo "  ❌ Docker daemon is not accessible"
    fi
    echo
    
    # Container status
    echo -e "${BOLD}📦 Container Status${NC}"
    local existing_containers
    existing_containers=$(docker ps -a --filter "name=static-" --format "{{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true)
    
    if [[ -n "$existing_containers" ]]; then
        echo "$existing_containers" | while IFS=$'\t' read -r name status ports; do
            if [[ "$status" =~ Up ]]; then
                echo "  🟢 $name - Running"
                [[ -n "$ports" ]] && echo "    🔗 Ports: $ports"
            else
                echo "  🔴 $name - Stopped"
            fi
        done
    else
        echo "  📭 No Milou containers found"
    fi
    echo
    
    # Port status
    echo -e "${BOLD}🔌 Port Status${NC}"
    local -a ports_to_check=("5432:PostgreSQL" "6379:Redis" "15672:RabbitMQ Management" "443:HTTPS" "80:HTTP" "9999:API")
    
    for port_info in "${ports_to_check[@]}"; do
        local port="${port_info%:*}"
        local service="${port_info#*:}"
        
        if check_port_availability "$port" "$service"; then
            echo "  ✅ Port $port ($service) - Available"
        else
            echo "  🔴 Port $port ($service) - In use"
            local process_info
            process_info=$(get_port_process "$port")
            echo "    🔍 Used by: $process_info"
        fi
    done
    echo
    
    # Configuration status
    echo -e "${BOLD}⚙️  Configuration Status${NC}"
    if [[ -f "$ENV_FILE" ]]; then
        echo "  ✅ Configuration file exists: $ENV_FILE"
        local env_age
        env_age=$(stat -c %Y "$ENV_FILE" 2>/dev/null || stat -f %m "$ENV_FILE" 2>/dev/null || echo "0")
        local current_time=$(date +%s)
        local age_days=$(( (current_time - env_age) / 86400 ))
        echo "  📅 Age: $age_days days"
    else
        echo "  ❌ No configuration file found"
    fi
    echo
    
    # Recommendations
    echo -e "${BOLD}💡 Recommendations${NC}"
    
    if [[ $installation_status -ne 0 ]]; then
        echo "  • Existing installation detected - use 'start' command with conflict resolution"
    fi
    
    # Check for port conflicts
    local port_conflicts=false
    for port_info in "${ports_to_check[@]}"; do
        local port="${port_info%:*}"
        if ! check_port_availability "$port" "service"; then
            port_conflicts=true
            break
        fi
    done
    
    if [[ "$port_conflicts" == true ]]; then
        echo "  • Port conflicts detected - stop conflicting services or use 'start --force'"
    fi
    
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "  • No configuration found - run 'setup' command first"
    fi
    
    echo "  • Use 'debug-images' command to troubleshoot image issues"
    echo "  • Use 'logs [service]' to view service logs"
    echo "  • Use 'cleanup --complete' to remove everything and start fresh"
    echo
} 