#!/bin/bash

# =============================================================================
# System Management Command Handlers for Milou CLI
# Extracted from milou.sh to improve maintainability
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Ensure system modules are loaded (using centralized loader)
# Modules are loaded centrally by milou_load_command_modules() in main script

# Configuration display command handler
handle_config() {
    log "INFO" "📋 Displaying current configuration..."
    
    # Load required modules
    
    if command -v show_config >/dev/null 2>&1; then
        show_config "$@"
    elif command -v show_current_configuration >/dev/null 2>&1; then
        show_current_configuration "$@"
    else
        log "ERROR" "Configuration display function not available"
        log "DEBUG" "Available functions: $(compgen -A function | grep -E '(config|show)' | head -5 | tr '\n' ' ')"
        return 1
    fi
}

# Configuration validation command handler
handle_validate() {
    log "INFO" "🔍 Validating configuration and environment..."
    
    # Load required modules
    
    if command -v validate_configuration >/dev/null 2>&1; then
        validate_configuration "$@"
    elif command -v validate_config >/dev/null 2>&1; then
        validate_config "$@"
    elif command -v validate_milou_configuration >/dev/null 2>&1; then
        validate_milou_configuration "$@"
    else
        log "ERROR" "Configuration validation function not available"
        log "DEBUG" "Available functions: $(compgen -A function | grep -E '(validate|config)' | head -5 | tr '\n' ' ')"
        return 1
    fi
}

# Backup command handler
handle_backup() {
    log "INFO" "💾 Creating system backup..."
    
    # Load required modules
    
    if command -v backup_config >/dev/null 2>&1; then
        backup_config "$@"
    elif command -v create_system_backup >/dev/null 2>&1; then
        create_system_backup "$@"
    else
        log "ERROR" "Backup function not available"
        log "DEBUG" "Available functions: $(compgen -A function | grep -E '(backup|create)' | head -5 | tr '\n' ' ')"
        return 1
    fi
}

# Restore command handler
handle_restore() {
    local backup_file="${1:-}"
    
    if [[ -z "$backup_file" ]]; then
        log "ERROR" "Backup file is required for restore"
        log "INFO" "Usage: ./milou.sh restore <backup_file>"
        return 1
    fi
    
    log "INFO" "📁 Restoring from backup: $backup_file"
    
    # Load required modules
    
    if command -v restore_config >/dev/null 2>&1; then
        restore_config "$backup_file"
    elif command -v restore_from_backup >/dev/null 2>&1; then
        restore_from_backup "$backup_file"
    else
        log "ERROR" "Restore function not available"
        log "DEBUG" "Available functions: $(compgen -A function | grep -E '(restore|backup)' | head -5 | tr '\n' ' ')"
        return 1
    fi
}

# Update command handler
handle_update() {
    log "INFO" "🔄 Updating to latest version..."
    
    # Load required modules
    
    if command -v update_milou_system >/dev/null 2>&1; then
        update_milou_system "$@"
    elif command -v update_system >/dev/null 2>&1; then
        update_system "$@"
    else
        log "ERROR" "Update function not available"
        log "DEBUG" "Available functions: $(compgen -A function | grep -E '(update|milou)' | head -5 | tr '\n' ' ')"
        return 1
    fi
}

