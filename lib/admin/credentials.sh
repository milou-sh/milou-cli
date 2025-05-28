#!/bin/bash

# =============================================================================
# Milou CLI Admin Credentials Management Module
# Extracted from monolithic system.sh for better organization
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Module guard to prevent multiple loading
if [[ "${MILOU_ADMIN_CREDENTIALS_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_ADMIN_CREDENTIALS_LOADED="true"

# Update admin password in database
_milou_admin_update_database_password() {
    local new_password="$1"
    
    # Check if database container is running
    if ! docker ps --filter "name=static-database" --format "{{.Names}}" | grep -q "static-database"; then
        milou_log "DEBUG" "Database container not running - password will be updated on next startup"
        return 1
    fi
    
    # Get database credentials
    local env_file="${SCRIPT_DIR}/.env"
    local db_name="${POSTGRES_DB:-milou_database}"
    local db_user="${POSTGRES_USER:-milou_user}"
    
    # Hash the password (this depends on your application's password hashing method)
    local password_hash
    if command -v python3 >/dev/null 2>&1; then
        password_hash=$(python3 -c "
import hashlib
import secrets
import base64

password = '$new_password'
salt = secrets.token_bytes(32)
pwdhash = hashlib.pbkdf2_hmac('sha256', password.encode('utf-8'), salt, 100000)
print(base64.b64encode(salt + pwdhash).decode('ascii'))
" 2>/dev/null)
    fi
    
    if [[ -n "$password_hash" ]]; then
        # Update password in database (adjust SQL based on your schema)
        local sql_update="UPDATE users SET password_hash='$password_hash' WHERE username='admin' OR email='admin@localhost';"
        
        if docker exec static-database psql -U "$db_user" -d "$db_name" -c "$sql_update" >/dev/null 2>&1; then
            return 0
        fi
    fi
    
    return 1
}

# Display current admin credentials
milou_admin_show_credentials() {
    milou_log "STEP" "🔑 Displaying admin credentials..."
    
    local env_file="${SCRIPT_DIR}/.env"
    
    if [[ ! -f "$env_file" ]]; then
        milou_log "ERROR" "Environment file not found: $env_file"
        milou_log "INFO" "💡 Run './milou.sh setup' to create initial configuration"
        return 1
    fi
    
    # Extract credentials from environment file
    local admin_user admin_password admin_email
    admin_user=$(grep "^ADMIN_USER=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "admin")
    admin_password=$(grep "^ADMIN_PASSWORD=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    admin_email=$(grep "^ADMIN_EMAIL=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    
    # Get domain information
    local domain
    domain=$(grep "^DOMAIN=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//') 
    domain="${domain:-localhost}"
    
    # Display credentials in a clear format
    echo ""
    echo "🔑 MILOU ADMIN CREDENTIALS"
    echo "=========================="
    echo "👤 Username: $admin_user"
    if [[ -n "$admin_password" ]]; then
        echo "🔒 Password: $admin_password"
    else
        echo "🔒 Password: (not set - check environment file)"
    fi
    if [[ -n "$admin_email" ]]; then
        echo "📧 Email: $admin_email"
    fi
    echo "🌐 Access URL: https://$domain/"
    echo ""
    echo "⚠️  IMPORTANT: Save these credentials securely!"
    echo "   You'll need them to access the web interface."
    echo ""
    
    return 0
}

# Reset admin password
milou_admin_reset_password() {
    local new_password="${1:-}"
    local force="${2:-false}"
    
    milou_log "STEP" "🔄 Resetting admin password..."
    
    local env_file="${SCRIPT_DIR}/.env"
    
    if [[ ! -f "$env_file" ]]; then
        milou_log "ERROR" "Environment file not found: $env_file"
        return 1
    fi
    
    # Generate new password if not provided
    if [[ -z "$new_password" ]]; then
        if command -v milou_generate_secure_random >/dev/null 2>&1; then
            new_password=$(milou_generate_secure_random 16)
        else
            # Fallback password generation
            new_password=$(openssl rand -base64 16 2>/dev/null || date +%s | sha256sum | base64 | head -c 16)
        fi
        milou_log "INFO" "🎲 Generated new secure password"
    fi
    
    # Confirm password reset unless forced
    if [[ "$force" != "true" ]]; then
        echo ""
        echo "⚠️  WARNING: This will change the admin password!"
        echo "   Current admin will need to use the new password."
        echo ""
        
        if command -v milou_confirm >/dev/null 2>&1; then
            if ! milou_confirm "Do you want to proceed with password reset?"; then
                milou_log "INFO" "Password reset cancelled"
                return 0
            fi
        else
            read -p "Do you want to proceed? (y/N): " -r confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                milou_log "INFO" "Password reset cancelled"
                return 0
            fi
        fi
    fi
    
    # Backup environment file
    cp "$env_file" "${env_file}.backup.$(date +%s)"
    milou_log "DEBUG" "Environment file backed up"
    
    # Update password in environment file
    if grep -q "^ADMIN_PASSWORD=" "$env_file"; then
        sed -i "s/^ADMIN_PASSWORD=.*/ADMIN_PASSWORD=\"$new_password\"/" "$env_file"
    else
        echo "ADMIN_PASSWORD=\"$new_password\"" >> "$env_file"
    fi
    
    # Update password in database if services are running
    if _milou_admin_update_database_password "$new_password"; then
        milou_log "SUCCESS" "✅ Admin password updated in database"
    else
        milou_log "WARN" "⚠️ Password updated in configuration, but database update failed"
        milou_log "INFO" "💡 Restart services to apply the new password"
    fi
    
    milou_log "SUCCESS" "✅ Admin password reset completed"
    milou_log "INFO" "🔑 New password: $new_password"
    milou_log "INFO" "⚠️  Please save this password securely!"
    
    return 0
}

# Create initial admin user
milou_admin_create_user() {
    local username="${1:-admin}"
    local password="${2:-}"
    local email="${3:-admin@localhost}"
    
    milou_log "INFO" "👤 Creating admin user: $username"
    
    # Generate password if not provided
    if [[ -z "$password" ]]; then
        if command -v milou_generate_secure_random >/dev/null 2>&1; then
            password=$(milou_generate_secure_random 16)
        else
            password=$(openssl rand -base64 16 2>/dev/null || date +%s | sha256sum | base64 | head -c 16)
        fi
        milou_log "DEBUG" "Generated secure password for admin user"
    fi
    
    # Update environment file
    local env_file="${SCRIPT_DIR}/.env"
    
    # Backup environment file
    if [[ -f "$env_file" ]]; then
        cp "$env_file" "${env_file}.backup.$(date +%s)"
    fi
    
    # Update or add admin credentials
    if [[ -f "$env_file" ]]; then
        # Update existing values
        if grep -q "^ADMIN_USER=" "$env_file"; then
            sed -i "s/^ADMIN_USER=.*/ADMIN_USER=\"$username\"/" "$env_file"
        else
            echo "ADMIN_USER=\"$username\"" >> "$env_file"
        fi
        
        if grep -q "^ADMIN_PASSWORD=" "$env_file"; then
            sed -i "s/^ADMIN_PASSWORD=.*/ADMIN_PASSWORD=\"$password\"/" "$env_file"
        else
            echo "ADMIN_PASSWORD=\"$password\"" >> "$env_file"
        fi
        
        if grep -q "^ADMIN_EMAIL=" "$env_file"; then
            sed -i "s/^ADMIN_EMAIL=.*/ADMIN_EMAIL=\"$email\"/" "$env_file"
        else
            echo "ADMIN_EMAIL=\"$email\"" >> "$env_file"
        fi
    else
        # Create new environment file with admin credentials
        cat > "$env_file" << EOF
# Admin credentials
ADMIN_USER="$username"
ADMIN_PASSWORD="$password"
ADMIN_EMAIL="$email"
EOF
    fi
    
    milou_log "SUCCESS" "✅ Admin user created"
    milou_log "INFO" "🔑 Username: $username"
    milou_log "INFO" "🔒 Password: $password"
    milou_log "INFO" "📧 Email: $email"
    
    return 0
}

# Validate admin credentials
milou_admin_validate_credentials() {
    local env_file="${SCRIPT_DIR}/.env"
    
    if [[ ! -f "$env_file" ]]; then
        milou_log "ERROR" "Environment file not found"
        return 1
    fi
    
    # Check for required admin variables
    local admin_user admin_password
    admin_user=$(grep "^ADMIN_USER=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    admin_password=$(grep "^ADMIN_PASSWORD=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    
    local validation_errors=0
    
    if [[ -z "$admin_user" ]]; then
        milou_log "ERROR" "ADMIN_USER not set in environment"
        ((validation_errors++))
    fi
    
    if [[ -z "$admin_password" ]]; then
        milou_log "ERROR" "ADMIN_PASSWORD not set in environment"
        ((validation_errors++))
    elif [[ ${#admin_password} -lt 8 ]]; then
        milou_log "WARN" "Admin password is less than 8 characters (insecure)"
    fi
    
    if [[ $validation_errors -eq 0 ]]; then
        milou_log "SUCCESS" "✅ Admin credentials validation passed"
        return 0
    else
        milou_log "ERROR" "❌ Admin credentials validation failed ($validation_errors errors)"
        return 1
    fi
}

# =============================================================================
# CLEAN PUBLIC API - Export only essential functions
# =============================================================================

# Main admin functions (4 exports - CLEAN PUBLIC API)
export -f milou_admin_show_credentials      # Display credentials
export -f milou_admin_reset_password        # Reset password
export -f milou_admin_create_user           # Create admin user
export -f milou_admin_validate_credentials  # Validate credentials

# Internal functions are NOT exported (marked with _ prefix)
# This keeps the namespace clean and makes it clear what's public vs internal 