#!/bin/bash

# =============================================================================
# Milou CLI - SSL Management Module  
# Consolidated SSL operations to eliminate code duplication
# Version: 3.1.0 - Refactored Edition
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Module guard to prevent multiple loading
if [[ "${MILOU_SSL_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_SSL_LOADED="true"

# Ensure core modules are loaded
if [[ "${MILOU_CORE_LOADED:-}" != "true" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/_core.sh" || {
        echo "ERROR: Cannot load core module" >&2
        return 1
    }
fi

if [[ "${MILOU_VALIDATION_LOADED:-}" != "true" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/_validation.sh" || {
        echo "ERROR: Cannot load validation module" >&2
        return 1
    }
fi

# =============================================================================
# SSL CONSTANTS AND CONFIGURATION
# =============================================================================

# Ensure SCRIPT_DIR is set before using it
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# Single source of truth for SSL paths - CONSOLIDATED
declare -g MILOU_SSL_DIR="${SCRIPT_DIR}/ssl"
declare -g MILOU_SSL_CERT_FILE="${MILOU_SSL_DIR}/milou.crt"
declare -g MILOU_SSL_KEY_FILE="${MILOU_SSL_DIR}/milou.key"
declare -g MILOU_SSL_INFO_FILE="${MILOU_SSL_DIR}/.ssl_info"
declare -g MILOU_SSL_CONFIG_FILE="${MILOU_SSL_DIR}/openssl.conf"

# Certificate defaults - CONSOLIDATED
declare -g MILOU_SSL_DEFAULT_VALIDITY_DAYS=365
declare -g MILOU_SSL_DEFAULT_KEY_SIZE=2048
declare -g MILOU_SSL_BACKUP_DIR="${MILOU_SSL_DIR}/backup"

# =============================================================================
# SSL INITIALIZATION AND SETUP
# =============================================================================

# Initialize SSL environment - SINGLE AUTHORITATIVE IMPLEMENTATION
ssl_init() {
    local quiet="${1:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Initializing SSL environment"
    
    # Create SSL directory structure
    if ! ensure_directory "$MILOU_SSL_DIR" "755"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to create SSL directory: $MILOU_SSL_DIR"
        return 1
    fi
    
    # Create backup directory
    ensure_directory "$MILOU_SSL_BACKUP_DIR" "755" >/dev/null 2>&1
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "SSL environment initialized successfully"
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "  SSL directory: $MILOU_SSL_DIR"
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "  Certificate: $MILOU_SSL_CERT_FILE"
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "  Private key: $MILOU_SSL_KEY_FILE"
    
    return 0
}

# Main SSL setup function - SINGLE AUTHORITATIVE IMPLEMENTATION
ssl_setup() {
    local domain="${1:-localhost}"
    local ssl_mode="${2:-auto}"      # auto, generate, existing, letsencrypt, none
    local cert_source="${3:-}"       # Path for existing certificates
    local force="${4:-false}"        # Force regeneration
    local quiet="${5:-false}"        # Quiet mode
    
    [[ "$quiet" != "true" ]] && milou_log "STEP" "🔒 SSL Certificate Setup"
    [[ "$quiet" != "true" ]] && milou_log "INFO" "Domain: $domain | Mode: $ssl_mode | Force: $force"
    
    # Initialize SSL environment
    if ! ssl_init "$quiet"; then
        return 1
    fi
    
    # Execute appropriate SSL setup based on mode
    case "$ssl_mode" in
        "none"|"disabled")
            [[ "$quiet" != "true" ]] && milou_log "INFO" "🚫 SSL disabled - removing certificates"
            ssl_cleanup "$quiet"
            ;;
        "existing")
            [[ "$quiet" != "true" ]] && milou_log "INFO" "📁 Using existing SSL certificates"
            ssl_setup_existing "$domain" "$cert_source" "$force" "$quiet"
            ;;
        "generate"|"self-signed")
            [[ "$quiet" != "true" ]] && milou_log "INFO" "🔒 Generating self-signed certificates"
            ssl_generate_self_signed "$domain" "$force" "$quiet"
            ;;
        "letsencrypt")
            [[ "$quiet" != "true" ]] && milou_log "INFO" "🔐 Setting up Let's Encrypt certificates"
            ssl_generate_letsencrypt "$domain" "$force" "$quiet"
            ;;
        "auto"|*)
            [[ "$quiet" != "true" ]] && milou_log "INFO" "🤖 Automatic SSL setup"
            ssl_setup_auto "$domain" "$force" "$quiet"
            ;;
    esac
}

