#!/bin/bash

# =============================================================================
# Milou CLI - Setup Management Module
# Consolidated setup operations to eliminate massive code duplication
# Version: 4.0.0 - Refactored for Correctness and Clarity
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Module guard to prevent multiple loading
if [[ "${MILOU_SETUP_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_SETUP_LOADED="true"

# Ensure core modules are loaded
if [[ -z "${MILOU_CORE_MODULE_LOADED:-}" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # Load required modules. Use a guard to prevent re-sourcing if they are already loaded.
    source "${script_dir}/_core.sh"
    source "${script_dir}/_validation.sh"
    source "${script_dir}/_config.sh"
    source "${script_dir}/_docker.sh"
    source "${script_dir}/_ssl.sh"
fi

# ============================================================================
# MAIN SETUP ENTRY POINT
# ============================================================================

# handle_setup is the primary entry point called by `milou.sh setup`
handle_setup() {
    local force="false"
    local clean="false"
    local github_token=""
    local mode="interactive" # Default to interactive setup

    # Parse command line options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f) force="true"; shift ;;
            --clean) clean="true"; shift ;;
            --token) github_token="$2"; shift 2 ;;
            --repair) mode="repair"; shift ;;
            --help|-h) show_setup_help; return 0 ;;
            *) milou_log "WARN" "Unknown setup option: $1"; shift ;;
        esac
    done

    # Set GitHub token if provided via command line
    if [[ -n "$github_token" ]]; then
        export GITHUB_TOKEN="$github_token"
        milou_log "INFO" "✓ GitHub token provided via command line"
    fi

    # Handle clean install first if requested
    if [[ "$clean" == "true" ]]; then
        if ! _setup_clean_installation; then
            return 1
        fi
    fi
    
    # Run the main setup orchestrator
    if ! _setup_orchestrator "$mode" "$force"; then
         milou_log "ERROR" "Milou setup failed. Please check the logs above for details."
         return 1
    fi
    
    milou_log "SUCCESS" "🎉 Milou setup completed successfully! 🎉"
    echo
    return 0
}

# ============================================================================
# SETUP ORCHESTRATOR
# This function controls the main flow of the setup process.
# ============================================================================

_setup_orchestrator() {
    local mode="$1"
    local force="$2"

    _setup_show_logo

    # STEP 1: System Validation (Docker, etc.)
    if ! _setup_validate_system; then return 1; fi

    # STEP 2: Interactive Configuration (domain, email, ssl, version)
    # This function will set global variables with user choices.
    if ! _setup_run_interactive_configuration; then
        log_error "Configuration was cancelled or failed."
        return 1
    fi
    
    # THE CRITICAL FIX IS HERE:
    # We now have the user's version choice. If they chose a dynamic version
    # like 'stable' or 'latest', we MUST get the GitHub token now, *before*
    # we generate the configuration file.

    # STEP 3: Acquire GitHub Token (if needed)
    if [[ "$USE_LATEST_IMAGES" == "true" ]]; then
        log_step "🔑" "GitHub Token Required"
        milou_log "INFO" "A GitHub token is needed to find the specific version number for 'latest stable'."
        if ! core_require_github_token "${GITHUB_TOKEN:-}" "true"; then
            log_error "A valid GitHub token is required to proceed."
            return 1
        fi
        # The token is now available in the environment via GITHUB_TOKEN export in core_require_github_token
    fi

    # STEP 4: Generate .env Configuration File
    # Now that the token is present (if it was needed), we can generate the config.
    # config_generate will use the token to resolve 'latest' to a real version.
    log_step "⚙️" "Generating Configuration File"
    if ! config_generate "$DOMAIN_CHOICE" "$EMAIL_CHOICE" "$SSL_MODE_CHOICE" "$USE_LATEST_IMAGES" "false" "false"; then
        log_error "Failed to generate the .env configuration file."
        return 1
    fi
    milou_log "SUCCESS" "Configuration file '.env' created successfully."

    # STEP 5: SSL Certificate Setup
    log_step "🛡️" "Setting Up SSL Certificates"
    if ! ssl_setup_certificates "$SSL_MODE_CHOICE" "$DOMAIN_CHOICE"; then
        log_error "Failed to configure SSL certificates."
        return 1
    fi

    # STEP 6: Final Docker Deployment (Pull & Start)
    log_step "🚀" "Deploying Milou Services"
    if ! service_start_with_validation "" "120" "false"; then
        log_error "Failed to start Milou services."
        docker_handle_startup_error # Provide detailed troubleshooting
        return 1
    fi
    
    # STEP 7: Display Completion Summary
    _setup_display_completion_report
    
    return 0
}


