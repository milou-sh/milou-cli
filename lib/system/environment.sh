#!/bin/bash

# =============================================================================
# Environment Manager - Centralized Environment Handling
# State-of-the-art environment management for Milou CLI
# =============================================================================

# Global environment state
declare -g ENV_FILE_PATH=""
declare -g ENV_FILE_VALIDATED=false
declare -g ENV_CREDENTIALS_HASH=""

# =============================================================================
# Environment File Discovery and Validation
# =============================================================================

# Discover the correct environment file with smart fallback
discover_environment_file() {
    local -a search_paths=(
        "${SCRIPT_DIR}/.env"
        "$(pwd)/.env"
        "${PWD}/.env"
    )
    
    # Add user-specific paths if running as specific user
    if [[ "$(whoami)" == "milou" ]]; then
        search_paths+=(
            "$HOME/milou-cli/.env"
            "/home/milou/milou-cli/.env"
        )
    fi
    
    # Add system paths
    search_paths+=(
        "/opt/milou-cli/.env"
        "/usr/local/milou-cli/.env"
    )
    
    local best_env_file=""
    local best_score=0
    
    for env_file in "${search_paths[@]}"; do
        if [[ -f "$env_file" && -r "$env_file" ]]; then
            local score=0
            
            # Score based on completeness and recency
            local var_count
            var_count=$(grep -c "^[A-Z_]\+=" "$env_file" 2>/dev/null || echo "0")
            score=$((score + var_count))
            
            # Prefer files with essential variables
            if grep -q "^DATABASE_URI=" "$env_file" 2>/dev/null; then
                score=$((score + 50))
            fi
            if grep -q "^REDIS_URL=" "$env_file" 2>/dev/null; then
                score=$((score + 30))
            fi
            if grep -q "^JWT_SECRET=" "$env_file" 2>/dev/null; then
                score=$((score + 30))
            fi
            
            # Prefer files in script directory
            if [[ "$env_file" == "${SCRIPT_DIR}/.env" ]]; then
                score=$((score + 100))
            fi
            
            log "DEBUG" "Environment file: $env_file, score: $score, vars: $var_count"
            
            if [[ $score -gt $best_score ]]; then
                best_score=$score
                best_env_file="$env_file"
            fi
        fi
    done
    
    if [[ -n "$best_env_file" ]]; then
        ENV_FILE_PATH="$best_env_file"
        log "SUCCESS" "Using environment file: $ENV_FILE_PATH (score: $best_score)"
        return 0
    else
        log "ERROR" "No valid environment file found"
        return 1
    fi
}

# Validate environment file completeness (using centralized validation)
validate_environment_file() {
    local env_file="${1:-$ENV_FILE_PATH}"
    
    # Load centralized validation if available
    if [[ -f "${BASH_SOURCE%/*}/config/validation.sh" ]]; then
        source "${BASH_SOURCE%/*}/config/validation.sh" 2>/dev/null || true
    fi
    
    # Use centralized validation if available
    if command -v validate_environment_essential >/dev/null 2>&1; then
        if validate_environment_essential "$env_file"; then
            ENV_FILE_VALIDATED=true
            return 0
        else
            return 1
        fi
    else
        # Fallback validation for essential variables only
        if [[ ! -f "$env_file" ]]; then
            log "ERROR" "Environment file not found: $env_file"
            return 1
        fi
        
        if [[ ! -r "$env_file" ]]; then
            log "ERROR" "Environment file not readable: $env_file"
            return 1
        fi
        
        if [[ ! -s "$env_file" ]]; then
            log "ERROR" "Environment file is empty: $env_file"
            return 1
        fi
        
        # Basic syntax check
        if ! env -i bash -n "$env_file" 2>/dev/null; then
            log "ERROR" "Environment file has syntax errors"
            return 1
        fi
        
        ENV_FILE_VALIDATED=true
        log "SUCCESS" "Environment file validated successfully (basic check)"
        return 0
    fi
}

# Generate credential hash for change detection
generate_credentials_hash() {
    local env_file="${1:-$ENV_FILE_PATH}"
    
    if [[ ! -f "$env_file" ]]; then
        echo ""
        return 1
    fi
    
    # Extract credential-related variables and hash them
    local cred_vars
    cred_vars=$(grep -E "^(POSTGRES_USER|POSTGRES_PASSWORD|REDIS_PASSWORD|RABBITMQ_USER|RABBITMQ_PASSWORD|DB_USER|DB_PASSWORD)=" "$env_file" 2>/dev/null | sort)
    
    if command -v sha256sum >/dev/null 2>&1; then
        echo "$cred_vars" | sha256sum | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        echo "$cred_vars" | shasum -a 256 | cut -d' ' -f1
    else
        # Fallback to a simple hash
        echo "$cred_vars" | wc -c
    fi
}

