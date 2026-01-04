#!/usr/bin/env bash
#!/bin/bash

# 進階系統健康檢查與監控系統

# 載入共用函數庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || {
    echo "錯誤: 無法載入共用函數庫"
    exit 1
}

# 載入配置管理
if [ -f "$SCRIPT_DIR/config_manager_simple.sh" ]; then
    source "$SCRIPT_DIR/config_manager_simple.sh" 2>/dev/null || true
fi

log_info "########## 進階系統健康檢查 ##########"

# 健康檢查配置
readonly HEALTH_CHECK_LOG="$HOME/.local/log/health_check.log"
readonly HEALTH_CHECK_CACHE="$HOME/.cache/linux-setting/health"
readonly ALERT_THRESHOLD_CPU=80
readonly ALERT_THRESHOLD_MEMORY=85
readonly ALERT_THRESHOLD_DISK=90

# 確保目錄存在
mkdir -p "$(dirname "$HEALTH_CHECK_LOG")"
mkdir -p "$HEALTH_CHECK_CACHE"

# 檢查結果計數
total_checks=0
passed_checks=0
failed_checks=0
warning_checks=0

# 健康檢查狀態
HEALTH_STATUS_OK=0
HEALTH_STATUS_WARNING=1
HEALTH_STATUS_CRITICAL=2

# 記錄健康檢查結果
log_health_result() {
    local status="$1"
    local category="$2" 
    local message="$3"
    local details="${4:-}"
    
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    local status_text
    case "$status" in
        $HEALTH_STATUS_OK) status_text="OK" ;;
        $HEALTH_STATUS_WARNING) status_text="WARNING" ;;
        $HEALTH_STATUS_CRITICAL) status_text="CRITICAL" ;;
        *) status_text="UNKNOWN" ;;
    esac
    
    {
        echo "[$timestamp] [$status_text] [$category] $message"
        if [ -n "$details" ]; then
            echo "    詳情: $details"
        fi
    } >> "$HEALTH_CHECK_LOG"
    
    # 更新檢查計數
    total_checks=$((total_checks + 1))
    case "$status" in
        $HEALTH_STATUS_OK) passed_checks=$((passed_checks + 1)) ;;
        $HEALTH_STATUS_WARNING) warning_checks=$((warning_checks + 1)) ;;
        $HEALTH_STATUS_CRITICAL) failed_checks=$((failed_checks + 1)) ;;
    esac
}

