#!/bin/bash

# =============================================================================
# Milou CLI - Setup Management Module
# Consolidated setup operations to eliminate massive code duplication
# Version: 1.0.0 - Refactored Edition
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
if [[ "${MILOU_CORE_LOADED:-}" != "true" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/_core.sh" || {
        echo "ERROR: Cannot load core module" >&2
        return 1
    }
fi

if [[ "${MILOU_VALIDATION_LOADED:-}" != "true" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/_validation.sh" || {
        echo "ERROR: Cannot load validation module" >&2
        return 1
    }
fi

if [[ "${MILOU_CONFIG_LOADED:-}" != "true" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/_config.sh" || {
        echo "ERROR: Cannot load config module" >&2
        return 1
    }
fi

if [[ "${MILOU_DOCKER_LOADED:-}" != "true" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/_docker.sh" || {
        echo "ERROR: Cannot load docker module" >&2
        return 1
    }
fi

if [[ "${MILOU_UPDATE_LOADED:-}" != "true" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${script_dir}/_update.sh" || {
        echo "ERROR: Cannot load update module" >&2
        return 1
    }
fi

# ============================================================================
# HELPER: Sanitize .env file to remove invalid lines before sourcing
# ============================================================================
sanitize_env_file() {
    local target_file="$1"
    [[ -f "$target_file" ]] || return 0
    local tmp_file="${target_file}.sanitized.$$"
    awk '/^[[:space:]]*$/ || /^[[:space:]]*#/ || /^[A-Za-z_][A-Za-z0-9_]*=.*/ {print}' "$target_file" > "$tmp_file"
    mv "$tmp_file" "$target_file"
}

# =============================================================================
# SETUP CONSTANTS AND DEFAULTS
# =============================================================================

# Setup mode constants
declare -g SETUP_MODE_INTERACTIVE="interactive"
declare -g SETUP_MODE_AUTOMATED="automated"
declare -g SETUP_MODE_SMART="smart"

# Setup state variables
declare -g SETUP_IS_FRESH_SERVER="false"
declare -g SETUP_NEEDS_DEPS="false"
declare -g SETUP_NEEDS_USER="false"
declare -g SETUP_CURRENT_MODE="$SETUP_MODE_INTERACTIVE"

# =============================================================================
# ENHANCED LOGO AND BRANDING FUNCTIONS  
# Version: 3.1.1 - Enhanced User Experience Edition
# =============================================================================

# Professional Milou logo with consistent design
setup_show_logo() {
    # If called from install.sh, skip showing logo again.
    if [[ "${MILOU_INSTALLER_RUN:-}" == "true" ]]; then
        return 0
    fi

    if tty -s && [[ "${QUIET:-false}" != "true" ]]; then
        echo -e "${BOLD}${PURPLE}"
        cat << 'EOF'

    ███╗   ███╗██╗██╗      ██████╗ ██╗   ██╗
    ████╗ ████║██║██║     ██╔═══██╗██║   ██║  
    ██╔████╔██║██║██║     ██║   ██║██║   ██║  
    ██║╚██╔╝██║██║██║     ██║   ██║██║   ██║  
    ██║ ╚═╝ ██║██║███████╗╚██████╔╝╚██████╔╝  
    ╚═╝     ╚═╝╚═╝╚══════╝ ╚═════╝  ╚═════╝   
    
EOF
        echo -e "${NC}"
        log_header "The tool for the lazy - v$VERSION"
        log_info "Welcome to the Milou setup wizard. Let's get your environment configured."
        echo
    fi
}

# Enhanced setup header with progress indication
setup_show_header() {
    local current_step="${1:-1}"
    local total_steps="${2:-7}"
    local step_name="${3:-Starting Setup}"
    
    if tty -s && [[ "${QUIET:-false}" != "true" ]]; then
        log_progress "$current_step" "$total_steps" "$step_name"
    fi
}

# User-friendly step announcements
setup_announce_step() {
    local step_number="$1"
    local step_title="$2"
    local step_description="${3:-}"
    
    log_step "$step_number: $step_title"
    if [[ -n "$step_description" ]]; then
        echo -e "${DIM}  ${step_description}${NC}"
    fi
    echo
}

# Enhanced success messages with clear next steps  
setup_show_success() {
    local domain="${1:-localhost}"
    local admin_user="${2:-admin}"
    local admin_password="${3:-[generated]}"
    local admin_email="${4:-admin@localhost}"
    
    milou_log "HEADER" "🎉 Setup Complete! Welcome to Milou 🎉"
    
    local success_message
    success_message=$(cat <<EOF
Your Milou system is ready to use!

Access URL:   https://$domain
Admin User:   $admin_user
Password:     $admin_password

IMPORTANT: Save these credentials securely!
EOF
)
    milou_log "PANEL" "$success_message"

    log_next_steps \
        "Open ${CYAN}https://$domain${NC} in your browser" \
        "Log in with your new credentials" \
        "Create a backup: ${CYAN}./milou.sh backup${NC}"
    
    log_tip "Need help? Run ${CYAN}./milou.sh --help${NC} or check the documentation."
}

# Enhanced error display with helpful guidance
setup_show_error() {
    local error_msg="$1"
    local context="${2:-}"
    local solutions=("${@:3}")
    
    echo
    milou_log "ERROR" "$error_msg"
    
    if [[ -n "$context" ]]; then
        echo -e "${DIM}Context: $context${NC}"
        echo
    fi
    
    if [[ ${#solutions[@]} -gt 0 ]]; then
        echo -e "${YELLOW}${BOLD}✓ How to fix this:${NC}"
        for i in "${!solutions[@]}"; do
            echo -e "   ${BLUE}$((i+1)).${NC} ${solutions[$i]}"
        done
        echo
    fi
    
    log_tip "If you need help, check our troubleshooting guide or contact support"
}

# System analysis display with user-friendly language
setup_show_analysis() {
    local is_fresh="${1:-true}"
    local needs_deps="${2:-false}"
    local needs_user="${3:-false}"
    local existing_install="${4:-false}"
    
    log_section "System Analysis" "Understanding your current environment"
    
    # Translate technical status to user-friendly language
    if [[ "$is_fresh" == "true" ]]; then
        echo -e "   ${GREEN}${CHECKMARK}${NC} Fresh system detected - perfect for a clean installation"
    else
        echo -e "   ${BLUE}${BULLET}${NC} Existing system detected - we'll work with your current setup"
    fi
    
    if [[ "$needs_deps" == "true" ]]; then
        echo -e "   ${YELLOW}${WRENCH}${NC} Docker and other tools will be installed automatically."
    else
        echo -e "   ${GREEN}${CHECKMARK}${NC} All required tools are already installed."
    fi
    
    if [[ "$needs_user" == "true" ]]; then
        echo -e "   ${BLUE}${BULLET}${NC} A dedicated 'milou' user will be created for security."
    else
        echo -e "   ${GREEN}${CHECKMARK}${NC} User account is properly configured."
    fi
    
    if [[ "$existing_install" == "true" ]]; then
        echo -e "   ${YELLOW}${WRENCH}${NC} Existing Milou installation found. We'll update it carefully."
    else
        echo -e "   ${GREEN}${SPARKLES}${NC} This will be a fresh Milou installation."
    fi
    
    echo
    log_tip "Everything looks good! The setup will handle any required installations automatically."
}

# =============================================================================
# MAIN SETUP ORCHESTRATION FUNCTIONS
# =============================================================================

# Repair mode orchestration
_setup_run_repair() {
    local force="$1"
    local preserve_creds="$2"

    log_step "🛠️" "Repair Mode"
    
    # Load existing config
    if [[ ! -f "${MILOU_ENV_FILE:-${SCRIPT_DIR}/.env}" ]]; then
        log_error "No .env file found. Cannot run repair. Please run standard setup."
        return 1
    fi
    
    # ------------------------------------------------------------------
    # Preserve any token that might have been supplied via --token or
    # environment variable BEFORE we source the user's .env file (which
    # may contain an empty or outdated GITHUB_TOKEN entry).
    # ------------------------------------------------------------------
    local cli_github_token="${GITHUB_TOKEN:-}"

    # Sanitize .env first to avoid syntax errors from corrupt lines
    sanitize_env_file "${MILOU_ENV_FILE:-${SCRIPT_DIR}/.env}"

    # Source the .env file to get existing values
    set -a
    source "${MILOU_ENV_FILE:-${SCRIPT_DIR}/.env}"
    set +a

    # If the .env did not provide a token, fall back to the one supplied
    # on the command line (if any)
    if [[ -z "${GITHUB_TOKEN:-}" && -n "$cli_github_token" ]]; then
        export GITHUB_TOKEN="$cli_github_token"
    fi

    # Ensure we have a token (will prompt if interactive) and perform registry login
    if ! core_require_github_token "${GITHUB_TOKEN:-}" "${MILOU_INTERACTIVE:-true}"; then
        return 1
    fi

    local domain="${DOMAIN:-localhost}"
    local admin_email="${ADMIN_EMAIL:-admin@localhost}"
    local ssl_mode="${SSL_MODE:-generate}"

    log_info "Found existing configuration:"
    log_info "  Domain: $domain"
    log_info "  Admin Email: $admin_email"
    log_info "  SSL Mode: $ssl_mode"

    # STEP 1: System Validation
    if ! _setup_validate_system; then
        log_error "System validation failed. Please address the issues above."
        return 1
    fi
    
    log_success "System validation passed. Ready to repair."
    echo

    # NEW: Automatically detect and offer to fix credential mismatches
    log_step "🔑" "Checking for Credential Mismatch"
    if detect_credential_mismatch "true"; then # Quietly check
        log_warning "Credential mismatch detected. This is a common issue after re-installations."
        log_info "This happens when the application has a different password than the database."
        
        if confirm "Attempt to resolve credential mismatch automatically?" "Y"; then
            if resolve_credential_mismatch "false" "false"; then
                log_success "Credential mismatch resolved successfully! The system should now start correctly."
            else
                log_error "Failed to resolve credential mismatch. The setup may fail."
                log_info "You can try a full reset with: ./milou.sh setup --clean"
                return 1
            fi
        else
            log_warning "Skipping automatic credential fix. The setup will likely fail."
        fi
    else
        log_success "No credential mismatch detected. Your credentials appear to be in sync."
    fi
    echo

    # STEP 2: Configuration Regeneration (non-interactive)
    log_step "⚙️" "Configuration Regeneration"
    
    # We directly call config_generate, skipping interactive part.
    # The 'true' for preserve_creds is critical.
    if ! config_generate "$domain" "$admin_email" "$ssl_mode" "false" "true" "false" "true"; then
        log_error "Configuration regeneration failed."
        return 1
    fi

    # STEP 3: GitHub Token and Deployment
    if ! _setup_handle_github_and_deployment; then
        log_error "Deployment failed."
        return 1
    fi

    # STEP 4: Finalization and Credentials
    if ! _setup_finalize_and_display_credentials "$preserve_creds"; then
        log_error "Finalization step failed."
        return 1
    fi
    
    milou_log "SUCCESS" "🎉 Milou repair completed successfully! 🎉"
    echo
    
    return 0
}

# Main setup entry point with enhanced UX
setup_run() {
    local force="${1:-false}"
    local mode="${2:-auto}"
    local skip_validation="${3:-false}"
    local preserve_creds="${4:-auto}"
    local from_installer="${5:-false}"
    
    if [[ "$mode" == "repair" ]]; then
        if ! _setup_run_repair "$force" "$preserve_creds"; then
            log_error "Repair process failed."
            return 1
        fi
        return 0
    fi
    
    # Ensure interactive mode is properly set for setup wizard
    if [[ "${MILOU_INTERACTIVE:-}" == "true" ]] || [[ "${INTERACTIVE:-}" == "true" ]]; then
        export MILOU_INTERACTIVE=true
        export INTERACTIVE=true
        milou_log "DEBUG" "Setup running in interactive mode (forced by environment)"
    elif [[ -t 0 && -t 1 ]]; then
        export MILOU_INTERACTIVE=true
        export INTERACTIVE=true
        milou_log "DEBUG" "Setup running in interactive mode (stdin/stdout available)"
    else
        export MILOU_INTERACTIVE=false
        export INTERACTIVE=false
        milou_log "WARN" "Setup detected non-interactive environment"
    fi
    
    # Show enhanced Milou logo and welcome, unless coming from installer
    if [[ "$from_installer" != "true" ]]; then
        setup_show_logo
    fi
    
    # Enhanced setup header with progress tracking
    setup_show_header 1 7 "Starting Setup"
    
    # STEP 0: System Analysis (this sets the SETUP_IS_FRESH_SERVER flags)
    setup_analyze_system
    
    # Improved detection of installation state
    local has_env_file="false"
    local has_docker_resources="false"
    
    if [[ -f "${MILOU_ENV_FILE:-${SCRIPT_DIR}/.env}" ]]; then
        has_env_file="true"
    fi
    
    # Check for any Docker resources (containers, volumes) that might need cleanup
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        local container_count=0
        local volume_count=0
        
        # Check for containers
        if docker ps -a --filter "name=milou-" --format "{{.Names}}" 2>/dev/null | grep -q milou; then
            container_count=$(docker ps -a --filter "name=milou-" --format "{{.Names}}" 2>/dev/null | wc -l)
        fi
        
        # Check for volumes
        if docker volume ls --format "{{.Name}}" 2>/dev/null | grep -E "(milou|static)" >/dev/null 2>&1; then
            volume_count=$(docker volume ls --format "{{.Name}}" 2>/dev/null | grep -E "(milou|static)" | wc -l)
        fi
        
        if [[ $container_count -gt 0 ]] || [[ $volume_count -gt 0 ]]; then
            has_docker_resources="true"
            milou_log "DEBUG" "Found existing Docker resources: $container_count containers, $volume_count volumes"
        fi
    fi
    
    # Determine cleanup strategy based on what we found
    if [[ "$has_env_file" == "true" && "$has_docker_resources" == "true" ]]; then
        # This is a re-configuration of existing installation
        setup_announce_step "🧹" "Preparing Environment" "Stopping existing services to apply new settings."
        if ! docker_cleanup_environment "safe"; then # Safe mode preserves data
             log_warning "Could not stop all services cleanly, but proceeding."
        fi
        echo
    elif [[ "$has_env_file" == "false" && "$has_docker_resources" == "true" ]]; then
        # This is likely leftover from a previous broken installation
        setup_announce_step "🧹" "Cleanup" "Found leftover Docker resources from a previous installation."
        
        # For cleanup without .env file, we need to use a more direct approach
        if command -v docker >/dev/null 2>&1; then
            # Stop and remove containers by name pattern
            if docker ps -q --filter "name=milou-" | head -1 >/dev/null 2>&1; then
                log_info "Stopping Milou containers..."
                docker stop $(docker ps -q --filter "name=milou-") 2>/dev/null || true
            fi
            if docker ps -aq --filter "name=milou-" | head -1 >/dev/null 2>&1; then
                log_info "Removing Milou containers..."
                docker rm $(docker ps -aq --filter "name=milou-") 2>/dev/null || true
            fi
            
            # Remove networks (but not volumes - preserve data)
            local networks
            if networks=$(docker network ls --filter "name=milou" --format "{{.Name}}" 2>/dev/null); then
                for network in $networks; do
                    if [[ "$network" != "bridge" && "$network" != "host" && "$network" != "none" ]]; then
                        log_info "Removing network: $network"
                        docker network rm "$network" 2>/dev/null || true
                    fi
                done
            fi
        fi
        echo
    elif [[ "$has_env_file" == "false" && "$has_docker_resources" == "false" ]]; then
        # This is a truly fresh installation - no cleanup needed
        setup_announce_step "✨" "Fresh Installation" "Clean system detected. Ready to begin."
        echo
    else
        # Edge case: has .env but no Docker resources
        setup_announce_step "🔧" "Configuration Recovery" "Configuration file found but no active services."
        echo
    fi

    # STEP 1: Introduction
    log_section "🚀 Welcome to the Milou Setup Wizard"
    echo -e "${DIM}This wizard will guide you through installing and configuring Milou.${NC}"
    echo -e "${DIM}It should only take a few minutes.${NC}"
    echo
    
    # Preserve existing credentials if this is a re-run
    local preserve_creds="false"
    if [[ "$has_env_file" == "true" ]]; then
        if confirm "Do you want to preserve your existing admin credentials?" "Y"; then
            preserve_creds="true"
        fi
        echo
    fi
    
    # STEP 2: System Validation
    if ! _setup_validate_system; then
        log_error "System validation failed. Please address the issues above."
        return 1
    fi
    
    # ------------------------------------------------------------------
    # The GitHub token is now requested just-in-time during the interactive
    # configuration if the user selects a dynamic version. This avoids
    # asking for it unnecessarily. For other modes, the token must be
    # in the environment, and config_generate will fail correctly if not.
    # ------------------------------------------------------------------
    
    log_success "System validation passed. Ready to configure."
    echo
    
    # STEP 3: Interactive Configuration
    if [[ "$INTERACTIVE" == "true" ]]; then
        setup_announce_step "2" "Configuration" "Let's personalize your Milou setup."
        
        # Use the existing setup_generate_configuration_interactive function
        if ! setup_generate_configuration_interactive "$preserve_creds"; then
            log_error "Configuration was cancelled or failed."
            return 1
        fi
    else
        # Automated mode
        setup_announce_step "2" "Configuration" "Generating configuration automatically."
        if ! setup_generate_configuration_automated "$preserve_creds"; then
            log_error "Automated configuration failed."
            return 1
        fi
    fi
    
    # STEP 4: GitHub Token and Deployment
    setup_announce_step "4" "Deployment" "Pulling images and starting services."
    if ! _setup_handle_github_and_deployment; then
        log_error "Deployment failed."
        return 1
    fi

    # STEP 5: Finalization and Credentials
    setup_announce_step "5" "Finalizing"
    if ! _setup_finalize_and_display_credentials "$preserve_creds"; then
        log_error "Finalization step failed."
        return 1
    fi
    
    milou_log "SUCCESS" "🎉 Milou setup completed successfully! 🎉"
    echo
    
    return 0
}

# =============================================================================
# SETUP ORCHESTRATION FUNCTIONS  
# =============================================================================

# System validation orchestrator
_setup_validate_system() {
    log_section "System Validation"
    
    local errors=0
    local warnings=0
    
    # For fresh installations, we need to install dependencies first before validation
    # Check if this is a fresh server that needs dependencies
    local needs_docker_install=false
    if ! command -v docker >/dev/null 2>&1; then
        needs_docker_install=true
        log_info "Docker not detected. It will be installed automatically."
    elif ! docker info >/dev/null 2>&1; then
        log_warning "Docker is installed but the daemon is not running."
        if systemctl is-active --quiet docker 2>/dev/null || service docker status >/dev/null 2>&1; then
            log_info "Attempting to start the Docker daemon..."
            if systemctl start docker 2>/dev/null || service docker start 2>/dev/null; then
                log_success "Docker daemon started successfully."
                sleep 2  # Give Docker a moment to fully start
            else
                log_warning "Could not start the Docker daemon automatically."
                ((warnings++))
            fi
        else
            log_warning "Docker daemon is not running and the service is not available/enabled."
            ((warnings++))
        fi
    fi
    
    # Install dependencies if needed (on fresh systems) - USE INTERACTIVE VERSION
    if [[ "$needs_docker_install" == "true" ]]; then
        log_info "🔧 Milou requires Docker to function. The installer will now set it up for you."
        
        # Use interactive installation to ask user permission
        if ! setup_install_dependencies_interactive; then
            log_error "Dependencies installation was cancelled or failed."
            ((errors++))
        else
            log_success "Dependencies installed successfully."
            
            # Verify Docker is now working
            if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
                log_success "Docker is now available and running."
            else
                log_warning "Docker was installed but may need to be started manually."
                ((warnings++))
            fi
        fi
    fi
    
    # Now validate what we have
    if command -v docker >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then
            log_success "Docker is available and running."
            
            # Test Docker Compose
            if docker compose version >/dev/null 2>&1; then
                log_success "✓ Docker Compose is available"
            else
                log_error "Docker Compose is not available"
                ((errors++))
            fi
        else
            log_warning "Docker is installed but daemon is not accessible"
            ((warnings++))
        fi
    else
        if [[ "$needs_docker_install" == "true" ]]; then
            log_error "Docker installation failed"
            ((errors++))
        else
            log_error "Docker is not installed"
            ((errors++))
        fi
    fi
    
    # Check system prerequisites (non-critical)
    if ! setup_assess_prerequisites; then
        log_info "Prerequisites assessment completed with notes"
    fi
    
    # Report results
    if [[ $errors -eq 0 ]]; then
        if [[ $warnings -eq 0 ]]; then
            log_success "System validation completed successfully"
        else
            log_success "System validation completed with $warnings warning(s)"
        fi
        return 0
    else
        log_error "System validation failed with $errors error(s)"
        return 1
    fi
}

# Interactive configuration orchestrator  
_setup_interactive_configuration() {
    local preserve_creds="${1:-auto}"
    
    log_section "⚙️" "Interactive Configuration"
    
    # Use the existing setup_generate_configuration_interactive function
    if setup_generate_configuration_interactive "$preserve_creds"; then
        log_success "Interactive configuration completed"
        return 0
    else
        log_error "Interactive configuration failed"
        return 1
    fi
}

# GitHub and deployment orchestrator
_setup_handle_github_and_deployment() {
    log_step "🚀" "GitHub Authentication & Deployment"
    
    # Validate and start services using existing function
    if setup_validate_and_start_services; then
        log_success "GitHub authentication and deployment completed"
        return 0
    else
        log_error "GitHub authentication and deployment failed"
        return 1
    fi
}

# Finalization and credentials display orchestrator
_setup_finalize_and_display_credentials() {
    local preserve_creds="${1:-auto}"
    
    log_step "🎯" "Finalizing Setup"
    
    # Display completion report using existing function
    if setup_display_completion_report; then
        log_success "Setup finalization completed"
        return 0
    else
        log_error "Setup finalization failed"
        return 1
    fi
}

# =============================================================================
# SYSTEM ANALYSIS FUNCTIONS
# =============================================================================

# Analyze system and detect setup requirements - SINGLE AUTHORITATIVE IMPLEMENTATION
setup_analyze_system() {
    milou_log "STEP" "Step 1: System Analysis"
    
    # Reset analysis state
    SETUP_IS_FRESH_SERVER="false"
    SETUP_NEEDS_DEPS="false" 
    SETUP_NEEDS_USER="false"
    
    milou_log "INFO" "✓ Analyzing system state..."
    
    # Check if this is a fresh server installation
    if setup_detect_fresh_server; then
        SETUP_IS_FRESH_SERVER="true"
        milou_log "INFO" "✓ Fresh server detected"
    else
        milou_log "INFO" "✓ Existing system detected"
    fi
    
    # Check for existing Milou installation
    local has_existing_installation=false
    if setup_check_existing_installation; then
        has_existing_installation=true
        milou_log "INFO" "✓ Found existing Milou installation"
    fi
    
    # Determine dependency needs
    if ! setup_check_dependencies_status; then
        SETUP_NEEDS_DEPS="true"
        milou_log "INFO" "✓ Dependencies installation required"
    fi
    
    # Determine user management needs
    if ! setup_check_user_status; then
        SETUP_NEEDS_USER="true"
        milou_log "INFO" "✓ User management required"
    fi
    
    # Summary
    milou_log "SUCCESS" "✓ System Analysis Complete:"
    milou_log "INFO" "  ✓ Fresh Server: $SETUP_IS_FRESH_SERVER"
    milou_log "INFO" "  ✓ Needs Dependencies: $SETUP_NEEDS_DEPS"
    milou_log "INFO" "  ✓ Needs User Setup: $SETUP_NEEDS_USER"
    milou_log "INFO" "  ✓ Existing Installation: $has_existing_installation"
    
    return 0
}

# Detect if this is a fresh server installation
setup_detect_fresh_server() {
    local fresh_indicators=0
    local total_checks=6
    
    # Check 1: No Docker containers (only if Docker is available)
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        if [[ $(docker ps -a --format "{{.Names}}" 2>/dev/null | wc -l) -eq 0 ]]; then
            ((fresh_indicators++))
            milou_log "DEBUG" "✓ No existing Docker containers"
        fi
    else
        # Docker not available = fresh system
        ((fresh_indicators++))
        milou_log "DEBUG" "✓ Docker not installed (fresh system)"
    fi
    
    # Check 2: No Docker volumes (only if Docker is available)
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        if [[ $(docker volume ls --format "{{.Name}}" 2>/dev/null | wc -l) -eq 0 ]]; then
            ((fresh_indicators++))
            milou_log "DEBUG" "✓ No existing Docker volumes"
        fi
    else
        # Docker not available = fresh system
        ((fresh_indicators++))
        milou_log "DEBUG" "✓ Docker not installed (fresh system volumes)"
    fi
    
    # Check 3: No configuration files
    if [[ ! -f "${SCRIPT_DIR:-$(pwd)}/.env" ]]; then
        ((fresh_indicators++))
        milou_log "DEBUG" "✓ No existing configuration"
    fi
    
    # Check 4: System looks newly provisioned
    if [[ -f /var/log/cloud-init.log ]] || [[ -f /var/log/cloud-init-output.log ]]; then
        ((fresh_indicators++))
        milou_log "DEBUG" "✓ Cloud-init detected (fresh cloud instance)"
    fi
    
    # Check 5: Minimal package history
    if command -v dpkg >/dev/null 2>&1; then
        local pkg_count
        pkg_count=$(dpkg -l 2>/dev/null | wc -l)
        if [[ $pkg_count -lt 200 ]]; then
            ((fresh_indicators++))
            milou_log "DEBUG" "✓ Minimal package installation ($pkg_count packages)"
        fi
    elif command -v rpm >/dev/null 2>&1; then
        local pkg_count
        pkg_count=$(rpm -qa 2>/dev/null | wc -l)
        if [[ $pkg_count -lt 150 ]]; then
            ((fresh_indicators++))
            milou_log "DEBUG" "✓ Minimal package installation ($pkg_count packages)"
        fi
    else
        ((fresh_indicators++))
        milou_log "DEBUG" "✓ Unknown package manager (assuming minimal)"
    fi
    
    # Check 6: System uptime
    if command -v uptime >/dev/null 2>&1; then
        local uptime_days
        uptime_days=$(uptime | grep -o '[0-9]* day' | cut -d' ' -f1 || echo "0")
        if [[ ${uptime_days:-0} -lt 7 ]]; then
            ((fresh_indicators++))
            milou_log "DEBUG" "✓ Recent system boot (${uptime_days:-0} days uptime)"
        fi
    fi
    
    # Determine if server is "fresh" (majority of indicators suggest it)
    if [[ $fresh_indicators -ge $((total_checks / 2)) ]]; then
        milou_log "DEBUG" "Fresh server detected ($fresh_indicators/$total_checks indicators)"
        return 0
    else
        milou_log "DEBUG" "Existing system detected ($fresh_indicators/$total_checks indicators)"
        return 1
    fi
}

# Check for existing Milou installation
setup_check_existing_installation() {
    local has_containers=false
    local has_config=false
    local has_volumes=false
    
    # Check for existing containers (only if Docker is available)
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        if docker ps -a --filter "name=milou-" --format "{{.Names}}" 2>/dev/null | grep -q milou; then
            has_containers=true
            milou_log "DEBUG" "Found existing Milou containers"
        fi
        
        # Check for data volumes
        if docker volume ls --format "{{.Name}}" 2>/dev/null | grep -E "(milou|static)"; then
            has_volumes=true
            milou_log "DEBUG" "Found existing data volumes"
        fi
    fi
    
    # Check for configuration
    if [[ -f "${SCRIPT_DIR:-$(pwd)}/.env" ]]; then
        has_config=true
        milou_log "DEBUG" "Found existing configuration file"
    fi
    
    # Return true if any component exists
    if [[ "$has_containers" == "true" || "$has_config" == "true" || "$has_volumes" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Check dependency installation status - SIMPLIFIED using unified validation
setup_check_dependencies_status() {
    # Check if Docker is available and working
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        milou_log "DEBUG" "All dependencies are available"
        return 0
    else
        milou_log "DEBUG" "Dependencies need installation"
        return 1
    fi
}

# Check user management status
setup_check_user_status() {
    # Check if running as root and if milou user exists
    if [[ $EUID -eq 0 ]]; then
        if id milou >/dev/null 2>&1; then
            milou_log "DEBUG" "Milou user already exists"
            return 0
        else
            milou_log "DEBUG" "Running as root, milou user needed"
            return 1
        fi
    else
        # Check if current user has Docker access (if Docker is available)
        if command -v docker >/dev/null 2>&1 && docker version >/dev/null 2>&1; then
            milou_log "DEBUG" "Current user has Docker access"
            return 0
        elif command -v docker >/dev/null 2>&1; then
            milou_log "DEBUG" "Current user needs Docker access"
            return 1
        else
            # Docker not installed yet, assume user setup will be needed
            milou_log "DEBUG" "Docker not available, user setup may be needed"
            return 1
        fi
    fi
}

# =============================================================================
# PREREQUISITES ASSESSMENT FUNCTIONS
# =============================================================================

# Assess system prerequisites - SIMPLIFIED using unified validation
setup_assess_prerequisites() {
    milou_log "STEP" "Step 2: Prerequisites Assessment"
    
    # Check if Docker is missing
    local docker_missing=false
    if ! command -v docker >/dev/null 2>&1; then
        docker_missing=true
    elif ! docker info >/dev/null 2>&1; then
        docker_missing=true
    elif ! docker compose version >/dev/null 2>&1; then
        docker_missing=true
    fi
    
    # On fresh systems, missing Docker is expected and normal
    if [[ "$docker_missing" == "true" ]]; then
        if [[ "$SETUP_IS_FRESH_SERVER" == "true" ]] || [[ "$SETUP_NEEDS_DEPS" == "true" ]]; then
            milou_log "INFO" "✓ Docker installation needed (will be installed automatically)"
            return 0  # Return 0 - this is expected for fresh systems
        else
            # On existing systems, missing Docker is an error
            milou_log "ERROR" "Docker is not installed"
            milou_log "INFO" "💡 Install Docker: https://docs.docker.com/get-docker/"
            return 1
        fi
    else
        milou_log "SUCCESS" "✓ All prerequisites satisfied"
        return 0
    fi
}

# =============================================================================
# SETUP MODE DETERMINATION FUNCTIONS
# =============================================================================

# Determine optimal setup mode - SINGLE AUTHORITATIVE IMPLEMENTATION
setup_determine_mode() {
    local requested_mode="${1:-auto}"
    
    milou_log "STEP" "Step 3: Setup Mode Determination"
    
    case "$requested_mode" in
        "interactive")
            SETUP_CURRENT_MODE="$SETUP_MODE_INTERACTIVE"
            milou_log "INFO" "✓ Interactive mode selected"
            ;;
        "automated"|"auto")
            # For automated mode, check if we have required variables OR if user explicitly requested it
            if setup_can_run_automated || [[ "$requested_mode" == "automated" ]]; then
                SETUP_CURRENT_MODE="$SETUP_MODE_AUTOMATED"
                milou_log "INFO" "✓ Automated mode selected"
            else
                SETUP_CURRENT_MODE="$SETUP_MODE_INTERACTIVE"
                milou_log "INFO" "✓ Falling back to interactive mode (missing environment variables)"
            fi
            ;;
        "smart")
            SETUP_CURRENT_MODE="$SETUP_MODE_SMART"
            milou_log "INFO" "✓ Smart mode selected"
            ;;
        *)
            milou_log "WARN" "Unknown setup mode: $requested_mode, using interactive"
            SETUP_CURRENT_MODE="$SETUP_MODE_INTERACTIVE"
            ;;
    esac
    
    milou_log "SUCCESS" "✓ Setup mode determined: $SETUP_CURRENT_MODE"
    return 0
}

# Check if automated mode is possible
setup_can_run_automated() {
    # Check for required environment variables
    local required_vars=("DOMAIN" "ADMIN_EMAIL")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -eq 0 ]]; then
        milou_log "DEBUG" "Environment variables available for automated setup"
        return 0
    else
        milou_log "DEBUG" "Missing variables for automated setup: ${missing_vars[*]}"
        return 1
    fi
}

# =============================================================================
# DEPENDENCIES INSTALLATION FUNCTIONS
# =============================================================================

# Install required dependencies - SINGLE AUTHORITATIVE IMPLEMENTATION
setup_install_dependencies() {
    milou_log "STEP" "Step 4: Dependencies Installation"
    
    case "$SETUP_CURRENT_MODE" in
        "$SETUP_MODE_INTERACTIVE")
            setup_install_dependencies_interactive
            ;;
        "$SETUP_MODE_AUTOMATED")
            setup_install_dependencies_automated
            ;;
        "$SETUP_MODE_SMART")
            setup_install_dependencies_smart
            ;;
        *)
            milou_log "ERROR" "Unknown setup mode for dependencies: $SETUP_CURRENT_MODE"
            return 1
            ;;
    esac
}

# Interactive dependencies installation
setup_install_dependencies_interactive() {
    log_section "▼ Step 4: Dependencies Installation" "Installing Docker and required tools"
    
    echo -e "${BOLD}${CYAN}🔧 Required Dependencies:${NC}"
    echo -e "   • Docker Engine - Container platform"
    echo -e "   • Docker Compose - Multi-container applications"
    echo -e "   • System tools - curl, wget, jq, openssl"
    echo
    
    if ! confirm "Install missing dependencies now?" "Y"; then
        milou_log "INFO" "Dependencies installation skipped by user"
        return 1
    fi
    
    setup_install_dependencies_core
}

# Automated dependencies installation
setup_install_dependencies_automated() {
    milou_log "INFO" "✓ Automated Dependencies Installation"
    setup_install_dependencies_core
}

# Smart dependencies installation  
setup_install_dependencies_smart() {
    milou_log "INFO" "✓ Smart Dependencies Installation"
    
    # Install critical dependencies automatically, prompt for optional
    if ! setup_install_dependencies_core "critical_only"; then
        return 1
    fi
    
    # Optionally install additional tools
    if confirm "Install optional tools (curl, wget, jq, openssl)?" "Y"; then
        setup_install_system_tools
    fi
}

# Core dependencies installation logic
setup_install_dependencies_core() {
    local mode="${1:-all}"
    
    milou_log "INFO" "✓ Installing core dependencies..."
    
    # Install Docker if missing
    if ! command -v docker >/dev/null 2>&1; then
        if ! setup_install_docker; then
            milou_log "ERROR" "Failed to install Docker"
            return 1
        fi
    fi
    
    # Install Docker Compose if missing
    if ! docker compose version >/dev/null 2>&1; then
        if ! setup_install_docker_compose; then
            milou_log "ERROR" "Failed to install Docker Compose"
            return 1
        fi
    fi
    
    # Install system tools if requested
    if [[ "$mode" != "critical_only" ]]; then
        setup_install_system_tools
    fi
    
    milou_log "SUCCESS" "✓ Dependencies installation completed"
    return 0
}

# Install Docker
setup_install_docker() {
    milou_log "INFO" "🐳 Installing Docker..."
    
    # Show progress indicator for user feedback
    printf "${CYAN}${BULLET} Installing Docker Engine...${NC}"
    
    # Use official Docker installation script with suppressed output
    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL https://get.docker.com | sh >/dev/null 2>&1; then
            printf "\r${GREEN}${CHECKMARK} Docker Engine installed successfully${NC}\n"
            
            # Start and enable Docker service quietly
            systemctl start docker >/dev/null 2>&1 || true
            systemctl enable docker >/dev/null 2>&1 || true
            
            milou_log "SUCCESS" "✓ Docker installation completed"
            return 0
        else
            printf "\r${RED}${CROSSMARK} Docker installation failed${NC}\n"
        fi
    fi
    
    milou_log "ERROR" "Failed to install Docker"
    return 1
}

# Install Docker Compose
setup_install_docker_compose() {
    milou_log "INFO" "🐳 Installing Docker Compose..."
    
    printf "${CYAN}${BULLET} Installing Docker Compose plugin...${NC}"
    
    # Try package manager first
    local install_success=false
    if command -v apt-get >/dev/null 2>&1; then
        if apt-get update >/dev/null 2>&1 && apt-get install -y docker-compose-plugin >/dev/null 2>&1; then
            install_success=true
        fi
    elif command -v yum >/dev/null 2>&1; then
        if yum install -y docker-compose-plugin >/dev/null 2>&1; then
            install_success=true
        fi
    fi
    
    if [[ "$install_success" == "true" ]]; then
        printf "\r${GREEN}${CHECKMARK} Docker Compose plugin installed successfully${NC}\n"
        milou_log "SUCCESS" "✓ Docker Compose plugin installed"
        return 0
    fi
    
    printf "\r${YELLOW}⚠️  Package manager failed, trying manual installation...${NC}\n"
    milou_log "WARN" "Package manager installation failed, trying manual installation"
    
    # Manual installation fallback
    local compose_version="v2.20.0"
    local compose_url="https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-$(uname -s)-$(uname -m)"
    
    printf "${CYAN}${BULLET} Downloading Docker Compose binary...${NC}"
    
    if command -v curl >/dev/null 2>&1; then
        if curl -L "$compose_url" -o /usr/local/bin/docker-compose >/dev/null 2>&1; then
            chmod +x /usr/local/bin/docker-compose
            printf "\r${GREEN}${CHECKMARK} Docker Compose installed manually${NC}\n"
            milou_log "SUCCESS" "✓ Docker Compose installed manually"
            return 0
        else
            printf "\r${RED}${CROSSMARK} Manual installation failed${NC}\n"
        fi
    fi
    
    milou_log "ERROR" "Failed to install Docker Compose"
    return 1
}

# Install system tools
setup_install_system_tools() {
    milou_log "INFO" "🔧 Installing system tools..."
    
    local tools=("curl" "wget" "jq" "openssl")
    local to_install=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            to_install+=("$tool")
        fi
    done
    
    if [[ ${#to_install[@]} -eq 0 ]]; then
        milou_log "SUCCESS" "✓ All system tools already installed"
        return 0
    fi
    
    printf "${CYAN}${BULLET} Installing: ${to_install[*]}...${NC}"
    
    local install_success=false
    if command -v apt-get >/dev/null 2>&1; then
        if apt-get update >/dev/null 2>&1 && apt-get install -y "${to_install[@]}" >/dev/null 2>&1; then
            install_success=true
        fi
    elif command -v yum >/dev/null 2>&1; then
        if yum install -y "${to_install[@]}" >/dev/null 2>&1; then
            install_success=true
        fi
    elif command -v dnf >/dev/null 2>&1; then
        if dnf install -y "${to_install[@]}" >/dev/null 2>&1; then
            install_success=true
        fi
    else
        printf "\r${RED}${CROSSMARK} Unsupported package manager${NC}\n"
        milou_log "WARN" "Unsupported package manager"
        return 1
    fi
    
    if [[ "$install_success" == "true" ]]; then
        printf "\r${GREEN}${CHECKMARK} System tools installed successfully${NC}\n"
        milou_log "SUCCESS" "✓ System tools installed"
        return 0
    else
        printf "\r${RED}${CROSSMARK} Failed to install system tools${NC}\n"
        milou_log "ERROR" "Failed to install system tools"
        return 1
    fi
}

# =============================================================================
# USER MANAGEMENT FUNCTIONS
# =============================================================================

# Manage user setup - SINGLE AUTHORITATIVE IMPLEMENTATION
setup_manage_user() {
    milou_log "STEP" "Step 5: User Management"
    
    if [[ $EUID -eq 0 ]]; then
        setup_create_milou_user
    else
        setup_configure_current_user
    fi
}

# Create dedicated milou user
setup_create_milou_user() {
    milou_log "INFO" "✓ Creating dedicated milou user..."
    
    # Create user if it doesn't exist
    if ! id milou >/dev/null 2>&1; then
        if useradd -m -s /bin/bash milou; then
            milou_log "SUCCESS" "✓ Milou user created"
        else
            milou_log "ERROR" "Failed to create milou user"
            return 1
        fi
    else
        milou_log "INFO" "Milou user already exists"
    fi
    
    # Add to docker group
    if ! groups milou | grep -q docker; then
        if usermod -aG docker milou; then
            milou_log "SUCCESS" "✓ Added milou user to docker group"
        else
            milou_log "ERROR" "Failed to add milou user to docker group"
            return 1
        fi
    fi
    
    milou_log "SUCCESS" "✓ User management completed"
    return 0
}

# Configure current user for Docker access
setup_configure_current_user() {
    local current_user="${USER:-$(whoami)}"
    
    milou_log "INFO" "✓ Configuring current user ($current_user) for Docker access..."
    
    # Check if user is in docker group
    if ! groups "$current_user" | grep -q docker; then
        milou_log "INFO" "Adding current user to docker group (requires sudo)..."
        if sudo usermod -aG docker "$current_user"; then
            milou_log "SUCCESS" "✓ Added $current_user to docker group"
            milou_log "WARN" "✓  You may need to log out and log back in for group changes to take effect"
        else
            milou_log "ERROR" "Failed to add user to docker group"
            return 1
        fi
    else
        milou_log "SUCCESS" "✓ User already has Docker access"
    fi
    
    return 0
}

# =============================================================================
# CONFIGURATION GENERATION FUNCTIONS
# =============================================================================

# Generate configuration based on setup mode - SINGLE AUTHORITATIVE IMPLEMENTATION
setup_generate_configuration() {
    local preserve_creds="${1:-auto}"
    
    milou_log "STEP" "Step 6: Configuration Generation"
    
    case "$SETUP_CURRENT_MODE" in
        "$SETUP_MODE_INTERACTIVE")
            setup_generate_configuration_interactive "$preserve_creds"
            ;;
        "$SETUP_MODE_AUTOMATED")
            setup_generate_configuration_automated "$preserve_creds"
            ;;
        "$SETUP_MODE_SMART")
            setup_generate_configuration_smart "$preserve_creds"
            ;;
        *)
            milou_log "ERROR" "Unknown setup mode for configuration: $SETUP_CURRENT_MODE"
            return 1
            ;;
    esac
}

