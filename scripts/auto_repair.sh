#!/bin/bash

# 智能自動修復系統 - 自動檢測和修復常見問題

# 載入共用函數庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || exit 1
if [ -f "$SCRIPT_DIR/config_manager_simple.sh" ]; then
    source "$SCRIPT_DIR/config_manager_simple.sh" 2>/dev/null || true
fi

log_info "########## 智能自動修復系統 ##########"

readonly REPAIR_LOG_FILE="$HOME/.local/log/linux-setting/repair_$(date +%Y%m%d_%H%M%S).log"
readonly REPAIR_CACHE_DIR="$HOME/.cache/linux-setting/repair"
readonly REPAIR_LOCK_FILE="$REPAIR_CACHE_DIR/repair.lock"
readonly REPAIR_CONFIG_FILE="$HOME/.config/linux-setting/repair.conf"

# 確保目錄存在
mkdir -p "$REPAIR_CACHE_DIR"
mkdir -p "$(dirname "$REPAIR_LOG_FILE")"
mkdir -p "$(dirname "$REPAIR_CONFIG_FILE")"

# 修復配置
REPAIR_AUTO_MODE="${REPAIR_AUTO_MODE:-true}"
REPAIR_BACKUP_ENABLED="${REPAIR_BACKUP_ENABLED:-true}"
REPAIR_MAX_ATTEMPTS="${REPAIR_MAX_ATTEMPTS:-3}"
REPAIR_NOTIFY_ENABLED="${REPAIR_NOTIFY_ENABLED:-true}"

# 修復級別
readonly REPAIR_LEVEL_INFO=0
readonly REPAIR_LEVEL_WARNING=1
readonly REPAIR_LEVEL_ERROR=2
readonly REPAIR_LEVEL_CRITICAL=3

# 定義已知問題和修復方法
declare -A REPAIR_RULES

# 初始化修復規則
init_repair_rules() {
    # Docker 相關問題
    REPAIR_RULES["docker_permission"]="Docker 權限問題:fix_docker_permission"
    REPAIR_RULES["docker_not_running"]="Docker 服務未運行:fix_docker_service"
    
    # 網路相關問題
    REPAIR_RULES["dns_resolution"]="DNS 解析問題:fix_dns_resolution"
    REPAIR_RULES["network_unreachable"]="網絡不可達:fix_network_connectivity"
    
    # 套件管理問題
    REPAIR_RULES["apt_lock"]="APT 鎖定問題:fix_apt_lock"
    REPAIR_RULES["broken_packages"]="破損套件:fix_broken_packages"
    REPAIR_RULES["missing_packages"]="缺失套件:fix_missing_packages"
    
    # 權限問題
    REPAIR_RULES["sudo_timeout"]="Sudo 超時:fix_sudo_timeout"
    REPAIR_RULES["permission_denied"]="權限拒絕:fix_permission_denied"
    
    # Python 環境問題
    REPAIR_RULES["python_not_found"]="Python 未找到:fix_python_missing"
    REPAIR_RULES["pip_broken"]="Pip 損壞:fix_pip_broken"
    REPAIR_RULES["uv_not_found"]="UV 未安裝:fix_uv_missing"
    
    # 系統資源問題
    REPAIR_RULES["disk_full"]="磁盤空間不足:fix_disk_full"
    REPAIR_RULES["memory_exhausted"]="內存不足:fix_memory_exhausted"
    
    # 配置檔問題
    REPAIR_RULES["config_corrupted"]="配置檔損壞:fix_config_corrupted"
    REPAIR_RULES["missing_config"]="配置檔缺失:fix_missing_config"
}

# 記錄修復日誌
log_repair() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    local level_text
    case "$level" in
        $REPAIR_LEVEL_INFO) level_text="INFO" ;;
        $REPAIR_LEVEL_WARNING) level_text="WARN" ;;
        $REPAIR_LEVEL_ERROR) level_text="ERROR" ;;
        $REPAIR_LEVEL_CRITICAL) level_text="CRITICAL" ;;
        *) level_text="UNKNOWN" ;;
    esac
    
    echo "[$timestamp] [$level_text] $message" >> "$REPAIR_LOG_FILE"
    
    case "$level" in
        $REPAIR_LEVEL_WARNING) log_warning "$message" ;;
        $REPAIR_LEVEL_ERROR) log_error "$message" ;;
        $REPAIR_LEVEL_CRITICAL) log_error "🚨 CRITICAL: $message" ;;
        *) log_info "$message" ;;
    esac
}

