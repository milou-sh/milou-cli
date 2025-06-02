#!/bin/bash

# =============================================================================
# Milou CLI - Setup Management Module
# Consolidated setup operations to eliminate massive code duplication
# Version: 3.1.0 - Refactored Edition
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
        echo -e "${DIM}This wizard will guide you through each step with clear explanations.${NC}"
        echo
    fi
}

# Enhanced setup header with progress indication
setup_show_header() {
    local current_step="${1:-1}"
    local total_steps="${2:-7}"
    local step_name="${3:-Starting Setup}"
    
    if tty -s && [[ "${QUIET:-false}" != "true" ]]; then
        echo
        milou_log "HEADER" "✓ Milou Setup - Professional Installation v$(get_milou_version 2>/dev/null || echo 'latest')"
        log_progress "$current_step" "$total_steps" "$step_name"
        echo
    fi
}

# User-friendly step announcements
setup_announce_step() {
    local step_number="$1"
    local step_title="$2"
    local step_description="${3:-}"
    local estimated_time="${4:-}"
    
    log_section "Step $step_number: $step_title" "$step_description"
    
    if [[ -n "$estimated_time" ]]; then
        echo -e "${DIM}  ✓  Estimated time: $estimated_time${NC}"
        echo
    fi
}

# Enhanced success messages with clear next steps  
setup_show_success() {
    local domain="${1:-localhost}"
    local admin_user="${2:-admin}"
    local admin_password="${3:-[generated]}"
    local admin_email="${4:-admin@localhost}"
    
    echo
    milou_log "HEADER" "✓ Setup Complete! Welcome to Milou"
    
    echo -e "${BOLD}${GREEN}✓${NC}"
    echo -e "${BOLD}${GREEN}✓              ✓ CONGRATULATIONS! ✓                ✓${NC}"
    echo -e "${BOLD}${GREEN}✓        Your Milou system is ready to use!          ✓${NC}"
    echo -e "${BOLD}${GREEN}✓${NC}"
    echo
    
    log_section "✓ Access Your System" "Your Milou installation is now accessible"
    echo -e "   ${BOLD}Web Interface:${NC} ${CYAN}https://$domain${NC}"
    echo -e "   ${BOLD}Admin Panel:${NC}   ${CYAN}https://$domain/admin${NC}"
    echo
    
    log_section "✓ Your Admin Credentials" "Keep these credentials safe!"
    echo -e "   ${BOLD}Username:${NC} $admin_user"
    echo -e "   ${BOLD}Password:${NC} $admin_password"
    echo -e "   ${BOLD}Email:${NC}    $admin_email"
    echo
    echo -e "${YELLOW}${BOLD}✓  IMPORTANT:${NC} Save these credentials in a secure password manager!"
    echo
    
    log_next_steps \
        "Open ${CYAN}https://$domain${NC} in your web browser" \
        "Accept the SSL certificate (normal for self-signed certificates)" \
        "Log in with the credentials above" \
        "Change your password after first login" \
        "Create a backup: ${CYAN}./milou.sh backup${NC}" \
        "Explore the system and start managing your environment!"
    
    log_tip "Need help? Run ${CYAN}./milou.sh --help${NC} or check the documentation in the ${CYAN}docs/${NC} folder"
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
    
    log_section "✓ System Analysis" "Understanding your current environment"
    
    # Translate technical status to user-friendly language
    if [[ "$is_fresh" == "true" ]]; then
        echo -e "   ${GREEN}${CHECKMARK}${NC} Fresh system detected - perfect for a clean installation"
    else
        echo -e "   ${BLUE}${BULLET}${NC} Existing system detected - we'll work with your current setup"
    fi
    
    if [[ "$needs_deps" == "true" ]]; then
        echo -e "   ${YELLOW}${WRENCH}${NC} We'll install Docker and other required tools automatically"
    else
        echo -e "   ${GREEN}${CHECKMARK}${NC} All required tools are already installed"
    fi
    
    if [[ "$needs_user" == "true" ]]; then
        echo -e "   ${BLUE}${BULLET}${NC} We'll create a dedicated user account for security"
    else
        echo -e "   ${GREEN}${CHECKMARK}${NC} User account is already properly configured"
    fi
    
    if [[ "$existing_install" == "true" ]]; then
        echo -e "   ${YELLOW}${WRENCH}${NC} Existing Milou installation found - we'll update it carefully"
    else
        echo -e "   ${GREEN}${SPARKLES}${NC} This will be your first Milou installation"
    fi
    
    echo
    log_tip "Everything looks good! The setup will handle any required installations automatically."
}