# ============================================================================
# HELPER FUNCTIONS FOR ORCHESTRATOR
# ============================================================================

# Displays the welcome logo
_setup_show_logo() {
    if tty -s && [[ "${QUIET:-false}" != "true" ]]; then
        echo -e "${BOLD}${PURPLE}"
        cat << 'EOF'

    ███╗   ███╗██╗██╗      ██████╗ ██╗   ██╗
    ████╗ ████║██║██║     ██╔═══██╗██║   ██║  
    ██╔████╔██║██║██║     ██║   ██║██║   ██║  
    ██║╚██╔╝██║██║██║     ██║   ██║██║   ██║  
    ██║ ╚═╝ ██║██║███████╗╚██████╔╝╚██████╔╝  
    ╚═╝     ╚═╝╚═╝╚══════╝ ╚═════╝  ╚═════╝   
    
    ┌─────────────────────────────────────────┐
    │   🚀 Professional Docker Management     │
    │   Simple • Secure • Reliable           │
    └─────────────────────────────────────────┘

EOF
        echo -e "${NC}"
        log_welcome "Let's get your Milou environment set up quickly and easily!"
    fi
}

# Validates that Docker is installed and running
_setup_validate_system() {
    log_step "🔍" "System Validation"
    if ! validate_system_dependencies "docker" "unknown" "true"; then
        log_error "System validation failed. Please ensure Docker is installed and running."
        return 1
    fi
    log_success "System validation passed."
    return 0
}

# Runs the interactive portion of the setup wizard
_setup_run_interactive_configuration() {
    log_step "⚙️" "Interactive Configuration"

    # These prompts will set the global vars needed by the orchestrator
    DOMAIN_CHOICE=$(_prompt_for_domain) || return 1
    EMAIL_CHOICE=$(_prompt_for_email "${DOMAIN_CHOICE}") || return 1
    SSL_MODE_CHOICE=$(_prompt_for_ssl) || return 1
    
    local version_tag
    version_tag=$(_prompt_for_version) || return 1
    
    # Set global flags based on version choice
    if [[ "$version_tag" == "latest" || "$version_tag" == "stable" ]]; then
        USE_LATEST_IMAGES="true"
    else
        USE_LATEST_IMAGES="false"
    fi
    export MILOU_SELECTED_VERSION="$version_tag"
    
    _setup_show_summary "$DOMAIN_CHOICE" "$EMAIL_CHOICE" "$SSL_MODE_CHOICE" "$version_tag"
    return 0
}


# Helper for Domain Prompt
_prompt_for_domain() {
    local domain
    log_section "✓ Domain Configuration" "Where will your Milou system be accessible?"
    domain=$(prompt_user "Domain name" "localhost" "domain")
    echo "$domain"
}

# Helper for Email Prompt
_prompt_for_email() {
    local domain="$1"
    local email
    log_section "✓ Admin Contact Email" "Your administrator email address for SSL certs."
    email=$(prompt_user "Admin email" "admin@$domain" "email")
    echo "$email"
}

# Helper for SSL Prompt
_prompt_for_ssl() {
    log_section "✓ Security & SSL Setup" "How to secure your connection"
    echo -e "${BOLD}${CYAN}Choose your security level:${NC}"
    echo -e "   1) Quick & Easy (Self-signed - recommended for testing)"
    echo -e "   2) Production Ready (Bring your own existing certificates)"
    echo -e "   3) No Encryption (HTTP only - not recommended)"
    
    local ssl_choice
    ssl_choice=$(prompt_user "Choose security option [1-3]" "1")
    
    case "$ssl_choice" in
        1) echo "generate" ;;
        2) echo "existing" ;;
        3) echo "none" ;;
        *) echo "generate" ;;
    esac
}

# Helper for Version Prompt
_prompt_for_version() {
    log_section "✓ Version Selection" "Choose your Milou version"
    echo -e "${BOLD}${CYAN}Available options:${NC}"
    echo -e "   1) Latest Stable (Recommended for production)"
    echo -e "   2) Latest Development (Beta features)"
    echo -e "   3) Specific Version (Advanced users)"

    local version_choice
    version_choice=$(prompt_user "Choose version option [1-3]" "1")

    case "$version_choice" in
        1) echo "stable" ;;
        2) echo "latest" ;;
        3) prompt_user "Enter the exact version tag (e.g., 1.2.3)" ;;
        *) echo "stable" ;;
    esac
}

