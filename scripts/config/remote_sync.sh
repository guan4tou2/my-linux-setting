#!/usr/bin/env bash

# 遠程配置同步系統 - 多設備間配置同步

# 載入共用函數庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || exit 1
if [ -f "$SCRIPT_DIR/config_manager_simple.sh" ]; then
    source "$SCRIPT_DIR/config_manager_simple.sh" 2>/dev/null || true
fi

log_info "########## 遠程配置同步系統 ##########"

readonly REMOTE_SYNC_CONFIG_DIR="$HOME/.config/linux-setting/remote-sync"
readonly REMOTE_SYNC_CACHE_DIR="$HOME/.cache/linux-setting/remote-sync"
readonly REMOTE_SYNC_LOG_FILE="$HOME/.local/log/linux-setting/remote_sync_$(date +%Y%m%d).log"
readonly DEVICE_ID_FILE="$REMOTE_SYNC_CONFIG_DIR/device_id"
readonly SYNC_MANIFEST_FILE="$REMOTE_SYNC_CACHE_DIR/sync_manifest.json"

# 確保目錄存在
mkdir -p "$REMOTE_SYNC_CONFIG_DIR"
mkdir -p "$REMOTE_SYNC_CACHE_DIR"
mkdir -p "$(dirname "$REMOTE_SYNC_LOG_FILE")"

# 同步配置
REMOTE_SYNC_ENABLED="${REMOTE_SYNC_ENABLED:-false}"
SYNC_SERVER_URL="${SYNC_SERVER_URL:-}"
SYNC_TOKEN="${SYNC_TOKEN:-}"
SYNC_ENCRYPTION_ENABLED="${SYNC_ENCRYPTION_ENABLED:-true}"
SYNC_COMPRESSION_ENABLED="${SYNC_COMPRESSION_ENABLED:-true}"
CONFLICT_RESOLUTION="${CONFLICT_RESOLUTION:-merge}"  # merge, local, remote, ask

# 支援的同步項目
SYNC_ITEMS=(
    "bashrc:$HOME/.bashrc"
    "zshrc:$HOME/.zshrc"
    "gitconfig:$HOME/.gitconfig"
    "vimrc:$HOME/.vimrc"
    "ssh_config:$HOME/.ssh/config"
    "linux_setting_config:$HOME/.config/linux-setting"
    "aliases:$HOME/.bash_aliases"
    "env_vars:$HOME/.profile"
)

# 記錄同步日誌
log_remote_sync() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" >> "$REMOTE_SYNC_LOG_FILE"
    
    case "$level" in
        "ERROR") log_error "$message" ;;
        "WARN") log_warning "$message" ;;
        "INFO") log_info "$message" ;;
        *) log_debug "$message" ;;
    esac
}

# 生成或獲取設備ID
get_device_id() {
    if [ -f "$DEVICE_ID_FILE" ]; then
        cat "$DEVICE_ID_FILE"
    else
        local device_id
        device_id="$(hostname)-$(date +%s)-$(openssl rand -hex 4 2>/dev/null || echo $RANDOM)"
        echo "$device_id" > "$DEVICE_ID_FILE"
        log_remote_sync "INFO" "生成新設備ID: $device_id"
        echo "$device_id"
    fi
}

# 檢查同步配置
check_sync_config() {
    if [ "$REMOTE_SYNC_ENABLED" != "true" ]; then
        log_remote_sync "WARN" "遠程同步未啟用"
        return 1
    fi
    
    if [ -z "$SYNC_SERVER_URL" ]; then
        log_remote_sync "ERROR" "未設定同步服務器 URL"
        return 1
    fi
    
    if [ -z "$SYNC_TOKEN" ]; then
        log_remote_sync "ERROR" "未設定同步令牌"
        return 1
    fi
    
    return 0
}

# 加密文件
encrypt_file() {
    local input_file="$1"
    local output_file="$2"
    local password="${SYNC_TOKEN:-default}"
    
    if [ "$SYNC_ENCRYPTION_ENABLED" = "true" ] && command -v openssl >/dev/null 2>&1; then
        openssl enc -aes-256-cbc -salt -in "$input_file" -out "$output_file" -pass pass:"$password"
        return $?
    else
        cp "$input_file" "$output_file"
        return $?
    fi
}

