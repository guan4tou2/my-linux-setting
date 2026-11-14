#!/bin/bash
# shellcheck shell=bash
# 檔案與下載：安裝清單、備份、安全追加、快取、SHA-256 驗證與下載。
# 由 scripts/core/common.sh 載入（source），不可單獨執行。

# 追加一筆安裝記錄到安裝清單（只追加、不重複）。
# 用法: manifest_record <package|path|file|backup> <值>
# 任何失敗都安靜略過，絕不影響安裝；--dry-run 不寫入。
manifest_record() {
    local kind="${1:-}" value="${2:-}"
    [ "${DRY_RUN:-false}" != "true" ] || return 0
    case "$kind" in package|path|file|backup) ;; *) return 0 ;; esac
    [ -n "$value" ] || return 0
    case "$value" in *$'\n'*|*$'\r'*) return 0 ;; esac
    case "$kind" in
        path|file|backup) case "$value" in /*) ;; *) return 0 ;; esac ;;
    esac
    local manifest="${INSTALL_MANIFEST_FILE:-}"
    [ -n "$manifest" ] || return 0
    (
        umask 077
        mkdir -p "$(dirname "$manifest")" || exit 0
        chmod 0700 "$(dirname "$manifest")" || true
        [ -f "$manifest" ] || : > "$manifest" || exit 0
        chmod 0600 "$manifest" || true
        if ! grep -qxF -- "$kind:$value" "$manifest"; then
            printf '%s:%s\n' "$kind" "$value" >> "$manifest"
        fi
    ) 2>/dev/null || true
    return 0
}

# ==============================================================================
# 文件操作函數
# ==============================================================================

backup_file() {
    local file="$1"
    local backup_dir="${2:-${BACKUP_DIR:-}}"
    
    if [ -f "$file" ] || [ -d "$file" ]; then
        local backup_name
        backup_name="$(basename "$file").backup.$(date +%Y%m%d_%H%M%S)"
        # 如果沒有預設備份目錄，使用 ~/.config/linux-setting-backup/<當前時間>
        if [ -z "$backup_dir" ]; then
            local ts
            ts="$(date +%Y%m%d_%H%M%S)"
            backup_dir="$HOME/.config/linux-setting-backup/$ts"
        fi
        mkdir -p "$backup_dir"
        chmod 0700 "$backup_dir" 2>/dev/null || true
        cp -r "$file" "$backup_dir/$backup_name"
        log_info "已備份 $file 到 $backup_dir/$backup_name"
        return 0
    else
        log_warning "文件不存在，跳過備份: $file"
        return 1
    fi
}

# 確保 npm 使用使用者層級 prefix（~/.npm-global），避免 `npm install -g` 因
# /usr/local/lib/node_modules 沒寫權限而 EACCES。
# 已正確設定（prefix 在 $HOME 下）就直接 return 0。
# 第一次設定時：建立 ~/.npm-global、寫入 npm config、注入 PATH，並 idempotent
# 寫一行到 ~/.bashrc / ~/.zshrc。
ensure_npm_user_prefix() {
    if ! command -v npm >/dev/null 2>&1; then
        return 1
    fi

    local current_prefix
    current_prefix=$(npm config get prefix 2>/dev/null || true)

    # 已經是使用者目錄底下就不動
    case "$current_prefix" in
        "$HOME"/*) export PATH="$current_prefix/bin:$PATH"; return 0 ;;
    esac

    local target="$HOME/.npm-global"
    log_info "設定 npm 使用者級 prefix → $target（避免需要 sudo）"
    mkdir -p "$target"

    if ! npm config set prefix "$target" 2>/dev/null; then
        log_warning "npm config set prefix 失敗"
        return 1
    fi

    export PATH="$target/bin:$PATH"

    # 寫一行 PATH 到 shell rc（idempotent）
    local rc_line='export PATH="$HOME/.npm-global/bin:$PATH"  # linux-setting:npm-prefix'
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [ -f "$rc" ] && ! grep -Fq 'linux-setting:npm-prefix' "$rc"; then
            printf '\n%s\n' "$rc_line" >> "$rc"
            log_debug "已注入 npm-prefix PATH 到 $rc"
        fi
    done

    return 0
}

# 統一判斷是否為非互動模式
# - NON_INTERACTIVE=true 環境變數
# - stdin 不是 tty（curl|bash、CI、cron 等）
# 任一條件成立即視為非互動。
is_non_interactive() {
    [ "${NON_INTERACTIVE:-false}" = "true" ] || [ ! -t 0 ]
}

# 互動安全 read
# 用法：safe_read <提示文字> <預設答案> <變數名> [read 額外參數...]
# 在非互動模式下不阻塞，直接把預設答案寫進指定變數並回 0
safe_read() {
    local prompt="$1"
    local default_value="$2"
    local var_name="$3"
    shift 3 || true

    if is_non_interactive; then
        printf -v "$var_name" '%s' "$default_value"
        log_debug "non-interactive: $var_name=$default_value (prompt='$prompt')"
        return 0
    fi

    # 互動模式：照常 read
    read ${1+"$@"} -p "$prompt" "${var_name?}"
}

safe_append_to_file() {
    local content="$1"
    local file="$2"
    local check_pattern="${3:-$content}"
    
    if [ ! -f "$file" ]; then
        echo "$content" > "$file"
        log_info "創建文件並添加內容: $file"
        return 0
    fi
    
    if ! grep -Fq "$check_pattern" "$file"; then
        echo "$content" >> "$file"
        log_info "添加內容到文件: $file"
        return 0
    else
        log_info "內容已存在，跳過: $file"
        return 0
    fi
}

# ==============================================================================
# 快取機制
# ==============================================================================

# 初始化快取系統
init_cache_system() {
    # CACHE_DIR 和 CACHE_TTL 已在檔案頂部定義為 readonly，這裡只設定 CACHE_ENABLED
    export CACHE_ENABLED="${CACHE_ENABLED:-true}"

    if [ "$CACHE_ENABLED" = "true" ]; then
        mkdir -p "$CACHE_DIR/downloads"
        mkdir -p "$CACHE_DIR/metadata"
        log_debug "快取系統已初始化: $CACHE_DIR"
    fi
}

# 檢查快取是否有效
is_cache_valid() {
    local cache_file="$1"
    local ttl="${2:-$CACHE_TTL}"
    
    if [ ! -f "$cache_file" ]; then
        return 1
    fi
    
    local file_age
    local current_time
    file_age=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)
    current_time=$(date +%s)
    
    if [ $((current_time - file_age)) -lt "$ttl" ]; then
        return 0
    else
        return 1
    fi
}

# 從快取獲取文件
get_from_cache() {
    local url="$1"
    local output="$2"
    
    if [ "$CACHE_ENABLED" != "true" ]; then
        return 1
    fi
    
    local cache_key
    cache_key=$(echo "$url" | sha256sum | cut -d' ' -f1)
    local cache_file="$CACHE_DIR/downloads/$cache_key"
    
    if is_cache_valid "$cache_file"; then
        cp "$cache_file" "$output"
        log_info "從快取獲取: $(basename "$output")"
        return 0
    else
        return 1
    fi
}

# 保存到快取
save_to_cache() {
    local url="$1"
    local file="$2"
    
    if [ "$CACHE_ENABLED" != "true" ] || [ ! -f "$file" ]; then
        return 1
    fi
    
    local cache_key
    cache_key=$(echo "$url" | sha256sum | cut -d' ' -f1)
    local cache_file="$CACHE_DIR/downloads/$cache_key"
    
    cp "$file" "$cache_file"
    echo "$url" > "$CACHE_DIR/metadata/$cache_key.url"
    log_debug "保存到快取: $cache_file"
}


# ==============================================================================
# Security Functions
# ==============================================================================

# 驗證檔案的 SHA-256 是否與 checksums 清單（每行「sha256␠␠檔名」）中指定資產一致。
# 用法: verify_sha256_in_list <檔案> <checksums 檔> <資產檔名>
# 找不到該檔名、清單格式不合或無法計算雜湊都視為失敗（回傳 1）。
verify_sha256_in_list() {
    local file="${1:-}" list="${2:-}" asset="${3:-}"
    [ -f "$file" ] && [ -f "$list" ] && [ -n "$asset" ] || return 1

    local expected
    expected=$(awk -v name="$asset" '
        { n = $2; sub(/^\*/, "", n) }
        n == name && $1 ~ /^[0-9A-Fa-f]{64}$/ { print tolower($1); exit }
    ' "$list" 2>/dev/null) || return 1
    [ -n "$expected" ] || return 1

    local actual=""
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$file" 2>/dev/null) || return 1
    elif command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 256 "$file" 2>/dev/null) || return 1
    else
        return 1
    fi
    actual="${actual%% *}"
    actual=$(printf '%s' "$actual" | tr '[:upper:]' '[:lower:]')
    [ -n "$actual" ] && [ "$actual" = "$expected" ]
}

