#!/bin/bash

# =============================================================================
# Enhanced Interactive SSL Certificate Management for Milou CLI
# Provides user-friendly certificate setup with multiple options
# =============================================================================

# Module guard to prevent multiple loading
if [[ "${MILOU_SSL_INTERACTIVE_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_SSL_INTERACTIVE_LOADED="true"

# Ensure logging and SSL modules are available with fallback
if ! command -v milou_log >/dev/null 2>&1; then
    # Try to load logging module if SCRIPT_DIR is available
    if [[ -n "${SCRIPT_DIR:-}" ]] && [[ -f "${SCRIPT_DIR}/lib/core/logging.sh" ]]; then
        source "${SCRIPT_DIR}/lib/core/logging.sh" 2>/dev/null || true
    fi
    
    # Provide fallback logging function if still not available
    if ! command -v milou_log >/dev/null 2>&1; then
        milou_log() {
            local level="$1"
            shift
            local message="$*"
            case "$level" in
                "ERROR") echo "[ERROR] $message" >&2 ;;
                "WARN") echo "[WARN] $message" >&2 ;;
                "INFO") echo "[INFO] $message" ;;
                "DEBUG") [[ "${VERBOSE:-false}" == "true" ]] && echo "[DEBUG] $message" ;;
                "SUCCESS") echo "[SUCCESS] $message" ;;
                *) echo "[$level] $message" ;;
            esac
        }
    fi
fi

# =============================================================================
# Enhanced Interactive SSL Setup
# =============================================================================

# Main interactive SSL setup function
setup_ssl_interactive_enhanced() {
    local action="$1"
    local ssl_path="$2"
    local domain="$3"
    local restart_nginx="$4"
    shift 4
    local remaining_args=("$@")
    
    case "$action" in
        setup|generate|create)
            ssl_setup_wizard "$ssl_path" "$domain" "$restart_nginx" "${remaining_args[@]}"
            ;;
        status|info|show)
            # Now shows container status (renamed from status-container)
            ssl_status_container_enhanced "$domain"
            ;;
        validate|check)
            ssl_validate_enhanced "$ssl_path" "$domain"
            ;;
        backup)
            # Now only does container backup (simplified)
            ssl_backup_container_enhanced
            ;;
        inject)
            # Enhanced inject command with direct cert file support
            if command -v inject_ssl_certificates_enhanced >/dev/null 2>&1; then
                inject_ssl_certificates_enhanced "$ssl_path" "$domain" "${remaining_args[@]}"
            else
                ssl_inject_enhanced "$ssl_path" "$domain"
            fi
            ;;
        restart|restart-nginx)
            ssl_restart_nginx
            ;;
        help|--help|-h|"")
            # Show help by default when no command provided
            ssl_show_help
            ;;
        *)
            milou_log "ERROR" "Unknown SSL command: $action"
            milou_log "INFO" "Available commands: setup, status, backup, inject, validate, restart, help"
            ssl_show_help
            return 1
            ;;
    esac
}

# =============================================================================
# SSL Setup Wizard
# =============================================================================

ssl_setup_wizard() {
    local ssl_path="$1"
    local domain="$2" 
    local restart_nginx="$3"
    shift 3
    local remaining_args=("$@")
    
    milou_log "STEP" "🔒 SSL Certificate Setup Wizard"
    echo
    
    # Resolve SSL path
    ssl_path=$(get_appropriate_ssl_path "$ssl_path" "$(pwd)")
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
        show_certificate_info "$cert_file" "$domain"
        echo
        
        if validate_ssl_certificates "$cert_file" "$key_file" "$domain" >/dev/null 2>&1; then
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
                    ssl_restart_nginx
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
        backup_ssl_certificates "$ssl_path"
        echo
    fi
    
    # Certificate type selection
    ssl_certificate_type_wizard "$ssl_path" "$domain" "$restart_nginx"
}