# 解密文件
decrypt_file() {
    local input_file="$1"
    local output_file="$2"
    local password="${SYNC_TOKEN:-default}"
    
    if [ "$SYNC_ENCRYPTION_ENABLED" = "true" ] && command -v openssl >/dev/null 2>&1; then
        openssl enc -aes-256-cbc -d -in "$input_file" -out "$output_file" -pass pass:"$password"
        return $?
    else
        cp "$input_file" "$output_file"
        return $?
    fi
}

# 壓縮文件
compress_file() {
    local input_file="$1"
    local output_file="$2"
    
    if [ "$SYNC_COMPRESSION_ENABLED" = "true" ] && command -v gzip >/dev/null 2>&1; then
        gzip -c "$input_file" > "$output_file"
        return $?
    else
        cp "$input_file" "$output_file"
        return $?
    fi
}

# 解壓縮文件
decompress_file() {
    local input_file="$1"
    local output_file="$2"
    
    if [ "$SYNC_COMPRESSION_ENABLED" = "true" ] && command -v gzip >/dev/null 2>&1; then
        if [[ "$input_file" == *.gz ]]; then
            gzip -dc "$input_file" > "$output_file"
            return $?
        fi
    fi
    
    cp "$input_file" "$output_file"
    return $?
}

# 計算文件哈希
calculate_file_hash() {
    local file="$1"
    
    if [ ! -f "$file" ]; then
        echo "missing"
        return
    fi
    
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | cut -d' ' -f1
    else
        # 使用文件大小和修改時間作為簡單的哈希
        stat -c "%s-%Y" "$file" 2>/dev/null || stat -f "%z-%m" "$file" 2>/dev/null || echo "unknown"
    fi
}

# 生成同步清單
generate_sync_manifest() {
    local manifest_file="$1"
    local device_id
    device_id=$(get_device_id)
    
    {
        echo "{"
        echo "  \"device_id\": \"$device_id\","
        echo "  \"hostname\": \"$(hostname)\","
        echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
        echo "  \"files\": {"
        
        local first=true
        for item in "${SYNC_ITEMS[@]}"; do
            local name="${item%:*}"
            local path="${item#*:}"
            
            if [ "$first" = "true" ]; then
                first=false
            else
                echo ","
            fi
            
            local hash
            local size=0
            local mtime=""
            
            if [ -f "$path" ]; then
                hash=$(calculate_file_hash "$path")
                size=$(stat -c "%s" "$path" 2>/dev/null || stat -f "%z" "$path" 2>/dev/null || echo 0)
                mtime=$(stat -c "%Y" "$path" 2>/dev/null || stat -f "%m" "$path" 2>/dev/null || echo 0)
            elif [ -d "$path" ]; then
                # 對於目錄，計算內容的組合哈希
                hash=$(find "$path" -type f -exec sha256sum {} \; 2>/dev/null | sha256sum | cut -d' ' -f1 || echo "unknown")
                size=$(du -s "$path" 2>/dev/null | cut -f1 || echo 0)
                mtime=$(stat -c "%Y" "$path" 2>/dev/null || stat -f "%m" "$path" 2>/dev/null || echo 0)
            else
                hash="missing"
            fi
            
            printf "    \"%s\": {\"hash\": \"%s\", \"size\": %d, \"mtime\": %s}" "$name" "$hash" "$size" "$mtime"
        done
        
        echo ""
        echo "  }"
        echo "}"
    } > "$manifest_file"
}

# 比較同步清單
compare_manifests() {
    local local_manifest="$1"
    local remote_manifest="$2"
    local diff_file="$3"
    
    if [ ! -f "$local_manifest" ] || [ ! -f "$remote_manifest" ]; then
        log_remote_sync "ERROR" "清單文件不存在"
        return 1
    fi
    
    # 簡單的JSON解析（使用grep和awk）
    {
        echo "{"
        echo "  \"conflicts\": [],"
        echo "  \"local_newer\": [],"
        echo "  \"remote_newer\": [],"
        echo "  \"missing_local\": [],"
        echo "  \"missing_remote\": []"
        echo "}"
    } > "$diff_file"
    
    # 實際比較邏輯會更複雜，這裡簡化處理
    log_remote_sync "INFO" "清單比較完成"
}

