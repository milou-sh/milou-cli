#!/bin/bash

# =============================================================================
# System Management Command Handlers for Milou CLI
# Simplified and standardized command handlers
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Modules are loaded centrally by milou_load_command_modules() in main script

# Configuration display command handler
handle_config() {
    milou_log "INFO" "📋 Displaying current configuration..."
    
    if command -v milou_config_show >/dev/null 2>&1; then
        milou_config_show "$@"
    elif command -v show_config >/dev/null 2>&1; then
        show_config "$@"
    else
        milou_log "ERROR" "Configuration display function not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize configuration modules"
        return 1
    fi
}

# Configuration validation command handler
handle_validate() {
    milou_log "INFO" "🔍 Validating configuration and environment..."
    
    if command -v milou_config_validate_environment_production >/dev/null 2>&1; then
        milou_config_validate_environment_production "$@"
    elif command -v validate_configuration >/dev/null 2>&1; then
        validate_configuration "$@"
    else
        milou_log "ERROR" "Configuration validation function not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize validation modules"
        return 1
    fi
}

# Backup command handler
handle_backup() {
    milou_log "INFO" "💾 Creating system backup..."
    
    if command -v milou_config_backup >/dev/null 2>&1; then
        milou_config_backup "$@"
    elif command -v backup_config >/dev/null 2>&1; then
        backup_config "$@"
    else
        milou_log "ERROR" "Backup function not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize backup modules"
        return 1
    fi
}

# Restore command handler
handle_restore() {
    local backup_file="${1:-}"
    
    if [[ -z "$backup_file" ]]; then
        milou_log "ERROR" "Backup file is required for restore"
        milou_log "INFO" "Usage: ./milou.sh restore <backup_file>"
        return 1
    fi
    
    milou_log "INFO" "📁 Restoring from backup: $backup_file"
    
    if command -v restore_config >/dev/null 2>&1; then
        restore_config "$backup_file"
    elif command -v restore_from_backup >/dev/null 2>&1; then
        restore_from_backup "$backup_file"
    else
        milou_log "ERROR" "Restore function not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize backup modules"
        return 1
    fi
}

# Update command handler
handle_update() {
    milou_log "INFO" "🔄 Updating to latest version..."
    
    if command -v milou_system_update >/dev/null 2>&1; then
        milou_system_update "$@"
    elif command -v update_milou_system >/dev/null 2>&1; then
        update_milou_system "$@"
    else
        milou_log "ERROR" "Update function not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize update modules"
        return 1
    fi
}

# SSL management command handler
handle_ssl() {
    milou_log "INFO" "🔒 Managing SSL certificates..."
    
    # Delegate to SSL module with enhanced interactive system
    if command -v milou_ssl_setup_interactive_enhanced >/dev/null 2>&1; then
        milou_ssl_setup_interactive_enhanced "$@"
    elif command -v setup_ssl_interactive_enhanced >/dev/null 2>&1; then
        setup_ssl_interactive_enhanced "$@"
    elif command -v setup_ssl_interactive >/dev/null 2>&1; then
        setup_ssl_interactive "$@"
    else
        milou_log "ERROR" "SSL management function not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize SSL modules"
        return 1
    fi
}

# Update domain configuration in environment files
update_domain_configuration() {
    local new_domain="$1"
    local ssl_path="$2"
    local env_file="${SCRIPT_DIR}/.env"
    
    if [[ ! -f "$env_file" ]]; then
    milou_log "WARN" "⚠️  Environment file not found: $env_file"
        return 1
    fi
    
    milou_log "INFO" "📝 Updating domain configuration..."
    
    # Create backup of .env file
    cp "$env_file" "${env_file}.backup.$(date +%s)"
    
    # Update domain-related variables
    sed -i.tmp "s/^SERVER_NAME=.*/SERVER_NAME=$new_domain/" "$env_file"
    sed -i.tmp "s/^CUSTOMER_DOMAIN_NAME=.*/CUSTOMER_DOMAIN_NAME=$new_domain/" "$env_file"
    sed -i.tmp "s/^DOMAIN=.*/DOMAIN=$new_domain/" "$env_file"
    sed -i.tmp "s/^MILOU_DOMAIN=.*/MILOU_DOMAIN=$new_domain/" "$env_file"
    
    # Update CORS origin
    sed -i.tmp "s|^CORS_ORIGIN=.*|CORS_ORIGIN=https://$new_domain|" "$env_file"
    
    # Update API URLs
    sed -i.tmp "s|^API_URL=.*|API_URL=https://$new_domain/api|" "$env_file"
    sed -i.tmp "s|^API_BASE_URL=.*|API_BASE_URL=https://$new_domain/api|" "$env_file"
    
    # Clean up temporary file
    rm -f "${env_file}.tmp"
    
    milou_log "SUCCESS" "✅ Domain configuration updated to: $new_domain"
    milou_log "INFO" "  Updated variables: SERVER_NAME, DOMAIN, CORS_ORIGIN, API_URL"
    
    # Update exported environment variables for current session
    export SERVER_NAME="$new_domain"
    export DOMAIN="$new_domain"
    export CORS_ORIGIN="https://$new_domain"
    export API_URL="https://$new_domain/api"
    export API_BASE_URL="https://$new_domain/api"
}

