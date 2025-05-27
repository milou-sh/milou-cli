#!/bin/bash

# =============================================================================
# Simplified Module Loader for Milou CLI
# Provides essential module loading functionality without redundancy
# =============================================================================

# Global variables
declare -A MILOU_MODULES_LOADED

# Initialize module loading system
milou_modules_init() {
    local script_dir="${1:-${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}}"
    
    # Check if module loader is already initialized
    if [[ "${MILOU_MODULE_LOADER_INITIALIZED:-}" == "true" ]]; then
        return 0
    fi
    
    readonly MILOU_MODULE_LOADER_INITIALIZED="true"
    
    # Set library directory
    MILOU_LIB_DIR="${script_dir}/lib"
    export MILOU_LIB_DIR
    
    if [[ ! -d "$MILOU_LIB_DIR" ]]; then
        echo "ERROR: Module library directory not found: $MILOU_LIB_DIR" >&2
        return 1
    fi
    
    # Always load core logging first
    milou_load_module "core/logging"
    
    return 0
}

# Load a specific module
milou_load_module() {
    local module_name="$1"
    local force_reload="${2:-false}"
    
    # Check if already loaded
    if [[ "${MILOU_MODULES_LOADED[$module_name]:-}" == "true" ]] && [[ "$force_reload" != "true" ]]; then
        return 0
    fi
    
    local module_path="${MILOU_LIB_DIR}/${module_name}.sh"
    
    if [[ ! -f "$module_path" ]]; then
        echo "ERROR: Module not found: $module_path" >&2
        return 1
    fi
    
    # Source the module with error handling for readonly variables
    if source "$module_path" 2>/dev/null; then
        MILOU_MODULES_LOADED[$module_name]="true"
        
        # Initialize logging if available
        if command -v milou_log >/dev/null 2>&1; then
            milou_log "DEBUG" "Loaded module: $module_name"
        fi
        
        return 0
    else
        # Try again with stderr captured to handle readonly variable warnings
        local stderr_output
        stderr_output=$(source "$module_path" 2>&1)
        local exit_code=$?
        
        # If it's just readonly variable warnings, consider it successful
        if [[ $exit_code -ne 0 ]] && echo "$stderr_output" | grep -q "readonly variable"; then
            MILOU_MODULES_LOADED[$module_name]="true"
            if command -v milou_log >/dev/null 2>&1; then
                milou_log "DEBUG" "Loaded module: $module_name (with readonly variable warnings)"
            fi
            return 0
        else
            echo "ERROR: Failed to load module: $module_path" >&2
            if [[ -n "$stderr_output" ]]; then
                echo "Error details: $stderr_output" >&2
            fi
            return 1
        fi
    fi
}

# Load multiple modules
milou_load_modules() {
    local -a modules=("$@")
    local failed_modules=()
    
    for module in "${modules[@]}"; do
        if ! milou_load_module "$module"; then
            failed_modules+=("$module")
        fi
    done
    
    if [[ ${#failed_modules[@]} -gt 0 ]]; then
        echo "ERROR: Failed to load modules: ${failed_modules[*]}" >&2
        return 1
    fi
    
    return 0
}

# Check if a module is loaded
milou_module_loaded() {
    local module_name="$1"
    [[ "${MILOU_MODULES_LOADED[$module_name]:-}" == "true" ]]
}

# Load essential modules for Milou CLI
milou_load_essentials() {
    # Load in dependency order
    local -a essential_modules=(
        "core/logging"        # Must be first
        "core/validation"     # Validation functions
        "core/user-interface" # UI functions
        "core/utilities"      # Core utility functions
        "docker/compose"      # Docker operations
        "core/command-loader" # Command loading system
    )
    
    milou_load_modules "${essential_modules[@]}"
    
    # Initialize command loader but don't load commands yet (on-demand loading)
    if command -v milou_commands_init >/dev/null 2>&1; then
        MILOU_COMMANDS_DIR="${MILOU_LIB_DIR}/../commands"
        export MILOU_COMMANDS_DIR
    fi
}

# Load modules for specific commands (centralized command-specific loading)
milou_load_command_modules() {
    local command="$1"
    
    # Define module groups
    local -a system_modules=(
        "config/core" "config/validation" "config/migration"
        "ssl/core" "ssl/generation" "ssl/interactive"
        "prerequisites" "system" "security"
    )
    
    local -a docker_modules=(
        "docker/core" "docker/registry" "docker/uninstall" "docker/health"
    )
    
    local -a user_modules=(
        "user/core" "user/management" "user/switching" "user/environment"
        "user/security" "user/docker" "user/interface"
    )
    
    case "$command" in
        setup)
            milou_load_modules "${user_modules[@]}" "${system_modules[@]}" "${docker_modules[@]}"
            ;;
        start|stop|restart|status|detailed-status|logs|health|health-check|shell|debug-images)
            milou_load_modules "${docker_modules[@]}" "${system_modules[@]}"
            ;;
        config|validate|backup|restore|update|ssl|cleanup|uninstall|cleanup-test-files|install-deps|diagnose|admin)
            milou_load_modules "${system_modules[@]}" "${docker_modules[@]}"
            ;;
        user-status|create-user|migrate-user|security-check|security-harden|security-report)
            milou_load_modules "${user_modules[@]}" "${system_modules[@]}"
            ;;
        *)
            # For unknown commands, load essentials only
            if command -v milou_log >/dev/null 2>&1; then
                milou_log "DEBUG" "Unknown command '$command', loading essential modules only"
            fi
            ;;
    esac
}

# Export core functions only
export -f milou_modules_init milou_load_module milou_load_modules
export -f milou_module_loaded milou_load_essentials milou_load_command_modules 