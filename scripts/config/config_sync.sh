#!/usr/bin/env bash

# 進階配置同步系統 - 跨設備配置管理與版本控制

# 載入共用函數庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || exit 1

# 載入配置管理
if [ -f "$SCRIPT_DIR/config_manager_simple.sh" ]; then
    source "$SCRIPT_DIR/config_manager_simple.sh" 2>/dev/null || true
fi

log_info "########## 配置同步系統 ##########"

# 同步配置
readonly SYNC_DIR="$HOME/.config/linux-setting-sync"
readonly SYNC_METADATA_DIR="$SYNC_DIR/.metadata"
readonly SYNC_VERSIONS_DIR="$SYNC_DIR/.versions" 
readonly SYNC_LOG="$HOME/.local/log/config_sync.log"

# 確保目錄存在
mkdir -p "$SYNC_DIR" "$SYNC_METADATA_DIR" "$SYNC_VERSIONS_DIR" "$(dirname "$SYNC_LOG")"

# 可同步的配置文件類型
readonly CONFIG_TYPES="shell theme git editor ssh system tools"

# 配置文件定義
get_config_files() {
    local type="$1"
    case "$type" in
        "shell")
            echo "$HOME/.zshrc $HOME/.bashrc $HOME/.profile $HOME/.aliases"
            ;;
        "theme")
            echo "$HOME/.p10k.zsh"
            ;;
        "git")
            echo "$HOME/.gitconfig $HOME/.gitignore_global"
            ;;
        "editor")
            echo "$HOME/.vimrc $HOME/.config/nvim"
            ;;
        "ssh")
            echo "$HOME/.ssh/config $HOME/.ssh/known_hosts"
            ;;
        "system")
            echo "$HOME/.config/linux-setting"
            ;;
        "tools")
            echo "$HOME/.tmux.conf $HOME/.config/htop"
            ;;
    esac
}

# 設備信息
DEVICE_ID=""
DEVICE_NAME=""
DEVICE_PLATFORM=""

# 初始化設備信息
init_device_info() {
    DEVICE_NAME="$(hostname)"
    DEVICE_PLATFORM="$(uname -s)"
    DEVICE_ID="${DEVICE_NAME}_${DEVICE_PLATFORM}_$(date +%Y%m%d)"
    
    log_info "初始化設備信息: $DEVICE_ID"
    
    # 保存設備信息
    cat > "$SYNC_METADATA_DIR/device_info.json" << EOF
{
    "device_id": "$DEVICE_ID",
    "device_name": "$DEVICE_NAME",
    "device_platform": "$DEVICE_PLATFORM",
    "last_sync": "$(date -Iseconds)",
    "sync_count": 0,
    "created_at": "$(date -Iseconds)"
}
EOF
}

# 記錄同步日誌
log_sync() {
    local level="$1"
    local operation="$2"
    local message="$3"
    local details="${4:-}"
    
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    {
        echo "[$timestamp] [$level] [$DEVICE_ID] [$operation] $message"
        if [ -n "$details" ]; then
            echo "    詳情: $details"
        fi
    } >> "$SYNC_LOG"
    
    # 同時輸出到控制台
    case "$level" in
        "ERROR") log_error "[$operation] $message" ;;
        "WARNING") log_warning "[$operation] $message" ;;
        *) log_info "[$operation] $message" ;;
    esac
}

# 計算文件校驗和
calculate_checksum() {
    local file="$1"
    if [ -f "$file" ]; then
        if command -v sha256sum >/dev/null 2>&1; then
            sha256sum "$file" | cut -d' ' -f1
        else
            shasum -a 256 "$file" | cut -d' ' -f1
        fi
    else
        echo "directory"
    fi
}

# 創建配置快照
create_config_snapshot() {
    local config_type="$1"
    local snapshot_name="${2:-$(date +%Y%m%d_%H%M%S)}"
    
    log_sync "INFO" "SNAPSHOT" "創建 $config_type 配置快照" "$snapshot_name"
    
    local snapshot_dir="$SYNC_VERSIONS_DIR/$config_type/$snapshot_name"
    mkdir -p "$snapshot_dir"
    
    # 獲取配置文件列表
    local files
    files=$(get_config_files "$config_type")
    
    local snapshot_files=0
    for file in $files; do
        if [ -e "$file" ]; then
            local relative_path
            relative_path=$(echo "$file" | sed "s|$HOME|HOME|")
            local target_dir="$snapshot_dir/$(dirname "$relative_path")"
            
            mkdir -p "$target_dir"
            
            if [ -d "$file" ]; then
                cp -r "$file" "$target_dir/"
            else
                cp "$file" "$target_dir/"
            fi
            
            snapshot_files=$((snapshot_files + 1))
            log_sync "INFO" "SNAPSHOT" "已快照文件: $relative_path"
        fi
    done
    
    # 創建快照元數據
    cat > "$snapshot_dir/metadata.json" << EOF
{
    "snapshot_name": "$snapshot_name",
    "config_type": "$config_type",
    "device_id": "$DEVICE_ID",
    "created_at": "$(date -Iseconds)",
    "file_count": $snapshot_files,
    "description": "自動創建的配置快照"
}
EOF
    
    log_sync "INFO" "SNAPSHOT" "配置快照創建完成" "$snapshot_files 個文件已保存到 $snapshot_dir"
    echo "$snapshot_dir"
}

