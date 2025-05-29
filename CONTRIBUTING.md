# Contributing to Milou CLI

Thank you for your interest in contributing to Milou CLI! This document provides guidelines for contributing to the project.

## 🚀 Getting Started

### Prerequisites

- **Bash 4.0+**: Modern bash features required
- **Docker 20.10+**: For container operations
- **Docker Compose 2.0+**: For service orchestration
- **Git**: Version control

### Development Setup

```bash
# Clone the repository
git clone <repository-url>
cd milou-cli

# Make scripts executable
chmod +x milou.sh
chmod +x scripts/dev/*.sh
chmod +x tests/unit/*.sh

# Copy environment template
cp .env.example .env

# Run development setup
./scripts/dev/test-setup.sh

# Verify installation
./milou.sh --help
```

## 🏗️ Architecture

Milou CLI follows a modular architecture with clear separation of concerns:

```
src/
├── milou              # Main CLI entry point
├── _core.sh           # Core utilities & logging
├── _validation.sh     # Validation functions
├── _docker.sh         # Docker operations
├── _ssl.sh            # SSL management
├── _config.sh         # Configuration management
├── _setup.sh          # Setup operations
├── _backup.sh         # Backup operations
├── _user.sh           # User management
├── _update.sh         # Update operations
└── _admin.sh          # Admin operations
```

## 📝 Coding Standards

### Shell Script Standards

- Use `#!/usr/bin/env bash` shebang
- Set `set -euo pipefail` for strict error handling
- Follow consistent naming conventions
- Document all public functions
- Use `milou_log` for all logging operations

### Function Documentation Template

```bash
#
# Function: function_name
# Description: Brief description of what the function does
# Parameters:
#   $1 - parameter_name: Description of parameter
#   $2 - optional_param: Optional parameter description
# Returns:
#   0 - Success
#   1 - Error condition
# Example:
#   function_name "value1" "value2"
#
function_name() {
    local param1="$1"
    local param2="${2:-default_value}"
    
    # Function implementation
}
```

## 🧪 Testing

### Running Tests

```bash
# Run specific module tests
./tests/unit/test-core.sh
./tests/unit/test-validation.sh

# Run all unit tests
for test in tests/unit/test-*.sh; do
    echo "Running $test..."
    "$test"
done
```

### Writing Tests

- Create test files in `tests/unit/` following the pattern `test-module-name.sh`
- Use the test framework in `tests/helpers/test-framework.sh`
- Include setup and teardown functions
- Test both success and failure cases

## 🔄 Development Workflow

### Making Changes

1. **Create a branch**: `git checkout -b feature/your-feature-name`
2. **Make changes**: Follow coding standards and document your code
3. **Test changes**: Run relevant tests to ensure functionality
4. **Commit changes**: Use clear, descriptive commit messages
5. **Push branch**: `git push origin feature/your-feature-name`
6. **Create pull request**: Submit for review

### Commit Message Format

```
type(scope): brief description

Longer description if needed

- List specific changes
- Reference issues if applicable
```

**Types**: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

## 🐛 Reporting Issues

When reporting issues, please include:

- **Environment**: OS, Docker version, Bash version
- **Steps to reproduce**: Clear steps to reproduce the issue
- **Expected behavior**: What should happen
- **Actual behavior**: What actually happens
- **Error messages**: Include full error messages and logs
- **Configuration**: Relevant configuration (remove sensitive data)

## 📚 Documentation

- Update documentation when adding new features
- Keep README.md up to date
- Document breaking changes
- Add examples for new functionality

## 🎯 Pull Request Guidelines

### Before Submitting

- [ ] Code follows the style guidelines
- [ ] Self-review of the code
- [ ] Code is documented
- [ ] Tests pass
- [ ] No merge conflicts

### Pull Request Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Tests pass
- [ ] Manual testing completed

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] No breaking changes (or documented)
```

## 🤝 Code of Conduct

- Be respectful and inclusive
- Focus on constructive feedback
- Help others learn and grow
- Follow the project's goals and vision

## 📞 Getting Help

- **Documentation**: Check `docs/` directory
- **Issues**: Create a GitHub issue
- **Questions**: Use GitHub discussions

## 🎉 Recognition

Contributors will be recognized in:
- CONTRIBUTORS.md file
- Release notes for significant contributions
- Project documentation

Thank you for contributing to Milou CLI! 🚀 