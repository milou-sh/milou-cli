# Milou CLI API Documentation

**Version 3.1.0** - Complete Modular Architecture

This document provides comprehensive API documentation for all public functions available in the Milou CLI modular architecture.

---

## 📋 **Module Overview**

The Milou CLI consists of 11 specialized modules, each with a specific responsibility:

| Module | Purpose | Lines | Key Functions |
|--------|---------|-------|---------------|
| `_core.sh` | Core utilities & logging | 714 | `milou_log`, `generate_secure_random`, `confirm_action` |
| `_validation.sh` | All validation functions | 694 | `validate_domain`, `validate_github_token`, `validate_docker_access` |
| `_docker.sh` | Docker operations | 895 | `docker_start`, `docker_status`, `docker_health_check` |
| `_ssl.sh` | SSL management | 992 | `ssl_setup`, `ssl_generate_self_signed`, `ssl_validate` |
| `_config.sh` | Configuration management | 914 | `config_generate`, `config_validate`, `config_migrate` |
| `_setup.sh` | Setup orchestration | 1,142 | `setup_main`, `setup_interactive`, `setup_validate_environment` |
| `_backup.sh` | Backup operations | 792 | `backup_create`, `backup_restore`, `backup_list` |
| `_user.sh` | User management | 854 | `user_create`, `user_reset_password`, `user_manage_permissions` |
| `_update.sh` | Update operations | 832 | `milou_self_update`, `update_check_version`, `update_apply` |
| `_admin.sh` | Admin operations | 591 | `admin_show_credentials`, `admin_reset_password`, `admin_manage` |
| `milou` | Main CLI entry point | 563 | `main`, `show_help`, `handle_command` |

---

## 🔧 **Core Module (`_core.sh`)**

### **Logging Functions**

#### `milou_log(level, message, [context])`
Centralized logging function with multiple levels.

**Parameters:**
- `level`: Log level (DEBUG, INFO, WARN, ERROR, SUCCESS)
- `message`: Log message
- `context`: Optional context for debugging

**Example:**
```bash
milou_log "INFO" "Starting setup process"
milou_log "ERROR" "Docker not found" "setup"
milou_log "SUCCESS" "Setup completed successfully"
```

### **Random Generation Functions**

#### `generate_secure_random([length])`
Generate cryptographically secure random strings.

**Parameters:**
- `length`: Optional length (default: 16)

**Returns:** Secure random string

**Example:**
```bash
password=$(generate_secure_random 32)
token=$(generate_secure_random)
```

### **UI Functions**

#### `confirm_action(message, [default])`
Interactive confirmation prompt with force mode support.

**Parameters:**
- `message`: Confirmation message
- `default`: Default response (y/n)

**Returns:** 0 for yes, 1 for no

**Example:**
```bash
if confirm_action "Delete all data?"; then
    echo "Confirmed"
fi
```

#### `prompt_user(message, [default])`
Interactive user input prompt.

**Parameters:**
- `message`: Prompt message
- `default`: Default value

**Returns:** User input or default

**Example:**
```bash
domain=$(prompt_user "Enter domain" "localhost")
```

---

## ✅ **Validation Module (`_validation.sh`)**

### **Domain Validation**

#### `validate_domain(domain)`
Validate domain name format and accessibility.

**Parameters:**
- `domain`: Domain to validate

**Returns:** 0 if valid, 1 if invalid

**Example:**
```bash
if validate_domain "example.com"; then
    echo "Valid domain"
fi
```

#### `validate_email(email)`
Validate email address format.

**Parameters:**
- `email`: Email to validate

**Returns:** 0 if valid, 1 if invalid

### **GitHub Integration**

#### `validate_github_token(token)`
Validate GitHub personal access token format and permissions.

**Parameters:**
- `token`: GitHub token to validate

**Returns:** 0 if valid, 1 if invalid

#### `test_github_authentication(token)`
Test GitHub token authentication with API call.

**Parameters:**
- `token`: GitHub token to test

**Returns:** 0 if authenticated, 1 if failed

### **Docker Validation**

#### `validate_docker_access()`
Validate Docker daemon access and permissions.

**Returns:** 0 if accessible, 1 if failed

#### `validate_docker_resources()`
Check Docker system resources (memory, disk space).

**Returns:** 0 if sufficient, 1 if insufficient

#### `validate_docker_compose_config(config_file)`
Validate Docker Compose configuration file.

**Parameters:**
- `config_file`: Path to docker-compose.yml

**Returns:** 0 if valid, 1 if invalid

### **Environment Validation**

#### `validate_environment([context])`
Comprehensive environment validation.

**Parameters:**
- `context`: Validation context (minimal, production, all)

