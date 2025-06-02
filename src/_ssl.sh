#!/bin/bash

# =============================================================================
# Milou CLI - SSL Management Module  
# Consolidated SSL operations to eliminate code duplication
# Version: 3.2.0 - Enhanced User Experience Edition
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Module guard to prevent multiple loading
if [[ "${MILOU_SSL_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_SSL_LOADED="true"

# Ensure core modules are loaded
if [[ "${MILOU_CORE_LOADED:-}" != "true" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/_core.sh" || {
        echo "ERROR: Cannot load core module" >&2
        return 1
    }
fi

if [[ "${MILOU_VALIDATION_LOADED:-}" != "true" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/_validation.sh" || {
        echo "ERROR: Cannot load validation module" >&2
        return 1
    }
fi

# =============================================================================
# SSL CONSTANTS AND CONFIGURATION
# =============================================================================

# Robust SCRIPT_DIR detection with failsafe mechanisms
ssl_detect_script_dir() {
    local detected_dir=""
    
    # Method 1: Use pre-exported SCRIPT_DIR if available and valid
    if [[ -n "${SCRIPT_DIR:-}" ]] && [[ -f "${SCRIPT_DIR}/milou.sh" ]]; then
        detected_dir="$SCRIPT_DIR"
    # Method 2: Detect from main entry point location  
    elif [[ -n "${BASH_SOURCE[0]:-}" ]]; then
        local src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [[ -f "$src_dir/../milou.sh" ]]; then
            detected_dir="$(cd "$src_dir/.." && pwd)"
        fi
    # Method 3: Search upward from current directory
    else
        local search_dir="$(pwd)"
        for i in {1..5}; do  # Limit search depth
            if [[ -f "$search_dir/milou.sh" ]]; then
                detected_dir="$search_dir"
                break
            fi
            search_dir="$(dirname "$search_dir")"
            [[ "$search_dir" == "/" ]] && break
        done
    fi
    
    # Failsafe: use current directory if all else fails
    if [[ -z "$detected_dir" ]]; then
        detected_dir="$(pwd)"
    fi
    
    echo "$detected_dir"
}

# Initialize SCRIPT_DIR robustly
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(ssl_detect_script_dir)"
    export SCRIPT_DIR
fi

# Single source of truth for SSL paths - CONSOLIDATED
declare -g MILOU_SSL_DIR="${SCRIPT_DIR}/ssl"
declare -g MILOU_SSL_CERT_FILE="${MILOU_SSL_DIR}/milou.crt"
declare -g MILOU_SSL_KEY_FILE="${MILOU_SSL_DIR}/milou.key"
declare -g MILOU_SSL_INFO_FILE="${MILOU_SSL_DIR}/.ssl_info"
declare -g MILOU_SSL_CONFIG_FILE="${MILOU_SSL_DIR}/openssl.conf"

# Certificate defaults - CONSOLIDATED
declare -g MILOU_SSL_DEFAULT_VALIDITY_DAYS=365
declare -g MILOU_SSL_DEFAULT_KEY_SIZE=2048
declare -g MILOU_SSL_BACKUP_DIR="${MILOU_SSL_DIR}/backup"

# =============================================================================
# ENHANCED USER EXPERIENCE FUNCTIONS
# =============================================================================

# Interactive SSL mode selection with intelligent defaults
ssl_select_mode_interactive() {
    local domain="${1:-localhost}"
    local current_mode="${2:-auto}"
    local quiet="${3:-false}"
    
    [[ "$quiet" == "true" ]] && echo "$current_mode" && return 0
    
    echo -e "${BLUE}🔒 SSL Certificate Setup${NC}"
    echo "=============================="
    echo
    echo "Choose how you want to handle SSL certificates for: ${BOLD}$domain${NC}"
    echo
    
    # Show mode options with intelligent recommendations
    if [[ "$domain" == "localhost" || "$domain" == "127.0.0.1" ]]; then
        echo -e "${GREEN}   1) ${BOLD}Generate Self-Signed${NC} ${DIM}(Recommended for localhost)${NC}"
        echo -e "      ${GREEN}✓${NC} Quick and automatic"
        echo -e "      ${GREEN}✓${NC} Perfect for local development"
        echo -e "      ${YELLOW}⚠${NC}  Browser security warnings"
        echo
        echo -e "${BLUE}   2) ${BOLD}Use Existing Certificates${NC}"
        echo -e "      ${BLUE}✓${NC} Bring your own certificates"
        echo -e "      ${BLUE}✓${NC} No security warnings"
        echo
        echo -e "${GRAY}   3) ${BOLD}Disable SSL${NC} ${DIM}(HTTP Only)${NC}"
        echo -e "      ${YELLOW}⚠${NC}  Less secure"
        echo -e "      ${YELLOW}⚠${NC}  Not recommended for production"
        echo
        
        local default_choice="1"
    else
        echo -e "${GREEN}   1) ${BOLD}Let's Encrypt${NC} ${DIM}(Recommended for public domains)${NC}"
        echo -e "      ${GREEN}✓${NC} Free trusted certificates"
        echo -e "      ${GREEN}✓${NC} Automatic renewal"
        echo -e "      ${YELLOW}⚠${NC}  Requires domain pointing to this server"
        echo
        echo -e "${BLUE}   2) ${BOLD}Use Existing Certificates${NC}"
        echo -e "      ${BLUE}✓${NC} Bring your own certificates"
        echo -e "      ${BLUE}✓${NC} Full control over certificate source"
        echo
        echo -e "${CYAN}   3) ${BOLD}Generate Self-Signed${NC}"
        echo -e "      ${CYAN}✓${NC} Quick and automatic"
        echo -e "      ${YELLOW}⚠${NC}  Browser security warnings"
        echo
        echo -e "${GRAY}   4) ${BOLD}Disable SSL${NC} ${DIM}(HTTP Only)${NC}"
        echo -e "      ${YELLOW}⚠${NC}  Not secure"
        echo -e "      ${RED}❌${NC} Not recommended for public domains"
        echo
        
        local default_choice="1"
    fi
    
    local choice
    while true; do
        if [[ "$domain" == "localhost" || "$domain" == "127.0.0.1" ]]; then
            read -p "Choose SSL option [1-3] (default: $default_choice): " choice
            choice="${choice:-$default_choice}"
            
            case "$choice" in
                1) echo "generate"; return 0 ;;
                2) echo "existing"; return 0 ;;
                3) echo "none"; return 0 ;;
                *) echo -e "${RED}Please choose 1, 2, or 3${NC}" ;;
            esac
        else
            read -p "Choose SSL option [1-4] (default: $default_choice): " choice
            choice="${choice:-$default_choice}"
            
            case "$choice" in
                1) echo "letsencrypt"; return 0 ;;
                2) echo "existing"; return 0 ;;
                3) echo "generate"; return 0 ;;
                4) echo "none"; return 0 ;;
                *) echo -e "${RED}Please choose 1, 2, 3, or 4${NC}" ;;
            esac
        fi
    done
}

