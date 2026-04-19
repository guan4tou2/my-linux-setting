#!/usr/bin/env bash

# 完整系統測試和驗證 - 全面測試 Linux Setting Scripts 功能

# 載入共用函數庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || exit 1
if [ -f "$SCRIPT_DIR/config_manager_simple.sh" ]; then
    source "$SCRIPT_DIR/config_manager_simple.sh" 2>/dev/null || true
fi

log_info "########## 完整系統測試和驗證 ##########"

readonly TEST_LOG_FILE="$HOME/.local/log/linux-setting/system_test_$(date +%Y%m%d_%H%M%S).log"
readonly TEST_CACHE_DIR="$HOME/.cache/linux-setting/system-test"
readonly TEST_REPORT_FILE="$TEST_CACHE_DIR/test_report_$(date +%Y%m%d_%H%M%S).html"

# 確保目錄存在
mkdir -p "$TEST_CACHE_DIR"
mkdir -p "$(dirname "$TEST_LOG_FILE")"

# 測試配置
TEST_VERBOSE="${TEST_VERBOSE:-false}"
TEST_PARALLEL="${TEST_PARALLEL:-true}"
TEST_TIMEOUT="${TEST_TIMEOUT:-300}"  # 5分鐘
GENERATE_REPORT="${GENERATE_REPORT:-true}"

# 測試統計
TEST_TOTAL=0
TEST_PASSED=0
TEST_FAILED=0
TEST_SKIPPED=0
TEST_WARNINGS=0

# 測試結果數組
declare -a TEST_RESULTS
declare -a TEST_DETAILS

# 記錄測試日誌
log_test() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" >> "$TEST_LOG_FILE"
    
    case "$level" in
        "ERROR") log_error "$message" ;;
        "WARN") log_warning "$message" ;;
        "INFO") log_info "$message" ;;
        "PASS") log_success "$message" ;;
        "FAIL") log_error "$message" ;;
        "SKIP") log_warning "$message" ;;
        *) log_debug "$message" ;;
    esac
}

# 執行測試
run_test() {
    local test_name="$1"
    local test_function="$2"
    local test_description="$3"
    
    TEST_TOTAL=$((TEST_TOTAL + 1))
    
    log_test "INFO" "開始測試: $test_name - $test_description"
    
    # 設置測試超時
    local start_time
    start_time=$(date +%s)
    
    # 執行測試
    local test_result="FAIL"
    local test_output=""
    local test_error=""
    
    if timeout "$TEST_TIMEOUT" bash -c "$test_function" 2>"$TEST_CACHE_DIR/test_error_$$"; then
        test_result="PASS"
        TEST_PASSED=$((TEST_PASSED + 1))
        log_test "PASS" "✅ $test_name: 通過"
    else
        test_error=$(cat "$TEST_CACHE_DIR/test_error_$$" 2>/dev/null || true)
        TEST_FAILED=$((TEST_FAILED + 1))
        log_test "FAIL" "❌ $test_name: 失敗 - $test_error"
    fi
    
    # 清理臨時文件
    rm -f "$TEST_CACHE_DIR/test_error_$$"
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # 記錄測試結果
    TEST_RESULTS+=("$test_name:$test_result:$duration:$test_description")
    TEST_DETAILS+=("$test_name:$test_result:$duration:$test_description:$test_error")
}

# 跳過測試
skip_test() {
    local test_name="$1"
    local reason="$2"
    
    TEST_TOTAL=$((TEST_TOTAL + 1))
    TEST_SKIPPED=$((TEST_SKIPPED + 1))
    
    log_test "SKIP" "⏭️  $test_name: 跳過 - $reason"
    TEST_RESULTS+=("$test_name:SKIP:0:跳過 - $reason")
    TEST_DETAILS+=("$test_name:SKIP:0:跳過 - $reason:")
}

