#!/usr/bin/env bash
#!/bin/bash

# 進階智能故障診斷系統

# 載入共用函數庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || exit 1
if [ -f "$SCRIPT_DIR/config_manager_simple.sh" ]; then
    source "$SCRIPT_DIR/config_manager_simple.sh" 2>/dev/null || true
fi

log_info "########## 智能故障診斷系統 ##########"

readonly DIAGNOSTIC_LOG="$HOME/.local/log/diagnostic_$(date +%Y%m%d_%H%M%S).log"
readonly DIAGNOSTIC_CACHE_DIR="$HOME/.cache/linux-setting/diagnostics"
readonly HEALTH_CHECK_INTERVAL=300  # 5 分鐘

# 確保目錄存在
mkdir -p "$(dirname "$DIAGNOSTIC_LOG")"
mkdir -p "$DIAGNOSTIC_CACHE_DIR"

# 診斷級別定義
readonly LEVEL_INFO=0
readonly LEVEL_WARNING=1
readonly LEVEL_ERROR=2
readonly LEVEL_CRITICAL=3

# 故障類別
readonly CATEGORY_SYSTEM="system"
readonly CATEGORY_NETWORK="network"
readonly CATEGORY_PACKAGE="package"
readonly CATEGORY_CONFIG="config"
readonly CATEGORY_PERMISSION="permission"

# 診斷記錄函數
log_diagnostic() {
    local level="$1"
    local category="$2"
    local message="$3"
    local solution="${4:-無解決方案}"
    
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    local level_text
    case "$level" in
        $LEVEL_INFO) level_text="INFO" ;;
        $LEVEL_WARNING) level_text="WARNING" ;;
        $LEVEL_ERROR) level_text="ERROR" ;;
        $LEVEL_CRITICAL) level_text="CRITICAL" ;;
        *) level_text="UNKNOWN" ;;
    esac
    
    {
        echo "[$timestamp] [$level_text] [$category] $message"
        if [ "$solution" != "無解決方案" ]; then
            echo "    解決方案: $solution"
        fi
        echo ""
    } >> "$DIAGNOSTIC_LOG"
    
    # 顯示到控制台
    case "$level" in
        $LEVEL_WARNING) log_warning "[$category] $message" ;;
        $LEVEL_ERROR) log_error "[$category] $message" ;;
        $LEVEL_CRITICAL) log_error "🚨 CRITICAL [$category] $message" ;;
        *) log_info "[$category] $message" ;;
    esac
}

# 系統健康檢查
check_system_health() {
    log_info "執行系統健康檢查..."
    
    local issues_found=0
    
    # 檢查磁盤空間
    local disk_usage
    disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 90 ]; then
        log_diagnostic $LEVEL_CRITICAL $CATEGORY_SYSTEM "磁盤空間不足: ${disk_usage}%" "清理不需要的文件或擴展磁盤空間"
        issues_found=$((issues_found + 1))
    elif [ "$disk_usage" -gt 80 ]; then
        log_diagnostic $LEVEL_WARNING $CATEGORY_SYSTEM "磁盤空間告警: ${disk_usage}%" "建議清理臨時文件"
    fi
    
    # 檢查記憶體使用
    local mem_usage
    mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [ "$mem_usage" -gt 90 ]; then
        log_diagnostic $LEVEL_ERROR $CATEGORY_SYSTEM "記憶體使用過高: ${mem_usage}%" "關閉不必要的程序或增加記憶體"
        issues_found=$((issues_found + 1))
    elif [ "$mem_usage" -gt 80 ]; then
        log_diagnostic $LEVEL_WARNING $CATEGORY_SYSTEM "記憶體使用告警: ${mem_usage}%" "監控記憶體使用情況"
    fi
    
    # 檢查系統負載
    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{ print $2 }' | awk '{ print $1 }' | sed 's/,//')
    local cpu_cores
    cpu_cores=$(nproc)
    
    if (( $(echo "$load_avg > $cpu_cores * 2" | bc -l 2>/dev/null || echo 0) )); then
        log_diagnostic $LEVEL_ERROR $CATEGORY_SYSTEM "系統負載過高: $load_avg (CPU核心: $cpu_cores)" "檢查高CPU使用的進程"
        issues_found=$((issues_found + 1))
    fi
    
    # 檢查必要服務
    check_essential_services
    
    # 檢查網絡連接
    check_network_connectivity
    
    # 檢查套件管理器
    check_package_manager_health
    
    if [ $issues_found -eq 0 ]; then
        log_diagnostic $LEVEL_INFO $CATEGORY_SYSTEM "系統健康檢查通過" "無需採取行動"
    else
        log_diagnostic $LEVEL_WARNING $CATEGORY_SYSTEM "發現 $issues_found 個系統問題" "查看詳細報告: $DIAGNOSTIC_LOG"
    fi
    
    return $issues_found
}

