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
# Enhanced Let's Encrypt Certificate Generation Functions
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
    
    milou_log "DEBUG" "Let's Encrypt prerequisites met"
    return 0
}

# Check if port 80 is available or nginx is running
check_port_80_status() {
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

# Webroot approach removed - using simple standalone mode with container stop/start

# Generate Let's Encrypt certificate with simplified approach
generate_letsencrypt_certificate() {
    local ssl_path="$1"
    local domain="$2"
    local email="${3:-admin@$domain}"
    
    milou_log "INFO" "🌟 Obtaining Let's Encrypt certificate for: $domain"
    
    # Install certbot if not available
    if ! command -v certbot >/dev/null 2>&1; then
        if ! install_certbot; then
            return 1
        fi
    fi
    
    # Check port 80 status to determine mode
    local port_status
    check_port_80_status
    port_status=$?
    
    local cert_success=false
    local cert_method=""
    
    case $port_status in
        0)
            # Port 80 available - use standalone mode
            milou_log "INFO" "🔧 Using standalone mode (port 80 available)"
            cert_method="standalone"
            if generate_letsencrypt_standalone "$ssl_path" "$domain" "$email"; then
                cert_success=true
            fi
            ;;
        2)
            # Nginx running - stop containers and use standalone mode
            milou_log "INFO" "🐳 Nginx detected - stopping containers for certificate generation"
            cert_method="standalone-with-stop"
            if generate_letsencrypt_with_nginx_stop "$ssl_path" "$domain" "$email"; then
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
        show_letsencrypt_troubleshooting "$domain"
        return 1
    fi
}

# Generate certificate using standalone mode
generate_letsencrypt_standalone() {
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
        
        return copy_letsencrypt_certificates "$ssl_path" "$domain"
    else
        milou_log "DEBUG" "Standalone mode failed"
        return 1
    fi
}

# Webroot mode removed - using simple standalone approach only

