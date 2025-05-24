#!/bin/bash

# =============================================================================
# SSL Certificate Validation and Management Module for Milou CLI
# Handles certificate validation, information display, and management
# =============================================================================

# Module guard to prevent multiple loading
if [[ "${MILOU_SSL_VALIDATION_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_SSL_VALIDATION_LOADED="true"

# Ensure logging is available
if ! command -v milou_log >/dev/null 2>&1; then
    source "${SCRIPT_DIR}/lib/core/logging.sh" 2>/dev/null || {
        echo "ERROR: Cannot load logging module" >&2
        exit 1
    }
fi

# =============================================================================
# Certificate Validation Functions
# =============================================================================

# Validate SSL certificates comprehensively
validate_ssl_certificates() {
    local cert_file="$1"
    local key_file="$2"
    local domain="${3:-}"
    
    milou_log "DEBUG" "Validating SSL certificates"
    
    # Check if files exist
    if [[ ! -f "$cert_file" ]]; then
        milou_log "ERROR" "Certificate file not found: $cert_file"
        return 1
    fi
    
    if [[ ! -f "$key_file" ]]; then
        milou_log "ERROR" "Private key file not found: $key_file"
        return 1
    fi
    
    # Check file permissions
    local cert_perms key_perms
    cert_perms=$(stat -c "%a" "$cert_file" 2>/dev/null || echo "unknown")
    key_perms=$(stat -c "%a" "$key_file" 2>/dev/null || echo "unknown")
    
    if [[ "$key_perms" != "600" ]]; then
        milou_log "WARN" "Private key permissions are not secure: $key_perms (should be 600)"
        chmod 600 "$key_file" 2>/dev/null && milou_log "INFO" "Fixed private key permissions"
    fi
    
    # Validate certificate format
    if ! openssl x509 -in "$cert_file" -noout -text >/dev/null 2>&1; then
        milou_log "ERROR" "Invalid certificate format: $cert_file"
        return 1
    fi
    
    # Validate private key format
    if ! openssl rsa -in "$key_file" -check -noout >/dev/null 2>&1; then
        milou_log "ERROR" "Invalid private key format: $key_file"
        return 1
    fi
    
    # Check if certificate and key match
    local cert_modulus key_modulus
    cert_modulus=$(openssl x509 -noout -modulus -in "$cert_file" 2>/dev/null | openssl md5 2>/dev/null)
    key_modulus=$(openssl rsa -noout -modulus -in "$key_file" 2>/dev/null | openssl md5 2>/dev/null)
    
    if [[ "$cert_modulus" != "$key_modulus" ]]; then
        milou_log "ERROR" "Certificate and private key do not match"
        return 1
    fi
    
    # Check certificate expiration
    if ! check_ssl_expiration "$cert_file"; then
        milou_log "WARN" "Certificate is expired or expires soon"
        # Don't return error for expiration - just warn
    fi
    
    # Validate domain if provided
    if [[ -n "$domain" ]]; then
        if ! validate_certificate_domain "$cert_file" "$domain"; then
            milou_log "WARN" "Certificate domain validation failed for: $domain"
            return 1  # Return error for domain mismatch to trigger regeneration
        fi
    fi
    
    milou_log "SUCCESS" "SSL certificates validation passed"
    return 0
}

# Check SSL certificate expiration
check_ssl_expiration() {
    local cert_file="$1"
    local warning_days="${2:-30}"
    
    if [[ ! -f "$cert_file" ]]; then
        milou_log "ERROR" "Certificate file not found: $cert_file"
        return 1
    fi
    
    # Get certificate expiration date
    local exp_date
    exp_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
    
    if [[ -z "$exp_date" ]]; then
        milou_log "ERROR" "Could not read certificate expiration date"
        return 1
    fi
    
    # Convert to epoch time
    local exp_epoch current_epoch
    exp_epoch=$(date -d "$exp_date" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$exp_date" +%s 2>/dev/null)
    current_epoch=$(date +%s)
    
    if [[ -z "$exp_epoch" ]]; then
        milou_log "ERROR" "Could not parse certificate expiration date: $exp_date"
        return 1
    fi
    
    # Calculate days until expiration
    local days_until_exp=$(( (exp_epoch - current_epoch) / 86400 ))
    
    if [[ $days_until_exp -lt 0 ]]; then
        milou_log "ERROR" "Certificate has expired ${days_until_exp#-} days ago"
        return 1
    elif [[ $days_until_exp -le $warning_days ]]; then
        milou_log "WARN" "Certificate expires in $days_until_exp days"
        return 1
    else
        milou_log "DEBUG" "Certificate valid for $days_until_exp more days"
        return 0
    fi
}

# Validate certificate domain
validate_certificate_domain() {
    local cert_file="$1"
    local domain="$2"
    
    if [[ ! -f "$cert_file" ]]; then
        milou_log "ERROR" "Certificate file not found: $cert_file"
        return 1
    fi
    
    # Get certificate subject and SAN
    local cert_cn cert_san
    cert_cn=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed -n 's/.*CN=\([^,]*\).*/\1/p')
    cert_san=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -1 | tr ',' '\n' | grep "DNS:" | sed 's/.*DNS://')
    
    # Check if domain matches CN or SAN
    if [[ "$cert_cn" == "$domain" ]]; then
        milou_log "DEBUG" "Domain matches certificate CN: $domain"
        return 0
    fi
    
    # Check SAN entries
    while IFS= read -r san_entry; do
        san_entry=$(echo "$san_entry" | xargs)  # Trim whitespace
        if [[ "$san_entry" == "$domain" ]]; then
            milou_log "DEBUG" "Domain matches certificate SAN: $domain"
            return 0
        fi
        # Check wildcard match
        if [[ "$san_entry" == "*."* ]]; then
            local wildcard_domain="${san_entry#*.}"
            if [[ "$domain" == *".$wildcard_domain" ]]; then
                milou_log "DEBUG" "Domain matches wildcard SAN: $domain -> $san_entry"
                return 0
            fi
        fi
    done <<< "$cert_san"
    
    milou_log "WARN" "Domain '$domain' does not match certificate (CN: $cert_cn)"
    return 1
}

# =============================================================================
# Certificate Information Display Functions
# =============================================================================

# Show comprehensive SSL information
show_ssl_info() {
    local ssl_path="${1:-./ssl}"
    local cert_file="$ssl_path/milou.crt"
    local key_file="$ssl_path/milou.key"
    
    milou_log "INFO" "SSL Certificate Information"
    echo
    
    if [[ ! -f "$cert_file" ]]; then
        milou_log "ERROR" "Certificate file not found: $cert_file"
        return 1
    fi
    
    if [[ ! -f "$key_file" ]]; then
        milou_log "ERROR" "Private key file not found: $key_file"
        return 1
    fi
    
    # Show file information
    milou_log "INFO" "📁 File Locations:"
    milou_log "INFO" "  Certificate: $cert_file"
    milou_log "INFO" "  Private Key: $key_file"
    
    # Show file permissions and sizes
    local cert_perms cert_size key_perms key_size
    cert_perms=$(stat -c "%a" "$cert_file" 2>/dev/null || echo "unknown")
    cert_size=$(stat -c "%s" "$cert_file" 2>/dev/null || echo "unknown")
    key_perms=$(stat -c "%a" "$key_file" 2>/dev/null || echo "unknown")
    key_size=$(stat -c "%s" "$key_file" 2>/dev/null || echo "unknown")
    
    echo
    milou_log "INFO" "📊 File Details:"
    milou_log "INFO" "  Certificate: $cert_size bytes, permissions: $cert_perms"
    milou_log "INFO" "  Private Key: $key_size bytes, permissions: $key_perms"
    
    # Show certificate details
    show_certificate_info "$cert_file"
    
    # Validate certificates
    echo
    milou_log "INFO" "🔍 Validation Results:"
    if validate_ssl_certificates "$cert_file" "$key_file"; then
        milou_log "SUCCESS" "✅ SSL certificates are valid"
    else
        milou_log "ERROR" "❌ SSL certificates have issues"
    fi
}

# Show detailed certificate information
show_certificate_info() {
    local cert_file="$1"
    local domain="${2:-}"
    
    if [[ ! -f "$cert_file" ]]; then
        milou_log "ERROR" "Certificate file not found: $cert_file"
        return 1
    fi
    
    milou_log "DEBUG" "Reading certificate information from: $cert_file"
    
    # Extract certificate information with better error handling
    local subject issuer serial not_before not_after
    subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed 's/subject=//' || echo "Unable to read subject")
    issuer=$(openssl x509 -in "$cert_file" -noout -issuer 2>/dev/null | sed 's/issuer=//' || echo "Unable to read issuer")
    serial=$(openssl x509 -in "$cert_file" -noout -serial 2>/dev/null | sed 's/serial=//' || echo "Unable to read serial")
    not_before=$(openssl x509 -in "$cert_file" -noout -startdate 2>/dev/null | sed 's/notBefore=//' || echo "Unable to read start date")
    not_after=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | sed 's/notAfter=//' || echo "Unable to read end date")
    
    # Get certificate algorithm and key size with better error handling
    local algorithm key_size
    algorithm=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | grep "Signature Algorithm" | head -1 | awk '{print $3}' || echo "Unknown")
    key_size=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | grep "Public-Key:" | sed 's/.*(\([0-9]*\) bit).*/\1/' || echo "Unknown")
    
    # Get Subject Alternative Names with better error handling
    local san_list
    san_list=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -1 | tr ',' '\n' | sed 's/^[[:space:]]*//' | grep -v "^$" || echo "")
    
    echo
    milou_log "INFO" "🔒 Certificate Details:"
    milou_log "INFO" "  Subject: $subject"
    milou_log "INFO" "  Issuer: $issuer"
    milou_log "INFO" "  Serial: $serial"
    milou_log "INFO" "  Algorithm: $algorithm"
    milou_log "INFO" "  Key Size: $key_size bits"
    
    echo
    milou_log "INFO" "📅 Validity Period:"
    milou_log "INFO" "  Valid From: $not_before"
    milou_log "INFO" "  Valid Until: $not_after"
    
    # Calculate and show days until expiration
    local exp_epoch current_epoch days_until_exp
    exp_epoch=$(date -d "$not_after" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$not_after" +%s 2>/dev/null || echo "")
    current_epoch=$(date +%s)
    
    if [[ -n "$exp_epoch" ]]; then
        days_until_exp=$(( (exp_epoch - current_epoch) / 86400 ))
        if [[ $days_until_exp -lt 0 ]]; then
            milou_log "ERROR" "  Status: ❌ EXPIRED (${days_until_exp#-} days ago)"
        elif [[ $days_until_exp -le 30 ]]; then
            milou_log "WARN" "  Status: ⚠️  EXPIRES SOON ($days_until_exp days)"
        else
            milou_log "SUCCESS" "  Status: ✅ VALID ($days_until_exp days remaining)"
        fi
    fi
    
    # Show Subject Alternative Names
    if [[ -n "$san_list" ]]; then
        echo
        milou_log "INFO" "🌐 Subject Alternative Names:"
        while IFS= read -r san_entry; do
            [[ -n "$san_entry" ]] && milou_log "INFO" "  $san_entry"
        done <<< "$san_list"
    fi
    
    # Domain validation if provided
    if [[ -n "$domain" ]]; then
        echo
        milou_log "INFO" "🎯 Domain Validation for: $domain"
        if validate_certificate_domain "$cert_file" "$domain"; then
            milou_log "SUCCESS" "  ✅ Domain matches certificate"
        else
            milou_log "WARN" "  ⚠️  Domain does not match certificate"
        fi
    fi
    
    # Check if it's a self-signed certificate
    if [[ "$subject" == "$issuer" ]]; then
        milou_log "INFO" "  Type: Self-signed certificate"
    else
        milou_log "INFO" "  Type: CA-signed certificate"
    fi
}

