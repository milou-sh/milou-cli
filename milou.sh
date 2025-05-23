#!/bin/bash

set -euo pipefail

# =============================================================================
# Milou Management CLI - Enhanced Edition v3.1.0
# State-of-the-art CLI with comprehensive improvements using modular utilities
# =============================================================================

# Version and Constants
readonly SCRIPT_VERSION="3.1.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_DIR="${HOME}/.milou"
readonly ENV_FILE="${SCRIPT_DIR}/.env"
readonly BACKUP_DIR="${CONFIG_DIR}/backups"
readonly LOG_FILE="${CONFIG_DIR}/milou.log"
readonly CACHE_DIR="${CONFIG_DIR}/cache"
readonly DEFAULT_SSL_PATH="./ssl"

# Global State - Enhanced with better defaults
declare -g VERBOSE=false
declare -g FORCE=false
declare -g DRY_RUN=false
declare -g GITHUB_TOKEN=""
declare -g USE_LATEST_IMAGES=false
declare -g SKIP_VERSION_CHECK=false
declare -g INTERACTIVE=true
declare -g AUTO_CREATE_USER=false
declare -g SKIP_USER_CHECK=false
declare -g FRESH_INSTALL=false
declare -g AUTO_INSTALL_DEPS=false

# Enhanced state management for user switching
declare -g ORIGINAL_COMMAND=""
declare -g ORIGINAL_ARGUMENTS=()
declare -g USER_SWITCH_IN_PROGRESS=false

# Source utility functions with better error handling
source_utility() {
    local util_file="$1"
    if [[ -f "${SCRIPT_DIR}/utils/${util_file}" ]]; then
        source "${SCRIPT_DIR}/utils/${util_file}"
    else
        echo "ERROR: Required utility file not found: ${util_file}" >&2
        exit 1
    fi
}

# Source all utilities
source_utility "utils.sh"
source_utility "docker.sh"
source_utility "docker-registry.sh"
source_utility "ssl.sh"
source_utility "backup.sh"
source_utility "update.sh"
source_utility "configure.sh"
source_utility "setup_wizard.sh"
source_utility "user-management.sh"
source_utility "security.sh"
source_utility "prerequisites.sh"

# Create necessary directories
mkdir -p "${CONFIG_DIR}" "${BACKUP_DIR}" "${CACHE_DIR}"
touch "${LOG_FILE}"

# =============================================================================
# Enhanced State Management
# =============================================================================

# Save the original command and arguments for user switching
preserve_original_command() {
    ORIGINAL_COMMAND="${1:-}"
    shift 2>/dev/null || true
    ORIGINAL_ARGUMENTS=("$@")
    export ORIGINAL_COMMAND
    # Export the arguments as a string for simpler handling in subshells
    export ORIGINAL_ARGUMENTS_STR="$(printf '%q ' "$@")"
    log "DEBUG" "Preserved command: '$ORIGINAL_COMMAND' with ${#ORIGINAL_ARGUMENTS[@]} arguments"
}

# Check if we're resuming after a user switch
check_user_switch_resume() {
    if [[ "${USER_SWITCH_IN_PROGRESS:-false}" == "true" && -n "${ORIGINAL_COMMAND:-}" ]]; then
        log "DEBUG" "Resuming after user switch with command: $ORIGINAL_COMMAND"
        return 0
    fi
    return 1
}

# =============================================================================
# Enhanced Help System
# =============================================================================