# Enhanced existing certificate setup with better user guidance
ssl_setup_existing_enhanced() {
    local domain="$1"
    local cert_source="$2"
    local force="$3"
    local quiet="$4"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "📁 Setting up existing SSL certificates"
    
    # Enhanced interactive certificate path selection
    if [[ -z "$cert_source" ]] || [[ ! -d "$cert_source" ]] || [[ -z "$(ls -A "$cert_source" 2>/dev/null)" ]]; then
        if [[ "$INTERACTIVE" != "false" ]] && [[ "$quiet" != "true" ]]; then
            echo
            echo -e "${BLUE}📁 SSL Certificate Location${NC}"
            echo "================================"
            echo
            echo "We need to locate your SSL certificate files."
            echo -e "Current SSL directory: ${BOLD}$(realpath "$MILOU_SSL_DIR")${NC}"
            echo
            echo -e "${BOLD}💡 Common Certificate Locations:${NC}"
            echo
            echo -e "${GREEN}Let's Encrypt (Certbot):${NC}"
            echo "  • /etc/letsencrypt/live/yourdomain.com/"
            echo "  • Contains: fullchain.pem + privkey.pem"
            echo
            echo -e "${BLUE}Custom Certificates:${NC}"  
            echo "  • /path/to/your/certificates/"
            echo "  • Contains: *.crt + *.key files"
            echo "  • Or: *.pem files"
            echo
            echo -e "${CYAN}Supported Formats:${NC}"
            echo "  • Let's Encrypt: fullchain.pem + privkey.pem"
            echo "  • Standard: *.crt + *.key"
            echo "  • PEM format: certificate.pem + private.pem"
            echo "  • Custom naming: server.crt + server.key"
            echo
            
            # Show some path suggestions based on system
            if [[ -d "/etc/letsencrypt/live" ]]; then
                echo -e "${GREEN}💡 Found Let's Encrypt directory!${NC}"
                echo "Available domains:"
                ls /etc/letsencrypt/live/ 2>/dev/null | grep -v README | head -5 | sed 's/^/  • /'
                echo
            fi
            
            while true; do
                read -p "Enter certificate directory path: " cert_source
                
                if [[ -z "$cert_source" ]]; then
                    echo -e "${YELLOW}No path provided. Try again or press Ctrl+C to cancel.${NC}"
                    continue
                fi
                
                # Expand tilde
                cert_source="${cert_source/#\~/$HOME}"
                
                if [[ ! -d "$cert_source" ]]; then
                    echo -e "${RED}Directory not found: $cert_source${NC}"
                    echo "Please check the path and try again."
                    continue
                fi
                
                if [[ -z "$(ls -A "$cert_source" 2>/dev/null)" ]]; then
                    echo -e "${YELLOW}Directory is empty: $cert_source${NC}"
                    echo "Please choose a directory containing certificate files."
                    continue
                fi
                
                echo -e "${GREEN}✓ Using certificate directory: $cert_source${NC}"
                break
            done
        else
            [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate source path required for non-interactive mode"
            return 1
        fi
    fi
    
    # Continue with existing implementation but with enhanced error messages
    ssl_setup_existing "$domain" "$cert_source" "$force" "$quiet"
}

# =============================================================================
# SSL INITIALIZATION AND SETUP (Enhanced)
# =============================================================================

# Initialize SSL environment - ENHANCED IMPLEMENTATION
ssl_init() {
    local quiet="${1:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Initializing SSL environment"
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Detected SCRIPT_DIR: $SCRIPT_DIR"
    
    # Validate SCRIPT_DIR before proceeding
    if [[ ! -d "$SCRIPT_DIR" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Invalid SCRIPT_DIR: $SCRIPT_DIR"
        return 1
    fi
    
    # Create SSL directory structure
    if ! ensure_directory "$MILOU_SSL_DIR" "755"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to create SSL directory: $MILOU_SSL_DIR"
        return 1
    fi
    
    # Create backup directory
    ensure_directory "$MILOU_SSL_BACKUP_DIR" "755" >/dev/null 2>&1
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "SSL environment initialized successfully"
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "  SSL directory: $MILOU_SSL_DIR"
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "  Certificate: $MILOU_SSL_CERT_FILE"
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "  Private key: $MILOU_SSL_KEY_FILE"
    
    return 0
}

# Main SSL setup function - ENHANCED IMPLEMENTATION
ssl_setup() {
    local domain="${1:-localhost}"
    local ssl_mode="${2:-auto}"      # auto, generate, existing, letsencrypt, none
    local cert_source="${3:-}"       # Path for existing certificates
    local force="${4:-false}"        # Force regeneration
    local quiet="${5:-false}"        # Quiet mode
    
    [[ "$quiet" != "true" ]] && milou_log "STEP" "🔒 SSL Certificate Setup"
    [[ "$quiet" != "true" ]] && milou_log "INFO" "Domain: $domain | Mode: $ssl_mode | Force: $force"
    
    # Initialize SSL environment
    if ! ssl_init "$quiet"; then
        return 1
    fi
    
    # Interactive mode selection if mode is auto and we're in interactive mode
    if [[ "$ssl_mode" == "auto" ]] && [[ "${INTERACTIVE:-true}" != "false" ]] && [[ "$quiet" != "true" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "INFO" "🤖 Starting intelligent SSL setup"
        ssl_mode=$(ssl_select_mode_interactive "$domain" "$ssl_mode" "$quiet")
        [[ "$quiet" != "true" ]] && milou_log "INFO" "Selected SSL mode: $ssl_mode"
    fi
    
    # Execute appropriate SSL setup based on mode
    case "$ssl_mode" in
        "none"|"disabled")
            [[ "$quiet" != "true" ]] && milou_log "INFO" "🚫 SSL disabled - removing certificates"
            ssl_cleanup "$quiet"
            ;;
        "existing")
            [[ "$quiet" != "true" ]] && milou_log "INFO" "📁 Using existing SSL certificates"
            ssl_setup_existing_enhanced "$domain" "$cert_source" "$force" "$quiet"
            ;;
        "generate"|"self-signed")
            [[ "$quiet" != "true" ]] && milou_log "INFO" "🔒 Generating self-signed certificates"
            ssl_generate_self_signed "$domain" "$force" "$quiet"
            ;;
        "letsencrypt")
            [[ "$quiet" != "true" ]] && milou_log "INFO" "🔐 Setting up Let's Encrypt certificates"
            ssl_generate_letsencrypt_enhanced "$domain" "$force" "$quiet"
            ;;
        "auto"|*)
            [[ "$quiet" != "true" ]] && milou_log "INFO" "🤖 Automatic SSL setup"
            ssl_setup_auto "$domain" "$force" "$quiet"
            ;;
    esac
}

