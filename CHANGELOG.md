# Milou CLI Changelog

All notable changes to this project will be documented in this file.

## [3.1.3] - 2024-12-19

### 🏠 **Installation Directory Improvements**
- **Smart Directory Detection**: Installation now defaults to /home/ instead of /root/
- **Multi-user Support**: When running as root, detects first regular user and installs to their home
- **Interactive Directory Selection**: Users can choose custom installation directories with recommendations
- **Proper Ownership**: Automatically sets correct file ownership for multi-user scenarios

### 🎯 **Enhanced Error Handling**
- **Interactive Recovery**: When errors occur, users get actionable choices (retry, exit, continue)
- **Contextual Suggestions**: Each error includes specific solutions based on the problem type
- **Multi-package Manager Support**: Automatic detection and instructions for apt, yum, dnf, brew, pacman
- **Graceful Fallbacks**: Non-interactive mode handles errors appropriately for automation

### 🔧 **Installation Script Enhancements**
- **User-Friendly Prompts**: Clear recommendations for different installation scenarios
- **Cross-Shell Support**: Improved shell integration for bash, zsh, fish with proper ownership
- **Better Documentation**: Enhanced help text with directory selection guidance
- **Development Support**: Special handling for development installations

## [3.1.2] - 2024-12-19

### 🎯 **Major User Experience Improvements**
- **Fixed BASH_SOURCE Error**: Resolved "unbound variable" error in install.sh when run via curl | bash
- **Fixed Email Validation Loop**: Resolved infinite loop in setup wizard when entering localhost emails
- **Compact ASCII Art**: Replaced large ASCII art with terminal-friendly version across all components
- **Enhanced Installation Flow**: Dramatically improved user experience from discovery to production

### 🐛 **Critical Bug Fixes**
- **Email Validation**: Fixed infinite loop in setup wizard caused by overly strict email regex
- **Localhost Support**: Email validation now properly accepts admin@localhost and similar local emails
- **Script Execution**: Fixed BASH_SOURCE unbound variable error in curl | bash execution
- **Core Validation**: Improved email validation function to handle development scenarios

### ✨ **Installation Script Enhancements**
- **Better Error Handling**: Improved error messages with clear solutions and troubleshooting guidance
- **Professional Formatting**: Clean, colored output with progress indicators and status messages
- **Validation Improvements**: Comprehensive checks with helpful error recovery suggestions
- **User Experience**: Streamlined flow from download to running setup

### 📚 **Documentation**
- **User Experience Guide**: Added comprehensive docs/USER_EXPERIENCE.md with detailed setup flows
- **Installation Examples**: Real-world scenarios with screenshots and step-by-step instructions
- **Troubleshooting Guide**: Common issues and solutions for different environments

### 🔧 **Technical Improvements**
- **Modular Architecture**: Consolidated codebase with clean separation of concerns
- **Enhanced Logging**: Better debug output and user-friendly messages
- **Cross-platform**: Improved compatibility across different Linux distributions
- **Error Recovery**: Robust error handling with user choice prompts

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