show_help() {
    printf "${BOLD}${PURPLE}Milou Management CLI v${SCRIPT_VERSION}${NC}\n\n"

    printf "${BOLD}USAGE:${NC}\n"
    printf "    $(basename "$0") [COMMAND] [OPTIONS]\n\n"

    printf "${BOLD}COMMANDS:${NC}\n"
    printf "    ${CYAN}setup${NC}             Interactive setup wizard (recommended for first-time setup)\n"
    printf "    ${CYAN}start${NC}             Start all services\n"
    printf "    ${CYAN}stop${NC}              Stop all services\n"
    printf "    ${CYAN}restart${NC}           Restart all services\n"
    printf "    ${CYAN}status${NC}            Show detailed status of all services\n"
    printf "    ${CYAN}detailed-status${NC}   Show comprehensive system status and conflicts\n"
    printf "    ${CYAN}logs${NC} [SERVICE]    View logs for all or specific service\n"
    printf "    ${CYAN}health${NC}            Run comprehensive health checks\n"
    printf "    ${CYAN}health-check${NC}      Quick health check for running services\n"
    printf "    ${CYAN}config${NC}            View current configuration\n"
    printf "    ${CYAN}validate${NC}          Validate configuration and environment\n"
    printf "    ${CYAN}backup${NC}            Create system backup\n"
    printf "    ${CYAN}restore${NC} [FILE]    Restore from backup file\n"
    printf "    ${CYAN}update${NC}            Update to latest version\n"
    printf "    ${CYAN}ssl${NC}               Manage SSL certificates\n"
    printf "    ${CYAN}cleanup${NC}           Clean up Docker resources\n"
    printf "    ${CYAN}shell${NC} [SERVICE]   Get shell access to a running container\n"
    printf "    ${CYAN}debug-images${NC}      Debug Docker image availability (troubleshooting)\n"
    printf "    ${CYAN}diagnose${NC}          Run comprehensive Docker environment diagnosis\n"
    printf "    ${CYAN}user-status${NC}       Show current user and permission status\n"
    printf "    ${CYAN}create-user${NC}       Create dedicated milou user (requires sudo)\n"
    printf "    ${CYAN}migrate-user${NC}      Migrate existing installation to milou user\n"
    printf "    ${CYAN}security-check${NC}    Run comprehensive security assessment\n"
    printf "    ${CYAN}security-harden${NC}   Apply security hardening measures (requires sudo)\n"
    printf "    ${CYAN}security-report${NC}   Generate detailed security report\n"
    printf "    ${CYAN}install-deps${NC}      Install system dependencies (Docker, tools, etc.)\n"
    printf "    ${CYAN}help${NC}              Show this help message\n\n"

    printf "${BOLD}SETUP OPTIONS:${NC}\n"
    printf "    ${YELLOW}--token${NC} TOKEN        GitHub Personal Access Token for authentication\n"
    printf "    ${YELLOW}--domain${NC} DOMAIN      Domain name for the installation\n"
    printf "    ${YELLOW}--ssl-path${NC} PATH      Path to SSL certificates directory\n"
    printf "    ${YELLOW}--email${NC} EMAIL        Admin email address\n"
    printf "    ${YELLOW}--latest${NC}             Use latest available Docker image versions\n"
    printf "    ${YELLOW}--non-interactive${NC}    Run setup without interactive prompts\n"
    printf "    ${YELLOW}--fresh-install${NC}      Optimized mode for fresh server installations\n"
    printf "    ${YELLOW}--auto-install-deps${NC}  Automatically install missing dependencies\n\n"

    printf "${BOLD}GLOBAL OPTIONS:${NC}\n"
    printf "    ${YELLOW}--verbose${NC}            Show detailed output and debug information\n"
    printf "    ${YELLOW}--force${NC}              Force operation without confirmation prompts\n"
    printf "    ${YELLOW}--dry-run${NC}            Show what would be done without executing\n"
    printf "    ${YELLOW}--auto-create-user${NC}   Automatically create milou user if running as root\n"
    printf "    ${YELLOW}--skip-user-check${NC}    Skip user management validation (not recommended)\n"
    printf "    ${YELLOW}--help${NC}               Show this help message\n\n"

    printf "${BOLD}EXAMPLES:${NC}\n"
    printf "    ${DIM}# Fresh server setup (recommended for new installations)${NC}\n"
    printf "    $(basename "$0") setup --fresh-install\n\n"
    
    printf "    ${DIM}# Interactive setup (recommended)${NC}\n"
    printf "    $(basename "$0") setup\n\n"
    
    printf "    ${DIM}# Install dependencies first, then setup${NC}\n"
    printf "    sudo $(basename "$0") install-deps\n"
    printf "    $(basename "$0") setup\n\n"
    
    printf "    ${DIM}# Automated fresh server setup${NC}\n"
    printf "    sudo $(basename "$0") setup --fresh-install --auto-install-deps\n\n"
    
    printf "    ${DIM}# Non-interactive setup${NC}\n"
    printf "    $(basename "$0") setup --token ghp_xxxx --domain example.com --latest\n\n"
    
    printf "    ${DIM}# Start services${NC}\n"
    printf "    $(basename "$0") start\n\n"
    
    printf "    ${DIM}# Check detailed status${NC}\n"
    printf "    $(basename "$0") status --verbose\n\n"
    
    printf "    ${DIM}# View backend logs${NC}\n"
    printf "    $(basename "$0") logs backend\n\n"
    
    printf "    ${DIM}# Update SSL certificates${NC}\n"
    printf "    $(basename "$0") ssl --domain example.com\n\n"
    
    printf "    ${DIM}# Debug image availability (troubleshooting)${NC}\n"
    printf "    $(basename "$0") debug-images --token ghp_xxxx\n\n"

    printf "${BOLD}AUTHENTICATION:${NC}\n"
    printf "    ${INFO_EMOJI} GitHub Personal Access Token is required for pulling private Docker images\n"
    printf "    ${INFO_EMOJI} Required scopes: ${YELLOW}read:packages${NC}, ${YELLOW}write:packages${NC}\n"
    printf "    ${INFO_EMOJI} Create token at: ${CYAN}https://github.com/settings/tokens${NC}\n\n"

    printf "${BOLD}SSL CERTIFICATES:${NC}\n"
    printf "    Place SSL certificate files in your SSL directory:\n"
    printf "    ${YELLOW}•${NC} milou.crt (certificate file)\n"
    printf "    ${YELLOW}•${NC} milou.key (private key file)\n\n"

    printf "${BOLD}SECURITY:${NC}\n"
    printf "    ${LOCK_EMOJI} Never store GitHub tokens in configuration files\n"
    printf "    ${LOCK_EMOJI} Always pass tokens via command line arguments\n"
    printf "    ${LOCK_EMOJI} Configuration files are automatically secured (600 permissions)\n\n"

    printf "${BOLD}SUPPORT:${NC}\n"
    printf "    ${INFO_EMOJI} Documentation: https://docs.milou.sh\n"
    printf "    ${INFO_EMOJI} Issues: https://github.com/milou-sh/milou/issues\n"
    printf "    ${INFO_EMOJI} Email: support@milou.sh\n\n"
}

# =============================================================================
# Command Handlers - Enhanced
# =============================================================================

