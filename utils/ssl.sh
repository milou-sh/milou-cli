#!/bin/bash

# =============================================================================
# SSL Certificate Management for Milou CLI
# Production-ready, zero-interaction SSL certificate handling
# =============================================================================

# Production-ready SSL certificate setup
setup_ssl() {
    local ssl_path="$1"
    local domain="$2"
    
    log "STEP" "Setting up SSL certificates for domain: $domain"
    
    # Create SSL directory if it doesn't exist
    mkdir -p "$ssl_path"
    
    local cert_file="$ssl_path/milou.crt"
    local key_file="$ssl_path/milou.key"
    
    # Strategy 1: Check if valid certificates already exist
    if [[ -f "$cert_file" && -f "$key_file" ]]; then
        log "INFO" "SSL certificates found at $ssl_path"
        if validate_ssl_certificates "$cert_file" "$key_file" "$domain"; then
            log "SUCCESS" "Existing SSL certificates are valid"
            return 0
        else
            log "WARN" "Existing SSL certificates are invalid, will regenerate"
            # Backup invalid certificates
            mv "$cert_file" "${cert_file}.invalid.$(date +%s)" 2>/dev/null || true
            mv "$key_file" "${key_file}.invalid.$(date +%s)" 2>/dev/null || true
        fi
    fi
    
    # Strategy 2: Try to consolidate from other locations (migration)
    if consolidate_existing_certificates "$ssl_path"; then
        log "SUCCESS" "SSL certificates consolidated from existing installation"
        return 0
    fi
    
    # Strategy 3: Generate appropriate certificates based on domain
    if [[ "$domain" == "localhost" || "$domain" == "127.0.0.1" ]]; then
        log "INFO" "Generating development self-signed certificate for localhost"
        if generate_localhost_certificate "$ssl_path"; then
            log "SUCCESS" "Development SSL certificate generated"
            return 0
        fi
    else
        log "INFO" "Generating production self-signed certificate for $domain"
        if generate_production_certificate "$ssl_path" "$domain"; then
            log "SUCCESS" "Production SSL certificate generated"
            log "WARN" "⚠️  Using self-signed certificate - for production, consider using certificates from a trusted CA"
            return 0
        fi
    fi
    
    # Strategy 4: Last resort - minimal certificate
    log "WARN" "Generating minimal fallback certificate"
    if generate_minimal_certificate "$ssl_path" "$domain"; then
        log "SUCCESS" "Minimal SSL certificate generated as fallback"
        return 0
    fi
    
    # If all strategies fail
    log "ERROR" "All SSL certificate generation strategies failed"
    return 1
}

# Validate SSL certificates with comprehensive checks
validate_ssl_certificates() {
    local cert_file="$1"
    local key_file="$2"
    local domain="$3"
    
    # Basic file checks
    if [[ ! -r "$cert_file" ]]; then
        log "DEBUG" "Certificate file not readable: $cert_file"
        return 1
    fi
    
    if [[ ! -r "$key_file" ]]; then
        log "DEBUG" "Private key file not readable: $key_file"
        return 1
    fi
    
    # Check if OpenSSL is available
    if ! command -v openssl >/dev/null 2>&1; then
        log "WARN" "OpenSSL not available - using basic file validation only"
        return 0
    fi
    
    # Check certificate format
    if ! openssl x509 -in "$cert_file" -noout -text >/dev/null 2>&1; then
        log "DEBUG" "Invalid certificate format: $cert_file"
        return 1
    fi
    
    # Check private key format
    if ! openssl rsa -in "$key_file" -check -noout >/dev/null 2>&1; then
        log "DEBUG" "Invalid private key format: $key_file"
        return 1
    fi
    
    # Check if certificate and key match
    local cert_modulus key_modulus
    cert_modulus=$(openssl x509 -noout -modulus -in "$cert_file" 2>/dev/null | openssl md5 2>/dev/null)
    key_modulus=$(openssl rsa -noout -modulus -in "$key_file" 2>/dev/null | openssl md5 2>/dev/null)
    
    if [[ -n "$cert_modulus" && -n "$key_modulus" && "$cert_modulus" != "$key_modulus" ]]; then
        log "DEBUG" "Certificate and private key do not match"
        return 1
    fi
    
    # Check certificate expiration
    local expiry_date
    expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
    if [[ -n "$expiry_date" ]]; then
        local expiry_timestamp current_timestamp
        expiry_timestamp=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry_date" +%s 2>/dev/null)
        current_timestamp=$(date +%s)
        
        if [[ -n "$expiry_timestamp" && $expiry_timestamp -le $current_timestamp ]]; then
            log "DEBUG" "Certificate has expired"
            return 1
        fi
    fi
    
    log "DEBUG" "SSL certificate validation passed"
    return 0
}

