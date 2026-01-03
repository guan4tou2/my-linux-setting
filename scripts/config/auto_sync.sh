#!/bin/bash

# 自動同步系統 - 智能配置和腳本同步

# 載入共用函數庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || exit 1
if [ -f "$SCRIPT_DIR/config_manager_simple.sh" ]; then
    source "$SCRIPT_DIR/config_manager_simple.sh" 2>/dev/null || true
fi

log_info "########## 自動同步系統 ##########"

readonly SYNC_CONFIG_DIR="$HOME/.config/linux-setting/sync"
readonly SYNC_CACHE_DIR="$HOME/.cache/linux-setting/sync"
readonly SYNC_LOG_FILE="$HOME/.local/log/linux-setting/sync_$(date +%Y%m%d).log"
readonly SYNC_LOCK_FILE="$SYNC_CACHE_DIR/sync.lock"
readonly REMOTE_CONFIG_URL="https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main/config"
readonly VERSION_CHECK_URL="https://api.github.com/repos/guan4tou2/my-linux-setting/commits/main"

# 確保目錄存在
mkdir -p "$SYNC_CONFIG_DIR"
mkdir -p "$SYNC_CACHE_DIR"
mkdir -p "$(dirname "$SYNC_LOG_FILE")"

# 同步配置
SYNC_ENABLED="${SYNC_ENABLED:-true}"
SYNC_INTERVAL="${SYNC_INTERVAL:-3600}"  # 1小時
SYNC_AUTO_APPLY="${SYNC_AUTO_APPLY:-false}"
SYNC_BACKUP_ENABLED="${SYNC_BACKUP_ENABLED:-true}"
SYNC_NOTIFY_ENABLED="${SYNC_NOTIFY_ENABLED:-true}"

# 檢查同步鎖
check_sync_lock() {
    if [ -f "$SYNC_LOCK_FILE" ]; then
        local lock_pid
        lock_pid=$(cat "$SYNC_LOCK_FILE")
        if kill -0 "$lock_pid" 2>/dev/null; then
            log_warning "同步正在進行中 (PID: $lock_pid)"
            return 1
        else
            log_warning "發現僵屍鎖文件，正在清理..."
            rm -f "$SYNC_LOCK_FILE"
        fi
    fi
    return 0
}

# 創建同步鎖
create_sync_lock() {
    echo $$ > "$SYNC_LOCK_FILE"
}

# 移除同步鎖
remove_sync_lock() {
    rm -f "$SYNC_LOCK_FILE"
}

# 記錄同步日誌
log_sync() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" >> "$SYNC_LOG_FILE"
    
    case "$level" in
        "ERROR") log_error "$message" ;;
        "WARN") log_warning "$message" ;;
        "INFO") log_info "$message" ;;
        *) log_debug "$message" ;;
    esac
}

# 檢查網絡連接
check_network() {
    if ! ping -c 1 -W 5 github.com >/dev/null 2>&1; then
        log_sync "ERROR" "網絡連接失敗，無法執行同步"
        return 1
    fi
    return 0
}

# 獲取遠程版本信息
get_remote_version() {
    local version_info
    if command -v curl >/dev/null 2>&1; then
        version_info=$(curl -s --max-time 10 "$VERSION_CHECK_URL" 2>/dev/null)
    elif command -v wget >/dev/null 2>&1; then
        version_info=$(wget -qO- --timeout=10 "$VERSION_CHECK_URL" 2>/dev/null)
    else
        log_sync "ERROR" "缺少 curl 或 wget，無法檢查版本"
        return 1
    fi
    
    if [ -z "$version_info" ]; then
        log_sync "ERROR" "無法獲取遠程版本信息"
        return 1
    fi
    
    # 提取 SHA 值作為版本標識
    echo "$version_info" | grep -o '"sha":"[^"]*"' | cut -d'"' -f4 | head -1
}

# 獲取本地版本
get_local_version() {
    local version_file="$SYNC_CACHE_DIR/local_version"
    if [ -f "$version_file" ]; then
        cat "$version_file"
    else
        echo "unknown"
    fi
}

# 更新本地版本記錄
update_local_version() {
    local version="$1"
    echo "$version" > "$SYNC_CACHE_DIR/local_version"
}

# 檢查是否需要同步
needs_sync() {
    local remote_version
    local local_version
    
    remote_version=$(get_remote_version)
    if [ -z "$remote_version" ]; then
        return 1
    fi
    
    local_version=$(get_local_version)
    
    if [ "$remote_version" != "$local_version" ]; then
        log_sync "INFO" "發現新版本: $remote_version (本地: $local_version)"
        return 0
    else
        log_sync "INFO" "已是最新版本: $remote_version"
        return 1
    fi
}

