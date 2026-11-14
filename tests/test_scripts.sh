#!/usr/bin/env bash
#!/bin/bash

# 腳本測試工具
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_PASSED=0
TESTS_FAILED=0

# 測試顏色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_test() {
    echo -e "${GREEN}[TEST]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Portable text search helper.
# Prefer ripgrep when available, fallback to grep in minimal CI images.
search_text() {
    local pattern="$1"
    local file="$2"

    if command -v rg >/dev/null 2>&1; then
        rg -n "$pattern" "$file" >/dev/null 2>&1
    else
        grep -nE "$pattern" "$file" >/dev/null 2>&1
    fi
}

# Portable literal text search helper.
search_literal() {
    local pattern="$1"
    local file="$2"

    if command -v rg >/dev/null 2>&1; then
        rg -F -n "$pattern" "$file" >/dev/null 2>&1
    else
        grep -F -n "$pattern" "$file" >/dev/null 2>&1
    fi
}

# 測試腳本語法
test_script_syntax() {
    log_test "測試腳本語法..."
    
    for script in "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR"/scripts/*/*.sh; do
        if [ -f "$script" ]; then
            if bash -n "$script" 2>/dev/null; then
                log_pass "$(basename "$script") 語法正確"
            else
                log_fail "$(basename "$script") 語法錯誤"
            fi
        fi
    done
}

# 測試腳本權限
test_script_permissions() {
    log_test "測試腳本權限..."
    
    for script in "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR"/scripts/*/*.sh; do
        if [ -f "$script" ]; then
            if [ -x "$script" ]; then
                log_pass "$(basename "$script") 具有執行權限"
            else
                log_fail "$(basename "$script") 缺少執行權限"
            fi
        fi
    done
}

# 測試共用函數庫
test_common_library() {
    log_test "測試共用函數庫..."
    
    if [ -f "$SCRIPT_DIR/scripts/core/common.sh" ]; then
        if source "$SCRIPT_DIR/scripts/core/common.sh" 2>/dev/null; then
            log_pass "common.sh 載入成功"
            
            # 測試關鍵函數是否存在
            if declare -f log_info >/dev/null 2>&1; then
                log_pass "log_info 函數存在"
            else
                log_fail "log_info 函數不存在"
            fi
            
            if declare -f check_command >/dev/null 2>&1; then
                log_pass "check_command 函數存在"
            else
                log_fail "check_command 函數不存在"
            fi
        else
            log_fail "common.sh 載入失敗"
        fi
    else
        log_fail "common.sh 文件不存在"
    fi
}

# 測試必要文件存在
test_required_files() {
    log_test "測試必要文件..."
    
    required_files=(
        "install.sh"
        "requirements.txt"
        "scripts/core/common.sh"
        "scripts/core/python_setup.sh"
        "scripts/core/terminal_setup.sh"
        "scripts/maintenance/health_check.sh"
        "scripts/maintenance/update_tools.sh"
        "README.md"
    )
    
    for file in "${required_files[@]}"; do
        if [ -f "$SCRIPT_DIR/$file" ]; then
            log_pass "$file 存在"
        else
            log_fail "$file 不存在"
        fi
    done
}

# 測試參數解析
test_argument_parsing() {
    log_test "測試參數解析..."
    
    # 測試幫助參數
    if bash "$SCRIPT_DIR/install.sh" --help >/dev/null 2>&1; then
        log_pass "install.sh --help 正常"
    else
        log_fail "install.sh --help 失敗"
    fi
}

# 檢查 install.sh --config 未帶值時印出明確錯誤，而非 set -u 的 unbound variable
test_install_config_requires_path() {
    log_test "檢查 install.sh --config 未帶值的錯誤訊息..."

    # 前面的 test_common_library 會把 common.sh 的 set -e 帶進這個 shell，
    # 預期失敗的指令必須用 || 接住，否則整支測試會在此中止。
    local out exit_code=0
    out="$(bash "$SCRIPT_DIR/install.sh" --config 2>&1)" || exit_code=$?

    if [ "$exit_code" -ne 0 ] && \
       [[ "$out" == *"--config requires a file path"* ]] && \
       [[ "$out" != *"unbound variable"* ]]; then
        log_pass "--config 未帶值會回報明確錯誤"
    else
        log_fail "--config 未帶值行為不正確 (exit=$exit_code): $out"
    fi
}

# 靜態檢查：sudo 防護區塊內不得有未被單引號保護的 $(curl
test_install_sudo_guard_no_command_substitution() {
    log_test "靜態檢查 sudo 防護區塊不執行 curl..."

    local installer="$SCRIPT_DIR/install.sh"
    local block bad
    block="$(awk '/\$\{SUDO_USER:-\}/ && /ALLOW_ROOT/ {f=1} f {print} f && /^fi$/ {exit}' "$installer")"
    if [ -z "$block" ]; then
        log_fail "找不到 sudo 防護區塊"
        return
    fi

    # 逐行移除單引號字串後，不得再出現 $(curl
    bad="$(printf '%s\n' "$block" | sed "s/'[^']*'//g" | grep -F '$(curl' || true)"
    if [ -z "$bad" ] && \
       ! printf '%s\n' "$block" | grep -qE '\$\{(YELLOW|GREEN|CYAN|NC)\}'; then
        log_pass "sudo 防護區塊不會執行 curl 且不依賴 common.sh 顏色變數"
    else
        log_fail "sudo 防護區塊含未保護的 \$(curl 或使用尚未定義的顏色變數"
    fi
}

# 行為測試：sudo 執行 install.sh 時應顯示提示並結束（僅 CI 且免密 sudo 時執行）
test_install_sudo_guard_behavior() {
    log_test "檢查 sudo 防護的實際行為..."

    if [ "${CI:-}" != "true" ] || ! command -v sudo >/dev/null 2>&1 || ! sudo -n true >/dev/null 2>&1; then
        log_warn "略過：需要 CI=true 且 sudo -n 可用"
        return
    fi

    # 同上：以 || 接住預期的非 0 結束碼，避免被 set -e 中止
    local out exit_code=0
    out="$(env -u ALLOW_ROOT sudo -n env -u ALLOW_ROOT bash "$SCRIPT_DIR/install.sh" --dry-run 2>&1)" || exit_code=$?

    if [ "$exit_code" -ne 0 ] && \
       [[ "$out" == *"請改用一般使用者執行"* ]] && \
       [[ "$out" != *"unbound variable"* ]] && \
       [[ "$out" != *"#!/usr/bin/env bash"* ]]; then
        log_pass "sudo 防護會顯示提示並以非 0 結束"
    else
        log_fail "sudo 防護行為不正確 (exit=$exit_code): $out"
    fi
}

# 檢查顯示版本與共用版本常數同步
test_script_version_bumped() {
    log_test "檢查腳本版本已更新..."

    local installer="$SCRIPT_DIR/install.sh"
    local common="$SCRIPT_DIR/scripts/core/common.sh"
    if [ ! -f "$installer" ] || [ ! -f "$common" ]; then
        log_fail "找不到 install.sh 或 common.sh"
        return
    fi

    if search_literal 'Version: 2.2.9' "$installer" && \
       search_literal '自動安裝腳本 v2.2.9' "$installer" && \
       search_literal 'Linux Setting Scripts  v2.2.9' "$installer" && \
       search_literal 'readonly SCRIPT_VERSION="2.2.9"' "$common" && \
       ! search_literal '2.2.8' "$installer" && \
       ! search_literal 'SCRIPT_VERSION="2.2.8"' "$common"; then
        log_pass "版本已更新為 2.2.9"
    else
        log_fail "版本仍未完整更新為 2.2.9"
    fi
}

# 模組管理器可能在函式內被 source（install.sh 的 load_module_manager 就是如此）。
# 若資料表不是以全域宣告，函式返回後就會消失，實際安裝時以模組 id 當索引會出現
# "unbound variable"。用真正的 common.sh、module_manager.sh 與 modules.conf 驗證，不用替身。
test_module_manager_survives_function_scope() {
    log_test "檢查在函式內載入模組管理器後資料表仍然存在..."

    if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
        log_warn "略過：模組管理器需要 bash 4 以上"
        return
    fi

    local out rc=0
    out="$(HOME="$(mktemp -d)" bash -c '
        set -euo pipefail
        root="$1"
        SCRIPT_DIR="$root/scripts"
        # shellcheck source=/dev/null
        source "$root/scripts/core/common.sh" >/dev/null 2>&1
        loader() {
            # shellcheck source=/dev/null
            source "$SCRIPT_DIR/core/module_manager.sh"
            init_module_manager >/dev/null 2>&1
        }
        loader
        first="${MODULE_LIST[0]}"
        printf "%s|%s|%s" "${#MODULE_LIST[@]}" "$first" "${MODULE_NAMES[$first]:-MISSING}"
    ' _ "$SCRIPT_DIR" 2>&1)" || rc=$?

    local count="${out%%|*}"
    if [ "$rc" -eq 0 ] && [[ "$count" =~ ^[0-9]+$ ]] && [ "$count" -gt 0 ] \
       && [[ "$out" != *"MISSING"* ]] && [[ "$out" != *"unbound variable"* ]]; then
        log_pass "函式返回後仍可用模組 id 取得資料（$out）"
    else
        log_fail "函式內載入後模組資料遺失 (rc=$rc): ${out:0:200}"
    fi
}

# 檢查 install.sh 是否初始化 SKIP_PYTHON_CHECK
test_skip_python_check_default() {
    log_test "檢查 SKIP_PYTHON_CHECK 預設值..."

    if search_text "SKIP_PYTHON_CHECK=\\\"\\$\\{SKIP_PYTHON_CHECK:-" "$SCRIPT_DIR/install.sh"; then
        log_pass "SKIP_PYTHON_CHECK 已設定預設值"
    else
        log_fail "SKIP_PYTHON_CHECK 未設定預設值"
    fi
}

# 檢查 install.sh 是否使用模組管理器進行安裝
test_module_manager_install_path() {
    log_test "檢查模組管理器安裝路徑..."

    if search_text "install_module" "$SCRIPT_DIR/install.sh"; then
        log_pass "install.sh 使用 install_module"
    else
        log_fail "install.sh 未使用 install_module"
    fi
}

# 只載入暫存替身，不執行安裝流程；驗證必要模組管理器的失敗邊界。
test_required_module_manager() {
    log_test "檢查必要模組管理器的載入與失敗處理..."
    local funcs tmp mode out rc
    funcs="$(extract_install_functions load_module_manager)"
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/core"
    for mode in missing source_failed init_failed empty ready; do
        rm -f "$tmp/core/module_manager.sh"
        case "$mode" in
            source_failed) printf 'return 1\n' > "$tmp/core/module_manager.sh" ;;
            init_failed) printf 'init_module_manager() { return 1; }\n' > "$tmp/core/module_manager.sh" ;;
            empty) printf 'init_module_manager() { MODULE_LIST=(); }\n' > "$tmp/core/module_manager.sh" ;;
            ready) printf 'init_module_manager() { MODULE_LIST=(base); }\n' > "$tmp/core/module_manager.sh" ;;
        esac
        rc=0
        out="$(bash -c '
            set -euo pipefail
            eval "$1"
            SCRIPT_DIR="$2"
            log_error() { printf "%s\n" "$1" >&2; return 1; }
            load_module_manager
            printf ready
        ' _ "$funcs" "$tmp" 2>&1)" || rc=$?
        case "$mode:$rc:$out" in
            missing:1:*找不到必要的模組管理器*|source_failed:1:*無法載入*|init_failed:1:*初始化失敗*|empty:1:*未載入任何模組*|ready:0:ready)
                log_pass "模組管理器載入邊界：$mode" ;;
            *) log_fail "模組管理器載入邊界不正確：$mode rc=$rc $out" ;;
        esac
    done
    rm -rf "$tmp"
}

# 檢查 run_all_tests.sh 是否只在 Linux CI 跑進階測試
test_linux_ci_gate_for_extended_suites() {
    log_test "檢查 Linux CI 測試 gate..."

    if search_text "should_run_linux_only_suites" "$SCRIPT_DIR/tests/run_all_tests.sh" && \
       search_text "if should_run_linux_only_suites; then" "$SCRIPT_DIR/tests/run_all_tests.sh"; then
        log_pass "run_all_tests.sh 已配置 Linux CI gate"
    else
        log_fail "run_all_tests.sh 缺少 Linux CI gate"
    fi
}

