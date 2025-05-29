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
# LOGO AND BRANDING FUNCTIONS
# =============================================================================

# Show Milou logo during setup
setup_show_logo() {
    if tty -s && [[ "${QUIET:-false}" != "true" ]]; then
        echo -e "${PURPLE:-}"
        cat << 'EOF'
                                                        @@@@@@@@@@@                     
                                                        @@@@@@@@@@@                     
                                            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@          
                                            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@          
                                            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@          
                                            @@@@@@@@@@@   @@@@@@@@@@@@@@@@@@@          
                                            @@@@@@@@@@    @@@@@@@@@@@@@@@@@@@          
                                            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@          
                                            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                                            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                                            @@@@@@@@@@@@@@@@@@@@@    @@@@@@@@@@@@@@@@@@
                                            @@@@@@@@@@@@@@@@@@@@@@  @@@@@@@@@@@@@@@@@@@
                                            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                                            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                                  @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                                  @@@@@@@@@@@@@@@@@@@@@@@@                               
                                  @@@@@@@@@@@@@@@@@@@@@@@@                               
                                  @@@@@@@@@@@@@@@@@@@@@@@@                               
                                  @@@@@@@@@@@@@@@@@@@@@@@@                               
                                  @@@@@@@@@@@@@@@@@@@@@@@@                                                                                                                 
EOF
    ┌─────────────────────────────────────┐
    │  Milou CLI - Docker Management      │
    │  Professional • Secure • Simple    │
    └─────────────────────────────────────┘
EOF
        echo -e "${NC:-}"
        echo -e "${BOLD:-}${CYAN:-}Welcome to the Milou CLI Setup Wizard${NC:-}"
        echo -e "${CYAN:-}Setting up your professional Docker environment...${NC:-}"
        echo
    fi
}

# =============================================================================
# MAIN SETUP ORCHESTRATION FUNCTIONS
# =============================================================================