# Enhanced interactive configuration generation with better UX
setup_generate_configuration_interactive() {
    local preserve_creds="${1:-auto}"
    
    log_section "✓ Interactive Configuration" "Let's personalize your Milou setup"
    echo -e "${DIM}We'll ask you a few quick questions to configure everything perfectly for your needs.${NC}"
    echo
    
    # Domain Configuration with enhanced UX
    local domain
    while true; do
        log_section "✓ Domain Configuration" "Where will your Milou system be accessible?"
        echo -e "${DIM}This is the web address where you'll access Milou in your browser.${NC}"
        echo
        echo -e "${YELLOW}✓ Common examples:${NC}"
        echo -e "   ${CYAN}✓${NC} ${BOLD}localhost${NC} - For testing on this computer"
        echo -e "   ${CYAN}✓${NC} ${BOLD}milou.company.com${NC} - For company use"
        echo -e "   ${CYAN}✓${NC} ${BOLD}192.168.1.100${NC} - For local network access"
        echo
        echo -ne "${BOLD}${GREEN}Domain name${NC} [${CYAN}localhost${NC}]: "
        read -r domain
        if [[ -z "$domain" ]]; then
            domain="localhost"
        fi
        
        # Enhanced domain validation with helpful feedback
        if [[ "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9\.-]*[a-zA-Z0-9]$ ]] || [[ "$domain" == "localhost" ]]; then
            echo -e "   ${GREEN}${CHECKMARK} Perfect!${NC} Your domain: ${BOLD}$domain${NC}"
            break
        else
            echo -e "   ${RED}${CROSSMARK} That doesn't look like a valid domain.${NC}"
            echo -e "   ${YELLOW}✓ Try:${NC} localhost, your-domain.com, or an IP address"
            echo
        fi
    done
    echo
    
    # Admin Email Configuration with enhanced UX
    local email
    while true; do
        log_section "✓ Admin Contact Email" "Your administrator email address"
        echo -e "${DIM}This email will be used for important notifications and SSL certificates.${NC}"
        echo -e "${DIM}Don't worry - we won't send you spam or share it with anyone.${NC}"
        echo
        echo -ne "${BOLD}${GREEN}Admin email${NC} [${CYAN}admin@$domain${NC}]: "
        read -r email
        if [[ -z "$email" ]]; then
            email="admin@$domain"
        fi
        
        # Enhanced email validation with helpful feedback
        if validate_email "$email" "true"; then
            echo -e "   ${GREEN}${CHECKMARK} Great!${NC} Admin email: ${BOLD}$email${NC}"
            break
        else
            echo -e "   ${RED}${CROSSMARK} That email format doesn't look right.${NC}"
            echo -e "   ${YELLOW}✓ Examples:${NC} admin@yourdomain.com, admin@localhost"
            echo
        fi
    done
    echo
    
    # SSL Configuration with enhanced UX and better explanations
    log_section "✓ Security & SSL Setup" "How to secure your connection"
    echo -e "${DIM}SSL certificates encrypt the connection between your browser and Milou.${NC}"
    echo -e "${DIM}This keeps your login and data safe from prying eyes.${NC}"
    echo

    if [[ "$domain" == "localhost" || "$domain" == "127.0.0.1" ]]; then
        echo -e "${BOLD}${CYAN}Choose your security level:${NC}"
        echo
        echo -e "${GREEN}   1) ${BOLD}Quick & Easy${NC} ${DIM}(Self-signed certificates)${NC}"
        echo -e "      ${GREEN}✓${NC} Works immediately, no setup required"
        echo -e "      ${GREEN}✓${NC} Perfect for local development"
        echo -e "      ${YELLOW}⚠${NC}  Browser will show a security warning (this is normal)"
        echo
        echo -e "${YELLOW}   2) ${BOLD}Production Ready${NC} ${DIM}(Your own certificates)${NC}"
        echo -e "      ${GREEN}✓${NC} No browser warnings"
        echo -e "      ${GREEN}✓${NC} Perfect for business use"
        echo -e "      ${BLUE}✓${NC}  Requires: certificate files (supports .crt/.key or .pem formats)"
        echo -e "      ${DIM}      SSL directory: $(realpath "${SCRIPT_DIR:-$(pwd)}/ssl" 2>/dev/null || echo "${SCRIPT_DIR:-$(pwd)}/ssl")${NC}"
        echo
        echo -e "${RED}   3) ${BOLD}No Encryption${NC} ${DIM}(HTTP only - not recommended)${NC}"
        echo -e "      ${RED}✗${NC} Connection is not encrypted"
        echo -e "      ${RED}✗${NC} Only use for testing in trusted environments"
        echo

        local ssl_choice ssl_mode
        while true; do
            echo -ne "${BOLD}${GREEN}Choose security option${NC} [${CYAN}1-3${NC}] (recommended: ${BOLD}2${NC}): "
            read -r ssl_choice
            if [[ -z "$ssl_choice" ]]; then
                ssl_choice="2"
            fi
            
            case "$ssl_choice" in
                1) 
                    ssl_mode="generate"
                    echo -e "   ${GREEN}✓${NC} Using: ${BOLD}Self-signed certificates${NC}"
                    break
                    ;;
                2) 
                    ssl_mode="existing"
                    echo -e "   ${YELLOW}✓${NC} Using: ${BOLD}Your own certificates${NC}"
                    break
                    ;;
                3) 
                    ssl_mode="none"
                    echo -e "   ${RED}✗ No encryption selected${NC} Using: ${BOLD}HTTP only${NC}"
                    break
                    ;;
                *) 
                    echo -e "   ${RED}✗ Please choose 1, 2, or 3${NC}"
                    echo
                    ;;
            esac
        done
    else
        echo -e "${BOLD}${CYAN}Choose your security level:${NC}"
        echo
        echo -e "${BLUE}   1) ${BOLD}Production Ready${NC} ${DIM}(Your own certificates)${NC}"
        echo -e "      ${GREEN}✓${NC} No browser warnings"
        echo -e "      ${GREEN}✓${NC} Perfect for business use, full control over certificate source"
        echo
        echo -e "${GREEN}   2) ${BOLD}Let's Encrypt${NC} ${DIM}(Automated)${NC}"
        echo -e "      ${GREEN}✓${NC} Free trusted certificates"
        echo -e "      ${GREEN}✓${NC} Automatic renewal"
        echo -e "      ${YELLOW}⚠${NC}  Requires domain pointing to this server"
        echo
        echo -e "${CYAN}   3) ${BOLD}Generate Self-Signed${NC}"
        echo -e "      ${CYAN}✓${NC} Quick and automatic for testing"
        echo -e "      ${YELLOW}⚠${NC}  Browser security warnings"
        echo
        echo -e "${RED}   4) ${BOLD}No Encryption${NC} ${DIM}(HTTP only - not recommended)${NC}"
        echo -e "      ${RED}✗${NC} Not secure"
        echo -e "      ${RED}✗${NC} Not recommended for public domains"
        echo

        local ssl_choice ssl_mode
        while true; do
            echo -ne "${BOLD}${GREEN}Choose security option${NC} [${CYAN}1-4${NC}] (recommended: ${BOLD}1${NC}): "
            read -r ssl_choice
            if [[ -z "$ssl_choice" ]]; then
                ssl_choice="1"
            fi
            
            case "$ssl_choice" in
                1) 
                    ssl_mode="existing"
                    echo -e "   ${BLUE}✓${NC} Using: ${BOLD}Your own certificates${NC}"
                    break
                    ;;
                2) 
                    ssl_mode="letsencrypt"
                    echo -e "   ${GREEN}✓${NC} Using: ${BOLD}Let's Encrypt${NC}"
                    break
                    ;;
                3) 
                    ssl_mode="generate"
                    echo -e "   ${CYAN}✓${NC} Using: ${BOLD}Self-signed certificates${NC}"
                    break
                    ;;
                4) 
                    ssl_mode="none"
                    echo -e "   ${RED}✗${NC} Using: ${BOLD}No Encryption${NC}"
                    break
                    ;;
                *) 
                    echo -e "   ${RED}✗ Please choose 1, 2, 3, or 4${NC}"
                    echo
                    ;;
            esac
        done
    fi
    echo
    
    # Version Selection with enhanced UX
    log_section "✓ Version Selection" "Choose your Milou version"
    echo -e "${DIM}Select which version of Milou you'd like to install.${NC}"
    echo
    
    echo -e "${BOLD}${CYAN}Available options:${NC}"
    echo
    echo -e "${GREEN}   1) ${BOLD}Latest Stable${NC} ${DIM}(Recommended)${NC}"
    echo -e "      ${GREEN}✓${NC} Most recent stable release"
    echo -e "      ${GREEN}✓${NC} Thoroughly tested and reliable"
    echo -e "      ${GREEN}✓${NC} Best for production use"
    echo
    echo -e "${BLUE}   2) ${BOLD}Specific Version${NC} ${DIM}(Advanced users)${NC}"
    echo -e "      ${BLUE}✓${NC}  Choose exact version tag"
    echo -e "      ${BLUE}✓${NC}  Full control over deployment"
    echo -e "      ${YELLOW}⚠${NC}  Requires knowledge of available versions"
    echo
    
    local version_choice version_tag="1.0.0"
    while true; do
        echo -ne "${BOLD}${GREEN}Choose version option${NC} [${CYAN}1-2${NC}] (recommended: ${BOLD}1${NC}): "
        read -r version_choice
        if [[ -z "$version_choice" ]]; then
            version_choice="1"
        fi
        
        case "$version_choice" in
            1) 
                version_tag="stable"
                echo -e "   ${GREEN}✓ Excellent choice!${NC} Using: ${BOLD}Latest Stable${NC}"
                echo -e "   ${DIM}The most reliable version will be fetched during deployment.${NC}"
                break
                ;;
            2) 
                echo -e "   ${BLUE}✓ Custom version selected!${NC}"
                
                # Loop until a valid version is entered
                while true; do
                    echo -e "   ${DIM}Enter the exact version tag (e.g., 1.0.0, 2.1.3):${NC}"
                    echo -ne "   ${BOLD}Version tag:${NC} "
                    read -r custom_version
                    if [[ -z "$custom_version" ]]; then
                        milou_log "WARN" "No version entered. Please provide a version tag."
                        continue
                    fi

                    # Ensure we have a token before we can validate
                    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
                         if ! core_require_github_token "" "true"; then
                             milou_log "ERROR" "A GitHub token is required to verify the version. Setup cannot continue."
                             return 1
                         fi
                    fi

                    milou_log "INFO" "🔍 Verifying if version '$custom_version' exists for all services..."
                    
                    local all_versions_exist=true
                    local missing_for_services=()
                    for service in "${MILOU_SERVICE_LIST[@]}"; do
                        local available_versions
                        available_versions=$(get_all_available_versions "$service" "${GITHUB_TOKEN}")
                        if ! [[ "$available_versions" =~ (^|,)$custom_version(,|$) ]]; then
                            all_versions_exist=false
                            missing_for_services+=("$service")
                        fi
                        sleep 0.1 # Prevent hitting API rate limits
                    done
                    
                    if [[ "$all_versions_exist" == "true" ]]; then
                        version_tag="$custom_version"
                        echo -e "   ${GREEN}${CHECKMARK}${NC} Version ${BOLD}$version_tag${NC} is valid and available for all services."
                        break # Exit validation loop
                    else
                        milou_log "ERROR" "Version '$custom_version' is not available for the following service(s): ${missing_for_services[*]}"
                        milou_log "INFO" "Please enter a different version tag or choose another option (Ctrl+C to exit)."
                    fi
                done
                
                break
                ;;
            *) 
                echo -e "   ${RED}✗ Please choose 1 or 2${NC}"
                echo
                ;;
        esac
    done
    echo
    
    # Enhanced configuration summary with visual appeal
    local summary_panel
    summary_panel=$(cat <<EOF
Your Configuration Summary:
- Domain:         $domain
- Admin Email:    $email
- SSL Security:   $ssl_mode
- Milou Version:  $version_tag
EOF
)
    milou_log "PANEL" "$summary_panel"

    echo -e "${GREEN}${CHECKMARK} Everything looks perfect! Generating your configuration...${NC}"
    echo
    
    # Generate configuration using consolidated config module with credential preservation
    # Pass version_tag information for proper image tag configuration
    local use_latest_images="false"
    if [[ "$version_tag" == "latest" || "$version_tag" == "stable" ]]; then
        use_latest_images="true"
    fi
    
    # Set version tag environment variable for config generation
    export MILOU_SELECTED_VERSION="$version_tag"
    
    # DEBUG: show chosen version strategy
    milou_log "DEBUG" "Version selection: tag=$version_tag, use_latest_images=$use_latest_images"
    
    # Acquire GitHub token. It's always needed to pull images, and sometimes to resolve 'latest' tags.
    milou_log "INFO" "🔑 A GitHub token is required to pull images from the registry."

    # Call the core function which contains the detailed prompt. This avoids duplication.
    if ! core_require_github_token "${GITHUB_TOKEN:-}" "true"; then
        milou_log "ERROR" "A valid GitHub token is required to proceed."
        return 1
    fi
    export MILOU_GITHUB_TOKEN="${GITHUB_TOKEN}"
    milou_log "DEBUG" "GitHub token obtained and exported."
    
    # Call with correct positional arguments: quiet flag, preserve_creds, use_latest_images
    if config_generate "$domain" "$email" "$ssl_mode" "false" "$preserve_creds" "false" "$use_latest_images"; then
        milou_log "SUCCESS" "Configuration created successfully"
        
        # Only force container recreation if credentials are NEW (not preserved)
        if [[ "$preserve_creds" == "false" || ("$preserve_creds" == "auto" && "${CREDENTIALS_PRESERVED:-false}" == "false") ]]; then
            milou_log "INFO" "✓ New credentials generated - recreating containers for security"
            # setup_force_container_recreation "false"  # TODO: Implement this function
        else
            milou_log "INFO" "✓ Credentials preserved - keeping existing containers and data"
        fi
        
        return 0
    else
        setup_show_error "Configuration generation failed" "Unable to create configuration files" \
            "Check file permissions in the installation directory" \
            "Verify sufficient disk space is available" \
            "Try running the setup again"
        return 1
    fi
}