**Returns:** 0 if valid, 1 if invalid

---

## 🐳 **Docker Module (`_docker.sh`)**

### **Service Management**

#### `docker_start([service])`
Start Docker services.

**Parameters:**
- `service`: Optional specific service name

**Returns:** 0 if successful, 1 if failed

**Example:**
```bash
docker_start              # Start all services
docker_start "nginx"      # Start specific service
```

#### `docker_stop([service])`
Stop Docker services.

**Parameters:**
- `service`: Optional specific service name

#### `docker_restart([service])`
Restart Docker services.

**Parameters:**
- `service`: Optional specific service name

#### `docker_status([service])`
Get Docker service status.

**Parameters:**
- `service`: Optional specific service name

**Returns:** Service status information

### **Health Monitoring**

#### `docker_health_check([service])`
Perform health check on services.

**Parameters:**
- `service`: Optional specific service name

**Returns:** 0 if healthy, 1 if unhealthy

#### `docker_comprehensive_health()`
Comprehensive health check with detailed reporting.

**Returns:** Detailed health status

### **Utility Functions**

#### `docker_logs([service])`
View Docker service logs.

**Parameters:**
- `service`: Optional specific service name

#### `docker_shell(service)`
Open shell in Docker container.

**Parameters:**
- `service`: Service name

---

## 🔒 **SSL Module (`_ssl.sh`)**

### **SSL Setup**

#### `ssl_setup([mode])`
Main SSL setup function.

**Parameters:**
- `mode`: SSL mode (self-signed, letsencrypt, existing)

**Returns:** 0 if successful, 1 if failed

#### `ssl_generate_self_signed(domain, [additional_domains])`
Generate self-signed SSL certificates.

**Parameters:**
- `domain`: Primary domain
- `additional_domains`: Optional additional domains

**Returns:** 0 if successful, 1 if failed

### **SSL Management**

#### `ssl_status()`
Check SSL certificate status.

**Returns:** Certificate status information

#### `ssl_validate([cert_path])`
Validate SSL certificates.

**Parameters:**
- `cert_path`: Optional certificate path

**Returns:** 0 if valid, 1 if invalid

#### `ssl_cleanup()`
Clean up SSL certificates and configuration.

**Returns:** 0 if successful, 1 if failed

---

## ⚙️ **Configuration Module (`_config.sh`)**

### **Configuration Generation**

#### `config_generate([mode])`
Generate system configuration.

**Parameters:**
- `mode`: Configuration mode (interactive, automated)

**Returns:** 0 if successful, 1 if failed

#### `config_validate([config_file])`
Validate configuration file.

**Parameters:**
- `config_file`: Optional configuration file path

**Returns:** 0 if valid, 1 if invalid

### **Configuration Management**

#### `config_backup_single(config_file)`
Backup single configuration file.

**Parameters:**
- `config_file`: Configuration file to backup

**Returns:** 0 if successful, 1 if failed

#### `config_migrate([from_version])`
Migrate configuration between versions.

**Parameters:**
- `from_version`: Optional source version

**Returns:** 0 if successful, 1 if failed

---

## 🚀 **Setup Module (`_setup.sh`)**

### **Main Setup Functions**

#### `setup_main([options])`
Main setup orchestration function.

**Parameters:**
- `options`: Setup options (--clean, --force, etc.)

**Returns:** 0 if successful, 1 if failed

#### `setup_interactive()`
Interactive setup wizard.

**Returns:** 0 if successful, 1 if failed

### **Setup Validation**

#### `setup_validate_environment()`
Validate environment before setup.

**Returns:** 0 if valid, 1 if invalid

#### `setup_check_prerequisites()`
Check system prerequisites.

**Returns:** 0 if satisfied, 1 if missing

---

## 💾 **Backup Module (`_backup.sh`)**

### **Backup Operations**

#### `backup_create([name])`
Create system backup.

**Parameters:**
- `name`: Optional backup name

**Returns:** 0 if successful, 1 if failed

#### `backup_restore(backup_file)`
Restore from backup.

**Parameters:**
- `backup_file`: Backup file to restore

**Returns:** 0 if successful, 1 if failed

#### `backup_list()`
List available backups.

**Returns:** List of backup files

### **Backup Management**

#### `backup_cleanup([days])`
Clean up old backups.

**Parameters:**
- `days`: Optional retention days (default: 30)

**Returns:** 0 if successful, 1 if failed

---

## 👤 **User Module (`_user.sh`)**

### **User Management**

#### `user_create(username, [email])`
Create new user account.

**Parameters:**
- `username`: Username
- `email`: Optional email address

**Returns:** 0 if successful, 1 if failed

