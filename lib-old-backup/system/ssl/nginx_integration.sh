#!/bin/bash

# =============================================================================
# Nginx SSL Integration Module for Milou CLI
# Handles certificate injection, nginx restarts, and configuration updates
# =============================================================================

# Module guard to prevent multiple loading
if [[ "${MILOU_NGINX_INTEGRATION_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_NGINX_INTEGRATION_LOADED="true"

# Ensure logging is available with fallback
if ! command -v milou_log >/dev/null 2>&1; then
    # Try to load logging module if SCRIPT_DIR is available
    if [[ -n "${SCRIPT_DIR:-}" ]] && [[ -f "${SCRIPT_DIR}/lib/core/logging.sh" ]]; then
        source "${SCRIPT_DIR}/lib/core/logging.sh" 2>/dev/null || true
    fi
    
    # Provide fallback logging function if still not available
    if ! command -v milou_log >/dev/null 2>&1; then
        milou_log() {
            local level="$1"
            shift
            local message="$*"
            case "$level" in
                "ERROR") echo "[ERROR] $message" >&2 ;;
                "WARN") echo "[WARN] $message" >&2 ;;
                "INFO") echo "[INFO] $message" ;;
                "DEBUG") [[ "${VERBOSE:-false}" == "true" ]] && echo "[DEBUG] $message" ;;
                "SUCCESS") echo "[SUCCESS] $message" ;;
                *) echo "[$level] $message" ;;
            esac
        }
    fi
fi

# =============================================================================
# Certificate Injection Functions
# =============================================================================

# Inject SSL certificates into nginx container
inject_ssl_certificates() {
    local ssl_path="$1"
    local domain="${2:-localhost}"
    local backup="${3:-true}"
    
    milou_log "STEP" "🔄 Injecting SSL certificates into nginx container"
    
    # Validate input parameters
    if [[ -z "$ssl_path" ]]; then
        milou_log "ERROR" "SSL path not specified"
        return 1
    fi
    
    local cert_file="$ssl_path/milou.crt"
    local key_file="$ssl_path/milou.key"
    
    # Validate certificate files exist
    if [[ ! -f "$cert_file" ]]; then
        milou_log "ERROR" "Certificate file not found: $cert_file"
        return 1
    fi
    
    if [[ ! -f "$key_file" ]]; then
        milou_log "ERROR" "Private key file not found: $key_file"
        return 1
    fi
    
    # Validate certificate and key
    if ! validate_cert_key_pair "$cert_file" "$key_file"; then
        milou_log "ERROR" "Certificate and private key do not match"
        return 1
    fi
    
    # Check if nginx container is running
    if ! is_nginx_container_running; then
        milou_log "WARN" "⚠️  Nginx container is not running"
        milou_log "INFO" "Starting nginx container first..."
        if ! start_nginx_container; then
            milou_log "ERROR" "Failed to start nginx container"
            return 1
        fi
    fi
    
    # Backup existing certificates from container if requested
    if [[ "$backup" == "true" ]]; then
        backup_nginx_certificates_from_container
    fi
    
    # Inject certificates into container
    milou_log "INFO" "📋 Injecting certificates into nginx container..."
    
    if inject_certificates_to_container "$cert_file" "$key_file"; then
        milou_log "SUCCESS" "✅ Certificates injected successfully"
        
        # Validate nginx configuration
        if validate_nginx_config_in_container; then
            milou_log "SUCCESS" "✅ Nginx configuration is valid"
            
            # Reload nginx to apply changes
            if reload_nginx_config; then
                milou_log "SUCCESS" "✅ Nginx reloaded successfully"
                
                # Show certificate info
                show_nginx_certificate_status "$domain"
                
                return 0
            else
                milou_log "ERROR" "❌ Failed to reload nginx configuration"
                return 1
            fi
        else
            milou_log "ERROR" "❌ Invalid nginx configuration after certificate injection"
            return 1
        fi
    else
        milou_log "ERROR" "❌ Failed to inject certificates into container"
        return 1
    fi
}

