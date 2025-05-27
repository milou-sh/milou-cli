#!/bin/bash

# =============================================================================
# SSL Interactive Setup Module for Milou CLI
# Provides user-friendly certificate setup with multiple options
# =============================================================================

# Module guard to prevent multiple loading
if [[ "${MILOU_SSL_INTERACTIVE_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_SSL_INTERACTIVE_LOADED="true"

# Ensure logging is available
if ! command -v milou_log >/dev/null 2>&1; then
    local script_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
    if [[ -f "${script_dir}/lib/core/logging.sh" ]]; then
        source "${script_dir}/lib/core/logging.sh"
    else
        echo "ERROR: Logging module not available" >&2
        return 1
    fi
fi

# =============================================================================
# Enhanced Interactive SSL Setup
# =============================================================================

# Main interactive SSL setup function
milou_ssl_setup_interactive_enhanced() {
    local action="$1"
    local ssl_path="$2"
    local domain="$3"
    local restart_nginx="$4"
    shift 4
    local remaining_args=("$@")
    
    case "$action" in
        setup|generate|create)
            milou_ssl_setup_wizard "$ssl_path" "$domain" "$restart_nginx" "${remaining_args[@]}"
            ;;
        status|info|show)
            milou_ssl_show_container_status "$domain"
            ;;
        validate|check)
            milou_ssl_validate_enhanced "$ssl_path" "$domain"
            ;;
        backup)
            milou_ssl_backup_container_enhanced
            ;;
        inject)
            milou_ssl_inject_enhanced "$ssl_path" "$domain" "${remaining_args[@]}"
            ;;
        restart|restart-nginx)
            milou_ssl_restart_nginx
            ;;
        help|--help|-h|"")
            milou_ssl_show_help
            ;;
        *)
            milou_log "ERROR" "Unknown SSL command: $action"
            milou_log "INFO" "Available commands: setup, status, backup, inject, validate, restart, help"
            milou_ssl_show_help
            return 1
            ;;
    esac
}

# =============================================================================
# SSL Setup Wizard
# =============================================================================

# Main SSL setup wizard
milou_ssl_setup_wizard() {
    local ssl_path="$1"
    local domain="$2" 
    local restart_nginx="$3"
    shift 3
    local remaining_args=("$@")
    
    milou_log "STEP" "🔒 SSL Certificate Setup Wizard"
    echo
    
    # Resolve SSL path
    ssl_path=$(milou_ssl_get_appropriate_ssl_path "$ssl_path" "$(pwd)")
    mkdir -p "$ssl_path"
    
    # Get domain if not provided
    if [[ -z "$domain" || "$domain" == "localhost" ]]; then
        echo "🌐 Domain Configuration"
        echo "======================"
        echo
        echo "Enter the domain name for your SSL certificate:"
        echo "  • Use 'localhost' for local development"
        echo "  • Use your actual domain (e.g., 'example.com') for production"
        echo
        echo -n "Domain name [localhost]: "
        read -r user_domain
        domain=${user_domain:-localhost}
        echo
    fi
    
    # Check existing certificates
    local cert_file="$ssl_path/milou.crt"
    local key_file="$ssl_path/milou.key"
    
    if [[ -f "$cert_file" && -f "$key_file" ]]; then
        milou_log "INFO" "📋 Existing SSL certificates found"
        echo
        milou_ssl_show_certificate_info "$cert_file" "$domain"
        echo
        
        if milou_ssl_validate_certificates "$ssl_path" "$domain" >/dev/null 2>&1; then
            milou_log "SUCCESS" "✅ Existing certificates are valid for domain: $domain"
            echo
            echo "Do you want to:"
            echo "  1) Keep existing certificates"
            echo "  2) Replace with new certificates"
            echo
            echo -n "Choose option [1]: "
            read -r replace_choice
            
            if [[ "$replace_choice" != "2" ]]; then
                milou_log "INFO" "Keeping existing certificates"
                if [[ "$restart_nginx" == "true" ]]; then
                    milou_ssl_restart_nginx
                fi
                return 0
            fi
        else
            milou_log "WARN" "⚠️  Existing certificates are not valid for domain: $domain"
            echo "The certificates will be replaced automatically."
            echo
        fi
        
        # Backup existing certificates
        milou_log "INFO" "💾 Backing up existing certificates..."
        milou_ssl_backup_certificates "$ssl_path"
        echo
    fi
    
    # Certificate type selection
    milou_ssl_certificate_type_wizard "$ssl_path" "$domain" "$restart_nginx"
}

