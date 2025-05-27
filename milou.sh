#!/bin/bash

set -euo pipefail

# =============================================================================
# Milou Management CLI - Consolidated Edition v3.2.0
# Simplified architecture with consolidated modules
# =============================================================================

# Preserve system PATH to prevent corruption
readonly SYSTEM_PATH="${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"
export PATH="$SYSTEM_PATH"

# Version and Constants
readonly SCRIPT_VERSION="3.2.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# SIMPLE MODULE LOADING - No complex loader needed!
# =============================================================================

# Load all consolidated modules in dependency order
source "${SCRIPT_DIR}/lib/utils.sh"    # Core utilities & logging (must be first)
source "${SCRIPT_DIR}/lib/config.sh"   # Configuration management
source "${SCRIPT_DIR}/lib/ssl.sh"      # SSL certificate management
source "${SCRIPT_DIR}/lib/docker.sh"   # Docker operations
source "${SCRIPT_DIR}/lib/users.sh"    # User management
source "${SCRIPT_DIR}/lib/system.sh"   # System operations

# =============================================================================
# CONFIGURATION
# =============================================================================

# Default Configuration
readonly CONFIG_DIR="${HOME}/.milou"
readonly ENV_FILE="${CONFIG_DIR}/.env"

# Get milou user config directory
get_milou_config_dir() {
    local milou_home
    milou_home=$(getent passwd milou | cut -d: -f6)
    echo "${milou_home}/.milou"
}

# Initialize configuration system
config_init

# Global State
ORIGINAL_COMMAND=""
ORIGINAL_ARGUMENTS=()
ORIGINAL_ARGUMENTS_STR=""
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# Default option values
AUTO_INSTALL_DEPS="${AUTO_INSTALL_DEPS:-false}"
AUTO_CREATE_USER="${AUTO_CREATE_USER:-false}"
SKIP_USER_CHECK="${SKIP_USER_CHECK:-false}"
FRESH_INSTALL="${FRESH_INSTALL:-false}"
DEV_MODE="${DEV_MODE:-false}"
INTERACTIVE="${INTERACTIVE:-true}"
USE_LATEST="${USE_LATEST:-true}"
VERBOSE="${VERBOSE:-false}"
FORCE="${FORCE:-false}"
DRY_RUN="${DRY_RUN:-false}"

# =============================================================================
# ARGUMENT PRESERVATION FOR USER SWITCHING
# =============================================================================

preserve_arguments() {
    ORIGINAL_COMMAND="$1"
    shift
    ORIGINAL_ARGUMENTS=("$@")
    
    # Create a safe string representation for debugging
    local debug_args_str=""
    for arg in "${ORIGINAL_ARGUMENTS[@]}"; do
        if [[ "$arg" =~ ^--token$ ]] || [[ "$arg" =~ ^ghp_ ]]; then
            debug_args_str+="[TOKEN] "
        else
            debug_args_str+="$arg "
        fi
    done
    
    log "DEBUG" "Preserved command: '$ORIGINAL_COMMAND' with ${#ORIGINAL_ARGUMENTS[@]} arguments"
    log "DEBUG" "All arguments (sanitized): $debug_args_str"
    
    # Ensure the GitHub token is properly exported for user switching
    if [[ -n "${GITHUB_TOKEN}" ]]; then
        export GITHUB_TOKEN
        log "DEBUG" "GitHub token preserved for user switching (length: ${#GITHUB_TOKEN})"
    fi
}

# Resume after user switch
resume_after_user_switch() {
    log "DEBUG" "Resuming after user switch with command: $ORIGINAL_COMMAND"
    log "DEBUG" "Original arguments: ${ORIGINAL_ARGUMENTS_STR:-none}"
    
    # Re-execute with preserved arguments
    exec "$0" "$ORIGINAL_COMMAND" "${ORIGINAL_ARGUMENTS[@]}"
}

# =============================================================================
# HELP SYSTEM
# =============================================================================

