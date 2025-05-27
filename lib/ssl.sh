#!/bin/bash

# =============================================================================
# Milou CLI - Consolidated SSL Certificate Management
# All SSL functionality in one organized module (500 lines max)
# =============================================================================

# Module guard to prevent multiple loading
if [[ "${MILOU_SSL_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_SSL_LOADED="true"

# =============================================================================
# Core SSL Configuration and Variables (Lines 1-50)
# =============================================================================

# Default configuration
DEFAULT_SSL_PATH="./ssl"
DEFAULT_DOMAIN="localhost"
SSL_PATH="${SSL_CERT_PATH:-$DEFAULT_SSL_PATH}"
DOMAIN="${CUSTOMER_DOMAIN_NAME:-$DEFAULT_DOMAIN}"

# SSL file names
SSL_CERT_FILE="milou.crt"
SSL_KEY_FILE="milou.key"
SSL_CONFIG_FILE="openssl.cnf"

# Certificate validation settings
CERT_MIN_DAYS=30
CERT_DEFAULT_DAYS=365

# Ensure logging is available
if ! command -v log >/dev/null 2>&1 && ! command -v milou_log >/dev/null 2>&1; then
    log() {
        local level="$1"; shift
        local message="$*"
        case "$level" in
            "ERROR")   echo -e "\033[0;31m❌ [ERROR] $message\033[0m" >&2 ;;
            "WARN")    echo -e "\033[1;33m⚠️  [WARN] $message\033[0m" ;;
            "SUCCESS") echo -e "\033[0;32m✅ [SUCCESS] $message\033[0m" ;;
            "INFO")    echo -e "\033[0;34mℹ️ [INFO] $message\033[0m" ;;
            "STEP")    echo -e "\033[0;35m⚙️ [STEP] $message\033[0m" ;;
            *)         echo "[$level] $message" ;;
        esac
    }
fi

# Use milou_log if available, otherwise use log
ssl_log() { 
    if command -v milou_log >/dev/null 2>&1; then
        milou_log "$@"
    else
        log "$@"
    fi
}

# =============================================================================
# Certificate Generation Functions (Lines 51-150)
# =============================================================================

generate_ssl_certificate() {
    local domain="${1:-$DOMAIN}"
    local ssl_path="${2:-$SSL_PATH}"
    local cert_type="${3:-selfsigned}"
    
    ssl_log "STEP" "Generating SSL certificate for: $domain"
    
    # Create SSL directory
    mkdir -p "$ssl_path"
    
    case "$cert_type" in
        "letsencrypt"|"le")
            generate_letsencrypt_certificate "$domain" "$ssl_path"
            ;;
        "selfsigned"|"self"|*)
            generate_selfsigned_certificate "$domain" "$ssl_path"
            ;;
    esac
}

