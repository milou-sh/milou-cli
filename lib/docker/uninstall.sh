#!/bin/bash

# =============================================================================
# Docker Uninstall Module for Milou CLI
# Handles complete removal of Milou installation
# =============================================================================

# Module guard to prevent multiple loading
if [[ "${MILOU_UNINSTALL_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_UNINSTALL_LOADED="true"

# Ensure logging is available
if ! command -v log >/dev/null 2>&1; then
    source "${SCRIPT_DIR}/lib/core/logging.sh" 2>/dev/null || {
        echo "ERROR: Cannot load logging module" >&2
        exit 1
    }
fi

# =============================================================================
# Complete Uninstall Function
# =============================================================================

# Enhanced complete uninstall with granular options
complete_milou_uninstall() {
    local include_images="${1:-true}"
    local include_volumes="${2:-true}"
    local include_config="${3:-true}"
    local include_ssl="${4:-true}"
    local include_logs="${5:-true}"
    local aggressive_mode="${6:-false}"
    
    # Temporarily disable strict error handling for this function
    set +e
    
    log "INFO" "🗑️ Starting complete Milou uninstall..."
    echo
    
    # Enhanced warning based on what will be removed
    local warnings=()
    [[ "$include_images" == "true" ]] && warnings+=("All Docker images")
    [[ "$include_volumes" == "true" ]] && warnings+=("All database and application data")
    [[ "$include_config" == "true" ]] && warnings+=("Configuration files (.env)")
    [[ "$include_ssl" == "true" ]] && warnings+=("SSL certificates")
    [[ "$include_logs" == "true" ]] && warnings+=("Application logs")
    [[ "$aggressive_mode" == "true" ]] && warnings+=("Global system configurations")
    
    if [[ ${#warnings[@]} -gt 0 ]]; then
        log "WARN" "⚠️  WARNING: This will permanently remove:"
        for warning in "${warnings[@]}"; do
            log "WARN" "    • $warning"
        done
        echo
        log "WARN" "⚠️  This action cannot be undone!"
        echo
    fi
    
    # Enhanced safety check with detailed confirmation
    log "INFO" "📋 Uninstall Summary:"
    log "INFO" "  🗂️ Remove images: $([ "$include_images" == "true" ] && echo "YES" || echo "NO")"
    log "INFO" "  💾 Remove volumes: $([ "$include_volumes" == "true" ] && echo "YES" || echo "NO")"
    log "INFO" "  ⚙️ Remove config: $([ "$include_config" == "true" ] && echo "YES" || echo "NO")"
    log "INFO" "  🔒 Remove SSL: $([ "$include_ssl" == "true" ] && echo "YES" || echo "NO")"
    log "INFO" "  📄 Remove logs: $([ "$include_logs" == "true" ] && echo "YES" || echo "NO")"
    log "INFO" "  🌍 Aggressive mode: $([ "$aggressive_mode" == "true" ] && echo "YES" || echo "NO")"
    echo
    
    # Safety confirmation unless --force is used
    if [[ "${FORCE:-false}" != "true" && "${INTERACTIVE:-true}" == "true" ]]; then
        echo -n "Are you sure you want to proceed with the uninstall? [y/N]: "
        read -r confirmation
        case "$confirmation" in
            [Yy]|[Yy][Ee][Ss])
                log "INFO" "Proceeding with uninstall..."
                ;;
            *)
                log "INFO" "Uninstall cancelled by user"
                return 0
                ;;
        esac
        echo
    elif [[ "${FORCE:-false}" == "true" ]]; then
        log "INFO" "Force mode enabled - skipping confirmation"
        echo
    fi
    
    # Step 1: Stop and remove containers
    log "STEP" "Step 1: Stopping and removing Milou containers"
    local containers_removed=0
    local containers
    containers=$(docker ps -a --filter "name=milou-" --format "{{.Names}}" 2>/dev/null || true)
    
    if [[ -n "$containers" ]]; then
        log "INFO" "🛑 Stopping containers..."
        # Stop containers with timeout and error handling
        local container_list=()
        while IFS= read -r container; do
            if [[ -n "$container" ]]; then
                container_list+=("$container")
                if docker stop "$container" --time 30 >/dev/null 2>&1; then
                    log "SUCCESS" "Stopped container: $container"
                else
                    log "WARN" "Failed to stop container: $container (may already be stopped)"
                fi
            fi
        done <<< "$containers"
        
        log "INFO" "🗑️ Removing containers..."
        for container in "${container_list[@]}"; do
            if docker rm -f "$container" >/dev/null 2>&1; then
                log "SUCCESS" "Removed container: $container"
                ((containers_removed++))
            else
                log "WARN" "Failed to remove container: $container"
            fi
        done
        
        # Try to remove by pattern for any missed containers
        local static_containers
        static_containers=$(docker ps -a --filter "name=static-*" --format "{{.Names}}" 2>/dev/null || true)
        if [[ -n "$static_containers" ]]; then
            while IFS= read -r container; do
                if [[ -n "$container" ]]; then
                    docker rm -f "$container" >/dev/null 2>&1 || true
                fi
            done <<< "$static_containers"
        fi
        
        log "SUCCESS" "Container removal step completed (processed: ${#container_list[@]} containers)"
    else
        log "INFO" "No Milou containers found"
    fi
    echo
    
    # Step 2: Remove Milou Docker images (enhanced detection)
    if [[ "$include_images" == "true" ]]; then
        log "STEP" "Step 2: Removing Milou Docker images"
        local images_removed=0
        
        # Enhanced image detection using multiple methods
        local all_images
        all_images=$(docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -E "(milou|ghcr\.io/milou-sh)" || true)
        
        if [[ -n "$all_images" ]]; then
            log "INFO" "🗑️ Removing Milou images from registry..."
            local image_count=0
            local image_list=()
            while IFS= read -r image; do
                if [[ -n "$image" ]]; then
                    image_list+=("$image")
                fi
            done <<< "$all_images"
            
            for image in "${image_list[@]}"; do
                if docker rmi -f "$image" >/dev/null 2>&1; then
                    log "SUCCESS" "Removed image: $image"
                    ((image_count++))
                else
                    log "WARN" "Failed to remove image: $image"
                fi
            done
            
            # Calculate space freed (enhanced)
            local space_freed
            space_freed=$(docker system df --format "table {{.Type}}\t{{.Reclaimable}}" 2>/dev/null | grep "Images" | awk '{print $2}' || echo "unknown")
            if [[ "$space_freed" != "unknown" && "$space_freed" != "0B" ]]; then
                log "INFO" "💾 Disk space potentially freed: $space_freed"
            fi
            
            log "SUCCESS" "Image removal step completed (processed: ${#image_list[@]} images)"
        else
            log "INFO" "No Milou images found"
        fi
    else
        log "INFO" "⏭️ Skipping image removal (--keep-images)"
    fi
    echo
    
    # Step 3: Remove Docker volumes
    if [[ "$include_volumes" == "true" ]]; then
        log "STEP" "Step 3: Removing Docker volumes"
        local volumes_removed=0
        local volumes
        volumes=$(docker volume ls --filter "name=milou" --format "{{.Name}}" 2>/dev/null || true)
        
        if [[ -z "$volumes" ]]; then
            # Try alternative patterns
            volumes=$(docker volume ls --filter "label=project=milou" --format "{{.Name}}" 2>/dev/null || true)
        fi
        
        if [[ -z "$volumes" ]]; then
            # Try generic static pattern
            volumes=$(docker volume ls --filter "name=static_" --format "{{.Name}}" 2>/dev/null || true)
        fi
        
        if [[ -n "$volumes" ]]; then
            log "INFO" "🗑️ Removing volumes..."
            local volume_count=0
            local volume_list=()
            while IFS= read -r volume; do
                if [[ -n "$volume" ]]; then
                    volume_list+=("$volume")
                fi
            done <<< "$volumes"
            
            for volume in "${volume_list[@]}"; do
                if docker volume rm -f "$volume" >/dev/null 2>&1; then
                    log "SUCCESS" "Removed volume: $volume"
                    ((volume_count++))
                else
                    log "WARN" "Failed to remove volume: $volume"
                fi
            done
            
            log "SUCCESS" "Volume removal step completed (processed: ${#volume_list[@]} volumes)"
        else
            log "INFO" "No Milou volumes found"
        fi
    else
        log "INFO" "⏭️ Skipping volume removal (--keep-volumes)"
    fi
    echo
    
    # Step 4: Remove Docker networks
    log "STEP" "Step 4: Removing Docker networks"
    local networks_removed=0
    local networks
    networks=$(docker network ls --filter "name=milou" --format "{{.Name}}" 2>/dev/null | grep -v "bridge\|host\|none" || true)
    
    if [[ -z "$networks" ]]; then
        # Try label-based search
        networks=$(docker network ls --filter "label=project=milou" --format "{{.Name}}" 2>/dev/null || true)
    fi
    
    if [[ -z "$networks" ]]; then
        # Try common network names
        networks=$(docker network ls --format "{{.Name}}" 2>/dev/null | grep -E "(static_|milou_)" || true)
    fi
    
    if [[ -n "$networks" ]]; then
        log "INFO" "🗑️ Removing networks..."
        local network_count=0
        local network_list=()
        while IFS= read -r network; do
            if [[ -n "$network" && "$network" != "bridge" && "$network" != "host" && "$network" != "none" ]]; then
                network_list+=("$network")
            fi
        done <<< "$networks"
        
        for network in "${network_list[@]}"; do
            if docker network rm "$network" >/dev/null 2>&1; then
                log "SUCCESS" "Removed network: $network"
                ((network_count++))
            else
                log "WARN" "Failed to remove network: $network (may be in use)"
            fi
        done
        
        log "SUCCESS" "Network removal step completed (processed: ${#network_list[@]} networks)"
    else
        log "INFO" "No Milou networks found"
    fi
    echo
    
    # Step 5: Remove configuration files (enhanced)
    if [[ "$include_config" == "true" ]]; then
        log "STEP" "Step 5: Removing configuration files"
        local config_files_removed=0
        
        # Current directory config files
        local current_dir_files=(".env" ".env.example" "docker-compose.override.yml")
        for file in "${current_dir_files[@]}"; do
            if [[ -f "$file" ]]; then
                rm -f "$file"
                log "SUCCESS" "Removed configuration file: $file"
                ((config_files_removed++))
            fi
        done
        
        # Global cleanup if aggressive mode
        if [[ "$aggressive_mode" == "true" ]]; then
            log "INFO" "🌍 Running global configuration cleanup..."
            
            # Search for Milou config files in common locations
            local search_paths=("/home/milou" "/home/*/milou-cli" "/opt/milou" "/etc/milou")
            for search_path in "${search_paths[@]}"; do
                if [[ -d "$search_path" ]]; then
                    find "$search_path" -name ".env" -path "*/milou-cli/*" -exec rm -f {} \; 2>/dev/null || true
                    find "$search_path" -name "docker-compose.override.yml" -path "*/milou-cli/*" -exec rm -f {} \; 2>/dev/null || true
                    log "INFO" "Cleaned configuration files in: $search_path"
                fi
            done
        fi
        
        if [[ $config_files_removed -eq 0 && "$aggressive_mode" == "false" ]]; then
            log "INFO" "No local configuration files found"
        else
            log "SUCCESS" "Configuration cleanup completed"
        fi
    else
        log "INFO" "⏭️ Skipping configuration removal (--keep-config)"
    fi
    echo
    
    # Step 6: Remove SSL certificates
    if [[ "$include_ssl" == "true" ]]; then
        log "STEP" "Step 6: Removing SSL certificates"
        local ssl_files_removed=0
        
        # Remove SSL directory and contents
        if [[ -d "ssl" ]]; then
            local ssl_files
            ssl_files=$(find ssl -type f 2>/dev/null | wc -l)
            rm -rf ssl/
            log "SUCCESS" "Removed SSL directory with $ssl_files files"
            ((ssl_files_removed += ssl_files))
        fi
        
        # Global SSL cleanup if aggressive mode
        if [[ "$aggressive_mode" == "true" ]]; then
            log "INFO" "🌍 Running global SSL cleanup..."
            local search_paths=("/home/milou" "/home/*/milou-cli" "/opt/milou")
            for search_path in "${search_paths[@]}"; do
                if [[ -d "$search_path" ]]; then
                    find "$search_path" -name "ssl" -type d -path "*/milou-cli/*" -exec rm -rf {} \; 2>/dev/null || true
                    log "INFO" "Cleaned SSL certificates in: $search_path"
                fi
            done
        fi
        
        if [[ $ssl_files_removed -eq 0 ]]; then
            log "INFO" "No SSL certificates found"
        else
            log "SUCCESS" "Removed SSL certificates"
        fi
    else
        log "INFO" "⏭️ Skipping SSL removal (--keep-ssl)"
    fi
    echo
    
    # Step 7: Remove logs and temporary files
    if [[ "$include_logs" == "true" ]]; then
        log "STEP" "Step 7: Removing logs and temporary files"
        local logs_removed=0
        
        # Remove log directories
        local log_dirs=("logs" "backup" ".cache" "tmp")
        for dir in "${log_dirs[@]}"; do
            if [[ -d "$dir" ]]; then
                local file_count
                file_count=$(find "$dir" -type f 2>/dev/null | wc -l)
                rm -rf "$dir"
                log "SUCCESS" "Removed $dir directory with $file_count files"
                ((logs_removed += file_count))
            fi
        done
        
        # Remove temporary files
        rm -f *.log *.tmp .milou_* 2>/dev/null || true
        
        if [[ $logs_removed -eq 0 ]]; then
            log "INFO" "No log files found"
        else
            log "SUCCESS" "Removed log files and temporary data"
        fi
    else
        log "INFO" "⏭️ Skipping log removal (--keep-logs)"
    fi
    echo
    
    # Step 8: Docker system cleanup
    log "STEP" "Step 8: Docker system cleanup"
    log "INFO" "🧹 Running Docker system prune..."
    
    # Remove unused Docker resources
    if docker system prune -f >/dev/null 2>&1; then
        log "SUCCESS" "Docker system cleanup completed"
    else
        log "WARN" "Docker system cleanup may have failed"
    fi
    
    # Show disk space summary
    local current_space
    current_space=$(df -h . 2>/dev/null | tail -1 | awk '{print $4}' || echo "unknown")
    if [[ "$current_space" != "unknown" ]]; then
        log "INFO" "💾 Available disk space: $current_space"
    fi
    echo
    
    # Final verification and summary
    log "STEP" "Step 9: Final verification"
    
    local remaining_containers remaining_images remaining_volumes
    remaining_containers=$(docker ps -a --filter "name=milou-" --format "{{.Names}}" 2>/dev/null | wc -l | tr -d ' \n' || echo "0")
    remaining_images=$(docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -E "(milou|ghcr\.io/milou-sh)" | wc -l | tr -d ' \n' || echo "0")
    remaining_volumes=$(docker volume ls --filter "name=milou" --format "{{.Name}}" 2>/dev/null | wc -l | tr -d ' \n' || echo "0")
    
    log "INFO" "📊 Uninstall Summary:"
    log "INFO" "  🗂️ Remaining containers: $remaining_containers"
    log "INFO" "  🐳 Remaining images: $remaining_images"
    log "INFO" "  💾 Remaining volumes: $remaining_volumes"
    log "INFO" "  ⚙️ Config files: $([ "$include_config" == "true" ] && echo "Removed" || echo "Preserved")"
    log "INFO" "  🔒 SSL certificates: $([ "$include_ssl" == "true" ] && echo "Removed" || echo "Preserved")"
    
    if [[ "$remaining_containers" -eq 0 && "$remaining_images" -eq 0 && "$remaining_volumes" -eq 0 ]]; then
        log "SUCCESS" "✅ Complete uninstall successful!"
    else
        log "WARN" "⚠️ Some resources may remain - manual cleanup may be required"
    fi
    
    echo
    log "INFO" "💡 Next steps:"
    if [[ "$include_config" == "false" || "$include_volumes" == "false" ]]; then
        log "INFO" "  • Some data was preserved - you can reinstall and potentially recover"
        log "INFO" "  • Use './milou.sh setup' to create a fresh installation"
    else
        log "INFO" "  • All Milou data has been permanently removed"
        log "INFO" "  • Use './milou.sh setup' to create a completely fresh installation"
        log "INFO" "  • You can now safely remove this directory if desired"
    fi
    
    # Restore strict error handling
    set -e
    
    return 0
}

# Export the function
export -f complete_milou_uninstall 