# Consolidate certificates from scattered locations (migration helper)
consolidate_existing_certificates() {
    local ssl_path="$1"
    
    # Priority order for certificate search
    local cert_candidates=(
        "./certificates/server.crt"
        "./certificates/milou.crt"
        "./ssl_backup/milou.crt"
        "./ssl_backup/server.crt"
    )
    
    local key_candidates=(
        "./certificates/server.key"
        "./certificates/milou.key"
        "./ssl_backup/milou.key"
        "./ssl_backup/server.key"
    )
    
    # Find the first valid certificate pair
    for i in "${!cert_candidates[@]}"; do
        local cert="${cert_candidates[$i]}"
        local key="${key_candidates[$i]}"
        
        if [[ -f "$cert" && -f "$key" ]]; then
            if validate_ssl_certificates "$cert" "$key" ""; then
                log "INFO" "Found valid certificates: $cert, $key"
                
                # Copy to standard location
                cp "$cert" "$ssl_path/milou.crt"
                cp "$key" "$ssl_path/milou.key"
                chmod 644 "$ssl_path/milou.crt"
                chmod 600 "$ssl_path/milou.key"
                
                log "DEBUG" "Consolidated certificates to $ssl_path"
                return 0
            fi
        fi
    done
    
    return 1
}

# Generate localhost development certificate
generate_localhost_certificate() {
    local ssl_path="$1"
    
    if ! command -v openssl >/dev/null 2>&1; then
        log "ERROR" "OpenSSL is required for certificate generation"
        return 1
    fi
    
    local cert_file="$ssl_path/milou.crt"
    local key_file="$ssl_path/milou.key"
    local config_file="$ssl_path/openssl.cnf"
    
    # Create comprehensive localhost OpenSSL configuration
    cat > "$config_file" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = Development
L = Local
O = Milou Development
OU = Security
CN = localhost

[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = *.localhost
DNS.3 = 127.0.0.1
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

    # Generate certificate with comprehensive error handling
    if openssl genrsa -out "$key_file" 2048 >/dev/null 2>&1 && \
       openssl req -new -x509 -key "$key_file" -out "$cert_file" -days 365 \
       -config "$config_file" -extensions v3_req >/dev/null 2>&1; then
        
        # Set secure permissions
        chmod 600 "$key_file"
        chmod 644 "$cert_file"
        rm -f "$config_file"
        
        log "DEBUG" "Localhost SSL certificate generated successfully"
        return 0
    else
        # Cleanup on failure
        rm -f "$config_file" "$cert_file" "$key_file"
        return 1
    fi
}

# Generate production certificate for custom domain
generate_production_certificate() {
    local ssl_path="$1"
    local domain="$2"
    
    if ! command -v openssl >/dev/null 2>&1; then
        log "ERROR" "OpenSSL is required for certificate generation"
        return 1
    fi
    
    local cert_file="$ssl_path/milou.crt"
    local key_file="$ssl_path/milou.key"
    local config_file="$ssl_path/openssl.cnf"
    
    # Create production OpenSSL configuration
    cat > "$config_file" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = Production
L = Cloud
O = Milou
OU = Security
CN = $domain

[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $domain
DNS.2 = *.$domain
DNS.3 = localhost
IP.1 = 127.0.0.1
EOF

    # Generate certificate
    if openssl genrsa -out "$key_file" 2048 >/dev/null 2>&1 && \
       openssl req -new -x509 -key "$key_file" -out "$cert_file" -days 365 \
       -config "$config_file" -extensions v3_req >/dev/null 2>&1; then
        
        # Set secure permissions
        chmod 600 "$key_file"
        chmod 644 "$cert_file"
        rm -f "$config_file"
        
        log "DEBUG" "Production SSL certificate generated for $domain"
        return 0
    else
        # Cleanup on failure
        rm -f "$config_file" "$cert_file" "$key_file"
        return 1
    fi
}

# Generate minimal fallback certificate (last resort)
generate_minimal_certificate() {
    local ssl_path="$1"
    local domain="$2"
    
    if ! command -v openssl >/dev/null 2>&1; then
        log "ERROR" "OpenSSL is required and not available"
        return 1
    fi
    
    local cert_file="$ssl_path/milou.crt"
    local key_file="$ssl_path/milou.key"
    
    # Generate minimal certificate without config file
    if openssl req -x509 -newkey rsa:2048 -keyout "$key_file" -out "$cert_file" \
       -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Milou/CN=$domain" >/dev/null 2>&1; then
        
        chmod 600 "$key_file"
        chmod 644 "$cert_file"
        
        log "DEBUG" "Minimal SSL certificate generated as fallback"
        return 0
    else
        rm -f "$cert_file" "$key_file"
        return 1
    fi
}

# Legacy function for compatibility - now calls new setup_ssl
generate_self_signed_certificate() {
    local ssl_path="$1"
    local domain="$2"
    
    log "DEBUG" "generate_self_signed_certificate called - redirecting to setup_ssl"
    setup_ssl "$ssl_path" "$domain"
}

# Check SSL certificate expiration
check_ssl_expiration() {
    local ssl_path="${1:-./ssl}"
    local cert_file="$ssl_path/milou.crt"
    
    if [[ ! -f "$cert_file" ]]; then
        log "WARN" "SSL certificate not found: $cert_file"
        return 1
    fi
    
    if ! command -v openssl >/dev/null 2>&1; then
        log "WARN" "OpenSSL not available for certificate checking"
        return 1
    fi
    
    local not_after
    not_after=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d'=' -f2)
    
    if [[ -z "$not_after" ]]; then
        log "WARN" "Could not determine certificate expiration"
        return 1
    fi
    
    # Calculate days until expiry
    local expiry_timestamp current_timestamp
    expiry_timestamp=$(date -d "$not_after" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$not_after" +%s 2>/dev/null)
    current_timestamp=$(date +%s)
    
    if [[ -z "$expiry_timestamp" ]]; then
        log "WARN" "Could not parse certificate expiration date"
        return 1
    fi
    
    if [[ $expiry_timestamp -le $current_timestamp ]]; then
        log "ERROR" "SSL Certificate has EXPIRED!"
        return 1
    fi
    
    local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
    
    if [[ $days_until_expiry -le 7 ]]; then
        log "WARN" "SSL Certificate expires in $days_until_expiry days - renewal recommended"
    elif [[ $days_until_expiry -le 30 ]]; then
        log "INFO" "SSL Certificate expires in $days_until_expiry days"
    else
        log "DEBUG" "SSL Certificate valid for $days_until_expiry more days"
    fi
    
    return 0
}

# Backup SSL certificates
backup_ssl_certificates() {
    local ssl_path="${1:-./ssl}"
    local backup_name="${2:-ssl_$(date +%Y%m%d_%H%M%S)}"
    
    if [[ ! -d "$ssl_path" ]]; then
        log "WARN" "SSL directory not found: $ssl_path"
        return 1
    fi
    
    local backup_dir="${CONFIG_DIR:-~/.milou}/backups"
    mkdir -p "$backup_dir"
    
    local backup_path="${backup_dir}/${backup_name}.tar.gz"
    
    if tar -czf "$backup_path" -C "$(dirname "$ssl_path")" "$(basename "$ssl_path")" 2>/dev/null; then
        chmod 600 "$backup_path"
        log "INFO" "SSL certificates backed up to: $backup_path"
        return 0
    else
        log "WARN" "Failed to create SSL certificate backup"
        return 1
    fi
}

# Production-ready setup_ssl_interactive for wizard use
setup_ssl_interactive() {
    local ssl_path="$1"
    local domain="$2"
    
    # First try automatic setup
    if setup_ssl "$ssl_path" "$domain"; then
        return 0
    fi
    
    # If automatic setup fails and we're in interactive mode, offer options
    if [[ "${INTERACTIVE:-true}" == "true" ]]; then
        echo
        log "WARN" "Automatic SSL setup failed. Manual intervention required."
        echo "Options:"
        echo "  1) Retry automatic setup"
        echo "  2) Skip SSL setup (HTTP only - not recommended)"
        echo "  3) Place your own certificates manually"
        echo
        
        while true; do
            read -p "Choose an option (1-3): " choice
            case "$choice" in
                1)
                    if setup_ssl "$ssl_path" "$domain"; then
                        return 0
                    else
                        echo "Automatic setup failed again."
                    fi
                    ;;
                2)
                    log "WARN" "Skipping SSL setup - HTTP only mode"
                    return 0
                    ;;
                3)
                    echo "Please place your certificate files:"
                    echo "  - $ssl_path/milou.crt (certificate)"
                    echo "  - $ssl_path/milou.key (private key)"
                    echo "Press Enter when ready..."
                    read
                    
                    if [[ -f "$ssl_path/milou.crt" && -f "$ssl_path/milou.key" ]]; then
                        if validate_ssl_certificates "$ssl_path/milou.crt" "$ssl_path/milou.key" "$domain"; then
                            log "SUCCESS" "Manual SSL certificates validated"
                            return 0
                        else
                            log "ERROR" "Manual certificates are invalid"
                        fi
                    else
                        log "ERROR" "Certificate files not found"
                    fi
                    ;;
                *)
                    echo "Invalid choice. Please enter 1-3."
                    ;;
            esac
        done
    else
        # Non-interactive mode - setup already attempted and failed
        return 1
    fi
}