# =============================================================================
# Certificate Management Functions
# =============================================================================

# Backup SSL certificates
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
    
    if cp "$cert_file" "$backup_cert" && cp "$key_file" "$backup_key"; then
        chmod 644 "$backup_cert"
        chmod 600 "$backup_key"
        
        milou_log "SUCCESS" "SSL certificates backed up:"
        milou_log "INFO" "  Certificate: $backup_cert"
        milou_log "INFO" "  Private Key: $backup_key"
        return 0
    else
        milou_log "ERROR" "Failed to backup SSL certificates"
        return 1
    fi
}

# Backup SSL certificates from nginx docker container
backup_nginx_ssl_certificates() {
    local backup_dir="${1:-./ssl_backups}"
    local backup_name="${2:-nginx_ssl_backup_$(date +%Y%m%d_%H%M%S)}"
    
    milou_log "INFO" "Backing up SSL certificates from nginx container..."
    
    # Check if nginx container is running
    if ! docker ps --filter "name=milou-nginx" --format "{{.Names}}" | grep -q "milou-nginx"; then
        milou_log "ERROR" "Nginx container (milou-nginx) is not running"
        milou_log "INFO" "Start the services first with: ./milou.sh start"
        return 1
    fi
    
    # Check if certificates exist in container
    if ! docker exec milou-nginx test -f /etc/ssl/milou.crt; then
        milou_log "ERROR" "No SSL certificate found in nginx container"
        return 1
    fi
    
    if ! docker exec milou-nginx test -f /etc/ssl/milou.key; then
        milou_log "ERROR" "No SSL private key found in nginx container"
        return 1
    fi
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    # Copy certificates from container
    local backup_cert="$backup_dir/${backup_name}.crt"
    local backup_key="$backup_dir/${backup_name}.key"
    
    if docker cp milou-nginx:/etc/ssl/milou.crt "$backup_cert" && \
       docker cp milou-nginx:/etc/ssl/milou.key "$backup_key"; then
        
        # Set appropriate permissions
        chmod 644 "$backup_cert"
        chmod 600 "$backup_key"
        
        # Get certificate info for the backup
        local cert_subject cert_expires
        cert_subject=$(openssl x509 -in "$backup_cert" -noout -subject 2>/dev/null | sed 's/subject=//' || echo "Unknown")
        cert_expires=$(openssl x509 -in "$backup_cert" -noout -enddate 2>/dev/null | sed 's/notAfter=//' || echo "Unknown")
        
        milou_log "SUCCESS" "✅ SSL certificates backed up from nginx container:"
        milou_log "INFO" "  📁 Location: $backup_dir"
        milou_log "INFO" "  🏷️  Name: $backup_name"
        milou_log "INFO" "  📄 Certificate: $backup_cert"
        milou_log "INFO" "  🔑 Private Key: $backup_key"
        milou_log "INFO" "  👤 Subject: $cert_subject"
        milou_log "INFO" "  📅 Expires: $cert_expires"
        
        return 0
    else
        milou_log "ERROR" "❌ Failed to copy SSL certificates from nginx container"
        return 1
    fi
}

