#!/bin/bash

# =============================================================================
# Milou CLI - Shared Utilities for Scripts
# Consolidated logging and utility functions to eliminate code duplication
# Version: 1.0.0 - Initial Consolidation
# =============================================================================

# Ensure this script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script should be sourced, not executed directly" >&2
    exit 1
fi

# Module guard to prevent multiple loading
if [[ "${MILOU_SHARED_UTILS_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MILOU_SHARED_UTILS_LOADED="true"

# =============================================================================
# COLOR DEFINITIONS (SINGLE SOURCE OF TRUTH)
# =============================================================================

# Color codes - safe declarations to avoid readonly conflicts
if [[ -z "${RED:-}" ]]; then
    readonly RED='\033[0;31m'
fi
if [[ -z "${GREEN:-}" ]]; then
    readonly GREEN='\033[0;32m'
fi
if [[ -z "${YELLOW:-}" ]]; then
    readonly YELLOW='\033[1;33m'
fi
if [[ -z "${BLUE:-}" ]]; then
    readonly BLUE='\033[0;34m'
fi
if [[ -z "${CYAN:-}" ]]; then
    readonly CYAN='\033[0;36m'
fi
if [[ -z "${PURPLE:-}" ]]; then
    readonly PURPLE='\033[0;35m'
fi
if [[ -z "${BOLD:-}" ]]; then
    readonly BOLD='\033[1m'
fi
if [[ -z "${DIM:-}" ]]; then
    readonly DIM='\033[2m'
fi
if [[ -z "${NC:-}" ]]; then
    readonly NC='\033[0m' # No Color
fi

# =============================================================================
# UNIFIED LOGGING FUNCTIONS (SINGLE AUTHORITATIVE IMPLEMENTATION)
# =============================================================================

# Main logging function - replaces all scattered log() functions
log() {
    if [[ "${QUIET:-false}" != "true" ]]; then
        echo -e "${CYAN}[INFO]${NC} $*"
    fi
}

# Warning function - unified across all scripts
warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

# Error function - unified across all scripts  
error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Success function - unified across all scripts
success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

# Step function for progress indication
step() {
    echo -e "${BLUE}[STEP]${NC} $*"
}

# Debug function for development
debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${DIM}[DEBUG]${NC} $*" >&2
    fi
}

# =============================================================================
# UNIFIED USER INTERACTION FUNCTIONS
# =============================================================================

# Basic prompt function - covers most script needs
prompt_basic() {
    local prompt="$1"
    local default="${2:-}"
    local response
    
    if [[ "${INTERACTIVE:-true}" == "false" ]] || [[ "${QUIET:-false}" == "true" ]]; then
        echo "$default"
        return 0
    fi
    
    if [[ -n "$default" ]]; then
        read -p "$prompt [$default]: " response
        echo "${response:-$default}"
    else
        read -p "$prompt: " response
        echo "$response"
    fi
}

# Confirmation function
confirm_basic() {
    local prompt="$1"
    local default="${2:-N}"
    
    if [[ "${FORCE:-false}" == "true" ]]; then
        return 0
    fi
    
    if [[ "${INTERACTIVE:-true}" == "false" ]] || [[ "${QUIET:-false}" == "true" ]]; then
        [[ "$default" == "Y" || "$default" == "y" ]] && return 0 || return 1
    fi
    
    local prompt_text=""
    if [[ "$default" == "Y" || "$default" == "y" ]]; then
        prompt_text="$prompt [Y/n]: "
    else
        prompt_text="$prompt [y/N]: "
    fi
    
    while true; do
        read -p "$prompt_text" response
        case "$response" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            "") [[ "$default" == "Y" || "$default" == "y" ]] && return 0 || return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Safe directory creation
ensure_directory() {
    local dir_path="$1"
    local permissions="${2:-755}"
    
    if [[ ! -d "$dir_path" ]]; then
        if mkdir -p "$dir_path"; then
            debug "Created directory: $dir_path"
            chmod "$permissions" "$dir_path" 2>/dev/null || true
        else
            error "Failed to create directory: $dir_path"
            return 1
        fi
    fi
    return 0
}

# =============================================================================
# ERROR HANDLING
# =============================================================================

# Enhanced error handler for scripts
handle_script_error() {
    local error_msg="$1"
    local context="${2:-}"
    local suggestions=("${@:3}")
    
    error "$error_msg"
    
    if [[ -n "$context" ]]; then
        echo -e "${YELLOW}Context:${NC} $context"
    fi
    
    if [[ ${#suggestions[@]} -gt 0 ]]; then
        echo
        echo -e "${YELLOW}💡 Suggested solutions:${NC}"
        for i in "${!suggestions[@]}"; do
            echo "   $((i+1)). ${suggestions[$i]}"
        done
    fi
    
    if [[ "${INTERACTIVE:-true}" == "false" ]] || [[ "${QUIET:-false}" == "true" ]]; then
        echo -e "${RED}❌ Script failed. Please address the issue and try again.${NC}"
        exit 1
    fi
    
    echo
    echo -e "${CYAN}What would you like to do?${NC}"
    echo "1. Try again"
    echo "2. Exit script" 
    echo "3. Continue anyway (not recommended)"
    
    local choice
    choice=$(prompt_basic "Enter your choice (1-3)" "2")
    
    case "$choice" in
        1)
            echo -e "${BLUE}Retrying...${NC}"
            return 0  # Continue execution
            ;;
        3)
            warn "Continuing despite error - script may not work properly"
            return 0  # Continue execution
            ;;
        *)
            echo -e "${RED}Exiting script.${NC}"
            exit 1
            ;;
    esac
}

# =============================================================================
# LEGACY COMPATIBILITY ALIASES
# =============================================================================

# Provide aliases for existing function calls to maintain compatibility
milou_log() {
    case "${1:-INFO}" in
        "ERROR") error "${@:2}" ;;
        "WARN") warn "${@:2}" ;;
        "SUCCESS") success "${@:2}" ;;
        "STEP") step "${@:2}" ;;
        "DEBUG") debug "${@:2}" ;;
        *) log "${@:1}" ;;
    esac
}

# Legacy prompt alias
prompt_user() {
    prompt_basic "$@"
}

# =============================================================================
# EXPORT FUNCTIONS FOR SUBSHELLS
# =============================================================================

export -f log warn error success step debug
export -f prompt_basic confirm_basic
export -f command_exists ensure_directory
export -f handle_script_error
export -f milou_log prompt_user

debug "Shared utilities loaded successfully" 