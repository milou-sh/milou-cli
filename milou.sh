#!/bin/bash

set -euo pipefail

# =============================================================================
# Milou Management CLI - Enhanced Edition
# State-of-the-art CLI with comprehensive improvements using modular utilities
# =============================================================================

# Version and Constants
readonly SCRIPT_VERSION="3.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_DIR="${HOME}/.milou"
readonly ENV_FILE="${SCRIPT_DIR}/.env"
readonly BACKUP_DIR="${CONFIG_DIR}/backups"
readonly LOG_FILE="${CONFIG_DIR}/milou.log"
readonly CACHE_DIR="${CONFIG_DIR}/cache"
readonly DEFAULT_SSL_PATH="./ssl"

# Global State
declare -g VERBOSE=false
declare -g FORCE=false
declare -g DRY_RUN=false
declare -g GITHUB_TOKEN=""
declare -g USE_LATEST_IMAGES=false
declare -g SKIP_VERSION_CHECK=false
declare -g INTERACTIVE=true
declare -g AUTO_CREATE_USER=false
declare -g SKIP_USER_CHECK=false

# Source utility functions
source "${SCRIPT_DIR}/utils/utils.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/utils/docker.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/utils/docker-registry.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/utils/ssl.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/utils/backup.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/utils/update.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/utils/configure.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/utils/setup_wizard.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/utils/user-management.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/utils/security.sh" 2>/dev/null || true

# Create necessary directories
mkdir -p "${CONFIG_DIR}" "${BACKUP_DIR}" "${CACHE_DIR}"
touch "${LOG_FILE}"

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
    printf "    ${CYAN}help${NC}              Show this help message\n\n"

    printf "${BOLD}SETUP OPTIONS:${NC}\n"
    printf "    ${YELLOW}--token${NC} TOKEN        GitHub Personal Access Token for authentication\n"
    printf "    ${YELLOW}--domain${NC} DOMAIN      Domain name for the installation\n"
    printf "    ${YELLOW}--ssl-path${NC} PATH      Path to SSL certificates directory\n"
    printf "    ${YELLOW}--email${NC} EMAIL        Admin email address\n"
    printf "    ${YELLOW}--latest${NC}             Use latest available Docker image versions\n"
    printf "    ${YELLOW}--non-interactive${NC}    Run setup without interactive prompts\n\n"

    printf "${BOLD}GLOBAL OPTIONS:${NC}\n"
    printf "    ${YELLOW}--verbose${NC}            Show detailed output and debug information\n"
    printf "    ${YELLOW}--force${NC}              Force operation without confirmation prompts\n"
    printf "    ${YELLOW}--dry-run${NC}            Show what would be done without executing\n"
    printf "    ${YELLOW}--auto-create-user${NC}   Automatically create milou user if running as root\n"
    printf "    ${YELLOW}--skip-user-check${NC}    Skip user management validation (not recommended)\n"
    printf "    ${YELLOW}--help${NC}               Show this help message\n\n"

    printf "${BOLD}EXAMPLES:${NC}\n"
    printf "    ${DIM}# Interactive setup (recommended)${NC}\n"
    printf "    $(basename "$0") setup\n\n"
    
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
# Argument Parsing
# =============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose)
                VERBOSE=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --token)
                GITHUB_TOKEN="$2"
                shift 2
                ;;
            --domain)
                DOMAIN="$2"
                shift 2
                ;;
            --ssl-path)
                SSL_PATH="$2"
                shift 2
                ;;
            --email)
                ADMIN_EMAIL="$2"
                shift 2
                ;;
            --latest)
                USE_LATEST_IMAGES=true
                shift
                ;;
            --non-interactive)
                INTERACTIVE=false
                shift
                ;;
            --auto-create-user)
                AUTO_CREATE_USER=true
                shift
                ;;
            --skip-user-check)
                SKIP_USER_CHECK=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                # Unknown option, keep for command processing
                break
                ;;
        esac
    done
}

