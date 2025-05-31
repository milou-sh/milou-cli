#!/bin/bash

# =============================================================================
# Test script for the improved build-and-push.sh script
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SCRIPT="$SCRIPT_DIR/build-and-push.sh"

echo "Testing Milou Build & Push Script Improvements"
echo "=============================================="
echo

# Test 1: Help message should include new options
echo "Test 1: Checking help message includes new options..."
if "$BUILD_SCRIPT" --help | grep -q -- "--token"; then
    echo "✅ --token option found in help"
else
    echo "❌ --token option missing from help"
    exit 1
fi

if "$BUILD_SCRIPT" --help | grep -q -- "--save-token"; then
    echo "✅ --save-token option found in help"
else
    echo "❌ --save-token option missing from help"
    exit 1
fi

if "$BUILD_SCRIPT" --help | grep -q -- "--non-interactive"; then
    echo "✅ --non-interactive option found in help"
else
    echo "❌ --non-interactive option missing from help"
    exit 1
fi

# Test 2: Token validation should work with dry-run
echo
echo "Test 2: Testing token validation (dry-run)..."

# Test invalid token format
if "$BUILD_SCRIPT" --dry-run --service frontend --push --token "invalid_token" --non-interactive 2>/dev/null; then
    echo "❌ Invalid token should have been rejected"
    exit 1
else
    echo "✅ Invalid token correctly rejected"
fi

# Test valid token format (fake but correct format)
if "$BUILD_SCRIPT" --dry-run --service frontend --push --token "ghp_1234567890123456789012345678901234567890" --non-interactive >/dev/null 2>&1; then
    echo "✅ Valid token format accepted in dry-run mode"
else
    echo "❌ Valid token format should be accepted in dry-run mode"
fi

# Test 3: Non-interactive mode should fail without token
echo
echo "Test 3: Testing non-interactive mode without token..."
if "$BUILD_SCRIPT" --dry-run --service frontend --push --non-interactive 2>/dev/null; then
    echo "❌ Non-interactive mode should fail without token"
    exit 1
else
    echo "✅ Non-interactive mode correctly fails without token"
fi

# Test 4: List images should work without authentication (dry-run)
echo
echo "Test 4: Testing list-images in dry-run mode..."
if "$BUILD_SCRIPT" --list-images --dry-run --non-interactive 2>/dev/null; then
    echo "✅ List images works in dry-run mode"
else
    echo "❌ List images should work in dry-run mode"
fi

echo
echo "All tests passed! ✅"
echo
echo "Manual testing suggestions:"
echo "1. Test with a real GitHub token: ./build-and-push.sh --service frontend --dry-run --token YOUR_TOKEN"
echo "2. Test interactive mode: ./build-and-push.sh --service frontend --dry-run"
echo "3. Test save token functionality: ./build-and-push.sh --list-images --token YOUR_TOKEN --save-token"
echo "4. Test .env file loading after saving a token" 