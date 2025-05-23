#!/bin/bash

# =============================================================================
# Milou SSL Certificate Manager
# Unified SSL certificate management for development and production
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
DEFAULT_SSL_PATH="./ssl"
DEFAULT_DOMAIN="localhost"

# Load environment if exists
if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

SSL_PATH="${SSL_CERT_PATH:-$DEFAULT_SSL_PATH}"
DOMAIN="${CUSTOMER_DOMAIN_NAME:-$DEFAULT_DOMAIN}"

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "ERROR")   echo -e "${RED}❌ [ERROR] $message${NC}" ;;
        "WARN")    echo -e "${YELLOW}⚠️  [WARN] $message${NC}" ;;
        "SUCCESS") echo -e "${GREEN}✅ [SUCCESS] $message${NC}" ;;
        "INFO")    echo -e "${BLUE}ℹ️ [INFO] $message${NC}" ;;
        "STEP")    echo -e "${PURPLE}⚙️ [STEP] $message${NC}" ;;
        *)         echo -e "[$level] $message" ;;
    esac
}

show_help() {
    cat << EOF
Milou SSL Certificate Manager

USAGE:
    $(basename "$0") [COMMAND] [OPTIONS]

COMMANDS:
    status          Show current SSL certificate status
    generate        Generate self-signed certificates
    validate        Validate existing certificates
    clean           Clean up all SSL certificates
    consolidate     Consolidate scattered certificates
    setup           Interactive SSL setup

OPTIONS:
    --domain DOMAIN     Domain name (default: $DOMAIN)
    --ssl-path PATH     SSL certificate path (default: $SSL_PATH)
    --force             Force operation without prompts
    --help              Show this help

EXAMPLES:
    $(basename "$0") status                    # Check current SSL status
    $(basename "$0") generate --domain example.com  # Generate cert for domain
    $(basename "$0") clean                     # Clean up all certificates
    $(basename "$0") consolidate               # Fix scattered certificates

EOF
}

get_ssl_status() {
    log "INFO" "SSL Certificate Status Report"
    echo
    
    # Check configured SSL path
    log "INFO" "Configuration:"
    echo "  SSL Path: $SSL_PATH"
    echo "  Domain: $DOMAIN"
    echo
    
    # Find all certificate files
    log "INFO" "Certificate Files Found:"
    local found_certs=false
    
    while IFS= read -r -d '' file; do
        found_certs=true
        local size=$(stat -c%s "$file" 2>/dev/null || echo "0")
        local perms=$(stat -c%A "$file" 2>/dev/null || echo "unknown")
        echo "  📁 $file (${size} bytes, $perms)"
        
        # Try to get certificate info
        if [[ "$file" =~ \.crt$ ]] && command -v openssl >/dev/null 2>&1; then
            local subject=$(openssl x509 -in "$file" -noout -subject 2>/dev/null | sed 's/subject=/  Subject: /' || echo "  Subject: Invalid certificate")
            local expiry=$(openssl x509 -in "$file" -noout -enddate 2>/dev/null | sed 's/notAfter=/  Expires: /' || echo "  Expires: Invalid certificate")
            echo "$subject"
            echo "$expiry"
        fi
        echo
    done < <(find . -name "*.crt" -o -name "*.key" -o -name "*.pem" -print0 2>/dev/null)
    
    if [[ "$found_certs" == false ]]; then
        log "WARN" "No SSL certificates found"
    fi
    
    # Check what docker-compose expects
    log "INFO" "Docker Compose Configuration:"
    if [[ -f "./static/docker-compose.yml" ]]; then
        local nginx_volume=$(grep -A5 "nginx:" "./static/docker-compose.yml" | grep "volumes:" -A1 | grep ssl || echo "  No SSL volume configured")
        echo "  $nginx_volume"
    else
        log "WARN" "docker-compose.yml not found"
    fi
}