# 檢查 CI workflow 是否明確配置 CI=true 並執行整合測試入口
test_workflow_linux_ci_settings() {
    log_test "檢查 workflow 的 Linux CI 設定..."

    local wf="$SCRIPT_DIR/.github/workflows/test.yml"
    if [ ! -f "$wf" ]; then
        log_fail "找不到 workflow: $wf"
        return
    fi

    if search_text "CI:\\s*true" "$wf" && \
       search_text "tests/run_all_tests\\.sh" "$wf"; then
        log_pass "workflow 已配置 CI=true 且執行 run_all_tests.sh"
    else
        log_fail "workflow 缺少 CI=true 或 run_all_tests.sh"
    fi
}

# 檢查配置預覽腳本在非互動模式可正常執行
test_preview_script_noninteractive() {
    log_test "檢查 preview_config.sh 共用函數載入路徑..."

    local preview_script="$SCRIPT_DIR/scripts/config/preview_config.sh"
    if [ ! -f "$preview_script" ]; then
        log_fail "找不到 preview_config.sh"
        return
    fi

    if search_text "\\.\\./core/common\\.sh" "$preview_script"; then
        log_pass "preview_config.sh 使用 scripts/core/common.sh 路徑"
    else
        log_fail "preview_config.sh 未使用 scripts/core/common.sh 路徑"
    fi
}

# 檢查 preview_config.sh 對 set -u 的環境有安全預設值
test_preview_config_strict_defaults() {
    log_test "檢查 preview_config.sh 嚴格模式預設值..."

    local preview_script="$SCRIPT_DIR/scripts/config/preview_config.sh"
    if [ ! -f "$preview_script" ]; then
        log_fail "找不到 preview_config.sh"
        return
    fi

    if search_text "MIRROR_MODE=\\\"\\$\\{MIRROR_MODE:-" "$preview_script" && \
       search_text "INSTALL_MODE=\\\"\\$\\{INSTALL_MODE:-" "$preview_script"; then
        log_pass "preview_config.sh 已設定 MIRROR_MODE/INSTALL_MODE 預設值"
    else
        log_fail "preview_config.sh 缺少 MIRROR_MODE/INSTALL_MODE 預設值"
    fi
}

# 檢查 module_manager.sh 在嚴格模式下對可選欄位使用安全展開
test_module_manager_strict_safe_access() {
    log_test "檢查 module_manager.sh 嚴格模式 map 存取..."

    local module_manager="$SCRIPT_DIR/scripts/core/module_manager.sh"
    if [ ! -f "$module_manager" ]; then
        log_fail "找不到 module_manager.sh"
        return
    fi

    if search_literal 'local brew_packages="${MODULE_BREW_PACKAGES[$module_id]:-}"' "$module_manager" && \
       search_literal 'local apt_fallback="${MODULE_APT_FALLBACK[$module_id]:-}"' "$module_manager" && \
       search_literal 'local pip_packages="${MODULE_PIP_PACKAGES[$module_id]:-}"' "$module_manager" && \
       search_literal 'local cargo_packages="${MODULE_CARGO_PACKAGES[$module_id]:-}"' "$module_manager" && \
       search_literal 'local npm_packages="${MODULE_NPM_PACKAGES[$module_id]:-}"' "$module_manager"; then
        log_pass "module_manager.sh 已使用安全展開存取可選欄位"
    else
        log_fail "module_manager.sh 仍有未安全展開的可選欄位"
    fi
}

# 檢查模組詳情的套件狀態查詢有快取，避免 Kali 顯示全部套件時重複查詢造成卡住
test_module_manager_package_status_cache() {
    log_test "檢查 module_manager.sh 套件狀態快取..."

    local module_manager="$SCRIPT_DIR/scripts/core/module_manager.sh"
    if [ ! -f "$module_manager" ]; then
        log_fail "找不到 module_manager.sh"
        return
    fi

    if search_literal 'declare -gA MODULE_PKG_STATUS_CACHE' "$module_manager" && \
       search_literal '_module_pkg_is_installed()' "$module_manager" && \
       search_literal 'MODULE_PKG_STATUS_CACHE["$cache_key"]' "$module_manager"; then
        log_pass "module_manager.sh 已快取套件狀態查詢"
    else
        log_fail "module_manager.sh 缺少套件狀態快取"
    fi
}

# 檢查 common.sh 支援更好用的 TUI backend，並保留 whiptail fallback
test_common_tui_backends() {
    log_test "檢查 common.sh 的 gum/fzf TUI backend..."

    local common="$SCRIPT_DIR/scripts/core/common.sh"
    if [ ! -f "$common" ]; then
        log_fail "找不到 common.sh"
        return
    fi

    if search_literal 'TUI_BACKEND="${TUI_BACKEND:-auto}"' "$common" && \
       search_literal '_select_tui_backend()' "$common" && \
       search_literal 'command -v gum' "$common" && \
       search_literal 'command -v fzf' "$common" && \
       search_literal 'TUI_BACKEND="whiptail"' "$common"; then
        log_pass "common.sh 已支援 gum/fzf 並保留 whiptail fallback"
    else
        log_fail "common.sh 缺少 gum/fzf TUI backend"
    fi
}

# 檢查 common.sh 在回落到 whiptail/CLI 時提示可選的 TUI 工具
test_common_tui_backend_hint() {
    log_test "檢查 common.sh 的 TUI backend 提示..."

    local common="$SCRIPT_DIR/scripts/core/common.sh"
    if [ ! -f "$common" ]; then
        log_fail "找不到 common.sh"
        return
    fi

    if search_literal '_log_tui_backend_hint()' "$common" && \
       search_literal 'TUI_BACKEND=fzf' "$common" && \
       search_literal 'TUI_BACKEND=gum' "$common"; then
        log_pass "common.sh 已提供 TUI backend 提示"
    else
        log_fail "common.sh 缺少 TUI backend 提示"
    fi
}

# 檢查 common.sh 提供 TUI 日誌檢視器，讓安裝日誌留在 TUI 流程中查看
test_common_tui_log_viewer() {
    log_test "檢查 common.sh 的 TUI log viewer..."

    local common="$SCRIPT_DIR/scripts/core/common.sh"
    if [ ! -f "$common" ]; then
        log_fail "找不到 common.sh"
        return
    fi

    if search_literal 'tui_log_viewer()' "$common" && \
       search_literal 'gum pager < "$view_file"' "$common" && \
       search_literal 'fzf --height=80% --border --no-sort' "$common" && \
       search_literal 'whiptail --title "$title" --textbox "$view_file"' "$common" && \
       search_literal 'func_list="$func_list ensure_tui_available tui_checklist tui_checklist_with_state tui_menu tui_yesno tui_msgbox tui_log_viewer tui_gauge"' "$common"; then
        log_pass "common.sh 已提供跨 backend 的 TUI log viewer"
    else
        log_fail "common.sh 缺少跨 backend 的 TUI log viewer"
    fi
}

# 檢查 TUI quiet 模式下狀態 log 不直接刷到終端，而是收進日誌
test_common_tui_quiet_status_logs_are_log_only() {
    log_test "檢查 TUI quiet 模式下狀態 log 只寫入日誌..."

    local common="$SCRIPT_DIR/scripts/core/common.sh"
    if [ ! -f "$common" ]; then
        log_fail "找不到 common.sh"
        return
    fi

    local tmp_log
    tmp_log="$(mktemp)"
    local tui_output
    tui_output=$(
        NON_INTERACTIVE=false \
        USE_TUI=true \
        TUI_MODE=quiet \
        ENABLE_LOGGING=true \
        LOG_FILE="$tmp_log" \
        bash -c 'source "$1"; log_info "hidden info"; log_success "hidden success"; log_warning "hidden warning"' _ "$common" 2>&1
    )

    local cli_output
    cli_output=$(
        NON_INTERACTIVE=false \
        USE_TUI=false \
        TUI_MODE=quiet \
        ENABLE_LOGGING=false \
        bash -c 'source "$1"; log_info "shown info"; log_success "shown success"' _ "$common" 2>&1
    )

    if [ -z "$tui_output" ] && \
       search_literal 'hidden info' "$tmp_log" && \
       search_literal 'hidden success' "$tmp_log" && \
       search_literal 'hidden warning' "$tmp_log" && \
       [[ "$cli_output" == *"INFO: shown info"* ]] && \
       [[ "$cli_output" == *"SUCCESS: shown success"* ]]; then
        log_pass "TUI quiet 狀態 log 已收進日誌且 CLI 輸出維持可見"
    else
        log_fail "TUI quiet 狀態 log 仍會刷到終端或未寫入日誌"
    fi

    rm -f "$tmp_log"
}

# 檢查 bootstrap 階段的狀態輸出可被 quiet 模式收斂（common.sh 載入前不可污染 TUI），
# 且已移除逐檔下載的遠端流程
test_install_remote_bootstrap_status_quiet() {
    log_test "檢查 bootstrap 狀態輸出可被 quiet 模式收斂..."

    local installer="$SCRIPT_DIR/install.sh"
    if [ ! -f "$installer" ]; then
        log_fail "找不到 install.sh"
        return
    fi

    if search_literal 'bootstrap_status()' "$installer" && \
       search_literal 'bootstrap_status "INFO" "下載專案壓縮檔：$url"' "$installer" && \
       search_literal '[ "$level" != "ERROR" ] && [ "${TUI_MODE:-quiet}" = "quiet" ]' "$installer" && \
       ! search_literal 'REMOTE_INSTALL' "$installer" && \
       ! search_literal 'Downloading common library from remote source' "$installer"; then
        log_pass "bootstrap 狀態輸出已支援 quiet 收斂，且無逐檔下載流程"
    else
        log_fail "bootstrap 狀態輸出或遠端流程不符合新設計"
    fi
}

# 檢查 fzf checklist 允許 Space 勾選，Enter 確認，而不是啟動時預選全部
test_common_fzf_checklist_enter_selects_current_item() {
    log_test "檢查 fzf checklist 的 Space 勾選與 Enter 確認行為..."

    local common="$SCRIPT_DIR/scripts/core/common.sh"
    if [ ! -f "$common" ]; then
        log_fail "找不到 common.sh"
        return
    fi

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    local fake_fzf="$tmp_dir/fzf"
    local args_file="$tmp_dir/fzf_args"

    cat > "$fake_fzf" <<'FAKE_FZF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "${FAKE_FZF_ARGS_FILE:?}"
cat >/dev/null
printf 'module_two\tModule Two\n'
FAKE_FZF
    chmod +x "$fake_fzf"

    local result
    result=$(
        PATH="$tmp_dir:$PATH" \
        FAKE_FZF_ARGS_FILE="$args_file" \
        USE_TUI=true \
        TUI_BACKEND=fzf \
        bash -c 'source "$1"; tui_checklist "Title" "Prompt" "module_one" "Module One" "module_two" "Module Two"' _ "$common"
    )
    local exit_code=$?
    local fzf_args
    fzf_args="$(cat "$args_file" 2>/dev/null || true)"

    rm -rf "$tmp_dir"

    if [ "$exit_code" -eq 0 ] && \
       [ "$result" = "module_two" ] && \
       [[ "$fzf_args" == *"--multi"* ]] && \
       [[ "$fzf_args" == *"--bind=space:toggle"* ]] && \
       [[ "$fzf_args" == *"--marker=✓ "* ]] && \
       [[ "$fzf_args" == *"Space 勾選/取消；Tab 多選；Enter 確認；Esc 取消"* ]] && \
       [[ "$fzf_args" != *"start:select-all"* ]]; then
        log_pass "fzf checklist 可用 Space 勾選並用 Enter 確認"
    else
        log_fail "fzf checklist 仍缺少 Space 勾選或 Enter 確認行為"
    fi
}

# 檢查 install.sh 的模組選擇提示不要綁死 whiptail 的空格鍵操作
test_install_module_prompt_backend_neutral() {
    log_test "檢查 install.sh 模組選擇提示為 backend-neutral..."

    local installer="$SCRIPT_DIR/install.sh"
    if [ ! -f "$installer" ]; then
        log_fail "找不到 install.sh"
        return
    fi

    # fzf 後端的 checklist 自帶按鍵說明，install.sh 只對其他後端補「空白鍵勾選」提示；
    # 舊的「[✓]=已安裝 [◐]=部分安裝」圖例會和勾選框混淆，不應再出現。
    if ! search_literal '請使用空格鍵選擇要安裝的模組' "$installer" && \
       search_literal '請勾選要安裝的模組（已安裝的預設不勾選）：' "$installer" && \
       search_literal 'fzf) key_hint="" ;;' "$installer" && \
       ! search_literal '[✓]=已安裝 [◐]=部分安裝' "$installer"; then
        log_pass "install.sh 模組選擇提示未綁定單一 TUI backend"
    else
        log_fail "install.sh 模組選擇提示仍綁定 whiptail 空格鍵操作"
    fi
}

