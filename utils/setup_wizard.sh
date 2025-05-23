#!/bin/bash

# Interactive Setup Wizard for Milou CLI

# Import utility functions
source "${SCRIPT_DIR}/utils/utils.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/utils/docker-registry.sh" 2>/dev/null || true

# Colors for interactive prompts
readonly CYAN_PROMPT='\033[0;36m'
readonly MAGENTA_PROMPT='\033[0;35m'
readonly BOLD_PROMPT='\033[1m'
readonly NC_PROMPT='\033[0m'

# Interactive prompts
prompt_user() {
    local prompt_text="$1"
    local default_value="$2"
    local var_to_set="$3"
    local is_hidden_input="${4:-false}"

    local current_user_input # Variable to store read input

    if [[ "$is_hidden_input" == "true" ]]; then
        # Prompt for hidden input (e.g., passwords, tokens)
        echo -ne "${CYAN_PROMPT}${prompt_text}${NC_PROMPT}"
        [[ -n "$default_value" ]] && echo -ne " ${YELLOW}(default: *****)${NC_PROMPT}"
        echo -ne ": "
        read -rs current_user_input # Use -r to read raw input, -s for silent
        echo  # Ensure a new line after hidden input
    else
        # Prompt for regular input
        echo -ne "${CYAN_PROMPT}${prompt_text}${NC_PROMPT}"
        [[ -n "$default_value" ]] && echo -ne " ${YELLOW}(default: $default_value)${NC_PROMPT}"
        echo -ne ": "
        read -r current_user_input # Use -r to read raw input
    fi

    # Use default_value if no input was provided by the user
    if [[ -z "$current_user_input" && -n "$default_value" ]]; then
        current_user_input="$default_value"
    fi

    # Safely set the target variable using printf -v
    # This avoids issues with special characters in current_user_input that could break eval
    if printf -v "$var_to_set" '%s' "$current_user_input"; then
        return 0 # Success
    else
        # In case printf -v fails (e.g., var_to_set is an invalid variable name)
        # Fallback error echo if log function is not available
        echo "[ERROR] Critical: Failed to set variable '$var_to_set' in prompt_user function." >&2
        return 1 # Failure
    fi
}

