#!/bin/bash

# =============================================================================
# Milou CLI Release Preparation Script
# Helps prepare the CLI for distribution by updating URLs and organization
# =============================================================================

# Load shared utilities to eliminate code duplication
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$script_dir/shared-utils.sh" ]]; then
    source "$script_dir/shared-utils.sh"
else
    echo "ERROR: Cannot find shared-utils.sh in $script_dir" >&2
    exit 1
fi

set -euo pipefail

# Global variables
GITHUB_ORG=""
REPO_NAME="milou-cli"
DRY_RUN=false

# Show help
show_help() {
    echo -e "${BOLD}Milou CLI Release Preparation Script${NC}"
    echo
    echo "Usage: $0 --org GITHUB_ORG [OPTIONS]"
    echo
    echo "Options:"
    echo "  --org ORG         GitHub organization/username (required)"
    echo "  --repo REPO       Repository name (default: milou-cli)"
    echo "  --dry-run         Show what would be changed without making changes"
    echo "  --help, -h        Show this help"
    echo
    echo "Examples:"
    echo "  $0 --org mycompany"
    echo "  $0 --org mycompany --repo my-milou-cli"
    echo "  $0 --org mycompany --dry-run  # Preview changes"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --org)
                GITHUB_ORG="$2"
                shift 2
                ;;
            --repo)
                REPO_NAME="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    if [[ -z "$GITHUB_ORG" ]]; then
        error "GitHub organization/username is required"
        show_help
        exit 1
    fi
}

# Validate we're in the right directory
validate_directory() {
    if [[ ! -f "milou.sh" ]] || [[ ! -f "install.sh" ]] || [[ ! -d "src" ]]; then
        error "This doesn't appear to be the milou-cli repository root"
        error "Please run this script from the milou-cli directory"
        exit 1
    fi
}

# Update URLs in a file
update_file() {
    local file="$1"
    local description="$2"
    
    if [[ ! -f "$file" ]]; then
        warn "File not found: $file (skipping)"
        return 0
    fi
    
    log "Processing $description: $file"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  Would replace:"
        grep -n "YOUR_ORG" "$file" 2>/dev/null | head -5 | sed 's/^/    /' || true
        grep -n "raw.githubusercontent.com.*YOUR_ORG" "$file" 2>/dev/null | head -5 | sed 's/^/    /' || true
    else
        # Backup original file
        cp "$file" "$file.backup"
        
        # Replace URLs
        sed -i "s/YOUR_ORG/$GITHUB_ORG/g" "$file"
        sed -i "s/your-org/$GITHUB_ORG/g" "$file"
        sed -i "s/milou-cli/$REPO_NAME/g" "$file"
        
        success "  Updated $file"
    fi
}

# Main function to update all files
update_repository() {
    log "Updating repository URLs..."
    log "GitHub Org: $GITHUB_ORG"
    log "Repository: $REPO_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN MODE - No files will be modified"
    fi
    
    echo
    
    # Update main installation script
    update_file "install.sh" "Installation script"
    
    # Update README
    update_file "README.md" "Main README"
    
    # Update documentation
    update_file "docs/USER_GUIDE.md" "User guide"
    update_file "DEPLOYMENT.md" "Deployment guide"
    
    # Update any other documentation files
    for doc_file in docs/*.md; do
        if [[ -f "$doc_file" && "$doc_file" != "docs/USER_GUIDE.md" ]]; then
            update_file "$doc_file" "Documentation file"
        fi
    done
    
    # Update setup help text
    if grep -q "YOUR_ORG" src/_setup.sh 2>/dev/null; then
        update_file "src/_setup.sh" "Setup module"
    fi
    
    echo
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Preview complete. Run without --dry-run to apply changes."
    else
        success "Repository URLs updated successfully!"
        echo
        log "Backup files created with .backup extension"
        log "Review changes and commit when ready:"
        echo
        echo "  git add ."
        echo "  git commit -m \"Update URLs for $GITHUB_ORG/$REPO_NAME\""
        echo "  git push origin main"
        echo
        log "Test your installation URL:"
        echo "  curl -fsSL https://raw.githubusercontent.com/$GITHUB_ORG/$REPO_NAME/main/install.sh | bash"
    fi
}

# Cleanup function
cleanup_backups() {
    log "Cleaning up backup files..."
    find . -name "*.backup" -type f -delete
    success "Backup files removed"
}

# Main execution
main() {
    parse_args "$@"
    validate_directory
    update_repository
    
    # Offer to clean up backups if not dry run
    if [[ "$DRY_RUN" == "false" ]]; then
        echo
        read -p "Remove backup files? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cleanup_backups
        fi
    fi
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 