handle_setup() {
    # CRITICAL FIX: Preserve command state BEFORE user management check
    preserve_original_command "setup" "$@"
    
    echo
    echo -e "${BOLD}${PURPLE}🚀 Milou Setup - State-of-the-Art CLI v${SCRIPT_VERSION}${NC}"
    echo -e "${BOLD}${PURPLE}═══════════════════════════════════════════════════${NC}"
    echo
    
    # Step 1: System Information and Analysis
    log "STEP" "Step 1: System Analysis and Detection"
    echo
    
    # Detect system characteristics for smart setup
    local is_fresh_server=false
    local needs_deps_install=false
    local needs_user_management=false
    local setup_mode="interactive"  # Default to interactive
    
    # Analyze system state
    log "INFO" "🔍 Analyzing system state..."
    
    # Fresh server detection with multiple indicators
    local fresh_indicators=0
    local fresh_reasons=()
    
    log "DEBUG" "Starting fresh server detection..."
    
    # Temporarily disable strict error handling for system checks
    set +euo pipefail
    
    # Check 1: Root user
    if [[ $EUID -eq 0 ]]; then
        ((fresh_indicators++))
        fresh_reasons+=("Running as root user")
        log "DEBUG" "Fresh indicator: Running as root"
    fi
    
    # Check 2: Milou user existence
    log "DEBUG" "Checking milou user existence..."
    local milou_user_missing=true
    if command -v milou_user_exists >/dev/null 2>&1; then
        if milou_user_exists 2>/dev/null; then
            milou_user_missing=false
        fi
    fi
    
    if [[ "$milou_user_missing" == "true" ]]; then
        ((fresh_indicators++))
        fresh_reasons+=("No dedicated milou user")
        log "DEBUG" "Fresh indicator: No milou user"
    fi
    
    # Check 3: Configuration file
    log "DEBUG" "Checking configuration file..."
    if [[ ! -f "${ENV_FILE:-}" ]]; then
        ((fresh_indicators++))
        fresh_reasons+=("No existing configuration")
        log "DEBUG" "Fresh indicator: No config file"
    else
        log "DEBUG" "Found configuration file: $ENV_FILE"
    fi
    
    # Check 4: Docker installation
    log "DEBUG" "Checking Docker installation..."
    if ! command -v docker >/dev/null 2>&1; then
        ((fresh_indicators++))
        fresh_reasons+=("Docker not installed")
        needs_deps_install=true
        log "DEBUG" "Fresh indicator: Docker not installed"
    fi
    
    # Check 5: Existing containers (only if Docker is available)
    log "DEBUG" "Checking existing containers..."
    local has_containers=false
    if command -v docker >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then
            local container_output
            container_output=$(docker ps -a --filter "name=static-" --quiet 2>/dev/null || echo "")
            if [[ -n "$container_output" ]]; then
                has_containers=true
                log "DEBUG" "Found existing containers"
            fi
        else
            log "DEBUG" "Docker daemon not accessible"
        fi
    fi
    
    if [[ "$has_containers" == "false" ]]; then
        ((fresh_indicators++))
        fresh_reasons+=("No existing Milou containers")
        log "DEBUG" "Fresh indicator: No containers"
    fi
    
    # Re-enable strict error handling
    set -euo pipefail
    
    log "DEBUG" "Fresh indicators found: $fresh_indicators"
    
    # Determine if this is a fresh server (3+ indicators)
    if [[ $fresh_indicators -ge 3 ]] || [[ "${FRESH_INSTALL:-false}" == "true" ]]; then
        is_fresh_server=true
        log "INFO" "🆕 Fresh server installation detected"
        for reason in "${fresh_reasons[@]}"; do
            log "INFO" "   • $reason"
        done
    else
        log "INFO" "🔄 Existing system setup detected"
    fi
    
    echo
    
    # Step 2: Prerequisites Assessment (Non-blocking)
    log "STEP" "Step 2: Prerequisites Assessment"
    echo
    
    # Quick assessment without blocking
    local missing_deps=()
    local warnings=()
    local prereq_status="good"
    
    # Check critical dependencies
    if ! command -v docker >/dev/null 2>&1; then
        missing_deps+=("Docker")
        needs_deps_install=true
    elif ! docker info >/dev/null 2>&1; then
        warnings+=("Docker daemon not accessible")
    fi
    
    if ! docker compose version >/dev/null 2>&1; then
        missing_deps+=("Docker Compose")
    fi
    
    # Check system tools
    local -a tools=("curl" "wget" "jq" "openssl")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_deps+=("$tool")
        fi
    done
    
    # Report status
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        prereq_status="missing"
        log "WARN" "⚠️  Missing dependencies: ${missing_deps[*]}"
    elif [[ ${#warnings[@]} -gt 0 ]]; then
        prereq_status="warnings"
        log "WARN" "⚠️  Warnings: ${warnings[*]}"
    else
        prereq_status="good"
        log "SUCCESS" "✅ All prerequisites satisfied"
    fi
    
    echo
    
    # Step 3: Smart Setup Mode Selection
    log "STEP" "Step 3: Setup Mode Selection"
    echo
    
    # Determine setup mode based on conditions and flags
    if [[ -n "$GITHUB_TOKEN" ]] || [[ "${INTERACTIVE:-true}" == "false" ]]; then
        setup_mode="non-interactive"
        log "INFO" "🤖 Non-interactive mode selected"
    else
        setup_mode="interactive"
        log "INFO" "🎯 Interactive mode selected"
    fi
    
    # Handle fresh server optimization
    if [[ "$is_fresh_server" == "true" ]]; then
        log "INFO" "🚀 Fresh server optimizations enabled"
        
        # Auto-enable dependency installation for fresh servers
        if [[ "$needs_deps_install" == "true" ]] && [[ "${AUTO_INSTALL_DEPS:-false}" != "true" ]]; then
            if [[ "${FRESH_INSTALL:-false}" == "true" ]]; then
                AUTO_INSTALL_DEPS=true
                export AUTO_INSTALL_DEPS
                log "INFO" "✅ Auto-dependency installation enabled"
            fi
        fi
        
        # Auto-enable user creation for fresh servers
        if [[ "$needs_user_management" == "true" ]] && [[ "${AUTO_CREATE_USER:-false}" != "true" ]]; then
            if [[ "${FRESH_INSTALL:-false}" == "true" ]]; then
                AUTO_CREATE_USER=true
                export AUTO_CREATE_USER
                log "INFO" "✅ Auto-user creation enabled"
            fi
        fi
    fi
    
    echo
    
    # Step 4: Dependencies Resolution (Optional)
    if [[ "$prereq_status" == "missing" ]]; then
        log "STEP" "Step 4: Dependencies Resolution"
        echo
        
        local install_deps=false
        
        # Determine if we should install dependencies
        if [[ "${AUTO_INSTALL_DEPS:-false}" == "true" ]]; then
            install_deps=true
            log "INFO" "🔧 Auto-installing dependencies..."
        elif [[ "$setup_mode" == "interactive" ]]; then
            echo "Missing dependencies can be installed automatically or manually."
            echo "Dependencies needed: ${missing_deps[*]}"
            echo
            
            if confirm "Install missing dependencies automatically?" "Y"; then
                install_deps=true
            else
                log "INFO" "📋 Manual installation will be required"
                echo
                log "INFO" "💡 Manual installation commands:"
                show_manual_installation_commands
                echo
                
                if ! confirm "Continue setup without installing dependencies?" "N"; then
                    log "INFO" "Setup cancelled - please install dependencies and try again"
                    exit 0
                fi
            fi
        else
            # Non-interactive mode - require dependencies
            log "ERROR" "Missing dependencies in non-interactive mode"
            log "INFO" "💡 Solutions:"
            log "INFO" "  • Run: $0 setup --auto-install-deps"
            log "INFO" "  • Run: $0 install-deps (install separately)"
            log "INFO" "  • Install manually and retry setup"
            exit 1
        fi
        
        # Install dependencies if requested
        if [[ "$install_deps" == "true" ]]; then
            if [[ $EUID -eq 0 ]]; then
                if install_prerequisites "true" "false" "true"; then
                    log "SUCCESS" "✅ Dependencies installed successfully"
                    prereq_status="good"
                else
                    log "ERROR" "Failed to install dependencies"
                    if [[ "$setup_mode" == "interactive" ]] && confirm "Continue anyway?" "N"; then
                        log "WARN" "Continuing with missing dependencies"
                    else
                        exit 1
                    fi
                fi
            else
                log "ERROR" "Root privileges required for dependency installation"
                log "INFO" "💡 Run: sudo $0 setup --auto-install-deps"
                log "INFO" "💡 Or: sudo $0 install-deps && $0 setup"
                
                if [[ "$setup_mode" == "interactive" ]] && confirm "Continue without installing dependencies?" "N"; then
                    log "WARN" "Continuing with missing dependencies"
                else
                    exit 1
                fi
            fi
        fi
        
        echo
    fi
    
    # Step 5: User Management (For fresh servers or root users)
    if [[ "${SKIP_USER_CHECK:-false}" != "true" ]]; then
        if is_running_as_root || [[ "$is_fresh_server" == "true" ]]; then
            log "STEP" "Step 5: User Management"
            echo
            
            if is_running_as_root && (! command -v milou_user_exists >/dev/null 2>&1 || ! milou_user_exists); then
                local create_user=false
                
                if [[ "${AUTO_CREATE_USER:-false}" == "true" ]]; then
                    create_user=true
                    log "INFO" "🔧 Auto-creating milou user..."
                elif [[ "$setup_mode" == "interactive" ]]; then
                    echo "For security and best practices, Milou should run as a dedicated user."
                    echo "This will create a 'milou' user and continue setup from there."
                    echo
                    
                    if confirm "Create dedicated milou user?" "Y" 10; then
                        create_user=true
                    else
                        log "INFO" "Continuing as root (not recommended for production)"
                    fi
                else
                    # Non-interactive mode - create user automatically for fresh installs
                    if [[ "$is_fresh_server" == "true" ]]; then
                        create_user=true
                        log "INFO" "🔧 Creating milou user for fresh server setup..."
                    fi
                fi
                
                if [[ "$create_user" == "true" ]]; then
                    if create_milou_user; then
                        log "SUCCESS" "✅ Milou user created successfully"
                        log "INFO" "🔄 Switching to milou user to continue setup..."
                        switch_to_milou_user "$@"
                        return $?  # This should never be reached due to exec
                    else
                        log "ERROR" "Failed to create milou user"
                        if [[ "$setup_mode" == "interactive" ]] && confirm "Continue as root?" "N"; then
                            log "WARN" "Continuing as root (not recommended)"
                        else
                            exit 1
                        fi
                    fi
                fi
            elif command -v milou_user_exists >/dev/null 2>&1 && milou_user_exists && is_running_as_root; then
                log "INFO" "Milou user exists - switching for secure setup..."
                switch_to_milou_user "$@"
                return $?  # This should never be reached due to exec
            fi
            
            echo
        fi
    fi
    
    # Step 6: Execute Setup
    log "STEP" "Step 6: Milou Configuration"
    echo
    
    case "$setup_mode" in
        "interactive")
            log "INFO" "🎯 Starting interactive setup wizard..."
            interactive_setup_wizard
            ;;
        "non-interactive")
            log "INFO" "🤖 Starting non-interactive setup..."
            handle_non_interactive_setup "$@"
            ;;
        *)
            log "ERROR" "Unknown setup mode: $setup_mode"
            exit 1
            ;;
    esac
}

