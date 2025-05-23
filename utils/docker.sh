#!/bin/bash

# Docker utility functions

# Validate GitHub token format
validate_github_token() {
    local token="$1"
    if [[ ! "$token" =~ ^gh[pousr]_[A-Za-z0-9_]{36,251}$ ]]; then
        return 1
    fi
    return 0
}

# Pull Docker images from GitHub Container Registry
pull_images() {
    local github_token="$1"
    
    echo "Pulling Docker images from GitHub Container Registry..."
    
    # Validate token if provided
    if [[ -n "$github_token" ]] && ! validate_github_token "$github_token"; then
        echo "Error: Invalid GitHub token format"
        return 1
    fi
    
    # List of images to pull
    local images=(
        "ghcr.io/milou-sh/milou/backend:v1.0.0"
        "ghcr.io/milou-sh/milou/frontend:v1.0.0"
        "ghcr.io/milou-sh/milou/engine:v1.0.0"
        "ghcr.io/milou-sh/milou/nginx:v1.0.0"
        "ghcr.io/milou-sh/milou/database:v1.0.0"
    )
    
    local failed_images=()
    
    for image in "${images[@]}"; do
        echo "Pulling ${image}..."
        if ! docker pull "${image}" 2>/dev/null; then
            echo "Warning: Failed to pull ${image}"
            failed_images+=("$image")
        fi
    done
    
    if [[ ${#failed_images[@]} -gt 0 ]]; then
        echo "Error: Failed to pull the following images:"
        printf '  %s\n' "${failed_images[@]}"
        echo "Please check your GitHub token and network connection."
        return 1
    fi
    
    echo "All Docker images pulled successfully."
    return 0
}

# Check if Docker daemon is accessible
check_docker_access() {
    if ! docker info >/dev/null 2>&1; then
        echo "Error: Cannot access Docker daemon."
        echo "Please ensure:"
        echo "  1. Docker is installed and running"
        echo "  2. Current user has Docker permissions"
        echo "  3. Try: sudo usermod -aG docker \$USER && newgrp docker"
        return 1
    fi
    return 0
}

# Create Docker networks if they don't exist
create_networks() {
    echo "Creating Docker networks..."
    
    # Create milou_network if it doesn't exist
    if ! docker network inspect milou_network >/dev/null 2>&1; then
        echo "Creating milou_network..."
        if ! docker network create milou_network; then
            echo "Error: Failed to create milou_network"
            return 1
        fi
    fi
    
    # Create proxy network if it doesn't exist
    if ! docker network inspect proxy >/dev/null 2>&1; then
        echo "Creating proxy network..."
        if ! docker network create proxy; then
            echo "Error: Failed to create proxy network"
            return 1
        fi
    fi
    
    return 0
}

# Start all services
start_services() {
    # Check Docker access first
    if ! check_docker_access; then
        return 1
    fi
    
    # Ensure we have a valid configuration
    if ! validate_config; then
        echo "Error: Invalid configuration. Please run setup first."
        return 1
    fi
    
    # Create networks
    if ! create_networks; then
        return 1
    fi
    
    # Start services with Docker Compose
    echo "Starting services with Docker Compose..."
    cd "${SCRIPT_DIR}" || {
        echo "Error: Cannot change to script directory"
        return 1
    }
    
    if ! docker compose -f static/docker-compose.yml --env-file .env up -d; then
        echo "Error: Failed to start services."
        return 1
    fi
    
    # Wait for services to be ready
    echo "Waiting for services to be ready..."
    if wait_for_services; then
        echo "All services are ready!"
        return 0
    else
        echo "Warning: Some services may not be fully ready yet."
        return 0
    fi
}

# Wait for services to be healthy
wait_for_services() {
    local timeout=120
    local interval=5
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        # Check if backend is healthy
        if docker compose -f "${SCRIPT_DIR}/static/docker-compose.yml" ps --format "table {{.Service}}\t{{.Status}}" 2>/dev/null | grep -q "healthy"; then
            return 0
        fi
        
        echo "Waiting for services to be ready... ($elapsed/$timeout seconds)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo "Warning: Timeout waiting for services to be ready."
    return 1
}

# Stop all services
stop_services() {
    echo "Stopping services..."
    
    cd "${SCRIPT_DIR}" || {
        echo "Error: Cannot change to script directory"
        return 1
    }
    
    if ! docker compose -f static/docker-compose.yml down; then
        echo "Warning: Some services may not have stopped cleanly"
        return 1
    fi
    
    echo "Services stopped successfully."
    return 0
}

# Restart all services
restart_services() {
    echo "Restarting services..."
    
    if ! stop_services; then
        echo "Warning: Stop operation had issues"
    fi
    
    # Wait a moment for cleanup
    sleep 2
    
    if start_services; then
        echo "Services restarted successfully"
        return 0
    else
        echo "Error: Failed to restart services"
        return 1
    fi
}

# Check the status of all services
check_service_status() {
    echo "Service Status:"
    
    cd "${SCRIPT_DIR}" || {
        echo "Error: Cannot change to script directory"
        return 1
    }
    
    if ! docker compose -f static/docker-compose.yml ps; then
        echo "Error: Failed to check service status."
        return 1
    fi
    
    return 0
}

# View logs for a specific service or all services
view_logs() {
    local service="$1"
    
    cd "${SCRIPT_DIR}" || {
        echo "Error: Cannot change to script directory"
        return 1
    }
    
    if [ -z "$service" ]; then
        # View logs for all services
        if ! docker compose -f static/docker-compose.yml logs --tail=100; then
            echo "Error: Failed to view logs."
            return 1
        fi
    else
        # View logs for a specific service
        if ! docker compose -f static/docker-compose.yml logs --tail=100 "$service"; then
            echo "Error: Failed to view logs for $service."
            return 1
        fi
    fi
    
    return 0
}

# Clean up Docker resources
cleanup_docker() {
    echo "Cleaning up Docker resources..."
    
    if ! check_docker_access; then
        return 1
    fi
    
    # Remove unused images
    docker image prune -f
    
    # Remove unused volumes (optional, use with caution)
    # docker volume prune -f
    
    echo "Docker cleanup complete."
    return 0
}

# Get a shell in a running container
get_shell() {
    local service="$1"
    
    if [ -z "$service" ]; then
        echo "Error: Service name is required."
        echo "Usage: get_shell SERVICE_NAME"
        return 1
    fi
    
    cd "${SCRIPT_DIR}" || {
        echo "Error: Cannot change to script directory"
        return 1
    }
    
    # Check if the service is running
    if ! docker compose -f static/docker-compose.yml ps --format "table {{.Service}}\t{{.Status}}" | grep "$service" | grep -q "Up"; then
        echo "Error: Service $service is not running."
        return 1
    fi
    
    # Get a shell in the container
    if ! docker compose -f static/docker-compose.yml exec "$service" /bin/bash; then
        # Try with sh if bash is not available
        if ! docker compose -f static/docker-compose.yml exec "$service" /bin/sh; then
            echo "Error: Failed to get shell in $service."
            return 1
        fi
    fi
    
    return 0
} 