# Validate user inputs interactively
validate_input() {
    local input="$1"
    local type="$2"
    
    case "$type" in
        "github_token")
            if [[ -z "$input" ]]; then
                echo -e "${RED}Error: GitHub token is required${NC_PROMPT}"
                return 1
            fi
            if ! validate_github_token "$input"; then
                echo -e "${RED}Error: Invalid GitHub token format${NC_PROMPT}"
                echo "Token should start with 'ghp_', 'gho_', 'ghu_', 'ghs_', or 'ghr_'"
                return 1
            fi
            ;;
        "domain")
            if [[ -n "$input" ]] && [[ "$input" != "localhost" ]]; then
                if ! validate_domain "$input"; then
                    echo -e "${RED}Error: Invalid domain format: $input${NC_PROMPT}"
                    return 1
                fi
            fi
            ;;
        "ssl_path")
            if [[ -n "$input" ]]; then
                local ssl_dir=$(dirname "$input")
                if [[ ! -d "$ssl_dir" ]]; then
                    echo -e "${RED}Error: SSL directory does not exist: $ssl_dir${NC_PROMPT}"
                    echo "Creating directory..."
                    mkdir -p "$ssl_dir" || {
                        echo -e "${RED}Error: Failed to create SSL directory${NC_PROMPT}"
                        return 1
                    }
                fi
            fi
            ;;
        "email")
            if [[ -n "$input" ]] && [[ ! "$input" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
                echo -e "${RED}Error: Invalid email format${NC_PROMPT}"
                return 1
            fi
            ;;
    esac
    
    return 0
}

# Test GitHub token authentication
test_github_auth() {
    local token="$1"
    
    echo -e "${BLUE}[INFO]${NC_PROMPT} Testing GitHub authentication..."
    
    # Test authentication by trying to login
    if echo "$token" | docker login ghcr.io -u "token" --password-stdin >/dev/null 2>&1; then
        echo -e "${GREEN}[SUCCESS]${NC_PROMPT} GitHub authentication successful"
        docker logout ghcr.io >/dev/null 2>&1
        return 0
    else
        echo -e "${RED}[ERROR]${NC_PROMPT} GitHub authentication failed"
        echo "Please check your token permissions and try again"
        return 1
    fi
}

# Interactive SSL certificate setup
setup_ssl_interactive() {
    local ssl_path="$1"
    local domain="$2"
    
    echo -e "\n${BOLD_PROMPT}${MAGENTA_PROMPT}=== SSL Certificate Setup ===${NC_PROMPT}"
    echo "SSL certificates are required for secure HTTPS access."
    echo
    
    # Check if certificates already exist
    if [[ -f "$ssl_path/milou.crt" && -f "$ssl_path/milou.key" ]]; then
        echo -e "${GREEN}[INFO]${NC_PROMPT} SSL certificates found at $ssl_path"
        if confirm "Use existing certificates?"; then
            return 0
        fi
    fi
    
    # Create SSL directory if it doesn't exist
    mkdir -p "$ssl_path"
    
    echo "Choose SSL certificate option:"
    echo "1) Use existing certificates (place milou.crt and milou.key in $ssl_path)"
    echo "2) Generate self-signed certificate for development"
    echo "3) Use Let's Encrypt (for production domains)"
    echo "4) Skip SSL setup (HTTP only - not recommended for production)"
    
    while true; do
        echo -ne "${CYAN_PROMPT}Enter your choice (1-4): ${NC_PROMPT}"
        read ssl_choice
        
        case "$ssl_choice" in
            1)
                echo "Please place your SSL certificate files in $ssl_path:"
                echo "  - milou.crt (certificate file)"
                echo "  - milou.key (private key file)"
                echo
                echo "Press Enter when ready to continue..."
                read
                
                if [[ -f "$ssl_path/milou.crt" && -f "$ssl_path/milou.key" ]]; then
                    echo -e "${GREEN}[SUCCESS]${NC_PROMPT} SSL certificates found"
                    return 0
                else
                    echo -e "${RED}[ERROR]${NC_PROMPT} Certificate files not found"
                    continue
                fi
                ;;
            2)
                echo "Generating self-signed certificate for $domain..."
                generate_self_signed_cert "$ssl_path" "$domain"
                return $?
                ;;
            3)
                echo "Let's Encrypt setup not implemented yet."
                echo "Please use option 1 or 2 for now."
                continue
                ;;
            4)
                echo -e "${YELLOW}[WARNING]${NC_PROMPT} Skipping SSL setup"
                echo "Your Milou instance will run on HTTP only"
                return 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter 1-4.${NC_PROMPT}"
                continue
                ;;
        esac
    done
}

# Generate self-signed certificate
generate_self_signed_cert() {
    local ssl_path="$1"
    local domain="$2"
    
    # Check if OpenSSL is available
    if ! command -v openssl >/dev/null 2>&1; then
        echo -e "${RED}[ERROR]${NC_PROMPT} OpenSSL is not installed"
        return 1
    fi
    
    echo "Generating self-signed certificate for $domain..."
    
    # Generate private key
    openssl genrsa -out "$ssl_path/milou.key" 2048 2>/dev/null || {
        echo -e "${RED}[ERROR]${NC_PROMPT} Failed to generate private key"
        return 1
    }
    
    # Generate certificate
    openssl req -new -x509 -key "$ssl_path/milou.key" -out "$ssl_path/milou.crt" -days 365 \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=$domain" 2>/dev/null || {
        echo -e "${RED}[ERROR]${NC_PROMPT} Failed to generate certificate"
        return 1
    }
    
    # Set appropriate permissions
    chmod 600 "$ssl_path/milou.key"
    chmod 644 "$ssl_path/milou.crt"
    
    echo -e "${GREEN}[SUCCESS]${NC_PROMPT} Self-signed certificate generated"
    echo "Certificate valid for 365 days"
    
    return 0
}