show_help() {
    # Use direct echo with color codes instead of log function to avoid emoji prefixes
    echo
    echo -e "${BOLD}${PURPLE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${PURPLE}║                    🚀 Milou Management CLI v${SCRIPT_VERSION}                     ║${NC}"
    echo -e "${BOLD}${PURPLE}║              Production-Ready Container Management Platform              ║${NC}"
    echo -e "${BOLD}${PURPLE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    echo -e "${BOLD}${BLUE}📋 USAGE:${NC}"
    echo -e "    ${WHITE}milou.sh${NC} ${CYAN}[COMMAND]${NC} ${YELLOW}[OPTIONS]${NC}"
    echo
    
    echo -e "${BOLD}${BLUE}🎯 MAIN COMMANDS:${NC}"
    echo -e "    ${CYAN}setup${NC}                 🚀 Interactive setup wizard (installs dependencies & configures Milou)"
    echo -e "    ${CYAN}start${NC}                 ▶️  Start all services"
    echo -e "    ${CYAN}stop${NC}                  ⏹️  Stop all services"
    echo -e "    ${CYAN}restart${NC}               🔄 Restart all services"
    echo -e "    ${CYAN}status${NC}                📊 Show detailed status of all services"
    echo -e "    ${CYAN}health${NC}                🏥 Run comprehensive health checks"
    echo
    
    echo -e "${BOLD}${BLUE}🔧 MANAGEMENT COMMANDS:${NC}"
    echo -e "    ${CYAN}logs${NC} ${DIM}[SERVICE]${NC}       📋 View logs for all or specific service"
    echo -e "    ${CYAN}config${NC}                ⚙️  View current configuration"
    echo -e "    ${CYAN}validate${NC}              ✅ Validate configuration and environment"
    echo -e "    ${CYAN}credentials${NC}           🔐 Display current login credentials and access URLs"
    echo -e "    ${CYAN}seed${NC}                  🌱 Run database seeder to populate sample data"
    echo -e "    ${CYAN}shell${NC} ${DIM}[SERVICE]${NC}       🐚 Get shell access to a running container"
    echo
    
    echo -e "${BOLD}${BLUE}💾 BACKUP & MAINTENANCE:${NC}"
    echo -e "    ${CYAN}backup${NC}                💾 Create system backup"
    echo -e "    ${CYAN}restore${NC} ${DIM}[FILE]${NC}       📥 Restore from backup file"
    echo -e "    ${CYAN}update${NC}                🔄 Update to latest version"
    echo -e "    ${CYAN}cleanup${NC}               🧹 Clean up Docker resources"
    echo
    
    echo -e "${BOLD}${BLUE}🔒 SECURITY & SSL:${NC}"
    echo -e "    ${CYAN}ssl${NC}                   🔒 Manage SSL certificates"
    echo -e "    ${CYAN}security-check${NC}        🛡️  Run comprehensive security assessment"
    echo
    
    echo -e "${BOLD}${BLUE}👤 USER & SYSTEM:${NC}"
    echo -e "    ${CYAN}user-status${NC}           👤 Show current user and permission status"
    echo -e "    ${CYAN}create-user${NC}           👥 Create dedicated milou user (requires sudo)"
    echo -e "    ${CYAN}install-deps${NC}          📦 Install system dependencies (Docker, etc.)"
    echo -e "    ${CYAN}build-images${NC}          🔨 Build Docker images locally for development"
    echo
    
    echo -e "${BOLD}${BLUE}❓ HELP:${NC}"
    echo -e "    ${CYAN}help${NC}                  ❓ Show this help message"
    echo
    
    echo -e "${BOLD}${YELLOW}⚙️  COMMON OPTIONS:${NC}"
    echo -e "    ${GREEN}--verbose${NC}             📝 Enable verbose output"
    echo -e "    ${GREEN}--force${NC}               💪 Force operations without confirmation"
    echo -e "    ${GREEN}--dry-run${NC}             👁️  Show what would be done without executing"
    echo -e "    ${GREEN}--non-interactive${NC}     🤖 Run in non-interactive mode"
    echo -e "    ${GREEN}--help, -h${NC}            ❓ Show this help message"
    echo
    
    echo -e "${BOLD}${YELLOW}🔧 SETUP OPTIONS:${NC}"
    echo -e "    ${GREEN}--token${NC} ${DIM}TOKEN${NC}         🔑 GitHub personal access token"
    echo -e "    ${GREEN}--domain${NC} ${DIM}DOMAIN${NC}       🌐 Domain name for SSL certificates"
    echo -e "    ${GREEN}--email${NC} ${DIM}EMAIL${NC}         📧 Admin email address"
    echo -e "    ${GREEN}--ssl-path${NC} ${DIM}PATH${NC}       📁 Path to SSL certificates"
    echo -e "    ${GREEN}--auto-install-deps${NC}   📦 Automatically install missing dependencies"
    echo -e "    ${GREEN}--fresh-install${NC}       🆕 Optimize for fresh server installation"
    echo -e "    ${GREEN}--auto-create-user${NC}    👥 Automatically create milou user if needed"
    echo -e "    ${GREEN}--skip-user-check${NC}     ⏭️  Skip user permission validation"
    echo
    
    echo -e "${BOLD}${YELLOW}🐳 DOCKER OPTIONS:${NC}"
    echo -e "    ${GREEN}--latest${NC}              🔄 Use latest Docker images (default)"
    echo -e "    ${GREEN}--fixed-version${NC}       📌 Use fixed/pinned Docker image versions"
    echo -e "    ${GREEN}--dev${NC}                 🛠️  Enable development mode (use local Docker images)"
    echo
    
    echo -e "${BOLD}${GREEN}💡 QUICK START EXAMPLES:${NC}"
    echo -e "    ${WHITE}# First-time setup (recommended)${NC}"
    echo -e "    ${CYAN}milou.sh setup${NC}"
    echo
    echo -e "    ${WHITE}# Fresh server installation${NC}"
    echo -e "    ${CYAN}milou.sh setup --fresh-install${NC}"
    echo
    echo -e "    ${WHITE}# Automated setup with custom domain${NC}"
    echo -e "    ${CYAN}milou.sh setup --token ghp_xxxx --domain example.com --non-interactive${NC}"
    echo
    echo -e "    ${WHITE}# Install dependencies only${NC}"
    echo -e "    ${CYAN}milou.sh install-deps${NC}"
    echo
    echo -e "    ${WHITE}# Start services with verbose logging${NC}"
    echo -e "    ${CYAN}milou.sh start --verbose${NC}"
    echo
    echo -e "    ${WHITE}# Create backup${NC}"
    echo -e "    ${CYAN}milou.sh backup${NC}"
    echo
    echo -e "    ${WHITE}# Security assessment${NC}"
    echo -e "    ${CYAN}milou.sh security-check --verbose${NC}"
    echo
    
    echo -e "${BOLD}${BLUE}📚 GETTING STARTED:${NC}"
    echo -e "    ${WHITE}1.${NC} Run ${CYAN}milou.sh setup${NC} for interactive installation"
    echo -e "    ${WHITE}2.${NC} Use ${CYAN}milou.sh start${NC} to launch services"
    echo -e "    ${WHITE}3.${NC} Check ${CYAN}milou.sh status${NC} to verify everything is running"
    echo -e "    ${WHITE}4.${NC} View ${CYAN}milou.sh credentials${NC} for login information"
    echo
    
    echo -e "${DIM}For more information, visit: https://github.com/your-org/milou-cli${NC}"
    echo
}

