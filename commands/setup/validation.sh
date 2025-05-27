#!/bin/bash

# =============================================================================
# Setup Module: Final Validation and Service Startup
# Extracted from monolithic handle_setup() function
# =============================================================================

# Ensure logging is available
if ! command -v milou_log >/dev/null 2>&1; then
    if [[ -n "${SCRIPT_DIR:-}" ]] && [[ -f "${SCRIPT_DIR}/lib/core/logging.sh" ]]; then
        source "${SCRIPT_DIR}/lib/core/logging.sh" 2>/dev/null || {
            echo "ERROR: Cannot load logging module" >&2
            exit 1
        }
    else
        echo "ERROR: milou_log function not available" >&2
        exit 1
    fi
fi

# =============================================================================
# Final Validation and Service Startup Functions
# =============================================================================

# Main final validation coordinator
setup_final_validation() {
    milou_log "STEP" "Step 7: Final Validation and Service Startup"
    echo
    
    # Pre-startup validation
    _validate_system_readiness || return 1
    
    # SSL certificate setup
    _setup_ssl_certificates || return 1
    
    # Docker environment preparation
    _prepare_docker_environment || return 1
    
    # Service startup and validation
    _start_and_validate_services || return 1
    
    # Post-startup validation
    _validate_service_health || return 1
    
    # Final success report
    _generate_success_report || return 1
    
    return 0
}

# Validate system readiness before startup
_validate_system_readiness() {
    milou_log "INFO" "🔍 System Readiness Validation"
    
    local validation_errors=0
    
    # Check configuration file exists
    if [[ ! -f "${ENV_FILE:-}" ]]; then
        milou_log "ERROR" "Configuration file not found: ${ENV_FILE:-}"
        ((validation_errors++))
    else
        milou_log "DEBUG" "✅ Configuration file exists: ${ENV_FILE}"
    fi
    
    # Validate Docker access
    if ! milou_check_docker_access "true" "true" "true" "true"; then
        milou_log "ERROR" "Docker validation failed"
        ((validation_errors++))
    else
        milou_log "DEBUG" "✅ Docker access validated"
    fi
    
    # Check Docker Compose file
    local compose_file="${DOCKER_COMPOSE_FILE:-docker-compose.yml}"
    if [[ ! -f "$compose_file" ]]; then
        milou_log "ERROR" "Docker Compose file not found: $compose_file"
        ((validation_errors++))
    else
        milou_log "DEBUG" "✅ Docker Compose file exists: $compose_file"
    fi
    
    # Load and validate environment variables
    if [[ -f "${ENV_FILE:-}" ]]; then
        source "${ENV_FILE}" || {
            milou_log "ERROR" "Failed to load environment file: ${ENV_FILE}"
            ((validation_errors++))
        }
    fi
    
    # Validate essential environment variables
    local required_vars=("DOMAIN" "ADMIN_EMAIL" "ADMIN_PASSWORD" "DB_PASSWORD")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            milou_log "ERROR" "Required environment variable not set: $var"
            ((validation_errors++))
        fi
    done
    
    # Check GitHub token if present
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        if ! milou_validate_github_token "$GITHUB_TOKEN" "false"; then
            milou_log "WARN" "⚠️  GitHub token validation failed (continuing without registry auth)"
        else
            milou_log "DEBUG" "✅ GitHub token validated"
        fi
    fi
    
    if [[ $validation_errors -gt 0 ]]; then
        milou_log "ERROR" "System readiness validation failed with $validation_errors error(s)"
        return 1
    fi
    
    milou_log "SUCCESS" "✅ System readiness validation passed"
    return 0
}

# Setup SSL certificates based on configuration
_setup_ssl_certificates() {
    milou_log "INFO" "🔒 SSL Certificate Setup"
    
    local ssl_mode="${SSL_MODE:-generate}"
    
    case "$ssl_mode" in
        "generate")
            milou_log "INFO" "Generating self-signed SSL certificates..."
            _generate_ssl_certificates || return 1
            ;;
        "existing")
            milou_log "INFO" "Validating existing SSL certificates..."
            _validate_existing_ssl_certificates || return 1
            ;;
        "none")
            milou_log "INFO" "SSL disabled - skipping certificate setup"
            return 0
            ;;
        *)
            milou_log "ERROR" "Unknown SSL mode: $ssl_mode"
            return 1
            ;;
    esac
    
    milou_log "SUCCESS" "✅ SSL certificate setup completed"
    return 0
}