# 備份當前配置
backup_current_config() {
    local backup_dir="$SYNC_CACHE_DIR/backup/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # 備份用戶配置
    if [ -d "$HOME/.config/linux-setting" ]; then
        cp -r "$HOME/.config/linux-setting" "$backup_dir/" 2>/dev/null || true
    fi
    
    # 備份重要的 dotfiles
    local important_files=(
        "$HOME/.bashrc"
        "$HOME/.zshrc"
        "$HOME/.gitconfig"
        "$HOME/.vimrc"
    )
    
    for file in "${important_files[@]}"; do
        if [ -f "$file" ]; then
            cp "$file" "$backup_dir/" 2>/dev/null || true
        fi
    done
    
    log_sync "INFO" "配置已備份到: $backup_dir"
    echo "$backup_dir"
}

# 下載遠程配置文件
download_remote_config() {
    local config_name="$1"
    local target_path="$2"
    local remote_url="$REMOTE_CONFIG_URL/$config_name"
    
    log_sync "INFO" "下載配置: $config_name"
    
    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL --max-time 30 "$remote_url" -o "$target_path"; then
            log_sync "INFO" "成功下載: $config_name"
            return 0
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -q --timeout=30 "$remote_url" -O "$target_path"; then
            log_sync "INFO" "成功下載: $config_name"
            return 0
        fi
    fi
    
    log_sync "ERROR" "下載失敗: $config_name"
    return 1
}

# 同步配置文件
sync_config_files() {
    log_sync "INFO" "開始同步配置文件..."
    
    local temp_dir="$SYNC_CACHE_DIR/temp_$(date +%s)"
    mkdir -p "$temp_dir"
    
    # 定義需要同步的配置文件
    local config_files=(
        "default.conf:$temp_dir/default.conf"
        "mirrors/china.conf:$temp_dir/china.conf"
        "mirrors/global.conf:$temp_dir/global.conf"
        "templates/user.conf:$temp_dir/user_template.conf"
    )
    
    local downloaded=0
    local failed=0
    
    # 下載所有配置文件
    for config_entry in "${config_files[@]}"; do
        local remote_path="${config_entry%:*}"
        local local_path="${config_entry#*:}"
        
        if download_remote_config "$remote_path" "$local_path"; then
            downloaded=$((downloaded + 1))
        else
            failed=$((failed + 1))
        fi
    done
    
    if [ $failed -gt 0 ]; then
        log_sync "WARN" "部分配置下載失敗: $failed/$((downloaded + failed))"
    else
        log_sync "INFO" "所有配置下載成功: $downloaded 個文件"
    fi
    
    # 如果自動應用，則更新本地配置
    if [ "$SYNC_AUTO_APPLY" = "true" ] && [ $downloaded -gt 0 ]; then
        apply_synced_configs "$temp_dir"
    else
        log_sync "INFO" "配置已下載，等待手動應用。運行: $0 apply"
    fi
    
    return 0
}