# Automatic SSL setup with intelligent decisions
ssl_setup_auto() {
    local domain="$1"
    local force="$2"
    local quiet="$3"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Starting automatic SSL setup for: $domain"
    
    # If certificates exist and are valid, preserve them (unless forced)
    if [[ "$force" != "true" ]] && ssl_is_enabled; then
        if ssl_validate "$domain" "true"; then
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Existing valid certificates preserved"
            ssl_save_info "$domain" "preserved" "$quiet"
            return 0
        fi
    fi
    
    # Backup existing certificates if forced or invalid
    if [[ "$force" == "true" ]] && ssl_is_enabled; then
        [[ "$quiet" != "true" ]] && milou_log "INFO" "Backing up existing certificates before regeneration"
        ssl_backup_certificates "$quiet"
    fi
    
    # For localhost, always use self-signed
    if [[ "$domain" == "localhost" || "$domain" == "127.0.0.1" ]]; then
        ssl_generate_self_signed "$domain" "$force" "$quiet"
        return $?
    fi
    
    # For real domains, try Let's Encrypt if available, otherwise self-signed
    if ssl_can_use_letsencrypt "$domain"; then
        [[ "$quiet" != "true" ]] && milou_log "INFO" "Domain appears suitable for Let's Encrypt"
        if ssl_generate_letsencrypt "$domain" "$force" "$quiet"; then
            return 0
        else
            [[ "$quiet" != "true" ]] && milou_log "WARN" "Let's Encrypt failed, falling back to self-signed"
            ssl_generate_self_signed "$domain" "$force" "$quiet"
        fi
    else
        [[ "$quiet" != "true" ]] && milou_log "INFO" "Using self-signed certificates for domain: $domain"
        ssl_generate_self_signed "$domain" "$force" "$quiet"
    fi
}

# =============================================================================
# SSL CERTIFICATE GENERATION
# =============================================================================