# ==============================================================================
# Download Functions
# ==============================================================================

safe_download() {
    local url="$1"
    local output="$2"
    local max_retries="${3:-$DOWNLOAD_RETRIES}"
    local use_cache="${4:-true}"

    log_debug "Downloading: $url"

    # Try to get from cache first
    if [ "$use_cache" = "true" ] && [ "$CACHE_ENABLED" = "true" ]; then
        if get_from_cache "$url" "$output"; then
            log_debug "Retrieved from cache"
            return 0
        fi
    fi

    # Download with retries（只做大小上限與重試；內容是否可信取決於來源與 TLS）
    local retry=0
    local temp_output
    temp_output="${output}.tmp.$$"

    # https 網址：跟隨轉址時也只允許 https；本機測試用的 http://127.0.0.1 不加限制
    local proto_opts=()
    case "$url" in
        https://*) proto_opts=(--proto '=https' --proto-redir '=https') ;;
    esac

    while [ $retry -lt $max_retries ]; do
        if curl -fsSL ${proto_opts[@]+"${proto_opts[@]}"} \
            --max-time "$DOWNLOAD_TIMEOUT" \
            --connect-timeout "${CONNECTION_TIMEOUT:-10}" \
            --max-filesize "$MAX_SCRIPT_SIZE" \
            "$url" -o "$temp_output" 2>/dev/null; then

            # --max-filesize 在伺服器未提供長度時不一定生效，下載後再檢查一次
            local file_size
            file_size=$(stat -c%s "$temp_output" 2>/dev/null || stat -f%z "$temp_output" 2>/dev/null || echo 0)
            if [ "$file_size" -gt "$MAX_SCRIPT_SIZE" ]; then
                rm -f "$temp_output"
                log_error "Download too large: $file_size bytes (max: $MAX_SCRIPT_SIZE)"
                return 1
            fi

            mv "$temp_output" "$output"

            # Save to cache
            if [ "$use_cache" = "true" ] && [ "$CACHE_ENABLED" = "true" ]; then
                save_to_cache "$url" "$output"
            fi

            log_success "Download successful: $(basename "$output")"
            return 0
        else
            rm -f "$temp_output"
            retry=$((retry + 1))
            log_debug "Download failed, retry $retry/$max_retries: $url"
            sleep $((retry * 2))  # Exponential backoff
        fi
    done

    log_error "Download failed after $max_retries attempts: $url"
    return 1
}