# Generate certificate by temporarily stopping nginx
generate_letsencrypt_with_nginx_stop() {
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
    if generate_letsencrypt_standalone "$ssl_path" "$domain" "$email"; then
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
copy_letsencrypt_certificates() {
    local ssl_path="$1"
    local domain="$2"
    
    local le_cert_dir="/etc/letsencrypt/live/$domain"
    
    if [[ -f "$le_cert_dir/fullchain.pem" && -f "$le_cert_dir/privkey.pem" ]]; then
        # Backup existing certificates
        if [[ -f "$ssl_path/milou.crt" || -f "$ssl_path/milou.key" ]]; then
            backup_ssl_certificates "$ssl_path" "${ssl_path}/backups" "letsencrypt_replace_$(date +%Y%m%d_%H%M%S)"
        fi
        
        # Copy new certificates
        cp "$le_cert_dir/fullchain.pem" "$ssl_path/milou.crt"
        cp "$le_cert_dir/privkey.pem" "$ssl_path/milou.key"
        
        # Set appropriate permissions
        chmod 644 "$ssl_path/milou.crt"
        chmod 600 "$ssl_path/milou.key"
        
        milou_log "DEBUG" "Certificates copied from Let's Encrypt directory"
    return 0
    else
        milou_log "ERROR" "Let's Encrypt certificates not found in expected location: $le_cert_dir"
        return 1
    fi
}

# Show Let's Encrypt troubleshooting information
show_letsencrypt_troubleshooting() {
    local domain="$1"
    
    echo
    milou_log "INFO" "🛠️  Let's Encrypt Troubleshooting Guide:"
    echo
    echo "Common issues and solutions:"
    echo
    echo "1. 🌐 Domain Resolution:"
    echo "   • Ensure $domain points to this server's IP"
    echo "   • Test: nslookup $domain"
    echo "   • Current server IP: $(curl -s ifconfig.me 2>/dev/null || echo 'unknown')"
    echo
    echo "2. 🔥 Firewall & Ports:"
    echo "   • Port 80 must be accessible from internet"
    echo "   • Test: curl -I http://$domain"
    echo "   • Check firewall: ufw status"
    echo
    echo "3. 🌍 HTTP Redirects:"
    echo "   • HTTP must NOT redirect to HTTPS during validation"
    echo "   • Let's Encrypt needs HTTP access for domain validation"
    echo "   • Temporarily disable HTTP to HTTPS redirects"
    echo
    echo "4. ⏱️  Rate Limiting:"
    echo "   • Let's Encrypt has rate limits (5 failures per hour)"
    echo "   • Wait before retrying if hitting limits"
    echo "   • Use staging for testing: --test-cert"
    echo
    echo "5. 🔧 Alternative Solutions:"
    echo "   • Use self-signed certificates: ./milou.sh ssl setup --domain $domain"
    echo "   • Import existing certificates: ./milou.sh ssl copy"
    echo "   • Use DNS validation with certbot plugins"
    echo
}

# Install certbot with enhanced user prompts and better error handling
install_certbot() {
    local interactive="${INTERACTIVE:-true}"
    
    milou_log "STEP" "📦 Certbot Installation Required"
    echo
    
    # In non-interactive mode, don't install automatically
    if [[ "$interactive" == "false" ]]; then
        milou_log "ERROR" "Certbot not found and running in non-interactive mode"
        milou_log "INFO" "Please install certbot manually and retry"
        show_certbot_install_instructions
        return 1
    fi
    
    # Check if we have root privileges
    if [[ $EUID -ne 0 ]]; then
        milou_log "WARN" "⚠️  Root privileges required to install certbot"
        milou_log "INFO" "Please run with sudo or install certbot manually:"
        show_certbot_install_instructions
        return 1
    fi
    
    # Show installation prompt
    milou_log "INFO" "🔍 Certbot (Let's Encrypt client) is required for SSL certificates"
    milou_log "INFO" "Benefits of certbot installation:"
    milou_log "INFO" "  ✅ Free SSL certificates from Let's Encrypt"
    milou_log "INFO" "  ✅ Automatically trusted by all browsers" 
    milou_log "INFO" "  ✅ 90-day validity with auto-renewal support"
    echo
    
    echo -n "Would you like to install certbot now? [Y/n]: "
    read -r response
    
    case "$response" in
        [nN][oO]|[nN])
            milou_log "INFO" "Certbot installation declined"
            show_certbot_install_instructions
            return 1
            ;;
        *)
            milou_log "INFO" "📥 Installing certbot..."
            ;;
    esac
    
    # Detect package manager and install certbot
    local install_success=false
    
    if command -v apt-get >/dev/null 2>&1; then
        # Debian/Ubuntu
        milou_log "INFO" "🔄 Updating package lists (Ubuntu/Debian)..."
        if apt-get update >/dev/null 2>&1; then
            milou_log "INFO" "📦 Installing certbot..."
            if apt-get install -y certbot >/dev/null 2>&1; then
                install_success=true
            fi
        fi
    elif command -v yum >/dev/null 2>&1; then
        # RHEL/CentOS
        milou_log "INFO" "📦 Installing certbot via yum (RHEL/CentOS)..."
        # Try EPEL first for older systems
        yum install -y epel-release >/dev/null 2>&1 || true
        if yum install -y certbot >/dev/null 2>&1; then
            install_success=true
        fi
    elif command -v dnf >/dev/null 2>&1; then
        # Fedora
        milou_log "INFO" "📦 Installing certbot via dnf (Fedora)..."
        if dnf install -y certbot >/dev/null 2>&1; then
            install_success=true
        fi
    elif command -v pacman >/dev/null 2>&1; then
        # Arch Linux
        milou_log "INFO" "📦 Installing certbot via pacman (Arch Linux)..."
        if pacman -S --noconfirm certbot >/dev/null 2>&1; then
            install_success=true
        fi
    elif command -v apk >/dev/null 2>&1; then
        # Alpine Linux
        milou_log "INFO" "📦 Installing certbot via apk (Alpine Linux)..."
        if apk add --no-cache certbot >/dev/null 2>&1; then
            install_success=true
        fi
    elif command -v zypper >/dev/null 2>&1; then
        # openSUSE
        milou_log "INFO" "📦 Installing certbot via zypper (openSUSE)..."
        if zypper install -y python3-certbot >/dev/null 2>&1; then
            install_success=true
        fi
    fi
    
    if [[ "$install_success" == "true" ]]; then
        milou_log "SUCCESS" "✅ Certbot installed successfully!"
        
        # Verify installation
        if command -v certbot >/dev/null 2>&1; then
            local certbot_version
            certbot_version=$(certbot --version 2>&1 | head -1)
            milou_log "INFO" "📋 Installed: $certbot_version"
            return 0
        else
            milou_log "WARN" "⚠️  Certbot installed but not found in PATH"
            milou_log "INFO" "Try running: hash -r && certbot --version"
        fi
    else
        milou_log "ERROR" "❌ Failed to install certbot automatically"
        echo
        milou_log "INFO" "🛠️  Manual installation required:"
        show_certbot_install_instructions
        echo
        milou_log "INFO" "After installing certbot manually, run the SSL setup again"
    fi
    
    return 1
}