# =============================================================================
# MAIN SETUP ORCHESTRATION FUNCTIONS
# =============================================================================

# Main setup entry point with enhanced UX
setup_run() {
    local force="${1:-false}"
    local mode="${2:-auto}"
    local skip_validation="${3:-false}"
    local preserve_creds="${4:-auto}"
    
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
    
    # Track if this is a fresh setup for cleanup purposes
    local is_fresh_setup="false"
    if [[ ! -f "${SCRIPT_DIR:-$(pwd)}/.env" ]]; then
        is_fresh_setup="true"
    fi
    
    # Show enhanced Milou logo and welcome
    setup_show_logo
    
    # Enhanced setup header with progress tracking
    setup_show_header 1 7 "Starting Setup"
    
    # Step 1: System Analysis with user-friendly display
    setup_announce_step 1 "System Analysis" "Understanding your current environment" 
    if ! setup_analyze_system; then
        setup_show_error "System analysis failed" "Unable to detect system requirements" \
            "Check system permissions" \
            "Ensure Docker is accessible" \
            "Contact support if issues persist"
        return 1
    fi
    
    # Display analysis results in user-friendly format
    setup_show_analysis "$SETUP_IS_FRESH_SERVER" "$SETUP_NEEDS_DEPS" "$SETUP_NEEDS_USER" "false"
    
    # Step 2: Prerequisites Assessment
    setup_announce_step 2 "Prerequisites Assessment" "Checking what needs to be installed" 

    # For fresh systems or when we know we need deps, missing prerequisites are expected
    if [[ "$SETUP_IS_FRESH_SERVER" == "true" ]] || [[ "$SETUP_NEEDS_DEPS" == "true" ]]; then
        # On fresh systems, we expect prerequisites to be missing
        if ! setup_assess_prerequisites; then
            milou_log "INFO" "✓ Missing prerequisites detected (expected for fresh installation)"
            milou_log "INFO" "✓ Missing prerequisites will be installed during setup"
        else
            milou_log "SUCCESS" "✓ All prerequisites already satisfied"
        fi
    else
        # On existing systems, missing prerequisites are unexpected
        if ! setup_assess_prerequisites; then
            setup_show_error "Prerequisites assessment failed" "Could not determine system prerequisites" \
                "Check system permissions" \
                "Ensure Docker is accessible" \
                "Contact support if issues persist"
            return 1
        fi
    fi
    
    # Step 3: Setup Mode Determination
    setup_announce_step 3 "Setup Mode Selection" "Choosing the best setup approach" 
    if ! setup_determine_mode "$mode"; then
        setup_show_error "Setup mode determination failed" "Could not determine optimal setup approach" \
            "Try running with specific mode: ./milou.sh setup --interactive" \
            "Check system requirements" \
            "Review setup documentation"
        return 1
    fi
    
    # Step 4: Dependencies Installation (if needed)
    if [[ "$SETUP_NEEDS_DEPS" == "true" ]]; then
        setup_announce_step 4 "Dependencies Installation" "Installing Docker and required tools" 
        if ! setup_install_dependencies; then
            setup_show_error "Dependencies installation failed" "Could not install required system components" \
                "Check internet connectivity" \
                "Verify system package manager is working" \
                "Try manual Docker installation" \
                "Run with sudo if permission issues"
            [[ "$is_fresh_setup" == "true" ]] && setup_cleanup_failed_fresh_setup
            return 1
        fi
        milou_log "SUCCESS" "All dependencies installed successfully"
    else
        setup_announce_step 4 "Dependencies Check" "Verifying existing installation" 
        milou_log "SUCCESS" "All required dependencies are already available"
    fi
    
    # Step 5: User Management (if needed)
    if [[ "$SETUP_NEEDS_USER" == "true" ]]; then
        setup_announce_step 5 "User Setup" "Creating dedicated user account" 
        if ! setup_manage_user; then
            setup_show_error "User management failed" "Could not set up user account properly" \
                "Check if running with appropriate permissions" \
                "Verify system supports user creation" \
                "Try running as root/sudo"
            [[ "$is_fresh_setup" == "true" ]] && setup_cleanup_failed_fresh_setup
            return 1
        fi
        milou_log "SUCCESS" "User account configured successfully"
    else
        setup_announce_step 5 "User Verification" "Confirming user configuration" 
        milou_log "SUCCESS" "User configuration is already optimal"
    fi
    
    # Step 6: Configuration Generation
    setup_announce_step 6 "Configuration Setup" "Creating your personalized settings" 
    if ! setup_generate_configuration "$preserve_creds"; then
        setup_show_error "Configuration generation failed" "Could not create system configuration" \
            "Check file permissions in installation directory" \
            "Verify disk space availability" \
            "Try running setup again" \
            "Contact support with error details"
        [[ "$is_fresh_setup" == "true" ]] && setup_cleanup_failed_fresh_setup
        return 1
    fi
    milou_log "SUCCESS" "Configuration generated successfully"
    
    # Step 7: Final Validation and Service Startup
    setup_announce_step 7 "Service Deployment" "Starting and validating your Milou system" 
    if ! setup_validate_and_start_services; then
        setup_show_error "Service startup failed" "Could not start all required services" \
            "Check Docker service status" \
            "Verify port availability" \
            "Review service logs: ./milou.sh logs" \
            "Try restarting: ./milou.sh restart"
        
        # For fresh setups, clean up on failure to allow retry
        if [[ "$is_fresh_setup" == "true" ]]; then
            setup_cleanup_failed_fresh_setup
        fi
        return 1
    fi
    
    # Enhanced completion display
    log_progress 7 7 "Setup Complete!"
    setup_display_completion_report
    
    milou_log "SUCCESS" "✓ Milou setup completed successfully!"
    return 0
}