# Automated configuration generation
setup_generate_configuration_automated() {
    local preserve_creds="${1:-auto}"
    
    milou_log "INFO" "✓ Automated Configuration Generation"
    
    local domain="${DOMAIN:-localhost}"
    local email="${ADMIN_EMAIL:-admin@localhost}"
    local ssl_mode="${SSL_MODE:-generate}"
    
    # Always resolve concrete versions when using automated mode (latest/stable)
    if config_generate "$domain" "$email" "$ssl_mode" "true" "$preserve_creds" "false" "true"; then
        milou_log "SUCCESS" "✓ Configuration generated successfully"
        
        # Only force container recreation if credentials are NEW (not preserved)
        if [[ "$preserve_creds" == "false" || ("$preserve_creds" == "auto" && "${CREDENTIALS_PRESERVED:-false}" == "false") ]]; then
            milou_log "INFO" "✓ New credentials generated - recreating containers for security"
            # setup_force_container_recreation "false"  # TODO: Implement this function
        else
            milou_log "INFO" "✓ Credentials preserved - keeping existing containers and data"
        fi
        
        return 0
    else
        milou_log "ERROR" "Configuration generation failed"
        return 1
    fi
}

# Smart configuration generation
setup_generate_configuration_smart() {
    local preserve_creds="${1:-auto}"
    
    milou_log "INFO" "✓ Smart Configuration Generation"
    
    # Use environment variables if available, otherwise use smart defaults
    local domain="${DOMAIN:-localhost}"
    local email="${ADMIN_EMAIL:-admin@localhost}"
    local ssl_mode="generate"
    
    # Smart SSL mode selection
    if [[ "$domain" != "localhost" && "$domain" != "127.0.0.1" ]]; then
        ssl_mode="generate"  # Real domain gets certificates
    else
        ssl_mode="generate"  # Development also gets self-signed
    fi
    
    milou_log "INFO" "✓ Smart defaults: domain=$domain, email=$email, ssl=$ssl_mode"
    
    # Smart mode also wants concrete pinned versions
    if config_generate "$domain" "$email" "$ssl_mode" "true" "$preserve_creds" "false" "true"; then
        milou_log "SUCCESS" "✓ Configuration generated successfully"
        
        # Only force container recreation if credentials are NEW (not preserved)
        if [[ "$preserve_creds" == "false" || ("$preserve_creds" == "auto" && "${CREDENTIALS_PRESERVED:-false}" == "false") ]]; then
            milou_log "INFO" "✓ New credentials generated - recreating containers for security"
            # setup_force_container_recreation "false"  # TODO: Implement this function
        else
            milou_log "INFO" "✓ Credentials preserved - keeping existing containers and data"
        fi
        
        return 0
    else
        milou_log "ERROR" "Configuration generation failed"
        return 1
    fi
}