# 測試基礎環境
test_basic_environment() {
    # 測試基本命令
    command -v bash >/dev/null || return 1
    command -v git >/dev/null || return 1
    command -v curl >/dev/null || return 1
    
    # 測試文件權限
    [ -r "$SCRIPT_DIR/common.sh" ] || return 1
    [ -x "$SCRIPT_DIR/../install.sh" ] || return 1
    
    # 測試目錄結構
    [ -d "$HOME/.local" ] || return 1
    [ -d "$HOME/.cache" ] || return 1
    [ -d "$HOME/.config" ] || return 1
    
    return 0
}

# 測試共用函數庫
test_common_library() {
    # 測試日誌函數
    log_info "測試日誌功能" >/dev/null
    log_warning "測試警告功能" >/dev/null
    log_error "測試錯誤功能" >/dev/null
    
    # 測試進度條（如果可用）
    if declare -f show_progress >/dev/null 2>&1; then
        show_progress 50 100 >/dev/null
    fi
    
    # 測試實用函數
    check_command "bash" || return 1
    get_os_type >/dev/null || return 1
    
    return 0
}

# 測試配置管理系統
test_config_management() {
    # 測試配置初始化
    if [ -f "$SCRIPT_DIR/config_manager_simple.sh" ]; then
        "$SCRIPT_DIR/config_manager_simple.sh" init >/dev/null 2>&1 || return 1
        
        # 測試配置讀寫
        "$SCRIPT_DIR/config_manager_simple.sh" set test_key "test_value" >/dev/null 2>&1 || return 1
        local value
        value=$("$SCRIPT_DIR/config_manager_simple.sh" get test_key) || return 1
        [ "$value" = "test_value" ] || return 1
    fi
    
    return 0
}

# 測試安全下載機制
test_secure_download() {
    local secure_download_path=""

    # 嘗試多個可能的路徑
    if [ -f "$SCRIPT_DIR/utils/secure_download.sh" ]; then
        secure_download_path="$SCRIPT_DIR/utils/secure_download.sh"
    elif [ -f "$SCRIPT_DIR/../utils/secure_download.sh" ]; then
        secure_download_path="$SCRIPT_DIR/../utils/secure_download.sh"
    elif [ -f "$SCRIPT_DIR/secure_download.sh" ]; then
        secure_download_path="$SCRIPT_DIR/secure_download.sh"
    fi

    if [ -n "$secure_download_path" ]; then
        # 測試腳本語法
        bash -n "$secure_download_path" || return 1

        # 測試安全檢查函數（如果可用）
        if source "$secure_download_path" 2>/dev/null; then
            if declare -f verify_domain >/dev/null 2>&1; then
                verify_domain "github.com" || return 1
            fi
        fi
    fi

    return 0
}

# 測試健康檢查系統
test_health_check() {
    if [ -f "$SCRIPT_DIR/health_check.sh" ]; then
        # 測試腳本語法
        bash -n "$SCRIPT_DIR/health_check.sh" || return 1
        
        # 測試快速健康檢查
        timeout 30 "$SCRIPT_DIR/health_check.sh" quick >/dev/null 2>&1 || return 1
    fi
    
    return 0
}

# 測試診斷系統
test_diagnostic_system() {
    if [ -f "$SCRIPT_DIR/diagnostic_system.sh" ]; then
        # 測試腳本語法
        bash -n "$SCRIPT_DIR/diagnostic_system.sh" || return 1
        
        # 測試系統信息收集
        timeout 30 "$SCRIPT_DIR/diagnostic_system.sh" collect >/dev/null 2>&1
    fi
    
    return 0
}

# 測試自動同步機制
test_auto_sync() {
    if [ -f "$SCRIPT_DIR/auto_sync.sh" ]; then
        # 測試腳本語法
        bash -n "$SCRIPT_DIR/auto_sync.sh" || return 1
        
        # 測試版本檢查
        timeout 15 "$SCRIPT_DIR/auto_sync.sh" version >/dev/null 2>&1
    fi
    
    return 0
}