# Legacy compatibility functions (not used in new flow)
setup_existing_certificates() { return 1; }
setup_letsencrypt_certificate() { return 1; }
restore_ssl_certificates() { return 1; }

# Show SSL certificate information
show_ssl_info() {
    local ssl_path="${1:-./ssl}"
    local cert_file="$ssl_path/milou.crt"
    local key_file="$ssl_path/milou.key"
    
    if [[ ! -f "$cert_file" ]]; then
        log "INFO" "No SSL certificate found at: $cert_file"
        return 1
    fi
    
    log "INFO" "SSL Certificate Information:"
    echo
    
    if command -v openssl >/dev/null 2>&1; then
        # Certificate details
        echo "📄 Certificate Details:"
        openssl x509 -in "$cert_file" -noout -text | grep -A1 -E "(Subject:|Issuer:|Not Before|Not After|DNS:|IP Address:)"
        echo
        
        # Key information
        if [[ -f "$key_file" ]]; then
            echo "🔑 Private Key Information:"
            local key_size
            key_size=$(openssl rsa -in "$key_file" -noout -text 2>/dev/null | grep "Private-Key:" | grep -o '[0-9]*')
            echo "  Key size: ${key_size:-unknown} bits"
            echo
        fi
        
        # File information
        echo "📁 File Information:"
        echo "  Certificate: $cert_file"
        if [[ -f "$key_file" ]]; then
            echo "  Private key: $key_file"
        fi
        
        # File sizes and permissions
        local cert_size=$(stat -c%s "$cert_file" 2>/dev/null || stat -f%z "$cert_file" 2>/dev/null || echo "?")
        local cert_perms=$(stat -c "%a" "$cert_file" 2>/dev/null || stat -f "%A" "$cert_file" 2>/dev/null || echo "?")
        echo "  Certificate size: $cert_size bytes (permissions: $cert_perms)"
        
        if [[ -f "$key_file" ]]; then
            local key_size_file=$(stat -c%s "$key_file" 2>/dev/null || stat -f%z "$key_file" 2>/dev/null || echo "?")
            local key_perms=$(stat -c "%a" "$key_file" 2>/dev/null || stat -f "%A" "$key_file" 2>/dev/null || echo "?")
            echo "  Private key size: $key_size_file bytes (permissions: $key_perms)"
        fi
        
    else
        log "WARN" "OpenSSL not available - limited certificate information"
        echo "  Certificate file: $cert_file"
        if [[ -f "$key_file" ]]; then
            echo "  Private key file: $key_file"
        fi
    fi
} 