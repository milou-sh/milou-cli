# Milou CLI - Enhanced Edition v3.0.0

A state-of-the-art command-line interface for managing Milou deployments with comprehensive security, user management, and automation features.

## 🚀 Key Features

- **🔐 Security-First Design**: Automatic user management, security hardening, and comprehensive assessments
- **👤 User Management**: Dedicated user creation and permission management for secure operations
- **🛡️ Security Hardening**: Built-in security measures and compliance checks
- **🐳 Docker Integration**: Advanced Docker management with security best practices
- **📊 Comprehensive Monitoring**: Health checks, diagnostics, and detailed reporting
- **🔧 Automated Setup**: Interactive and non-interactive setup wizards
- **📋 Backup & Recovery**: Automated backup and restore capabilities

## 📋 Prerequisites

- **Operating System**: Linux (Ubuntu 20.04+, CentOS 8+, or similar)
- **Docker**: Version 20.10.0 or higher
- **Docker Compose**: Version 2.0.0 or higher
- **System Resources**: 
  - RAM: 2GB+ available
  - Disk: 2GB+ free space
  - Network: Internet connectivity for image downloads

## 🔧 Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/milou-sh/milou-cli.git
   cd milou-cli
   ```

2. **Make the script executable**:
   ```bash
   chmod +x milou.sh
   ```

3. **Run the setup wizard** (recommended):
   ```bash
   ./milou.sh setup
   ```

## 🔐 Security & User Management

### Automatic User Creation

For security reasons, Milou should not run as root. The CLI automatically handles user management:

```bash
# Create dedicated milou user (requires sudo)
sudo ./milou.sh create-user

# Check current user status
./milou.sh user-status

# Migrate existing installation to milou user
sudo ./milou.sh migrate-user
```

### Security Features

```bash
# Run comprehensive security assessment
./milou.sh security-check

# Apply security hardening (requires sudo)
sudo ./milou.sh security-harden

# Generate detailed security report
./milou.sh security-report
```

## 📖 Usage Guide

### Basic Commands

```bash
# Interactive setup (recommended for first-time users)
./milou.sh setup

# Non-interactive setup
./milou.sh setup --token ghp_xxxx --domain example.com --latest

# Start all services
./milou.sh start

# Stop all services
./milou.sh stop

# Check service status
./milou.sh status

# View logs
./milou.sh logs [service_name]
```

### Advanced Operations

```bash
# Run comprehensive diagnostics
./milou.sh diagnose

# Health checks
./milou.sh health
./milou.sh health-check

# SSL certificate management
./milou.sh ssl --domain example.com

# Backup and restore
./milou.sh backup
./milou.sh restore backup_file.tar.gz

# System cleanup
./milou.sh cleanup
./milou.sh cleanup --complete  # Destructive cleanup
```

### Development & Debugging

```bash
# Get shell access to containers
./milou.sh shell backend

# Debug Docker images
./milou.sh debug-images --token ghp_xxxx

# View configuration
./milou.sh config