# 檢查必要服務
check_essential_services() {
    log_info "檢查必要服務狀態..."
    
    local services=("ssh" "systemd-resolved" "systemd-networkd")
    
    for service in "${services[@]}"; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            log_diagnostic $LEVEL_INFO $CATEGORY_SYSTEM "服務 $service 運行正常"
        else
            if systemctl list-unit-files | grep -q "^$service"; then
                log_diagnostic $LEVEL_WARNING $CATEGORY_SYSTEM "服務 $service 未運行" "systemctl start $service"
            fi
        fi
    done
}

# 網絡連接檢查
check_network_connectivity() {
    log_info "檢查網絡連接..."
    
    # 檢查本地網絡接口
    if ! ip link show | grep -q "state UP"; then
        log_diagnostic $LEVEL_CRITICAL $CATEGORY_NETWORK "沒有活躍的網絡接口" "檢查網絡配置"
        return 1
    fi
    
    # 檢查 DNS 解析
    if ! nslookup google.com >/dev/null 2>&1; then
        log_diagnostic $LEVEL_ERROR $CATEGORY_NETWORK "DNS 解析失敗" "檢查 /etc/resolv.conf 或網絡設置"
        return 1
    fi
    
    # 檢查外部連接
    if ! ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        log_diagnostic $LEVEL_ERROR $CATEGORY_NETWORK "無法連接到外部網絡" "檢查防火牆和路由設置"
        return 1
    fi
    
    # 檢查 HTTPS 連接
    if ! curl -s --max-time 10 https://google.com >/dev/null; then
        log_diagnostic $LEVEL_WARNING $CATEGORY_NETWORK "HTTPS 連接問題" "檢查 SSL/TLS 設置"
    fi
    
    log_diagnostic $LEVEL_INFO $CATEGORY_NETWORK "網絡連接正常"
    return 0
}

# 套件管理器健康檢查
check_package_manager_health() {
    log_info "檢查套件管理器狀態..."
    
    # 檢查 APT 鎖定
    if lsof /var/lib/dpkg/lock >/dev/null 2>&1 || lsof /var/lib/apt/lists/lock >/dev/null 2>&1; then
        log_diagnostic $LEVEL_WARNING $CATEGORY_PACKAGE "APT 被鎖定" "等待其他安裝程序完成或重啟系統"
        return 1
    fi
    
    # 檢查破損的套件
    local broken_packages
    broken_packages=$(dpkg -l | grep '^..r' | wc -l)
    if [ "$broken_packages" -gt 0 ]; then
        log_diagnostic $LEVEL_ERROR $CATEGORY_PACKAGE "發現 $broken_packages 個破損套件" "sudo apt --fix-broken install"
    fi
    
    # 檢查 APT 源的可用性
    if ! apt update -q 2>/dev/null; then
        log_diagnostic $LEVEL_WARNING $CATEGORY_PACKAGE "APT 源更新失敗" "檢查網絡連接和 APT 源配置"
    fi
    
    log_diagnostic $LEVEL_INFO $CATEGORY_PACKAGE "套件管理器狀態良好"
    return 0
}