# Show manual certbot installation instructions
show_certbot_install_instructions() {
    echo
    milou_log "INFO" "📋 Manual Certbot Installation Commands:"
    echo
    echo "Ubuntu/Debian:"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install certbot"
    echo
    echo "RHEL/CentOS 7/8:"
    echo "  sudo yum install epel-release"
    echo "  sudo yum install certbot"
    echo
    echo "Fedora:"
    echo "  sudo dnf install certbot"
    echo
    echo "Arch Linux:"
    echo "  sudo pacman -S certbot"
    echo
    echo "Alpine Linux:"
    echo "  sudo apk add certbot"
    echo
    echo "openSUSE:"
    echo "  sudo zypper install python3-certbot"
    echo
    echo "Alternative (pip):"
    echo "  pip3 install certbot"
    echo
}

# Backup SSL certificates with enhanced metadata
backup_ssl_certificates() {
    local ssl_path="$1"
    local backup_dir="${2:-${ssl_path}/backups}"
    local backup_name="${3:-ssl_backup_$(date +%Y%m%d_%H%M%S)}"
    
    local cert_file="$ssl_path/milou.crt"
    local key_file="$ssl_path/milou.key"
    
    if [[ ! -f "$cert_file" || ! -f "$key_file" ]]; then
        milou_log "ERROR" "SSL certificates not found for backup"
            return 1
    fi
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    # Create backup with timestamp
    local backup_cert="$backup_dir/${backup_name}.crt"
    local backup_key="$backup_dir/${backup_name}.key"
    local backup_info="$backup_dir/${backup_name}.info"
    
    if cp "$cert_file" "$backup_cert" && cp "$key_file" "$backup_key"; then
        chmod 644 "$backup_cert"
        chmod 600 "$backup_key"
        
        # Create backup info file
        cat > "$backup_info" << EOF
# SSL Certificate Backup Information
# Generated: $(date)
# Backup Name: $backup_name

Certificate File: $backup_cert
Private Key File: $backup_key
Original Cert: $cert_file
Original Key: $key_file

# Certificate Details:
$(openssl x509 -in "$backup_cert" -noout -text 2>/dev/null | head -20 || echo "Certificate details unavailable")
EOF
        chmod 644 "$backup_info"
        
        milou_log "SUCCESS" "SSL certificates backed up:"
        milou_log "INFO" "  📄 Certificate: $backup_cert"
        milou_log "INFO" "  🔑 Private Key: $backup_key"
        milou_log "INFO" "  📋 Info: $backup_info"
            return 0
    else
        milou_log "ERROR" "Failed to backup SSL certificates"
        return 1
    fi
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