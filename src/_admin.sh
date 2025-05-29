#!/bin/bash

# =============================================================================
# Milou CLI Admin Management Module
# Professional consolidation of all admin-related functionality
# Final module completing Phase 3 refactoring
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Module guard to prevent multiple loading
if [[ "${MILOU_ADMIN_MODULE_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_ADMIN_MODULE_LOADED="true"

# Load dependencies
if [[ -f "${BASH_SOURCE[0]%/*}/_core.sh" ]]; then
    source "${BASH_SOURCE[0]%/*}/_core.sh" || return 1
fi

# =============================================================================
# ADMIN CREDENTIALS CORE FUNCTIONS
# =============================================================================

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
    
    # Hash the password using Python if available
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
            milou_log "DEBUG" "Database password updated successfully"
            return 0
        else
            milou_log "DEBUG" "Failed to update password in database"
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
    admin_user=$(grep "^ADMIN_USERNAME=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    if [[ -z "$admin_user" ]]; then
        admin_user=$(grep "^ADMIN_USER=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    fi
    admin_user="${admin_user:-admin}"
    
    admin_password=$(grep "^ADMIN_PASSWORD=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    admin_email=$(grep "^ADMIN_EMAIL=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    
    # Get domain information
    local domain
    domain=$(grep "^DOMAIN=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//') 
    domain="${domain:-localhost}"
    
    # Get SSL mode for URL protocol
    local ssl_mode
    ssl_mode=$(grep "^SSL_MODE=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    local protocol="https"
    if [[ "$ssl_mode" == "none" ]]; then
        protocol="http"
    fi
    
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
    echo "🌐 Access URL: $protocol://$domain/"
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
            if ! milou_confirm "Do you want to proceed with password reset?" "N"; then
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
        milou_log "DEBUG" "Environment file backed up"
    fi
    
    # Update or add admin credentials
    if [[ -f "$env_file" ]]; then
        # Update existing values (check both ADMIN_USER and ADMIN_USERNAME)
        if grep -q "^ADMIN_USERNAME=" "$env_file"; then
            sed -i "s/^ADMIN_USERNAME=.*/ADMIN_USERNAME=\"$username\"/" "$env_file"
        elif grep -q "^ADMIN_USER=" "$env_file"; then
            sed -i "s/^ADMIN_USER=.*/ADMIN_USER=\"$username\"/" "$env_file"
        else
            echo "ADMIN_USERNAME=\"$username\"" >> "$env_file"
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
ADMIN_USERNAME="$username"
ADMIN_PASSWORD="$password"
ADMIN_EMAIL="$email"
EOF
        chmod 600 "$env_file"
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
    
    milou_log "INFO" "🔍 Validating admin credentials..."
    
    if [[ ! -f "$env_file" ]]; then
        milou_log "ERROR" "Environment file not found: $env_file"
        return 1
    fi
    
    # Check for required admin variables
    local admin_user admin_password admin_email
    admin_user=$(grep "^ADMIN_USERNAME=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    if [[ -z "$admin_user" ]]; then
        admin_user=$(grep "^ADMIN_USER=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    fi
    admin_password=$(grep "^ADMIN_PASSWORD=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    admin_email=$(grep "^ADMIN_EMAIL=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')
    
    local validation_errors=0
    local validation_warnings=0
    
    # Check for username
    if [[ -z "$admin_user" ]]; then
        milou_log "ERROR" "❌ ADMIN_USERNAME/ADMIN_USER not set in environment"
        ((validation_errors++))
    else
        milou_log "DEBUG" "✅ Admin username: $admin_user"
    fi
    
    # Check for password
    if [[ -z "$admin_password" ]]; then
        milou_log "ERROR" "❌ ADMIN_PASSWORD not set in environment"
        ((validation_errors++))
    elif [[ ${#admin_password} -lt 8 ]]; then
        milou_log "WARN" "⚠️  Admin password is less than 8 characters (insecure)"
        ((validation_warnings++))
    else
        milou_log "DEBUG" "✅ Admin password is set and meets minimum length"
    fi
    
    # Check for email
    if [[ -z "$admin_email" ]]; then
        milou_log "WARN" "⚠️  ADMIN_EMAIL not set in environment"
        ((validation_warnings++))
    else
        # Basic email validation
        if [[ "$admin_email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            milou_log "DEBUG" "✅ Admin email format is valid"
        else
            milou_log "WARN" "⚠️  Admin email format may be invalid: $admin_email"
            ((validation_warnings++))
        fi
    fi
    
    # Report results
    if [[ $validation_errors -eq 0 ]]; then
        if [[ $validation_warnings -eq 0 ]]; then
            milou_log "SUCCESS" "✅ Admin credentials validation passed"
        else
            milou_log "SUCCESS" "✅ Admin credentials validation passed ($validation_warnings warnings)"
        fi
        return 0
    else
        milou_log "ERROR" "❌ Admin credentials validation failed ($validation_errors errors, $validation_warnings warnings)"
        return 1
    fi
}

# =============================================================================
# ADMIN COMMAND HANDLERS
# =============================================================================

# Combined help function to reduce exports
_show_admin_help() {
    local help_type="${1:-main}"
    
    case "$help_type" in
        "main")
            echo "👤 Admin Command Usage"
            echo "======================"
            echo ""
            echo "ADMIN COMMANDS:"
            echo "  ./milou.sh admin [SUBCOMMAND] [OPTIONS]"
            echo ""
            echo "Subcommands:"
            echo "  show, credentials    Display current admin credentials (default)"
            echo "  reset, reset-password Reset admin password"
            echo "  create, create-user  Create new admin user"
            echo "  validate            Validate admin credentials"
            echo "  help                Show this help"
            echo ""
            echo "Examples:"
            echo "  ./milou.sh admin"
            echo "  ./milou.sh admin show"
            echo "  ./milou.sh admin reset --force"
            echo "  ./milou.sh admin create --username newadmin --email admin@example.com"
            echo ""
            echo "For detailed help on subcommands:"
            echo "  ./milou.sh admin [subcommand] --help"
            ;;
        "credentials")
            echo "🔑 Admin Credentials Command"
            echo "==========================="
            echo ""
            echo "DISPLAY CREDENTIALS:"
            echo "  ./milou.sh admin credentials"
            echo "  ./milou.sh admin show"
            echo ""
            echo "This command shows:"
            echo "  • Admin username"
            echo "  • Admin password"
            echo "  • Admin email"
            echo "  • Access URL"
            echo ""
            echo "Note: Keep these credentials secure!"
            ;;
        "reset")
            echo "🔄 Admin Password Reset Command"
            echo "==============================="
            echo ""
            echo "RESET PASSWORD:"
            echo "  ./milou.sh admin reset [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --password PASSWORD   Set specific password (default: auto-generate)"
            echo "  --force               Skip confirmation prompt"
            echo "  --help, -h            Show this help"
            echo ""
            echo "Examples:"
            echo "  ./milou.sh admin reset"
            echo "  ./milou.sh admin reset --password myNewPassword123"
            echo "  ./milou.sh admin reset --force"
            ;;
        "create")
            echo "👤 Admin User Creation Command"
            echo "============================="
            echo ""
            echo "CREATE ADMIN USER:"
            echo "  ./milou.sh admin create [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --username USER       Admin username (default: admin)"
            echo "  --password PASSWORD   Admin password (default: auto-generate)"
            echo "  --email EMAIL         Admin email (default: admin@localhost)"
            echo "  --help, -h            Show this help"
            echo ""
            echo "Examples:"
            echo "  ./milou.sh admin create"
            echo "  ./milou.sh admin create --username admin --email admin@example.com"
            echo "  ./milou.sh admin create --password myPassword123"
            ;;
        "validate")
            echo "🔍 Admin Credentials Validation Command"
            echo "======================================"
            echo ""
            echo "VALIDATE CREDENTIALS:"
            echo "  ./milou.sh admin validate"
            echo ""
            echo "This command checks:"
            echo "  • Environment file exists"
            echo "  • Required admin variables are set"
            echo "  • Password strength"
            echo "  • Email format validation"
            echo "  • Configuration consistency"
            ;;
    esac
}

# Main admin command handler
handle_admin() {
    local subcommand="${1:-show}"
    shift || true
    
    case "$subcommand" in
        show|credentials)
            handle_admin_credentials "$@"
            ;;
        reset|reset-password)
            handle_admin_reset "$@"
            ;;
        create|create-user)
            handle_admin_create "$@"
            ;;
        validate)
            handle_admin_validate "$@"
            ;;
        --help|-h|help)
            _show_admin_help "main"
            ;;
        *)
            milou_log "ERROR" "Unknown admin subcommand: $subcommand"
            _show_admin_help "main"
            return 1
            ;;
    esac
}

# Show admin credentials command handler
handle_admin_credentials() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                _show_admin_help "credentials"
                return 0
                ;;
            *)
                milou_log "WARN" "Unknown admin credentials argument: $1"
                shift
                ;;
        esac
    done
    
    milou_admin_show_credentials
}

# Reset admin password command handler
handle_admin_reset() {
    local new_password=""
    local force=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --password)
                new_password="$2"
                shift 2
                ;;
            --force)
                force=true
                shift
                ;;
            --help|-h)
                _show_admin_help "reset"
                return 0
                ;;
            *)
                milou_log "WARN" "Unknown admin reset argument: $1"
                shift
                ;;
        esac
    done
    
    milou_admin_reset_password "$new_password" "$force"
}