# 系統資源健康檢查
check_system_resources() {
    log_info "檢查系統資源使用情況..."
    
    # CPU 使用率檢查
    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' 2>/dev/null || echo "0")
    cpu_usage=${cpu_usage%.*}  # 去除小數點
    
    if [ "$cpu_usage" -gt "$ALERT_THRESHOLD_CPU" ]; then
        log_health_result $HEALTH_STATUS_CRITICAL "SYSTEM" "CPU 使用率過高: ${cpu_usage}%" "建議檢查高CPU使用的進程"
    elif [ "$cpu_usage" -gt 60 ]; then
        log_health_result $HEALTH_STATUS_WARNING "SYSTEM" "CPU 使用率偏高: ${cpu_usage}%" "正常範圍內，但需要監控"
    else
        log_health_result $HEALTH_STATUS_OK "SYSTEM" "CPU 使用率正常: ${cpu_usage}%"
    fi
    
    # 記憶體使用檢查
    local mem_info
    mem_info=$(free | awk 'NR==2{printf "%.0f %.0f", $3*100/$2, ($2-$3-$6)*100/$2}')
    local mem_used_percent=${mem_info%% *}
    local mem_available_percent=${mem_info##* }
    
    if [ "$mem_used_percent" -gt "$ALERT_THRESHOLD_MEMORY" ]; then
        log_health_result $HEALTH_STATUS_CRITICAL "MEMORY" "記憶體使用率過高: ${mem_used_percent}%" "可用記憶體: ${mem_available_percent}%"
    elif [ "$mem_used_percent" -gt 70 ]; then
        log_health_result $HEALTH_STATUS_WARNING "MEMORY" "記憶體使用率偏高: ${mem_used_percent}%" "可用記憶體: ${mem_available_percent}%"
    else
        log_health_result $HEALTH_STATUS_OK "MEMORY" "記憶體使用率正常: ${mem_used_percent}%" "可用記憶體: ${mem_available_percent}%"
    fi
    
    # 磁盤空間檢查
    while read -r filesystem size used available use_percent mount; do
        use_num=${use_percent%?}  # 移除 % 符號
        
        if [ "$use_num" -gt "$ALERT_THRESHOLD_DISK" ]; then
            log_health_result $HEALTH_STATUS_CRITICAL "DISK" "磁盤空間不足: $mount ($use_percent)" "可用空間: $available"
        elif [ "$use_num" -gt 80 ]; then
            log_health_result $HEALTH_STATUS_WARNING "DISK" "磁盤空間告警: $mount ($use_percent)" "可用空間: $available"
        else
            log_health_result $HEALTH_STATUS_OK "DISK" "磁盤空間正常: $mount ($use_percent)" "可用空間: $available"
        fi
    done < <(df -h | grep -vE '^Filesystem|tmpfs|cdrom' | awk '{print $1 " " $2 " " $3 " " $4 " " $5 " " $6}')
}

# 網絡健康檢查
check_network_health() {
    log_info "檢查網絡健康狀態..."
    
    # 檢查網絡接口
    local active_interfaces
    active_interfaces=$(ip link show up | grep -c "state UP" || echo 0)
    
    if [ "$active_interfaces" -eq 0 ]; then
        log_health_result $HEALTH_STATUS_CRITICAL "NETWORK" "沒有活躍的網絡接口" "檢查網絡配置"
    else
        log_health_result $HEALTH_STATUS_OK "NETWORK" "網絡接口正常" "$active_interfaces 個活躍接口"
    fi
    
    # DNS 解析測試
    if nslookup google.com >/dev/null 2>&1; then
        log_health_result $HEALTH_STATUS_OK "NETWORK" "DNS 解析正常"
    else
        log_health_result $HEALTH_STATUS_CRITICAL "NETWORK" "DNS 解析失敗" "檢查 DNS 設置"
    fi
    
    # 網絡延遲測試
    local ping_time
    ping_time=$(ping -c 1 -W 5 8.8.8.8 2>/dev/null | grep "time=" | awk -F"time=" '{print $2}' | awk '{print $1}' | cut -d'=' -f1)
    
    if [ -n "$ping_time" ]; then
        local ping_ms
        ping_ms=${ping_time%.*}  # 去除小數點
        
        if [ "$ping_ms" -gt 200 ]; then
            log_health_result $HEALTH_STATUS_WARNING "NETWORK" "網絡延遲較高: ${ping_time}ms" "可能影響網絡性能"
        else
            log_health_result $HEALTH_STATUS_OK "NETWORK" "網絡延遲正常: ${ping_time}ms"
        fi
    else
        log_health_result $HEALTH_STATUS_CRITICAL "NETWORK" "無法連接外部網絡" "檢查網絡連接"
    fi
}

# 服務健康檢查
check_services_health() {
    log_info "檢查系統服務狀態..."
    
    local critical_services=("systemd-resolved" "systemd-networkd")
    local optional_services=("ssh" "docker" "systemd-timesyncd")
    
    # 檢查關鍵服務
    for service in "${critical_services[@]}"; do
        if systemctl list-unit-files | grep -q "^$service"; then
            if systemctl is-active "$service" >/dev/null 2>&1; then
                log_health_result $HEALTH_STATUS_OK "SERVICE" "關鍵服務 $service 運行正常"
            else
                log_health_result $HEALTH_STATUS_CRITICAL "SERVICE" "關鍵服務 $service 未運行" "systemctl start $service"
            fi
        fi
    done
    
    # 檢查可選服務
    for service in "${optional_services[@]}"; do
        if systemctl list-unit-files | grep -q "^$service"; then
            if systemctl is-active "$service" >/dev/null 2>&1; then
                log_health_result $HEALTH_STATUS_OK "SERVICE" "可選服務 $service 運行正常"
            else
                log_health_result $HEALTH_STATUS_WARNING "SERVICE" "可選服務 $service 未運行" "如需要，可執行: systemctl start $service"
            fi
        fi
    done
}

# 工具可用性檢查
check_tools_availability() {
    log_info "檢查重要工具可用性..."
    
    local essential_tools=("python3" "pip3" "git" "curl" "wget")
    local development_tools=("uv" "docker" "zsh" "node" "npm")
    
    # 檢查必要工具
    for tool in "${essential_tools[@]}"; do
        if check_command "$tool"; then
            local version
            case "$tool" in
                "python3") version=$(python3 --version 2>/dev/null | cut -d' ' -f2) ;;
                "pip3") version=$(pip3 --version 2>/dev/null | cut -d' ' -f2) ;;
                "git") version=$(git --version 2>/dev/null | cut -d' ' -f3) ;;
                *) version=$($tool --version 2>/dev/null | head -1 | awk '{print $NF}' || echo "已安裝") ;;
            esac
            log_health_result $HEALTH_STATUS_OK "TOOLS" "必要工具 $tool 可用" "版本: $version"
        else
            log_health_result $HEALTH_STATUS_CRITICAL "TOOLS" "必要工具 $tool 不可用" "sudo apt install $tool"
        fi
    done
    
    # 檢查開發工具
    for tool in "${development_tools[@]}"; do
        if check_command "$tool"; then
            local version
            case "$tool" in
                "uv") version=$(uv --version 2>/dev/null | cut -d' ' -f2) ;;
                "docker") version=$(docker --version 2>/dev/null | cut -d' ' -f3 | sed 's/,//') ;;
                "node") version=$(node --version 2>/dev/null) ;;
                "npm") version=$(npm --version 2>/dev/null) ;;
                *) version=$($tool --version 2>/dev/null | head -1 | awk '{print $NF}' || echo "已安裝") ;;
            esac
            log_health_result $HEALTH_STATUS_OK "TOOLS" "開發工具 $tool 可用" "版本: $version"
        else
            log_health_result $HEALTH_STATUS_WARNING "TOOLS" "開發工具 $tool 不可用" "可選安裝"
        fi
    done
}