# 測試自動修復系統
test_auto_repair() {
    if [ -f "$SCRIPT_DIR/auto_repair.sh" ]; then
        # 測試腳本語法
        bash -n "$SCRIPT_DIR/auto_repair.sh" || return 1
        
        # 測試狀態檢查
        timeout 20 "$SCRIPT_DIR/auto_repair.sh" status >/dev/null 2>&1
        
        # 測試診斷功能
        timeout 30 "$SCRIPT_DIR/auto_repair.sh" diagnose >/dev/null 2>&1
    fi
    
    return 0
}

# 測試遠程同步系統
test_remote_sync() {
    if [ -f "$SCRIPT_DIR/remote_sync.sh" ]; then
        # 測試腳本語法
        bash -n "$SCRIPT_DIR/remote_sync.sh" || return 1
        
        # 測試設備ID生成
        timeout 10 "$SCRIPT_DIR/remote_sync.sh" id >/dev/null 2>&1
        
        # 測試狀態檢查
        timeout 10 "$SCRIPT_DIR/remote_sync.sh" status >/dev/null 2>&1
    fi
    
    return 0
}

# 測試自動恢復系統
test_auto_recovery() {
    if [ -f "$SCRIPT_DIR/auto_recovery.sh" ]; then
        # 測試腳本語法
        bash -n "$SCRIPT_DIR/auto_recovery.sh" || return 1
        
        # 測試系統檢查
        timeout 30 "$SCRIPT_DIR/auto_recovery.sh" check >/dev/null 2>&1
        
        # 測試狀態報告
        timeout 15 "$SCRIPT_DIR/auto_recovery.sh" status >/dev/null 2>&1
    fi
    
    return 0
}

# 測試配置版本控制
test_config_version_control() {
    if [ -f "$SCRIPT_DIR/config_version_control.sh" ]; then
        # 測試腳本語法
        bash -n "$SCRIPT_DIR/config_version_control.sh" || return 1
        
        # 測試狀態檢查
        timeout 15 "$SCRIPT_DIR/config_version_control.sh" status >/dev/null 2>&1
    fi
    
    return 0
}

# 測試自動更新機制
test_auto_update() {
    if [ -f "$SCRIPT_DIR/auto_update.sh" ]; then
        # 測試腳本語法
        bash -n "$SCRIPT_DIR/auto_update.sh" || return 1
        
        # 測試狀態檢查
        timeout 15 "$SCRIPT_DIR/auto_update.sh" status >/dev/null 2>&1
    fi
    
    return 0
}

# 測試主安裝腳本
test_main_installer() {
    local installer="$SCRIPT_DIR/../install.sh"
    
    if [ -f "$installer" ]; then
        # 測試腳本語法
        bash -n "$installer" || return 1
        
        # 測試參數解析
        "$installer" --help >/dev/null 2>&1 || return 1
        
        # 測試乾跑模式（如果支援）
        timeout 30 "$installer" --dry-run >/dev/null 2>&1 || true
    fi
    
    return 0
}

