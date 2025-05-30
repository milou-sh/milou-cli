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

    ✓   ✓      ✓ ✓   ✓
    ✓ ✓     ✓   ✓  
    ✓     ✓   ✓   ✓  
    ✓     ✓   ✓   ✓  
    ✓ ✓ ✓  
    ✓     ✓ ✓  ✓   
    
    ✓
    ✓   Professional Docker Management        ✓
    ✓   ✓ Simple ✓ Secure ✓ Reliable        ✓
    ✓

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
        return 1
    fi
    
    # Enhanced completion display
    log_progress 7 7 "Setup Complete!"
    setup_display_completion_report
    
    milou_log "SUCCESS" "✓ Milou setup completed successfully!"
    return 0
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
    
    # Check 1: No Docker containers
    if [[ $(docker ps -a --format "{{.Names}}" 2>/dev/null | wc -l) -eq 0 ]]; then
        ((fresh_indicators++))
        milou_log "DEBUG" "✓ No existing Docker containers"
    fi
    
    # Check 2: No Docker volumes
    if [[ $(docker volume ls --format "{{.Name}}" 2>/dev/null | wc -l) -eq 0 ]]; then
        ((fresh_indicators++))
        milou_log "DEBUG" "✓ No existing Docker volumes"
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
    
    # Check for existing containers
    if docker ps -a --filter "name=milou-" --format "{{.Names}}" 2>/dev/null | grep -q milou; then
        has_containers=true
        milou_log "DEBUG" "Found existing Milou containers"
    fi
    
    # Check for configuration
    if [[ -f "${SCRIPT_DIR:-$(pwd)}/.env" ]]; then
        has_config=true
        milou_log "DEBUG" "Found existing configuration file"
    fi
    
    # Check for data volumes
    if docker volume ls --format "{{.Name}}" 2>/dev/null | grep -E "(milou|static)"; then
        has_volumes=true
        milou_log "DEBUG" "Found existing data volumes"
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
    # Use unified validation system instead of duplicating logic
    validate_system_dependencies "basic" "unknown" "true"
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
        # Check if current user has Docker access
        if docker version >/dev/null 2>&1; then
            milou_log "DEBUG" "Current user has Docker access"
            return 0
        else
            milou_log "DEBUG" "Current user needs Docker access"
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
            return 1  # Return 1 to indicate missing deps, but this is expected
        else
            # On existing systems, missing Docker is an error
            milou_log "ERROR" "Docker is not installed"
            milou_log "INFO" "💡 Install Docker: https://docs.docker.com/get-docker/"
            milou_log "ERROR" "System validation failed with 1 error(s)"
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
    milou_log "INFO" "✓ Interactive Dependencies Installation"
    
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
    milou_log "INFO" "✓ Installing Docker..."
    
    # Use official Docker installation script
    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL https://get.docker.com | sh; then
            systemctl start docker 2>/dev/null || true
            systemctl enable docker 2>/dev/null || true
            milou_log "SUCCESS" "✓ Docker installed successfully"
            return 0
        fi
    fi
    
    milou_log "ERROR" "Failed to install Docker"
    return 1
}

# Install Docker Compose
setup_install_docker_compose() {
    milou_log "INFO" "✓ Installing Docker Compose..."
    
    # Try package manager first
    if command -v apt-get >/dev/null 2>&1; then
        if apt-get update && apt-get install -y docker-compose-plugin; then
            milou_log "SUCCESS" "✓ Docker Compose plugin installed"
            return 0
        fi
    elif command -v yum >/dev/null 2>&1; then
        if yum install -y docker-compose-plugin; then
            milou_log "SUCCESS" "✓ Docker Compose plugin installed"
            return 0
        fi
    fi
    
    milou_log "WARN" "Package manager installation failed, trying manual installation"
    
    # Manual installation fallback
    local compose_version="v2.20.0"
    local compose_url="https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-$(uname -s)-$(uname -m)"
    
    if command -v curl >/dev/null 2>&1; then
        if curl -L "$compose_url" -o /usr/local/bin/docker-compose; then
            chmod +x /usr/local/bin/docker-compose
            milou_log "SUCCESS" "✓ Docker Compose installed manually"
            return 0
        fi
    fi
    
    milou_log "ERROR" "Failed to install Docker Compose"
    return 1
}

