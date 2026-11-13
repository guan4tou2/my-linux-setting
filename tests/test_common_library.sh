#!/usr/bin/env bash

# ==============================================================================
# Unit Tests for common.sh Functions
# ==============================================================================

# Source the common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LOG_DIR="/tmp/linux-setting-test-logs-$$"
export BACKUP_DIR="/tmp/linux-setting-test-backups-$$"
export CACHE_ENABLED="false"
export SKIP_NETWORK_TESTS="${SKIP_NETWORK_TESTS:-true}"
if [ -f "$SCRIPT_DIR/scripts/core/common.sh" ]; then
    source "$SCRIPT_DIR/scripts/core/common.sh"
else
    echo "Error: Cannot find common.sh"
    exit 1
fi
set +e
set +u

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
    assert_true "[ -d \"$LOG_DIR\" ]" "Log directory created"
}

# ==============================================================================
# Tests for System Check Functions
# ==============================================================================

test_distro_detection() {
    local distro
    distro=$(detect_distro)
    assert_true "[ -n \"$distro\" ]" "Distro detection returns non-empty string"
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
    if [ "$pkg_manager" = "dnf" ] || [ "$pkg_manager" = "yum" ]; then
        assert_equals "$pkg_manager" "$pkg_manager" "RHEL uses dnf or yum"
    else
        assert_equals "dnf|yum" "$pkg_manager" "RHEL uses dnf or yum"
    fi

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
    backup_file "$test_file" "$BACKUP_DIR"

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
    safe_download "https://nonexistent.invalid/file.sh" "$test_file"
    local result=$?
    assert_equals "1" "$result" "Invalid URL download fails"

    rm -f "$test_file"
}

# ==============================================================================
# Tests for Homebrew fallback behavior
# ==============================================================================

test_install_with_homebrew_fallback_no_brew() {
    # Force a PATH without brew to verify fallback behavior
    PATH="/nonexistent" PREFER_HOMEBREW=true install_with_homebrew_fallback "fakepkg" "fakebin"
    local result=$?
    assert_equals "1" "$result" "install_with_homebrew_fallback returns non-zero when brew is missing"
}

# ==============================================================================
# Tests for TUI dialog sizing
# ==============================================================================

test_tui_dialog_size() {
    local out h w lh sc

    # 單行短訊息：使用最小寬度與最小高度，不捲動
    out=$(TUI_TERM_ROWS=40 TUI_TERM_COLS=120 _tui_dialog_size yesno "短訊息" 0 0 4)
    read -r h w lh sc <<< "$out"
    assert_equals "9 60 0 0" "$h $w $lh $sc" "yesno 單行訊息使用最小尺寸"

    # 多行訊息（\n 表示換行）：高度隨行數增加，且足以容納所有行
    out=$(TUI_TERM_ROWS=40 TUI_TERM_COLS=120 _tui_dialog_size yesno "a\nb\nc\nd\ne\nf\ng\nh\ni\nj\nk\nl" 0 0 4)
    read -r h w lh sc <<< "$out"
    assert_equals "19 0" "$h $sc" "yesno 12 行訊息高度為行數 + 7 且不捲動"

    # 長行：寬度放寬到內容寬度，受終端機欄數上限限制
    local longline
    longline="$(printf 'x%.0s' $(seq 1 90))"
    out=$(TUI_TERM_ROWS=40 TUI_TERM_COLS=120 _tui_dialog_size yesno "$longline" 0 0 4)
    read -r h w lh sc <<< "$out"
    assert_equals "98" "$w" "長行會放寬對話框寬度"

    # 終端機較窄：寬度被限制在欄數 - 4，長行折成多行使高度增加
    local veryl
    veryl="$(printf 'x%.0s' $(seq 1 200))"
    out=$(TUI_TERM_ROWS=40 TUI_TERM_COLS=60 _tui_dialog_size yesno "$veryl" 0 0 4)
    read -r h w lh sc <<< "$out"
    assert_equals "56 11" "$w $h" "窄終端機限制寬度為欄數 - 4，200 字長行折成 4 行（高度 11）"

    # 中文為雙寬字元：40 個中文字（80 欄）不可被當成 40 欄
    local zh
    zh="$(printf '測試中文寬度%.0s' $(seq 1 7))"
    local zw
    zw=$(_tui_display_width "$zh")
    assert_true "[ '$zw' -ge 70 ]" "中文顯示寬度以雙寬估計（42 字 >= 70 欄）"
    assert_equals "5" "$(_tui_display_width abcde)" "ASCII 顯示寬度等於字元數"

    # 內容超過終端機高度：高度被限制在列數 - 2，並要求捲動
    local many="" i
    for i in $(seq 1 60); do many="${many}line $i\n"; done
    out=$(TUI_TERM_ROWS=32 TUI_TERM_COLS=100 _tui_dialog_size msgbox "$many" 0 0 4)
    read -r h w lh sc <<< "$out"
    assert_equals "30 1" "$h $sc" "超長訊息限制在終端機高度內並啟用捲動"

    # menu：提示文字多行時清單高度要跟著留位置，且不超出終端機
    out=$(TUI_TERM_ROWS=32 TUI_TERM_COLS=100 _tui_dialog_size menu "a\nb\nc\nd\ne" 3 20 4)
    read -r h w lh sc <<< "$out"
    assert_equals "15 3" "$h $lh" "menu 高度包含提示文字行數與項目數"

    # menu：提示文字過長時清單至少保留 3 列，整體仍不超過終端機高度
    out=$(TUI_TERM_ROWS=24 TUI_TERM_COLS=100 _tui_dialog_size checklist "$many" 10 20 4)
    read -r h w lh sc <<< "$out"
    assert_equals "3" "$lh" "checklist 提示過長時仍保留至少 3 列清單"
    assert_true "[ '$h' -le 22 ]" "checklist 高度不超過終端機高度"
}

