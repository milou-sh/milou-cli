#!/bin/bash

# =============================================================================
# Setup Command Handler for Milou CLI
# FIXED: Now properly integrates with working modular setup system
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# =============================================================================
# FIXED: Setup command handler using working modular system
# =============================================================================

handle_setup() {
    # Modules are loaded centrally by milou_load_command_modules() in main script
    
    # Load the working modular setup system
    local setup_main_file="${SCRIPT_DIR}/commands/setup/main.sh"
    
    if [[ ! -f "$setup_main_file" ]]; then
        log "ERROR" "Modular setup system not found: $setup_main_file"
        log "ERROR" "The setup system appears to be incomplete"
        return 1
    fi
    
    # Source the modular setup system
    if ! source "$setup_main_file"; then
        log "ERROR" "Failed to load modular setup system"
        return 1
    fi
    
    # Verify the modular function is available
    if ! command -v handle_setup_modular >/dev/null 2>&1; then
        log "ERROR" "Modular setup function not available after loading"
        return 1
    fi
    
    # Call the working modular setup system
    log "INFO" "🔧 Using modular setup system..."
    handle_setup_modular "$@"
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        log "SUCCESS" "✅ Setup completed successfully using modular system"
    else
        log "ERROR" "❌ Setup failed with exit code: $exit_code"
    fi
    
    return $exit_code
}

# Export the function for use in the main script
export -f handle_setup 