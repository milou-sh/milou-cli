#!/bin/bash

# =============================================================================
# Command Loader for Milou CLI
# Handles loading all command handler modules
# =============================================================================

# Global variables for command tracking
declare -g -A MILOU_COMMANDS_LOADED=()
declare -g MILOU_COMMANDS_DIR=""

# Initialize command loader
milou_commands_init() {
    local script_dir="${1:-${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}}"
    MILOU_COMMANDS_DIR="${script_dir}/commands"
    
    if [[ ! -d "$MILOU_COMMANDS_DIR" ]]; then
        if command -v milou_log >/dev/null 2>&1; then
            milou_log "WARN" "Commands directory not found: $MILOU_COMMANDS_DIR"
        else
            echo "WARN: Commands directory not found: $MILOU_COMMANDS_DIR" >&2
        fi
        return 1
    fi
    
    # Load all command handlers
    milou_load_all_commands
    
    return 0
}

# Load a specific command handler
milou_load_command() {
    local command_name="$1"
    local force_reload="${2:-false}"
    
    # Check if already loaded
    if [[ "${MILOU_COMMANDS_LOADED[$command_name]:-}" == "true" ]] && [[ "$force_reload" != "true" ]]; then
        return 0
    fi
    
    local command_path="${MILOU_COMMANDS_DIR}/${command_name}.sh"
    
    if [[ ! -f "$command_path" ]]; then
        return 1
    fi
    
    # Source the command handler with safer approach
    if source "$command_path" 2>/dev/null; then
        MILOU_COMMANDS_LOADED[$command_name]="true"
        return 0
    else
        return 1
    fi
}

# Load all available command handlers
milou_load_all_commands() {
    if [[ ! -d "$MILOU_COMMANDS_DIR" ]]; then
        return 1
    fi
    
    # Use safer approach to prevent hangs
    local loaded_count=0
    local failed_commands=()
    
    # Use ls instead of globbing to avoid potential issues
    local command_files
    command_files=$(ls "$MILOU_COMMANDS_DIR"/*.sh 2>/dev/null) || return 0
    
    # Process each command file
    for command_file in $command_files; do
        # Skip if not a regular file
        [[ -f "$command_file" ]] || continue
        
        local command_name
        command_name=$(basename "$command_file" .sh)
        
        # Load command without extensive debug output to prevent hangs
        if milou_load_command "$command_name"; then
            ((loaded_count++))
        else
            failed_commands+=("$command_name")
        fi
    done
    
    # Only log results if logging is available
    if command -v milou_log >/dev/null 2>&1; then
        milou_log "DEBUG" "Loaded $loaded_count command handlers"
        if [[ ${#failed_commands[@]} -gt 0 ]]; then
            milou_log "WARN" "Failed to load command handlers: ${failed_commands[*]}"
        fi
    fi
    
    return 0
}

# Check if a command handler is loaded
milou_command_loaded() {
    local command_name="$1"
    [[ "${MILOU_COMMANDS_LOADED[$command_name]:-}" == "true" ]]
}

# List loaded command handlers
milou_list_loaded_commands() {
    if command -v milou_log >/dev/null 2>&1; then
        milou_log "INFO" "Loaded command handlers:"
        for command in "${!MILOU_COMMANDS_LOADED[@]}"; do
            if [[ "${MILOU_COMMANDS_LOADED[$command]}" == "true" ]]; then
                milou_log "INFO" "  ✓ $command"
            fi
        done
    else
        echo "Loaded command handlers:"
        for command in "${!MILOU_COMMANDS_LOADED[@]}"; do
            if [[ "${MILOU_COMMANDS_LOADED[$command]}" == "true" ]]; then
                echo "  ✓ $command"
            fi
        done
    fi
}

# Check if command handlers are available
milou_commands_available() {
    [[ -d "$MILOU_COMMANDS_DIR" ]] && [[ ${#MILOU_COMMANDS_LOADED[@]} -gt 0 ]]
}

# Export functions
export -f milou_commands_init milou_load_command milou_load_all_commands
export -f milou_command_loaded milou_list_loaded_commands milou_commands_available 