# Certificate type selection wizard
ssl_certificate_type_wizard() {
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
        
        if generate_localhost_certificate "$ssl_path"; then
            ssl_setup_complete "$ssl_path" "$domain" "$restart_nginx"
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
    echo "  2) 🔧 Self-Signed Certificate"
    echo "     ✅ Works immediately, no external requirements"
    echo "     ✅ Strong encryption (4096-bit RSA)"
    echo "     ⚠️  Browsers will show security warnings"
    echo "     ⚠️  Not suitable for production without manual installation"
    echo
    echo "  3) 📁 Import Existing Certificate"
    echo "     ✅ Use your own certificate from CA"
    echo "     ✅ No security warnings if from trusted CA"
    echo "     ⚠️  You must provide both certificate and private key"
    echo
    
    # Check Let's Encrypt compatibility
    local le_available=false
    if ssl_check_letsencrypt_compatibility "$domain"; then
        echo "🔍 Let's Encrypt Compatibility: ✅ Available"
        le_available=true
    else
        echo "🔍 Let's Encrypt Compatibility: ⚠️  Limited (see details below)"
        le_available=false
    fi
    echo
    
    echo -n "Choose certificate type [1]: "
    read -r cert_choice
    cert_choice=${cert_choice:-1}
    echo
    
    case "$cert_choice" in
        1)
            if [[ "$le_available" == "true" ]] || ssl_prompt_letsencrypt_anyway; then
                ssl_letsencrypt_wizard "$ssl_path" "$domain" "$restart_nginx"
            else
                milou_log "INFO" "Falling back to self-signed certificate..."
                ssl_selfsigned_wizard "$ssl_path" "$domain" "$restart_nginx"
            fi
            ;;
        2)
            ssl_selfsigned_wizard "$ssl_path" "$domain" "$restart_nginx"
            ;;
        3)
            ssl_import_wizard "$ssl_path" "$domain" "$restart_nginx"
            ;;
        *)
            milou_log "WARN" "Invalid choice, using self-signed certificate"
            ssl_selfsigned_wizard "$ssl_path" "$domain" "$restart_nginx"
            ;;
    esac
}

# =============================================================================
# Certificate Type Wizards
# =============================================================================

# Let's Encrypt wizard
ssl_letsencrypt_wizard() {
    local ssl_path="$1"
    local domain="$2"
    local restart_nginx="$3"
    
    milou_log "STEP" "🌟 Let's Encrypt Certificate Setup"
    echo
    
    # Install certbot if needed
    if ! command -v certbot >/dev/null 2>&1; then
        milou_log "WARN" "Certbot not found. Installing..."
        if ! install_certbot; then
            milou_log "ERROR" "❌ Failed to install certbot"
            milou_log "INFO" "Falling back to self-signed certificate..."
            ssl_selfsigned_wizard "$ssl_path" "$domain" "$restart_nginx"
            return $?
        fi
    fi
    
    # Get email for Let's Encrypt
    echo "📧 Let's Encrypt requires an email address for:"
    echo "   • Important security notifications"
    echo "   • Certificate expiration reminders"
    echo
    echo -n "Email address [admin@$domain]: "
    read -r le_email
    le_email=${le_email:-admin@$domain}
    echo
    
    milou_log "INFO" "🔄 Obtaining Let's Encrypt certificate..."
    milou_log "INFO" "This may take a few moments..."
    echo
    
    if generate_letsencrypt_certificate "$ssl_path" "$domain" "$le_email"; then
        ssl_setup_complete "$ssl_path" "$domain" "$restart_nginx" "letsencrypt"
    else
        milou_log "ERROR" "❌ Let's Encrypt certificate generation failed"
        echo
        milou_log "INFO" "💡 Common issues and solutions:"
        milou_log "INFO" "   • Ensure $domain points to this server's IP"
        milou_log "INFO" "   • Check that port 80 is open and accessible"
        milou_log "INFO" "   • Verify no other service is using port 80"
        milou_log "INFO" "   • Check firewall settings"
        echo
        echo "Would you like to:"
        echo "  1) Try again with Let's Encrypt"
        echo "  2) Use self-signed certificate instead"
        echo
        echo -n "Choose option [2]: "
        read -r retry_choice
        
        if [[ "$retry_choice" == "1" ]]; then
            ssl_letsencrypt_wizard "$ssl_path" "$domain" "$restart_nginx"
        else
            ssl_selfsigned_wizard "$ssl_path" "$domain" "$restart_nginx"
        fi
    fi
}