# Generate self-signed SSL certificates
_generate_ssl_certificates() {
    local ssl_dir="${SSL_DIR:-./ssl}"
    local domain="${DOMAIN:-localhost}"
    
    # Create SSL directory
    mkdir -p "$ssl_dir"
    
    # Check if certificates already exist
    if [[ -f "$ssl_dir/milou.crt" && -f "$ssl_dir/milou.key" ]]; then
        milou_log "INFO" "SSL certificates already exist - validating..."
        if milou_validate_ssl_certificates "$ssl_dir" "$domain" "false" "true"; then
            milou_log "INFO" "✅ Existing certificates are valid"
            return 0
        else
            milou_log "WARN" "⚠️  Existing certificates are invalid - regenerating..."
        fi
    fi
    
    # Generate new certificates
    if command -v milou_generate_ssl_certificates >/dev/null 2>&1; then
        milou_log "DEBUG" "Using milou_generate_ssl_certificates function"
        milou_generate_ssl_certificates "$ssl_dir" "$domain" || return 1
    else
        milou_log "DEBUG" "Using openssl directly for certificate generation"
        _generate_ssl_with_openssl "$ssl_dir" "$domain" || return 1
    fi
    
    # Validate generated certificates
    if milou_validate_ssl_certificates "$ssl_dir" "$domain" "false" "true"; then
        milou_log "SUCCESS" "✅ SSL certificates generated and validated"
        return 0
    else
        milou_log "ERROR" "Generated SSL certificates failed validation"
        return 1
    fi
}

# Generate SSL certificates using OpenSSL directly
_generate_ssl_with_openssl() {
    local ssl_dir="$1"
    local domain="$2"
    
    if ! command -v openssl >/dev/null 2>&1; then
        milou_log "ERROR" "OpenSSL not available for certificate generation"
        return 1
    fi
    
    # Generate private key
    openssl genrsa -out "$ssl_dir/milou.key" 2048 2>/dev/null || {
        milou_log "ERROR" "Failed to generate SSL private key"
        return 1
    }
    
    # Generate certificate
    openssl req -new -x509 -key "$ssl_dir/milou.key" -out "$ssl_dir/milou.crt" -days 365 \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=$domain" 2>/dev/null || {
        milou_log "ERROR" "Failed to generate SSL certificate"
        return 1
    }
    
    # Set secure permissions
    chmod 600 "$ssl_dir/milou.key"
    chmod 644 "$ssl_dir/milou.crt"
    
    milou_log "DEBUG" "SSL certificates generated with OpenSSL"
    return 0
}

# Validate existing SSL certificates
_validate_existing_ssl_certificates() {
    local cert_path="${SSL_CERT_PATH:-}"
    local key_path="${SSL_KEY_PATH:-}"
    local domain="${DOMAIN:-localhost}"
    
    if [[ -z "$cert_path" || -z "$key_path" ]]; then
        milou_log "ERROR" "SSL_CERT_PATH and SSL_KEY_PATH must be set for existing certificates"
        return 1
    fi
    
    # Validate the certificates
    if milou_validate_ssl_certificates "$cert_path" "$domain" "true" "false"; then
        milou_log "SUCCESS" "✅ Existing SSL certificates validated"
        return 0
    else
        milou_log "ERROR" "Existing SSL certificates validation failed"
        return 1
    fi
}