# 應用同步的配置
apply_synced_configs() {
    local temp_dir="${1:-$SYNC_CACHE_DIR/temp_*}"
    
    # 查找最新的臨時目錄
    if [[ "$temp_dir" == *"*"* ]]; then
        temp_dir=$(find "$SYNC_CACHE_DIR" -name "temp_*" -type d | sort | tail -1)
    fi
    
    if [ ! -d "$temp_dir" ]; then
        log_sync "ERROR" "找不到待應用的配置文件"
        return 1
    fi
    
    log_sync "INFO" "應用同步的配置..."
    
    # 備份當前配置
    local backup_dir
    if [ "$SYNC_BACKUP_ENABLED" = "true" ]; then
        backup_dir=$(backup_current_config)
    fi
    
    # 應用新配置
    local applied=0
    
    # 更新預設配置
    if [ -f "$temp_dir/default.conf" ]; then
        mkdir -p "$(dirname "$SCRIPT_DIR/../config/default.conf")"
        cp "$temp_dir/default.conf" "$SCRIPT_DIR/../config/default.conf"
        applied=$((applied + 1))
        log_sync "INFO" "已更新預設配置"
    fi
    
    # 更新鏡像配置
    if [ -f "$temp_dir/china.conf" ]; then
        mkdir -p "$SCRIPT_DIR/../config/mirrors"
        cp "$temp_dir/china.conf" "$SCRIPT_DIR/../config/mirrors/"
        applied=$((applied + 1))
    fi
    
    if [ -f "$temp_dir/global.conf" ]; then
        mkdir -p "$SCRIPT_DIR/../config/mirrors"
        cp "$temp_dir/global.conf" "$SCRIPT_DIR/../config/mirrors/"
        applied=$((applied + 1))
    fi
    
    # 檢查用戶配置模板更新
    if [ -f "$temp_dir/user_template.conf" ]; then
        local user_config="$HOME/.config/linux-setting/user.conf"
        if [ ! -f "$user_config" ]; then
            # 如果用戶配置不存在，使用新模板
            mkdir -p "$(dirname "$user_config")"
            cp "$temp_dir/user_template.conf" "$user_config"
            log_sync "INFO" "已創建用戶配置文件"
            applied=$((applied + 1))
        else
            # 如果用戶配置存在，提示手動合併
            cp "$temp_dir/user_template.conf" "$user_config.new"
            log_sync "WARN" "用戶配置模板已更新，請手動合併: $user_config.new"
        fi
    fi
    
    if [ $applied -gt 0 ]; then
        log_sync "INFO" "已應用 $applied 個配置文件"
        
        # 更新版本記錄
        local remote_version
        remote_version=$(get_remote_version)
        if [ -n "$remote_version" ]; then
            update_local_version "$remote_version"
        fi
        
        # 發送通知
        if [ "$SYNC_NOTIFY_ENABLED" = "true" ]; then
            send_sync_notification "配置同步完成" "已應用 $applied 個配置更新"
        fi
    fi
    
    # 清理臨時文件
    rm -rf "$temp_dir"
    
    return 0
}

# 發送同步通知
send_sync_notification() {
    local title="$1"
    local message="$2"
    
    # 嘗試使用系統通知
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "$title" "$message"
    elif command -v osascript >/dev/null 2>&1; then
        # macOS
        osascript -e "display notification \"$message\" with title \"$title\""
    fi
    
    # 日誌記錄
    log_sync "INFO" "通知: $title - $message"
}

# 檢查同步狀態
check_sync_status() {
    log_info "檢查同步狀態..."
    
    echo "=== 同步系統狀態 ==="
    echo "同步啟用: $SYNC_ENABLED"
    echo "同步間隔: $SYNC_INTERVAL 秒"
    echo "自動應用: $SYNC_AUTO_APPLY"
    echo "備份啟用: $SYNC_BACKUP_ENABLED"
    echo "通知啟用: $SYNC_NOTIFY_ENABLED"
    echo ""
    
    # 檢查版本信息
    local remote_version
    local local_version
    
    if check_network; then
        remote_version=$(get_remote_version)
        local_version=$(get_local_version)
        
        echo "=== 版本信息 ==="
        echo "遠程版本: ${remote_version:-未知}"
        echo "本地版本: ${local_version:-未知}"
        
        if [ -n "$remote_version" ] && [ -n "$local_version" ]; then
            if [ "$remote_version" != "$local_version" ]; then
                echo "狀態: 需要同步 ⚠️"
            else
                echo "狀態: 已是最新 ✅"
            fi
        else
            echo "狀態: 無法確定"
        fi
    else
        echo "=== 版本信息 ==="
        echo "網絡連接失敗，無法檢查版本"
    fi
    
    echo ""
    
    # 檢查最近的同步記錄
    if [ -f "$SYNC_LOG_FILE" ]; then
        echo "=== 最近的同步記錄 ==="
        tail -10 "$SYNC_LOG_FILE"
    fi
}

# 執行完整同步
perform_full_sync() {
    log_sync "INFO" "開始完整同步..."
    
    # 檢查同步鎖
    if ! check_sync_lock; then
        return 1
    fi
    
    # 創建同步鎖
    create_sync_lock
    
    # 設置清理函數
    trap 'remove_sync_lock' EXIT
    
    # 檢查網絡連接
    if ! check_network; then
        return 1
    fi
    
    # 檢查是否需要同步
    if needs_sync; then
        # 同步配置文件
        if sync_config_files; then
            log_sync "INFO" "同步完成"
            return 0
        else
            log_sync "ERROR" "同步失敗"
            return 1
        fi
    else
        log_sync "INFO" "無需同步，已是最新版本"
        return 0
    fi
}