# =============================================================================
# Command Handlers
# =============================================================================

handle_setup() {
    # Early user management check for security
    if [[ "${SKIP_USER_CHECK:-false}" != "true" ]]; then
        ensure_proper_user_setup "$@"
    fi
    
    if [[ -n "$GITHUB_TOKEN" ]]; then
        # Non-interactive setup
        handle_non_interactive_setup "$@"
    else
        # Interactive setup
        interactive_setup_wizard
    fi
}

handle_non_interactive_setup() {
    log "STEP" "Running non-interactive setup..."
    log "INFO" "Image versioning strategy: $([ "$USE_LATEST_IMAGES" == true ] && echo "Latest available versions" || echo "Fixed version (v1.0.0)")"
    
    # Set defaults
    local domain="${DOMAIN:-localhost}"
    local ssl_path="${SSL_PATH:-./ssl}"
    local admin_email="${ADMIN_EMAIL:-}"
    
    # Validate required inputs
    if [[ -z "$GITHUB_TOKEN" ]]; then
        error_exit "GitHub token is required for non-interactive setup"
    fi
    
    # Run setup steps
    check_system_requirements
    
    if ! test_github_authentication "$GITHUB_TOKEN"; then
        error_exit "GitHub authentication failed"
    fi
    
    if ! generate_config "$domain" "$ssl_path" "$admin_email"; then
        error_exit "Configuration generation failed"
    fi
    
    # SSL setup with automatic fallbacks - NEVER FAILS
    log "STEP" "Setting up SSL certificates for $domain..."
    mkdir -p "$ssl_path"
    
    if setup_ssl "$ssl_path" "$domain"; then
        log "SUCCESS" "SSL certificates ready"
    else
        # This should never happen with the new setup_ssl, but just in case
        error_exit "Critical error: SSL setup failed despite automatic fallbacks"
    fi
    
    # Verify certificates exist before proceeding
    if [[ ! -f "$ssl_path/milou.crt" || ! -f "$ssl_path/milou.key" ]]; then
        error_exit "SSL certificate files are missing after setup. This indicates a critical system issue."
    fi
    
    # Enhanced image pulling with better feedback
    log "INFO" "Pulling Docker images with strategy: $([ "$USE_LATEST_IMAGES" == true ] && echo "latest" || echo "fixed v1.0.0")"
    if ! pull_images "$GITHUB_TOKEN" "$USE_LATEST_IMAGES"; then
        if [[ "$FORCE" == true ]]; then
            log "WARN" "Some images failed to pull, but --force flag is set, continuing..."
        else
            log "ERROR" "Image pull failed. Use --force to continue anyway or fix the issues."
            log "INFO" "💡 Try running: $0 debug-images --token YOUR_TOKEN"
            error_exit "Failed to pull Docker images"
        fi
    fi
    
    # Start services - make this automatic for truly non-interactive setup
    log "STEP" "Starting services..."
    if start_services_with_checks; then
        log "SUCCESS" "${ROCKET_EMOJI} Non-interactive setup complete!"
        log "INFO" "Access your instance at: https://$domain"
        if [[ "$domain" == "localhost" ]]; then
            log "INFO" "Local access: https://localhost"
        fi
        
        # Show quick health status
        log "INFO" "Performing quick health check..."
        sleep 10  # Give services a moment to start
        show_service_status
    else
        log "ERROR" "Failed to start services"
        log "INFO" "You can try starting manually with: $0 start"
        exit 1
    fi
}

handle_start() {
    start_services_with_checks
}

handle_stop() {
    stop_services
}

handle_restart() {
    restart_services
}

handle_status() {
    show_service_status
}

handle_detailed_status() {
    show_detailed_status
}

