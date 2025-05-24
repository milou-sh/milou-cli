#!/bin/bash

# =============================================================================
# Setup Command Handler for Milou CLI
# Extracted from milou.sh to improve maintainability
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Setup command handler
handle_setup() {
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
            log "INFO" "🤖 Auto-installing dependencies..."
        elif [[ "$setup_mode" == "interactive" ]]; then
            if confirm "Install missing dependencies automatically?" "Y"; then
                install_deps=true
            fi
        fi
        
        # Install dependencies if approved
        if [[ "$install_deps" == "true" ]]; then
            log "INFO" "📦 Installing system dependencies..."
            if command -v install_system_dependencies >/dev/null 2>&1; then
                install_system_dependencies
            else
                log "ERROR" "Dependency installation function not available"
                if [[ "$setup_mode" == "interactive" ]]; then
                    log "INFO" "Please install dependencies manually and run setup again"
                    return 1
                fi
            fi
        else
            log "WARN" "⚠️  Dependencies not installed. Setup may fail."
            if [[ "$setup_mode" == "interactive" ]]; then
                if ! confirm "Continue anyway?" "N"; then
                    log "INFO" "Setup cancelled by user"
                    return 0
                fi
            fi
        fi
    fi
    
    echo
    
    # Step 5: User Management (if needed)
    if [[ $EUID -eq 0 ]] && [[ "${milou_user_missing:-true}" == "true" ]]; then
        log "STEP" "Step 5: User Management"
        echo
        
        local create_user=false
        
        # Determine if we should create the user
        if [[ "${AUTO_CREATE_USER:-false}" == "true" ]]; then
            create_user=true
            log "INFO" "🤖 Auto-creating milou user..."
        elif [[ "$setup_mode" == "interactive" ]]; then
            log "INFO" "Running as root without dedicated milou user"
            if confirm "Create dedicated milou user for better security?" "Y"; then
                create_user=true
            fi
        fi
        
        # Create user if approved
        if [[ "$create_user" == "true" ]]; then
            if command -v create_milou_user >/dev/null 2>&1; then
                create_milou_user
                log "SUCCESS" "✅ Milou user created successfully"
                
                # Switch to milou user and continue setup
                log "INFO" "🔄 Switching to milou user to continue setup..."
                switch_to_milou_user_and_continue
                return $?
            else
                log "ERROR" "User creation function not available"
                return 1
            fi
        else
            log "WARN" "⚠️  Continuing as root user (not recommended for production)"
        fi
    fi
    
    echo
    
    # Step 6: Configuration Wizard
    log "STEP" "Step 6: Configuration Setup"
    echo
    
    # Use the appropriate wizard based on mode
    if [[ "$setup_mode" == "interactive" ]]; then
        log "INFO" "🎯 Starting interactive configuration wizard..."
        if command -v run_setup_wizard >/dev/null 2>&1; then
            run_setup_wizard
        else
            log "ERROR" "Setup wizard not available"
            return 1
        fi
    else
        log "INFO" "🤖 Running non-interactive configuration..."
        if command -v run_non_interactive_setup >/dev/null 2>&1; then
            run_non_interactive_setup
        else
            log "ERROR" "Non-interactive setup not available"
            return 1
        fi
    fi
    
    echo
    
    # Step 7: Final Setup and Validation
    log "STEP" "Step 7: Final Setup and Validation"
    echo
    
    # Validate the configuration
    log "INFO" "🔍 Validating configuration..."
    if command -v validate_milou_configuration >/dev/null 2>&1; then
        if validate_milou_configuration; then
            log "SUCCESS" "✅ Configuration validation passed"
        else
            log "ERROR" "❌ Configuration validation failed"
            log "INFO" "Please check your configuration and try again"
            return 1
        fi
    else
        log "WARN" "Configuration validation not available"
    fi
    
    # Offer to start services
    echo
    log "SUCCESS" "🎉 Setup completed successfully!"
    echo
    
    if [[ "$setup_mode" == "interactive" ]]; then
        if confirm "Start Milou services now?" "Y"; then
            log "INFO" "🚀 Starting services..."
            if command -v handle_start >/dev/null 2>&1; then
                handle_start
            else
                log "ERROR" "Start command not available"
            fi
        else
            log "INFO" "Setup complete. Use './milou.sh start' to start services when ready."
        fi
    else
        log "INFO" "Setup complete. Use './milou.sh start' to start services."
    fi
    
    echo
    log "SUCCESS" "✅ Milou CLI setup completed successfully!"
}

# Export the function for use in the main script
export -f handle_setup 