# Helper function to show manual installation commands
show_manual_installation_commands() {
    local distro_id=""
    local pkg_manager=""
    
    if command -v detect_distribution >/dev/null 2>&1; then
        distro_id=$(detect_distribution)
        pkg_manager=$(detect_package_manager)
    else
        # Fallback detection
        if command -v apt-get >/dev/null 2>&1; then
            pkg_manager="apt"
        elif command -v dnf >/dev/null 2>&1; then
            pkg_manager="dnf"
        elif command -v yum >/dev/null 2>&1; then
            pkg_manager="yum"
        fi
    fi
    
    log "INFO" "📋 Manual Installation Commands:"
    
    # Docker installation
    log "INFO" "  Docker:"
    case "$pkg_manager" in
        "apt")
            log "INFO" "    sudo apt-get update && sudo apt-get install -y docker.io docker-compose-plugin"
            ;;
        "dnf")
            log "INFO" "    sudo dnf install -y docker docker-compose-plugin"
            ;;
        "yum")
            log "INFO" "    sudo yum install -y docker docker-compose-plugin"
            ;;
        *)
            log "INFO" "    curl -fsSL https://get.docker.com | sh"
            ;;
    esac
    
    # System tools
    log "INFO" "  System tools:"
    case "$pkg_manager" in
        "apt")
            log "INFO" "    sudo apt-get install -y curl wget jq openssl git"
            ;;
        "dnf"|"yum")
            log "INFO" "    sudo $pkg_manager install -y curl wget jq openssl git"
            ;;
        *)
            log "INFO" "    Install curl, wget, jq, openssl, git using your package manager"
            ;;
    esac
    
    # Docker service
    log "INFO" "  Docker service:"
    log "INFO" "    sudo systemctl enable docker && sudo systemctl start docker"
    log "INFO" "    sudo usermod -aG docker \$USER && newgrp docker"
}

handle_non_interactive_setup() {
    log "STEP" "Running non-interactive setup..."
    log "INFO" "Image versioning strategy: $([ "$USE_LATEST_IMAGES" == true ] && echo "Latest available versions" || echo "Fixed version (v1.0.0)")"
    
    # Set defaults with validation
    local domain="${DOMAIN:-localhost}"
    local ssl_path="${SSL_PATH:-./ssl}"
    local admin_email="${ADMIN_EMAIL:-}"
    
    # Enhanced input validation
    if [[ -z "$GITHUB_TOKEN" ]]; then
        if [[ "${INTERACTIVE:-true}" == "true" ]]; then
            log "WARN" "No GitHub token provided, switching to interactive mode"
            interactive_setup_wizard
            return $?
        else
            error_exit "GitHub token is required for non-interactive setup. Use --token option."
        fi
    fi
    
    # Validate domain format
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$|^localhost$ ]]; then
        log "WARN" "Invalid domain format: $domain, using localhost"
        domain="localhost"
    fi
    
    # Run setup steps with better error handling
    log "STEP" "Checking system requirements..."
    check_system_requirements
    
    log "STEP" "Authenticating with GitHub..."
    if ! test_github_authentication "$GITHUB_TOKEN"; then
        error_exit "GitHub authentication failed. Please check your token."
    fi
    
    log "STEP" "Generating configuration..."
    if ! generate_config "$domain" "$ssl_path" "$admin_email"; then
        error_exit "Configuration generation failed"
    fi
    
    # SSL setup with enhanced fallbacks
    log "STEP" "Setting up SSL certificates for $domain..."
    mkdir -p "$ssl_path"
    
    if setup_ssl "$ssl_path" "$domain"; then
        log "SUCCESS" "SSL certificates ready"
    else
        error_exit "SSL setup failed - please check your configuration"
    fi
    
    # Verify certificates exist
    if [[ ! -f "$ssl_path/milou.crt" || ! -f "$ssl_path/milou.key" ]]; then
        error_exit "SSL certificate files are missing after setup"
    fi
    
    # Enhanced image pulling with retry logic
    log "STEP" "Pulling Docker images..."
    log "INFO" "Strategy: $([ "$USE_LATEST_IMAGES" == true ] && echo "latest versions" || echo "fixed v1.0.0")"
    
    local pull_attempts=0
    local max_attempts=3
    
    while [[ $pull_attempts -lt $max_attempts ]]; do
        if pull_images "$GITHUB_TOKEN" "$USE_LATEST_IMAGES"; then
            break
        else
            ((pull_attempts++))
            if [[ $pull_attempts -lt $max_attempts ]]; then
                log "WARN" "Image pull failed (attempt $pull_attempts/$max_attempts), retrying in 5 seconds..."
                sleep 5
            else
                if [[ "$FORCE" == true ]]; then
                    log "WARN" "Image pull failed after $max_attempts attempts, but --force flag is set"
                    break
                else
                    log "ERROR" "Image pull failed after $max_attempts attempts"
                    log "INFO" "💡 Try: $0 debug-images --token YOUR_TOKEN"
                    log "INFO" "💡 Or use --force to continue anyway"
                    error_exit "Failed to pull Docker images"
                fi
            fi
        fi
    done
    
    # Enhanced service startup
    log "STEP" "Starting services..."
    if start_services_with_checks; then
        log "SUCCESS" "${ROCKET_EMOJI} Non-interactive setup complete!"
        log "INFO" "🌐 Access your instance at: https://$domain"
        if [[ "$domain" == "localhost" ]]; then
            log "INFO" "🏠 Local access: https://localhost"
        fi
        
        # Enhanced health check
        log "INFO" "Performing initial health check..."
        sleep 5
        if show_service_status; then
            log "SUCCESS" "All services are running correctly!"
        else
            log "WARN" "Some services may need more time to start"
            log "INFO" "💡 Run '$0 status' later to check service health"
        fi
    else
        log "ERROR" "Failed to start services"
        log "INFO" "💡 You can try starting manually with: $0 start"
        log "INFO" "💡 Check logs with: $0 logs"
        exit 1
    fi
}

