#!/bin/bash

# 完整測試套件執行器
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$SCRIPT_DIR/tests"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 測試結果統計
TOTAL_TESTS_PASSED=0
TOTAL_TESTS_FAILED=0
TOTAL_TEST_SUITES=0
FAILED_SUITES=()

# 測試報告
REPORT_FILE="/tmp/linux_setting_test_report_$(date +%Y%m%d_%H%M%S).txt"

log_header() {
    echo -e "${CYAN}======================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}======================================${NC}"
}

log_suite() {
    echo -e "${BLUE}[SUITE]${NC} $1"
}

log_result() {
    local suite_name="$1"
    local exit_code="$2"
    local passed="$3"
    local failed="$4"
    
    TOTAL_TEST_SUITES=$((TOTAL_TEST_SUITES + 1))
    TOTAL_TESTS_PASSED=$((TOTAL_TESTS_PASSED + passed))
    TOTAL_TESTS_FAILED=$((TOTAL_TESTS_FAILED + failed))
    
    if [ "$exit_code" -eq 0 ]; then
        echo -e "${GREEN}[SUITE PASSED]${NC} $suite_name (通過: $passed, 失敗: $failed)"
    else
        echo -e "${RED}[SUITE FAILED]${NC} $suite_name (通過: $passed, 失敗: $failed)"
        FAILED_SUITES+=("$suite_name")
    fi
}

# 執行單個測試套件
run_test_suite() {
    local test_script="$1"
    local suite_name="$2"
    
    if [ ! -f "$test_script" ]; then
        echo -e "${RED}[ERROR]${NC} 測試文件不存在: $test_script"
        return 1
    fi
    
    if [ ! -x "$test_script" ]; then
        chmod +x "$test_script"
    fi
    
    log_suite "執行 $suite_name"
    echo ""
    
    # 執行測試並捕獲輸出
    local test_output
    test_output=$(bash "$test_script" 2>&1)
    local exit_code=$?
    
    # 解析測試結果
    local passed failed
    if echo "$test_output" | grep -q "通過:"; then
        passed=$(echo "$test_output" | grep "通過:" | sed 's/.*通過: \([0-9]*\).*/\1/')
        failed=$(echo "$test_output" | grep "失敗:" | sed 's/.*失敗: \([0-9]*\).*/\1/')
    else
        passed=0
        failed=1
    fi
    
    # 記錄到報告文件
    {
        echo "========================================"
        echo "測試套件: $suite_name"
        echo "時間: $(date)"
        echo "退出碼: $exit_code"
        echo "通過: $passed"
        echo "失敗: $failed"
        echo "========================================"
        echo "$test_output"
        echo ""
    } >> "$REPORT_FILE"
    
    # 顯示結果
    echo "$test_output"
    echo ""
    log_result "$suite_name" "$exit_code" "$passed" "$failed"
    echo ""
    
    return $exit_code
}

# 預檢查
pre_check() {
    log_header "執行預檢查"
    
    # 檢查測試文件是否存在
    local test_files=(
        "$TESTS_DIR/test_scripts.sh"
        "$TESTS_DIR/test_dependencies.sh"
        "$TESTS_DIR/test_functionality.sh"
    )
    
    for file in "${test_files[@]}"; do
        if [ -f "$file" ]; then
            echo -e "${GREEN}✓${NC} $(basename "$file") 存在"
        else
            echo -e "${RED}✗${NC} $(basename "$file") 不存在"
            exit 1
        fi
    done
    
    # 檢查主腳本
    if [ -f "$SCRIPT_DIR/install.sh" ]; then
        echo -e "${GREEN}✓${NC} install.sh 存在"
    else
        echo -e "${RED}✗${NC} install.sh 不存在"
        exit 1
    fi
    
    # 檢查共用函數庫
    if [ -f "$SCRIPT_DIR/scripts/common.sh" ]; then
        echo -e "${GREEN}✓${NC} common.sh 存在"
    else
        echo -e "${RED}✗${NC} common.sh 不存在"
        exit 1
    fi
    
    echo ""
}

# 系統信息收集
collect_system_info() {
    log_header "收集系統信息"
    
    {
        echo "========================================"
        echo "系統信息報告"
        echo "時間: $(date)"
        echo "========================================"
        echo "操作系統: $(uname -a)"
        echo "發行版: $(cat /etc/os-release 2>/dev/null | head -3 || echo '未知')"
        echo "Python 版本: $(python3 --version 2>/dev/null || echo '未安裝')"
        echo "磁盤空間: $(df -h / | tail -1)"
        echo "內存信息: $(free -h | head -2)"
        echo "當前用戶: $(whoami)"
        echo "當前目錄: $(pwd)"
        echo "PATH: $PATH"
        echo "========================================"
        echo ""
    } > "$REPORT_FILE"
    
    echo "系統信息已收集到報告文件: $REPORT_FILE"
    echo ""
}

# 執行所有測試套件
run_all_test_suites() {
    log_header "執行測試套件"
    
    # 1. 腳本語法和基礎測試
    run_test_suite "$TESTS_DIR/test_scripts.sh" "腳本語法測試"
    
    # 2. 系統依賴測試
    run_test_suite "$TESTS_DIR/test_dependencies.sh" "系統依賴測試"
    
    # 3. 功能測試
    run_test_suite "$TESTS_DIR/test_functionality.sh" "功能測試"
}