# 檢查修復鎖
check_repair_lock() {
    if [ -f "$REPAIR_LOCK_FILE" ]; then
        local lock_pid
        lock_pid=$(cat "$REPAIR_LOCK_FILE")
        if kill -0 "$lock_pid" 2>/dev/null; then
            log_repair $REPAIR_LEVEL_WARNING "修復正在進行中 (PID: $lock_pid)"
            return 1
        else
            log_repair $REPAIR_LEVEL_WARNING "發現僵屍鎖文件，正在清理..."
            rm -f "$REPAIR_LOCK_FILE"
        fi
    fi
    return 0
}

# 創建修復鎖
create_repair_lock() {
    echo $$ > "$REPAIR_LOCK_FILE"
}

# 移除修復鎖
remove_repair_lock() {
    rm -f "$REPAIR_LOCK_FILE"
}

# 備份相關檔案
backup_before_repair() {
    local item_name="$1"
    
    if [ "$REPAIR_BACKUP_ENABLED" != "true" ]; then
        return 0
    fi
    
    local backup_dir="$REPAIR_CACHE_DIR/backup/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    case "$item_name" in
        "docker")
            [ -f "/etc/docker/daemon.json" ] && cp "/etc/docker/daemon.json" "$backup_dir/"
            ;;
        "network")
            [ -f "/etc/resolv.conf" ] && cp "/etc/resolv.conf" "$backup_dir/"
            [ -f "/etc/hosts" ] && cp "/etc/hosts" "$backup_dir/"
            ;;
        "apt")
            [ -f "/etc/apt/sources.list" ] && cp "/etc/apt/sources.list" "$backup_dir/"
            cp -r /etc/apt/sources.list.d "$backup_dir/" 2>/dev/null || true
            ;;
        "user_config")
            [ -d "$HOME/.config/linux-setting" ] && cp -r "$HOME/.config/linux-setting" "$backup_dir/"
            ;;
    esac
    
    log_repair $REPAIR_LEVEL_INFO "已備份 $item_name 到: $backup_dir"
    echo "$backup_dir"
}

# Docker 權限修復
fix_docker_permission() {
    log_repair $REPAIR_LEVEL_INFO "修復 Docker 權限問題..."
    
    backup_before_repair "docker"
    
    # 檢查 Docker 群組是否存在
    if ! getent group docker >/dev/null; then
        log_repair $REPAIR_LEVEL_INFO "創建 Docker 群組..."
        sudo groupadd docker
    fi
    
    # 將用戶添加到 Docker 群組
    if ! groups "$USER" | grep -q docker; then
        log_repair $REPAIR_LEVEL_INFO "將用戶 $USER 添加到 Docker 群組..."
        sudo usermod -aG docker "$USER"
        
        # 更新當前會話的群組
        if command -v newgrp >/dev/null 2>&1; then
            echo "執行 'newgrp docker' 或重新登入以套用變更"
        fi
        
        log_repair $REPAIR_LEVEL_INFO "Docker 權限修復完成，需要重新登入"
        return 0
    else
        log_repair $REPAIR_LEVEL_INFO "用戶已在 Docker 群組中，檢查 Docker 守護進程..."
        
        # 檢查 Docker 服務是否運行
        if ! systemctl is-active docker >/dev/null 2>&1; then
            log_repair $REPAIR_LEVEL_INFO "啟動 Docker 服務..."
            sudo systemctl start docker
            sudo systemctl enable docker
        fi
        
        log_repair $REPAIR_LEVEL_INFO "Docker 權限檢查完成"
        return 0
    fi
}

# Docker 服務修復
fix_docker_service() {
    log_repair $REPAIR_LEVEL_INFO "修復 Docker 服務問題..."
    
    backup_before_repair "docker"
    
    # 檢查 Docker 是否安裝
    if ! command -v docker >/dev/null 2>&1; then
        log_repair $REPAIR_LEVEL_ERROR "Docker 未安裝，需要重新安裝"
        return 1
    fi
    
    # 嘗試啟動 Docker 服務
    if sudo systemctl start docker; then
        log_repair $REPAIR_LEVEL_INFO "Docker 服務已啟動"
        sudo systemctl enable docker
        return 0
    else
        log_repair $REPAIR_LEVEL_ERROR "無法啟動 Docker 服務，檢查日誌: sudo journalctl -u docker"
        return 1
    fi
}

