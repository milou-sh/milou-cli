# Milou CLI Scripts

This directory contains utility scripts for Milou CLI development and management.

## Structure

```
scripts/
├── dev/
│   ├── build-local-images.sh  # Build Docker images locally for development
│   └── test-setup.sh           # Setup test environment
└── README.md                   # This file
```

## Development Scripts (`dev/`)

### Build Local Images

```bash
# Build all images with smart rebuild logic
./scripts/dev/build-local-images.sh

# Force rebuild all images
./scripts/dev/build-local-images.sh --force

# Build with verbose output
./scripts/dev/build-local-images.sh --verbose

# Show help
./scripts/dev/build-local-images.sh --help
```

**Features:**
- Smart rebuild logic (skips up-to-date images)
- Force rebuild option
- Automatic path detection
- Detailed build status reporting

### Test Setup

```bash
# Setup development test environment
./scripts/dev/test-setup.sh
```

**Features:**
- Creates necessary directories
- Sets up SSL directory structure
- Copies configuration templates

## Using with `--dev` Flag

The `--dev` flag in the main CLI enables development mode:

```bash
# Use locally built images instead of pulling from registry
./milou.sh setup --dev --fresh-install

# Build images first, then setup
./scripts/dev/build-local-images.sh
./milou.sh setup --dev
```

## Design Principles

- **Organized Structure**: Development utilities in `scripts/dev/`
- **Self-Contained**: Scripts handle their own path detection
- **Consistent Interface**: All scripts support `--help` flag
- **Clean Root**: No development scripts cluttering project root
- **Proper Documentation**: Clear usage instructions and examples 