# SSL management command handler
handle_ssl() {
    log "INFO" "🔒 Managing SSL certificates..."
    
    # Parse command-line options and delegate to the enhanced SSL system
    local domain="${DOMAIN:-${SERVER_NAME:-localhost}}"
    local ssl_path="${SSL_PATH:-./ssl}"
    local restart_nginx=false
    
    # Parse basic options
    local action="${1:-}"
    if [[ $# -gt 0 ]]; then
        shift
    fi
    
    # Extract domain and nginx restart flags if present
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --domain|--domain=*)
                if [[ "$1" == *"="* ]]; then
                    domain="${1#*=}"
                else
                    domain="${2:-}"
                    shift
                fi
                shift
                ;;
            --restart-nginx)
                restart_nginx=true
                shift
                ;;
            *)
                # Keep other arguments for SSL module
                break
                ;;
        esac
    done
    
    # Update environment configuration if domain changed
    if [[ "$domain" != "${SERVER_NAME:-localhost}" ]]; then
        log "INFO" "📝 Updating configuration for domain: $domain"
        update_domain_configuration "$domain" "$ssl_path"
    fi
    
    # Delegate to enhanced SSL management system
    if command -v setup_ssl_interactive_enhanced >/dev/null 2>&1; then
        setup_ssl_interactive_enhanced "$action" "$ssl_path" "$domain" "$restart_nginx" "$@"
    else
        # Fallback to existing SSL functions
        case "$action" in
            setup|generate|create)
                if command -v setup_ssl_interactive >/dev/null 2>&1; then
                    setup_ssl_interactive "$ssl_path" "$domain"
                    if [[ "$restart_nginx" == true ]]; then
                        restart_nginx_container
                    fi
                else
                    log "ERROR" "SSL setup function not available"
                    return 1
                fi
                ;;
            status|info|show)
                # Show status from nginx container (renamed from status-container)
                if command -v show_nginx_certificate_status >/dev/null 2>&1; then
                    show_nginx_certificate_status "$domain"
                else
                    log "ERROR" "Nginx certificate status function not available"
                    return 1
                fi
                ;;
            backup)
                # Backup directly from nginx container (simplified - only container backup)
                if command -v backup_nginx_ssl_certificates >/dev/null 2>&1; then
                    backup_nginx_ssl_certificates "./ssl_backups"
                else
                    log "ERROR" "Nginx SSL backup function not available"
                    return 1
                fi
                ;;
            inject)
                # Enhanced inject command - can accept cert file directly as argument
                if command -v inject_ssl_certificates_enhanced >/dev/null 2>&1; then
                    inject_ssl_certificates_enhanced "$ssl_path" "$domain" "$@"
                elif command -v inject_ssl_certificates >/dev/null 2>&1; then
                    log "INFO" "💉 Injecting SSL certificates into nginx container..."
                    inject_ssl_certificates "$ssl_path" "$domain" true
                else
                    log "ERROR" "SSL injection function not available"
                    return 1
                fi
                ;;
            validate)
                # Validate certificates
                if command -v ssl_validate_enhanced >/dev/null 2>&1; then
                    ssl_validate_enhanced "$ssl_path" "$domain"
                elif command -v validate_ssl_certificates >/dev/null 2>&1; then
                    validate_ssl_certificates "$ssl_path/milou.crt" "$ssl_path/milou.key" "$domain"
                else
                    log "ERROR" "SSL validation function not available"
                    return 1
                fi
                ;;
            restart)
                # Restart nginx
                restart_nginx_container
                ;;
            help|--help|-h)
                # Show help
                if command -v ssl_show_help >/dev/null 2>&1; then
                    ssl_show_help
                else
                    echo "SSL Management Commands - see detailed help with ssl help"
                fi
                ;;
            *)
                log "ERROR" "Unknown SSL command: $action"
                log "INFO" "Available commands: setup, status, backup, inject, validate, restart, help"
                log "INFO" "Use './milou.sh ssl help' for detailed information"
                return 1
                ;;
        esac
    fi
}

# Update domain configuration in environment files
update_domain_configuration() {
    local new_domain="$1"
    local ssl_path="$2"
    local env_file="${SCRIPT_DIR}/.env"
    
    if [[ ! -f "$env_file" ]]; then
        log "WARN" "⚠️  Environment file not found: $env_file"
        return 1
    fi
    
    log "INFO" "📝 Updating domain configuration..."
    
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
    
    log "SUCCESS" "✅ Domain configuration updated to: $new_domain"
    log "INFO" "  Updated variables: SERVER_NAME, DOMAIN, CORS_ORIGIN, API_URL"
    
    # Update exported environment variables for current session
    export SERVER_NAME="$new_domain"
    export DOMAIN="$new_domain"
    export CORS_ORIGIN="https://$new_domain"
    export API_URL="https://$new_domain/api"
    export API_BASE_URL="https://$new_domain/api"
}

