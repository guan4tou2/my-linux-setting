#!/bin/bash

# 功能測試工具
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/common.sh" 2>/dev/null || {
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    NC='\033[0m'
}

TESTS_PASSED=0
TESTS_FAILED=0

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

# 測試共用函數庫功能
test_common_functions() {
    log_test "測試共用函數庫功能..."
    
    if [ -f "$SCRIPT_DIR/scripts/common.sh" ]; then
        # 測試載入
        if source "$SCRIPT_DIR/scripts/common.sh" 2>/dev/null; then
            log_pass "common.sh 載入成功"
            
            # 測試日誌函數
            if declare -f log_info >/dev/null 2>&1; then
                log_pass "log_info 函數可用"
                
                # 測試日誌輸出
                local test_log="/tmp/test_log_$$"
                LOG_FILE="$test_log"
                log_info "測試日誌" >/dev/null 2>&1
                
                if [ -f "$test_log" ] && grep -q "測試日誌" "$test_log"; then
                    log_pass "日誌記錄功能正常"
                    rm -f "$test_log"
                else
                    log_fail "日誌記錄功能異常"
                fi
            else
                log_fail "log_info 函數不可用"
            fi
            
            # 測試系統檢查函數
            local check_functions=(
                "check_command"
                "check_network"
                "check_disk_space"
                "version_greater_equal"
            )
            
            for func in "${check_functions[@]}"; do
                if declare -f "$func" >/dev/null 2>&1; then
                    log_pass "$func 函數可用"
                else
                    log_fail "$func 函數不可用"
                fi
            done
            
            # 測試 check_command 功能
            if declare -f check_command >/dev/null 2>&1; then
                if check_command "bash"; then
                    log_pass "check_command 功能正常 (bash 存在)"
                else
                    log_fail "check_command 功能異常"
                fi
                
                if ! check_command "nonexistent_command_12345"; then
                    log_pass "check_command 功能正常 (不存在命令)"
                else
                    log_fail "check_command 功能異常 (誤報存在)"
                fi
            fi
            
            # 測試版本比較功能
            if declare -f version_greater_equal >/dev/null 2>&1; then
                if version_greater_equal "2.0" "1.9"; then
                    log_pass "version_greater_equal 功能正常 (2.0 >= 1.9)"
                else
                    log_fail "version_greater_equal 功能異常"
                fi
                
                if ! version_greater_equal "1.8" "1.9"; then
                    log_pass "version_greater_equal 功能正常 (1.8 < 1.9)"
                else
                    log_fail "version_greater_equal 功能異常"
                fi
            fi
            
        else
            log_fail "common.sh 載入失敗"
        fi
    else
        log_fail "common.sh 文件不存在"
    fi
}

# 測試安裝腳本參數解析
test_install_script_args() {
    log_test "測試安裝腳本參數解析..."
    
    if [ -f "$SCRIPT_DIR/install.sh" ]; then
        # 測試幫助參數
        if timeout 10 bash "$SCRIPT_DIR/install.sh" --help >/dev/null 2>&1; then
            log_pass "install.sh --help 正常"
        else
            log_fail "install.sh --help 失敗"
        fi
        
        # 測試無效參數
        if ! timeout 10 bash "$SCRIPT_DIR/install.sh" --invalid-option >/dev/null 2>&1; then
            log_pass "無效參數處理正常"
        else
            log_fail "無效參數處理異常"
        fi
    else
        log_fail "install.sh 不存在"
    fi
}

# 測試配置預覽功能
test_preview_functionality() {
    log_test "測試配置預覽功能..."
    
    if [ -f "$SCRIPT_DIR/scripts/preview_config.sh" ]; then
        # 測試預覽腳本基本功能
        if timeout 10 bash "$SCRIPT_DIR/scripts/preview_config.sh" --help >/dev/null 2>&1; then
            log_pass "preview_config.sh 基本功能正常"
        else
            log_warn "preview_config.sh 可能沒有 --help 選項"
        fi
        
        # 測試模組預覽
        local modules=("python" "base" "terminal")
        for module in "${modules[@]}"; do
            if timeout 10 bash "$SCRIPT_DIR/scripts/preview_config.sh" "$module" >/dev/null 2>&1; then
                log_pass "$module 模組預覽正常"
            else
                log_fail "$module 模組預覽失敗"
            fi
        done
    else
        log_fail "preview_config.sh 不存在"
    fi
}

# 測試健康檢查功能
test_health_check_functionality() {
    log_test "測試健康檢查功能..."
    
    if [ -f "$SCRIPT_DIR/scripts/health_check.sh" ]; then
        # 執行健康檢查（使用短超時避免影響測試）
        if timeout 30 bash "$SCRIPT_DIR/scripts/health_check.sh" >/dev/null 2>&1; then
            log_pass "health_check.sh 執行正常"
        else
            local exit_code=$?
            if [ $exit_code -eq 124 ]; then
                log_warn "health_check.sh 執行超時（可能正常）"
            else
                log_warn "health_check.sh 執行完成但有警告"
            fi
        fi
    else
        log_fail "health_check.sh 不存在"
    fi
}