# Self-signed certificate wizard
ssl_selfsigned_wizard() {
    local ssl_path="$1"
    local domain="$2"
    local restart_nginx="$3"
    
    milou_log "STEP" "🔧 Self-Signed Certificate Setup"
    echo
    
    milou_log "INFO" "Generating self-signed certificate for: $domain"
    milou_log "INFO" "This certificate will:"
    milou_log "INFO" "  ✅ Provide strong encryption (4096-bit RSA)"
    milou_log "INFO" "  ✅ Include wildcard support (*.$domain)"
    milou_log "INFO" "  ✅ Be valid for 365 days"
    milou_log "INFO" "  ⚠️  Show browser security warnings"
    echo
    
    if generate_production_certificate "$ssl_path" "$domain"; then
        ssl_setup_complete "$ssl_path" "$domain" "$restart_nginx" "self-signed"
    else
        milou_log "ERROR" "❌ Failed to generate self-signed certificate"
        return 1
    fi
}

# Import certificate wizard  
ssl_import_wizard() {
    local ssl_path="$1"
    local domain="$2"
    local restart_nginx="$3"
    
    milou_log "STEP" "📁 Import Existing Certificate"
    echo
    
    milou_log "INFO" "To import your certificate, you need:"
    milou_log "INFO" "  📄 Certificate file (usually .crt, .pem, or .cer)"
    milou_log "INFO" "  🔑 Private key file (usually .key or .pem)"
    echo
    
    # Get certificate file
    echo -n "Enter path to certificate file: "
    read -r cert_file
    
    if [[ ! -f "$cert_file" ]]; then
        milou_log "ERROR" "❌ Certificate file not found: $cert_file"
        return 1
    fi
    
    # Get private key file
    echo -n "Enter path to private key file: "
    read -r key_file
    
    if [[ ! -f "$key_file" ]]; then
        milou_log "ERROR" "❌ Private key file not found: $key_file"
        return 1
    fi
    
    echo
    milou_log "INFO" "🔍 Validating certificate and key..."
    
    # Validate certificate and key compatibility
    if ! ssl_validate_cert_key_pair "$cert_file" "$key_file"; then
        milou_log "ERROR" "❌ Certificate and private key do not match"
        return 1
    fi
    
    milou_log "SUCCESS" "✅ Certificate and key are compatible"
    echo
    
    # Backup existing certificates
    if [[ -f "$ssl_path/milou.crt" || -f "$ssl_path/milou.key" ]]; then
        milou_log "INFO" "💾 Backing up existing certificates..."
        backup_ssl_certificates "$ssl_path"
    fi
    
    # Copy certificates
    milou_log "INFO" "📁 Importing certificates..."
    cp "$cert_file" "$ssl_path/milou.crt" || {
        milou_log "ERROR" "❌ Failed to copy certificate"
        return 1
    }
    
    cp "$key_file" "$ssl_path/milou.key" || {
        milou_log "ERROR" "❌ Failed to copy private key"
        return 1
    }
    
    # Set proper permissions
    chmod 644 "$ssl_path/milou.crt"
    chmod 600 "$ssl_path/milou.key"
    
    ssl_setup_complete "$ssl_path" "$domain" "$restart_nginx" "imported"
}

# =============================================================================
# Copy Certificate Wizard  
# =============================================================================