# =============================================================================
# COMMAND HANDLERS
# =============================================================================

cmd_setup() {
    log "INFO" "🚀 Starting Milou smart setup..."
    
    # Welcome message for interactive setup
    if [[ "${INTERACTIVE:-true}" == "true" ]]; then
        echo
        echo -e "${BOLD}${PURPLE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BOLD}${PURPLE}║                        🚀 Welcome to Milou CLI Setup!                       ║${NC}"
        echo -e "${BOLD}${PURPLE}║                                                                              ║${NC}"
        echo -e "${BOLD}${PURPLE}║    This wizard will guide you through setting up Milou on your system      ║${NC}"
        echo -e "${BOLD}${PURPLE}║                                                                              ║${NC}"
        echo -e "${BOLD}${PURPLE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
        echo
    fi
    
    # Check prerequisites first
    if ! milou_check_prerequisites; then
        echo
        echo -e "${BOLD}${YELLOW}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BOLD}${YELLOW}║                    ⚠️  Missing System Dependencies Detected!                ║${NC}"
        echo -e "${BOLD}${YELLOW}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
        echo
        
        # Show what's missing in a user-friendly way
        echo -e "${BOLD}${BLUE}📋 The following components need to be installed:${NC}"
        echo
        
        # Check specific missing components
        if ! command -v docker >/dev/null 2>&1; then
            echo -e "  ${RED}❌ Docker Engine${NC} - Container platform for running Milou services"
        fi
        
        if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
            echo -e "  ${RED}❌ Docker Compose${NC} - Multi-container orchestration tool"
        fi
        
        if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
            echo -e "  ${RED}❌ curl or wget${NC} - Download utilities for fetching resources"
        fi
        
        local missing_basic=()
        for cmd in tar gzip; do
            if ! command -v "$cmd" >/dev/null 2>&1; then
                missing_basic+=("$cmd")
            fi
        done
        
        if [[ ${#missing_basic[@]} -gt 0 ]]; then
            echo -e "  ${RED}❌ Basic tools${NC}: ${missing_basic[*]} - Archive and compression utilities"
        fi
        
        echo
        
        # In non-interactive mode or if AUTO_INSTALL_DEPS is set, install automatically
        if [[ "${INTERACTIVE:-true}" == "false" ]] || [[ "${AUTO_INSTALL_DEPS}" == "true" ]]; then
            log "INFO" "🔧 Auto-installing missing dependencies..."
            if milou_install_prerequisites; then
                log "SUCCESS" "✅ Dependencies installed successfully!"
                # Re-check prerequisites after installation
                if ! milou_check_prerequisites; then
                    log "ERROR" "❌ Some dependencies are still missing after installation"
                    return 1
                fi
            else
                log "ERROR" "❌ Failed to install dependencies"
                return 1
            fi
        # In interactive mode, ask user with clear explanation
        else
            echo -e "${BOLD}${GREEN}🔧 Automatic Installation Available!${NC}"
            echo
            echo -e "${BOLD}${BLUE}Milou can automatically install these dependencies for you.${NC}"
            echo
            echo -e "${BOLD}${CYAN}📦 This installation will:${NC}"
            echo -e "  ${GREEN}✅${NC} Install Docker Engine and Docker Compose"
            echo -e "  ${GREEN}✅${NC} Install basic system tools (curl, wget, tar, gzip)"
            echo -e "  ${GREEN}✅${NC} Configure Docker to start automatically"
            echo -e "  ${GREEN}✅${NC} Add your user to the docker group (if not root)"
            echo -e "  ${GREEN}✅${NC} Set up proper permissions and security"
            echo
            
            if ask_yes_no "🚀 Would you like Milou to install these dependencies automatically?" "y"; then
                echo
                log "INFO" "🔧 Installing dependencies... This may take a few minutes."
                
                if milou_install_prerequisites; then
                    echo
                    log "SUCCESS" "🎉 Dependencies installed successfully!"
                    
                    # Re-check prerequisites after installation
                    if ! milou_check_prerequisites; then
                        log "ERROR" "❌ Some dependencies are still missing after installation"
                        return 1
                    fi
                    
                    # Check if user needs to log out for Docker group
                    if ! milou_is_root && ! groups "$(whoami)" | grep -q docker 2>/dev/null; then
                        echo
                        log "WARN" "⚠️  You may need to log out and back in for Docker group changes to take effect"
                        log "INFO" "Or run: newgrp docker"
                        echo
                        if ask_yes_no "Continue with setup anyway?" "y"; then
                            log "INFO" "Continuing with setup..."
                        else
                            log "INFO" "Setup cancelled. Please log out/in and run setup again."
                            return 0
                        fi
                    fi
                else
                    echo
                    log "ERROR" "❌ Failed to install dependencies"
                    log "INFO" "You can install them manually:"
                    log "INFO" "  • Docker: https://docs.docker.com/engine/install/"
                    log "INFO" "  • Docker Compose: https://docs.docker.com/compose/install/"
                    echo
                    log "INFO" "Then run: ./milou.sh setup"
                    return 1
                fi
            else
                echo
                log "INFO" "Setup cancelled. You can install dependencies manually:"
                log "INFO" "  • Run: ./milou.sh install-deps"
                log "INFO" "  • Or install Docker manually: https://docs.docker.com/engine/install/"
                echo
                log "INFO" "Then run: ./milou.sh setup"
                return 0
            fi
        fi
        
        echo
        log "SUCCESS" "✅ All dependencies are now installed!"
        echo
    else
        log "SUCCESS" "✅ All system dependencies are already installed"
    fi
    
    # Use smart configuration that handles all installation scenarios
    local domain="${DOMAIN:-localhost}"
    local email="${EMAIL:-admin@localhost}"
    local github_token="${GITHUB_TOKEN:-}"
    
    # If no token provided and interactive mode, ask for it
    if [[ -z "$github_token" && "${INTERACTIVE:-true}" == "true" ]]; then
        echo
        log "INFO" "GitHub token is required for downloading Docker images"
        read -p "GitHub personal access token: " github_token
        if [[ -n "$github_token" ]]; then
            export GITHUB_TOKEN="$github_token"
        fi
    fi
    
    # Use smart environment configuration
    local setup_result=0
    if smart_env_configuration "$domain" "$email" "$github_token"; then
        log "SUCCESS" "Smart configuration completed successfully"
    else
        log "ERROR" "Smart configuration failed"
        setup_result=1
    fi
    
    # Load the generated environment if configuration succeeded
    if [[ $setup_result -eq 0 ]]; then
        if load_env_file ".env"; then
            log "SUCCESS" "Environment loaded successfully"
        else
            log "ERROR" "Failed to load environment"
            setup_result=1
        fi
    fi
    
    # Run remaining setup steps if needed and configuration succeeded
    if [[ $setup_result -eq 0 && "${INTERACTIVE:-true}" == "true" ]]; then
        # SSL setup
        if ask_yes_no "Set up SSL certificates?"; then
            ssl_interactive_setup || log "WARN" "SSL setup failed"
        fi
        
        # User setup
        if ask_yes_no "Set up system users?"; then
            milou_user_setup_wizard || log "WARN" "User setup failed"
        fi
    fi
    
    # Final validation if everything succeeded so far
    if [[ $setup_result -eq 0 ]]; then
        log "INFO" "🔍 Validating setup..."
        if milou_validate_system; then
            log "SUCCESS" "Setup validation passed"
        else
            log "ERROR" "Setup validation failed"
            setup_result=1
        fi
    fi
    
    # Complete setup process with credentials display and service startup
    milou_setup_completion $setup_result
    return $setup_result
}

cmd_start() {
    log "INFO" "🚀 Starting Milou services..."
    
    # Use smart Docker startup that handles all scenarios
    if smart_docker_start; then
        log "SUCCESS" "Milou services started successfully"
        
        # Show status after startup
        echo
        log "INFO" "Service Status:"
        docker_status
        
        # Show access information
        local domain=$(grep "^DOMAIN=" .env 2>/dev/null | cut -d'=' -f2 || echo "localhost")
        local http_port=$(grep "^HTTP_PORT=" .env 2>/dev/null | cut -d'=' -f2 || echo "80")
        local https_port=$(grep "^HTTPS_PORT=" .env 2>/dev/null | cut -d'=' -f2 || echo "443")
        
        echo
        log "INFO" "🌐 Access Information:"
        if [[ "$http_port" != "80" ]]; then
            echo "  HTTP:  http://${domain}:${http_port}"
        else
            echo "  HTTP:  http://${domain}"
        fi
        
        if [[ "$https_port" != "443" ]]; then
            echo "  HTTPS: https://${domain}:${https_port}"
        else
            echo "  HTTPS: https://${domain}"
        fi
        
        return 0
    else
        log "ERROR" "Failed to start Milou services"
        return 1
    fi
}

cmd_stop() {
    log "INFO" "🛑 Stopping Milou services..."
    docker_stop "$@"
}

cmd_restart() {
    log "INFO" "🔄 Restarting Milou services..."
    docker_restart "$@"
}

cmd_status() {
    log "INFO" "📊 Checking service status..."
    docker_status "$@"
}

cmd_logs() {
    log "INFO" "📋 Viewing service logs..."
    docker_logs "$@"
}

cmd_health() {
    log "INFO" "🏥 Running health checks..."
    milou_system_health
    docker_health_check
}

cmd_config() {
    case "${1:-show}" in
        "show")
            show_config
            ;;
        "edit")
            ssl_interactive_setup
            ;;
        "validate")
            test_config
            ;;
        *)
            log "ERROR" "Unknown config command: $1"
            log "INFO" "Available: show, edit, validate"
            return 1
            ;;
    esac
}

