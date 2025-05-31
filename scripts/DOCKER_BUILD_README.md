# Docker Build and Push Scripts

This directory contains scripts to build and push Milou Docker images to GitHub Container Registry (GHCR) with proper versioning, smart rebuild capabilities, comprehensive image management, and **automatic latest tag management**.

## 🚀 Quick Start

### 1. First-time Setup

The script will prompt for GitHub token when needed:
```bash
# Build and push with interactive login
./scripts/build-and-push.sh --service backend --version 1.0.0 --push
```

Or set up environment variables:
```bash
export GITHUB_TOKEN="your_github_token_here"
export GITHUB_USERNAME="your_github_username"  # optional, defaults to org name
```

### 2. Build and Push Examples

**Build and push a specific service with version:**
```bash
./scripts/build-and-push.sh --service backend --version 1.0.0 --push
# Creates: backend:1.0.0 and backend:latest (latest moves to 1.0.0)
```

**Build and push all services with version:**
```bash
./scripts/build-and-push.sh --all --version 1.2.0 --push
# All services get version 1.2.0 + latest tags
```

**Build only (no push):**
```bash
./scripts/build-and-push.sh --service frontend --version 1.1.0
```

**Push without version (latest only):**
```bash
./scripts/build-and-push.sh --service frontend --push
# Creates/updates: frontend:latest
```

### 3. Image Management Examples

**List all images with their actual tags:**
```bash
./scripts/build-and-push.sh --list-images
# Shows: Tag: latest, Tag: 1.0.0, Tag: 1.1.0, etc.
```

**Delete images (with safety confirmations):**
```bash
./scripts/build-and-push.sh --delete-images --service backend  # Delete backend images
./scripts/build-and-push.sh --delete-images --all            # Delete ALL images
```

## 📋 Main Script Features

### `build-and-push.sh`
Complete Docker image lifecycle management script.

**Key Features:**
- ✅ **Automatic Latest Tag Management**: Latest tag automatically moves to newest version
- ✅ **Smart Tag Display**: Lists actual tags (latest, 1.0.0, 1.1.0) not just digests
- ✅ **State-of-the-art diff detection**: SHA256 digest comparison + build context hashing
- ✅ **Integrated authentication**: Interactive login when token not available
- ✅ **Version tagging**: Supports semantic versioning (e.g., 1.0.0) + latest
- ✅ **Selective building**: Build individual services or all at once
- ✅ **Image management**: List and delete images with safety confirmations
- ✅ **Enhanced labeling**: Stores build context hash and metadata in image labels
- ✅ **Dry-run mode**: Preview all operations without executing
- ✅ **Smart caching**: Only rebuilds when actually needed

## 🏷️ **Tag Management (Key Feature)**

### How Latest Tag Works

When you push with a version, the script handles tags properly:

```bash
# Current state: backend:1.0.0 (with latest tag)
./scripts/build-and-push.sh --service backend --version 1.1.0 --push

# Result:
# ✅ backend:1.0.0 (keeps version tag, loses latest)
# ✅ backend:1.1.0 (gets version + latest tags)
# ✅ backend:latest → points to 1.1.0 image
```

### Tag Behavior
- **Version tags** (1.0.0, 1.1.0): **Permanent** - never change or move
- **Latest tag**: **Automatic** - always points to the most recently pushed version
- **Proper ordering**: Version tag pushed first, then latest (ensures correct behavior)

### Visual Example
```
Before: backend:1.0.0 [latest] ← latest points here
                    
Push 1.1.0:
                    
After:  backend:1.0.0           ← keeps version, no latest
        backend:1.1.0 [latest] ← latest moved here
```

## 🛠️ Available Services

The script supports building these Milou services:

| Service    | Description           | Image Name                                 |
|------------|----------------------|-------------------------------------------|
| `database` | PostgreSQL database  | `ghcr.io/milou-sh/milou/database`       |
| `backend`  | API backend service  | `ghcr.io/milou-sh/milou/backend`        |
| `frontend` | Web frontend         | `ghcr.io/milou-sh/milou/frontend`       |
| `engine`   | Processing engine    | `ghcr.io/milou-sh/milou/engine`         |
| `nginx`    | Reverse proxy        | `ghcr.io/milou-sh/milou/nginx`          |

