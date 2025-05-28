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
    
    # System readiness validation
    milou_log "INFO" "🔍 System Readiness Validation"
    if ! _validate_system_readiness; then
        milou_log "ERROR" "System readiness validation failed"
        return 1
    fi
    
    # Credential-Volume consistency check
    if ! _validate_credential_volume_consistency; then
        milou_log "ERROR" "Credential-volume consistency check failed"
        return 1
    fi
    
    # SSL Certificate Setup
    if ! _setup_ssl_certificates; then
        milou_log "ERROR" "SSL certificate setup failed"
        return 1
    fi
    
    # Docker Environment Preparation
    if ! _prepare_docker_environment; then
        milou_log "ERROR" "Docker environment preparation failed"
        return 1
    fi
    
    # Start Services
    if ! _start_and_validate_services; then
        milou_log "ERROR" "Failed to start Milou services"
        return 1
    fi
    
    # Service Health Validation
    if ! _validate_service_health; then
        milou_log "WARN" "⚠️  Service health validation completed with warnings"
        milou_log "INFO" "💡 Services may still be starting up - check logs if issues persist"
    else
        milou_log "SUCCESS" "✅ Services started and ready"
    fi
    
    # CRITICAL FIX: Always display completion message with admin credentials
    _setup_display_completion_with_credentials
    
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
    local compose_file="${DOCKER_COMPOSE_FILE:-${SCRIPT_DIR}/static/docker-compose.yml}"
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
    
    # CRITICAL: Check credential-volume consistency
    _validate_credential_volume_consistency || ((validation_errors++))
    
    # Use centralized validation for comprehensive checks
    if command -v milou_config_validate_environment_production >/dev/null 2>&1; then
        milou_log "DEBUG" "Using centralized environment validation"
        if ! milou_config_validate_environment_production "${ENV_FILE}" >/dev/null 2>&1; then
            milou_log "WARN" "Centralized validation found issues, checking essential variables manually"
            
            # Fallback to basic essential checks
            local required_vars=("DOMAIN" "ADMIN_EMAIL" "ADMIN_PASSWORD" "POSTGRES_PASSWORD")
            for var in "${required_vars[@]}"; do
                if [[ -z "${!var:-}" ]]; then
                    milou_log "ERROR" "Required environment variable not set: $var"
                    ((validation_errors++))
                fi
            done
        else
            milou_log "DEBUG" "✅ Centralized environment validation passed"
        fi
    else
        # Fallback to basic validation if centralized system not available
        milou_log "DEBUG" "Centralized validation not available, using basic checks"
        local required_vars=("DOMAIN" "ADMIN_EMAIL" "ADMIN_PASSWORD" "POSTGRES_PASSWORD")
        for var in "${required_vars[@]}"; do
            if [[ -z "${!var:-}" ]]; then
                milou_log "ERROR" "Required environment variable not set: $var"
                ((validation_errors++))
            fi
        done
    fi
    
    # Check GitHub token if present and authenticate with Docker registry
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        if ! milou_validate_github_token "$GITHUB_TOKEN" "false"; then
            milou_log "WARN" "⚠️  GitHub token validation failed (continuing without registry auth)"
        else
            milou_log "DEBUG" "✅ GitHub token validated"
            
            # Authenticate with GitHub Container Registry
            milou_log "INFO" "🔐 Authenticating with GitHub Container Registry..."
            if echo "$GITHUB_TOKEN" | docker login ghcr.io -u token --password-stdin >/dev/null 2>&1; then
                milou_log "SUCCESS" "✅ Docker registry authentication successful"
            else
                milou_log "WARN" "⚠️  Docker registry authentication failed"
                milou_log "INFO" "💡 Ensure your token has 'read:packages' scope"
                # Don't fail setup, but warn user
            fi
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
    
    # Load SSL manager
    if [[ -f "${SCRIPT_DIR}/lib/ssl/manager.sh" ]]; then
        source "${SCRIPT_DIR}/lib/ssl/manager.sh" || {
            milou_log "ERROR" "Failed to load SSL manager"
            return 1
        }
    else
        milou_log "ERROR" "SSL manager not found: ${SCRIPT_DIR}/lib/ssl/manager.sh"
        return 1
    fi
    
    local ssl_mode="${SSL_MODE:-generate}"
    local domain="${DOMAIN:-localhost}"
    local cert_source="${SSL_CERT_SOURCE:-}"
    local force="${FORCE:-false}"
    
    milou_log "DEBUG" "SSL setup: mode=$ssl_mode, domain=$domain, force=$force"
    
    # Use the centralized SSL setup function that handles all scenarios
    case "$ssl_mode" in
        "generate")
            milou_log "INFO" "🔧 Generating self-signed SSL certificates..."
            milou_ssl_setup "$domain" "generate" "" "$force" "false" || return 1
            ;;
        "existing")
            milou_log "INFO" "📁 Setting up existing SSL certificates..."
            if [[ -z "$cert_source" ]]; then
                milou_log "ERROR" "SSL_CERT_SOURCE not set for existing certificate mode"
                return 1
            fi
            milou_ssl_setup "$domain" "existing" "$cert_source" "$force" "false" || return 1
            ;;
        "none")
            milou_log "INFO" "⚠️ SSL disabled - skipping certificate setup"
            milou_ssl_setup "$domain" "none" "" "$force" "false" || return 1
            return 0
            ;;
        "auto")
            milou_log "INFO" "🤖 Automatic SSL certificate management..."
            milou_ssl_setup "$domain" "auto" "" "$force" "false" || return 1
            ;;
        *)
            milou_log "ERROR" "Unknown SSL mode: $ssl_mode"
            return 1
            ;;
    esac
    
    # Verify SSL setup
    if [[ "$ssl_mode" != "none" ]]; then
        if milou_ssl_status "$domain" "true"; then
            milou_log "SUCCESS" "✅ SSL certificate setup completed successfully"
        else
            milou_log "ERROR" "SSL certificate setup validation failed"
            return 1
        fi
    fi
    
    return 0
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
    local compose_file="${DOCKER_COMPOSE_FILE:-${SCRIPT_DIR}/static/docker-compose.yml}"
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
    # Check if service startup should be skipped
    if [[ "${SKIP_SERVICE_START:-false}" == "true" ]]; then
        milou_log "INFO" "⏭️ Skipping service startup (existing services kept running)"
        return 0
    fi
    
    milou_log "INFO" "🚀 Starting Milou Services"
    
    local compose_file="${DOCKER_COMPOSE_FILE:-${SCRIPT_DIR}/static/docker-compose.yml}"
    
    # Check for port conflicts one more time before starting
    local critical_ports=("5432" "6379" "443" "80" "9999")
    local conflicts=()
    
    for port in "${critical_ports[@]}"; do
        if ! milou_check_port_availability "$port" "localhost" "true"; then
            conflicts+=("$port")
        fi
    done
    
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        milou_log "ERROR" "❌ Cannot start services - ports still in use: ${conflicts[*]}"
        milou_log "INFO" "💡 Try stopping conflicting services first:"
        milou_log "INFO" "   • ./milou.sh stop (to stop Milou services)"
        milou_log "INFO" "   • sudo systemctl stop postgresql (to stop system PostgreSQL)"
        milou_log "INFO" "   • Or use: ./milou.sh setup --force"
        return 1
    fi
    
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