# 配置文件健康檢查
check_configuration_health() {
    log_info "檢查配置文件健康狀態..."
    
    # 檢查重要配置文件
    local config_files=(
        "/etc/resolv.conf:DNS配置"
        "/etc/hosts:主機配置" 
        "$HOME/.bashrc:Bash配置"
        "$HOME/.zshrc:Zsh配置"
        "$HOME/.gitconfig:Git配置"
    )
    
    for config_entry in "${config_files[@]}"; do
        local config_file="${config_entry%:*}"
        local description="${config_entry#*:}"
        
        if [ -f "$config_file" ]; then
            if [ -r "$config_file" ]; then
                log_health_result $HEALTH_STATUS_OK "CONFIG" "$description 存在且可讀" "$config_file"
            else
                log_health_result $HEALTH_STATUS_WARNING "CONFIG" "$description 存在但不可讀" "$config_file"
            fi
        else
            log_health_result $HEALTH_STATUS_WARNING "CONFIG" "$description 不存在" "$config_file"
        fi
    done
    
    # 檢查 SSH 配置
    if [ -f "$HOME/.ssh/config" ]; then
        log_health_result $HEALTH_STATUS_OK "CONFIG" "SSH 配置存在" "$HOME/.ssh/config"
    fi
    
    # 檢查系統配置管理
    if get_config "mirror_mode" >/dev/null 2>&1; then
        local mirror_mode
        mirror_mode=$(get_config "mirror_mode" "auto")
        log_health_result $HEALTH_STATUS_OK "CONFIG" "配置管理系統可用" "鏡像模式: $mirror_mode"
    else
        log_health_result $HEALTH_STATUS_WARNING "CONFIG" "配置管理系統不可用" "執行配置初始化"
    fi
}
        
# 全面健康檢查
run_comprehensive_health_check() {
    log_info "開始全面健康檢查..."
    
    local start_time
    start_time=$(date +%s)
    
    # 重置計數器
    total_checks=0
    passed_checks=0
    failed_checks=0
    warning_checks=0
    
    # 執行各項檢查
    check_system_resources
    check_network_health
    check_services_health
    check_tools_availability
    check_configuration_health
    
    # 生成健康檢查報告
    generate_health_report
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_success "健康檢查完成，耗時 ${duration} 秒"
    
    # 返回健康狀態
    if [ $failed_checks -gt 0 ]; then
        return 2  # 嚴重問題
    elif [ $warning_checks -gt 0 ]; then
        return 1  # 警告
    else
        return 0  # 正常
    fi
}