# Enhanced start handler with better checks
handle_start() {
    # Check if already running
    if check_services_running >/dev/null 2>&1; then
        log "INFO" "Services are already running"
        show_service_status
        return 0
    fi
    
    log "STEP" "Starting Milou services..."
    if start_services_with_checks; then
        log "SUCCESS" "Services started successfully"
    else
        error_exit "Failed to start services"
    fi
}

# Enhanced handlers for other commands  
handle_stop() {
    log "STEP" "Stopping Milou services..."
    if stop_services; then
        log "SUCCESS" "Services stopped successfully"
    else
        error_exit "Failed to stop services"
    fi
}

handle_restart() {
    log "STEP" "Restarting Milou services..."
    if restart_services; then
        log "SUCCESS" "Services restarted successfully"
    else
        error_exit "Failed to restart services"
    fi
}

handle_status() {
    show_service_status
}

handle_detailed_status() {
    show_detailed_status
}

handle_logs() {
    local service="${1:-}"
    
    cd "$SCRIPT_DIR" || error_exit "Cannot change to script directory"
    
    if [[ -n "$service" ]]; then
        log "INFO" "Viewing logs for service: $service"
        run_docker_compose logs --tail=100 -f "$service"
    else
        log "INFO" "Viewing logs for all services"
        run_docker_compose logs --tail=100 -f
    fi
}

handle_health() {
    log "STEP" "Running comprehensive health checks..."
    
    # System requirements check
    if ! check_system_requirements; then
        log "ERROR" "System requirements check failed"
        return 1
    fi
    
    # Configuration validation
    if ! validate_configuration; then
        log "ERROR" "Configuration validation failed"
        return 1
    fi
    
    # Service health check
    if ! show_service_status; then
        log "ERROR" "Service health check failed"
        return 1
    fi
    
    log "SUCCESS" "All health checks passed!"
    return 0
}

handle_config() {
    if [[ -f "$ENV_FILE" ]]; then
        log "INFO" "Current configuration:"
        echo
        # Show configuration but hide sensitive values
        sed 's/=.*PASSWORD.*/=***HIDDEN***/g; s/=.*SECRET.*/=***HIDDEN***/g; s/=.*KEY.*/=***HIDDEN***/g; s/=.*TOKEN.*/=***HIDDEN***/g' "$ENV_FILE"
    else
        error_exit "Configuration file not found. Please run setup first."
    fi
}

handle_validate() {
    log "STEP" "Validating Milou installation..."
    
    local issues=0
    
    if ! validate_configuration; then
        ((issues++))
    fi
    
    if ! check_system_requirements; then
        ((issues++))
    fi
    
    if [[ $issues -eq 0 ]]; then
        log "SUCCESS" "Validation completed - no issues found"
        return 0
    else
        log "ERROR" "Validation found $issues issue(s)"
        return 1
    fi
}

handle_backup() {
    local backup_type="full"
    
    # Parse backup arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)
                backup_type="$2"
                shift 2
                ;;
            --config-only)
                backup_type="config"
                shift
                ;;
            --list)
                list_backups
                return $?
                ;;
            --clean)
                local days="${2:-30}"
                if [[ "$2" =~ ^[0-9]+$ ]]; then
                    shift 2
                else
                    shift
                fi
                clean_old_backups "$days"
                return $?
                ;;
            --help)
                show_backup_help
                return 0
                ;;
            *)
                shift
                ;;
        esac
    done
    
    log "INFO" "Creating $backup_type backup..."
    if create_backup "$backup_type"; then
        log "SUCCESS" "Backup created successfully"
    else
        error_exit "Failed to create backup"
    fi
}

handle_restore() {
    local backup_file="$1"
    if [[ -z "$backup_file" ]]; then
        error_exit "Backup file path is required. Usage: $(basename "$0") restore [backup_file]"
    fi
    
    if [[ ! -f "$backup_file" ]]; then
        error_exit "Backup file does not exist: $backup_file"
    fi
    
    log "INFO" "Restoring from backup: $backup_file"
    if restore_backup "$backup_file"; then
        log "SUCCESS" "Restore completed successfully"
    else
        error_exit "Failed to restore from backup"
    fi
}

handle_update() {
    log "STEP" "Checking for updates..."
    if update_milou; then
        log "SUCCESS" "Update completed successfully"
    else
        error_exit "Failed to update"
    fi
}

