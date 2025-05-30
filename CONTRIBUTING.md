# Contributing to Milou CLI

## 🎉 Welcome Contributors!

Thank you for your interest in contributing to the Milou CLI project! This document provides comprehensive guidelines for contributing to our enterprise-grade, state-driven CLI system.

## 📋 Quick Start

1. **Fork the repository** on GitHub
2. **Clone your fork** locally
3. **Create a feature branch** from `main`
4. **Make your changes** following our standards
5. **Run the test suite** to ensure quality
6. **Submit a pull request** with clear description

## 🏗️ Project Architecture

### Understanding the Codebase

The Milou CLI is built with a **state-driven, modular architecture**:

```
src/
├── _core.sh          # Foundation utilities and logging
├── _state.sh         # Smart state detection system  
├── _docker.sh        # Docker operations management
├── _config.sh        # Configuration and credentials
├── _validation.sh    # System validation
├── _setup.sh         # Installation procedures
├── _error_recovery.sh # Enterprise error recovery
├── _update.sh        # Smart update system
├── _backup.sh        # Backup and disaster recovery
├── _ssl.sh           # SSL certificate management
├── _user.sh          # User management
└── _admin.sh         # Administrative functions
```

### Key Design Principles

1. **State-Driven Operations**: All commands adapt based on detected system state
2. **Fail-Safe by Design**: Data preservation and automatic rollback
3. **Enterprise-Grade Recovery**: Comprehensive error handling and recovery
4. **Modular Architecture**: Clean separation of concerns

## 🎯 Development Standards

### Code Quality Requirements

- **Test Coverage**: ≥80% (currently 96%)
- **Function Coverage**: All new functions must have tests
- **Documentation**: All public functions must be documented
- **Error Handling**: Comprehensive error handling required
- **Performance**: Must meet established benchmarks

### Shell Scripting Standards

#### 1. **File Structure**
```bash
#!/bin/bash

# =============================================================================
# Module Name - Description
# Purpose and functionality explanation
# =============================================================================

# Module guard to prevent multiple loading
if [[ "${MODULE_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly MODULE_LOADED="true"

# Dependencies
source "${BASH_SOURCE[0]%/*}/_core.sh" || return 1

# Module implementation...

# Exports
export -f function_name
```

#### 2. **Function Standards**
```bash
# Function documentation template
function_name() {
    local param1="${1:-default}"
    local param2="${2:-}"
    
    # Validate inputs
    if [[ -z "$param1" ]]; then
        milou_log "ERROR" "Parameter 1 is required"
        return 1
    fi
    
    # Log function entry
    milou_log "DEBUG" "function_name called with: $param1, $param2"
    
    # Implementation...
    
    # Return appropriate exit code
    return 0
}
```

#### 3. **Error Handling Standards**
```bash
# Always use proper error handling
if ! command_that_might_fail; then
    milou_log "ERROR" "Command failed: specific error description"
    return 1
fi

# Use safe operations wrapper for critical functions
safe_operation \
    "risky_operation_function" \
    "cleanup_function" \
    "Human readable operation description"
```

#### 4. **Logging Standards**
```bash
# Use appropriate log levels
milou_log "STEP" "Starting major operation"
milou_log "INFO" "General information"
milou_log "DEBUG" "Detailed debugging info"
milou_log "WARN" "Warning condition"
milou_log "ERROR" "Error condition"
milou_log "SUCCESS" "Operation completed successfully"
```

## 🧪 Testing Requirements

### Test Structure

All tests must follow our established pattern:

```bash
#!/bin/bash
# Test file for module_name

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_ROOT/tests/helpers/test-framework.sh"
source "$PROJECT_ROOT/src/_core.sh"
source "$PROJECT_ROOT/src/_module.sh"

test_function_name() {
    test_log "INFO" "Testing function_name..."
    
    # Test function exists
    assert_function_exists "function_name" "Function should be exported"
    
    # Test functionality
    if function_name "test_param"; then
        test_log "SUCCESS" "Function executed successfully"
    else
        test_log "ERROR" "Function failed"
        return 1
    fi
    
    test_log "SUCCESS" "Function test completed"
}

# Main test runner
main() {
    echo "🧪 Module Tests"
    echo "==============="
    
    test_function_name
    
    echo "✅ All tests completed"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

### Running Tests

```bash
# Run all tests
./tests/run-all-tests.sh

# Run specific module tests  
./tests/unit/test-module-name.sh

# Run tests with coverage analysis
./tests/run-all-tests.sh --coverage
```

### Test Requirements

- **Function Tests**: Every exported function must have tests
- **Error Handling Tests**: Test failure scenarios
- **Integration Tests**: Test module interactions
- **Performance Tests**: Ensure performance standards
- **Edge Case Tests**: Test boundary conditions

## 📚 Documentation Standards

### Code Documentation

#### 1. **Function Documentation**
```bash
# Brief description of what the function does
# 
# Parameters:
#   $1 - parameter_name: Description of parameter
#   $2 - parameter_name: Description of parameter (optional)
# 
# Returns:
#   0 - Success
#   1 - Failure condition description
# 
# Example:
#   function_name "value1" "value2"
function_name() {
    # Implementation...
}
```

#### 2. **Module Documentation**
Each module should have comprehensive header documentation explaining:
- Purpose and responsibility
- Key functions and exports
- Dependencies and interactions
- Usage examples

### API Documentation

When adding new functions to modules:
1. Update `docs/API_REFERENCE.md`
2. Include function signature and parameters
3. Provide usage examples
4. Document return codes and error conditions

## 🚀 Contribution Workflow

### 1. **Setting Up Development Environment**

```bash
# Clone your fork
git clone https://github.com/yourusername/milou-cli.git
cd milou-cli

