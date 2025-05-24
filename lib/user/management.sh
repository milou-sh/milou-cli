#!/bin/bash

# =============================================================================
# User Management Orchestrator for Milou CLI
# Unified interface for all user management functionality
# =============================================================================

# Source utility functions
source "${BASH_SOURCE%/*}/utils.sh" 2>/dev/null || true

# Source all user management modules
source "${BASH_SOURCE%/*}/user-core.sh" 2>/dev/null || true
source "${BASH_SOURCE%/*}/user-docker.sh" 2>/dev/null || true
source "${BASH_SOURCE%/*}/user-environment.sh" 2>/dev/null || true
source "${BASH_SOURCE%/*}/user-switching.sh" 2>/dev/null || true
source "${BASH_SOURCE%/*}/user-security.sh" 2>/dev/null || true
source "${BASH_SOURCE%/*}/user-interface.sh" 2>/dev/null || true

# =============================================================================
# Main User Management Interface
# =============================================================================

# Main user management function dispatcher
user_management_main() {
    local command="${1:-status}"
    shift
    
    case "$command" in
        "status"|"user-status")
            show_user_status
            ;;
        "create"|"create-user")
            create_user_command
            ;;
        "test"|"test-user")
            test_user_command
            ;;
        "migrate"|"migrate-user")
            migrate_user_command
            ;;
        "switch"|"switch-user")
            switch_to_milou_user "$@"
            ;;
        "setup"|"interactive-setup")
            interactive_user_setup "$@"
            ;;
        "security-check"|"security")
            security_assessment
            ;;
        "security-harden"|"harden")
            harden_milou_user
            ;;
        "diagnose-docker")
            local target_user="${1:-$(whoami)}"
            diagnose_docker_access "$target_user"
            ;;
        "validate-environment"|"validate")
            validate_milou_user_environment
            ;;
        "fix-docker"|"fix-docker-permissions")
            fix_docker_permissions
            ;;
        "ensure-setup")
            ensure_proper_user_setup "$@"
            ;;
        "help"|"--help"|"-h")
            show_user_management_help
            ;;
        *)
            log "ERROR" "Unknown user management command: $command"
            show_user_management_help
            return 1
            ;;
    esac
}

# Show help for user management commands
show_user_management_help() {
    echo -e "${BOLD}User Management Commands:${NC}"
    echo "========================="
    echo
    echo -e "${CYAN}Status and Information:${NC}"
    echo "  status, user-status          Show detailed user status information"
    echo "  validate, validate-environment  Validate milou user environment"
    echo "  diagnose-docker [user]       Diagnose Docker access issues"
    echo
    echo -e "${CYAN}User Creation and Setup:${NC}"
    echo "  create, create-user          Create the milou user"
    echo "  setup, interactive-setup     Interactive user setup wizard"
    echo "  migrate, migrate-user        Migrate existing installation to milou user"
    echo "  test, test-user              Test user setup and functionality"
    echo
    echo -e "${CYAN}User Switching:${NC}"
    echo "  switch, switch-user          Switch to milou user for operations"
    echo "  ensure-setup                 Ensure proper user setup (auto-switch if needed)"
    echo
    echo -e "${CYAN}Security:${NC}"
    echo "  security-check, security     Comprehensive security assessment"
    echo "  security-harden, harden      Apply security hardening measures"
    echo
    echo -e "${CYAN}Docker Management:${NC}"
    echo "  fix-docker, fix-docker-permissions  Fix Docker permissions for milou user"
    echo
    echo -e "${CYAN}General:${NC}"
    echo "  help, --help, -h             Show this help message"
    echo
    echo -e "${YELLOW}Examples:${NC}"
    echo "  $0 user-management status"
    echo "  sudo $0 user-management create"
    echo "  sudo $0 user-management migrate"
    echo "  $0 user-management security-check"
    echo "  $0 user-management diagnose-docker milou"
}

# =============================================================================
# Cleanup and Utilities
# =============================================================================

# Clean up user management resources
cleanup_user_management() {
    log "DEBUG" "Cleaning up user management resources..."
    
    # Clean up temporary files
    local -a temp_patterns=(
        "/tmp/milou_user_*"
        "/tmp/milou_setup_*"
    )
    
    for pattern in "${temp_patterns[@]}"; do
        if compgen -G "$pattern" >/dev/null 2>&1; then
            rm -f $pattern 2>/dev/null || true
        fi
    done
    
    # Clean up security resources
    cleanup_security_resources 2>/dev/null || true
}

# =============================================================================
# Backward Compatibility
# =============================================================================

# Maintain backward compatibility with existing function calls
# These functions are exported for use in other scripts

# Export all core functions for backward compatibility
export -f is_running_as_root
export -f milou_user_exists
export -f get_current_user_info
export -f create_milou_user
export -f get_milou_home
export -f validate_milou_home

# Export Docker functions
export -f has_docker_permissions
export -f fix_docker_permissions
export -f copy_docker_credentials_to_milou
export -f diagnose_docker_access

# Export environment functions
export -f setup_milou_user_environment
export -f validate_milou_user_environment
export -f test_milou_user_cli

# Export switching functions
export -f switch_to_milou_user
export -f migrate_to_milou_user
export -f ensure_proper_user_setup

# Export security functions
export -f validate_user_permissions
export -f harden_milou_user
export -f security_assessment
export -f quick_security_check

# Export interface functions
export -f interactive_user_setup
export -f show_user_status

# Export main functions
export -f user_management_main
export -f cleanup_user_management

# =============================================================================
# Module Information
# =============================================================================

# Show module information
show_user_management_info() {
    echo -e "${BOLD}User Management Module Information:${NC}"
    echo "=================================="
    echo
    echo "This module provides comprehensive user management for Milou CLI:"
    echo
    echo -e "${CYAN}Core Modules:${NC}"
    echo "  • user-core.sh         - Basic user operations and creation"
    echo "  • user-docker.sh       - Docker permissions and diagnostics"
    echo "  • user-environment.sh  - Environment setup and validation"
    echo "  • user-switching.sh    - User switching and migration"
    echo "  • user-security.sh     - Security validation and hardening"
    echo "  • user-interface.sh    - Interactive setup and status display"
    echo
    echo -e "${CYAN}Key Features:${NC}"
    echo "  • Secure user creation and management"
    echo "  • Docker permissions handling"
    echo "  • Environment configuration"
    echo "  • Security assessment and hardening"
    echo "  • Interactive setup wizards"
    echo "  • Comprehensive status reporting"
    echo
    echo -e "${CYAN}Security Best Practices:${NC}"
    echo "  • Dedicated non-root user for operations"
    echo "  • Proper file permissions and ownership"
    echo "  • Docker group management"
    echo "  • Configuration security validation"
    echo
}

# If script is run directly, execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    user_management_main "$@"
fi 