cmd_validate() {
    log "INFO" "🔍 Validating system..."
    milou_validate_system
}

cmd_backup() {
    local backup_name="${1:-milou-backup-$(date +%Y%m%d-%H%M%S)}"
    log "INFO" "💾 Creating backup: $backup_name"
    milou_system_backup "$backup_name"
}

cmd_restore() {
    local backup_file="$1"
    if [[ -z "$backup_file" ]]; then
        log "ERROR" "Backup file required"
        log "INFO" "Usage: milou restore <backup-file>"
        return 1
    fi
    log "INFO" "📥 Restoring from backup: $backup_file"
    milou_system_restore "$backup_file"
}

cmd_update() {
    log "INFO" "🔄 Updating Milou system..."
    milou_system_update "$@"
}

cmd_seed() {
    log "INFO" "🌱 Running database seeder..."
    
    # Check if services are running
    if ! docker ps --filter "name=milou-" --format "{{.Names}}" | grep -q "milou-database"; then
        log "ERROR" "Database service is not running"
        log "INFO" "Start services first with: ./milou.sh start"
        return 1
    fi
    
    # Run the seeder
    if run_database_seeder; then
        log "SUCCESS" "Database seeder completed successfully"
        return 0
    else
        log "ERROR" "Database seeder failed"
        return 1
    fi
}