# 深度系統診斷
comprehensive_system_scan() {
    log_info "開始全面系統掃描..."
    
    {
        echo "========== 全面系統診斷報告 =========="
        echo "生成時間: $(date)"
        echo "主機名稱: $(hostname)"
        echo "用戶: $(whoami)"
        echo ""
        
        echo "=== 系統基本信息 ==="
        if [ -f /etc/os-release ]; then
            grep PRETTY_NAME /etc/os-release | cut -d'=' -f2 | tr -d '"'
        fi
        echo "核心版本: $(uname -r)"
        echo "架構: $(uname -m)"
        echo "運行時間: $(uptime -p 2>/dev/null || uptime)"
        echo ""
        
        echo "=== 硬體資源 ==="
        echo "CPU:"
        echo "  核心數: $(nproc)"
        echo "  負載平均: $(uptime | awk -F'load average:' '{print $2}')"
        if [ -f /proc/cpuinfo ]; then
            echo "  型號: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d':' -f2 | sed 's/^[ \t]*//')"
        fi
        echo ""
        
        echo "記憶體:"
        free -h
        echo ""
        
        echo "磁盤空間:"
        df -h
        echo ""
        
        echo "=== 網絡狀態 ==="
        echo "網絡接口:"
        ip addr show | grep -E '^[0-9]+:|inet '
        echo ""
        
        echo "路由表:"
        ip route show
        echo ""
        
        echo "=== 重要服務狀態 ==="
        for service in ssh systemd-resolved systemd-networkd systemd-timesyncd; do
            if systemctl list-unit-files | grep -q "^$service"; then
                status=$(systemctl is-active "$service" 2>/dev/null)
                echo "$service: $status"
            fi
        done
        echo ""
        
        echo "=== 安裝的重要工具 ==="
        for tool in python3 pip3 uv git curl wget docker zsh; do
            if command -v "$tool" >/dev/null 2>&1; then
                version=$($tool --version 2>/dev/null | head -1 || echo "已安裝")
                echo "$tool: $version"
            else
                echo "$tool: 未安裝"
            fi
        done
        echo ""
        
        echo "=== 最近日誌錯誤 (最近1小時) ==="
        if command -v journalctl >/dev/null 2>&1; then
            journalctl --since "1 hour ago" --priority=err --no-pager --lines=10 2>/dev/null || echo "無法讀取系統日誌"
        else
            echo "journalctl 不可用"
        fi
        
    } | tee "$DIAGNOSTIC_CACHE_DIR/system_scan_$(date +%Y%m%d_%H%M%S).log"
    
    log_success "全面掃描完成，報告保存到: $DIAGNOSTIC_CACHE_DIR/"
}

# 收集系統信息
collect_system_info() {
    local diagnostic_log="$DIAGNOSTIC_CACHE_DIR/system_info_$(date +%Y%m%d_%H%M%S).log"
    
    log_info "收集系統診斷信息..."
    
    {
        echo "--- 重要工具狀態 ---"
        for tool in git curl wget zsh docker; do
            if command -v "$tool" >/dev/null; then
                echo "✓ $tool: $(command -v "$tool")"
            else
                echo "✗ $tool: 未安裝"
            fi
        done
        echo ""
        
        echo "--- 權限檢查 ---"
        sudo -n true 2>/dev/null && echo "✓ sudo 權限可用" || echo "✗ sudo 權限需要密碼"
        [ -w "$HOME" ] && echo "✓ HOME 目錄可寫" || echo "✗ HOME 目錄不可寫"
        [ -w "/tmp" ] && echo "✓ /tmp 可寫" || echo "✗ /tmp 不可寫"
        echo ""
        
        echo "--- 最近錯誤 ---"
        if [ -f "$HOME/.local/log/linux-setting/install.log" ]; then
            echo "最近的安裝日誌錯誤:"
            grep -i "error\|fail" "$HOME/.local/log/linux-setting/install.log" 2>/dev/null | tail -5 || echo "無錯誤記錄"
        else
            echo "無安裝日誌"
        fi
        
    } > "$diagnostic_log"
    
    echo "$diagnostic_log"
}

# 分析日誌中的錯誤
analyze_log_errors() {
    local log_file="$1"
    
    if [ ! -f "$log_file" ]; then
        log_warning "日誌文件不存在: $log_file"
        return 1
    fi
    
    log_info "分析日誌錯誤: $log_file"
    
    # 提取錯誤行
    local errors
    errors=$(grep -i "error\|fail\|exception" "$log_file" | tail -10)
    
    if [ -z "$errors" ]; then
        log_success "未發現錯誤"
        return 0
    fi
    
    echo "發現的錯誤:"
    echo "$errors"
    echo ""
    
    # 匹配已知問題
    log_info "搜索解決方案..."
    echo "$errors" | while read -r error_line; do
        for pattern in "${!KNOWN_ISSUES[@]}"; do
            if [[ "$error_line" =~ $pattern ]]; then
                echo "🔍 發現已知問題: $pattern"
                echo "💡 建議解決方案: ${KNOWN_ISSUES[$pattern]}"
                echo ""
            fi
        done
    done
}

# 運行自動修復
auto_fix() {
    local issue="$1"
    
    log_info "嘗試自動修復: $issue"
    
    case "$issue" in
        "docker-permission")
            if groups "$USER" | grep -q docker; then
                log_info "用戶已在 docker 群組中"
            else
                log_info "將用戶添加到 docker 群組"
                sudo usermod -aG docker "$USER"
                log_warning "請重新登入以套用群組變更"
            fi
            ;;
        "missing-package")
            local package="$2"
            if [ -n "$package" ]; then
                log_info "嘗試安裝缺失的包: $package"
                sudo apt update && sudo apt install -y "$package"
            fi
            ;;
        "network-issue")
            log_info "嘗試修復網路問題"
            # 重新啟動網路管理服務
            sudo systemctl restart systemd-resolved 2>/dev/null || true
            ;;
        *)
            log_warning "無法自動修復此問題: $issue"
            ;;
    esac
}

