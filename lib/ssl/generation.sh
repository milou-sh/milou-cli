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
    local script_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
    if [[ -f "${script_dir}/lib/core/logging.sh" ]]; then
        source "${script_dir}/lib/core/logging.sh"
    else
        echo "ERROR: Logging module not available" >&2
        return 1
    fi
fi

# =============================================================================
# Self-Signed Certificate Generation Functions
# =============================================================================

# Generate localhost development certificate
milou_ssl_generate_localhost_certificate() {
    local ssl_path="$1"
    local cert_file="$ssl_path/milou.crt"
    local key_file="$ssl_path/milou.key"
    
    milou_log "DEBUG" "Generating localhost development certificate"
    
    # Create SSL directory if it doesn't exist
    mkdir -p "$ssl_path"
    
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
milou_ssl_generate_production_certificate() {
    local ssl_path="$1"
    local domain="$2"
    local cert_file="$ssl_path/milou.crt"
    local key_file="$ssl_path/milou.key"
    
    milou_log "DEBUG" "Generating production self-signed certificate for: $domain"
    
    # Create SSL directory if it doesn't exist
    mkdir -p "$ssl_path"
    
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
milou_ssl_generate_minimal_certificate() {
    local ssl_path="$1"
    local domain="${2:-localhost}"
    local cert_file="$ssl_path/milou.crt"
    local key_file="$ssl_path/milou.key"
    
    milou_log "WARN" "Generating minimal fallback certificate"
    
    # Create SSL directory if it doesn't exist
    mkdir -p "$ssl_path"
    
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

# Generic self-signed certificate generator
milou_ssl_generate_self_signed_certificate() {
    local ssl_path="$1"
    local domain="${2:-localhost}"
    
    if [[ "$domain" == "localhost" ]]; then
        milou_ssl_generate_localhost_certificate "$ssl_path"
    else
        milou_ssl_generate_production_certificate "$ssl_path" "$domain"
    fi
}

# =============================================================================
# Let's Encrypt Certificate Generation Functions
# =============================================================================

# Check if Let's Encrypt can be used
milou_ssl_can_use_letsencrypt() {
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
    
    milou_log "DEBUG" "Let's Encrypt prerequisites met"
    return 0
}

# Check if port 80 is available or nginx is running
milou_ssl_check_port_80_status() {
    local port_check_result=""
    
    # Check if port 80 is occupied
    if command -v ss >/dev/null 2>&1; then
        port_check_result=$(ss -tlnp | grep ":80 " 2>/dev/null)
    elif command -v netstat >/dev/null 2>&1; then
        port_check_result=$(netstat -tlnp 2>/dev/null | grep ":80 ")
    fi
    
    if [[ -n "$port_check_result" ]]; then
        # Check if it's docker/nginx
        if echo "$port_check_result" | grep -q "docker-proxy\|nginx"; then
            milou_log "DEBUG" "Port 80 occupied by docker/nginx - will use webroot mode"
            return 2  # nginx running - use webroot
        else
            milou_log "DEBUG" "Port 80 occupied by other service"
            return 1  # other service - cannot use
        fi
    else
        milou_log "DEBUG" "Port 80 is available - can use standalone mode"
        return 0  # available - use standalone
    fi
}

# Generate Let's Encrypt certificate with simplified approach
milou_ssl_generate_letsencrypt_certificate() {
    local ssl_path="$1"
    local domain="$2"
    local email="${3:-admin@$domain}"
    
    milou_log "INFO" "🌟 Obtaining Let's Encrypt certificate for: $domain"
    
    # Install certbot if not available
    if ! command -v certbot >/dev/null 2>&1; then
        if ! milou_ssl_install_certbot; then
            return 1
        fi
    fi
    
    # Check port 80 status to determine mode
    local port_status
    milou_ssl_check_port_80_status
    port_status=$?
    
    local cert_success=false
    local cert_method=""
    
    case $port_status in
        0)
            # Port 80 available - use standalone mode
            milou_log "INFO" "🔧 Using standalone mode (port 80 available)"
            cert_method="standalone"
            if milou_ssl_generate_letsencrypt_standalone "$ssl_path" "$domain" "$email"; then
                cert_success=true
            fi
            ;;
        2)
            # Nginx running - stop containers and use standalone mode
            milou_log "INFO" "🐳 Nginx detected - stopping containers for certificate generation"
            cert_method="standalone-with-stop"
            if milou_ssl_generate_letsencrypt_with_nginx_stop "$ssl_path" "$domain" "$email"; then
                cert_success=true
            fi
            ;;
        1)
            # Port 80 occupied by other service
            milou_log "ERROR" "❌ Port 80 is occupied by another service"
            milou_log "INFO" "Please stop the service using port 80 and try again"
            return 1
            ;;
    esac
    
    if [[ "$cert_success" == true ]]; then
        milou_log "SUCCESS" "✅ Let's Encrypt certificate obtained successfully"
        milou_log "INFO" "📋 Certificate details:"
        milou_log "INFO" "  🏷️  Method: $cert_method"
        milou_log "INFO" "  📄 Certificate: $ssl_path/milou.crt"
        milou_log "INFO" "  🔑 Private key: $ssl_path/milou.key"
        milou_log "INFO" "  ⏰ Valid for: 90 days (auto-renewal recommended)"
        milou_log "INFO" "  📧 Email: $email"
        
        return 0
    else
        milou_log "ERROR" "❌ Certificate generation failed"
        milou_ssl_show_letsencrypt_troubleshooting "$domain"
        return 1
    fi
}

