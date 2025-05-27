#!/bin/bash

# =============================================================================
# Setup Module: Mode Selection
# Extracted from monolithic handle_setup() function
# =============================================================================

# Ensure logging is available
if ! command -v milou_log >/dev/null 2>&1; then
    if [[ -n "${SCRIPT_DIR:-}" ]] && [[ -f "${SCRIPT_DIR}/lib/core/logging.sh" ]]; then
        source "${SCRIPT_DIR}/lib/core/logging.sh" 2>/dev/null || {
            echo "ERROR: Cannot load logging module" >&2
            exit 1
        }
    else
        echo "ERROR: milou_log function not available" >&2
        exit 1
    fi
fi

# =============================================================================
# Setup Mode Selection Functions
# =============================================================================

# Determine and configure setup mode
setup_select_mode() {
    local is_fresh_server="$1"
    local -n setup_mode_ref="$2"
    
    milou_log "STEP" "Step 3: Setup Mode Selection"
    echo
    
    # Default mode based on system state and command line arguments
    if [[ "${NON_INTERACTIVE:-false}" == "true" ]] || [[ "${INTERACTIVE:-true}" == "false" ]]; then
        setup_mode_ref="non-interactive"
        milou_log "INFO" "🤖 Non-interactive mode (forced by parameter)"
    elif [[ "$is_fresh_server" == "true" ]] && [[ $EUID -eq 0 ]]; then
        setup_mode_ref="interactive"
        milou_log "INFO" "👤 Interactive mode recommended for fresh server setup"
        
        if _prompt_mode_selection setup_mode_ref; then
            milou_log "SUCCESS" "Setup mode selected: $setup_mode_ref"
        else
            milou_log "WARN" "Using default interactive mode"
            setup_mode_ref="interactive"
        fi
    else
        setup_mode_ref="auto"
        milou_log "INFO" "🧠 Smart mode (automated with prompts when needed)"
    fi
    
    # Configure environment based on mode
    _configure_mode_environment "$setup_mode_ref"
    
    echo
    return 0
}

# Prompt user for mode selection
_prompt_mode_selection() {
    local -n mode_ref="$1"
    
    echo "Setup Mode Options:"
    echo "  1) Interactive    - Full guided setup with all options"
    echo "  2) Non-Interactive - Automated setup with defaults" 
    echo "  3) Smart          - Automated with prompts only when needed"
    echo
    
    local choice
    if command -v milou_prompt_user >/dev/null 2>&1; then
        milou_prompt_user "Select setup mode (1-3)" "1" "choice" "false" 3
        choice="$choice"
    else
        echo -n "Select setup mode (1-3) [1]: "
        read -r choice
        choice="${choice:-1}"
    fi
    
    case "$choice" in
        1) mode_ref="interactive" ;;
        2) mode_ref="non-interactive" ;;
        3) mode_ref="smart" ;;
        *) 
            milou_log "WARN" "Invalid selection: $choice"
            return 1
            ;;
    esac
    
    return 0
}

# Configure environment variables based on selected mode
_configure_mode_environment() {
    local mode="$1"
    
    case "$mode" in
        interactive)
            export INTERACTIVE=true
            export NON_INTERACTIVE=false
            export QUIET=false
            export FORCE=false
            milou_log "DEBUG" "Configured interactive mode environment"
            ;;
        non-interactive)
            export INTERACTIVE=false
            export NON_INTERACTIVE=true
            export QUIET=true
            export FORCE=true
            milou_log "DEBUG" "Configured non-interactive mode environment"
            ;;
        smart)
            export INTERACTIVE=false
            export NON_INTERACTIVE=false
            export QUIET=false
            export FORCE=false
            milou_log "DEBUG" "Configured smart mode environment"
            ;;
    esac
}

# Export functions
export -f setup_select_mode
export -f _prompt_mode_selection
export -f _configure_mode_environment 