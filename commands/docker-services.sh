#!/bin/bash

# =============================================================================
# Docker Services Command Handlers for Milou CLI
# Extracted from milou.sh to improve maintainability
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Start services command handler
handle_start() {
    log "INFO" "🚀 Starting Milou services..."
    
    # Use consolidated Docker function if available
    if command -v milou_docker_start >/dev/null 2>&1; then
        milou_docker_start "$@"
    elif command -v start_services >/dev/null 2>&1; then
        start_services "$@"
    else
        log "ERROR" "No start function available"
        return 1
    fi
}

# Stop services command handler
handle_stop() {
    log "INFO" "🛑 Stopping Milou services..."
    
    # Use consolidated Docker function if available
    if command -v milou_docker_stop >/dev/null 2>&1; then
        milou_docker_stop "$@"
    elif command -v stop_services >/dev/null 2>&1; then
        stop_services "$@"
    else
        log "ERROR" "No stop function available"
        return 1
    fi
}

# Restart services command handler
handle_restart() {
    log "INFO" "🔄 Restarting Milou services..."
    
    # Use consolidated Docker function if available
    if command -v milou_docker_restart >/dev/null 2>&1; then
        milou_docker_restart "$@"
    elif command -v restart_services >/dev/null 2>&1; then
        restart_services "$@"
    else
        log "ERROR" "No restart function available"
        return 1
    fi
}

# Status command handler
handle_status() {
    log "INFO" "📊 Checking Milou services status..."
    
    # Use consolidated Docker function if available
    if command -v milou_docker_status >/dev/null 2>&1; then
        milou_docker_status "$@"
    elif command -v show_service_status >/dev/null 2>&1; then
        show_service_status "$@"
    else
        log "ERROR" "No status function available"
        return 1
    fi
}

# Detailed status command handler
handle_detailed_status() {
    log "INFO" "📋 Generating detailed system status..."
    
    if command -v show_detailed_status >/dev/null 2>&1; then
        show_detailed_status "$@"
    else
        log "WARN" "Detailed status function not available, showing basic status"
        handle_status "$@"
    fi
}

# Logs command handler
handle_logs() {
    local service="${1:-}"
    
    if [[ -n "$service" ]]; then
        log "INFO" "📄 Showing logs for service: $service"
    else
        log "INFO" "📄 Showing logs for all services"
    fi
    
    if command -v show_service_logs >/dev/null 2>&1; then
        show_service_logs "$@"
    else
        log "ERROR" "Logs function not available"
        return 1
    fi
}

# Health check command handler
handle_health() {
    log "INFO" "🏥 Running comprehensive health checks..."
    
    if command -v run_health_checks >/dev/null 2>&1; then
        run_health_checks "$@"
    else
        log "ERROR" "Health check function not available"
        return 1
    fi
}

# Quick health check command handler
handle_health_check() {
    log "INFO" "⚡ Running quick health check..."
    
    if command -v quick_health_check >/dev/null 2>&1; then
        quick_health_check "$@"
    else
        log "ERROR" "Quick health check function not available"
        return 1
    fi
}

# Shell access command handler
handle_shell() {
    local service="${1:-}"
    
    if [[ -z "$service" ]]; then
        log "ERROR" "Service name is required for shell access"
        log "INFO" "Usage: ./milou.sh shell <service_name>"
        return 1
    fi
    
    log "INFO" "🐚 Accessing shell for service: $service"
    
    if command -v get_service_shell >/dev/null 2>&1; then
        get_service_shell "$service"
    else
        log "ERROR" "Shell access function not available"
        return 1
    fi
}

# Export all functions
export -f handle_start handle_stop handle_restart handle_status
export -f handle_detailed_status handle_logs handle_health handle_health_check
export -f handle_shell 