generate_selfsigned_certificate() {
    local domain="$1"
    local ssl_path="$2"
    
    if ! command -v openssl >/dev/null 2>&1; then
        ssl_log "ERROR" "OpenSSL is required for certificate generation"
        return 1
    fi
    
    local cert_file="$ssl_path/$SSL_CERT_FILE"
    local key_file="$ssl_path/$SSL_KEY_FILE"
    local config_file="$ssl_path/$SSL_CONFIG_FILE"
    
    # Create OpenSSL configuration with SAN
    cat > "$config_file" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = Development
L = Local
O = Milou
OU = Security
CN = $domain

[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $domain
DNS.2 = localhost
DNS.3 = *.localhost
DNS.4 = *.local
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

    # Generate private key
    openssl genrsa -out "$key_file" 2048 || {
        ssl_log "ERROR" "Failed to generate private key"
        return 1
    }
    
    # Generate certificate
    openssl req -new -x509 -key "$key_file" -out "$cert_file" -days $CERT_DEFAULT_DAYS \
        -config "$config_file" -extensions v3_req || {
        ssl_log "ERROR" "Failed to generate certificate"
        return 1
    }
    
    # Set appropriate permissions
    chmod 644 "$cert_file"
    chmod 600 "$key_file"
    rm -f "$config_file"
    
    ssl_log "SUCCESS" "Self-signed SSL certificate generated"
    ssl_log "INFO" "Certificate: $cert_file"
    ssl_log "INFO" "Private key: $key_file"
    
    return 0
}

generate_letsencrypt_certificate() {
    local domain="$1"
    local ssl_path="$2"
    
    # Check prerequisites
    if [[ $EUID -ne 0 ]]; then
        ssl_log "ERROR" "Root privileges required for Let's Encrypt"
        return 1
    fi
    
    # Install certbot if not available
    if ! command -v certbot >/dev/null 2>&1; then
        ssl_log "INFO" "Installing certbot..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update && apt-get install -y certbot
        elif command -v yum >/dev/null 2>&1; then
            yum install -y certbot
        else
            ssl_log "ERROR" "Cannot install certbot automatically"
            return 1
        fi
    fi
    
    # Generate certificate using standalone mode
    ssl_log "INFO" "Generating Let's Encrypt certificate for $domain"
    certbot certonly --standalone --non-interactive --agree-tos \
        --email "${ADMIN_EMAIL:-admin@$domain}" -d "$domain" || {
        ssl_log "ERROR" "Let's Encrypt certificate generation failed"
        return 1
    }
    
    # Copy certificates to our SSL path
    local le_path="/etc/letsencrypt/live/$domain"
    cp "$le_path/fullchain.pem" "$ssl_path/$SSL_CERT_FILE"
    cp "$le_path/privkey.pem" "$ssl_path/$SSL_KEY_FILE"
    
    ssl_log "SUCCESS" "Let's Encrypt certificate generated and copied"
    return 0
}

# =============================================================================
# Interactive SSL Setup Wizard (Lines 151-250)
# =============================================================================

ssl_interactive_setup() {
    local domain="${1:-}"
    local ssl_path="${2:-$SSL_PATH}"
    
    ssl_log "INFO" "🔒 SSL Certificate Setup Wizard"
    echo
    
    # Get domain if not provided
    if [[ -z "$domain" ]]; then
        echo -n "Enter domain name (default: $DOMAIN): "
        read -r domain
        domain="${domain:-$DOMAIN}"
    fi
    
    ssl_log "INFO" "Setting up SSL for domain: $domain"
    
    # Check if certificates already exist
    local cert_file="$ssl_path/$SSL_CERT_FILE"
    local key_file="$ssl_path/$SSL_KEY_FILE"
    
    if [[ -f "$cert_file" && -f "$key_file" ]]; then
        ssl_log "INFO" "Existing certificates found"
        show_ssl_status "$ssl_path"
        
        if validate_ssl_certificate "$cert_file" "$key_file" "$domain"; then
            echo -n "Valid certificates exist. Regenerate? (y/N): "
            read -r regenerate
            if [[ ! "$regenerate" =~ ^[Yy] ]]; then
                ssl_log "INFO" "Using existing certificates"
                return 0
            fi
        fi
    fi
    
    # Choose certificate type
    echo
    ssl_log "INFO" "Certificate Type Options:"
    echo "  1. Self-signed (Development/Testing)"
    echo "  2. Let's Encrypt (Production)"
    echo
    echo -n "Choose certificate type (1-2, default: 1): "
    read -r cert_choice
    
    case "$cert_choice" in
        "2")
            # Let's Encrypt prerequisites check
            if ! check_letsencrypt_prerequisites "$domain"; then
                ssl_log "WARN" "Let's Encrypt prerequisites not met, falling back to self-signed"
                generate_ssl_certificate "$domain" "$ssl_path" "selfsigned"
            else
                generate_ssl_certificate "$domain" "$ssl_path" "letsencrypt"
            fi
            ;;
        "1"|*)
            generate_ssl_certificate "$domain" "$ssl_path" "selfsigned"
            ;;
    esac
    
    # Validate generated certificate
    if validate_ssl_certificate "$cert_file" "$key_file" "$domain"; then
        ssl_log "SUCCESS" "SSL setup completed successfully"
        show_ssl_status "$ssl_path"
        
        # Offer to configure nginx
        echo -n "Configure nginx for SSL? (Y/n): "
        read -r configure_nginx
        if [[ ! "$configure_nginx" =~ ^[Nn] ]]; then
            configure_nginx_ssl "$ssl_path" "$domain"
        fi
        
        return 0
    else
        ssl_log "ERROR" "SSL setup failed - certificate validation failed"
        return 1
    fi
}