# Validate setup
./milou.sh validate
```

## 🎛️ Configuration Options

### Global Options

- `--verbose`: Show detailed output and debug information
- `--force`: Force operation without confirmation prompts
- `--dry-run`: Show what would be done without executing
- `--auto-create-user`: Automatically create milou user if running as root
- `--skip-user-check`: Skip user management validation (not recommended)
- `--non-interactive`: Run without interactive prompts

### Setup Options

- `--token TOKEN`: GitHub Personal Access Token
- `--domain DOMAIN`: Domain name for the installation
- `--ssl-path PATH`: Path to SSL certificates directory
- `--email EMAIL`: Admin email address
- `--latest`: Use latest available Docker image versions

## 🔑 Authentication

### GitHub Personal Access Token

A GitHub Personal Access Token is required for pulling private Docker images:

1. Go to [GitHub Settings > Tokens](https://github.com/settings/tokens)
2. Create a new token with these scopes:
   - `read:packages`
   - `write:packages`
3. Use the token with the `--token` parameter

**Security Note**: Never store tokens in configuration files. Always pass them via command line arguments.

## 🛡️ Security Best Practices

### User Management

1. **Never run as root**: The CLI will warn and offer to create a dedicated user
2. **Use dedicated user**: Create and use the `milou` user for all operations
3. **Proper permissions**: Ensure Docker group membership for non-root users

### System Security

1. **Regular assessments**: Run `security-check` regularly
2. **Apply hardening**: Use `security-harden` for production deployments
3. **Monitor logs**: Check security logs in `~/.milou/security.log`
4. **Update regularly**: Keep system and Docker updated

### SSL/TLS

1. **Use valid certificates**: Avoid self-signed certificates in production
2. **Monitor expiration**: Check certificate expiration dates
3. **Strong encryption**: Use 2048-bit or higher SSL keys

## 📁 Directory Structure

```
milou-cli/
├── milou.sh                 # Main CLI script
├── utils/                   # Utility modules
│   ├── utils.sh            # Core utilities
│   ├── user-management.sh  # User management functions
│   ├── security.sh         # Security hardening
│   ├── docker.sh           # Docker operations
│   ├── ssl.sh              # SSL management
│   ├── backup.sh           # Backup/restore
│   └── setup_wizard.sh     # Interactive setup
├── .env                    # Configuration file (auto-generated)
└── ssl/                    # SSL certificates directory
```

## 🔍 Troubleshooting

### Common Issues

1. **Permission Denied**:
   ```bash
   # Add user to docker group
   sudo usermod -aG docker $USER
   newgrp docker
   
   # Or create milou user
   sudo ./milou.sh create-user
   ```

2. **Docker Not Running**:
   ```bash
   sudo systemctl start docker
   sudo systemctl enable docker
   ```

3. **Network Issues**:
   ```bash
   # Test connectivity
   curl -I https://ghcr.io/
   
   # Check firewall
   sudo ufw status
   ```

4. **Image Pull Failures**:
   ```bash
   # Debug images
   ./milou.sh debug-images --token YOUR_TOKEN
   
   # Check authentication
   docker login ghcr.io
   ```

### Diagnostic Commands

```bash
# Comprehensive system diagnosis
./milou.sh diagnose

# Check system requirements
./milou.sh health

# View detailed status
./milou.sh detailed-status

# Check user permissions
./milou.sh user-status
```

## 📊 Monitoring & Logging

### Log Files

- **Main log**: `~/.milou/milou.log`
- **Security log**: `~/.milou/security.log`
- **Service logs**: `./milou.sh logs [service]`

### Health Monitoring

```bash
# Quick health check
./milou.sh health-check

# Comprehensive health assessment
./milou.sh health

# Security monitoring
./milou.sh security-check
```

## 🔄 Updates & Maintenance

### Updating Milou CLI

```bash
# Update to latest version
./milou.sh update

# Check for updates manually
git pull origin main
```

### Maintenance Tasks

```bash
# Regular backup
./milou.sh backup

# Clean up Docker resources
./milou.sh cleanup

# Security assessment
./milou.sh security-check

# System health check
./milou.sh health
```

## 🆘 Support

- **Documentation**: [https://docs.milou.sh](https://docs.milou.sh)
- **Issues**: [GitHub Issues](https://github.com/milou-sh/milou/issues)
- **Email**: support@milou.sh

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## 🔖 Version History

### v3.0.0 (Current)
- ✨ Enhanced user management system
- 🔐 Comprehensive security hardening
- 🛡️ Security assessment and reporting
- 🚀 Improved setup wizard
- 📊 Advanced monitoring and diagnostics
- 🔧 Better error handling and suggestions

### v2.x.x
- Basic Docker management
- SSL certificate handling
- Backup and restore functionality

### v1.x.x
- Initial release
- Basic service management 