# Inject certificates directly to running container
inject_certificates_to_container() {
    local cert_file="$1"
    local key_file="$2"
    
    milou_log "DEBUG" "Copying certificates to nginx container..."
    
    # Copy certificate to container
    if docker cp "$cert_file" milou-nginx:/etc/ssl/milou.crt >/dev/null 2>&1; then
        milou_log "DEBUG" "✅ Certificate copied to container"
    else
        milou_log "ERROR" "❌ Failed to copy certificate to container"
        return 1
    fi
    
    # Copy private key to container
    if docker cp "$key_file" milou-nginx:/etc/ssl/milou.key >/dev/null 2>&1; then
        milou_log "DEBUG" "✅ Private key copied to container"
    else
        milou_log "ERROR" "❌ Failed to copy private key to container"
        return 1
    fi
    
    # Set proper permissions inside container
    if docker exec milou-nginx chmod 644 /etc/ssl/milou.crt >/dev/null 2>&1 && \
       docker exec milou-nginx chmod 600 /etc/ssl/milou.key >/dev/null 2>&1; then
        milou_log "DEBUG" "✅ Certificate permissions set correctly"
        return 0
    else
        milou_log "WARN" "⚠️  Failed to set certificate permissions (may still work)"
        return 0  # Don't fail the injection for permission issues
    fi
}

# Enhanced inject SSL certificates with flexible input
inject_ssl_certificates_enhanced() {
    local ssl_path="$1"
    local domain="${2:-localhost}"
    shift 2  # Remove first two arguments
    
    milou_log "STEP" "🔄 Injecting SSL certificates into nginx container (enhanced)"
    
    # Check if a certificate file was provided directly as argument
    local cert_file=""
    local key_file=""
    local backup=true
    
    # Parse remaining arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            *.crt|*.cert|*.pem)
                cert_file="$1"
                shift
                ;;
            *.key)
                key_file="$1"
                shift
                ;;
            --no-backup)
                backup=false
                shift
                ;;
            --cert=*)
                cert_file="${1#*=}"
                shift
                ;;
            --key=*)
                key_file="${1#*=}"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # If certificate files were provided directly, validate them
    if [[ -n "$cert_file" ]]; then
        if [[ ! -f "$cert_file" ]]; then
            milou_log "ERROR" "Certificate file not found: $cert_file"
            return 1
        fi
        
        # If key file not provided, try to infer it
        if [[ -z "$key_file" ]]; then
            # Try common patterns
            local base_name="${cert_file%.*}"
            local possible_keys=(
                "${base_name}.key"
                "${cert_file%.crt}.key"
                "${cert_file%.cert}.key"
                "${cert_file%.pem}.key"
                "$(dirname "$cert_file")/milou.key"
            )
            
            for possible_key in "${possible_keys[@]}"; do
                if [[ -f "$possible_key" ]]; then
                    key_file="$possible_key"
                    milou_log "INFO" "Auto-detected private key: $key_file"
                    break
                fi
            done
            
            if [[ -z "$key_file" ]]; then
                milou_log "ERROR" "Private key file not found. Please specify with --key=path/to/key.key"
                milou_log "INFO" "Tried: ${possible_keys[*]}"
                return 1
            fi
        fi
        
        if [[ ! -f "$key_file" ]]; then
            milou_log "ERROR" "Private key file not found: $key_file"
            return 1
        fi
        
        milou_log "INFO" "Using provided certificate files:"
        milou_log "INFO" "  📄 Certificate: $cert_file"
        milou_log "INFO" "  🔑 Private Key: $key_file"
        
        # Use the provided files directly
        inject_ssl_certificates_from_files "$cert_file" "$key_file" "$domain" "$backup"
    else
        # Use standard SSL path
        milou_log "INFO" "Using certificates from SSL path: $ssl_path"
        inject_ssl_certificates "$ssl_path" "$domain" "$backup"
    fi
}