check_letsencrypt_prerequisites() {
    local domain="$1"
    local issues=()
    
    # Check root privileges
    if [[ $EUID -ne 0 ]]; then
        issues+=("Root privileges required")
    fi
    
    # Check domain accessibility
    if ! is_domain_publicly_accessible "$domain"; then
        issues+=("Domain not publicly accessible")
    fi
    
    # Check port 80 availability
    if command -v netstat >/dev/null 2>&1; then
        if netstat -tlnp 2>/dev/null | grep -q ":80 "; then
            issues+=("Port 80 is occupied")
        fi
    fi
    
    if [[ ${#issues[@]} -gt 0 ]]; then
        ssl_log "WARN" "Let's Encrypt issues:"
        for issue in "${issues[@]}"; do
            ssl_log "WARN" "  • $issue"
        done
        return 1
    fi
    
    return 0
}

is_domain_publicly_accessible() {
    local domain="$1"
    
    # Skip localhost/local domains
    if [[ "$domain" =~ ^(localhost|.*\.local|127\.|192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.).*$ ]]; then
        return 1
    fi
    
    # Try to resolve domain
    if command -v dig >/dev/null 2>&1; then
        dig +short "$domain" >/dev/null 2>&1
    elif command -v nslookup >/dev/null 2>&1; then
        nslookup "$domain" >/dev/null 2>&1
    else
        # Fallback to ping
        ping -c 1 -W 2 "$domain" >/dev/null 2>&1
    fi
}

# =============================================================================
# Nginx Integration Functions (Lines 251-350)
# =============================================================================

configure_nginx_ssl() {
    local ssl_path="$1"
    local domain="$2"
    
    ssl_log "INFO" "Configuring nginx SSL integration"
    
    # Check if we're in Docker environment
    if [[ -f "./static/docker-compose.yml" ]]; then
        configure_nginx_docker_ssl "$ssl_path" "$domain"
    else
        configure_nginx_host_ssl "$ssl_path" "$domain"
    fi
}

configure_nginx_docker_ssl() {
    local ssl_path="$1"
    local domain="$2"
    
    # Ensure SSL path is accessible to Docker
    local docker_ssl_path="./static/ssl"
    
    if [[ "$ssl_path" != "$docker_ssl_path" ]]; then
        ssl_log "INFO" "Copying certificates to Docker-accessible location"
        mkdir -p "$docker_ssl_path"
        cp "$ssl_path/$SSL_CERT_FILE" "$docker_ssl_path/"
        cp "$ssl_path/$SSL_KEY_FILE" "$docker_ssl_path/"
        ssl_path="$docker_ssl_path"
    fi
    
    # Update docker-compose.yml if needed
    local compose_file="./static/docker-compose.yml"
    if [[ -f "$compose_file" ]]; then
        # Check if SSL volume is already configured
        if ! grep -q "ssl:" "$compose_file"; then
            ssl_log "INFO" "Adding SSL volume to docker-compose.yml"
            # This would need more sophisticated YAML editing
            ssl_log "WARN" "Manual docker-compose.yml SSL configuration may be needed"
        fi
    fi
    
    ssl_log "SUCCESS" "Nginx Docker SSL configuration completed"
}

configure_nginx_host_ssl() {
    local ssl_path="$1"
    local domain="$2"
    
    # Create nginx SSL configuration snippet
    local nginx_ssl_conf="/etc/nginx/snippets/ssl-$domain.conf"
    
    if [[ -w "/etc/nginx/snippets" ]] || [[ $EUID -eq 0 ]]; then
        cat > "$nginx_ssl_conf" << EOF
ssl_certificate $ssl_path/$SSL_CERT_FILE;
ssl_certificate_key $ssl_path/$SSL_KEY_FILE;

ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
ssl_prefer_server_ciphers off;
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;
EOF
        ssl_log "SUCCESS" "Nginx SSL configuration created: $nginx_ssl_conf"
    else
        ssl_log "WARN" "Cannot write nginx configuration (insufficient permissions)"
    fi
}

ensure_docker_ssl_compatibility() {
    local ssl_path="$1"
    local docker_ssl_path="./static/ssl"
    
    # If SSL path is not Docker-accessible, copy certificates
    if [[ "$ssl_path" != "$docker_ssl_path" && -f "$ssl_path/$SSL_CERT_FILE" ]]; then
        ssl_log "INFO" "Ensuring Docker SSL compatibility"
        mkdir -p "$docker_ssl_path"
        cp "$ssl_path/$SSL_CERT_FILE" "$docker_ssl_path/" 2>/dev/null || true
        cp "$ssl_path/$SSL_KEY_FILE" "$docker_ssl_path/" 2>/dev/null || true
        echo "$docker_ssl_path"
    else
        echo "$ssl_path"
    fi
}

# =============================================================================
# Certificate Validation and Status Functions (Lines 351-450)
# =============================================================================

validate_ssl_certificate() {
    local cert_file="$1"
    local key_file="$2"
    local domain="${3:-}"
    
    # Check if files exist
    if [[ ! -f "$cert_file" ]] || [[ ! -f "$key_file" ]]; then
        ssl_log "ERROR" "Certificate files not found"
        return 1
    fi
    
    # Check if OpenSSL is available
    if ! command -v openssl >/dev/null 2>&1; then
        ssl_log "WARN" "OpenSSL not available for validation"
        return 0  # Assume valid if we can't validate
    fi
    
    # Validate certificate format
    if ! openssl x509 -in "$cert_file" -noout -text >/dev/null 2>&1; then
        ssl_log "ERROR" "Invalid certificate format"
        return 1
    fi
    
    # Validate private key format
    if ! openssl rsa -in "$key_file" -check -noout >/dev/null 2>&1; then
        ssl_log "ERROR" "Invalid private key format"
        return 1
    fi
    
    # Check if certificate and key match
    local cert_modulus key_modulus
    cert_modulus=$(openssl x509 -noout -modulus -in "$cert_file" 2>/dev/null | openssl md5)
    key_modulus=$(openssl rsa -noout -modulus -in "$key_file" 2>/dev/null | openssl md5)
    
    if [[ "$cert_modulus" != "$key_modulus" ]]; then
        ssl_log "ERROR" "Certificate and private key do not match"
        return 1
    fi
    
    # Check certificate expiry
    if ! openssl x509 -in "$cert_file" -noout -checkend $((CERT_MIN_DAYS * 86400)) >/dev/null 2>&1; then
        ssl_log "WARN" "Certificate expires within $CERT_MIN_DAYS days"
    fi
    
    # Check domain match if provided
    if [[ -n "$domain" ]]; then
        local cert_cn
        cert_cn=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed -n 's/.*CN=\([^,]*\).*/\1/p')
        if [[ "$cert_cn" != "$domain" ]]; then
            # Check SAN (Subject Alternative Names)
            if ! openssl x509 -in "$cert_file" -noout -text 2>/dev/null | grep -q "DNS:$domain"; then
                ssl_log "WARN" "Certificate domain ($cert_cn) does not match requested domain ($domain)"
            fi
        fi
    fi
    
    ssl_log "SUCCESS" "Certificate validation passed"
    return 0
}

show_ssl_status() {
    local ssl_path="${1:-$SSL_PATH}"
    
    ssl_log "INFO" "SSL Certificate Status Report"
    echo
    
    # Configuration
    ssl_log "INFO" "Configuration:"
    echo "  SSL Path: $ssl_path"
    echo "  Domain: $DOMAIN"
    echo
    
    # Find certificate files
    local cert_file="$ssl_path/$SSL_CERT_FILE"
    local key_file="$ssl_path/$SSL_KEY_FILE"
    
    if [[ -f "$cert_file" && -f "$key_file" ]]; then
        ssl_log "INFO" "Certificate Files:"
        echo "  Certificate: $cert_file ($(stat -c%s "$cert_file" 2>/dev/null || echo "0") bytes)"
        echo "  Private Key: $key_file ($(stat -c%s "$key_file" 2>/dev/null || echo "0") bytes)"
        echo
        
        # Certificate details
        if command -v openssl >/dev/null 2>&1; then
            ssl_log "INFO" "Certificate Details:"
            local subject expiry issuer
            subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed 's/subject=//')
            expiry=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
            issuer=$(openssl x509 -in "$cert_file" -noout -issuer 2>/dev/null | sed 's/issuer=//')
            
            echo "  Subject: $subject"
            echo "  Issuer: $issuer"
            echo "  Expires: $expiry"
            
            # Check if certificate is valid
            if validate_ssl_certificate "$cert_file" "$key_file"; then
                ssl_log "SUCCESS" "Certificate is valid"
            else
                ssl_log "ERROR" "Certificate validation failed"
            fi
        fi
    else
        ssl_log "WARN" "No SSL certificates found at $ssl_path"
    fi
    
    # Check Docker compatibility
    local docker_ssl_path="./static/ssl"
    if [[ -d "$docker_ssl_path" && "$ssl_path" != "$docker_ssl_path" ]]; then
        echo
        ssl_log "INFO" "Docker SSL Status:"
        if [[ -f "$docker_ssl_path/$SSL_CERT_FILE" ]]; then
            echo "  Docker certificates: Available"
        else
            echo "  Docker certificates: Not found"
        fi
    fi
}

# =============================================================================
# Backup, Restore and Utility Functions (Lines 451-500)
# =============================================================================

backup_ssl_certificates() {
    local ssl_path="${1:-$SSL_PATH}"
    local backup_path="${2:-./ssl-backup-$(date +%Y%m%d-%H%M%S)}"
    
    if [[ ! -d "$ssl_path" ]]; then
        ssl_log "ERROR" "SSL path does not exist: $ssl_path"
        return 1
    fi
    
    ssl_log "INFO" "Backing up SSL certificates to: $backup_path"
    mkdir -p "$backup_path"
    
    cp -r "$ssl_path"/* "$backup_path/" 2>/dev/null || {
        ssl_log "ERROR" "Failed to backup SSL certificates"
        return 1
    }
    
    ssl_log "SUCCESS" "SSL certificates backed up successfully"
    return 0
}

restore_ssl_certificates() {
    local backup_path="$1"
    local ssl_path="${2:-$SSL_PATH}"
    
    if [[ ! -d "$backup_path" ]]; then
        ssl_log "ERROR" "Backup path does not exist: $backup_path"
        return 1
    fi
    
    ssl_log "INFO" "Restoring SSL certificates from: $backup_path"
    mkdir -p "$ssl_path"
    
    cp -r "$backup_path"/* "$ssl_path/" 2>/dev/null || {
        ssl_log "ERROR" "Failed to restore SSL certificates"
        return 1
    }
    
    ssl_log "SUCCESS" "SSL certificates restored successfully"
    return 0
}

clean_ssl_certificates() {
    local ssl_path="${1:-$SSL_PATH}"
    
    if [[ ! -d "$ssl_path" ]]; then
        ssl_log "WARN" "SSL path does not exist: $ssl_path"
        return 0
    fi
    
    ssl_log "INFO" "Cleaning SSL certificates from: $ssl_path"
    
    # Backup before cleaning
    backup_ssl_certificates "$ssl_path" "./ssl-backup-before-clean-$(date +%Y%m%d-%H%M%S)"
    
    # Remove certificate files
    rm -f "$ssl_path"/*.crt "$ssl_path"/*.key "$ssl_path"/*.pem "$ssl_path"/*.cnf 2>/dev/null
    
    ssl_log "SUCCESS" "SSL certificates cleaned"
    return 0
}

consolidate_ssl_certificates() {
    local target_ssl_path="${1:-$SSL_PATH}"
    
    ssl_log "INFO" "Consolidating SSL certificates to: $target_ssl_path"
    
    # Search for certificates in common locations
    local search_paths=(
        "./ssl"
        "./static/ssl"
        "./certificates"
        "./static/certificates"
        "./certs"
        "./static/certs"
    )
    
    local found_certs=false
    
    for search_path in "${search_paths[@]}"; do
        if [[ -d "$search_path" && "$search_path" != "$target_ssl_path" ]]; then
            if [[ -f "$search_path/$SSL_CERT_FILE" && -f "$search_path/$SSL_KEY_FILE" ]]; then
                ssl_log "INFO" "Found certificates in: $search_path"
                
                # Validate before consolidating
                if validate_ssl_certificate "$search_path/$SSL_CERT_FILE" "$search_path/$SSL_KEY_FILE"; then
                    mkdir -p "$target_ssl_path"
                    cp "$search_path/$SSL_CERT_FILE" "$target_ssl_path/"
                    cp "$search_path/$SSL_KEY_FILE" "$target_ssl_path/"
                    ssl_log "SUCCESS" "Consolidated certificates from: $search_path"
                    found_certs=true
                    break
                fi
            fi
        fi
    done
    
    if [[ "$found_certs" == false ]]; then
        ssl_log "WARN" "No valid certificates found to consolidate"
        return 1
    fi
    
    return 0
}

# Main SSL setup function (entry point)
setup_ssl() {
    local ssl_path="${1:-$SSL_PATH}"
    local domain="${2:-$DOMAIN}"
    local interactive="${3:-${INTERACTIVE:-true}}"
    
    if [[ "$interactive" == "true" ]]; then
        ssl_interactive_setup "$domain" "$ssl_path"
    else
        generate_ssl_certificate "$domain" "$ssl_path" "selfsigned"
    fi
}

# =============================================================================
# Interactive SSL Setup Wizard
# =============================================================================

# Interactive SSL setup wizard
milou_ssl_interactive_setup() {
    ssl_log "INFO" "🔒 Starting SSL certificate setup wizard..."
    
    local domain="${DOMAIN:-localhost}"
    local ssl_path="${SSL_PATH:-./ssl}"
    
    # Check if we're in non-interactive mode
    if [[ "${INTERACTIVE:-true}" == "false" ]]; then
        ssl_log "INFO" "Non-interactive mode detected, using automatic SSL setup"
        
        # Use self-signed certificates for localhost or development
        if [[ "$domain" == "localhost" || "$domain" == "127.0.0.1" ]]; then
            ssl_log "INFO" "Generating self-signed certificate for localhost"
            generate_ssl_certificate "$domain" "$ssl_path" "selfsigned"
        else
            ssl_log "INFO" "Using Let's Encrypt for domain: $domain"
            generate_ssl_certificate "$domain" "$ssl_path" "letsencrypt"
        fi
        
        return $?
    fi
    
    # Interactive setup
    echo
    ssl_log "INFO" "SSL Certificate Setup Options:"
    echo "  Domain: $domain"
    echo "  SSL Path: $ssl_path"
    echo
    
    # Check if certificates already exist
    if [[ -f "$ssl_path/$SSL_CERT_FILE" && -f "$ssl_path/$SSL_KEY_FILE" ]]; then
        ssl_log "INFO" "Existing SSL certificates found"
        
        if validate_ssl_certificate "$ssl_path/$SSL_CERT_FILE" "$ssl_path/$SSL_KEY_FILE" "$domain"; then
            ssl_log "SUCCESS" "Existing certificates are valid"
            
            if ask_yes_no "Use existing SSL certificates?"; then
                ssl_log "INFO" "Using existing SSL certificates"
                return 0
            fi
        else
            ssl_log "WARN" "Existing certificates are invalid or expired"
        fi
    fi
    
    # SSL provider selection
    echo
    ssl_log "INFO" "Choose SSL certificate provider:"
    echo "  1) Self-signed (for development/localhost)"
    echo "  2) Let's Encrypt (for production domains)"
    echo "  3) Custom certificates (provide your own)"
    
    local ssl_choice
    read -p "Choose option (1-3, default: 1): " ssl_choice
    ssl_choice="${ssl_choice:-1}"
    
    case "$ssl_choice" in
        1)
            ssl_log "INFO" "Generating self-signed certificate..."
            generate_ssl_certificate "$domain" "$ssl_path" "selfsigned"
            ;;
        2)
            if [[ "$domain" == "localhost" || "$domain" == "127.0.0.1" ]]; then
                ssl_log "WARN" "Let's Encrypt cannot be used with localhost"
                ssl_log "INFO" "Falling back to self-signed certificate"
                generate_ssl_certificate "$domain" "$ssl_path" "selfsigned"
            else
                ssl_log "INFO" "Setting up Let's Encrypt certificate..."
                generate_ssl_certificate "$domain" "$ssl_path" "letsencrypt"
            fi
            ;;
        3)
            ssl_log "INFO" "Custom certificate setup"
            echo
            read -p "Path to certificate file (.crt): " cert_file
            read -p "Path to private key file (.key): " key_file
            
            if [[ -f "$cert_file" && -f "$key_file" ]]; then
                if validate_ssl_certificate "$cert_file" "$key_file" "$domain"; then
                    mkdir -p "$ssl_path"
                    cp "$cert_file" "$ssl_path/$SSL_CERT_FILE"
                    cp "$key_file" "$ssl_path/$SSL_KEY_FILE"
                    ssl_log "SUCCESS" "Custom certificates installed"
                else
                    ssl_log "ERROR" "Custom certificate validation failed"
                    return 1
                fi
            else
                ssl_log "ERROR" "Certificate files not found"
                return 1
            fi
            ;;
        *)
            ssl_log "ERROR" "Invalid option selected"
            return 1
            ;;
    esac
    
    # Verify final setup
    if [[ -f "$ssl_path/$SSL_CERT_FILE" && -f "$ssl_path/$SSL_KEY_FILE" ]]; then
        ssl_log "SUCCESS" "SSL certificate setup completed"
        show_ssl_status "$ssl_path"
        return 0
    else
        ssl_log "ERROR" "SSL certificate setup failed"
        return 1
    fi
}

# =============================================================================
# Certificate Validation and Auto-Renewal (Lines 401-500)
# =============================================================================

# Check if certificate is about to expire
check_certificate_expiration() {
    local cert_file="${1:-$SSL_PATH/$SSL_CERT_FILE}"
    local warning_days="${2:-$CERT_MIN_DAYS}"
    
    if [[ ! -f "$cert_file" ]]; then
        ssl_log "WARN" "Certificate file not found: $cert_file"
        return 1
    fi
    
    if ! command -v openssl >/dev/null 2>&1; then
        ssl_log "WARN" "OpenSSL not available for certificate validation"
        return 1
    fi
    
    # Get certificate expiration date
    local expiry_date
    expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
    
    if [[ -z "$expiry_date" ]]; then
        ssl_log "ERROR" "Cannot read certificate expiration date"
        return 1
    fi
    
    # Convert to epoch time
    local expiry_epoch
    if command -v date >/dev/null 2>&1; then
        expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null)
    else
        ssl_log "WARN" "Cannot parse certificate expiration date"
        return 1
    fi
    
    local current_epoch=$(date +%s)
    local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    ssl_log "INFO" "Certificate expires in $days_until_expiry days"
    
    if [[ $days_until_expiry -le $warning_days ]]; then
        ssl_log "WARN" "Certificate expires in $days_until_expiry days (warning threshold: $warning_days)"
        return 2  # Warning: certificate expires soon
    elif [[ $days_until_expiry -le 0 ]]; then
        ssl_log "ERROR" "Certificate has expired!"
        return 3  # Error: certificate expired
    fi
    
    ssl_log "SUCCESS" "Certificate is valid for $days_until_expiry more days"
    return 0
}

# Auto-renew certificate if needed
auto_renew_certificate() {
    local domain="${1:-$DOMAIN}"
    local ssl_path="${2:-$SSL_PATH}"
    local force="${3:-false}"
    
    ssl_log "INFO" "Checking certificate auto-renewal for: $domain"
    
    local cert_file="$ssl_path/$SSL_CERT_FILE"
    local renewal_needed=false
    
    if [[ "$force" == "true" ]]; then
        ssl_log "INFO" "Forced renewal requested"
        renewal_needed=true
    elif [[ ! -f "$cert_file" ]]; then
        ssl_log "INFO" "Certificate not found, generating new one"
        renewal_needed=true
    else
        # Check expiration
        check_certificate_expiration "$cert_file" "$CERT_MIN_DAYS"
        local check_result=$?
        
        case $check_result in
            2|3)  # Warning or expired
                ssl_log "INFO" "Certificate renewal needed"
                renewal_needed=true
                ;;
            0)    # Valid
                ssl_log "INFO" "Certificate is still valid, no renewal needed"
                return 0
                ;;
            *)    # Error checking
                ssl_log "WARN" "Cannot determine certificate status, renewing to be safe"
                renewal_needed=true
                ;;
        esac
    fi
    
    if [[ "$renewal_needed" == "true" ]]; then
        ssl_log "STEP" "Renewing SSL certificate for: $domain"
        
        # Backup existing certificate if it exists
        if [[ -f "$cert_file" ]]; then
            local backup_dir="$ssl_path/backup-$(date +%Y%m%d-%H%M%S)"
            mkdir -p "$backup_dir"
            cp "$cert_file" "$backup_dir/" 2>/dev/null || true
            cp "$ssl_path/$SSL_KEY_FILE" "$backup_dir/" 2>/dev/null || true
            ssl_log "INFO" "Backed up existing certificates to: $backup_dir"
        fi
        
        # Determine certificate type based on domain
        local cert_type="selfsigned"
        if [[ "$domain" != "localhost" && ! "$domain" =~ \.local$ ]] && check_letsencrypt_prerequisites "$domain"; then
            cert_type="letsencrypt"
        fi
        
        # Generate new certificate
        if generate_ssl_certificate "$domain" "$ssl_path" "$cert_type"; then
            ssl_log "SUCCESS" "Certificate renewed successfully"
            
            # Restart nginx if running in Docker
            if command -v docker >/dev/null 2>&1 && docker ps --format "{{.Names}}" | grep -q "nginx"; then
                ssl_log "INFO" "Restarting nginx to load new certificate"
                docker restart milou-nginx 2>/dev/null || true
            fi
            
            return 0
        else
            ssl_log "ERROR" "Certificate renewal failed"
            return 1
        fi
    fi
    
    return 0
}

# Setup automatic certificate renewal (cron job)
setup_auto_renewal() {
    local domain="${1:-$DOMAIN}"
    local ssl_path="${2:-$SSL_PATH}"
    
    ssl_log "INFO" "Setting up automatic certificate renewal"
    
    # Create renewal script
    local renewal_script="/usr/local/bin/milou-ssl-renew"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    if [[ $EUID -eq 0 ]]; then
        cat > "$renewal_script" << EOF
#!/bin/bash
# Milou SSL Certificate Auto-Renewal Script
# Generated on $(date)

cd "$script_dir"
./milou.sh ssl-renew --domain "$domain" --ssl-path "$ssl_path" --quiet
EOF
        chmod +x "$renewal_script"
        
        # Add cron job (check daily at 2 AM)
        local cron_entry="0 2 * * * $renewal_script"
        
        if command -v crontab >/dev/null 2>&1; then
            # Check if entry already exists
            if ! crontab -l 2>/dev/null | grep -q "$renewal_script"; then
                (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
                ssl_log "SUCCESS" "Automatic renewal cron job added"
            else
                ssl_log "INFO" "Automatic renewal cron job already exists"
            fi
        else
            ssl_log "WARN" "Cron not available, automatic renewal not configured"
        fi
        
        ssl_log "SUCCESS" "Automatic renewal setup completed"
        ssl_log "INFO" "Renewal script: $renewal_script"
        ssl_log "INFO" "Cron schedule: Daily at 2:00 AM"
    else
        ssl_log "WARN" "Root privileges required for automatic renewal setup"
        ssl_log "INFO" "You can manually run: ./milou.sh ssl-renew"
    fi
}

# =============================================================================
# SSL Status and Information Functions (Lines 501-600)
# =============================================================================

# Export main functions for external use
export -f setup_ssl generate_ssl_certificate validate_ssl_certificate show_ssl_status
export -f backup_ssl_certificates restore_ssl_certificates clean_ssl_certificates milou_ssl_interactive_setup 