# 檢查 TUI 安裝流程有包裝安裝狀態與日誌入口
test_install_tui_log_flow() {
    log_test "檢查 install.sh 的 TUI 安裝與日誌流程..."

    local installer="$SCRIPT_DIR/install.sh"
    if [ ! -f "$installer" ]; then
        log_fail "找不到 install.sh"
        return
    fi

    if search_literal 'show_install_log_dialog()' "$installer" && \
       search_literal 'run_install_with_tui()' "$installer" && \
       search_literal '"查看安裝日誌"' "$installer" && \
       search_literal 'show_install_log_dialog' "$installer" && \
       search_literal 'run_install_with_tui' "$installer" && \
       search_literal 'tui_log_viewer "安裝日誌" "$LOG_FILE"' "$installer" && \
       ! search_literal 'tui_msgbox "開始安裝"' "$installer" && \
       ! search_literal 'tui_yesno "查看安裝日誌"' "$installer" && \
       ! search_literal 'tui_log_viewer "安裝日誌" "$LOG_FILE" "$tail_lines" 2>/dev/null' "$installer"; then
        # 確認摘要後不再跳「開始安裝」；安裝後不再多問一次「是否查看日誌」；
        # 日誌檢視器不可把 stderr 丟進 /dev/null（whiptail 在 fd 交換後會畫在 stderr 上）
        log_pass "install.sh 已將安裝狀態與日誌入口包進 TUI"
    else
        log_fail "install.sh 缺少 TUI 安裝狀態或日誌入口"
    fi
}

# 檢查 TUI 主流程改為導覽式：模組勾選（含進階列）→ 摘要 → 安裝 → 合併結果畫面（可重試）
test_install_guided_tui_flow() {
    log_test "檢查 install.sh 使用導覽式 TUI 安裝流程..."

    local installer="$SCRIPT_DIR/install.sh"
    if [ ! -f "$installer" ]; then
        log_fail "找不到 install.sh"
        return
    fi

    if search_literal 'run_guided_tui_flow()' "$installer" && \
       search_literal 'select_modules_tui()' "$installer" && \
       search_literal 'confirm_install_summary_tui()' "$installer" && \
       search_literal 'show_install_result_tui()' "$installer" && \
       search_literal 'select_modules_tui || return 0' "$installer" && \
       search_literal 'confirm_install_summary_tui || continue' "$installer" && \
       search_literal 'offer_homebrew_if_needed' "$installer" && \
       search_literal 'run_install_with_tui' "$installer" && \
       search_literal 'show_install_result_tui || result_action=$?' "$installer" && \
       search_literal 'prepare_package_index "$use_progress"' "$installer" && \
       ! search_literal 'choose_install_mode_tui' "$installer" && \
       [ -n "$(awk '/^run_guided_tui_flow\(\) \{/{f=1} f && /select_modules_tui \|\| return 0/{s=NR} f && /offer_homebrew_if_needed/{if (s) print NR} f && /^}$/{exit}' "$installer")" ] && \
       ! search_literal 'while true; do' "$installer" && \
       ! search_literal '"選擇模組安裝" "$advanced_label" "查看模組詳情" "查看安裝日誌" "退出"' "$installer"; then
        log_pass "install.sh 已使用導覽式 TUI 安裝流程（無獨立安裝模式選單）"
    else
        log_fail "install.sh 導覽式流程不符合預期"
    fi
}

# 檢查 TUI quiet 模式下，安裝日誌提示不再直接刷到終端，且逐檔下載函式已移除
test_install_tui_wraps_pre_menu_logs() {
    log_test "檢查 TUI quiet 會包住安裝日誌，且逐檔下載已移除..."

    local installer="$SCRIPT_DIR/install.sh"
    if [ ! -f "$installer" ]; then
        log_fail "找不到 install.sh"
        return
    fi

    if search_literal 'installer_tui_quiet()' "$installer" && \
       search_literal 'run_logged_command()' "$installer" && \
       search_literal 'if installer_tui_quiet; then' "$installer" && \
       search_literal 'log_success "安裝日誌將保存到：$LOG_FILE"' "$installer" && \
       search_literal 'run_logged_command install_module "$module"' "$installer" && \
       ! search_literal 'run_remote_script_downloads' "$installer" && \
       ! search_literal 'download_remote_file' "$installer" && \
       ! search_literal 'exec 1> >(tee -a "$LOG_FILE") 2>&1' "$installer"; then
        log_pass "TUI quiet 已收斂前置日誌，逐檔下載流程已移除"
    else
        log_fail "TUI quiet 前置日誌或逐檔下載移除狀態不符"
    fi
}

# 檢查 install.sh --help 有列出 TUI_BACKEND / TUI log 用法
test_install_help_tui_backend_docs() {
    log_test "檢查 install.sh help 的 TUI 說明..."

    local installer="$SCRIPT_DIR/install.sh"
    if [ ! -f "$installer" ]; then
        log_fail "找不到 install.sh"
        return
    fi

    if search_literal 'TUI_BACKEND=auto|gum|fzf|whiptail' "$installer" && \
       search_literal 'TUI_LOG_LINES=300' "$installer" && \
       search_literal 'TUI_BACKEND=fzf ./install.sh' "$installer" && \
       search_literal 'TUI_BACKEND=gum ./install.sh' "$installer"; then
        log_pass "install.sh help 已說明 TUI 設定"
    else
        log_fail "install.sh help 缺少 TUI 設定說明"
    fi
}

# 檢查 README 有記錄 TUI backend、日誌與安裝提示
test_readme_tui_backend_docs() {
    log_test "檢查 README 的 TUI 說明..."

    local readme="$SCRIPT_DIR/README.md"
    if [ ! -f "$readme" ]; then
        log_fail "找不到 README.md"
        return
    fi

    if search_literal 'TUI_BACKEND=fzf ./install.sh' "$readme" && \
       search_literal 'TUI_BACKEND=gum ./install.sh' "$readme" && \
       search_literal 'TUI_LOG_LINES=500 ./install.sh' "$readme" && \
       search_literal '查看安裝日誌' "$readme" && \
       search_literal 'sudo apt install -y fzf' "$readme" && \
       search_literal 'brew install gum' "$readme"; then
        log_pass "README 已說明 TUI backend、日誌與可選工具安裝"
    else
        log_fail "README 缺少 TUI backend 或日誌說明"
    fi
}

# 檢查 python_setup.sh 在 uv venv 下不依賴固定 pip 路徑
test_python_setup_uv_venv_bootstrap() {
    log_test "檢查 python_setup.sh 的 uv venv 啟動流程..."

    local python_setup="$SCRIPT_DIR/scripts/core/python_setup.sh"
    if [ ! -f "$python_setup" ]; then
        log_fail "找不到 python_setup.sh"
        return
    fi

    if search_literal 'uv pip install --python "$VENV_DIR/bin/python" "setuptools<81" wheel' "$python_setup"; then
        log_pass "python_setup.sh 使用 uv pip 為 venv 安裝 setuptools"
    else
        log_fail "python_setup.sh 缺少 uv venv 的 setuptools 啟動邏輯"
    fi
}

# 檢查 python_setup.sh 在 uv 失敗時使用 python -m pip 後備
test_python_setup_requirements_fallback() {
    log_test "檢查 python_setup.sh requirements 後備流程..."

    local python_setup="$SCRIPT_DIR/scripts/core/python_setup.sh"
    if [ ! -f "$python_setup" ]; then
        log_fail "找不到 python_setup.sh"
        return
    fi

    if search_literal 'uv pip install --no-build-isolation -r "$REQUIREMENTS_FILE" --python "$VENV_DIR/bin/python"' "$python_setup" && \
       search_literal '"$VENV_DIR/bin/python" -m ensurepip --upgrade' "$python_setup" && \
       search_literal '"$VENV_DIR/bin/python" -m pip install --no-build-isolation -r "$REQUIREMENTS_FILE"' "$python_setup"; then
        log_pass "python_setup.sh 已使用 python -m pip 作為 requirements 後備"
    else
        log_fail "python_setup.sh requirements 後備仍依賴固定 pip 路徑"
    fi
}

# 檢查 requirements.txt 對 setuptools 做相容性鎖定
test_requirements_setuptools_pin() {
    log_test "檢查 requirements.txt 的 setuptools 版本鎖定..."

    local requirements="$SCRIPT_DIR/requirements.txt"
    if [ ! -f "$requirements" ]; then
        log_fail "找不到 requirements.txt"
        return
    fi

    if search_literal 'setuptools<81' "$requirements"; then
        log_pass "requirements.txt 已鎖定 setuptools<81"
    else
        log_fail "requirements.txt 缺少 setuptools<81 相容性鎖定"
    fi
}

# 維護腳本必須能載入 scripts/core/common.sh。
# 過去它們從自己所在的 scripts/maintenance/ 載入，一啟動就失敗，
# 連帶 `install.sh --update` 與健康檢查都不能用，卻因呼叫端的 `|| true` 而沒人發現。
test_maintenance_scripts_load_common() {
    log_test "檢查維護腳本能載入共用函數庫..."

    local script out rc ok=true
    for script in scripts/maintenance/health_check.sh scripts/maintenance/update_tools.sh; do
        if ! search_literal 'source "$SCRIPT_DIR/../core/common.sh"' "$SCRIPT_DIR/$script"; then
            log_fail "$script 沒有從 scripts/core 載入 common.sh"
            ok=false
        fi
    done

    # health_check.sh 不帶參數只印用法，不會改動系統，可以實際執行
    rc=0
    out="$(bash "$SCRIPT_DIR/scripts/maintenance/health_check.sh" 2>&1)" || rc=$?
    if [ "$rc" -ne 0 ] || [[ "$out" == *"無法載入共用函數庫"* ]] || [[ "$out" == *"No such file"* ]]; then
        log_fail "health_check.sh 無法啟動 (rc=$rc): ${out:0:200}"
        ok=false
    fi

    if [ "$ok" = true ]; then
        log_pass "維護腳本可載入 common.sh，health_check.sh 可啟動"
    fi
}

# 檢查 update_tools.sh 使用 repo root 的 requirements.txt 路徑
test_update_tools_requirements_path() {
    log_test "檢查 update_tools.sh 的 requirements 路徑..."

    local update_tools="$SCRIPT_DIR/scripts/maintenance/update_tools.sh"
    if [ ! -f "$update_tools" ]; then
        log_fail "找不到 update_tools.sh"
        return
    fi

    if search_literal 'PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"' "$update_tools" && \
       search_literal 'if [ -f "$PROJECT_ROOT/requirements.txt" ]; then' "$update_tools" && \
       search_literal '"$VENV_DIR/bin/python" -m pip install --upgrade -r "$PROJECT_ROOT/requirements.txt"' "$update_tools"; then
        log_pass "update_tools.sh 已使用 repo root 的 requirements.txt"
    else
        log_fail "update_tools.sh 仍未正確引用 repo root 的 requirements.txt"
    fi
}

# 檢查 update_tools.sh 在 uv venv 下有 python -m pip 後備
test_update_tools_venv_pip_fallback() {
    log_test "檢查 update_tools.sh 的 venv pip 後備..."

    local update_tools="$SCRIPT_DIR/scripts/maintenance/update_tools.sh"
    if [ ! -f "$update_tools" ]; then
        log_fail "找不到 update_tools.sh"
        return
    fi

    if search_literal '"$VENV_DIR/bin/python" -m ensurepip --upgrade' "$update_tools" && \
       search_literal '"$VENV_DIR/bin/python" -m pip install --upgrade pip' "$update_tools" && \
       search_literal '"$VENV_DIR/bin/python" -m pip install --upgrade ranger-fm s-tui "git+https://github.com/nvbn/thefuck.git@$THEFUCK_PINNED_COMMIT"' "$update_tools"; then
        log_pass "update_tools.sh 已使用 python -m pip 作為 venv 後備"
    else
        log_fail "update_tools.sh 仍依賴固定的 venv pip 路徑"
    fi
}