# Displays a summary of the user's choices before proceeding
_setup_show_summary() {
    local domain="$1" email="$2" ssl_mode="$3" version="$4"
    echo
    milou_log "HEADER" "Configuration Summary"
    echo -e "   ${BOLD}Domain:${NC}        ${CYAN}$domain${NC}"
    echo -e "   ${BOLD}Admin Email:${NC}   ${CYAN}$email${NC}"
    echo -e "   ${BOLD}SSL Security:${NC}  ${CYAN}$ssl_mode${NC}"
    echo -e "   ${BOLD}Milou Version:${NC} ${CYAN}$version${NC}"
    echo
    if ! confirm "Proceed with this configuration?" "Y"; then
        return 1
    fi
}

# Handles the --clean option
_setup_clean_installation() {
    log_step "🧹" "Clean Installation"
    milou_log "WARN" "This will PERMANENTLY DELETE all Milou data, containers, and configurations."
    if ! confirm "Are you ABSOLUTELY SURE you want to delete ALL data?" "N"; then
        milou_log "INFO" "Clean install cancelled."
        return 1
    fi

    milou_log "INFO" "Stopping and removing all Milou services and networks..."
    docker_cleanup_environment "full" # "full" removes data volumes

    milou_log "INFO" "Deleting configuration files and SSL certificates..."
    rm -f "${SCRIPT_DIR:-$(pwd)}/.env"*
    rm -rf "${SCRIPT_DIR:-$(pwd)}/ssl"
    
    milou_log "SUCCESS" "System cleaned. Ready for a fresh installation."
    return 0
}

# Displays the final success message with credentials
_setup_display_completion_report() {
    # Load the freshly generated .env file to get credentials
    if [[ -f "${SCRIPT_DIR:-$(pwd)}/.env" ]]; then
        # Sanitize before sourcing
        awk '/^[[:space:]]*$/ || /^[[:space:]]*#/ || /^[A-Za-z_][A-Za-z0-9_]*=.*/' "${SCRIPT_DIR}/.env" > "${SCRIPT_DIR}/.env.tmp" && mv "${SCRIPT_DIR}/.env.tmp" "${SCRIPT_DIR}/.env"
        set -a
        source "${SCRIPT_DIR:-$(pwd)}/.env"
        set +a
    fi

    local domain="${DOMAIN:-localhost}"
    local admin_user="${ADMIN_USERNAME:-admin}"
    local admin_password="${ADMIN_PASSWORD:-[check .env file]}"
    
    echo
    milou_log "HEADER" "✓ Setup Complete! Welcome to Milou"
    
    log_section "✓ Access Your System" "Your Milou installation is now accessible"
    echo -e "   ${BOLD}Web Interface:${NC} ${CYAN}https://$domain${NC}"
    echo
    
    log_section "✓ Your Admin Credentials" "Keep these credentials safe!"
    echo -e "   ${BOLD}Username:${NC} $admin_user"
    echo -e "   ${BOLD}Password:${NC} $admin_password"
    echo
    
    log_next_steps \
        "Open ${CYAN}https://$domain${NC} in your browser" \
        "Log in with the credentials above" \
        "Create a backup: ${CYAN}./milou.sh backup${NC}"
}

# Displays the help message for the setup command
show_setup_help() {
    echo "✓ Milou CLI Setup Command"
    echo "=========================="
    echo ""
    echo "USAGE:"
    echo "  ./milou.sh setup [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  --token TOKEN          Provide a GitHub Personal Access Token non-interactively."
    echo "  --clean                DELETES all existing Milou data and configuration before starting."
    echo "  --force, -f            Bypasses confirmation prompts. DANGEROUS with --clean."
    echo "  --repair               (Coming soon) Interactively repair a broken installation."
    echo "  --help, -h             Show this help message."
    echo ""
    echo "EXAMPLE:"
    echo "  ./milou.sh setup       # Start the interactive setup wizard."
    echo "  ./milou.sh setup --clean --force # Unattended full wipe and fresh install."
}

# Export the main entry point
export -f handle_setup
milou_log "DEBUG" "Setup module loaded successfully"