handle_ssl() {
    local domain="${DOMAIN:-localhost}"
    local ssl_path="${SSL_PATH:-./ssl}"
    
    # Parse SSL-specific arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --domain)
                domain="$2"
                shift 2
                ;;
            --ssl-path)
                ssl_path="$2"
                shift 2
                ;;
            --status)
                # Pass through to ssl-manager for status
                if [[ -f "./ssl-manager.sh" ]]; then
                    exec ./ssl-manager.sh status
                else
                    # Fallback to basic SSL status check
                    log "INFO" "SSL Certificate Status Report"
                    echo
                    log "INFO" "Configuration:"
                    echo "  SSL Path: $ssl_path"
                    echo "  Domain: $domain"
                    echo
                    
                    if [[ -f "$ssl_path/milou.crt" && -f "$ssl_path/milou.key" ]]; then
                        log "INFO" "Certificate Files Found:"
                        echo "  Certificate: $ssl_path/milou.crt"
                        echo "  Private Key: $ssl_path/milou.key"
                        
                        # Check expiration
                        if command -v openssl >/dev/null 2>&1; then
                            local exp_date
                            exp_date=$(openssl x509 -in "$ssl_path/milou.crt" -noout -enddate 2>/dev/null | cut -d= -f2)
                            if [[ -n "$exp_date" ]]; then
                                echo "  Expires: $exp_date"
                            fi
                        fi
                    else
                        log "WARN" "No SSL certificates found"
                    fi
                fi
                return 0
                ;;
            --validate)
                if [[ -f "./ssl-manager.sh" ]]; then
                    exec ./ssl-manager.sh validate
                else
                    # Fallback validation
                    if [[ -f "$ssl_path/milou.crt" && -f "$ssl_path/milou.key" ]]; then
                        log "SUCCESS" "SSL certificates exist"
                        if command -v openssl >/dev/null 2>&1; then
                            if openssl x509 -in "$ssl_path/milou.crt" -noout -text >/dev/null 2>&1; then
                                log "SUCCESS" "Certificate is valid"
                            else
                                log "ERROR" "Certificate appears to be corrupted"
                                return 1
                            fi
                        fi
                    else
                        log "ERROR" "SSL certificates not found"
                        return 1
                    fi
                fi
                return 0
                ;;
            --clean)
                if [[ -f "./ssl-manager.sh" ]]; then
                    exec ./ssl-manager.sh clean
                else
                    # Fallback clean
                    log "STEP" "Cleaning up SSL certificates..."
                    if [[ -d "$ssl_path" ]]; then
                        find "$ssl_path" -name "*.crt" -o -name "*.key" -o -name "*.pem" | while read -r file; do
                            log "INFO" "Removing: $file"
                            rm -f "$file"
                        done
                        log "SUCCESS" "SSL cleanup completed"
                    else
                        log "INFO" "No SSL directory found to clean"
                    fi
                fi
                return 0
                ;;
            --consolidate)
                if [[ -f "./ssl-manager.sh" ]]; then
                    exec ./ssl-manager.sh consolidate
                else
                    log "WARN" "Consolidation requires ssl-manager.sh"
                    return 1
                fi
                ;;
            --help)
                show_ssl_help
                return 0
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Default action: SSL setup
    log "STEP" "SSL Certificate Management for domain: $domain"
    
    mkdir -p "$ssl_path"
    
    if setup_ssl "$ssl_path" "$domain"; then
        log "SUCCESS" "SSL certificates ready"
        log "INFO" "📄 Certificate: $ssl_path/milou.crt"
        log "INFO" "🔑 Private key: $ssl_path/milou.key"
        
        if check_ssl_expiration "$ssl_path"; then
            log "SUCCESS" "SSL certificates are valid and not expiring soon"
        fi
    else
        error_exit "SSL setup failed"
    fi
}

handle_cleanup() {
    local cleanup_type="regular"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --complete)
                cleanup_type="complete"
                shift
                ;;
            --help)
                show_cleanup_help
                return 0
                ;;
            *)
                shift
                ;;
        esac
    done
    
    case "$cleanup_type" in
        "complete")
            log "INFO" "Performing COMPLETE cleanup of all Milou resources..."
            complete_cleanup_milou_resources
            ;;
        "regular")
            log "INFO" "Performing regular Docker cleanup..."
            cleanup_docker_resources
            ;;
    esac
}

handle_shell() {
    local service="$1"
    
    if [[ -z "$service" ]]; then
        log "ERROR" "Service name is required"
        log "INFO" "Available services: backend, frontend, engine, nginx, db, redis, rabbitmq"
        exit 1
    fi
    
    cd "$SCRIPT_DIR" || error_exit "Cannot change to script directory"
    
    if ! run_docker_compose ps "$service" | grep -q "Up"; then
        error_exit "Service $service is not running"
    fi
    
    log "INFO" "Opening shell in $service container..."
    run_docker_compose exec "$service" /bin/bash || \
    run_docker_compose exec "$service" /bin/sh
}

handle_debug_images() {
    local token="${GITHUB_TOKEN:-}"
    
    if [[ -z "$token" ]]; then
        log "ERROR" "GitHub token is required for image debugging"
        log "INFO" "Usage: $0 debug-images --token YOUR_TOKEN"
        return 1
    fi
    
    debug_docker_images "$token"
}

handle_diagnose() {
    log "STEP" "Running comprehensive system diagnostics..."
    
    if ! diagnose_docker_environment; then
        log "WARN" "Some issues were found during diagnosis"
        echo
        log "INFO" "Recommended actions:"
        log "INFO" "  • Fix critical issues shown above"
        log "INFO" "  • Run '$0 setup' if configuration is missing"
        log "INFO" "  • Run '$0 health' for service health check"
        return 1
    fi
    
    return 0
}

handle_health_check() {
    quick_health_check
}

# User management handlers
handle_user_status() {
    show_user_status
}

handle_create_user() {
    if ! is_running_as_root; then
        log "ERROR" "Root privileges required to create user"
        log "INFO" "Please run with sudo: sudo $0 create-user"
        exit 1
    fi
    
    if milou_user_exists; then
        log "INFO" "User $MILOU_USER already exists"
        show_user_status
        exit 0
    fi
    
    log "INFO" "Creating dedicated milou user..."
    if create_milou_user; then
        log "SUCCESS" "User created successfully!"
        log "INFO" "💡 Run commands as: sudo -u milou $0 [command]"
        
        if [[ "${INTERACTIVE:-true}" == "true" ]]; then
            if confirm "Apply security hardening?" "Y"; then
                harden_milou_user
            fi
            
            if confirm "Switch to milou user now?" "Y"; then
                preserve_original_command "${ORIGINAL_COMMAND:-}" "${ORIGINAL_ARGUMENTS[@]}"
                switch_to_milou_user
            fi
        fi
    else
        error_exit "Failed to create milou user"
    fi
}

handle_migrate_user() {
    if ! is_running_as_root; then
        log "ERROR" "Root privileges required for user migration"
        log "INFO" "Please run with sudo: sudo $0 migrate-user"
        exit 1
    fi
    
    log "INFO" "Migrating to dedicated milou user..."
    if migrate_to_milou_user; then
        log "SUCCESS" "Migration completed!"
        
        if [[ "${INTERACTIVE:-true}" == "true" ]] && confirm "Switch to milou user now?" "Y"; then
            preserve_original_command "${ORIGINAL_COMMAND:-}" "${ORIGINAL_ARGUMENTS[@]}"
            switch_to_milou_user
        fi
    else
        error_exit "Migration failed"
    fi
}