# Main interactive setup wizard
interactive_setup() {
    echo -e "${BOLD_PROMPT}${MAGENTA_PROMPT}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                    Milou Setup Wizard                         ║"
    echo "║                    Version ${VERSION:-1.1.0}                               ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC_PROMPT}"
    
    echo "Welcome to the Milou setup wizard!"
    echo "This wizard will guide you through the initial configuration."
    echo
    
    # Check prerequisites
    echo -e "${BOLD_PROMPT}Step 1: System Prerequisites${NC_PROMPT}"
    if ! check_prerequisites; then
        echo -e "${RED}[ERROR]${NC_PROMPT} Prerequisites check failed"
        return 1
    fi
    echo -e "${GREEN}[SUCCESS]${NC_PROMPT} Prerequisites check passed"
    echo
    
    # Collect configuration
    echo -e "${BOLD_PROMPT}Step 2: Configuration${NC_PROMPT}"
    
    local github_token=""
    local domain="localhost"
    local ssl_path="./ssl"
    local admin_email=""
    
    # GitHub token
    while true; do
        prompt_user "GitHub Personal Access Token" "" "github_token" "true"
        if validate_input "$github_token" "github_token" && test_github_auth "$github_token"; then
            break
        fi
        echo "Please try again with a valid GitHub token."
        echo
    done
    
    # Domain
    while true; do
        prompt_user "Domain name" "localhost" "domain"
        if validate_input "$domain" "domain"; then
            break
        fi
        echo "Please enter a valid domain name."
    done
    
    # SSL path
    while true; do
        prompt_user "SSL certificates directory" "./ssl" "ssl_path"
        if validate_input "$ssl_path" "ssl_path"; then
            break
        fi
        echo "Please enter a valid SSL path."
    done
    
    # Admin email (optional)
    prompt_user "Admin email (optional)" "" "admin_email"
    if [[ -n "$admin_email" ]]; then
        while ! validate_input "$admin_email" "email"; do
            prompt_user "Admin email (optional)" "" "admin_email"
        done
    fi
    
    echo
    echo -e "${BOLD_PROMPT}Step 3: Configuration Summary${NC_PROMPT}"
    echo "Domain: $domain"
    echo "SSL Path: $ssl_path"
    echo "Admin Email: ${admin_email:-Not provided}"
    echo "GitHub Token: *****(provided)"
    echo
    
    if ! confirm "Proceed with this configuration?"; then
        echo "Setup cancelled."
        return 1
    fi
    
    # Generate configuration
    echo -e "\n${BOLD_PROMPT}Step 4: Generating Configuration${NC_PROMPT}"
    if ! generate_config "$domain" "$ssl_path" "$admin_email"; then
        echo -e "${RED}[ERROR]${NC_PROMPT} Failed to generate configuration"
        return 1
    fi
    
    # Set up SSL
    echo -e "\n${BOLD_PROMPT}Step 5: SSL Certificate Setup${NC_PROMPT}"
    if ! setup_ssl_interactive "$ssl_path" "$domain"; then
        echo -e "${RED}[ERROR]${NC_PROMPT} SSL setup failed"
        return 1
    fi
    
    # Pull Docker images
    echo -e "\n${BOLD_PROMPT}Step 6: Pulling Docker Images${NC_PROMPT}"
    if ! pull_images "$github_token" "true"; then
        echo -e "${RED}[ERROR]${NC_PROMPT} Failed to pull Docker images"
        return 1
    fi
    
    # Final step - start services
    echo -e "\n${BOLD_PROMPT}Step 7: Starting Services${NC_PROMPT}"
    if confirm "Start Milou services now?"; then
        if start_services; then
            echo -e "\n${GREEN}${BOLD_PROMPT}🎉 Setup Complete!${NC_PROMPT}"
            echo
            echo "Milou is now running and accessible at:"
            echo "  https://$domain (if SSL is configured)"
            echo "  http://$domain:8080 (HTTP fallback)"
            echo
            echo "Useful commands:"
            echo "  ./milou.sh status    - Check service status"
            echo "  ./milou.sh logs      - View service logs"
            echo "  ./milou.sh health    - Run health checks"
            echo "  ./milou.sh help      - Show all commands"
        else
            echo -e "${RED}[ERROR]${NC_PROMPT} Failed to start services"
            echo "You can try starting them manually with: ./milou.sh start"
            return 1
        fi
    else
        echo -e "\n${GREEN}${BOLD_PROMPT}Setup Complete!${NC_PROMPT}"
        echo "Start services when ready with: ./milou.sh start"
    fi
    
    return 0
}