# Restart nginx container to apply SSL changes
restart_nginx_container() {
    milou_log "INFO" "🔄 Restarting nginx container to apply SSL changes..."
    
    # Check if nginx container is running
    if ! docker ps --format "{{.Names}}" | grep -q "milou-nginx"; then
    milou_log "WARN" "⚠️  Nginx container is not running, starting services..."
        if command -v start_services >/dev/null 2>&1; then
            start_services
            return $?
        else
    milou_log "ERROR" "❌ Cannot start services - start function not available"
            return 1
        fi
    fi
    
    # Get the compose file
    local compose_file="${SCRIPT_DIR}/static/docker-compose.yml"
    if [[ ! -f "$compose_file" ]]; then
        compose_file="./static/docker-compose.yml"
    fi
    
    if [[ ! -f "$compose_file" ]]; then
    milou_log "ERROR" "❌ Docker compose file not found"
        return 1
    fi
    
    # Restart nginx container
    milou_log "INFO" "🔄 Restarting nginx container..."
    if docker compose -f "$compose_file" restart nginx; then
    milou_log "SUCCESS" "✅ Nginx container restarted successfully"
        
        # Wait a moment for nginx to start
        sleep 2
        
        # Check nginx health
        if docker ps --format "{{.Names}}\t{{.Status}}" | grep "milou-nginx" | grep -q "healthy\|Up"; then
    milou_log "SUCCESS" "✅ Nginx is healthy and serving requests"
            return 0
        else
    milou_log "WARN" "⚠️  Nginx restarted but health check pending"
            return 0
        fi
    else
    milou_log "ERROR" "❌ Failed to restart nginx container"
        return 1
    fi
}

# Cleanup command handler
handle_cleanup() {
    local cleanup_type="${1:-docker}"
    
    case "$cleanup_type" in
        docker|--docker)
    milou_log "INFO" "🧹 Cleaning up Docker resources..."
            if command -v cleanup_docker_resources >/dev/null 2>&1; then
                cleanup_docker_resources
            else
    milou_log "ERROR" "Docker cleanup function not available"
                return 1
            fi
            ;;
        system|--system)
    milou_log "INFO" "🧹 Cleaning up system resources..."
            if command -v cleanup_system_resources >/dev/null 2>&1; then
                cleanup_system_resources
            else
    milou_log "ERROR" "System cleanup function not available"
                return 1
            fi
            ;;
        all|--all)
    milou_log "INFO" "🧹 Performing complete system cleanup..."
            if command -v cleanup_docker_resources >/dev/null 2>&1; then
                cleanup_docker_resources
            fi
            if command -v cleanup_system_resources >/dev/null 2>&1; then
                cleanup_system_resources
            fi
            ;;
        complete|--complete|uninstall|--uninstall)
    milou_log "INFO" "🗑️ Complete Milou uninstallation..."
            handle_uninstall "${@:2}"
            ;;
        --help|-h)
            echo "Cleanup command usage:"
            echo "  ./milou.sh cleanup [docker|system|all|complete]"
            echo ""
            echo "Options:"
            echo "  docker     Clean Docker resources (default)"
            echo "  system     Clean system temporary files"
            echo "  all        Clean everything (non-destructive)"
            echo "  complete   Complete uninstall (DESTRUCTIVE - removes all data)"
            echo ""
            echo "For complete uninstall, see: ./milou.sh uninstall --help"
            ;;
        *)
    milou_log "WARN" "Unknown cleanup type: $cleanup_type, defaulting to docker cleanup"
            if command -v cleanup_docker_resources >/dev/null 2>&1; then
                cleanup_docker_resources
            else
    milou_log "ERROR" "Docker cleanup function not available"
                return 1
            fi
            ;;
    esac
}

