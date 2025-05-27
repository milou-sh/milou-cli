#!/bin/bash

# =============================================================================
# Setup Command Handler for Milou CLI
# Extracted from milou.sh to improve maintainability
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Setup command handler - Now uses modular approach
handle_setup() {
    # Load modular setup functionality
    local setup_main_file="${SCRIPT_DIR}/commands/setup/main.sh"
    
    if [[ -f "$setup_main_file" ]]; then
        source "$setup_main_file" || {
            if command -v milou_log >/dev/null 2>&1; then
                milou_log "ERROR" "Failed to load modular setup system"
            else
                echo "ERROR: Failed to load modular setup system" >&2
            fi
            return 1
        }
        
        # Use the modular setup function
        handle_setup_modular "$@"
    else
        if command -v milou_log >/dev/null 2>&1; then
            milou_log "ERROR" "Modular setup system not found: $setup_main_file"
            milou_log "INFO" "💡 Please ensure all setup modules are properly installed"
        else
            echo "ERROR: Modular setup system not found: $setup_main_file" >&2
            echo "INFO: Please ensure all setup modules are properly installed" >&2
        fi
        return 1
    fi
}

# Export the function for use in the main script
export -f handle_setup