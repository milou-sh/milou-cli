# Milou CLI - State-of-the-Art Infrastructure Management

Comprehensive CLI tool for deploying and managing Milou, the AI Pentest Orchestration platform.

## Quick Start

```bash
# Clone the repository
git clone <repository-url>
cd milou-cli

# Development mode (uses locally built images)
./milou.sh setup --dev

# Production mode (uses registry images)
./milou.sh setup
```

## Development Setup

The CLI supports two development approaches:

### 1. Local Development with Override (Recommended)

Uses `docker-compose.local.yml` as an override file to replace registry images with locally built images.

```bash
# Build local images and setup development environment
./milou.sh setup --dev

# This automatically:
# 1. Builds local Docker images if needed
# 2. Uses docker-compose.local.yml to override image sources
# 3. Starts services with local images
```

**Docker Compose Files:**
- `static/docker-compose.yml` - Main production compose file
- `static/docker-compose.local.yml` - Development override (uses local images)

### 2. Full Development Environment

For active development with source mounting and hot-reload, use the development compose file directly in your main project:

```bash
cd /path/to/milou_fresh
docker compose -f docker-compose.dev.yml up
```

## Architecture

The setup uses a layered Docker Compose approach:

1. **Base Layer**: `docker-compose.yml` - Production services with registry images
2. **Development Override**: `docker-compose.local.yml` - Replaces image sources with local builds
3. **Development Standalone**: `docker-compose.dev.yml` (in main project) - Full dev environment with source mounting

## Key Features

- 🚀 Automated setup and configuration
- 🔧 Development mode with local image building
- 🔒 SSL certificate management
- 🌐 Domain configuration
- 🔐 Secure credential generation
- 📊 Comprehensive health monitoring
- 🛡️ Security checks and validation

## Commands

```bash
# Setup and configuration
./milou.sh setup [--dev] [--token TOKEN]

# Service management
./milou.sh start|stop|restart|status

# Monitoring and debugging
./milou.sh logs [service]
./milou.sh health
./milou.sh shell <service>

# Utilities
./milou.sh ssl-manager
./milou.sh security-check
./milou.sh backup|restore
```

## Development Workflow

1. **Initial Setup**: `./milou.sh setup --dev`
2. **Build Local Images**: Done automatically or manually with build scripts
3. **Start Development**: Services use local images via override
4. **Active Development**: Use standalone dev compose in main project for source mounting
5. **Testing**: `./milou.sh health` and `./milou.sh logs`

## Configuration

All configuration is stored in `.env` file with secure defaults:
- Database credentials (auto-generated)
- Security keys and secrets
- Domain and SSL settings
- Service-specific configurations

For detailed documentation, see the individual script files and inline help. 