# Enhanced interactive setup wizard with better existing installation handling
interactive_setup_wizard() {
    echo
    echo -e "${BOLD}${PURPLE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${PURPLE}║                    Milou Setup Wizard                         ║${NC}"
    echo -e "${BOLD}${PURPLE}║                    Version ${SCRIPT_VERSION:-3.0.0}                     ║${NC}"
    echo -e "${BOLD}${PURPLE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo "Welcome to the Milou setup wizard!"
    echo "This wizard will guide you through the initial configuration."

    # Step 0: Pre-flight System Check with Enhanced Options
    echo -e "${BOLD}Step 0: Pre-flight System Check${NC}"
    echo "Let's first check your current system state..."
    echo
    
    # Detect existing installation and get details
    if detect_existing_installation; then
        # Fresh installation detected (return 0)
        export PRESERVE_EXISTING=false
        export FRESH_INSTALL=true
        log "SUCCESS" "Fresh installation detected - proceeding with new setup"
        echo
    else
        # Existing installation detected (return 1)
        show_existing_installation_summary
        
        echo "An existing Milou installation was detected. How would you like to proceed?"
        echo
        echo "  1) Preserve existing configuration and data (recommended for upgrades)"
        echo "  2) Start fresh with new configuration (will remove all containers and data)"
        echo "  3) Cancel setup"
        echo
        
        local setup_choice=""
        while true; do
            echo -ne "${CYAN}Choose option (1-3): ${NC}"
            read setup_choice
            case "$setup_choice" in
                1)
                    export PRESERVE_EXISTING=true
                    export FRESH_INSTALL=false
                    log "INFO" "✅ Will preserve existing configuration and data"
                    break
                    ;;
                2)
                    export PRESERVE_EXISTING=false
                    export FRESH_INSTALL=true
                    log "INFO" "🆕 Will start fresh (existing data will be removed)"
                    
                    echo
                    echo -e "${RED}⚠️  WARNING: This will remove all existing containers and data!${NC}"
                    if ! confirm "Are you sure you want to proceed with a fresh installation?" "N"; then
                        log "INFO" "Setup cancelled by user"
                        exit 0
                    fi
                    
                    # Stop and remove existing containers
                    log "INFO" "Stopping and removing existing containers..."
                    if docker ps -a --filter "name=static-" --format "{{.Names}}" | xargs -r docker rm -f >/dev/null 2>&1; then
                        log "SUCCESS" "Existing containers removed"
                    fi
                    
                    # Optionally remove volumes
                    if confirm "Also remove existing data volumes? (This will delete all data)" "N"; then
                        if docker volume ls --filter "name=static_" --format "{{.Name}}" | xargs -r docker volume rm >/dev/null 2>&1; then
                            log "SUCCESS" "Existing volumes removed"
                        fi
                    fi
                    break
                    ;;
                3)
                    log "INFO" "Setup cancelled by user"
                    exit 0
                    ;;
                *)
                    echo "Invalid choice. Please enter 1-3."
                    ;;
            esac
        done
        echo
    fi

    # Step 1: System Prerequisites
    echo -e "${BOLD}Step 1: System Prerequisites${NC}"
    check_system_requirements
    echo
    
    # Step 2: GitHub Authentication
    echo -e "${BOLD}Step 2: GitHub Authentication${NC}"
    local github_token=""
    while true; do
        echo -ne "${CYAN}GitHub Personal Access Token: ${NC}"
        read -rs github_token
        echo
        
        if [[ -z "$github_token" ]]; then
            log "ERROR" "GitHub token is required"
            continue
        fi
        
        if test_github_authentication "$github_token"; then
            break
        else
            echo "Please try again with a valid token."
            echo
        fi
    done
    echo
    
    # Step 3: Domain Configuration
    echo -e "${BOLD}Step 3: Domain Configuration${NC}"
    local domain="localhost"
    
    # Check if preserving existing config and get current domain
    if [[ "${PRESERVE_EXISTING:-false}" == "true" ]]; then
        local current_domain
        local env_file="${MILOU_EXISTING_ENV_FILE:-${SCRIPT_DIR}/.env}"
        current_domain=$(grep "^SERVER_NAME=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "localhost")
        if [[ "$current_domain" != "localhost" ]]; then
            echo "Current domain: $current_domain"
            if confirm "Keep existing domain ($current_domain)?" "Y"; then
                domain="$current_domain"
            else
                echo -ne "${CYAN}Enter new domain name: ${NC}"
                read user_domain
                if [[ -n "$user_domain" ]] && validate_input "$user_domain" "domain"; then
                    domain="$user_domain"
                fi
            fi
        else
            echo -ne "${CYAN}Domain name (default: localhost): ${NC}"
            read user_domain
            if [[ -n "$user_domain" ]] && validate_input "$user_domain" "domain"; then
                domain="$user_domain"
            fi
        fi
    else
        echo -ne "${CYAN}Domain name (default: localhost): ${NC}"
        read user_domain
        if [[ -n "$user_domain" ]] && validate_input "$user_domain" "domain"; then
            domain="$user_domain"
        fi
    fi
    echo
    
    # Step 4: SSL Configuration with Smart Detection
    echo -e "${BOLD}Step 4: SSL Configuration${NC}"
    local ssl_path="./ssl"
    local ssl_choice=""
    
    # Check if SSL certificates already exist
    if [[ -f "./ssl/milou.crt" && -f "./ssl/milou.key" ]]; then
        echo "📄 Existing SSL certificates found!"
        
        # Show certificate information
        if command -v openssl >/dev/null 2>&1; then
            echo
            echo "Certificate Information:"
            show_certificate_info "./ssl/milou.crt" "$domain"
        fi
        
        echo "SSL Certificate Options:"
        echo "  1) Use existing certificates"
        echo "  2) Generate new certificates"
        echo "  3) Specify different SSL path"
        echo
        
        while true; do
            echo -ne "${CYAN}Choose option (1-3): ${NC}"
            read ssl_choice
            case "$ssl_choice" in
                1)
                    ssl_path="./ssl"
                    log "INFO" "✅ Will use existing SSL certificates"
                    break
                    ;;
                2)
                    ssl_path="./ssl"
                    log "INFO" "🆕 Will generate new SSL certificates"
                    # Backup existing certificates
                    mv "./ssl/milou.crt" "./ssl/milou.crt.backup.$(date +%s)" 2>/dev/null || true
                    mv "./ssl/milou.key" "./ssl/milou.key.backup.$(date +%s)" 2>/dev/null || true
                    break
                    ;;
                3)
                    echo -ne "${CYAN}SSL certificates directory: ${NC}"
                    read user_ssl_path
                    if [[ -n "$user_ssl_path" ]]; then
                        ssl_path="$user_ssl_path"
                    fi
                    break
                    ;;
                *)
                    echo "Invalid choice. Please enter 1-3."
                    ;;
            esac
        done
    else
        echo -ne "${CYAN}SSL certificates directory (default: ./ssl): ${NC}"
        read user_ssl_path
        if [[ -n "$user_ssl_path" ]]; then
            ssl_path="$user_ssl_path"
        fi
    fi
    echo
    
    # Step 5: Optional Configuration
    echo -e "${BOLD}Step 5: Optional Configuration${NC}"
    local admin_email=""
    
    # Check if preserving existing and get current email
    if [[ "${PRESERVE_EXISTING:-false}" == "true" ]]; then
        local current_email
        local env_file="${MILOU_EXISTING_ENV_FILE:-${SCRIPT_DIR}/.env}"
        current_email=$(grep "^MILOU_ADMIN_EMAIL=" "$env_file" 2>/dev/null | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//' || echo "")
        if [[ -n "$current_email" ]]; then
            echo "Current admin email: $current_email"
            if confirm "Keep existing admin email ($current_email)?" "Y"; then
                admin_email="$current_email"
            else
                echo -ne "${CYAN}Enter new admin email (optional): ${NC}"
                read admin_email
                if [[ -n "$admin_email" ]] && ! validate_input "$admin_email" "email" false; then
                    log "WARN" "Invalid email format, skipping"
                    admin_email=""
                fi
            fi
        else
            echo -ne "${CYAN}Admin email (optional): ${NC}"
            read admin_email
            if [[ -n "$admin_email" ]] && ! validate_input "$admin_email" "email" false; then
                log "WARN" "Invalid email format, skipping"
                admin_email=""
            fi
        fi
    else
        echo -ne "${CYAN}Admin email (optional): ${NC}"
        read admin_email
        if [[ -n "$admin_email" ]] && ! validate_input "$admin_email" "email" false; then
            log "WARN" "Invalid email format, skipping"
            admin_email=""
        fi
    fi
    echo
    
    # Step 6: Image Version Strategy
    echo -e "${BOLD}Step 6: Image Version Strategy${NC}"
    echo "Choose Docker image versioning strategy:"
    echo "  1) Use latest available versions (recommended)"
    echo "  2) Use specific version (v1.0.0)"
    echo
    local use_latest=false
    while true; do
        echo -ne "${CYAN}Enter your choice (1-2): ${NC}"
        read version_choice
        case "$version_choice" in
            1) use_latest=true; break ;;
            2) use_latest=false; break ;;
            *) echo "Invalid choice. Please enter 1 or 2." ;;
        esac
    done
    echo
    
    # Configuration Summary
    echo -e "${BOLD}Step 7: Configuration Summary${NC}"
    echo "Setup Mode: $([ "${PRESERVE_EXISTING:-false}" == "true" ] && echo "Preserve existing" || echo "Fresh installation")"
    echo "Domain: $domain"
    echo "SSL Path: $ssl_path"
    echo "SSL Certificates: $([ "$ssl_choice" == "1" ] && echo "Use existing" || echo "Generate new")"
    echo "Admin Email: ${admin_email:-Not provided}"
    echo "GitHub Token: *****(provided)"
    echo "Image Strategy: $([ "$use_latest" == true ] && echo "Latest versions" || echo "Fixed version (v1.0.0)")"
    echo
    
    if ! confirm "Proceed with this configuration?" "Y"; then
        log "INFO" "Setup cancelled by user"
        exit 0
    fi
    echo
    
    # Step 8: Generate Configuration
    echo -e "${BOLD}Step 8: Generating Configuration${NC}"
    show_progress "Generating .env configuration file" 2
    
    # Choose configuration generation mode based on user choice
    if [[ "${PRESERVE_EXISTING:-false}" == "true" ]]; then
        # Use the credential preservation mode
        if ! generate_config_with_preservation "$domain" "$ssl_path" "$admin_email" "auto"; then
            error_exit "Failed to generate configuration with preservation"
        fi
        # Set the environment variable for later use
        export MILOU_PRESERVED_CREDENTIALS="true"
    else
        # Fresh installation - force new credentials
        if ! generate_config_with_preservation "$domain" "$ssl_path" "$admin_email" "never"; then
            error_exit "Failed to generate configuration"
        fi
        # Set the environment variable for later use
        export MILOU_PRESERVED_CREDENTIALS="false"
    fi
    echo
    
    # Step 9: SSL Certificate Setup (only if not using existing)
    echo -e "${BOLD}Step 9: SSL Certificate Setup${NC}"
    if [[ "$ssl_choice" != "1" ]]; then
        if ! setup_ssl "$ssl_path" "$domain"; then
            if ! confirm "SSL setup failed. Continue anyway?" "N"; then
                error_exit "Setup cancelled due to SSL certificate issues"
            fi
        fi
    else
        log "SUCCESS" "Using existing SSL certificates"
    fi
    echo
    
    # Step 10: Pull Docker Images
    echo -e "${BOLD}Step 10: Pulling Docker Images${NC}"
    show_progress "Validating image availability" 2
    if ! validate_images_exist "$github_token" "$use_latest"; then
        log "WARN" "Some images may not be available - continuing anyway"
    fi
    
    show_progress "Pulling Docker images from GitHub Container Registry" 2
    if ! pull_images "$github_token" "$use_latest"; then
        error_exit "Failed to pull Docker images"
    fi
    echo
    
    # Step 11: Start Services with Enhanced Handling
    echo -e "${BOLD}Step 11: Start Services${NC}"
    if confirm "Start services now?" "Y"; then
        show_progress "Starting services" 2
        # Use the enhanced startup function with setup mode enabled
        if start_services_with_checks "true"; then
            echo
            echo -e "${GREEN}${BOLD}🎉 Setup Complete!${NC}"
            echo
            echo "Milou is now running and accessible at:"
            if [[ "$domain" != "localhost" ]]; then
                echo "  🌐 https://$domain (if SSL is configured)"
                echo "  🌐 http://$domain (HTTP fallback)"
            else
                echo "  🌐 https://localhost (if SSL is configured)"
                echo "  🌐 http://localhost:8080 (HTTP fallback)"
            fi
            echo
            echo "Useful commands:"
            echo "  📊 ./milou.sh status       - Check service status"
            echo "  📋 ./milou.sh logs        - View service logs"
            echo "  🏥 ./milou.sh health      - Run health checks"
            echo "  📖 ./milou.sh help        - Show all commands"
            echo
            
            # Show setup summary
            echo -e "${BOLD}Setup Summary:${NC}"
            echo "  📝 Setup Mode: $([ "${PRESERVE_EXISTING:-false}" == "true" ] && echo "Preserved existing" || echo "Fresh installation")"
            echo "  🌍 Domain: $domain"
            echo "  🔒 SSL: $([ "$ssl_choice" == "1" ] && echo "Using existing certificates" || echo "Generated new certificates")"
            echo "  🔑 Credentials: $([ "${PRESERVE_EXISTING:-false}" == "true" ] && echo "Preserved existing" || echo "Generated new")"
            echo "  📧 Admin Email: ${admin_email:-Not provided}"
            echo
        else
            echo -e "${RED}[ERROR]${NC} Failed to start services"
            echo
            echo "🔧 Troubleshooting options:"
            echo "  1. Check service status: ./milou.sh status"
            echo "  2. View detailed logs: ./milou.sh logs"
            echo "  3. Run diagnostics: ./milou.sh diagnose"
            echo "  4. Try manual start: ./milou.sh start --force"
            echo
            return 1
        fi
    else
        echo
        echo -e "${GREEN}${BOLD}🎉 Configuration Complete!${NC}"
        echo
        echo "Setup completed successfully. Start services when ready with:"
        echo "  🚀 ./milou.sh start"
        echo
        echo "Setup Summary:"
        echo "  📝 Setup Mode: $([ "${PRESERVE_EXISTING:-false}" == "true" ] && echo "Preserved existing" || echo "Fresh installation")"
        echo "  🌍 Domain: $domain"
        echo "  🔒 SSL: $([ "$ssl_choice" == "1" ] && echo "Using existing certificates" || echo "Generated new certificates")"
        echo "  🔑 Credentials: $([ "${PRESERVE_EXISTING:-false}" == "true" ] && echo "Preserved existing" || echo "Generated new")"
        echo "  📧 Admin Email: ${admin_email:-Not provided}"
    fi
    
    return 0
} 