generate_certificates() {
    local domain="$1"
    local ssl_path="$2"
    
    log "STEP" "Generating self-signed SSL certificate for: $domain"
    
    # Create SSL directory
    mkdir -p "$ssl_path"
    
    if ! command -v openssl >/dev/null 2>&1; then
        log "ERROR" "OpenSSL is required for certificate generation"
        return 1
    fi
    
    local cert_file="$ssl_path/milou.crt"
    local key_file="$ssl_path/milou.key"
    local config_file="$ssl_path/openssl.cnf"
    
    # Create OpenSSL configuration
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
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

    # Generate private key
    openssl genrsa -out "$key_file" 2048
    
    # Generate certificate
    openssl req -new -x509 -key "$key_file" -out "$cert_file" -days 365 -config "$config_file" -extensions v3_req
    
    # Set appropriate permissions
    chmod 644 "$cert_file"
    chmod 600 "$key_file"
    rm -f "$config_file"
    
    log "SUCCESS" "SSL certificate generated successfully"
    log "INFO" "Certificate: $cert_file"
    log "INFO" "Private key: $key_file"
    
    # Validate the generated certificate
    if validate_certificate "$cert_file" "$key_file"; then
        log "SUCCESS" "Generated certificate is valid"
        return 0
    else
        log "ERROR" "Generated certificate failed validation"
        return 1
    fi
}

validate_certificate() {
    local cert_file="$1"
    local key_file="$2"
    
    if [[ ! -f "$cert_file" ]] || [[ ! -f "$key_file" ]]; then
        log "ERROR" "Certificate files not found"
        return 1
    fi
    
    if ! command -v openssl >/dev/null 2>&1; then
        log "WARN" "OpenSSL not available - skipping validation"
        return 0
    fi
    
    # Check certificate format
    if ! openssl x509 -in "$cert_file" -noout 2>/dev/null; then
        log "ERROR" "Invalid certificate format"
        return 1
    fi
    
    # Check private key format
    if ! openssl rsa -in "$key_file" -check -noout 2>/dev/null; then
        log "ERROR" "Invalid private key format"
        return 1
    fi
    
    # Check if certificate and key match
    local cert_modulus key_modulus
    cert_modulus=$(openssl x509 -noout -modulus -in "$cert_file" 2>/dev/null | openssl md5)
    key_modulus=$(openssl rsa -noout -modulus -in "$key_file" 2>/dev/null | openssl md5)
    
    if [[ "$cert_modulus" != "$key_modulus" ]]; then
        log "ERROR" "Certificate and private key do not match"
        return 1
    fi
    
    log "SUCCESS" "Certificate validation passed"
    return 0
}

