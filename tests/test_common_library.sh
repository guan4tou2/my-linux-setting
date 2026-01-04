#!/usr/bin/env bash

# ==============================================================================
# Unit Tests for common.sh Functions
# ==============================================================================

# Source the common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../core/common.sh" ]; then
    source "$SCRIPT_DIR/../core/common.sh"
else
    echo "Error: Cannot find common.sh"
    exit 1
fi

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ "$expected" = "$actual" ]; then
        echo "✓ PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo "✗ FAIL: $test_name"
        echo "  Expected: $expected"
        echo "  Actual: $actual"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_true() {
    local condition="$1"
    local test_name="$2"

    if eval "$condition"; then
        assert_equals "true" "true" "$test_name"
    else
        assert_equals "true" "false" "$test_name"
    fi
}

assert_false() {
    local condition="$1"
    local test_name="$2"

    if ! eval "$condition"; then
        assert_equals "false" "false" "$test_name"
    else
        assert_equals "false" "true" "$test_name"
    fi
}

# ==============================================================================
# Tests for Logging Functions
# ==============================================================================

test_log_functions_exist() {
    assert_true "command -v log_error" "log_error function exists"
    assert_true "command -v log_info" "log_info function exists"
    assert_true "command -v log_success" "log_success function exists"
    assert_true "command -v log_warning" "log_warning function exists"
    assert_true "command -v log_debug" "log_debug function exists"
}

test_init_logging() {
    # Test that init_logging creates log directory
    init_logging
    assert_true "[ -d '$LOG_DIR']" "Log directory created"
}

# ==============================================================================
# Tests for System Check Functions
# ==============================================================================

test_distro_detection() {
    local distro
    distro=$(detect_distro)
    assert_true "[ -n '$distro']" "Distro detection returns non-empty string"
}

test_distro_family() {
    local family
    family=$(get_distro_family "ubuntu")
    assert_equals "debian" "$family" "Ubuntu distro family is debian"

    family=$(get_distro_family "fedora")
    assert_equals "rhel" "$family" "Fedora distro family is rhel"
}

test_package_manager() {
    local pkg_manager
    pkg_manager=$(get_package_manager "debian")
    assert_equals "apt" "$pkg_manager" "Debian uses apt"

    pkg_manager=$(get_package_manager "rhel")
    assert_equals "dnf" "$pkg_manager" "RHEL uses dnf (or yum)"

    pkg_manager=$(get_package_manager "arch")
    assert_equals "pacman" "$pkg_manager" "Arch uses pacman"
}

test_command_check() {
    assert_true "check_command bash" "bash command exists"
    assert_false "check_command nonexistentcommand123" "nonexistent command check returns false"
}

# ==============================================================================
# Tests for Version Comparison
# ==============================================================================

test_version_comparison() {
    assert_true "version_greater_equal '2.0.0' '1.9.0'" "2.0.0 >= 1.9.0"
    assert_true "version_greater_equal '2.0.0' '2.0.0'" "2.0.0 >= 2.0.0"
    assert_false "version_greater_equal '1.9.0' '2.0.0'" "1.9.0 < 2.0.0"
    assert_true "version_greater_equal '2.1.3' '2.1.2'" "2.1.3 >= 2.1.2"
}

# ==============================================================================
# Tests for Architecture Detection
# ==============================================================================

test_architecture_compatibility() {
    local arch
    arch=$(uname -m)

    case "$arch" in
        x86_64|amd64|aarch64|arm64)
            assert_true "check_architecture_compatibility" "$arch is supported"
            ;;
        *)
            assert_false "check_architecture_compatibility" "$arch is not supported"
            ;;
    esac
}

# ==============================================================================
# Tests for String Operations
# ==============================================================================

test_string_operations() {
    # Test backup file naming
    local test_file="/tmp/test_file_$$"
    touch "$test_file"
    backup_file "$test_file"

    local backup_count
    backup_count=$(find "$BACKUP_DIR" -name "*test_file_*" 2>/dev/null | wc -l)

    assert_true "[ '$backup_count' -ge 1 ]" "Backup created"

    # Cleanup
    rm -f "$test_file"
    rm -rf "$BACKUP_DIR"
}

# ==============================================================================
# Tests for Safe Download
# ==============================================================================

test_safe_download_invalid_url() {
    if [ "${SKIP_NETWORK_TESTS:-}" = "true" ]; then
        echo "- SKIP: test_safe_download_invalid_url (network tests disabled)"
        return 0
    fi

    local test_file="/tmp/test_download_$$"
    ! safe_download "https://nonexistent.invalid/file.sh" "$test_file"
    local result=$?
    assert_equals "1" "$result" "Invalid URL download fails"

    rm -f "$test_file"
}

# ==============================================================================
# Test Runner
# ==============================================================================

run_all_tests() {
    echo "========================================================================"
    echo "Running Unit Tests for common.sh"
    echo "========================================================================"
    echo ""

    echo "Testing Logging Functions..."
    test_log_functions_exist
    test_init_logging
    echo ""

    echo "Testing System Check Functions..."
    test_distro_detection
    test_distro_family
    test_package_manager
    test_command_check
    echo ""

    echo "Testing Version Comparison..."
    test_version_comparison
    echo ""

    echo "Testing Architecture Detection..."
    test_architecture_compatibility
    echo ""

    echo "Testing String Operations..."
    test_string_operations
    echo ""

    echo "Testing Safe Download..."
    test_safe_download_invalid_url
    echo ""

    # Print summary
    echo "========================================================================"
    echo "Test Summary"
    echo "========================================================================"
    echo "Total: $TESTS_RUN"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        echo "✓ All tests passed!"
        return 0
    else
        echo "✗ Some tests failed"
        return 1
    fi
}

# Run tests if script is executed directly
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    # Set test mode
    export ENABLE_LOGGING=false
    export DEBUG=false

    run_all_tests
    exit $?
fi