# Security handlers
run_comprehensive_security_assessment() {
    log "STEP" "Running comprehensive security assessment..."
    
    if run_security_assessment; then
        log "SUCCESS" "Security assessment completed - no critical issues found"
        return 0
    else
        log "WARN" "Security assessment found issues"
        log "INFO" "💡 Consider running: $0 security-harden (requires sudo)"
        return 1
    fi
}

apply_security_hardening_measures() {
    if ! is_running_as_root; then
        log "ERROR" "Root privileges required for security hardening"
        log "INFO" "Please run with sudo: sudo $0 security-harden"
        exit 1
    fi
    
    echo
    echo -e "${BOLD}${YELLOW}⚠️  Security Hardening Warning${NC}"
    echo "This will apply security hardening measures that may modify:"
    echo "  • File permissions"
    echo "  • Docker daemon configuration"
    echo "  • Firewall rules"
    echo "  • System security settings"
    echo
    
    if [[ "${INTERACTIVE:-true}" == "true" ]] && ! confirm "Apply security hardening?" "N"; then
        log "INFO" "Security hardening cancelled"
        exit 0
    fi
    
    log "INFO" "Applying security hardening..."
    if harden_system; then
        log "SUCCESS" "Security hardening completed!"
        log "INFO" "💡 Run security assessment: $0 security-check"
        
        if [[ "${INTERACTIVE:-true}" == "true" ]] && confirm "Restart Docker daemon?" "Y"; then
            systemctl restart docker || log "WARN" "Failed to restart Docker daemon"
        fi
    else
        error_exit "Security hardening failed"
    fi
}

generate_detailed_security_report() {
    local report_file="milou-security-report-$(date +%Y%m%d_%H%M%S).txt"
    
    log "INFO" "Generating security report..."
    if create_security_report "$report_file"; then
        log "SUCCESS" "Security report generated: $report_file"
        
        if command -v less >/dev/null 2>&1 && [[ "${INTERACTIVE:-true}" == "true" ]]; then
            if confirm "View the report now?" "Y"; then
                less "$report_file"
            fi
        fi
    else
        error_exit "Failed to generate security report"
    fi
}

# System dependencies installation handler
install_system_dependencies() {
    local enable_firewall=false
    local auto_install=true
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --enable-firewall)
                enable_firewall=true
                shift
                ;;
            --manual)
                auto_install=false
                shift
                ;;
            --help)
                show_install_deps_help
                return 0
                ;;
            *)
                shift
                ;;
        esac
    done
    
    log "STEP" "Installing system dependencies for Milou..."
    
    # Check if we need root privileges
    if [[ "$auto_install" == "true" ]] && [[ $EUID -ne 0 ]]; then
        log "ERROR" "Root privileges required for automatic installation"
        log "INFO" "Please run with sudo: sudo $0 install-deps"
        log "INFO" "Or use manual mode: $0 install-deps --manual"
        exit 1
    fi
    
    if install_prerequisites "$auto_install" "$enable_firewall" "false"; then
        log "SUCCESS" "✅ System dependencies installation completed!"
        echo
        log "INFO" "🎯 Next Steps:"
        log "INFO" "  • Run: $0 setup (to configure Milou)"
        log "INFO" "  • Run: $0 diagnose (to verify installation)"
        
        # If user was added to docker group, suggest relogin
        if [[ $EUID -ne 0 ]] && ! groups | grep -q docker && command -v docker >/dev/null 2>&1; then
            echo
            log "INFO" "⚠️  IMPORTANT: You may need to log out and back in for Docker group changes to take effect"
            log "INFO" "💡 Or run: newgrp docker"
        fi
    else
        error_exit "System dependencies installation failed"
    fi
}

show_install_deps_help() {
    echo "System Dependencies Installation:"
    echo
    echo "  Basic installation:"
    echo "    sudo $0 install-deps                    # Install all dependencies automatically"
    echo
    echo "  Advanced options:"
    echo "    sudo $0 install-deps --enable-firewall  # Also configure basic firewall rules"
    echo "    $0 install-deps --manual                 # Show manual installation instructions"
    echo
    echo "  What gets installed:"
    echo "    • Docker and Docker Compose"
    echo "    • Required system tools (curl, wget, jq, openssl, git)"
    echo "    • Docker service configuration"
    echo "    • User permissions for Docker"
    echo "    • Optional: Basic firewall configuration"
}

# =============================================================================
# Enhanced Help Functions
# =============================================================================

show_backup_help() {
    echo "Backup Management:"
    echo
    echo "  Create backups:"
    echo "    $0 backup                    # Full backup"
    echo "    $0 backup --config-only      # Configuration only"
    echo "    $0 backup --type config      # Same as --config-only"
    echo
    echo "  Manage backups:"
    echo "    $0 backup --list             # List all backups"
    echo "    $0 backup --clean            # Clean old backups (30 days)"
    echo "    $0 backup --clean 7          # Clean backups older than 7 days"
    echo
    echo "  Restore:"
    echo "    $0 restore backup_file.tar.gz # Restore from backup"
}

show_ssl_help() {
    echo "SSL Certificate Management:"
    echo
    echo "  Basic operations:"
    echo "    $0 ssl                       # Setup SSL for default domain"
    echo "    $0 ssl --domain example.com  # Setup SSL for custom domain"
    echo
    echo "  Certificate management:"
    echo "    $0 ssl --status              # Check certificate status"
    echo "    $0 ssl --validate            # Validate certificates"
    echo "    $0 ssl --clean               # Clean up certificates"
    echo "    $0 ssl --consolidate         # Consolidate scattered certificates"
    echo
    echo "  Advanced:"
    echo "    ./ssl-manager.sh --help      # Advanced SSL operations"
}

show_cleanup_help() {
    echo "Cleanup Commands:"
    echo
    echo "  Regular cleanup (safe):"
    echo "    $0 cleanup"
    echo "    • Removes unused Docker images"
    echo "    • Removes unused volumes (with confirmation)"
    echo "    • Removes unused networks"
    echo
    echo "  Complete cleanup (destructive):"
    echo "    $0 cleanup --complete"
    echo "    • Removes ALL Milou containers"
    echo "    • Removes ALL Milou images"
    echo "    • Removes ALL Milou volumes"
    echo "    • Removes ALL Milou networks"
    echo "    • Removes configuration files"
    echo "    • Removes SSL certificates (with confirmation)"
    echo
    echo "  Options:"
    echo "    --force      Skip confirmation prompts"
    echo "    --help       Show this help"
}

# =============================================================================
# Enhanced Main Function
# =============================================================================