# Inject certificates from specific files
inject_ssl_certificates_from_files() {
    local cert_file="$1"
    local key_file="$2"
    local domain="${3:-localhost}"
    local backup="${4:-true}"
    
    milou_log "STEP" "🔄 Injecting SSL certificates from specific files"
    
    # Validate certificate and key
    if ! validate_cert_key_pair "$cert_file" "$key_file"; then
        milou_log "ERROR" "Certificate and private key do not match"
        return 1
    fi
    
    # Check if nginx container is running
    if ! is_nginx_container_running; then
        milou_log "WARN" "⚠️  Nginx container is not running"
        milou_log "INFO" "Starting nginx container first..."
        if ! start_nginx_container; then
            milou_log "ERROR" "Failed to start nginx container"
            return 1
        fi
    fi
    
    # Backup existing certificates from container if requested
    if [[ "$backup" == "true" ]]; then
        backup_nginx_certificates_from_container
    fi
    
    # Inject certificates into container
    milou_log "INFO" "📋 Injecting certificates into nginx container..."
    
    if inject_certificates_to_container "$cert_file" "$key_file"; then
        milou_log "SUCCESS" "✅ Certificates injected successfully"
        
        # Validate nginx configuration
        if validate_nginx_config_in_container; then
            milou_log "SUCCESS" "✅ Nginx configuration is valid"
            
            # Reload nginx to apply changes
            if reload_nginx_config; then
                milou_log "SUCCESS" "✅ Nginx reloaded successfully"
                
                # Show certificate info
                show_nginx_certificate_status "$domain"
                
                return 0
            else
                milou_log "ERROR" "❌ Failed to reload nginx configuration"
                return 1
            fi
        else
            milou_log "ERROR" "❌ Invalid nginx configuration after certificate injection"
            return 1
        fi
    else
        milou_log "ERROR" "❌ Failed to inject certificates into container"
        return 1
    fi
}

# =============================================================================
# Nginx Container Management Functions  
# =============================================================================

# Check if nginx container is running
is_nginx_container_running() {
    docker ps --filter "name=milou-nginx" --format "{{.Names}}" | grep -q "milou-nginx"
}

# Check if nginx container exists (running or stopped)
is_nginx_container_exists() {
    docker ps -a --filter "name=milou-nginx" --format "{{.Names}}" | grep -q "milou-nginx"
}

# Start nginx container
start_nginx_container() {
    if is_nginx_container_exists; then
        milou_log "DEBUG" "Starting existing nginx container..."
        docker start milou-nginx >/dev/null 2>&1
    else
        milou_log "DEBUG" "Creating and starting nginx container..."
        # This should be handled by docker-compose
        if [[ -f "./docker-compose.yml" ]] || [[ -f "./static/docker-compose.yml" ]]; then
            local compose_file="./docker-compose.yml"
            [[ -f "./static/docker-compose.yml" ]] && compose_file="./static/docker-compose.yml"
            
            docker-compose -f "$compose_file" up -d nginx >/dev/null 2>&1
        else
            milou_log "ERROR" "No docker-compose.yml found to start nginx"
            return 1
        fi
    fi
    
    # Wait for container to be ready
    local attempts=0
    while [[ $attempts -lt 10 ]]; do
        if is_nginx_container_running; then
            milou_log "DEBUG" "✅ Nginx container is running"
            return 0
        fi
        sleep 1
        ((attempts++))
    done
    
    milou_log "ERROR" "❌ Nginx container failed to start within timeout"
    return 1
}

# Stop nginx container
stop_nginx_container() {
    if is_nginx_container_running; then
        milou_log "DEBUG" "Stopping nginx container..."
        docker stop milou-nginx >/dev/null 2>&1
        return $?
    else
        milou_log "DEBUG" "Nginx container is not running"
        return 0
    fi
}

# Restart nginx container
restart_nginx_container() {
    milou_log "INFO" "🔄 Restarting nginx container..."
    
    if is_nginx_container_running; then
        docker restart milou-nginx >/dev/null 2>&1
    else
        start_nginx_container
    fi
    
    if [[ $? -eq 0 ]]; then
        milou_log "SUCCESS" "✅ Nginx container restarted successfully"
        return 0
    else
        milou_log "ERROR" "❌ Failed to restart nginx container"
        return 1
    fi
}

# =============================================================================
# Nginx Configuration Functions
# =============================================================================

# Validate nginx configuration inside container
validate_nginx_config_in_container() {
    if ! is_nginx_container_running; then
        milou_log "ERROR" "Nginx container is not running"
        return 1
    fi
    
    milou_log "DEBUG" "Validating nginx configuration..."
    
    if docker exec milou-nginx nginx -t >/dev/null 2>&1; then
        milou_log "DEBUG" "✅ Nginx configuration is valid"
        return 0
    else
        milou_log "ERROR" "❌ Nginx configuration is invalid"
        # Show detailed error
        local error_output
        error_output=$(docker exec milou-nginx nginx -t 2>&1)
        milou_log "ERROR" "Nginx error: $error_output"
        return 1
    fi
}