# Complete uninstall command handler
handle_uninstall() {
    local show_help=false
    local include_images=true
    local include_volumes=true
    local include_config=true
    local include_ssl=true
    local include_logs=true
    local include_user_data=false
    local aggressive_cleanup=false
    
    # Parse uninstall-specific options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help=true
                shift
                ;;
            --keep-images)
                include_images=false
                shift
                ;;
            --keep-volumes)
                include_volumes=false
                shift
                ;;
            --keep-config)
                include_config=false
                shift
                ;;
            --keep-ssl)
                include_ssl=false
                shift
                ;;
            --keep-logs)
                include_logs=false
                shift
                ;;
            --include-user-data)
                include_user_data=true
                shift
                ;;
            --aggressive|--nuclear)
                aggressive_cleanup=true
                include_images=true
                include_volumes=true
                include_config=true
                include_ssl=true
                include_logs=true
                include_user_data=true
                shift
                ;;
            *)
                # Ignore unknown flags
                shift
                ;;
        esac
    done
    
    if [[ "$show_help" == "true" ]]; then
        echo "Milou Complete Uninstall"
        echo "========================="
        echo "This command completely removes Milou from your system."
        echo ""
        echo "Usage: ./milou.sh uninstall [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --keep-images         Keep downloaded Docker images"
        echo "  --keep-volumes        Keep data volumes (databases, etc.)"
        echo "  --keep-config         Keep configuration files (.env, etc.)"
        echo "  --keep-ssl            Keep SSL certificates"
        echo "  --keep-logs           Keep log files"
        echo "  --include-user-data   Remove user data directories (~/.milou)"
        echo "  --aggressive          Remove everything including system data"
        echo "  --force               Skip confirmation prompts"
        echo "  --help, -h            Show this help"
        echo ""
        echo "Examples:"
        echo "  ./milou.sh uninstall                    # Standard uninstall"
        echo "  ./milou.sh uninstall --keep-config      # Keep configuration"
        echo "  ./milou.sh uninstall --aggressive       # Remove everything"
        echo "  ./milou.sh uninstall --force            # Skip confirmations"
        echo ""
        echo "⚠️  WARNING: This operation is DESTRUCTIVE and cannot be undone!"
        return 0
    fi

    # Ensure the uninstall module is loaded
    if ! command -v complete_milou_uninstall >/dev/null 2>&1; then
        milou_log "INFO" "Loading uninstall module..."
        if command -v milou_load_module >/dev/null 2>&1; then
            milou_load_module "docker/uninstall" || {
                milou_log "ERROR" "Failed to load uninstall module"
                return 1
            }
        else
            milou_log "ERROR" "Module loader not available"
            return 1
        fi
    fi
    
    # Call the enhanced complete cleanup function with proper parameters
    if command -v complete_milou_uninstall >/dev/null 2>&1; then
        complete_milou_uninstall "$include_images" "$include_volumes" "$include_config" "$include_ssl" "$include_logs" "$aggressive_cleanup"
        local exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            milou_log "SUCCESS" "🎉 Uninstall completed successfully"
        else
            milou_log "ERROR" "Uninstall completed with errors (exit code: $exit_code)"
        fi
        
        return $exit_code
    elif command -v complete_cleanup_milou_resources >/dev/null 2>&1; then
        milou_log "WARN" "Using legacy cleanup function (limited options)"
        complete_cleanup_milou_resources
        return $?
    else
        milou_log "ERROR" "Uninstall function not available"
        milou_log "INFO" "💡 Try restarting services and running the command again"
        return 1
    fi
}

# Debug images command handler
handle_debug_images() {
    milou_log "INFO" "🔧 Debugging Docker image availability..."
    
    if command -v debug_docker_images >/dev/null 2>&1; then
        debug_docker_images "$@"
    else
        milou_log "ERROR" "Debug images function not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize Docker debugging"
        return 1
    fi
}

