#!/bin/bash

# =============================================================================
# Setup Module: Prerequisites Assessment
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
# Prerequisites Assessment Functions
# =============================================================================

# Assess system prerequisites (non-blocking)
setup_assess_prerequisites() {
    local -n needs_deps_ref="$1"
    
    milou_log "STEP" "Step 2: Prerequisites Assessment"
    echo
    
    # Quick assessment without blocking
    local missing_deps=()
    local warnings=()
    local prereq_status="good"
    
    # Reset needs_deps based on assessment
    needs_deps_ref=false
    
    _check_critical_dependencies missing_deps warnings needs_deps_ref
    _check_system_tools missing_deps
    _report_prerequisites_status missing_deps warnings prereq_status
    
    echo
    return 0
}

# Check critical dependencies (Docker, Docker Compose)
_check_critical_dependencies() {
    local -n missing_ref="$1"
    local -n warnings_ref="$2"
    local -n deps_ref="$3"
    
    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
        missing_ref+=("Docker")
        deps_ref=true
    elif ! docker info >/dev/null 2>&1; then
        warnings_ref+=("Docker daemon not accessible")
    fi
    
    # Check Docker Compose
    if ! docker compose version >/dev/null 2>&1; then
        missing_ref+=("Docker Compose")
        deps_ref=true
    fi
}

# Check system tools (optional)
_check_system_tools() {
    local -n missing_ref="$1"
    
    # Essential tools (will be reported as missing)
    local -a essential_tools=("openssl")
    # Optional tools (will be reported as recommendations)
    local -a optional_tools=("curl" "wget" "jq")
    
    # Check essential tools
    for tool in "${essential_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_ref+=("$tool")
        fi
    done
    
    # Check optional tools (report separately)
    local missing_optional=()
    for tool in "${optional_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_optional+=("$tool")
        fi
    done
    
    # Report optional tools separately
    if [[ ${#missing_optional[@]} -gt 0 ]]; then
        milou_log "INFO" "💡 Optional tools not installed (can install later): ${missing_optional[*]}"
        milou_log "DEBUG" "Optional tools improve functionality but are not required"
    fi
}

# Report prerequisites status
_report_prerequisites_status() {
    local -n missing_ref="$1"
    local -n warnings_ref="$2"
    local -n status_ref="$3"
    
    if [[ ${#missing_ref[@]} -gt 0 ]]; then
        status_ref="missing"
        milou_log "WARN" "⚠️  Missing dependencies: ${missing_ref[*]}"
    elif [[ ${#warnings_ref[@]} -gt 0 ]]; then
        status_ref="warnings"
        milou_log "WARN" "⚠️  Warnings: ${warnings_ref[*]}"
    else
        status_ref="good"
        milou_log "SUCCESS" "✅ All prerequisites satisfied"
    fi
}

# Export functions
export -f setup_assess_prerequisites
export -f _check_critical_dependencies
export -f _check_system_tools
export -f _report_prerequisites_status