# =============================================================================
# VALIDATION AND SERVICE STARTUP FUNCTIONS
# =============================================================================

# Validate configuration and start services - SINGLE AUTHORITATIVE IMPLEMENTATION
setup_validate_and_start_services() {
    milou_log "STEP" "Step 7: Final Validation and Service Startup"
    
    # Validate system readiness
    if ! setup_validate_system_readiness; then
        milou_log "ERROR" "System readiness validation failed"
        return 1
    fi
    
    # Setup SSL certificates if needed
    if ! setup_configure_ssl; then
        milou_log "ERROR" "SSL configuration failed"
        return 1
    fi
    
    # Prepare Docker environment
    if ! setup_prepare_docker_environment; then
        milou_log "ERROR" "Docker environment preparation failed"
        return 1
    fi
    
    # Start services
    if ! setup_start_services; then
        milou_log "ERROR" "Service startup failed"
        return 1
    fi
    
    # Validate service health
    if ! setup_validate_service_health; then
        milou_log "WARN" "Service health validation completed with warnings"
    fi
    
    milou_log "SUCCESS" "✓ Services started and validated"
    return 0
}

# Validate system readiness
setup_validate_system_readiness() {
    milou_log "INFO" "✓ Validating system readiness..."
    
    local errors=0
    
    # Check configuration file exists
    if [[ ! -f "${SCRIPT_DIR:-$(pwd)}/.env" ]]; then
        milou_log "ERROR" "Configuration file not found"
        ((errors++))
    fi
    
    # Validate configuration using consolidated config module
    if ! config_validate "${SCRIPT_DIR:-$(pwd)}/.env" "production" "true"; then
        milou_log "ERROR" "Configuration validation failed"
        ((errors++))
    fi
    
    # Check Docker access
    if ! validate_system_dependencies "basic" "unknown" "false"; then
        milou_log "ERROR" "Docker validation failed"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        milou_log "SUCCESS" "✓ System readiness validated"
        return 0
    else
        milou_log "ERROR" "System readiness validation failed ($errors errors)"
        return 1
    fi
}