# 生成最終報告
generate_final_report() {
    log_header "測試總結報告"
    
    local success_rate
    if [ $((TOTAL_TESTS_PASSED + TOTAL_TESTS_FAILED)) -gt 0 ]; then
        success_rate=$((TOTAL_TESTS_PASSED * 100 / (TOTAL_TESTS_PASSED + TOTAL_TESTS_FAILED)))
    else
        success_rate=0
    fi
    
    {
        echo "========================================"
        echo "最終測試報告"
        echo "時間: $(date)"
        echo "========================================"
        echo "測試套件總數: $TOTAL_TEST_SUITES"
        echo "測試項目總數: $((TOTAL_TESTS_PASSED + TOTAL_TESTS_FAILED))"
        echo "通過測試數: $TOTAL_TESTS_PASSED"
        echo "失敗測試數: $TOTAL_TESTS_FAILED"
        echo "成功率: ${success_rate}%"
        echo ""
        
        if [ ${#FAILED_SUITES[@]} -gt 0 ]; then
            echo "失敗的測試套件:"
            for suite in "${FAILED_SUITES[@]}"; do
                echo "  - $suite"
            done
        else
            echo "所有測試套件都通過了！"
        fi
        
        echo ""
        echo "詳細報告已保存到: $REPORT_FILE"
        echo "========================================"
    } >> "$REPORT_FILE"
    
    # 顯示報告
    echo ""
    echo "📊 測試統計："
    echo "  測試套件: $TOTAL_TEST_SUITES"
    echo "  測試項目: $((TOTAL_TESTS_PASSED + TOTAL_TESTS_FAILED))"
    echo "  ✅ 通過: $TOTAL_TESTS_PASSED"
    echo "  ❌ 失敗: $TOTAL_TESTS_FAILED"
    echo "  📈 成功率: ${success_rate}%"
    echo ""
    
    if [ ${#FAILED_SUITES[@]} -gt 0 ]; then
        echo -e "${RED}失敗的測試套件:${NC}"
        for suite in "${FAILED_SUITES[@]}"; do
            echo -e "${RED}  ✗ $suite${NC}"
        done
        echo ""
    fi
    
    echo "📄 詳細報告: $REPORT_FILE"
    echo ""
}

# 提供建議和後續步驟
provide_recommendations() {
    if [ ${#FAILED_SUITES[@]} -eq 0 ]; then
        log_header "🎉 恭喜！所有測試通過"
        cat << 'EOF'
您的系統已準備好安裝 Linux Setting Scripts！

🚀 下一步：
  1. 運行安裝腳本：./install.sh
  2. 或選擇特定選項：./install.sh --help
  3. 預覽配置：./scripts/preview_config.sh

📚 更多選項：
  - 最小安裝：./install.sh --minimal
  - 使用鏡像：./install.sh --mirror china
  - 詳細模式：./install.sh --verbose
EOF
    elif [ ${#FAILED_SUITES[@]} -le 1 ] && [ "$TOTAL_TESTS_FAILED" -le 3 ]; then
        log_header "⚠️  輕微問題，但可以繼續"
        cat << 'EOF'
雖然有一些測試失敗，但主要功能應該正常。

🔧 建議：
  1. 檢查網絡連接
  2. 確保有足夠的磁盤空間
  3. 運行：./install.sh --verbose 查看詳細信息

🚀 可以嘗試安裝：
  - 測試安裝：./install.sh --minimal
  - 檢查依賴：./tests/test_dependencies.sh
EOF
    else
        log_header "❌ 需要修復問題"
        cat << 'EOF'
發現多個問題，建議先修復後再安裝。

🔧 修復建議：
  1. 檢查系統是否為 Ubuntu/Debian
  2. 確保 Python 3.8+ 已安裝
  3. 檢查網絡連接和權限
  4. 運行單個測試查看具體問題：
     - ./tests/test_dependencies.sh
     - ./tests/test_functionality.sh

📄 查看詳細錯誤信息：
     cat $REPORT_FILE
EOF
    fi
    echo ""
}

# 主函數
main() {
    local start_time
    start_time=$(date +%s)
    
    echo ""
    echo "🧪 Linux Setting Scripts - 完整測試套件"
    echo ""
    
    # 解析參數
    local quick_mode=false
    local verbose_mode=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --quick)
                quick_mode=true
                shift
                ;;
            --verbose|-v)
                verbose_mode=true
                shift
                ;;
            --help|-h)
                cat << 'EOF'
使用方法: ./tests/run_all_tests.sh [選項]

選項:
  --quick     快速模式（跳過某些耗時測試）
  --verbose   詳細輸出模式
  --help      顯示此幫助信息

範例:
  ./tests/run_all_tests.sh           # 完整測試
  ./tests/run_all_tests.sh --quick   # 快速測試
  ./tests/run_all_tests.sh --verbose # 詳細測試
EOF
                exit 0
                ;;
            *)
                echo "未知參數: $1"
                echo "使用 --help 查看用法"
                exit 1
                ;;
        esac
    done
    
    # 設置環境變數
    if [ "$verbose_mode" = true ]; then
        export DEBUG=true
        export VERBOSE=true
    fi
    
    if [ "$quick_mode" = true ]; then
        export QUICK_MODE=true
    fi
    
    # 執行測試流程
    collect_system_info
    pre_check
    run_all_test_suites
    generate_final_report
    provide_recommendations
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo "⏱️  總測試時間: $(printf '%02d:%02d' $((duration / 60)) $((duration % 60)))"
    echo ""
    
    # 返回適當的退出碼
    if [ ${#FAILED_SUITES[@]} -eq 0 ]; then
        exit 0
    elif [ ${#FAILED_SUITES[@]} -le 1 ] && [ "$TOTAL_TESTS_FAILED" -le 3 ]; then
        exit 0  # 輕微問題，允許繼續
    else
        exit 1  # 重大問題
    fi
}

# 執行主函數
main "$@"