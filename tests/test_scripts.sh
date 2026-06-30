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

    if search_literal 'declare -A MODULE_PKG_STATUS_CACHE' "$module_manager" && \
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
       search_literal 'func_list="$func_list ensure_tui_available tui_checklist tui_checklist_with_state tui_menu tui_yesno tui_msgbox tui_log_viewer tui_gauge tui_inputbox"' "$common"; then
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
        USE_TUI=true \
        TUI_MODE=quiet \
        ENABLE_LOGGING=true \
        LOG_FILE="$tmp_log" \
        bash -c 'source "$1"; log_info "hidden info"; log_success "hidden success"; log_warning "hidden warning"' _ "$common" 2>&1
    )

    local cli_output
    cli_output=$(
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

# 檢查 remote bootstrap 階段不再直接輸出 INFO/SUCCESS，避免 common.sh 載入前污染 TUI
test_install_remote_bootstrap_status_quiet() {
    log_test "檢查 remote bootstrap 狀態輸出可被 quiet 模式收斂..."

    local installer="$SCRIPT_DIR/install.sh"
    if [ ! -f "$installer" ]; then
        log_fail "找不到 install.sh"
        return
    fi

    if search_literal 'bootstrap_status()' "$installer" && \
       search_literal 'bootstrap_status "INFO" "Downloading common library from remote source..."' "$installer" && \
       search_literal 'bootstrap_status "SUCCESS" "Common library loaded"' "$installer" && \
       search_literal '[ "$level" != "ERROR" ] && [ "${TUI_MODE:-quiet}" = "quiet" ]' "$installer" && \
       ! search_literal 'echo -e "\033[0;36mINFO: Downloading common library from remote source...\033[0m"' "$installer" && \
       ! search_literal 'echo -e "\033[0;32mSUCCESS: Common library loaded\033[0m"' "$installer"; then
        log_pass "remote bootstrap 狀態輸出已支援 quiet 收斂"
    else
        log_fail "remote bootstrap 仍可能直接輸出 INFO/SUCCESS"
    fi
}

# 檢查 fzf checklist 允許 Enter 直接選擇目前項目，而不是啟動時預選全部
test_common_fzf_checklist_enter_selects_current_item() {
    log_test "檢查 fzf checklist 的 Enter 選擇行為..."

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
       [[ "$fzf_args" == *"Enter 選擇目前項目；Tab 多選；Esc 取消"* ]] && \
       [[ "$fzf_args" != *"start:select-all"* ]]; then
        log_pass "fzf checklist 可用 Enter 選目前項目"
    else
        log_fail "fzf checklist 仍可能預選全部，導致 Enter 無法直覺選擇目前項目"
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

    if ! search_literal '請使用空格鍵選擇要安裝的模組' "$installer" && \
       search_literal '請選擇要安裝的模組，依目前選單提示選取後確認：' "$installer"; then
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
       search_literal 'tui_log_viewer "安裝日誌" "$LOG_FILE"' "$installer"; then
        log_pass "install.sh 已將安裝狀態與日誌入口包進 TUI"
    else
        log_fail "install.sh 缺少 TUI 安裝狀態或日誌入口"
    fi
}

# 檢查 TUI quiet 模式下，安裝日誌提示與 remote 下載腳本訊息不再直接刷到終端
test_install_tui_wraps_pre_menu_logs() {
    log_test "檢查 TUI quiet 會包住安裝日誌與 remote 下載訊息..."

    local installer="$SCRIPT_DIR/install.sh"
    if [ ! -f "$installer" ]; then
        log_fail "找不到 install.sh"
        return
    fi

    if search_literal 'installer_tui_quiet()' "$installer" && \
       search_literal 'run_logged_command()' "$installer" && \
       search_literal 'run_remote_script_downloads()' "$installer" && \
       search_literal 'download_remote_file()' "$installer" && \
       search_literal 'if installer_tui_quiet; then' "$installer" && \
       search_literal 'log_success "安裝日誌將保存到：$LOG_FILE"' "$installer" && \
       search_literal 'run_logged_command install_module "$module"' "$installer" && \
       search_literal 'run_remote_script_downloads' "$installer" && \
       ! search_literal 'exec 1> >(tee -a "$LOG_FILE") 2>&1' "$installer" && \
       ! search_literal 'printf "${CYAN}########## 下載安裝腳本 ##########${NC}\n"' "$installer" && \
       ! search_literal 'printf "${BLUE}下載 core/$script...${NC}\n"' "$installer" && \
       ! search_literal 'printf "${BLUE}下載 utils/secure_download.sh...${NC}\n"' "$installer"; then
        log_pass "TUI quiet 已收斂前置日誌與 remote 下載訊息"
    else
        log_fail "TUI quiet 仍可能讓安裝日誌或 remote 下載訊息刷到終端"
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
       search_literal '"$VENV_DIR/bin/python" -m pip install --upgrade thefuck ranger-fm s-tui' "$update_tools"; then
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

# 檢查 common.sh 的 sudo 次數統計不會產生 0\n0 造成整數比較錯誤
test_common_sudo_count_numeric() {
    log_test "檢查 common.sh 的 sudo 計數數值穩定性..."

    local common_sh="$SCRIPT_DIR/scripts/core/common.sh"
    if [ ! -f "$common_sh" ]; then
        log_fail "找不到 common.sh"
        return
    fi

    if search_literal 'sudo_count=$(grep -cE "^\s*(sudo|su)\s" "$script_file" 2>/dev/null || true)' "$common_sh" && \
       search_literal 'sudo_count="${sudo_count:-0}"' "$common_sh"; then
        log_pass "common.sh 已避免 sudo_count 非數值輸出"
    else
        log_fail "common.sh 的 sudo_count 仍可能造成 integer expression expected"
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
    test_script_version_bumped
    echo
    test_skip_python_check_default
    echo
    test_module_manager_install_path
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
    test_common_sudo_count_numeric
    echo
    test_install_non_interactive_mode
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