# System diagnosis command handler
handle_diagnose() {
    milou_log "INFO" "🔍 Running comprehensive system diagnosis..."
    echo
    
    # System information
    echo -e "${BOLD}🖥️  System Information:${NC}"
    echo "  OS: $(uname -s) $(uname -r)"
    echo "  User: $(whoami)"
    echo "  Working Directory: $(pwd)"
    echo "  Script Directory: $SCRIPT_DIR"
    echo
    
    # Configuration status
    echo -e "${BOLD}⚙️  Configuration Status:${NC}"
    local env_file="${SCRIPT_DIR}/.env"
    if [[ -f "$env_file" ]]; then
        echo "  ✅ Configuration file exists: $env_file"
        local file_size=$(stat -f%z "$env_file" 2>/dev/null || stat -c%s "$env_file" 2>/dev/null || echo "unknown")
        echo "  📏 File size: ${file_size} bytes"
        echo "  🔒 Permissions: $(ls -la "$env_file" | cut -d' ' -f1)"
        
        # Extract key configuration without exposing secrets
        echo
        echo -e "${BOLD}🔧 Key Configuration (sanitized):${NC}"
        if grep -q "^DOMAIN=" "$env_file"; then
            local domain=$(grep "^DOMAIN=" "$env_file" | cut -d'=' -f2- | tr -d '"')
            echo "  🌐 Domain: $domain"
        fi
        if grep -q "^SSL_MODE=" "$env_file"; then
            local ssl_mode=$(grep "^SSL_MODE=" "$env_file" | cut -d'=' -f2- | tr -d '"')
            echo "  🔒 SSL Mode: $ssl_mode"
        fi
        if grep -q "^ADMIN_EMAIL=" "$env_file"; then
            local admin_email=$(grep "^ADMIN_EMAIL=" "$env_file" | cut -d'=' -f2- | tr -d '"')
            echo "  👤 Admin Email: $admin_email"
        fi
        
        # Check for credential fields (without exposing values)
        local cred_fields=("POSTGRES_PASSWORD" "REDIS_PASSWORD" "JWT_SECRET" "SESSION_SECRET" "ENCRYPTION_KEY")
        echo "  🔑 Credentials present:"
        for field in "${cred_fields[@]}"; do
            if grep -q "^${field}=" "$env_file"; then
                local value=$(grep "^${field}=" "$env_file" | cut -d'=' -f2- | tr -d '"')
                local length=${#value}
                echo "     • $field: ${length} characters"
            else
                echo "     • $field: ❌ MISSING"
            fi
        done
    else
        echo "  ❌ No configuration file found"
        echo "  💡 Run './milou.sh setup' to create configuration"
    fi
    echo
    
    # Docker status
    echo -e "${BOLD}🐳 Docker Status:${NC}"
    if command -v docker >/dev/null 2>&1; then
        echo "  ✅ Docker CLI available"
        if docker info >/dev/null 2>&1; then
            echo "  ✅ Docker daemon accessible"
            local docker_version=$(docker --version | cut -d' ' -f3 | tr -d ',')
            echo "  📦 Docker version: $docker_version"
            
            # Docker Compose
            if docker compose version >/dev/null 2>&1; then
                echo "  ✅ Docker Compose available"
                local compose_version=$(docker compose version --short 2>/dev/null || echo "unknown")
                echo "  🔧 Compose version: $compose_version"
            else
                echo "  ❌ Docker Compose not available"
            fi
        else
            echo "  ❌ Docker daemon not accessible"
            echo "     💡 Try: sudo systemctl start docker"
        fi
    else
        echo "  ❌ Docker not installed"
        echo "     💡 Run installation: ./milou.sh install-deps"
    fi
    echo
    
    # Container status
    echo -e "${BOLD}📦 Container Status:${NC}"
    local containers=$(docker ps -a --filter "name=milou-" --format "{{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "")
    if [[ -n "$containers" ]]; then
        local running_count=0
        local total_count=0
        
        echo "  Container Details:"
        while IFS=$'\t' read -r name status ports; do
            ((total_count++))
            local status_icon="🔴"
            if [[ "$status" =~ Up|running ]]; then
                ((running_count++))
                status_icon="🟢"
            elif [[ "$status" =~ Restarting ]]; then
                status_icon="🟡"
            fi
            
            echo "     $status_icon $name"
            echo "        Status: $status"
            if [[ -n "$ports" ]]; then
                echo "        Ports: $ports"
            fi
        done <<< "$containers"
        
        echo
        echo "  📊 Summary: $running_count/$total_count containers running"
    else
        echo "  ❌ No Milou containers found"
        echo "     💡 Run: ./milou.sh setup"
    fi
    echo
    
    # Volume status
    echo -e "${BOLD}💾 Volume Status:${NC}"
    local volumes=$(docker volume ls --filter "name=milou" --filter "name=static" --format "{{.Name}}\t{{.Driver}}" 2>/dev/null || echo "")
    if [[ -n "$volumes" ]]; then
        echo "  Data Volumes:"
        while IFS=$'\t' read -r name driver; do
            if [[ -n "$name" ]]; then
                echo "     📁 $name ($driver)"
                
                # Get volume size
                local volume_size
                volume_size=$(docker run --rm -v "$name:/data" alpine sh -c 'du -sh /data 2>/dev/null | cut -f1' 2>/dev/null || echo "unknown")
                echo "        Size: $volume_size"
            fi
        done <<< "$volumes"
    else
        echo "  ❌ No data volumes found"
    fi
    echo
    
    # Network status
    echo -e "${BOLD}🌐 Network Status:${NC}"
    local critical_ports=("80:HTTP" "443:HTTPS" "5432:PostgreSQL" "6379:Redis" "9999:API")
    local ports_in_use=0
    
    echo "  Port Status:"
    for port_info in "${critical_ports[@]}"; do
        local port="${port_info%:*}"
        local service="${port_info#*:}"
        
        if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
            echo "     🟢 Port $port ($service) - In use"
            ((ports_in_use++))
        else
            echo "     🔴 Port $port ($service) - Available"
        fi
    done
    
    echo "  📊 Ports in use: $ports_in_use/${#critical_ports[@]}"
    echo
    
    # SSL certificate status
    echo -e "${BOLD}🔒 SSL Certificate Status:${NC}"
    local ssl_dir="${SCRIPT_DIR}/ssl"
    if [[ -d "$ssl_dir" ]]; then
        if [[ -f "$ssl_dir/milou.crt" && -f "$ssl_dir/milou.key" ]]; then
            echo "  ✅ SSL certificates found"
            
            # Check certificate validity
            if openssl x509 -in "$ssl_dir/milou.crt" -noout >/dev/null 2>&1; then
                echo "  ✅ Certificate format is valid"
                
                # Get certificate details
                local cert_subject=$(openssl x509 -in "$ssl_dir/milou.crt" -noout -subject 2>/dev/null | sed 's/subject=//')
                local cert_expiry=$(openssl x509 -in "$ssl_dir/milou.crt" -noout -dates 2>/dev/null | grep "notAfter" | cut -d'=' -f2)
                
                echo "     Subject: $cert_subject"
                echo "     Expires: $cert_expiry"
            else
                echo "  ❌ Certificate format is invalid"
            fi
        else
            echo "  ❌ SSL certificates missing"
            echo "     💡 Generate with: ./milou.sh ssl --generate"
        fi
    else
        echo "  ❌ SSL directory not found: $ssl_dir"
    fi
    echo
    
    # Quick connectivity test
    echo -e "${BOLD}🔌 Connectivity Test:${NC}"
    if [[ $ports_in_use -gt 0 ]]; then
        # Test HTTP
        local http_status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost" 2>/dev/null || echo "000")
        if [[ "$http_status" =~ ^[23] ]]; then
            echo "  ✅ HTTP (port 80): $http_status"
        else
            echo "  ⚠️  HTTP (port 80): $http_status"
        fi
        
        # Test HTTPS (if available)
        if netstat -tlnp 2>/dev/null | grep -q ":443 "; then
            local https_status=$(curl -s -k -o /dev/null -w "%{http_code}" "https://localhost" 2>/dev/null || echo "000")
            if [[ "$https_status" =~ ^[23] ]]; then
                echo "  ✅ HTTPS (port 443): $https_status"
            else
                echo "  ⚠️  HTTPS (port 443): $https_status"
            fi
        fi
    else
        echo "  ⚠️  No services appear to be running"
    fi
    echo
    
    # Recommendations
    echo -e "${BOLD}💡 Recommendations:${NC}"
    
    if [[ ! -f "${SCRIPT_DIR}/.env" ]]; then
        echo "  1. Run initial setup: ./milou.sh setup"
    elif [[ $running_count -eq 0 ]]; then
        echo "  1. Start services: ./milou.sh start"
        echo "  2. Check logs: ./milou.sh logs"
    elif [[ $running_count -lt $total_count ]]; then
        echo "  1. Check service logs: ./milou.sh logs"
        echo "  2. Restart services: ./milou.sh restart"
    else
        echo "  1. All services appear to be running ✅"
        echo "  2. Access web interface using displayed URL"
    fi
    
    if command -v docker >/dev/null 2>&1 && ! docker info >/dev/null 2>&1; then
        echo "  🚨 Fix Docker daemon access first"
    fi
    
    echo
    milou_log "SUCCESS" "✅ Diagnosis complete"
    
    return 0
}

# Cleanup test files command handler (DEPRECATED - use uninstall instead)
handle_cleanup_test_files() {
    milou_log "WARN" "⚠️  The 'cleanup-test-files' command is deprecated"
    milou_log "INFO" "💡 Use 'cleanup' or 'uninstall' commands instead:"
    echo "  • './milou.sh cleanup all' - Clean temporary files and unused resources"
    echo "  • './milou.sh uninstall --keep-config' - Remove everything except config"
    echo "  • './milou.sh uninstall' - Complete removal"
    echo ""
    echo "See './milou.sh cleanup --help' or './milou.sh uninstall --help' for details"
    return 1
}

# Install dependencies command handler  
handle_install_deps() {
    milou_log "INFO" "📦 Installing system dependencies..."
    
    # Parse command-specific options
    local auto_install="true"
    local enable_firewall="false"
    local skip_confirmation="false"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --manual|--no-auto)
                auto_install="false"
                shift
                ;;
            --firewall)
                enable_firewall="true"
                shift
                ;;
            --skip-confirmation)
                skip_confirmation="true"
                shift
                ;;
            --help|-h)
                echo "Install dependencies usage:"
                echo "  ./milou.sh install-deps [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --manual          Show manual installation instructions"
                echo "  --firewall        Configure basic firewall rules"
                echo "  --skip-confirmation  Skip confirmation prompts"
                echo "  --help            Show this help"
                return 0
                ;;
            *)
                # Ignore other flags like --verbose (handled by main script)
                shift
                ;;
        esac
    done
    
    if command -v install_prerequisites >/dev/null 2>&1; then
        # Temporarily disable strict error handling for prerequisites installation
        set +e
        install_prerequisites "$auto_install" "$enable_firewall" "$skip_confirmation"
        local exit_code=$?
        set -e
        return $exit_code
    elif command -v install_system_dependencies >/dev/null 2>&1; then
        install_system_dependencies "$auto_install" "$enable_firewall" "$skip_confirmation"
        return $?
    else
        milou_log "ERROR" "Install dependencies function not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize dependency installation"
        return 1
    fi
}