ssl_copy_wizard() {
    local ssl_path="$1"
    local domain="$2"
    local restart_nginx="$3"
    shift 3
    local remaining_args=("$@")
    
    # Check if certificate files are provided as arguments
    if [[ ${#remaining_args[@]} -ge 2 ]]; then
        local cert_file="${remaining_args[0]}"
        local key_file="${remaining_args[1]}"
        
        milou_log "STEP" "📁 Copying SSL certificates from command line arguments"
        echo
        
        # Validate provided files
        if [[ ! -f "$cert_file" ]]; then
            milou_log "ERROR" "❌ Certificate file not found: $cert_file"
            return 1
        fi
        
        if [[ ! -f "$key_file" ]]; then
            milou_log "ERROR" "❌ Private key file not found: $key_file"
            return 1
        fi
        
        # Import the certificates
        ssl_import_certificates "$ssl_path" "$domain" "$restart_nginx" "$cert_file" "$key_file"
    else
        # Interactive copy wizard
        ssl_import_wizard "$ssl_path" "$domain" "$restart_nginx"
    fi
}

# Import certificates with validation
ssl_import_certificates() {
    local ssl_path="$1"
    local domain="$2" 
    local restart_nginx="$3"
    local cert_file="$4"
    local key_file="$5"
    
    milou_log "INFO" "🔍 Validating certificate and key..."
    
    # Validate certificate and key compatibility
    if ! ssl_validate_cert_key_pair "$cert_file" "$key_file"; then
        milou_log "ERROR" "❌ Certificate and private key do not match"
        return 1
    fi
    
    milou_log "SUCCESS" "✅ Certificate and key are compatible"
    echo
    
    # Backup existing certificates
    if [[ -f "$ssl_path/milou.crt" || -f "$ssl_path/milou.key" ]]; then
        milou_log "INFO" "💾 Backing up existing certificates..."
        backup_ssl_certificates "$ssl_path"
    fi
    
    # Copy certificates
    milou_log "INFO" "📁 Importing certificates..."
    cp "$cert_file" "$ssl_path/milou.crt" || {
        milou_log "ERROR" "❌ Failed to copy certificate"
        return 1
    }
    
    cp "$key_file" "$ssl_path/milou.key" || {
        milou_log "ERROR" "❌ Failed to copy private key"
        return 1
    }
    
    # Set proper permissions
    chmod 644 "$ssl_path/milou.crt"
    chmod 600 "$ssl_path/milou.key"
    
    milou_log "SUCCESS" "✅ SSL certificates imported successfully"
    echo
    
    ssl_setup_complete "$ssl_path" "$domain" "$restart_nginx" "imported"
}

# =============================================================================
# Helper Functions
# =============================================================================

# Check Let's Encrypt compatibility
ssl_check_letsencrypt_compatibility() {
    local domain="$1"
    local issues=0
    
    # Check if certbot is available
    if ! command -v certbot >/dev/null 2>&1; then
        milou_log "WARN" "   ⚠️  Certbot not installed (can be installed automatically)"
        ((issues++))
    fi
    
    # Check root privileges
    if [[ $EUID -ne 0 ]]; then
        milou_log "WARN" "   ⚠️  Root privileges required for Let's Encrypt"
        ((issues++))
    fi
    
    # Check port 80 availability
    if command -v netstat >/dev/null 2>&1; then
        if netstat -tlnp 2>/dev/null | grep -q ":80 "; then
            milou_log "WARN" "   ⚠️  Port 80 is occupied (needed for validation)"
            ((issues++))
        fi
    fi
    
    # Check domain accessibility (basic)
    if ! is_domain_publicly_accessible "$domain"; then
        milou_log "WARN" "   ⚠️  Domain '$domain' may not be publicly accessible"
        ((issues++))
    fi
    
    return $((issues == 0))
}

# Prompt user about Let's Encrypt anyway
ssl_prompt_letsencrypt_anyway() {
    echo "Some Let's Encrypt requirements are not met, but you can still try."
    echo "Many issues can be resolved during the setup process."
    echo
    echo -n "Would you like to try Let's Encrypt anyway? [y/N]: "
    read -r response
    
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Validate certificate and key pair
ssl_validate_cert_key_pair() {
    local cert_file="$1"
    local key_file="$2"
    
    if ! command -v openssl >/dev/null 2>&1; then
        milou_log "WARN" "OpenSSL not available, skipping validation"
        return 0
    fi
    
    local cert_modulus key_modulus
    cert_modulus=$(openssl x509 -noout -modulus -in "$cert_file" 2>/dev/null | openssl md5 2>/dev/null)
    key_modulus=$(openssl rsa -noout -modulus -in "$key_file" 2>/dev/null | openssl md5 2>/dev/null)
    
    [[ "$cert_modulus" == "$key_modulus" && -n "$cert_modulus" ]]
}

# Setup completion handler
ssl_setup_complete() {
    local ssl_path="$1"
    local domain="$2"
    local restart_nginx="$3"
    local cert_type="${4:-}"
    
    echo
    milou_log "SUCCESS" "🎉 SSL certificate setup completed!"
    echo
    
    # Show certificate information
    local cert_file="$ssl_path/milou.crt"
    if [[ -f "$cert_file" ]]; then
        show_certificate_info "$cert_file" "$domain"
        echo
    fi
    
    # Restart nginx if requested
    if [[ "$restart_nginx" == "true" ]]; then
        ssl_restart_nginx
        echo
    fi
    
    # Show next steps
    milou_log "INFO" "📋 Next Steps:"
    case "$cert_type" in
        "letsencrypt")
            milou_log "INFO" "  ✅ Your Let's Encrypt certificate is ready"
            milou_log "INFO" "  📅 Certificate is valid for 90 days"
            milou_log "INFO" "  🔄 Set up auto-renewal: certbot renew --quiet --cron"
            ;;
        "self-signed")
            milou_log "INFO" "  ✅ Your self-signed certificate is ready"
            milou_log "INFO" "  ⚠️  Browsers will show security warnings"
            milou_log "INFO" "  💡 For production, consider Let's Encrypt or CA certificate"
            ;;
        "imported")
            milou_log "INFO" "  ✅ Your imported certificate is ready"
            milou_log "INFO" "  📅 Monitor certificate expiration date"
            ;;
        *)
            milou_log "INFO" "  ✅ Certificate is ready for use"
            ;;
    esac
    
    if [[ "$restart_nginx" != "true" ]]; then
        milou_log "INFO" "  🔄 Restart nginx to apply changes: ./milou.sh ssl restart"
    fi
    
    milou_log "INFO" "  🌐 Test your setup: https://$domain"
}