handle_logs() {
    local service="$1"
    
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
    
    check_system_requirements
    validate_configuration
    
    # Check service health
    if show_service_status; then
        log "SUCCESS" "Health check completed"
    else
        error_exit "Health check failed"
    fi
}

handle_config() {
    if [[ -f "$ENV_FILE" ]]; then
        log "INFO" "Current configuration:"
        echo
        # Show configuration but hide sensitive values
        sed 's/=.*PASSWORD.*/=***HIDDEN***/g; s/=.*SECRET.*/=***HIDDEN***/g; s/=.*KEY.*/=***HIDDEN***/g' "$ENV_FILE"
    else
        error_exit "Configuration file not found. Please run setup first."
    fi
}

handle_validate() {
    validate_configuration && check_system_requirements
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
            *)
                shift
                ;;
        esac
    done
    
    log "INFO" "Creating $backup_type backup..."
    if create_backup "$backup_type"; then
        log "INFO" "Backup created successfully"
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
        log "INFO" "Restore completed successfully"
    else
        error_exit "Failed to restore from backup"
    fi
}

handle_update() {
    log "STEP" "Checking for updates..."
    if update_milou; then
        log "INFO" "Update completed successfully"
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
                # Use ssl-manager for status
                exec ./ssl-manager.sh status
                ;;
            --validate)
                # Use ssl-manager for validation
                exec ./ssl-manager.sh validate
                ;;
            --clean)
                # Use ssl-manager for cleanup
                exec ./ssl-manager.sh clean
                ;;
            --consolidate)
                # Use ssl-manager for consolidation
                exec ./ssl-manager.sh consolidate
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
    
    # Default action: run SSL setup with new production-ready system
    log "STEP" "SSL Certificate Management"
    
    # Ensure SSL path exists
    mkdir -p "$ssl_path"
    
    # Use the production-ready SSL setup
    if setup_ssl "$ssl_path" "$domain"; then
        log "SUCCESS" "SSL certificates are ready for domain: $domain"
        log "INFO" "Certificate location: $ssl_path/milou.crt"
        log "INFO" "Private key location: $ssl_path/milou.key"
        
        # Validate the setup
        if check_ssl_expiration "$ssl_path"; then
            log "SUCCESS" "SSL certificates are valid and not expiring soon"
        fi
    else
        error_exit "SSL setup failed"
    fi
}

# Show SSL help
show_ssl_help() {
    echo "SSL Certificate Management"
    echo
    echo "USAGE:"
    echo "    $(basename "$0") ssl [OPTIONS]"
    echo
    echo "OPTIONS:"
    echo "    --domain DOMAIN     Domain name (default: from .env or localhost)"
    echo "    --ssl-path PATH     SSL certificate path (default: from .env or ./ssl)"
    echo "    --status            Show SSL certificate status"
    echo "    --validate          Validate existing certificates"
    echo "    --clean             Clean up all SSL certificates"
    echo "    --consolidate       Consolidate scattered certificates"
    echo "    --help              Show this help"
    echo
    echo "EXAMPLES:"
    echo "    $(basename "$0") ssl                            # Setup SSL for default domain"
    echo "    $(basename "$0") ssl --domain example.com       # Setup SSL for custom domain"
    echo "    $(basename "$0") ssl --status                   # Check certificate status"
    echo "    $(basename "$0") ssl --validate                 # Validate certificates"
    echo
    echo "ADVANCED SSL MANAGEMENT:"
    echo "    Use ./ssl-manager.sh for advanced SSL operations"
    echo "    ./ssl-manager.sh --help for more options"
}

handle_cleanup() {
    local cleanup_type="regular"
    local cleanup_args=()
    
    # Parse cleanup arguments
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
                cleanup_args+=("$1")
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
        *)
            log "ERROR" "Unknown cleanup type: $cleanup_type"
            return 1
            ;;
    esac
}