# 打包同步文件
pack_sync_files() {
    local pack_file="$1"
    local temp_dir="$REMOTE_SYNC_CACHE_DIR/pack_$(date +%s)"
    
    mkdir -p "$temp_dir"
    
    # 複製要同步的文件
    for item in "${SYNC_ITEMS[@]}"; do
        local name="${item%:*}"
        local path="${item#*:}"
        
        if [ -f "$path" ]; then
            local target="$temp_dir/$name"
            mkdir -p "$(dirname "$target")"
            cp "$path" "$target"
        elif [ -d "$path" ]; then
            local target="$temp_dir/$name"
            cp -r "$path" "$target"
        fi
    done
    
    # 添加清單文件
    generate_sync_manifest "$temp_dir/manifest.json"
    
    # 創建壓縮包
    (cd "$temp_dir" && tar czf "$pack_file" .)
    
    # 清理臨時目錄
    rm -rf "$temp_dir"
    
    log_remote_sync "INFO" "同步包已創建: $pack_file"
}

# 解包同步文件
unpack_sync_files() {
    local pack_file="$1"
    local extract_dir="$2"
    
    mkdir -p "$extract_dir"
    
    # 解壓縮
    if tar xzf "$pack_file" -C "$extract_dir"; then
        log_remote_sync "INFO" "同步包已解包到: $extract_dir"
        return 0
    else
        log_remote_sync "ERROR" "解包失敗: $pack_file"
        return 1
    fi
}

# 上傳到遠程服務器
upload_to_remote() {
    local pack_file="$1"
    local device_id
    device_id=$(get_device_id)
    
    if [ ! -f "$pack_file" ]; then
        log_remote_sync "ERROR" "上傳文件不存在: $pack_file"
        return 1
    fi
    
    # 使用 curl 上傳
    if command -v curl >/dev/null 2>&1; then
        local response
        response=$(curl -s \
            -X POST \
            -H "Authorization: Bearer $SYNC_TOKEN" \
            -H "Content-Type: application/octet-stream" \
            -H "X-Device-ID: $device_id" \
            --data-binary "@$pack_file" \
            "$SYNC_SERVER_URL/upload")
        
        if [ $? -eq 0 ]; then
            log_remote_sync "INFO" "上傳成功: $response"
            return 0
        else
            log_remote_sync "ERROR" "上傳失敗"
            return 1
        fi
    else
        log_remote_sync "ERROR" "curl 不可用，無法上傳"
        return 1
    fi
}

# 從遠程服務器下載
download_from_remote() {
    local output_file="$1"
    local device_filter="${2:-}"
    
    # 構建URL
    local download_url="$SYNC_SERVER_URL/download"
    if [ -n "$device_filter" ]; then
        download_url="$download_url?device=$device_filter"
    fi
    
    # 使用 curl 下載
    if command -v curl >/dev/null 2>&1; then
        if curl -s \
            -H "Authorization: Bearer $SYNC_TOKEN" \
            -o "$output_file" \
            "$download_url"; then
            log_remote_sync "INFO" "下載成功: $output_file"
            return 0
        else
            log_remote_sync "ERROR" "下載失敗"
            return 1
        fi
    else
        log_remote_sync "ERROR" "curl 不可用，無法下載"
        return 1
    fi
}

