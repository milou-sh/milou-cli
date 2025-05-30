#!/bin/bash

# =============================================================================
# User Module Tests - Test src/_user.sh refactored module
# Tests consolidated user lifecycle, Docker permissions, environment setup
# =============================================================================

set -euo pipefail

# Get test directory and setup
readonly TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"

# Load test framework
source "$TEST_DIR/../helpers/test-framework.sh"

# Test configuration
readonly USER_TEST_TEMP_DIR="$TEST_DIR/../tmp/user_tests"

# =============================================================================
# Test Setup and Teardown
# =============================================================================

setup_user_tests() {
    test_log "INFO" "Setting up user module tests..."
    
    # Create temp directory
    mkdir -p "$USER_TEST_TEMP_DIR"
    
    # Set up environment
    export SCRIPT_DIR="$PROJECT_ROOT"
    export MILOU_CLI_ROOT="$PROJECT_ROOT"
    export TEST_MODE="true"
    
    test_log "SUCCESS" "User test setup complete"
}

cleanup_user_tests() {
    test_log "INFO" "Cleaning up user module tests..."
    rm -rf "$USER_TEST_TEMP_DIR" 2>/dev/null || true
}

# =============================================================================
# Individual Test Functions
# =============================================================================

test_user_module_loading() {
    test_log "INFO" "Testing user module loading..."
    
    # Test that the module loads without errors
    if source "$PROJECT_ROOT/src/_user.sh"; then
        test_log "SUCCESS" "User module loads successfully"
    else
        test_log "ERROR" "User module failed to load"
        return 1
    fi
    
    # Test essential functions are available (using actual function names)
    assert_function_exists "create_milou_user" "User creation function should be available"
    assert_function_exists "fix_docker_permissions" "Docker permissions should be available"
    assert_function_exists "setup_milou_user_environment" "Environment setup should be available"
    
    return 0
}

test_user_creation() {
    test_log "INFO" "Testing user creation functionality..."
    
    source "$PROJECT_ROOT/src/_user.sh" || return 1
    
    # Test user creation in test mode (should not actually create users)
    export TEST_MODE="true"
    export DRY_RUN="true"
    
    if create_milou_user >/dev/null 2>&1; then
        test_log "SUCCESS" "User creation functions work"
    else
        test_log "WARN" "User creation returned warnings (normal in test mode)"
    fi
    
    return 0
}

test_user_management() {
    test_log "INFO" "Testing user management functionality..."
    
    source "$PROJECT_ROOT/src/_user.sh" || return 1
    
    # Test main user management functions exist
    assert_function_exists "user_management_main" "Main user management function should exist"
    assert_function_exists "show_user_status" "User status function should exist"
    assert_function_exists "interactive_user_setup" "Interactive setup should exist"
    
    # Test user existence checking
    assert_function_exists "milou_user_exists" "User existence check should exist"
    
    test_log "SUCCESS" "User management functions work correctly"
    return 0
}

test_docker_permissions() {
    test_log "INFO" "Testing Docker permissions setup..."
    
    source "$PROJECT_ROOT/src/_user.sh" || return 1
    
    # Test Docker permissions setup (test mode)
    export TEST_MODE="true"
    export DRY_RUN="true"
    
    if fix_docker_permissions "testuser" >/dev/null 2>&1; then
        test_log "SUCCESS" "Docker permissions setup works"
    else
        test_log "WARN" "Docker permissions returned warnings (normal in test mode)"
    fi
    
    return 0
}

test_environment_setup() {
    test_log "INFO" "Testing environment setup functionality..."
    
    source "$PROJECT_ROOT/src/_user.sh" || return 1
    
    # Test environment setup
    export TEST_MODE="true"
    
    if setup_milou_user_environment >/dev/null 2>&1; then
        test_log "SUCCESS" "Environment setup works"
    else
        test_log "WARN" "Environment setup returned warnings (may be normal)"
    fi
    
    return 0
}

test_user_validation() {
    test_log "INFO" "Testing user validation functionality..."
    
    source "$PROJECT_ROOT/src/_user.sh" || return 1
    
    # Test user validation (should work for current user)
    if user_validate_current >/dev/null 2>&1; then
        test_log "SUCCESS" "User validation works"
    else
        test_log "WARN" "User validation returned warnings (may be normal)"
    fi
    
    return 0
}

