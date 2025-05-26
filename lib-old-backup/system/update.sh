#!/bin/bash

# Update and migration utility functions

# Update the application to the latest version
update_milou() {
    echo "Checking for Milou updates..."
    
    # Check if GitHub token is configured
    local github_token=$(get_config_value "GITHUB_TOKEN")
    if [ -z "$github_token" ]; then
        echo "Error: GitHub token not found in configuration."
        echo "Please provide a token using --token parameter."
        return 1
    fi
    
    # Check if services are running
    local services_running=false
    if docker compose -f "${SCRIPT_DIR}/static/docker-compose.yml" ps | grep "Up" &>/dev/null; then
        services_running=true
    fi
    
    # Create backup before update
    echo "Creating backup before update..."
    create_backup || {
        echo "Error: Failed to create backup before update."
        echo "Update aborted for safety reasons."
        return 1
    }
    
    # Pull the latest Docker images
    echo "Pulling latest Docker images..."
    pull_images "$github_token" || {
        echo "Error: Failed to pull latest Docker images."
        return 1
    }
    
    # Stop services if they are running
    if [ "$services_running" = true ]; then
        echo "Stopping services..."
        stop_services
    fi
    
    # Apply migrations if needed
    echo "Applying database migrations..."
    apply_migrations || {
        echo "Warning: Failed to apply migrations."
    }
    
    # Start services
    echo "Starting services with the updated version..."
    start_services
    
    echo "Update completed successfully."
    echo "Current version: $(get_milou_version)"
    
    return 0
}

# Apply database migrations
apply_migrations() {
    echo "Applying database migrations..."
    
    # Create temporary container to run migrations
    echo "Running migration container..."
    docker compose -f "${SCRIPT_DIR}/static/docker-compose.yml" run --rm backend npm run migrate || {
        echo "Error: Failed to apply migrations."
        return 1
    }
    
    echo "Migrations applied successfully."
    return 0
}

# Get the current version of Milou
get_milou_version() {
    # Try to get version from backend container
    local version=$(docker compose -f "${SCRIPT_DIR}/static/docker-compose.yml" exec backend cat /app/VERSION 2>/dev/null)
    if [ -n "$version" ]; then
        echo "$version"
        return 0
    fi
    
    # Fallback to hardcoded version
    echo "${VERSION}"
    return 0
}

# Check for available updates
check_for_updates() {
    echo "Checking for available updates..."
    
    # This is a placeholder for checking updates
    # In a real implementation, this would check a repository or API
    # for newer versions of the Docker images
    
    echo "Feature not implemented in this version."
    echo "Use 'update' command to pull the latest images."
    
    return 0
} 