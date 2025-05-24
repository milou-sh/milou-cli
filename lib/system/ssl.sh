#!/bin/bash

# =============================================================================
# SSL Certificate Management for Milou CLI
# Production-ready, zero-interaction SSL certificate handling
# =============================================================================

# Module guard to prevent multiple loading
if [[ "${MILOU_SSL_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_SSL_LOADED="true"

# Load SSL sub-modules
source "${BASH_SOURCE%/*}/ssl/paths.sh" 2>/dev/null || true
source "${BASH_SOURCE%/*}/ssl/generation.sh" 2>/dev/null || true
source "${BASH_SOURCE%/*}/ssl/validation.sh" 2>/dev/null || true

# Ensure logging is available
if ! command -v milou_log >/dev/null 2>&1; then
    source "${SCRIPT_DIR}/lib/core/logging.sh" 2>/dev/null || {
        echo "ERROR: Cannot load logging module" >&2
        exit 1
    }
fi

# =============================================================================
# Main SSL Setup Functions
# =============================================================================

# Production-ready SSL certificate setup
setup_ssl() {
    local ssl_path="$1"
    local domain="$2"
    
    milou_log "STEP" "Setting up SSL certificates for domain: $domain"
    
    # Get the appropriate SSL path for the current environment
    ssl_path=$(get_appropriate_ssl_path "$ssl_path" "$(pwd)")
    milou_log "DEBUG" "Using SSL path: $ssl_path"
    
    # Create SSL directory if it doesn't exist
    mkdir -p "$ssl_path"
    
    local cert_file="$ssl_path/milou.crt"
    local key_file="$ssl_path/milou.key"
    
    # Strategy 1: Check if valid certificates already exist
    if [[ -f "$cert_file" && -f "$key_file" ]]; then
        milou_log "INFO" "SSL certificates found at $ssl_path"
        
        # Show current certificate information
        show_certificate_info "$cert_file" "$domain"
        
        if validate_ssl_certificates "$cert_file" "$key_file" "$domain"; then
            milou_log "SUCCESS" "Existing SSL certificates are valid"
            
            # Ensure Docker compatibility
            local docker_ssl_path
            docker_ssl_path=$(ensure_docker_compatible_ssl "$ssl_path" "$(pwd)")
            if [[ "$docker_ssl_path" != "$ssl_path" ]]; then
                milou_log "INFO" "SSL certificates prepared for Docker at: $docker_ssl_path"
            fi
            
            return 0
        else
            milou_log "WARN" "Existing SSL certificates are invalid, will regenerate"
            # Backup invalid certificates
            mv "$cert_file" "${cert_file}.invalid.$(date +%s)" 2>/dev/null || true
            mv "$key_file" "${key_file}.invalid.$(date +%s)" 2>/dev/null || true
        fi
    fi
    
    # Strategy 2: Try to consolidate from other locations (migration)
    if consolidate_existing_certificates "$ssl_path"; then
        milou_log "SUCCESS" "SSL certificates consolidated from existing installation"
        show_certificate_info "$cert_file" "$domain"
        
        # Ensure Docker compatibility
        local docker_ssl_path
        docker_ssl_path=$(ensure_docker_compatible_ssl "$ssl_path" "$(pwd)")
        if [[ "$docker_ssl_path" != "$ssl_path" ]]; then
            milou_log "INFO" "SSL certificates prepared for Docker at: $docker_ssl_path"
        fi
        
        return 0
    fi
    
    # Strategy 3: Generate appropriate certificates based on domain
    if [[ "$domain" == "localhost" || "$domain" == "127.0.0.1" ]]; then
        milou_log "INFO" "Generating development self-signed certificate for localhost"
        if generate_localhost_certificate "$ssl_path"; then
            milou_log "SUCCESS" "Development SSL certificate generated"
            
            # Ensure Docker compatibility
            local docker_ssl_path
            docker_ssl_path=$(ensure_docker_compatible_ssl "$ssl_path" "$(pwd)")
            if [[ "$docker_ssl_path" != "$ssl_path" ]]; then
                milou_log "INFO" "SSL certificates prepared for Docker at: $docker_ssl_path"
            fi
            
            return 0
        fi
    else
        # Real domain - try Let's Encrypt first, then fallback to self-signed
        milou_log "INFO" "Real domain detected: $domain"
        
        # Check if Let's Encrypt is available and domain is publicly accessible
        if is_domain_publicly_accessible "$domain" && can_use_letsencrypt; then
            milou_log "INFO" "Attempting to obtain Let's Encrypt certificate for $domain"
            if generate_letsencrypt_certificate "$ssl_path" "$domain"; then
                milou_log "SUCCESS" "Let's Encrypt certificate obtained successfully"
                show_certificate_info "$cert_file" "$domain"
                
                # Ensure Docker compatibility
                local docker_ssl_path
                docker_ssl_path=$(ensure_docker_compatible_ssl "$ssl_path" "$(pwd)")
                if [[ "$docker_ssl_path" != "$ssl_path" ]]; then
                    milou_log "INFO" "SSL certificates prepared for Docker at: $docker_ssl_path"
                fi
                
                return 0
            else
                milou_log "WARN" "Let's Encrypt failed, falling back to self-signed certificate"
            fi
        else
            milou_log "INFO" "Let's Encrypt not available, using self-signed certificate"
        fi
        
        milou_log "INFO" "Generating production self-signed certificate for $domain"
        if generate_production_certificate "$ssl_path" "$domain"; then
            milou_log "SUCCESS" "Production SSL certificate generated"
            milou_log "WARN" "⚠️  Using self-signed certificate - for production, consider using certificates from a trusted CA"
            
            # Ensure Docker compatibility
            local docker_ssl_path
            docker_ssl_path=$(ensure_docker_compatible_ssl "$ssl_path" "$(pwd)")
            if [[ "$docker_ssl_path" != "$ssl_path" ]]; then
                milou_log "INFO" "SSL certificates prepared for Docker at: $docker_ssl_path"
            fi
            
            return 0
        fi
    fi
    
    # Strategy 4: Last resort - minimal certificate
    milou_log "WARN" "Generating minimal fallback certificate"
    if generate_minimal_certificate "$ssl_path" "$domain"; then
        milou_log "SUCCESS" "Minimal SSL certificate generated"
        milou_log "WARN" "⚠️  Minimal certificate - replace with proper certificate ASAP"
        
        # Ensure Docker compatibility
        local docker_ssl_path
        docker_ssl_path=$(ensure_docker_compatible_ssl "$ssl_path" "$(pwd)")
        if [[ "$docker_ssl_path" != "$ssl_path" ]]; then
            milou_log "INFO" "SSL certificates prepared for Docker at: $docker_ssl_path"
        fi
        
        return 0
    fi
    
    # If we get here, everything failed
    milou_log "ERROR" "Failed to set up SSL certificates"
    return 1
}

# Interactive SSL setup with user prompts
setup_ssl_interactive() {
    local ssl_path="${1:-./ssl}"
    local domain="${2:-}"
    
    milou_log "STEP" "Interactive SSL Certificate Setup"
    echo
    
    # Get domain if not provided
    if [[ -z "$domain" ]]; then
        echo -n "Enter domain name (or 'localhost' for development): "
        read -r domain
        domain=${domain:-localhost}
    fi
    
    # Get SSL path preference
    echo -n "SSL certificate path [$ssl_path]: "
    read -r user_ssl_path
    ssl_path=${user_ssl_path:-$ssl_path}
    
    # Show current SSL status
    echo
    milou_log "INFO" "Current SSL Configuration:"
    milou_log "INFO" "  Domain: $domain"
    milou_log "INFO" "  SSL Path: $ssl_path"
    
    # Check if certificates already exist
    local cert_file="$ssl_path/milou.crt"
    local key_file="$ssl_path/milou.key"
    
    if [[ -f "$cert_file" && -f "$key_file" ]]; then
        echo
        milou_log "INFO" "Existing certificates found:"
        show_certificate_info "$cert_file" "$domain"
        
        echo
        echo -n "Replace existing certificates? [y/N]: "
        read -r replace_certs
        
        if [[ "$replace_certs" =~ ^[Yy]$ ]]; then
            # Backup existing certificates
            backup_ssl_certificates "$ssl_path"
            milou_log "INFO" "Existing certificates backed up"
        else
            milou_log "INFO" "Keeping existing certificates"
            return 0
        fi
    fi
    
    # Certificate type selection for real domains
    if [[ "$domain" != "localhost" && "$domain" != "127.0.0.1" ]]; then
        echo
        milou_log "INFO" "Certificate Options:"
        milou_log "INFO" "  1. Let's Encrypt (free, trusted, requires public domain)"
        milou_log "INFO" "  2. Self-signed (works offline, browser warnings)"
        echo -n "Choose certificate type [1/2]: "
        read -r cert_type
        
        case "$cert_type" in
            1)
                if is_domain_publicly_accessible "$domain" && can_use_letsencrypt; then
                    milou_log "INFO" "Attempting Let's Encrypt certificate..."
                    if generate_letsencrypt_certificate "$ssl_path" "$domain"; then
                        milou_log "SUCCESS" "Let's Encrypt certificate obtained!"
                        show_certificate_info "$cert_file" "$domain"
                        return 0
                    else
                        milou_log "ERROR" "Let's Encrypt failed, falling back to self-signed"
                    fi
                else
                    milou_log "WARN" "Let's Encrypt not available, using self-signed"
                fi
                ;;
            2|*)
                milou_log "INFO" "Using self-signed certificate"
                ;;
        esac
    fi
    
    # Generate appropriate certificate
    if setup_ssl "$ssl_path" "$domain"; then
        echo
        milou_log "SUCCESS" "SSL setup completed successfully!"
        show_certificate_info "$cert_file" "$domain"
        
        # Show usage instructions
        echo
        milou_log "INFO" "📋 Next Steps:"
        milou_log "INFO" "  • Update your configuration to use SSL path: $ssl_path"
        milou_log "INFO" "  • Restart your application to use the new certificates"
        if [[ "$domain" != "localhost" ]]; then
            milou_log "INFO" "  • For production, consider using certificates from a trusted CA"
        fi
        
        return 0
    else
        milou_log "ERROR" "SSL setup failed"
        return 1
    fi
}