# 生成健康檢查報告
generate_health_report() {
    local report_file="$HEALTH_CHECK_CACHE/health_report_$(date +%Y%m%d_%H%M%S).html"
    
    {
        cat << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>系統健康檢查報告</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f0f0f0; padding: 10px; border-radius: 5px; }
        .ok { color: green; }
        .warning { color: orange; }
        .critical { color: red; }
        .summary { background: #e8f4f8; padding: 15px; border-radius: 5px; margin: 20px 0; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
EOF
        
        echo "<div class='header'>"
        echo "<h1>系統健康檢查報告</h1>"
        echo "<p>生成時間: $(date)</p>"
        echo "<p>主機: $(hostname)</p>"
        echo "</div>"
        
        echo "<div class='summary'>"
        echo "<h2>檢查摘要</h2>"
        echo "<table>"
        echo "<tr><th>項目</th><th>數量</th><th>狀態</th></tr>"
        echo "<tr><td>總檢查項目</td><td>$total_checks</td><td>-</td></tr>"
        echo "<tr><td>通過檢查</td><td>$passed_checks</td><td><span class='ok'>正常</span></td></tr>"
        echo "<tr><td>警告項目</td><td>$warning_checks</td><td><span class='warning'>警告</span></td></tr>"
        echo "<tr><td>失敗項目</td><td>$failed_checks</td><td><span class='critical'>嚴重</span></td></tr>"
        echo "</table>"
        echo "</div>"
        
        echo "<h2>詳細檢查結果</h2>"
        
        if [ -f "$HEALTH_CHECK_LOG" ]; then
            echo "<pre style='background: #f5f5f5; padding: 10px; overflow-x: auto;'>"
            tail -100 "$HEALTH_CHECK_LOG"
            echo "</pre>"
        fi
        
        echo "</body></html>"
        
    } > "$report_file"
    
    log_success "健康檢查報告已生成: $report_file"
}

# 監控模式 - 持續健康檢查
start_monitoring_mode() {
    local interval="${1:-300}"  # 預設5分鐘
    
    log_info "啟動監控模式，檢查間隔: ${interval} 秒"
    
    while true; do
        log_info "執行定期健康檢查..."
        
        # 只檢查關鍵項目以減少系統負載
        check_system_resources
        check_network_health
        
        # 檢查是否有嚴重問題
        if [ $failed_checks -gt 0 ]; then
            log_error "發現 $failed_checks 個嚴重問題，詳情請查看: $HEALTH_CHECK_LOG"
        fi
        
        # 保存監控狀態
        echo "$(date '+%Y-%m-%d %H:%M:%S'): OK=$passed_checks, WARNING=$warning_checks, CRITICAL=$failed_checks" >> "$HEALTH_CHECK_CACHE/monitoring.log"
        
        sleep "$interval"
        
        # 重置計數器
        total_checks=0
        passed_checks=0
        failed_checks=0
        warning_checks=0
    done
}

# 快速健康檢查
quick_health_check() {
    log_info "執行快速健康檢查..."
    
    # 重置計數器
    total_checks=0
    passed_checks=0
    failed_checks=0
    warning_checks=0
    
    # 只檢查關鍵項目
    check_system_resources
    check_network_health
    
    # 顯示簡要結果
    local health_score=$((passed_checks * 100 / total_checks))
    
    echo ""
    log_info "=== 快速健康檢查結果 ==="
    echo "🏥 健康分數: ${health_score}%"
    echo "✅ 通過項目: $passed_checks"
    echo "⚠️  警告項目: $warning_checks" 
    echo "❌ 失敗項目: $failed_checks"
    
    if [ $failed_checks -eq 0 ] && [ $warning_checks -eq 0 ]; then
        echo "🎉 系統健康狀況良好！"
        return 0
    elif [ $failed_checks -eq 0 ]; then
        echo "⚠️  系統基本正常，但有一些警告項目"
        return 1
    else
        echo "🚨 系統存在嚴重問題，需要立即處理"
        return 2
    fi
}

# 命令行接口
case "${1:-help}" in
    "quick")
        quick_health_check
        ;;
    "full")
        run_comprehensive_health_check
        ;;
    "monitor")
        start_monitoring_mode "${2:-300}"
        ;;
    "resources")
        check_system_resources
        ;;
    "network")
        check_network_health
        ;;
    "services")
        check_services_health
        ;;
    "tools")
        check_tools_availability
        ;;
    "config")
        check_configuration_health
        ;;
    "report")
        generate_health_report
        ;;
    *)
        echo "進階系統健康檢查工具"
        echo ""
        echo "用法: $0 <command> [選項]"
        echo ""
        echo "命令:"
        echo "  quick             快速健康檢查"
        echo "  full              全面健康檢查"
        echo "  monitor [間隔]    監控模式（預設5分鐘）"
        echo "  resources         檢查系統資源"
        echo "  network           檢查網絡狀態"
        echo "  services          檢查服務狀態"
        echo "  tools             檢查工具可用性"
        echo "  config            檢查配置文件"
        echo "  report            生成HTML報告"
        echo ""
        echo "範例:"
        echo "  $0 quick          # 快速檢查"
        echo "  $0 full           # 全面檢查"
        echo "  $0 monitor 600    # 10分鐘間隔監控"
        echo ""
        echo "日誌文件: $HEALTH_CHECK_LOG"
        ;;
esac

log_success "########## 健康檢查執行完成 ##########"
