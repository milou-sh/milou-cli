#!/bin/bash

# =============================================================================
# Security Validation and Hardening for Milou CLI
# Handles security checks, permission validation, and hardening measures
# =============================================================================

# Source utility functions
source "${BASH_SOURCE%/*}/utils.sh" 2>/dev/null || true
source "${BASH_SOURCE%/*}/user-core.sh" 2>/dev/null || true
source "${BASH_SOURCE%/*}/user-docker.sh" 2>/dev/null || true

# =============================================================================
# Permission Validation
# =============================================================================

# Validate current user has appropriate permissions
validate_user_permissions() {
    log "DEBUG" "Validating user permissions..."
    
    local current_user
    current_user=$(whoami)
    local issues=0
    
    # Check if running as root (not recommended)
    if is_running_as_root; then
        log "WARN" "Running as root user - not recommended for security"
        log "INFO" "💡 Consider creating and using the $MILOU_USER user instead"
        ((issues++))
    fi
    
    # Check Docker access
    if ! has_docker_permissions; then
        log "ERROR" "Current user ($current_user) does not have Docker permissions"
        log "INFO" "💡 Add user to docker group: sudo usermod -aG docker $current_user"
        log "INFO" "💡 Or switch to $MILOU_USER user: sudo -u $MILOU_USER"
        ((issues++))
    else
        log "SUCCESS" "Docker permissions verified for user: $current_user"
    fi
    
    # Check file permissions on critical paths
    local -a critical_paths=("$SCRIPT_DIR" "$ENV_FILE" "$CONFIG_DIR")
    for path in "${critical_paths[@]}"; do
        if [[ -e "$path" ]]; then
            if [[ ! -r "$path" ]]; then
                log "ERROR" "No read permission for: $path"
                ((issues++))
            fi
            if [[ -d "$path" && ! -w "$path" ]]; then
                log "ERROR" "No write permission for directory: $path"
                ((issues++))
            fi
        fi
    done
    
    return $issues
}

# =============================================================================
# Security Hardening
# =============================================================================

# Security hardening for milou user
harden_milou_user() {
    log "STEP" "Applying security hardening for $MILOU_USER user..."
    
    if ! is_running_as_root; then
        log "WARN" "Root privileges required for security hardening"
        return 1
    fi
    
    if ! milou_user_exists; then
        log "ERROR" "User $MILOU_USER does not exist"
        return 1
    fi
    
    local milou_home
    milou_home=$(get_milou_home)
    
    # Disable password login (use key-based auth only)
    if command -v passwd >/dev/null 2>&1; then
        passwd -l "$MILOU_USER" >/dev/null 2>&1 || log "WARN" "Could not lock password for $MILOU_USER"
    fi
    
    # Set restrictive permissions on home directory
    chmod 750 "$milou_home"
    
    # Secure configuration directory
    if [[ -d "$milou_home/.milou" ]]; then
        chmod -R 750 "$milou_home/.milou"
        # Make sensitive files even more restrictive
        find "$milou_home/.milou" -name "*.env" -o -name "*.key" -o -name "*.pem" | xargs chmod 600 2>/dev/null || true
    fi
    
    # Create sudoers entry for limited privileges if needed
    local sudoers_file="/etc/sudoers.d/milou"
    if [[ ! -f "$sudoers_file" ]]; then
        cat > "$sudoers_file" << EOF
# Milou user sudo privileges
# Allow milou user to manage Docker and systemd services
$MILOU_USER ALL=(root) NOPASSWD: /usr/bin/docker, /bin/systemctl start docker, /bin/systemctl stop docker, /bin/systemctl restart docker, /bin/systemctl status docker
EOF
        chmod 440 "$sudoers_file"
        log "INFO" "Created sudoers configuration for $MILOU_USER"
    fi
    
    log "SUCCESS" "Security hardening applied for $MILOU_USER user"
}

# =============================================================================
# Security Assessment
# =============================================================================

