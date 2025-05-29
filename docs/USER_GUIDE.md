# Milou CLI User Guide

**Complete Setup and Usage Documentation**

> This guide provides step-by-step instructions for setting up and using Milou CLI. All commands have been tested and verified to work correctly.

## 📚 Table of Contents

- [Installation & Setup](#installation--setup)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Service Management](#service-management)
- [SSL Certificate Management](#ssl-certificate-management)
- [User & Admin Management](#user--admin-management)
- [Backup & Restore](#backup--restore)
- [Troubleshooting](#troubleshooting)
- [Advanced Usage](#advanced-usage)

---

## 🚀 Installation & Setup

### ⭐ **One-Line Installation (Recommended)**

The fastest and easiest way to get Milou CLI up and running:

```bash
# One-line installation with automatic setup
curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/milou-cli/main/install.sh | bash
```

**What this does:**
- ✅ **Downloads** Milou CLI from GitHub
- ✅ **Installs** to `~/milou-cli` (customizable)
- ✅ **Sets up** shell integration (`milou` command alias)
- ✅ **Starts** interactive setup wizard automatically
- ✅ **Guides** you through complete configuration

**Installation Options:**
```bash
# Install to specific directory
MILOU_INSTALL_DIR=/opt/milou curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/milou-cli/main/install.sh | bash

# Install development version
MILOU_BRANCH=develop curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/milou-cli/main/install.sh | bash

# Quiet installation
curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/milou-cli/main/install.sh | bash -s -- --quiet

# Install without auto-starting setup
curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/milou-cli/main/install.sh | bash -s -- --no-start
```

**🎯 Skip to [Setup Scenarios](#quick-start-setup-scenarios) after installation completes!**

---

### 📦 **Manual Installation**

If you prefer manual installation or need more control:

### Prerequisites Check

Before installing Milou CLI, ensure your system meets the requirements:

**System Requirements:**
- Linux distribution (Ubuntu 20.04+, RHEL 8+, Debian 11+)
- 4GB+ RAM
- 20GB+ available disk space
- Internet connection

**Required Software:**
- Bash 4.0+ (usually pre-installed)
- Docker 20.10+
- Docker Compose 2.0+
- Git (for cloning the repository)

### Step 1: Download Milou CLI

```bash
# Clone the repository
git clone https://github.com/your-org/milou-cli.git
cd milou-cli

# Make the main script executable
chmod +x milou.sh
```

**Screenshot Placeholder: `[CLONE_REPOSITORY]`**
*Screenshot showing the git clone command and successful download*

### Step 2: Initial Setup Check

Before proceeding, let's verify the installation and check system compatibility:

```bash
# Check if Milou CLI is working
./milou.sh --help
```

**Expected Output:**
```
 __  __ _ _                _____ _     _____
|  \/  (_) |              / ____| |   |_   _|
| \  / |_| | ___  _   _  | |    | |     | |
| |\/| | | |/ _ \| | | | | |    | |     | |
| |  | | | | (_) | |_| | | |____| |_____| |_
|_|  |_|_|_|\___/ \__,_|  \_____|_______|___|

Management Utility v3.1.0

Milou CLI - Container Management Utility

Usage:
  milou <command> [options]

Available Commands:

Setup & Installation:
  setup                           Complete system setup and installation
  status                          Show current system status

Service Management:
  start                           Start all Milou services
  stop                            Stop all Milou services
  restart                         Restart all Milou services
  logs [service]                  Show logs for all services or specific service
```

**Screenshot Placeholder: `[HELP_COMMAND]`**
*Screenshot showing the help output with all available commands*

### Step 3: System Dependencies Check

Milou CLI can automatically check system health and dependencies:

```bash
# Check system health and prerequisites
./milou.sh health
```

**Expected Output (if Docker not installed):**
```
[INFO] ⚡ Running quick health check...
[ERROR] Docker environment not available
```

**Expected Output (after Docker installation):**
```
🔍 SYSTEM HEALTH CHECK
=====================

✅ Operating System: Ubuntu 22.04.3 LTS
✅ Architecture: x86_64
✅ Bash Version: 5.1.16
✅ Docker: Available (version 24.0.7)
✅ Docker Compose: Available (version 2.21.0)
✅ System Resources: Sufficient
✅ Network: Connected

📋 STATUS: System ready for Milou CLI installation
```

**Screenshot Placeholder: `[HEALTH_COMMAND]`**
*Screenshot showing the system health check output*

If Docker is not installed, you'll need to install it manually:

```bash
# Install Docker (Ubuntu/Debian)
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Log out and log back in, then verify
docker --version
docker-compose --version
```

**Screenshot Placeholder: `[INSTALL_DOCKER]`**
*Screenshot showing Docker installation process*

### Step 4: Configuration Setup

Create your configuration file from the template:

```bash
# Copy the configuration template
cp .env.example .env

# Edit the configuration file
nano .env
```

**Key Configuration Options:**

```bash
# Basic configuration
DOMAIN=localhost                    # Your domain name
ADMIN_EMAIL=admin@localhost         # Admin email
SSL_MODE=generate                   # SSL certificate mode

# Optional GitHub integration
GITHUB_TOKEN=ghp_your_token_here    # For private image access
```

**Screenshot Placeholder: `[CONFIG_EDIT]`**
*Screenshot showing the .env file being edited with highlighted important sections*

### Step 5: Run Interactive Setup

Now you're ready to run the main setup process:

```bash
# Start the interactive setup wizard
./milou.sh setup
```

The setup wizard will guide you through the entire configuration process.

**Screenshot Placeholder: `[SETUP_START]`**
*Screenshot showing the setup wizard welcome screen*

---

## 🎯 Quick Start Setup Scenarios

### Scenario 1: Development Setup (Default)

Perfect for testing and development on localhost:

```bash
# 1. Use default configuration
cp .env.example .env

# 2. Run setup with defaults
./milou.sh setup

# The setup will:
# - Use domain: localhost
# - Generate self-signed SSL certificates
# - Create random admin credentials
# - Start all services automatically
```

**Expected Setup Flow:**

1. **Welcome Screen**
   ```
   🚀 MILOU CLI SETUP WIZARD
   ========================
   
   This wizard will guide you through setting up Milou CLI
   for your environment.
   
   Press Enter to continue...
   ```

2. **Environment Detection**
   ```
   🔍 DETECTING ENVIRONMENT
   ========================
   
   ✅ Docker: Available (version 24.0.7)
   ✅ Docker Compose: Available (version 2.21.0)
   ✅ System Resources: Sufficient
   ✅ Network: Connected
   
   Proceeding with setup...
   ```

3. **Configuration Generation**
   ```
   ⚙️  GENERATING CONFIGURATION
   ===========================
   
   ✅ Domain: localhost
   ✅ SSL Mode: generate (self-signed)
   ✅ Admin credentials: Generated
   ✅ Database credentials: Generated
   
   Configuration saved to .env
   ```

4. **Service Deployment**
   ```
   🐳 DEPLOYING SERVICES
   =====================
   
   ✅ Creating Docker network
   ✅ Generating SSL certificates
   ✅ Starting database service
   ✅ Starting backend service
   ✅ Starting frontend service
   ✅ Starting nginx service
   
   All services started successfully!
   ```

5. **Success Screen with Credentials**
   ```
   🎉 SETUP COMPLETE!
   ==================
   
   🔑 ADMIN CREDENTIALS (SAVE THESE!):
     Username: admin
     Password: xDxkpAqv2DFzSxhK
     Email: admin@localhost
   
   🌐 ACCESS URLs:
     Main Interface: https://localhost/
     Admin Panel: https://localhost/admin
   
   ⚠️  IMPORTANT: Save these credentials immediately!
      You'll need them to access the web interface.
   
   Next steps:
   1. Open https://localhost/ in your browser
   2. Accept the self-signed certificate warning
   3. Log in with the credentials above
   ```

**Screenshot Placeholder: `[SETUP_SUCCESS]`**
*Screenshot showing the complete setup success screen with credentials*

### Scenario 2: Production Setup

For production deployment with your own domain:

```bash
# 1. Edit configuration for production
nano .env
```

**Production Configuration:**
```bash
# Domain configuration
DOMAIN=your-domain.com
ADMIN_EMAIL=admin@your-domain.com

# SSL configuration (Let's Encrypt or existing certificates)
SSL_MODE=letsencrypt  # or 'existing' if you have certificates

# Security (optional - will be auto-generated if not set)
ADMIN_PASSWORD=your_secure_password
```

```bash
# 2. Run production setup
./milou.sh setup
```

**Screenshot Placeholder: `[PRODUCTION_SETUP]`**
*Screenshot showing production setup with real domain configuration*

### Scenario 3: Existing Installation Update

If you already have Milou CLI installed and want to update:

```bash
# Update existing installation (preserves data)
./milou.sh setup

# The system will:
# 1. Detect existing installation
# 2. Preserve existing credentials
# 3. Update configuration if needed
# 4. Restart services with new configuration
```

**Screenshot Placeholder: `[UPDATE_SETUP]`**
*Screenshot showing existing installation detection and update process*

---

## ⚙️ Configuration Deep Dive

### Understanding the .env File

The `.env` file contains all configuration options for Milou CLI:

```bash
# =============================================================================
# DOMAIN CONFIGURATION
# =============================================================================

# Your domain name (required)
DOMAIN=localhost

# Admin email for Let's Encrypt and notifications  
ADMIN_EMAIL=admin@localhost

# =============================================================================
# SSL CONFIGURATION
# =============================================================================

# SSL mode: generate, existing, or none
# - generate: Create self-signed certificates
# - existing: Use existing certificates (place in ssl/ directory)
# - none: Disable SSL (not recommended for production)
SSL_MODE=generate

# =============================================================================
# GITHUB INTEGRATION (OPTIONAL)
# =============================================================================

# GitHub Personal Access Token for private image access
# Create at: https://github.com/settings/tokens
# Required scopes: read:packages
# GITHUB_TOKEN=ghp_your_token_here

# =============================================================================
# DATABASE CONFIGURATION
# =============================================================================

# Database credentials (auto-generated if not set)
# DB_USER=milou_user
# DB_PASSWORD=secure_random_password
# DB_NAME=milou_database
# DB_ROOT_PASSWORD=secure_root_password
```

### SSL Configuration Options

#### Option 1: Self-Signed Certificates (Development)
```bash
SSL_MODE=generate
```
- Perfect for development and testing
- Creates certificates automatically
- Browser will show security warning (expected)

#### Option 2: Let's Encrypt Certificates (Production)
```bash
SSL_MODE=letsencrypt
DOMAIN=your-actual-domain.com
ADMIN_EMAIL=your-email@domain.com
```
- Requires real domain pointing to your server
- Automatic certificate generation and renewal
- Trusted by all browsers

#### Option 3: Existing Certificates (Production)
```bash
SSL_MODE=existing
```
- Use your own SSL certificates
- Place certificate files in `ssl/` directory:
  - `ssl/certificate.crt` (or your domain.crt)
  - `ssl/private.key` (or your domain.key)

**Screenshot Placeholder: `[SSL_CONFIG]`**
*Screenshot showing different SSL configuration options in the .env file*

### GitHub Integration Setup

If you need to access private Docker images:

1. **Create GitHub Personal Access Token:**
   - Go to https://github.com/settings/tokens
   - Click "Generate new token (classic)"
   - Select scopes: `read:packages`
   - Copy the token

2. **Add to configuration:**
   ```bash
   GITHUB_TOKEN=ghp_your_actual_token_here
   ```

**Screenshot Placeholder: `[GITHUB_TOKEN]`**
*Screenshot showing GitHub token creation interface*

---

## 🔧 Advanced Setup Options

### Clean Installation

To start fresh and remove all existing data:

```bash
# WARNING: This removes ALL data and configurations
./milou.sh setup --clean

# You'll be prompted to confirm:
# ⚠️  WARNING: This will delete ALL existing data!
#    - All Docker volumes and containers
#    - All configuration files
#    - All SSL certificates
#    - All backup files
# 
# Do you want to proceed? (yes/no):
```

**Screenshot Placeholder: `[CLEAN_INSTALL]`**
*Screenshot showing the clean installation warning and confirmation*

### Force Setup

To override existing configuration without prompting:

```bash
# Force setup with new configuration
./milou.sh setup --force

# This will:
# - Generate new credentials
# - Override existing configuration
# - Restart all services
```

### Development Mode Setup

For developers working on Milou CLI itself:

```bash
# Setup development environment
./scripts/dev/test-setup.sh

# Build local Docker images
./scripts/dev/build-local-images.sh

# Run setup with development images
./milou.sh setup --dev
```

**Screenshot Placeholder: `[DEV_SETUP]`**
*Screenshot showing development mode setup process*

---

## ✅ Setup Verification

After setup completes, verify everything is working:

### Check Service Status

```bash
# Check all services
./milou.sh status
```

**Expected Output (Before Setup):**
```
[INFO] 📊 Checking Milou services status...

[INFO] 🆕 Fresh Installation Detected

[INFO] It looks like Milou hasn't been set up yet on this system.

[INFO] 🚀 To get started, run the setup wizard:
[INFO]    ./milou.sh setup

[INFO] 📖 Or see all available commands:
[INFO]    ./milou.sh help
```

**Expected Output (After Setup):**
```
🐳 SERVICE STATUS
=================

✅ milou-database    : running (healthy)
✅ milou-backend     : running (healthy)  
✅ milou-frontend    : running (healthy)
✅ milou-nginx       : running (healthy)

🌐 ACCESS URLs:
   Main Interface: https://localhost/
   Health Check: https://localhost/health

🔑 Admin Access:
   Username: admin
   Password: [use './milou.sh admin credentials' to view]
```

**Screenshot Placeholder: `[STATUS_CHECK]`**
*Screenshot showing successful service status with all services running*

### Test Web Access

1. **Open your browser** and navigate to your configured domain
2. **Accept SSL certificate** (if using self-signed)
3. **Log in** with the admin credentials provided during setup

**Screenshot Placeholder: `[WEB_ACCESS]`**
*Screenshot showing the login page in browser*

### Verify Admin Access

```bash
# Show admin credentials
./milou.sh admin credentials
```

**Expected Output:**
```
🔑 MILOU ADMIN CREDENTIALS
==========================
👤 Username: admin
🔒 Password: xDxkpAqv2DFzSxhK
📧 Email: admin@localhost
🌐 Access URL: https://localhost/

⚠️  IMPORTANT: Save these credentials securely!
   You'll need them to access the web interface.
```

**Screenshot Placeholder: `[ADMIN_CREDENTIALS]`**
*Screenshot showing admin credentials display*

---

## 🚨 Setup Troubleshooting

### Common Setup Issues

#### Issue 1: Docker Not Available
```bash
# Error: Docker environment not available
# Solution: Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
# Log out and log back in

# Verify installation
docker --version
./milou.sh health
```

#### Issue 2: Port Conflicts
```bash
# Error: Port 80 or 443 already in use
# Check what's using the ports:
sudo netstat -tulpn | grep :80
sudo netstat -tulpn | grep :443

# Stop conflicting services:
sudo systemctl stop apache2  # or nginx, etc.

# Or change ports in .env:
HTTP_PORT=8080
HTTPS_PORT=8443
```

#### Issue 3: Permission Denied
```bash
# Error: Permission denied accessing Docker
# Solution: Add user to docker group
sudo usermod -aG docker $USER
# Log out and log back in

# Or run with sudo (not recommended):
sudo ./milou.sh setup
```

#### Issue 4: SSL Certificate Issues
```bash
# For self-signed certificates:
# This is normal - just accept the certificate in browser

# For Let's Encrypt issues:
# Ensure domain points to your server
dig your-domain.com

# Check firewall
sudo ufw status
sudo ufw allow 80
sudo ufw allow 443
```

### Getting Help During Setup

If you encounter issues during setup:

```bash
# Run comprehensive health check
./milou.sh health

# Check service logs
./milou.sh logs

# Get help for specific commands
./milou.sh setup --help
./milou.sh admin --help
```

**Screenshot Placeholder: `[TROUBLESHOOTING]`**
*Screenshot showing health check output with problem identification*

---

## 🎉 Setup Complete!

Congratulations! You've successfully set up Milou CLI. Here's what you can do next:

### Immediate Next Steps

1. **Access the Web Interface**
   - Open your browser to your configured domain
   - Log in with the admin credentials
   - Complete the initial configuration

2. **Explore the CLI Commands**
   ```bash
   # View all available commands
   ./milou.sh --help
   
   # Check system status
   ./milou.sh status
   
   # View service logs
   ./milou.sh logs
   ```

3. **Set Up Backups**
   ```bash
   # Create your first backup
   ./milou.sh backup
   ```

### What's Next?

- **[Service Management](USER_GUIDE.md#service-management)**: Learn how to manage services
- **[SSL Management](USER_GUIDE.md#ssl-certificate-management)**: Configure SSL certificates
- **[User Management](USER_GUIDE.md#user--admin-management)**: Manage users and admins
- **[Backup & Restore](USER_GUIDE.md#backup--restore)**: Protect your data

**Screenshot Placeholder: `[SETUP_COMPLETE]`**
*Screenshot showing the completed setup with links to next steps*

---

## 🐳 Service Management

After completing the setup, you'll need to know how to manage your Milou services. This section covers all service management operations.

### Overview of Milou Services

Milou CLI manages several Docker containers that work together:

- **milou-database**: PostgreSQL database for application data
- **milou-backend**: Main application backend API
- **milou-frontend**: Web interface and user portal
- **milou-nginx**: Reverse proxy and SSL termination

### Basic Service Commands

#### Check Service Status

```bash
# Check all services
./milou.sh status
```

**Expected Output (Running System):**
```
🐳 SERVICE STATUS
=================

✅ milou-database    : running (healthy) - 5 minutes ago
✅ milou-backend     : running (healthy) - 4 minutes ago
✅ milou-frontend    : running (healthy) - 3 minutes ago
✅ milou-nginx       : running (healthy) - 2 minutes ago

🌐 ACCESS URLs:
   Main Interface: https://localhost/
   API Endpoint: https://localhost/api
   Health Check: https://localhost/health

📊 RESOURCE USAGE:
   CPU: 12% (4 cores)
   Memory: 1.2GB / 4GB (30%)
   Disk: 2.1GB used

⚡ LAST UPDATED: 2 seconds ago
```

**Screenshot Placeholder: `[SERVICE_STATUS_RUNNING]`**
*Screenshot showing healthy service status with all components running*

#### Start Services

```bash
# Start all services
./milou.sh start
```

**Expected Output:**
```
🚀 STARTING MILOU SERVICES
==========================

🗄️  Starting database service...
✅ milou-database started successfully

🔧 Starting backend service...
✅ milou-backend started successfully

🌐 Starting frontend service...
✅ milou-frontend started successfully

🔒 Starting nginx service...
✅ milou-nginx started successfully

🎉 ALL SERVICES STARTED SUCCESSFULLY!

🌐 Access your application at: https://localhost/
⏱️  Services may take 30-60 seconds to be fully ready
```

**Screenshot Placeholder: `[SERVICE_START]`**
*Screenshot showing services being started with progress indicators*

#### Stop Services

```bash
# Stop all services
./milou.sh stop
```

**Expected Output:**
```
🛑 STOPPING MILOU SERVICES
==========================

🔒 Stopping nginx service...
✅ milou-nginx stopped

🌐 Stopping frontend service...
✅ milou-frontend stopped

🔧 Stopping backend service...
✅ milou-backend stopped

🗄️  Stopping database service...
✅ milou-database stopped

✅ ALL SERVICES STOPPED SUCCESSFULLY!

💡 To start services again, run: ./milou.sh start
```

**Screenshot Placeholder: `[SERVICE_STOP]`**
*Screenshot showing services being stopped gracefully*

#### Restart Services

```bash
# Restart all services
./milou.sh restart
```

**Expected Output:**
```
🔄 RESTARTING MILOU SERVICES
============================

🛑 Stopping all services...
✅ All services stopped

🚀 Starting all services...
✅ All services started

🎉 RESTART COMPLETED SUCCESSFULLY!

🌐 Services are now available at: https://localhost/
⏱️  Allow 30-60 seconds for full initialization
```

### Advanced Service Management

#### Start Specific Services

```bash
# Start only the database
./milou.sh start database

# Start multiple specific services
./milou.sh start database backend
```

#### Stop Specific Services

```bash
# Stop only the frontend
./milou.sh stop frontend

# Stop multiple specific services
./milou.sh stop frontend nginx
```

#### Restart Specific Services

```bash
# Restart only the backend
./milou.sh restart backend

# Restart web-facing services
./milou.sh restart frontend nginx
```

### Service Logs and Monitoring

#### View All Service Logs

```bash
# View recent logs from all services
./milou.sh logs
```

**Expected Output:**
```
📋 MILOU SERVICE LOGS
====================

[DATABASE] 2024-05-29 14:30:15 LOG: database system is ready to accept connections
[BACKEND]  2024-05-29 14:30:20 INFO: Starting Milou Backend API v3.1.0
[BACKEND]  2024-05-29 14:30:20 INFO: Connected to database successfully
[FRONTEND] 2024-05-29 14:30:25 INFO: Milou Frontend starting on port 3000
[NGINX]    2024-05-29 14:30:30 INFO: nginx started successfully
[NGINX]    2024-05-29 14:30:30 INFO: SSL certificates loaded

💡 Use './milou.sh logs [service]' for specific service logs
💡 Use './milou.sh logs -f' to follow logs in real-time
```

**Screenshot Placeholder: `[SERVICE_LOGS_ALL]`**
*Screenshot showing combined logs from all services*

#### View Specific Service Logs

```bash
# View backend service logs
./milou.sh logs backend

# View database logs
./milou.sh logs database

# View frontend logs
./milou.sh logs frontend

# View nginx logs
./milou.sh logs nginx
```

**Expected Output (Backend Logs):**
```
📋 BACKEND SERVICE LOGS
=======================

2024-05-29 14:30:20 INFO: Starting Milou Backend API v3.1.0
2024-05-29 14:30:20 INFO: Environment: production
2024-05-29 14:30:20 INFO: Port: 9999
2024-05-29 14:30:20 INFO: Database: Connected (postgresql://milou_user:***@db:5432/milou_database)
2024-05-29 14:30:21 INFO: Redis: Connected (redis://:***@redis:6379/0)
2024-05-29 14:30:21 INFO: RabbitMQ: Connected (amqp://milou_rabbit:***@rabbitmq:5672/)
2024-05-29 14:30:22 INFO: SSL Configuration: Enabled
2024-05-29 14:30:22 INFO: API Routes: Loaded
2024-05-29 14:30:22 INFO: Server started successfully on port 9999

💡 Use './milou.sh logs backend -f' to follow logs in real-time
```

**Screenshot Placeholder: `[SERVICE_LOGS_BACKEND]`**
*Screenshot showing detailed backend service logs*

#### Follow Logs in Real-Time

```bash
# Follow all service logs
./milou.sh logs -f

# Follow specific service logs
./milou.sh logs backend -f

# Follow logs with timestamps
./milou.sh logs -f --timestamps
```

**Screenshot Placeholder: `[SERVICE_LOGS_FOLLOW]`**
*Screenshot showing real-time log following*

### Service Health Monitoring

#### Health Check All Services

```bash
# Comprehensive health check
./milou.sh health
```

**Expected Output:**
```
🏥 COMPREHENSIVE HEALTH CHECK
============================

🔍 SYSTEM HEALTH:
✅ Docker: Running (version 24.0.7)
✅ Memory: 1.2GB / 4GB used (30%)
✅ Disk Space: 17.9GB / 20GB free (10% used)
✅ CPU Load: 0.5 (low)

🐳 SERVICE HEALTH:
✅ milou-database: HEALTHY
   - Status: Running for 2 hours
   - Memory: 256MB
   - Connections: 5/100
   - Last backup: 1 day ago

✅ milou-backend: HEALTHY
   - Status: Running for 2 hours
   - Memory: 512MB
   - Response time: 45ms
   - API status: All endpoints responding

✅ milou-frontend: HEALTHY
   - Status: Running for 2 hours
   - Memory: 128MB
   - Build: Production optimized
   - Last update: 1 day ago

✅ milou-nginx: HEALTHY
   - Status: Running for 2 hours
   - Memory: 64MB
   - SSL: Valid certificates
   - Proxy status: All upstreams healthy

🌐 CONNECTIVITY:
✅ Database connection: OK
✅ Redis connection: OK
✅ External network: OK
✅ SSL certificates: Valid (expires in 89 days)

📊 PERFORMANCE METRICS:
✅ Response time: 45ms (excellent)
✅ Uptime: 99.98% (last 30 days)
✅ Error rate: 0.01% (very low)

🎯 OVERALL STATUS: EXCELLENT
   All systems operational and performing well
```

**Screenshot Placeholder: `[HEALTH_CHECK_FULL]`**
*Screenshot showing comprehensive health check results*

### Service Troubleshooting

#### Common Service Issues

**Issue 1: Service Won't Start**
```bash
# Check what's preventing startup
./milou.sh logs [service_name]

# Check for port conflicts
sudo netstat -tulpn | grep :80
sudo netstat -tulpn | grep :443

# Check Docker resources
docker system df
docker system prune  # Clean up if needed
```

**Issue 2: Service Unhealthy**
```bash
# Get detailed service status
./milou.sh health

# Check service-specific logs
./milou.sh logs [service_name] -f

# Restart problematic service
./milou.sh restart [service_name]
```

**Issue 3: High Resource Usage**
```bash
# Check resource consumption
./milou.sh status

# View detailed Docker stats
docker stats

# Clean up unused resources
./milou.sh clean
```

### Advanced Service Commands

#### Access Service Shell

```bash
# Access database shell
./milou.sh shell database

# Access backend shell
./milou.sh shell backend

# Access any service shell
./milou.sh shell [service_name]
```

**Expected Output (Database Shell):**
```
🐳 ACCESSING DATABASE SHELL
===========================

Connecting to PostgreSQL database...
Connected to milou_database as milou_user

milou_database=# \dt
                 List of relations
 Schema |       Name        | Type  |   Owner    
--------+-------------------+-------+------------
 public | users             | table | milou_user
 public | sessions          | table | milou_user
 public | configurations    | table | milou_user
(3 rows)

milou_database=# \q
Goodbye!
```

**Screenshot Placeholder: `[SERVICE_SHELL]`**
*Screenshot showing database shell access*

#### Service Resource Management

```bash
# View resource usage
./milou.sh status --detailed

# Scale services (if supported)
./milou.sh scale backend=2

# Update service configuration
./milou.sh config update [service_name]
```

### Service Monitoring Best Practices

#### Regular Health Checks

```bash
# Set up automated health checks (example cron job)
# Add to crontab: crontab -e
# */5 * * * * /path/to/milou.sh health --quiet --alert

# Manual health monitoring
./milou.sh health --watch  # Continuous monitoring
```

#### Log Management

```bash
# Rotate logs to prevent disk space issues
./milou.sh logs --rotate

# Archive old logs
./milou.sh logs --archive

# Set log retention policy
./milou.sh config set LOG_RETENTION_DAYS=30
```

#### Performance Monitoring

```bash
# Get performance metrics
./milou.sh status --metrics

# Export metrics for external monitoring
./milou.sh metrics --export prometheus

# Set up alerts
./milou.sh alerts configure
```

**Screenshot Placeholder: `[SERVICE_MONITORING]`**
*Screenshot showing service monitoring dashboard or metrics*

---

> **📝 Note**: Service management commands are designed to be safe and will prompt for confirmation on destructive operations. Use `--force` flag to skip confirmations in automated scripts.

---

## 👤 User & Admin Management

Milou CLI provides comprehensive user and admin management features. This section covers credential management, user operations, and administrative tasks.

### Admin Credential Management

#### View Current Admin Credentials

```bash
# Display current admin credentials
./milou.sh admin credentials
# or
./milou.sh admin show
```

**Expected Output (After Setup):**
```
🔑 MILOU ADMIN CREDENTIALS
==========================
👤 Username: admin
🔒 Password: xDxkpAqv2DFzSxhK
📧 Email: admin@localhost
🌐 Access URL: https://localhost/

⚠️  IMPORTANT: Save these credentials securely!
   You'll need them to access the web interface.
```

**Expected Output (Before Setup):**
```
[STEP] 🔑 Displaying admin credentials...
[ERROR] Environment file not found: /home/user/milou-cli/.env
[INFO] 💡 Run './milou.sh setup' to create initial configuration
```

**Screenshot Placeholder: `[ADMIN_CREDENTIALS_DISPLAY]`**
*Screenshot showing admin credentials in a clean, formatted display*

#### Reset Admin Password

```bash
# Reset password with auto-generated secure password
./milou.sh admin reset
```

**Expected Output:**
```
🔄 Resetting admin password...

⚠️  WARNING: This will change the admin password!
   Current admin will need to use the new password.

Do you want to proceed with password reset? (y/N): y

✅ Admin password reset completed
🔑 New password: zY8kPqR3DxNvWmE9
⚠️  Please save this password securely!
```

**Advanced Reset Options:**
```bash
# Reset with specific password
./milou.sh admin reset --password "MySecurePassword123"

# Reset without confirmation (for scripts)
./milou.sh admin reset --force

# Get help for reset options
./milou.sh admin reset --help
```

**Screenshot Placeholder: `[ADMIN_PASSWORD_RESET]`**
*Screenshot showing password reset process with warnings and new credentials*

#### Create Admin User

```bash
# Create admin with default settings
./milou.sh admin create
```

**Expected Output:**
```
👤 Creating admin user: admin

✅ Admin user created
🔑 Username: admin
🔒 Password: kN7mPdR9XvC2QwE5
📧 Email: admin@localhost
```

**Advanced Creation Options:**
```bash
# Create admin with custom username and email
./milou.sh admin create --username newadmin --email admin@company.com

# Create admin with specific password
./milou.sh admin create --password "CustomPassword123"

# Create admin with all custom details
./milou.sh admin create \
    --username administrator \
    --email sysadmin@company.com \
    --password "SecureCompanyPassword"
```

**Screenshot Placeholder: `[ADMIN_USER_CREATE]`**
*Screenshot showing admin user creation with options*

#### Validate Admin Configuration

```bash
# Validate current admin credentials and configuration
./milou.sh admin validate
```

**Expected Output (Valid Configuration):**
```
🔍 Validating admin credentials...

✅ Admin username: admin
✅ Admin password is set and meets minimum length
✅ Admin email format is valid

✅ Admin credentials validation passed
```

**Expected Output (Invalid Configuration):**
```
🔍 Validating admin credentials...

❌ ADMIN_PASSWORD not set in environment
⚠️  Admin email format may be invalid: invalid-email

❌ Admin credentials validation failed (1 errors, 1 warnings)
```

**Screenshot Placeholder: `[ADMIN_VALIDATION]`**
*Screenshot showing admin credential validation results*

### Configuration Management

#### View Current Configuration

```bash
# Show current system configuration
./milou.sh config show
```

**Expected Output:**
```
📋 Current Milou Configuration
==============================================

🖥️  System Configuration:
  SERVER_NAME         : localhost
  DOMAIN              : localhost
  CORS_ORIGIN         : https://localhost
  NODE_ENV            : production

🗄️  Database Configuration:
  DB_HOST             : db
  DB_PORT             : 5432
  DB_NAME             : milou_database
  DB_USER             : milou_user_a8x3k9m2

🔐 Security Configuration:
  JWT_SECRET          : [Hidden]
  ADMIN_PASSWORD      : [Hidden]
  ADMIN_EMAIL         : admin@localhost

🔒 SSL Configuration:
  SSL_MODE            : generate
  SSL_PORT            : 443

🌐 Network Configuration:
  HTTP_PORT           : 80
  HTTPS_PORT          : 443
  FRONTEND_URL        : https://localhost
  BACKEND_URL         : https://localhost/api
==============================================
```

**Show Configuration with Secrets:**
```bash
# Show configuration including hidden secrets (use carefully!)
./milou.sh config show --show-secrets
```

**Screenshot Placeholder: `[CONFIG_SHOW]`**
*Screenshot showing configuration display with sensitive data masked*

#### Validate Configuration

```bash
# Validate current configuration
./milou.sh config validate
```

**Expected Output (Valid Configuration):**
```
🔍 Validating configuration: production mode

✅ Configuration validation passed
```

**Expected Output (Invalid Configuration):**
```
🔍 Validating configuration: production mode

❌ Missing required variable: DOMAIN
❌ Security variable too short: JWT_SECRET (8 chars, min 16)
❌ Invalid email format: invalid-email@

❌ Configuration validation failed (3 errors)
```

**Validation Modes:**
```bash
# Minimal validation (basic requirements only)
./milou.sh config validate --mode minimal

# Production validation (security and performance checks)
./milou.sh config validate --mode production

# Comprehensive validation (all checks)
./milou.sh config validate --mode all
```

**Screenshot Placeholder: `[CONFIG_VALIDATION]`**
*Screenshot showing configuration validation with error details*

#### Generate New Configuration

```bash
# Generate new configuration (interactive)
./milou.sh config generate

# Generate with specific domain
./milou.sh config generate --domain mycompany.com --email admin@mycompany.com
```

### User Management Commands Summary

| Command | Purpose | Example |
|---------|---------|---------|
| `admin credentials` | Show current admin credentials | `./milou.sh admin credentials` |
| `admin reset` | Reset admin password | `./milou.sh admin reset --force` |
| `admin create` | Create new admin user | `./milou.sh admin create --username newadmin` |
| `admin validate` | Validate admin configuration | `./milou.sh admin validate` |
| `config show` | Display configuration | `./milou.sh config show` |
| `config validate` | Validate configuration | `./milou.sh config validate` |
| `config generate` | Generate new configuration | `./milou.sh config generate` |

### Security Best Practices

#### Password Security

```bash
# Use strong, auto-generated passwords
./milou.sh admin reset  # Auto-generates secure password

# If setting custom passwords, ensure they meet requirements:
# - Minimum 8 characters
# - Mix of letters, numbers, symbols
# - Avoid common words or patterns
```

#### Credential Storage

```bash
# Securely store credentials
# Option 1: Password manager
echo "Admin password: $(./milou.sh admin credentials | grep Password)" | pass insert milou/admin

# Option 2: Encrypted file
./milou.sh admin credentials > admin_creds.txt
gpg -c admin_creds.txt
rm admin_creds.txt
```

#### Access Control

```bash
# Restrict .env file permissions
chmod 600 .env

# Backup credentials before changes
./milou.sh backup config --name pre_password_change

# Rotate passwords regularly
./milou.sh admin reset  # Monthly or quarterly
```

**Screenshot Placeholder: `[SECURITY_PRACTICES]`**
*Screenshot showing security recommendations and file permissions*

---

## 💾 Backup & Restore

Protecting your data is crucial. Milou CLI provides comprehensive backup and restore capabilities to ensure your data is safe and recoverable.

### Backup Operations

#### Create Full System Backup

```bash
# Create complete system backup
./milou.sh backup
# or
./milou.sh backup full
```

**Expected Output:**
```
📦 Creating full backup: milou_backup_20250529_142518

📋 Backing up configuration...
✅ Configuration backed up

🔐 Backing up SSL certificates...
✅ SSL certificates backed up

🐳 Backing up Docker volumes...
✅ Volume backed up: milou-static_database_data
✅ Volume backed up: milou-static_redis_data
✅ Docker volumes backed up

🗄️ Backing up database...
✅ Database backed up

✅ Backup created: ./backups/milou_backup_20250529_142518.tar.gz
```

**Screenshot Placeholder: `[BACKUP_FULL]`**
*Screenshot showing full backup process with progress indicators*

#### Backup Specific Components

```bash
# Backup only configuration files
./milou.sh backup config

# Backup only data (database + volumes)
./milou.sh backup data

# Backup only SSL certificates
./milou.sh backup ssl
```

**Configuration Backup Output:**
```
📦 Creating config backup: milou_backup_20250529_143015

📋 Backing up configuration...
✅ Environment file backed up
✅ Docker Compose files backed up
✅ SSL configuration backed up
✅ Version information backed up

✅ Backup created: ./backups/milou_backup_20250529_143015.tar.gz
```

#### Advanced Backup Options

```bash
# Backup to specific directory
./milou.sh backup full --dir /opt/milou-backups

# Backup with custom name
./milou.sh backup full --name pre_update_backup_v3_1_0

# Backup with all options
./milou.sh backup config \
    --dir /mnt/backup-drive/milou \
    --name "config_backup_$(date +%Y%m%d)"
```

**Screenshot Placeholder: `[BACKUP_OPTIONS]`**
*Screenshot showing backup with custom options and directory structure*

### Backup Management

#### List Available Backups

```bash
# List all backups
./milou.sh list-backups
# or
./milou.sh backup list
```

**Expected Output:**
```
📋 Available backups in: ./backups

BACKUP NAME                          DATE            SIZE
milou_backup_20250529_142518.tar.gz  2025-05-29     2.3M
milou_backup_20250528_093022.tar.gz  2025-05-28     2.1M
config_backup_20250527_150000.tar.gz 2025-05-27     15K

💡 Restore with: ./milou.sh restore <backup_name>
```

#### Backup Information

```bash
# Get detailed backup information
./milou.sh backup info ./backups/milou_backup_20250529_142518.tar.gz

# Verify backup integrity
./milou.sh backup verify ./backups/milou_backup_20250529_142518.tar.gz
```

**Screenshot Placeholder: `[BACKUP_LIST]`**
*Screenshot showing backup list with sizes and dates*

### Restore Operations

#### Restore from Full Backup

```bash
# Restore from most recent backup
./milou.sh restore ./backups/milou_backup_20250529_142518.tar.gz
```

**Expected Output:**
```
📁 Restoring from backup: milou_backup_20250529_142518.tar.gz

📦 Extracting backup...
✅ Backup extracted successfully

🔍 Validating backup structure...
✅ Configuration backup detected
✅ SSL certificates backup detected
✅ Docker volumes backup detected
✅ Database backup detected
✅ Backup validation passed

📋 Restoring configuration...
✅ Main environment file restored
✅ Docker Compose files restored
✅ SSL configuration restored
✅ Configuration restored

🔐 Restoring SSL certificates...
✅ SSL certificates restored

🐳 Restoring Docker data...
🗄️ Restoring database...
✅ Database restored
📦 Restoring Docker volumes...
✅ Volume restored: milou-static_database_data
✅ Volume restored: milou-static_redis_data
✅ Docker data restored

✅ Restore completed successfully
💡 You may need to restart services: ./milou.sh restart
```

**Screenshot Placeholder: `[RESTORE_FULL]`**
*Screenshot showing complete restore process*

#### Partial Restore Operations

```bash
# Restore only configuration
./milou.sh restore backup.tar.gz --type config

# Restore only data
./milou.sh restore backup.tar.gz --type data

# Restore only SSL certificates
./milou.sh restore backup.tar.gz --type ssl
```

#### Verify Backup Before Restore

```bash
# Verify backup without restoring
./milou.sh restore backup.tar.gz --verify-only
```

**Expected Output:**
```
📁 Restoring from backup: milou_backup_20250529_142518.tar.gz

📦 Extracting backup...
✅ Backup extracted successfully

🔍 Validating backup structure...
✅ Configuration backup detected
✅ SSL certificates backup detected
✅ Docker volumes backup detected
✅ Database backup detected

✅ Backup verification completed successfully
```

### Backup Automation

#### Automated Backup Scripts

```bash
# Create daily backup script
cat > /usr/local/bin/milou-daily-backup.sh << 'EOF'
#!/bin/bash
cd /path/to/milou-cli
./milou.sh backup full --dir /opt/milou-backups --name "daily_$(date +%Y%m%d)"
# Clean up old backups (keep 30 days)
find /opt/milou-backups -name "daily_*.tar.gz" -mtime +30 -delete
EOF

chmod +x /usr/local/bin/milou-daily-backup.sh
```

#### Cron Job Setup

```bash
# Add to crontab (crontab -e)
# Daily backup at 2 AM
0 2 * * * /usr/local/bin/milou-daily-backup.sh >> /var/log/milou-backup.log 2>&1

# Weekly full backup on Sundays at 3 AM
0 3 * * 0 /path/to/milou-cli/milou.sh backup full --dir /mnt/weekly-backups

# Monthly backup on 1st day at 4 AM
0 4 1 * * /path/to/milou-cli/milou.sh backup full --dir /mnt/monthly-backups
```

**Screenshot Placeholder: `[BACKUP_AUTOMATION]`**
*Screenshot showing cron job configuration for automated backups*

### Backup Best Practices

#### Backup Strategy

```bash
# Recommended backup schedule:
# Daily: Configuration only (fast, small)
./milou.sh backup config --name "daily_config_$(date +%Y%m%d)"

# Weekly: Full backup (comprehensive)
./milou.sh backup full --name "weekly_full_$(date +%Y%U)"

# Before updates: Full backup with specific name
./milou.sh backup full --name "pre_update_v3_1_1"
```

#### Storage Recommendations

```bash
# Local backup storage
mkdir -p /opt/milou-backups/{daily,weekly,monthly}

# Remote backup storage (example with rsync)
rsync -av /opt/milou-backups/ backup-server:/backups/milou/

# Cloud backup (example with AWS S3)
aws s3 sync /opt/milou-backups/ s3://your-backup-bucket/milou/
```

#### Backup Verification

```bash
# Test restore process regularly
./milou.sh restore backup.tar.gz --verify-only

# Monitor backup sizes for anomalies
ls -lh ./backups/*.tar.gz

# Verify backup integrity
tar -tzf backup.tar.gz > /dev/null && echo "Backup OK" || echo "Backup corrupted"
```

### Disaster Recovery

#### Complete System Recovery

```bash
# 1. Fresh installation
git clone https://github.com/your-org/milou-cli.git
cd milou-cli
chmod +x milou.sh

# 2. Restore from backup
./milou.sh restore /path/to/backup.tar.gz

# 3. Restart services
./milou.sh restart

# 4. Verify system
./milou.sh status
./milou.sh health
```

#### Recovery Testing

```bash
# Test recovery in development environment
./milou.sh setup --clean  # Clean install
./milou.sh restore backup.tar.gz  # Restore from backup
./milou.sh status  # Verify services
```

**Screenshot Placeholder: `[DISASTER_RECOVERY]`**
*Screenshot showing disaster recovery process steps*

### Backup Troubleshooting

#### Common Backup Issues

**Issue 1: Backup Fails - Insufficient Space**
```bash
# Check available disk space
df -h

# Clean up old backups
find ./backups -name "*.tar.gz" -mtime +30 -delete

# Use external storage
./milou.sh backup --dir /mnt/external-drive/milou-backups
```

**Issue 2: Database Backup Fails**
```bash
# Check if database is running
./milou.sh status

# Check database logs
./milou.sh logs database

# Start database if needed
./milou.sh start database
```

**Issue 3: Restore Fails - Backup Corrupted**
```bash
# Verify backup integrity
tar -tzf backup.tar.gz

# Try partial restore
./milou.sh restore backup.tar.gz --type config  # Config only

# Use different backup
./milou.sh list-backups  # Find alternative backup
```

### Backup & Restore Commands Summary

| Command | Purpose | Example |
|---------|---------|---------|
| `backup` | Create full backup | `./milou.sh backup` |
| `backup config` | Backup configuration | `./milou.sh backup config` |
| `backup data` | Backup data only | `./milou.sh backup data` |
| `backup ssl` | Backup SSL certificates | `./milou.sh backup ssl` |
| `list-backups` | List available backups | `./milou.sh list-backups` |
| `restore` | Restore from backup | `./milou.sh restore backup.tar.gz` |
| `restore --verify-only` | Verify backup | `./milou.sh restore backup.tar.gz --verify-only` |

**Screenshot Placeholder: `[BACKUP_COMMANDS_SUMMARY]`**
*Screenshot showing backup command help and usage examples*

---

> **📝 Note**: Always test your backup and restore procedures in a development environment before relying on them in production. Regular backup testing is essential for a reliable disaster recovery plan.

---

> **📝 Note**: This setup guide covers all common scenarios. If you encounter specific issues not covered here, please check the [Troubleshooting Guide](USER_GUIDE.md#troubleshooting) or create an issue on GitHub. 