# Restart nginx container to apply SSL changes
restart_nginx_container() {
    log "INFO" "🔄 Restarting nginx container to apply SSL changes..."
    
    # Check if nginx container is running
    if ! docker ps --format "{{.Names}}" | grep -q "milou-nginx"; then
        log "WARN" "⚠️  Nginx container is not running, starting services..."
        if command -v start_services >/dev/null 2>&1; then
            start_services
            return $?
        else
            log "ERROR" "❌ Cannot start services - start function not available"
            return 1
        fi
    fi
    
    # Get the compose file
    local compose_file="${SCRIPT_DIR}/static/docker-compose.yml"
    if [[ ! -f "$compose_file" ]]; then
        compose_file="./static/docker-compose.yml"
    fi
    
    if [[ ! -f "$compose_file" ]]; then
        log "ERROR" "❌ Docker compose file not found"
        return 1
    fi
    
    # Restart nginx container
    log "INFO" "🔄 Restarting nginx container..."
    if docker compose -f "$compose_file" restart nginx; then
        log "SUCCESS" "✅ Nginx container restarted successfully"
        
        # Wait a moment for nginx to start
        sleep 2
        
        # Check nginx health
        if docker ps --format "{{.Names}}\t{{.Status}}" | grep "milou-nginx" | grep -q "healthy\|Up"; then
            log "SUCCESS" "✅ Nginx is healthy and serving requests"
            return 0
        else
            log "WARN" "⚠️  Nginx restarted but health check pending"
            return 0
        fi
    else
        log "ERROR" "❌ Failed to restart nginx container"
        return 1
    fi
}

# Cleanup command handler
handle_cleanup() {
    local cleanup_type="${1:-docker}"
    
    case "$cleanup_type" in
        docker|--docker)
            log "INFO" "🧹 Cleaning up Docker resources..."
            if command -v cleanup_docker_resources >/dev/null 2>&1; then
                cleanup_docker_resources
            else
                log "ERROR" "Docker cleanup function not available"
                return 1
            fi
            ;;
        system|--system)
            log "INFO" "🧹 Cleaning up system resources..."
            if command -v cleanup_system_resources >/dev/null 2>&1; then
                cleanup_system_resources
            else
                log "ERROR" "System cleanup function not available"
                return 1
            fi
            ;;
        all|--all)
            log "INFO" "🧹 Performing complete system cleanup..."
            if command -v cleanup_docker_resources >/dev/null 2>&1; then
                cleanup_docker_resources
            fi
            if command -v cleanup_system_resources >/dev/null 2>&1; then
                cleanup_system_resources
            fi
            ;;
        complete|--complete|uninstall|--uninstall)
            log "INFO" "🗑️ Complete Milou uninstallation..."
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
            log "WARN" "Unknown cleanup type: $cleanup_type, defaulting to docker cleanup"
            if command -v cleanup_docker_resources >/dev/null 2>&1; then
                cleanup_docker_resources
            else
                log "ERROR" "Docker cleanup function not available"
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
        log "INFO" "Loading uninstall module..."
        if command -v milou_load_module >/dev/null 2>&1; then
            milou_load_module "docker/uninstall" || {
                log "ERROR" "Failed to load uninstall module"
                return 1
            }
        else
            log "ERROR" "Module loader not available"
            return 1
        fi
    fi
    
    # Call the enhanced complete cleanup function with proper parameters
    if command -v complete_milou_uninstall >/dev/null 2>&1; then
        complete_milou_uninstall "$include_images" "$include_volumes" "$include_config" "$include_ssl" "$include_logs" "$aggressive_cleanup"
        local exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            log "SUCCESS" "🎉 Uninstall completed successfully"
        else
            log "ERROR" "Uninstall completed with errors (exit code: $exit_code)"
        fi
        
        return $exit_code
    elif command -v complete_cleanup_milou_resources >/dev/null 2>&1; then
        log "WARN" "Using legacy cleanup function (limited options)"
        complete_cleanup_milou_resources
        return $?
    else
        log "ERROR" "Uninstall function not available"
        log "DEBUG" "Available functions: $(compgen -A function | grep -E '(uninstall|cleanup)' | head -5 | tr '\n' ' ')"
        return 1
    fi
}

# Debug images command handler
handle_debug_images() {
    log "INFO" "🔧 Debugging Docker image availability..."
    
    if command -v debug_docker_images >/dev/null 2>&1; then
        debug_docker_images "$@"
    else
        log "ERROR" "Debug images function not available"
        return 1
    fi
}

# System diagnosis command handler
handle_diagnose() {
    log "INFO" "🩺 Running comprehensive system diagnosis..."
    
    if command -v run_system_diagnosis >/dev/null 2>&1; then
        run_system_diagnosis "$@"
    else
        log "ERROR" "System diagnosis function not available"
        return 1
    fi
}