# =============================================================================
# Environment File Consolidation
# =============================================================================

# Consolidate multiple environment files into the canonical location
consolidate_environment_files() {
    log "STEP" "Consolidating environment files..."
    
    local canonical_path="${SCRIPT_DIR}/.env"
    local -a found_files=()
    
    # Find all environment files
    local -a search_paths=(
        "${SCRIPT_DIR}/.env"
        "/home/milou/milou-cli/.env"
        "/home/milou-cli/.env"
        "$(pwd)/.env"
    )
    
    for path in "${search_paths[@]}"; do
        if [[ -f "$path" && "$path" != "$canonical_path" ]]; then
            found_files+=("$path")
        fi
    done
    
    if [[ ${#found_files[@]} -eq 0 ]]; then
        log "INFO" "No additional environment files found to consolidate"
        return 0
    fi
    
    log "INFO" "Found ${#found_files[@]} environment files to consolidate"
    
    # Find the best source file
    local best_file=""
    local best_score=0
    
    for file in "${found_files[@]}"; do
        local score=0
        local var_count
        var_count=$(grep -c "^[A-Z_]\+=" "$file" 2>/dev/null || echo "0")
        score=$((score + var_count))
        
        # Check for essential variables
        if grep -q "^DATABASE_URI=" "$file" 2>/dev/null; then
            score=$((score + 50))
        fi
        if grep -q "^REDIS_URL=" "$file" 2>/dev/null; then
            score=$((score + 30))
        fi
        
        log "DEBUG" "Environment file: $file, score: $score"
        
        if [[ $score -gt $best_score ]]; then
            best_score=$score
            best_file="$file"
        fi
    done
    
    if [[ -n "$best_file" ]]; then
        log "INFO" "Using $best_file as source (score: $best_score)"
        
        # Backup existing canonical file if it exists
        if [[ -f "$canonical_path" ]]; then
            local backup_path="${canonical_path}.backup.$(date +%Y%m%d_%H%M%S)"
            cp "$canonical_path" "$backup_path"
            log "INFO" "Backed up existing file to: $backup_path"
        fi
        
        # Copy the best file to canonical location
        cp "$best_file" "$canonical_path"
        chmod 600 "$canonical_path"
        
        log "SUCCESS" "Environment file consolidated to: $canonical_path"
        
        # Clean up other files (with confirmation)
        for file in "${found_files[@]}"; do
            if [[ "$file" != "$best_file" ]]; then
                if [[ "${FORCE:-false}" == "true" ]] || confirm "Remove duplicate environment file: $file?" "N"; then
                    rm -f "$file"
                    log "INFO" "Removed duplicate: $file"
                fi
            fi
        done
    fi
    
    ENV_FILE_PATH="$canonical_path"
    return 0
}

# =============================================================================
# Environment Loading and Export
# =============================================================================

# Load environment file with validation
load_environment() {
    local env_file="${1:-}"
    
    if [[ -z "$env_file" ]]; then
        if ! discover_environment_file; then
            return 1
        fi
        env_file="$ENV_FILE_PATH"
    fi
    
    if ! validate_environment_file "$env_file"; then
        return 1
    fi
    
    # Source the environment file in a controlled way
    set -o allexport
    source "$env_file"
    set +o allexport
    
    # Store credential hash for change detection
    ENV_CREDENTIALS_HASH=$(generate_credentials_hash "$env_file")
    
    log "DEBUG" "Environment loaded from: $env_file"
    log "DEBUG" "Credentials hash: ${ENV_CREDENTIALS_HASH:0:8}..."
    
    return 0
}

# Export environment for Docker Compose
export_environment_for_docker() {
    local target_file="${1:-${SCRIPT_DIR}/.env}"
    
    if [[ "$ENV_FILE_PATH" != "$target_file" ]]; then
        log "DEBUG" "Copying environment to Docker location: $target_file"
        cp "$ENV_FILE_PATH" "$target_file"
        chmod 600 "$target_file"
    fi
    
    echo "$target_file"
}

# =============================================================================
# Credential Change Detection
# =============================================================================

# Check if credentials have changed since last deployment
check_credentials_changed() {
    local current_hash
    current_hash=$(generate_credentials_hash)
    
    if [[ -z "$current_hash" ]]; then
        log "WARN" "Could not generate credentials hash"
        return 1
    fi
    
    # Check if we have a stored hash from previous deployment
    local stored_hash_file="${CONFIG_DIR}/credentials.hash"
    
    if [[ -f "$stored_hash_file" ]]; then
        local stored_hash
        stored_hash=$(cat "$stored_hash_file" 2>/dev/null)
        
        if [[ "$current_hash" != "$stored_hash" ]]; then
            log "INFO" "Credential changes detected"
            log "DEBUG" "Stored hash: ${stored_hash:0:8}..., Current hash: ${current_hash:0:8}..."
            return 0  # Changed
        else
            log "DEBUG" "No credential changes detected"
            return 1  # Not changed
        fi
    else
        log "DEBUG" "No previous credential hash found"
        return 0  # Assume changed if no previous hash
    fi
}

# Store current credentials hash
store_credentials_hash() {
    local hash
    hash=$(generate_credentials_hash)
    
    if [[ -n "$hash" ]]; then
        local stored_hash_file="${CONFIG_DIR}/credentials.hash"
        mkdir -p "$(dirname "$stored_hash_file")"
        echo "$hash" > "$stored_hash_file"
        log "DEBUG" "Stored credentials hash: ${hash:0:8}..."
    fi
}

# =============================================================================
# Path Resolution
# =============================================================================

# Resolve SSL path to absolute path for Docker
resolve_ssl_path_for_docker() {
    local ssl_path="${1:-./ssl}"
    
    # If already absolute, return as-is
    if [[ "$ssl_path" =~ ^/ ]]; then
        echo "$ssl_path"
        return 0
    fi
    
    # Resolve relative path based on script directory
    local absolute_path="${SCRIPT_DIR}/${ssl_path}"
    
    # Normalize the path
    absolute_path=$(readlink -f "$absolute_path" 2>/dev/null || echo "$absolute_path")
    
    log "DEBUG" "Resolved SSL path: $ssl_path -> $absolute_path"
    echo "$absolute_path"
}

# =============================================================================
# Environment Initialization
# =============================================================================

# Initialize environment management
initialize_environment_manager() {
    log "DEBUG" "Initializing environment manager..."
    
    # Ensure config directory exists
    mkdir -p "${CONFIG_DIR}"
    
    # Consolidate environment files
    if ! consolidate_environment_files; then
        log "WARN" "Failed to consolidate environment files"
    fi
    
    # Load the environment
    if ! load_environment; then
        log "ERROR" "Failed to load environment"
        return 1
    fi
    
    log "SUCCESS" "Environment manager initialized successfully"
    return 0
}

# =============================================================================
# Utility Functions
# =============================================================================

# Get environment variable with fallback
get_env_var() {
    local var_name="$1"
    local default_value="${2:-}"
    
    if [[ -n "${!var_name:-}" ]]; then
        echo "${!var_name}"
    elif [[ -n "$ENV_FILE_PATH" ]] && grep -q "^${var_name}=" "$ENV_FILE_PATH" 2>/dev/null; then
        grep "^${var_name}=" "$ENV_FILE_PATH" | cut -d'=' -f2- | sed 's/^["'\'']\(.*\)["'\'']$/\1/'
    else
        echo "$default_value"
    fi
}

# Check if environment is properly configured
is_environment_configured() {
    if [[ "$ENV_FILE_VALIDATED" == "true" ]] && [[ -n "$ENV_FILE_PATH" ]]; then
        return 0
    else
        return 1
    fi
}

# Show environment status
show_environment_status() {
    echo
    log "INFO" "Environment Status:"
    echo "  📁 Environment file: ${ENV_FILE_PATH:-'Not found'}"
    echo "  ✅ Validated: ${ENV_FILE_VALIDATED}"
    echo "  🔑 Credentials hash: ${ENV_CREDENTIALS_HASH:0:8}..."
    
    if [[ -n "$ENV_FILE_PATH" && -f "$ENV_FILE_PATH" ]]; then
        local var_count
        var_count=$(grep -c "^[A-Z_]\+=" "$ENV_FILE_PATH" 2>/dev/null || echo "0")
        echo "  📊 Variables count: $var_count"
        
        local file_size
        file_size=$(wc -c < "$ENV_FILE_PATH" 2>/dev/null || echo "0")
        echo "  📏 File size: ${file_size} bytes"
        
        local modified
        modified=$(stat -c %Y "$ENV_FILE_PATH" 2>/dev/null || echo "0")
        if [[ "$modified" != "0" ]]; then
            echo "  📅 Last modified: $(date -d @"$modified" 2>/dev/null || echo 'Unknown')"
        fi
    fi
    echo
}

# =============================================================================
# Auto-initialization
# =============================================================================

# Auto-initialize if not in setup mode
if [[ "${BASH_SOURCE[0]}" != "${0}" ]] && [[ "${1:-}" != "setup" ]]; then
    initialize_environment_manager
fi 