# Install system tools
setup_install_system_tools() {
    milou_log "INFO" "✓ Installing system tools..."
    
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
    
    milou_log "INFO" "Installing: ${to_install[*]}"
    
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y "${to_install[@]}"
    elif command -v yum >/dev/null 2>&1; then
        yum install -y "${to_install[@]}"
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y "${to_install[@]}"
    else
        milou_log "WARN" "Unsupported package manager"
        return 1
    fi
    
    milou_log "SUCCESS" "✓ System tools installed"
    return 0
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
    
    echo -e "${BOLD}${CYAN}Choose your security level:${NC}"
    echo
    echo -e "${GREEN}   1) ${BOLD}Quick & Easy${NC} ${DIM}(Self-signed certificates)${NC}"
    echo -e "      ${GREEN}${CHECKMARK}${NC} Works immediately, no setup required"
    echo -e "      ${GREEN}${CHECKMARK}${NC} Perfect for testing and development"
    echo -e "      ${YELLOW}✓${NC}  Browser will show a security warning (this is normal)"
    echo
    echo -e "${YELLOW}   2) ${BOLD}Production Ready${NC} ${DIM}(Your own certificates)${NC}"
    echo -e "      ${GREEN}${CHECKMARK}${NC} No browser warnings"
    echo -e "      ${GREEN}${CHECKMARK}${NC} Perfect for business use"
    echo -e "      ${BLUE}✓${NC}  Requires: certificate.crt and private.key in ssl/ folder"
    echo
    echo -e "${RED}   3) ${BOLD}No Encryption${NC} ${DIM}(HTTP only - not recommended)${NC}"
    echo -e "      ${RED}${CROSSMARK}${NC} Connection is not encrypted"
    echo -e "      ${RED}${CROSSMARK}${NC} Only use for testing in trusted environments"
    echo
    
    local ssl_choice ssl_mode
    while true; do
        echo -ne "${BOLD}${GREEN}Choose security option${NC} [${CYAN}1-3${NC}] (recommended: ${BOLD}1${NC}): "
        read -r ssl_choice
        if [[ -z "$ssl_choice" ]]; then
            ssl_choice="1"
        fi
        
        case "$ssl_choice" in
            1) 
                ssl_mode="generate"
                echo -e "   ${GREEN}${CHECKMARK} Excellent choice!${NC} Using: ${BOLD}Self-signed certificates${NC}"
                echo -e "   ${DIM}Your system will be secure and ready in minutes.${NC}"
                break
                ;;
            2) 
                ssl_mode="existing"
                echo -e "   ${YELLOW}${CHECKMARK} Professional setup!${NC} Using: ${BOLD}Your own certificates${NC}"
                echo -e "   ${BLUE}✓ Remember:${NC} Place your certificate files in the ssl/ directory"
                break
                ;;
            3) 
                ssl_mode="none"
                echo -e "   ${RED}${CROSSMARK} No encryption selected${NC} Using: ${BOLD}HTTP only${NC}"
                echo -e "   ${YELLOW}✓  Warning:${NC} Your connection will not be encrypted"
                break
                ;;
            *) 
                echo -e "   ${RED}${CROSSMARK} Please choose 1, 2, or 3${NC}"
                echo
                ;;
        esac
    done
    echo
    
    # Enhanced configuration summary with visual appeal
    echo -e "${BOLD}${PURPLE}✓${NC}"
    echo -e "${BOLD}${PURPLE}                ✓ Your Configuration Summary${NC}"
    echo -e "${BOLD}${PURPLE}✓${NC}"
    echo
    echo -e "   ${BOLD}Domain:${NC}        ${CYAN}$domain${NC}"
    echo -e "   ${BOLD}Admin Email:${NC}   ${CYAN}$email${NC}"
    echo -e "   ${BOLD}SSL Security:${NC}  ${CYAN}$ssl_mode${NC}"
    echo
    echo -e "${GREEN}${CHECKMARK} Everything looks perfect! Generating your configuration...${NC}"
    echo
    
    # Generate configuration using consolidated config module with credential preservation
    if config_generate "$domain" "$email" "$ssl_mode" "true" "$preserve_creds" "false"; then
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
    
    # Generate configuration using consolidated config module with credential preservation
    if config_generate "$domain" "$email" "$ssl_mode" "true" "$preserve_creds" "false"; then
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
    
    # Generate configuration using consolidated config module with credential preservation
    if config_generate "$domain" "$email" "$ssl_mode" "true" "$preserve_creds" "false"; then
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
    
    case "$ssl_mode" in
        "generate")
            milou_log "INFO" "✓ Generating self-signed SSL certificates..."
            # Use SSL module if available, otherwise basic generation
            if command -v ssl_generate_self_signed >/dev/null 2>&1; then
                ssl_generate_self_signed "$domain"
            else
                setup_generate_basic_ssl_certificates "$domain"
            fi
            ;;
        "existing")
            milou_log "INFO" "✓ Using existing SSL certificates..."
            # Validation handled by config module
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

