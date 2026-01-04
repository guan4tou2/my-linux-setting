#!/usr/bin/env bash

# ==============================================================================
# Security Audit Tests for Linux Setting Scripts
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly NC='\033[0m'

# Test counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

# Helper functions
check_pass() {
    local check_name="$1"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
    echo -e "${GREEN}✓ PASS${NC}: $check_name"
}

check_fail() {
    local check_name="$1"
    local details="${2:-}"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
    echo -e "${RED}✗ FAIL${NC}: $check_name"
    [ -n "$details" ] && echo "  → $details"
}

check_warn() {
    local check_name="$1"
    local details="${2:-}"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    WARNINGS=$((WARNINGS + 1))
    echo -e "${YELLOW}⚠ WARN${NC}: $check_name"
    [ -n "$details" ] && echo "  → $details"
}

# ==============================================================================
# Script Security Checks
# ==============================================================================

check_script_permissions() {
    echo ""
    echo "=== Script Permissions ==="

    local scripts
    scripts=$(find "$SCRIPT_DIR" -name "*.sh" -type f)

    for script in $scripts; do
        local perms
        perms=$(stat -c %a "$script" 2>/dev/null || stat -f %Lp "$script" 2>/dev/null)

        # Check if scripts are not world-writable
        if echo "$perms" | grep -q ".[2-9]$"; then
            check_fail "World-writable script" "$script"
        else
            check_pass "Proper permissions on $(basename "$script")"
        fi

        # Check for proper shebang
        if head -1 "$script" | grep -qE '^#!/(usr/bin/env )?(ba|z)?sh$'; then
            check_pass "Valid shebang in $(basename "$script")"
        else
            check_warn "Missing or invalid shebang" "$script"
        fi
    done
}

check_dangerous_commands() {
    echo ""
    echo "=== Dangerous Command Checks ==="

    local dangerous_patterns=(
        "rm[[:space:]]*-rf[[:space:]]+/"
        "dd[[:space:]]+if="
        "mkfs\."
        ":(){ :|:& };:"
        "eval[[:space:]]+\$\(.*\)"
    )

    local scripts
    scripts=$(find "$SCRIPT_DIR" -name "*.sh" -type f)

    for script in $scripts; do
        for pattern in "${dangerous_patterns[@]}"; do
            if grep -qE "$pattern" "$script" 2>/dev/null; then
                # Check if it's in a comment
                local line_num
                line_num=$(grep -nE "$pattern" "$script" | head -1 | cut -d: -f1)
                local line_content
                line_content=$(sed -n "${line_num}p" "$script")

                if ! echo "$line_content" | grep -qE '^\s*#'; then
                    check_fail "Dangerous pattern found" "$(basename "$script"):$line_num - $pattern"
                fi
            fi
        done
    done
}

check_hardcoded_secrets() {
    echo ""
    echo "=== Hardcoded Secrets Check ==="

    local secret_patterns=(
        "password[[:space:]]*=[\"']?[^\"]+[\"']"
        "api_key[[:space:]]*=[\"']?[^\"]+[\"']"
        "token[[:space:]]*=[\"']?[^\"]+[\"']"
        "secret[[:space:]]*=[\"']?[^\"]+[\"']"
    )

    local scripts
    scripts=$(find "$SCRIPT_DIR" -name "*.sh" -type f)

    local found=false
    for script in $scripts; do
        for pattern in "${secret_patterns[@]}"; do
            if grep -qiE "$pattern" "$script" 2>/dev/null; then
                local line_num
                line_num=$(grep -nE "$pattern" "$script" | head -1 | cut -d: -f1)
                check_fail "Potential hardcoded secret" "$(basename "$script"):$line_num"
                found=true
            fi
        done
    done

    $found || check_pass "No hardcoded secrets found"
}