# 測試各個子腳本
test_sub_scripts() {
    local scripts_dir="$SCRIPT_DIR"
    local failed_scripts=()
    
    # 測試所有 .sh 文件的語法
    for script in "$scripts_dir"/*.sh; do
        [ -f "$script" ] || continue
        local script_name=$(basename "$script")
        
        if ! bash -n "$script"; then
            failed_scripts+=("$script_name")
        fi
    done
    
    if [ ${#failed_scripts[@]} -gt 0 ]; then
        log_test "ERROR" "語法檢查失敗的腳本: ${failed_scripts[*]}"
        return 1
    fi
    
    return 0
}

# 測試網絡連接
test_network_connectivity() {
    # 測試基本網絡連接
    ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1 || return 1
    
    # 測試 DNS 解析
    nslookup google.com >/dev/null 2>&1 || return 1
    
    # 測試 HTTPS 連接
    curl -s --max-time 10 https://google.com >/dev/null 2>&1 || return 1
    
    return 0
}

# 測試權限檢查
test_permissions() {
    # 測試必要目錄的寫入權限
    [ -w "$HOME" ] || return 1
    [ -w "/tmp" ] || return 1
    
    # 測試創建必要目錄的權限
    mkdir -p "$HOME/.test_permission_$$" || return 1
    rmdir "$HOME/.test_permission_$$" || return 1
    
    # 測試腳本執行權限
    [ -x "$SCRIPT_DIR/../install.sh" ] || return 1
    
    return 0
}

# 測試系統資源
test_system_resources() {
    # 檢查磁盤空間（至少需要 1GB）
    local available_space
    available_space=$(df "$HOME" | awk 'NR==2 {print $4}')
    [ "$available_space" -gt 1048576 ] || return 1  # 1GB in KB
    
    # 檢查內存使用
    local mem_usage
    mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    [ "$mem_usage" -lt 90 ] || return 1
    
    return 0
}

# 測試 Python 環境
test_python_environment() {
    # 測試 Python3
    command -v python3 >/dev/null || return 1
    python3 --version >/dev/null || return 1
    
    # 測試 pip3
    command -v pip3 >/dev/null || return 1
    pip3 --version >/dev/null || return 1
    
    # 測試 UV（如果安裝）
    if command -v uv >/dev/null 2>&1; then
        uv --version >/dev/null || return 1
    fi
    
    return 0
}

# 測試 Git 環境
test_git_environment() {
    # 測試 Git
    command -v git >/dev/null || return 1
    git --version >/dev/null || return 1
    
    # 測試 Git 配置
    git config user.name >/dev/null 2>&1 || return 1
    git config user.email >/dev/null 2>&1 || return 1
    
    return 0
}

# 壓力測試
stress_test() {
    log_test "INFO" "開始壓力測試..."
    
    # 並行執行多個腳本
    local pids=()
    
    # 健康檢查
    if [ -f "$SCRIPT_DIR/health_check.sh" ]; then
        timeout 60 "$SCRIPT_DIR/health_check.sh" quick >/dev/null 2>&1 &
        pids+=($!)
    fi
    
    # 診斷系統
    if [ -f "$SCRIPT_DIR/diagnostic_system.sh" ]; then
        timeout 60 "$SCRIPT_DIR/diagnostic_system.sh" collect >/dev/null 2>&1 &
        pids+=($!)
    fi
    
    # 等待所有進程完成
    local failed=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            failed=$((failed + 1))
        fi
    done
    
    [ $failed -eq 0 ] || return 1
    return 0
}

# 生成測試報告
generate_test_report() {
    log_test "INFO" "生成測試報告..."
    
    local pass_rate
    if [ $TEST_TOTAL -gt 0 ]; then
        pass_rate=$(awk "BEGIN {printf \"%.1f\", $TEST_PASSED * 100 / $TEST_TOTAL}")
    else
        pass_rate="0.0"
    fi
    
    cat > "$TEST_REPORT_FILE" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Linux Setting Scripts 系統測試報告</title>
    <meta charset="utf-8">
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; line-height: 1.6; }
        .header { background: #f0f0f0; padding: 20px; border-radius: 5px; margin-bottom: 20px; }
        .summary { background: #e8f4f8; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .pass { color: green; font-weight: bold; }
        .fail { color: red; font-weight: bold; }
        .skip { color: orange; font-weight: bold; }
        .warn { color: #ff8c00; font-weight: bold; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #f2f2f2; font-weight: bold; }
        .progress-bar { width: 100%; height: 20px; background-color: #f0f0f0; border-radius: 10px; overflow: hidden; }
        .progress-fill { height: 100%; background: linear-gradient(90deg, #4CAF50 0%, #45a049 100%); transition: width 0.3s ease; }
        .footer { margin-top: 40px; padding: 20px; background: #f9f9f9; border-radius: 5px; font-size: 12px; color: #666; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🧪 Linux Setting Scripts 系統測試報告</h1>
        <p><strong>生成時間:</strong> $(date)</p>
        <p><strong>主機:</strong> $(hostname)</p>
        <p><strong>用戶:</strong> $(whoami)</p>
        <p><strong>系統:</strong> $(uname -s) $(uname -r)</p>
    </div>

    <div class="summary">
        <h2>📊 測試摘要</h2>
        <table>
            <tr><th>項目</th><th>數量</th><th>百分比</th></tr>
            <tr><td>總測試數</td><td>$TEST_TOTAL</td><td>100%</td></tr>
            <tr><td><span class="pass">通過</span></td><td>$TEST_PASSED</td><td>${pass_rate}%</td></tr>
            <tr><td><span class="fail">失敗</span></td><td>$TEST_FAILED</td><td>$(awk "BEGIN {printf \"%.1f\", $TEST_FAILED * 100 / ($TEST_TOTAL > 0 ? $TEST_TOTAL : 1)}")%</td></tr>
            <tr><td><span class="skip">跳過</span></td><td>$TEST_SKIPPED</td><td>$(awk "BEGIN {printf \"%.1f\", $TEST_SKIPPED * 100 / ($TEST_TOTAL > 0 ? $TEST_TOTAL : 1)}")%</td></tr>
        </table>
        
        <h3>通過率</h3>
        <div class="progress-bar">
            <div class="progress-fill" style="width: ${pass_rate}%;"></div>
        </div>
        <p style="text-align: center; margin-top: 10px;"><strong>${pass_rate}%</strong></p>
    </div>

    <h2>📝 詳細測試結果</h2>
    <table>
        <tr>
            <th>測試名稱</th>
            <th>狀態</th>
            <th>持續時間</th>
            <th>描述</th>
        </tr>
EOF

    # 添加測試結果
    for result in "${TEST_RESULTS[@]}"; do
        IFS=':' read -r test_name test_result duration description <<< "$result"
        
        local status_class="pass"
        local status_text="✅ 通過"
        
        case "$test_result" in
            "FAIL")
                status_class="fail"
                status_text="❌ 失敗"
                ;;
            "SKIP")
                status_class="skip"
                status_text="⏭️ 跳過"
                ;;
        esac
        
        cat >> "$TEST_REPORT_FILE" << EOF
        <tr>
            <td>$test_name</td>
            <td><span class="$status_class">$status_text</span></td>
            <td>${duration}s</td>
            <td>$description</td>
        </tr>
EOF
    done

    cat >> "$TEST_REPORT_FILE" << EOF
    </table>

    <h2>🔧 系統信息</h2>
    <table>
        <tr><th>項目</th><th>值</th></tr>
        <tr><td>操作系統</td><td>$(lsb_release -d 2>/dev/null | cut -f2 || uname -s)</td></tr>
        <tr><td>核心版本</td><td>$(uname -r)</td></tr>
        <tr><td>架構</td><td>$(uname -m)</td></tr>
        <tr><td>內存</td><td>$(free -h | awk 'NR==2{printf "%s / %s", $3, $2}')</td></tr>
        <tr><td>磁盤使用</td><td>$(df -h $HOME | awk 'NR==2{printf "%s / %s (%s)", $3, $2, $5}')</td></tr>
        <tr><td>負載平均</td><td>$(uptime | awk -F'load average:' '{print $2}')</td></tr>
    </table>

    <h2>📋 已安裝工具</h2>
    <table>
        <tr><th>工具</th><th>版本</th><th>狀態</th></tr>
EOF

    # 檢查工具版本
    local tools=("bash" "git" "curl" "python3" "pip3" "docker" "uv" "zsh" "vim")
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            local version
            case "$tool" in
                "python3") version=$($tool --version 2>&1 | cut -d' ' -f2) ;;
                "pip3") version=$($tool --version 2>&1 | cut -d' ' -f2) ;;
                *) version=$($tool --version 2>&1 | head -1 | awk '{print $NF}' 2>/dev/null || echo "已安裝") ;;
            esac
            echo "        <tr><td>$tool</td><td>$version</td><td><span class=\"pass\">✅ 已安裝</span></td></tr>" >> "$TEST_REPORT_FILE"
        else
            echo "        <tr><td>$tool</td><td>-</td><td><span class=\"skip\">❌ 未安裝</span></td></tr>" >> "$TEST_REPORT_FILE"
        fi
    done

    cat >> "$TEST_REPORT_FILE" << EOF
    </table>

    <div class="footer">
        <p>🤖 此報告由 Linux Setting Scripts 系統測試工具自動生成</p>
        <p>測試日誌位置: $TEST_LOG_FILE</p>
        <p>如有問題，請查看詳細日誌或聯繫支持團隊</p>
    </div>
</body>
</html>
EOF

    log_test "INFO" "測試報告已生成: $TEST_REPORT_FILE"
}

# 執行所有測試
run_all_tests() {
    log_test "INFO" "開始執行完整系統測試..."
    
    echo "🧪 Linux Setting Scripts 系統測試"
    echo "======================================"
    echo ""
    
    # 基礎環境測試
    echo "📋 基礎環境測試"
    run_test "basic_environment" "test_basic_environment" "測試基本命令和環境"
    run_test "common_library" "test_common_library" "測試共用函數庫"
    run_test "permissions" "test_permissions" "測試文件權限"
    run_test "system_resources" "test_system_resources" "測試系統資源"
    echo ""
    
    # 網絡和連接測試
    echo "🌐 網絡連接測試"
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        run_test "network_connectivity" "test_network_connectivity" "測試網絡連接"
    else
        skip_test "network_connectivity" "無網絡連接"
    fi
    echo ""
    
    # 工具環境測試
    echo "🛠️ 工具環境測試"
    if command -v python3 >/dev/null 2>&1; then
        run_test "python_environment" "test_python_environment" "測試 Python 環境"
    else
        skip_test "python_environment" "Python 未安裝"
    fi
    
    if command -v git >/dev/null 2>&1; then
        run_test "git_environment" "test_git_environment" "測試 Git 環境"
    else
        skip_test "git_environment" "Git 未安裝"
    fi
    echo ""
    
    # 核心功能測試
    echo "⚙️ 核心功能測試"
    run_test "config_management" "test_config_management" "測試配置管理系統"
    run_test "secure_download" "test_secure_download" "測試安全下載機制"
    run_test "main_installer" "test_main_installer" "測試主安裝腳本"
    run_test "sub_scripts" "test_sub_scripts" "測試子腳本語法"
    echo ""
    
    # 高級功能測試
    echo "🚀 高級功能測試"
    run_test "health_check" "test_health_check" "測試健康檢查系統"
    run_test "diagnostic_system" "test_diagnostic_system" "測試診斷系統"
    run_test "auto_sync" "test_auto_sync" "測試自動同步機制"
    run_test "auto_repair" "test_auto_repair" "測試自動修復系統"
    run_test "remote_sync" "test_remote_sync" "測試遠程同步系統"
    run_test "auto_recovery" "test_auto_recovery" "測試自動恢復系統"
    run_test "config_version_control" "test_config_version_control" "測試配置版本控制"
    run_test "auto_update" "test_auto_update" "測試自動更新機制"
    echo ""
    
    # 壓力測試
    echo "💪 壓力測試"
    if [ "$TEST_PARALLEL" = "true" ]; then
        run_test "stress_test" "stress_test" "並行執行壓力測試"
    else
        skip_test "stress_test" "並行測試已禁用"
    fi
    echo ""
    
    # 生成報告
    if [ "$GENERATE_REPORT" = "true" ]; then
        generate_test_report
    fi
    
    # 顯示測試摘要
    echo "📊 測試摘要"
    echo "======================================"
    echo "總測試數: $TEST_TOTAL"
    echo "通過數: $TEST_PASSED"
    echo "失敗數: $TEST_FAILED"
    echo "跳過數: $TEST_SKIPPED"
    
    if [ $TEST_TOTAL -gt 0 ]; then
        local pass_rate
        pass_rate=$(awk "BEGIN {printf \"%.1f\", $TEST_PASSED * 100 / $TEST_TOTAL}")
        echo "通過率: ${pass_rate}%"
    fi
    echo ""
    
    if [ $TEST_FAILED -eq 0 ]; then
        echo "🎉 所有測試通過！系統運行正常。"
        log_test "PASS" "系統測試完成: 所有測試通過"
        return 0
    else
        echo "⚠️  發現 $TEST_FAILED 個失敗的測試，請檢查日誌: $TEST_LOG_FILE"
        log_test "FAIL" "系統測試完成: $TEST_FAILED 個測試失敗"
        return 1
    fi
}

# 快速測試
quick_test() {
    log_test "INFO" "執行快速測試..."
    
    echo "⚡ 快速系統測試"
    echo "==================="
    echo ""
    
    # 只測試關鍵功能
    run_test "basic_environment" "test_basic_environment" "基礎環境檢查"
    run_test "common_library" "test_common_library" "共用函數庫檢查"
    run_test "main_installer" "test_main_installer" "主安裝腳本檢查"
    
    echo ""
    echo "快速測試完成: 通過 $TEST_PASSED/$TEST_TOTAL 個測試"
    
    [ $TEST_FAILED -eq 0 ]
}

# 命令行接口
case "${1:-full}" in
    "full")
        run_all_tests
        ;;
    "quick")
        quick_test
        ;;
    "basic")
        echo "🔧 基礎測試"
        echo "============"
        run_test "basic_environment" "test_basic_environment" "基礎環境"
        run_test "permissions" "test_permissions" "權限檢查"
        run_test "system_resources" "test_system_resources" "系統資源"
        echo "基礎測試完成: 通過 $TEST_PASSED/$TEST_TOTAL 個測試"
        [ $TEST_FAILED -eq 0 ]
        ;;
    "network")
        echo "🌐 網絡測試"
        echo "============"
        run_test "network_connectivity" "test_network_connectivity" "網絡連接"
        echo "網絡測試完成: 通過 $TEST_PASSED/$TEST_TOTAL 個測試"
        [ $TEST_FAILED -eq 0 ]
        ;;
    "scripts")
        echo "📜 腳本測試"
        echo "============"
        run_test "sub_scripts" "test_sub_scripts" "腳本語法檢查"
        run_test "main_installer" "test_main_installer" "主安裝腳本"
        echo "腳本測試完成: 通過 $TEST_PASSED/$TEST_TOTAL 個測試"
        [ $TEST_FAILED -eq 0 ]
        ;;
    "report")
        if [ -f "$TEST_REPORT_FILE" ]; then
            echo "最新測試報告: $TEST_REPORT_FILE"
            if command -v xdg-open >/dev/null 2>&1; then
                xdg-open "$TEST_REPORT_FILE"
            elif command -v open >/dev/null 2>&1; then
                open "$TEST_REPORT_FILE"
            fi
        else
            echo "沒有找到測試報告，請先執行完整測試"
            exit 1
        fi
        ;;
    *)
        echo "完整系統測試和驗證工具"
        echo ""
        echo "用法: $0 <command>"
        echo ""
        echo "命令:"
        echo "  full      執行完整系統測試（默認）"
        echo "  quick     執行快速測試"
        echo "  basic     執行基礎環境測試"
        echo "  network   執行網絡連接測試"
        echo "  scripts   執行腳本語法測試"
        echo "  report    顯示最新測試報告"
        echo ""
        echo "環境變數:"
        echo "  TEST_VERBOSE       詳細輸出模式"
        echo "  TEST_PARALLEL      啟用並行測試"
        echo "  TEST_TIMEOUT       測試超時時間（秒）"
        echo "  GENERATE_REPORT    生成 HTML 報告"
        echo ""
        echo "範例:"
        echo "  $0 full            # 完整測試"
        echo "  $0 quick           # 快速測試"
        echo "  TEST_VERBOSE=true $0 full  # 詳細模式"
        echo ""
        echo "測試日誌: $TEST_LOG_FILE"
        echo "測試報告: $TEST_REPORT_FILE"
        ;;
esac

log_success "########## 完整系統測試和驗證執行完成 ##########"