cmd_credentials() {
    log "INFO" "🔐 Displaying current credentials..."
    
    if [[ -f ".env" ]]; then
        display_setup_credentials ".env"
    else
        log "ERROR" "Environment file not found"
        log "INFO" "Run setup first with: ./milou.sh setup"
        return 1
    fi
}

cmd_ssl() {
    case "${1:-status}" in
        "generate")
            shift
            generate_ssl_certificate "$@"
            ;;
        "validate")
            validate_ssl_certificate
            ;;
        "status")
            show_ssl_status
            ;;
        "setup")
            ssl_interactive_setup
            ;;
        "renew")
            shift
            auto_renew_certificate "$@"
            ;;
        "check-expiry")
            shift
            check_certificate_expiration "$@"
            ;;
        "auto-setup")
            shift
            setup_auto_renewal "$@"
            ;;
        "force-renew")
            shift
            auto_renew_certificate "${1:-$DOMAIN}" "${2:-$SSL_PATH}" "true"
            ;;
        *)
            log "ERROR" "Unknown SSL command: $1"
            log "INFO" "Available commands:"
            log "INFO" "  generate     - Generate new SSL certificate"
            log "INFO" "  validate     - Validate existing certificate"
            log "INFO" "  status       - Show certificate status"
            log "INFO" "  setup        - Interactive SSL setup"
            log "INFO" "  renew        - Auto-renew certificate if needed"
            log "INFO" "  check-expiry - Check certificate expiration"
            log "INFO" "  auto-setup   - Setup automatic renewal (cron)"
            log "INFO" "  force-renew  - Force certificate renewal"
            return 1
            ;;
    esac
}

