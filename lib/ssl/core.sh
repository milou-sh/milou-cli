#!/bin/bash

# =============================================================================
# SSL Core Module for Milou CLI
# Consolidated SSL validation, information display, and core utilities
# =============================================================================

# Module guard to prevent multiple loading
if [[ "${MILOU_SSL_CORE_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_SSL_CORE_LOADED="true"

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
# SSL Certificate Validation Functions (Consolidated from core/validation.sh)
# =============================================================================

# Main SSL certificate validation function
milou_ssl_validate_certificates() {
    local ssl_path="$1"
    local domain="${2:-}"
    local check_files_only="${3:-false}"
    local require_domain_match="${4:-true}"
    
    milou_log "DEBUG" "Validating SSL certificates in: $ssl_path"
    
    # Determine certificate and key paths
    local cert_file key_file
    if [[ -f "$ssl_path" ]]; then
        # Single file provided, assume it's the certificate
        cert_file="$ssl_path"
        key_file="${ssl_path%.*}.key"
    elif [[ -d "$ssl_path" ]]; then
        # Directory provided, use standard names
        cert_file="$ssl_path/milou.crt"
        key_file="$ssl_path/milou.key"
    else
        milou_log "ERROR" "SSL path does not exist: $ssl_path"
        return 1
    fi
    
    # Check if files exist
    if [[ ! -f "$cert_file" ]]; then
        milou_log "ERROR" "Certificate file not found: $cert_file"
        return 1
    fi
    
    if [[ ! -f "$key_file" ]]; then
        milou_log "ERROR" "Private key file not found: $key_file"
        return 1
    fi
    
    # Validate certificate file format
    if ! openssl x509 -in "$cert_file" -noout -text >/dev/null 2>&1; then
        milou_log "ERROR" "Invalid certificate format: $cert_file"
        return 1
    fi
    
    # Validate private key file format
    if ! openssl rsa -in "$key_file" -check -noout >/dev/null 2>&1; then
        milou_log "ERROR" "Invalid private key format: $key_file"
        return 1
    fi
    
    # If only checking files, stop here
    if [[ "$check_files_only" == "true" ]]; then
        milou_log "DEBUG" "SSL certificate files are valid"
        return 0
    fi
    
    # Validate certificate and key pair match
    if ! milou_ssl_validate_cert_key_pair "$cert_file" "$key_file"; then
        milou_log "ERROR" "Certificate and private key do not match"
        return 1
    fi
    
    # Check certificate expiration
    if ! milou_ssl_check_expiration "$cert_file" "false" "30"; then
        milou_log "WARN" "Certificate expiration check failed or expires soon"
    fi
    
    # Validate domain if provided
    if [[ -n "$domain" && "$require_domain_match" == "true" ]]; then
        if ! milou_ssl_validate_certificate_domain "$cert_file" "$domain"; then
            milou_log "ERROR" "Certificate does not match domain: $domain"
            return 1
        fi
    fi
    
    milou_log "DEBUG" "SSL certificate validation passed"
    return 0
}

# Validate certificate and private key pair match
milou_ssl_validate_cert_key_pair() {
    local cert_file="$1"
    local key_file="$2"
    
    if [[ ! -f "$cert_file" || ! -f "$key_file" ]]; then
        milou_log "ERROR" "Certificate or key file not found"
        return 1
    fi
    
    # Get the public key from certificate and private key
    local cert_modulus key_modulus
    cert_modulus=$(openssl x509 -noout -modulus -in "$cert_file" 2>/dev/null | openssl md5 2>/dev/null)
    key_modulus=$(openssl rsa -noout -modulus -in "$key_file" 2>/dev/null | openssl md5 2>/dev/null)
    
    if [[ -z "$cert_modulus" || -z "$key_modulus" ]]; then
        milou_log "ERROR" "Failed to extract certificate/key modulus"
        return 1
    fi
    
    if [[ "$cert_modulus" == "$key_modulus" ]]; then
        milou_log "DEBUG" "Certificate and key pair match"
        return 0
    else
        milou_log "ERROR" "Certificate and private key do not match"
        return 1
    fi
}

# Check SSL certificate expiration
milou_ssl_check_expiration() {
    local cert_file="$1"
    local quiet="${2:-false}"
    local warning_days="${3:-30}"
    
    if [[ ! -f "$cert_file" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate file not found: $cert_file"
        return 1
    fi
    
    # Get certificate expiration date
    local expiry_date
    expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
    
    if [[ -z "$expiry_date" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to read certificate expiration date"
        return 1
    fi
    
    # Convert to epoch time for comparison
    local expiry_epoch current_epoch days_until_expiry
    expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null)
    current_epoch=$(date +%s)
    
    if [[ -z "$expiry_epoch" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to parse expiration date: $expiry_date"
        return 1
    fi
    
    days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    if [[ $days_until_expiry -lt 0 ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate has expired ${days_until_expiry#-} days ago"
        return 1
    elif [[ $days_until_expiry -lt $warning_days ]]; then
        [[ "$quiet" != "true" ]] && milou_log "WARN" "Certificate expires in $days_until_expiry days"
        return 2
    else
        [[ "$quiet" != "true" ]] && milou_log "INFO" "Certificate expires in $days_until_expiry days"
        return 0
    fi
}

# Validate certificate matches domain
milou_ssl_validate_certificate_domain() {
    local cert_file="$1"
    local domain="$2"
    
    if [[ ! -f "$cert_file" ]]; then
        milou_log "ERROR" "Certificate file not found: $cert_file"
        return 1
    fi
    
    if [[ -z "$domain" ]]; then
        milou_log "ERROR" "Domain is required for validation"
        return 1
    fi
    
    # Get certificate subject CN
    local cert_cn
    cert_cn=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed -n 's/.*CN[[:space:]]*=[[:space:]]*\([^,]*\).*/\1/p' | tr -d ' ')
    
    # Get Subject Alternative Names
    local san_list
    san_list=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -1 | tr ',' '\n' | sed 's/^[[:space:]]*//' | grep "^DNS:" | sed 's/DNS://')
    
    # Check if domain matches CN
    if [[ "$cert_cn" == "$domain" ]]; then
        milou_log "DEBUG" "Domain matches certificate CN: $domain"
        return 0
    fi
    
    # Check if domain matches any SAN entry
    if [[ -n "$san_list" ]]; then
        while IFS= read -r san_entry; do
            if [[ "$san_entry" == "$domain" ]] || [[ "$san_entry" == "*.$domain" ]]; then
                milou_log "DEBUG" "Domain matches certificate SAN: $domain"
                return 0
            fi
        done <<< "$san_list"
    fi
    
    milou_log "DEBUG" "Domain $domain does not match certificate (CN: $cert_cn)"
    return 1
}

# =============================================================================
# SSL Certificate Information Display Functions
# =============================================================================

# Show comprehensive SSL information
milou_ssl_show_info() {
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
    milou_ssl_show_certificate_info "$cert_file"
    
    # Validate certificates
    echo
    milou_log "INFO" "🔍 Validation Results:"
    if milou_ssl_validate_certificates "$ssl_path"; then
        milou_log "SUCCESS" "✅ SSL certificates are valid"
    else
        milou_log "ERROR" "❌ SSL certificates have issues"
    fi
}

# Show detailed certificate information
milou_ssl_show_certificate_info() {
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
    
    # Get certificate algorithm and key size
    local algorithm key_size
    algorithm=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | grep "Signature Algorithm" | head -1 | awk '{print $3}' || echo "Unknown")
    key_size=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | grep "Public-Key:" | sed 's/.*(\([0-9]*\) bit).*/\1/' || echo "Unknown")
    
    # Get Subject Alternative Names
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
    milou_ssl_check_expiration "$cert_file" "false" "30"
    
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
        if milou_ssl_validate_certificate_domain "$cert_file" "$domain"; then
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
# SSL Certificate Backup Functions
# =============================================================================

# Backup SSL certificates
milou_ssl_backup_certificates() {
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

# =============================================================================
# CLEAN PUBLIC API - Export only essential functions
# =============================================================================

# Core SSL validation and utility functions (3 exports - CLEAN PUBLIC API)
export -f milou_ssl_validate_certificates          # Validate SSL certificates
export -f milou_ssl_show_info                      # Show SSL certificate information
export -f milou_ssl_check_expiration               # Check certificate expiration

# Note: Internal functions are NOT exported (marked with _ prefix):
#   _milou_ssl_validate_cert_key_pair               # Internal: cert/key pair validation
#   _milou_ssl_validate_certificate_domain         # Internal: domain validation
#   _milou_ssl_show_certificate_info                # Internal: detailed cert info display  
#   _milou_ssl_backup_certificates                  # Internal: backup functionality

# This provides a clean, focused API while keeping implementation details internal 