# Reload nginx configuration without restarting container
reload_nginx_config() {
    if ! is_nginx_container_running; then
        milou_log "ERROR" "Nginx container is not running"
        return 1
    fi
    
    milou_log "DEBUG" "Reloading nginx configuration..."
    
    if docker exec milou-nginx nginx -s reload >/dev/null 2>&1; then
        milou_log "DEBUG" "✅ Nginx configuration reloaded"
        return 0
    else
        milou_log "WARN" "⚠️  Failed to reload nginx, attempting restart..."
        return restart_nginx_container
    fi
}

# =============================================================================
# Certificate Validation and Status Functions
# =============================================================================

# Validate certificate and private key pair
validate_cert_key_pair() {
    local cert_file="$1"
    local key_file="$2"
    
    if ! command -v openssl >/dev/null 2>&1; then
        milou_log "WARN" "OpenSSL not available, skipping validation"
        return 0
    fi
    
    # Get certificate public key
    local cert_pubkey
    cert_pubkey=$(openssl x509 -in "$cert_file" -noout -pubkey 2>/dev/null)
    
    if [[ -z "$cert_pubkey" ]]; then
        milou_log "ERROR" "❌ Cannot extract public key from certificate"
        return 1
    fi
    
    # Get private key public key (works for both RSA and ECDSA)
    local key_pubkey
    key_pubkey=$(openssl pkey -in "$key_file" -pubout 2>/dev/null)
    
    if [[ -z "$key_pubkey" ]]; then
        milou_log "ERROR" "❌ Cannot extract public key from private key"
        return 1
    fi
    
    # Compare public keys using MD5 hash (more reliable than string comparison)
    local cert_hash key_hash
    cert_hash=$(echo "$cert_pubkey" | md5sum | cut -d' ' -f1)
    key_hash=$(echo "$key_pubkey" | md5sum | cut -d' ' -f1)
    
    if [[ "$cert_hash" == "$key_hash" ]]; then
        milou_log "DEBUG" "✅ Certificate and key pair validation successful"
        return 0
    else
        milou_log "ERROR" "❌ Certificate and key pair validation failed (cert: $cert_hash, key: $key_hash)"
        return 1
    fi
}