# Create admin user command handler
handle_admin_create() {
    local username="admin"
    local password=""
    local email="admin@localhost"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --username|--user)
                username="$2"
                shift 2
                ;;
            --password)
                password="$2"
                shift 2
                ;;
            --email)
                email="$2"
                shift 2
                ;;
            --help|-h)
                _show_admin_help "create"
                return 0
                ;;
            *)
                milou_log "WARN" "Unknown admin create argument: $1"
                shift
                ;;
        esac
    done
    
    milou_admin_create_user "$username" "$password" "$email"
}

# Validate admin credentials command handler
handle_admin_validate() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                _show_admin_help "validate"
                return 0
                ;;
            *)
                milou_log "WARN" "Unknown admin validate argument: $1"
                shift
                ;;
        esac
    done
    
    milou_admin_validate_credentials
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

# Core admin functions (4 exports)
export -f milou_admin_show_credentials      # Display credentials
export -f milou_admin_reset_password        # Reset password
export -f milou_admin_create_user           # Create admin user
export -f milou_admin_validate_credentials  # Validate credentials

# Command handlers (5 exports)
export -f handle_admin                      # Main admin command handler
export -f handle_admin_credentials          # Credentials subcommand
export -f handle_admin_reset                # Reset subcommand
export -f handle_admin_create               # Create subcommand
export -f handle_admin_validate             # Validate subcommand

# Internal functions are NOT exported (marked with _ prefix)
# This keeps the namespace clean and makes it clear what's public vs internal

milou_log "DEBUG" "Admin management module loaded successfully" 