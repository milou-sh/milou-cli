# Milou CLI Changelog

All notable changes to this project will be documented in this file.

## [3.1.1] - 2024-12-19

### 🚀 Added
- **One-Line Installation**: Added `install.sh` script for easy installation via `curl | bash`
- **New ASCII Art Logo**: Updated from text-based logo to custom Milou ASCII art
- **Shell Integration**: Automatic setup of `milou` command alias
- **Installation Options**: Support for custom installation directories and branches
- **Release Tools**: Added `scripts/prepare-release.sh` for GitHub release preparation
- **Installation Testing**: Added `scripts/test-install.sh` for local testing

### ✨ Enhanced
- **Setup Wizard**: Now displays the new Milou logo during interactive setup
- **Documentation**: Comprehensive installation guide with one-liner examples
- **User Experience**: Streamlined installation process from GitHub to running setup

### 🔧 Technical Changes
- **`install.sh`**: New one-line installer with comprehensive options
- **`src/milou`**: Updated `show_header()` function with new ASCII art
- **`src/_setup.sh`**: Added `setup_show_logo()` function for setup wizard
- **`README.md`**: Updated with prominent one-line installation section
- **`docs/USER_GUIDE.md`**: Updated installation documentation

### 📦 Installation Options
```bash
# Basic installation
curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/milou-cli/main/install.sh | bash

# Custom directory
MILOU_INSTALL_DIR=/opt/milou curl -fsSL ... | bash

# Development branch
MILOU_BRANCH=develop curl -fsSL ... | bash

# Quiet installation
curl -fsSL ... | bash -s -- --quiet
```

### 🛠️ Developer Tools
- **`scripts/prepare-release.sh`**: Automated URL replacement for GitHub releases
- **`scripts/test-install.sh`**: Local installation testing
- **`DEPLOYMENT.md`**: Comprehensive deployment guide

### 📋 Migration Notes
- Existing installations continue to work unchanged
- New installations benefit from streamlined setup process
- Manual installation method still available for advanced users

### 🔒 Security
- Installation script follows security best practices
- Prerequisites validation before installation
- Support for custom installation directories
- Clear error messages and validation

## [3.1.0] - Previous Release
- Modular architecture with consolidated modules
- Enterprise-grade configuration management
- Comprehensive backup and restore
- Advanced Docker management
- SSL certificate automation 