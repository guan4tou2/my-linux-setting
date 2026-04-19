#!/usr/bin/env bash
#!/bin/bash

# 系統自動恢復功能 - 自動檢測和恢復系統狀態

# 載入共用函數庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || exit 1
if [ -f "$SCRIPT_DIR/config_manager_simple.sh" ]; then
    source "$SCRIPT_DIR/config_manager_simple.sh" 2>/dev/null || true
fi

log_info "########## 系統自動恢復功能 ##########"

readonly RECOVERY_LOG_FILE="$HOME/.local/log/linux-setting/recovery_$(date +%Y%m%d_%H%M%S).log"
readonly RECOVERY_CACHE_DIR="$HOME/.cache/linux-setting/recovery"
readonly RECOVERY_CONFIG_FILE="$HOME/.config/linux-setting/recovery.conf"
readonly SYSTEM_SNAPSHOT_DIR="$RECOVERY_CACHE_DIR/snapshots"
readonly RECOVERY_LOCK_FILE="$RECOVERY_CACHE_DIR/recovery.lock"

# 確保目錄存在
mkdir -p "$RECOVERY_CACHE_DIR"
mkdir -p "$SYSTEM_SNAPSHOT_DIR"
mkdir -p "$(dirname "$RECOVERY_LOG_FILE")"
mkdir -p "$(dirname "$RECOVERY_CONFIG_FILE")"

# 恢復配置
RECOVERY_ENABLED="${RECOVERY_ENABLED:-true}"
RECOVERY_AUTO_MODE="${RECOVERY_AUTO_MODE:-true}"
RECOVERY_BACKUP_ENABLED="${RECOVERY_BACKUP_ENABLED:-true}"
RECOVERY_MAX_SNAPSHOTS="${RECOVERY_MAX_SNAPSHOTS:-5}"
RECOVERY_CHECK_INTERVAL="${RECOVERY_CHECK_INTERVAL:-300}"  # 5分鐘
RECOVERY_NOTIFY_ENABLED="${RECOVERY_NOTIFY_ENABLED:-true}"

# 恢復級別
readonly RECOVERY_LEVEL_INFO=0
readonly RECOVERY_LEVEL_WARNING=1
readonly RECOVERY_LEVEL_ERROR=2
readonly RECOVERY_LEVEL_CRITICAL=3

# 系統組件狀態
declare -A SYSTEM_COMPONENTS
declare -A RECOVERY_ACTIONS

# 初始化系統組件監控
init_system_components() {
    # 核心系統服務
    SYSTEM_COMPONENTS["systemd"]="systemctl is-system-running"
    SYSTEM_COMPONENTS["network"]="ping -c 1 -W 5 8.8.8.8"
    SYSTEM_COMPONENTS["dns"]="nslookup google.com"
    SYSTEM_COMPONENTS["filesystem"]="df /"
    
    # 重要服務
    SYSTEM_COMPONENTS["ssh"]="systemctl is-active ssh"
    SYSTEM_COMPONENTS["docker"]="systemctl is-active docker"
    
    # 應用程序
    SYSTEM_COMPONENTS["python"]="python3 --version"
    SYSTEM_COMPONENTS["git"]="git --version"
    SYSTEM_COMPONENTS["curl"]="curl --version"
    
    # 配置文件
    SYSTEM_COMPONENTS["bashrc"]="test -f $HOME/.bashrc"
    SYSTEM_COMPONENTS["gitconfig"]="test -f $HOME/.gitconfig"
    SYSTEM_COMPONENTS["linux_setting"]="test -d $HOME/.config/linux-setting"
    
    log_recovery $RECOVERY_LEVEL_INFO "系統組件初始化完成: ${#SYSTEM_COMPONENTS[@]} 個組件"
}