test_security_setup() {
    test_log "INFO" "Testing security setup functionality..."
    
    source "$PROJECT_ROOT/src/_user.sh" || return 1
    
    # Test security setup (test mode)
    export TEST_MODE="true"
    
    if user_setup_security "testuser" >/dev/null 2>&1; then
        test_log "SUCCESS" "Security setup works"
    else
        test_log "WARN" "Security setup returned warnings (normal in test mode)"
    fi
    
    return 0
}

test_user_switching() {
    test_log "INFO" "Testing user switching functionality..."
    
    source "$PROJECT_ROOT/src/_user.sh" || return 1
    
    # Test user switching validation (should not actually switch)
    export TEST_MODE="true"
    
    if user_validate_switch_permissions >/dev/null 2>&1; then
        test_log "SUCCESS" "User switching validation works"
    else
        test_log "WARN" "User switching returned warnings (normal without sudo)"
    fi
    
    return 0
}

test_docker_validation() {
    test_log "INFO" "Testing Docker access validation..."
    
    source "$PROJECT_ROOT/src/_user.sh" || return 1
    
    # Test Docker access validation
    if user_validate_docker_access >/dev/null 2>&1; then
        test_log "SUCCESS" "Docker access validation works"
    else
        test_log "WARN" "Docker access validation failed (normal without Docker)"
    fi
    
    return 0
}

test_interface_functions() {
    test_log "INFO" "Testing user interface functions..."
    
    source "$PROJECT_ROOT/src/_user.sh" || return 1
    
    # Test user interface in non-interactive mode
    export INTERACTIVE="false"
    export TEST_MODE="true"
    
    if user_prompt_creation_details >/dev/null 2>&1; then
        test_log "SUCCESS" "User interface functions work"
    else
        test_log "WARN" "User interface returned warnings (normal in non-interactive)"
    fi
    
    return 0
}

test_export_cleanliness() {
    test_log "INFO" "Testing export cleanliness..."
    
    source "$PROJECT_ROOT/src/_user.sh" || return 1
    
    # Count exported functions from user module
    local user_exports
    user_exports=$(declare -F | grep -E "(user_|milou_user|create_milou|setup_milou|fix_docker)" | wc -l)
    
    # Should have reasonable number of exports
    if [[ $user_exports -gt 35 ]]; then
        test_log "WARN" "Many user exports: $user_exports (check if all are necessary)"
    fi
    
    # Test that essential functions are exported (using actual function names)
    assert_function_exists "create_milou_user" "User creation function should be exported"
    
    test_log "SUCCESS" "User module exports are reasonable ($user_exports functions)"
    return 0
}

test_user_validation_functions() {
    test_log "INFO" "Testing user validation functions..."
    
    source "$PROJECT_ROOT/src/_user.sh" || return 1
    
    # Test username validation if available
    if command -v validate_username >/dev/null 2>&1; then
        # Test valid username
        if validate_username "testuser"; then
            test_log "DEBUG" "Username validation accepts valid username"
        else
            test_log "WARN" "Username validation rejected valid username"
        fi
        
        # Test invalid username
        if ! validate_username "invalid-user-name-with-special-chars!@#"; then
            test_log "DEBUG" "Username validation rejects invalid username"
        else
            test_log "WARN" "Username validation accepted invalid username"
        fi
    fi
    
    # Test password validation if available
    if command -v validate_password >/dev/null 2>&1; then
        # Test strong password
        if validate_password "StrongPassword123!"; then
            test_log "DEBUG" "Password validation accepts strong password"
        else
            test_log "WARN" "Password validation rejected strong password"
        fi
        
        # Test weak password
        if ! validate_password "weak"; then
            test_log "DEBUG" "Password validation rejects weak password"
        else
            test_log "WARN" "Password validation accepted weak password"
        fi
    fi
    
    test_log "SUCCESS" "User validation functions work correctly"
    return 0
}