# 恢復配置快照
restore_config_snapshot() {
    local config_type="$1"
    local snapshot_name="$2"
    
    local snapshot_dir="$SYNC_VERSIONS_DIR/$config_type/$snapshot_name"
    
    if [ ! -d "$snapshot_dir" ]; then
        log_sync "ERROR" "RESTORE" "快照不存在" "$snapshot_dir"
        return 1
    fi
    
    log_sync "INFO" "RESTORE" "恢復 $config_type 配置快照" "$snapshot_name"
    
    # 創建當前配置的備份
    create_config_snapshot "$config_type" "backup_before_restore_$(date +%Y%m%d_%H%M%S)"
    
    local restored_files=0
    find "$snapshot_dir" -type f -name "*.json" -prune -o -type f -print | while read -r file; do
        local relative_path
        relative_path=$(echo "$file" | sed "s|$snapshot_dir/||")
        local target_file
        target_file=$(echo "$relative_path" | sed "s|HOME|$HOME|")
        
        # 確保目標目錄存在
        mkdir -p "$(dirname "$target_file")"
        
        # 恢復文件
        cp "$file" "$target_file"
        restored_files=$((restored_files + 1))
        log_sync "INFO" "RESTORE" "已恢復文件: $target_file"
    done
    
    log_sync "INFO" "RESTORE" "配置恢復完成" "$restored_files 個文件已恢復"
}

# 比較配置差異
compare_configs() {
    local config_type="$1"
    local snapshot1="$2"
    local snapshot2="${3:-current}"
    
    log_sync "INFO" "COMPARE" "比較 $config_type 配置" "$snapshot1 vs $snapshot2"
    
    if [ "$snapshot2" = "current" ]; then
        # 與當前配置比較
        local temp_snapshot
        temp_snapshot=$(create_config_snapshot "$config_type" "temp_$(date +%s)")
        snapshot2="temp_$(date +%s)"
    fi
    
    local snapshot1_dir="$SYNC_VERSIONS_DIR/$config_type/$snapshot1"
    local snapshot2_dir="$SYNC_VERSIONS_DIR/$config_type/$snapshot2"
    
    if [ ! -d "$snapshot1_dir" ] || [ ! -d "$snapshot2_dir" ]; then
        log_sync "ERROR" "COMPARE" "快照目錄不存在"
        return 1
    fi
    
    local diff_report="$SYNC_DIR/diff_${config_type}_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "配置差異報告"
        echo "============="
        echo "配置類型: $config_type"
        echo "快照1: $snapshot1"
        echo "快照2: $snapshot2"
        echo "比較時間: $(date)"
        echo ""
        
        # 使用 diff 比較目錄
        if command -v diff >/dev/null 2>&1; then
            diff -ur "$snapshot1_dir" "$snapshot2_dir" || true
        else
            echo "diff 命令不可用，使用基本比較"
            find "$snapshot1_dir" -type f -exec basename {} \; | sort > /tmp/snap1_files
            find "$snapshot2_dir" -type f -exec basename {} \; | sort > /tmp/snap2_files
            
            echo "只在快照1中的文件:"
            comm -23 /tmp/snap1_files /tmp/snap2_files
            echo ""
            echo "只在快照2中的文件:"
            comm -13 /tmp/snap1_files /tmp/snap2_files
            
            rm -f /tmp/snap1_files /tmp/snap2_files
        fi
    } > "$diff_report"
    
    log_sync "INFO" "COMPARE" "差異報告已生成" "$diff_report"
    
    # 顯示簡要差異
    cat "$diff_report"
}

# 同步到遠程倉庫
sync_to_remote() {
    local config_type="$1"
    local remote_url="${2:-$(get_config 'sync_remote_url' '')}"
    
    if [ -z "$remote_url" ]; then
        log_sync "ERROR" "SYNC" "未配置遠程倉庫URL"
        return 1
    fi
    
    log_sync "INFO" "SYNC" "同步 $config_type 到遠程倉庫" "$remote_url"
    
    # 初始化 git 倉庫（如果需要）
    if [ ! -d "$SYNC_DIR/.git" ]; then
        cd "$SYNC_DIR"
        git init
        git remote add origin "$remote_url" 2>/dev/null || true
    fi
    
    # 創建當前快照
    local snapshot_name="sync_$(date +%Y%m%d_%H%M%S)"
    create_config_snapshot "$config_type" "$snapshot_name"
    
    # 提交更改
    cd "$SYNC_DIR"
    git add .
    git commit -m "Sync $config_type config from $DEVICE_ID at $(date)" || true
    
    # 推送到遠程
    if git push origin main 2>/dev/null; then
        log_sync "INFO" "SYNC" "成功同步到遠程倉庫"
    else
        log_sync "WARNING" "SYNC" "推送到遠程倉庫失敗，可能需要手動處理衝突"
    fi
}