# Generate certificate using standalone mode
milou_ssl_generate_letsencrypt_standalone() {
    local ssl_path="$1"
    local domain="$2"
    local email="$3"
    
    milou_log "DEBUG" "Attempting standalone mode..."
    
    if certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --email "$email" \
        --domains "$domain" \
        --preferred-challenges http >/dev/null 2>&1; then
        
        milou_ssl_copy_letsencrypt_certificates "$ssl_path" "$domain"
        return $?
    else
        milou_log "DEBUG" "Standalone mode failed"
        return 1
    fi
}

# Generate certificate by temporarily stopping nginx
milou_ssl_generate_letsencrypt_with_nginx_stop() {
    local ssl_path="$1"
    local domain="$2"
    local email="$3"
    
    milou_log "INFO" "⏸️  Temporarily stopping nginx for certificate generation..."
    
    # Check if milou-nginx container exists and is running
    local nginx_was_running=false
    if docker ps --filter "name=milou-nginx" --format "{{.Names}}" | grep -q "milou-nginx"; then
        nginx_was_running=true
        milou_log "DEBUG" "Stopping milou-nginx container..."
        docker stop milou-nginx >/dev/null 2>&1
        sleep 2
    fi
    
    # Generate certificate
    local cert_result=false
    if milou_ssl_generate_letsencrypt_standalone "$ssl_path" "$domain" "$email"; then
        cert_result=true
    fi
    
    # Restart nginx if it was running
    if [[ "$nginx_was_running" == true ]]; then
        milou_log "DEBUG" "Restarting milou-nginx container..."
        docker start milou-nginx >/dev/null 2>&1
        sleep 3
        milou_log "INFO" "▶️  Nginx restarted"
    fi
    
    if [[ "$cert_result" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Copy Let's Encrypt certificates to our SSL path
milou_ssl_copy_letsencrypt_certificates() {
    local ssl_path="$1"
    local domain="$2"
    
    local letsencrypt_cert="/etc/letsencrypt/live/$domain/fullchain.pem"
    local letsencrypt_key="/etc/letsencrypt/live/$domain/privkey.pem"
    
    if [[ ! -f "$letsencrypt_cert" || ! -f "$letsencrypt_key" ]]; then
        milou_log "ERROR" "Let's Encrypt certificates not found"
        return 1
    fi
    
    # Create SSL directory if it doesn't exist
    mkdir -p "$ssl_path"
    
    # Copy certificates
    if cp "$letsencrypt_cert" "$ssl_path/milou.crt" && \
       cp "$letsencrypt_key" "$ssl_path/milou.key"; then
        
        chmod 644 "$ssl_path/milou.crt"
        chmod 600 "$ssl_path/milou.key"
        
        milou_log "SUCCESS" "Let's Encrypt certificates copied to: $ssl_path"
        return 0
    else
        milou_log "ERROR" "Failed to copy Let's Encrypt certificates"
        return 1
    fi
}

# Install certbot
milou_ssl_install_certbot() {
    milou_log "INFO" "Installing certbot for Let's Encrypt..."
    
    # Detect package manager and install certbot
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y certbot
    elif command -v yum >/dev/null 2>&1; then
        yum install -y certbot
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y certbot
    elif command -v pacman >/dev/null 2>&1; then
        pacman -S --noconfirm certbot
    else
        milou_log "ERROR" "Unsupported package manager for certbot installation"
        return 1
    fi
    
    # Verify installation
    if command -v certbot >/dev/null 2>&1; then
        milou_log "SUCCESS" "Certbot installed successfully"
        return 0
    else
        milou_log "ERROR" "Failed to install certbot"
        return 1
    fi
}

# Show Let's Encrypt troubleshooting information
milou_ssl_show_letsencrypt_troubleshooting() {
    local domain="$1"
    
    echo
    milou_log "INFO" "🔧 Let's Encrypt Troubleshooting"
    echo "================================="
    echo "1. Ensure your domain points to this server's public IP"
    echo "2. Check if port 80 is accessible from the internet"
    echo "3. Verify domain is not behind a proxy/CDN"
    echo "4. Check DNS propagation: https://dnschecker.org/"
    echo ""
    echo "Manual checks:"
    echo "  curl -I http://$domain/.well-known/acme-challenge/test"
    echo "  nslookup $domain"
    echo ""
    echo "If issues persist, consider using a self-signed certificate:"
    echo "  ./milou.sh ssl setup --self-signed --domain $domain"
}

# =============================================================================
# Module Exports
# =============================================================================

# Self-signed certificate generation
export -f milou_ssl_generate_localhost_certificate
export -f milou_ssl_generate_production_certificate
export -f milou_ssl_generate_minimal_certificate
export -f milou_ssl_generate_self_signed_certificate

# Let's Encrypt functions
export -f milou_ssl_can_use_letsencrypt
export -f milou_ssl_check_port_80_status
export -f milou_ssl_generate_letsencrypt_certificate
export -f milou_ssl_generate_letsencrypt_standalone
export -f milou_ssl_generate_letsencrypt_with_nginx_stop
export -f milou_ssl_copy_letsencrypt_certificates
export -f milou_ssl_install_certbot
export -f milou_ssl_show_letsencrypt_troubleshooting 