test_tui_yesno_whiptail_args() {
    local tmp
    tmp=$(mktemp -d)
    cat > "$tmp/whiptail" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${FAKE_ARGS_FILE:?}"
exit 0
FAKE
    chmod +x "$tmp/whiptail"

    local many="" i
    for i in $(seq 1 60); do many="${many}line $i\n"; done

    (
        PATH="$tmp:$PATH" FAKE_ARGS_FILE="$tmp/args_long" USE_TUI=true TUI_BACKEND=whiptail \
        TUI_TERM_ROWS=32 TUI_TERM_COLS=100 tui_yesno "T" "$many" yes
    )
    (
        PATH="$tmp:$PATH" FAKE_ARGS_FILE="$tmp/args_short" USE_TUI=true TUI_BACKEND=whiptail \
        TUI_TERM_ROWS=32 TUI_TERM_COLS=100 tui_yesno "T" "第一行\n第二行\n第三行" no
    )
    local long_args short_args
    long_args=$(cat "$tmp/args_long")
    short_args=$(cat "$tmp/args_short")
    rm -rf "$tmp"

    assert_true "echo \"\$long_args\" | grep -qx -- '--scrolltext'" "超長 yesno 對話框加上 --scrolltext"
    assert_true "echo \"\$short_args\" | grep -qx -- '--defaultno'" "預設 no 時使用 --defaultno"
    assert_false "echo \"\$short_args\" | grep -qx -- '--scrolltext'" "短 yesno 對話框不使用 --scrolltext"
    assert_true "echo \"\$short_args\" | grep -q '第三行'" "yesno 內容完整交給 whiptail"
    assert_true "echo \"\$short_args\" | grep -qx '10'" "三行 yesno 高度為 10（行數 + 7）"
}

test_tui_fzf_expands_newlines() {
    local tmp
    tmp=$(mktemp -d)
    cat > "$tmp/fzf" <<'FAKE'
#!/usr/bin/env bash
cat >/dev/null
for a in "$@"; do
    case "$a" in --header=*) printf '%s' "${a#--header=}" > "${FAKE_HEADER_FILE:?}" ;; esac
done
printf 'Yes\n'
FAKE
    chmod +x "$tmp/fzf"

    (
        PATH="$tmp:$PATH" FAKE_HEADER_FILE="$tmp/header" USE_TUI=true TUI_BACKEND=fzf \
        tui_yesno "T" "第一行\n第二行" yes
    )
    local header
    header=$(cat "$tmp/header")
    rm -rf "$tmp"

    assert_false "echo \"\$header\" | grep -qF '\\n'" "fzf header 不含字面 \\n"
    assert_equals "2" "$(printf '%s\n' "$header" | wc -l | tr -d ' ')" "fzf header 多行提示正確換行"
}