check_insecure_downloads() {
    echo ""
    echo "=== Insecure Download Checks ==="

    local insecure_patterns=(
        "curl.*[|].*sh"
        "wget.*[|].*sh"
        "curl.*[|].*bash"
        "wget.*[|].*bash"
    )

    local scripts
    scripts=$(find "$SCRIPT_DIR" -name "*.sh" -type f)

    for script in $scripts; do
        for pattern in "${insecure_patterns[@]}"; do
            if grep -qE "$pattern" "$script" 2>/dev/null; then
                local line_num
                line_num=$(grep -nE "$pattern" "$script" | head -1 | cut -d: -f1)

                # Check if it's a trusted download (has SECURE_DOWNLOAD_ALLOW_PIPE or is in allowed list)
                local line_content
                line_content=$(sed -n "${line_num}p" "$script")
                local prev_line
                prev_line=$(sed -n "$((line_num - 1))p" "$script")

                if ! echo "$prev_line" | grep -q "SECURE_DOWNLOAD_ALLOW_PIPE=1"; then
                    check_warn "Unverified pipe to shell" "$(basename "$script"):$line_num"
                fi
            fi
        done
    done
}

check_sudo_usage() {
    echo ""
    echo "=== Excessive Sudo Usage Check ==="

    local scripts
    scripts=$(find "$SCRIPT_DIR" -name "*.sh" -type f)

    for script in $scripts; do
        local sudo_count
        sudo_count=$(grep -cE "^\s*(sudo|su)\s" "$script" 2>/dev/null || echo 0)

        if [ "$sudo_count" -gt 30 ]; then
            check_fail "Excessive sudo usage" "$(basename "$script") has $sudo_count sudo commands"
        elif [ "$sudo_count" -gt 20 ]; then
            check_warn "High sudo usage" "$(basename "$script") has $sudo_count sudo commands"
        else
            check_pass "Reasonable sudo count in $(basename "$script") ($sudo_count)"
        fi
    done
}

check_temp_file_cleanup() {
    echo ""
    echo "=== Temporary File Cleanup ==="

    local scripts
    scripts=$(find "$SCRIPT_DIR" -name "*.sh" -type f)

    for script in $scripts; do
        local temp_patterns=(
            "mktemp"
            "/tmp/"
            "\$\${TEMP_DIR}"
        )

        for pattern in "${temp_patterns[@]}"; do
            if grep -qE "$pattern" "$script" 2>/dev/null; then
                # Check if there's cleanup code
                if grep -q "rm.*-rf.*tmp" "$script" || grep -q "cleanup_temp_files" "$script"; then
                    check_pass "Has temp file cleanup" "$(basename "$script")"
                else
                    check_warn "Possible temp file leak" "$(basename "$script") - creates temp files but may not clean them"
                fi
                break
            fi
        done
    done
}

check_input_validation() {
    echo ""
    echo "=== Input Validation Checks ==="

    local scripts
    scripts=$(find "$SCRIPT_DIR" -name "*.sh" -type f)

    for script in $scripts; do
        # Check for unchecked user input
        if grep -q "read.*-r.*\|.*\$" "$script" 2>/dev/null; then
            # Check if there's any validation
            local read_line
            read_line=$(grep -n "read" "$script" | head -1 | cut -d: -f1)
            local next_5_lines
            next_5_lines=$(sed -n "$((read_line + 1)),$((read_line + 5))p" "$script")

            if ! echo "$next_5_lines" | grep -qiE "grep|test|\[|\[\[|case|validate"; then
                check_warn "Unchecked user input" "$(basename "$script"):$read_line"
            fi
        fi
    done
}

check_error_handling() {
    echo ""
    echo "=== Error Handling Checks ==="

    local scripts
    scripts=$(find "$SCRIPT_DIR" -name "*.sh" -type f)

    for script in $scripts; do
        # Check for set -e
        if grep -q "set -e" "$script" 2>/dev/null; then
            check_pass "Has error handling (set -e)" "$(basename "$script")"
        else
            check_warn "Missing error handling (set -e)" "$(basename "$script")"
        fi

        # Check for trap
        if grep -q "trap.*ERR" "$script" 2>/dev/null; then
            check_pass "Has error trap" "$(basename "$script")"
        else
            check_warn "Missing error trap" "$(basename "$script")"
        fi
    done
}