# 從遠程倉庫拉取
pull_from_remote() {
    local remote_url="${1:-$(get_config 'sync_remote_url' '')}"
    
    if [ -z "$remote_url" ]; then
        log_sync "ERROR" "PULL" "未配置遠程倉庫URL"
        return 1
    fi
    
    log_sync "INFO" "PULL" "從遠程倉庫拉取配置" "$remote_url"
    
    if [ ! -d "$SYNC_DIR/.git" ]; then
        # 克隆倉庫
        rm -rf "$SYNC_DIR"
        git clone "$remote_url" "$SYNC_DIR"
    else
        # 拉取更新
        cd "$SYNC_DIR"
        git pull origin main || log_sync "WARNING" "PULL" "拉取失敗，可能有衝突"
    fi
    
    log_sync "INFO" "PULL" "配置拉取完成"
}

# 列出可用快照
list_snapshots() {
    local config_type="$1"
    
    log_info "可用的 $config_type 配置快照:"
    echo "=================================="
    
    local snapshot_count=0
    if [ -d "$SYNC_VERSIONS_DIR/$config_type" ]; then
        for snapshot_dir in "$SYNC_VERSIONS_DIR/$config_type"/*; do
            if [ -d "$snapshot_dir" ]; then
                local snapshot_name
                snapshot_name=$(basename "$snapshot_dir")
                
                local metadata_file="$snapshot_dir/metadata.json"
                if [ -f "$metadata_file" ]; then
                    local created_at
                    created_at=$(grep '"created_at"' "$metadata_file" | cut -d'"' -f4)
                    local file_count
                    file_count=$(grep '"file_count"' "$metadata_file" | cut -d':' -f2 | tr -d ' ,')
                    
                    printf "%-25s %s (%s files)\n" "$snapshot_name" "$created_at" "$file_count"
                else
                    printf "%-25s %s\n" "$snapshot_name" "無元數據"
                fi
                
                snapshot_count=$((snapshot_count + 1))
            fi
        done
    fi
    
    if [ $snapshot_count -eq 0 ]; then
        echo "沒有找到任何快照"
    else
        echo ""
        echo "總計: $snapshot_count 個快照"
    fi
}

# 清理舊快照
cleanup_old_snapshots() {
    local config_type="$1"
    local keep_count="${2:-10}"
    
    log_sync "INFO" "CLEANUP" "清理舊的 $config_type 快照" "保留最新 $keep_count 個"
    
    if [ ! -d "$SYNC_VERSIONS_DIR/$config_type" ]; then
        return 0
    fi
    
    # 獲取按時間排序的快照列表
    local snapshots
    snapshots=$(find "$SYNC_VERSIONS_DIR/$config_type" -maxdepth 1 -type d -name "*" | sort -r)
    
    local count=0
    local removed=0
    echo "$snapshots" | while read -r snapshot_dir; do
        if [ "$(basename "$snapshot_dir")" = "$config_type" ]; then
            continue
        fi
        
        count=$((count + 1))
        if [ $count -gt $keep_count ]; then
            local snapshot_name
            snapshot_name=$(basename "$snapshot_dir")
            rm -rf "$snapshot_dir"
            removed=$((removed + 1))
            log_sync "INFO" "CLEANUP" "已刪除舊快照: $snapshot_name"
        fi
    done
    
    log_sync "INFO" "CLEANUP" "清理完成" "刪除了 $removed 個舊快照"
}

# 自動備份配置
auto_backup() {
    local config_type="$1"
    
    log_sync "INFO" "AUTO_BACKUP" "執行自動備份" "$config_type"
    
    # 檢查是否需要備份（基於時間間隔）
    local last_backup_file="$SYNC_METADATA_DIR/last_backup_${config_type}"
    local current_time
    current_time=$(date +%s)
    local backup_interval=86400  # 24小時
    
    if [ -f "$last_backup_file" ]; then
        local last_backup_time
        last_backup_time=$(cat "$last_backup_file")
        local time_diff=$((current_time - last_backup_time))
        
        if [ $time_diff -lt $backup_interval ]; then
            log_sync "INFO" "AUTO_BACKUP" "距離上次備份時間不足，跳過" "$time_diff 秒"
            return 0
        fi
    fi
    
    # 執行備份
    create_config_snapshot "$config_type" "auto_backup_$(date +%Y%m%d_%H%M%S)"
    
    # 更新最後備份時間
    echo "$current_time" > "$last_backup_file"
    
    # 清理舊備份
    cleanup_old_snapshots "$config_type" 5
}

# 監控配置文件變化
monitor_config_changes() {
    local config_type="$1"
    local interval="${2:-60}"  # 預設60秒
    
    log_sync "INFO" "MONITOR" "開始監控 $config_type 配置變化" "間隔: $interval 秒"
    
    # 創建初始快照
    local last_snapshot
    last_snapshot=$(create_config_snapshot "$config_type" "monitor_initial_$(date +%s)")
    
    while true; do
        sleep "$interval"
        
        # 創建當前快照
        local current_snapshot
        current_snapshot=$(create_config_snapshot "$config_type" "monitor_current_$(date +%s)")
        
        # 比較變化
        local diff_output
        diff_output=$(compare_configs "$config_type" "$(basename "$last_snapshot")" "$(basename "$current_snapshot")" 2>/dev/null)
        
        if [ -n "$diff_output" ]; then
            log_sync "INFO" "MONITOR" "檢測到 $config_type 配置變化"
            # 可以在這裡添加自動備份或通知邏輯
            auto_backup "$config_type"
        fi
        
        # 清理臨時快照
        rm -rf "$current_snapshot" 2>/dev/null
        last_snapshot="$current_snapshot"
    done
}

# 生成同步報告
generate_sync_report() {
    local report_file="$SYNC_DIR/sync_report_$(date +%Y%m%d_%H%M%S).html"
    
    {
        cat << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>配置同步報告</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .header { background: #2c3e50; color: white; padding: 20px; border-radius: 8px; }
        .section { background: white; margin: 20px 0; padding: 15px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .config-type { background: #3498db; color: white; padding: 10px; border-radius: 5px; display: inline-block; margin: 5px; }
        .snapshot-item { border-left: 4px solid #3498db; padding: 10px; margin: 10px 0; background: #f8f9fa; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #34495e; color: white; }
        .device-info { background: #e8f6f3; padding: 10px; border-radius: 5px; }
    </style>
</head>
<body>
EOF
        
        echo "<div class='header'>"
        echo "<h1>🔄 配置同步報告</h1>"
        echo "<p>生成時間: $(date)</p>"
        echo "<p>設備: $DEVICE_ID</p>"
        echo "</div>"
        
        echo "<div class='section'>"
        echo "<h2>📱 設備信息</h2>"
        if [ -f "$SYNC_METADATA_DIR/device_info.json" ]; then
            echo "<div class='device-info'>"
            echo "<p><strong>設備名稱:</strong> $DEVICE_NAME</p>"
            echo "<p><strong>平台:</strong> $DEVICE_PLATFORM</p>"
            echo "<p><strong>設備ID:</strong> $DEVICE_ID</p>"
            echo "</div>"
        fi
        echo "</div>"
        
        echo "<div class='section'>"
        echo "<h2>📂 配置類型和快照</h2>"
        for config_type in $CONFIG_TYPES; do
            echo "<div class='config-type'>$config_type</div>"
            
            if [ -d "$SYNC_VERSIONS_DIR/$config_type" ]; then
                local snapshot_count
                snapshot_count=$(find "$SYNC_VERSIONS_DIR/$config_type" -maxdepth 1 -type d | wc -l)
                snapshot_count=$((snapshot_count - 1))  # 減去父目錄
                
                echo "<p>快照數量: $snapshot_count</p>"
                
                echo "<div style='margin-left: 20px;'>"
                for snapshot_dir in "$SYNC_VERSIONS_DIR/$config_type"/*; do
                    if [ -d "$snapshot_dir" ]; then
                        local snapshot_name
                        snapshot_name=$(basename "$snapshot_dir")
                        
                        echo "<div class='snapshot-item'>"
                        echo "<strong>$snapshot_name</strong>"
                        
                        if [ -f "$snapshot_dir/metadata.json" ]; then
                            local created_at
                            created_at=$(grep '"created_at"' "$snapshot_dir/metadata.json" | cut -d'"' -f4)
                            local file_count
                            file_count=$(grep '"file_count"' "$snapshot_dir/metadata.json" | cut -d':' -f2 | tr -d ' ,')
                            echo " - $created_at ($file_count 文件)"
                        fi
                        echo "</div>"
                    fi
                done
                echo "</div>"
            else
                echo "<p>無快照</p>"
            fi
        done
        echo "</div>"
        
        echo "<div class='section'>"
        echo "<h2>📊 同步統計</h2>"
        if [ -f "$SYNC_LOG" ]; then
            echo "<p><strong>最近的同步活動:</strong></p>"
            echo "<pre style='background: #f4f4f4; padding: 10px; border-radius: 4px; overflow-x: auto;'>"
            tail -20 "$SYNC_LOG"
            echo "</pre>"
        fi
        echo "</div>"
        
        echo "</body></html>"
        
    } > "$report_file"
    
    log_sync "INFO" "REPORT" "同步報告已生成" "$report_file"
    echo "$report_file"
}

# 命令行接口
main() {
    # 初始化設備信息
    init_device_info
    
    case "${1:-help}" in
        "snapshot"|"backup")
            if [ -z "$2" ]; then
                log_error "請指定配置類型: $CONFIG_TYPES"
                exit 1
            fi
            create_config_snapshot "$2" "${3:-$(date +%Y%m%d_%H%M%S)}"
            ;;
        "restore")
            if [ -z "$2" ] || [ -z "$3" ]; then
                log_error "用法: $0 restore <config_type> <snapshot_name>"
                exit 1
            fi
            restore_config_snapshot "$2" "$3"
            ;;
        "list")
            if [ -z "$2" ]; then
                log_error "請指定配置類型: $CONFIG_TYPES"
                exit 1
            fi
            list_snapshots "$2"
            ;;
        "compare"|"diff")
            if [ -z "$2" ] || [ -z "$3" ]; then
                log_error "用法: $0 compare <config_type> <snapshot1> [snapshot2]"
                exit 1
            fi
            compare_configs "$2" "$3" "$4"
            ;;
        "sync"|"push")
            if [ -z "$2" ]; then
                log_error "請指定配置類型: $CONFIG_TYPES"
                exit 1
            fi
            sync_to_remote "$2" "$3"
            ;;
        "pull")
            pull_from_remote "$2"
            ;;
        "monitor")
            if [ -z "$2" ]; then
                log_error "請指定配置類型: $CONFIG_TYPES"
                exit 1
            fi
            monitor_config_changes "$2" "${3:-60}"
            ;;
        "cleanup")
            if [ -z "$2" ]; then
                log_error "請指定配置類型: $CONFIG_TYPES"
                exit 1
            fi
            cleanup_old_snapshots "$2" "${3:-10}"
            ;;
        "auto-backup")
            if [ -z "$2" ]; then
                log_error "請指定配置類型: $CONFIG_TYPES"
                exit 1
            fi
            auto_backup "$2"
            ;;
        "report")
            generate_sync_report
            ;;
        "status")
            log_info "配置同步系統狀態:"
            echo "===================="
            echo "設備ID: $DEVICE_ID"
            echo "同步目錄: $SYNC_DIR"
            echo "日誌文件: $SYNC_LOG"
            echo ""
            echo "支援的配置類型: $CONFIG_TYPES"
            echo ""
            
            for config_type in $CONFIG_TYPES; do
                if [ -d "$SYNC_VERSIONS_DIR/$config_type" ]; then
                    local count
                    count=$(find "$SYNC_VERSIONS_DIR/$config_type" -maxdepth 1 -type d | wc -l)
                    count=$((count - 1))
                    echo "  $config_type: $count 個快照"
                else
                    echo "  $config_type: 0 個快照"
                fi
            done
            ;;
        *)
            echo "進階配置同步系統"
            echo ""
            echo "用法: $0 <command> [選項...]"
            echo ""
            echo "快照管理:"
            echo "  snapshot <type> [name]     創建配置快照"
            echo "  restore <type> <name>      恢復配置快照"
            echo "  list <type>               列出可用快照"
            echo "  compare <type> <s1> [s2]  比較配置差異"
            echo "  cleanup <type> [count]    清理舊快照"
            echo ""
            echo "遠程同步:"
            echo "  sync <type> [url]         同步到遠程倉庫"
            echo "  pull [url]                從遠程拉取"
            echo ""
            echo "監控與自動化:"
            echo "  monitor <type> [interval] 監控配置變化"
            echo "  auto-backup <type>        自動備份"
            echo ""
            echo "報告與狀態:"
            echo "  status                    顯示系統狀態"
            echo "  report                    生成HTML報告"
            echo ""
            echo "支援的配置類型: $CONFIG_TYPES"
            echo ""
            echo "範例:"
            echo "  $0 snapshot shell                    # 快照shell配置"
            echo "  $0 restore shell 20231215_120000     # 恢復shell快照"
            echo "  $0 sync git https://github.com/user/dotfiles.git  # 同步git配置"
            echo "  $0 monitor system 300                # 每5分鐘監控系統配置"
            echo ""
            echo "日誌文件: $SYNC_LOG"
            echo "同步目錄: $SYNC_DIR"
            ;;
    esac
}

# 執行主函數
main "$@"

log_success "########## 配置同步系統執行完成 ##########"

# 記錄同步日誌
log_sync() {
    local operation="$1"
    local file="$2" 
    local status="$3"
    local details="${4:-}"
    
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    {
        echo "[$timestamp] [$DEVICE_ID] [$operation] $file - $status"
        if [ -n "$details" ]; then
            echo "    詳情: $details"
        fi
    } >> "$SYNC_LOG"
}

# 計算文件哈希值
calculate_file_hash() {
    local file="$1"
    
    if [ -f "$file" ]; then
        if command -v sha256sum >/dev/null 2>&1; then
            sha256sum "$file" | cut -d' ' -f1
        else
            # macOS 兼容性
            shasum -a 256 "$file" | cut -d' ' -f1
        fi
    else
        echo "FILE_NOT_FOUND"
    fi
}

# 創建配置文件版本
create_config_version() {
    local config_file="$1"
    local config_type="$2"
    
    if [ ! -f "$config_file" ]; then
        log_sync "VERSION" "$config_file" "SKIPPED" "文件不存在"
        return 1
    fi
    
    local hash
    hash=$(calculate_file_hash "$config_file")
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local version_file="$SYNC_VERSIONS_DIR/${config_type}_${timestamp}_${hash:0:8}"
    
    # 複製文件到版本目錄
    cp "$config_file" "$version_file"
    
    # 創建版本元數據
    cat > "${version_file}.meta" << EOF
{
    "original_path": "$config_file",
    "config_type": "$config_type",
    "device_id": "$DEVICE_ID",
    "hash": "$hash",
    "timestamp": "$timestamp",
    "created": "$(date -Iseconds)"
}
EOF

    log_sync "VERSION" "$config_file" "SUCCESS" "版本: ${timestamp}"
    echo "$version_file"
}

# 備份配置文件
backup_config_type() {
    local config_type="$1"
    
    if [ -z "${SYNC_CONFIG_TYPES[$config_type]}" ]; then
        log_error "未知的配置類型: $config_type"
        return 1
    fi
    
    log_info "備份 $config_type 配置..."
    
    local config_files="${SYNC_CONFIG_TYPES[$config_type]}"
    local backup_count=0
    
    # 創建類型特定的備份目錄
    local type_backup_dir="$SYNC_DIR/$config_type"
    mkdir -p "$type_backup_dir"
    
    for config_file in $config_files; do
        if [ -f "$config_file" ]; then
            local filename
            filename=$(basename "$config_file")
            local backup_file="$type_backup_dir/$filename"
            
            # 檢查是否需要更新
            local current_hash
            current_hash=$(calculate_file_hash "$config_file")
            local last_hash=""
            
            if [ -f "${backup_file}.hash" ]; then
                last_hash=$(cat "${backup_file}.hash")
            fi
            
            if [ "$current_hash" != "$last_hash" ]; then
                # 創建版本
                create_config_version "$config_file" "$config_type"
                
                # 備份到同步目錄
                cp "$config_file" "$backup_file"
                echo "$current_hash" > "${backup_file}.hash"
                
                log_sync "BACKUP" "$config_file" "SUCCESS" "哈希: ${current_hash:0:8}"
                backup_count=$((backup_count + 1))
            else
                log_sync "BACKUP" "$config_file" "SKIPPED" "無變化"
            fi
        elif [ -d "$config_file" ]; then
            # 處理目錄
            local dirname
            dirname=$(basename "$config_file")
            local backup_dir="$type_backup_dir/$dirname"
            
            # 同步整個目錄
            rsync -a "$config_file/" "$backup_dir/" 2>/dev/null && \
                log_sync "BACKUP" "$config_file" "SUCCESS" "目錄同步" || \
                log_sync "BACKUP" "$config_file" "FAILED" "目錄同步失敗"
        fi
    done
    
    log_success "$config_type 配置備份完成，處理了 $backup_count 個文件"
    return 0
}

# 恢復配置文件
restore_config_type() {
    local config_type="$1"
    local force="${2:-false}"
    
    if [ -z "${SYNC_CONFIG_TYPES[$config_type]}" ]; then
        log_error "未知的配置類型: $config_type"
        return 1
    fi
    
    log_info "恢復 $config_type 配置..."
    
    local type_backup_dir="$SYNC_DIR/$config_type"
    if [ ! -d "$type_backup_dir" ]; then
        log_error "找不到 $config_type 的備份"
        return 1
    fi
    
    local config_files="${SYNC_CONFIG_TYPES[$config_type]}"
    local restore_count=0
    
    for config_file in $config_files; do
        local filename
        filename=$(basename "$config_file")
        local backup_file="$type_backup_dir/$filename"
        
        if [ -f "$backup_file" ]; then
            # 備份現有文件
            if [ -f "$config_file" ] && [ "$force" != "true" ]; then
                local backup_original="${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
                cp "$config_file" "$backup_original"
                log_info "原文件已備份到: $backup_original"
            fi
            
            # 恢復文件
            mkdir -p "$(dirname "$config_file")"
            cp "$backup_file" "$config_file"
            
            log_sync "RESTORE" "$config_file" "SUCCESS" "從備份恢復"
            restore_count=$((restore_count + 1))
            
        elif [ -d "$backup_file" ]; then
            # 恢復目錄
            mkdir -p "$config_file"
            rsync -a "$backup_file/" "$config_file/" && \
                log_sync "RESTORE" "$config_file" "SUCCESS" "目錄恢復" || \
                log_sync "RESTORE" "$config_file" "FAILED" "目錄恢復失敗"
        fi
    done
    
    log_success "$config_type 配置恢復完成，處理了 $restore_count 個文件"
    return 0
}

# 列出可用的配置版本
list_config_versions() {
    local config_type="$1"
    
    log_info "可用的 $config_type 配置版本:"
    
    local versions=()
    for version_file in "$SYNC_VERSIONS_DIR"/${config_type}_*; do
        if [ -f "$version_file" ] && [[ "$version_file" != *.meta ]]; then
            local meta_file="${version_file}.meta"
            if [ -f "$meta_file" ]; then
                local timestamp
                timestamp=$(basename "$version_file" | cut -d'_' -f2-3)
                local hash
                hash=$(basename "$version_file" | cut -d'_' -f4)
                
                echo "  版本: ${timestamp} (哈希: ${hash})"
                echo "    文件: $version_file"
                if command -v jq >/dev/null 2>&1; then
                    local created
                    created=$(jq -r '.created' "$meta_file" 2>/dev/null || echo "未知")
                    echo "    創建: $created"
                fi
                echo ""
                
                versions+=("$version_file")
            fi
        fi
    done
    
    if [ ${#versions[@]} -eq 0 ]; then
        log_warning "沒有找到 $config_type 的配置版本"
        return 1
    fi
    
    log_info "總共找到 ${#versions[@]} 個版本"
    return 0
}

# 同步狀態檢查
check_sync_status() {
    log_info "檢查配置同步狀態..."
    
    init_device_info
    
    for config_type in "${!SYNC_CONFIG_TYPES[@]}"; do
        echo ""
        log_info "=== $config_type 配置狀態 ==="
        
        local type_backup_dir="$SYNC_DIR/$config_type"
        local config_files="${SYNC_CONFIG_TYPES[$config_type]}"
        
        for config_file in $config_files; do
            if [ -f "$config_file" ]; then
                local current_hash
                current_hash=$(calculate_file_hash "$config_file")
                local filename
                filename=$(basename "$config_file")
                local backup_file="$type_backup_dir/$filename"
                
                if [ -f "$backup_file" ]; then
                    local backup_hash
                    if [ -f "${backup_file}.hash" ]; then
                        backup_hash=$(cat "${backup_file}.hash")
                    else
                        backup_hash=$(calculate_file_hash "$backup_file")
                    fi
                    
                    if [ "$current_hash" = "$backup_hash" ]; then
                        echo "✅ $config_file: 已同步"
                    else
                        echo "⚠️  $config_file: 需要同步 (已修改)"
                    fi
                else
                    echo "❌ $config_file: 未備份"
                fi
            elif [ -d "$config_file" ]; then
                local backup_dir="$type_backup_dir/$(basename "$config_file")"
                if [ -d "$backup_dir" ]; then
                    echo "✅ $config_file: 目錄已備份"
                else
                    echo "❌ $config_file: 目錄未備份"
                fi
            else
                echo "⚪ $config_file: 不存在"
            fi
        done
    done
    
    echo ""
    log_info "同步日誌: $SYNC_LOG"
    log_info "版本目錄: $SYNC_VERSIONS_DIR"
}

# 自動同步所有配置
sync_all_configs() {
    log_info "自動同步所有配置..."
    
    init_device_info
    
    local total_backups=0
    for config_type in "${!SYNC_CONFIG_TYPES[@]}"; do
        backup_config_type "$config_type"
        total_backups=$((total_backups + 1))
    done
    
    # 更新最後同步時間
    local device_info="$SYNC_METADATA_DIR/device_info.json"
    if [ -f "$device_info" ]; then
        # 創建更新的設備信息
        cat > "${device_info}.tmp" << EOF
{
    "device_id": "$DEVICE_ID",
    "device_name": "$DEVICE_NAME", 
    "platform": "$DEVICE_PLATFORM",
    "created": "$(date -Iseconds)",
    "last_sync": "$(date -Iseconds)"
}
EOF
        mv "${device_info}.tmp" "$device_info"
    fi
    
    log_success "所有配置同步完成，處理了 $total_backups 種配置類型"
}

# 清理舊版本
cleanup_old_versions() {
    local keep_days="${1:-30}"
    
    log_info "清理 $keep_days 天前的舊版本..."
    
    local cleaned_count=0
    
    # 查找並刪除過期的版本文件
    find "$SYNC_VERSIONS_DIR" -type f -mtime +$keep_days -name "*.meta" | while read -r meta_file; do
        local version_file="${meta_file%.meta}"
        if [ -f "$version_file" ]; then
            rm -f "$version_file" "$meta_file"
            cleaned_count=$((cleaned_count + 1))
            log_info "已清理過期版本: $(basename "$version_file")"
        fi
    done
    
    log_success "清理完成，刪除了 $cleaned_count 個舊版本"
}

# 導出配置
export_configs() {
    local export_dir="$1"
    local config_type="${2:-all}"
    
    if [ -z "$export_dir" ]; then
        log_error "請指定導出目錄"
        return 1
    fi
    
    mkdir -p "$export_dir"
    
    if [ "$config_type" = "all" ]; then
        log_info "導出所有配置到: $export_dir"
        cp -r "$SYNC_DIR"/* "$export_dir/"
    else
        if [ -z "${SYNC_CONFIG_TYPES[$config_type]}" ]; then
            log_error "未知的配置類型: $config_type"
            return 1
        fi
        
        log_info "導出 $config_type 配置到: $export_dir"
        local type_backup_dir="$SYNC_DIR/$config_type"
        if [ -d "$type_backup_dir" ]; then
            cp -r "$type_backup_dir" "$export_dir/"
        else
            log_warning "$config_type 配置備份不存在"
            return 1
        fi
    fi
    
    log_success "配置導出完成"
}

# 命令行接口
case "${1:-help}" in
    "init")
        init_device_info
        log_success "配置同步系統已初始化"
        ;;
    "status")
        check_sync_status
        ;;
    "backup")
        if [ -z "$2" ]; then
            sync_all_configs
        else
            backup_config_type "$2"
        fi
        ;;
    "restore")
        if [ -z "$2" ]; then
            log_error "請指定要恢復的配置類型"
            echo "可用類型: ${!SYNC_CONFIG_TYPES[*]}"
            exit 1
        fi
        restore_config_type "$2" "$3"
        ;;
    "versions")
        if [ -z "$2" ]; then
            log_error "請指定配置類型"
            echo "可用類型: ${!SYNC_CONFIG_TYPES[*]}"
            exit 1
        fi
        list_config_versions "$2"
        ;;
    "cleanup")
        cleanup_old_versions "${2:-30}"
        ;;
    "export")
        if [ -z "$2" ]; then
            log_error "請指定導出目錄"
            exit 1
        fi
        export_configs "$2" "$3"
        ;;
    "sync")
        sync_all_configs
        ;;
    "types")
        log_info "支援的配置類型:"
        for config_type in "${!SYNC_CONFIG_TYPES[@]}"; do
            echo "  $config_type: ${SYNC_CONFIG_TYPES[$config_type]}"
        done
        ;;
    *)
        echo "進階配置同步系統"
        echo ""
        echo "用法: $0 <command> [選項]"
        echo ""
        echo "命令:"
        echo "  init                     初始化同步系統"
        echo "  status                   檢查同步狀態"
        echo "  backup [type]           備份配置 (不指定類型則備份全部)"
        echo "  restore <type> [force]  恢復配置"
        echo "  versions <type>         列出配置版本"
        echo "  cleanup [days]          清理舊版本 (預設30天)"
        echo "  export <dir> [type]     導出配置到目錄"
        echo "  sync                    同步所有配置"
        echo "  types                   顯示支援的配置類型"
        echo ""
        echo "配置類型:"
        for config_type in "${!SYNC_CONFIG_TYPES[@]}"; do
            echo "  $config_type"
        done
        echo ""
        echo "範例:"
        echo "  $0 backup shell          # 備份 shell 配置"
        echo "  $0 restore git           # 恢復 git 配置"
        echo "  $0 export /tmp/config    # 導出所有配置"
        echo "  $0 versions editor       # 查看編輯器配置版本"
        echo ""
        echo "同步目錄: $SYNC_DIR"
        echo "日誌文件: $SYNC_LOG"
        ;;
esac

log_success "########## 配置同步系統執行完成 ##########"

# 生成配置差異報告
generate_diff_report() {
    local backup_dir="$1"
    local report_file="$SYNC_DIR/diff_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "配置差異報告"
        echo "生成時間: $(date)"
        echo "設備: $(cat "$SYNC_DIR/device_id" 2>/dev/null || echo "未知")"
        echo "========================================="
        
        for config in "${CONFIG_FILES[@]}"; do
            local config_name
            config_name=$(basename "$config")
            
            echo ""
            echo "檔案: $config_name"
            echo "---------------------"
            
            if [ -f "$config" ] && [ -f "$backup_dir/$config_name" ]; then
                if diff -q "$config" "$backup_dir/$config_name" >/dev/null; then
                    echo "無變化"
                else
                    echo "發現變化:"
                    diff -u "$backup_dir/$config_name" "$config" || true
                fi
            elif [ -f "$config" ]; then
                echo "新檔案（備份中不存在）"
            elif [ -f "$backup_dir/$config_name" ]; then
                echo "檔案已刪除"
            else
                echo "檔案不存在"
            fi
        done
    } > "$report_file"
    
    echo "$report_file"
}

# 雲端同步集成（示例）
cloud_sync() {
    local action="$1"  # upload/download
    local cloud_service="$2"  # git/dropbox/gdrive
    
    case "$cloud_service" in
        "git")
            git_sync "$action"
            ;;
        "dropbox")
            dropbox_sync "$action"
            ;;
        *)
            log_error "不支援的雲端服務: $cloud_service"
            return 1
            ;;
    esac
}

# Git 同步
git_sync() {
    local action="$1"
    local git_repo="$LINUX_SETTING_SYNC_REPO"
    
    if [ -z "$git_repo" ]; then
        log_error "請設定環境變數 LINUX_SETTING_SYNC_REPO"
        return 1
    fi
    
    case "$action" in
        "upload")
            backup_configs
            cd "$SYNC_DIR" || return 1
            
            if [ ! -d ".git" ]; then
                git init
                git remote add origin "$git_repo"
            fi
            
            git add .
            git commit -m "配置同步 - $(hostname) - $(date)"
            git push origin main
            ;;
        "download")
            if [ -d "$SYNC_DIR/.git" ]; then
                cd "$SYNC_DIR" && git pull
            else
                git clone "$git_repo" "$SYNC_DIR"
            fi
            ;;
    esac
}

# 命令行接口
case "${1:-help}" in
    "init")
        init_sync
        ;;
    "backup")
        backup_configs
        ;;
    "diff")
        if [ -z "$2" ]; then
            log_error "請指定備份目錄"
            exit 1
        fi
        report_file=$(generate_diff_report "$2")
        echo "差異報告: $report_file"
        ;;
    "cloud-upload")
        cloud_sync "upload" "${2:-git}"
        ;;
    "cloud-download")
        cloud_sync "download" "${2:-git}"
        ;;
    *)
        echo "配置同步系統"
        echo ""
        echo "用法: $0 <command>"
        echo ""
        echo "命令:"
        echo "  init                 初始化同步系統"
        echo "  backup              備份當前配置"
        echo "  diff <backup_dir>   生成差異報告"
        echo "  cloud-upload        上傳到雲端"
        echo "  cloud-download      從雲端下載"
        echo ""
        echo "環境變數:"
        echo "  LINUX_SETTING_SYNC_REPO  Git 同步倉庫 URL"
        ;;
esac
