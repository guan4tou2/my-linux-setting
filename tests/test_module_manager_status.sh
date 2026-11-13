#!/usr/bin/env bash

# ==============================================================================
# Module manager status/detail regression tests
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log_warn() {
    printf '[WARN] %s\n' "$1"
}

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
    log_warn "略過模組狀態測試：需要 Bash 4+（關聯陣列），不計入通過"
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

test_package_command_fallback() {
    local result rc=0
    result=$(
        bash -s -- "$SCRIPT_DIR/scripts/core/module_manager.sh" <<'RUN'
        set -euo pipefail
        source "$1"
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        HOME="$tmp/home"
        mkdir -p "$HOME/.local/bin" "$HOME/.cargo/bin" "$tmp/path"
        check_package_installed() { return 1; }
        check_brew_package_installed() { return 1; }
        # PATH 以外的可執行檔也能滿足三種套件類別。
        printf '#!/bin/sh\nexit 0\n' > "$HOME/.local/bin/tldr"
        chmod +x "$HOME/.local/bin/tldr"
        for kind in apt apt_fallback brew; do
            _module_pkg_is_installed "$kind" tealdeer
            [ "${MODULE_PKG_STATUS_CACHE[$kind:tealdeer]:-}" = 1 ]
        done
        MODULE_LIST=(demo)
        MODULE_PACKAGES[demo]=tealdeer
        [ "$(check_module_status demo)" = installed ]
        # 明確測試別名、PATH、cargo 目錄以及不可執行檔。
        printf '#!/bin/sh\nexit 0\n' > "$tmp/path/rg"
        chmod +x "$tmp/path/rg"
        PATH="$tmp/path:$PATH" _module_pkg_is_installed apt ripgrep
        printf '#!/bin/sh\nexit 0\n' > "$HOME/.cargo/bin/module-test-cargo"
        chmod +x "$HOME/.cargo/bin/module-test-cargo"
        _module_pkg_is_installed apt module-test-cargo
        touch "$HOME/.local/bin/module-test-not-executable"
        if _module_pkg_is_installed apt module-test-not-executable; then exit 1; fi
        # 負快取維持有效，清除後才會看到新加入的指令。
        chmod +x "$HOME/.local/bin/module-test-not-executable"
        if _module_pkg_is_installed apt module-test-not-executable; then exit 1; fi
        _module_pkg_status_cache_clear
        _module_pkg_is_installed apt module-test-not-executable
        for pair in 'lazygit:lazygit' 'lsd:lsd' 'tealdeer:tldr' 'fd-find:fd fdfind' \
            'fd:fd fdfind' 'ripgrep:rg' 'bat:bat batcat' 'neovim:nvim' \
            'nodejs:node nodejs' 'node:node nodejs' 'lua5.4:lua lua5.4' \
            'lua:lua lua5.4' 'luarocks:luarocks' 'btop:btop' 'fzf:fzf'; do
            [ "$(_module_pkg_commands "${pair%%:*}")" = "${pair#*:}" ]
        done
        printf ok
RUN
    ) || rc=$?
    assert_equals "0:ok" "$rc:$result" "套件管理器查不到時以指令判斷，並保留狀態快取"
}

test_install_module_reconciles_script_packages() {
    local result rc=0
    result=$(
        bash -s -- "$SCRIPT_DIR/scripts/core/module_manager.sh" <<'RUN'
        set -euo pipefail
        source "$1"
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        HOME="$tmp/home"
        SCRIPT_DIR="$tmp/scripts"
        mkdir -p "$SCRIPT_DIR/core" "$HOME/.local/bin"
        log_info() { printf '%s\n' "$*" >> "$tmp/log"; }
        log_warning() { :; }
        log_success() { :; }
        log_error() { :; }
        ensure_package_index_fresh() { :; }
        check_package_installed() { return 1; }
        check_brew_package_installed() { return 1; }
        install_apt_packages_parallel() {
            printf '%s\n' "$*" >> "$tmp/apt-calls"
            APT_BATCH_FAILED_PACKAGES=("$@")
            return 1
        }
        # 這是隔離的假設定腳本，只在暫存 HOME 建立假指令。
        cat > "$SCRIPT_DIR/core/fake.sh" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '#!/bin/sh\nexit 0\n' > "$HOME/.local/bin/module-test-recovered"
chmod +x "$HOME/.local/bin/module-test-recovered"
FAKE
        MODULE_LIST=(demo)
        MODULE_NAMES[demo]=demo
        MODULE_APT_FALLBACK[demo]="module-test-recovered module-test-missing"
        MODULE_SCRIPTS[demo]=fake.sh
        MODULE_POST_INSTALL[demo]='printf "#!/bin/sh\nexit 0\n" > "$HOME/.local/bin/module-test-post"; chmod +x "$HOME/.local/bin/module-test-post"'
        MODULE_PACKAGES[demo]=module-test-post
        install_module demo
        [ "${MODULE_INSTALL_FAILURES[0]}" = 'demo: apt:module-test-missing' ]
        grep -q 'module-test-recovered 已由設定腳本安裝' "$tmp/log"
        grep -q 'module-test-post 已由設定腳本安裝' "$tmp/log"
        _module_pkg_is_installed apt module-test-recovered
        _module_pkg_is_installed apt_fallback module-test-recovered
        # 第二輪不可再向 APT 安裝已補裝的工具。
        : > "$tmp/apt-calls"
        install_module demo
        [ "$(cat "$tmp/apt-calls")" = module-test-missing ]
        # 所有失敗都已補裝時，不應留下空的失敗摘要。
        MODULE_APT_FALLBACK[demo]=module-test-recovered
        MODULE_INSTALL_FAILURES=()
        rm "$HOME/.local/bin/module-test-recovered"
        _module_pkg_status_cache_clear
        install_module demo
        [ "${#MODULE_INSTALL_FAILURES[@]}" -eq 0 ]
        printf ok
RUN
    ) || rc=$?
    assert_equals "0:ok" "$rc:$result" "設定腳本與 post_install 補裝後移除失敗，重跑跳過 APT"
}

run_all_tests() {
    echo "========================================"
    echo "Module Manager Status Tests"
    echo "========================================"

    test_module_detail_reuses_package_status_checks
    test_package_command_fallback
    test_install_module_reconciles_script_packages

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
