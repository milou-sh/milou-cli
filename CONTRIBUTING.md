# Contributing to Milou

Thanks for your interest in improving Milou! 🎉

## Quick Start

1. **Fork** this repository
2. **Clone** your fork locally  
3. **Create** a feature branch
4. **Make** your changes
5. **Test** that everything works
6. **Submit** a pull request

## Development Setup

```bash
# Clone your fork
git clone https://github.com/yourusername/milou-cli.git
cd milou-cli

# Test the current version
./milou.sh setup
./milou.sh status

# Make your changes
# ...

# Test your changes
./milou.sh restart
./milou.sh status
```

## What We're Looking For

### 🐛 Bug Fixes
- Fix issues that prevent Milou from working
- Improve error messages
- Better error handling

### ✨ Features  
- Simplify user experience
- Add useful commands
- Improve setup process

### 📚 Documentation
- Fix unclear instructions
- Add examples
- Improve troubleshooting

## Guidelines

### Keep It Simple
- Milou should be easy to use
- Avoid over-engineering  
- Focus on the 80/20 rule (80% of users need 20% of features)

### Test Your Changes
```bash
# Basic testing
./milou.sh setup    # Should work
./milou.sh status   # Should show services running
./milou.sh backup   # Should create backup
./milou.sh restart  # Should restart services
```

### Code Style
- Follow existing patterns
- Use clear, descriptive names
- Add comments for complex logic
- Keep functions small and focused

## Pull Request Process

### 1. Create a Good PR Title
```
✅ Good: "Fix backup command failing on Ubuntu 22.04"
❌ Bad: "Fix bug"
```

### 2. Describe Your Changes
```markdown
## What This Fixes
- Backup command was failing because...

## How to Test
1. Run `milou backup`
2. Check that backup file is created
3. Verify backup can be restored

## Additional Notes
- Only affects Ubuntu 22.04+
- Backwards compatible
```

### 3. Keep PRs Small
- One feature/fix per PR
- Makes review easier
- Faster to merge

## Types of Contributions

### 🆘 High Priority
- Security fixes
- Data loss prevention
- Installation failures
- Service startup issues

### 🔧 Medium Priority  
- Improve error messages
- Better documentation
- Performance improvements
- Code cleanup

### 💡 Nice to Have
- New features
- Advanced options
- Additional integrations

## Testing

### Manual Testing
```bash
# Test fresh installation
rm -rf .env ssl/ backups/
./milou.sh setup

# Test backup/restore
./milou.sh backup
./milou.sh stop
./milou.sh restore backups/latest_backup.tar.gz
./milou.sh start
```

### Test on Different Systems
- Ubuntu 20.04, 22.04
- CentOS/RHEL 8+
- Debian 11+

## Getting Help

### Before You Start
1. Check [existing issues](https://github.com/milou-sh/milou-cli/issues)
2. Read [Getting Started](docs/GETTING_STARTED.md)
3. Try the troubleshooting steps

### If You're Stuck
1. **Open an issue** describing what you want to work on
2. **Ask questions** - we're here to help!
3. **Start small** - even tiny improvements help

## Recognition

Contributors are recognized in:
- Release notes
- README contributor section  
- GitHub contributors page

## Questions?

- **Bug reports**: [Open an issue](https://github.com/milou-sh/milou-cli/issues)
- **Feature ideas**: [Start a discussion](https://github.com/milou-sh/milou-cli/discussions)
- **Questions**: [Open an issue](https://github.com/milou-sh/milou-cli/issues) with "Question:" prefix

Thanks for helping make Milou better! 🚀 