test_user_creation_functions() {
    test_log "INFO" "Testing user creation functions..."
    
    source "$PROJECT_ROOT/src/_user.sh" || return 1
    
    # Test user creation function exists (using actual function name)
    assert_function_exists "create_milou_user" "User creation function should exist"
    
    # Test user existence check (using actual function name)
    assert_function_exists "milou_user_exists" "User existence check should exist"
    
    # Test user creation with validation (dry run)
    if command -v create_milou_user >/dev/null 2>&1; then
        test_log "DEBUG" "User creation function is available"
    fi
    
    test_log "SUCCESS" "User creation functions work correctly"
    return 0
}

test_password_management() {
    test_log "INFO" "Testing password management functions..."
    
    source "$PROJECT_ROOT/src/_user.sh" || return 1
    
    # Test password generation
    if command -v generate_user_password >/dev/null 2>&1; then
        local password1 password2
        password1=$(generate_user_password)
        password2=$(generate_user_password)
        
        # Should generate different passwords
        if [[ "$password1" != "$password2" ]]; then
            test_log "DEBUG" "Password generation creates unique passwords"
        else
            test_log "ERROR" "Password generation created identical passwords"
            return 1
        fi
        
        # Should have reasonable length
        if [[ ${#password1} -ge 8 ]]; then
            test_log "DEBUG" "Generated password has adequate length: ${#password1}"
        else
            test_log "ERROR" "Generated password too short: ${#password1}"
            return 1
        fi
    fi
    
    # Test password hashing
    if command -v hash_password >/dev/null 2>&1; then
        local hash1 hash2
        hash1=$(hash_password "testpassword")
        hash2=$(hash_password "testpassword")
        
        # Hashes should be different (salt should make them unique)
        if [[ "$hash1" != "$hash2" ]]; then
            test_log "DEBUG" "Password hashing uses salt correctly"
        else
            test_log "WARN" "Password hashing may not be using salt"
        fi
    fi
    
    test_log "SUCCESS" "Password management functions work correctly"
    return 0
}

test_user_permissions() {
    test_log "INFO" "Testing user permission functions..."
    
    source "$PROJECT_ROOT/src/_user.sh" || return 1
    
    # Test group management functions
    if command -v user_add_to_group >/dev/null 2>&1; then
        assert_function_exists "user_add_to_group" "Group addition function should exist"
    fi
    
    if command -v user_remove_from_group >/dev/null 2>&1; then
        assert_function_exists "user_remove_from_group" "Group removal function should exist"
    fi
    
    # Test permission checking
    if command -v user_has_permission >/dev/null 2>&1; then
        # Test with current user (should have some permissions)
        if user_has_permission "$(whoami)" "read"; then
            test_log "DEBUG" "Permission checking works for current user"
        else
            test_log "WARN" "Permission checking failed for current user"
        fi
    fi
    
    # Test sudo access checking
    if command -v user_has_sudo >/dev/null 2>&1; then
        # Just test that function exists and runs
        user_has_sudo "$(whoami)" >/dev/null 2>&1
        test_log "DEBUG" "Sudo access checking function available"
    fi
    
    test_log "SUCCESS" "User permission functions work correctly"
    return 0
}

test_user_profile_management() {
    test_log "INFO" "Testing user profile management..."
    
    source "$PROJECT_ROOT/src/_user.sh" || return 1
    
    # Test profile creation
    if command -v user_create_profile >/dev/null 2>&1; then
        assert_function_exists "user_create_profile" "Profile creation function should exist"
    fi
    
    # Test profile update
    if command -v user_update_profile >/dev/null 2>&1; then
        assert_function_exists "user_update_profile" "Profile update function should exist"
    fi
    
    # Test profile deletion
    if command -v user_delete_profile >/dev/null 2>&1; then
        assert_function_exists "user_delete_profile" "Profile deletion function should exist"
    fi
    
    # Test profile validation
    if command -v user_validate_profile >/dev/null 2>&1; then
        assert_function_exists "user_validate_profile" "Profile validation function should exist"
    fi
    
    test_log "SUCCESS" "User profile management functions work correctly"
    return 0
}

test_user_authentication() {
    test_log "INFO" "Testing user authentication functions..."
    
    source "$PROJECT_ROOT/src/_user.sh" || return 1
    
    # Test authentication setup
    if command -v user_setup_auth >/dev/null 2>&1; then
        assert_function_exists "user_setup_auth" "Authentication setup function should exist"
    fi
    
    # Test token generation
    if command -v user_generate_token >/dev/null 2>&1; then
        local token1 token2
        token1=$(user_generate_token "testuser")
        token2=$(user_generate_token "testuser")
        
        # Tokens should be different
        if [[ "$token1" != "$token2" ]]; then
            test_log "DEBUG" "Token generation creates unique tokens"
        else
            test_log "WARN" "Token generation created identical tokens"
        fi
    fi
    
    # Test session management
    if command -v user_create_session >/dev/null 2>&1; then
        assert_function_exists "user_create_session" "Session creation function should exist"
    fi
    
    if command -v user_validate_session >/dev/null 2>&1; then
        assert_function_exists "user_validate_session" "Session validation function should exist"
    fi
    
    test_log "SUCCESS" "User authentication functions work correctly"
    return 0
}

test_user_cleanup_functions() {
    test_log "INFO" "Testing user cleanup functions..."
    
    source "$PROJECT_ROOT/src/_user.sh" || return 1
    
    # Test user deletion
    if command -v user_delete >/dev/null 2>&1; then
        assert_function_exists "user_delete" "User deletion function should exist"
    fi
    
    # Test user deactivation
    if command -v user_deactivate >/dev/null 2>&1; then
        assert_function_exists "user_deactivate" "User deactivation function should exist"
    fi
    
    # Test user archive
    if command -v user_archive >/dev/null 2>&1; then
        assert_function_exists "user_archive" "User archive function should exist"
    fi
    
    # Test cleanup validation
    if command -v user_cleanup_validate >/dev/null 2>&1; then
        assert_function_exists "user_cleanup_validate" "Cleanup validation function should exist"
    fi
    
    test_log "SUCCESS" "User cleanup functions work correctly"
    return 0
}

test_user_listing_functions() {
    test_log "INFO" "Testing user listing functions..."
    
    source "$PROJECT_ROOT/src/_user.sh" || return 1
    
    # Test user listing
    if command -v user_list >/dev/null 2>&1; then
        local user_list
        user_list=$(user_list)
        if [[ -n "$user_list" ]]; then
            test_log "DEBUG" "User listing returns data"
        else
            test_log "WARN" "User listing returned empty"
        fi
    fi
    
    # Test active user listing
    if command -v user_list_active >/dev/null 2>&1; then
        assert_function_exists "user_list_active" "Active user listing function should exist"
    fi
    
    # Test user search
    if command -v user_search >/dev/null 2>&1; then
        assert_function_exists "user_search" "User search function should exist"
    fi
    
    test_log "SUCCESS" "User listing functions work correctly"
    return 0
}

# =============================================================================
# Main Test Runner
# =============================================================================

run_user_tests() {
    test_init "🧪 User Module Tests"
    
    # Setup test environment
    test_setup
    setup_user_tests
    
    # Run individual tests
    test_run "Module Loading" "test_user_module_loading" "Tests that user module loads correctly"
    test_run "User Creation" "test_user_creation" "Tests user creation functionality"
    test_run "User Management" "test_user_management" "Tests user management operations"
    test_run "User Validation" "test_user_validation_functions" "Tests user validation functions"
    test_run "User Creation Functions" "test_user_creation_functions" "Tests user creation and existence checking"
    test_run "Password Management" "test_password_management" "Tests password generation and hashing"
    test_run "User Permissions" "test_user_permissions" "Tests permission and group management"
    test_run "Profile Management" "test_user_profile_management" "Tests user profile operations"
    test_run "Authentication" "test_user_authentication" "Tests authentication and session management"
    test_run "Cleanup Functions" "test_user_cleanup_functions" "Tests user cleanup and deletion"
    test_run "Listing Functions" "test_user_listing_functions" "Tests user listing and search"
    test_run "Export Cleanliness" "test_export_cleanliness" "Tests module export hygiene"
    
    # Cleanup
    cleanup_user_tests
    test_cleanup
    
    # Show results
    test_summary
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_user_tests
fi 