# =============================================================================
# SSL Management Functions
# =============================================================================

# Renew SSL certificates
renew_ssl_certificates() {
    local ssl_path="${1:-./ssl}"
    local domain="${2:-}"
    
    milou_log "STEP" "Renewing SSL certificates"
    
    local cert_file="$ssl_path/milou.crt"
    local key_file="$ssl_path/milou.key"
    
    if [[ ! -f "$cert_file" ]]; then
        milou_log "ERROR" "No certificates found to renew at: $ssl_path"
        return 1
    fi
    
    # Determine domain from certificate if not provided
    if [[ -z "$domain" ]]; then
        domain=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed -n 's/.*CN=\([^,]*\).*/\1/p')
        milou_log "DEBUG" "Detected domain from certificate: $domain"
    fi
    
    # Check if renewal is needed
    if ! needs_renewal "$cert_file" 30; then
        milou_log "INFO" "Certificate does not need renewal yet"
        return 0
    fi
    
    # Backup current certificates
    backup_ssl_certificates "$ssl_path"
    
    # Check if this is a Let's Encrypt certificate
    local issuer
    issuer=$(openssl x509 -in "$cert_file" -noout -issuer 2>/dev/null)
    
    if [[ "$issuer" =~ "Let's Encrypt" ]]; then
        milou_log "INFO" "Renewing Let's Encrypt certificate"
        if renew_letsencrypt_certificate "$domain" "$ssl_path"; then
            milou_log "SUCCESS" "Let's Encrypt certificate renewed successfully"
            return 0
        else
            milou_log "ERROR" "Let's Encrypt renewal failed"
            return 1
        fi
    else
        milou_log "INFO" "Regenerating self-signed certificate"
        if setup_ssl "$ssl_path" "$domain"; then
            milou_log "SUCCESS" "Self-signed certificate regenerated successfully"
            return 0
        else
            milou_log "ERROR" "Certificate regeneration failed"
            return 1
        fi
    fi
}

# =============================================================================
# Backward Compatibility Functions
# =============================================================================

# Stub functions for backward compatibility (now handled by sub-modules)
setup_existing_certificates() { 
    milou_log "WARN" "setup_existing_certificates is deprecated - use consolidate_existing_certificates"
    return 1
}

setup_letsencrypt_certificate() { 
    milou_log "WARN" "setup_letsencrypt_certificate is deprecated - use generate_letsencrypt_certificate"
    return 1
}

restore_ssl_certificates() { 
    milou_log "WARN" "restore_ssl_certificates is deprecated - use backup/restore functions from validation module"
    return 1
}

# =============================================================================
# SSL Module Complete
# =============================================================================
# All SSL functions are now available through the loaded sub-modules:
# - ssl/paths.sh - SSL path resolution and Docker compatibility
# - ssl/generation.sh - Certificate generation (self-signed and Let's Encrypt)
# - ssl/validation.sh - Certificate validation, information display, and management
# =============================================================================

milou_log "DEBUG" "SSL certificate management module loaded successfully" 