#### `user_reset_password(username)`
Reset user password.

**Parameters:**
- `username`: Username

**Returns:** 0 if successful, 1 if failed

#### `user_manage_permissions(username, action)`
Manage user permissions.

**Parameters:**
- `username`: Username
- `action`: Permission action (grant, revoke)

**Returns:** 0 if successful, 1 if failed

---

## 🔄 **Update Module (`_update.sh`)**

### **Self-Update Functions**

#### `milou_self_update([version])`
Update Milou CLI to latest or specific version.

**Parameters:**
- `version`: Optional specific version

**Returns:** 0 if successful, 1 if failed

#### `update_check_version()`
Check for available updates.

**Returns:** Version information

#### `update_apply(version)`
Apply specific update.

**Parameters:**
- `version`: Version to apply

**Returns:** 0 if successful, 1 if failed

---

## 👑 **Admin Module (`_admin.sh`)**

### **Admin Operations**

#### `admin_show_credentials()`
Display admin credentials.

**Returns:** Admin credential information

#### `admin_reset_password()`
Reset admin password.

**Returns:** 0 if successful, 1 if failed

#### `admin_manage([action])`
General admin management.

**Parameters:**
- `action`: Admin action

**Returns:** 0 if successful, 1 if failed

---

## 🎯 **Main Entry Point (`milou`)**

### **CLI Functions**

#### `main(args...)`
Main CLI entry point.

**Parameters:**
- `args`: Command line arguments

**Returns:** Exit code

#### `show_help([command])`
Display help information.

**Parameters:**
- `command`: Optional specific command

#### `handle_command(command, args...)`
Handle specific command.

**Parameters:**
- `command`: Command to handle
- `args`: Command arguments

**Returns:** Command exit code

---

## 🔗 **Module Dependencies**

### **Dependency Graph**
```
milou (main entry point)
├── _core.sh (required by all modules)
├── _validation.sh (depends on _core.sh)
├── _docker.sh (depends on _core.sh, _validation.sh)
├── _ssl.sh (depends on _core.sh, _validation.sh)
├── _config.sh (depends on _core.sh, _validation.sh)
├── _setup.sh (depends on all modules)
├── _backup.sh (depends on _core.sh, _docker.sh)
├── _user.sh (depends on _core.sh, _validation.sh)
├── _update.sh (depends on _core.sh, _validation.sh)
└── _admin.sh (depends on _core.sh, _user.sh)
```

### **Loading Order**
1. `_core.sh` - Always loaded first
2. `_validation.sh` - Loaded by most modules
3. Feature modules loaded as needed
4. `_setup.sh` - Loads all dependencies

---

## 🛠️ **Usage Examples**

### **Basic Module Usage**
```bash
# Load core module
source "src/_core.sh"

# Use logging
milou_log "INFO" "Starting operation"

# Generate secure password
password=$(generate_secure_random 32)
```

### **Validation Example**
```bash
# Load validation module (auto-loads core)
source "src/_validation.sh"

# Validate domain
if validate_domain "$domain"; then
    milou_log "SUCCESS" "Domain is valid"
else
    milou_log "ERROR" "Invalid domain"
    exit 1
fi
```

### **Docker Operations**
```bash
# Load docker module
source "src/_docker.sh"

# Start services
if docker_start; then
    milou_log "SUCCESS" "Services started"
    docker_status
fi
```

---

## 📚 **Best Practices**

### **Module Loading**
- Always load `_core.sh` first
- Use module auto-loading when possible
- Check return codes for all operations

### **Error Handling**
- Use `milou_log` for all logging
- Return appropriate exit codes
- Provide meaningful error messages

### **Function Naming**
- Use module prefix for public functions
- Use descriptive names
- Follow consistent naming patterns

### **Documentation**
- Document all public functions
- Include parameter descriptions
- Provide usage examples

---

## 🔍 **Troubleshooting**

### **Module Loading Issues**
```bash
# Check if module exists
if [[ ! -f "src/_core.sh" ]]; then
    echo "Core module not found"
    exit 1
fi

# Load with error checking
if ! source "src/_core.sh"; then
    echo "Failed to load core module"
    exit 1
fi
```

### **Function Availability**
```bash
# Check if function exists
if declare -f milou_log >/dev/null; then
    milou_log "INFO" "Function available"
else
    echo "Function not available"
fi
```

### **Debugging**
```bash
# Enable debug logging
export MILOU_DEBUG=1

# Use debug logging
milou_log "DEBUG" "Debug information" "context"
```

---

This API documentation provides comprehensive coverage of all public functions available in the Milou CLI modular architecture. For implementation details, refer to the individual module source files in the `src/` directory. 