# DNS 解析修復
fix_dns_resolution() {
    log_repair $REPAIR_LEVEL_INFO "修復 DNS 解析問題..."
    
    backup_before_repair "network"
    
    # 檢查 /etc/resolv.conf
    if [ ! -f "/etc/resolv.conf" ] || [ ! -s "/etc/resolv.conf" ]; then
        log_repair $REPAIR_LEVEL_WARNING "resolv.conf 檔案缺失或為空，正在重建..."
        
        # 創建基本的 resolv.conf
        sudo tee /etc/resolv.conf > /dev/null << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF
        log_repair $REPAIR_LEVEL_INFO "已重建 resolv.conf"
    fi
    
    # 重啟 DNS 相關服務
    if systemctl is-active systemd-resolved >/dev/null 2>&1; then
        sudo systemctl restart systemd-resolved
        log_repair $REPAIR_LEVEL_INFO "已重啟 systemd-resolved"
    fi
    
    # 測試 DNS 解析
    if nslookup google.com >/dev/null 2>&1; then
        log_repair $REPAIR_LEVEL_INFO "DNS 解析修復成功"
        return 0
    else
        log_repair $REPAIR_LEVEL_ERROR "DNS 解析修復失敗"
        return 1
    fi
}

# 網絡連接修復
fix_network_connectivity() {
    log_repair $REPAIR_LEVEL_INFO "修復網絡連接問題..."
    
    backup_before_repair "network"
    
    # 重啟網絡服務
    if systemctl is-active systemd-networkd >/dev/null 2>&1; then
        sudo systemctl restart systemd-networkd
        log_repair $REPAIR_LEVEL_INFO "已重啟 systemd-networkd"
    fi
    
    # 重新配置網絡接口
    for interface in $(ip link show | grep -E "^[0-9]+:" | cut -d: -f2 | tr -d ' ' | grep -v lo); do
        if ip link show "$interface" | grep -q "state DOWN"; then
            log_repair $REPAIR_LEVEL_INFO "嘗試啟用網絡接口: $interface"
            sudo ip link set "$interface" up
        fi
    done
    
    # 測試網絡連接
    sleep 2
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        log_repair $REPAIR_LEVEL_INFO "網絡連接修復成功"
        return 0
    else
        log_repair $REPAIR_LEVEL_ERROR "網絡連接修復失敗"
        return 1
    fi
}

# APT 鎖定修復
fix_apt_lock() {
    log_repair $REPAIR_LEVEL_INFO "修復 APT 鎖定問題..."
    
    # 檢查正在運行的 APT 進程
    local apt_processes
    apt_processes=$(ps aux | grep -E "(apt|dpkg)" | grep -v grep)
    
    if [ -n "$apt_processes" ]; then
        log_repair $REPAIR_LEVEL_WARNING "發現正在運行的 APT 進程："
        echo "$apt_processes" >> "$REPAIR_LOG_FILE"
        
        # 等待進程完成
        log_repair $REPAIR_LEVEL_INFO "等待 APT 進程完成..."
        while pgrep -f "(apt|dpkg)" >/dev/null; do
            sleep 5
        done
    fi
    
    # 移除鎖文件
    local lock_files=(
        "/var/lib/dpkg/lock"
        "/var/lib/dpkg/lock-frontend" 
        "/var/lib/apt/lists/lock"
        "/var/cache/apt/archives/lock"
    )
    
    for lock_file in "${lock_files[@]}"; do
        if [ -f "$lock_file" ]; then
            log_repair $REPAIR_LEVEL_INFO "移除鎖文件: $lock_file"
            sudo rm -f "$lock_file"
        fi
    done
    
    # 重新配置 dpkg
    sudo dpkg --configure -a
    
    # 測試 APT
    if sudo apt update >/dev/null 2>&1; then
        log_repair $REPAIR_LEVEL_INFO "APT 鎖定修復成功"
        return 0
    else
        log_repair $REPAIR_LEVEL_ERROR "APT 鎖定修復失敗"
        return 1
    fi
}