# 初始化恢復動作
init_recovery_actions() {
    # 網絡恢復
    RECOVERY_ACTIONS["network"]="recover_network"
    RECOVERY_ACTIONS["dns"]="recover_dns"
    
    # 服務恢復
    RECOVERY_ACTIONS["ssh"]="recover_ssh_service"
    RECOVERY_ACTIONS["docker"]="recover_docker_service"
    
    # 應用程序恢復
    RECOVERY_ACTIONS["python"]="recover_python"
    RECOVERY_ACTIONS["git"]="recover_git"
    RECOVERY_ACTIONS["curl"]="recover_curl"
    
    # 配置文件恢復
    RECOVERY_ACTIONS["bashrc"]="recover_bashrc"
    RECOVERY_ACTIONS["gitconfig"]="recover_gitconfig"
    RECOVERY_ACTIONS["linux_setting"]="recover_linux_setting_config"
    
    log_recovery $RECOVERY_LEVEL_INFO "恢復動作初始化完成: ${#RECOVERY_ACTIONS[@]} 個動作"
}

# 記錄恢復日誌
log_recovery() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    local level_text
    case "$level" in
        $RECOVERY_LEVEL_INFO) level_text="INFO" ;;
        $RECOVERY_LEVEL_WARNING) level_text="WARN" ;;
        $RECOVERY_LEVEL_ERROR) level_text="ERROR" ;;
        $RECOVERY_LEVEL_CRITICAL) level_text="CRITICAL" ;;
        *) level_text="UNKNOWN" ;;
    esac
    
    echo "[$timestamp] [$level_text] $message" >> "$RECOVERY_LOG_FILE"
    
    case "$level" in
        $RECOVERY_LEVEL_WARNING) log_warning "$message" ;;
        $RECOVERY_LEVEL_ERROR) log_error "$message" ;;
        $RECOVERY_LEVEL_CRITICAL) log_error "🚨 CRITICAL: $message" ;;
        *) log_info "$message" ;;
    esac
}

# 檢查恢復鎖
check_recovery_lock() {
    if [ -f "$RECOVERY_LOCK_FILE" ]; then
        local lock_pid
        lock_pid=$(cat "$RECOVERY_LOCK_FILE")
        if kill -0 "$lock_pid" 2>/dev/null; then
            log_recovery $RECOVERY_LEVEL_WARNING "恢復正在進行中 (PID: $lock_pid)"
            return 1
        else
            log_recovery $RECOVERY_LEVEL_WARNING "發現僵屍鎖文件，正在清理..."
            rm -f "$RECOVERY_LOCK_FILE"
        fi
    fi
    return 0
}

# 創建恢復鎖
create_recovery_lock() {
    echo $$ > "$RECOVERY_LOCK_FILE"
}

# 移除恢復鎖
remove_recovery_lock() {
    rm -f "$RECOVERY_LOCK_FILE"
}