main() {
    # If no command provided, show help
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    # Store original arguments for state preservation
    local original_args=("$@")
    local command="$1"
    shift

    # Enhanced argument parsing with better error handling
    local -a remaining_args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose)
                VERBOSE=true
                export VERBOSE
                shift
                ;;
            --force)
                FORCE=true
                export FORCE
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                export DRY_RUN
                shift
                ;;
            --token)
                if [[ -n "${2:-}" ]]; then
                    GITHUB_TOKEN="$2"
                    export GITHUB_TOKEN
                    shift 2
                else
                    error_exit "GitHub token value is required after --token"
                fi
                ;;
            --domain)
                if [[ -n "${2:-}" ]]; then
                    DOMAIN="$2"
                    export DOMAIN
                    shift 2
                else
                    error_exit "Domain value is required after --domain"
                fi
                ;;
            --ssl-path)
                if [[ -n "${2:-}" ]]; then
                    SSL_PATH="$2"
                    export SSL_PATH
                    shift 2
                else
                    error_exit "SSL path value is required after --ssl-path"
                fi
                ;;
            --email)
                if [[ -n "${2:-}" ]]; then
                    ADMIN_EMAIL="$2"
                    export ADMIN_EMAIL
                    shift 2
                else
                    error_exit "Email value is required after --email"
                fi
                ;;
            --latest)
                USE_LATEST_IMAGES=true
                export USE_LATEST_IMAGES
                shift
                ;;
            --non-interactive)
                INTERACTIVE=false
                export INTERACTIVE
                shift
                ;;
            --auto-create-user)
                AUTO_CREATE_USER=true
                export AUTO_CREATE_USER
                shift
                ;;
            --skip-user-check)
                SKIP_USER_CHECK=true
                export SKIP_USER_CHECK
                shift
                ;;
            --auto-install-deps)
                AUTO_INSTALL_DEPS=true
                export AUTO_INSTALL_DEPS
                shift
                ;;
            --fresh-install)
                FRESH_INSTALL=true
                AUTO_CREATE_USER=true  # Automatically enable auto-create-user for fresh installs
                AUTO_INSTALL_DEPS=true  # Automatically enable auto-install-deps for fresh installs
                export FRESH_INSTALL
                export AUTO_CREATE_USER
                export AUTO_INSTALL_DEPS
                shift
                ;;
            --help|-h)
                # Command-specific help
                if [[ "$command" == "cleanup" || "$command" == "backup" || "$command" == "ssl" ]]; then
                    remaining_args+=("$1")
                    shift
                else
                    show_help
                    exit 0
                fi
                ;;
            *)
                remaining_args+=("$1")
                shift
                ;;
        esac
    done
    
    # Log script start with enhanced information
    log "DEBUG" "Milou CLI v$SCRIPT_VERSION started"
    log "DEBUG" "Command: $command, User: $(whoami), PID: $$"
    log "DEBUG" "Working directory: $(pwd)"
    
    # Check if we're resuming after user switch
    if check_user_switch_resume; then
        log "DEBUG" "Resuming operation after user switch"
        command="$ORIGINAL_COMMAND"
        # Parse the arguments from the string
        if [[ -n "${ORIGINAL_ARGUMENTS_STR:-}" ]]; then
            eval "remaining_args=($ORIGINAL_ARGUMENTS_STR)"
        fi
    fi
    
    # Enhanced command routing with error handling
    case "$command" in
        setup)
            handle_setup "${remaining_args[@]}"
            ;;
        start)
            handle_start "${remaining_args[@]}"
            ;;
        stop)
            handle_stop "${remaining_args[@]}"
            ;;
        restart)
            handle_restart "${remaining_args[@]}"
            ;;
        status)
            handle_status "${remaining_args[@]}"
            ;;
        detailed-status)
            handle_detailed_status "${remaining_args[@]}"
            ;;
        logs)
            handle_logs "${remaining_args[@]}"
            ;;
        health)
            handle_health "${remaining_args[@]}"
            ;;
        health-check)
            handle_health_check "${remaining_args[@]}"
            ;;
        config)
            handle_config "${remaining_args[@]}"
            ;;
        validate)
            handle_validate "${remaining_args[@]}"
            ;;
        backup)
            handle_backup "${remaining_args[@]}"
            ;;
        restore)
            handle_restore "${remaining_args[@]}"
            ;;
        update)
            handle_update "${remaining_args[@]}"
            ;;
        ssl)
            handle_ssl "${remaining_args[@]}"
            ;;
        cleanup)
            handle_cleanup "${remaining_args[@]}"
            ;;
        shell)
            handle_shell "${remaining_args[@]}"
            ;;
        debug-images)
            handle_debug_images "${remaining_args[@]}"
            ;;
        diagnose)
            handle_diagnose "${remaining_args[@]}"
            ;;
        user-status)
            handle_user_status "${remaining_args[@]}"
            ;;
        create-user)
            handle_create_user "${remaining_args[@]}"
            ;;
        migrate-user)
            handle_migrate_user "${remaining_args[@]}"
            ;;
        security-check)
            run_comprehensive_security_assessment "${remaining_args[@]}"
            ;;
        security-harden)
            apply_security_hardening_measures "${remaining_args[@]}"
            ;;
        security-report)
            generate_detailed_security_report "${remaining_args[@]}"
            ;;
        install-deps)
            install_system_dependencies "${remaining_args[@]}"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log "ERROR" "Unknown command: $command"
            echo
            log "INFO" "Available commands:"
            log "INFO" "  setup, start, stop, restart, status, logs, health, config"
            log "INFO" "  backup, restore, update, ssl, cleanup, shell, diagnose"
            log "INFO" "  user-status, create-user, security-check"
            echo
            log "INFO" "Use '$0 help' for detailed information"
            exit 1
            ;;
    esac
}

# =============================================================================
# Enhanced Script Entry Point
# =============================================================================

# Enhanced cleanup on exit
cleanup_on_exit() {
    local exit_code=$?
    log "DEBUG" "Script execution completed with exit code: $exit_code"
    
    # Clean up temporary files
    cleanup_user_management 2>/dev/null || true
    
    # Reset terminal if needed
    if [[ -t 1 ]]; then
        tput sgr0 2>/dev/null || true
    fi
    
    exit $exit_code
}

# Set up signal handlers
trap cleanup_on_exit EXIT
trap 'log "WARN" "Script interrupted by user"; exit 130' INT TERM

# Validate environment before starting
if [[ ! -d "$SCRIPT_DIR" ]]; then
    echo "ERROR: Script directory not found: $SCRIPT_DIR" >&2
    exit 1
fi

if [[ ! -d "$SCRIPT_DIR/utils" ]]; then
    echo "ERROR: Utils directory not found: $SCRIPT_DIR/utils" >&2
    exit 1
fi

# Run main function with all arguments
main "$@"
