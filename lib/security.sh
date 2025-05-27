#!/bin/bash

# =============================================================================
# Security Hardening and Validation for Milou CLI
# Comprehensive security measures and compliance checks
# =============================================================================

# Ensure logging is available
if ! command -v milou_log >/dev/null 2>&1; then
    local script_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    if [[ -f "${script_dir}/lib/core/logging.sh" ]]; then
        source "${script_dir}/lib/core/logging.sh"
    else
        echo "ERROR: Logging module not available" >&2
        return 1
    fi
fi

# Security Constants
readonly SECURITY_LOG_FILE="${CONFIG_DIR}/security.log"
readonly ALLOWED_PORTS=(80 443 5432 6379 15672 9999)
readonly SENSITIVE_FILES=("*.key" "*.pem" "*.p12" "*.pfx" "*.env" "*token*" "*secret*")
readonly DOCKER_SECURITY_OPTS=(
    "--security-opt=no-new-privileges:true"
    "--security-opt=apparmor:unconfined"
    "--read-only"
    "--tmpfs=/tmp"
)

# =============================================================================
# Security Validation Functions
# =============================================================================

# Comprehensive security assessment
run_security_assessment() {
    milou_log "STEP" "Running comprehensive security assessment..."
    
    local score=100
    local issues=0
    local warnings=0
    local recommendations=()
    
    echo "🔐 MILOU SECURITY ASSESSMENT REPORT"
    echo "===================================="
    echo "Date: $(date)"
    echo "User: $(whoami)"
    echo "System: $(uname -a)"
    echo
    
    # User Security Assessment
    echo "👤 USER SECURITY:"
    if is_running_as_root; then
        echo "  ❌ Running as root (-20 points)"
        ((score -= 20))
        ((issues++))
        recommendations+=("Create dedicated milou user for better security")
    else
        echo "  ✅ Running as non-root user (+10 points)"
        ((score += 10))
    fi
    
    if has_docker_permissions; then
        echo "  ✅ Docker permissions configured"
    else
        echo "  ⚠️  No Docker permissions (-10 points)"
        ((score -= 10))
        ((warnings++))
    fi
    
    # File Permissions Assessment
    echo
    echo "📁 FILE PERMISSIONS:"
    local file_issues=0
    
    # Check configuration files
    if [[ -f "$ENV_FILE" ]]; then
        local env_perms
        env_perms=$(stat -c %a "$ENV_FILE" 2>/dev/null || stat -f %A "$ENV_FILE" 2>/dev/null)
        if [[ "$env_perms" -gt 600 ]]; then
            echo "  ⚠️  Configuration file too permissive: $env_perms (-5 points)"
            ((score -= 5))
            ((warnings++))
            ((file_issues++))
            recommendations+=("Fix permissions: chmod 600 $ENV_FILE")
        else
            echo "  ✅ Configuration file properly secured"
        fi
    fi
    
    # Check SSL certificates
    if [[ -d "./ssl" ]]; then
        local ssl_perms
        ssl_perms=$(stat -c %a "./ssl" 2>/dev/null || stat -f %A "./ssl" 2>/dev/null)
        if [[ "$ssl_perms" -gt 750 ]]; then
            echo "  ⚠️  SSL directory too permissive: $ssl_perms (-5 points)"
            ((score -= 5))
            ((warnings++))
            ((file_issues++))
            recommendations+=("Fix permissions: chmod 750 ./ssl")
        else
            echo "  ✅ SSL directory properly secured"
        fi
    fi
    
    # Network Security Assessment
    echo
    echo "🌐 NETWORK SECURITY:"
    local network_issues=0
    
    # Check for exposed services
    for port in 22 80 443 5432 6379 15672; do
        if check_port_listening "$port"; then
            case $port in
                22)
                    echo "  ⚠️  SSH exposed on port 22"
                    ((warnings++))
                    recommendations+=("Consider changing SSH port or using VPN")
                    ;;
                80|443)
                    echo "  ✅ Web services on standard ports"
                    ;;
                5432)
                    echo "  ⚠️  PostgreSQL exposed (-10 points)"
                    ((score -= 10))
                    ((warnings++))
                    recommendations+=("Restrict PostgreSQL access to localhost only")
                    ;;
                6379)
                    echo "  ❌ Redis exposed (-15 points)"
                    ((score -= 15))
                    ((issues++))
                    recommendations+=("CRITICAL: Secure Redis - never expose to internet")
                    ;;
                15672)
                    echo "  ⚠️  RabbitMQ management exposed (-5 points)"
                    ((score -= 5))
                    ((warnings++))
                    recommendations+=("Restrict RabbitMQ management interface")
                    ;;
            esac
        fi
    done
    
    # Docker Security Assessment
    echo
    echo "🐳 DOCKER SECURITY:"
    if command -v docker >/dev/null 2>&1; then
        # Check Docker daemon configuration
        if docker info --format '{{.SecurityOptions}}' 2>/dev/null | grep -q apparmor; then
            echo "  ✅ AppArmor enabled"
        else
            echo "  ⚠️  AppArmor not enabled (-5 points)"
            ((score -= 5))
            ((warnings++))
        fi
        
        # Check for privileged containers
        local privileged_containers
        privileged_containers=$(docker ps --filter "label=privileged=true" --format "{{.Names}}" 2>/dev/null || true)
        if [[ -n "$privileged_containers" ]]; then
            echo "  ❌ Privileged containers detected (-20 points)"
            ((score -= 20))
            ((issues++))
            recommendations+=("Remove privileged containers: $privileged_containers")
        else
            echo "  ✅ No privileged containers"
        fi
        
        # Check Docker socket permissions
        if [[ -S /var/run/docker.sock ]]; then
            local socket_perms
            socket_perms=$(stat -c %a /var/run/docker.sock 2>/dev/null || echo "unknown")
            if [[ "$socket_perms" == "666" ]]; then
                echo "  ⚠️  Docker socket too permissive (-10 points)"
                ((score -= 10))
                ((warnings++))
                recommendations+=("Secure Docker socket permissions")
            else
                echo "  ✅ Docker socket properly secured"
            fi
        fi
    else
        echo "  ❌ Docker not available"
    fi
    
    # SSL/TLS Assessment
    echo
    echo "🔒 SSL/TLS SECURITY:"
    if [[ -f "./ssl/milou.crt" && -f "./ssl/milou.key" ]]; then
        # Check certificate expiration
        local cert_expiry
        cert_expiry=$(openssl x509 -in "./ssl/milou.crt" -noout -enddate 2>/dev/null | cut -d= -f2)
        if [[ -n "$cert_expiry" ]]; then
            local expiry_epoch
            expiry_epoch=$(date -d "$cert_expiry" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$cert_expiry" +%s 2>/dev/null)
            local current_epoch
            current_epoch=$(date +%s)
            local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
            
            if [[ $days_until_expiry -lt 30 ]]; then
                echo "  ❌ SSL certificate expires soon: $days_until_expiry days (-15 points)"
                ((score -= 15))
                ((issues++))
                recommendations+=("Renew SSL certificate before expiration")
            elif [[ $days_until_expiry -lt 90 ]]; then
                echo "  ⚠️  SSL certificate expires in $days_until_expiry days (-5 points)"
                ((score -= 5))
                ((warnings++))
                recommendations+=("Plan SSL certificate renewal")
            else
                echo "  ✅ SSL certificate valid for $days_until_expiry days"
            fi
        fi
        
        # Check certificate strength
        local key_size
        key_size=$(openssl rsa -in "./ssl/milou.key" -text -noout 2>/dev/null | grep "Private-Key:" | grep -oE '[0-9]+')
        if [[ -n "$key_size" && $key_size -lt 2048 ]]; then
            echo "  ⚠️  Weak SSL key size: ${key_size} bits (-10 points)"
            ((score -= 10))
            ((warnings++))
            recommendations+=("Use at least 2048-bit SSL keys")
        else
            echo "  ✅ SSL key strength adequate"
        fi
    else
        echo "  ⚠️  No SSL certificates found (-5 points)"
        ((score -= 5))
        ((warnings++))
        recommendations+=("Configure SSL certificates for secure communication")
    fi
    
    # System Security Assessment
    echo
    echo "🛡️  SYSTEM SECURITY:"
    
    # Check for security updates
    if command -v apt-get >/dev/null 2>&1; then
        local security_updates
        security_updates=$(apt list --upgradable 2>/dev/null | grep -c security || echo "0")
        if [[ $security_updates -gt 0 ]]; then
            echo "  ⚠️  $security_updates security updates available (-5 points)"
            ((score -= 5))
            ((warnings++))
            recommendations+=("Install security updates: sudo apt-get upgrade")
        else
            echo "  ✅ System up to date"
        fi
    fi
    
    # Check firewall status
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "Status: active"; then
            echo "  ✅ Firewall enabled"
        else
            echo "  ⚠️  Firewall disabled (-10 points)"
            ((score -= 10))
            ((warnings++))
            recommendations+=("Enable firewall: sudo ufw enable")
        fi
    elif command -v firewall-cmd >/dev/null 2>&1; then
        if firewall-cmd --state 2>/dev/null | grep -q running; then
            echo "  ✅ Firewall enabled"
        else
            echo "  ⚠️  Firewall disabled (-10 points)"
            ((score -= 10))
            ((warnings++))
            recommendations+=("Enable firewall: sudo systemctl start firewalld")
        fi
    else
        echo "  ⚠️  No firewall detected (-5 points)"
        ((score -= 5))
        ((warnings++))
        recommendations+=("Install and configure a firewall")
    fi
    
    # Final Assessment
    echo
    echo "📊 SECURITY SCORE: $score/100"
    if [[ $score -ge 90 ]]; then
        echo "🎉 EXCELLENT - Your Milou installation is very secure!"
    elif [[ $score -ge 80 ]]; then
        echo "👍 GOOD - Your installation is reasonably secure with minor improvements needed"
    elif [[ $score -ge 70 ]]; then
        echo "⚠️  FAIR - Several security improvements recommended"
    elif [[ $score -ge 60 ]]; then
        echo "🔶 POOR - Significant security issues need attention"
    else
        echo "🚨 CRITICAL - Immediate security action required!"
    fi
    
    echo
    echo "Summary:"
    echo "  🔴 Critical Issues: $issues"
    echo "  🟡 Warnings: $warnings"
    
    if [[ ${#recommendations[@]} -gt 0 ]]; then
        echo
        echo "🔧 RECOMMENDATIONS:"
        local i=1
        for rec in "${recommendations[@]}"; do
            echo "  $i. $rec"
            ((i++))
        done
    fi
    
    # Log assessment
    {
        echo "$(date): Security Assessment - Score: $score/100, Issues: $issues, Warnings: $warnings"
        [[ ${#recommendations[@]} -gt 0 ]] && printf "Recommendations: %s\n" "${recommendations[*]}"
    } >> "$SECURITY_LOG_FILE"
    
    return $((issues > 0 ? 1 : 0))
}

# =============================================================================
# Security Hardening Functions
# =============================================================================

# Apply comprehensive security hardening
harden_system() {
    milou_log "STEP" "Applying system security hardening..."
    
    if ! is_running_as_root; then
    milou_log "WARN" "Root privileges required for system hardening"
        return 1
    fi
    
    local applied=0
    
    # Secure file permissions
    milou_log "INFO" "Hardening file permissions..."
    if [[ -f "$ENV_FILE" ]]; then
        chmod 600 "$ENV_FILE"
        ((applied++))
    fi
    
    if [[ -d "./ssl" ]]; then
        chmod -R 750 "./ssl"
        find "./ssl" -name "*.key" -exec chmod 600 {} \;
        ((applied++))
    fi
    
    # Secure Docker daemon configuration
    if [[ -f /etc/docker/daemon.json ]]; then
    milou_log "INFO" "Hardening Docker daemon configuration..."
        local docker_config="/etc/docker/daemon.json"
        local backup_config="${docker_config}.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Backup existing config
        cp "$docker_config" "$backup_config"
        
        # Create hardened Docker configuration
        cat > "$docker_config" << 'EOF'
{
  "icc": false,
  "userns-remap": "default",
  "no-new-privileges": true,
  "seccomp-profile": "/etc/docker/seccomp/default.json",
  "apparmor-profile": "docker-default",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "live-restore": true,
  "userland-proxy": false,
  "experimental": false
}
EOF
    milou_log "INFO" "Docker daemon configuration hardened (backup: $backup_config)"
        ((applied++))
    fi
    
    # Configure firewall rules
    if command -v ufw >/dev/null 2>&1; then
    milou_log "INFO" "Configuring firewall rules..."
        
        # Reset and configure UFW
        ufw --force reset >/dev/null 2>&1
        ufw default deny incoming >/dev/null 2>&1
        ufw default allow outgoing >/dev/null 2>&1
        
        # Allow necessary ports
        ufw allow 22/tcp comment "SSH" >/dev/null 2>&1
        ufw allow 80/tcp comment "HTTP" >/dev/null 2>&1
        ufw allow 443/tcp comment "HTTPS" >/dev/null 2>&1
        
        # Block dangerous ports
        ufw deny 5432/tcp comment "PostgreSQL" >/dev/null 2>&1
        ufw deny 6379/tcp comment "Redis" >/dev/null 2>&1
        ufw deny 15672/tcp comment "RabbitMQ" >/dev/null 2>&1
        
        ufw --force enable >/dev/null 2>&1
    milou_log "INFO" "Firewall rules configured"
        ((applied++))
    fi
    
    # Set up fail2ban if available
    if command -v fail2ban-server >/dev/null 2>&1; then
    milou_log "INFO" "Configuring fail2ban..."
        
        # Create Milou-specific jail
        cat > /etc/fail2ban/jail.d/milou.conf << 'EOF'
[milou-auth]
enabled = true
port = http,https
filter = milou-auth
logpath = /var/log/milou/*.log
maxretry = 5
bantime = 3600
findtime = 600

[milou-docker]
enabled = true
port = 2376
filter = milou-docker
logpath = /var/log/docker.log
maxretry = 3
bantime = 7200
findtime = 300
EOF
        
        systemctl restart fail2ban >/dev/null 2>&1
    milou_log "INFO" "Fail2ban configured for Milou"
        ((applied++))
    fi
    
    milou_log "SUCCESS" "Applied $applied security hardening measures"
    return 0
}

# =============================================================================
# Security Monitoring Functions
# =============================================================================

# Monitor for security events
monitor_security_events() {
    milou_log "INFO" "Monitoring security events..."
    
    local events=0
    
    # Check for failed login attempts
    if [[ -f /var/log/auth.log ]]; then
        local failed_logins
        failed_logins=$(grep "authentication failure" /var/log/auth.log | wc -l)
        if [[ $failed_logins -gt 10 ]]; then
    milou_log "WARN" "High number of failed login attempts detected: $failed_logins"
            ((events++))
        fi
    fi
    
    # Check for Docker security events
    if command -v docker >/dev/null 2>&1; then
        # Check for privilege escalation attempts
        local priv_attempts
        priv_attempts=$(docker events --since="1h" --filter="event=start" 2>/dev/null | grep -c "privileged" || echo "0")
        if [[ $priv_attempts -gt 0 ]]; then
    milou_log "WARN" "Privileged container starts detected: $priv_attempts"
            ((events++))
        fi
    fi
    
    # Check for unusual network activity
    if command -v netstat >/dev/null 2>&1; then
        local suspicious_connections
        suspicious_connections=$(netstat -tuln | grep -E ":5432|:6379|:15672" | grep -v "127.0.0.1" | wc -l)
        if [[ $suspicious_connections -gt 0 ]]; then
    milou_log "WARN" "Suspicious network connections detected"
            ((events++))
        fi
    fi
    
    return $events
}

# =============================================================================
# Security Utilities
# =============================================================================

# Check if port is listening
check_port_listening() {
    local port="$1"
    
    if command -v netstat >/dev/null 2>&1; then
        netstat -tuln | grep -q ":$port "
    elif command -v ss >/dev/null 2>&1; then
        ss -tuln | grep -q ":$port "
    else
        return 1
    fi
}

# Generate secure random string
generate_secure_password() {
    local length="${1:-32}"
    local chars="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*"
    
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
    else
        head /dev/urandom | tr -dc "$chars" | head -c "$length"
    fi
}

# Validate secure configuration
validate_secure_config() {
    local config_file="$1"
    local issues=0
    
    if [[ ! -f "$config_file" ]]; then
    milou_log "ERROR" "Configuration file not found: $config_file"
        return 1
    fi
    
    # Check for insecure configurations
    local -a insecure_patterns=(
        "password.*=.*123"
        "token.*=.*test"
        "secret.*=.*debug"
        "ssl.*=.*false"
        "debug.*=.*true"
    )
    
    for pattern in "${insecure_patterns[@]}"; do
        if grep -qi "$pattern" "$config_file"; then
    milou_log "WARN" "Potentially insecure configuration found: $pattern"
            ((issues++))
        fi
    done
    
    return $issues
}

# Create security report
create_security_report() {
    local report_file="${1:-security-report-$(date +%Y%m%d_%H%M%S).txt}"
    
    milou_log "INFO" "Generating security report: $report_file"
    
    {
        echo "MILOU SECURITY REPORT"
        echo "===================="
        echo "Generated: $(date)"
        echo "System: $(uname -a)"
        echo "User: $(whoami)"
        echo
        
        echo "SECURITY ASSESSMENT:"
        run_security_assessment
        
        echo
        echo "SYSTEM INFORMATION:"
        get_system_info
        
        echo
        echo "USER INFORMATION:"
        show_user_status
        
        echo
        echo "NETWORK STATUS:"
        if command -v netstat >/dev/null 2>&1; then
            netstat -tuln | head -20
        fi
        
        echo
        echo "DOCKER STATUS:"
        if command -v docker >/dev/null 2>&1; then
            docker info
        fi
        
    } > "$report_file"
    
    milou_log "SUCCESS" "Security report saved to: $report_file"
}

# Export security functions
export -f run_security_assessment
export -f harden_system
export -f monitor_security_events
export -f generate_secure_password
export -f validate_secure_config
export -f create_security_report 