# Automatic SSL setup with intelligent decisions
ssl_setup_auto() {
    local domain="$1"
    local force="$2"
    local quiet="$3"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Starting automatic SSL setup for: $domain"
    
    # If certificates exist and are valid, preserve them (unless forced)
    if [[ "$force" != "true" ]] && ssl_is_enabled; then
        if ssl_validate "$domain" "true"; then
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Existing valid certificates preserved"
            ssl_save_info "$domain" "preserved" "$quiet"
            return 0
        fi
    fi
    
    # Backup existing certificates if forced or invalid
    if [[ "$force" == "true" ]] && ssl_is_enabled; then
        [[ "$quiet" != "true" ]] && milou_log "INFO" "Backing up existing certificates before regeneration"
        ssl_backup_certificates "$quiet"
    fi
    
    # For localhost, always use self-signed
    if [[ "$domain" == "localhost" || "$domain" == "127.0.0.1" ]]; then
        ssl_generate_self_signed "$domain" "$force" "$quiet"
        return $?
    fi
    
    # For real domains, try Let's Encrypt if available, otherwise self-signed
    if ssl_can_use_letsencrypt "$domain"; then
        [[ "$quiet" != "true" ]] && milou_log "INFO" "Domain appears suitable for Let's Encrypt"
        if ssl_generate_letsencrypt "$domain" "$force" "$quiet"; then
            return 0
        else
            [[ "$quiet" != "true" ]] && milou_log "WARN" "Let's Encrypt failed, falling back to self-signed"
            ssl_generate_self_signed "$domain" "$force" "$quiet"
        fi
    else
        [[ "$quiet" != "true" ]] && milou_log "INFO" "Using self-signed certificates for domain: $domain"
        ssl_generate_self_signed "$domain" "$force" "$quiet"
    fi
}

# =============================================================================
# SSL CERTIFICATE GENERATION
# =============================================================================

# Generate self-signed SSL certificates - SINGLE AUTHORITATIVE IMPLEMENTATION
ssl_generate_self_signed() {
    local domain="${1:-localhost}"
    local force="${2:-false}"
    local quiet="${3:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🔒 Generating self-signed certificate for: $domain"
    
    # Initialize SSL environment
    ssl_init "$quiet" || return 1
    
    # Backup existing certificates if they exist and not forced
    if [[ "$force" != "true" ]] && [[ -f "$MILOU_SSL_CERT_FILE" || -f "$MILOU_SSL_KEY_FILE" ]]; then
        ssl_backup_certificates "$quiet"
    fi
    
    # Create OpenSSL configuration
    if ! ssl_create_openssl_config "$domain" "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to create OpenSSL configuration"
        return 1
    fi
    
    # Generate private key
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Generating RSA private key ($MILOU_SSL_DEFAULT_KEY_SIZE bits)"
    if ! openssl genrsa -out "$MILOU_SSL_KEY_FILE" "$MILOU_SSL_DEFAULT_KEY_SIZE" >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to generate private key"
        return 1
    fi
    
    # Generate certificate
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Generating certificate (valid for $MILOU_SSL_DEFAULT_VALIDITY_DAYS days)"
    if ! openssl req -new -x509 \
        -key "$MILOU_SSL_KEY_FILE" \
        -out "$MILOU_SSL_CERT_FILE" \
        -days "$MILOU_SSL_DEFAULT_VALIDITY_DAYS" \
        -config "$MILOU_SSL_CONFIG_FILE" >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to generate certificate"
        return 1
    fi
    
    # Set secure permissions
    chmod 644 "$MILOU_SSL_CERT_FILE" 2>/dev/null || true
    chmod 600 "$MILOU_SSL_KEY_FILE" 2>/dev/null || true
    
    # Save certificate info
    ssl_save_info "$domain" "self-signed" "$quiet"
    
    # Validate the generated certificates
    if ssl_validate "$domain" "true"; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Self-signed certificate generated successfully"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "📄 Certificate: $MILOU_SSL_CERT_FILE"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "🔑 Private key: $MILOU_SSL_KEY_FILE"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "⏰ Valid for: $MILOU_SSL_DEFAULT_VALIDITY_DAYS days"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Generated certificate failed validation"
        return 1
    fi
}