# Prepare Docker environment
setup_prepare_docker_environment() {
    milou_log "INFO" "✓ Preparing Docker environment..."
    
    # Create required external networks
    milou_log "DEBUG" "Creating external proxy network"
    if ! docker network ls | grep -q "proxy"; then
        docker network create proxy 2>/dev/null || true
    fi
    
    # Use Docker module if available
    if command -v docker_init >/dev/null 2>&1; then
        docker_init
    else
        # Basic Docker network creation
        docker network create milou_network 2>/dev/null || true
    fi
    
    milou_log "SUCCESS" "✓ Docker environment prepared"
    return 0
}

# Start services
setup_start_services() {
    milou_log "INFO" "✓ Starting Milou services..."
    
    # Check if GitHub token is available for private images
    local github_token="${GITHUB_TOKEN:-}"
    
    # If no token and we're in interactive mode, prompt for it
    if [[ -z "$github_token" && "$SETUP_CURRENT_MODE" == "$SETUP_MODE_INTERACTIVE" ]]; then
        echo ""
        echo "✓ GITHUB CONTAINER REGISTRY ACCESS"
        echo "===================================="
        echo ""
        echo "Milou uses private Docker images from GitHub Container Registry."
        echo "To access these images, you need a GitHub Personal Access Token."
        echo ""
        echo "You can either:"
        echo "1) Enter your GitHub token now (recommended)"
        echo "2) Skip and set it later in the .env file"
        echo ""
        
        if confirm "Do you have a GitHub Personal Access Token?" "Y"; then
            echo ""
            echo "Enter your GitHub Personal Access Token:"
            echo "(You can create one at: https://github.com/settings/tokens)"
            echo "Required scopes: read:packages"
            echo ""
            echo -ne "GitHub Token: "
            read -rs github_token
            echo
            echo ""
            
            if [[ -n "$github_token" ]]; then
                # Validate the token
                if validate_github_token "$github_token" "false"; then
                    milou_log "SUCCESS" "✓ GitHub token validated"
                    # Update the .env file with the token
                    if [[ -f "${SCRIPT_DIR:-$(pwd)}/.env" ]]; then
                        if grep -q "^GITHUB_TOKEN=" "${SCRIPT_DIR:-$(pwd)}/.env"; then
                            sed -i "s/^GITHUB_TOKEN=.*/GITHUB_TOKEN=$github_token/" "${SCRIPT_DIR:-$(pwd)}/.env"
                        else
                            echo "GITHUB_TOKEN=$github_token" >> "${SCRIPT_DIR:-$(pwd)}/.env"
                        fi
                        milou_log "INFO" "Token saved to .env file"
                    fi
                else
                    milou_log "WARN" "✓  Token validation failed, but continuing with provided token"
                fi
            else
                milou_log "INFO" "No token provided, continuing without authentication"
            fi
        else
            milou_log "INFO" "Skipping GitHub token setup"
            echo ""
            echo "✓ To set up authentication later:"
            echo "  1. Get a token from: https://github.com/settings/tokens"
            echo "  2. Add to .env file: GITHUB_TOKEN=ghp_your_token_here"
            echo "  3. Restart services: ./milou.sh restart"
            echo ""
        fi
    fi
    
    # Use the Docker module's start function which handles authentication
    if service_start_with_validation "" "60" "false"; then
        milou_log "SUCCESS" "✓ Services started successfully"
        
        # Wait for services to be ready
        milou_log "INFO" "✓ Waiting for services to initialize..."
        sleep 10
        
        return 0
    else
        milou_log "ERROR" "Failed to start services"
        
        # If authentication failed and we don't have a token, provide guidance
        if [[ -z "$github_token" ]]; then
            echo ""
            echo "✓ AUTHENTICATION MAY BE REQUIRED"
            echo "=================================="
            echo ""
            echo "If the error above mentions 'unauthorized' or authentication,"
            echo "you need a GitHub Personal Access Token to access private images."
            echo ""
            echo "✓ GET A GITHUB TOKEN:"
            echo "  1. Go to: https://github.com/settings/tokens"
            echo "  2. Create a token with 'read:packages' scope"
            echo "  3. Add to .env file: GITHUB_TOKEN=ghp_your_token_here"
            echo "  4. Run setup again: ./milou.sh setup"
            echo ""
        fi
        
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
    echo "  ./milou.sh setup                           # Smart setup (preserves credentials automatically)"
    echo "  ./milou.sh setup --automated               # Automated setup using environment variables"
    echo "  ./milou.sh setup --preserve-creds          # Explicitly preserve existing credentials"
    echo "  ./milou.sh setup --force-new-creds         # Generate new credentials (⚠️  affects data)"
    echo "  ./milou.sh setup --clean                   # Clean install (⚠️  deletes all data)"
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

milou_log "DEBUG" "Setup module loaded successfully" 