# Cleanup test files command handler (DEPRECATED - use uninstall instead)
handle_cleanup_test_files() {
    log "WARN" "⚠️  The 'cleanup-test-files' command is deprecated"
    log "INFO" "💡 Use 'cleanup' or 'uninstall' commands instead:"
    echo "  • './milou.sh cleanup all' - Clean temporary files and unused resources"
    echo "  • './milou.sh uninstall --keep-config' - Remove everything except config"
    echo "  • './milou.sh uninstall' - Complete removal"
    echo ""
    echo "See './milou.sh cleanup --help' or './milou.sh uninstall --help' for details"
    return 1
}

# Install dependencies command handler  
handle_install_deps() {
    log "INFO" "📦 Installing system dependencies..."
    
    # Ensure system modules are loaded
    
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
    
    log "DEBUG" "Checking for install_prerequisites function..."
    if command -v install_prerequisites >/dev/null 2>&1; then
        log "DEBUG" "Found install_prerequisites, calling with params: auto_install=$auto_install, enable_firewall=$enable_firewall, skip_confirmation=$skip_confirmation"
        
        # Temporarily disable strict error handling for prerequisites installation
        set +e
        install_prerequisites "$auto_install" "$enable_firewall" "$skip_confirmation"
        local exit_code=$?
        set -e
        
        log "DEBUG" "install_prerequisites returned with exit code: $exit_code"
        return $exit_code
    elif command -v install_system_dependencies >/dev/null 2>&1; then
        log "DEBUG" "Found install_system_dependencies, calling with params: auto_install=$auto_install, enable_firewall=$enable_firewall, skip_confirmation=$skip_confirmation"
        install_system_dependencies "$auto_install" "$enable_firewall" "$skip_confirmation"
        local exit_code=$?
        log "DEBUG" "install_system_dependencies returned with exit code: $exit_code"
        return $exit_code
    else
        log "ERROR" "Install dependencies function not available"
        log "DEBUG" "Available functions: $(compgen -A function | grep -E '(install|deps|prerequisites)' | head -5 | tr '\n' ' ')"
        return 1
    fi
}

# Build local images command handler  
handle_build_images() {
    log "INFO" "🔨 Building Docker images locally for development..."
    
    # Get script directory to find the build script
    local script_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    local build_script="${script_dir}/scripts/dev/build-local-images.sh"
    
    if [[ ! -f "$build_script" ]]; then
        log "ERROR" "Build script not found: $build_script"
        log "INFO" "Expected location: scripts/dev/build-local-images.sh"
        return 1
    fi
    
    # Make sure it's executable
    chmod +x "$build_script"
    
    # Execute the build script with all arguments
    log "DEBUG" "Executing: $build_script $*"
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
            log "ERROR" "Admin subcommand is required"
            show_admin_help
            return 1
            ;;
        *)
            log "ERROR" "Unknown admin subcommand: $subcommand"
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
    log "INFO" "🔐 Displaying admin credentials..."
    
    local env_file="${SCRIPT_DIR}/.env"
    if [[ ! -f "$env_file" ]]; then
        log "ERROR" "Environment file not found: $env_file"
        log "INFO" "Run './milou.sh setup' to create configuration"
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
        log "SUCCESS" "🔐 ADMIN CREDENTIALS"
        echo "=================================================================="
        echo "  📧 Email:    $admin_email"
        
        if [[ "$password_changed" == "true" ]]; then
            echo "  🔑 Password: *** (changed by user - no longer visible) ***"
            echo "=================================================================="
            echo
            log "INFO" "ℹ️  The admin password has been changed by the user"
            log "INFO" "   • The original password is no longer valid"
            log "INFO" "   • Use './milou.sh admin reset' if you've lost access"
        else
            echo "  🔑 Password: $admin_password"
            echo "=================================================================="
            echo
            log "WARN" "⚠️  These credentials provide full system access"
            log "WARN" "   • Keep them secure and change them after first login"
            log "WARN" "   • Use './milou.sh admin reset' to generate a new password"
        fi
    else
        log "ERROR" "Admin credentials not found in configuration"
        log "INFO" "Run './milou.sh setup' to configure admin credentials"
        return 1
    fi
}