## 📖 Detailed Usage

### Script Options

```bash
./scripts/build-and-push.sh [OPTIONS]

Options:
  --service SERVICE     Build specific service (database, backend, frontend, engine, nginx)
  --version VERSION     Tag with version number (e.g., 1.0.0)
  --all                 Build all services
  --push                Push to GHCR after building
  --force               Force rebuild even if image exists and is recent
  --no-diff-check       Skip checking for source code differences
  --list-images         List all images in GHCR with tags
  --delete-images       Delete images from GHCR (interactive)
  --org ORG             GitHub organization (default: milou-sh)
  --repo REPO           Repository name (default: milou)
  --dry-run             Show what would be done without executing
  --debug               Enable debug logging
  --help, -h            Show this help

Tag Management:
  • When you push with --version 1.2.0, both tags are created: 1.2.0 and latest
  • The 'latest' tag automatically moves to the newest version
  • Previous versions keep their specific version tags (1.1.0, 1.0.0, etc.)
```

### Version Tagging

When you specify a version (e.g., `--version 1.0.0`), the script creates two tags:
- `ghcr.io/milou-sh/milou/SERVICE:1.0.0` (specific version - permanent)
- `ghcr.io/milou-sh/milou/SERVICE:latest` (moves from previous image)

Without a version, only the `latest` tag is created/updated.

### 🧠 State-of-the-Art Diff Detection

The script uses advanced techniques to determine if rebuilds are needed:

1. **Build Context Hashing**: 
   - Creates SHA256 hash of Dockerfile + key source files
   - Stores hash in image labels (`milou.context.hash`)
   - Compares current vs stored hash for changes

2. **Enhanced Digest Comparison**:
   - Uses proper SHA256 image digests (not just image IDs)
   - Compares local vs remote registry digests
   - Handles repo digests and fallback to config digests

3. **Smart File Detection**:
   - Scans for relevant source files (*.py, *.js, *.ts, package.json, etc.)
   - Limited depth scanning for performance
   - Timestamp-based change detection

4. **Multi-layer Validation**:
   - Image existence check
   - Dockerfile modification time
   - Source file changes
   - Registry digest comparison
   - Context hash validation

This approach is **significantly better** than basic timestamp comparison and provides near-perfect change detection while maintaining performance.

### Image Management

#### Listing Images with Tags
```bash
# List all service images with actual tags
./scripts/build-and-push.sh --list-images

# Example output:
# 📦 backend images:
#   • Tag: latest (created: 2024-01-15 10:30)
#   • Tag: 1.0.0 (created: 2024-01-14 09:15)
#   • Tag: 1.1.0 (created: 2024-01-15 10:30)

# List specific service images
./scripts/build-and-push.sh --list-images --service backend
```

#### Deleting Images
```bash
# Delete specific service images (with confirmation)
./scripts/build-and-push.sh --delete-images --service backend

# Shows what will be deleted:
# Images that will be deleted:
#   backend: 3 images
#     - latest
#     - 1.0.0
#     - 1.1.0

# Delete ALL images (DANGER - multiple confirmations required)
./scripts/build-and-push.sh --delete-images --all
```

**Safety Features:**
- Shows exactly what tags will be deleted
- Requires typing "yes" and "DELETE" to confirm
- Supports dry-run mode
- Cannot be automated (interactive confirmations)

## 🔧 Configuration

### Environment Variables

| Variable         | Description                    | Default                |
|------------------|--------------------------------|------------------------|
| `GITHUB_TOKEN`   | GitHub Personal Access Token  | (interactive prompt)   |
| `GITHUB_USERNAME`| GitHub username               | (uses org name)        |
| `DEBUG`          | Enable debug logging           | `false`                |

### GitHub Token Permissions

Your GitHub token needs these permissions:
- `write:packages` - To push packages
- `read:packages` - To pull packages  
- `delete:packages` - To delete packages (for cleanup)

Create a token at: https://github.com/settings/tokens

### Interactive Authentication

When `GITHUB_TOKEN` is not set, the script will:
1. Explain what permissions are needed
2. Ask if you want to enter credentials interactively
3. Validate token format
4. Test authentication
5. Set token for the session