# 檢查 base_tools.sh 套件庫更新失敗時不應中止安裝
test_base_tools_update_nonfatal() {
    log_test "檢查 base_tools.sh 更新失敗容錯..."

    local base_tools="$SCRIPT_DIR/scripts/core/base_tools.sh"
    if [ ! -f "$base_tools" ]; then
        log_fail "找不到 base_tools.sh"
        return
    fi

    # 接受兩種寫法：原本 'sudo apt-get update' 與我們新加的 'sudo DEBIAN_FRONTEND=... apt-get update'
    if search_literal 'update_system || log_warning "系統套件列表更新失敗，將繼續安裝流程"' "$base_tools" && \
       { search_literal 'sudo apt-get update || log_warning "APT 套件列表更新失敗，將繼續安裝流程"' "$base_tools" || \
         search_literal 'sudo DEBIAN_FRONTEND=noninteractive apt-get update || log_warning "APT 套件列表更新失敗，將繼續安裝流程"' "$base_tools"; }; then
        log_pass "base_tools.sh 已容忍套件庫更新失敗"
    else
        log_fail "base_tools.sh 套件庫更新失敗仍可能中止流程"
    fi
}

# 檢查 base_tools.sh 的 ipinfo APT source 採用明確 opt-in
test_base_tools_ipinfo_opt_in() {
    log_test "檢查 base_tools.sh 的 ipinfo source opt-in..."

    local base_tools="$SCRIPT_DIR/scripts/core/base_tools.sh"
    if [ ! -f "$base_tools" ]; then
        log_fail "找不到 base_tools.sh"
        return
    fi

    if search_literal 'if [ "$DISTRO_FAMILY" = "debian" ] && [ "${ENABLE_IPINFO_REPO:-false}" = "true" ]; then' "$base_tools" && \
       search_literal 'if [ "$DISTRO" != "kali" ] && [ "${ENABLE_IPINFO_REPO:-false}" = "true" ]; then' "$base_tools"; then
        log_pass "base_tools.sh 已將 ipinfo repo 與套件改為 opt-in"
    else
        log_fail "base_tools.sh 仍可能在預設情況寫入 ipinfo source"
    fi
}

# 檢查 secure_download.sh 共用函數路徑正確
test_secure_download_common_path() {
    log_test "檢查 secure_download.sh 共用函數路徑..."

    local secure_download="$SCRIPT_DIR/scripts/utils/secure_download.sh"
    if [ ! -f "$secure_download" ]; then
        log_fail "找不到 secure_download.sh"
        return
    fi

    if search_literal 'COMMON_SH="$SCRIPT_DIR/../core/common.sh"' "$secure_download"; then
        log_pass "secure_download.sh 使用 scripts/core/common.sh 路徑"
    else
        log_fail "secure_download.sh 未使用 scripts/core/common.sh 路徑"
    fi
}

# 檢查 secure_download.sh 避免與 common.sh readonly 變數衝突
test_secure_download_variable_namespace() {
    log_test "檢查 secure_download.sh 變數命名空間..."

    local secure_download="$SCRIPT_DIR/scripts/utils/secure_download.sh"
    if [ ! -f "$secure_download" ]; then
        log_fail "找不到 secure_download.sh"
        return
    fi

    if search_literal 'readonly SECURE_DOWNLOAD_TIMEOUT=' "$secure_download" && \
       search_literal 'readonly SECURE_MAX_SCRIPT_SIZE=' "$secure_download" && \
       search_literal 'readonly SECURE_ALLOWED_DOMAINS=' "$secure_download"; then
        log_pass "secure_download.sh 已使用專用前綴變數"
    else
        log_fail "secure_download.sh 仍可能與 common.sh 變數衝突"
    fi
}

# 檢查 common.sh backup_file 在 set -u 下不會讀取未初始化 BACKUP_DIR
test_common_backup_file_strict_default() {
    log_test "檢查 common.sh backup_file 嚴格模式預設值..."

    local common_sh="$SCRIPT_DIR/scripts/core/common.sh"
    if [ ! -f "$common_sh" ]; then
        log_fail "找不到 common.sh"
        return
    fi

    if search_literal 'local backup_dir="${2:-${BACKUP_DIR:-}}"' "$common_sh"; then
        log_pass "common.sh backup_file 已安全處理未設定 BACKUP_DIR"
    else
        log_fail "common.sh backup_file 仍可能在 set -u 下觸發未綁定變數"
    fi
}

# 檢查 terminal_setup.sh 在 .zshrc 不存在時不會因 backup_file 回傳失敗而中止
test_terminal_setup_optional_zshrc_backup() {
    log_test "檢查 terminal_setup.sh 的 .zshrc 備份容錯..."

    local terminal_setup="$SCRIPT_DIR/scripts/core/terminal_setup.sh"
    if [ ! -f "$terminal_setup" ]; then
        log_fail "找不到 terminal_setup.sh"
        return
    fi

    if search_literal 'if [ -f "$HOME/.zshrc" ]; then' "$terminal_setup" && \
       search_literal 'backup_file "$HOME/.zshrc"' "$terminal_setup"; then
        log_pass "terminal_setup.sh 已在 .zshrc 存在時才執行備份"
    else
        log_fail "terminal_setup.sh 仍可能因缺少 .zshrc 造成備份步驟失敗"
    fi
}

# 檢查 dev_tools.sh 下載 lazygit 時使用可寫入暫存目錄
test_dev_tools_lazygit_tmpdir() {
    log_test "檢查 dev_tools.sh 的 lazygit 暫存下載路徑..."

    local dev_tools="$SCRIPT_DIR/scripts/core/dev_tools.sh"
    if [ ! -f "$dev_tools" ]; then
        log_fail "找不到 dev_tools.sh"
        return
    fi

    # curl 那行被換行加 timeout 切成多行，改用較鬆的 token 檢查
    if search_literal 'lazygit_tmp_dir="$(mktemp -d)"' "$dev_tools" \
       && search_literal '$lazygit_tmp_dir/lazygit.tar.gz' "$dev_tools" \
       && grep -q 'curl -fsSL' "$dev_tools"; then
        log_pass "dev_tools.sh 已使用暫存目錄下載 lazygit"
    else
        log_fail "dev_tools.sh 仍可能在不可寫目錄下載 lazygit"
    fi
}

# 檢查 monitoring_tools.sh 在無 systemd 環境不會因 fail2ban 啟動失敗中止
test_monitoring_tools_systemd_guard() {
    log_test "檢查 monitoring_tools.sh 的 systemd 容錯..."

    local monitoring_tools="$SCRIPT_DIR/scripts/core/monitoring_tools.sh"
    if [ ! -f "$monitoring_tools" ]; then
        log_fail "找不到 monitoring_tools.sh"
        return
    fi

    if search_literal 'if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then' "$monitoring_tools" && \
       search_literal 'sudo systemctl enable --now fail2ban || log_warning "fail2ban 服務啟動失敗，請稍後手動檢查"' "$monitoring_tools"; then
        log_pass "monitoring_tools.sh 已在無 systemd 環境安全略過服務啟動"
    else
        log_fail "monitoring_tools.sh 仍可能因 systemctl 失敗中止"
    fi
}

# 檢查 docker_setup.sh 在 Docker 安裝失敗時不會中止整體流程
test_docker_setup_nonfatal_docker_install() {
    log_test "檢查 docker_setup.sh 的 Docker 安裝失敗容錯..."

    local docker_setup="$SCRIPT_DIR/scripts/core/docker_setup.sh"
    if [ ! -f "$docker_setup" ]; then
        log_fail "找不到 docker_setup.sh"
        return
    fi

    if search_literal 'install_docker || log_warning "Docker 安裝失敗，將跳過 Docker 相關配置"' "$docker_setup" && \
       ! search_text 'install_docker[[:space:]]*\|\|[[:space:]]*\{' "$docker_setup"; then
        log_pass "docker_setup.sh 已將 Docker 安裝失敗改為非致命"
    else
        log_fail "docker_setup.sh 仍可能因 Docker 安裝失敗中止流程"
    fi
}

# 檢查 Docker 測試映像為報告 volume 預先建立可寫目錄
test_dockerfile_report_dir_permissions() {
    log_test "檢查 Docker 測試報告目錄權限..."

    local dockerfile="$SCRIPT_DIR/Dockerfile"
    if [ ! -f "$dockerfile" ]; then
        log_fail "找不到 Dockerfile"
        return
    fi

    if search_literal 'mkdir -p /opt/reports' "$dockerfile" && \
       search_literal 'chown -R testuser:testuser /opt/reports' "$dockerfile"; then
        log_pass "Dockerfile 已為 /opt/reports 提供 testuser 寫入權限"
    else
        log_fail "Dockerfile 尚未為 /opt/reports 建立可寫目錄"
    fi
}

# 檢查 docker-compose test-runner 先修正 reports volume 權限再寫入報告
test_docker_compose_report_volume_bootstrap() {
    log_test "檢查 docker-compose 測試報告 volume 初始化..."

    local compose_file="$SCRIPT_DIR/docker-compose.test.yml"
    if [ ! -f "$compose_file" ]; then
        log_fail "找不到 docker-compose.test.yml"
        return
    fi

    if search_literal "sudo chown -R testuser:testuser /opt/reports" "$compose_file" && \
       search_literal "tee /opt/reports/test_report_" "$compose_file"; then
        log_pass "docker-compose.test.yml 已在寫入報告前處理 volume 權限"
    else
        log_fail "docker-compose.test.yml 仍可能因 reports volume 權限導致測試失敗"
    fi
}

# 檢查 docker-compose test-runner 會強制執行 Linux-only 測試套件
test_docker_compose_linux_suite_gate() {
    log_test "檢查 docker-compose Linux 測試 gate..."

    local compose_file="$SCRIPT_DIR/docker-compose.test.yml"
    if [ ! -f "$compose_file" ]; then
        log_fail "找不到 docker-compose.test.yml"
        return
    fi

    if search_literal "CI=true" "$compose_file" || \
       search_literal "FORCE_LINUX_TESTS=true" "$compose_file"; then
        log_pass "docker-compose.test.yml 已啟用 Linux-only 測試套件"
    else
        log_fail "docker-compose.test.yml 仍會跳過 Linux-only 測試套件"
    fi
}

# 檢查 docker-compose 設定不再使用過時的 version 欄位
test_docker_compose_no_obsolete_version_field() {
    log_test "檢查 docker-compose 過時 version 欄位..."

    local compose_file="$SCRIPT_DIR/docker-compose.test.yml"
    if [ ! -f "$compose_file" ]; then
        log_fail "找不到 docker-compose.test.yml"
        return
    fi

    if search_text '^version:' "$compose_file"; then
        log_fail "docker-compose.test.yml 仍包含過時的 version 欄位"
    else
        log_pass "docker-compose.test.yml 已移除過時的 version 欄位"
    fi
}

# 檢查 common.sh 可被重複 source 而不觸發 readonly 重新宣告
test_common_idempotent_source_guard() {
    log_test "檢查 common.sh 重複載入保護..."

    local common_sh="$SCRIPT_DIR/scripts/core/common.sh"
    if [ ! -f "$common_sh" ]; then
        log_fail "找不到 common.sh"
        return
    fi

    if search_literal 'if [ "${COMMON_SH_LOADED:-0}" = "1" ]; then' "$common_sh" && \
       search_literal 'return 0 2>/dev/null || exit 0' "$common_sh"; then
        log_pass "common.sh 已有重複載入保護"
    else
        log_fail "common.sh 缺少重複載入保護，可能觸發 readonly 變數錯誤"
    fi
}

# 檢查 install.sh 提供無人值守入口
test_install_non_interactive_mode() {
    log_test "檢查 install.sh 的 non-interactive 模式..."

    local installer="$SCRIPT_DIR/install.sh"
    if [ ! -f "$installer" ]; then
        log_fail "找不到 install.sh"
        return
    fi

    if search_text "non-interactive" "$installer" && \
       search_literal 'NON_INTERACTIVE="${NON_INTERACTIVE:-false}"' "$installer" && \
       search_literal 'if [ "$NON_INTERACTIVE" = "true" ]; then' "$installer"; then
        log_pass "install.sh 已提供 non-interactive 入口"
    else
        log_fail "install.sh 仍缺少穩定的 non-interactive 入口"
    fi
}

# 從 install.sh 取出指定的頂層函式定義（不執行主流程），供行為測試在子 shell 中 eval
extract_install_functions() {
    local installer="$SCRIPT_DIR/install.sh"
    local fn
    for fn in "$@"; do
        awk -v fn="$fn" '
            index($0, fn "() {") == 1 { f = 1 }
            f { print }
            f && /^}$/ { exit }
        ' "$installer"
    done
}

# 從 common.sh 取出指定函式（供子 shell 測試）
extract_common_functions() {
    local common="$SCRIPT_DIR/scripts/core/common.sh"
    local fn
    for fn in "$@"; do
        awk -v fn="$fn" '
            index($0, fn "() {") == 1 { f = 1 }
            f { print }
            f && /^}$/ { exit }
        ' "$common"
    done
}

