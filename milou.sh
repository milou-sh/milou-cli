#!/bin/bash

set -euo pipefail

# =============================================================================
# Milou CLI Wrapper Script
# Clean wrapper that delegates to the modular main entry point
# =============================================================================

readonly SCRIPT_VERSION="3.1.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MAIN_ENTRY_POINT="${SCRIPT_DIR}/src/milou"

# =============================================================================
# COMPATIBILITY AND MIGRATION
# =============================================================================

# Check if the new modular system exists
if [[ ! -f "$MAIN_ENTRY_POINT" ]]; then
    echo "ERROR: Modular entry point not found: $MAIN_ENTRY_POINT" >&2
    echo "This indicates an incomplete installation or update." >&2
    echo "Please run the setup process again." >&2
    exit 1
fi

# Make sure the main entry point is executable
if [[ ! -x "$MAIN_ENTRY_POINT" ]]; then
    chmod +x "$MAIN_ENTRY_POINT" 2>/dev/null || {
        echo "ERROR: Cannot make main entry point executable: $MAIN_ENTRY_POINT" >&2
        exit 1
    }
fi

# =============================================================================
# LEGACY COMMAND MAPPING
# =============================================================================

# Map legacy commands to new commands for backwards compatibility
map_legacy_commands() {
    case "${1:-}" in
        # Legacy setup commands
        "setup-wizard"|"configure")
            echo "setup"
            ;;
        # Legacy service commands
        "services-start")
            echo "start"
            ;;
        "services-stop")
            echo "stop"
            ;;
        "services-restart")
            echo "restart"
            ;;
        "services-status")
            echo "status"
            ;;
        # Legacy backup commands
        "backup-create")
            echo "backup"
            ;;
        "backup-restore")
            echo "restore"
            ;;
        # Legacy admin commands
        "admin-credentials")
            echo "admin credentials"
            ;;
        "admin-reset")
            echo "admin reset-password"
            ;;
        # Legacy update commands
        "update-system")
            echo "update"
            ;;
        "update-cli"|"self-update")
            echo "self-update"
            ;;
        # Legacy config commands
        "config-show")
            echo "config show"
            ;;
        "config-validate")
            echo "config validate"
            ;;
        # Pass through new commands unchanged
        "setup"|"status"|"start"|"stop"|"restart"|"logs"|"backup"|"restore"|"update"|"admin"|"config"|"health"|"shell"|"help"|"--help"|"-h"|"--version")
            echo "$1"
            ;;
        # Unknown command - let main entry point handle it
        *)
            echo "$1"
            ;;
    esac
}

# =============================================================================
# USER ENVIRONMENT SETUP
# =============================================================================

# Set up environment for the main entry point
setup_environment() {
    # Export script directory for modules
    export SCRIPT_DIR
    
    # Preserve important environment variables
    export MILOU_VERSION="$SCRIPT_VERSION"
    
    # Handle user-specific configuration
    local config_dir
    if [[ $EUID -eq 0 ]] && command -v getent >/dev/null 2>&1 && getent passwd milou >/dev/null 2>&1; then
        local milou_home
        milou_home=$(getent passwd milou | cut -d: -f6)
        config_dir="${milou_home}/.milou"
    else
        config_dir="${HOME}/.milou"
    fi
    
    export CONFIG_DIR="$config_dir"
    export ENV_FILE="${SCRIPT_DIR}/.env"
    export BACKUP_DIR="${config_dir}/backups"
    export LOG_FILE="${config_dir}/milou.log"
    
    # Create directories if needed
    mkdir -p "$config_dir" "$BACKUP_DIR" 2>/dev/null || true
    touch "$LOG_FILE" 2>/dev/null || true
    
    # Set ownership if running as root with milou user
    if [[ $EUID -eq 0 ]] && [[ "$config_dir" == */milou/.milou ]]; then
        chown -R milou:milou "$config_dir" 2>/dev/null || true
    fi
}

# =============================================================================
# MAIN DELEGATION
# =============================================================================

main() {
    # Set up environment
    setup_environment
    
    # Handle legacy command mapping
    local mapped_command=""
    if [[ $# -gt 0 ]]; then
        mapped_command=$(map_legacy_commands "$1")
        shift
        
        # Handle multi-word mapped commands
        if [[ "$mapped_command" == *" "* ]]; then
            # Split the mapped command and add remaining args
            set -- $mapped_command "$@"
        else
            # Single word command
            set -- "$mapped_command" "$@"
        fi
    fi
    
    # Show deprecation warning for legacy commands (but don't fail)
    if [[ -n "${mapped_command:-}" && "$mapped_command" != "${1:-}" ]]; then
        echo "NOTICE: Legacy command detected. Consider using the new syntax." >&2
        echo "  Old: $(basename "$0") ${1:-}" >&2
        echo "  New: $(basename "$0") $mapped_command" >&2
        echo >&2
    fi
    
    # Delegate to the main entry point
    exec "$MAIN_ENTRY_POINT" "$@"
}

# =============================================================================
# DIRECT EXECUTION CHECK
# =============================================================================

# Only run main if this script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 