check_path_traversal() {
    echo ""
    echo "=== Path Traversal Vulnerability Check ==="

    local scripts
    scripts=$(find "$SCRIPT_DIR" -name "*.sh" -type f)

    for script in $scripts; do
        # Check for unsafe path operations
        local unsafe_patterns=(
            "cat.*\$USER_INPUT"
            "rm.*\$USER_INPUT"
            "\.\.\/"
        )

        for pattern in "${unsafe_patterns[@]}"; do
            if grep -qiE "$pattern" "$script" 2>/dev/null; then
                check_fail "Potential path traversal" "$(basename "$script") - $pattern"
            fi
        done
    done
}

check_configuration_files() {
    echo ""
    echo "=== Configuration File Security ==="

    local config_files=(
        "$HOME/.config/linux-setting/config"
        "$HOME/.config/linux-setting.conf"
    )

    for config_file in "${config_files[@]}"; do
        if [ -f "$config_file" ]; then
            local perms
            perms=$(stat -c %a "$config_file" 2>/dev/null || stat -f %Lp "$config_file" 2>/dev/null)

            if echo "$perms" | grep -q ".[0-6]$"; then
                check_pass "Config file is not world-writable" "$(basename "$config_file")"
            else
                check_fail "Config file is world-writable" "$(basename "$config_file")"
            fi
        fi
    done
}

# ==============================================================================
# Dependency Checks
# ==============================================================================

check_suspicious_dependencies() {
    echo ""
    echo "=== Suspicious Dependency Check ==="

    local suspicious_packages=(
        "netcat"
        "nc"
        "backdoor"
        "rootkit"
        "keylogger"
    )

    for script in "$SCRIPT_DIR"/scripts/core/*.sh "$SCRIPT_DIR"/scripts/utils/*.sh; do
        [ -f "$script" ] || continue

        for pkg in "${suspicious_packages[@]}"; do
            if grep -qi "$pkg" "$script" 2>/dev/null; then
                # Check if it's in comments
                local line_num
                line_num=$(grep -n "$pkg" "$script" | head -1 | cut -d: -f1)
                local line_content
                line_content=$(sed -n "${line_num}p" "$script")

                if ! echo "$line_content" | grep -qE '^\s*#'; then
                    check_fail "Suspicious package reference" "$(basename "$script"):$line_num - $pkg"
                fi
            fi
        done
    done
}

# ==============================================================================
# Run All Checks
# ==============================================================================

run_security_audit() {
    echo "=========================================================================="
    echo "Security Audit for Linux Setting Scripts"
    echo "=========================================================================="
    echo ""

    check_script_permissions
    check_dangerous_commands
    check_hardcoded_secrets
    check_insecure_downloads
    check_sudo_usage
    check_temp_file_cleanup
    check_input_validation
    check_error_handling
    check_path_traversal
    check_configuration_files
    check_suspicious_dependencies

    echo ""
    echo "=========================================================================="
    echo "Security Audit Summary"
    echo "=========================================================================="
    echo "Total Checks: $TOTAL_CHECKS"
    echo -e "Passed: ${GREEN}$PASSED_CHECKS${NC}"
    echo -e "Failed: ${RED}$FAILED_CHECKS${NC}"
    echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
    echo ""

    if [ $FAILED_CHECKS -eq 0 ]; then
        echo -e "${GREEN}✓ No critical security issues found!${NC}"
        return 0
    else
        echo -e "${RED}✗ Found $FAILED_CHECKS critical security issues!${NC}"
        return 1
    fi
}

# Run audit if executed directly
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    run_security_audit
    exit $?
fi
