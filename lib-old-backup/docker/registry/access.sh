#!/bin/bash

# =============================================================================
# Docker Access Verification Module for Milou CLI
# Handles Docker daemon verification and credential management
# =============================================================================

# Module guard to prevent multiple loading
if [[ "${MILOU_DOCKER_REGISTRY_ACCESS_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_DOCKER_REGISTRY_ACCESS_LOADED="true"

# Ensure logging is available
if ! command -v milou_log >/dev/null 2>&1; then
    source "${SCRIPT_DIR}/lib/core/logging.sh" 2>/dev/null || {
        echo "ERROR: Cannot load logging module" >&2
        exit 1
    }
fi

# Constants
GITHUB_REGISTRY="${GITHUB_REGISTRY:-ghcr.io/milou-sh/milou}"
GITHUB_API_BASE="${GITHUB_API_BASE:-https://api.github.com}"

# =============================================================================
# Docker Access Verification Functions
# =============================================================================

# Verify Docker access and functionality
verify_docker_access() {
    milou_log "STEP" "Verifying Docker access..."
    
    # Check if Docker is installed
    if ! command -v docker >/dev/null 2>&1; then
        milou_log "ERROR" "Docker is not installed or not in PATH"
        milou_log "INFO" "💡 Install Docker: https://docs.docker.com/get-docker/"
        return 1
    fi
    
    milou_log "SUCCESS" "✅ Docker command available"
    
    # Check Docker version
    local docker_version
    docker_version=$(docker --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
    if [[ -n "$docker_version" ]]; then
        milou_log "INFO" "Docker version: $docker_version"
    fi
    
    # Check if Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        milou_log "ERROR" "Docker daemon is not running"
        milou_log "INFO" "💡 Start Docker daemon:"
        milou_log "INFO" "  • Linux: sudo systemctl start docker"
        milou_log "INFO" "  • macOS/Windows: Start Docker Desktop"
        return 1
    fi
    
    milou_log "SUCCESS" "✅ Docker daemon is running"
    
    # Check Docker permissions
    if ! docker ps >/dev/null 2>&1; then
        milou_log "ERROR" "Docker permission denied"
        milou_log "INFO" "💡 Fix Docker permissions:"
        milou_log "INFO" "  • Add user to docker group: sudo usermod -aG docker \$USER"
        milou_log "INFO" "  • Then logout and login again"
        milou_log "INFO" "  • Or run with sudo (not recommended)"
        return 1
    fi
    
    milou_log "SUCCESS" "✅ Docker permissions OK"
    
    # Test basic Docker functionality
    milou_log "DEBUG" "Testing basic Docker functionality..."
    if docker run --rm hello-world >/dev/null 2>&1; then
        milou_log "SUCCESS" "✅ Docker functionality test passed"
    else
        milou_log "WARN" "⚠️  Docker functionality test failed (may be network related)"
        # Don't return error as this might be due to network issues
    fi
    
    return 0
}

# Ensure Docker credentials are properly configured
ensure_docker_credentials() {
    local token="$1"
    local username="${2:-}"
    
    milou_log "STEP" "Ensuring Docker registry credentials..."
    
    # Verify Docker access first
    if ! verify_docker_access; then
        return 1
    fi
    
    # If no token provided, check if already authenticated
    if [[ -z "$token" ]]; then
        milou_log "DEBUG" "No token provided, checking existing authentication..."
        
        # Try to access a private registry endpoint to test authentication
        if docker pull ghcr.io/milou-sh/milou/test:latest >/dev/null 2>&1; then
            milou_log "SUCCESS" "✅ Already authenticated with Docker registry"
            return 0
        else
            milou_log "WARN" "No valid Docker registry authentication found"
            return 1
        fi
    fi
    
    # Get username if not provided
    if [[ -z "$username" ]]; then
        milou_log "DEBUG" "Detecting username from GitHub API..."
        local user_response
        user_response=$(curl -s -H "Authorization: Bearer $token" \
                       -H "Accept: application/vnd.github.v3+json" \
                       "$GITHUB_API_BASE/user" 2>/dev/null)
        
        if echo "$user_response" | grep -q '"login"'; then
            username=$(echo "$user_response" | grep -o '"login": *"[^"]*"' | cut -d'"' -f4)
            milou_log "DEBUG" "Detected username: $username"
        else
            milou_log "DEBUG" "Could not detect username, using 'token'"
            username="token"
        fi
    fi
    
    # Authenticate with Docker registry
    milou_log "DEBUG" "Authenticating with Docker registry..."
    if echo "$token" | docker login ghcr.io -u "$username" --password-stdin >/dev/null 2>&1; then
        milou_log "SUCCESS" "✅ Docker registry authentication successful"
        
        # Verify authentication by testing access
        if docker pull ghcr.io/milou-sh/milou/test:latest >/dev/null 2>&1; then
            milou_log "DEBUG" "Authentication verification successful"
        else
            milou_log "DEBUG" "Authentication verification failed (test image may not exist)"
        fi
        
        return 0
    else
        milou_log "ERROR" "❌ Docker registry authentication failed"
        milou_log "INFO" "💡 Ensure your GitHub token has the following scopes:"
        milou_log "INFO" "  • read:packages"
        milou_log "INFO" "  • write:packages (if pushing images)"
        return 1
    fi
}

# Debug Docker images and registry state
debug_docker_images() {
    milou_log "STEP" "Debugging Docker images and registry state..."
    
    # Check Docker system info
    milou_log "INFO" "🐳 Docker System Information:"
    if docker info >/dev/null 2>&1; then
        local docker_info
        docker_info=$(docker info 2>/dev/null)
        
        # Extract key information
        local containers_running containers_total images_total
        containers_running=$(echo "$docker_info" | grep "Containers:" | awk '{print $2}' || echo "unknown")
        containers_total=$(echo "$docker_info" | grep "Running:" | awk '{print $2}' || echo "unknown")
        images_total=$(echo "$docker_info" | grep "Images:" | awk '{print $2}' || echo "unknown")
        
        milou_log "INFO" "  Containers: $containers_running running, $containers_total total"
        milou_log "INFO" "  Images: $images_total total"
        
        # Check storage driver
        local storage_driver
        storage_driver=$(echo "$docker_info" | grep "Storage Driver:" | awk '{print $3}' || echo "unknown")
        milou_log "INFO" "  Storage Driver: $storage_driver"
        
        # Check available space
        local docker_root_dir
        docker_root_dir=$(echo "$docker_info" | grep "Docker Root Dir:" | awk '{print $4}' || echo "/var/lib/docker")
        if command -v df >/dev/null 2>&1; then
            local available_space
            available_space=$(df -h "$docker_root_dir" 2>/dev/null | tail -1 | awk '{print $4}' || echo "unknown")
            milou_log "INFO" "  Available Space: $available_space"
        fi
    else
        milou_log "ERROR" "Cannot access Docker system information"
        return 1
    fi
    
    # List Milou-related images
    milou_log "INFO" "🖼️  Milou-related Docker Images:"
    local milou_images
    milou_images=$(docker images --filter "reference=*milou*" --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" 2>/dev/null || echo "")
    
    if [[ -n "$milou_images" ]]; then
        echo "$milou_images" | while IFS= read -r line; do
            milou_log "INFO" "  $line"
        done
    else
        milou_log "INFO" "  No Milou-related images found"
    fi
    
    # Check registry authentication status
    milou_log "INFO" "🔐 Registry Authentication Status:"
    local docker_config_file="$HOME/.docker/config.json"
    if [[ -f "$docker_config_file" ]]; then
        if command -v jq >/dev/null 2>&1; then
            local registries
            registries=$(jq -r '.auths | keys[]' "$docker_config_file" 2>/dev/null || echo "")
            if [[ -n "$registries" ]]; then
                echo "$registries" | while IFS= read -r registry; do
                    milou_log "INFO" "  ✅ Authenticated with: $registry"
                done
            else
                milou_log "INFO" "  No registry authentications found"
            fi
        else
            milou_log "INFO" "  Docker config exists but jq not available for parsing"
        fi
    else
        milou_log "INFO" "  No Docker config file found"
    fi
    
    # Test network connectivity to GitHub Container Registry
    milou_log "INFO" "🌐 Network Connectivity Test:"
    if command -v curl >/dev/null 2>&1; then
        local ghcr_response
        ghcr_response=$(curl -s -o /dev/null -w "%{http_code}" "https://ghcr.io/v2/" 2>/dev/null || echo "000")
        if [[ "$ghcr_response" == "200" ]]; then
            milou_log "SUCCESS" "  ✅ GitHub Container Registry accessible"
        else
            milou_log "ERROR" "  ❌ GitHub Container Registry not accessible (HTTP: $ghcr_response)"
        fi
        
        # Test GitHub API connectivity
        local github_api_response
        github_api_response=$(curl -s -o /dev/null -w "%{http_code}" "$GITHUB_API_BASE" 2>/dev/null || echo "000")
        if [[ "$github_api_response" == "200" ]]; then
            milou_log "SUCCESS" "  ✅ GitHub API accessible"
        else
            milou_log "ERROR" "  ❌ GitHub API not accessible (HTTP: $github_api_response)"
        fi
    else
        milou_log "WARN" "  curl not available for connectivity testing"
    fi
    
    return 0
}

# Check Docker resource usage and limits
check_docker_resources() {
    milou_log "STEP" "Checking Docker resource usage..."
    
    if ! docker info >/dev/null 2>&1; then
        milou_log "ERROR" "Docker daemon not accessible"
        return 1
    fi
    
    # Check disk usage
    milou_log "INFO" "💾 Docker Disk Usage:"
    if docker system df >/dev/null 2>&1; then
        local disk_usage
        disk_usage=$(docker system df 2>/dev/null)
        echo "$disk_usage" | while IFS= read -r line; do
            milou_log "INFO" "  $line"
        done
        
        # Check if cleanup is needed
        local total_size
        total_size=$(echo "$disk_usage" | grep "Total" | awk '{print $3}' | sed 's/[^0-9.]//g' || echo "0")
        if [[ -n "$total_size" ]] && (( $(echo "$total_size > 10" | bc -l 2>/dev/null || echo "0") )); then
            milou_log "WARN" "⚠️  Docker is using significant disk space (${total_size}GB)"
            milou_log "INFO" "💡 Consider running: docker system prune -f"
        fi
    else
        milou_log "WARN" "Cannot check Docker disk usage"
    fi
    
    # Check memory usage of running containers
    milou_log "INFO" "🧠 Container Memory Usage:"
    local container_stats
    container_stats=$(docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}" 2>/dev/null || echo "")
    
    if [[ -n "$container_stats" ]]; then
        echo "$container_stats" | while IFS= read -r line; do
            milou_log "INFO" "  $line"
        done
    else
        milou_log "INFO" "  No running containers"
    fi
    
    return 0
}

# Clean up Docker resources
cleanup_docker_resources() {
    local aggressive="${1:-false}"
    
    milou_log "STEP" "Cleaning up Docker resources..."
    
    if ! docker info >/dev/null 2>&1; then
        milou_log "ERROR" "Docker daemon not accessible"
        return 1
    fi
    
    # Basic cleanup
    milou_log "INFO" "Removing unused containers, networks, and images..."
    if docker system prune -f >/dev/null 2>&1; then
        milou_log "SUCCESS" "✅ Basic cleanup completed"
    else
        milou_log "WARN" "Basic cleanup failed"
    fi
    
    # Aggressive cleanup if requested
    if [[ "$aggressive" == "true" ]]; then
        milou_log "INFO" "Performing aggressive cleanup (removing all unused images)..."
        if docker system prune -a -f >/dev/null 2>&1; then
            milou_log "SUCCESS" "✅ Aggressive cleanup completed"
        else
            milou_log "WARN" "Aggressive cleanup failed"
        fi
        
        # Clean up volumes (be careful with this)
        milou_log "INFO" "Cleaning up unused volumes..."
        if docker volume prune -f >/dev/null 2>&1; then
            milou_log "SUCCESS" "✅ Volume cleanup completed"
        else
            milou_log "WARN" "Volume cleanup failed"
        fi
    fi
    
    # Show space reclaimed
    milou_log "INFO" "💾 Updated disk usage:"
    if docker system df >/dev/null 2>&1; then
        docker system df 2>/dev/null | while IFS= read -r line; do
            milou_log "INFO" "  $line"
        done
    fi
    
    return 0
}

# Test Docker registry connectivity
test_registry_connectivity() {
    local registry="${1:-ghcr.io}"
    
    milou_log "STEP" "Testing connectivity to Docker registry: $registry"
    
    # Test basic connectivity
    if command -v curl >/dev/null 2>&1; then
        local registry_url="https://$registry/v2/"
        local response
        response=$(curl -s -o /dev/null -w "%{http_code}" "$registry_url" 2>/dev/null || echo "000")
        
        case "$response" in
            200)
                milou_log "SUCCESS" "✅ Registry accessible: $registry"
                ;;
            401)
                milou_log "SUCCESS" "✅ Registry accessible but requires authentication: $registry"
                ;;
            404)
                milou_log "WARN" "⚠️  Registry endpoint not found: $registry"
                ;;
            *)
                milou_log "ERROR" "❌ Registry not accessible: $registry (HTTP: $response)"
                return 1
                ;;
        esac
    else
        milou_log "WARN" "curl not available for connectivity testing"
    fi
    
    # Test Docker's ability to connect
    milou_log "DEBUG" "Testing Docker's registry connectivity..."
    if docker pull hello-world >/dev/null 2>&1; then
        milou_log "SUCCESS" "✅ Docker can pull from registries"
    else
        milou_log "WARN" "⚠️  Docker registry connectivity test failed"
    fi
    
    return 0
}

milou_log "DEBUG" "Docker access verification module loaded successfully" 