# Configure SSL certificates
setup_configure_ssl() {
    milou_log "INFO" "✓ Setting up SSL certificates..."
    
    # Load environment variables
    if [[ -f "${SCRIPT_DIR:-$(pwd)}/.env" ]]; then
        source "${SCRIPT_DIR:-$(pwd)}/.env"
    fi
    
    local ssl_mode="${SSL_MODE:-generate}"
    local domain="${DOMAIN:-localhost}"
    
    # Load SSL module if not already loaded
    if [[ "${MILOU_SSL_LOADED:-}" != "true" ]]; then
        local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        source "${script_dir}/_ssl.sh" || {
            milou_log "ERROR" "Cannot load SSL module"
            return 1
        }
    fi
    
    case "$ssl_mode" in
        "generate")
            milou_log "INFO" "✓ Generating self-signed SSL certificates..."
            # Use SSL module for proper certificate generation
            if command -v ssl_generate_self_signed >/dev/null 2>&1; then
                ssl_generate_self_signed "$domain" "false" "false"
            else
                setup_generate_basic_ssl_certificates "$domain"
            fi
            ;;
        "existing")
            milou_log "INFO" "✓ Setting up existing SSL certificates..."
            # Use the certificate source collected during interactive setup
            local cert_source="${MILOU_SSL_CERT_SOURCE:-}"
            
            if [[ -z "$cert_source" ]]; then
                milou_log "ERROR" "No certificate source specified for existing SSL mode"
                return 1
            fi
            
            # Use SSL module for existing certificate setup
            if command -v ssl_setup_existing >/dev/null 2>&1; then
                ssl_setup_existing "$domain" "$cert_source" "false" "false"
            else
                setup_copy_existing_certificates "$domain" "$cert_source"
            fi
            ;;
        "none")
            milou_log "INFO" "✓ SSL disabled - using HTTP only"
            return 0
            ;;
        *)
            milou_log "WARN" "Unknown SSL mode: $ssl_mode, defaulting to generate"
            setup_generate_basic_ssl_certificates "$domain"
            ;;
    esac
    
    milou_log "SUCCESS" "✓ SSL configuration completed"
    return 0
}