# Import user's own SSL certificates
import_user_certificates() {
    local cert_source="$1"
    local key_source="$2"
    local ssl_path="${3:-./static/ssl}"
    
    milou_log "INFO" "Importing user-provided SSL certificates..."
    
    # Validate input files exist
    if [[ ! -f "$cert_source" ]]; then
        milou_log "ERROR" "Certificate file not found: $cert_source"
        return 1
    fi
    
    if [[ ! -f "$key_source" ]]; then
        milou_log "ERROR" "Private key file not found: $key_source"
        return 1
    fi
    
    # Validate certificate format
    if ! openssl x509 -in "$cert_source" -noout -text >/dev/null 2>&1; then
        milou_log "ERROR" "Invalid certificate format: $cert_source"
        return 1
    fi
    
    # Validate private key format
    if ! openssl rsa -in "$key_source" -check -noout >/dev/null 2>&1; then
        milou_log "ERROR" "Invalid private key format: $key_source"
        return 1
    fi
    
    # Check if certificate and key match
    local cert_modulus key_modulus
    cert_modulus=$(openssl x509 -noout -modulus -in "$cert_source" 2>/dev/null | openssl md5 2>/dev/null)
    key_modulus=$(openssl rsa -noout -modulus -in "$key_source" 2>/dev/null | openssl md5 2>/dev/null)
    
    if [[ "$cert_modulus" != "$key_modulus" ]]; then
        milou_log "ERROR" "Certificate and private key do not match"
        return 1
    fi
    
    # Create SSL directory if it doesn't exist
    mkdir -p "$ssl_path"
    
    # Backup existing certificates if they exist
    if [[ -f "$ssl_path/milou.crt" ]]; then
        backup_ssl_certificates "$ssl_path"
    fi
    
    # Copy user certificates
    if cp "$cert_source" "$ssl_path/milou.crt" && cp "$key_source" "$ssl_path/milou.key"; then
        # Set appropriate permissions
        chmod 644 "$ssl_path/milou.crt"
        chmod 600 "$ssl_path/milou.key"
        
        # Get certificate information
        local cert_subject cert_expires cert_issuer
        cert_subject=$(openssl x509 -in "$ssl_path/milou.crt" -noout -subject 2>/dev/null | sed 's/subject=//' || echo "Unknown")
        cert_expires=$(openssl x509 -in "$ssl_path/milou.crt" -noout -enddate 2>/dev/null | sed 's/notAfter=//' || echo "Unknown")
        cert_issuer=$(openssl x509 -in "$ssl_path/milou.crt" -noout -issuer 2>/dev/null | sed 's/issuer=//' || echo "Unknown")
        
        milou_log "SUCCESS" "✅ User SSL certificates imported successfully:"
        milou_log "INFO" "  📁 Destination: $ssl_path"
        milou_log "INFO" "  👤 Subject: $cert_subject"
        milou_log "INFO" "  🏢 Issuer: $cert_issuer"
        milou_log "INFO" "  📅 Expires: $cert_expires"
        milou_log "INFO" "  🔄 To apply changes, restart nginx: ./milou.sh restart"
        
        return 0
    else
        milou_log "ERROR" "❌ Failed to import SSL certificates"
        return 1
    fi
}