# =============================================================================
# Other Enhanced SSL Functions
# =============================================================================

# Enhanced SSL status
ssl_status_enhanced() {
    local ssl_path="$1"
    local domain="$2"
    
    milou_log "INFO" "📋 SSL Certificate Status"
    echo
    
    ssl_path=$(get_appropriate_ssl_path "$ssl_path" "$(pwd)")
    
    milou_log "INFO" "Configuration:"
    milou_log "INFO" "  Domain: $domain"
    milou_log "INFO" "  SSL Path: $ssl_path"
    echo
    
    local cert_file="$ssl_path/milou.crt"
    local key_file="$ssl_path/milou.key"
    
    if [[ -f "$cert_file" && -f "$key_file" ]]; then
        show_certificate_info "$cert_file" "$domain"
    else
        milou_log "ERROR" "❌ SSL certificates not found"
        milou_log "INFO" "💡 Run './milou.sh ssl setup --domain $domain' to generate certificates"
        return 1
    fi
}

# Enhanced SSL validation
ssl_validate_enhanced() {
    local ssl_path="$1"
    local domain="$2"
    
    milou_log "INFO" "🔍 Validating SSL certificates"
    echo
    
    ssl_path=$(get_appropriate_ssl_path "$ssl_path" "$(pwd)")
    local cert_file="$ssl_path/milou.crt"
    local key_file="$ssl_path/milou.key"
    
    if command -v validate_ssl_certificates >/dev/null 2>&1; then
        validate_ssl_certificates "$cert_file" "$key_file" "$domain"
    else
        milou_log "ERROR" "SSL validation function not available"
        return 1
    fi
}

# Enhanced SSL backup
ssl_backup_enhanced() {
    local ssl_path="$1"
    
    milou_log "INFO" "💾 Creating SSL certificate backup"
    echo
    
    ssl_path=$(get_appropriate_ssl_path "$ssl_path" "$(pwd)")
    
    if command -v backup_ssl_certificates >/dev/null 2>&1; then
        backup_ssl_certificates "$ssl_path"
    else
        milou_log "ERROR" "SSL backup function not available"
        return 1
    fi
}