# Certificate type selection wizard
milou_ssl_certificate_type_wizard() {
    local ssl_path="$1"
    local domain="$2"
    local restart_nginx="$3"
    
    echo "🔐 Certificate Type Selection"
    echo "============================="
    echo
    
    if [[ "$domain" == "localhost" || "$domain" == "127.0.0.1" ]]; then
        milou_log "INFO" "🏠 Local development domain detected"
        milou_log "INFO" "Generating self-signed certificate for localhost..."
        echo
        
        if milou_ssl_generate_localhost_certificate "$ssl_path"; then
            milou_ssl_setup_complete "$ssl_path" "$domain" "$restart_nginx"
            return 0
        else
            milou_log "ERROR" "❌ Failed to generate localhost certificate"
            return 1
        fi
    fi
    
    # Real domain - offer options
    echo "Please choose your certificate type:"
    echo
    echo "  1) 🌟 Let's Encrypt (Free, Trusted)"
    echo "     ✅ Automatically trusted by all browsers"
    echo "     ✅ Free and automatically renewable"
    echo "     ⚠️  Requires domain to point to this server"
    echo "     ⚠️  Needs port 80 accessible from internet"
    echo
    echo "  2) 🔐 Self-Signed Certificate"
    echo "     ✅ Works offline and for development"
    echo "     ✅ No external dependencies"
    echo "     ⚠️  Browsers will show security warnings"
    echo "     ⚠️  Users must manually accept certificate"
    echo
    echo "  3) 📁 Import Existing Certificate"
    echo "     ✅ Use your own CA-signed certificate"
    echo "     ✅ Full control over certificate properties"
    echo "     ⚠️  Must have valid certificate and key files"
    echo
    echo -n "Choose certificate type [1]: "
    read -r cert_choice
    
    case "${cert_choice:-1}" in
        1)
            milou_ssl_setup_letsencrypt "$ssl_path" "$domain" "$restart_nginx"
            ;;
        2)
            milou_ssl_setup_self_signed "$ssl_path" "$domain" "$restart_nginx"
            ;;
        3)
            milou_ssl_setup_import_existing "$ssl_path" "$domain" "$restart_nginx"
            ;;
        *)
            milou_log "ERROR" "Invalid choice: $cert_choice"
            return 1
            ;;
    esac
}

# Let's Encrypt setup wizard
milou_ssl_setup_letsencrypt() {
    local ssl_path="$1"
    local domain="$2"
    local restart_nginx="$3"
    
    echo
    milou_log "INFO" "🌟 Setting up Let's Encrypt certificate"
    echo
    
    # Prerequisites check
    if ! milou_ssl_can_use_letsencrypt; then
        milou_log "ERROR" "❌ Let's Encrypt prerequisites not met"
        milou_log "INFO" "Requirements: certbot installed and root privileges"
        echo
        milou_log "INFO" "Falling back to self-signed certificate..."
        milou_ssl_setup_self_signed "$ssl_path" "$domain" "$restart_nginx"
        return $?
    fi
    
    # Get email for Let's Encrypt
    echo "📧 Email Configuration"
    echo "====================="
    echo "Let's Encrypt requires an email address for notifications"
    echo "This will be used for certificate renewal alerts"
    echo
    echo -n "Email address [admin@$domain]: "
    read -r email
    email=${email:-admin@$domain}
    echo
    
    # Domain validation warning
    echo "⚠️  Domain Validation Requirements"
    echo "=================================="
    echo "Before proceeding, ensure that:"
    echo "  1. Domain '$domain' points to this server's public IP"
    echo "  2. Port 80 is accessible from the internet"
    echo "  3. No firewall is blocking HTTP access"
    echo
    echo -n "Domain is properly configured? [Y/n]: "
    read -r domain_ready
    
    if [[ "${domain_ready,,}" == "n" || "${domain_ready,,}" == "no" ]]; then
        milou_log "INFO" "Please configure your domain and try again"
        milou_log "INFO" "Alternatively, choose option 2 for self-signed certificate"
        return 1
    fi
    
    # Generate Let's Encrypt certificate
    if milou_ssl_generate_letsencrypt_certificate "$ssl_path" "$domain" "$email"; then
        milou_ssl_setup_complete "$ssl_path" "$domain" "$restart_nginx"
        return 0
    else
        milou_log "ERROR" "❌ Let's Encrypt certificate generation failed"
        echo
        milou_log "INFO" "Would you like to use a self-signed certificate instead?"
        echo -n "Use self-signed certificate? [Y/n]: "
        read -r fallback_choice
        
        if [[ "${fallback_choice,,}" != "n" && "${fallback_choice,,}" != "no" ]]; then
            milou_ssl_setup_self_signed "$ssl_path" "$domain" "$restart_nginx"
        else
            return 1
        fi
    fi
}

