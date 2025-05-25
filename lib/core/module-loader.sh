#!/bin/bash

# =============================================================================
# Module Loader for Milou CLI
# Handles sourcing modules in the right order with dependency management
# =============================================================================

# Global variables for module tracking
declare -g -A MILOU_MODULES_LOADED=()
declare -g MILOU_LIB_DIR=""

# Initialize module loader
milou_modules_init() {
    local script_dir="${1:-${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}}"
    MILOU_LIB_DIR="${script_dir}/lib"
    
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
    
    # Source the module
    if source "$module_path"; then
        MILOU_MODULES_LOADED[$module_name]="true"
        
        # Initialize logging if available
        if command -v milou_log >/dev/null 2>&1; then
            milou_log "DEBUG" "Loaded module: $module_name"
        fi
        
        return 0
    else
        echo "ERROR: Failed to load module: $module_path" >&2
        return 1
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

# Load all modules in a category
milou_load_category() {
    local category="$1"
    local category_dir="${MILOU_LIB_DIR}/${category}"
    
    if [[ ! -d "$category_dir" ]]; then
        echo "ERROR: Module category directory not found: $category_dir" >&2
        return 1
    fi
    
    local -a modules=()
    while IFS= read -r -d '' module_file; do
        local module_name="${module_file#$MILOU_LIB_DIR/}"
        module_name="${module_name%.sh}"
        modules+=("$module_name")
    done < <(find "$category_dir" -name "*.sh" -type f -print0)
    
    if [[ ${#modules[@]} -gt 0 ]]; then
        milou_load_modules "${modules[@]}"
    else
        if command -v milou_log >/dev/null 2>&1; then
            milou_log "DEBUG" "No modules found in category: $category"
        fi
    fi
}

# Check if a module is loaded
milou_module_loaded() {
    local module_name="$1"
    [[ "${MILOU_MODULES_LOADED[$module_name]:-}" == "true" ]]
}

# List loaded modules
milou_list_loaded_modules() {
    if command -v milou_log >/dev/null 2>&1; then
        milou_log "INFO" "Loaded modules:"
        for module in "${!MILOU_MODULES_LOADED[@]}"; do
            if [[ "${MILOU_MODULES_LOADED[$module]}" == "true" ]]; then
                milou_log "INFO" "  ✓ $module"
            fi
        done
    else
        echo "Loaded modules:"
        for module in "${!MILOU_MODULES_LOADED[@]}"; do
            if [[ "${MILOU_MODULES_LOADED[$module]}" == "true" ]]; then
                echo "  ✓ $module"
            fi
        done
    fi
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

# Load all system modules
milou_load_system_modules() {
    local -a system_modules=(
        "system/configuration"  # Configuration management
        "system/ssl"           # SSL certificate management
        "system/prerequisites" # System prerequisites
        "system/security"      # System security
        "system/backup"        # Backup operations
        "system/environment"   # Environment management
        "system/update"        # Update functions
        "system/setup"         # Setup wizard
    )
    
    milou_load_modules "${system_modules[@]}"
}

# Load all docker modules
milou_load_docker_modules() {
    local -a docker_modules=(
        "docker/compose"       # Docker Compose operations (already loaded in essentials)
        "docker/core"          # Core Docker functions
        "docker/registry"      # Docker registry operations
    )
    
    milou_load_modules "${docker_modules[@]}"
}

# Load all user modules
milou_load_user_modules() {
    local -a user_modules=(
        "user/core"            # Core user functions
        "user/management"      # User management
        "user/switching"       # User switching logic
        "user/environment"     # User environment setup
        "user/security"        # User security functions
        "user/docker"          # User Docker permissions
        "user/interface"       # User interface functions
    )
    
    milou_load_modules "${user_modules[@]}"
}

# Load all modules (comprehensive loading)
milou_load_all_modules() {
    milou_load_essentials
    milou_load_system_modules
    milou_load_docker_modules
    milou_load_user_modules
}

# Load modules for specific commands (centralized command-specific loading)
milou_load_command_modules() {
    local command="$1"
    
    case "$command" in
        setup)
            milou_load_user_modules
            milou_load_system_modules
            milou_load_docker_modules
            ;;
        start|stop|restart|status|detailed-status|logs|health|health-check|shell|debug-images)
            milou_load_docker_modules
            milou_load_system_modules
            ;;
        config|validate|backup|restore|update|ssl|cleanup|cleanup-test-files|install-deps|diagnose)
            milou_load_system_modules
            milou_load_docker_modules
            ;;
        user-status|create-user|migrate-user|security-check|security-harden|security-report)
            milou_load_user_modules
            milou_load_system_modules
            ;;
        *)
            # For unknown commands, load essentials only
            if command -v milou_log >/dev/null 2>&1; then
                milou_log "DEBUG" "Unknown command '$command', loading essential modules only"
            fi
            ;;
    esac
}

# Export functions
export -f milou_modules_init milou_load_module milou_load_modules
export -f milou_load_category milou_module_loaded milou_list_loaded_modules
export -f milou_load_essentials milou_load_system_modules milou_load_docker_modules
export -f milou_load_user_modules milou_load_all_modules milou_load_command_modules 