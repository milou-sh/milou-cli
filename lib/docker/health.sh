#!/bin/bash

# =============================================================================
# Docker Health Check Functions for Milou CLI
# Comprehensive health monitoring and diagnostics
# =============================================================================

# Run comprehensive health checks
run_health_checks() {
    milou_log "STEP" "Running comprehensive health checks..."
    
    # Initialize if needed
    if ! milou_docker_init 2>/dev/null; then
    milou_log "ERROR" "Failed to initialize Docker environment"
        return 1
    fi
    
    local issues_found=0
    
    echo
    milou_log "INFO" "🏥 Health Check Report"
    echo
    
    # 1. Docker daemon check
    milou_log "INFO" "1️⃣  Docker Daemon Status"
    if docker info >/dev/null 2>&1; then
    milou_log "SUCCESS" "   ✅ Docker daemon is running"
    else
    milou_log "ERROR" "   ❌ Docker daemon is not accessible"
        ((issues_found++))
    fi
    
    # 2. Service status check
    milou_log "INFO" "2️⃣  Service Status"
    local total_services running_services
    total_services=$(milou_docker_compose config --services 2>/dev/null | wc -l || echo "0")
    running_services=$(milou_docker_compose ps --services --filter "status=running" 2>/dev/null | wc -l || echo "0")
    
    if [[ "$running_services" -eq "$total_services" && "$total_services" -gt 0 ]]; then
    milou_log "SUCCESS" "   ✅ All services running ($running_services/$total_services)"
    else
    milou_log "WARN" "   ⚠️  Some services not running ($running_services/$total_services)"
        ((issues_found++))
    fi
    
    # 3. Network connectivity
    milou_log "INFO" "3️⃣  Network Connectivity"
    local network_name="${DOCKER_PROJECT_NAME:-static}_default"
    if docker network inspect "$network_name" >/dev/null 2>&1; then
    milou_log "SUCCESS" "   ✅ Docker network exists: $network_name"
    else
    milou_log "ERROR" "   ❌ Docker network missing: $network_name"
        ((issues_found++))
    fi
    
    # 4. Volume health
    milou_log "INFO" "4️⃣  Volume Health"
    local volumes
    volumes=$(docker volume ls --filter "name=${DOCKER_PROJECT_NAME:-static}_" --format "{{.Name}}" 2>/dev/null || true)
    if [[ -n "$volumes" ]]; then
        local volume_count
        volume_count=$(echo "$volumes" | wc -l)
    milou_log "SUCCESS" "   ✅ Data volumes found: $volume_count volumes"
    else
    milou_log "WARN" "   ⚠️  No data volumes found"
    fi
    
    # 5. Configuration validation
    milou_log "INFO" "5️⃣  Configuration Validation"
    if [[ -f "${DOCKER_ENV_FILE:-${SCRIPT_DIR}/.env}" ]]; then
    milou_log "SUCCESS" "   ✅ Environment file exists"
    else
    milou_log "ERROR" "   ❌ Environment file missing"
        ((issues_found++))
    fi
    
    if [[ -f "${DOCKER_COMPOSE_FILE:-static/docker-compose.yml}" ]]; then
    milou_log "SUCCESS" "   ✅ Docker Compose file exists"
    else
    milou_log "ERROR" "   ❌ Docker Compose file missing"
        ((issues_found++))
    fi
    
    # 6. Port accessibility test
    milou_log "INFO" "6️⃣  Port Accessibility"
    if curl -k -s --max-time 5 https://localhost >/dev/null 2>&1; then
    milou_log "SUCCESS" "   ✅ HTTPS endpoint accessible"
    else
    milou_log "WARN" "   ⚠️  HTTPS endpoint not accessible"
        ((issues_found++))
    fi
    
    # Summary
    echo
    if [[ $issues_found -eq 0 ]]; then
    milou_log "SUCCESS" "🎉 Health check passed! No issues found."
    else
    milou_log "WARN" "⚠️  Health check completed with $issues_found issue(s) found."
    milou_log "INFO" "💡 Run './milou.sh diagnose' for detailed troubleshooting"
    fi
    
    echo
    return $issues_found
}

# Quick health check
quick_health_check() {
    milou_log "INFO" "⚡ Running quick health check..."
    
    if ! milou_docker_init 2>/dev/null; then
    milou_log "ERROR" "Docker environment not available"
        return 1
    fi
    
    local running_services
    running_services=$(milou_docker_compose ps --services --filter "status=running" 2>/dev/null | wc -l || echo "0")
    local total_services
    total_services=$(milou_docker_compose config --services 2>/dev/null | wc -l || echo "0")
    
    if [[ "$running_services" -eq "$total_services" && "$total_services" -gt 0 ]]; then
    milou_log "SUCCESS" "✅ Quick check passed: All $total_services services running"
        return 0
    else
    milou_log "WARN" "⚠️  Quick check: $running_services/$total_services services running"
        return 1
    fi
}

# Export functions
export -f run_health_checks quick_health_check 