# Enhanced SSL backup from container
ssl_backup_container_enhanced() {
    milou_log "INFO" "💾 Creating SSL certificate backup from nginx container"
    echo
    
    if command -v backup_nginx_ssl_certificates >/dev/null 2>&1; then
        backup_nginx_ssl_certificates "./ssl_backups"
    else
        milou_log "ERROR" "Nginx SSL backup function not available"
        return 1
    fi
}

# Enhanced SSL status from container
ssl_status_container_enhanced() {
    local domain="$1"
    
    milou_log "INFO" "📋 SSL Certificate Status (from nginx container)"
    echo
    
    if command -v show_nginx_certificate_status >/dev/null 2>&1; then
        show_nginx_certificate_status "$domain"
    else
        milou_log "ERROR" "Nginx certificate status function not available"
        return 1
    fi
}

# Enhanced SSL injection
ssl_inject_enhanced() {
    local ssl_path="$1"
    local domain="$2"
    
    milou_log "INFO" "💉 Injecting SSL certificates into nginx container"
    echo
    
    ssl_path=$(get_appropriate_ssl_path "$ssl_path" "$(pwd)")
    
    if command -v inject_ssl_certificates >/dev/null 2>&1; then
        inject_ssl_certificates "$ssl_path" "$domain" true
    else
        milou_log "ERROR" "SSL injection function not available"
        return 1
    fi
}

# Restart nginx container
ssl_restart_nginx() {
    milou_log "INFO" "🔄 Restarting nginx container..."
    
    if command -v restart_nginx_container >/dev/null 2>&1; then
        restart_nginx_container
    else
        # Fallback nginx restart
        if docker ps --format "{{.Names}}" | grep -q "milou-nginx"; then
            docker restart milou-nginx >/dev/null 2>&1 && {
                milou_log "SUCCESS" "✅ Nginx restarted successfully"
            } || {
                milou_log "ERROR" "❌ Failed to restart nginx"
                return 1
            }
        else
            milou_log "WARN" "⚠️  Nginx container not found"
            return 1
        fi
    fi
}

# Show SSL help
ssl_show_help() {
    echo "Streamlined SSL Management for Milou"
    echo "===================================="
    echo
    echo "Usage: ./milou.sh ssl [COMMAND] [OPTIONS]"
    echo
    echo "Commands:"
    echo "  setup             Interactive SSL certificate setup wizard"
    echo "  status            Show certificate information from running nginx container"
    echo "  backup            Create backup from running nginx container"
    echo "  inject [CERT]     Inject certificates into nginx container"
    echo "  validate          Validate certificates against domain"
    echo "  restart           Restart nginx to apply SSL changes"
    echo "  help              Show this help"
    echo
    echo "Options:"
    echo "  --domain DOMAIN       Target domain (default: current SERVER_NAME)"
    echo "  --restart-nginx       Restart nginx after setup"
    echo
    echo "Inject Command Usage:"
    echo "  ./milou.sh ssl inject                    # Use certificates from default SSL path"
    echo "  ./milou.sh ssl inject cert.crt           # Inject specific certificate (auto-find key)"
    echo "  ./milou.sh ssl inject cert.crt key.key   # Inject specific certificate and key"
    echo "  ./milou.sh ssl inject --cert=cert.crt --key=key.key  # Using explicit options"
    echo
    echo "Certificate Types Supported:"
    echo "  🌟 Let's Encrypt     Free, trusted, auto-renewable"
    echo "  🔧 Self-signed       Quick setup, browser warnings"
    echo "  📁 Direct inject     Use any certificate files directly"
    echo
    echo "Examples:"
    echo "  ./milou.sh ssl setup --domain example.com --restart-nginx"
    echo "  ./milou.sh ssl status --domain example.com"
    echo "  ./milou.sh ssl backup"
    echo "  ./milou.sh ssl inject /path/to/new-cert.crt"
    echo "  ./milou.sh ssl inject --cert=/etc/ssl/cert.pem --key=/etc/ssl/key.pem"
    echo
} 