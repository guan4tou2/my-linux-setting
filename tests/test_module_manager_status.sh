#!/usr/bin/env bash

# ==============================================================================
# Module manager status/detail regression tests
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    for brew_bash in \
        /opt/homebrew/bin/bash \
        /usr/local/bin/bash \
        /home/linuxbrew/.linuxbrew/bin/bash \
        "$HOME/.linuxbrew/bin/bash"; do
        if [ -x "$brew_bash" ] && "$brew_bash" --version 2>/dev/null | grep -q "version [4-9]"; then
            exec "$brew_bash" "$0" "$@"
        fi
    done
    echo "========================================"
    echo "Module Manager Status Tests"
    echo "========================================"
    echo "[SKIP] module_manager status tests require Bash 4+"
    echo "========================================"
    echo "測試結果"
    echo "========================================"
    echo "通過: 0"
    echo "失敗: 0"
    echo "總計: 0"
    exit 0
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local name="$3"

    if [ "$expected" = "$actual" ]; then
        log_pass "$name"
    else
        log_fail "$name (expected: $expected, actual: $actual)"
    fi
}

test_module_detail_reuses_package_status_checks() {
    source "$SCRIPT_DIR/scripts/core/module_manager.sh"

    MODULE_LIST=(demo)
    MODULE_NAMES["demo"]="Demo"
    MODULE_DESCRIPTIONS["demo"]="Demo module"
    MODULE_PACKAGES["demo"]="apt-one apt-two"
    MODULE_PIP_PACKAGES["demo"]="py-one"
    MODULE_CARGO_PACKAGES["demo"]="cargo-one"
    MODULE_NPM_PACKAGES["demo"]="npm-one"

    APT_CHECKS=0
    PIP_CHECKS=0
    CARGO_CHECKS=0
    NPM_CHECKS=0

    check_package_installed() {
        APT_CHECKS=$((APT_CHECKS + 1))
        [ "$1" = "apt-one" ]
    }

    check_pip_package_installed() {
        PIP_CHECKS=$((PIP_CHECKS + 1))
        return 1
    }

    check_cargo_package_installed() {
        CARGO_CHECKS=$((CARGO_CHECKS + 1))
        return 1
    }

    check_npm_package_installed() {
        NPM_CHECKS=$((NPM_CHECKS + 1))
        return 1
    }

    cargo() { return 0; }
    npm() { return 0; }

    get_module_detail_status demo >/dev/null

    assert_equals "2" "$APT_CHECKS" "APT package status is checked once per package"
    assert_equals "1" "$PIP_CHECKS" "pip package status is checked once per package"
    assert_equals "1" "$CARGO_CHECKS" "cargo package status is checked once per package"
    assert_equals "1" "$NPM_CHECKS" "npm package status is checked once per package"
}

run_all_tests() {
    echo "========================================"
    echo "Module Manager Status Tests"
    echo "========================================"

    test_module_detail_reuses_package_status_checks

    echo "========================================"
    echo "測試結果"
    echo "========================================"
    echo "通過: $TESTS_PASSED"
    echo "失敗: $TESTS_FAILED"
    echo "總計: $((TESTS_PASSED + TESTS_FAILED))"

    if [ "$TESTS_FAILED" -eq 0 ]; then
        exit 0
    fi
    exit 1
}

run_all_tests
