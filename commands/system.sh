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
ensure_system_modules() {
    # Use the centralized module loader function
    if command -v milou_load_system_modules >/dev/null 2>&1; then
        milou_load_system_modules
    else
        # Fallback if centralized loader not available
        if command -v milou_log >/dev/null 2>&1; then
            milou_log "WARN" "Centralized module loader not available, loading minimal modules"
        fi
        # Only load essential system modules as fallback
        if command -v milou_load_module >/dev/null 2>&1; then
            milou_load_module "system/configuration" 2>/dev/null || true
            milou_load_module "system/backup" 2>/dev/null || true
            milou_load_module "system/update" 2>/dev/null || true
            milou_load_module "system/ssl" 2>/dev/null || true
            milou_load_module "docker/core" 2>/dev/null || true
        fi
    fi
}

# Configuration display command handler
handle_config() {
    log "INFO" "📋 Displaying current configuration..."
    
    # Load required modules
    ensure_system_modules
    
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
    ensure_system_modules
    
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
    ensure_system_modules
    
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
    ensure_system_modules
    
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
    ensure_system_modules
    
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
    
    # Load required modules
    ensure_system_modules
    
    # Get current environment values for SSL and resolve Docker-compatible path
    local ssl_path_raw="${SSL_CERT_PATH:-./ssl}"
    local domain="${SERVER_NAME:-localhost}"
    
    # Use proper SSL path resolution for Docker compatibility
    local ssl_path
    if command -v get_appropriate_ssl_path >/dev/null 2>&1; then
        ssl_path=$(get_appropriate_ssl_path "$ssl_path_raw" "$(pwd)")
        log "DEBUG" "Resolved SSL path: $ssl_path_raw -> $ssl_path"
    else
        ssl_path="$ssl_path_raw"
        log "WARN" "SSL path resolution function not available, using raw path: $ssl_path"
    fi
    
    # Check if no arguments provided - show status
    if [[ $# -eq 0 ]]; then
        log "INFO" "📋 Current SSL Configuration:"
        log "INFO" "  Domain: $domain"
        log "INFO" "  SSL Path: $ssl_path"
        echo
        
        # Check certificate status
        local cert_file="$ssl_path/milou.crt"
        local key_file="$ssl_path/milou.key"
        
        if [[ -f "$cert_file" && -f "$key_file" ]]; then
            log "INFO" "✅ SSL certificates found"
            if command -v show_certificate_info >/dev/null 2>&1; then
                show_certificate_info "$cert_file" "$domain"
            else
                log "INFO" "  Certificate: $cert_file"
                log "INFO" "  Private Key: $key_file"
                # Basic certificate info
                if command -v openssl >/dev/null 2>&1; then
                    local cert_subject
                    cert_subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed 's/subject=//')
                    local cert_expires
                    cert_expires=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
                    log "INFO" "  Subject: $cert_subject"
                    log "INFO" "  Expires: $cert_expires"
                fi
            fi
        else
            log "ERROR" "❌ SSL certificates not found"
            log "INFO" "Run './milou.sh ssl setup' to generate certificates"
        fi
        return 0
    fi
    
    # Handle different SSL sub-commands
    local action="${1:-setup}"
    shift
    
    case "$action" in
        setup|generate|create)
            if command -v setup_ssl >/dev/null 2>&1; then
                setup_ssl "$ssl_path" "$domain" "$@"
            elif command -v setup_ssl_interactive >/dev/null 2>&1; then
                setup_ssl_interactive "$ssl_path" "$domain" "$@"
            else
                log "ERROR" "SSL setup function not available"
                return 1
            fi
            ;;
        status|info|show)
            # Show detailed certificate status
            if command -v show_certificate_info >/dev/null 2>&1; then
                local cert_file="$ssl_path/milou.crt"
                if [[ -f "$cert_file" ]]; then
                    show_certificate_info "$cert_file" "$domain"
                else
                    log "ERROR" "Certificate file not found: $cert_file"
                    return 1
                fi
            else
                log "ERROR" "Certificate info function not available"
                return 1
            fi
            ;;
        validate|check)
            if command -v validate_ssl_certificates >/dev/null 2>&1; then
                local cert_file="$ssl_path/milou.crt"
                local key_file="$ssl_path/milou.key"
                validate_ssl_certificates "$cert_file" "$key_file" "$domain"
            else
                log "ERROR" "SSL validation function not available"
                return 1
            fi
            ;;
        backup)
            if command -v backup_ssl_certificates >/dev/null 2>&1; then
                backup_ssl_certificates "$ssl_path"
            else
                log "ERROR" "SSL backup function not available"
                return 1
            fi
            ;;
        help|--help|-h)
            echo "SSL management usage:"
            echo "  ./milou.sh ssl [COMMAND]"
            echo ""
            echo "Commands:"
            echo "  setup     Generate or update SSL certificates"
            echo "  status    Show certificate information"
            echo "  validate  Validate existing certificates"
            echo "  backup    Backup current certificates"
            echo "  help      Show this help"
            echo ""
            echo "If no command is provided, shows current SSL status."
            ;;
        *)
            log "ERROR" "Unknown SSL command: $action"
            log "INFO" "Use './milou.sh ssl help' for available commands"
            return 1
            ;;
    esac
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
        --help|-h)
            echo "Cleanup command usage:"
            echo "  ./milou.sh cleanup [docker|system|all]"
            echo ""
            echo "Options:"
            echo "  docker    Clean Docker resources (default)"
            echo "  system    Clean system temporary files"
            echo "  all       Clean everything"
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

# Cleanup test files command handler
handle_cleanup_test_files() {
    log "INFO" "🧹 Cleaning up test configuration files..."
    
    if command -v cleanup_test_configuration_files >/dev/null 2>&1; then
        cleanup_test_configuration_files "$@"
    else
        log "ERROR" "Test cleanup function not available"
        return 1
    fi
}

# Install dependencies command handler  
handle_install_deps() {
    log "INFO" "📦 Installing system dependencies..."
    
    # Ensure system modules are loaded
    ensure_system_modules
    
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

# Export all functions
export -f handle_config handle_validate handle_backup handle_restore
export -f handle_update handle_ssl handle_cleanup handle_debug_images
export -f handle_diagnose handle_cleanup_test_files handle_install_deps ensure_system_modules 