# Self-signed certificate setup
milou_ssl_setup_self_signed() {
    local ssl_path="$1"
    local domain="$2"
    local restart_nginx="$3"
    
    echo
    milou_log "INFO" "🔐 Setting up self-signed certificate"
    echo
    
    if milou_ssl_generate_production_certificate "$ssl_path" "$domain"; then
        milou_ssl_setup_complete "$ssl_path" "$domain" "$restart_nginx"
        return 0
    else
        milou_log "ERROR" "❌ Failed to generate self-signed certificate"
        return 1
    fi
}

# Import existing certificate setup
milou_ssl_setup_import_existing() {
    local ssl_path="$1"
    local domain="$2"
    local restart_nginx="$3"
    
    echo
    milou_log "INFO" "📁 Importing existing certificate"
    echo
    
    echo "Please provide the paths to your certificate files:"
    echo
    echo -n "Certificate file path (.crt/.pem): "
    read -r cert_source
    
    if [[ ! -f "$cert_source" ]]; then
        milou_log "ERROR" "Certificate file not found: $cert_source"
        return 1
    fi
    
    echo -n "Private key file path (.key): "
    read -r key_source
    
    if [[ ! -f "$key_source" ]]; then
        milou_log "ERROR" "Private key file not found: $key_source"
        return 1
    fi
    
    # Import the certificates
    if milou_ssl_import_user_certificates "$cert_source" "$key_source" "$ssl_path"; then
        milou_ssl_setup_complete "$ssl_path" "$domain" "$restart_nginx"
        return 0
    else
        milou_log "ERROR" "❌ Failed to import certificates"
        return 1
    fi
}

# Setup completion handler
milou_ssl_setup_complete() {
    local ssl_path="$1"
    local domain="$2"
    local restart_nginx="$3"
    
    echo
    milou_log "SUCCESS" "🎉 SSL certificate setup completed!"
    echo
    
    # Show certificate information
    milou_ssl_show_info "$ssl_path"
    
    # Inject certificates if containers are running
    if docker ps --filter "name=milou-nginx" --format "{{.Names}}" | grep -q "milou-nginx"; then
        echo
        milou_log "INFO" "💉 Injecting certificates into nginx container..."
        if milou_ssl_inject_certificates "$ssl_path" "$domain"; then
            milou_log "SUCCESS" "✅ Certificates injected successfully"
        else
            milou_log "WARN" "⚠️  Certificate injection failed"
        fi
    fi
    
    # Restart nginx if requested
    if [[ "$restart_nginx" == "true" ]]; then
        echo
        milou_ssl_restart_nginx
    fi
    
    echo
    milou_log "INFO" "📋 Next steps:"
    milou_log "INFO" "  • Your SSL certificates are ready to use"
    milou_log "INFO" "  • Access your application at: https://$domain"
    milou_log "INFO" "  • Check certificate status: ./milou.sh ssl status"
}

# =============================================================================
# SSL Utility Functions
# =============================================================================

# Get appropriate SSL path
milou_ssl_get_appropriate_ssl_path() {
    local ssl_path="$1"
    local current_dir="$2"
    
    # If no path provided, use default
    if [[ -z "$ssl_path" || "$ssl_path" == "./ssl" ]]; then
        # If we're in milou-cli directory, use static/ssl
        if [[ "$(basename "$current_dir")" == "milou-cli" ]]; then
            echo "$current_dir/static/ssl"
        else
            echo "$current_dir/ssl"
        fi
    else
        echo "$ssl_path"
    fi
}