# 生成修復建議
generate_fix_suggestions() {
    local diagnostic_log="$1"
    
    log_info "生成修復建議..."
    
    {
        echo "========== 修復建議 =========="
        echo ""
        
        # 檢查常見問題
        if grep -q "docker.*Permission denied" "$diagnostic_log"; then
            echo "🐳 Docker 權限問題:"
            echo "   sudo usermod -aG docker \$USER"
            echo "   newgrp docker  # 或重新登入"
            echo ""
        fi
        
        if grep -q "command not found" "$diagnostic_log"; then
            echo "📦 缺失命令:"
            echo "   sudo apt update"
            echo "   sudo apt install -y <缺失的包>"
            echo ""
        fi
        
        if grep -q "Network is unreachable" "$diagnostic_log"; then
            echo "🌐 網路問題:"
            echo "   檢查網路連接"
            echo "   ping google.com"
            echo "   sudo systemctl restart systemd-resolved"
            echo ""
        fi
        
        if grep -q "Python3 未安裝" "$diagnostic_log"; then
            echo "🐍 Python 環境:"
            echo "   sudo apt install -y python3 python3-pip python3-venv"
            echo ""
        fi
        
        if grep -q "sudo 權限需要密碼" "$diagnostic_log"; then
            echo "🔐 權限設定:"
            echo "   設定 sudo 免密碼（可選）:"
            echo "   echo '\$USER ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/\$USER"
            echo ""
        fi
        
        echo "💡 通用修復步驟:"
        echo "1. 重新執行安裝腳本: ./install.sh --verbose"
        echo "2. 檢查系統更新: sudo apt update && sudo apt upgrade"
        echo "3. 重新啟動終端或重新登入"
        echo "4. 如問題持續，請提交 GitHub Issue 並附上診斷報告"
        
    } > "${diagnostic_log%.log}_suggestions.txt"
    
    echo "${diagnostic_log%.log}_suggestions.txt"
}

# 互動式診斷
interactive_diagnosis() {
    log_info "啟動互動式診斷..."
    
    echo ""
    echo "🔍 Linux Setting Scripts 診斷系統"
    echo ""
    
    # 收集基本信息
    diagnostic_log=$(collect_system_info)
    echo "✓ 系統信息已收集: $diagnostic_log"
    
    # 檢查是否有最近的錯誤日誌
    local recent_log
    recent_log=$(find "$HOME/.local/log" -name "*.log" -mtime -1 2>/dev/null | head -1)
    
    if [ -n "$recent_log" ]; then
        echo "✓ 發現最近的日誌: $recent_log"
        analyze_log_errors "$recent_log"
    fi
    
    # 生成建議
    suggestions_file=$(generate_fix_suggestions "$diagnostic_log")
    echo "✓ 修復建議已生成: $suggestions_file"
    
    echo ""
    echo "是否查看詳細診斷報告？(y/N)"
    read -r response
    if [[ "$response" =~ ^[Yy] ]]; then
        cat "$diagnostic_log"
    fi
    
    echo ""
    echo "是否查看修復建議？(y/N)"
    read -r response
    if [[ "$response" =~ ^[Yy] ]]; then
        cat "$suggestions_file"
    fi
}

# 命令行接口
case "${1:-help}" in
    "collect")
        collect_system_info
        ;;
    "analyze")
        if [ -z "$2" ]; then
            log_error "請指定要分析的日誌文件"
            exit 1
        fi
        analyze_log_errors "$2"
        ;;
    "fix")
        auto_fix "$2" "$3"
        ;;
    "suggest")
        if [ -z "$2" ]; then
            diagnostic_log=$(collect_system_info)
        else
            diagnostic_log="$2"
        fi
        generate_fix_suggestions "$diagnostic_log"
        ;;
    "interactive"|"")
        interactive_diagnosis
        ;;
    *)
        echo "智能故障診斷系統"
        echo ""
        echo "用法: $0 <command> [選項]"
        echo ""
        echo "命令:"
        echo "  collect              收集系統診斷信息"
        echo "  analyze <log_file>   分析日誌錯誤"
        echo "  fix <issue> [param]  自動修復問題"
        echo "  suggest [diag_file]  生成修復建議"
        echo "  interactive          互動式診斷"
        echo ""
        echo "自動修復選項:"
        echo "  docker-permission    修復 Docker 權限問題"
        echo "  missing-package      安裝缺失的包"
        echo "  network-issue        修復網路問題"
        ;;
esac