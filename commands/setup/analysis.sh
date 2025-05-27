#!/bin/bash

# =============================================================================
# Setup Module: System Analysis and Detection
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
# System Analysis Functions
# =============================================================================

# Analyze system state and detect setup requirements
setup_analyze_system() {
    local -n is_fresh_ref="$1"
    local -n needs_deps_ref="$2"
    local -n needs_user_ref="$3"
    
    milou_log "STEP" "Step 1: System Analysis and Detection"
    echo
    
    # Detect system characteristics for smart setup
    is_fresh_ref=false
    needs_deps_ref=false
    needs_user_ref=false
    
    # Analyze system state
    milou_log "INFO" "🔍 Analyzing system state..."
    
    # Fresh server detection with multiple indicators
    local fresh_indicators=0
    local fresh_reasons=()
    
    _detect_fresh_server_indicators fresh_indicators fresh_reasons
    _determine_setup_requirements "$fresh_indicators" is_fresh_ref needs_deps_ref needs_user_ref fresh_reasons
    
    echo
    return 0
}

# Detect fresh server indicators
_detect_fresh_server_indicators() {
    local -n indicators_ref="$1"
    local -n reasons_ref="$2"
    
    milou_log "DEBUG" "Starting fresh server detection..."
    
    # Temporarily disable strict error handling for system checks
    set +euo pipefail
    
    # Check 1: Root user
    if [[ $EUID -eq 0 ]]; then
        ((indicators_ref++))
        reasons_ref+=("Running as root user")
        milou_log "DEBUG" "Fresh indicator: Running as root"
    fi
    
    # Check 2: Milou user existence
    milou_log "DEBUG" "Checking milou user existence..."
    local milou_user_missing=true
    if command -v milou_user_exists >/dev/null 2>&1; then
        if milou_user_exists 2>/dev/null; then
            milou_user_missing=false
        fi
    fi
    
    if [[ "$milou_user_missing" == "true" ]]; then
        ((indicators_ref++))
        reasons_ref+=("No dedicated milou user")
        milou_log "DEBUG" "Fresh indicator: No milou user"
    fi
    
    # Check 3: Configuration file
    milou_log "DEBUG" "Checking configuration file..."
    if [[ ! -f "${ENV_FILE:-}" ]]; then
        ((indicators_ref++))
        reasons_ref+=("No existing configuration")
        milou_log "DEBUG" "Fresh indicator: No config file"
    else
        milou_log "DEBUG" "Found configuration file: $ENV_FILE"
    fi
    
    # Check 4: Docker installation
    milou_log "DEBUG" "Checking Docker installation..."
    if ! command -v docker >/dev/null 2>&1; then
        ((indicators_ref++))
        reasons_ref+=("Docker not installed")
        milou_log "DEBUG" "Fresh indicator: Docker not installed"
    fi
    
    # Check 5: Existing containers (only if Docker is available)
    milou_log "DEBUG" "Checking existing containers..."
    local has_containers=false
    if command -v docker >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then
            local container_output
            container_output=$(docker ps -a --filter "name=static-" --quiet 2>/dev/null || echo "")
            if [[ -n "$container_output" ]]; then
                has_containers=true
                milou_log "DEBUG" "Found existing containers"
            fi
        else
            milou_log "DEBUG" "Docker daemon not accessible"
        fi
    fi
    
    if [[ "$has_containers" == "false" ]]; then
        ((indicators_ref++))
        reasons_ref+=("No existing Milou containers")
        milou_log "DEBUG" "Fresh indicator: No containers"
    fi
    
    # Re-enable strict error handling
    set -euo pipefail
    
    milou_log "DEBUG" "Fresh indicators found: $indicators_ref"
}

# Determine setup requirements based on analysis
_determine_setup_requirements() {
    local indicators="$1"
    local -n fresh_ref="$2"
    local -n deps_ref="$3"
    local -n user_ref="$4"
    local -n reasons_ref="$5"
    
    # Determine if this is a fresh server (3+ indicators)
    if [[ $indicators -ge 3 ]] || [[ "${FRESH_INSTALL:-false}" == "true" ]]; then
        fresh_ref=true
        milou_log "INFO" "🆕 Fresh server installation detected"
        for reason in "${reasons_ref[@]}"; do
            milou_log "INFO" "   • $reason"
        done
        
        # Set requirements for fresh server
        if ! command -v docker >/dev/null 2>&1; then
            deps_ref=true
        fi
        
        if [[ $EUID -eq 0 ]] && ! command -v milou_user_exists >/dev/null 2>&1; then
            user_ref=true
        fi
    else
        fresh_ref=false
        milou_log "INFO" "🔄 Existing system setup detected"
    fi
}

# Export functions
export -f setup_analyze_system
export -f _detect_fresh_server_indicators
export -f _determine_setup_requirements