# ==============================================================================
# Tests for package index handling and quiet-mode logging
# ==============================================================================

test_ensure_package_index_fresh_once() {
    local tmp
    tmp=$(mktemp -d)

    # 空的 apt lists：第一次呼叫要更新，同一行程第二次呼叫不可再更新
    local count
    count=$(
        unset LINUX_SETTING_PKG_INDEX_UPDATED LINUX_SETTING_PKG_INDEX_CHECKED
        PKG_MANAGER=apt
        APT_LISTS_DIR="$tmp/lists"; mkdir -p "$APT_LISTS_DIR"
        APT_PKGCACHE_FILE="$tmp/none1"; APT_UPDATE_STAMP_FILE="$tmp/none2"
        n=0
        update_system() { n=$((n + 1)); return 0; }
        ensure_package_index_fresh >/dev/null 2>&1
        ensure_package_index_fresh >/dev/null 2>&1
        ensure_package_index_fresh >/dev/null 2>&1
        echo "$n"
    )
    assert_equals "1" "$count" "ensure_package_index_fresh 同一行程只更新一次"

    # 索引新鮮：完全不更新
    mkdir -p "$tmp/fresh"
    echo "pkg" > "$tmp/fresh/archive.ubuntu.com_dists_jammy_main_binary-amd64_Packages"
    count=$(
        unset LINUX_SETTING_PKG_INDEX_UPDATED LINUX_SETTING_PKG_INDEX_CHECKED
        PKG_MANAGER=apt
        APT_LISTS_DIR="$tmp/fresh"
        APT_PKGCACHE_FILE="$tmp/none1"; APT_UPDATE_STAMP_FILE="$tmp/none2"
        n=0
        update_system() { n=$((n + 1)); return 0; }
        ensure_package_index_fresh >/dev/null 2>&1
        echo "$n"
    )
    assert_equals "0" "$count" "索引新鮮時不更新"

    # 索引過舊：更新（把檔案時間改成很久以前）
    touch -t 200001010000 "$tmp/fresh/archive.ubuntu.com_dists_jammy_main_binary-amd64_Packages"
    count=$(
        unset LINUX_SETTING_PKG_INDEX_UPDATED LINUX_SETTING_PKG_INDEX_CHECKED
        PKG_MANAGER=apt
        APT_LISTS_DIR="$tmp/fresh"
        APT_PKGCACHE_FILE="$tmp/none1"; APT_UPDATE_STAMP_FILE="$tmp/none2"
        n=0
        update_system() { n=$((n + 1)); return 0; }
        ensure_package_index_fresh >/dev/null 2>&1
        echo "$n"
    )
    assert_equals "1" "$count" "索引過舊時更新"

    # 更新失敗只警告，不中斷（回傳 0）
    (
        unset LINUX_SETTING_PKG_INDEX_UPDATED LINUX_SETTING_PKG_INDEX_CHECKED
        PKG_MANAGER=apt
        APT_LISTS_DIR="$tmp/lists"
        APT_PKGCACHE_FILE="$tmp/none1"; APT_UPDATE_STAMP_FILE="$tmp/none2"
        update_system() { return 1; }
        ensure_package_index_fresh >/dev/null 2>&1
    )
    assert_equals "0" "$?" "套件索引更新失敗不會中斷"

    rm -rf "$tmp"
}

test_update_system_skips_when_already_updated() {
    local tmp
    tmp=$(mktemp -d)
    cat > "$tmp/apt-get" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "${FAKE_APT_CALLS:?}"
exit 0
FAKE
    chmod +x "$tmp/apt-get"

    local calls
    calls=$(
        unset LINUX_SETTING_PKG_INDEX_UPDATED LINUX_SETTING_PKG_INDEX_CHECKED
        export PATH="$tmp:$PATH" FAKE_APT_CALLS="$tmp/calls"
        PKG_MANAGER=apt TUI_MODE=quiet LOG_FILE=""
        sudo() { env "$@"; }
        update_system >/dev/null 2>&1
        update_system >/dev/null 2>&1
        update_system force >/dev/null 2>&1
        grep -c '^update' "$tmp/calls"
    )
    rm -rf "$tmp"
    assert_equals "2" "$calls" "update_system 第二次略過、force 才會重新更新"
}