cmd_cleanup() {
    log "INFO" "🧹 Cleaning up Docker resources..."
    docker_clean_system "$@"
}

cmd_shell() {
    local service="${1:-app}"
    log "INFO" "🐚 Opening shell to $service..."
    docker_shell "$service"
}

cmd_user_status() {
    log "INFO" "👤 Checking user status..."
    show_user_info
}

cmd_create_user() {
    log "INFO" "👤 Creating milou user..."
    create_milou_user
}

cmd_security_check() {
    log "INFO" "🔒 Running security check..."
    show_milou_status
}

cmd_install_deps() {
    log "INFO" "📦 Installing Milou dependencies..."
    
    # Check current status
    log "INFO" "Checking current system status..."
    
    # Show what will be installed
    echo
    log "INFO" "This will install the following if missing:"
    echo "  • Docker Engine"
    echo "  • Docker Compose"
    echo "  • Basic system tools (curl, wget, tar, gzip)"
    echo
    
    # Check if running as root or with sudo access
    if ! milou_is_root && ! sudo -n true 2>/dev/null; then
        log "WARN" "Root privileges required for installation"
        if [[ "${INTERACTIVE:-true}" == "true" ]]; then
            if ! ask_yes_no "Continue with installation? (will prompt for sudo password)" "y"; then
                log "INFO" "Installation cancelled"
                return 0
            fi
        else
            log "ERROR" "Cannot install dependencies without root privileges"
            return 1
        fi
    fi
    
    # Install prerequisites
    if milou_install_prerequisites; then
        echo
        log "SUCCESS" "✅ All dependencies installed successfully!"
        
        # Show what was installed
        echo
        log "INFO" "Installed components:"
        if command -v docker >/dev/null 2>&1; then
            local docker_version=$(docker --version | cut -d' ' -f3 | tr -d ',')
            echo "  ✅ Docker: $docker_version"
        fi
        
        if docker compose version >/dev/null 2>&1; then
            local compose_version=$(docker compose version --short 2>/dev/null)
            echo "  ✅ Docker Compose: $compose_version"
        fi
        
        echo "  ✅ System tools: curl, wget, tar, gzip"
        
        # Check if user needs to log out for Docker group
        if ! milou_is_root && groups "$(whoami)" | grep -q docker; then
            echo
            log "INFO" "🎉 Installation complete! You can now run:"
            echo "  ./milou.sh setup --auto-install-deps"
        elif ! milou_is_root; then
            echo
            log "WARN" "⚠️  You may need to log out and back in for Docker group changes to take effect"
            log "INFO" "Or run: newgrp docker"
            echo
            log "INFO" "Then you can run: ./milou.sh setup"
        else
            echo
            log "INFO" "🎉 Installation complete! You can now run:"
            echo "  ./milou.sh setup"
        fi
        
        return 0
    else
        log "ERROR" "❌ Failed to install dependencies"
        echo
        log "INFO" "Manual installation instructions:"
        log "INFO" "  • Docker: https://docs.docker.com/engine/install/"
        log "INFO" "  • Docker Compose: https://docs.docker.com/compose/install/"
        return 1
    fi
}

cmd_build_images() {
    log "INFO" "🔨 Building Docker images..."
    docker_build_images "$@"
}