INSTALL_REPORT_FUNCS="module_display_name module_result_status module_result_succeeded install_results_overall install_report_title module_failure_packages count_words build_install_report_text record_module_result reset_install_results install_result_counts install_result_summary_line install_result_menu_text"

# 行為測試：安裝報告依每個模組的實際結果產生標題、清單與提示
test_install_report_reflects_results() {
    log_test "檢查安裝報告反映實際模組結果..."

    local funcs
    # shellcheck disable=SC2086
    funcs="$(extract_install_functions $INSTALL_REPORT_FUNCS)"
    local fake_home
    fake_home="$(mktemp -d)"
    touch "$fake_home/.zshrc" "$fake_home/.p10k.zsh"

    local runner='eval "$1"; shift; reset_install_results; while [ $# -ge 2 ]; do record_module_result "$1" "$2" "${3:-}"; shift 3; done; install_report_title; printf "|"; build_install_report_text; printf "|"; install_result_menu_text'

    local ok_out mixed_out failed_out aborted_out rc=0
    ok_out="$(HOME="$fake_home" LOG_FILE=/tmp/fake.log bash -c "$runner" _ "$funcs" base ok "" terminal ok "")" || rc=$?
    mixed_out="$(HOME="$fake_home" LOG_FILE=/tmp/fake.log bash -c "$runner" _ "$funcs" base ok "" dev partial "apt:neovim brew:lazygit" terminal failed "")" || rc=$?
    failed_out="$(HOME="$fake_home" LOG_FILE=/tmp/fake.log bash -c "$runner" _ "$funcs" base failed "" terminal failed "")" || rc=$?
    aborted_out="$(HOME="$fake_home" LOG_FILE=/tmp/fake.log INSTALL_ABORTED=true bash -c 'eval "$1"; reset_install_results; INSTALL_ABORTED=true; record_module_result base ok ""; record_module_result dev failed ""; record_module_result terminal not_run ""; install_report_title; printf "|"; build_install_report_text' _ "$funcs")" || rc=$?
    rm -rf "$fake_home"

    if [ "$rc" -eq 0 ] && \
       [[ "$ok_out" == "安裝完成|"* ]] && \
       [[ "$ok_out" == *"全部 2 個模組安裝成功"* ]] && \
       [[ "$ok_out" == *"✓ 基礎工具"* ]] && \
       [[ "$ok_out" == *"✓ 終端設定"* ]] && \
       [[ "$ok_out" == *"zsh 設定：~/.zshrc"* ]] && \
       [[ "$ok_out" == *"exec zsh -l"* ]] && \
       [[ "$ok_out" == *"日誌：/tmp/fake.log"* ]] && \
       [[ "$ok_out" == *"全部 2 個模組安裝完成"* ]] && \
       [[ "$mixed_out" == "安裝完成（部分失敗）|"* ]] && \
       [[ "$mixed_out" == *"⚠ 開發工具 — 2 個套件失敗：apt:neovim brew:lazygit"* ]] && \
       [[ "$mixed_out" == *"✗ 終端設定 — 安裝失敗"* ]] && \
       [[ "$mixed_out" != *"zsh 設定"* ]] && \
       [[ "$mixed_out" != *"exec zsh -l"* ]] && \
       [[ "$mixed_out" == *"成功 1 個、部分失敗 1 個、失敗 1 個"* ]] && \
       [[ "$failed_out" == "安裝失敗|"* ]] && \
       [[ "$failed_out" == *"失敗 2 個"* ]] && \
       [[ "$failed_out" != *"下一步"* ]] && \
       [[ "$failed_out" != *"安裝流程已完成"* ]] && \
       [[ "$aborted_out" == "安裝已中止|"* ]] && \
       [[ "$aborted_out" == *"- 終端設定 — 未執行（安裝已中止）"* ]]; then
        log_pass "安裝報告依模組結果顯示標題、狀態與對應提示"
    else
        log_fail "安裝報告未正確反映模組結果 (rc=$rc)"
        printf '%s\n---\n%s\n---\n%s\n---\n%s\n' "$ok_out" "$mixed_out" "$failed_out" "$aborted_out"
    fi
}