# Modern certificate validation for all key types
ssl_validate_key_file() {
    local key_file="$1"
    local quiet="${2:-false}"
    
    if [[ ! -f "$key_file" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Key file not found: $key_file"
        return 1
    fi
    
    # Use modern openssl pkey command (supports RSA, EC, and all key types)
    if openssl pkey -in "$key_file" -check -noout >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "TRACE" "Key file validated"
        return 0
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "ERROR" "Key file validation failed"
    return 1
}

# Generate self-signed SSL certificates - SINGLE AUTHORITATIVE IMPLEMENTATION
ssl_generate_self_signed() {
    local domain="${1:-localhost}"
    local force="${2:-false}"
    local quiet="${3:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🔒 Generating self-signed certificate for: $domain"
    
    # Initialize SSL environment
    ssl_init "$quiet" || return 1
    
    # Backup existing certificates if they exist and not forced
    if [[ "$force" != "true" ]] && [[ -f "$MILOU_SSL_CERT_FILE" || -f "$MILOU_SSL_KEY_FILE" ]]; then
        ssl_backup_certificates "$quiet"
    fi
    
    # Create OpenSSL configuration
    if ! ssl_create_openssl_config "$domain" "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to create OpenSSL configuration"
        return 1
    fi
    
    # Generate private key
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Generating RSA private key ($MILOU_SSL_DEFAULT_KEY_SIZE bits)"
    if ! openssl genrsa -out "$MILOU_SSL_KEY_FILE" "$MILOU_SSL_DEFAULT_KEY_SIZE" >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to generate private key"
        return 1
    fi
    
    # Generate certificate
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Generating certificate (valid for $MILOU_SSL_DEFAULT_VALIDITY_DAYS days)"
    if ! openssl req -new -x509 \
        -key "$MILOU_SSL_KEY_FILE" \
        -out "$MILOU_SSL_CERT_FILE" \
        -days "$MILOU_SSL_DEFAULT_VALIDITY_DAYS" \
        -config "$MILOU_SSL_CONFIG_FILE" >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to generate certificate"
        return 1
    fi
    
    # Set secure permissions
    chmod 644 "$MILOU_SSL_CERT_FILE" 2>/dev/null || true
    chmod 600 "$MILOU_SSL_KEY_FILE" 2>/dev/null || true
    
    # Save certificate info
    ssl_save_info "$domain" "self-signed" "$quiet"
    
    # Validate the generated certificates
    if ssl_validate "$domain" "true"; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Self-signed certificate generated successfully"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "📄 Certificate: $MILOU_SSL_CERT_FILE"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "🔑 Private key: $MILOU_SSL_KEY_FILE"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "⏰ Valid for: $MILOU_SSL_DEFAULT_VALIDITY_DAYS days"
        
        # Show browser warning info for non-localhost domains
        if [[ "$domain" != "localhost" && "$domain" != "127.0.0.1" ]]; then
            [[ "$quiet" != "true" ]] && milou_log "INFO" "⚠️  Note: Browsers will show security warnings for self-signed certificates"
            [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 For production, consider using Let's Encrypt certificates"
        fi
        
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Generated certificate failed validation"
        return 1
    fi
}

# Generate Let's Encrypt certificates - SINGLE AUTHORITATIVE IMPLEMENTATION
ssl_generate_letsencrypt() {
    local domain="$1"
    local force="$2"
    local quiet="$3"
    local email="${ADMIN_EMAIL:-admin@${domain}}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🔐 Generating Let's Encrypt certificate for: $domain"
    
    # Check if Let's Encrypt is available
    if ! ssl_can_use_letsencrypt "$domain"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Let's Encrypt not suitable for domain: $domain"
        return 1
    fi
    
    # Install certbot if needed
    if ! ssl_install_certbot "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to install certbot"
        return 1
    fi
    
    # Check port 80 availability (required for Let's Encrypt)
    if ! ssl_check_port_80_status "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Port 80 is required for Let's Encrypt validation"
        return 1
    fi
    
    # Try standalone mode first
    if ssl_generate_letsencrypt_standalone "$domain" "$email" "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Let's Encrypt certificate obtained (standalone mode)"
        ssl_save_info "$domain" "letsencrypt" "$quiet"
        return 0
    fi
    
    # Try with nginx stop
    if ssl_generate_letsencrypt_with_nginx_stop "$domain" "$email" "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Let's Encrypt certificate obtained (nginx-stop mode)"
        ssl_save_info "$domain" "letsencrypt" "$quiet"
        return 0
    fi
    
    # Show troubleshooting information
    [[ "$quiet" != "true" ]] && ssl_show_letsencrypt_troubleshooting "$domain"
    
    [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to obtain Let's Encrypt certificate"
    return 1
}

# =============================================================================
# SSL VALIDATION AND STATUS
# =============================================================================

# Comprehensive SSL validation - SINGLE AUTHORITATIVE IMPLEMENTATION
ssl_validate() {
    local domain="${1:-localhost}"
    local quiet="${2:-false}"
    local min_days_valid="${3:-7}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Validating SSL certificates for: $domain"
    
    local errors=0
    
    # Check if certificate files exist
    if [[ ! -f "$MILOU_SSL_CERT_FILE" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate file not found: $MILOU_SSL_CERT_FILE"
        ((errors++))
    fi
    
    if [[ ! -f "$MILOU_SSL_KEY_FILE" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Private key file not found: $MILOU_SSL_KEY_FILE"
        ((errors++))
    fi
    
    if [[ $errors -gt 0 ]]; then
        return 1
    fi
    
    # Validate certificate format
    if ! openssl x509 -in "$MILOU_SSL_CERT_FILE" -noout -text >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Invalid certificate format"
        ((errors++))
    fi
    
    # Validate key file (support both RSA and EC keys)
    if ! ssl_validate_key_file "$MILOU_SSL_KEY_FILE" "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Invalid private key format"
        ((errors++))
    fi
    
    # Check if certificate and key match
    if ! ssl_validate_cert_key_pair "$MILOU_SSL_CERT_FILE" "$MILOU_SSL_KEY_FILE" "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate and private key do not match"
        ((errors++))
    fi
    
    # Check certificate expiration
    if ! ssl_check_expiration "$MILOU_SSL_CERT_FILE" "$quiet" "$min_days_valid"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate is expired or expires soon"
        ((errors++))
    fi
    
    # Check domain match
    if ! ssl_validate_certificate_domain "$MILOU_SSL_CERT_FILE" "$domain" "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "WARN" "Certificate domain may not match: $domain"
        # Note: Not incrementing errors as this might be intentional for localhost
    fi
    
    if [[ $errors -eq 0 ]]; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ SSL certificate validation passed"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "SSL certificate validation failed ($errors errors)"
        return 1
    fi
}

# Get comprehensive SSL status - SINGLE AUTHORITATIVE IMPLEMENTATION
ssl_status() {
    local domain="${1:-localhost}"
    local quiet="${2:-false}"
    
    if [[ "$quiet" != "true" ]]; then
        milou_log "INFO" "🔍 SSL Certificate Status"
        echo
    fi
    
    # Check if certificates exist
    if [[ ! -f "$MILOU_SSL_CERT_FILE" || ! -f "$MILOU_SSL_KEY_FILE" ]]; then
        if [[ "$quiet" != "true" ]]; then
            milou_log "INFO" "📋 Status: No certificates found"
            milou_log "INFO" "📁 Expected location: $MILOU_SSL_DIR"
        fi
        return 1
    fi
    
    local cert_valid=false
    local key_valid=false
    local cert_info=""
    
    # Validate certificate file
    if openssl x509 -in "$MILOU_SSL_CERT_FILE" -noout -text >/dev/null 2>&1; then
        cert_valid=true
        cert_info=$(openssl x509 -in "$MILOU_SSL_CERT_FILE" -noout -subject -dates 2>/dev/null || echo "")
    fi
    
    # Validate key file using enhanced validation (supports both RSA and EC keys)
    if ssl_validate_key_file "$MILOU_SSL_KEY_FILE" "true"; then
        key_valid=true
    fi
    
    # Check if certificate and key match
    local cert_key_match=false
    if [[ "$cert_valid" == "true" && "$key_valid" == "true" ]]; then
        if ssl_validate_cert_key_pair "$MILOU_SSL_CERT_FILE" "$MILOU_SSL_KEY_FILE" "true"; then
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
        if ssl_validate_certificate_domain "$MILOU_SSL_CERT_FILE" "$domain" "true"; then
            domain_match=true
        fi
    fi
    
    # Display detailed status
    if [[ "$quiet" != "true" ]]; then
        echo "  📁 Location: $MILOU_SSL_DIR"
        echo "  📄 Certificate: $([ "$cert_valid" == "true" ] && echo "✅ Valid" || echo "❌ Invalid")"
        echo "  🔑 Private Key: $([ "$key_valid" == "true" ] && echo "✅ Valid" || echo "❌ Invalid")"
        echo "  🔗 Cert-Key Match: $([ "$cert_key_match" == "true" ] && echo "✅ Match" || echo "❌ Mismatch")"
        echo "  🌐 Domain Match: $([ "$domain_match" == "true" ] && echo "✅ $domain" || echo "❌ Not for $domain")"
        
        if [[ "$cert_expired" == "true" ]]; then
            echo "  ⏰ Expiration: ❌ Expired"
        elif [[ -n "$days_until_expiry" ]]; then
            if [[ "$days_until_expiry" -lt 30 ]]; then
                echo "  ⏰ Expiration: ⚠️  Expires in $days_until_expiry days"
            else
                echo "  ⏰ Expiration: ✅ Valid ($days_until_expiry days)"
            fi
        else
            echo "  ⏰ Expiration: ❓ Unknown"
        fi
        
        # Show certificate info if available
        if [[ -n "$cert_info" ]]; then
            echo
            milou_log "INFO" "📜 Certificate Details:"
            ssl_show_certificate_info "$MILOU_SSL_CERT_FILE" "$quiet"
        fi
        echo
    fi
    
    # Return overall health status
    if [[ "$cert_valid" == "true" && "$key_valid" == "true" && "$cert_key_match" == "true" && "$cert_expired" != "true" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ SSL certificates are healthy"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "WARN" "⚠️ SSL certificates need attention"
        return 1
    fi
}

# =============================================================================
# SSL HELPER FUNCTIONS
# =============================================================================

# Check if SSL is enabled (certificates exist)
ssl_is_enabled() {
    [[ -f "$MILOU_SSL_CERT_FILE" && -f "$MILOU_SSL_KEY_FILE" ]]
}

# Get SSL directory path
ssl_get_path() {
    echo "$MILOU_SSL_DIR"
}

# Validate certificate and key pair match - SINGLE AUTHORITATIVE IMPLEMENTATION
ssl_validate_cert_key_pair() {
    local cert_file="$1"
    local key_file="$2"
    local quiet="${3:-false}"
    
    if [[ ! -f "$cert_file" || ! -f "$key_file" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate or key file not found"
        return 1
    fi
    
    # Modern method: Compare public key hashes (works for all key types: RSA, EC, etc.)
    local cert_pubkey_hash key_pubkey_hash
    
    # Extract public key hash from certificate
    cert_pubkey_hash=$(openssl x509 -in "$cert_file" -pubkey -noout 2>/dev/null | openssl dgst -sha256 2>/dev/null | cut -d' ' -f2)
    
    # Extract public key hash from private key
    key_pubkey_hash=$(openssl pkey -in "$key_file" -pubout 2>/dev/null | openssl dgst -sha256 2>/dev/null | cut -d' ' -f2)
    
    if [[ -n "$cert_pubkey_hash" && -n "$key_pubkey_hash" && "$cert_pubkey_hash" == "$key_pubkey_hash" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "TRACE" "Certificate and key pair match"
        return 0
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate and key pair do not match"
    return 1
}

# Check certificate expiration - SINGLE AUTHORITATIVE IMPLEMENTATION
ssl_check_expiration() {
    local cert_file="$1"
    local quiet="${2:-false}"
    local min_days="${3:-7}"
    
    if [[ ! -f "$cert_file" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate file not found: $cert_file"
        return 1
    fi
    
    local exp_date
    exp_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2 || echo "")
    
    if [[ -z "$exp_date" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Cannot read certificate expiration date"
        return 1
    fi
    
    local exp_timestamp current_timestamp days_until_expiry
    exp_timestamp=$(date -d "$exp_date" +%s 2>/dev/null || echo "0")
    current_timestamp=$(date +%s)
    
    if [[ "$exp_timestamp" -le "$current_timestamp" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate has expired"
        return 1
    fi
    
    days_until_expiry=$(( (exp_timestamp - current_timestamp) / 86400 ))
    
    if [[ "$days_until_expiry" -lt "$min_days" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "WARN" "Certificate expires in $days_until_expiry days (minimum: $min_days)"
        return 1
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "TRACE" "Certificate valid for $days_until_expiry days"
    return 0
}

# Validate certificate domain - SINGLE AUTHORITATIVE IMPLEMENTATION
ssl_validate_certificate_domain() {
    local cert_file="$1"
    local domain="$2"
    local quiet="${3:-false}"
    
    if [[ ! -f "$cert_file" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate file not found: $cert_file"
        return 1
    fi
    
    # Extract certificate text for domain validation
    local cert_text
    cert_text=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null || echo "")
    
    if [[ -z "$cert_text" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Cannot read certificate content"
        return 1
    fi
    
    # Check for exact domain match in CN or SAN
    if echo "$cert_text" | grep -E "(CN|DNS).*\b${domain}\b" >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "TRACE" "Certificate valid for domain: $domain"
        return 0
    fi
    
    # Check for wildcard match
    local domain_parts
    IFS='.' read -ra domain_parts <<< "$domain"
    if [[ ${#domain_parts[@]} -gt 1 ]]; then
        local parent_domain="${domain#*.}"
        if echo "$cert_text" | grep -E "(CN|DNS).*\*\.${parent_domain}" >/dev/null 2>&1; then
            [[ "$quiet" != "true" ]] && milou_log "TRACE" "Certificate valid for domain via wildcard: *.${parent_domain}"
            return 0
        fi
    fi
    
    # Special case: localhost certificates often include 127.0.0.1
    if [[ "$domain" == "localhost" ]] && echo "$cert_text" | grep -E "(CN|DNS).*(localhost|127\.0\.0\.1)" >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "TRACE" "Certificate valid for localhost"
        return 0
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "WARN" "Certificate not valid for domain: $domain"
    return 1
}

# Create OpenSSL configuration file - SINGLE AUTHORITATIVE IMPLEMENTATION
ssl_create_openssl_config() {
    local domain="$1"
    local quiet="${2:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Creating OpenSSL configuration for domain: $domain"
    
    cat > "$MILOU_SSL_CONFIG_FILE" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = State
L = City
O = Milou
OU = IT Department
CN = $domain

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $domain
DNS.2 = localhost
DNS.3 = 127.0.0.1
EOF

    # Add wildcard for non-localhost domains
    if [[ "$domain" != "localhost" && "$domain" != "127.0.0.1" ]]; then
        echo "DNS.4 = *.$domain" >> "$MILOU_SSL_CONFIG_FILE"
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "TRACE" "OpenSSL configuration created: $MILOU_SSL_CONFIG_FILE"
    return 0
}

# Show certificate information - SINGLE AUTHORITATIVE IMPLEMENTATION
ssl_show_certificate_info() {
    local cert_file="${1:-$MILOU_SSL_CERT_FILE}"
    local quiet="${2:-false}"
    
    if [[ ! -f "$cert_file" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Certificate file not found: $cert_file"
        return 1
    fi
    
    local cert_info
    cert_info=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null || echo "")
    
    if [[ -z "$cert_info" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Cannot read certificate information"
        return 1
    fi
    
    # Extract key information
    local subject issuer not_before not_after
    subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | cut -d= -f2- || echo "Unknown")
    issuer=$(openssl x509 -in "$cert_file" -noout -issuer 2>/dev/null | cut -d= -f2- || echo "Unknown")
    not_before=$(openssl x509 -in "$cert_file" -noout -startdate 2>/dev/null | cut -d= -f2 || echo "Unknown")
    not_after=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2 || echo "Unknown")
    
    if [[ "$quiet" != "true" ]]; then
        echo "    Subject: $subject"
        echo "    Issuer: $issuer"
        echo "    Valid from: $not_before"
        echo "    Valid until: $not_after"
        
        # Show SAN entries
        local san_entries
        san_entries=$(echo "$cert_info" | grep -A 1 "Subject Alternative Name" | tail -1 2>/dev/null || echo "")
        if [[ -n "$san_entries" ]]; then
            echo "    Subject Alt Names: $san_entries"
        fi
    fi
    
    return 0
}

# Save SSL certificate information - SINGLE AUTHORITATIVE IMPLEMENTATION
ssl_save_info() {
    local domain="$1"
    local ssl_type="$2"
    local quiet="${3:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Saving SSL certificate information"
    
    cat > "$MILOU_SSL_INFO_FILE" << EOF
DOMAIN=$domain
SSL_TYPE=$ssl_type
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CERT_FILE=$MILOU_SSL_CERT_FILE
KEY_FILE=$MILOU_SSL_KEY_FILE
VALIDITY_DAYS=$MILOU_SSL_DEFAULT_VALIDITY_DAYS
KEY_SIZE=$MILOU_SSL_DEFAULT_KEY_SIZE
EOF
    
    [[ "$quiet" != "true" ]] && milou_log "TRACE" "SSL information saved to: $MILOU_SSL_INFO_FILE"
    return 0
}

# Backup existing certificates - SINGLE AUTHORITATIVE IMPLEMENTATION
ssl_backup_certificates() {
    local quiet="${1:-false}"
    
    if [[ ! -f "$MILOU_SSL_CERT_FILE" && ! -f "$MILOU_SSL_KEY_FILE" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "No certificates to backup"
        return 0
    fi
    
    ensure_directory "$MILOU_SSL_BACKUP_DIR" "755" >/dev/null 2>&1
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backed_up=0
    
    if [[ -f "$MILOU_SSL_CERT_FILE" ]]; then
        if cp "$MILOU_SSL_CERT_FILE" "$MILOU_SSL_BACKUP_DIR/milou.crt.${timestamp}"; then
            ((backed_up++))
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Backed up certificate"
        fi
    fi
    
    if [[ -f "$MILOU_SSL_KEY_FILE" ]]; then
        if cp "$MILOU_SSL_KEY_FILE" "$MILOU_SSL_BACKUP_DIR/milou.key.${timestamp}"; then
            ((backed_up++))
            [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Backed up private key"
        fi
    fi
    
    if [[ $backed_up -gt 0 ]]; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ SSL certificates backed up ($backed_up files)"
    else
        [[ "$quiet" != "true" ]] && milou_log "WARN" "Failed to backup SSL certificates"
        return 1
    fi
    
    return 0
}

# Clean up SSL certificates - SINGLE AUTHORITATIVE IMPLEMENTATION
ssl_cleanup() {
    local quiet="${1:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🗑️ Cleaning up SSL certificates"
    
    # Backup before cleanup if certificates exist
    if [[ -f "$MILOU_SSL_CERT_FILE" || -f "$MILOU_SSL_KEY_FILE" ]]; then
        ssl_backup_certificates "$quiet"
    fi
    
    # Remove certificate files
    rm -f "$MILOU_SSL_CERT_FILE" "$MILOU_SSL_KEY_FILE" "$MILOU_SSL_CONFIG_FILE" 2>/dev/null || true
    
    # Archive info file
    if [[ -f "$MILOU_SSL_INFO_FILE" ]]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        mv "$MILOU_SSL_INFO_FILE" "$MILOU_SSL_BACKUP_DIR/ssl_info.${timestamp}" 2>/dev/null || rm -f "$MILOU_SSL_INFO_FILE" 2>/dev/null || true
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ SSL certificates cleaned up"
    return 0
}

# =============================================================================
# LETSENCRYPT FUNCTIONS (Simplified)
# =============================================================================

# Check if domain can use Let's Encrypt
ssl_can_use_letsencrypt() {
    local domain="$1"
    
    # Skip for localhost/IP addresses
    if [[ "$domain" == "localhost" || "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 1
    fi
    
    # Check if domain looks valid for Let's Encrypt
    if [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    fi
    
    return 1
}

# Install certbot (enhanced implementation)
ssl_install_certbot() {
    local quiet="${1:-false}"
    
    if command -v certbot >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "TRACE" "certbot already installed"
        return 0
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "📦 Installing certbot..."
    
    # Update package lists first
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq >/dev/null 2>&1
        if apt-get install -y certbot python3-certbot-nginx >/dev/null 2>&1; then
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ certbot installed successfully (apt)"
            return 0
        fi
    elif command -v yum >/dev/null 2>&1; then
        if yum install -y certbot python3-certbot-nginx >/dev/null 2>&1; then
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ certbot installed successfully (yum)"
            return 0
        fi
    elif command -v dnf >/dev/null 2>&1; then
        if dnf install -y certbot python3-certbot-nginx >/dev/null 2>&1; then
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ certbot installed successfully (dnf)"
            return 0
        fi
    elif command -v snap >/dev/null 2>&1; then
        if snap install certbot --classic >/dev/null 2>&1; then
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ certbot installed successfully (snap)"
            return 0
        fi
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to install certbot"
    [[ "$quiet" != "true" ]] && milou_log "INFO" "💡 Try installing manually: apt install certbot"
    return 1
}

# Enhanced port 80 status check
ssl_check_port_80_status() {
    local quiet="${1:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Checking port 80 availability for Let's Encrypt"
    
    # Check if port 80 is in use
    if ss -tlnp | grep -q ":80 "; then
        local process
        process=$(ss -tlnp | grep ":80 " | head -1 | awk '{print $NF}' | cut -d',' -f2 2>/dev/null || echo "unknown")
        [[ "$quiet" != "true" ]] && milou_log "WARN" "Port 80 is in use by: $process"
        
        # Check if it's a service we can temporarily stop
        if systemctl is-active nginx >/dev/null 2>&1 || systemctl is-active apache2 >/dev/null 2>&1; then
            [[ "$quiet" != "true" ]] && milou_log "INFO" "Can temporarily stop web server for certificate generation"
            return 0
        else
            [[ "$quiet" != "true" ]] && milou_log "WARN" "Port 80 conflict may prevent Let's Encrypt"
            return 1
        fi
    else
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Port 80 is available"
        return 0
    fi
}

# Remove the stub implementations and replace with enhanced ones
ssl_generate_letsencrypt_standalone() {
    ssl_letsencrypt_standalone "$@"
}

ssl_generate_letsencrypt_with_nginx_stop() {
    ssl_letsencrypt_nginx "$@"
}

# Enhanced troubleshooting guide
ssl_show_letsencrypt_troubleshooting() {
    local domain="$1"
    
    echo
    echo -e "${BLUE}💡 Let's Encrypt Troubleshooting Guide for $domain${NC}"
    echo "============================================================"
    echo
    echo -e "${BOLD}Common Issues and Solutions:${NC}"
    echo
    echo -e "${GREEN}1. Domain Configuration:${NC}"
    echo "   • Ensure $domain points to this server's IP address"
    echo "   • Check DNS with: nslookup $domain"
    echo "   • Verify A record is correct in DNS settings"
    echo
    echo -e "${GREEN}2. Network Connectivity:${NC}"
    echo "   • Port 80 must be accessible from the internet"
    echo "   • Check firewall: ufw status or iptables -L"
    echo "   • Test external access: curl -I http://$domain"
    echo
    echo -e "${GREEN}3. Server Requirements:${NC}"
    echo "   • Stop conflicting web servers: systemctl stop nginx apache2"
    echo "   • Ensure no other service uses port 80"
    echo "   • Check with: ss -tlnp | grep :80"
    echo
    echo -e "${GREEN}4. Rate Limiting:${NC}"
    echo "   • Let's Encrypt has rate limits (5 failures per hour)"
    echo "   • Wait before retrying if you hit limits"
    echo "   • Use staging environment for testing"
    echo
    echo -e "${YELLOW}💡 Alternative Options:${NC}"
    echo "   • Use self-signed certificates: Choose option 3"
    echo "   • Import existing certificates: Choose option 2"
    echo "   • Try manual verification later"
    echo
    echo -e "${CYAN}🔧 Manual Let's Encrypt Commands:${NC}"
    echo "   • Test: certbot certonly --dry-run --standalone -d $domain"
    echo "   • Get cert: certbot certonly --standalone -d $domain"
    echo "   • Check status: certbot certificates"
    echo
}

# Enhanced certificate generation with better error handling
ssl_generate_self_signed() {
    local domain="${1:-localhost}"
    local force="${2:-false}"
    local quiet="${3:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🔒 Generating self-signed certificate for: $domain"
    
    # Initialize SSL environment
    ssl_init "$quiet" || return 1
    
    # Backup existing certificates if they exist and not forced
    if [[ "$force" != "true" ]] && [[ -f "$MILOU_SSL_CERT_FILE" || -f "$MILOU_SSL_KEY_FILE" ]]; then
        ssl_backup_certificates "$quiet"
    fi
    
    # Create OpenSSL configuration
    if ! ssl_create_openssl_config "$domain" "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to create OpenSSL configuration"
        return 1
    fi
    
    # Generate private key
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Generating RSA private key ($MILOU_SSL_DEFAULT_KEY_SIZE bits)"
    if ! openssl genrsa -out "$MILOU_SSL_KEY_FILE" "$MILOU_SSL_DEFAULT_KEY_SIZE" >/dev/null 2>&1; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Failed to generate private key"
        return 1
    fi
    
    # Generate certificate
    # Set secure permissions
    chmod 644 "$MILOU_SSL_CERT_FILE" 2>/dev/null || true
    chmod 600 "$MILOU_SSL_KEY_FILE" 2>/dev/null || true
    
    # Validate the installed certificates
    if ssl_validate "$domain" "true"; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Existing certificates installed successfully"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "📄 Certificate: $MILOU_SSL_CERT_FILE"
        [[ "$quiet" != "true" ]] && milou_log "INFO" "🔑 Private key: $MILOU_SSL_KEY_FILE"
        ssl_save_info "$domain" "existing" "$quiet"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Installed certificates failed validation"
        return 1
    fi
}

# Enhanced helper function for setup integration
ssl_interactive_setup() {
    local domain="${1:-localhost}"
    local quiet="${2:-false}"
    
    [[ "$quiet" == "true" ]] && return 0
    
    echo
    echo -e "${BOLD}${BLUE}🔒 SSL Certificate Configuration${NC}"
    echo "========================================"
    echo
    echo "Milou requires SSL certificates for secure operation."
    echo -e "Domain: ${BOLD}$domain${NC}"
    echo
    
    # Check if certificates already exist
    if ssl_is_enabled; then
        echo -e "${GREEN}✓ SSL certificates found${NC}"
        if ssl_validate "$domain" "true"; then
            echo -e "${GREEN}✓ Certificates are valid${NC}"
            echo
            if milou_confirm "Keep existing certificates?" "Y"; then
                return 0
            fi
        else
            echo -e "${YELLOW}⚠ Certificates may be invalid or expired${NC}"
            echo
        fi
    else
        echo -e "${YELLOW}⚠ No SSL certificates found${NC}"
        echo
    fi
    
    # Get SSL mode from user
    local ssl_mode
    ssl_mode=$(ssl_select_mode_interactive "$domain" "auto" "$quiet")
    
    # Execute SSL setup
    ssl_setup "$domain" "$ssl_mode" "" "false" "$quiet"
    return $?
}

# Add missing Let's Encrypt function implementations
ssl_generate_letsencrypt_enhanced() {
    local domain="$1"
    local force="${2:-false}"
    local quiet="${3:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🔐 Enhanced Let's Encrypt setup for: $domain"
    
    # Pre-flight checks
    if ! ssl_verify_domain_for_letsencrypt "$domain" "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Domain verification failed for Let's Encrypt"
        return 1
    fi
    
    # Attempt certificate generation with multiple methods
    if ssl_attempt_letsencrypt_certificate "$domain" "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Let's Encrypt certificate obtained"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Let's Encrypt certificate generation failed"
        ssl_show_letsencrypt_troubleshooting "$domain"
        return 1
    fi
}

ssl_verify_domain_for_letsencrypt() {
    local domain="$1"
    local quiet="${2:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Verifying domain for Let's Encrypt: $domain"
    
    # Basic domain format check
    if ! ssl_can_use_letsencrypt "$domain"; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Domain not suitable for Let's Encrypt: $domain"
        return 1
    fi
    
    # DNS resolution check
    if command -v nslookup >/dev/null 2>&1; then
        if ! nslookup "$domain" >/dev/null 2>&1; then
            [[ "$quiet" != "true" ]] && milou_log "WARN" "DNS resolution failed for domain: $domain"
            return 1
        fi
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Domain verification passed"
    return 0
}

ssl_attempt_letsencrypt_certificate() {
    local domain="$1"
    local quiet="${2:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Attempting Let's Encrypt certificate generation"
    
    # Install certbot if needed
    if ! ssl_install_certbot "$quiet"; then
        return 1
    fi
    
    # Try different acquisition methods
    local methods=("standalone" "webroot" "nginx")
    
    for method in "${methods[@]}"; do
        [[ "$quiet" != "true" ]] && milou_log "INFO" "Trying method: $method"
        
        case "$method" in
            "standalone")
                if ssl_letsencrypt_standalone "$domain" "$quiet"; then
                    return 0
                fi
                ;;
            "webroot")
                if ssl_letsencrypt_webroot "$domain" "$quiet"; then
                    return 0
                fi
                ;;
            "nginx")
                if ssl_letsencrypt_nginx "$domain" "$quiet"; then
                    return 0
                fi
                ;;
        esac
    done
    
    return 1
}

ssl_letsencrypt_standalone() {
    local domain="$1"
    local quiet="${2:-false}"
    local email="${ADMIN_EMAIL:-admin@${domain}}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Attempting standalone Let's Encrypt certificate"
    
    # Check port 80 availability
    if ! ssl_check_port_80_status "$quiet"; then
        [[ "$quiet" != "true" ]] && milou_log "WARN" "Port 80 not available for standalone mode"
        return 1
    fi
    
    # Attempt certificate generation
    if certbot certonly --standalone --non-interactive --agree-tos \
        --email "$email" -d "$domain" >/dev/null 2>&1; then
        
        # Copy certificates to our SSL directory
        if ssl_copy_letsencrypt_certificates "$domain" "$quiet"; then
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Standalone Let's Encrypt certificate obtained"
            return 0
        fi
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "ERROR" "Standalone Let's Encrypt failed"
    return 1
}

ssl_letsencrypt_webroot() {
    local domain="$1"
    local quiet="${2:-false}"
    local email="${ADMIN_EMAIL:-admin@${domain}}"
    local webroot_path="/tmp/letsencrypt-webroot"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Attempting webroot Let's Encrypt certificate"
    
    # Create webroot directory
    mkdir -p "$webroot_path"
    
    # Attempt certificate generation
    if certbot certonly --webroot -w "$webroot_path" --non-interactive \
        --agree-tos --email "$email" -d "$domain" >/dev/null 2>&1; then
        
        # Copy certificates to our SSL directory
        if ssl_copy_letsencrypt_certificates "$domain" "$quiet"; then
            [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Webroot Let's Encrypt certificate obtained"
            rm -rf "$webroot_path"
            return 0
        fi
    fi
    
    rm -rf "$webroot_path"
    [[ "$quiet" != "true" ]] && milou_log "ERROR" "Webroot Let's Encrypt failed"
    return 1
}

ssl_letsencrypt_nginx() {
    local domain="$1"
    local quiet="${2:-false}"
    local email="${ADMIN_EMAIL:-admin@${domain}}"
    
    [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Attempting nginx Let's Encrypt certificate"
    
    # Stop nginx if running
    local nginx_was_running=false
    if systemctl is-active nginx >/dev/null 2>&1; then
        nginx_was_running=true
        systemctl stop nginx >/dev/null 2>&1
    fi
    
    # Use standalone mode since nginx is stopped
    local result=1
    if ssl_letsencrypt_standalone "$domain" "$quiet"; then
        result=0
    fi
    
    # Restart nginx if it was running
    if [[ "$nginx_was_running" == "true" ]]; then
        systemctl start nginx >/dev/null 2>&1
    fi
    
    return $result
}

ssl_copy_letsencrypt_certificates() {
    local domain="$1"
    local quiet="${2:-false}"
    
    local letsencrypt_dir="/etc/letsencrypt/live/$domain"
    
    if [[ ! -d "$letsencrypt_dir" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Let's Encrypt directory not found: $letsencrypt_dir"
        return 1
    fi
    
    # Copy fullchain and private key
    if [[ -f "$letsencrypt_dir/fullchain.pem" && -f "$letsencrypt_dir/privkey.pem" ]]; then
        cp "$letsencrypt_dir/fullchain.pem" "$MILOU_SSL_CERT_FILE"
        cp "$letsencrypt_dir/privkey.pem" "$MILOU_SSL_KEY_FILE"
        
        # Set secure permissions
        chmod 644 "$MILOU_SSL_CERT_FILE"
        chmod 600 "$MILOU_SSL_KEY_FILE"
        
        [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Let's Encrypt certificates copied"
        return 0
    else
        [[ "$quiet" != "true" ]] && milou_log "ERROR" "Let's Encrypt certificate files not found"
        return 1
    fi
}

# Setup existing certificates - ENHANCED IMPLEMENTATION  
ssl_setup_existing() {
    local domain="$1"
    local cert_source="$2"
    local force="$3"
    local quiet="$4"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "Setting up existing SSL certificates"
    
    # Use the enhanced version
    ssl_setup_existing_enhanced "$domain" "$cert_source" "$force" "$quiet"
}

# =============================================================================
# EXPORT ALL FUNCTIONS
# =============================================================================

# Core SSL operations
export -f ssl_init
export -f ssl_setup
export -f ssl_status
export -f ssl_validate
export -f ssl_generate_self_signed
export -f ssl_generate_letsencrypt
export -f ssl_setup_existing
export -f ssl_cleanup

# Enhanced SSL functions
export -f ssl_detect_script_dir
export -f ssl_select_mode_interactive
export -f ssl_setup_existing_enhanced
export -f ssl_generate_letsencrypt_enhanced
export -f ssl_verify_domain_for_letsencrypt
export -f ssl_attempt_letsencrypt_certificate
export -f ssl_letsencrypt_standalone
export -f ssl_letsencrypt_webroot
export -f ssl_letsencrypt_nginx
export -f ssl_interactive_setup

# SSL utility functions
export -f ssl_is_enabled
export -f ssl_get_path
export -f ssl_validate_key_file
export -f ssl_validate_cert_key_pair
export -f ssl_check_expiration
export -f ssl_validate_certificate_domain
export -f ssl_create_openssl_config
export -f ssl_show_certificate_info
export -f ssl_save_info
export -f ssl_backup_certificates

# Let's Encrypt functions
export -f ssl_can_use_letsencrypt
export -f ssl_install_certbot
export -f ssl_check_port_80_status
export -f ssl_generate_letsencrypt_standalone
export -f ssl_generate_letsencrypt_with_nginx_stop
export -f ssl_show_letsencrypt_troubleshooting
export -f ssl_copy_letsencrypt_certificates

milou_log "DEBUG" "SSL module loaded successfully"