# Consolidate existing certificates from various locations
consolidate_existing_certificates() {
    local target_ssl_path="$1"
    
    milou_log "DEBUG" "Searching for existing SSL certificates to consolidate"
    
    # Common SSL certificate locations
    local -a search_paths=(
        "./ssl"
        "../ssl"
        "/etc/ssl/certs"
        "/etc/nginx/ssl"
        "/etc/apache2/ssl"
        "/opt/ssl"
        "$HOME/ssl"
        "./static/ssl"
        "../static/ssl"
    )
    
    # Look for certificates in common locations
    for search_path in "${search_paths[@]}"; do
        if [[ -d "$search_path" && "$search_path" != "$target_ssl_path" ]]; then
            local found_cert="$search_path/milou.crt"
            local found_key="$search_path/milou.key"
            
            if [[ -f "$found_cert" && -f "$found_key" ]]; then
                milou_log "INFO" "Found existing certificates at: $search_path"
                
                # Validate found certificates
                if validate_ssl_certificates "$found_cert" "$found_key"; then
                    milou_log "INFO" "Consolidating valid certificates to: $target_ssl_path"
                    
                    # Copy certificates to target location
                    if cp "$found_cert" "$target_ssl_path/milou.crt" && cp "$found_key" "$target_ssl_path/milou.key"; then
                        chmod 644 "$target_ssl_path/milou.crt"
                        chmod 600 "$target_ssl_path/milou.key"
                        
                        milou_log "SUCCESS" "SSL certificates consolidated successfully"
                        return 0
                    else
                        milou_log "ERROR" "Failed to copy certificates to target location"
                    fi
                else
                    milou_log "WARN" "Found certificates are invalid, skipping: $search_path"
                fi
            fi
        fi
    done
    
    milou_log "DEBUG" "No valid existing certificates found for consolidation"
    return 1
}