# 創建系統快照
create_system_snapshot() {
    local snapshot_name="${1:-auto_$(date +%Y%m%d_%H%M%S)}"
    local snapshot_dir="$SYSTEM_SNAPSHOT_DIR/$snapshot_name"
    
    log_recovery $RECOVERY_LEVEL_INFO "創建系統快照: $snapshot_name"
    
    mkdir -p "$snapshot_dir"
    
    # 備份重要配置文件
    local config_files=(
        "$HOME/.bashrc"
        "$HOME/.zshrc"
        "$HOME/.gitconfig"
        "$HOME/.vimrc"
        "$HOME/.profile"
        "/etc/hosts"
        "/etc/resolv.conf"
    )
    
    for config_file in "${config_files[@]}"; do
        if [ -f "$config_file" ]; then
            local target_dir="$snapshot_dir/$(dirname "$config_file")"
            mkdir -p "$target_dir"
            cp "$config_file" "$target_dir/"
        fi
    done
    
    # 備份重要目錄
    local config_dirs=(
        "$HOME/.config/linux-setting"
        "$HOME/.ssh"
    )
    
    for config_dir in "${config_dirs[@]}"; do
        if [ -d "$config_dir" ]; then
            local target_dir="$snapshot_dir/$config_dir"
            mkdir -p "$(dirname "$target_dir")"
            cp -r "$config_dir" "$target_dir"
        fi
    done
    
    # 記錄系統狀態
    {
        echo "# 系統快照信息"
        echo "創建時間: $(date)"
        echo "主機名: $(hostname)"
        echo "用戶: $(whoami)"
        echo "核心版本: $(uname -r)"
        echo ""
        
        echo "# 安裝的套件"
        dpkg -l > "$snapshot_dir/installed_packages.list" 2>/dev/null || true
        
        echo "# 系統服務狀態"
        systemctl list-unit-files --type=service > "$snapshot_dir/services.list" 2>/dev/null || true
        
        echo "# 網絡配置"
        ip addr show > "$snapshot_dir/network_config.txt" 2>/dev/null || true
        
        echo "# 環境變數"
        env > "$snapshot_dir/environment.txt" 2>/dev/null || true
        
    } > "$snapshot_dir/snapshot_info.txt"
    
    # 壓縮快照
    (cd "$SYSTEM_SNAPSHOT_DIR" && tar czf "${snapshot_name}.tar.gz" "$snapshot_name" && rm -rf "$snapshot_name")
    
    log_recovery $RECOVERY_LEVEL_INFO "系統快照已創建: ${snapshot_name}.tar.gz"
    
    # 清理舊快照
    cleanup_old_snapshots
    
    echo "$snapshot_name"
}

# 恢復系統快照
restore_system_snapshot() {
    local snapshot_name="$1"
    
    if [ -z "$snapshot_name" ]; then
        # 使用最新的快照
        snapshot_name=$(ls -t "$SYSTEM_SNAPSHOT_DIR"/*.tar.gz 2>/dev/null | head -1 | xargs basename -s .tar.gz)
    fi
    
    if [ -z "$snapshot_name" ]; then
        log_recovery $RECOVERY_LEVEL_ERROR "找不到可用的快照"
        return 1
    fi
    
    local snapshot_file="$SYSTEM_SNAPSHOT_DIR/${snapshot_name}.tar.gz"
    
    if [ ! -f "$snapshot_file" ]; then
        log_recovery $RECOVERY_LEVEL_ERROR "快照文件不存在: $snapshot_file"
        return 1
    fi
    
    log_recovery $RECOVERY_LEVEL_INFO "恢復系統快照: $snapshot_name"
    
    # 創建當前狀態的備份
    local backup_snapshot
    backup_snapshot=$(create_system_snapshot "backup_before_restore_$(date +%Y%m%d_%H%M%S)")
    
    # 解壓縮快照
    local temp_dir="$RECOVERY_CACHE_DIR/restore_temp"
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    
    if ! tar xzf "$snapshot_file" -C "$temp_dir"; then
        log_recovery $RECOVERY_LEVEL_ERROR "快照解壓縮失敗"
        return 1
    fi
    
    local snapshot_dir="$temp_dir/$snapshot_name"
    
    if [ ! -d "$snapshot_dir" ]; then
        log_recovery $RECOVERY_LEVEL_ERROR "快照目錄不存在"
        return 1
    fi
    
    # 恢復配置文件
    local restored=0
    
    # 查找並恢復所有文件
    find "$snapshot_dir" -type f | while read -r file; do
        local relative_path="${file#$snapshot_dir}"
        local target_path="$relative_path"
        
        # 跳過特殊文件
        [[ "$relative_path" == */snapshot_info.txt ]] && continue
        [[ "$relative_path" == */installed_packages.list ]] && continue
        [[ "$relative_path" == */services.list ]] && continue
        [[ "$relative_path" == */network_config.txt ]] && continue
        [[ "$relative_path" == */environment.txt ]] && continue
        
        if [ -f "$target_path" ]; then
            # 備份現有文件
            cp "$target_path" "${target_path}.backup.$(date +%s)" 2>/dev/null || true
        fi
        
        # 恢復文件
        mkdir -p "$(dirname "$target_path")"
        if cp "$file" "$target_path"; then
            log_recovery $RECOVERY_LEVEL_INFO "已恢復: $target_path"
            restored=$((restored + 1))
        else
            log_recovery $RECOVERY_LEVEL_ERROR "恢復失敗: $target_path"
        fi
    done
    
    # 清理臨時目錄
    rm -rf "$temp_dir"
    
    log_recovery $RECOVERY_LEVEL_INFO "系統快照恢復完成: 恢復了 $restored 個文件"
    log_recovery $RECOVERY_LEVEL_INFO "恢復前的狀態已備份為: $backup_snapshot"
    
    return 0
}

