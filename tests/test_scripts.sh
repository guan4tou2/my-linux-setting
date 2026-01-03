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