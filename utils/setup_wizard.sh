#!/bin/bash

# Interactive Setup Wizard for Milou CLI

# Import utility functions
source "${SCRIPT_DIR}/utils/utils.sh" 2>/dev/null || true

# Colors for interactive prompts
readonly CYAN_PROMPT='\033[0;36m'
readonly MAGENTA_PROMPT='\033[0;35m'
readonly BOLD_PROMPT='\033[1m'
readonly NC_PROMPT='\033[0m'

# Interactive prompts
prompt_user() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local is_hidden="${4:-false}"
    
    if [[ "$is_hidden" == "true" ]]; then
        echo -ne "${CYAN_PROMPT}${prompt}${NC_PROMPT}"
        [[ -n "$default" ]] && echo -ne " ${YELLOW}(default: *****)${NC_PROMPT}"
        echo -ne ": "
        read -s user_input
        echo  # New line after secret input
    else
        echo -ne "${CYAN_PROMPT}${prompt}${NC_PROMPT}"
        [[ -n "$default" ]] && echo -ne " ${YELLOW}(default: $default)${NC_PROMPT}"
        echo -ne ": "
        read user_input
    fi
    
    # Use default if no input provided
    if [[ -z "$user_input" && -n "$default" ]]; then
        user_input="$default"
    fi
    
    # Set the variable dynamically
    eval "$var_name='$user_input'"
}

# Validate user inputs interactively
validate_input() {
    local input="$1"
    local type="$2"
    local field_name="$3"
    
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
    if ! generate_config "$domain" "$ssl_path"; then
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
    if ! pull_images "$github_token"; then
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