cmd_status_install() {
    log "INFO" "📋 Checking installation status..."
    local install_state
    install_state=$(milou_detect_installation)
    
    echo
    log "INFO" "${BOLD}Milou Installation Status${NC}"
    echo "=========================="
    
    case "$install_state" in
        "$INSTALL_STATE_NONE")
            log "INFO" "Status: ${RED}No installation detected${NC}"
            log "INFO" "Next steps: Run 'milou setup' to install Milou"
            ;;
        "$INSTALL_STATE_DEV")
            log "INFO" "Status: ${YELLOW}Development environment${NC}"
            log "INFO" "Location: $(pwd)"
            log "INFO" "Mode: Local development"
            ;;
        "$INSTALL_STATE_PROD")
            log "INFO" "Status: ${GREEN}Production installation${NC}"
            log "INFO" "Location: ${MILOU_INSTALL_PATH}"
            log "INFO" "Service: Active"
            ;;
        "$INSTALL_STATE_PARTIAL")
            log "INFO" "Status: ${YELLOW}Partial installation${NC}"
            log "INFO" "Warning: Some components may be missing"
            ;;
    esac
    
    echo
    log "INFO" "Environment:"
    log "INFO" "  - User: $(whoami)"
    log "INFO" "  - Working directory: $(pwd)"
    log "INFO" "  - Config directory: ${MILOU_CONFIG_DIR}"
    log "INFO" "  - Development mode: ${DEV_MODE:-false}"
    
    if [[ -f ".env" ]]; then
        log "INFO" "  - Environment file: Present"
    else
        log "INFO" "  - Environment file: Missing"
    fi
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