# Show cleanup help
show_cleanup_help() {
    echo "Cleanup Commands:"
    echo
    echo "  Regular cleanup (safe):"
    echo "    ./milou.sh cleanup"
    echo "    • Removes unused Docker images"
    echo "    • Removes unused volumes (with confirmation)"
    echo "    • Removes unused networks"
    echo
    echo "  Complete cleanup (destructive):"
    echo "    ./milou.sh cleanup --complete"
    echo "    • Removes ALL Milou containers"
    echo "    • Removes ALL Milou images"
    echo "    • Removes ALL Milou volumes"
    echo "    • Removes ALL Milou networks"
    echo "    • Removes configuration files"
    echo "    • Removes SSL certificates (with confirmation)"
    echo
    echo "  Options:"
    echo "    --force      Skip confirmation prompts (use with --complete for automation)"
    echo "    --help       Show this help message"
    echo
    echo "  Examples:"
    echo "    ./milou.sh cleanup                    # Safe cleanup"
    echo "    ./milou.sh cleanup --complete         # Complete cleanup with prompts"
    echo "    ./milou.sh cleanup --complete --force # Complete cleanup without prompts"
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
    local token="$GITHUB_TOKEN"
    
    if [[ -z "$token" ]]; then
        log "ERROR" "GitHub token is required for image debugging"
        log "INFO" "Usage: $0 debug-images --token YOUR_TOKEN"
        return 1
    fi
    
    debug_docker_images "$token"
}

handle_diagnose() {
    log "STEP" "Running comprehensive system diagnostics..."
    
    # Use the comprehensive Docker environment diagnosis
    if ! diagnose_docker_environment; then
        log "WARN" "Some issues were found during diagnosis"
        echo
        log "INFO" "Recommended actions:"
        log "INFO" "  • Fix critical issues shown above"
        log "INFO" "  • Run './milou.sh setup' if configuration is missing"
        log "INFO" "  • Run './milou.sh health' for a quick service check"
        return 1
    fi
    
    return 0
}

# Quick health check handler
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
    
    log "INFO" "Creating dedicated milou user for secure operations..."
    if create_milou_user; then
        log "SUCCESS" "User created successfully!"
        log "INFO" "You can now run: sudo -u milou $0 [command]"
        
        if confirm "Apply security hardening to milou user?" "Y"; then
            harden_milou_user
        fi
        
        if confirm "Switch to milou user now?" "Y"; then
            switch_to_milou_user "$@"
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
    
    log "INFO" "Migrating existing Milou installation to dedicated user..."
    if migrate_to_milou_user; then
        log "SUCCESS" "Migration completed successfully!"
        log "INFO" "Your Milou installation is now owned by the milou user"
        
        if confirm "Switch to milou user now?" "Y"; then
            switch_to_milou_user "$@"
        fi
    else
        error_exit "Failed to migrate to milou user"
    fi
}

# Security management handlers
run_comprehensive_security_assessment() {
    log "STEP" "Running comprehensive security assessment..."
    
    if run_security_assessment; then
        log "SUCCESS" "Security assessment completed - no critical issues found"
        return 0
    else
        log "WARN" "Security assessment found issues that need attention"
        echo
        log "INFO" "Consider running: $0 security-harden (requires sudo)"
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
    
    if [[ "${INTERACTIVE:-true}" == "true" ]] && ! confirm "Apply security hardening measures?" "N"; then
        log "INFO" "Security hardening cancelled"
        exit 0
    fi
    
    log "INFO" "Applying comprehensive security hardening..."
    if harden_system; then
        log "SUCCESS" "Security hardening completed successfully!"
        log "INFO" "System services may need to be restarted for changes to take effect"
        
        if confirm "Restart Docker daemon to apply changes?" "Y"; then
            systemctl restart docker || log "WARN" "Failed to restart Docker daemon"
        fi
        
        log "INFO" "Run security assessment again to verify improvements: $0 security-check"
    else
        error_exit "Failed to apply security hardening"
    fi
}