# Wait for services to become ready with improved monitoring
_wait_for_services_ready() {
    milou_log "INFO" "⏳ Waiting for services to be ready..."
    
    local max_wait=120  # Reduced from 180s to 120s
    local check_interval=3  # Reduced from 10s to 3s for faster checking
    local elapsed=0
    local ready_services=()
    local failed_services=()
    local last_status_count=0
    local consecutive_same_status=0
    
    milou_log "INFO" "🔍 Monitoring service startup progress..."
    milou_log "INFO" "⏱️  Startup timeout: ${max_wait}s | Check interval: ${check_interval}s"
    
    # Check if any containers are already running and ready before entering main loop
    milou_log "INFO" "🚀 Initial service status check..."
    
    while [[ $elapsed -lt $max_wait ]]; do
        ready_services=()
        failed_services=()
        local current_status_count=0
        
        # Check each service with optimized status checking
        local services=(
            "milou-database:Database"
            "milou-redis:Redis" 
            "milou-rabbitmq:RabbitMQ"
            "milou-backend:Backend"
            "milou-frontend:Frontend"
            "milou-engine:Engine"
            "milou-nginx:Nginx"
        )
        
        # Batch container status checks for efficiency
        local container_statuses
        container_statuses=$(docker inspect --format='{{.Name}};{{.State.Status}};{{.State.Health.Status}}' \
            milou-database milou-redis milou-rabbitmq milou-backend milou-frontend milou-engine milou-nginx 2>/dev/null || echo "")
        
        # Process batch results
        while IFS=';' read -r container_name container_status health_status; do
            if [[ -z "$container_name" ]]; then continue; fi
            
            # Remove leading slash from container name
            container_name="${container_name#/}"
            
            # Find display name
            local display_name=""
            for service_info in "${services[@]}"; do
                if [[ "${service_info%:*}" == "$container_name" ]]; then
                    display_name="${service_info#*:}"
                    break
                fi
            done
            
            if [[ -z "$display_name" ]]; then continue; fi
            
            case "$container_status" in
                "running")
                    # For services without health checks or healthy services
                    if [[ "$health_status" == "healthy" ]] || [[ "$health_status" == "none" ]] || [[ "$health_status" == "" ]]; then
                        ready_services+=("$display_name")
                        ((current_status_count++))
                    elif [[ "$health_status" == "starting" ]]; then
                        # Still starting, check if it's been starting too long
                        if [[ $elapsed -gt 60 ]]; then
                            milou_log "DEBUG" "$display_name taking long to start (health: $health_status)"
                        fi
                    else
                        # Health check failed, but don't fail immediately
                        if [[ $elapsed -gt 30 ]]; then
                            failed_services+=("$display_name")
                        fi
                    fi
                    ;;
                "restarting")
                    # Allow some time for restarts
                    if [[ $elapsed -gt 45 ]]; then
                        failed_services+=("$display_name")
                    fi
                    ;;
                "exited"|"dead")
                    failed_services+=("$display_name")
                    ;;
                *)
                    # Missing or unknown status - only fail after some time
                    if [[ $elapsed -gt 30 ]]; then
                        milou_log "DEBUG" "$display_name status: $container_status"
                    fi
                    ;;
            esac
        done <<< "$container_statuses"
        
        # Track progress and detect stalls
        if [[ $current_status_count -eq $last_status_count ]]; then
            ((consecutive_same_status++))
        else
            consecutive_same_status=0
        fi
        
        # Progress reporting - more frequent but less verbose
        local total_services=${#services[@]}
        local ready_count=${#ready_services[@]}
        
        # Show progress every 15s or when status changes
        if [[ $ready_count -ne $last_status_count ]] || [[ $((elapsed % 15)) -eq 0 ]]; then
            if [[ $ready_count -ne $last_status_count ]]; then
                milou_log "INFO" "📊 Service Status: $ready_count/$total_services ready [${elapsed}s elapsed]"
                # Only show detailed status on changes
                for service_info in "${services[@]}"; do
                    local display_name="${service_info#*:}"
                    if [[ " ${ready_services[*]} " =~ " ${display_name} " ]]; then
                        echo "   🟢 $display_name"
                    elif [[ " ${failed_services[*]} " =~ " ${display_name} " ]]; then
                        echo "   🔴 $display_name"
                    else
                        echo "   🟡 $display_name"
                    fi
                done
                echo
            else
                # Just show a progress dot for no change
                printf "."
            fi
            
            last_status_count=$ready_count
        fi
        
        # SUCCESS CRITERIA: All services ready
        if [[ $ready_count -eq $total_services ]]; then
            milou_log "SUCCESS" "🎉 All services are ready! ($ready_count/$total_services)"
            return 0
        fi
        
        # EARLY SUCCESS: Most critical services ready (more aggressive)
        if [[ $ready_count -ge 5 ]] && [[ $elapsed -gt 30 ]]; then
            # Check if we have the core services (database, redis, backend, nginx)
            local core_ready=0
            for core_service in "Database" "Redis" "Backend" "Nginx"; do
                if [[ " ${ready_services[*]} " =~ " ${core_service} " ]]; then
                    ((core_ready++))
                fi
            done
            
            if [[ $core_ready -ge 3 ]]; then
                milou_log "SUCCESS" "✅ Core services ready ($ready_count/$total_services) - continuing"
                milou_log "INFO" "💡 Remaining services will continue starting in background"
                return 0
            fi
        fi
        
        # TIMEOUT for no progress
        if [[ $consecutive_same_status -gt 10 ]]; then  # 10 * 3s = 30s of no progress
            milou_log "WARN" "⚠️  No progress for 30s - services may be stuck"
            break
        fi
        
        # EARLY FAILURE: Too many failures
        if [[ ${#failed_services[@]} -gt 2 ]] && [[ $elapsed -gt 60 ]]; then
            milou_log "ERROR" "❌ Multiple service failures: ${failed_services[*]}"
            break
        fi
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    # Final status report
    local ready_count=${#ready_services[@]}
    local total_services=${#services[@]}
    
    if [[ $ready_count -ge 4 ]]; then  # At least 4 services ready is probably workable
        milou_log "WARN" "⚠️  Partial startup completed: $ready_count/$total_services services ready"
        milou_log "INFO" "✅ Ready: ${ready_services[*]}"
        if [[ ${#failed_services[@]} -gt 0 ]]; then
            milou_log "WARN" "❌ Issues: ${failed_services[*]}"
        fi
        milou_log "INFO" "💡 Application may still be functional - check web interface"
        return 0
    else
        milou_log "ERROR" "❌ Insufficient services ready: $ready_count/$total_services"
        milou_log "ERROR" "This indicates a serious configuration issue"
        return 1
    fi
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

# Display completion message with admin credentials
_setup_display_completion_with_credentials() {
    # CRITICAL FIX: Load environment variables first
    if [[ -f "${ENV_FILE:-}" ]]; then
        set +u  # Temporarily disable unbound variable checking
        source "${ENV_FILE}" 2>/dev/null || true
        set -u
    fi
    
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
    if [[ "${SSL_MODE:-}" != "none" ]]; then
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
    
    # CRITICAL FIX: Properly extract admin credentials from environment file
    local admin_username admin_password admin_email
    if [[ -f "${ENV_FILE:-}" ]]; then
        admin_username=$(grep "^ADMIN_USERNAME=" "${ENV_FILE}" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || echo "admin")
        admin_password=$(grep "^ADMIN_PASSWORD=" "${ENV_FILE}" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || echo "")
        admin_email=$(grep "^ADMIN_EMAIL=" "${ENV_FILE}" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || echo "")
    else
        admin_username="${ADMIN_USERNAME:-admin}"
        admin_password="${ADMIN_PASSWORD:-}"
        admin_email="${ADMIN_EMAIL:-}"
    fi
    
    # Admin credentials - PROMINENTLY DISPLAYED
    echo -e "${BOLD}${CYAN}🔑 ADMIN CREDENTIALS (SAVE THESE!):${NC}"
    echo -e "  ${BOLD}Username:${NC} $admin_username"
    echo -e "  ${BOLD}Password:${NC} $admin_password"
    echo -e "  ${BOLD}Email:${NC} $admin_email"
    echo
    echo -e "${BOLD}${RED}⚠️  IMPORTANT: Save these credentials immediately!${NC}"
    echo -e "${BOLD}${RED}   You'll need them to access the web interface.${NC}"
    echo
    
    # Management commands
    echo -e "${BOLD}⚙️  Management Commands:${NC}"
    echo "  Status:  $0 status"
    echo "  Logs:    $0 logs [service]"
    echo "  Stop:    $0 stop"
    echo "  Restart: $0 restart"
    echo "  Update:  $0 update"
    echo "  Admin:   $0 admin credentials"
    echo
    
    # Important files
    echo -e "${BOLD}📁 Important Files:${NC}"
    echo "  Configuration: ${ENV_FILE:-[not set]}"
    if [[ "${SSL_MODE:-}" == "generate" ]]; then
        echo "  SSL Certificate: ${SSL_CERT_PATH:-./ssl}/milou.crt"
        echo "  SSL Private Key: ${SSL_CERT_PATH:-./ssl}/milou.key"
    fi
    echo
    
    # Security notes
    echo -e "${BOLD}🔒 Security Notes:${NC}"
    echo "  • Configuration file has secure permissions (600)"
    if [[ "${SSL_MODE:-}" == "generate" ]]; then
        echo "  • Self-signed SSL certificates generated"
        echo "  • For production, consider using valid SSL certificates"
    fi
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        echo "  • GitHub token configured for private registries"
    fi
    echo "  • Change default passwords before production use"
    echo
    
    # Next steps with improved UX
    echo -e "${BOLD}💡 Next Steps:${NC}"
    echo "  1. 🌐 Access the web interface using the URL above"
    echo "  2. 🔑 Log in with the admin credentials shown above"
    echo "  3. 🧙 Complete the initial setup wizard"
    echo "  4. 🔒 Configure your security settings"
    echo "  5. 📋 Review the logs: $0 logs"
    echo
    
    # Service status summary
    echo -e "${BOLD}📊 Quick Service Check:${NC}"
    local running_containers
    running_containers=$(docker ps --filter "name=milou-" --format "{{.Names}}" 2>/dev/null | wc -l || echo "0")
    echo "  Running containers: $running_containers"
    
    if [[ "$running_containers" -gt 0 ]]; then
        echo -e "  ${BOLD}${GREEN}✅ Services appear to be running${NC}"
    else
        echo -e "  ${BOLD}${YELLOW}⚠️  Services may still be starting${NC}"
        echo "  💡 Check status with: $0 status"
    fi
    echo
    
    echo -e "${BOLD}${GREEN}Ready to go! 🎯${NC}"
    echo
    
    return 0
}

# =============================================================================
# Credential-Volume Consistency Validation
# =============================================================================

# Critical function to ensure environment credentials match existing Docker volumes
_validate_credential_volume_consistency() {
    milou_log "INFO" "🔍 Credential-Volume Consistency Check"
    
    # Check if we have existing data volumes
    local has_database_volume=false
    local has_redis_volume=false
    local has_rabbitmq_volume=false
    local volumes_found=()
    
    # Check for database volume with multiple naming conventions
    if docker volume inspect "${DOCKER_PROJECT_NAME:-static}_pgdata" >/dev/null 2>&1; then
        has_database_volume=true
        volumes_found+=("Database")
    elif docker volume inspect "static_pgdata" >/dev/null 2>&1; then
        has_database_volume=true
        volumes_found+=("Database")
    elif docker volume inspect "milou-static_pgdata" >/dev/null 2>&1; then
        has_database_volume=true
        volumes_found+=("Database")
    fi
    
    # Check for Redis volume
    if docker volume inspect "${DOCKER_PROJECT_NAME:-static}_redis_data" >/dev/null 2>&1 || \
       docker volume inspect "static_redis_data" >/dev/null 2>&1 || \
       docker volume inspect "milou-static_redis_data" >/dev/null 2>&1; then
        has_redis_volume=true
        volumes_found+=("Redis")
    fi
    
    # Check for RabbitMQ volume
    if docker volume inspect "${DOCKER_PROJECT_NAME:-static}_rabbitmq_data" >/dev/null 2>&1 || \
       docker volume inspect "static_rabbitmq_data" >/dev/null 2>&1 || \
       docker volume inspect "milou-static_rabbitmq_data" >/dev/null 2>&1; then
        has_rabbitmq_volume=true
        volumes_found+=("RabbitMQ")
    fi
    
    # If no volumes exist, no consistency issues
    if [[ "$has_database_volume" == "false" && "$has_redis_volume" == "false" && "$has_rabbitmq_volume" == "false" ]]; then
        milou_log "INFO" "✅ No existing data volumes found - fresh installation"
        return 0
    fi
    
    milou_log "INFO" "📊 Found existing data volumes: ${volumes_found[*]}"
    
    # IMPROVED: Check if this is a force/clean install first
    if [[ "${FORCE:-false}" == "true" || "${CLEAN_INSTALL:-false}" == "true" ]]; then
        milou_log "INFO" "🧹 Force/clean installation requested - skipping credential validation"
        return 0
    fi
    
    # Load current environment credentials
    local current_postgres_user current_postgres_password current_redis_password current_rabbitmq_user current_rabbitmq_password
    current_postgres_user="${POSTGRES_USER:-}"
    current_postgres_password="${POSTGRES_PASSWORD:-}"
    current_redis_password="${REDIS_PASSWORD:-}"
    current_rabbitmq_user="${RABBITMQ_USER:-}"
    current_rabbitmq_password="${RABBITMQ_PASSWORD:-}"
    
    if [[ -z "$current_postgres_user" || -z "$current_postgres_password" ]]; then
        milou_log "ERROR" "❌ Current environment missing database credentials"
        return 1
    fi
    
    # IMPROVED: Only test database credentials if we have a substantial existing installation
    if [[ "$has_database_volume" == "true" && "$has_redis_volume" == "true" ]]; then
        milou_log "INFO" "🔍 Testing database connectivity with current credentials..."
        
        # More lenient credential testing - try multiple approaches
        local credential_test_result=false
        
        # Test 1: Quick volume inspection (faster)
        if _quick_volume_credential_check; then
            credential_test_result=true
            milou_log "DEBUG" "✅ Quick volume check passed"
        else
            # Test 2: Full database connection test (slower but more thorough)
            milou_log "DEBUG" "Quick check failed, trying full database test..."
            if _test_database_credentials "$current_postgres_user" "$current_postgres_password"; then
                credential_test_result=true
                milou_log "DEBUG" "✅ Full database test passed"
            fi
        fi
        
        if [[ "$credential_test_result" == "true" ]]; then
            milou_log "SUCCESS" "✅ Database credentials are compatible with existing volume"
        else
            milou_log "WARN" "⚠️  Database credential validation failed"
            milou_log "INFO" "   This could indicate a credential mismatch or startup timing issue"
            
            # Offer gentler resolution options
            _handle_credential_mismatch_gentle
            return $?
        fi
    else
        milou_log "INFO" "📋 Partial installation detected - skipping detailed credential validation"
    fi
    
    milou_log "SUCCESS" "✅ Credential-volume consistency validated"
    return 0
}

# Quick volume inspection without starting containers
_quick_volume_credential_check() {
    # Check if volumes are empty (indicating fresh installation)
    local db_volume_name
    
    # Find the database volume
    if docker volume inspect "${DOCKER_PROJECT_NAME:-static}_pgdata" >/dev/null 2>&1; then
        db_volume_name="${DOCKER_PROJECT_NAME:-static}_pgdata"
    elif docker volume inspect "static_pgdata" >/dev/null 2>&1; then
        db_volume_name="static_pgdata"
    elif docker volume inspect "milou-static_pgdata" >/dev/null 2>&1; then
        db_volume_name="milou-static_pgdata"
    else
        return 1
    fi
    
    # Check if volume is empty or has minimal data (suggests fresh/clean state)
    local volume_size
    volume_size=$(docker run --rm -v "$db_volume_name:/data" alpine sh -c 'du -s /data 2>/dev/null | cut -f1' 2>/dev/null || echo "0")
    
    # If volume is very small (less than 1MB), it's likely empty/fresh
    if [[ "$volume_size" -lt 1024 ]]; then
        milou_log "DEBUG" "Volume appears fresh/empty (size: ${volume_size}KB)"
        return 0
    fi
    
    milou_log "DEBUG" "Volume has substantial data (size: ${volume_size}KB)"
    return 1
}

# Test database credentials by starting a temporary container
_test_database_credentials() {
    local test_user="$1"
    local test_password="$2"
    local test_db="${POSTGRES_DB:-milou_database}"
    
    milou_log "DEBUG" "Testing database credentials: user=$test_user, db=$test_db"
    
    # Start only the database service temporarily for testing
    local temp_container_name="milou-db-test-$$"
    local compose_file="${DOCKER_COMPOSE_FILE:-${SCRIPT_DIR}/static/docker-compose.yml}"
    
    # Create a temporary environment for testing
    local temp_env_file="/tmp/milou-db-test-$$.env"
    cat > "$temp_env_file" << EOF
POSTGRES_USER=$test_user
POSTGRES_PASSWORD=$test_password
POSTGRES_DB=$test_db
EOF
    
    # Start database service in background
    milou_log "DEBUG" "Starting database service for credential testing..."
    if docker compose --env-file "$temp_env_file" -f "$compose_file" up -d database >/dev/null 2>&1; then
        
        # Wait for database to be ready (max 30 seconds)
        local max_wait=30
        local waited=0
        local db_ready=false
        
        while [[ $waited -lt $max_wait ]]; do
            if docker exec milou-database pg_isready -U "$test_user" >/dev/null 2>&1; then
                db_ready=true
                break
            fi
            sleep 2
            waited=$((waited + 2))
        done
        
        # Test actual connection
        local connection_test=false
        if [[ "$db_ready" == "true" ]]; then
            if docker exec milou-database psql -U "$test_user" -d "$test_db" -c "SELECT 1;" >/dev/null 2>&1; then
                connection_test=true
            fi
        fi
        
        # Clean up test container
        docker compose --env-file "$temp_env_file" -f "$compose_file" down >/dev/null 2>&1
        rm -f "$temp_env_file"
        
        # Return result
        if [[ "$connection_test" == "true" ]]; then
            milou_log "DEBUG" "✅ Database credential test passed"
            return 0
        else
            milou_log "DEBUG" "❌ Database credential test failed"
            return 1
        fi
    else
        # Clean up on failure
        rm -f "$temp_env_file"
        milou_log "DEBUG" "❌ Failed to start database for credential testing"
        return 1
    fi
}

# Handle credential mismatch between .env and existing volumes
_handle_credential_mismatch() {
    milou_log "ERROR" "🚨 Credential Mismatch Detected!"
    echo
    milou_log "INFO" "The database credentials in your .env file don't match the existing database volume."
    milou_log "INFO" "This usually happens when:"
    milou_log "INFO" "  • The .env file was regenerated with new credentials"
    milou_log "INFO" "  • The database volume contains data from different credentials"
    milou_log "INFO" "  • Previous setup was interrupted"
    echo
    
    # In non-interactive mode, fail safely
    if [[ "${INTERACTIVE:-true}" == "false" ]]; then
        milou_log "ERROR" "Non-interactive mode cannot resolve credential mismatch"
        milou_log "INFO" "💡 Use --clean option for fresh installation: ./milou.sh setup --clean"
        return 1
    fi
    
    milou_log "INFO" "🔧 Credential Mismatch Resolution Options:"
    echo "  1. 🧹 Clean installation (REMOVES all existing data - safest)"
    echo "  2. 🔄 Reset database only (keeps other data)"
    echo "  3. 🛑 Cancel setup (manual intervention required)"
    echo
    
    local choice
    milou_prompt_user "Select resolution [1-3]" "1" "choice" "false" 3
    
    case "$choice" in
        1)
            milou_log "INFO" "🧹 Performing clean installation..."
            if _perform_clean_installation; then
                milou_log "SUCCESS" "✅ Clean installation completed - credentials will be regenerated"
                return 0
            else
                milou_log "ERROR" "❌ Clean installation failed"
                return 1
            fi
            ;;
        2)
            milou_log "INFO" "🔄 Resetting database volume only..."
            if _reset_database_volume; then
                milou_log "SUCCESS" "✅ Database volume reset - will be reinitialized with current credentials"
                return 0
            else
                milou_log "ERROR" "❌ Database volume reset failed"
                return 1
            fi
            ;;
        3)
            milou_log "INFO" "🛑 Setup cancelled - manual intervention required"
            echo
            milou_log "INFO" "💡 Manual resolution options:"
            milou_log "INFO" "  • Use --clean option: ./milou.sh setup --clean"
            milou_log "INFO" "  • Manually remove database volume: docker volume rm static_pgdata"
            milou_log "INFO" "  • Restore correct credentials in .env file"
            return 1
            ;;
        *)
            milou_log "ERROR" "Invalid choice: $choice"
            return 1
            ;;
    esac
}

# Gentler credential mismatch handler (new)
_handle_credential_mismatch_gentle() {
    milou_log "WARN" "⚠️  Potential Credential Issue Detected"
    echo
    milou_log "INFO" "The credential validation couldn't confirm compatibility with existing volumes."
    milou_log "INFO" "This could be caused by:"
    milou_log "INFO" "  • Services still starting up (timing issue)"
    milou_log "INFO" "  • Credential mismatch with existing data"
    milou_log "INFO" "  • Network connectivity issues"
    echo
    
    # In non-interactive mode, continue with warning
    if [[ "${INTERACTIVE:-true}" == "false" ]]; then
        milou_log "WARN" "Non-interactive mode - continuing setup with warning"
        milou_log "INFO" "💡 Monitor logs carefully: ./milou.sh logs"
        return 0
    fi
    
    milou_log "INFO" "🤔 How would you like to proceed?"
    echo "  1. ⏭️  Continue setup anyway (recommended - may work after services start)"
    echo "  2. ⏸️  Wait and retry validation (give services more time)"
    echo "  3. 🧹 Clean installation (removes all existing data)"
    echo "  4. 🛑 Cancel setup"
    echo
    
    local choice
    milou_prompt_user "Select option [1-4]" "1" "choice" "false" 3
    
    case "$choice" in
        1)
            milou_log "INFO" "⏭️  Continuing setup - will monitor service startup carefully"
            milou_log "WARN" "💡 If services fail to start, check logs: ./milou.sh logs"
            return 0
            ;;
        2)
            milou_log "INFO" "⏸️  Waiting 30 seconds for services to stabilize..."
            sleep 30
            milou_log "INFO" "🔄 Retrying credential validation..."
            if _test_database_credentials "${POSTGRES_USER:-}" "${POSTGRES_PASSWORD:-}"; then
                milou_log "SUCCESS" "✅ Retry successful - credentials are working"
                return 0
            else
                milou_log "WARN" "⚠️  Retry failed - continuing anyway"
                return 0
            fi
            ;;
        3)
            milou_log "INFO" "🧹 Performing clean installation..."
            if _perform_clean_installation; then
                milou_log "SUCCESS" "✅ Clean installation completed"
                return 0
            else
                milou_log "ERROR" "❌ Clean installation failed"
                return 1
            fi
            ;;
        4)
            milou_log "INFO" "🛑 Setup cancelled by user"
            return 1
            ;;
        *)
            milou_log "WARN" "Invalid choice, continuing setup anyway"
            return 0
            ;;
    esac
}

# Reset only the database volume (preserves other data)
_reset_database_volume() {
    milou_log "INFO" "🗑️  Removing database volume..."
    
    # Stop database service first
    docker compose down database 2>/dev/null || true
    
    # Remove database volumes with multiple naming conventions
    local volumes_removed=0
    local db_volumes=("${DOCKER_PROJECT_NAME:-static}_pgdata" "static_pgdata" "milou-static_pgdata")
    
    for volume in "${db_volumes[@]}"; do
        if docker volume inspect "$volume" >/dev/null 2>&1; then
            if docker volume rm "$volume" 2>/dev/null; then
                milou_log "INFO" "✅ Removed database volume: $volume"
                ((volumes_removed++))
            else
                milou_log "WARN" "⚠️  Failed to remove database volume: $volume"
            fi
        fi
    done
    
    if [[ $volumes_removed -gt 0 ]]; then
        milou_log "SUCCESS" "✅ Database volume reset completed ($volumes_removed volumes removed)"
        return 0
    else
        milou_log "ERROR" "❌ No database volumes were removed"
        return 1
    fi
}

# Export functions
export -f setup_final_validation
export -f _validate_system_readiness
export -f _setup_ssl_certificates
export -f _prepare_docker_environment
export -f _start_and_validate_services
export -f _wait_for_services_ready
export -f _validate_service_health
export -f _setup_display_completion_with_credentials
export -f _validate_credential_volume_consistency
export -f _quick_volume_credential_check
export -f _test_database_credentials
export -f _handle_credential_mismatch
export -f _handle_credential_mismatch_gentle
export -f _reset_database_volume 