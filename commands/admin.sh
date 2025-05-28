#!/bin/bash

# =============================================================================
# Milou CLI Admin Command Module
# Focused command handlers for admin operations
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Module guard to prevent multiple loading
if [[ "${MILOU_ADMIN_COMMANDS_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_ADMIN_COMMANDS_LOADED="true"

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
            echo "  • Configuration consistency"
            ;;
    esac
}

# Admin credentials command handler
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

# Show admin credentials
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
    
    milou_log "STEP" "🔑 Displaying admin credentials..."
    
    if command -v milou_admin_show_credentials >/dev/null 2>&1; then
        milou_admin_show_credentials
    else
        milou_log "ERROR" "Admin credentials module not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize admin modules"
        return 1
    fi
}

# Reset admin password
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
    
    milou_log "STEP" "🔄 Resetting admin password..."
    
    if command -v milou_admin_reset_password >/dev/null 2>&1; then
        milou_admin_reset_password "$new_password" "$force"
    else
        milou_log "ERROR" "Admin password reset module not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize admin modules"
        return 1
    fi
}

# Create admin user
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
    
    milou_log "STEP" "👤 Creating admin user..."
    
    if command -v milou_admin_create_user >/dev/null 2>&1; then
        milou_admin_create_user "$username" "$password" "$email"
    else
        milou_log "ERROR" "Admin user creation module not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize admin modules"
        return 1
    fi
}

# Validate admin credentials
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
    
    milou_log "STEP" "🔍 Validating admin credentials..."
    
    if command -v milou_admin_validate_credentials >/dev/null 2>&1; then
        milou_admin_validate_credentials
    else
        milou_log "ERROR" "Admin validation module not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize admin modules"
        return 1
    fi
}

# =============================================================================
# CLEAN PUBLIC API - Export only essential functions
# =============================================================================

# Main command handlers (5 exports - CLEAN PUBLIC API)
export -f handle_admin                  # Main admin command handler
export -f handle_admin_credentials      # Credentials subcommand
export -f handle_admin_reset            # Reset subcommand
export -f handle_admin_create           # Create subcommand
export -f handle_admin_validate         # Validate subcommand

# Internal functions are NOT exported (marked with _ prefix)
# This keeps the namespace clean and makes it clear what's public vs internal 