# 合併衝突文件
merge_conflicted_file() {
    local local_file="$1"
    local remote_file="$2"
    local output_file="$3"
    
    case "$CONFLICT_RESOLUTION" in
        "local")
            cp "$local_file" "$output_file"
            log_remote_sync "INFO" "使用本地版本: $(basename "$local_file")"
            ;;
        "remote")
            cp "$remote_file" "$output_file"
            log_remote_sync "INFO" "使用遠程版本: $(basename "$local_file")"
            ;;
        "merge")
            # 簡單的合併策略，實際可以更複雜
            if command -v diff >/dev/null 2>&1 && command -v patch >/dev/null 2>&1; then
                # 嘗試自動合併
                if diff -u "$local_file" "$remote_file" > "$output_file.patch"; then
                    cp "$local_file" "$output_file"
                    if patch "$output_file" < "$output_file.patch"; then
                        log_remote_sync "INFO" "自動合併成功: $(basename "$local_file")"
                    else
                        cp "$local_file" "$output_file"
                        log_remote_sync "WARN" "合併失敗，使用本地版本: $(basename "$local_file")"
                    fi
                    rm -f "$output_file.patch"
                else
                    cp "$local_file" "$output_file"
                    log_remote_sync "INFO" "文件相同或無衝突: $(basename "$local_file")"
                fi
            else
                cp "$local_file" "$output_file"
                log_remote_sync "WARN" "無法自動合併，使用本地版本: $(basename "$local_file")"
            fi
            ;;
        "ask")
            # 非互動模式：預設使用本地版本，避免阻塞
            if [ "${NON_INTERACTIVE:-false}" = "true" ] || [ ! -t 0 ]; then
                log_remote_sync "WARN" "非互動模式，文件衝突自動使用本地版本: $(basename "$local_file")"
                cp "$local_file" "$output_file"
            else
                echo "文件衝突: $(basename "$local_file")"
                echo "1) 使用本地版本"
                echo "2) 使用遠程版本"
                echo "3) 手動編輯"
                read -p "請選擇 (1-3): " choice

                case "$choice" in
                    1) cp "$local_file" "$output_file" ;;
                    2) cp "$remote_file" "$output_file" ;;
                    3)
                        if command -v "$EDITOR" >/dev/null 2>&1; then
                            cp "$local_file" "$output_file"
                            "$EDITOR" "$output_file"
                        else
                            cp "$local_file" "$output_file"
                            echo "請手動編輯: $output_file"
                        fi
                        ;;
                    *) cp "$local_file" "$output_file" ;;
                esac
            fi
            ;;
    esac
}

# 應用遠程更新
apply_remote_changes() {
    local remote_pack="$1"
    local extract_dir="$REMOTE_SYNC_CACHE_DIR/remote_$(date +%s)"
    
    # 解包遠程文件
    if ! unpack_sync_files "$remote_pack" "$extract_dir"; then
        return 1
    fi
    
    # 備份當前配置
    local backup_dir="$REMOTE_SYNC_CACHE_DIR/backup_$(date +%s)"
    mkdir -p "$backup_dir"
    
    # 應用更新
    local applied=0
    local conflicts=0
    
    for item in "${SYNC_ITEMS[@]}"; do
        local name="${item%:*}"
        local local_path="${item#*:}"
        local remote_path="$extract_dir/$name"
        
        if [ -e "$remote_path" ]; then
            if [ -e "$local_path" ]; then
                # 檢查是否有衝突
                local local_hash
                local remote_hash
                local_hash=$(calculate_file_hash "$local_path")
                remote_hash=$(calculate_file_hash "$remote_path")
                
                if [ "$local_hash" != "$remote_hash" ]; then
                    # 備份本地文件
                    local backup_target="$backup_dir/$(basename "$local_path")"
                    cp "$local_path" "$backup_target" 2>/dev/null || true
                    
                    # 處理衝突
                    merge_conflicted_file "$local_path" "$remote_path" "$local_path"
                    conflicts=$((conflicts + 1))
                fi
            else
                # 新文件，直接複製
                mkdir -p "$(dirname "$local_path")"
                cp "$remote_path" "$local_path"
                log_remote_sync "INFO" "新增文件: $local_path"
            fi
            applied=$((applied + 1))
        fi
    done
    
    # 清理
    rm -rf "$extract_dir"
    
    log_remote_sync "INFO" "遠程更新應用完成: 應用 $applied 個文件，衝突 $conflicts 個"
    
    if [ $conflicts -gt 0 ]; then
        log_remote_sync "INFO" "本地文件已備份到: $backup_dir"
    fi
    
    return 0
}

# 推送本地更改到遠程
push_local_changes() {
    log_remote_sync "INFO" "推送本地更改到遠程..."
    
    if ! check_sync_config; then
        return 1
    fi
    
    # 創建同步包
    local pack_file="$REMOTE_SYNC_CACHE_DIR/local_$(date +%s).tar.gz"
    pack_sync_files "$pack_file"
    
    # 上傳到遠程
    if upload_to_remote "$pack_file"; then
        log_remote_sync "INFO" "本地更改推送成功"
        rm -f "$pack_file"
        return 0
    else
        log_remote_sync "ERROR" "本地更改推送失敗"
        return 1
    fi
}