# Main setup entry point - SINGLE AUTHORITATIVE IMPLEMENTATION
setup_run() {
    local force="${1:-false}"
    local mode="${2:-auto}"
    local skip_validation="${3:-false}"
    local preserve_creds="${4:-auto}"
    
    # Show Milou logo
    setup_show_logo
    
    # Display header
    milou_log "STEP" "🚀 Milou Setup - State-of-the-Art CLI v${SCRIPT_VERSION:-latest}"
    echo "═══════════════════════════════════════════════════"
    echo ""
    
    # Step 1: System Analysis (always succeeds, just gathers information)
    if ! setup_analyze_system; then
        milou_log "ERROR" "System analysis failed"
        return 1
    fi
    
    # Step 2: Prerequisites Assessment (reports status, doesn't fail setup)
    setup_assess_prerequisites || true  # Always continue regardless of result
    
    # Step 3: Setup Mode Determination
    if ! setup_determine_mode "$mode"; then
        milou_log "ERROR" "Setup mode determination failed"
        return 1
    fi
    
    # Step 4: Dependencies Installation (only if needed)
    if [[ "$SETUP_NEEDS_DEPS" == "true" ]]; then
        if ! setup_install_dependencies; then
            milou_log "ERROR" "Dependencies installation failed"
            return 1
        fi
    fi
    
    # Step 5: User Management (only if needed)
    if [[ "$SETUP_NEEDS_USER" == "true" ]]; then
        if ! setup_manage_user; then
            milou_log "ERROR" "User management failed"
            return 1
        fi
    fi
    
    # Step 6: Configuration Generation (with credential preservation)
    if ! setup_generate_configuration "$preserve_creds"; then
        milou_log "ERROR" "Configuration generation failed"
        return 1
    fi
    
    # Step 7: Final Validation and Service Startup
    if [[ "$skip_validation" != "true" ]]; then
        if ! setup_validate_and_start_services; then
            milou_log "ERROR" "Final validation and service startup failed"
            return 1
        fi
    fi
    
    # Step 8: Completion Report
    setup_display_completion_report
    
    milou_log "SUCCESS" "🎉 Milou setup completed successfully!"
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
    
    milou_log "INFO" "🔍 Analyzing system state..."
    
    # Check if this is a fresh server installation
    if setup_detect_fresh_server; then
        SETUP_IS_FRESH_SERVER="true"
        milou_log "INFO" "✨ Fresh server detected"
    else
        milou_log "INFO" "🔄 Existing system detected"
    fi
    
    # Check for existing Milou installation
    local has_existing_installation=false
    if setup_check_existing_installation; then
        has_existing_installation=true
        milou_log "INFO" "🔍 Found existing Milou installation"
    fi
    
    # Determine dependency needs
    if ! setup_check_dependencies_status; then
        SETUP_NEEDS_DEPS="true"
        milou_log "INFO" "📦 Dependencies installation required"
    fi
    
    # Determine user management needs
    if ! setup_check_user_status; then
        SETUP_NEEDS_USER="true"
        milou_log "INFO" "👤 User management required"
    fi
    
    # Summary
    milou_log "SUCCESS" "📊 System Analysis Complete:"
    milou_log "INFO" "  • Fresh Server: $SETUP_IS_FRESH_SERVER"
    milou_log "INFO" "  • Needs Dependencies: $SETUP_NEEDS_DEPS"
    milou_log "INFO" "  • Needs User Setup: $SETUP_NEEDS_USER"
    milou_log "INFO" "  • Existing Installation: $has_existing_installation"
    
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

# Check dependency installation status
setup_check_dependencies_status() {
    local missing_deps=()
    
    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
        missing_deps+=("docker")
    elif ! docker version >/dev/null 2>&1; then
        missing_deps+=("docker-service")
    fi
    
    # Check Docker Compose
    if ! docker compose version >/dev/null 2>&1; then
        missing_deps+=("docker-compose")
    fi
    
    # Check basic tools
    for tool in curl wget jq openssl; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_deps+=("$tool")
        fi
    done
    
    if [[ ${#missing_deps[@]} -eq 0 ]]; then
        milou_log "DEBUG" "All dependencies are installed"
        return 0
    else
        milou_log "DEBUG" "Missing dependencies: ${missing_deps[*]}"
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

# Assess system prerequisites - SINGLE AUTHORITATIVE IMPLEMENTATION
setup_assess_prerequisites() {
    milou_log "STEP" "Step 2: Prerequisites Assessment"
    
    local critical_missing=()
    local optional_missing=()
    
    # Critical prerequisites
    if ! command -v docker >/dev/null 2>&1; then
        critical_missing+=("docker")
    fi
    
    if ! docker compose version >/dev/null 2>&1; then
        critical_missing+=("docker-compose")
    fi
    
    # Optional but recommended
    for tool in curl wget jq openssl; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            optional_missing+=("$tool")
        fi
    done
    
    # Report status
    if [[ ${#critical_missing[@]} -eq 0 ]]; then
        milou_log "SUCCESS" "✅ All critical prerequisites satisfied"
        if [[ ${#optional_missing[@]} -gt 0 ]]; then
            milou_log "WARN" "📦 Optional tools missing: ${optional_missing[*]}"
            milou_log "INFO" "💡 These will be installed if needed during setup"
        fi
        return 0
    else
        milou_log "INFO" "📦 Critical prerequisites to be installed: ${critical_missing[*]}"
        if [[ ${#optional_missing[@]} -gt 0 ]]; then
            milou_log "INFO" "📦 Optional tools to be installed: ${optional_missing[*]}"
        fi
        milou_log "INFO" "🚀 Don't worry - setup will install these automatically"
        return 1  # Still return 1 to indicate missing deps, but setup continues
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
            milou_log "INFO" "🧙 Interactive mode selected"
            ;;
        "automated"|"auto")
            # For automated mode, check if we have required variables OR if user explicitly requested it
            if setup_can_run_automated || [[ "$requested_mode" == "automated" ]]; then
                SETUP_CURRENT_MODE="$SETUP_MODE_AUTOMATED"
                milou_log "INFO" "🤖 Automated mode selected"
            else
                SETUP_CURRENT_MODE="$SETUP_MODE_INTERACTIVE"
                milou_log "INFO" "🧙 Falling back to interactive mode (missing environment variables)"
            fi
            ;;
        "smart")
            SETUP_CURRENT_MODE="$SETUP_MODE_SMART"
            milou_log "INFO" "🧠 Smart mode selected"
            ;;
        *)
            milou_log "WARN" "Unknown setup mode: $requested_mode, using interactive"
            SETUP_CURRENT_MODE="$SETUP_MODE_INTERACTIVE"
            ;;
    esac
    
    milou_log "SUCCESS" "📋 Setup mode determined: $SETUP_CURRENT_MODE"
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
    milou_log "INFO" "🔧 Interactive Dependencies Installation"
    
    if ! confirm "Install missing dependencies now?" "Y"; then
        milou_log "INFO" "Dependencies installation skipped by user"
        return 1
    fi
    
    setup_install_dependencies_core
}

# Automated dependencies installation
setup_install_dependencies_automated() {
    milou_log "INFO" "🤖 Automated Dependencies Installation"
    setup_install_dependencies_core
}

# Smart dependencies installation  
setup_install_dependencies_smart() {
    milou_log "INFO" "🧠 Smart Dependencies Installation"
    
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
    
    milou_log "INFO" "📦 Installing core dependencies..."
    
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
    
    milou_log "SUCCESS" "✅ Dependencies installation completed"
    return 0
}

# Install Docker
setup_install_docker() {
    milou_log "INFO" "🐳 Installing Docker..."
    
    # Use official Docker installation script
    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL https://get.docker.com | sh; then
            systemctl start docker 2>/dev/null || true
            systemctl enable docker 2>/dev/null || true
            milou_log "SUCCESS" "✅ Docker installed successfully"
            return 0
        fi
    fi
    
    milou_log "ERROR" "Failed to install Docker"
    return 1
}

# Install Docker Compose
setup_install_docker_compose() {
    milou_log "INFO" "🛠️ Installing Docker Compose..."
    
    # Try package manager first
    if command -v apt-get >/dev/null 2>&1; then
        if apt-get update && apt-get install -y docker-compose-plugin; then
            milou_log "SUCCESS" "✅ Docker Compose plugin installed"
            return 0
        fi
    elif command -v yum >/dev/null 2>&1; then
        if yum install -y docker-compose-plugin; then
            milou_log "SUCCESS" "✅ Docker Compose plugin installed"
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
            milou_log "SUCCESS" "✅ Docker Compose installed manually"
            return 0
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
        milou_log "SUCCESS" "✅ All system tools already installed"
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
    
    milou_log "SUCCESS" "✅ System tools installed"
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
    milou_log "INFO" "👤 Creating dedicated milou user..."
    
    # Create user if it doesn't exist
    if ! id milou >/dev/null 2>&1; then
        if useradd -m -s /bin/bash milou; then
            milou_log "SUCCESS" "✅ Milou user created"
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
            milou_log "SUCCESS" "✅ Added milou user to docker group"
        else
            milou_log "ERROR" "Failed to add milou user to docker group"
            return 1
        fi
    fi
    
    milou_log "SUCCESS" "✅ User management completed"
    return 0
}

# Configure current user for Docker access
setup_configure_current_user() {
    local current_user="${USER:-$(whoami)}"
    
    milou_log "INFO" "👤 Configuring current user ($current_user) for Docker access..."
    
    # Check if user is in docker group
    if ! groups "$current_user" | grep -q docker; then
        milou_log "INFO" "Adding current user to docker group (requires sudo)..."
        if sudo usermod -aG docker "$current_user"; then
            milou_log "SUCCESS" "✅ Added $current_user to docker group"
            milou_log "WARN" "⚠️  You may need to log out and log back in for group changes to take effect"
        else
            milou_log "ERROR" "Failed to add user to docker group"
            return 1
        fi
    else
        milou_log "SUCCESS" "✅ User already has Docker access"
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

# Interactive configuration generation
setup_generate_configuration_interactive() {
    local preserve_creds="${1:-auto}"
    
    milou_log "INFO" "🧙 Interactive Configuration Setup"
    echo
    echo -e "${CYAN}Let's configure your Milou environment...${NC:-}"
    echo
    
    # Get domain with better prompting and validation
    local domain
    while true; do
        echo -e "${BOLD}${BLUE}🌐 Domain Configuration${NC:-}"
        echo -e "${DIM}Enter the domain where Milou will be accessible${NC:-}"
        echo -e "${DIM}Examples: localhost, yourdomain.com, server.company.com${NC:-}"
        echo
        echo -ne "${GREEN}Domain name${NC:-} [${BOLD}localhost${NC:-}]: "
        read -r domain
        if [[ -z "$domain" ]]; then
            domain="localhost"
        fi
        
        # Basic domain validation
        if [[ "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9\.-]*[a-zA-Z0-9]$ ]] || [[ "$domain" == "localhost" ]]; then
            echo -e "   ${GREEN}✓${NC:-} Domain: ${BOLD}$domain${NC:-}"
            break
        else
            echo -e "   ${RED}✗${NC:-} Invalid domain format. Please try again."
            echo
        fi
    done
    echo
    
    # Get admin email with validation
    local email
    while true; do
        echo -e "${BOLD}${BLUE}📧 Admin Email Configuration${NC:-}"
        echo -e "${DIM}This email will be used for admin notifications and SSL certificates${NC:-}"
        echo
        echo -ne "${GREEN}Admin email${NC:-} [${BOLD}admin@$domain${NC:-}]: "
        read -r email
        if [[ -z "$email" ]]; then
            email="admin@$domain"
        fi
        
        # Use core validation function that properly handles localhost
        if validate_email "$email" "true"; then
            echo -e "   ${GREEN}✓${NC:-} Email: ${BOLD}$email${NC:-}"
            break
        else
            echo -e "   ${RED}✗${NC:-} Invalid email format. Please try again."
            echo -e "   ${DIM}Examples: admin@yourdomain.com, admin@localhost, user@example.org${NC:-}"
            echo
        fi
    done
    echo
    
    # Get SSL mode with better explanation
    echo -e "${BOLD}${BLUE}🔒 SSL Certificate Configuration${NC:-}"
    echo -e "${DIM}Choose how to handle SSL certificates for secure HTTPS access${NC:-}"
    echo
    echo -e "${BOLD}Available options:${NC:-}"
    echo -e "   ${GREEN}1)${NC:-} ${BOLD}Generate self-signed certificates${NC:-} ${DIM}(Recommended for development)${NC:-}"
    echo -e "      ${DIM}• Quick setup, works immediately${NC:-}"
    echo -e "      ${DIM}• Browser will show security warning (normal)${NC:-}"
    echo -e "      ${DIM}• Perfect for testing and local development${NC:-}"
    echo
    echo -e "   ${YELLOW}2)${NC:-} ${BOLD}Use existing certificates${NC:-} ${DIM}(For production with your own certs)${NC:-}"
    echo -e "      ${DIM}• Place your certificates in ssl/ directory${NC:-}"
    echo -e "      ${DIM}• Required files: certificate.crt, private.key${NC:-}"
    echo
    echo -e "   ${RED}3)${NC:-} ${BOLD}No SSL${NC:-} ${DIM}(Not recommended, HTTP only)${NC:-}"
    echo -e "      ${DIM}• Unencrypted connection${NC:-}"
    echo -e "      ${DIM}• Only use for development or trusted networks${NC:-}"
    echo
    
    local ssl_choice
    while true; do
        echo -ne "${GREEN}Choose SSL option${NC:-} [${BOLD}1-3${NC:-}] (default: ${BOLD}1${NC:-}): "
        read -r ssl_choice
        if [[ -z "$ssl_choice" ]]; then
            ssl_choice="1"
        fi
        
        case "$ssl_choice" in
            1) 
                ssl_mode="generate"
                echo -e "   ${GREEN}✓${NC:-} SSL: ${BOLD}Self-signed certificates${NC:-}"
                break
                ;;
            2) 
                ssl_mode="existing"
                echo -e "   ${YELLOW}✓${NC:-} SSL: ${BOLD}Existing certificates${NC:-}"
                echo -e "   ${DIM}Make sure to place your certificates in ssl/ directory${NC:-}"
                break
                ;;
            3) 
                ssl_mode="none"
                echo -e "   ${RED}✓${NC:-} SSL: ${BOLD}Disabled${NC:-} ${DIM}(HTTP only)${NC:-}"
                break
                ;;
            *) 
                echo -e "   ${RED}✗${NC:-} Please choose 1, 2, or 3"
                ;;
        esac
    done
    echo
    
    # Summary of choices
    echo -e "${BOLD}${PURPLE}📋 Configuration Summary${NC:-}"
    echo -e "   ${CYAN}Domain:${NC:-}     ${BOLD}$domain${NC:-}"
    echo -e "   ${CYAN}Email:${NC:-}      ${BOLD}$email${NC:-}"
    echo -e "   ${CYAN}SSL Mode:${NC:-}   ${BOLD}$ssl_mode${NC:-}"
    echo
    
    # Generate configuration using consolidated config module with credential preservation
    if config_generate "$domain" "$email" "$ssl_mode" "true" "$preserve_creds" "false"; then
        milou_log "SUCCESS" "✅ Configuration generated successfully"
        
        # Only force container recreation if credentials are NEW (not preserved)
        if [[ "$preserve_creds" == "false" || ("$preserve_creds" == "auto" && "${CREDENTIALS_PRESERVED:-false}" == "false") ]]; then
            milou_log "INFO" "🔄 New credentials generated - recreating containers for security"
            setup_force_container_recreation "false"
        else
            milou_log "INFO" "✅ Credentials preserved - keeping existing containers and data"
        fi
        
        return 0
    else
        milou_log "ERROR" "Configuration generation failed"
        return 1
    fi
}

# Automated configuration generation
setup_generate_configuration_automated() {
    local preserve_creds="${1:-auto}"
    
    milou_log "INFO" "🤖 Automated Configuration Generation"
    
    local domain="${DOMAIN:-localhost}"
    local email="${ADMIN_EMAIL:-admin@localhost}"
    local ssl_mode="${SSL_MODE:-generate}"
    
    # Generate configuration using consolidated config module with credential preservation
    if config_generate "$domain" "$email" "$ssl_mode" "true" "$preserve_creds" "false"; then
        milou_log "SUCCESS" "✅ Configuration generated successfully"
        
        # Only force container recreation if credentials are NEW (not preserved)
        if [[ "$preserve_creds" == "false" || ("$preserve_creds" == "auto" && "${CREDENTIALS_PRESERVED:-false}" == "false") ]]; then
            milou_log "INFO" "🔄 New credentials generated - recreating containers for security"
            setup_force_container_recreation "false"
        else
            milou_log "INFO" "✅ Credentials preserved - keeping existing containers and data"
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
    
    milou_log "INFO" "🧠 Smart Configuration Generation"
    
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
    
    milou_log "INFO" "🧠 Smart defaults: domain=$domain, email=$email, ssl=$ssl_mode"
    
    # Generate configuration using consolidated config module with credential preservation
    if config_generate "$domain" "$email" "$ssl_mode" "true" "$preserve_creds" "false"; then
        milou_log "SUCCESS" "✅ Configuration generated successfully"
        
        # Only force container recreation if credentials are NEW (not preserved)
        if [[ "$preserve_creds" == "false" || ("$preserve_creds" == "auto" && "${CREDENTIALS_PRESERVED:-false}" == "false") ]]; then
            milou_log "INFO" "🔄 New credentials generated - recreating containers for security"
            setup_force_container_recreation "false"
        else
            milou_log "INFO" "✅ Credentials preserved - keeping existing containers and data"
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
    
    milou_log "SUCCESS" "✅ Services started and validated"
    return 0
}

# Validate system readiness
setup_validate_system_readiness() {
    milou_log "INFO" "🔍 Validating system readiness..."
    
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
    if ! validate_docker_access "true"; then
        milou_log "ERROR" "Docker validation failed"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        milou_log "SUCCESS" "✅ System readiness validated"
        return 0
    else
        milou_log "ERROR" "System readiness validation failed ($errors errors)"
        return 1
    fi
}

# Configure SSL certificates
setup_configure_ssl() {
    milou_log "INFO" "🔒 Setting up SSL certificates..."
    
    # Load environment variables
    if [[ -f "${SCRIPT_DIR:-$(pwd)}/.env" ]]; then
        source "${SCRIPT_DIR:-$(pwd)}/.env"
    fi
    
    local ssl_mode="${SSL_MODE:-generate}"
    local domain="${DOMAIN:-localhost}"
    
    case "$ssl_mode" in
        "generate")
            milou_log "INFO" "🔧 Generating self-signed SSL certificates..."
            # Use SSL module if available, otherwise basic generation
            if command -v ssl_generate_self_signed >/dev/null 2>&1; then
                ssl_generate_self_signed "$domain"
            else
                setup_generate_basic_ssl_certificates "$domain"
            fi
            ;;
        "existing")
            milou_log "INFO" "📁 Using existing SSL certificates..."
            # Validation handled by config module
            ;;
        "none")
            milou_log "INFO" "⚠️ SSL disabled - using HTTP only"
            return 0
            ;;
        *)
            milou_log "WARN" "Unknown SSL mode: $ssl_mode, defaulting to generate"
            setup_generate_basic_ssl_certificates "$domain"
            ;;
    esac
    
    milou_log "SUCCESS" "✅ SSL configuration completed"
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
    
    milou_log "SUCCESS" "✅ Self-signed SSL certificates generated"
}

# Prepare Docker environment
setup_prepare_docker_environment() {
    milou_log "INFO" "🐳 Preparing Docker environment..."
    
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
    
    milou_log "SUCCESS" "✅ Docker environment prepared"
    return 0
}

# Start services
setup_start_services() {
    milou_log "INFO" "🚀 Starting Milou services..."
    
    # Check if GitHub token is available for private images
    local github_token="${GITHUB_TOKEN:-}"
    
    # If no token and we're in interactive mode, prompt for it
    if [[ -z "$github_token" && "$SETUP_CURRENT_MODE" == "$SETUP_MODE_INTERACTIVE" ]]; then
        echo ""
        echo "🔐 GITHUB CONTAINER REGISTRY ACCESS"
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
                    milou_log "SUCCESS" "✅ GitHub token validated"
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
                    milou_log "WARN" "⚠️  Token validation failed, but continuing with provided token"
                fi
            else
                milou_log "INFO" "No token provided, continuing without authentication"
            fi
        else
            milou_log "INFO" "Skipping GitHub token setup"
            echo ""
            echo "💡 To set up authentication later:"
            echo "  1. Get a token from: https://github.com/settings/tokens"
            echo "  2. Add to .env file: GITHUB_TOKEN=ghp_your_token_here"
            echo "  3. Restart services: ./milou.sh restart"
            echo ""
        fi
    fi
    
    # Use the Docker module's start function which handles authentication
    if docker_start "$github_token" "false" "false"; then
        milou_log "SUCCESS" "✅ Services started successfully"
        
        # Wait for services to be ready
        milou_log "INFO" "⏳ Waiting for services to initialize..."
        sleep 10
        
        return 0
    else
        milou_log "ERROR" "Failed to start services"
        
        # If authentication failed and we don't have a token, provide guidance
        if [[ -z "$github_token" ]]; then
            echo ""
            echo "🔐 AUTHENTICATION MAY BE REQUIRED"
            echo "=================================="
            echo ""
            echo "If the error above mentions 'unauthorized' or authentication,"
            echo "you need a GitHub Personal Access Token to access private images."
            echo ""
            echo "🔧 GET A GITHUB TOKEN:"
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
    milou_log "INFO" "🏥 Validating service health..."
    
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
            milou_log "SUCCESS" "✅ All services healthy ($healthy_services/$total_services)"
            return 0
        fi
        
        milou_log "DEBUG" "Services status: $healthy_services/$total_services healthy"
        sleep 5
        elapsed=$((elapsed + 5))
    done
    
    if [[ $healthy_services -gt 0 ]]; then
        milou_log "WARN" "⚠️ Partial service health: $healthy_services/$total_services healthy"
        return 0
    else
        milou_log "ERROR" "❌ Service health validation failed"
        return 1
    fi
}

# =============================================================================
# COMPLETION AND REPORTING FUNCTIONS
# =============================================================================

# Display setup completion report - SINGLE AUTHORITATIVE IMPLEMENTATION
setup_display_completion_report() {
    milou_log "SUCCESS" "🎉 Milou Setup Completed Successfully!"
    echo
    echo -e "${BOLD}${GREEN}┌────────────────────────────────────────────────────┐${NC:-}"
    echo -e "${BOLD}${GREEN}│               SETUP COMPLETE! 🚀                  │${NC:-}"
    echo -e "${BOLD}${GREEN}└────────────────────────────────────────────────────┘${NC:-}"
    echo
    
    # Load configuration for display
    if [[ -f "${SCRIPT_DIR:-$(pwd)}/.env" ]]; then
        source "${SCRIPT_DIR:-$(pwd)}/.env"
    fi
    
    # Access information
    local domain="${DOMAIN:-localhost}"
    local https_port="${HTTPS_PORT:-443}"
    local http_port="${HTTP_PORT:-80}"
    
    echo -e "${BOLD}${CYAN}🌐 Access Information${NC:-}"
    if [[ "${SSL_MODE:-}" != "none" ]]; then
        if [[ "$https_port" == "443" ]]; then
            echo -e "   ${GREEN}Primary URL:${NC:-}    ${BOLD}https://$domain${NC:-}"
        else
            echo -e "   ${GREEN}Primary URL:${NC:-}    ${BOLD}https://$domain:$https_port${NC:-}"
        fi
        echo -e "   ${DIM}• Secure HTTPS connection with SSL certificates${NC:-}"
    fi
    
    if [[ "$http_port" == "80" ]]; then
        echo -e "   ${YELLOW}HTTP Redirect:${NC:-} ${BOLD}http://$domain${NC:-} ${DIM}(redirects to HTTPS)${NC:-}"
    else
        echo -e "   ${YELLOW}HTTP Redirect:${NC:-} ${BOLD}http://$domain:$http_port${NC:-} ${DIM}(redirects to HTTPS)${NC:-}"
    fi
    echo
    
    # Admin credentials with security notice
    echo -e "${BOLD}${PURPLE}🔑 Admin Credentials${NC:-}"
    echo -e "   ${GREEN}Username:${NC:-} ${BOLD}${ADMIN_USERNAME:-admin}${NC:-}"
    echo -e "   ${GREEN}Password:${NC:-} ${BOLD}${ADMIN_PASSWORD:-[check .env file]}${NC:-}"
    echo -e "   ${GREEN}Email:${NC:-}    ${BOLD}${ADMIN_EMAIL:-admin@localhost}${NC:-}"
    echo
    echo -e "   ${RED}⚠️  IMPORTANT SECURITY NOTICE:${NC:-}"
    echo -e "   ${DIM}• Save these credentials in a secure password manager${NC:-}"
    echo -e "   ${DIM}• Change the default password after first login${NC:-}"
    echo -e "   ${DIM}• Never share credentials via email or chat${NC:-}"
    echo
    
    # Management commands
    echo -e "${BOLD}${BLUE}⚙️  Management Commands${NC:-}"
    echo -e "   ${GREEN}Check Status:${NC:-}    ${BOLD}./milou.sh status${NC:-}"
    echo -e "   ${GREEN}View Logs:${NC:-}       ${BOLD}./milou.sh logs${NC:-} ${DIM}[service]${NC:-}"
    echo -e "   ${GREEN}Stop Services:${NC:-}   ${BOLD}./milou.sh stop${NC:-}"
    echo -e "   ${GREEN}Restart All:${NC:-}     ${BOLD}./milou.sh restart${NC:-}"
    echo -e "   ${GREEN}Create Backup:${NC:-}   ${BOLD}./milou.sh backup${NC:-}"
    echo -e "   ${GREEN}Get Help:${NC:-}        ${BOLD}./milou.sh --help${NC:-}"
    echo
    
    # Next steps with priorities
    echo -e "${BOLD}${YELLOW}💡 Next Steps (Recommended)${NC:-}"
    echo -e "   ${BOLD}1.${NC:-} ${GREEN}Access the web interface${NC:-}"
    echo -e "      ${DIM}• Open your browser and go to the URL above${NC:-}"
    echo -e "      ${DIM}• Accept the SSL certificate if using self-signed${NC:-}"
    echo
    echo -e "   ${BOLD}2.${NC:-} ${GREEN}Complete initial login${NC:-}"
    echo -e "      ${DIM}• Use the admin credentials shown above${NC:-}"
    echo -e "      ${DIM}• Change the default password immediately${NC:-}"
    echo
    echo -e "   ${BOLD}3.${NC:-} ${GREEN}Create your first backup${NC:-}"
    echo -e "      ${DIM}• Run: ./milou.sh backup${NC:-}"
    echo -e "      ${DIM}• Secure your configuration and data${NC:-}"
    echo
    echo -e "   ${BOLD}4.${NC:-} ${GREEN}Explore the documentation${NC:-}"
    echo -e "      ${DIM}• Check docs/USER_GUIDE.md for detailed instructions${NC:-}"
    echo -e "      ${DIM}• Learn about advanced features and administration${NC:-}"
    echo
    
    # Troubleshooting help
    echo -e "${BOLD}${RED}🚨 Having Issues?${NC:-}"
    echo -e "   ${DIM}• Services not starting: ./milou.sh logs${NC:-}"
    echo -e "   ${DIM}• Can't access web interface: ./milou.sh status${NC:-}"
    echo -e "   ${DIM}• Need help: ./milou.sh --help${NC:-}"
    echo -e "   ${DIM}• Health check: ./milou.sh health${NC:-}"
    echo
    
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
            --new-creds|--new-credentials)
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
        milou_log "STEP" "🧹 Clean Installation Requested"
        echo ""
        echo "⚠️  🚨 WARNING: CLEAN INSTALL WILL DELETE ALL DATA! 🚨"
        echo "==============================================="
        echo ""
        echo "This will PERMANENTLY DELETE:"
        echo "  🗄️  All database data"
        echo "  🔐 All SSL certificates"
        echo "  ⚙️  All configuration files"
        echo "  📦 All Docker volumes and containers"
        echo "  💾 All backup files"
        echo ""
        
        if ! confirm "Are you ABSOLUTELY SURE you want to delete ALL data?" "N"; then
            milou_log "INFO" "Clean install cancelled - wise choice!"
            return 0
        fi
        
        # Force container recreation with volume cleanup
        setup_force_container_recreation "false"
        
        # Remove configuration files
        rm -f "${SCRIPT_DIR:-$(pwd)}/.env"
        rm -rf "${SCRIPT_DIR:-$(pwd)}/ssl"
        
        milou_log "SUCCESS" "✅ Clean install preparation completed"
        echo ""
        
        # Force new credentials for clean install
        preserve_creds="false"
    fi
    
    # Run main setup with parsed options
    setup_run "$force" "$mode" "$skip_validation" "$preserve_creds"
}

# Show setup help
show_setup_help() {
    echo "🚀 Milou CLI Setup Command"
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
    echo "  --new-creds           Generate new credentials (will affect existing data!)"
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
    echo "  ./milou.sh setup                           # Interactive setup with credential preservation"
    echo "  ./milou.sh setup --automated               # Automated setup using environment variables"
    echo "  ./milou.sh setup --preserve-creds          # Explicitly preserve existing credentials"
    echo "  ./milou.sh setup --new-creds               # Generate new credentials (WARNING: affects data)"
    echo "  ./milou.sh setup --clean                   # Clean install (WARNING: deletes all data)"
    echo ""
    echo "CREDENTIAL PRESERVATION:"
    echo "  🔄 UPDATE: Credentials are preserved by default to protect your data"
    echo "  ✨ FRESH INSTALL: New credentials are generated for security"
    echo "  ⚠️  OVERRIDE: Use --new-creds to force new credentials (may affect data access)"
    echo ""
    echo "For more information, see: docs/USER_GUIDE.md"
}

# =============================================================================
# EXPORT ALL FUNCTIONS
# =============================================================================

# Main setup orchestration
export -f setup_run

# System analysis functions
export -f setup_analyze_system
export -f setup_detect_fresh_server
export -f setup_check_existing_installation
export -f setup_check_dependencies_status
export -f setup_check_user_status

# Prerequisites assessment
export -f setup_assess_prerequisites

# Setup mode determination
export -f setup_determine_mode
export -f setup_can_run_automated

# Dependencies installation
export -f setup_install_dependencies
export -f setup_install_dependencies_interactive
export -f setup_install_dependencies_automated
export -f setup_install_dependencies_smart
export -f setup_install_dependencies_core
export -f setup_install_docker
export -f setup_install_docker_compose
export -f setup_install_system_tools

# User management
export -f setup_manage_user
export -f setup_create_milou_user
export -f setup_configure_current_user

# Configuration generation
export -f setup_generate_configuration
export -f setup_generate_configuration_interactive
export -f setup_generate_configuration_automated
export -f setup_generate_configuration_smart

# Validation and service startup
export -f setup_validate_and_start_services
export -f setup_validate_system_readiness
export -f setup_configure_ssl
export -f setup_generate_basic_ssl_certificates
export -f setup_prepare_docker_environment
export -f setup_start_services
export -f setup_validate_service_health

# Completion and reporting
export -f setup_display_completion_report

# Container management
export -f setup_force_container_recreation

# Setup command handlers
export -f handle_setup_modular
export -f show_setup_help

# Legacy aliases (for backwards compatibility during transition)
export -f setup_run_configuration_wizard
export -f setup_final_validation

# Force clean restart when credentials change
setup_force_container_recreation() {
    local quiet="${1:-false}"
    
    [[ "$quiet" != "true" ]] && milou_log "INFO" "🔄 Forcing complete system recreation for credential updates"
    
    # Stop all containers first
    [[ "$quiet" != "true" ]] && milou_log "INFO" "Stopping all containers..."
    docker compose down --remove-orphans --volumes 2>/dev/null || true
    
    # Force stop any remaining containers
    local running_containers=$(docker ps -q --filter "name=milou")
    if [[ -n "$running_containers" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Force stopping remaining containers"
        echo "$running_containers" | xargs docker stop 2>/dev/null || true
        echo "$running_containers" | xargs docker rm -f 2>/dev/null || true
    fi
    
    # Clean up ALL volumes related to milou (this is critical for credential updates)
    [[ "$quiet" != "true" ]] && milou_log "INFO" "Cleaning up all data volumes for fresh initialization..."
    
    # Remove all milou-related volumes
    local milou_volumes=$(docker volume ls -q | grep -E "milou|static" 2>/dev/null || true)
    if [[ -n "$milou_volumes" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Removing volumes: $(echo $milou_volumes | tr '\n' ' ')"
        echo "$milou_volumes" | xargs docker volume rm -f 2>/dev/null || true
    fi
    
    # Also clean up any anonymous volumes that might exist
    docker volume prune -f >/dev/null 2>&1 || true
    
    # Clean up networks
    docker network prune -f >/dev/null 2>&1 || true
    
    # Clean up any orphaned containers
    docker container prune -f >/dev/null 2>&1 || true
    
    # Ensure docker-compose file exists and pull latest images
    if [[ -f "docker-compose.yml" ]] || [[ -f "static/docker-compose.yml" ]]; then
        [[ "$quiet" != "true" ]] && milou_log "DEBUG" "Pulling latest images to ensure fresh start"
        docker compose pull >/dev/null 2>&1 || true
    fi
    
    [[ "$quiet" != "true" ]] && milou_log "SUCCESS" "✅ Complete system cleanup finished - ready for fresh initialization"
    return 0
}

milou_log "DEBUG" "Setup module loaded successfully" 