#!/bin/bash

# =============================================================================
# Docker Services Command Handlers for Milou CLI
# Simplified and standardized command handlers
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Modules are loaded centrally by milou_load_command_modules() in main script

# Start services command handler
handle_start() {
    milou_log "INFO" "🚀 Starting Milou services..."
    
    if command -v milou_docker_start >/dev/null 2>&1; then
        milou_docker_start "$@"
    elif command -v start_services >/dev/null 2>&1; then
        start_services "$@"
    else
        milou_log "ERROR" "Start function not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize Docker modules"
        return 1
    fi
}

# Stop services command handler
handle_stop() {
    milou_log "INFO" "🛑 Stopping Milou services..."
    
    if command -v milou_docker_stop >/dev/null 2>&1; then
        milou_docker_stop "$@"
    elif command -v stop_services >/dev/null 2>&1; then
        stop_services "$@"
    else
        milou_log "ERROR" "Stop function not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize Docker modules"
        return 1
    fi
}

# Restart services command handler
handle_restart() {
    milou_log "INFO" "🔄 Restarting Milou services..."
    
    if command -v milou_docker_restart >/dev/null 2>&1; then
        milou_docker_restart "$@"
    elif command -v restart_services >/dev/null 2>&1; then
        restart_services "$@"
    else
        milou_log "ERROR" "Restart function not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize Docker modules"
        return 1
    fi
}

# Status command handler
handle_status() {
    if command -v milou_docker_status >/dev/null 2>&1; then
        milou_docker_status "$@"
    elif command -v show_service_status >/dev/null 2>&1; then
        show_service_status "$@"
    else
        milou_log "ERROR" "Status function not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize Docker modules"
        return 1
    fi
}

# Detailed status command handler
handle_detailed_status() {
    milou_log "INFO" "📋 Generating detailed system status..."
    
    if command -v show_detailed_status >/dev/null 2>&1; then
        show_detailed_status "$@"
    else
        milou_log "WARN" "Detailed status function not available, showing basic status"
        handle_status "$@"
    fi
}

# Logs command handler
handle_logs() {
    if command -v milou_docker_logs >/dev/null 2>&1; then
        # Check for special flags and handle them
        local args=("$@")
        local follow=false
        local service=""
        local tail_lines=""
        
        # Parse arguments
        while [[ $# -gt 0 ]]; do
            case $1 in
                --follow|-f)
                    follow=true
                    shift
                    ;;
                --tail)
                    tail_lines="$2"
                    shift 2
                    ;;
                --tail=*)
                    tail_lines="${1#*=}"
                    shift
                    ;;
                -*)
                    milou_log "WARN" "Unknown option: $1"
                    shift
                    ;;
                *)
                    service="$1"
                    shift
                    ;;
            esac
        done
        
        if [[ -n "$service" ]]; then
            milou_log "INFO" "📄 Showing logs for service: $service"
        else
            milou_log "INFO" "📄 Showing logs for all services"
        fi
        
        # Use Docker Compose directly for better argument handling
        if ! command -v milou_docker_compose >/dev/null 2>&1; then
            if ! command -v milou_docker_init >/dev/null 2>&1; then
                milou_log "ERROR" "Docker functions not available"
                return 1
            fi
            milou_docker_init
        fi
        
        # Build the command
        local cmd_args=()
        if [[ "$follow" == "true" ]]; then
            cmd_args+=("-f")
        fi
        
        if [[ -n "$tail_lines" ]]; then
            cmd_args+=("--tail=$tail_lines")
        elif [[ "$follow" != "true" ]]; then
            cmd_args+=("--tail=50")  # Default tail
        fi
        
        if [[ -n "$service" ]]; then
            cmd_args+=("$service")
        fi
        
        milou_docker_compose logs "${cmd_args[@]}"
    else
        milou_log "ERROR" "Docker logs function not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize Docker modules"
        return 1
    fi
}

# Health check command handler
handle_health() {
    milou_log "INFO" "🏥 Running comprehensive health checks..."
    
    if command -v run_health_checks >/dev/null 2>&1; then
        run_health_checks "$@"
    else
        milou_log "ERROR" "Health check function not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize health checking"
        return 1
    fi
}

# Quick health check command handler
handle_health_check() {
    milou_log "INFO" "⚡ Running quick health check..."
    
    if command -v quick_health_check >/dev/null 2>&1; then
        quick_health_check "$@"
    else
        milou_log "ERROR" "Quick health check function not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize health checking"
        return 1
    fi
}

# Shell access command handler
handle_shell() {
    local service="${1:-}"
    
    if [[ -z "$service" ]]; then
        milou_log "ERROR" "Service name is required for shell access"
        milou_log "INFO" "Usage: ./milou.sh shell <service_name>"
        return 1
    fi
    
    milou_log "INFO" "🐚 Accessing shell for service: $service"
    
    if command -v get_service_shell >/dev/null 2>&1; then
        get_service_shell "$service"
    else
        milou_log "ERROR" "Shell access function not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize Docker modules"
        return 1
    fi
}

# Debug images command handler
handle_debug_images() {
    milou_log "INFO" "🔍 Debugging Docker image availability..."
    
    if command -v debug_docker_images >/dev/null 2>&1; then
        debug_docker_images "$@"
    else
        milou_log "ERROR" "Debug images function not available"
        milou_log "INFO" "💡 Try running: ./milou.sh setup to initialize Docker debugging"
        return 1
    fi
}

# Export all functions
export -f handle_start handle_stop handle_restart handle_status
export -f handle_detailed_status handle_logs handle_health handle_health_check
export -f handle_shell handle_debug_images 