# 拉取遠程更改到本地
pull_remote_changes() {
    log_remote_sync "INFO" "拉取遠程更改到本地..."
    
    if ! check_sync_config; then
        return 1
    fi
    
    # 下載遠程包
    local pack_file="$REMOTE_SYNC_CACHE_DIR/remote_$(date +%s).tar.gz"
    
    if download_from_remote "$pack_file"; then
        # 應用遠程更改
        if apply_remote_changes "$pack_file"; then
            log_remote_sync "INFO" "遠程更改拉取成功"
            rm -f "$pack_file"
            return 0
        else
            log_remote_sync "ERROR" "應用遠程更改失敗"
            return 1
        fi
    else
        log_remote_sync "ERROR" "下載遠程更改失敗"
        return 1
    fi
}

# 雙向同步
bidirectional_sync() {
    log_remote_sync "INFO" "開始雙向同步..."
    
    if ! check_sync_config; then
        return 1
    fi
    
    # 先推送本地更改
    if push_local_changes; then
        # 再拉取遠程更改
        if pull_remote_changes; then
            log_remote_sync "INFO" "雙向同步完成"
            return 0
        else
            log_remote_sync "WARN" "拉取遠程更改失敗，但本地推送成功"
            return 1
        fi
    else
        log_remote_sync "ERROR" "推送本地更改失敗"
        return 1
    fi
}

# 列出遠程設備
list_remote_devices() {
    if ! check_sync_config; then
        return 1
    fi
    
    if command -v curl >/dev/null 2>&1; then
        local response
        response=$(curl -s \
            -H "Authorization: Bearer $SYNC_TOKEN" \
            "$SYNC_SERVER_URL/devices")
        
        if [ $? -eq 0 ]; then
            echo "遠程設備列表:"
            echo "$response" | grep -o '"device_id":"[^"]*"' | cut -d'"' -f4 | while read -r device; do
                echo "  - $device"
            done
        else
            log_remote_sync "ERROR" "獲取設備列表失敗"
            return 1
        fi
    else
        log_remote_sync "ERROR" "curl 不可用"
        return 1
    fi
}

# 設置同步配置
setup_remote_sync() {
    echo "設置遠程同步配置"
    echo ""

    # 非互動模式：必須由環境變數預先提供，否則直接退出
    if [ "${NON_INTERACTIVE:-false}" = "true" ] || [ ! -t 0 ]; then
        if [ -z "${SYNC_SERVER_URL:-}" ] || [ -z "${SYNC_TOKEN:-}" ]; then
            log_remote_sync "ERROR" "非互動模式下需設定 SYNC_SERVER_URL 與 SYNC_TOKEN"
            log_remote_sync "ERROR" "範例：SYNC_SERVER_URL=... SYNC_TOKEN=... SYNC_RESOLUTION=local $0 setup"
            return 1
        fi
        set_config "sync_server_url" "$SYNC_SERVER_URL"
        set_config "sync_token" "$SYNC_TOKEN"
        local resolution="${SYNC_RESOLUTION:-local}"
        case "$resolution" in
            local|remote|merge|ask) set_config "sync_resolution" "$resolution" ;;
            *) log_remote_sync "WARN" "未知 SYNC_RESOLUTION='$resolution'，使用 local"
               set_config "sync_resolution" "local" ;;
        esac
        log_remote_sync "INFO" "遠程同步設定（非互動）已完成"
        return 0
    fi

    # 輸入服務器URL
    read -p "同步服務器 URL: " server_url
    if [ -n "$server_url" ]; then
        set_config "sync_server_url" "$server_url"
    fi

    # 輸入同步令牌
    read -p "同步令牌: " token
    if [ -n "$token" ]; then
        set_config "sync_token" "$token"
    fi

    # 選擇衝突解決策略
    echo "衝突解決策略:"
    echo "1) 本地優先 (local)"
    echo "2) 遠程優先 (remote)"
    echo "3) 自動合併 (merge)"
    echo "4) 手動選擇 (ask)"
    read -p "請選擇 (1-4): " resolution_choice
    
    case "$resolution_choice" in
        1) set_config "conflict_resolution" "local" ;;
        2) set_config "conflict_resolution" "remote" ;;
        3) set_config "conflict_resolution" "merge" ;;
        4) set_config "conflict_resolution" "ask" ;;
        *) set_config "conflict_resolution" "merge" ;;
    esac
    
    # 啟用同步
    set_config "remote_sync_enabled" "true"
    
    echo "遠程同步配置完成"
    echo "設備ID: $(get_device_id)"
}