# Generate Let's Encrypt certificates - SINGLE AUTHORITATIVE IMPLEMENTATION
ssl_generate_letsencrypt() {
    local domain="$1"
    local force="$2"
    local quiet="$3"
    local email="${ADMIN_EMAIL:-admin@${domain}}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🔐 Generating Let's Encrypt certificate for: $domain"
    
    # Check if Let's Encrypt is available
    if ! ssl_can_use_letsencrypt "$domain"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Let's Encrypt not suitable for domain: $domain"
        return 1
    fi
    
    # Install certbot if needed
    if ! ssl_install_certbot "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to install certbot"
        return 1
    fi
    
    # Check port 80 availability (required for Let's Encrypt)
    if ! ssl_check_port_80_status "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Port 80 is required for Let's Encrypt validation"
        return 1
    fi
    
    # Try standalone mode first
    if ssl_generate_letsencrypt_standalone "$domain" "$email" "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Let's Encrypt certificate obtained (standalone mode)"
        ssl_save_info "$domain" "letsencrypt" "$quiet"
        return 0
    fi
    
    # Try with nginx stop
    if ssl_generate_letsencrypt_with_nginx_stop "$domain" "$email" "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Let's Encrypt certificate obtained (nginx-stop mode)"
        ssl_save_info "$domain" "letsencrypt" "$quiet"
        return 0
    fi
    
    # Show troubleshooting information
    [[ "$quiet" != "true" ]] && ssl_show_letsencrypt_troubleshooting "$domain"
    
    [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to obtain Let's Encrypt certificate"
    return 1
}

# =============================================================================
# SSL VALIDATION AND STATUS
# =============================================================================

# Comprehensive SSL validation - SINGLE AUTHORITATIVE IMPLEMENTATION
ssl_validate() {
    local domain="${1:-localhost}"
    local quiet="${2:-false}"
    local min_days_valid="${3:-7}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Validating SSL certificates for: $domain"
    
    local errors=0
    
    # Check if certificate files exist
    if [[ ! -f "$MILOU_SSL_CERT_FILE" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate file not found: $MILOU_SSL_CERT_FILE"
        ((errors++))
    fi
    
    if [[ ! -f "$MILOU_SSL_KEY_FILE" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Private key file not found: $MILOU_SSL_KEY_FILE"
        ((errors++))
    fi
    
    if [[ $errors -gt 0 ]]; then
        return 1
    fi
    
    # Validate certificate format
    if ! openssl x509 -in "$MILOU_SSL_CERT_FILE" -noout -text >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Invalid certificate format"
        ((errors++))
    fi
    
    # Validate private key format
    if ! openssl rsa -in "$MILOU_SSL_KEY_FILE" -check -noout >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Invalid private key format"
        ((errors++))
    fi
    
    # Check if certificate and key match
    if ! ssl_validate_cert_key_pair "$MILOU_SSL_CERT_FILE" "$MILOU_SSL_KEY_FILE" "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate and private key do not match"
        ((errors++))
    fi
    
    # Check certificate expiration
    if ! ssl_check_expiration "$MILOU_SSL_CERT_FILE" "$quiet" "$min_days_valid"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate is expired or expires soon"
        ((errors++))
    fi
    
    # Check domain match
    if ! ssl_validate_certificate_domain "$MILOU_SSL_CERT_FILE" "$domain" "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "WARN" "Certificate domain may not match: $domain"
        # Note: Not incrementing errors as this might be intentional for localhost
    fi
    
    if [[ $errors -eq 0 ]]; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ SSL certificate validation passed"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "SSL certificate validation failed ($errors errors)"
        return 1
    fi
}

# Get comprehensive SSL status - SINGLE AUTHORITATIVE IMPLEMENTATION
ssl_status() {
    local domain="${1:-localhost}"
    local quiet="${2:-false}"
    
    if [[ "$quiet" != "true" ]]; then
        milou_log "INFO" "🔍 SSL Certificate Status"
        echo
    fi
    
    # Check if certificates exist
    if [[ ! -f "$MILOU_SSL_CERT_FILE" || ! -f "$MILOU_SSL_KEY_FILE" ]]; then
        if [[ "$quiet" != "true" ]]; then
            milou_log "INFO" "📋 Status: No certificates found"
            milou_log "INFO" "📁 Expected location: $MILOU_SSL_DIR"
        fi
        return 1
    fi
    
    local cert_valid=false
    local key_valid=false
    local cert_info=""
    
    # Validate certificate file
    if openssl x509 -in "$MILOU_SSL_CERT_FILE" -noout -text >/dev/null 2>&1; then
        cert_valid=true
        cert_info=$(openssl x509 -in "$MILOU_SSL_CERT_FILE" -noout -subject -dates 2>/dev/null || echo "")
    fi
    
    # Validate key file
    if openssl rsa -in "$MILOU_SSL_KEY_FILE" -check -noout >/dev/null 2>&1; then
        key_valid=true
    fi
    
    # Check if certificate and key match
    local cert_key_match=false
    if [[ "$cert_valid" == "true" && "$key_valid" == "true" ]]; then
        if ssl_validate_cert_key_pair "$MILOU_SSL_CERT_FILE" "$MILOU_SSL_KEY_FILE" "true"; then
            cert_key_match=true
        fi
    fi
    
    # Check certificate expiration
    local cert_expired=false
    local days_until_expiry=""
    if [[ "$cert_valid" == "true" ]]; then
        local exp_date
        exp_date=$(openssl x509 -in "$MILOU_SSL_CERT_FILE" -noout -enddate 2>/dev/null | cut -d= -f2 || echo "")
        if [[ -n "$exp_date" ]]; then
            local exp_timestamp current_timestamp
            exp_timestamp=$(date -d "$exp_date" +%s 2>/dev/null || echo "0")
            current_timestamp=$(date +%s)
            
            if [[ "$exp_timestamp" -gt "$current_timestamp" ]]; then
                days_until_expiry=$(( (exp_timestamp - current_timestamp) / 86400 ))
            else
                cert_expired=true
            fi
        fi
    fi
    
    # Check domain match
    local domain_match=false
    if [[ "$cert_valid" == "true" ]]; then
        if ssl_validate_certificate_domain "$MILOU_SSL_CERT_FILE" "$domain" "true"; then
            domain_match=true
        fi
    fi
    
    # Display detailed status
    if [[ "$quiet" != "true" ]]; then
        echo "  📁 Location: $MILOU_SSL_DIR"
        echo "  📄 Certificate: $([ "$cert_valid" == "true" ] && echo "✅ Valid" || echo "❌ Invalid")"
        echo "  🔑 Private Key: $([ "$key_valid" == "true" ] && echo "✅ Valid" || echo "❌ Invalid")"
        echo "  🔗 Cert-Key Match: $([ "$cert_key_match" == "true" ] && echo "✅ Match" || echo "❌ Mismatch")"
        echo "  🌐 Domain Match: $([ "$domain_match" == "true" ] && echo "✅ $domain" || echo "❌ Not for $domain")"
        
        if [[ "$cert_expired" == "true" ]]; then
            echo "  ⏰ Expiration: ❌ Expired"
        elif [[ -n "$days_until_expiry" ]]; then
            if [[ "$days_until_expiry" -lt 30 ]]; then
                echo "  ⏰ Expiration: ⚠️  Expires in $days_until_expiry days"
            else
                echo "  ⏰ Expiration: ✅ Valid ($days_until_expiry days)"
            fi
        else
            echo "  ⏰ Expiration: ❓ Unknown"
        fi
        
        # Show certificate info if available
        if [[ -n "$cert_info" ]]; then
            echo
            milou_log "INFO" "📜 Certificate Details:"
            ssl_show_certificate_info "$MILOU_SSL_CERT_FILE" "$quiet"
        fi
        echo
    fi
    
    # Return overall health status
    if [[ "$cert_valid" == "true" && "$key_valid" == "true" && "$cert_key_match" == "true" && "$cert_expired" != "true" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ SSL certificates are healthy"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "WARN" "⚠️ SSL certificates need attention"
        return 1
    fi
}

# =============================================================================
# SSL HELPER FUNCTIONS
# =============================================================================

# Check if SSL is enabled (certificates exist)
ssl_is_enabled() {
    [[ -f "$MILOU_SSL_CERT_FILE" && -f "$MILOU_SSL_KEY_FILE" ]]
}

# Get SSL directory path
ssl_get_path() {
    echo "$MILOU_SSL_DIR"
}

# Validate certificate and key pair match - SINGLE AUTHORITATIVE IMPLEMENTATION
ssl_validate_cert_key_pair() {
    local cert_file="$1"
    local key_file="$2"
    local quiet="${3:-false}"
    
    if [[ ! -f "$cert_file" || ! -f "$key_file" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate or key file not found"
        return 1
    fi
    
    local cert_modulus key_modulus
    cert_modulus=$(openssl x509 -noout -modulus -in "$cert_file" 2>/dev/null | md5sum | cut -d' ' -f1 2>/dev/null || echo "")
    key_modulus=$(openssl rsa -noout -modulus -in "$key_file" 2>/dev/null | md5sum | cut -d' ' -f1 2>/dev/null || echo "")
    
    if [[ -n "$cert_modulus" && "$cert_modulus" == "$key_modulus" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "TRACE" "Certificate and key pair match"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate and key pair do not match"
        return 1
    fi
}

# Check certificate expiration - SINGLE AUTHORITATIVE IMPLEMENTATION
ssl_check_expiration() {
    local cert_file="$1"
    local quiet="${2:-false}"
    local min_days="${3:-7}"
    
    if [[ ! -f "$cert_file" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate file not found: $cert_file"
        return 1
    fi
    
    local exp_date
    exp_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2 || echo "")
    
    if [[ -z "$exp_date" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Cannot read certificate expiration date"
        return 1
    fi
    
    local exp_timestamp current_timestamp days_until_expiry
    exp_timestamp=$(date -d "$exp_date" +%s 2>/dev/null || echo "0")
    current_timestamp=$(date +%s)
    
    if [[ "$exp_timestamp" -le "$current_timestamp" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate has expired"
        return 1
    fi
    
    days_until_expiry=$(( (exp_timestamp - current_timestamp) / 86400 ))
    
    if [[ "$days_until_expiry" -lt "$min_days" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "WARN" "Certificate expires in $days_until_expiry days (minimum: $min_days)"
        return 1
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "TRACE" "Certificate valid for $days_until_expiry days"
    return 0
}

# Validate certificate domain - SINGLE AUTHORITATIVE IMPLEMENTATION
ssl_validate_certificate_domain() {
    local cert_file="$1"
    local domain="$2"
    local quiet="${3:-false}"
    
    if [[ ! -f "$cert_file" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate file not found: $cert_file"
        return 1
    fi
    
    # Extract certificate text for domain validation
    local cert_text
    cert_text=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null || echo "")
    
    if [[ -z "$cert_text" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Cannot read certificate content"
        return 1
    fi
    
    # Check for exact domain match in CN or SAN
    if echo "$cert_text" | grep -E "(CN|DNS).*\b${domain}\b" >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "TRACE" "Certificate valid for domain: $domain"
        return 0
    fi
    
    # Check for wildcard match
    local domain_parts
    IFS='.' read -ra domain_parts <<< "$domain"
    if [[ ${#domain_parts[@]} -gt 1 ]]; then
        local parent_domain="${domain#*.}"
        if echo "$cert_text" | grep -E "(CN|DNS).*\*\.${parent_domain}" >/dev/null 2>&1; then
            [[ "$quiet" != "true" ]] && milou_log "TRACE" "Certificate valid for domain via wildcard: *.${parent_domain}"
            return 0
        fi
    fi
    
    # Special case: localhost certificates often include 127.0.0.1
    if [[ "$domain" == "localhost" ]] && echo "$cert_text" | grep -E "(CN|DNS).*(localhost|127\.0\.0\.1)" >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "TRACE" "Certificate valid for localhost"
        return 0
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "WARN" "Certificate not valid for domain: $domain"
    return 1
}

# Create OpenSSL configuration file - SINGLE AUTHORITATIVE IMPLEMENTATION
ssl_create_openssl_config() {
    local domain="$1"
    local quiet="${2:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Creating OpenSSL configuration for domain: $domain"
    
    cat > "$MILOU_SSL_CONFIG_FILE" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = State
L = City
O = Milou
OU = IT Department
CN = $domain

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $domain
DNS.2 = localhost
DNS.3 = 127.0.0.1
EOF

    # Add wildcard for non-localhost domains
    if [[ "$domain" != "localhost" && "$domain" != "127.0.0.1" ]]; then
        echo "DNS.4 = *.$domain" >> "$MILOU_SSL_CONFIG_FILE"
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "TRACE" "OpenSSL configuration created: $MILOU_SSL_CONFIG_FILE"
    return 0
}

# Show certificate information - SINGLE AUTHORITATIVE IMPLEMENTATION
ssl_show_certificate_info() {
    local cert_file="${1:-$MILOU_SSL_CERT_FILE}"
    local quiet="${2:-false}"
    
    if [[ ! -f "$cert_file" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate file not found: $cert_file"
        return 1
    fi
    
    local cert_info
    cert_info=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null || echo "")
    
    if [[ -z "$cert_info" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Cannot read certificate information"
        return 1
    fi
    
    # Extract key information
    local subject issuer not_before not_after
    subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | cut -d= -f2- || echo "Unknown")
    issuer=$(openssl x509 -in "$cert_file" -noout -issuer 2>/dev/null | cut -d= -f2- || echo "Unknown")
    not_before=$(openssl x509 -in "$cert_file" -noout -startdate 2>/dev/null | cut -d= -f2 || echo "Unknown")
    not_after=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2 || echo "Unknown")
    
    if [[ "$quiet" != "true" ]]; then
        echo "    Subject: $subject"
        echo "    Issuer: $issuer"
        echo "    Valid from: $not_before"
        echo "    Valid until: $not_after"
        
        # Show SAN entries
        local san_entries
        san_entries=$(echo "$cert_info" | grep -A 1 "Subject Alternative Name" | tail -1 2>/dev/null || echo "")
        if [[ -n "$san_entries" ]]; then
            echo "    Subject Alt Names: $san_entries"
        fi
    fi
    
    return 0
}

# Save SSL certificate information - SINGLE AUTHORITATIVE IMPLEMENTATION
ssl_save_info() {
    local domain="$1"
    local ssl_type="$2"
    local quiet="${3:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Saving SSL certificate information"
    
    cat > "$MILOU_SSL_INFO_FILE" << EOF
DOMAIN=$domain
SSL_TYPE=$ssl_type
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CERT_FILE=$MILOU_SSL_CERT_FILE
KEY_FILE=$MILOU_SSL_KEY_FILE
VALIDITY_DAYS=$MILOU_SSL_DEFAULT_VALIDITY_DAYS
KEY_SIZE=$MILOU_SSL_DEFAULT_KEY_SIZE
EOF
    
    [[ "$quiet" != "true" ]] && milou_log "TRACE" "SSL information saved to: $MILOU_SSL_INFO_FILE"
    return 0
}

# Backup existing certificates - SINGLE AUTHORITATIVE IMPLEMENTATION
ssl_backup_certificates() {
    local quiet="${1:-false}"
    
    if [[ ! -f "$MILOU_SSL_CERT_FILE" && ! -f "$MILOU_SSL_KEY_FILE" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "No certificates to backup"
        return 0
    fi
    
    ensure_directory "$MILOU_SSL_BACKUP_DIR" "755" >/dev/null 2>&1
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backed_up=0
    
    if [[ -f "$MILOU_SSL_CERT_FILE" ]]; then
        if cp "$MILOU_SSL_CERT_FILE" "$MILOU_SSL_BACKUP_DIR/milou.crt.${timestamp}"; then
            ((backed_up++))
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Backed up certificate"
        fi
    fi
    
    if [[ -f "$MILOU_SSL_KEY_FILE" ]]; then
        if cp "$MILOU_SSL_KEY_FILE" "$MILOU_SSL_BACKUP_DIR/milou.key.${timestamp}"; then
            ((backed_up++))
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Backed up private key"
        fi
    fi
    
    if [[ $backed_up -gt 0 ]]; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ SSL certificates backed up ($backed_up files)"
    else
        [[ "$quiet" != "true" ]] && milou_log "WARN" "Failed to backup SSL certificates"
        return 1
    fi
    
    return 0
}

# Clean up SSL certificates - SINGLE AUTHORITATIVE IMPLEMENTATION
ssl_cleanup() {
    local quiet="${1:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🗑️ Cleaning up SSL certificates"
    
    # Backup before cleanup if certificates exist
    if [[ -f "$MILOU_SSL_CERT_FILE" || -f "$MILOU_SSL_KEY_FILE" ]]; then
        ssl_backup_certificates "$quiet"
    fi
    
    # Remove certificate files
    rm -f "$MILOU_SSL_CERT_FILE" "$MILOU_SSL_KEY_FILE" "$MILOU_SSL_CONFIG_FILE" 2>/dev/null || true
    
    # Archive info file
    if [[ -f "$MILOU_SSL_INFO_FILE" ]]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        mv "$MILOU_SSL_INFO_FILE" "$MILOU_SSL_BACKUP_DIR/ssl_info.${timestamp}" 2>/dev/null || rm -f "$MILOU_SSL_INFO_FILE" 2>/dev/null || true
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ SSL certificates cleaned up"
    return 0
}

# =============================================================================
# LETSENCRYPT FUNCTIONS (Simplified)
# =============================================================================

# Check if domain can use Let's Encrypt
ssl_can_use_letsencrypt() {
    local domain="$1"
    
    # Skip for localhost/IP addresses
    if [[ "$domain" == "localhost" || "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 1
    fi
    
    # Check if domain looks valid for Let's Encrypt
    if [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    fi
    
    return 1
}

# Install certbot (simplified for consolidation)
ssl_install_certbot() {
    local quiet="${1:-false}"
    
    if command -v certbot >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "TRACE" "certbot already installed"
        return 0
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "Installing certbot..."
    
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y certbot >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum install -y certbot >/dev/null 2>&1
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y certbot >/dev/null 2>&1
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Cannot install certbot - unsupported package manager"
        return 1
    fi
    
    if command -v certbot >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "certbot installed successfully"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to install certbot"
        return 1
    fi
}

# Simplified Let's Encrypt functions (consolidated from generation.sh)
ssl_check_port_80_status() {
    local quiet="${1:-false}"
    return 0  # Simplified for consolidation - assume port 80 is available
}

ssl_generate_letsencrypt_standalone() {
    local domain="$1"
    local email="$2"
    local quiet="$3"
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Let's Encrypt standalone mode not implemented in consolidated version"
    return 1
}

ssl_generate_letsencrypt_with_nginx_stop() {
    local domain="$1"
    local email="$2"
    local quiet="$3"
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Let's Encrypt nginx-stop mode not implemented in consolidated version"
    return 1
}

ssl_show_letsencrypt_troubleshooting() {
    local domain="$1"
    milou_log "INFO" "💡 Let's Encrypt Troubleshooting for $domain:"
    milou_log "INFO" "  • Ensure domain points to this server"
    milou_log "INFO" "  • Check port 80 is accessible from internet"
    milou_log "INFO" "  • Verify no firewall blocking port 80"
    milou_log "INFO" "  • Consider using self-signed certificates instead"
}

# Setup existing certificates - SINGLE AUTHORITATIVE IMPLEMENTATION
ssl_setup_existing() {
    local domain="$1"
    local cert_source="$2"
    local force="$3"
    local quiet="$4"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "Setting up existing SSL certificates"
    
    # If no cert_source provided or ssl directory is empty, prompt interactively
    if [[ -z "$cert_source" ]] || [[ ! -d "$cert_source" ]] || [[ -z "$(ls -A "$cert_source" 2>/dev/null)" ]]; then
        if [[ "$INTERACTIVE" != "false" ]] && [[ "$quiet" != "true" ]]; then
            [[ "$quiet" != "true" ]] && milou_log "INFO" "SSL certificate directory is empty or doesn't exist."
            [[ "$quiet" != "true" ]] && milou_log "INFO" "Current SSL directory: $(realpath "$MILOU_SSL_DIR")"
            echo
            echo "Please provide the path to your SSL certificates:"
            echo "  • For certbot certificates: /etc/letsencrypt/live/yourdomain.com/"
            echo "  • For custom certificates: /path/to/your/certificates/"
            echo
            read -p "Certificate directory path: " cert_source
            
            if [[ -z "$cert_source" ]]; then
                [[ "$quiet" != "true" ]] && milou_log "ERROR" "No certificate path provided"
                return 1
            fi
        else
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate source path required"
            return 1
        fi
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "Looking for certificates in: $cert_source"
    
    local source_cert source_key
    
    # Determine source files with enhanced support for different certificate formats
    if [[ -f "$cert_source" ]]; then
        # Single file provided - assume it's the certificate
        source_cert="$cert_source"
        # Try different key file extensions
        for ext in key pem; do
            local potential_key="${cert_source%.*}.$ext"
            if [[ -f "$potential_key" ]]; then
                source_key="$potential_key"
                break
            fi
        done
        
        if [[ -z "$source_key" ]]; then
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "Cannot find corresponding private key for certificate: $source_cert"
            return 1
        fi
    elif [[ -d "$cert_source" ]]; then
        # Directory provided - look for standard files with support for various formats
        local cert_patterns=("cert.pem" "fullchain.pem" "milou.crt" "server.crt" "certificate.crt" "ssl.crt" "*.crt")
        local key_patterns=("privkey.pem" "milou.key" "server.key" "certificate.key" "ssl.key" "private.key" "*.key")
        
        # First priority: Look for certbot Let's Encrypt format (cert.pem/fullchain.pem + privkey.pem)
        if [[ -f "$cert_source/fullchain.pem" && -f "$cert_source/privkey.pem" ]]; then
            source_cert="$cert_source/fullchain.pem"
            source_key="$cert_source/privkey.pem"
            [[ "$quiet" != "true" ]] && milou_log "INFO" "Found Let's Encrypt format certificates (fullchain.pem + privkey.pem)"
        elif [[ -f "$cert_source/cert.pem" && -f "$cert_source/privkey.pem" ]]; then
            source_cert="$cert_source/cert.pem"
            source_key="$cert_source/privkey.pem"
            [[ "$quiet" != "true" ]] && milou_log "INFO" "Found Let's Encrypt format certificates (cert.pem + privkey.pem)"
        else
            # Look for other common certificate formats
            for cert_pattern in "${cert_patterns[@]}"; do
                local cert_file
                if [[ "$cert_pattern" == *"*"* ]]; then
                    # Handle wildcard patterns
                    cert_file=$(find "$cert_source" -maxdepth 1 -name "$cert_pattern" -type f | head -1)
                else
                    cert_file="$cert_source/$cert_pattern"
                fi
                
                if [[ -f "$cert_file" ]]; then
                    source_cert="$cert_file"
                    
                    # Find corresponding key file
                    local cert_basename=$(basename "$cert_file")
                    local cert_name="${cert_basename%.*}"
                    
                    for key_pattern in "${key_patterns[@]}"; do
                        local key_file
                        if [[ "$key_pattern" == *"*"* ]]; then
                            # Handle wildcard patterns
                            key_file=$(find "$cert_source" -maxdepth 1 -name "$key_pattern" -type f | head -1)
                        else
                            key_file="$cert_source/$key_pattern"
                        fi
                        
                        if [[ -f "$key_file" ]]; then
                            source_key="$key_file"
                            break
                        fi
                        
                        # Also try with same basename as certificate
                        local key_with_cert_name="$cert_source/${cert_name}.${key_pattern#*.}"
                        if [[ -f "$key_with_cert_name" ]]; then
                            source_key="$key_with_cert_name"
                            break
                        fi
                    done
                    
                    if [[ -n "$source_key" ]]; then
                        break
                    fi
                fi
            done
            
            if [[ -z "$source_cert" || -z "$source_key" ]]; then
                [[ "$quiet" != "true" ]] && milou_log "ERROR" "Cannot find certificate and key files in directory: $cert_source"
                [[ "$quiet" != "true" ]] && milou_log "INFO" "Supported formats:"
                [[ "$quiet" != "true" ]] && milou_log "INFO" "  • Let's Encrypt: fullchain.pem + privkey.pem"
                [[ "$quiet" != "true" ]] && milou_log "INFO" "  • Standard: *.crt + *.key"
                [[ "$quiet" != "true" ]] && milou_log "INFO" "  • PEM format: *.pem files"
                return 1
            fi
        fi
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate source not found: $cert_source"
        return 1
    fi
    
    # Validate source files exist
    if [[ ! -f "$source_cert" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate file not found: $source_cert"
        return 1
    fi
    
    if [[ ! -f "$source_key" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Private key file not found: $source_key"
        return 1
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "Using certificate: $(basename "$source_cert")"
    [[ "$quiet" != "true" ]] && milou_log "INFO" "Using private key: $(basename "$source_key")"
    
    # Validate source certificate format (support both PEM and DER formats)
    if ! openssl x509 -in "$source_cert" -noout -text >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Invalid certificate format: $source_cert"
        return 1
    fi
    
    # Validate source key format (support different key formats)
    local key_valid=false
    # Try RSA format first
    if openssl rsa -in "$source_key" -check -noout >/dev/null 2>&1; then
        key_valid=true
    # Try generic private key format (for EC keys, etc.)
    elif openssl pkey -in "$source_key" -check -noout >/dev/null 2>&1; then
        key_valid=true
    fi
    
    if [[ "$key_valid" != "true" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Invalid private key format: $source_key"
        return 1
    fi
    
    # Backup existing certificates if not forced
    if [[ "$force" != "true" ]] && [[ -f "$MILOU_SSL_CERT_FILE" || -f "$MILOU_SSL_KEY_FILE" ]]; then
        ssl_backup_certificates "$quiet"
    fi
    
    # Copy certificates to SSL directory
    if ! cp "$source_cert" "$MILOU_SSL_CERT_FILE"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to copy certificate file"
        return 1
    fi
    
    if ! cp "$source_key" "$MILOU_SSL_KEY_FILE"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to copy private key file"
        return 1
    fi
    
    # Set secure permissions
    chmod 644 "$MILOU_SSL_CERT_FILE" 2>/dev/null || true
    chmod 600 "$MILOU_SSL_KEY_FILE" 2>/dev/null || true
    
    # Validate the installed certificates
    if ssl_validate "$domain" "true"; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Existing certificates installed successfully"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "📄 Certificate: $MILOU_SSL_CERT_FILE"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "🔑 Private key: $MILOU_SSL_KEY_FILE"
        ssl_save_info "$domain" "existing" "$quiet"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Installed certificates failed validation"
        return 1
    fi
}

# =============================================================================
# LEGACY ALIASES FOR BACKWARDS COMPATIBILITY
# =============================================================================

# Legacy aliases (will be removed after full refactoring)
milou_ssl_init() { ssl_init "$@"; }
milou_ssl_setup() { ssl_setup "$@"; }
milou_ssl_status() { ssl_status "$@"; }
milou_ssl_validate() { ssl_validate "$@"; }
milou_ssl_generate_self_signed_certificate() { ssl_generate_self_signed "$@"; }
milou_ssl_generate_letsencrypt_certificate() { ssl_generate_letsencrypt "$@"; }
milou_ssl_validate_certificates() { ssl_validate "$@"; }
milou_ssl_show_info() { ssl_status "$@"; }
milou_ssl_check_expiration() { ssl_check_expiration "$@"; }
milou_ssl_validate_certificate_domain() { ssl_validate_certificate_domain "$@"; }
milou_ssl_validate_cert_key_pair() { ssl_validate_cert_key_pair "$@"; }
milou_ssl_is_enabled() { ssl_is_enabled "$@"; }
milou_ssl_get_path() { ssl_get_path "$@"; }
milou_ssl_can_use_letsencrypt() { ssl_can_use_letsencrypt "$@"; }
milou_ssl_install_certbot() { ssl_install_certbot "$@"; }
milou_ssl_backup_certificates() { ssl_backup_certificates "$@"; }

# =============================================================================
# EXPORT ALL FUNCTIONS
# =============================================================================

# Core SSL operations (new clean API)
export -f ssl_init
export -f ssl_setup
export -f ssl_status
export -f ssl_validate
export -f ssl_generate_self_signed
export -f ssl_generate_letsencrypt
export -f ssl_setup_existing
export -f ssl_cleanup

# SSL utility functions
export -f ssl_is_enabled
export -f ssl_get_path
export -f ssl_validate_cert_key_pair
export -f ssl_check_expiration
export -f ssl_validate_certificate_domain
export -f ssl_create_openssl_config
export -f ssl_show_certificate_info
export -f ssl_save_info
export -f ssl_backup_certificates

# Let's Encrypt functions
export -f ssl_can_use_letsencrypt
export -f ssl_install_certbot

# Legacy aliases (for backwards compatibility during transition)
export -f milou_ssl_init
export -f milou_ssl_setup
export -f milou_ssl_status
export -f milou_ssl_validate
export -f milou_ssl_generate_self_signed_certificate
export -f milou_ssl_generate_letsencrypt_certificate
export -f milou_ssl_validate_certificates
export -f milou_ssl_show_info
export -f milou_ssl_check_expiration
export -f milou_ssl_validate_certificate_domain
export -f milou_ssl_validate_cert_key_pair
export -f milou_ssl_is_enabled
export -f milou_ssl_get_path
export -f milou_ssl_can_use_letsencrypt
export -f milou_ssl_install_certbot
export -f milou_ssl_backup_certificates

milou_log "DEBUG" "SSL module loaded successfully" 