# Show nginx certificate status
show_nginx_certificate_status() {
    local domain="${1:-localhost}"
    
    if ! is_nginx_container_running; then
        milou_log "WARN" "⚠️  Nginx container is not running"
        return 1
    fi
    
    milou_log "INFO" "📋 Nginx SSL Certificate Status"
    echo
    
    # Check if certificates exist in container
    if docker exec milou-nginx test -f /etc/ssl/milou.crt >/dev/null 2>&1; then
        milou_log "SUCCESS" "✅ Certificate file exists in container: /etc/ssl/milou.crt"
        
        # Try to get certificate details from container (if openssl is available)
        local cert_info
        if docker exec milou-nginx which openssl >/dev/null 2>&1; then
            cert_info=$(docker exec milou-nginx openssl x509 -in /etc/ssl/milou.crt -noout -text 2>/dev/null)
            
            if [[ -n "$cert_info" ]]; then
                local subject issuer not_before not_after
                subject=$(echo "$cert_info" | grep "Subject:" | sed 's/.*Subject: //')
                issuer=$(echo "$cert_info" | grep "Issuer:" | sed 's/.*Issuer: //')
                not_before=$(echo "$cert_info" | grep "Not Before:" | sed 's/.*Not Before: //')
                not_after=$(echo "$cert_info" | grep "Not After:" | sed 's/.*Not After: //')
                
                milou_log "INFO" "🔒 Certificate Details (from container):"
                milou_log "INFO" "  👤 Subject: $subject"
                milou_log "INFO" "  🏢 Issuer: $issuer"
                milou_log "INFO" "  📅 Valid From: $not_before"
                milou_log "INFO" "  📅 Valid Until: $not_after"
                
                # Check if certificate is valid for domain
                if echo "$cert_info" | grep -q "CN=$domain\|DNS:$domain\|DNS:\*.$domain"; then
                    milou_log "SUCCESS" "  ✅ Certificate is valid for domain: $domain"
                else
                    milou_log "WARN" "  ⚠️  Certificate may not be valid for domain: $domain"
                fi
            else
                milou_log "WARN" "⚠️  Could not parse certificate information from container"
            fi
        else
            milou_log "INFO" "ℹ️  OpenSSL not available in container, copying certificate for analysis..."
            
            # Copy certificate from container and analyze it locally
            local temp_cert="/tmp/nginx_cert_$(date +%s).crt"
            if docker cp milou-nginx:/etc/ssl/milou.crt "$temp_cert" 2>/dev/null; then
                if command -v openssl >/dev/null 2>&1; then
                    local subject issuer not_before not_after
                    subject=$(openssl x509 -in "$temp_cert" -noout -subject 2>/dev/null | sed 's/subject=//')
                    issuer=$(openssl x509 -in "$temp_cert" -noout -issuer 2>/dev/null | sed 's/issuer=//')
                    not_before=$(openssl x509 -in "$temp_cert" -noout -startdate 2>/dev/null | sed 's/notBefore=//')
                    not_after=$(openssl x509 -in "$temp_cert" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
                    
                    milou_log "INFO" "🔒 Certificate Details (analyzed locally):"
                    milou_log "INFO" "  👤 Subject: $subject"
                    milou_log "INFO" "  🏢 Issuer: $issuer"
                    milou_log "INFO" "  📅 Valid From: $not_before"
                    milou_log "INFO" "  📅 Valid Until: $not_after"
                    
                    # Check if certificate is valid for domain
                    local cert_text
                    cert_text=$(openssl x509 -in "$temp_cert" -noout -text 2>/dev/null)
                    if echo "$cert_text" | grep -q "CN=$domain\|DNS:$domain\|DNS:\*.$domain"; then
                        milou_log "SUCCESS" "  ✅ Certificate is valid for domain: $domain"
                    else
                        milou_log "WARN" "  ⚠️  Certificate may not be valid for domain: $domain"
                    fi
                else
                    milou_log "WARN" "⚠️  OpenSSL not available locally either"
                fi
                
                # Clean up temporary file
                rm -f "$temp_cert"
            else
                milou_log "WARN" "⚠️  Could not copy certificate from container for analysis"
            fi
        fi
        
        # Check private key exists
        if docker exec milou-nginx test -f /etc/ssl/milou.key >/dev/null 2>&1; then
            milou_log "SUCCESS" "✅ Private key file exists in container: /etc/ssl/milou.key"
        else
            milou_log "ERROR" "❌ Private key file missing in container: /etc/ssl/milou.key"
        fi
        
    else
        milou_log "ERROR" "❌ No certificate found in nginx container"
        return 1
    fi
    
    # Test HTTPS connectivity
    milou_log "INFO" "🌐 Testing HTTPS connectivity..."
    test_https_connectivity "$domain" || true  # Don't fail the command if connectivity test fails
}

# Test HTTPS connectivity to the domain
test_https_connectivity() {
    local domain="$1"
    
    if command -v curl >/dev/null 2>&1; then
        local https_url="https://$domain"
        
        # Test with curl (ignore certificate errors for self-signed)
        if curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$https_url" >/dev/null 2>&1; then
            milou_log "SUCCESS" "  ✅ HTTPS is accessible at $https_url"
        else
            milou_log "WARN" "  ⚠️  HTTPS connectivity test failed for $https_url"
            milou_log "INFO" "  This might be normal for self-signed certificates"
        fi
    else
        milou_log "DEBUG" "curl not available for HTTPS connectivity test"
    fi
}

# =============================================================================
# Backup and Recovery Functions
# =============================================================================

# Backup certificates from nginx container
backup_nginx_certificates_from_container() {
    local backup_dir="./ssl_backups"
    local backup_name="nginx_ssl_backup_$(date +%Y%m%d_%H%M%S)"
    
    if ! is_nginx_container_running; then
        milou_log "WARN" "⚠️  Nginx container is not running, skipping backup"
        return 1
    fi
    
    # Check if certificates exist in container
    if ! docker exec milou-nginx test -f /etc/ssl/milou.crt >/dev/null 2>&1; then
        milou_log "DEBUG" "No existing certificates in nginx container to backup"
        return 0
    fi
    
    milou_log "INFO" "💾 Backing up existing certificates from nginx container..."
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    # Copy certificates from container
    local backup_cert="$backup_dir/${backup_name}.crt"
    local backup_key="$backup_dir/${backup_name}.key"
    local backup_info="$backup_dir/${backup_name}.info"
    
    if docker cp milou-nginx:/etc/ssl/milou.crt "$backup_cert" 2>/dev/null && \
       docker cp milou-nginx:/etc/ssl/milou.key "$backup_key" 2>/dev/null; then
        
        # Set appropriate permissions
        chmod 644 "$backup_cert" 2>/dev/null || true
        chmod 600 "$backup_key" 2>/dev/null || true
        
        # Create backup info file
        cat > "$backup_info" << EOF
# Nginx SSL Certificate Backup Information
# Generated: $(date)
# Backup Name: $backup_name
# Source: milou-nginx container

Certificate File: $backup_cert
Private Key File: $backup_key
Original Location: /etc/ssl/milou.crt (in container)
Original Key Location: /etc/ssl/milou.key (in container)

# Certificate Details:
$(openssl x509 -in "$backup_cert" -noout -text 2>/dev/null | head -20 || echo "Certificate details unavailable")
EOF
        chmod 644 "$backup_info" 2>/dev/null || true
        
        milou_log "SUCCESS" "✅ Nginx certificates backed up:"
        milou_log "INFO" "  📁 Location: $backup_dir"
        milou_log "INFO" "  📄 Certificate: $backup_cert"
        milou_log "INFO" "  🔑 Private Key: $backup_key"
        milou_log "INFO" "  📋 Info: $backup_info"
        
        return 0
    else
        milou_log "ERROR" "❌ Failed to backup certificates from nginx container"
        return 1
    fi
}

# =============================================================================
# High-level SSL Integration Functions
# =============================================================================

# Complete SSL setup with nginx integration
setup_ssl_with_nginx() {
    local ssl_path="$1"
    local domain="$2"
    local cert_type="${3:-self-signed}"
    local email="${4:-admin@$domain}"
    
    milou_log "STEP" "🔒 Complete SSL setup with nginx integration"
    echo
    
    # Validate parameters
    if [[ -z "$ssl_path" || -z "$domain" ]]; then
        milou_log "ERROR" "SSL path and domain are required"
        return 1
    fi
    
    # Ensure SSL directory exists
    mkdir -p "$ssl_path"
    
    # Generate certificates based on type
    case "$cert_type" in
        "letsencrypt")
            if ! generate_letsencrypt_certificate "$ssl_path" "$domain" "$email"; then
                milou_log "WARN" "⚠️  Let's Encrypt failed, falling back to self-signed"
                cert_type="self-signed"
            fi
            ;;
        "self-signed")
            if ! generate_production_certificate "$ssl_path" "$domain"; then
                milou_log "ERROR" "❌ Failed to generate self-signed certificate"
                return 1
            fi
            ;;
        *)
            milou_log "ERROR" "Unknown certificate type: $cert_type"
            return 1
            ;;
    esac
    
    # Generate self-signed if Let's Encrypt failed
    if [[ "$cert_type" == "self-signed" ]]; then
        if ! generate_production_certificate "$ssl_path" "$domain"; then
            milou_log "ERROR" "❌ Failed to generate self-signed certificate"
            return 1
        fi
    fi
    
    # Inject certificates into nginx
    if inject_ssl_certificates "$ssl_path" "$domain" true; then
        milou_log "SUCCESS" "🎉 SSL setup with nginx integration completed!"
        echo
        
        # Show final status
        milou_log "INFO" "📋 Final Status:"
        milou_log "INFO" "  🏷️  Certificate Type: $cert_type"
        milou_log "INFO" "  🌐 Domain: $domain"
        milou_log "INFO" "  📄 Certificate: $ssl_path/milou.crt"
        milou_log "INFO" "  🔑 Private Key: $ssl_path/milou.key"
        milou_log "INFO" "  🐳 Nginx Status: Running with SSL"
        echo
        
        milou_log "INFO" "📋 Next Steps:"
        milou_log "INFO" "  🌐 Test your setup: https://$domain"
        if [[ "$cert_type" == "self-signed" ]]; then
            milou_log "INFO" "  ⚠️  Self-signed certificate - browsers will show warnings"
            milou_log "INFO" "  💡 Consider Let's Encrypt for production: ./milou.sh ssl setup --domain $domain --letsencrypt"
        else
            milou_log "INFO" "  ✅ Let's Encrypt certificate - trusted by browsers"
            milou_log "INFO" "  📅 Set up auto-renewal for continued operation"
        fi
        
        return 0
    else
        milou_log "ERROR" "❌ Failed to inject certificates into nginx"
        return 1
    fi
}

milou_log "DEBUG" "Nginx SSL integration module loaded successfully" 