# 行為測試：進度行的日誌清理、寬度截斷與組行不會超過終端寬度
test_install_progress_text_helpers() {
    log_test "檢查安裝進度行的文字處理..."

    local funcs
    funcs="$(extract_install_functions _progress_clean_log_line progress_clean_log_line _progress_fit_text progress_fit_text progress_text_width _progress_fmt_elapsed _progress_compose_line)"

    local out rc=0
    out="$(LC_ALL=C.UTF-8 bash -c '
        eval "$1"
        progress_clean_log_line "$(printf "2026-11-13T17:22:15+00:00 [INFO] [123] \033[0;36m安裝 htop\033[0m")"; printf "|"
        progress_clean_log_line "$(printf "Progress 10%%\rProgress 50%%\r")"; printf "|"
        progress_clean_log_line "$(printf "\033[0;33mWARNING: 套件安裝失敗: foo\033[0m")"; printf "|"
        progress_text_width "$(progress_fit_text "監控工具安裝中文字很長的一行訊息abcdef" 10)"; printf "|"
        progress_fit_text "short" 10; printf "|"
        _progress_compose_line "x" "[2/5]" "開發工具" 83 "正在設定 Neovim 與 LazyVim 外掛，這一行非常非常長會超過寬度限制" 40
        progress_text_width "$PROGRESS_FIT"; printf "|"
        printf "%s" "$PROGRESS_FIT"; printf "|"
        _progress_fmt_elapsed 3725
    ' _ "$funcs")" || rc=$?

    local -a parts=()
    IFS='|' read -r -d '' -a parts < <(printf '%s' "$out") || true

    if [ "$rc" -eq 0 ] && \
       [ "${parts[0]:-}" = "安裝 htop" ] && \
       [ "${parts[1]:-}" = "Progress 50%" ] && \
       [ "${parts[2]:-}" = "套件安裝失敗: foo" ] && \
       [ "${parts[3]:-99}" -le 10 ] 2>/dev/null && \
       [ "${parts[4]:-}" = "short" ] && \
       [ "${parts[5]:-99}" -le 39 ] 2>/dev/null && \
       [[ "${parts[6]:-}" == "  x [2/5] 開發工具  01:23"* ]] && \
       [[ "${parts[6]:-}" == *"…" ]] && \
       [ "${parts[7]:-}" = "62:05" ]; then
        log_pass "進度行會清除色碼/時間戳並依顯示寬度保守截斷"
    else
        log_fail "進度行文字處理不正確 (rc=$rc): $out"
    fi
}

# 行為測試：非 tty 時 progress_run 不啟動動畫、回傳原指令結束碼、不留背景行程
test_install_progress_run_non_tty() {
    log_test "檢查非 tty 時的安裝進度輸出..."

    local funcs
    funcs="$(extract_install_functions _ansi _progress_fmt_elapsed _progress_fit_text _progress_term_cols progress_can_animate _progress_stop_spinner _progress_pid_alive _progress_out _progress_tty_is_terminal progress_run progress_finish_line)"

    local out rc=0
    out="$(bash -c '
        eval "$1"
        PROGRESS_LINES=()
        PROGRESS_TTY_OPEN=false
        PROGRESS_SPINNER_PID=""
        rc=0
        progress_run "[1/2]" "測試模組" bash -c "exit 7" || rc=$?
        printf "rc=%s\n" "$rc"
        printf "pid=[%s]\n" "$PROGRESS_SPINNER_PID"
        progress_finish_line "[2/5]" "開發工具" partial "部分套件失敗（2 個）" 83
        printf "jobs=[%s]\n" "$(jobs -p)"
    ' _ "$funcs" < /dev/null 2>&1 | cat)" || rc=$?

    if [ "$rc" -eq 0 ] && \
       [[ "$out" == *"[1/2] 測試模組 安裝中"* ]] && \
       [[ "$out" == *"rc=7"* ]] && \
       [[ "$out" == *"pid=[]"* ]] && \
       [[ "$out" == *"! [2/5] 開發工具  部分套件失敗（2 個）  01:23"* ]] && \
       [[ "$out" == *"jobs=[]"* ]] && \
       [[ "$out" != *$'\r'* ]]; then
        log_pass "非 tty 時改用靜態進度行並正確回傳結束碼"
    else
        log_fail "非 tty 進度輸出不正確 (rc=$rc): $out"
    fi
}

# 行為測試：確認摘要使用顯示名稱、顯示實際套件統計；勾選清單標籤不使用方括號狀態
test_install_summary_and_checklist_labels() {
    log_test "檢查確認摘要與模組勾選標籤..."

    if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
        log_warn "略過確認摘要行為測試：需要 bash 4+（關聯陣列）"
        return
    fi

    local funcs
    funcs="$(extract_install_functions module_display_name module_install_plan_text build_install_summary_text module_checklist_label)"

    local out rc=0
    out="$(bash -c '
        eval "$1"
        declare -A MODULE_NAMES=([base]="基礎工具" [dev]="開發工具" [monitoring]="監控工具" [docker]="Docker 工具" [python]="Python 開發環境" [term]="終端設定")
        declare -A MODULE_PACKAGES=([base]="a b c d e" [dev]="x" [monitoring]="m1 m2 m3 m4 m5" [docker]="" [python]="p1 p2" [term]="")
        declare -A MODULE_APT_FALLBACK=([base]="b f")
        declare -A MODULE_BREW_PACKAGES=([dev]="y z")
        declare -A MODULE_PIP_PACKAGES=([python]="pipx1")
        declare -A MODULE_CARGO_PACKAGES=() MODULE_NPM_PACKAGES=()
        declare -A MODULE_SCRIPTS=([monitoring]="monitoring_tools.sh" [docker]="docker_setup.sh" [python]="python_setup.sh")
        _module_pkg_is_installed() { case " a b m1 x y z p1 p2 pipx1 " in *" $2 "*) return 0 ;; esac; return 1; }
        selected_modules="base dev monitoring docker python term"
        INSTALL_MODE=full
        ADVANCED_MODE=false
        HOMEBREW_DECISION=yes
        LOG_FILE=/tmp/fake.log
        build_install_summary_text; printf "|"
        ADVANCED_MODE=true; selected_modules="dev"; build_install_summary_text; printf "|"
        module_checklist_label "Python 開發環境" "python3, pip, uv, ranger" partial; printf "|"
        module_checklist_label "Docker 工具" "docker-ce, lazydocker" not_installed
    ' _ "$funcs")" || rc=$?

    local -a parts=()
    IFS='|' read -r -d '' -a parts < <(printf '%s' "$out") || true

    # base：a b c d e + f（b 與 fallback 重複只算一次）= 6 個、已裝 a b、待裝 4
    # monitoring：5 個、已裝 1、待裝 4，有腳本
    if [ "$rc" -eq 0 ] && \
       [[ "${parts[0]}" == "模組："* ]] && \
       [[ "${parts[0]}" != *"模式"* ]] && \
       [[ "${parts[0]}" == *"• 基礎工具：安裝 4 個套件、略過 2 個已安裝\n"* ]] && \
       [[ "${parts[0]}" == *"• 開發工具：套件皆已安裝\n"* ]] && \
       [[ "${parts[0]}" == *"• 監控工具：安裝 4 個套件、略過 1 個已安裝，並執行設定腳本\n"* ]] && \
       [[ "${parts[0]}" == *"• Docker 工具：只執行設定腳本\n"* ]] && \
       [[ "${parts[0]}" == *"• Python 開發環境：套件皆已安裝，只執行設定腳本\n"* ]] && \
       [[ "${parts[0]}" == *"• 終端設定：沒有宣告套件"* ]] && \
       [[ "${parts[0]}" == *"Homebrew：會先安裝"* ]] && \
       [[ "${parts[0]}" == *"日誌：/tmp/fake.log"* ]] && \
       [[ "${parts[0]}" != *"預估時間"* ]] && \
       [[ "${parts[1]}" == "模組：\n  • 開發工具：套件皆已安裝"*"進階模式：確認後會逐模組挑選"* ]] && \
       [[ "${parts[2]}" == "Python 開發環境 — python3, pip, uv, ranger（部分安裝）" ]] && \
       [[ "${parts[3]}" == "Docker 工具 — docker-ce, lazydocker" ]]; then
        log_pass "確認摘要顯示每個模組的套件統計與設定腳本說明"
    else
        log_fail "確認摘要或勾選標籤不正確 (rc=$rc): $out"
    fi

    # 沒有模組管理器資料時只列名稱
    local plain
    plain="$(bash -c '
        eval "$1"
        selected_modules="base dev"
        INSTALL_MODE=full; ADVANCED_MODE=false; LOG_FILE=/tmp/fake.log
        build_install_summary_text
    ' _ "$funcs")" || true
    if [[ "$plain" == *"• 基礎工具\n"* ]] && [[ "$plain" != *"：安裝"* ]] && \
       ! search_literal '預估時間：10-15 分鐘' "$SCRIPT_DIR/install.sh"; then
        log_pass "沒有模組管理器時確認摘要只列模組名稱"
    else
        log_fail "沒有模組管理器時確認摘要不正確: $plain"
    fi
}

# 行為測試：精簡報告、合併／兩步判斷、重試清單、結果畫面流程
test_install_result_screen_behavior() {
    log_test "檢查合併結果畫面（精簡報告、是否合併、重試清單）..."

    local funcs cfuncs
    # shellcheck disable=SC2086
    funcs="$(extract_install_functions $INSTALL_REPORT_FUNCS build_install_report_compact_text install_retry_modules install_result_fits_one_screen show_install_result_tui)"
    cfuncs="$(extract_common_functions _tui_expand_text _tui_display_width _tui_term_size _tui_menu_fits_text)"

    local fake_home tmp rc=0
    fake_home="$(mktemp -d)"
    tmp="$(mktemp -d)"

    # 精簡報告與重試清單
    local out
    out="$(HOME="$fake_home" LOG_FILE="$fake_home/x.log" BACKUP_DIR="$fake_home/bk" bash -c '
        eval "$1"; eval "$2"
        reset_install_results
        record_module_result base ok ""
        record_module_result dev partial "apt:neovim brew:lazygit"
        record_module_result terminal failed "x"
        record_module_result docker not_run ""
        build_install_report_compact_text; printf "|"
        install_retry_modules; printf "|"
        reset_install_results
        record_module_result base ok ""
        install_retry_modules; printf "|"
        build_install_report_compact_text
    ' _ "$funcs" "$cfuncs")" || rc=$?
    local -a parts=()
    IFS='|' read -r -d '' -a parts < <(printf '%s' "$out") || true
    local compact="${parts[0]:-}"
    if [ "$rc" -eq 0 ] && \
       [[ "$compact" == "成功 1 個、部分失敗 1 個、失敗 1 個、未執行 1 個。"* ]] && \
       [[ "$compact" == *"✓ 基礎工具"* ]] && \
       [[ "$compact" == *"⚠ 開發工具 — 2 個套件失敗"* ]] && \
       [[ "$compact" == *"✗ 終端設定 — 安裝失敗"* ]] && \
       [[ "$compact" == *"- Docker 工具 — 未執行"* ]] && \
       [[ "$compact" == *"日誌：~/x.log" ]] && \
       [[ "$compact" != *"備份"* ]] && [[ "$compact" != *"建議"* ]] && [[ "$compact" != *"apt:neovim"* ]] && \
       [ "${parts[1]:-}" = "dev terminal docker" ] && \
       [ -z "${parts[2]:-}" ] && \
       [[ "${parts[3]:-}" == "全部 1 個模組安裝完成。"* ]]; then
        log_pass "精簡報告只含總結、逐模組狀態與日誌；重試清單包含失敗／部分／未執行"
    else
        log_fail "精簡報告或重試清單不正確 (rc=$rc): $out"
    fi

    # 是否合併：依終端機列數（精簡報告 + 選項 + 邊框 <= 列數 - 2）
    out="$(HOME="$fake_home" LOG_FILE="$fake_home/x.log" bash -c '
        eval "$1"; eval "$2"
        reset_install_results
        for m in base dev python terminal monitoring docker; do record_module_result "$m" ok ""; done
        chk() { if install_result_fits_one_screen "$1"; then printf "Y"; else printf "N"; fi; }
        TUI_TERM_COLS=80
        TUI_TERM_ROWS=40 chk 4; TUI_TERM_ROWS=24 chk 4; TUI_TERM_ROWS=24 chk 3; TUI_TERM_ROWS=20 chk 4
        TUI_TERM_ROWS=24
        for m in a b c; do record_module_result "$m" failed ""; done
        chk 4
    ' _ "$funcs" "$cfuncs")" || rc=$?
    # 6 個模組：總結 1 + 空 1 + 6 + 空 1 + 日誌 1 = 10 列；24 列終端機可用 22 列，需 10 + 選項 + 7
    # 9 個模組：13 列 + 4 + 7 = 24 > 22 → 退回兩步
    if [ "$rc" -eq 0 ] && [ "$out" = "YYYNN" ]; then
        log_pass "合併判斷依終端機列數與選項數量決定"
    else
        log_fail "合併判斷不正確 (rc=$rc): $out（預期 YYYNN）"
    fi

    # 結果畫面流程：以假的 tui_menu／tui_msgbox 記錄呼叫（每個情境用獨立目錄）
    local flow='
        eval "$1"; eval "$2"
        tui_menu() { printf "%s\n---\n" "$2" > "$T/menu_prompt"; shift 2; printf "%s\n" "$@" > "$T/menu_items"; printf "%s" "$PICK"; }
        tui_msgbox() { printf "x" >> "$T/msgbox"; }
        show_install_log_dialog() { printf "x" >> "$T/logdlg"; }
        reset_install_results
        for spec in $SPECS; do record_module_result "${spec%%=*}" "${spec#*=}" ""; done
        rc=0; show_install_result_tui || rc=$?; printf "%s" "$rc"
    '
    local d1="$tmp/1" d2="$tmp/2" d3="$tmp/3" d4="$tmp/4"
    mkdir -p "$d1" "$d2" "$d3" "$d4"
    local r_merged r_two r_retry r_ok
    r_merged="$(T="$d1" PICK="退出" SPECS="base=ok dev=failed" TUI_TERM_ROWS=40 TUI_TERM_COLS=80 HOME="$fake_home" LOG_FILE="$fake_home/x.log" bash -c "$flow" _ "$funcs" "$cfuncs")" || rc=$?
    local merged_prompt merged_items msgbox_calls=""
    merged_prompt="$(cat "$d1/menu_prompt")"; merged_items="$(tr '\n' ',' < "$d1/menu_items")"
    if [ -f "$d1/msgbox" ]; then msgbox_calls="$(cat "$d1/msgbox")"; fi
    r_two="$(T="$d2" PICK="重新選擇" SPECS="a=ok b=ok c=ok d=failed e=ok f=ok" TUI_TERM_ROWS=20 TUI_TERM_COLS=80 HOME="$fake_home" LOG_FILE="$fake_home/x.log" bash -c "$flow" _ "$funcs" "$cfuncs")" || rc=$?
    local two_prompt two_msgbox=""
    two_prompt="$(cat "$d2/menu_prompt")"
    if [ -f "$d2/msgbox" ]; then two_msgbox="$(cat "$d2/msgbox")"; fi
    r_retry="$(T="$d3" PICK="重試失敗的模組" SPECS="base=ok dev=partial" TUI_TERM_ROWS=40 TUI_TERM_COLS=80 HOME="$fake_home" LOG_FILE="$fake_home/x.log" bash -c "$flow" _ "$funcs" "$cfuncs")" || rc=$?
    r_ok="$(T="$d4" PICK="退出" SPECS="base=ok terminal=ok" TUI_TERM_ROWS=40 TUI_TERM_COLS=80 HOME="$fake_home" LOG_FILE="$fake_home/x.log" bash -c "$flow" _ "$funcs" "$cfuncs")" || rc=$?
    local ok_items
    ok_items="$(tr '\n' ',' < "$d4/menu_items")"
    rm -rf "$tmp" "$fake_home"

    if [ "$r_merged" = "0" ] && [ -z "$msgbox_calls" ] && \
       [[ "$merged_prompt" == *"✗ 開發工具 — 安裝失敗"* ]] && \
       [ "$merged_items" = "重試失敗的模組,查看安裝日誌,重新選擇,退出," ] && \
       [ "$r_two" = "2" ] && [ "$two_msgbox" = "x" ] && \
       [[ "$two_prompt" != *"✓"* ]] && [[ "$two_prompt" == *"成功 5 個"*"日誌："* ]] && \
       [ "$r_retry" = "3" ] && \
       [ "$r_ok" = "0" ] && [ "$ok_items" = "查看安裝日誌,重新選擇,退出," ]; then
        log_pass "結果畫面：放得下時合併、放不下退回兩步；失敗時第一個選項為重試；全成功沒有重試"
    else
        log_fail "結果畫面流程不正確: merged=$r_merged/[$msgbox_calls]/$merged_items two=$r_two/[$two_msgbox] retry=$r_retry ok=$r_ok/$ok_items rc=$rc"
        printf '%s\n%s\n' "$merged_prompt" "$two_prompt"
    fi
}

# 行為測試：勾選清單預設狀態、虛擬進階項目與解析、選模組流程
test_install_module_checklist_behavior() {
    log_test "檢查模組勾選預設狀態與進階虛擬項目..."

    if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
        log_warn "略過勾選清單行為測試：需要 bash 4+（關聯陣列）"
        return
    fi

    local funcs tag_def
    funcs="$(extract_install_functions module_checklist_label build_module_checklist_items parse_module_selection parse_checklist_selection select_modules_tui module_display_names module_display_name)"
    tag_def="$(grep -E '^ADVANCED_CHECKLIST_(TAG|LABEL)=' "$SCRIPT_DIR/install.sh")"

    local rc=0 out
    # 預設狀態：已安裝 OFF、部分安裝／未安裝 ON
    out="$(bash -c '
        eval "$1"; eval "$2"
        declare -A MODULE_NAMES=([base]="基礎工具" [dev]="開發工具" [term]="終端設定")
        declare -A MODULE_DESCRIPTIONS=([base]="git" [dev]="nvim" [term]="zsh")
        MODULE_LIST=(base dev term)
        check_module_status() { case "$1" in base) echo installed ;; dev) echo partial ;; *) echo not_installed ;; esac; }
        checklist_items=(); checklist_states=()
        build_module_checklist_items
        echo "${checklist_states[*]}"; echo "${checklist_items[1]}"
    ' _ "$funcs" "$tag_def")" || rc=$?
    if [ "$rc" -eq 0 ] && \
       [[ "$out" == "OFF ON ON"$'\n'"基礎工具 — git（已安裝）" ]]; then
        log_pass "已安裝的模組預設不勾選，其餘預設勾選（標籤仍顯示已安裝）"
    else
        log_fail "勾選預設狀態不正確 (rc=$rc): $out"
    fi

    # 解析：進階列剔除並設定 ADVANCED_MODE；只勾進階視為未選擇
    out="$(bash -c '
        eval "$1"; eval "$2"
        r() { local rc=0; ADVANCED_MODE=${2:-false}; parse_checklist_selection "$1" || rc=$?; printf "[%s|%s|%s]" "$rc" "$selected_modules" "$ADVANCED_MODE"; }
        r "python base +advanced"
        r "\"python\" \"base\""
        r "+advanced"
        r ""
        r "dev" true
        r "dev +advanced dev"
    ' _ "$funcs" "$tag_def")" || rc=$?
    if [ "$rc" -eq 0 ] && \
       [ "$out" = "[0|python base|true][0|python base|false][1||true][1||false][0|dev|false][0|dev|true]" ]; then
        log_pass "進階虛擬項目從模組清單剔除並設定 ADVANCED_MODE；只勾進階視為未選擇"
    else
        log_fail "勾選結果解析不正確 (rc=$rc): $out"
    fi

    # 選模組流程：whiptail 傳入預設狀態與進階列；空選擇會提示並重問；取消即退出；其他後端退回 tui_checklist
    local tmp
    tmp="$(mktemp -d)"
    local flow='
        eval "$1"; eval "$2"
        declare -A MODULE_NAMES=([base]="基礎工具" [dev]="開發工具")
        declare -A MODULE_DESCRIPTIONS=([base]="git" [dev]="nvim")
        MODULE_LIST=(base dev); INSTALL_MODE=full
        check_module_status() { [ "$1" = base ] && echo installed || echo not_installed; }
        _tui_backend_supports_state_checklist() { [ "$STATE_BACKEND" = yes ]; }
        next_result() { local n; n=$(cat "$T/n" 2>/dev/null || echo 0); echo $((n + 1)) > "$T/n"; sed -n "$((n + 1))p" "$T/results"; }
        tui_checklist_with_state() { shift 2; printf "%s\n" "$@" > "$T/args_state"; local r; r="$(next_result)"; [ "$r" = CANCEL ] && return 1; printf "%s" "$r"; }
        tui_checklist() { shift 2; printf "%s\n" "$@" > "$T/args_plain"; local r; r="$(next_result)"; [ "$r" = CANCEL ] && return 1; printf "%s" "$r"; }
        tui_msgbox() { printf "x" >> "$T/msgbox"; }
        rc=0; select_modules_tui || rc=$?
        printf "[%s|%s|%s]" "$rc" "$selected_modules" "$ADVANCED_MODE"
    '
    local d1="$tmp/1" d2="$tmp/2" d3="$tmp/3" d4="$tmp/4"
    mkdir -p "$d1" "$d2" "$d3" "$d4"
    local o1 o2 o3 o4
    printf 'dev +advanced\n' > "$d1/results"
    o1="$(T="$d1" STATE_BACKEND=yes ADVANCED_MODE=false bash -c "$flow" _ "$funcs" "$tag_def")" || rc=$?
    local state_args
    state_args="$(tr '\n' ',' < "$d1/args_state")"
    printf '+advanced\ndev\n' > "$d2/results"
    o2="$(T="$d2" STATE_BACKEND=yes ADVANCED_MODE=true GUIDED_ADVANCED_DEFAULT=true bash -c "$flow" _ "$funcs" "$tag_def")" || rc=$?
    local state_args2 msgbox2=""
    state_args2="$(tr '\n' ',' < "$d2/args_state")"
    if [ -f "$d2/msgbox" ]; then msgbox2="$(cat "$d2/msgbox")"; fi
    printf 'CANCEL\n' > "$d3/results"
    o3="$(T="$d3" STATE_BACKEND=yes ADVANCED_MODE=false bash -c "$flow" _ "$funcs" "$tag_def")" || rc=$?
    printf 'base\n' > "$d4/results"
    o4="$(T="$d4" STATE_BACKEND=no ADVANCED_MODE=false bash -c "$flow" _ "$funcs" "$tag_def")" || rc=$?
    local plain_args
    plain_args="$(tr '\n' ',' < "$d4/args_plain")"
    rm -rf "$tmp"

    if [ "$rc" -eq 0 ] && \
       [ "$o1" = "[0|dev|true]" ] && \
       [[ "$state_args" == "base,基礎工具 — git（已安裝）,OFF,dev,開發工具 — nvim,ON,+advanced,進階：安裝前逐模組挑選套件,OFF," ]] && \
       [ "$o2" = "[0|dev|false]" ] && [ "$msgbox2" = "x" ] && [[ "$state_args2" == *",進階：安裝前逐模組挑選套件,ON," ]] && \
       [ "$o3" = "[1||false]" ] && \
       [ "$o4" = "[0|base|false]" ] && [[ "$plain_args" == "base,基礎工具 — git（已安裝）,dev,開發工具 — nvim,+advanced,進階：安裝前逐模組挑選套件," ]]; then
        log_pass "選模組流程：預設狀態、進階列（含 --advanced 預設）、空選擇重問、取消退出、非 whiptail 後端退回"
    else
        log_fail "選模組流程不正確 (rc=$rc): o1=$o1 o2=$o2/$msgbox2 o3=$o3 o4=$o4"
        printf '%s\n%s\n%s\n' "$state_args" "$state_args2" "$plain_args"
    fi
}

