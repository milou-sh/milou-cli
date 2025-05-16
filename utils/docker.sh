#!/bin/bash

# Docker utility functions

# Pull Docker images from GitHub Container Registry
pull_images() {
    local github_token="$1"
    
    echo "Pulling Docker images from GitHub Container Registry..."
    
    # List of images to pull
    local images=(
        "ghcr.io/milou-sh/milou/backend:v1.0.0"
        "ghcr.io/milou-sh/milou/frontend:v1.0.0"
        "ghcr.io/milou-sh/milou/engine:v1.0.0"
    )
    
    for image in "${images[@]}"; do
        echo "Pulling ${image}..."
        docker pull "${image}" || {
            echo "Error: Failed to pull ${image}. Please check your GitHub token and network connection."
            return 1
        }
    done
    
    echo "All Docker images pulled successfully."
    return 0
}

# Start all services
start_services() {
    # Ensure we have a valid configuration
    if ! validate_config; then
        echo "Error: Invalid configuration. Please run setup first."
        return 1
    fi
    
    # Create external network if it doesn't exist
    if ! docker network inspect proxy &>/dev/null; then
        echo "Creating proxy network..."
        docker network create proxy || {
            echo "Error: Failed to create proxy network."
            return 1
        }
    fi
    
    # Start services with Docker Compose
    echo "Starting services with Docker Compose..."
    cd "${SCRIPT_DIR}" && docker compose -f static/docker-compose.yml --env-file .env up -d || {
        echo "Error: Failed to start services."
        return 1
    }
    
    # Wait for services to be ready
    echo "Waiting for services to be ready..."
    local timeout=120
    local interval=5
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        # Check if backend is healthy
        if docker compose -f "${SCRIPT_DIR}/static/docker-compose.yml" ps | grep backend | grep "healthy" &>/dev/null; then
            echo "All services are ready!"
            return 0
        fi
        
        echo "Waiting for services to be ready... ($elapsed/$timeout seconds)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo "Warning: Timeout waiting for services to be ready. They might still be starting up."
    return 0
}

# Stop all services
stop_services() {
    echo "Stopping services..."
    cd "${SCRIPT_DIR}" && docker compose -f static/docker-compose.yml --env-file .env down || {
        echo "Error: Failed to stop services."
        return 1
    }
    
    echo "Services stopped successfully."
    return 0
}

# Restart all services
restart_services() {
    echo "Restarting services..."
    
    stop_services
    start_services
    
    return $?
}

# Check the status of all services
check_service_status() {
    echo "Service Status:"
    cd "${SCRIPT_DIR}" && docker compose -f static/docker-compose.yml ps || {
        echo "Error: Failed to check service status."
        return 1
    }
    
    return 0
}

# View logs for a specific service or all services
view_logs() {
    local service="$1"
    
    if [ -z "$service" ]; then
        # View logs for all services
        cd "${SCRIPT_DIR}" && docker compose -f static/docker-compose.yml logs --tail=100 || {
            echo "Error: Failed to view logs."
            return 1
        }
    else
        # View logs for a specific service
        cd "${SCRIPT_DIR}" && docker compose -f static/docker-compose.yml logs --tail=100 "$service" || {
            echo "Error: Failed to view logs for $service."
            return 1
        }
    fi
    
    return 0
}

# Clean up Docker resources
cleanup_docker() {
    echo "Cleaning up Docker resources..."
    
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
    
    # Check if the service is running
    if ! docker compose -f "${SCRIPT_DIR}/static/docker-compose.yml" ps | grep "$service" | grep "Up" &>/dev/null; then
        echo "Error: Service $service is not running."
        return 1
    fi
    
    # Get a shell in the container
    cd "${SCRIPT_DIR}" && docker compose -f static/docker-compose.yml exec "$service" sh || {
        echo "Error: Failed to get shell in $service."
        return 1
    }
    
    return 0
} 