# Build local images command handler  
handle_build_images() {
    milou_log "INFO" "🔨 Building Docker images locally for development..."
    
    # Get script directory to find the build script
    local script_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    local build_script="${script_dir}/scripts/dev/build-local-images.sh"
    
    if [[ ! -f "$build_script" ]]; then
    milou_log "ERROR" "Build script not found: $build_script"
    milou_log "INFO" "Expected location: scripts/dev/build-local-images.sh"
        return 1
    fi
    
    # Make sure it's executable
    chmod +x "$build_script"
    
    # Execute the build script with all arguments
    milou_log "DEBUG" "Executing: $build_script $*"
    exec "$build_script" "$@"
}

# Admin management command handlers
handle_admin() {
    local subcommand="${1:-}"
    
    case "$subcommand" in
        credentials|creds|show)
            handle_admin_credentials "${@:2}"
            ;;
        reset|reset-password)
            handle_admin_reset "${@:2}"
            ;;
        help|--help|-h)
            show_admin_help
            ;;
        "")
    milou_log "ERROR" "Admin subcommand is required"
            show_admin_help
            return 1
            ;;
        *)
    milou_log "ERROR" "Unknown admin subcommand: $subcommand"
            show_admin_help
            return 1
            ;;
    esac
}

show_admin_help() {
    echo "Admin Management Commands"
    echo "========================="
    echo ""
    echo "Usage: ./milou.sh admin <subcommand> [options]"
    echo ""
    echo "Subcommands:"
    echo "  credentials, creds, show  Display current admin credentials"
    echo "  reset, reset-password     Reset admin password and force change"
    echo "  help                      Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./milou.sh admin credentials      # Show current admin login info"
    echo "  ./milou.sh admin reset           # Generate new password & force change"
    echo "  ./milou.sh admin help            # Show detailed help"
    echo ""
    echo "Security Notes:"
    echo "  • Admin credentials provide full system access"
    echo "  • After reset, users must change password on first login"
    echo "  • Credentials are securely stored in the environment file"
}