# Enhanced SSL validation
milou_ssl_validate_enhanced() {
    local ssl_path="$1"
    local domain="$2"
    
    milou_log "INFO" "🔍 Enhanced SSL validation"
    echo
    
    local validation_failed=false
    
    # Basic file validation
    if milou_ssl_validate_certificates "$ssl_path" "$domain" "false" "false"; then
        milou_log "SUCCESS" "✅ SSL certificate files are valid"
    else
        milou_log "ERROR" "❌ SSL certificate validation failed"
        validation_failed=true
    fi
    
    # Domain validation if provided
    if [[ -n "$domain" && "$domain" != "localhost" ]]; then
        local cert_file="$ssl_path/milou.crt"
        if [[ -f "$cert_file" ]]; then
            if milou_ssl_validate_certificate_domain "$cert_file" "$domain"; then
                milou_log "SUCCESS" "✅ Certificate matches domain: $domain"
            else
                milou_log "WARN" "⚠️  Certificate does not match domain: $domain"
            fi
        fi
    fi
    
    # Container accessibility check
    if docker ps --filter "name=milou-nginx" --format "{{.Names}}" | grep -q "milou-nginx"; then
        if docker exec milou-nginx test -f /etc/ssl/milou.crt && \
           docker exec milou-nginx test -f /etc/ssl/milou.key; then
            milou_log "SUCCESS" "✅ Certificates accessible in nginx container"
        else
            milou_log "WARN" "⚠️  Certificates not found in nginx container"
            milou_log "INFO" "Run: ./milou.sh ssl inject"
        fi
    else
        milou_log "INFO" "ℹ️  Nginx container not running - cannot check container accessibility"
    fi
    
    if [[ "$validation_failed" == "true" ]]; then
        return 1
    else
        return 0
    fi
}

# Enhanced container backup
milou_ssl_backup_container_enhanced() {
    local backup_dir="${1:-./ssl_backups}"
    
    milou_log "INFO" "💾 Enhanced container SSL backup"
    echo
    
    if ! docker ps --filter "name=milou-nginx" --format "{{.Names}}" | grep -q "milou-nginx"; then
        milou_log "ERROR" "❌ Nginx container not running"
        return 1
    fi
    
    # Create timestamped backup
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="nginx_ssl_backup_$timestamp"
    
    if milou_ssl_backup_nginx_ssl_certificates "$backup_dir" "$backup_name"; then
        milou_log "SUCCESS" "✅ Container SSL backup completed"
        return 0
    else
        milou_log "ERROR" "❌ Container SSL backup failed"
        return 1
    fi
}