generate_detailed_security_report() {
    local report_file="milou-security-report-$(date +%Y%m%d_%H%M%S).txt"
    
    log "INFO" "Generating comprehensive security report..."
    if create_security_report "$report_file"; then
        log "SUCCESS" "Security report generated: $report_file"
        
        if command -v less >/dev/null 2>&1 && [[ "${INTERACTIVE:-true}" == "true" ]]; then
            if confirm "View the security report now?" "Y"; then
                less "$report_file"
            fi
        fi
        
        log "INFO" "Share this report with your security team or use it for compliance"
    else
        error_exit "Failed to generate security report"
    fi
}

# =============================================================================
# Main Function
# =============================================================================

main() {
    # If no command provided, show help
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    local command="$1"
    shift

    # Extract global arguments before command-specific arguments
    local -a remaining_args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose)
                VERBOSE=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --token)
                GITHUB_TOKEN="$2"
                shift 2
                ;;
            --domain)
                DOMAIN="$2"
                shift 2
                ;;
            --ssl-path)
                SSL_PATH="$2"
                shift 2
                ;;
            --email)
                ADMIN_EMAIL="$2"
                shift 2
                ;;
            --latest)
                USE_LATEST_IMAGES=true
                shift
                ;;
            --non-interactive)
                INTERACTIVE=false
                shift
                ;;
            --auto-create-user)
                AUTO_CREATE_USER=true
                shift
                ;;
            --skip-user-check)
                SKIP_USER_CHECK=true
                shift
                ;;
            --help|-h)
                # Only show general help if it's a global --help
                if [[ "$command" != "cleanup" && "$command" != "backup" && "$command" != "ssl" ]]; then
                    show_help
                    exit 0
                else
                    # Let command-specific handlers deal with --help
                    remaining_args+=("$1")
                    shift
                fi
                ;;
            *)
                # Preserve other arguments for command handlers
                remaining_args+=("$1")
                shift
                ;;
        esac
    done
    
    # Log script start
    log "DEBUG" "Milou CLI v$SCRIPT_VERSION started with command: $command"
    
    case "$command" in
        setup)
            handle_setup "${remaining_args[@]}"
            ;;
        start)
            handle_start
            ;;
        stop)
            handle_stop
            ;;
        restart)
            handle_restart
            ;;
        status)
            handle_status
            ;;
        detailed-status)
            handle_detailed_status
            ;;
        logs)
            handle_logs "${remaining_args[0]}"
            ;;
        health)
            handle_health
            ;;
        health-check)
            handle_health_check
            ;;
        config)
            handle_config
            ;;
        validate)
            handle_validate
            ;;
        backup)
            handle_backup "${remaining_args[@]}"
            ;;
        restore)
            handle_restore "${remaining_args[0]}"
            ;;
        update)
            handle_update
            ;;
        ssl)
            handle_ssl "${remaining_args[@]}"
            ;;
        cleanup)
            handle_cleanup "${remaining_args[@]}"
            ;;
        shell)
            handle_shell "${remaining_args[0]}"
            ;;
        debug-images)
            handle_debug_images
            ;;
        diagnose)
            handle_diagnose
            ;;
        user-status)
            handle_user_status
            ;;
        create-user)
            handle_create_user "${remaining_args[@]}"
            ;;
        migrate-user)
            handle_migrate_user "${remaining_args[@]}"
            ;;
        security-check)
            run_comprehensive_security_assessment
            ;;
        security-harden)
            apply_security_hardening_measures
            ;;
        security-report)
            generate_detailed_security_report
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log "ERROR" "Unknown command: $command"
            echo
            log "INFO" "Use '$0 help' to see available commands"
            exit 1
            ;;
    esac
}

# =============================================================================
# Script Entry Point
# =============================================================================

# Trap cleanup on exit
trap 'log "DEBUG" "Script execution completed"' EXIT

# Run main function with all arguments
main "$@"
