# Milou CLI - Enterprise-Grade Infrastructure Management Tool

🚀 **State-of-the-art CLI for deploying and managing Milou AI Pentest Orchestration platform**

## ✨ Latest Updates

**Version 3.1.0** - Production-Ready Release:
- ✅ **Intelligent Conflict Detection**: Automatically detects and handles existing installations
- ✅ **Modular Architecture**: 8 focused setup modules replacing monolithic functions
- ✅ **Enhanced Error Handling**: Comprehensive validation and recovery mechanisms
- ✅ **Zero-Downtime Updates**: Update configurations without stopping services
- ✅ **Smart Port Management**: Automatic port conflict resolution
- ✅ **Unified Logging**: Consistent logging across all 2,199+ log statements
- ✅ **Production Security**: Secure defaults and hardened configurations

## 🚀 Quick Start

### Fresh Installation
```bash
# Clone and setup in one step
git clone <repository-url>
cd milou-cli
./milou.sh setup
```

### Existing Installation
```bash
# Update existing installation (preserves data)
./milou.sh setup

# Force clean installation (removes all data)
./milou.sh setup --force

# Update configuration only (keeps services running)
./milou.sh config
```

## 📋 System Requirements

**Minimum Requirements:**
- **OS**: Linux (Ubuntu 20.04+, RHEL 8+, Debian 11+)
- **RAM**: 4GB (8GB recommended)
- **Disk**: 20GB free space
- **Network**: Internet access for image downloads

**Auto-Installed Dependencies:**
- Docker 20.10+
- Docker Compose V2
- OpenSSL, curl, jq

## 🛠️ Installation Modes

### 1. Interactive Mode (Default)
Full guided setup with all configuration options:
```bash
./milou.sh setup
```

### 2. Non-Interactive Mode
Automated setup using environment variables:
```bash
export DOMAIN="your-domain.com"
export ADMIN_EMAIL="admin@your-domain.com"
export GITHUB_TOKEN="your_token_here"
./milou.sh setup --non-interactive
```

### 3. Development Mode
Use locally built images instead of registry:
```bash
./milou.sh setup --dev
```

### 4. Force Mode
Override existing installations:
```bash
./milou.sh setup --force
```

## ⚙️ Core Commands

### Essential Operations
```bash
# Complete setup wizard
./milou.sh setup

# Service management
./milou.sh start|stop|restart|status

# System monitoring
./milou.sh health              # Comprehensive health check
./milou.sh logs [service]      # View service logs
./milou.sh diagnose           # Full system diagnosis
```

### Configuration Management
```bash
# Display current configuration
./milou.sh config

# Validate configuration
./milou.sh validate

# Backup configuration
./milou.sh backup

# Restore from backup
./milou.sh restore <backup-file>
```

### SSL Certificate Management
```bash
# Interactive SSL manager
./milou.sh ssl

# Generate new certificates
./milou.sh ssl --generate

# Validate existing certificates
./milou.sh ssl --validate
```

### Admin Account Management
```bash
# Show admin credentials
./milou.sh admin credentials

# Reset admin password
./milou.sh admin reset
```

### System Maintenance
```bash
# Update to latest version
./milou.sh update

# Clean up Docker resources
./milou.sh cleanup

# Complete uninstall
./milou.sh uninstall

# Security assessment
./milou.sh security-check
```

### Development Tools
```bash
# Build local images
./milou.sh build-images

# Debug Docker images
./milou.sh debug-images

# Install system dependencies
./milou.sh install-deps
```

## 🏗️ Architecture

### Modular Design
The CLI uses a modern modular architecture:

```
milou-cli/
├── commands/           # Command handlers
│   ├── setup/         # Modular setup system
│   │   ├── main.sh           # Setup coordinator
│   │   ├── analysis.sh       # System analysis
│   │   ├── prerequisites.sh  # Dependency checking
│   │   ├── configuration.sh  # Config wizard
│   │   └── validation.sh     # Final validation
│   ├── docker-services.sh    # Service management
│   ├── system.sh             # System commands
│   └── user-security.sh      # Security commands
├── lib/               # Core modules
│   ├── core/          # Essential utilities
│   ├── docker/        # Docker management
│   ├── ssl/           # SSL certificate handling
│   ├── config/        # Configuration management
│   └── user/          # User management
└── static/            # Docker Compose files
```

### Docker Compose Strategy
Three-layer approach for different environments:

1. **Base Layer**: `docker-compose.yml` - Production with registry images
2. **Dev Override**: `docker-compose.local.yml` - Local image builds
3. **Full Dev**: `docker-compose.dev.yml` - Source mounting + hot reload

## 🔧 Configuration

### Environment Variables
All configuration is stored in `.env` with secure defaults:

```bash
# Core Configuration
DOMAIN=your-domain.com
ADMIN_EMAIL=admin@your-domain.com
ADMIN_PASSWORD=generated_secure_password

# Database (auto-generated)
POSTGRES_USER=milou_user_abc123
POSTGRES_PASSWORD=generated_secure_password
DB_NAME=milou_database

# Security (auto-generated)
JWT_SECRET=generated_secure_secret
SESSION_SECRET=generated_secure_secret
ENCRYPTION_KEY=generated_secure_key

# SSL Configuration
SSL_MODE=generate|existing|none
SSL_CERT_PATH=./ssl/milou.crt
SSL_KEY_PATH=./ssl/milou.key

# Networking
HTTP_PORT=80
HTTPS_PORT=443
```

### SSL Options
1. **Generate** (default): Self-signed certificates for development
2. **Existing**: Use your own certificates
3. **None**: HTTP-only mode (not recommended for production)

## 🛡️ Security Features

### Automatic Security Hardening
- **Secure Password Generation**: 32+ character passwords with special characters
- **File Permissions**: Restricted access (600) for sensitive files  
- **Container Isolation**: Non-root containers with minimal privileges
- **Secret Management**: Environment-based secret injection
- **SSL/TLS**: HTTPS-first with proper certificate validation

### Security Commands
```bash
# Comprehensive security assessment
./milou.sh security-check

# Generate security report
./milou.sh security-report

# Harden system configuration
./milou.sh security-harden
```

## 🚨 Conflict Resolution

The CLI automatically detects and resolves conflicts:

### Existing Installation Detection
When running setup on a system with existing Milou:
1. **Smart Detection**: Checks containers, configs, and port usage
2. **User Choice**: Options to stop, update, or clean install
3. **Safe Defaults**: Preserves data unless explicitly requested

### Port Conflict Resolution
Automatic handling of port conflicts:
- **Detection**: Scans ports 80, 443, 5432, 6379, 9999
- **Resolution**: Options to stop conflicts or use alternative ports
- **Prevention**: Pre-flight checks before service startup

## 📊 Monitoring & Diagnostics

### Health Monitoring
```bash
# Quick health check
./milou.sh status

# Comprehensive health report
./milou.sh health

# Service-specific logs
./milou.sh logs nginx
./milou.sh logs backend
./milou.sh logs database
```

### Diagnostic Tools
```bash
# Full system diagnosis
./milou.sh diagnose

# Docker image debugging
./milou.sh debug-images

# Port and network analysis
./milou.sh network-check
```

## 🔄 Update & Maintenance

### Zero-Downtime Updates
```bash
# Update configuration only (services keep running)
./milou.sh setup --update-config-only

# Full update with service restart
./milou.sh update

# Update to specific version
./milou.sh update --version v3.1.0
```

### Backup & Recovery
```bash
# Create backup
./milou.sh backup

# Create backup with custom name
./milou.sh backup --name "pre-update-backup"

# Restore from backup
./milou.sh restore backup-20240115-120000.tar.gz

# List available backups
./milou.sh backup --list
```

## 🧹 Cleanup & Uninstall

### Selective Cleanup
```bash
# Clean Docker resources only
./milou.sh cleanup docker

# Clean system temporary files
./milou.sh cleanup system

# Clean everything (non-destructive)
./milou.sh cleanup all
```

### Complete Uninstall
```bash
# Standard uninstall (keeps user data)
./milou.sh uninstall

# Keep specific components
./milou.sh uninstall --keep-config --keep-ssl

# Complete removal (destructive)
./milou.sh uninstall --aggressive

# Show uninstall options
./milou.sh uninstall --help
```

## 🐛 Troubleshooting

### Common Issues

**Port Conflicts**
```bash
# Check what's using ports
sudo netstat -tlnp | grep :5432

# Stop conflicting services
sudo systemctl stop postgresql
./milou.sh setup
```

**Docker Permission Issues**
```bash
# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker
```

**SSL Certificate Issues**
```bash
# Regenerate certificates
./milou.sh ssl --regenerate

# Validate certificates
./milou.sh ssl --validate
```

### Getting Help
```bash
# Show all commands
./milou.sh help

# Command-specific help
./milou.sh setup --help
./milou.sh ssl --help
./milou.sh uninstall --help

# Verbose debugging
./milou.sh setup --verbose --debug
```

## 📞 Support

### Log Files
Important logs for troubleshooting:
- **CLI Logs**: Console output with `--verbose`
- **Docker Logs**: `./milou.sh logs [service]`
- **System Logs**: `/var/log/milou/` (if configured)

### Diagnostic Information
```bash
# Generate diagnostic report
./milou.sh diagnose > diagnostic-report.txt

# Include in support requests along with:
# - Operating system version
# - Docker version
# - Error messages
# - Steps to reproduce
```

---

## 🎯 Ready for Production

This CLI has been thoroughly tested and optimized for client deployment:

✅ **Zero Breaking Changes** - All existing functionality preserved  
✅ **Enhanced Reliability** - Comprehensive error handling and recovery  
✅ **Production Security** - Hardened defaults and security validation  
✅ **Client-Ready Documentation** - Complete setup and maintenance guides  
✅ **Modular Architecture** - Easy to maintain and extend  

**Your clients will love the improved reliability and user experience!** 🚀 