## 🎯 Common Workflows

### Development Workflow

1. **Make changes to your service**
2. **Test locally** with the dev build script:
   ```bash
   ./scripts/dev/build-local-images.sh
   ```
3. **Build and test the production image**:
   ```bash
   ./scripts/build-and-push.sh --service backend --dry-run
   ./scripts/build-and-push.sh --service backend
   ```
4. **Push to registry** when ready:
   ```bash
   ./scripts/build-and-push.sh --service backend --push
   # Creates/updates backend:latest
   ```

### Release Workflow

1. **Update version** in your release process
2. **Build and push all services** with the new version:
   ```bash
   ./scripts/build-and-push.sh --all --version 1.2.0 --push
   # All services get: 1.2.0 + latest (latest moves from previous versions)
   ```
3. **Verify images** are available:
   ```bash
   ./scripts/build-and-push.sh --list-images
   # Shows: Tag: latest, Tag: 1.2.0, Tag: 1.1.0, etc.
   ```

### Hotfix Workflow

1. **Build and push specific service** with patch version:
   ```bash
   ./scripts/build-and-push.sh --service backend --version 1.1.1 --push
   # Creates: backend:1.1.1 + moves latest from 1.1.0 to 1.1.1
   ```

### Cleanup Workflow

1. **List current images with tags**:
   ```bash
   ./scripts/build-and-push.sh --list-images
   # See exactly what tags exist
   ```
2. **Delete old/test images**:
   ```bash
   ./scripts/build-and-push.sh --delete-images --service backend
   # Shows which tags will be deleted before confirmation
   ```

## 🐛 Troubleshooting

### Authentication Issues

**Problem**: Authentication fails
```bash
# The script will guide you through interactive login
./scripts/build-and-push.sh --service backend --push

# Or set environment variables:
export GITHUB_TOKEN="ghp_xxxxxxxxxxxx"
export GITHUB_USERNAME="yourusername"
```

### Build Issues

**Problem**: Build fails due to missing context
```bash
# Check if you're in the right directory structure
# The script expects milou_fresh as a sibling directory
ls ../milou_fresh/

# Use debug mode to see detailed information
./scripts/build-and-push.sh --service backend --debug
```

**Problem**: Changes not detected
```bash
# Force rebuild to bypass all checks
./scripts/build-and-push.sh --service backend --force --push

# Or disable diff checking
./scripts/build-and-push.sh --service backend --no-diff-check --push
```

### Tag Management Issues

**Problem**: Don't see latest tag moving
```bash
# Use dry-run to see what would happen
./scripts/build-and-push.sh --service backend --version 1.2.0 --push --dry-run

# Check current tags
./scripts/build-and-push.sh --list-images --service backend
```

### Image Management Issues

**Problem**: Cannot list images or see wrong information
```bash
# Ensure your token has read:packages permission
# Try with debug mode:
./scripts/build-and-push.sh --list-images --debug
```

## 📊 Examples Output

### Successful Build and Push with Tag Management
```
[INFO] 🚀 Milou Docker Build & Push
[INFO] Organization: milou-sh
[INFO] Repository: milou
[INFO] Version: 1.2.0
[INFO] Building from: /path/to/milou_fresh
[INFO] 🔐 Logging in to GHCR...
[INFO] ✅ Successfully logged in to GHCR
[INFO] 🏷️  Will create tags: 1.2.0 and latest
[INFO] 📦 Processing backend...
[DEBUG] Build context hash changed for backend
[INFO] 🔨 Building backend...
[INFO] ✅ Successfully built ghcr.io/milou-sh/milou/backend:1.2.0
[INFO] 🚀 Pushing to GHCR...
[INFO] 💡 Tag behavior: Latest tag will move to version 1.2.0
[INFO] 📤 Pushing ghcr.io/milou-sh/milou/backend:1.2.0...
[INFO] ✅ Successfully pushed ghcr.io/milou-sh/milou/backend:1.2.0
[INFO] 📤 Pushing ghcr.io/milou-sh/milou/backend:latest (moving 'latest' tag)...
[INFO] ✅ Successfully pushed ghcr.io/milou-sh/milou/backend:latest
[INFO] 🏷️  The 'latest' tag now points to this image
[INFO] 📊 Build Summary:
[INFO]    ✅ Success: backend
[INFO] 🎉 All operations completed successfully!
[INFO] 📋 Published images:
[INFO]    • ghcr.io/milou-sh/milou/backend:1.2.0
[INFO]    • ghcr.io/milou-sh/milou/backend:latest (moved to 1.2.0)
[INFO] 💡 Use --list-images to see all tags in the registry
```