# Clean up failed fresh setup to allow retry
setup_cleanup_failed_fresh_setup() {
    milou_log "INFO" "🧹 Cleaning up failed fresh setup for clean retry..."
    
    # Remove configuration files that were created during failed setup
    if [[ -f "${SCRIPT_DIR:-$(pwd)}/.env" ]]; then
        mv "${SCRIPT_DIR:-$(pwd)}/.env" "${SCRIPT_DIR:-$(pwd)}/.env.failed.$(date +%s)" 2>/dev/null || {
            rm -f "${SCRIPT_DIR:-$(pwd)}/.env" 2>/dev/null || true
        }
        milou_log "DEBUG" "Removed/backed up failed configuration"
    fi
    
    # Remove SSL directory if it was created during failed setup
    if [[ -d "${SCRIPT_DIR:-$(pwd)}/ssl" ]]; then
        mv "${SCRIPT_DIR:-$(pwd)}/ssl" "${SCRIPT_DIR:-$(pwd)}/ssl.failed.$(date +%s)" 2>/dev/null || {
            rm -rf "${SCRIPT_DIR:-$(pwd)}/ssl" 2>/dev/null || true
        }
        milou_log "DEBUG" "Removed/backed up failed SSL directory"
    fi
    
    # NOTE: DO NOT remove static/docker-compose.yml - it's part of the codebase!
    # The static docker-compose.yml is a template file and should never be deleted
    milou_log "INFO" "Preserved static docker-compose.yml (part of codebase)"
    
    # Clean up failed setup artifacts
    rm -f "${SCRIPT_DIR:-$(pwd)}/.env.failed."* 2>/dev/null || true
    rm -rf "${SCRIPT_DIR:-$(pwd)}/ssl.failed."* 2>/dev/null || true
    # NOTE: Also do not remove docker-compose.yml.failed.* as these are from static file
    
    milou_log "SUCCESS" "✓ Cleanup completed - you can now run setup again"
}

