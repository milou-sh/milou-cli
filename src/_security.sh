#!/bin/bash

# =============================================================================
# Milou CLI - Security Module
# Consolidated security functions for credential generation and validation
# Version: 1.0.0 - Clean Architecture
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Module guard to prevent multiple loading
if [[ "${MILOU_SECURITY_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_SECURITY_LOADED="true"

# =============================================================================
# SECURE RANDOM GENERATION - SINGLE AUTHORITATIVE IMPLEMENTATION
# =============================================================================

# Generate secure random strings with multiple entropy sources
generate_secure_random() {
    local length="${1:-32}"
    local format="${2:-safe}"  # safe, alphanumeric, hex, numeric, alpha
    local exclude_ambiguous="${3:-true}"
    
    # Validate input
    if [[ ! "$length" =~ ^[0-9]+$ ]] || [[ "$length" -lt 1 ]]; then
        echo "ERROR: Invalid length: $length" >&2
        return 1
    fi
    
    local chars=""
    case "$format" in
        safe)
            if [[ "$exclude_ambiguous" == "true" ]]; then
                chars="ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#$%^&*()_+-="
            else
                chars="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()_+-="
            fi
            ;;
        alphanumeric)
            if [[ "$exclude_ambiguous" == "true" ]]; then
                chars="ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789"
            else
                chars="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
            fi
            ;;
        hex)
            chars="0123456789abcdef"
            ;;
        numeric)
            if [[ "$exclude_ambiguous" == "true" ]]; then
                chars="23456789"
            else
                chars="0123456789"
            fi
            ;;
        alpha)
            chars="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
            ;;
        *)
            echo "ERROR: Unknown format: $format. Use: safe, alphanumeric, hex, numeric, alpha" >&2
            return 1
            ;;
    esac
    
    local result=""
    
    # Method 1: OpenSSL (most secure)
    if command -v openssl >/dev/null 2>&1; then
        case "$format" in
            hex) 
                result=$(openssl rand -hex "$((length / 2))" 2>/dev/null | cut -c1-"$length")
                ;;
            *)
                local base64_length=$((length * 3))
                local base64_output
                base64_output=$(openssl rand -base64 "$base64_length" 2>/dev/null | tr -d "=+/\n")
                if [[ -n "$base64_output" ]]; then
                    result=""
                    for ((i=0; i<${#base64_output} && ${#result}<length; i++)); do
                        local char="${base64_output:$i:1}"
                        if [[ "$chars" == *"$char"* ]]; then
                            result+="$char"
                        fi
                    done
                fi
                ;;
        esac
    fi
    
    # Method 2: /dev/urandom fallback
    if [[ -z "$result" && -c /dev/urandom ]]; then
        if command -v tr >/dev/null 2>&1; then
            local random_bytes
            random_bytes=$(head -c "$((length * 4))" /dev/urandom 2>/dev/null | tr -dc "$chars" | head -c "$length")
            if [[ ${#random_bytes} -eq $length ]]; then
                result="$random_bytes"
            fi
        fi
    fi
    
    # Method 3: BASH $RANDOM fallback (less secure)
    if [[ -z "$result" ]]; then
        result=""
        for ((i=0; i<length; i++)); do
            result+="${chars:$((RANDOM % ${#chars})):1}"
        done
    fi
    
    # Ensure exact length
    if [[ ${#result} -ne $length ]]; then
        if [[ ${#result} -lt $length ]]; then
            while [[ ${#result} -lt $length ]]; do
                result+="${chars:$((RANDOM % ${#chars})):1}"
            done
        fi
        result="${result:0:$length}"
    fi
    
    echo "$result"
}

# Generate UUID
generate_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    elif [[ -f /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        # Fallback UUID generation
        printf '%08x-%04x-%04x-%04x-%012x\n' \
            $((RANDOM * RANDOM)) \
            $((RANDOM)) \
            $((RANDOM | 0x4000)) \
            $((RANDOM | 0x8000)) \
            $((RANDOM * RANDOM * RANDOM))
    fi
}

# =============================================================================
# CREDENTIAL GENERATION - SINGLE AUTHORITATIVE IMPLEMENTATION
# =============================================================================

# Generate database credentials
generate_database_credentials() {
    local prefix="${1:-milou}"
    
    cat << EOF
POSTGRES_USER=${prefix}_user_$(generate_secure_random 8 "alphanumeric")
POSTGRES_PASSWORD=$(generate_secure_random 32 "safe")
POSTGRES_DB=${prefix}_database
EOF
}

# Generate Redis credentials
generate_redis_credentials() {
    cat << EOF
REDIS_PASSWORD=$(generate_secure_random 32 "safe")
EOF
}

# Generate RabbitMQ credentials
generate_rabbitmq_credentials() {
    local prefix="${1:-milou}"
    
    cat << EOF
RABBITMQ_USER=${prefix}_rabbit_$(generate_secure_random 6 "alphanumeric")
RABBITMQ_PASSWORD=$(generate_secure_random 32 "safe")
EOF
}

# Generate application secrets
generate_app_secrets() {
    cat << EOF
SESSION_SECRET=$(generate_secure_random 64 "safe")
ENCRYPTION_KEY=$(generate_secure_random 64 "hex")
JWT_SECRET=$(generate_secure_random 32 "safe")
API_KEY=$(generate_secure_random 40 "safe")
EOF
}

# Generate admin credentials
generate_admin_credentials() {
    cat << EOF
ADMIN_PASSWORD=$(generate_secure_random 16 "safe")
EOF
}

# Generate all system credentials
generate_all_credentials() {
    local prefix="${1:-milou}"
    
    generate_database_credentials "$prefix"
    generate_redis_credentials
    generate_rabbitmq_credentials "$prefix"
    generate_app_secrets
    generate_admin_credentials
}

# =============================================================================
# TOKEN VALIDATION
# =============================================================================

# Validate GitHub token format
validate_github_token() {
    local token="$1"
    local strict="${2:-true}"
    
    if [[ -z "$token" ]]; then
        return 1
    fi
    
    # GitHub token patterns
    if [[ "$token" =~ ^ghp_[A-Za-z0-9]{36}$ ]] || \
       [[ "$token" =~ ^github_pat_[A-Za-z0-9_]{22,}$ ]] || \
       [[ "$token" =~ ^gho_[A-Za-z0-9]{36}$ ]] || \
       [[ "$token" =~ ^ghu_[A-Za-z0-9]{36}$ ]] || \
       [[ "$token" =~ ^ghs_[A-Za-z0-9]{36}$ ]] || \
       [[ "$token" =~ ^ghr_[A-Za-z0-9]{36}$ ]]; then
        return 0
    fi
    
    if [[ "$strict" == "false" ]]; then
        # Allow legacy tokens in non-strict mode
        if [[ ${#token} -ge 20 ]]; then
            return 0
        fi
    fi
    
    return 1
}

# =============================================================================
# PASSWORD STRENGTH VALIDATION
# =============================================================================

# Validate password strength
validate_password_strength() {
    local password="$1"
    local min_length="${2:-8}"
    
    if [[ ${#password} -lt $min_length ]]; then
        return 1
    fi
    
    # Check for at least one uppercase, lowercase, and number
    if [[ "$password" =~ [A-Z] ]] && \
       [[ "$password" =~ [a-z] ]] && \
       [[ "$password" =~ [0-9] ]]; then
        return 0
    fi
    
    return 1
}

# =============================================================================
# EXPORTS
# =============================================================================

# Export all security functions
export -f generate_secure_random
export -f generate_uuid
export -f generate_database_credentials
export -f generate_redis_credentials
export -f generate_rabbitmq_credentials
export -f generate_app_secrets
export -f generate_admin_credentials
export -f generate_all_credentials
export -f validate_github_token
export -f validate_password_strength 