clean_certificates() {
    log "STEP" "Cleaning up all SSL certificates..."
    
    local cert_files=()
    while IFS= read -r -d '' file; do
        cert_files+=("$file")
    done < <(find . -name "*.crt" -o -name "*.key" -o -name "*.pem" -print0 2>/dev/null)
    
    if [[ ${#cert_files[@]} -eq 0 ]]; then
        log "INFO" "No SSL certificates found to clean"
        return 0
    fi
    
    echo "Found ${#cert_files[@]} SSL certificate files:"
    for file in "${cert_files[@]}"; do
        echo "  - $file"
    done
    echo
    
    if [[ "${FORCE:-false}" != "true" ]]; then
        read -p "Are you sure you want to delete all these files? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "INFO" "Operation cancelled"
            return 0
        fi
    fi
    
    for file in "${cert_files[@]}"; do
        if sudo rm -f "$file" 2>/dev/null || rm -f "$file" 2>/dev/null; then
            log "SUCCESS" "Removed: $file"
        else
            log "ERROR" "Failed to remove: $file"
        fi
    done
    
    # Clean up empty SSL directories
    find . -type d -name "*ssl*" -empty -delete 2>/dev/null || true
    
    log "SUCCESS" "SSL cleanup completed"
}

consolidate_certificates() {
    log "STEP" "Consolidating SSL certificates..."
    
    # Ensure target directory exists
    mkdir -p "$SSL_PATH"
    
    local target_cert="$SSL_PATH/milou.crt"
    local target_key="$SSL_PATH/milou.key"
    
    # Find the best certificate to use
    local best_cert=""
    local best_key=""
    
    # Priority order for certificate selection
    local cert_candidates=(
        "./ssl/milou.crt"
        "./certificates/server.crt"
        "./certificates/milou.crt"
    )
    
    local key_candidates=(
        "./ssl/milou.key"
        "./certificates/server.key"
        "./certificates/milou.key"
    )
    
    # Find the first valid certificate pair
    for i in "${!cert_candidates[@]}"; do
        local cert="${cert_candidates[$i]}"
        local key="${key_candidates[$i]}"
        
        if [[ -f "$cert" ]] && [[ -f "$key" ]]; then
            if validate_certificate "$cert" "$key"; then
                best_cert="$cert"
                best_key="$key"
                break
            fi
        fi
    done
    
    if [[ -n "$best_cert" ]] && [[ -n "$best_key" ]]; then
        # Copy the best certificate to the standard location
        cp "$best_cert" "$target_cert"
        cp "$best_key" "$target_key"
        chmod 644 "$target_cert"
        chmod 600 "$target_key"
        
        log "SUCCESS" "Consolidated certificates to $SSL_PATH"
        log "INFO" "Source: $best_cert -> $target_cert"
        log "INFO" "Source: $best_key -> $target_key"
        
        # Remove other certificate files (but keep the ones we just copied)
        local cleanup_files=()
        while IFS= read -r -d '' file; do
            if [[ "$file" != "$target_cert" ]] && [[ "$file" != "$target_key" ]]; then
                cleanup_files+=("$file")
            fi
        done < <(find . -name "*.crt" -o -name "*.key" -print0 2>/dev/null)
        
        for file in "${cleanup_files[@]}"; do
            if sudo rm -f "$file" 2>/dev/null || rm -f "$file" 2>/dev/null; then
                log "INFO" "Cleaned up: $file"
            fi
        done
        
        return 0
    else
        log "WARN" "No valid certificate pairs found - generating new certificates"
        generate_certificates "$DOMAIN" "$SSL_PATH"
        return $?
    fi
}

interactive_setup() {
    log "STEP" "Interactive SSL Setup"
    echo
    echo "Current configuration:"
    echo "  Domain: $DOMAIN"
    echo "  SSL Path: $SSL_PATH"
    echo
    
    echo "SSL Setup Options:"
    echo "  1) Generate self-signed certificate (development)"
    echo "  2) Consolidate existing certificates"
    echo "  3) Clean up and generate fresh certificates"
    echo "  4) Show current status only"
    echo
    
    while true; do
        read -p "Choose an option (1-4): " choice
        case "$choice" in
            1)
                generate_certificates "$DOMAIN" "$SSL_PATH"
                break
                ;;
            2)
                consolidate_certificates
                break
                ;;
            3)
                clean_certificates
                generate_certificates "$DOMAIN" "$SSL_PATH"
                break
                ;;
            4)
                get_ssl_status
                break
                ;;
            *)
                echo "Invalid choice. Please enter 1-4."
                ;;
        esac
    done
}

# Parse arguments
COMMAND=""
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        status|generate|validate|clean|consolidate|setup)
            COMMAND="$1"
            shift
            ;;
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --ssl-path)
            SSL_PATH="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Execute command
case "$COMMAND" in
    status)
        get_ssl_status
        ;;
    generate)
        generate_certificates "$DOMAIN" "$SSL_PATH"
        ;;
    validate)
        if [[ -f "$SSL_PATH/milou.crt" ]] && [[ -f "$SSL_PATH/milou.key" ]]; then
            validate_certificate "$SSL_PATH/milou.crt" "$SSL_PATH/milou.key"
        else
            log "ERROR" "No certificates found at $SSL_PATH"
            exit 1
        fi
        ;;
    clean)
        clean_certificates
        ;;
    consolidate)
        consolidate_certificates
        ;;
    setup)
        interactive_setup
        ;;
    "")
        show_help
        ;;
    *)
        log "ERROR" "Unknown command: $COMMAND"
        show_help
        exit 1
        ;;
esac 