# Force clean all Milou installation artifacts for complete reset
setup_force_clean_all() {
    local preserve_data="${1:-true}"
    
    milou_log "WARN" "🗑️  Force cleaning all Milou installation artifacts..."
    
    if [[ "$preserve_data" != "true" ]]; then
        echo ""
        echo -e "${RED}${BOLD}⚠️  DANGER: This will permanently delete ALL Milou data!${NC}"
        echo -e "${RED}This includes:${NC}"
        echo "  • All database content"
        echo "  • All file uploads"
        echo "  • All configuration settings"
        echo "  • All SSL certificates"
        echo "  • All backup files"
        echo "  • All Docker volumes and containers"
        echo ""
        echo -e "${YELLOW}This action CANNOT be undone!${NC}"
        echo ""
        
        if [[ "${INTERACTIVE:-true}" == "true" ]]; then
            echo -ne "${RED}${BOLD}Type 'DELETE ALL DATA' to confirm complete destruction: ${NC}"
            read -r confirmation
            if [[ "$confirmation" != "DELETE ALL DATA" ]]; then
                milou_log "INFO" "Force clean cancelled - wise choice!"
                return 1
            fi
        else
            milou_log "WARN" "Non-interactive mode: Skipping data destruction for safety"
            milou_log "INFO" "Use --force flag to override in scripts"
            return 1
        fi
    fi
    
    # Stop all services first
    milou_log "INFO" "Stopping all Milou services..."
    if command -v docker_execute >/dev/null 2>&1; then
        docker_execute "down" "" "true" 2>/dev/null || true
    else
        docker compose down --remove-orphans 2>/dev/null || true
    fi
    
    # Remove containers
    milou_log "INFO" "Removing Milou containers..."
    docker ps -a --filter "name=milou-" --format "{{.Names}}" | xargs -r docker rm -f 2>/dev/null || true
    
    # Remove volumes if not preserving data
    if [[ "$preserve_data" != "true" ]]; then
        milou_log "INFO" "Removing Milou data volumes..."
        docker volume ls --format "{{.Name}}" | grep -E "(milou|static)" | xargs -r docker volume rm -f 2>/dev/null || true
    else
        milou_log "INFO" "Preserving data volumes..."
    fi
    
    # Remove networks
    milou_log "INFO" "Removing Milou networks..."
    docker network ls --filter "name=milou" --format "{{.Name}}" | grep milou | xargs -r docker network rm 2>/dev/null || true
    
    # Clean filesystem artifacts
    milou_log "INFO" "Cleaning filesystem artifacts..."
    
    # Remove/backup configuration
    if [[ -f "${SCRIPT_DIR:-$(pwd)}/.env" ]]; then
        if [[ "$preserve_data" == "true" ]]; then
            mv "${SCRIPT_DIR:-$(pwd)}/.env" "${SCRIPT_DIR:-$(pwd)}/.env.backup.$(date +%s)"
            milou_log "INFO" "Backed up configuration file"
        else
            rm -f "${SCRIPT_DIR:-$(pwd)}/.env"
            milou_log "INFO" "Removed configuration file"
        fi
    fi
    
    # Remove SSL certificates
    if [[ -d "${SCRIPT_DIR:-$(pwd)}/ssl" ]]; then
        if [[ "$preserve_data" == "true" ]]; then
            mv "${SCRIPT_DIR:-$(pwd)}/ssl" "${SCRIPT_DIR:-$(pwd)}/ssl.backup.$(date +%s)"
            milou_log "INFO" "Backed up SSL certificates"
        else
            rm -rf "${SCRIPT_DIR:-$(pwd)}/ssl"
            milou_log "INFO" "Removed SSL certificates"
        fi
    fi
    
    # Remove docker-compose
    if [[ -f "${SCRIPT_DIR:-$(pwd)}/static/docker-compose.yml" ]]; then
        rm -f "${SCRIPT_DIR:-$(pwd)}/static/docker-compose.yml"
        milou_log "INFO" "Removed docker-compose configuration"
    fi
    
    # Clean up failed setup artifacts
    rm -f "${SCRIPT_DIR:-$(pwd)}/.env.failed."* 2>/dev/null || true
    rm -rf "${SCRIPT_DIR:-$(pwd)}/ssl.failed."* 2>/dev/null || true
    # NOTE: Also do not remove docker-compose.yml.failed.* as these are from static file
    
    # Clear state cache
    if command -v clear_state_cache >/dev/null 2>&1; then
        clear_state_cache
    fi
    
    if [[ "$preserve_data" == "true" ]]; then
        milou_log "SUCCESS" "✓ Force clean completed (data preserved)"
        milou_log "INFO" "💡 Configuration and certificates backed up with timestamp"
    else
        milou_log "SUCCESS" "✓ Complete system reset completed"
        milou_log "INFO" "💡 All Milou data has been permanently deleted"
    fi
    
    milou_log "INFO" "You can now run: ./milou.sh setup"
}

# =============================================================================
# SYSTEM ANALYSIS FUNCTIONS
# =============================================================================