# 導覽結束碼必須反映每個模組，partial 本身仍可成功離開。
# 非互動與導覽流程共用的結束碼判斷：失敗、未執行、中止 → 1；成功、部分套件失敗、沒有結果 → 0
test_install_results_exit_code() {
    log_test "檢查安裝結果對應的結束碼..."
    local funcs out rc=0
    funcs="$(extract_install_functions install_results_exit_code)"
    out="$(LC_ALL=C bash -c '
        set -euo pipefail; eval "$1"
        for statuses in "ok ok" "ok partial" "ok failed" "ok not_run" "failed" ""; do
            INSTALL_ABORTED=false; INSTALL_RESULT_STATUS=($statuses)
            printf "%s " "$(install_results_exit_code)"
        done
        INSTALL_ABORTED=true; INSTALL_RESULT_STATUS=(ok ok)
        printf "%s " "$(install_results_exit_code)"
        unset INSTALL_RESULT_STATUS INSTALL_ABORTED
        printf "%s" "$(install_results_exit_code)"
    ' _ "$funcs")" || rc=$?
    local installer="$SCRIPT_DIR/install.sh"
    if [ "$rc" -eq 0 ] && [ "$out" = "0 0 1 1 1 0 1 0" ] && \
       search_literal 'exit "$(install_results_exit_code)"' "$installer" && \
       search_literal 'ni_rc="$(install_results_exit_code)"' "$installer"; then
        log_pass "失敗、未執行與中止回傳 1；非互動與非 tty 路徑都採用同一判斷"
    else
        log_fail "結束碼判斷不正確 (rc=$rc): $out"
    fi
}

test_guided_exit_status() {
    log_test "檢查導覽流程結束碼..."
    local funcs out rc=0
    funcs="$(extract_install_functions run_guided_tui_flow install_results_exit_code)"
    out="$(LC_ALL=C bash -c '
        set -euo pipefail; eval "$1"
        select_modules_tui() { :; }
        offer_homebrew_if_needed() { :; }
        confirm_install_summary_tui() { :; }
        log_info() { :; }
        show_install_result_tui() { :; }
        print_installation_report_plain() { :; }
        run_install_with_tui() { INSTALL_RESULT_IDS=(base dev); INSTALL_RESULT_STATUS=($statuses); INSTALL_ABORTED=$aborted; }
        for statuses in "ok ok" "ok partial" "ok failed" "ok not_run"; do
            aborted=false; GUIDED_EXIT_CODE=9
            run_guided_tui_flow
            printf "%s " "$GUIDED_EXIT_CODE"
        done
        statuses="ok ok"; aborted=true
        run_guided_tui_flow; printf "%s" "$GUIDED_EXIT_CODE"
    ' _ "$funcs")" || rc=$?
    if [ "$rc" -eq 0 ] && [ "$out" = "0 0 1 1 1" ]; then
        log_pass "failed、not_run 與中止回傳失敗，partial 與成功回傳成功"
    else
        log_fail "導覽結束碼不正確 (rc=$rc): $out"
    fi
}

test_guided_override_lifecycle() {
    log_test "檢查進階覆寫重新選擇清除、重試保留..."
    if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
        log_warn "略過覆寫生命週期測試：需要 bash 4+（關聯陣列）"
        return
    fi
    local funcs rc=0
    funcs="$(extract_install_functions run_guided_tui_flow install_selected_modules reset_install_results install_results_exit_code)"
    LC_ALL=C bash -c '
        set -euo pipefail; source "$2/scripts/core/module_manager.sh"; eval "$1"
        names="MODULE_HAS_OVERRIDE MODULE_PKG_OVERRIDE_APT MODULE_PKG_OVERRIDE_BREW MODULE_PKG_OVERRIDE_APT_FALLBACK MODULE_PKG_OVERRIDE_PIP MODULE_PKG_OVERRIDE_CARGO MODULE_PKG_OVERRIDE_NPM MODULE_RUN_SCRIPT"
        seed() { local name; for name in $names; do eval "$name[base]=saved"; done; }
        empty() { local name; for name in $names; do eval "[ \"\${#$name[@]}\" -eq 0 ]" || exit 91; done; }
        seed; reset_module_overrides; empty
        # 清空後仍須保有關聯陣列型別。
        for name in $names; do [[ "$(declare -p "$name")" == "declare -A"* ]]; done
        seed; selections=0; installs=0; screens=0
        select_modules_tui() { empty; selections=$((selections + 1)); selected_modules=base; seed; }
        offer_homebrew_if_needed() { :; }; confirm_install_summary_tui() { :; }
        log_info() { :; }; print_installation_report_plain() { :; }
        install_retry_modules() { echo base; }
        run_install_with_tui() {
            local name
            for name in $names; do eval "[ \"\${$name[base]}\" = saved ]" || exit 92; done
            installs=$((installs + 1)); INSTALL_RESULT_IDS=(base); INSTALL_RESULT_STATUS=(partial)
        }
        show_install_result_tui() { screens=$((screens + 1)); case "$screens" in 1) return 3 ;; 2) return 2 ;; esac; }
        run_guided_tui_flow
        [ "$selections/$installs/$screens" = 2/3/3 ]
        # CLI 完成後也清除覆寫；使用無對應模組的清單及 stub，避免任何安裝。
        (
            GUIDED_RESULT_SCREEN=false; selected_modules=unknown
            MODULE_LIST=(base); DRY_RUN=false; ADVANCED_MODE=false
            CYAN=""; NC=""
            installer_tui_quiet() { return 1; }
            prepare_package_index() { :; }; install_homebrew_if_requested() { :; }
            show_installation_report() { :; }; record_created_configs() { :; }; install_uninstaller_copy() { :; }
            seed
            trap "empty; [ -z \"\$selected_modules\" ] || exit 93" EXIT
            install_selected_modules >/dev/null
        )
    ' _ "$funcs" "$SCRIPT_DIR" || rc=$?
    if [ "$rc" -eq 0 ]; then
        log_pass "8 個覆寫陣列清空後保留型別；重試保留，重新選擇清除"
    else
        log_fail "覆寫生命週期不正確 (rc=$rc)"
    fi
}

test_guided_cancel_all_results() {
    log_test "檢查全部取消會清除舊結果並返回選擇..."
    local funcs rc=0
    funcs="$(extract_install_functions run_guided_tui_flow install_selected_modules reset_install_results install_results_exit_code)"
    LC_ALL=C bash -c '
        set -euo pipefail; eval "$1"
        RED=""; NC=""; MODULE_LIST=(base); DRY_RUN=false
        ADVANCED_MODE=true; NON_INTERACTIVE=false
        log_info() { :; }; log_warning() { :; }
        module_interactive_package_filter() { return 1; }
        INSTALL_RESULT_IDS=(old); INSTALL_RESULT_STATUS=(failed); INSTALL_RESULT_DETAIL=(old); INSTALL_ABORTED=true
        selected_modules=base; install_selected_modules
        [ "${#INSTALL_RESULT_IDS[@]}" -eq 0 ]; [ "$INSTALL_ABORTED" = false ]
        INSTALL_RESULT_IDS=(old); selected_modules=""; install_selected_modules >/dev/null
        [ "${#INSTALL_RESULT_IDS[@]}" -eq 0 ]
        selections=0
        select_modules_tui() { selections=$((selections + 1)); [ "$selections" -eq 1 ] || return 1; selected_modules=base; ADVANCED_MODE=true; }
        offer_homebrew_if_needed() { :; }; confirm_install_summary_tui() { :; }
        run_install_with_tui() { install_selected_modules; }
        show_install_result_tui() { echo "不應顯示結果" >&2; exit 99; }
        run_guided_tui_flow
        [ "$selections" -eq 2 ]
    ' _ "$funcs" || rc=$?
    if [ "$rc" -eq 0 ]; then
        log_pass "未選擇與全部取消均清除舊結果；空結果返回模組選擇"
    else
        log_fail "全部取消流程不正確 (rc=$rc)"
    fi
}

test_guided_advanced_stateless_backend() {
    log_test "檢查 fzf／gum 保留 --advanced..."
    local funcs rc=0
    funcs="$(extract_install_functions select_modules_tui parse_checklist_selection parse_module_selection)"
    LC_ALL=C bash -c '
        set -euo pipefail; eval "$1"
        INSTALL_MODE=full; GUIDED_ADVANCED_DEFAULT=true
        ADVANCED_CHECKLIST_TAG=+advanced; ADVANCED_CHECKLIST_LABEL=進階
        build_module_checklist_items() { checklist_items=(base 基礎工具); checklist_states=(ON); }
        _tui_backend_supports_state_checklist() { return 1; }
        tui_checklist() {
            [[ "$2" == *"進階模式已由 --advanced 啟用"* ]] || exit 91
            [ "$#" -eq 4 ] || exit 92
            [ "$3" = base ] || exit 93
            printf base
        }
        for TUI_BACKEND in fzf gum; do
            ADVANCED_MODE=true
            select_modules_tui
            [ "$selected_modules" = base ]; [ "$ADVANCED_MODE" = true ]
        done
    ' _ "$funcs" || rc=$?
    if [ "$rc" -eq 0 ]; then
        log_pass "fzf／gum 隱藏進階列、顯示 --advanced 提示並保留進階模式"
    else
        log_fail "無狀態勾選後端的進階模式不正確 (rc=$rc)"
    fi
}