# Check if domain is publicly accessible
is_domain_publicly_accessible() {
    local domain="$1"
    
    # Skip check for localhost and private IPs
    if [[ "$domain" == "localhost" || "$domain" == "127.0.0.1" || "$domain" =~ ^192\.168\. || "$domain" =~ ^10\. || "$domain" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]; then
        milou_log "DEBUG" "Domain is localhost/private IP: $domain"
        return 1
    fi
    
    # Try to resolve domain
    if ! command -v dig >/dev/null 2>&1 && ! command -v nslookup >/dev/null 2>&1; then
        milou_log "DEBUG" "No DNS lookup tools available"
        return 1
    fi
    
    # Check if domain resolves
    local resolved_ip
    if command -v dig >/dev/null 2>&1; then
        resolved_ip=$(dig +short "$domain" 2>/dev/null | head -1)
    elif command -v nslookup >/dev/null 2>&1; then
        resolved_ip=$(nslookup "$domain" 2>/dev/null | grep "Address:" | tail -1 | awk '{print $2}')
    fi
    
    if [[ -n "$resolved_ip" && "$resolved_ip" != "127.0.0.1" ]]; then
        milou_log "DEBUG" "Domain resolves to: $resolved_ip"
        return 0
    else
        milou_log "DEBUG" "Domain does not resolve publicly: $domain"
        return 1
    fi
}

# Validate Docker SSL access
validate_docker_ssl_access() {
    local ssl_path="$1"
    local cert_file="$ssl_path/milou.crt"
    local key_file="$ssl_path/milou.key"
    
    milou_log "DEBUG" "Validating Docker SSL access"
    
    # Check if certificates exist
    if [[ ! -f "$cert_file" || ! -f "$key_file" ]]; then
        milou_log "ERROR" "SSL certificates not found for Docker validation"
        return 1
    fi
    
    # Check if SSL path is accessible to Docker
    # This is important when running from different directories
    local working_dir
    working_dir=$(pwd)
    
    # If we're in milou-cli directory, ensure certificates are in static/ssl
    if [[ "$(basename "$working_dir")" == "milou-cli" ]]; then
        local static_ssl_dir="$working_dir/static/ssl"
        if [[ "$ssl_path" != "$static_ssl_dir" ]]; then
            milou_log "WARN" "SSL certificates may not be accessible to Docker"
            milou_log "INFO" "Consider moving certificates to: $static_ssl_dir"
            return 1
        fi
    fi
    
    # Check file permissions
    local cert_perms key_perms
    cert_perms=$(stat -c "%a" "$cert_file" 2>/dev/null || echo "unknown")
    key_perms=$(stat -c "%a" "$key_file" 2>/dev/null || echo "unknown")
    
    if [[ "$cert_perms" != "644" ]]; then
        milou_log "WARN" "Certificate permissions may cause Docker issues: $cert_perms"
    fi
    
    if [[ "$key_perms" != "600" ]]; then
        milou_log "WARN" "Private key permissions are not secure: $key_perms"
    fi
    
    milou_log "SUCCESS" "Docker SSL access validation passed"
    return 0
}

milou_log "DEBUG" "SSL validation and management module loaded successfully" 