# Enhanced certificate injection
milou_ssl_inject_enhanced() {
    local ssl_path="$1"
    local domain="$2"
    shift 2
    local additional_args=("$@")
    
    milou_log "INFO" "💉 Enhanced SSL certificate injection"
    echo
    
    # Check if cert file was provided directly as argument
    if [[ ${#additional_args[@]} -gt 0 && -f "${additional_args[0]}" ]]; then
        local cert_file="${additional_args[0]}"
        local key_file="${additional_args[1]:-${cert_file%.*}.key}"
        
        milou_log "INFO" "Using provided certificate files:"
        milou_log "INFO" "  Certificate: $cert_file"
        milou_log "INFO" "  Private key: $key_file"
        
        if milou_ssl_inject_certificates_direct "$cert_file" "$key_file" "$domain"; then
            milou_log "SUCCESS" "✅ Direct certificate injection successful"
            return 0
        else
            milou_log "ERROR" "❌ Direct certificate injection failed"
            return 1
        fi
    else
        # Standard injection from SSL path
        if milou_ssl_inject_certificates "$ssl_path" "$domain"; then
            milou_log "SUCCESS" "✅ SSL certificate injection successful"
            return 0
        else
            milou_log "ERROR" "❌ SSL certificate injection failed"
            return 1
        fi
    fi
}

# Show container status
milou_ssl_show_container_status() {
    local domain="${1:-}"
    
    milou_log "INFO" "📊 Nginx Container SSL Status"
    echo
    
    # Check if nginx container is running
    if ! docker ps --filter "name=milou-nginx" --format "{{.Names}}" | grep -q "milou-nginx"; then
        milou_log "ERROR" "❌ Nginx container (milou-nginx) is not running"
        milou_log "INFO" "Start services: ./milou.sh start"
        return 1
    fi
    
    milou_log "SUCCESS" "✅ Nginx container is running"
    echo
    
    # Check if SSL certificates exist in container
    if docker exec milou-nginx test -f /etc/ssl/milou.crt; then
        milou_log "SUCCESS" "✅ SSL certificate found in container"
        
        # Get certificate information from container
        local cert_subject cert_expires cert_issuer
        cert_subject=$(docker exec milou-nginx openssl x509 -in /etc/ssl/milou.crt -noout -subject 2>/dev/null | sed 's/subject=//' || echo "Unknown")
        cert_expires=$(docker exec milou-nginx openssl x509 -in /etc/ssl/milou.crt -noout -enddate 2>/dev/null | sed 's/notAfter=//' || echo "Unknown")
        cert_issuer=$(docker exec milou-nginx openssl x509 -in /etc/ssl/milou.crt -noout -issuer 2>/dev/null | sed 's/issuer=//' || echo "Unknown")
        
        echo
        milou_log "INFO" "🔒 Container Certificate Details:"
        milou_log "INFO" "  Subject: $cert_subject"
        milou_log "INFO" "  Issuer: $cert_issuer"
        milou_log "INFO" "  Expires: $cert_expires"
        
        # Domain validation if provided
        if [[ -n "$domain" ]]; then
            # Create temporary file to extract cert from container
            local temp_cert="/tmp/milou_container_cert_$$.crt"
            if docker cp milou-nginx:/etc/ssl/milou.crt "$temp_cert" 2>/dev/null; then
                echo
                if milou_ssl_validate_certificate_domain "$temp_cert" "$domain"; then
                    milou_log "SUCCESS" "✅ Container certificate matches domain: $domain"
                else
                    milou_log "WARN" "⚠️  Container certificate does not match domain: $domain"
                fi
                rm -f "$temp_cert"
            fi
        fi
    else
        milou_log "ERROR" "❌ No SSL certificate found in nginx container"
        milou_log "INFO" "Inject certificates: ./milou.sh ssl inject"
    fi
    
    # Check if private key exists
    if docker exec milou-nginx test -f /etc/ssl/milou.key; then
        milou_log "SUCCESS" "✅ SSL private key found in container"
    else
        milou_log "ERROR" "❌ No SSL private key found in nginx container"
    fi
    
    echo
    milou_log "INFO" "📊 Container SSL Summary:"
    
    # Quick certificate validation
    if docker exec milou-nginx openssl x509 -in /etc/ssl/milou.crt -noout -text >/dev/null 2>&1; then
        milou_log "SUCCESS" "  ✅ Certificate format is valid"
    else
        milou_log "ERROR" "  ❌ Certificate format is invalid"
    fi
    
    # Quick key validation
    if docker exec milou-nginx openssl rsa -in /etc/ssl/milou.key -check -noout >/dev/null 2>&1; then
        milou_log "SUCCESS" "  ✅ Private key format is valid"
    else
        milou_log "ERROR" "  ❌ Private key format is invalid"
    fi
}

# Restart nginx container
milou_ssl_restart_nginx() {
    milou_log "INFO" "🔄 Restarting nginx container..."
    
    if ! docker ps --filter "name=milou-nginx" --format "{{.Names}}" | grep -q "milou-nginx"; then
        milou_log "WARN" "⚠️  Nginx container not running, starting services..."
        if command -v milou_docker_start >/dev/null 2>&1; then
            milou_docker_start
        else
            milou_log "ERROR" "Cannot start services - start function not available"
            return 1
        fi
    else
        docker restart milou-nginx >/dev/null 2>&1
        sleep 2
        milou_log "SUCCESS" "✅ Nginx container restarted"
    fi
}

# Show SSL help
milou_ssl_show_help() {
    echo "SSL Certificate Management"
    echo "=========================="
    echo ""
    echo "Usage: ./milou.sh ssl <command> [options]"
    echo ""
    echo "Commands:"
    echo "  setup      Interactive SSL certificate setup wizard"
    echo "  status     Show SSL certificate status in nginx container"
    echo "  backup     Backup SSL certificates from nginx container"
    echo "  inject     Inject SSL certificates into nginx container"
    echo "  validate   Validate SSL certificates and configuration"
    echo "  restart    Restart nginx container to apply changes"
    echo "  help       Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./milou.sh ssl setup                    # Interactive setup wizard"
    echo "  ./milou.sh ssl setup --domain example.com"
    echo "  ./milou.sh ssl status                   # Show current status"
    echo "  ./milou.sh ssl inject ./ssl/cert.crt ./ssl/private.key"
    echo "  ./milou.sh ssl backup                   # Backup from container"
    echo "  ./milou.sh ssl validate --domain example.com"
    echo ""
    echo "SSL Paths:"
    echo "  Default: ./static/ssl/ (when in milou-cli directory)"
    echo "  Custom:  Specify with --ssl-path /path/to/ssl"
}

# =============================================================================
# Module Exports
# =============================================================================

# Main interactive functions
export -f milou_ssl_setup_interactive_enhanced
export -f milou_ssl_setup_wizard
export -f milou_ssl_certificate_type_wizard
export -f milou_ssl_setup_letsencrypt
export -f milou_ssl_setup_self_signed
export -f milou_ssl_setup_import_existing
export -f milou_ssl_setup_complete

# Utility functions
export -f milou_ssl_get_appropriate_ssl_path
export -f milou_ssl_validate_enhanced
export -f milou_ssl_backup_container_enhanced
export -f milou_ssl_inject_enhanced
export -f milou_ssl_show_container_status
export -f milou_ssl_restart_nginx
export -f milou_ssl_show_help 