# Comprehensive security check
security_assessment() {
    log "STEP" "Performing comprehensive security assessment..."
    echo
    
    local security_score=100
    local critical_issues=0
    local warnings=0
    local recommendations=()
    
    # Check 1: User privileges
    log "INFO" "1. User Privilege Assessment:"
    local current_user
    current_user=$(whoami)
    
    if is_running_as_root; then
        log "WARN" "  ⚠️  Running as root user (not recommended)"
        security_score=$((security_score - 15))
        ((warnings++))
        recommendations+=("Create and use dedicated milou user: sudo $0 create-user")
    else
        log "SUCCESS" "  ✅ Running as non-root user: $current_user"
    fi
    
    if milou_user_exists; then
        log "SUCCESS" "  ✅ Dedicated milou user exists"
        
        # Check if milou user is properly configured
        local milou_home
        milou_home=$(get_milou_home)
        if [[ -d "$milou_home" ]]; then
            log "SUCCESS" "  ✅ Milou user home directory configured"
        else
            log "ERROR" "  ❌ Milou user home directory missing"
            security_score=$((security_score - 10))
            ((critical_issues++))
            recommendations+=("Fix milou user home: sudo mkdir -p $milou_home && sudo chown milou:milou $milou_home")
        fi
    else
        log "WARN" "  ⚠️  No dedicated milou user found"
        security_score=$((security_score - 10))
        ((warnings++))
        recommendations+=("Create milou user: sudo $0 create-user")
    fi
    echo
    
    # Check 2: Docker security
    log "INFO" "2. Docker Security Assessment:"
    if command -v docker >/dev/null 2>&1; then
        log "SUCCESS" "  ✅ Docker is installed"
        
        # Check Docker daemon access
        if has_docker_permissions; then
            log "SUCCESS" "  ✅ Docker access properly configured"
        else
            log "ERROR" "  ❌ Docker access not properly configured"
            security_score=$((security_score - 20))
            ((critical_issues++))
            recommendations+=("Fix Docker permissions: sudo usermod -aG docker $current_user")
        fi
        
        # Check Docker socket permissions
        if [[ -S /var/run/docker.sock ]]; then
            local socket_perms socket_group
            socket_perms=$(stat -c %a /var/run/docker.sock 2>/dev/null || echo "unknown")
            socket_group=$(stat -c %G /var/run/docker.sock 2>/dev/null || echo "unknown")
            
            if [[ "$socket_group" == "docker" ]]; then
                log "SUCCESS" "  ✅ Docker socket group ownership correct"
            else
                log "WARN" "  ⚠️  Docker socket group should be 'docker'"
                security_score=$((security_score - 5))
                ((warnings++))
                recommendations+=("Fix Docker socket group: sudo chgrp docker /var/run/docker.sock")
            fi
            
            if [[ "$socket_perms" == "666" ]]; then
                log "WARN" "  ⚠️  Docker socket too permissive (666)"
                security_score=$((security_score - 10))
                ((warnings++))
                recommendations+=("Secure Docker socket: sudo chmod 660 /var/run/docker.sock")
            else
                log "SUCCESS" "  ✅ Docker socket permissions acceptable"
            fi
        else
            log "ERROR" "  ❌ Docker socket not found"
            security_score=$((security_score - 15))
            ((critical_issues++))
        fi
    else
        log "ERROR" "  ❌ Docker not installed"
        security_score=$((security_score - 25))
        ((critical_issues++))
        recommendations+=("Install Docker: curl -fsSL https://get.docker.com | sh")
    fi
    echo
    
    # Check 3: File permissions
    log "INFO" "3. File Permission Assessment:"
    local file_issues=0
    
    # Check configuration files
    if [[ -f "$ENV_FILE" ]]; then
        local env_perms
        env_perms=$(stat -c %a "$ENV_FILE" 2>/dev/null || echo "unknown")
        if [[ "$env_perms" -le 600 ]]; then
            log "SUCCESS" "  ✅ Configuration file permissions secure ($env_perms)"
        else
            log "WARN" "  ⚠️  Configuration file too permissive ($env_perms)"
            security_score=$((security_score - 10))
            ((file_issues++))
            recommendations+=("Secure config file: chmod 600 $ENV_FILE")
        fi
    else
        log "INFO" "  ℹ️  No configuration file found"
    fi
    
    # Check SSL directory
    if [[ -d "./ssl" ]]; then
        local ssl_issues=0
        while IFS= read -r -d '' keyfile; do
            local key_perms
            key_perms=$(stat -c %a "$keyfile" 2>/dev/null || echo "unknown")
            if [[ "$key_perms" -gt 600 ]]; then
                log "WARN" "  ⚠️  SSL key file too permissive: $(basename "$keyfile") ($key_perms)"
                ((ssl_issues++))
            fi
        done < <(find "./ssl" -name "*.key" -print0 2>/dev/null)
        
        if [[ $ssl_issues -eq 0 ]]; then
            log "SUCCESS" "  ✅ SSL key file permissions secure"
        else
            security_score=$((security_score - 15))
            ((file_issues++))
            recommendations+=("Secure SSL keys: find ./ssl -name '*.key' -exec chmod 600 {} \\;")
        fi
    else
        log "INFO" "  ℹ️  No SSL directory found"
    fi
    
    if [[ $file_issues -eq 0 ]]; then
        log "SUCCESS" "  ✅ File permissions assessment passed"
    fi
    echo
    
    # Check 4: System security
    log "INFO" "4. System Security Assessment:"
    
    # Check for automatic updates
    if command -v unattended-upgrades >/dev/null 2>&1; then
        if systemctl is-enabled unattended-upgrades >/dev/null 2>&1; then
            log "SUCCESS" "  ✅ Automatic security updates enabled"
        else
            log "WARN" "  ⚠️  Automatic security updates not enabled"
            security_score=$((security_score - 5))
            ((warnings++))
            recommendations+=("Enable auto-updates: sudo systemctl enable unattended-upgrades")
        fi
    else
        log "INFO" "  ℹ️  Automatic updates package not installed"
    fi
    
    # Check firewall status
    if command -v ufw >/dev/null 2>&1; then
        if ufw status 2>/dev/null | grep -q "Status: active"; then
            log "SUCCESS" "  ✅ UFW firewall is active"
        else
            log "WARN" "  ⚠️  UFW firewall not active"
            security_score=$((security_score - 10))
            ((warnings++))
            recommendations+=("Enable firewall: sudo ufw enable")
        fi
    elif command -v firewall-cmd >/dev/null 2>&1; then
        if firewall-cmd --state 2>/dev/null | grep -q "running"; then
            log "SUCCESS" "  ✅ Firewalld is active"
        else
            log "WARN" "  ⚠️  Firewalld not active"
            security_score=$((security_score - 10))
            ((warnings++))
            recommendations+=("Enable firewall: sudo systemctl enable --now firewalld")
        fi
    else
        log "WARN" "  ⚠️  No firewall detected"
        security_score=$((security_score - 15))
        ((warnings++))
        recommendations+=("Install firewall: sudo apt install ufw && sudo ufw enable")
    fi
    echo
    
    # Security score and summary
    local score_color="$GREEN"
    local score_status="EXCELLENT"
    
    if [[ $security_score -lt 50 ]]; then
        score_color="$RED"
        score_status="POOR"
    elif [[ $security_score -lt 70 ]]; then
        score_color="$YELLOW"
        score_status="FAIR"
    elif [[ $security_score -lt 85 ]]; then
        score_color="$CYAN"
        score_status="GOOD"
    fi
    
    echo -e "${BOLD}Security Assessment Summary:${NC}"
    echo "================================"
    echo -e "Security Score: ${score_color}${BOLD}$security_score/100 ($score_status)${NC}"
    echo "Critical Issues: $critical_issues"
    echo "Warnings: $warnings"
    echo
    
    if [[ ${#recommendations[@]} -gt 0 ]]; then
        echo -e "${CYAN}Recommendations:${NC}"
        for i in "${!recommendations[@]}"; do
            echo "  $((i+1)). ${recommendations[i]}"
        done
        echo
    fi
    
    # Return status based on critical issues
    if [[ $critical_issues -eq 0 ]]; then
        log "SUCCESS" "Security assessment completed - no critical issues found"
        return 0
    else
        log "ERROR" "Security assessment found $critical_issues critical issues"
        return 1
    fi
}

# Quick security check for common issues
quick_security_check() {
    log "INFO" "Performing quick security check..."
    
    local issues=0
    
    # Check if running as root
    if is_running_as_root; then
        log "WARN" "⚠️  Running as root (security risk)"
        ((issues++))
    fi
    
    # Check Docker access
    if ! has_docker_permissions; then
        log "WARN" "⚠️  Docker permissions not configured"
        ((issues++))
    fi
    
    # Check config file permissions
    if [[ -f "$ENV_FILE" ]]; then
        local env_perms
        env_perms=$(stat -c %a "$ENV_FILE" 2>/dev/null || echo "777")
        if [[ "$env_perms" -gt 600 ]]; then
            log "WARN" "⚠️  Configuration file permissions too permissive"
            ((issues++))
        fi
    fi
    
    # Check SSL key permissions
    if [[ -d "./ssl" ]]; then
        local ssl_issues
        ssl_issues=$(find "./ssl" -name "*.key" -not -perm 600 2>/dev/null | wc -l)
        if [[ $ssl_issues -gt 0 ]]; then
            log "WARN" "⚠️  $ssl_issues SSL key files have insecure permissions"
            ((issues++))
        fi
    fi
    
    if [[ $issues -eq 0 ]]; then
        log "SUCCESS" "✅ Quick security check passed"
        return 0
    else
        log "WARN" "⚠️  Quick security check found $issues issues"
        log "INFO" "💡 Run 'milou security-check' for detailed assessment"
        return 1
    fi
}

# =============================================================================
# Security Utilities
# =============================================================================

# Clean up security-related resources
cleanup_security_resources() {
    log "DEBUG" "Cleaning up security resources..."
    
    # Clean up temporary security files
    local -a temp_patterns=(
        "/tmp/milou_security_*"
        "/tmp/milou_audit_*"
    )
    
    for pattern in "${temp_patterns[@]}"; do
        if compgen -G "$pattern" >/dev/null 2>&1; then
            rm -f $pattern 2>/dev/null || true
        fi
    done
}

# Generate security report
generate_security_report() {
    local report_file="${1:-/tmp/milou_security_report_$(date +%Y%m%d_%H%M%S).txt}"
    
    log "INFO" "Generating security report: $report_file"
    
    {
        echo "Milou CLI Security Report"
        echo "Generated: $(date)"
        echo "User: $(whoami)"
        echo "Host: $(hostname)"
        echo "=========================="
        echo
        
        # Run security assessment and capture output
        security_assessment 2>&1
        
        echo
        echo "System Information:"
        echo "OS: $(uname -a)"
        echo "Docker: $(docker --version 2>/dev/null || echo "Not installed")"
        echo "User Groups: $(groups 2>/dev/null || echo "Unknown")"
        
        echo
        echo "File Permissions:"
        [[ -f "$ENV_FILE" ]] && echo "Config: $(stat -c '%a %n' "$ENV_FILE" 2>/dev/null || echo "Not found")"
        [[ -d "./ssl" ]] && echo "SSL files:" && find "./ssl" -type f -exec stat -c '%a %n' {} \; 2>/dev/null
        
    } > "$report_file"
    
    log "SUCCESS" "Security report generated: $report_file"
    echo "📄 Report saved to: $report_file"
}

# Export functions for use in other scripts
export -f validate_user_permissions
export -f harden_milou_user
export -f security_assessment
export -f quick_security_check
export -f cleanup_security_resources
export -f generate_security_report 