parse_arguments() {
    local remaining_args=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose)
                VERBOSE=true
                export LOG_LEVEL="DEBUG"
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
                    # Write debug to stderr to avoid interfering with command parsing
                    echo "DEBUG: Token set to: ${GITHUB_TOKEN}" >&2
                    shift 2
                else
                    log "ERROR" "GitHub token value is required after --token"
                    return 1
                fi
                ;;
            --domain)
                if [[ -n "${2:-}" ]]; then
                    DOMAIN="$2"
                    export DOMAIN
                    shift 2
                else
                    log "ERROR" "Domain value is required after --domain"
                    return 1
                fi
                ;;
            --ssl-path)
                if [[ -n "${2:-}" ]]; then
                    SSL_PATH="$2"
                    export SSL_PATH
                    shift 2
                else
                    log "ERROR" "SSL path value is required after --ssl-path"
                    return 1
                fi
                ;;
            --email)
                if [[ -n "${2:-}" ]]; then
                    EMAIL="$2"
                    export EMAIL
                    shift 2
                else
                    log "ERROR" "Email value is required after --email"
                    return 1
                fi
                ;;
            --latest)
                USE_LATEST=true
                export USE_LATEST
                shift
                ;;
            --fixed-version)
                USE_LATEST=false
                export USE_LATEST
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
                export FRESH_INSTALL
                shift
                ;;
            --dev)
                DEV_MODE=true
                export DEV_MODE
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            -*)
                log "ERROR" "Unknown option: $1"
                return 1
                ;;
            *)
                remaining_args+=("$1")
                shift
                ;;
        esac
    done
    
    # Return remaining arguments
    printf '%s\n' "${remaining_args[@]}"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    # Parse arguments directly to avoid subshell issues
    local remaining_args=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose)
                VERBOSE=true
                export LOG_LEVEL="DEBUG"
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
                    log "ERROR" "GitHub token value is required after --token"
                    return 1
                fi
                ;;
            --domain)
                if [[ -n "${2:-}" ]]; then
                    DOMAIN="$2"
                    export DOMAIN
                    shift 2
                else
                    log "ERROR" "Domain value is required after --domain"
                    return 1
                fi
                ;;
            --ssl-path)
                if [[ -n "${2:-}" ]]; then
                    SSL_PATH="$2"
                    export SSL_PATH
                    shift 2
                else
                    log "ERROR" "SSL path value is required after --ssl-path"
                    return 1
                fi
                ;;
            --email)
                if [[ -n "${2:-}" ]]; then
                    EMAIL="$2"
                    export EMAIL
                    shift 2
                else
                    log "ERROR" "Email value is required after --email"
                    return 1
                fi
                ;;
            --latest)
                USE_LATEST=true
                export USE_LATEST
                shift
                ;;
            --fixed-version)
                USE_LATEST=false
                export USE_LATEST
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
                export FRESH_INSTALL
                shift
                ;;
            --dev)
                DEV_MODE=true
                export DEV_MODE
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            -*)
                log "ERROR" "Unknown option: $1"
                return 1
                ;;
            *)
                remaining_args+=("$1")
                shift
                ;;
        esac
    done
    
    local command="${remaining_args[0]:-help}"
    local args=("${remaining_args[@]:1}")
    

    
    log "DEBUG" "Milou CLI v$SCRIPT_VERSION started"
    log "DEBUG" "Command: $command, User: $(whoami), PID: $$"
    log "DEBUG" "Working directory: $(pwd)"
    
    # Handle resumption after user switch
    if [[ -n "${MILOU_RESUMED:-}" ]]; then
        log "DEBUG" "Resuming operation after user switch"
        unset MILOU_RESUMED
        
        # Re-parse original arguments if available
        if [[ -n "${ORIGINAL_ARGUMENTS_STR:-}" ]]; then
            log "DEBUG" "Re-parsing original arguments: $ORIGINAL_ARGUMENTS_STR"
            
            # Convert string back to array
            local original_args_array
            IFS=' ' read -ra original_args_array <<< "$ORIGINAL_ARGUMENTS_STR"
            
            # Re-parse arguments
            mapfile -t remaining_args < <(parse_arguments "${original_args_array[@]}")
            command="${remaining_args[0]:-help}"
            args=("${remaining_args[@]:1}")
        fi
    else
        # First run - preserve arguments for potential user switching
        preserve_arguments "$command" "${args[@]}"
        
        # Create arguments string for user switching
        ORIGINAL_ARGUMENTS_STR=""
        for arg in "${ORIGINAL_ARGUMENTS[@]}"; do
            if [[ "$arg" =~ [[:space:]] ]]; then
                ORIGINAL_ARGUMENTS_STR+="\"$arg\" "
            else
                ORIGINAL_ARGUMENTS_STR+="$arg "
            fi
        done
        ORIGINAL_ARGUMENTS_STR="${ORIGINAL_ARGUMENTS_STR% }"  # Remove trailing space
        export ORIGINAL_ARGUMENTS_STR
        
        log "DEBUG" "Resumed with command: $command, verbose: $VERBOSE, remaining args: ${#remaining_args[@]}"
    fi
    
    # Initialize modules
    users_init
    docker_init
    
    log "DEBUG" "Before command routing: GITHUB_TOKEN=${GITHUB_TOKEN:-NOT_SET} (length: ${#GITHUB_TOKEN})"
    
    # Debug: Show all environment variables related to tokens
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        log "DEBUG" "All token-related environment variables:"
        env | grep -i token || log "DEBUG" "No token environment variables found"
    fi
    
    # Route to command handlers
    case "$command" in
        "setup")
            cmd_setup "${args[@]}"
            ;;
        "start")
            cmd_start "${args[@]}"
            ;;
        "stop")
            cmd_stop "${args[@]}"
            ;;
        "restart")
            cmd_restart "${args[@]}"
            ;;
        "status")
            cmd_status "${args[@]}"
            ;;
        "logs")
            cmd_logs "${args[@]}"
            ;;
        "health")
            cmd_health "${args[@]}"
            ;;
        "config")
            cmd_config "${args[@]}"
            ;;
        "validate")
            cmd_validate "${args[@]}"
            ;;
        "backup")
            cmd_backup "${args[@]}"
            ;;
        "restore")
            cmd_restore "${args[@]}"
            ;;
        "update")
            cmd_update "${args[@]}"
            ;;
        "seed")
            cmd_seed "${args[@]}"
            ;;
        "credentials")
            cmd_credentials "${args[@]}"
            ;;
        "ssl")
            cmd_ssl "${args[@]}"
            ;;
        "cleanup")
            cmd_cleanup "${args[@]}"
            ;;
        "shell")
            cmd_shell "${args[@]}"
            ;;
        "user-status")
            cmd_user_status "${args[@]}"
            ;;
        "create-user")
            cmd_create_user "${args[@]}"
            ;;
        "security-check")
            cmd_security_check "${args[@]}"
            ;;
        "install-deps")
            cmd_install_deps "${args[@]}"
            ;;
        "build-images")
            cmd_build_images "${args[@]}"
            ;;
        "status-install")
            cmd_status_install "${args[@]}"
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            log "ERROR" "Unknown command: $command"
            log "INFO" "Use 'milou help' to see available commands"
            exit 1
            ;;
    esac
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Set up error handling and cleanup
cleanup() {
    local exit_code=$?
    log "DEBUG" "Script execution completed with exit code: $exit_code"
    exit $exit_code
}

# Set up signal handlers
trap cleanup EXIT
trap 'log "WARN" "Script interrupted by user"; exit 130' INT TERM

# Execute main function with all arguments
main "$@" 