# 破損套件修復
fix_broken_packages() {
    log_repair $REPAIR_LEVEL_INFO "修復破損套件..."
    
    backup_before_repair "apt"
    
    # 修復破損的依賴關係
    if sudo apt --fix-broken install -y; then
        log_repair $REPAIR_LEVEL_INFO "破損套件修復成功"
        
        # 清理不需要的套件
        sudo apt autoremove -y
        sudo apt autoclean
        
        return 0
    else
        log_repair $REPAIR_LEVEL_ERROR "破損套件修復失敗"
        return 1
    fi
}

# 缺失套件修復
fix_missing_packages() {
    log_repair $REPAIR_LEVEL_INFO "修復缺失套件..."
    
    local essential_packages=(
        "curl"
        "wget"
        "git" 
        "python3"
        "python3-pip"
        "build-essential"
    )
    
    local missing_packages=()
    
    # 檢查缺失的套件
    for package in "${essential_packages[@]}"; do
        if ! dpkg -l "$package" >/dev/null 2>&1; then
            missing_packages+=("$package")
        fi
    done
    
    if [ ${#missing_packages[@]} -gt 0 ]; then
        log_repair $REPAIR_LEVEL_INFO "發現缺失的套件: ${missing_packages[*]}"
        
        # 更新套件列表
        sudo apt update
        
        # 安裝缺失的套件
        if sudo apt install -y "${missing_packages[@]}"; then
            log_repair $REPAIR_LEVEL_INFO "缺失套件安裝成功"
            return 0
        else
            log_repair $REPAIR_LEVEL_ERROR "缺失套件安裝失敗"
            return 1
        fi
    else
        log_repair $REPAIR_LEVEL_INFO "所有必要套件都已安裝"
        return 0
    fi
}

# Sudo 超時修復
fix_sudo_timeout() {
    log_repair $REPAIR_LEVEL_INFO "修復 Sudo 超時問題..."
    
    # 測試 sudo 是否正常工作
    if sudo -n true 2>/dev/null; then
        log_repair $REPAIR_LEVEL_INFO "Sudo 權限正常"
        return 0
    fi
    
    log_repair $REPAIR_LEVEL_WARNING "Sudo 需要密碼，這可能導致自動化腳本失敗"
    log_repair $REPAIR_LEVEL_INFO "建議設置免密碼 sudo 或運行: sudo -v"
    
    return 1
}

# 權限拒絕修復
fix_permission_denied() {
    log_repair $REPAIR_LEVEL_INFO "修復權限拒絕問題..."
    
    # 修復常見的權限問題
    local permission_fixes=(
        "$HOME/.local:755"
        "$HOME/.cache:755"
        "$HOME/.config:755"
    )
    
    for fix in "${permission_fixes[@]}"; do
        local path="${fix%:*}"
        local perm="${fix#*:}"
        
        if [ -d "$path" ]; then
            chmod "$perm" "$path"
            log_repair $REPAIR_LEVEL_INFO "已修復權限: $path ($perm)"
        fi
    done
    
    return 0
}

# Python 缺失修復
fix_python_missing() {
    log_repair $REPAIR_LEVEL_INFO "修復 Python 缺失問題..."
    
    # 安裝 Python
    if sudo apt update && sudo apt install -y python3 python3-pip python3-venv; then
        log_repair $REPAIR_LEVEL_INFO "Python 安裝成功"
        
        # 創建符號連結
        if [ ! -L "/usr/bin/python" ] && [ -f "/usr/bin/python3" ]; then
            sudo ln -sf /usr/bin/python3 /usr/bin/python
        fi
        
        return 0
    else
        log_repair $REPAIR_LEVEL_ERROR "Python 安裝失敗"
        return 1
    fi
}

# Pip 損壞修復
fix_pip_broken() {
    log_repair $REPAIR_LEVEL_INFO "修復 Pip 損壞問題..."
    
    # 重新安裝 pip
    if curl https://bootstrap.pypa.io/get-pip.py | python3 -; then
        log_repair $REPAIR_LEVEL_INFO "Pip 重新安裝成功"
        return 0
    else
        log_repair $REPAIR_LEVEL_ERROR "Pip 重新安裝失敗"
        return 1
    fi
}

# UV 缺失修復
fix_uv_missing() {
    log_repair $REPAIR_LEVEL_INFO "修復 UV 缺失問題..."
    
    # 使用安全方式安裝 uv
    if command -v curl >/dev/null 2>&1; then
        if curl -LsSf https://astral.sh/uv/install.sh | sh; then
            # 更新 PATH
            export PATH="$HOME/.local/bin:$PATH"
            log_repair $REPAIR_LEVEL_INFO "UV 安裝成功"
            return 0
        fi
    fi
    
    log_repair $REPAIR_LEVEL_ERROR "UV 安裝失敗"
    return 1
}

# 磁盤空間修復
fix_disk_full() {
    log_repair $REPAIR_LEVEL_INFO "修復磁盤空間不足問題..."
    
    # 清理 APT 緩存
    sudo apt clean
    sudo apt autoremove -y
    
    # 清理日誌
    sudo journalctl --vacuum-time=7d
    
    # 清理臨時文件
    sudo find /tmp -type f -atime +7 -delete 2>/dev/null || true
    
    # 清理用戶快取
    if [ -d "$HOME/.cache" ]; then
        find "$HOME/.cache" -type f -atime +30 -delete 2>/dev/null || true
    fi
    
    log_repair $REPAIR_LEVEL_INFO "磁盤清理完成"
    return 0
}

# 內存不足修復
fix_memory_exhausted() {
    log_repair $REPAIR_LEVEL_INFO "修復內存不足問題..."
    
    # 清理頁面緩存
    sudo sync
    echo 1 | sudo tee /proc/sys/vm/drop_caches >/dev/null
    
    # 顯示大量內存使用的進程
    log_repair $REPAIR_LEVEL_INFO "內存使用最多的進程："
    ps aux --sort=-%mem | head -10 >> "$REPAIR_LOG_FILE"
    
    log_repair $REPAIR_LEVEL_WARNING "建議手動檢查並終止不必要的進程"
    return 0
}

# 配置檔損壞修復
fix_config_corrupted() {
    log_repair $REPAIR_LEVEL_INFO "修復損壞的配置檔..."
    
    backup_before_repair "user_config"
    
    # 重建用戶配置
    if [ -f "$SCRIPT_DIR/config_manager_simple.sh" ]; then
        "$SCRIPT_DIR/config_manager_simple.sh" init
        log_repair $REPAIR_LEVEL_INFO "用戶配置已重建"
        return 0
    else
        log_repair $REPAIR_LEVEL_ERROR "無法找到配置管理器"
        return 1
    fi
}

# 配置檔缺失修復
fix_missing_config() {
    log_repair $REPAIR_LEVEL_INFO "修復缺失的配置檔..."
    
    # 初始化配置系統
    if [ -f "$SCRIPT_DIR/config_manager_simple.sh" ]; then
        "$SCRIPT_DIR/config_manager_simple.sh" init
        log_repair $REPAIR_LEVEL_INFO "配置檔已創建"
        return 0
    else
        log_repair $REPAIR_LEVEL_ERROR "無法找到配置管理器"
        return 1
    fi
}

# 自動診斷問題
auto_diagnose() {
    log_repair $REPAIR_LEVEL_INFO "開始自動診斷..."
    
    local issues_found=()
    
    # 檢查 Docker 問題
    if command -v docker >/dev/null 2>&1; then
        if ! docker ps >/dev/null 2>&1; then
            if [[ "$(docker ps 2>&1)" == *"permission denied"* ]]; then
                issues_found+=("docker_permission")
            elif ! systemctl is-active docker >/dev/null 2>&1; then
                issues_found+=("docker_not_running")
            fi
        fi
    fi
    
    # 檢查網絡問題
    if ! ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        issues_found+=("network_unreachable")
    fi
    
    if ! nslookup google.com >/dev/null 2>&1; then
        issues_found+=("dns_resolution")
    fi
    
    # 檢查 APT 問題
    if lsof /var/lib/dpkg/lock >/dev/null 2>&1; then
        issues_found+=("apt_lock")
    fi
    
    local broken_packages
    broken_packages=$(dpkg -l | grep '^..r' | wc -l)
    if [ "$broken_packages" -gt 0 ]; then
        issues_found+=("broken_packages")
    fi
    
    # 檢查磁盤空間
    local disk_usage
    disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 95 ]; then
        issues_found+=("disk_full")
    fi
    
    # 檢查內存使用
    local mem_usage
    mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [ "$mem_usage" -gt 95 ]; then
        issues_found+=("memory_exhausted")
    fi
    
    # 檢查 Python 環境
    if ! command -v python3 >/dev/null 2>&1; then
        issues_found+=("python_not_found")
    fi
    
    if ! command -v uv >/dev/null 2>&1; then
        issues_found+=("uv_not_found")
    fi
    
    # 檢查配置檔
    if [ ! -f "$HOME/.config/linux-setting/user.conf" ]; then
        issues_found+=("missing_config")
    fi
    
    echo "${issues_found[@]}"
}

# 執行自動修復
auto_repair() {
    log_repair $REPAIR_LEVEL_INFO "開始自動修復..."
    
    # 檢查修復鎖
    if ! check_repair_lock; then
        return 1
    fi
    
    # 創建修復鎖
    create_repair_lock
    trap 'remove_repair_lock' EXIT
    
    # 初始化修復規則
    init_repair_rules
    
    # 自動診斷問題
    local issues
    read -ra issues <<< "$(auto_diagnose)"
    
    if [ ${#issues[@]} -eq 0 ]; then
        log_repair $REPAIR_LEVEL_INFO "未發現需要修復的問題"
        return 0
    fi
    
    log_repair $REPAIR_LEVEL_INFO "發現 ${#issues[@]} 個問題需要修復"
    
    local repaired=0
    local failed=0
    
    # 修復每個問題
    for issue in "${issues[@]}"; do
        if [ -n "${REPAIR_RULES[$issue]:-}" ]; then
            local rule_info="${REPAIR_RULES[$issue]}"
            local description="${rule_info%:*}"
            local fix_function="${rule_info#*:}"
            
            log_repair $REPAIR_LEVEL_INFO "修復問題: $description"
            
            local attempts=0
            local success=false
            
            while [ $attempts -lt "$REPAIR_MAX_ATTEMPTS" ]; do
                attempts=$((attempts + 1))
                
                if $fix_function; then
                    log_repair $REPAIR_LEVEL_INFO "修復成功: $description"
                    repaired=$((repaired + 1))
                    success=true
                    break
                else
                    log_repair $REPAIR_LEVEL_WARNING "修復失敗 (嘗試 $attempts/$REPAIR_MAX_ATTEMPTS): $description"
                    sleep 2
                fi
            done
            
            if [ "$success" != "true" ]; then
                log_repair $REPAIR_LEVEL_ERROR "修復最終失敗: $description"
                failed=$((failed + 1))
            fi
        else
            log_repair $REPAIR_LEVEL_WARNING "未知問題，無法自動修復: $issue"
            failed=$((failed + 1))
        fi
    done
    
    # 總結修復結果
    log_repair $REPAIR_LEVEL_INFO "自動修復完成: 成功 $repaired 個，失敗 $failed 個"
    
    # 發送通知
    if [ "$REPAIR_NOTIFY_ENABLED" = "true" ]; then
        send_repair_notification "自動修復完成" "成功修復 $repaired 個問題，失敗 $failed 個"
    fi
    
    return $failed
}

# 發送修復通知
send_repair_notification() {
    local title="$1"
    local message="$2"
    
    # 嘗試使用系統通知
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "$title" "$message"
    elif command -v osascript >/dev/null 2>&1; then
        # macOS
        osascript -e "display notification \"$message\" with title \"$title\""
    fi
    
    log_repair $REPAIR_LEVEL_INFO "通知: $title - $message"
}

# 修復狀態報告
repair_status() {
    log_info "修復系統狀態報告"
    
    echo "=== 修復系統配置 ==="
    echo "自動模式: $REPAIR_AUTO_MODE"
    echo "備份啟用: $REPAIR_BACKUP_ENABLED"
    echo "最大嘗試次數: $REPAIR_MAX_ATTEMPTS"
    echo "通知啟用: $REPAIR_NOTIFY_ENABLED"
    echo ""
    
    # 顯示可修復的問題類型
    init_repair_rules
    echo "=== 可修復的問題類型 ==="
    for issue in "${!REPAIR_RULES[@]}"; do
        local description="${REPAIR_RULES[$issue]%:*}"
        echo "  $issue: $description"
    done
    echo ""
    
    # 檢查當前問題
    echo "=== 當前系統問題檢查 ==="
    local issues
    read -ra issues <<< "$(auto_diagnose)"
    
    if [ ${#issues[@]} -eq 0 ]; then
        echo "✅ 未發現問題"
    else
        echo "⚠️  發現以下問題:"
        for issue in "${issues[@]}"; do
            local description="${REPAIR_RULES[$issue]%:*}"
            echo "  - $issue: $description"
        done
    fi
    echo ""
    
    # 顯示最近的修復記錄
    if [ -f "$REPAIR_LOG_FILE" ]; then
        echo "=== 最近的修復記錄 ==="
        tail -10 "$REPAIR_LOG_FILE"
    fi
}

# 測試特定修復功能
test_repair() {
    local issue="$1"
    
    if [ -z "$issue" ]; then
        log_error "請指定要測試的問題類型"
        return 1
    fi
    
    init_repair_rules
    
    if [ -z "${REPAIR_RULES[$issue]:-}" ]; then
        log_error "未知的問題類型: $issue"
        return 1
    fi
    
    local rule_info="${REPAIR_RULES[$issue]}"
    local description="${rule_info%:*}"
    local fix_function="${rule_info#*:}"
    
    log_info "測試修復: $description"
    
    if $fix_function; then
        log_success "測試修復成功"
        return 0
    else
        log_error "測試修復失敗"
        return 1
    fi
}

# 清理修復緩存
cleanup_repair_cache() {
    log_info "清理修復緩存..."
    
    # 移除鎖文件
    rm -f "$REPAIR_LOCK_FILE"
    
    # 清理舊的備份（保留最近3天）
    if [ -d "$REPAIR_CACHE_DIR/backup" ]; then
        find "$REPAIR_CACHE_DIR/backup" -type d -mtime +3 -exec rm -rf {} \; 2>/dev/null || true
    fi
    
    # 清理舊的日誌（保留最近7天）
    if [ -d "$(dirname "$REPAIR_LOG_FILE")" ]; then
        find "$(dirname "$REPAIR_LOG_FILE")" -name "repair_*.log" -mtime +7 -delete 2>/dev/null || true
    fi
    
    log_success "修復緩存清理完成"
}

# 命令行接口
case "${1:-help}" in
    "status")
        repair_status
        ;;
    "diagnose")
        init_repair_rules
        issues=$(auto_diagnose)
        if [ -n "$issues" ]; then
            echo "發現問題: $issues"
            exit 1
        else
            echo "系統正常"
            exit 0
        fi
        ;;
    "repair")
        auto_repair
        ;;
    "test")
        if [ -z "$2" ]; then
            log_error "請指定要測試的問題類型"
            exit 1
        fi
        test_repair "$2"
        ;;
    "cleanup")
        cleanup_repair_cache
        ;;
    "rules")
        init_repair_rules
        echo "可修復的問題類型:"
        for issue in "${!REPAIR_RULES[@]}"; do
            echo "  $issue: ${REPAIR_RULES[$issue]%:*}"
        done
        ;;
    *)
        echo "智能自動修復系統"
        echo ""
        echo "用法: $0 <command> [選項]"
        echo ""
        echo "命令:"
        echo "  status               顯示修復系統狀態"
        echo "  diagnose             診斷系統問題"
        echo "  repair               執行自動修復"
        echo "  test <issue_type>    測試特定修復功能"
        echo "  cleanup              清理修復緩存"
        echo "  rules                顯示修復規則"
        echo ""
        echo "環境變數:"
        echo "  REPAIR_AUTO_MODE     自動修復模式 (true/false)"
        echo "  REPAIR_BACKUP_ENABLED 啟用備份 (true/false)"
        echo "  REPAIR_MAX_ATTEMPTS  最大嘗試次數"
        echo "  REPAIR_NOTIFY_ENABLED 啟用通知 (true/false)"
        echo ""
        echo "範例:"
        echo "  $0 status            # 檢查修復系統狀態"
        echo "  $0 diagnose          # 診斷系統問題"
        echo "  $0 repair            # 自動修復發現的問題"
        echo "  $0 test docker_permission # 測試 Docker 權限修復"
        echo ""
        echo "日誌文件: $REPAIR_LOG_FILE"
        ;;
esac

log_success "########## 智能自動修復系統執行完成 ##########"