# 顯示同步狀態
show_sync_status() {
    log_info "遠程同步狀態"
    
    echo "=== 同步配置 ==="
    echo "啟用狀態: $REMOTE_SYNC_ENABLED"
    echo "服務器URL: ${SYNC_SERVER_URL:-未設定}"
    echo "加密啟用: $SYNC_ENCRYPTION_ENABLED"
    echo "壓縮啟用: $SYNC_COMPRESSION_ENABLED"
    echo "衝突解決: $CONFLICT_RESOLUTION"
    echo "設備ID: $(get_device_id)"
    echo ""
    
    # 顯示同步項目
    echo "=== 同步項目 ==="
    for item in "${SYNC_ITEMS[@]}"; do
        local name="${item%:*}"
        local path="${item#*:}"
        local status="❌ 不存在"
        
        if [ -f "$path" ]; then
            status="📄 文件"
        elif [ -d "$path" ]; then
            status="📁 目錄"
        fi
        
        echo "  $name: $status ($path)"
    done
    echo ""
    
    # 顯示最近的同步記錄
    if [ -f "$REMOTE_SYNC_LOG_FILE" ]; then
        echo "=== 最近的同步記錄 ==="
        tail -10 "$REMOTE_SYNC_LOG_FILE"
    fi
}

# 清理同步緩存
cleanup_sync_cache() {
    log_info "清理遠程同步緩存..."
    
    # 清理舊的備份（保留最近3天）
    if [ -d "$REMOTE_SYNC_CACHE_DIR" ]; then
        find "$REMOTE_SYNC_CACHE_DIR" -name "backup_*" -type d -mtime +3 -exec rm -rf {} \; 2>/dev/null || true
        find "$REMOTE_SYNC_CACHE_DIR" -name "*.tar.gz" -mtime +1 -delete 2>/dev/null || true
    fi
    
    # 清理舊的日誌（保留最近7天）
    if [ -d "$(dirname "$REMOTE_SYNC_LOG_FILE")" ]; then
        find "$(dirname "$REMOTE_SYNC_LOG_FILE")" -name "remote_sync_*.log" -mtime +7 -delete 2>/dev/null || true
    fi
    
    log_success "遠程同步緩存清理完成"
}

# 命令行接口
case "${1:-help}" in
    "setup")
        setup_remote_sync
        ;;
    "status")
        show_sync_status
        ;;
    "push")
        push_local_changes
        ;;
    "pull")
        pull_remote_changes
        ;;
    "sync")
        bidirectional_sync
        ;;
    "devices")
        list_remote_devices
        ;;
    "cleanup")
        cleanup_sync_cache
        ;;
    "id")
        get_device_id
        ;;
    *)
        echo "遠程配置同步系統"
        echo ""
        echo "用法: $0 <command> [選項]"
        echo ""
        echo "命令:"
        echo "  setup                設置遠程同步配置"
        echo "  status               顯示同步狀態"
        echo "  push                 推送本地更改到遠程"
        echo "  pull                 拉取遠程更改到本地"
        echo "  sync                 雙向同步"
        echo "  devices              列出遠程設備"
        echo "  cleanup              清理同步緩存"
        echo "  id                   顯示設備ID"
        echo ""
        echo "環境變數:"
        echo "  REMOTE_SYNC_ENABLED     啟用遠程同步"
        echo "  SYNC_SERVER_URL         同步服務器URL"
        echo "  SYNC_TOKEN              同步令牌"
        echo "  SYNC_ENCRYPTION_ENABLED 啟用加密"
        echo "  CONFLICT_RESOLUTION     衝突解決策略"
        echo ""
        echo "範例:"
        echo "  $0 setup             # 設置同步配置"
        echo "  $0 sync              # 執行雙向同步"
        echo "  $0 push              # 只推送本地更改"
        echo ""
        echo "注意: 需要配置同步服務器和令牌"
        echo "日誌文件: $REMOTE_SYNC_LOG_FILE"
        ;;
esac

log_success "########## 遠程配置同步系統執行完成 ##########"