# 啟動同步守護進程
start_sync_daemon() {
    local interval="${1:-$SYNC_INTERVAL}"
    
    log_info "啟動同步守護進程，間隔: $interval 秒"
    
    # 檢查是否已在運行
    if [ -f "$SYNC_CACHE_DIR/daemon.pid" ]; then
        local daemon_pid
        daemon_pid=$(cat "$SYNC_CACHE_DIR/daemon.pid")
        if kill -0 "$daemon_pid" 2>/dev/null; then
            log_warning "同步守護進程已在運行 (PID: $daemon_pid)"
            return 1
        fi
    fi
    
    # 後台運行守護進程
    (
        echo $$ > "$SYNC_CACHE_DIR/daemon.pid"
        log_sync "INFO" "同步守護進程已啟動 (PID: $$)"
        
        while true; do
            if [ "$SYNC_ENABLED" = "true" ]; then
                log_sync "INFO" "執行定期同步檢查..."
                perform_full_sync
            fi
            
            sleep "$interval"
        done
    ) &
    
    log_success "同步守護進程已在後台啟動"
}

# 停止同步守護進程
stop_sync_daemon() {
    if [ -f "$SYNC_CACHE_DIR/daemon.pid" ]; then
        local daemon_pid
        daemon_pid=$(cat "$SYNC_CACHE_DIR/daemon.pid")
        if kill -0 "$daemon_pid" 2>/dev/null; then
            kill "$daemon_pid"
            rm -f "$SYNC_CACHE_DIR/daemon.pid"
            log_success "同步守護進程已停止"
        else
            log_warning "同步守護進程未在運行"
            rm -f "$SYNC_CACHE_DIR/daemon.pid"
        fi
    else
        log_warning "未找到同步守護進程"
    fi
}

# 強制同步
force_sync() {
    log_info "強制執行同步..."
    
    # 清除本地版本記錄以強制同步
    rm -f "$SYNC_CACHE_DIR/local_version"
    
    # 執行同步
    perform_full_sync
}

# 清理同步緩存
cleanup_sync_cache() {
    log_info "清理同步緩存..."
    
    # 停止守護進程
    stop_sync_daemon
    
    # 清理鎖文件
    rm -f "$SYNC_LOCK_FILE"
    
    # 清理舊的備份（保留最近7天）
    if [ -d "$SYNC_CACHE_DIR/backup" ]; then
        find "$SYNC_CACHE_DIR/backup" -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
    fi
    
    # 清理臨時文件
    find "$SYNC_CACHE_DIR" -name "temp_*" -type d -mtime +1 -exec rm -rf {} \; 2>/dev/null || true
    
    log_success "同步緩存清理完成"
}

# 命令行接口
case "${1:-help}" in
    "check")
        check_sync_status
        ;;
    "sync")
        perform_full_sync
        ;;
    "force")
        force_sync
        ;;
    "apply")
        apply_synced_configs
        ;;
    "daemon")
        case "${2:-start}" in
            "start")
                start_sync_daemon "$3"
                ;;
            "stop")
                stop_sync_daemon
                ;;
            "restart")
                stop_sync_daemon
                sleep 2
                start_sync_daemon "$3"
                ;;
            *)
                echo "用法: $0 daemon {start|stop|restart} [間隔秒數]"
                ;;
        esac
        ;;
    "cleanup")
        cleanup_sync_cache
        ;;
    "version")
        echo "遠程版本: $(get_remote_version)"
        echo "本地版本: $(get_local_version)"
        ;;
    *)
        echo "自動同步系統"
        echo ""
        echo "用法: $0 <command> [選項]"
        echo ""
        echo "命令:"
        echo "  check                檢查同步狀態"
        echo "  sync                 執行同步"
        echo "  force                強制同步"
        echo "  apply                應用已下載的配置"
        echo "  daemon start [間隔]  啟動同步守護進程"
        echo "  daemon stop          停止同步守護進程"
        echo "  daemon restart [間隔] 重啟同步守護進程"
        echo "  cleanup              清理同步緩存"
        echo "  version              顯示版本信息"
        echo ""
        echo "環境變數:"
        echo "  SYNC_ENABLED         啟用同步 (true/false)"
        echo "  SYNC_INTERVAL        同步間隔秒數 (預設: 3600)"
        echo "  SYNC_AUTO_APPLY      自動應用配置 (true/false)"
        echo "  SYNC_BACKUP_ENABLED  啟用備份 (true/false)"
        echo "  SYNC_NOTIFY_ENABLED  啟用通知 (true/false)"
        echo ""
        echo "範例:"
        echo "  $0 check             # 檢查同步狀態"
        echo "  $0 sync              # 手動同步"
        echo "  $0 daemon start 1800 # 每30分鐘同步一次"
        echo ""
        echo "日誌文件: $SYNC_LOG_FILE"
        ;;
esac

log_success "########## 自動同步系統執行完成 ##########"