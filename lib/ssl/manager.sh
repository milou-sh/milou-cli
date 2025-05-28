#!/bin/bash

# =============================================================================
# SSL Certificate Manager - Centralized SSL Handling for Milou CLI
# Handles ALL SSL operations: generation, preservation, validation, and cleanup
# =============================================================================

# Ensure this script is sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Guard against multiple loading
if [[ "${MILOU_SSL_MANAGER_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_SSL_MANAGER_LOADED="true"

# Ensure logging is available
if ! command -v milou_log >/dev/null 2>&1; then
    source "${SCRIPT_DIR}/lib/core/logging.sh" 2>/dev/null || {
        echo "ERROR: Cannot load logging module" >&2
        exit 1
    }
fi

# =============================================================================
# CONSTANTS AND CONFIGURATION
# =============================================================================

# Single source of truth for SSL paths
readonly MILOU_SSL_DIR="${SCRIPT_DIR}/ssl"
readonly MILOU_SSL_CERT_FILE="${MILOU_SSL_DIR}/milou.crt"
readonly MILOU_SSL_KEY_FILE="${MILOU_SSL_DIR}/milou.key"
readonly MILOU_SSL_INFO_FILE="${MILOU_SSL_DIR}/.ssl_info"
readonly MILOU_SSL_CONFIG_FILE="${MILOU_SSL_DIR}/openssl.conf"

# Certificate defaults
readonly MILOU_SSL_DEFAULT_VALIDITY_DAYS=365
readonly MILOU_SSL_DEFAULT_KEY_SIZE=2048

# =============================================================================
# CORE SSL MANAGEMENT FUNCTIONS
# =============================================================================

# Initialize SSL directory structure
milou_ssl_init() {
    local quiet="${1:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Initializing SSL directory structure"
    
    # Create SSL directory if it doesn't exist
    if [[ ! -d "$MILOU_SSL_DIR" ]]; then
        mkdir -p "$MILOU_SSL_DIR" || {
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to create SSL directory: $MILOU_SSL_DIR"
            return 1
        }
        [[ "$quiet" != "true" ]] && milou_log "INFO" "Created SSL directory: $MILOU_SSL_DIR"
    fi
    
    # Set secure permissions
    chmod 755 "$MILOU_SSL_DIR" 2>/dev/null || true
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "SSL directory structure initialized"
    return 0
}

# Get SSL status and information
milou_ssl_status() {
    local domain="${1:-localhost}"
    local quiet="${2:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🔍 SSL Certificate Status"
    
    # Check if certificates exist
    if [[ ! -f "$MILOU_SSL_CERT_FILE" || ! -f "$MILOU_SSL_KEY_FILE" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "INFO" "📋 Status: No certificates found"
        return 1
    fi
    
    # Check certificate validity
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
        local cert_modulus key_modulus
        cert_modulus=$(openssl x509 -noout -modulus -in "$MILOU_SSL_CERT_FILE" 2>/dev/null | md5sum | cut -d' ' -f1 || echo "")
        key_modulus=$(openssl rsa -noout -modulus -in "$MILOU_SSL_KEY_FILE" 2>/dev/null | md5sum | cut -d' ' -f1 || echo "")
        
        if [[ -n "$cert_modulus" && "$cert_modulus" == "$key_modulus" ]]; then
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
        if openssl x509 -in "$MILOU_SSL_CERT_FILE" -noout -text 2>/dev/null | grep -E "(CN|DNS).*$domain" >/dev/null; then
            domain_match=true
        fi
    fi
    
    # Display status
    if [[ "$quiet" != "true" ]]; then
        echo "  📁 Location: $MILOU_SSL_DIR"
        echo "  📄 Certificate: $([ "$cert_valid" == "true" ] && echo "✅ Valid" || echo "❌ Invalid")"
        echo "  🔑 Private Key: $([ "$key_valid" == "true" ] && echo "✅ Valid" || echo "❌ Invalid")"
        echo "  🔗 Cert-Key Match: $([ "$cert_key_match" == "true" ] && echo "✅ Match" || echo "❌ Mismatch")"
        echo "  🌐 Domain Match: $([ "$domain_match" == "true" ] && echo "✅ $domain" || echo "❌ Not for $domain")"
        echo "  ⏰ Expiration: $([ "$cert_expired" == "true" ] && echo "❌ Expired" || echo "✅ Valid ($days_until_expiry days)")"
    fi
    
    # Return overall status
    if [[ "$cert_valid" == "true" && "$key_valid" == "true" && "$cert_key_match" == "true" && "$cert_expired" != "true" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ SSL certificates are healthy"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "WARN" "⚠️ SSL certificates need attention"
        return 1
    fi
}

# Intelligent SSL setup - handles all scenarios
milou_ssl_setup() {
    local domain="${1:-localhost}"
    local ssl_mode="${2:-auto}"  # auto, generate, existing, none
    local cert_path="${3:-}"
    local force="${4:-false}"
    local quiet="${5:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "STEP" "🔒 SSL Certificate Setup"
    [[ "$quiet" != "true" ]] && milou_log "INFO" "Domain: $domain | Mode: $ssl_mode"
    
    # Initialize SSL directory
    milou_ssl_init "$quiet" || return 1
    
    case "$ssl_mode" in
        "none")
            [[ "$quiet" != "true" ]] && milou_log "INFO" "⚠️ SSL disabled - using HTTP only"
            milou_ssl_cleanup_certificates "$quiet"
            return 0
            ;;
        "existing")
            [[ "$quiet" != "true" ]] && milou_log "INFO" "📁 Using existing/provided SSL certificates"
            milou_ssl_setup_existing "$domain" "$cert_path" "$force" "$quiet"
            return $?
            ;;
        "generate")
            [[ "$quiet" != "true" ]] && milou_log "INFO" "🔧 Generating new SSL certificates"
            milou_ssl_generate_certificates "$domain" "$force" "$quiet"
            return $?
            ;;
        "auto")
            [[ "$quiet" != "true" ]] && milou_log "INFO" "🧠 Automatic SSL certificate management"
            milou_ssl_auto_setup "$domain" "$force" "$quiet"
            return $?
            ;;
        *)
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "Unknown SSL mode: $ssl_mode"
            return 1
            ;;
    esac
}

# Automatic SSL setup - intelligent decision making
milou_ssl_auto_setup() {
    local domain="$1"
    local force="$2"
    local quiet="$3"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🤖 Analyzing SSL certificate requirements..."
    
    # Check current certificate status
    if [[ "$force" != "true" ]] && milou_ssl_status "$domain" "true"; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Existing certificates are healthy - preserving them"
        milou_ssl_save_info "$domain" "preserved" "$quiet"
        return 0
    fi
    
    # Check if certificates exist but are problematic
    if [[ -f "$MILOU_SSL_CERT_FILE" || -f "$MILOU_SSL_KEY_FILE" ]]; then
        if [[ "$force" == "true" ]]; then
            [[ "$quiet" != "true" ]] && milou_log "INFO" "🔄 Force mode - regenerating certificates"
        else
            [[ "$quiet" != "true" ]] && milou_log "INFO" "🔄 Existing certificates are problematic - regenerating"
        fi
        milou_ssl_backup_certificates "$quiet"
    else
        [[ "$quiet" != "true" ]] && milou_log "INFO" "🆕 No certificates found - generating new ones"
    fi
    
    # Generate new certificates
    milou_ssl_generate_certificates "$domain" "$force" "$quiet"
}

# Generate new SSL certificates
milou_ssl_generate_certificates() {
    local domain="$1"
    local force="$2"
    local quiet="$3"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🔧 Generating SSL certificates for: $domain"
    
    # Check if OpenSSL is available
    if ! command -v openssl >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "OpenSSL is required but not installed"
        return 1
    fi
    
    # Backup existing certificates if they exist and force is not set
    if [[ "$force" != "true" ]] && [[ -f "$MILOU_SSL_CERT_FILE" || -f "$MILOU_SSL_KEY_FILE" ]]; then
        milou_ssl_backup_certificates "$quiet"
    fi
    
    # Create OpenSSL configuration
    milou_ssl_create_openssl_config "$domain" "$quiet" || return 1
    
    # Generate private key
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Generating private key..."
    if ! openssl genrsa -out "$MILOU_SSL_KEY_FILE" "$MILOU_SSL_DEFAULT_KEY_SIZE" 2>/dev/null; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to generate private key"
        return 1
    fi
    
    # Generate certificate
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Generating certificate..."
    if ! openssl req -new -x509 -key "$MILOU_SSL_KEY_FILE" -out "$MILOU_SSL_CERT_FILE" \
         -days "$MILOU_SSL_DEFAULT_VALIDITY_DAYS" -config "$MILOU_SSL_CONFIG_FILE" \
         -extensions v3_req 2>/dev/null; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to generate certificate"
        return 1
    fi
    
    # Set secure permissions
    chmod 644 "$MILOU_SSL_CERT_FILE" 2>/dev/null || true
    chmod 600 "$MILOU_SSL_KEY_FILE" 2>/dev/null || true
    
    # Clean up config file
    rm -f "$MILOU_SSL_CONFIG_FILE" 2>/dev/null || true
    
    # Validate generated certificates
    if milou_ssl_status "$domain" "true"; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ SSL certificates generated successfully"
        milou_ssl_save_info "$domain" "generated" "$quiet"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Generated certificates failed validation"
        return 1
    fi
}

# Setup existing certificates (copy from user location)
milou_ssl_setup_existing() {
    local domain="$1"
    local cert_path="$2"
    local force="$3"
    local quiet="$4"
    
    if [[ -z "$cert_path" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate path is required for existing mode"
        return 1
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "📁 Setting up existing certificates from: $cert_path"
    
    local source_cert source_key
    
    # Determine source files
    if [[ -f "$cert_path" ]]; then
        # Single file provided - assume it's the certificate
        source_cert="$cert_path"
        local cert_dir
        cert_dir=$(dirname "$cert_path")
        local base_name
        base_name=$(basename "$cert_path" .crt)
        base_name=$(basename "$base_name" .pem)
        
        # Look for corresponding key file
        for key_ext in ".key" ".pem" "_key.pem"; do
            if [[ -f "${cert_dir}/${base_name}${key_ext}" ]]; then
                source_key="${cert_dir}/${base_name}${key_ext}"
                break
            fi
        done
        
        if [[ -z "$source_key" ]]; then
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "Could not find corresponding private key for: $cert_path"
            return 1
        fi
    elif [[ -d "$cert_path" ]]; then
        # Directory provided - look for standard files
        source_cert="$cert_path/milou.crt"
        source_key="$cert_path/milou.key"
        
        if [[ ! -f "$source_cert" ]]; then
            # Try alternative names
            for cert_name in "server.crt" "certificate.crt" "cert.pem" "server.pem"; do
                if [[ -f "$cert_path/$cert_name" ]]; then
                    source_cert="$cert_path/$cert_name"
                    break
                fi
            done
        fi
        
        if [[ ! -f "$source_key" ]]; then
            # Try alternative names
            for key_name in "server.key" "private.key" "key.pem" "server.pem"; do
                if [[ -f "$cert_path/$key_name" ]]; then
                    source_key="$cert_path/$key_name"
                    break
                fi
            done
        fi
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate path does not exist: $cert_path"
        return 1
    fi
    
    # Validate source files
    if [[ ! -f "$source_cert" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate file not found: $source_cert"
        return 1
    fi
    
    if [[ ! -f "$source_key" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Private key file not found: $source_key"
        return 1
    fi
    
    # Validate certificate and key
    if ! openssl x509 -in "$source_cert" -noout -text >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Invalid certificate file: $source_cert"
        return 1
    fi
    
    if ! openssl rsa -in "$source_key" -check -noout >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Invalid private key file: $source_key"
        return 1
    fi
    
    # Check if certificate and key match
    local cert_modulus key_modulus
    cert_modulus=$(openssl x509 -noout -modulus -in "$source_cert" 2>/dev/null | md5sum | cut -d' ' -f1 || echo "")
    key_modulus=$(openssl rsa -noout -modulus -in "$source_key" 2>/dev/null | md5sum | cut -d' ' -f1 || echo "")
    
    if [[ -z "$cert_modulus" || "$cert_modulus" != "$key_modulus" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate and private key do not match"
        return 1
    fi
    
    # Backup existing certificates if they exist
    if [[ "$force" != "true" ]] && [[ -f "$MILOU_SSL_CERT_FILE" || -f "$MILOU_SSL_KEY_FILE" ]]; then
        milou_ssl_backup_certificates "$quiet"
    fi
    
    # Copy certificates to SSL directory
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Copying certificate files..."
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
    
    # Validate setup
    if milou_ssl_status "$domain" "true"; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Existing certificates setup successfully"
        milou_ssl_save_info "$domain" "existing" "$quiet"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate setup validation failed"
        return 1
    fi
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Create OpenSSL configuration file
milou_ssl_create_openssl_config() {
    local domain="$1"
    local quiet="$2"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Creating OpenSSL configuration for: $domain"
    
    cat > "$MILOU_SSL_CONFIG_FILE" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C=US
ST=State
L=City
O=Milou
OU=IT Department
CN=$domain

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $domain
DNS.2 = localhost
DNS.3 = *.localhost
IP.1 = 127.0.0.1
IP.2 = ::1
EOF
    
    # Add domain-specific SAN entries
    if [[ "$domain" != "localhost" ]]; then
        echo "DNS.4 = *.$domain" >> "$MILOU_SSL_CONFIG_FILE"
    fi
    
    return 0
}

# Save SSL information metadata
milou_ssl_save_info() {
    local domain="$1"
    local action="$2"
    local quiet="$3"
    
    cat > "$MILOU_SSL_INFO_FILE" << EOF
# SSL Certificate Information
DOMAIN=$domain
ACTION=$action
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GENERATED_BY=milou-cli
VALIDITY_DAYS=$MILOU_SSL_DEFAULT_VALIDITY_DAYS
KEY_SIZE=$MILOU_SSL_DEFAULT_KEY_SIZE
EOF
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "SSL info saved: $action for $domain"
}

# Backup existing certificates
milou_ssl_backup_certificates() {
    local quiet="$1"
    
    if [[ ! -f "$MILOU_SSL_CERT_FILE" && ! -f "$MILOU_SSL_KEY_FILE" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "No certificates to backup"
        return 0
    fi
    
    local backup_dir="${MILOU_SSL_DIR}/backup"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    
    mkdir -p "$backup_dir" || {
        [[ "$quiet" != "true" ]] && milou_log "WARN" "Could not create backup directory"
        return 1
    }
    
    local backed_up=0
    if [[ -f "$MILOU_SSL_CERT_FILE" ]]; then
        cp "$MILOU_SSL_CERT_FILE" "$backup_dir/milou.crt.${timestamp}" && ((backed_up++))
    fi
    
    if [[ -f "$MILOU_SSL_KEY_FILE" ]]; then
        cp "$MILOU_SSL_KEY_FILE" "$backup_dir/milou.key.${timestamp}" && ((backed_up++))
    fi
    
    if [[ "$backed_up" -gt 0 ]]; then
        [[ "$quiet" != "true" ]] && milou_log "INFO" "📦 Backed up $backed_up certificate files to: $backup_dir"
    fi
    
    return 0
}

# Clean up SSL certificates
milou_ssl_cleanup_certificates() {
    local quiet="$1"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Cleaning up SSL certificates..."
    
    # Remove certificate files
    rm -f "$MILOU_SSL_CERT_FILE" "$MILOU_SSL_KEY_FILE" "$MILOU_SSL_CONFIG_FILE" 2>/dev/null || true
    
    # Remove info file for SSL disabled mode
    if [[ -f "$MILOU_SSL_INFO_FILE" ]]; then
        milou_ssl_backup_certificates "$quiet"
        rm -f "$MILOU_SSL_INFO_FILE" 2>/dev/null || true
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🧹 SSL certificates cleaned up"
    return 0
}

# Get SSL directory path (for Docker Compose mounting)
milou_ssl_get_path() {
    echo "$MILOU_SSL_DIR"
}

# Check if SSL is enabled
milou_ssl_is_enabled() {
    [[ -f "$MILOU_SSL_CERT_FILE" && -f "$MILOU_SSL_KEY_FILE" ]]
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f milou_ssl_init
export -f milou_ssl_status
export -f milou_ssl_setup
export -f milou_ssl_auto_setup
export -f milou_ssl_generate_certificates
export -f milou_ssl_setup_existing
export -f milou_ssl_create_openssl_config
export -f milou_ssl_save_info
export -f milou_ssl_backup_certificates
export -f milou_ssl_cleanup_certificates
export -f milou_ssl_get_path
export -f milou_ssl_is_enabled 