# Prepare Docker environment
_prepare_docker_environment() {
    milou_log "INFO" "🐳 Docker Environment Preparation"
    
    # Create Docker networks
    if command -v ensure_docker_networks >/dev/null 2>&1; then
        ensure_docker_networks || {
            milou_log "WARN" "⚠️  Failed to create some Docker networks"
        }
    fi
    
    # Stop any conflicting services
    if command -v detect_and_handle_conflicts >/dev/null 2>&1; then
        detect_and_handle_conflicts "prod" || {
            milou_log "ERROR" "Failed to handle conflicting services"
            return 1
        }
    fi
    
    # Validate Docker Compose configuration
    local compose_file="${DOCKER_COMPOSE_FILE:-docker-compose.yml}"
    if command -v milou_validate_docker_compose_config >/dev/null 2>&1; then
        if milou_validate_docker_compose_config "${ENV_FILE}" "$compose_file" "true"; then
            milou_log "DEBUG" "✅ Docker Compose configuration validated"
        else
            milou_log "WARN" "⚠️  Docker Compose configuration validation failed"
        fi
    fi
    
    milou_log "SUCCESS" "✅ Docker environment prepared"
    return 0
}

# Start and validate services
_start_and_validate_services() {
    milou_log "INFO" "🚀 Starting Milou Services"
    
    local compose_file="${DOCKER_COMPOSE_FILE:-docker-compose.yml}"
    
    # Start services with Docker Compose
    milou_log "INFO" "Starting Docker Compose services..."
    if docker compose --env-file "${ENV_FILE}" -f "$compose_file" up -d; then
        milou_log "INFO" "✅ Docker Compose services started"
    else
        milou_log "ERROR" "Failed to start Docker Compose services"
        return 1
    fi
    
    # Wait for services to be ready
    milou_log "INFO" "⏳ Waiting for services to be ready..."
    _wait_for_services_ready || return 1
    
    milou_log "SUCCESS" "✅ Services started and ready"
    return 0
}

# Wait for services to become ready
_wait_for_services_ready() {
    local max_wait=120  # 2 minutes
    local waited=0
    local interval=5
    
    while [[ $waited -lt $max_wait ]]; do
        milou_log "DEBUG" "Checking service readiness... (${waited}s/${max_wait}s)"
        
        # Check if key services are responding
        local services_ready=true
        
        # Check database (PostgreSQL)
        if ! docker compose exec -T postgres pg_isready >/dev/null 2>&1; then
            services_ready=false
        fi
        
        # Check Redis
        if ! docker compose exec -T redis redis-cli ping >/dev/null 2>&1; then
            services_ready=false
        fi
        
        if [[ "$services_ready" == "true" ]]; then
            milou_log "DEBUG" "✅ Core services are ready"
            return 0
        fi
        
        sleep $interval
        waited=$((waited + interval))
    done
    
    milou_log "WARN" "⚠️  Services did not become ready within ${max_wait}s"
    milou_log "INFO" "💡 Services may still be starting - check logs with: docker compose logs"
    return 1
}

# Validate service health after startup
_validate_service_health() {
    milou_log "INFO" "🏥 Service Health Validation"
    
    local health_errors=0
    
    # Check container status
    milou_log "DEBUG" "Checking container status..."
    local containers
    containers=$(docker compose ps --format "{{.Name}}\t{{.Status}}" 2>/dev/null || echo "")
    
    if [[ -n "$containers" ]]; then
        local running_count=0
        local total_count=0
        
        while IFS=$'\t' read -r name status; do
            ((total_count++))
            if [[ "$status" =~ Up|running ]]; then
                ((running_count++))
                milou_log "DEBUG" "✅ $name - $status"
            else
                milou_log "WARN" "⚠️  $name - $status"
                ((health_errors++))
            fi
        done <<< "$containers"
        
        milou_log "INFO" "📊 Container Status: $running_count/$total_count running"
    else
        milou_log "ERROR" "No containers found"
        ((health_errors++))
    fi
    
    # Check port accessibility
    milou_log "DEBUG" "Checking port accessibility..."
    local http_port="${HTTP_PORT:-80}"
    local https_port="${HTTPS_PORT:-443}"
    
    if [[ "$SSL_MODE" != "none" ]]; then
        if ! milou_check_port_availability "$https_port" "localhost" "true"; then
            milou_log "DEBUG" "✅ HTTPS port $https_port is in use (expected)"
        else
            milou_log "WARN" "⚠️  HTTPS port $https_port appears unused"
            ((health_errors++))
        fi
    fi
    
    if ! milou_check_port_availability "$http_port" "localhost" "true"; then
        milou_log "DEBUG" "✅ HTTP port $http_port is in use (expected)"
    else
        milou_log "WARN" "⚠️  HTTP port $http_port appears unused"
        ((health_errors++))
    fi
    
    if [[ $health_errors -eq 0 ]]; then
        milou_log "SUCCESS" "✅ Service health validation passed"
        return 0
    else
        milou_log "WARN" "⚠️  Service health validation completed with $health_errors warning(s)"
        milou_log "INFO" "💡 Services may still be starting up - check logs if issues persist"
        return 0  # Don't fail setup for health warnings
    fi
}