handle_admin_credentials() {
    milou_log "INFO" "🔐 Displaying admin credentials..."
    
    local env_file="${SCRIPT_DIR}/.env"
    if [[ ! -f "$env_file" ]]; then
    milou_log "ERROR" "Environment file not found: $env_file"
    milou_log "INFO" "Run './milou.sh setup' to create configuration"
        return 1
    fi
    
    local admin_email admin_password
    admin_email=$(grep "^ADMIN_EMAIL=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "")
    admin_password=$(grep "^ADMIN_PASSWORD=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "")
    
    if [[ -n "$admin_email" && -n "$admin_password" ]]; then
        # Check if password has been changed by looking for requirePasswordChange in database
        local password_changed="false"
        if command -v milou_docker_status >/dev/null 2>&1 && milou_docker_status "false" >/dev/null 2>&1; then
            # Services are running, check database
            local db_user db_name
            db_user=$(grep "^DB_USER=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//') 
            db_name=$(grep "^DB_NAME=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
            db_user="${db_user:-milou}"
            db_name="${db_name:-milou}"
            
            local require_change
            require_change=$(docker exec milou-database psql -U "$db_user" -d "$db_name" -t -c "SELECT \"requirePasswordChange\" FROM users WHERE email = '$admin_email';" 2>/dev/null | tr -d ' \n' || echo "")
            
            if [[ "$require_change" == "f" ]]; then
                password_changed="true"
            fi
        fi
        
        echo
    milou_log "SUCCESS" "🔐 ADMIN CREDENTIALS"
        echo "=================================================================="
        echo "  📧 Email:    $admin_email"
        
        if [[ "$password_changed" == "true" ]]; then
            echo "  🔑 Password: *** (changed by user - no longer visible) ***"
            echo "=================================================================="
            echo
    milou_log "INFO" "ℹ️  The admin password has been changed by the user"
    milou_log "INFO" "   • The original password is no longer valid"
    milou_log "INFO" "   • Use './milou.sh admin reset' if you've lost access"
        else
            echo "  🔑 Password: $admin_password"
            echo "=================================================================="
            echo
    milou_log "WARN" "⚠️  These credentials provide full system access"
    milou_log "WARN" "   • Keep them secure and change them after first login"
    milou_log "WARN" "   • Use './milou.sh admin reset' to generate a new password"
        fi
    else
    milou_log "ERROR" "Admin credentials not found in configuration"
    milou_log "INFO" "Run './milou.sh setup' to configure admin credentials"
        return 1
    fi
}

handle_admin_reset() {
    milou_log "INFO" "🔄 Resetting admin credentials..."
    
    local env_file="${SCRIPT_DIR}/.env"
    if [[ ! -f "$env_file" ]]; then
    milou_log "ERROR" "Environment file not found: $env_file"
    milou_log "INFO" "Run './milou.sh setup' to create configuration"
        return 1
    fi
    
    # Check if services are running
    if ! command -v milou_docker_status >/dev/null 2>&1 || ! milou_docker_status "false" >/dev/null 2>&1; then
    milou_log "ERROR" "Docker services are not running"
    milou_log "INFO" "💡 Start services first: ./milou.sh start"
        return 1
    fi
    
    # Load configuration generation module
    if ! command -v generate_secure_random >/dev/null 2>&1; then
    milou_log "ERROR" "Configuration generation functions not available"
        return 1
    fi
    
    # Generate new admin password
    local new_password
    new_password=$(generate_secure_random 16 "safe")
    
    # Get current admin email
    local admin_email
    admin_email=$(grep "^ADMIN_EMAIL=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "admin@localhost")
    
    milou_log "INFO" "📧 Resetting password for admin user: $admin_email"
    
    # Update the database with the new password and force password change
    milou_log "INFO" "🔄 Updating database with new credentials..."
    if reset_admin_in_database "$admin_email" "$new_password"; then
    milou_log "SUCCESS" "✅ Database updated successfully"
        
        # Update the environment file
        if command -v update_env_variable >/dev/null 2>&1; then
            update_env_variable "$env_file" "ADMIN_PASSWORD" "$new_password"
        else
            # Fallback method using sed
            sed -i "s/^ADMIN_PASSWORD=.*/ADMIN_PASSWORD=$new_password/" "$env_file"
        fi
        
        echo
    milou_log "SUCCESS" "🔐 ADMIN PASSWORD RESET COMPLETED"
        echo "=================================================================="
        echo "  📧 Email:    $admin_email"
        echo "  🔑 Password: $new_password"
        echo "=================================================================="
        echo
    milou_log "WARN" "⚠️  IMPORTANT SECURITY NOTICE:"
    milou_log "WARN" "   • Please save these credentials in a secure location"
    milou_log "WARN" "   • User will be forced to change password on first login"
    milou_log "WARN" "   • The old password is no longer valid"
        echo
    milou_log "INFO" "✅ Ready to use! The admin user can now log in with:"
    milou_log "INFO" "   • Email: $admin_email"
    milou_log "INFO" "   • Password: $new_password"
    milou_log "INFO" "   • They will be prompted to change the password on first login"
    else
    milou_log "ERROR" "❌ Failed to update database"
    milou_log "INFO" "💡 Try restarting services and running the command again"
        return 1
    fi
}

# Function to reset admin password in the database
reset_admin_in_database() {
    local admin_email="$1"
    local new_password="$2"
    
    if [[ -z "$admin_email" || -z "$new_password" ]]; then
    milou_log "ERROR" "Admin email and password are required"
        return 1
    fi
    
    # Get database credentials from environment
    local db_user db_name
    db_user=$(grep "^DB_USER=" "${SCRIPT_DIR}/.env" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//') 
    db_name=$(grep "^DB_NAME=" "${SCRIPT_DIR}/.env" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    
    # Default values if not found
    db_user="${db_user:-milou}"
    db_name="${db_name:-milou}"
    
    milou_log "DEBUG" "Using database: $db_name, user: $db_user"
    
    # Generate bcrypt hash for the new password using a safer approach
    local password_hash
    if ! password_hash=$(docker exec milou-backend node -p "
        const bcrypt = require('bcrypt');
        const password = process.argv[1];
        bcrypt.hashSync(password, 10);
    " "$new_password" 2>/dev/null); then
    milou_log "ERROR" "Failed to generate password hash"
        return 1
    fi
    
    milou_log "DEBUG" "Generated password hash: ${password_hash:0:20}..."
    
    # Create a temporary SQL file to avoid quoting issues
    local temp_sql="/tmp/reset_admin_$$.sql"
    cat > "$temp_sql" << EOF
UPDATE users 
SET password = '$password_hash', 
    "requirePasswordChange" = true,
    "updatedAt" = NOW()
WHERE email = '$admin_email';
EOF
    
    # Copy SQL file to container and execute
    if docker cp "$temp_sql" milou-database:/tmp/reset_admin.sql && \
       docker exec milou-database psql -U "$db_user" -d "$db_name" -f /tmp/reset_admin.sql >/dev/null 2>&1; then
        
        # Clean up
        rm -f "$temp_sql"
        docker exec milou-database rm -f /tmp/reset_admin.sql
        
    milou_log "DEBUG" "Password updated in database for user: $admin_email"
        
        # Verify the update worked
        local updated_count
        updated_count=$(docker exec milou-database psql -U "$db_user" -d "$db_name" -t -c "SELECT COUNT(*) FROM users WHERE email = '$admin_email' AND \"requirePasswordChange\" = true;" | tr -d ' \n')
        
        if [[ "$updated_count" == "1" ]]; then
    milou_log "DEBUG" "Verified: requirePasswordChange is set for $admin_email"
            return 0
        else
    milou_log "ERROR" "Update verification failed"
            return 1
        fi
    else
    milou_log "ERROR" "Failed to update password in database"
        rm -f "$temp_sql"
        return 1
    fi
}

# Export all functions
export -f handle_config handle_validate handle_backup handle_restore
export -f handle_update handle_ssl handle_cleanup handle_uninstall handle_debug_images
export -f handle_install_deps handle_diagnose handle_cleanup_test_files handle_build_images
export -f handle_admin handle_admin_credentials handle_admin_reset reset_admin_in_database show_admin_help