test_update_system_rpm_exit_codes() {
    local manager code out
    for manager in dnf yum; do
        for code in 0 100 1 42; do
            out=$(
                set -euo pipefail
                unset LINUX_SETTING_PKG_INDEX_UPDATED
                PKG_MANAGER="$manager"
                log_info() { :; }
                _pkg_root_exec() {
                    [ "$2" = "$manager" ] && [ "$3" = check-update ] || return 99
                    return "$code"
                }
                rc=0; update_system || rc=$?
                printf '%s:%s' "$rc" "${LINUX_SETTING_PKG_INDEX_UPDATED:-未設定}"
            )
            case "$code" in
                0|100) assert_equals "0:1" "$out" "$manager check-update $code 視為成功並標記更新" ;;
                *) assert_equals "$code:未設定" "$out" "$manager check-update $code 保留失敗且不標記更新" ;;
            esac
        done
    done
}

test_tui_actual_terminal_minimum() {
    local size rows cols rc
    for size in '14 80' '24 49' '14 49' '15 50' '24 80' '0 0' '未知 未知'; do
        read -r rows cols <<< "$size"
        rc=0
        _tui_terminal_too_small "$rows" "$cols" || rc=$?
        case "$size" in
            '14 80'|'24 49'|'14 49'|'0 0') assert_equals 0 "$rc" "實際尺寸 $size 改用命令行模式" ;;
            *) assert_equals 1 "$rc" "實際尺寸 $size 不觸發過小判斷" ;;
        esac
    done
}

test_install_package_quiet_logs_failure_output() {
    local tmp
    tmp=$(mktemp -d)
    cat > "$tmp/apt-get" <<'FAKE'
#!/usr/bin/env bash
echo "E: Unable to locate package $*" >&2
echo "some stdout noise"
exit 100
FAKE
    chmod +x "$tmp/apt-get"

    local rc terminal
    terminal=$(
        export PATH="$tmp:$PATH"
        PKG_MANAGER=apt TUI_MODE=quiet LOG_FILE="$tmp/test.log"
        sudo() { env "$@"; }
        install_package "zz-no-such-package-zz" 2>&1
        echo "rc=$?"
    )
    rc="${terminal##*rc=}"
    assert_equals "1" "$rc" "安裝失敗時 install_package 回傳 1"
    assert_true "grep -q 'Unable to locate package' '$tmp/test.log'" "quiet 模式的 apt 錯誤輸出寫入日誌"
    assert_true "grep -q 'some stdout noise' '$tmp/test.log'" "quiet 模式的 stdout 也寫入日誌"
    assert_false "echo \"\$terminal\" | grep -q 'Unable to locate package'" "quiet 模式終端機不顯示 apt 輸出"

    # LOG_FILE 未設定時丟棄輸出，且不報錯
    terminal=$(
        export PATH="$tmp:$PATH"
        PKG_MANAGER=apt TUI_MODE=quiet LOG_FILE=""
        sudo() { env "$@"; }
        install_package "zz-no-such-package-zz" 2>&1
        echo "rc=$?"
    )
    assert_false "echo \"\$terminal\" | grep -q 'Unable to locate package'" "未設定 LOG_FILE 時 quiet 模式丟棄輸出"
    rm -rf "$tmp"
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

    echo "Testing Homebrew Fallback..."
    test_install_with_homebrew_fallback_no_brew
    echo ""

    echo "Testing TUI Dialog Sizing..."
    test_tui_actual_terminal_minimum
    test_tui_dialog_size
    test_tui_yesno_whiptail_args
    test_tui_fzf_expands_newlines
    echo ""

    echo "Testing Package Index and Quiet-mode Logging..."
    test_ensure_package_index_fresh_once
    test_update_system_skips_when_already_updated
    test_update_system_rpm_exit_codes
    test_install_package_quiet_logs_failure_output
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