handle_admin_reset() {
    log "INFO" "🔄 Resetting admin credentials..."
    
    local env_file="${SCRIPT_DIR}/.env"
    if [[ ! -f "$env_file" ]]; then
        log "ERROR" "Environment file not found: $env_file"
        log "INFO" "Run './milou.sh setup' to create configuration"
        return 1
    fi
    
    # Check if services are running
    if ! command -v milou_docker_status >/dev/null 2>&1 || ! milou_docker_status "false" >/dev/null 2>&1; then
        log "ERROR" "Docker services are not running"
        log "INFO" "💡 Start services first: ./milou.sh start"
        return 1
    fi
    
    # Load configuration generation module
    if ! command -v generate_secure_random >/dev/null 2>&1; then
        log "ERROR" "Configuration generation functions not available"
        return 1
    fi
    
    # Generate new admin password
    local new_password
    new_password=$(generate_secure_random 16 "safe")
    
    # Get current admin email
    local admin_email
    admin_email=$(grep "^ADMIN_EMAIL=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "admin@localhost")
    
    log "INFO" "📧 Resetting password for admin user: $admin_email"
    
    # Update the database with the new password and force password change
    log "INFO" "🔄 Updating database with new credentials..."
    if reset_admin_in_database "$admin_email" "$new_password"; then
        log "SUCCESS" "✅ Database updated successfully"
        
        # Update the environment file
        if command -v update_env_variable >/dev/null 2>&1; then
            update_env_variable "$env_file" "ADMIN_PASSWORD" "$new_password"
        else
            # Fallback method using sed
            sed -i "s/^ADMIN_PASSWORD=.*/ADMIN_PASSWORD=$new_password/" "$env_file"
        fi
        
        echo
        log "SUCCESS" "🔐 ADMIN PASSWORD RESET COMPLETED"
        echo "=================================================================="
        echo "  📧 Email:    $admin_email"
        echo "  🔑 Password: $new_password"
        echo "=================================================================="
        echo
        log "WARN" "⚠️  IMPORTANT SECURITY NOTICE:"
        log "WARN" "   • Please save these credentials in a secure location"
        log "WARN" "   • User will be forced to change password on first login"
        log "WARN" "   • The old password is no longer valid"
        echo
        log "INFO" "✅ Ready to use! The admin user can now log in with:"
        log "INFO" "   • Email: $admin_email"
        log "INFO" "   • Password: $new_password"
        log "INFO" "   • They will be prompted to change the password on first login"
    else
        log "ERROR" "❌ Failed to update database"
        log "INFO" "💡 Try restarting services and running the command again"
        return 1
    fi
}

# Function to reset admin password in the database
reset_admin_in_database() {
    local admin_email="$1"
    local new_password="$2"
    
    if [[ -z "$admin_email" || -z "$new_password" ]]; then
        log "ERROR" "Admin email and password are required"
        return 1
    fi
    
    # Get database credentials from environment
    local db_user db_name
    db_user=$(grep "^DB_USER=" "${SCRIPT_DIR}/.env" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//') 
    db_name=$(grep "^DB_NAME=" "${SCRIPT_DIR}/.env" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    
    # Default values if not found
    db_user="${db_user:-milou}"
    db_name="${db_name:-milou}"
    
    log "DEBUG" "Using database: $db_name, user: $db_user"
    
    # Generate bcrypt hash for the new password using a safer approach
    local password_hash
    if ! password_hash=$(docker exec milou-backend node -p "
        const bcrypt = require('bcrypt');
        const password = process.argv[1];
        bcrypt.hashSync(password, 10);
    " "$new_password" 2>/dev/null); then
        log "ERROR" "Failed to generate password hash"
        return 1
    fi
    
    log "DEBUG" "Generated password hash: ${password_hash:0:20}..."
    
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
        
        log "DEBUG" "Password updated in database for user: $admin_email"
        
        # Verify the update worked
        local updated_count
        updated_count=$(docker exec milou-database psql -U "$db_user" -d "$db_name" -t -c "SELECT COUNT(*) FROM users WHERE email = '$admin_email' AND \"requirePasswordChange\" = true;" | tr -d ' \n')
        
        if [[ "$updated_count" == "1" ]]; then
            log "DEBUG" "Verified: requirePasswordChange is set for $admin_email"
            return 0
        else
            log "ERROR" "Update verification failed"
            return 1
        fi
    else
        log "ERROR" "Failed to update password in database"
        rm -f "$temp_sql"
        return 1
    fi
}

# Export all functions
export -f handle_config handle_validate handle_backup handle_restore
export -f handle_update handle_ssl handle_cleanup handle_uninstall handle_debug_images
export -f handle_install_deps handle_diagnose handle_cleanup_test_files handle_build_images
export -f handle_admin handle_admin_credentials handle_admin_reset reset_admin_in_database show_admin_help