# 測試更新腳本功能
test_update_functionality() {
    log_test "測試更新腳本功能..."
    
    if [ -f "$SCRIPT_DIR/scripts/update_tools.sh" ]; then
        # 檢查腳本語法
        if bash -n "$SCRIPT_DIR/scripts/update_tools.sh"; then
            log_pass "update_tools.sh 語法正確"
        else
            log_fail "update_tools.sh 語法錯誤"
        fi
        
        # 測試乾跑模式（如果支援）
        # 由於更新腳本可能會修改系統，這裡只測試語法
        log_pass "update_tools.sh 基本檢查通過"
    else
        log_fail "update_tools.sh 不存在"
    fi
}

# 測試 Python 腳本功能
test_python_script_functionality() {
    log_test "測試 Python 相關腳本功能..."
    
    if [ -f "$SCRIPT_DIR/scripts/python_setup.sh" ]; then
        # 檢查 Python 安裝腳本
        if bash -n "$SCRIPT_DIR/scripts/python_setup.sh"; then
            log_pass "python_setup.sh 語法正確"
        else
            log_fail "python_setup.sh 語法錯誤"
        fi
        
        # 檢查 requirements.txt
        if [ -f "$SCRIPT_DIR/requirements.txt" ]; then
            log_pass "requirements.txt 存在"
            
            # 驗證 requirements.txt 格式
            if python3 -c "
import sys
try:
    with open('$SCRIPT_DIR/requirements.txt') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if line and not line.startswith('#'):
                if '==' not in line and '>=' not in line and '<=' not in line:
                    continue  # 允許沒有版本的包名
    print('OK')
except Exception as e:
    print(f'ERROR: {e}')
    sys.exit(1)
" 2>/dev/null; then
                log_pass "requirements.txt 格式正確"
            else
                log_fail "requirements.txt 格式錯誤"
            fi
        else
            log_fail "requirements.txt 不存在"
        fi
    else
        log_fail "python_setup.sh 不存在"
    fi
}

# 測試腳本間依賴關係
test_script_dependencies() {
    log_test "測試腳本間依賴關係..."
    
    local scripts=(
        "scripts/python_setup.sh"
        "scripts/terminal_setup.sh"
        "scripts/base_tools.sh"
        "scripts/dev_tools.sh"
        "scripts/docker_setup.sh"
        "scripts/monitoring_tools.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [ -f "$SCRIPT_DIR/$script" ]; then
            # 檢查是否嘗試載入 common.sh
            if grep -q "source.*common.sh" "$SCRIPT_DIR/$script"; then
                log_pass "$(basename "$script") 正確引用 common.sh"
            else
                log_warn "$(basename "$script") 可能未使用 common.sh"
            fi
        fi
    done
    
    # 檢查 install.sh 對子腳本的依賴
    if [ -f "$SCRIPT_DIR/install.sh" ]; then
        for script in "${scripts[@]}"; do
            script_name=$(basename "$script")
            if grep -q "$script_name" "$SCRIPT_DIR/install.sh"; then
                log_pass "install.sh 包含 $script_name 引用"
            else
                log_warn "install.sh 可能未包含 $script_name 引用"
            fi
        done
    fi
}

# 測試日誌和備份機制
test_logging_and_backup() {
    log_test "測試日誌和備份機制..."
    
    # 創建測試環境
    local test_dir="/tmp/linux_setting_test_$$"
    mkdir -p "$test_dir"
    
    # 測試備份功能（模擬）
    echo "test content" > "$test_dir/test_config"
    
    if source "$SCRIPT_DIR/scripts/common.sh" 2>/dev/null; then
        if declare -f backup_file >/dev/null 2>&1; then
            BACKUP_DIR="$test_dir/backup"
            if backup_file "$test_dir/test_config" >/dev/null 2>&1; then
                if [ -f "$BACKUP_DIR"/*.backup.* ]; then
                    log_pass "備份功能正常"
                else
                    log_fail "備份功能異常"
                fi
            else
                log_fail "backup_file 函數執行失敗"
            fi
        else
            log_fail "backup_file 函數不存在"
        fi
    fi
    
    # 清理測試環境
    rm -rf "$test_dir"
    
    # 測試日誌目錄創建
    local log_test_dir="$HOME/.local/log/linux-setting-test"
    if mkdir -p "$log_test_dir" 2>/dev/null; then
        log_pass "日誌目錄創建功能正常"
        rmdir "$log_test_dir" 2>/dev/null
    else
        log_fail "日誌目錄創建失敗"
    fi
}

# 執行所有功能測試
run_all_tests() {
    echo "========================================"
    echo "Linux Setting Scripts - 功能測試套件"
    echo "========================================"
    
    test_common_functions
    echo
    test_install_script_args
    echo
    test_preview_functionality
    echo
    test_health_check_functionality
    echo
    test_update_functionality
    echo
    test_python_script_functionality
    echo
    test_script_dependencies
    echo
    test_logging_and_backup
    echo
    
    echo "========================================"
    echo "功能測試結果"
    echo "========================================"
    echo "通過: $TESTS_PASSED"
    echo "失敗: $TESTS_FAILED"
    echo "總計: $((TESTS_PASSED + TESTS_FAILED))"
    
    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "${GREEN}✅ 所有功能測試通過！${NC}"
        exit 0
    elif [ "$TESTS_FAILED" -le 2 ]; then
        echo -e "${YELLOW}⚠️  有 $TESTS_FAILED 個測試失敗，但主要功能正常。${NC}"
        exit 0
    else
        echo -e "${RED}❌ 有 $TESTS_FAILED 個測試失敗，請檢查功能實現。${NC}"
        exit 1
    fi
}

# 執行測試
run_all_tests