### Enhanced Image Listing
```
[INFO] 📋 Listing images in GHCR with tags...
[INFO] 📦 backend images:
  • Tag: latest (created: 2024-01-15 10:30)
  • Tag: 1.2.0 (created: 2024-01-15 10:30)
  • Tag: 1.1.0 (created: 2024-01-14 15:20)
  • Tag: 1.0.0 (created: 2024-01-13 09:15)

[INFO] 💡 Tag Management Notes:
[INFO]   • 'latest' tag automatically moves to the newest pushed version
[INFO]   • Specific version tags (1.0.0, 1.1.0) remain permanently
[INFO]   • Only one image can have the 'latest' tag at a time
```

### Smart Skip Example
```
[INFO] 📦 Processing frontend...
[DEBUG] Local and remote digests match for frontend
[DEBUG] Image frontend is up to date, skipping build
[INFO] ⏭️  Skipping frontend (up to date)
[INFO] Image exists locally, pushing anyway...
[INFO] 🚀 Pushing to GHCR...
[INFO] 📤 Pushing ghcr.io/milou-sh/milou/frontend:latest (moving 'latest' tag)...
[INFO] ✅ Successfully pushed ghcr.io/milou-sh/milou/frontend:latest
[INFO] 🏷️  The 'latest' tag now points to this image
```

## 🔗 Integration with CI/CD

You can use this script in GitHub Actions or other CI/CD systems:

```yaml
# Example GitHub Actions workflow
- name: Build and Push
  run: ./scripts/build-and-push.sh --all --version ${{ github.ref_name }} --push
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

# For latest-only pushes (development)
- name: Build and Push Latest
  run: ./scripts/build-and-push.sh --service backend --push
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## 🚀 What's New & Improved

### Enhanced Tag Management
- **Automatic Latest Movement**: Latest tag automatically moves to newest version
- **Smart Tag Ordering**: Version tag pushed first, then latest (ensures correct behavior)
- **Clear Messaging**: Script explicitly tells you when latest tag moves
- **Permanent Versions**: Version tags (1.0.0, 1.1.0) never move or change

### Better Image Listing
- **Actual Tags**: Shows real tags (latest, 1.0.0) instead of SHA digests
- **Creation Times**: When each tag was created
- **Tag Notes**: Explains how latest tag behavior works
- **Fallback Handling**: Graceful handling when API responses vary

### Enhanced User Experience
- **Clear Tag Intent**: Script tells you which tags will be created
- **Latest Movement**: Explicitly shows when latest tag moves
- **Helpful Notes**: Guidance about tag management throughout
- **Dry-run Clarity**: Preview shows exact tag behavior

### Improved Build Process
- **Context Hashing**: SHA256 hash of build context stored in image labels
- **Proper Digests**: Uses repo digests instead of image IDs
- **Smart Scanning**: Detects relevant source files (Python, JS, Go, etc.)
- **Multi-layer Validation**: Multiple checks ensure accurate rebuild decisions

## 📝 Notes

- Images are built from the `milou_fresh` directory (sibling to `milou-cli`)
- **Latest tag automatically moves** when you push a new version
- Version tags (1.0.0, 1.1.0) are **permanent** and never change
- All images include enhanced labels for better tracking and comparison
- The script preserves your existing development workflow while adding production capabilities
- State-of-the-art diff detection minimizes unnecessary rebuilds
- Interactive safety confirmations prevent accidental deletions
- Build context hashing provides near-perfect change detection

## 🎯 Key Takeaway

**The script now properly handles the latest tag movement you requested:**
- Push version 1.1.1 → gets `latest` tag
- Push version 1.1.2 → `latest` moves to 1.1.2, 1.1.1 loses `latest` but keeps `1.1.1`
- List images shows actual tags: `latest`, `1.1.2`, `1.1.1`, `1.1.0`, etc. 