# 清理舊快照
cleanup_old_snapshots() {
    local snapshot_count
    snapshot_count=$(ls -1 "$SYSTEM_SNAPSHOT_DIR"/*.tar.gz 2>/dev/null | wc -l)
    
    if [ "$snapshot_count" -gt "$RECOVERY_MAX_SNAPSHOTS" ]; then
        local excess=$((snapshot_count - RECOVERY_MAX_SNAPSHOTS))
        log_recovery $RECOVERY_LEVEL_INFO "清理 $excess 個舊快照..."
        
        # 刪除最舊的快照
        ls -t "$SYSTEM_SNAPSHOT_DIR"/*.tar.gz | tail -n "$excess" | xargs rm -f
    fi
}

# 檢查系統組件狀態
check_system_component() {
    local component="$1"
    local check_command="${SYSTEM_COMPONENTS[$component]}"
    
    if [ -z "$check_command" ]; then
        log_recovery $RECOVERY_LEVEL_WARNING "未知組件: $component"
        return 2
    fi
    
    if eval "$check_command" >/dev/null 2>&1; then
        return 0  # 正常
    else
        return 1  # 異常
    fi
}

# 執行組件恢復
recover_component() {
    local component="$1"
    local recovery_action="${RECOVERY_ACTIONS[$component]}"
    
    if [ -z "$recovery_action" ]; then
        log_recovery $RECOVERY_LEVEL_WARNING "組件 $component 沒有恢復動作"
        return 1
    fi
    
    log_recovery $RECOVERY_LEVEL_INFO "嘗試恢復組件: $component"
    
    if eval "$recovery_action"; then
        log_recovery $RECOVERY_LEVEL_INFO "組件 $component 恢復成功"
        return 0
    else
        log_recovery $RECOVERY_LEVEL_ERROR "組件 $component 恢復失敗"
        return 1
    fi
}

# 網絡恢復
recover_network() {
    log_recovery $RECOVERY_LEVEL_INFO "恢復網絡連接..."
    
    # 重啟網絡服務
    if systemctl is-active systemd-networkd >/dev/null 2>&1; then
        sudo systemctl restart systemd-networkd
    fi
    
    # 重新啟用網絡接口
    for interface in $(ip link show | grep -E "^[0-9]+:" | cut -d: -f2 | tr -d ' ' | grep -v lo); do
        if ip link show "$interface" | grep -q "state DOWN"; then
            sudo ip link set "$interface" up
        fi
    done
    
    # 等待網絡恢復
    sleep 5
    
    # 測試連接
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# DNS 恢復
recover_dns() {
    log_recovery $RECOVERY_LEVEL_INFO "恢復 DNS 服務..."
    
    # 重建 resolv.conf
    if [ ! -f "/etc/resolv.conf" ] || [ ! -s "/etc/resolv.conf" ]; then
        sudo tee /etc/resolv.conf > /dev/null << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF
    fi
    
    # 重啟 DNS 服務
    if systemctl is-active systemd-resolved >/dev/null 2>&1; then
        sudo systemctl restart systemd-resolved
    fi
    
    # 測試 DNS 解析
    sleep 2
    if nslookup google.com >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# SSH 服務恢復
recover_ssh_service() {
    log_recovery $RECOVERY_LEVEL_INFO "恢復 SSH 服務..."
    
    # 檢查 SSH 是否安裝
    if ! command -v sshd >/dev/null 2>&1; then
        sudo DEBIAN_FRONTEND=noninteractive apt-get update \
            && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server
    fi
    
    # 啟動 SSH 服務
    sudo systemctl enable ssh
    sudo systemctl start ssh
    
    return $?
}

# Docker 服務恢復
recover_docker_service() {
    log_recovery $RECOVERY_LEVEL_INFO "恢復 Docker 服務..."
    
    # 檢查 Docker 是否安裝
    if ! command -v docker >/dev/null 2>&1; then
        log_recovery $RECOVERY_LEVEL_WARNING "Docker 未安裝，跳過恢復"
        return 0
    fi
    
    # 啟動 Docker 服務
    sudo systemctl enable docker
    sudo systemctl start docker
    
    # 檢查權限
    if ! docker ps >/dev/null 2>&1; then
        if ! groups "$USER" | grep -q docker; then
            sudo usermod -aG docker "$USER"
            log_recovery $RECOVERY_LEVEL_WARNING "用戶已添加到 Docker 群組，需要重新登入"
        fi
    fi
    
    return 0
}

# Python 恢復
recover_python() {
    log_recovery $RECOVERY_LEVEL_INFO "恢復 Python 環境..."
    
    # 安裝 Python
    sudo DEBIAN_FRONTEND=noninteractive apt-get update \
        && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-pip python3-venv
    
    # 創建符號連結
    if [ ! -L "/usr/bin/python" ] && [ -f "/usr/bin/python3" ]; then
        sudo ln -sf /usr/bin/python3 /usr/bin/python
    fi
    
    return 0
}

# Git 恢復
recover_git() {
    log_recovery $RECOVERY_LEVEL_INFO "恢復 Git..."

    sudo DEBIAN_FRONTEND=noninteractive apt-get update \
        && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git
    
    return $?
}

# Curl 恢復
recover_curl() {
    log_recovery $RECOVERY_LEVEL_INFO "恢復 Curl..."

    sudo DEBIAN_FRONTEND=noninteractive apt-get update \
        && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl
    
    return $?
}

# Bashrc 恢復
recover_bashrc() {
    log_recovery $RECOVERY_LEVEL_INFO "恢復 .bashrc..."
    
    if [ ! -f "$HOME/.bashrc" ]; then
        # 從系統默認模板複製
        if [ -f "/etc/skel/.bashrc" ]; then
            cp "/etc/skel/.bashrc" "$HOME/.bashrc"
        else
            # 創建基本的 .bashrc
            cat > "$HOME/.bashrc" << 'EOF'
# ~/.bashrc: executed by bash(1) for non-login shells.

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# Basic settings
export EDITOR=vim
export LANG=en_US.UTF-8

# Aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# enable color support
alias ls='ls --color=auto'
alias grep='grep --color=auto'
EOF
        fi
    fi
    
    return 0
}

# Git 配置恢復
recover_gitconfig() {
    log_recovery $RECOVERY_LEVEL_INFO "恢復 Git 配置..."
    
    if [ ! -f "$HOME/.gitconfig" ]; then
        # 創建基本的 Git 配置
        git config --global user.name "User"
        git config --global user.email "user@example.com"
        git config --global init.defaultBranch main
        git config --global core.editor vim
    fi
    
    return 0
}

# Linux Setting 配置恢復
recover_linux_setting_config() {
    log_recovery $RECOVERY_LEVEL_INFO "恢復 Linux Setting 配置..."
    
    if [ ! -d "$HOME/.config/linux-setting" ]; then
        # 初始化配置
        if [ -f "$SCRIPT_DIR/config_manager_simple.sh" ]; then
            "$SCRIPT_DIR/config_manager_simple.sh" init
        fi
    fi
    
    return 0
}

# 執行系統健康檢查
system_health_check() {
    log_recovery $RECOVERY_LEVEL_INFO "執行系統健康檢查..."
    
    local failed_components=()
    local total_components=0
    
    for component in "${!SYSTEM_COMPONENTS[@]}"; do
        total_components=$((total_components + 1))
        
        if ! check_system_component "$component"; then
            failed_components+=("$component")
            log_recovery $RECOVERY_LEVEL_WARNING "組件異常: $component"
        fi
    done
    
    if [ ${#failed_components[@]} -eq 0 ]; then
        log_recovery $RECOVERY_LEVEL_INFO "所有系統組件正常 ($total_components 個)"
        return 0
    else
        log_recovery $RECOVERY_LEVEL_WARNING "發現 ${#failed_components[@]} 個異常組件: ${failed_components[*]}"
        echo "${failed_components[@]}"
        return 1
    fi
}

# 自動恢復系統
auto_recovery() {
    log_recovery $RECOVERY_LEVEL_INFO "開始自動恢復..."
    
    # 檢查恢復鎖
    if ! check_recovery_lock; then
        return 1
    fi
    
    # 創建恢復鎖
    create_recovery_lock
    trap 'remove_recovery_lock' EXIT
    
    # 初始化組件
    init_system_components
    init_recovery_actions
    
    # 創建恢復前快照
    if [ "$RECOVERY_BACKUP_ENABLED" = "true" ]; then
        create_system_snapshot "before_recovery_$(date +%Y%m%d_%H%M%S)"
    fi
    
    # 系統健康檢查
    local failed_components_output
    if ! failed_components_output=$(system_health_check); then
        # 有組件異常，嘗試恢復
        read -ra failed_components <<< "$failed_components_output"
        
        local recovered=0
        local failed=0
        
        for component in "${failed_components[@]}"; do
            if recover_component "$component"; then
                # 再次檢查組件狀態
                if check_system_component "$component"; then
                    log_recovery $RECOVERY_LEVEL_INFO "組件 $component 恢復並驗證成功"
                    recovered=$((recovered + 1))
                else
                    log_recovery $RECOVERY_LEVEL_WARNING "組件 $component 恢復後仍異常"
                    failed=$((failed + 1))
                fi
            else
                failed=$((failed + 1))
            fi
        done
        
        log_recovery $RECOVERY_LEVEL_INFO "自動恢復完成: 成功 $recovered 個，失敗 $failed 個"
        
        # 發送通知
        if [ "$RECOVERY_NOTIFY_ENABLED" = "true" ]; then
            send_recovery_notification "系統自動恢復" "恢復 $recovered 個組件，失敗 $failed 個"
        fi
        
        return $failed
    else
        log_recovery $RECOVERY_LEVEL_INFO "系統健康，無需恢復"
        return 0
    fi
}

# 發送恢復通知
send_recovery_notification() {
    local title="$1"
    local message="$2"
    
    # 嘗試使用系統通知
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "$title" "$message"
    elif command -v osascript >/dev/null 2>&1; then
        # macOS
        osascript -e "display notification \"$message\" with title \"$title\""
    fi
    
    log_recovery $RECOVERY_LEVEL_INFO "通知: $title - $message"
}

# 啟動恢復監控守護進程
start_recovery_monitor() {
    local interval="${1:-$RECOVERY_CHECK_INTERVAL}"
    
    log_info "啟動恢復監控守護進程，檢查間隔: $interval 秒"
    
    # 檢查是否已在運行
    if [ -f "$RECOVERY_CACHE_DIR/monitor.pid" ]; then
        local monitor_pid
        monitor_pid=$(cat "$RECOVERY_CACHE_DIR/monitor.pid")
        if kill -0 "$monitor_pid" 2>/dev/null; then
            log_warning "恢復監控守護進程已在運行 (PID: $monitor_pid)"
            return 1
        fi
    fi
    
    # 後台運行監控進程
    (
        echo $$ > "$RECOVERY_CACHE_DIR/monitor.pid"
        log_recovery $RECOVERY_LEVEL_INFO "恢復監控守護進程已啟動 (PID: $$)"
        
        while true; do
            if [ "$RECOVERY_ENABLED" = "true" ]; then
                log_recovery $RECOVERY_LEVEL_INFO "執行定期系統檢查..."
                
                if [ "$RECOVERY_AUTO_MODE" = "true" ]; then
                    auto_recovery
                else
                    # 只檢查不恢復
                    system_health_check >/dev/null
                fi
            fi
            
            sleep "$interval"
        done
    ) &
    
    log_success "恢復監控守護進程已在後台啟動"
}

# 停止恢復監控守護進程
stop_recovery_monitor() {
    if [ -f "$RECOVERY_CACHE_DIR/monitor.pid" ]; then
        local monitor_pid
        monitor_pid=$(cat "$RECOVERY_CACHE_DIR/monitor.pid")
        if kill -0 "$monitor_pid" 2>/dev/null; then
            kill "$monitor_pid"
            rm -f "$RECOVERY_CACHE_DIR/monitor.pid"
            log_success "恢復監控守護進程已停止"
        else
            log_warning "恢復監控守護進程未在運行"
            rm -f "$RECOVERY_CACHE_DIR/monitor.pid"
        fi
    else
        log_warning "未找到恢復監控守護進程"
    fi
}

# 顯示恢復狀態
show_recovery_status() {
    log_info "系統恢復狀態報告"
    
    echo "=== 恢復系統配置 ==="
    echo "恢復啟用: $RECOVERY_ENABLED"
    echo "自動模式: $RECOVERY_AUTO_MODE"
    echo "備份啟用: $RECOVERY_BACKUP_ENABLED"
    echo "最大快照數: $RECOVERY_MAX_SNAPSHOTS"
    echo "檢查間隔: $RECOVERY_CHECK_INTERVAL 秒"
    echo "通知啟用: $RECOVERY_NOTIFY_ENABLED"
    echo ""
    
    # 顯示監控的組件
    init_system_components
    echo "=== 監控組件狀態 ==="
    for component in "${!SYSTEM_COMPONENTS[@]}"; do
        if check_system_component "$component"; then
            echo "  ✅ $component: 正常"
        else
            echo "  ❌ $component: 異常"
        fi
    done
    echo ""
    
    # 顯示快照列表
    echo "=== 系統快照 ==="
    if [ -d "$SYSTEM_SNAPSHOT_DIR" ]; then
        local snapshot_count=0
        for snapshot in "$SYSTEM_SNAPSHOT_DIR"/*.tar.gz; do
            if [ -f "$snapshot" ]; then
                local name=$(basename "$snapshot" .tar.gz)
                local date=$(stat -c "%Y" "$snapshot" | xargs -I{} date -d @{} '+%Y-%m-%d %H:%M:%S')
                echo "  📸 $name ($date)"
                snapshot_count=$((snapshot_count + 1))
            fi
        done
        
        if [ $snapshot_count -eq 0 ]; then
            echo "  無快照"
        fi
    fi
    echo ""
    
    # 顯示最近的恢復記錄
    if [ -f "$RECOVERY_LOG_FILE" ]; then
        echo "=== 最近的恢復記錄 ==="
        tail -10 "$RECOVERY_LOG_FILE"
    fi
}

# 列出快照
list_snapshots() {
    log_info "系統快照列表"
    
    if [ ! -d "$SYSTEM_SNAPSHOT_DIR" ]; then
        echo "沒有找到快照目錄"
        return 0
    fi
    
    local found=false
    for snapshot in "$SYSTEM_SNAPSHOT_DIR"/*.tar.gz; do
        if [ -f "$snapshot" ]; then
            found=true
            local name=$(basename "$snapshot" .tar.gz)
            local size=$(du -h "$snapshot" | cut -f1)
            local date=$(stat -c "%Y" "$snapshot" | xargs -I{} date -d @{} '+%Y-%m-%d %H:%M:%S')
            echo "📸 $name ($size, $date)"
        fi
    done
    
    if [ "$found" != "true" ]; then
        echo "沒有找到系統快照"
    fi
}

# 清理恢復緩存
cleanup_recovery_cache() {
    log_info "清理恢復緩存..."
    
    # 停止監控進程
    stop_recovery_monitor
    
    # 清理鎖文件
    rm -f "$RECOVERY_LOCK_FILE"
    
    # 清理舊的快照
    cleanup_old_snapshots
    
    # 清理舊的日誌（保留最近7天）
    if [ -d "$(dirname "$RECOVERY_LOG_FILE")" ]; then
        find "$(dirname "$RECOVERY_LOG_FILE")" -name "recovery_*.log" -mtime +7 -delete 2>/dev/null || true
    fi
    
    log_success "恢復緩存清理完成"
}

# 命令行接口
case "${1:-help}" in
    "status")
        show_recovery_status
        ;;
    "check")
        init_system_components
        if system_health_check >/dev/null; then
            echo "系統健康 ✅"
            exit 0
        else
            echo "發現系統問題 ⚠️"
            exit 1
        fi
        ;;
    "recover")
        auto_recovery
        ;;
    "snapshot")
        case "${2:-create}" in
            "create")
                create_system_snapshot "$3"
                ;;
            "restore")
                restore_system_snapshot "$3"
                ;;
            "list")
                list_snapshots
                ;;
            *)
                echo "用法: $0 snapshot {create|restore|list} [名稱]"
                ;;
        esac
        ;;
    "monitor")
        case "${2:-start}" in
            "start")
                start_recovery_monitor "$3"
                ;;
            "stop")
                stop_recovery_monitor
                ;;
            "restart")
                stop_recovery_monitor
                sleep 2
                start_recovery_monitor "$3"
                ;;
            *)
                echo "用法: $0 monitor {start|stop|restart} [間隔秒數]"
                ;;
        esac
        ;;
    "cleanup")
        cleanup_recovery_cache
        ;;
    *)
        echo "系統自動恢復功能"
        echo ""
        echo "用法: $0 <command> [選項]"
        echo ""
        echo "命令:"
        echo "  status               顯示恢復狀態"
        echo "  check                檢查系統健康狀態"
        echo "  recover              執行自動恢復"
        echo "  snapshot create [名稱] 創建系統快照"
        echo "  snapshot restore [名稱] 恢復系統快照"
        echo "  snapshot list        列出快照"
        echo "  monitor start [間隔] 啟動恢復監控"
        echo "  monitor stop         停止恢復監控"
        echo "  monitor restart [間隔] 重啟恢復監控"
        echo "  cleanup              清理恢復緩存"
        echo ""
        echo "環境變數:"
        echo "  RECOVERY_ENABLED        啟用恢復功能"
        echo "  RECOVERY_AUTO_MODE      自動恢復模式"
        echo "  RECOVERY_BACKUP_ENABLED 啟用備份"
        echo "  RECOVERY_MAX_SNAPSHOTS  最大快照數"
        echo "  RECOVERY_CHECK_INTERVAL 檢查間隔"
        echo "  RECOVERY_NOTIFY_ENABLED 啟用通知"
        echo ""
        echo "範例:"
        echo "  $0 status            # 檢查恢復狀態"
        echo "  $0 check             # 檢查系統健康"
        echo "  $0 recover           # 自動恢復系統"
        echo "  $0 snapshot create   # 創建快照"
        echo "  $0 monitor start 300 # 5分鐘間隔監控"
        echo ""
        echo "日誌文件: $RECOVERY_LOG_FILE"
        ;;
esac

log_success "########## 系統自動恢復功能執行完成 ##########"