# 行為測試：套件索引更新獨立成一行進度；只在會用到套件管理器時執行
test_install_package_index_step() {
    log_test "檢查套件索引更新進度行..."

    if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
        log_warn "略過套件索引行為測試：需要 bash 4+（關聯陣列）"
        return
    fi

    local funcs
    funcs="$(extract_install_functions selected_modules_need_package_index prepare_package_index)"

    local out rc=0
    out="$(bash -c '
        eval "$1"
        declare -A MODULE_SCRIPTS=([withscript]="x.sh" [noscript]="")
        declare -A MODULE_PACKAGES=([withscript]="" [noscript]="a b" [allin]="a" [partial]="a zz")
        declare -A MODULE_APT_FALLBACK=() MODULE_BREW_PACKAGES=()
        _module_pkg_is_installed() { [ "$2" = a ] || [ "$2" = b ]; }
        FORCE_REINSTALL=false
        need() { if selected_modules_need_package_index "$1"; then printf "Y"; else printf "N"; fi; }
        need allin; need withscript; need partial; need "allin noscript"
        FORCE_REINSTALL=true; need allin; FORCE_REINSTALL=false
        printf "|\n"

        # prepare_package_index：以假函式觀察行為
        calls=""
        progress_run() { local tag="$1" label="$2"; shift 2; calls+="run($label);"; "$@"; }
        progress_finish_line() { calls+="finish($3:$4);"; }
        run_logged_command() { "$@"; }
        ensure_package_index_fresh() { calls+="ensure;"; export LINUX_SETTING_PKG_INDEX_CHECKED=1; if [ "$IDX_OK" = yes ]; then export LINUX_SETTING_PKG_INDEX_UPDATED=1; fi; return 0; }
        _pkg_index_needs_update() { [ "$IDX_STALE" = yes ]; }
        selected_modules="withscript"
        t() { calls=""; unset LINUX_SETTING_PKG_INDEX_CHECKED LINUX_SETTING_PKG_INDEX_UPDATED; prepare_package_index "$1"; printf "%s\n" "$calls"; }
        IDX_STALE=yes IDX_OK=yes t true
        IDX_STALE=yes IDX_OK=no t true
        IDX_STALE=no IDX_OK=yes t true
        IDX_STALE=yes IDX_OK=yes t false
        selected_modules="allin"; IDX_STALE=yes IDX_OK=yes t true
        selected_modules="withscript"; calls=""; export LINUX_SETTING_PKG_INDEX_CHECKED=1; prepare_package_index true; printf "[%s]" "$calls"
    ' _ "$funcs")" || rc=$?

    local expected
    expected="NYYNY|"$'\n'"run(更新套件索引);ensure;finish(ok:);"$'\n'"run(更新套件索引);ensure;finish(partial:更新失敗，繼續安裝);"$'\n'"ensure;"$'\n'"ensure;"$'\n'$'\n'"[]"
    if [ "$rc" -eq 0 ] && [ "$out" = "$expected" ]; then
        log_pass "套件索引更新在第一個模組前以獨立進度行顯示，失敗為警示並繼續，且只在需要時執行"
    else
        log_fail "套件索引步驟不正確 (rc=$rc): $out"
    fi
}

# 行為測試：Homebrew 只在所選模組宣告 brew_packages 時才詢問，且不在環境檢查階段詢問
test_install_homebrew_offer_conditions() {
    log_test "檢查 Homebrew 詢問時機..."

    local installer="$SCRIPT_DIR/install.sh"
    local env_block
    env_block="$(awk '/^check_environment\(\) \{/{f=1} f{print} f && /^}$/{exit}' "$installer")"
    if [ -z "$env_block" ] || [[ "$env_block" == *"tui_yesno"* ]] || [[ "$env_block" == *"read -r install_brew_answer"* ]]; then
        log_fail "check_environment 仍在環境檢查階段詢問 Homebrew"
        return
    fi
    if [[ "$env_block" != *'shellenv'* ]]; then
        log_fail "check_environment 缺少既有 Homebrew 偵測與 PATH 注入"
        return
    fi

    if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
        log_warn "略過 Homebrew 條件行為測試：需要 bash 4+（關聯陣列）"
        return
    fi
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        log_warn "略過 Homebrew 條件行為測試：root 下設計上不詢問 Homebrew"
        log_pass "Homebrew 詢問已移出環境檢查階段"
        return
    fi

    local funcs
    funcs="$(extract_install_functions selected_modules_need_homebrew homebrew_offer_needed)"
    local out rc=0
    out="$(PATH="/usr/bin:/bin" bash -c '
        eval "$1"
        declare -A MODULE_BREW_PACKAGES=([base]="lsd bat" [python]="" [monitoring]="btop")
        check() { if homebrew_offer_needed "$1"; then printf "Y"; else printf "N"; fi; }
        NON_INTERACTIVE=false INSTALL_MODE=full DRY_RUN=false HOMEBREW_DECISION=""
        check "python"; check "base python"; check "monitoring"
        NON_INTERACTIVE=true; check "base"; NON_INTERACTIVE=false
        INSTALL_MODE=minimal; check "base"; INSTALL_MODE=full
        DRY_RUN=true; check "base"; DRY_RUN=false
        HOMEBREW_DECISION=no; check "base"
    ' _ "$funcs")" || rc=$?

    if [ "$rc" -eq 0 ] && [ "$out" = "NYYNNNN" ]; then
        log_pass "Homebrew 只在所選模組需要且尚未安裝時詢問"
    else
        log_fail "Homebrew 詢問條件不正確 (rc=$rc): $out（預期 NYYNNNN）"
    fi
}

# 行為測試：錯誤畫面顯示實際日誌路徑、依套件管理器給建議、沒有假的重試選項
test_install_error_summary() {
    log_test "檢查安裝失敗畫面內容..."

    local funcs
    funcs="$(extract_install_functions _ansi package_index_update_hint print_error_summary)"
    local tmp_log
    tmp_log="$(mktemp)"

    local apt_out dnf_out rc=0
    apt_out="$(LOG_FILE="$tmp_log" PKG_MANAGER=apt bash -c 'eval "$1"; print_error_summary 2 123 "apt-get install foo"' _ "$funcs")" || rc=$?
    dnf_out="$(LOG_FILE="$tmp_log" PKG_MANAGER=dnf bash -c 'eval "$1"; print_error_summary 1 45 ""' _ "$funcs")" || rc=$?
    rm -f "$tmp_log"

    if [ "$rc" -eq 0 ] && \
       [[ "$apt_out" == *"日誌：$tmp_log"* ]] && \
       [[ "$apt_out" == *"tail -n 50 $tmp_log"* ]] && \
       [[ "$apt_out" == *"sudo apt update"* ]] && \
       [[ "$apt_out" == *"第 123 行（結束碼 2）"* ]] && \
       [[ "$apt_out" != *'$LOG_FILE'* ]] && \
       [[ "$dnf_out" == *"sudo dnf makecache"* ]] && \
       [[ "$dnf_out" != *"apt update"* ]] && \
       ! search_literal '[r]${NC} 重試' "$SCRIPT_DIR/install.sh" && \
       ! search_literal '請重新執行安裝腳本' "$SCRIPT_DIR/install.sh"; then
        log_pass "錯誤畫面顯示實際日誌路徑與對應套件管理器的建議"
    else
        log_fail "錯誤畫面內容不正確 (rc=$rc): $apt_out / $dnf_out"
    fi
}

# 行為測試：--help 不印橫幅；橫幅保留版本字串但不再列出 ./install.sh 快速開始
test_install_help_without_banner() {
    log_test "檢查 --help 不顯示橫幅..."

    local out rc=0
    out="$(bash "$SCRIPT_DIR/install.sh" --help 2>&1)" || rc=$?
    local banner
    banner="$(awk '/^show_welcome\(\) \{/{f=1} f{print} f && /^}$/{exit}' "$SCRIPT_DIR/install.sh")"

    if [ "$rc" -eq 0 ] && \
       [[ "$out" == *"Linux Setting Scripts - 自動安裝腳本 v2.2.9"* ]] && \
       [[ "$out" != *"自動化開發環境配置工具"* ]] && \
       [[ "$out" != *"╔"* ]] && \
       [[ "$banner" == *"Linux Setting Scripts  v2.2.9"* ]] && \
       [[ "$banner" != *"快速開始"* ]]; then
        log_pass "--help 只顯示說明，橫幅已精簡"
    else
        log_fail "--help 仍顯示橫幅或橫幅未精簡 (rc=$rc)"
    fi
}

# 測試網路依賴（可選）
test_network_dependencies() {
    log_test "測試網路依賴..."
    
    urls=(
        "https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main/install.sh"
        "https://astral.sh/uv/install.sh"
        "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
    )
    
    for url in "${urls[@]}"; do
        if curl -s --head "$url" | head -n 1 | grep -q "200 OK"; then
            log_pass "$(basename "$url") 可訪問"
        else
            log_warn "$(basename "$url") 無法訪問"
        fi
    done
}

# 運行所有測試
run_all_tests() {
    echo "========================================"
    echo "Linux Setting Scripts - 測試套件"
    echo "========================================"
    
    test_required_files
    echo
    test_script_syntax
    echo  
    test_script_permissions
    echo
    test_common_library
    echo
    test_argument_parsing
    echo
    test_install_config_requires_path
    echo
    test_install_sudo_guard_no_command_substitution
    echo
    test_install_sudo_guard_behavior
    echo
    test_script_version_bumped
    echo
    test_module_manager_survives_function_scope
    echo
    test_skip_python_check_default
    echo
    test_module_manager_install_path
    test_required_module_manager
    echo
    test_linux_ci_gate_for_extended_suites
    echo
    test_workflow_linux_ci_settings
    echo
    test_preview_script_noninteractive
    echo
    test_preview_config_strict_defaults
    echo
    test_module_manager_strict_safe_access
    echo
    test_module_manager_package_status_cache
    echo
    test_common_tui_backends
    echo
    test_common_tui_backend_hint
    echo
    test_common_tui_log_viewer
    echo
    test_common_tui_quiet_status_logs_are_log_only
    echo
    test_install_remote_bootstrap_status_quiet
    echo
    test_common_fzf_checklist_enter_selects_current_item
    echo
    test_install_module_prompt_backend_neutral
    echo
    test_install_tui_log_flow
    echo
    test_install_guided_tui_flow
    echo
    test_install_tui_wraps_pre_menu_logs
    echo
    test_install_help_tui_backend_docs
    echo
    test_readme_tui_backend_docs
    echo
    test_python_setup_uv_venv_bootstrap
    echo
    test_python_setup_requirements_fallback
    echo
    test_requirements_setuptools_pin
    echo
    test_maintenance_scripts_load_common
    echo
    test_update_tools_requirements_path
    echo
    test_update_tools_venv_pip_fallback
    echo
    test_base_tools_update_nonfatal
    echo
    test_base_tools_ipinfo_opt_in
    echo
    test_secure_download_common_path
    echo
    test_secure_download_variable_namespace
    echo
    test_common_backup_file_strict_default
    echo
    test_terminal_setup_optional_zshrc_backup
    echo
    test_dev_tools_lazygit_tmpdir
    echo
    test_monitoring_tools_systemd_guard
    echo
    test_docker_setup_nonfatal_docker_install
    echo
    test_dockerfile_report_dir_permissions
    echo
    test_docker_compose_report_volume_bootstrap
    echo
    test_docker_compose_linux_suite_gate
    echo
    test_docker_compose_no_obsolete_version_field
    echo
    test_common_idempotent_source_guard
    echo
    test_install_non_interactive_mode
    echo
    test_install_report_reflects_results
    echo
    test_install_progress_text_helpers
    echo
    test_install_progress_run_non_tty
    echo
    test_install_summary_and_checklist_labels
    echo
    test_install_result_screen_behavior
    echo
    test_install_results_exit_code
    echo
    test_guided_exit_status
    test_guided_override_lifecycle
    test_guided_cancel_all_results
    test_guided_advanced_stateless_backend
    test_install_module_checklist_behavior
    echo
    test_install_package_index_step
    echo
    test_install_homebrew_offer_conditions
    echo
    test_install_error_summary
    echo
    test_install_help_without_banner
    echo
    test_network_dependencies
    echo
    
    echo "========================================"
    echo "測試結果"
    echo "========================================"
    echo "通過: $TESTS_PASSED"
    echo "失敗: $TESTS_FAILED"
    echo "總計: $((TESTS_PASSED + TESTS_FAILED))"
    
    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "${GREEN}所有測試通過！${NC}"
        exit 0
    else
        echo -e "${RED}有 $TESTS_FAILED 個測試失敗${NC}"
        exit 1
    fi
}

# 執行測試
run_all_tests