# Set up upstream remote
git remote add upstream https://github.com/milou-sh/milou-cli.git

# Install development dependencies (if any)
./scripts/dev/setup-dev-environment.sh
```

### 2. **Creating a Feature Branch**

```bash
# Create and switch to feature branch
git checkout -b feature/your-feature-name

# Or for bug fixes
git checkout -b fix/issue-description
```

### 3. **Making Changes**

- Follow all coding standards outlined above
- Write tests for new functionality
- Update documentation as needed
- Ensure all quality gates pass

### 4. **Testing Your Changes**

```bash
# Run full test suite
./tests/run-all-tests.sh

# Check code quality
shellcheck src/*.sh

# Test CLI functionality
./milou.sh --help
./milou.sh status
```

### 5. **Committing Changes**

#### Commit Message Format
```
type(scope): brief description

Detailed explanation of changes if needed.

- Bullet points for multiple changes
- Reference issues with #issue-number
- Include breaking changes with BREAKING CHANGE:
```

#### Commit Types
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `test`: Test additions or modifications
- `refactor`: Code refactoring
- `perf`: Performance improvements
- `style`: Code style changes

#### Example Commits
```bash
git commit -m "feat(backup): add incremental backup support

- Implement incremental backup detection
- Add base backup selection logic
- Include change detection for optimization
- Add comprehensive test coverage

Closes #123"
```

### 6. **Submitting Pull Request**

#### Pull Request Template
```markdown
## Description
Brief description of changes and motivation.

## Type of Change
- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update

## Testing
- [ ] All existing tests pass
- [ ] New tests added for new functionality
- [ ] Manual testing completed

## Quality Checklist
- [ ] Code follows established style guidelines
- [ ] Self-review of code completed
- [ ] Code is documented appropriately
- [ ] Performance impact considered

## Related Issues
Closes #issue-number
```

## 🎯 Types of Contributions

### 🐛 **Bug Fixes**
- Always include test that reproduces the bug
- Ensure fix doesn't break existing functionality
- Update documentation if behavior changes

### ✨ **New Features**
- Discuss major features in issues first
- Follow established architecture patterns
- Include comprehensive tests and documentation
- Consider backward compatibility

### 📚 **Documentation**
- API documentation updates
- User guide improvements
- Architecture documentation
- Code comments and inline documentation

### 🧪 **Testing**
- Additional test coverage
- Performance benchmarks
- Integration tests
- Error scenario testing

### 🔧 **Infrastructure**
- Development tooling improvements
- CI/CD enhancements
- Quality automation
- Build process improvements

## 🔍 Code Review Process

### Review Criteria

1. **Functionality**: Does the code work as intended?
2. **Quality**: Meets coding standards and best practices?
3. **Testing**: Adequate test coverage and quality?
4. **Documentation**: Properly documented changes?
5. **Performance**: No performance regressions?
6. **Security**: No security vulnerabilities introduced?

### Review Process

1. **Automated Checks**: All CI checks must pass
2. **Peer Review**: At least one approved review required
3. **Maintainer Review**: Core maintainer approval for significant changes
4. **Quality Gates**: All quality metrics must be maintained

## 🚨 Security Guidelines

### Security Best Practices

1. **Input Validation**: Sanitize all user inputs
2. **Credential Handling**: Never log sensitive information
3. **File Permissions**: Proper permissions for sensitive files
4. **Error Messages**: Don't expose sensitive information in errors
5. **Dependencies**: Keep dependencies updated and secure

### Reporting Security Issues

- **DO NOT** create public issues for security vulnerabilities
- Email security reports to: security@milou.sh
- Include detailed description and reproduction steps
- Allow reasonable time for fix before public disclosure

## 🏆 Recognition

### Contributors

We recognize contributors in multiple ways:
- Contributors section in README
- Release notes acknowledgments
- Special recognition for significant contributions
- Opportunity to become maintainers

### Becoming a Maintainer

Regular contributors may be invited to become maintainers based on:
- Consistent high-quality contributions
- Understanding of project architecture
- Community involvement and helpfulness
- Commitment to project goals

## 📞 Getting Help

### Communication Channels

- **GitHub Issues**: Bug reports and feature requests
- **GitHub Discussions**: General questions and discussions
- **Documentation**: Comprehensive docs in `/docs`
- **API Reference**: Detailed API documentation

### Development Support

- Check existing issues and discussions first
- Provide minimal reproduction cases for bugs
- Include system information and error logs
- Be respectful and constructive in communications

## 📋 Development Checklist

Before submitting your contribution:

### Code Quality
- [ ] Code follows style guidelines
- [ ] All functions are documented
- [ ] Error handling is comprehensive
- [ ] Performance standards are met
- [ ] Security considerations addressed

### Testing
- [ ] All tests pass
- [ ] New functionality has tests
- [ ] Edge cases are tested
- [ ] Performance tests included if relevant
- [ ] Manual testing completed

### Documentation
- [ ] API documentation updated
- [ ] User-facing changes documented
- [ ] Code comments added where needed
- [ ] README updated if necessary

### Quality Gates
- [ ] Test coverage maintained (≥80%)
- [ ] Performance benchmarks met
- [ ] No new security vulnerabilities
- [ ] Backward compatibility preserved

## 🎉 Thank You!

Your contributions help make Milou CLI better for everyone. Whether you're fixing bugs, adding features, improving documentation, or helping other users, every contribution is valued and appreciated.

Together, we're building an enterprise-grade CLI that sets the standard for reliability, usability, and maintainability.

---

**Last Updated**: January 2025  
**Version**: 4.0.0  
**Contributors Guide**: Week 5 Implementation 