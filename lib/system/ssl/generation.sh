#!/bin/bash

# =============================================================================
# SSL Certificate Generation Module for Milou CLI
# Handles all certificate generation including self-signed and Let's Encrypt
# =============================================================================

# Module guard to prevent multiple loading
if [[ "${MILOU_SSL_GENERATION_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_SSL_GENERATION_LOADED="true"

# Ensure logging is available
if ! command -v milou_log >/dev/null 2>&1; then
    source "${SCRIPT_DIR}/lib/core/logging.sh" 2>/dev/null || {
        echo "ERROR: Cannot load logging module" >&2
        exit 1
    }
fi

# =============================================================================
# Self-Signed Certificate Generation Functions
# =============================================================================

# Generate localhost development certificate
generate_localhost_certificate() {
    local ssl_path="$1"
    local cert_file="$ssl_path/milou.crt"
    local key_file="$ssl_path/milou.key"
    
    milou_log "DEBUG" "Generating localhost development certificate"
    
    # Create a configuration file for localhost certificate
    local config_file="$ssl_path/localhost.conf"
    cat > "$config_file" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C=US
ST=Development
L=Localhost
O=Milou Development
OU=Development Team
CN=localhost

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = *.localhost
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

    # Generate private key and certificate
    if openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout "$key_file" \
        -out "$cert_file" \
        -config "$config_file" \
        -extensions v3_req >/dev/null 2>&1; then
        
        # Set appropriate permissions
        chmod 644 "$cert_file"
        chmod 600 "$key_file"
        
        # Clean up config file
        rm -f "$config_file"
        
        milou_log "SUCCESS" "Localhost development certificate generated"
        milou_log "INFO" "Certificate: $cert_file"
        milou_log "INFO" "Private key: $key_file"
        milou_log "INFO" "Valid for: 365 days"
        milou_log "WARN" "⚠️  Development certificate - not suitable for production"
        
        return 0
    else
        milou_log "ERROR" "Failed to generate localhost certificate"
        rm -f "$config_file" "$cert_file" "$key_file"
        return 1
    fi
}

# Generate production self-signed certificate
generate_production_certificate() {
    local ssl_path="$1"
    local domain="$2"
    local cert_file="$ssl_path/milou.crt"
    local key_file="$ssl_path/milou.key"
    
    milou_log "DEBUG" "Generating production self-signed certificate for: $domain"
    
    # Create a configuration file for the domain
    local config_file="$ssl_path/domain.conf"
    cat > "$config_file" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C=US
ST=Production
L=Server
O=Milou Application
OU=Production Team
CN=$domain

[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $domain
DNS.2 = *.$domain
EOF

    # Generate private key and certificate (valid for 1 year)
    if openssl req -x509 -nodes -days 365 \
        -newkey rsa:4096 \
        -keyout "$key_file" \
        -out "$cert_file" \
        -config "$config_file" \
        -extensions v3_req >/dev/null 2>&1; then
        
        # Set appropriate permissions
        chmod 644 "$cert_file"
        chmod 600 "$key_file"
        
        # Clean up config file
        rm -f "$config_file"
        
        milou_log "SUCCESS" "Production self-signed certificate generated"
        milou_log "INFO" "Certificate: $cert_file"
        milou_log "INFO" "Private key: $key_file"
        milou_log "INFO" "Domain: $domain"
        milou_log "INFO" "Valid for: 365 days"
        milou_log "WARN" "⚠️  Self-signed certificate - browsers will show security warnings"
        
        return 0
    else
        milou_log "ERROR" "Failed to generate production certificate"
        rm -f "$config_file" "$cert_file" "$key_file"
        return 1
    fi
}

# Generate minimal fallback certificate
generate_minimal_certificate() {
    local ssl_path="$1"
    local domain="${2:-localhost}"
    local cert_file="$ssl_path/milou.crt"
    local key_file="$ssl_path/milou.key"
    
    milou_log "WARN" "Generating minimal fallback certificate"
    
    # Generate minimal certificate with basic settings
    if openssl req -x509 -nodes -days 30 \
        -newkey rsa:2048 \
        -keyout "$key_file" \
        -out "$cert_file" \
        -subj "/C=US/ST=Fallback/L=Minimal/O=Milou/CN=$domain" >/dev/null 2>&1; then
        
        chmod 644 "$cert_file"
        chmod 600 "$key_file"
        
        milou_log "SUCCESS" "Minimal certificate generated (30 days validity)"
        milou_log "WARN" "⚠️  Minimal certificate - replace with proper certificate ASAP"
        
        return 0
    else
        milou_log "ERROR" "Failed to generate minimal certificate"
        return 1
    fi
}

# Generic self-signed certificate generator (backward compatibility)
generate_self_signed_certificate() {
    local ssl_path="$1"
    local domain="${2:-localhost}"
    
    if [[ "$domain" == "localhost" ]]; then
        generate_localhost_certificate "$ssl_path"
    else
        generate_production_certificate "$ssl_path" "$domain"
    fi
}

# =============================================================================
# Let's Encrypt Certificate Generation Functions
# =============================================================================

# Check if Let's Encrypt can be used
can_use_letsencrypt() {
    # Check if certbot is available
    if ! command -v certbot >/dev/null 2>&1; then
        milou_log "DEBUG" "Certbot not available for Let's Encrypt"
        return 1
    fi
    
    # Check if we're running as root (required for certbot)
    if [[ $EUID -ne 0 ]]; then
        milou_log "DEBUG" "Root privileges required for Let's Encrypt"
        return 1
    fi
    
    # Check if port 80 is available (required for HTTP challenge)
    if command -v netstat >/dev/null 2>&1; then
        if netstat -tlnp 2>/dev/null | grep -q ":80 "; then
            milou_log "DEBUG" "Port 80 is occupied - Let's Encrypt HTTP challenge not possible"
            return 1
        fi
    fi
    
    milou_log "DEBUG" "Let's Encrypt prerequisites met"
    return 0
}

# Install certbot with user permission
install_certbot() {
    local interactive="${INTERACTIVE:-true}"
    
    milou_log "INFO" "Certbot is required for Let's Encrypt certificates"
    
    # In non-interactive mode, don't install automatically
    if [[ "$interactive" == "false" ]]; then
        milou_log "ERROR" "Certbot not found and running in non-interactive mode"
        milou_log "INFO" "Please install certbot manually: apt-get install certbot"
        return 1
    fi
    
    # Ask for user permission
    milou_log "QUESTION" "Certbot (Let's Encrypt client) is not installed."
    milou_log "INFO" "To obtain Let's Encrypt certificates, certbot needs to be installed."
    echo
    read -p "Would you like to install certbot now? [y/N]: " -r response
    
    case "$response" in
        [yY][eE][sS]|[yY])
            milou_log "INFO" "Installing certbot for Let's Encrypt..."
            ;;
        *)
            milou_log "INFO" "Certbot installation declined"
            milou_log "INFO" "You can install it manually later with: apt-get install certbot"
            return 1
            ;;
    esac
    
    # Detect package manager and install certbot
    if command -v apt-get >/dev/null 2>&1; then
        # Debian/Ubuntu
        milou_log "INFO" "Updating package lists..."
        if apt-get update >/dev/null 2>&1; then
            milou_log "INFO" "Installing certbot..."
            if apt-get install -y certbot >/dev/null 2>&1; then
                milou_log "SUCCESS" "✅ Certbot installed successfully"
                return 0
            fi
        fi
    elif command -v yum >/dev/null 2>&1; then
        # RHEL/CentOS
        milou_log "INFO" "Installing certbot via yum..."
        if yum install -y certbot >/dev/null 2>&1; then
            milou_log "SUCCESS" "✅ Certbot installed successfully"
            return 0
        fi
    elif command -v dnf >/dev/null 2>&1; then
        # Fedora
        milou_log "INFO" "Installing certbot via dnf..."
        if dnf install -y certbot >/dev/null 2>&1; then
            milou_log "SUCCESS" "✅ Certbot installed successfully"
            return 0
        fi
    elif command -v pacman >/dev/null 2>&1; then
        # Arch Linux
        milou_log "INFO" "Installing certbot via pacman..."
        if pacman -S --noconfirm certbot >/dev/null 2>&1; then
            milou_log "SUCCESS" "✅ Certbot installed successfully"
            return 0
        fi
    fi
    
    milou_log "ERROR" "❌ Failed to install certbot automatically"
    milou_log "INFO" "Please install certbot manually for Let's Encrypt support:"
    milou_log "INFO" "  Ubuntu/Debian: sudo apt-get install certbot"
    milou_log "INFO" "  RHEL/CentOS: sudo yum install certbot"
    milou_log "INFO" "  Fedora: sudo dnf install certbot"
    milou_log "INFO" "  Arch: sudo pacman -S certbot"
    return 1
}

# Generate Let's Encrypt certificate
generate_letsencrypt_certificate() {
    local ssl_path="$1"
    local domain="$2"
    local email="${3:-admin@$domain}"
    
    milou_log "INFO" "Obtaining Let's Encrypt certificate for: $domain"
    
    # Install certbot if not available
    if ! command -v certbot >/dev/null 2>&1; then
        if ! install_certbot; then
            return 1
        fi
    fi
    
    # Obtain certificate using standalone mode (use standard paths)
    if certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --email "$email" \
        --domains "$domain" >/dev/null 2>&1; then
        
        # Copy certificates to our SSL path
        local le_cert_dir="/etc/letsencrypt/live/$domain"
        if [[ -f "$le_cert_dir/fullchain.pem" && -f "$le_cert_dir/privkey.pem" ]]; then
            cp "$le_cert_dir/fullchain.pem" "$ssl_path/milou.crt"
            cp "$le_cert_dir/privkey.pem" "$ssl_path/milou.key"
            
            # Set appropriate permissions
            chmod 644 "$ssl_path/milou.crt"
            chmod 600 "$ssl_path/milou.key"
            
            milou_log "SUCCESS" "Let's Encrypt certificate obtained successfully"
            milou_log "INFO" "Certificate: $ssl_path/milou.crt"
            milou_log "INFO" "Private key: $ssl_path/milou.key"
            milou_log "INFO" "Valid for: 90 days (auto-renewal recommended)"
            
            return 0
        else
            milou_log "ERROR" "Let's Encrypt certificates not found in expected location"
        fi
    else
        milou_log "ERROR" "Failed to obtain Let's Encrypt certificate"
        milou_log "INFO" "This could be due to:"
        milou_log "INFO" "  • Domain not pointing to this server"
        milou_log "INFO" "  • Port 80 not accessible from internet"
        milou_log "INFO" "  • Rate limiting from Let's Encrypt"
        milou_log "INFO" "  • Firewall blocking HTTP traffic"
    fi
    
    return 1
}

# =============================================================================
# Certificate Renewal Functions
# =============================================================================

# Renew Let's Encrypt certificate
renew_letsencrypt_certificate() {
    local domain="$1"
    local ssl_path="$2"
    
    milou_log "INFO" "Renewing Let's Encrypt certificate for: $domain"
    
    if ! command -v certbot >/dev/null 2>&1; then
        milou_log "ERROR" "Certbot not available for certificate renewal"
        return 1
    fi
    
    # Attempt renewal
    if certbot renew --quiet --no-self-upgrade; then
        # Copy renewed certificates
        local le_cert_dir="/etc/letsencrypt/live/$domain"
        if [[ -f "$le_cert_dir/fullchain.pem" && -f "$le_cert_dir/privkey.pem" ]]; then
            cp "$le_cert_dir/fullchain.pem" "$ssl_path/milou.crt"
            cp "$le_cert_dir/privkey.pem" "$ssl_path/milou.key"
            
            chmod 644 "$ssl_path/milou.crt"
            chmod 600 "$ssl_path/milou.key"
            
            milou_log "SUCCESS" "Let's Encrypt certificate renewed successfully"
            return 0
        fi
    fi
    
    milou_log "ERROR" "Failed to renew Let's Encrypt certificate"
    return 1
}

# Check if certificate needs renewal
needs_renewal() {
    local cert_file="$1"
    local days_threshold="${2:-30}"
    
    if [[ ! -f "$cert_file" ]]; then
        return 0  # No certificate = needs renewal
    fi
    
    # Get certificate expiration date
    local exp_date
    exp_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
    
    if [[ -z "$exp_date" ]]; then
        return 0  # Can't read expiration = needs renewal
    fi
    
    # Convert to epoch time
    local exp_epoch
    exp_epoch=$(date -d "$exp_date" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$exp_date" +%s 2>/dev/null)
    
    if [[ -z "$exp_epoch" ]]; then
        return 0  # Can't parse date = needs renewal
    fi
    
    # Calculate days until expiration
    local current_epoch
    current_epoch=$(date +%s)
    local days_until_exp=$(( (exp_epoch - current_epoch) / 86400 ))
    
    if [[ $days_until_exp -le $days_threshold ]]; then
        milou_log "INFO" "Certificate expires in $days_until_exp days (threshold: $days_threshold)"
        return 0  # Needs renewal
    else
        milou_log "DEBUG" "Certificate valid for $days_until_exp more days"
        return 1  # No renewal needed
    fi
}

milou_log "DEBUG" "SSL certificate generation module loaded successfully" 