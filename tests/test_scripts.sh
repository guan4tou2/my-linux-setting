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

# 檢查 base_tools.sh 套件庫更新失敗時不應中止安裝
test_base_tools_update_nonfatal() {
    log_test "檢查 base_tools.sh 更新失敗容錯..."

    local base_tools="$SCRIPT_DIR/scripts/core/base_tools.sh"
    if [ ! -f "$base_tools" ]; then
        log_fail "找不到 base_tools.sh"
        return
    fi

    if search_literal 'update_system || log_warning "系統套件列表更新失敗，將繼續安裝流程"' "$base_tools" && \
       search_literal 'sudo apt-get update || log_warning "APT 套件列表更新失敗，將繼續安裝流程"' "$base_tools"; then
        log_pass "base_tools.sh 已容忍套件庫更新失敗"
    else
        log_fail "base_tools.sh 套件庫更新失敗仍可能中止流程"
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
    test_python_setup_uv_venv_bootstrap
    echo
    test_python_setup_requirements_fallback
    echo
    test_requirements_setuptools_pin
    echo
    test_base_tools_update_nonfatal
    echo
    test_secure_download_common_path
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
