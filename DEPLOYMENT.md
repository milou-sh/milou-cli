# Milou CLI - Deployment Guide

This guide explains how to prepare Milou CLI for GitHub release and customize it for your organization.

## 📋 Pre-Release Checklist

### 1. Update Repository URLs

Replace all placeholder URLs in the following files:

#### `install.sh`
```bash
# Update these lines
readonly REPO_URL="https://github.com/YOUR_ORG/milou-cli"
readonly REPO_RAW_URL="https://raw.githubusercontent.com/YOUR_ORG/milou-cli/main"

# Change to your actual repository
readonly REPO_URL="https://github.com/your-org/milou-cli"
readonly REPO_RAW_URL="https://raw.githubusercontent.com/your-org/milou-cli/main"
```

#### `README.md`
```bash
# Update installation URL in multiple places
curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/milou-cli/main/install.sh | bash

# Change to:
curl -fsSL https://raw.githubusercontent.com/your-org/milou-cli/main/install.sh | bash
```

#### Help documentation
Update any references to repository URLs in:
- `docs/USER_GUIDE.md`
- `install.sh` help text
- Any other documentation files

### 2. Configure Docker Registry

If using private Docker images, update the GitHub token requirements in:
- `src/_setup.sh` (GitHub token prompts)
- `.env.example` (GitHub token example)
- Documentation about private image access

### 3. Customize Branding

The ASCII logo is already updated. If you want to customize further:
- Update company/organization name in headers
- Modify color schemes in logging functions
- Update contact information in documentation

## 🚀 GitHub Release Process

### 1. Create Repository

```bash
# Create new repository on GitHub
# Clone and push your code
git remote add origin https://github.com/your-org/milou-cli.git
git branch -M main
git push -u origin main
```

### 2. Set Up GitHub Pages (Optional)

For documentation hosting:
1. Go to repository Settings → Pages
2. Select "Deploy from a branch"
3. Choose `main` branch and `/docs` folder

### 3. Create Release

```bash
# Tag your release
git tag -a v1.0.0 -m "Initial release of Milou CLI"
git push origin v1.0.0

# Create release on GitHub with release notes
```

### 4. Test Installation

Test your one-liner installation:

```bash
# Test from your repository
curl -fsSL https://raw.githubusercontent.com/your-org/milou-cli/main/install.sh | bash
```

## 🔒 Security Considerations

### 1. One-Line Installation Security

The `install.sh` script follows security best practices:

- ✅ Uses `set -euo pipefail` for error handling
- ✅ Validates prerequisites before installation
- ✅ Provides clear error messages
- ✅ Supports verification options
- ✅ Allows custom installation directories

### 2. Docker Image Security

If using private images:
- Ensure GitHub tokens have minimal required permissions (`read:packages`)
- Consider using GitHub App tokens for better security
- Document token rotation procedures

### 3. SSL/TLS Configuration

- Default configuration generates self-signed certificates
- Production deployments should use proper certificates
- Document Let's Encrypt integration if implemented

## 📚 Documentation Updates

### 1. Update Installation URLs

Search and replace in all documentation:
```bash
# Find all instances
grep -r "YOUR_ORG" .
grep -r "raw.githubusercontent.com" .

# Update systematically
```

### 2. Add Repository-Specific Information

Update the following in documentation:
- Issue reporting URLs
- Contribution guidelines
- Support channels
- License information

## 🧪 Testing Checklist

Before public release, test:

- [ ] One-line installation from GitHub
- [ ] Installation with custom directories
- [ ] Installation with different branches
- [ ] Setup wizard functionality
- [ ] All major CLI commands
- [ ] Documentation links and examples

## 📋 Post-Release Tasks

### 1. Monitor Installation

Watch for:
- GitHub issues related to installation
- Download/clone statistics
- User feedback on the installation process

### 2. Documentation

- Link to live documentation from README
- Create getting started videos if needed
- Maintain changelog for releases

### 3. Community

- Set up issue templates
- Create contributing guidelines
- Establish support channels

## 🔄 Update Process

For future releases:

1. Update version numbers in relevant files
2. Test installation script with new version
3. Update documentation
4. Create GitHub release with changelog
5. Notify users of updates

## 🛠️ Development Workflow

For organizations contributing to Milou CLI:

### 1. Fork and Branch
```bash
git checkout -b feature/your-feature
```

### 2. Test Locally
```bash
# Test installation script locally
bash install.sh --install-dir=/tmp/milou-test

# Test CLI functionality
cd /tmp/milou-test && ./milou.sh setup
```

### 3. Submit Pull Request
- Include clear description
- Test installation process
- Update documentation if needed

## 📞 Support

After deployment, provide clear support channels:
- GitHub Issues for bugs
- Documentation for common questions  
- Community channels for discussion

Remember to update all placeholder URLs and test thoroughly before your first public release! 