# Generate final success report
_generate_success_report() {
    milou_log "SUCCESS" "🎉 Milou Setup Completed Successfully!"
    echo
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}            MILOU SETUP COMPLETE! 🚀                ${NC}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════${NC}"
    echo
    
    # Access information
    local domain="${DOMAIN:-localhost}"
    local http_port="${HTTP_PORT:-80}"
    local https_port="${HTTPS_PORT:-443}"
    
    echo -e "${BOLD}📍 Access Information:${NC}"
    if [[ "$SSL_MODE" != "none" ]]; then
        if [[ "$https_port" == "443" ]]; then
            echo "  🌐 Web Interface: https://$domain"
        else
            echo "  🌐 Web Interface: https://$domain:$https_port"
        fi
    fi
    
    if [[ "$http_port" == "80" ]]; then
        echo "  🌐 HTTP Redirect: http://$domain"
    else
        echo "  🌐 HTTP Redirect: http://$domain:$http_port"
    fi
    echo
    
    # Admin credentials
    echo -e "${BOLD}👤 Admin Credentials:${NC}"
    echo "  Username: ${ADMIN_USERNAME:-admin}"
    echo "  Password: ${ADMIN_PASSWORD:-[check environment file]}"
    echo "  Email: ${ADMIN_EMAIL:-[not set]}"
    echo
    
    # Management commands
    echo -e "${BOLD}⚙️  Management Commands:${NC}"
    echo "  Status:  $0 status"
    echo "  Logs:    $0 logs [service]"
    echo "  Stop:    $0 stop"
    echo "  Restart: $0 restart"
    echo "  Update:  $0 update"
    echo
    
    # Important files
    echo -e "${BOLD}📁 Important Files:${NC}"
    echo "  Configuration: ${ENV_FILE:-[not set]}"
    if [[ "$SSL_MODE" == "generate" ]]; then
        echo "  SSL Certificate: ${SSL_DIR:-./ssl}/milou.crt"
        echo "  SSL Private Key: ${SSL_DIR:-./ssl}/milou.key"
    fi
    echo
    
    # Security notes
    echo -e "${BOLD}🔒 Security Notes:${NC}"
    echo "  • Configuration file has secure permissions (600)"
    if [[ "$SSL_MODE" == "generate" ]]; then
        echo "  • Self-signed SSL certificates generated"
        echo "  • For production, consider using valid SSL certificates"
    fi
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        echo "  • GitHub token configured for private registries"
    fi
    echo "  • Change default passwords before production use"
    echo
    
    # Next steps
    echo -e "${BOLD}💡 Next Steps:${NC}"
    echo "  1. Access the web interface using the URL above"
    echo "  2. Log in with the admin credentials"
    echo "  3. Complete the initial setup wizard"
    echo "  4. Configure your security settings"
    echo "  5. Review the logs: $0 logs"
    echo
    
    echo -e "${BOLD}${GREEN}Ready to go! 🎯${NC}"
    echo
    
    return 0
}

# Export functions
export -f setup_final_validation
export -f _validate_system_readiness
export -f _setup_ssl_certificates
export -f _generate_ssl_certificates
export -f _generate_ssl_with_openssl
export -f _validate_existing_ssl_certificates
export -f _prepare_docker_environment
export -f _start_and_validate_services
export -f _wait_for_services_ready
export -f _validate_service_health
export -f _generate_success_report 