# Generate basic SSL certificates (fallback)
setup_generate_basic_ssl_certificates() {
    local domain="$1"
    local ssl_dir="${SCRIPT_DIR:-$(pwd)}/ssl"
    
    ensure_directory "$ssl_dir" "755"
    
    # Generate self-signed certificate
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$ssl_dir/milou.key" \
        -out "$ssl_dir/milou.crt" \
        -subj "/C=US/ST=State/L=City/O=Organization/OU=OrgUnit/CN=$domain" \
        -extensions v3_req \
        -config <(cat <<EOF
[req]
distinguished_name = req
[v3_req]
subjectAltName = @alt_names
[alt_names]
DNS.1 = $domain
DNS.2 = localhost
DNS.3 = *.localhost
IP.1 = 127.0.0.1
IP.2 = ::1
EOF
    ) 2>/dev/null
    
    chmod 600 "$ssl_dir/milou.key"
    chmod 644 "$ssl_dir/milou.crt"
    
    milou_log "SUCCESS" "✓ Self-signed SSL certificates generated"
}

# Copy existing certificates to Milou SSL directory
setup_copy_existing_certificates() {
    local domain="$1"
    local cert_source="$2"
    local ssl_dir="${SCRIPT_DIR:-$(pwd)}/ssl"
    
    # Normalize cert_source path to remove trailing slashes and fix double slash issue
    cert_source="${cert_source%/}"
    
    # Expand tilde if present
    cert_source="${cert_source/#\~/$HOME}"
    
    milou_log "INFO" "📂 Copying certificates from: $cert_source"
    
    # Create SSL directory
    ensure_directory "$ssl_dir" "755"
    
    # Backup existing certificates if they exist
    if [[ -f "$ssl_dir/milou.crt" || -f "$ssl_dir/milou.key" ]]; then
        local backup_dir="$ssl_dir/backup"
        ensure_directory "$backup_dir" "755"
        local timestamp=$(date +%Y%m%d_%H%M%S)
        
        [[ -f "$ssl_dir/milou.crt" ]] && cp "$ssl_dir/milou.crt" "$backup_dir/milou.crt.$timestamp"
        [[ -f "$ssl_dir/milou.key" ]] && cp "$ssl_dir/milou.key" "$backup_dir/milou.key.$timestamp"
        milou_log "INFO" "✓ Backed up existing certificates"
    fi
    
    # Try to detect and copy certificate files based on common patterns
    local cert_file=""
    local key_file=""
    local found_format=""
    
    # Pattern 1: Let's Encrypt format (fullchain.pem + privkey.pem)
    if [[ -f "$cert_source/fullchain.pem" && -f "$cert_source/privkey.pem" ]]; then
        cert_file="$cert_source/fullchain.pem"
        key_file="$cert_source/privkey.pem"
        found_format="Let's Encrypt"
    
    # Pattern 2: Standard PEM format (certificate.pem + private-key.pem or similar)
    elif [[ -f "$cert_source/certificate.pem" && -f "$cert_source/private-key.pem" ]]; then
        cert_file="$cert_source/certificate.pem"
        key_file="$cert_source/private-key.pem"
        found_format="PEM"
    elif [[ -f "$cert_source/cert.pem" && -f "$cert_source/key.pem" ]]; then
        cert_file="$cert_source/cert.pem"
        key_file="$cert_source/key.pem"
        found_format="PEM"
    
    # Pattern 3: Standard CRT format (certificate.crt + private-key.key or similar)
    elif [[ -f "$cert_source/certificate.crt" && -f "$cert_source/private-key.key" ]]; then
        cert_file="$cert_source/certificate.crt"
        key_file="$cert_source/private-key.key"
        found_format="CRT/KEY"
    elif [[ -f "$cert_source/$domain.crt" && -f "$cert_source/$domain.key" ]]; then
        cert_file="$cert_source/$domain.crt"
        key_file="$cert_source/$domain.key"
        found_format="Domain-named CRT/KEY"
    
    # Pattern 4: Generic patterns - find any .crt/.pem with corresponding .key
    else
        # Look for any certificate file
        local cert_candidates=($(ls "$cert_source"/*.{crt,pem} 2>/dev/null | grep -v key || true))
        local key_candidates=($(ls "$cert_source"/*.{key,pem} 2>/dev/null | grep -E "(key|private)" || true))
        
        if [[ ${#cert_candidates[@]} -gt 0 && ${#key_candidates[@]} -gt 0 ]]; then
            cert_file="${cert_candidates[0]}"
            key_file="${key_candidates[0]}"
            found_format="Auto-detected"
        fi
    fi
    
    # If we found certificate files, copy them
    if [[ -n "$cert_file" && -n "$key_file" ]]; then
        milou_log "INFO" "✓ Found $found_format format certificates"
        milou_log "INFO" "  Certificate: $(basename "$cert_file")"
        milou_log "INFO" "  Private Key: $(basename "$key_file")"
        
        # Copy and set permissions
        if cp "$cert_file" "$ssl_dir/milou.crt" && cp "$key_file" "$ssl_dir/milou.key"; then
            chmod 644 "$ssl_dir/milou.crt"
            chmod 600 "$ssl_dir/milou.key"
            
            # Validate the certificates
            if openssl x509 -in "$ssl_dir/milou.crt" -noout -text >/dev/null 2>&1; then
                milou_log "SUCCESS" "✓ SSL certificates successfully copied and validated"
                
                # Show certificate info
                local cert_subject=$(openssl x509 -in "$ssl_dir/milou.crt" -noout -subject 2>/dev/null | cut -d= -f2- || echo "Unknown")
                local cert_expires=$(openssl x509 -in "$ssl_dir/milou.crt" -noout -enddate 2>/dev/null | cut -d= -f2 || echo "Unknown")
                milou_log "INFO" "  Subject: $cert_subject"
                milou_log "INFO" "  Expires: $cert_expires"
                
                return 0
            else
                milou_log "ERROR" "Certificate validation failed - invalid certificate format"
                return 1
            fi
        else
            milou_log "ERROR" "Failed to copy certificate files"
            return 1
        fi
    else
        milou_log "ERROR" "Could not find valid certificate files in: $cert_source"
        milou_log "INFO" "Expected formats:"
        milou_log "INFO" "  • fullchain.pem + privkey.pem (Let's Encrypt)"
        milou_log "INFO" "  • certificate.pem + private-key.pem"
        milou_log "INFO" "  • certificate.crt + private-key.key"
        milou_log "INFO" "  • $domain.crt + $domain.key"
        
        # List what we actually found
        milou_log "INFO" "Files in directory:"
        ls -la "$cert_source" | grep -E '\.(crt|key|pem|p12|pfx)$' | sed 's/^/    /' || true
        
        return 1
    fi
}

# Prepare Docker environment
setup_prepare_docker_environment() {
    milou_log "INFO" "✓ Preparing Docker environment..."
    
    # Networks will be created by Docker Compose - no need for manual creation
    milou_log "DEBUG" "Networks will be created by Docker Compose automatically"
    
    # Use Docker module if available
    if command -v docker_init >/dev/null 2>&1; then
        docker_init
    else
        milou_log "DEBUG" "Docker module not available, networks will be created by compose"
    fi
    
    # ------------------------------------------------------------------
    # Pin mutable image tags (latest/stable) once we have a valid
    # GitHub token – this guarantees concrete versions are recorded in
    # the .env BEFORE the first docker-compose pull so that future
    # update checks work reliably.
    # ------------------------------------------------------------------
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        local _env_file="${MILOU_ENV_FILE:-${SCRIPT_DIR}/.env}"
        if grep -Eq "^MILOU_(BACKEND|FRONTEND|ENGINE|DATABASE|NGINX)_TAG=(latest|stable)$" "$_env_file" 2>/dev/null; then
            milou_log "INFO" "📌 Resolving mutable image tags to concrete versions..."
            if config_resolve_mutable_tags "$_env_file" "$GITHUB_TOKEN" "false"; then
                milou_log "SUCCESS" "✓ Image tags pinned successfully"
            else
                milou_log "WARN" "⚠️  Failed to resolve image tags – proceeding with existing values"
            fi
        fi
    fi

    milou_log "SUCCESS" "✓ Docker environment prepared"
    return 0
}

# Start services
setup_start_services() {
    milou_log "INFO" "✓ Starting Milou services..."

    # The complex logic for token handling and intelligent pulling has been
    # simplified and moved. For repair mode, login is handled earlier.
    # For interactive mode, the user is prompted.
    # We now directly proceed to starting the services, and docker-compose
    # will handle pulling images if they are not present locally.

    # --- CHANGED: Run initial database migration using dedicated service ---
    milou_log "INFO" "⚙️  Running initial database migrations..."

    # Run the migrations service. It will bring up dependencies (db)
    # and run the migration, then exit. The `--abort-on-container-exit` flag
    # ensures that compose exits when the one-off migration task is done.
    if ! docker_compose up database-migrations --remove-orphans --abort-on-container-exit --exit-code-from database-migrations; then
        milou_log "ERROR" "❌ Database migration failed. Setup cannot continue."
        milou_log "INFO" "💡 Check the logs above for migration errors."
        milou_log "INFO" "💡 You may need to clean the installation with './milou.sh setup --clean' and try again."
        return 1
    fi
    milou_log "SUCCESS" "✅ Database migrations completed successfully."

    # --- ADDED: Clean up migration service and its dependencies ---
    # This brings down the services that were only started for the migration.
    milou_log "INFO" "✓ Stopping migration-related containers..."
    if ! docker_compose down; then
        milou_log "WARN" "Could not stop migration containers cleanly, but proceeding."
    fi

    milou_log "INFO" "▶️  Starting all services..."
    local result_output
    result_output=$(docker_compose up -d --remove-orphans 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        milou_log "SUCCESS" "✓ Services started successfully"

        # Wait for services to be ready
        milou_log "INFO" "✓ Waiting for services to initialize..."
        sleep 10
        
        return 0
    else
        milou_log "ERROR" "❌ Failed to start services with docker-compose."
        docker_handle_startup_error "$result_output" "" "false"
        return 1
    fi
}

# Validate service health
setup_validate_service_health() {
    milou_log "INFO" "✓ Validating service health..."
    
    local healthy_services=0
    local total_services=0
    local max_wait=60
    local elapsed=0
    
    while [[ $elapsed -lt $max_wait ]]; do
        healthy_services=0
        total_services=0
        
        # Check container status
        while IFS=$'\t' read -r name status; do
            ((total_services++))
            if [[ "$status" =~ "Up" ]] || [[ "$status" =~ "running" ]]; then
                ((healthy_services++))
            fi
        done < <(docker compose ps --format "{{.Name}}\t{{.Status}}" 2>/dev/null || echo "")
        
        if [[ $healthy_services -gt 0 && $healthy_services -eq $total_services ]]; then
            milou_log "SUCCESS" "✓ All services healthy ($healthy_services/$total_services)"
            return 0
        fi
        
        milou_log "DEBUG" "Services status: $healthy_services/$total_services healthy"
        sleep 5
        elapsed=$((elapsed + 5))
    done
    
    if [[ $healthy_services -gt 0 ]]; then
        milou_log "WARN" "✓ Partial service health: $healthy_services/$total_services healthy"
        return 0
    else
        milou_log "ERROR" "✓ Service health validation failed"
        return 1
    fi
}

# =============================================================================
# COMPLETION AND REPORTING FUNCTIONS
# =============================================================================

# Display setup completion report - SINGLE AUTHORITATIVE IMPLEMENTATION
setup_display_completion_report() {
    # Show enhanced success message using our new functions
    local domain="${DOMAIN:-localhost}"
    local admin_user="${ADMIN_USERNAME:-admin}"
    local admin_password="${ADMIN_PASSWORD:-[check .env file]}"
    local admin_email="${ADMIN_EMAIL:-admin@localhost}"
    
    # Load configuration for display
    if [[ -f "${SCRIPT_DIR:-$(pwd)}/.env" ]]; then
        source "${SCRIPT_DIR:-$(pwd)}/.env"
        admin_password="${ADMIN_PASSWORD:-[check .env file]}"
    fi
    
    # Use our enhanced success display function
    setup_show_success "$domain" "$admin_user" "$admin_password" "$admin_email"
    
    return 0
}

# =============================================================================
# LEGACY ALIASES FOR BACKWARDS COMPATIBILITY
# =============================================================================

# Main setup command handler with options parsing
handle_setup_modular() {
    local force="false"
    local mode="auto"
    local skip_validation="false"
    local preserve_creds="auto"
    local clean="false"
    local fix_credentials="false"
    local github_token=""
    local from_installer="false"
    
    # Parse command line options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force|-f)
                force="true"
                shift
                ;;
            --clean)
                clean="true"
                shift
                ;;
            --fix-credentials|--fix-creds)
                fix_credentials="true"
                mode="repair"  # Use repair mode for credential fixes
                shift
                ;;
            --repair)
                mode="repair"
                preserve_creds="true"  # Always preserve credentials in repair mode
                shift
                ;;
            --from-installer)
                from_installer="true"
                shift
                ;;
            --preserve-creds|--preserve-credentials)
                preserve_creds="true"
                shift
                ;;
            --new-creds|--new-credentials|--force-new-creds)
                preserve_creds="false"
                shift
                ;;
            --interactive|-i)
                mode="interactive"
                shift
                ;;
            --automated|--auto|-a)
                mode="automated"
                shift
                ;;
            --smart|-s)
                mode="smart"
                shift
                ;;
            --skip-validation)
                skip_validation="true"
                shift
                ;;
            --dev|--development)
                mode="interactive"
                export MILOU_DEV_MODE=1
                shift
                ;;
            --token)
                github_token="$2"
                shift 2
                ;;
            --help|-h)
                show_setup_help
                return 0
                ;;
            *)
                milou_log "WARN" "Unknown setup option: $1"
                shift
                ;;
        esac
    done
    
    # Set GitHub token if provided via command line
    if [[ -n "$github_token" ]]; then
        export GITHUB_TOKEN="$github_token"
        milou_log "INFO" "✓ GitHub token provided via command line"
    fi
    
    # ------------------------------------------------------------------
    # Safety fallback: If repair mode was selected automatically but the
    # .env file (configuration) is missing, the repair workflow cannot
    # proceed. In that situation we transparently fall back to the
    # interactive setup wizard instead of exiting with an error.
    # ------------------------------------------------------------------
    if [[ "$mode" == "repair" ]]; then
        local env_candidate="${MILOU_ENV_FILE:-${SCRIPT_DIR}/.env}"
        if [[ ! -f "$env_candidate" ]]; then
            milou_log "WARN" "Repair mode requested but no .env file found ($env_candidate). Falling back to interactive setup."
            mode="interactive"
        fi
    fi
    
    # Handle credential fix first
    if [[ "$fix_credentials" == "true" ]]; then
        milou_log "STEP" "🔧 Fixing Credential Mismatch"
        echo ""
        echo "🔍 CREDENTIAL MISMATCH FIX"
        echo "==========================="
        echo ""
        echo "This will detect and fix database credential mismatches."
        echo "Common after deleting milou-cli directory and setting up again."
        echo ""
        
        # Source Docker module to access credential functions
        source "${SCRIPT_DIR}/src/_docker.sh" || {
            milou_log "ERROR" "Failed to load Docker module"
            return 1
        }
        
        # Initialize Docker environment
        if ! docker_init "" "" "false" "true"; then
            milou_log "ERROR" "Failed to initialize Docker environment"
            return 1
        fi
        
        # Detect and resolve credential mismatch
        if detect_credential_mismatch "false"; then
            milou_log "INFO" "🔧 Credential mismatch detected - resolving automatically"
            if resolve_credential_mismatch "false" "false"; then
                milou_log "SUCCESS" "✅ Credential mismatch resolved successfully!"
                echo ""
                echo "🎉 FIXED! You can now start services:"
                echo "   ./milou.sh start"
                echo ""
                return 0
            else
                milou_log "ERROR" "❌ Failed to resolve credential mismatch"
                return 1
            fi
        else
            milou_log "SUCCESS" "✅ No credential mismatch detected - system looks good!"
            echo ""
            echo "💡 Your system appears to be healthy. If you're still having issues:"
            echo "   • Check logs: ./milou.sh logs"
            echo "   • Try starting: ./milou.sh start"
            echo "   • Run full setup: ./milou.sh setup"
            echo ""
            return 0
        fi
    fi
    
    # Handle clean install first
    if [[ "$clean" == "true" ]]; then
        milou_log "STEP" "✓ Clean Installation Requested"
        echo ""
        echo "✓  ✓ WARNING: CLEAN INSTALL WILL DELETE ALL DATA! ✓"
        echo "==============================================="
        echo ""
        echo "This will PERMANENTLY DELETE:"
        echo "  ✓  All database data"
        echo "  ✓ All SSL certificates"
        echo "  ✓  All configuration files"
        echo "  ✓ All Docker volumes and containers"
        echo "  ✓ All backup files"
        echo ""
        
        if ! confirm "Are you ABSOLUTELY SURE you want to delete ALL data?" "N"; then
            milou_log "INFO" "Clean install cancelled - wise choice!"
            return 0
        fi
        
        # Force container recreation with volume cleanup
        # setup_force_container_recreation "false"  # TODO: Implement this function
        
        # Remove configuration files
        rm -f "${SCRIPT_DIR:-$(pwd)}/.env"
        rm -rf "${SCRIPT_DIR:-$(pwd)}/ssl"
        
        milou_log "SUCCESS" "✓ Clean install preparation completed"
        echo ""
        
        # Force new credentials for clean install
        preserve_creds="false"
    fi
    
    # Run main setup with parsed options
    setup_run "$force" "$mode" "$skip_validation" "$preserve_creds" "$from_installer"
}

# Show setup help
show_setup_help() {
    echo "✓ Milou CLI Setup Command"
    echo "=========================="
    echo ""
    echo "USAGE:"
    echo "  ./milou.sh setup [OPTIONS]"
    echo ""
    echo "SETUP MODES:"
    echo "  --interactive, -i      Interactive setup wizard (default)"
    echo "  --automated, --auto, -a Automated setup using environment variables"
    echo "  --smart, -s            Smart setup with minimal prompts"
    echo "  --repair               Repair broken installation (preserves credentials)"
    echo ""
    echo "AUTHENTICATION:"
    echo "  --token TOKEN          GitHub Personal Access Token for private images"
    echo ""
    echo "CREDENTIAL OPTIONS:"
    echo "  --preserve-creds       Preserve existing credentials (recommended for updates)"
    echo "  --new-creds            Generate new credentials (⚠️  may affect data access)"
    echo "  --force-new-creds      Force new credentials even on existing installations"
    echo ""
    echo "INSTALLATION OPTIONS:"
    echo "  --clean               Clean install - DELETE ALL EXISTING DATA"
    echo "  --fix-credentials     Fix database credential mismatches (common after fresh setup)"
    echo "  --force, -f           Skip confirmation prompts"
    echo "  --dev, --development  Development mode setup"
    echo ""
    echo "ADVANCED OPTIONS:"
    echo "  --skip-validation     Skip final validation and service startup"
    echo "  --help, -h            Show this help"
    echo ""
    echo "EXAMPLES:"
    echo "  ./milou.sh setup --token ghp_your_token_here    # Setup with GitHub token"
    echo "  ./milou.sh setup                                # Smart setup (preserves credentials automatically)"
    echo "  ./milou.sh setup --automated                    # Automated setup using environment variables"
    echo "  ./milou.sh setup --preserve-creds               # Explicitly preserve existing credentials"
    echo "  ./milou.sh setup --fix-credentials              # Fix database credential mismatches"
    echo "  ./milou.sh setup --force-new-creds              # Generate new credentials (⚠️  affects data)"
    echo "  ./milou.sh setup --clean                        # Clean install (⚠️  deletes all data)"
    echo ""
    echo "🔒 INTELLIGENT CREDENTIAL MANAGEMENT:"
    echo "  ✅ EXISTING INSTALLATION: Credentials preserved automatically (safe default)"
    echo "  ✅ FRESH INSTALLATION: New credentials generated securely"
    echo "  ⚠️  OVERRIDE: Use --force-new-creds to force new credentials (may break data access)"
    echo "  💡 TIP: The system automatically detects your situation and chooses the safest option"
    echo ""
    echo "For more information, see: docs/USER_GUIDE.md"
}

# =============================================================================
# EXPORT ESSENTIAL FUNCTIONS ONLY
# =============================================================================

# Main setup functions
export -f handle_setup_modular
export -f show_setup_help

# Setup orchestration functions
export -f _setup_validate_system
export -f _setup_interactive_configuration
export -f _setup_handle_github_and_deployment
export -f _setup_finalize_and_display_credentials

# make sanitize helper available to subshells
export -f sanitize_env_file

milou_log "DEBUG" "Setup module loaded successfully" 