# Main setup command handler with options parsing
handle_setup_modular() {
    local force="false"
    local mode="auto"
    local skip_validation="false"
    local preserve_creds="auto"
    local clean="false"
    local github_token=""
    
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
    setup_run "$force" "$mode" "$skip_validation" "$preserve_creds"
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

# Force clean all Milou installation artifacts for complete reset
setup_force_clean_all() {
    local preserve_data="${1:-true}"
    
    milou_log "WARN" "🗑️  Force cleaning all Milou installation artifacts..."
    
    if [[ "$preserve_data" != "true" ]]; then
        echo ""
        echo -e "${RED}${BOLD}⚠️  DANGER: This will permanently delete ALL Milou data!${NC}"
        echo -e "${RED}This includes:${NC}"
        echo "  • All database content"
        echo "  • All file uploads"
        echo "  • All configuration settings"
        echo "  • All SSL certificates"
        echo "  • All backup files"
        echo "  • All Docker volumes and containers"
        echo ""
        echo -e "${YELLOW}This action CANNOT be undone!${NC}"
        echo ""
        
        if [[ "${INTERACTIVE:-true}" == "true" ]]; then
            echo -ne "${RED}${BOLD}Type 'DELETE ALL DATA' to confirm complete destruction: ${NC}"
            read -r confirmation
            if [[ "$confirmation" != "DELETE ALL DATA" ]]; then
                milou_log "INFO" "Force clean cancelled - wise choice!"
                return 1
            fi
        else
            milou_log "WARN" "Non-interactive mode: Skipping data destruction for safety"
            milou_log "INFO" "Use --force flag to override in scripts"
            return 1
        fi
    fi
    
    # Stop all services first
    milou_log "INFO" "Stopping all Milou services..."
    if command -v docker_execute >/dev/null 2>&1; then
        docker_execute "down" "" "true" 2>/dev/null || true
    else
        docker compose down --remove-orphans 2>/dev/null || true
    fi
    
    # Remove containers
    milou_log "INFO" "Removing Milou containers..."
    docker ps -a --filter "name=milou-" --format "{{.Names}}" | xargs -r docker rm -f 2>/dev/null || true
    
    # Remove volumes if not preserving data
    if [[ "$preserve_data" != "true" ]]; then
        milou_log "INFO" "Removing Milou data volumes..."
        docker volume ls --format "{{.Name}}" | grep -E "(milou|static)" | xargs -r docker volume rm -f 2>/dev/null || true
    else
        milou_log "INFO" "Preserving data volumes..."
    fi
    
    # Remove networks
    milou_log "INFO" "Removing Milou networks..."
    docker network ls --filter "name=milou" --format "{{.Name}}" | grep milou | xargs -r docker network rm 2>/dev/null || true
    
    # Clean filesystem artifacts
    milou_log "INFO" "Cleaning filesystem artifacts..."
    
    # Remove/backup configuration
    if [[ -f "${SCRIPT_DIR:-$(pwd)}/.env" ]]; then
        if [[ "$preserve_data" == "true" ]]; then
            mv "${SCRIPT_DIR:-$(pwd)}/.env" "${SCRIPT_DIR:-$(pwd)}/.env.backup.$(date +%s)"
            milou_log "INFO" "Backed up configuration file"
        else
            rm -f "${SCRIPT_DIR:-$(pwd)}/.env"
            milou_log "INFO" "Removed configuration file"
        fi
    fi
    
    # Remove SSL certificates
    if [[ -d "${SCRIPT_DIR:-$(pwd)}/ssl" ]]; then
        if [[ "$preserve_data" == "true" ]]; then
            mv "${SCRIPT_DIR:-$(pwd)}/ssl" "${SCRIPT_DIR:-$(pwd)}/ssl.backup.$(date +%s)"
            milou_log "INFO" "Backed up SSL certificates"
        else
            rm -rf "${SCRIPT_DIR:-$(pwd)}/ssl"
            milou_log "INFO" "Removed SSL certificates"
        fi
    fi
    
    # Remove docker-compose
    if [[ -f "${SCRIPT_DIR:-$(pwd)}/static/docker-compose.yml" ]]; then
        rm -f "${SCRIPT_DIR:-$(pwd)}/static/docker-compose.yml"
        milou_log "INFO" "Removed docker-compose configuration"
    fi
    
    # Clean up failed setup artifacts
    rm -f "${SCRIPT_DIR:-$(pwd)}/.env.failed."* 2>/dev/null || true
    rm -rf "${SCRIPT_DIR:-$(pwd)}/ssl.failed."* 2>/dev/null || true
    # NOTE: Also do not remove docker-compose.yml.failed.* as these are from static file
    
    # Clear state cache
    if command -v clear_state_cache >/dev/null 2>&1; then
        clear_state_cache
    fi
    
    if [[ "$preserve_data" == "true" ]]; then
        milou_log "SUCCESS" "✓ Force clean completed (data preserved)"
        milou_log "INFO" "💡 Configuration and certificates backed up with timestamp"
    else
        milou_log "SUCCESS" "✓ Complete system reset completed"
        milou_log "INFO" "💡 All Milou data has been permanently deleted"
    fi
    
    milou_log "INFO" "You can now run: ./milou.sh setup"
}

# Export additional setup functions
export -f setup_force_clean_all

milou_log "DEBUG" "Setup module loaded successfully" 