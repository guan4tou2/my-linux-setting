#!/bin/bash

# 配置管理器 - 統一處理配置文件

# 載入共用函數庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || exit 1

log_info "########## 配置管理系統 ##########"

# 配置文件路徑
readonly DEFAULT_CONFIG_FILE="$SCRIPT_DIR/../config/default.conf"
readonly SYSTEM_CONFIG_FILE="/etc/linux-setting/system.conf"
readonly USER_CONFIG_FILE="$HOME/.config/linux-setting/user.conf"
readonly TEMP_CONFIG_FILE="$HOME/.cache/linux-setting/runtime.conf"
readonly CONFIG_TEMPLATE_DIR="$SCRIPT_DIR/../config/templates"

# 配置儲存（使用文件方式兼容舊版 bash）
CONFIG_CACHE_DIR="$HOME/.cache/linux-setting/config"
mkdir -p "$CONFIG_CACHE_DIR"

# 配置操作函數
config_set() {
    local key="$1"
    local value="$2"
    echo "$value" > "$CONFIG_CACHE_DIR/$key"
}

config_get() {
    local key="$1"
    local default="$2"
    if [ -f "$CONFIG_CACHE_DIR/$key" ]; then
        cat "$CONFIG_CACHE_DIR/$key"
    else
        echo "$default"
    fi
}

config_exists() {
    local key="$1"
    [ -f "$CONFIG_CACHE_DIR/$key" ]
}

config_list_keys() {
    if [ -d "$CONFIG_CACHE_DIR" ]; then
        find "$CONFIG_CACHE_DIR" -maxdepth 1 -type f -exec basename {} \;
    fi
}

# 初始化配置系統
init_config_system() {
    log_info "初始化配置管理系統..."
    
    # 創建必要目錄
    mkdir -p "$HOME/.config/linux-setting"
    mkdir -p "$HOME/.cache/linux-setting"
    mkdir -p "$(dirname "$SYSTEM_CONFIG_FILE")" 2>/dev/null || true
    
    # 初始化配置模式定義
    init_config_schema
    
    # 按優先級載入配置
    load_all_configs
    
    # 驗證配置
    validate_all_configs
    
    log_success "配置管理系統初始化完成"
}

# 載入配置模式定義
load_config_schema() {
    # 定義配置模式（類型、預設值、描述、驗證規則）
    CONFIG_SCHEMA["mirror_mode"]="string|auto|鏡像源模式 (auto/china/global)|^(auto|china|global)$"
    CONFIG_SCHEMA["install_mode"]="string|full|安裝模式 (full/minimal)|^(full|minimal)$"
    CONFIG_SCHEMA["parallel_jobs"]="integer|4|並行任務數量|^[1-9][0-9]*$"
    CONFIG_SCHEMA["cache_enabled"]="boolean|true|是否啟用快取|^(true|false)$"
    CONFIG_SCHEMA["cache_ttl"]="integer|86400|快取過期時間（秒）|^[1-9][0-9]*$"
    CONFIG_SCHEMA["verbose"]="boolean|false|詳細日誌輸出|^(true|false)$"
    CONFIG_SCHEMA["debug"]="boolean|false|調試模式|^(true|false)$"
    CONFIG_SCHEMA["backup_enabled"]="boolean|true|是否備份配置文件|^(true|false)$"
    CONFIG_SCHEMA["auto_cleanup"]="boolean|true|是否自動清理|^(true|false)$"
    CONFIG_SCHEMA["repo_url"]="string|https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main|倉庫URL|^https?://.*"
    CONFIG_SCHEMA["requirements_url"]="string||Python requirements 文件URL|^(|https?://.*)$"
    CONFIG_SCHEMA["p10k_config_url"]="string||PowerLevel10k 配置URL|^(|https?://.*)$"
    
    log_debug "配置模式載入完成: ${#CONFIG_SCHEMA[@]} 項"
}

# 載入單個配置文件
load_config() {
    local config_file="$1"
    local priority="${2:-normal}"
    
    if [ ! -f "$config_file" ]; then
        log_debug "配置文件不存在: $config_file"
        return 1
    fi
    
    log_debug "載入配置文件: $config_file (優先級: $priority)"
    
    local section=""
    local line_num=0
    
    while IFS= read -r line; do
        line_num=$((line_num + 1))
        
        # 移除行首行尾空格
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # 跳過空行
        [[ -z "$line" ]] && continue
        
        # 跳過註釋行
        [[ "$line" =~ ^# ]] && continue
        
        # 處理段落
        if [[ "$line" =~ ^\[(.+)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi
        
        # 處理鍵值對
        if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            # 清理鍵和值
            key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            # 移除值周圍的引號
            value=$(echo "$value" | sed 's/^"\(.*\)"$/\1/;s/^'\''\\(.*\\)'\''$/\\1/')
            
            # 變數替換
            value=$(expand_config_variables "$value")
            
            # 如果有段落，加上段落前綴
            if [ -n "$section" ]; then
                key="${section}.${key}"
            fi
            
            CONFIG["$key"]="$value"
            CONFIG_METADATA["${key}.source"]="$config_file"
            CONFIG_METADATA["${key}.line"]="$line_num"
            CONFIG_METADATA["${key}.priority"]="$priority"
            
            log_debug "載入配置: $key = $value"
        else
            log_warning "配置文件 $config_file 第 $line_num 行格式錯誤: $line"
        fi
    done < "$config_file"
}

# 變數替換
expand_config_variables() {
    local value="$1"
    
    # 替換環境變數
    value=$(envsubst <<< "$value")
    
    # 替換已載入的配置變數
    while [[ "$value" =~ \$\{([^}]+)\} ]]; do
        local var_name="${BASH_REMATCH[1]}"
        local var_value="${CONFIG[$var_name]:-}"
        value="${value//\${$var_name}/$var_value}"
    done
    
    echo "$value"
}

# 載入所有配置文件（按優先級）
load_all_configs() {
    log_info "按優先級載入配置文件..."
    
    # 1. 載入預設配置
    if [ -f "$DEFAULT_CONFIG_FILE" ]; then
        load_config "$DEFAULT_CONFIG_FILE" "default"
    else
        log_debug "預設配置文件不存在，使用內建預設值"
        load_builtin_defaults
    fi
    
    # 2. 載入系統配置
    if [ -f "$SYSTEM_CONFIG_FILE" ]; then
        load_config "$SYSTEM_CONFIG_FILE" "system"
    fi
    
    # 3. 載入用戶配置
    if [ -f "$USER_CONFIG_FILE" ]; then
        load_config "$USER_CONFIG_FILE" "user"
    fi
    
    # 4. 載入環境變數覆蓋
    load_env_overrides
    
    # 5. 載入命令行參數（如果有）
    load_cli_overrides
    
    log_info "配置載入完成: ${#CONFIG[@]} 項"
}

# 載入內建預設值
load_builtin_defaults() {
    log_debug "載入內建預設值..."
    
    for key in "${!CONFIG_SCHEMA[@]}"; do
        IFS='|' read -r type default_value description pattern <<< "${CONFIG_SCHEMA[$key]}"
        CONFIG["$key"]="$default_value"
        CONFIG_METADATA["${key}.source"]="builtin"
        CONFIG_METADATA["${key}.priority"]="builtin"
    done
}

# 載入環境變數覆蓋
load_env_overrides() {
    log_debug "載入環境變數覆蓋..."
    
    for key in "${!CONFIG_SCHEMA[@]}"; do
        local env_var="LINUX_SETTING_$(echo "$key" | tr '[:lower:]' '[:upper:]')"
        if [ -n "${!env_var:-}" ]; then
            CONFIG["$key"]="${!env_var}"
            CONFIG_METADATA["${key}.source"]="environment"
            CONFIG_METADATA["${key}.priority"]="environment"
            log_debug "環境變數覆蓋: $key = ${!env_var}"
        fi
    done
}

# 載入命令行參數覆蓋
load_cli_overrides() {
    # 這個函數會被主腳本調用時傳入命令行參數
    log_debug "載入命令行參數覆蓋..."
    
    # 處理全局變數中的命令行參數
    if [ -n "${MIRROR_MODE:-}" ]; then
        CONFIG["mirror_mode"]="$MIRROR_MODE"
        CONFIG_METADATA["mirror_mode.source"]="cli"
    fi
    
    if [ -n "${INSTALL_MODE:-}" ]; then
        CONFIG["install_mode"]="$INSTALL_MODE"
        CONFIG_METADATA["install_mode.source"]="cli"
    fi
    
    if [ -n "${VERBOSE:-}" ]; then
        CONFIG["verbose"]="$VERBOSE"
        CONFIG_METADATA["verbose.source"]="cli"
    fi
    
    if [ -n "${DEBUG:-}" ]; then
        CONFIG["debug"]="$DEBUG"
        CONFIG_METADATA["debug.source"]="cli"
    fi
}

# 配置驗證
validate_all_configs() {
    log_info "驗證配置..."
    
    local errors=0
    
    for key in "${!CONFIG_SCHEMA[@]}"; do
        if ! validate_config_value "$key" "${CONFIG[$key]:-}"; then
            errors=$((errors + 1))
        fi
    done
    
    if [ $errors -eq 0 ]; then
        log_success "配置驗證通過"
    else
        log_error "配置驗證失敗: $errors 個錯誤"
        return 1
    fi
}

# 驗證單個配置值
validate_config_value() {
    local key="$1"
    local value="$2"
    
    if [ -z "${CONFIG_SCHEMA[$key]:-}" ]; then
        log_warning "未知的配置項: $key"
        return 1
    fi
    
    IFS='|' read -r type default_value description pattern <<< "${CONFIG_SCHEMA[$key]}"
    
    # 類型檢查
    case "$type" in
        "string")
            # 字符串類型，檢查模式
            if [ -n "$pattern" ] && ! [[ "$value" =~ $pattern ]]; then
                log_error "配置 $key 值 '$value' 不匹配模式: $pattern"
                return 1
            fi
            ;;
        "integer")
            if ! [[ "$value" =~ ^[0-9]+$ ]]; then
                log_error "配置 $key 必須是整數，當前值: $value"
                return 1
            fi
            ;;
        "boolean")
            if ! [[ "$value" =~ ^(true|false)$ ]]; then
                log_error "配置 $key 必須是 true 或 false，當前值: $value"
                return 1
            fi
            ;;
        *)
            log_warning "未知的配置類型: $type"
            return 1
            ;;
    esac
    
    return 0
}

# 創建配置文件模板
create_config_template() {
    local template_file="$1"
    local template_type="${2:-user}"
    
    mkdir -p "$(dirname "$template_file")"
    
    cat > "$template_file" << 'EOF'
# Linux Setting Scripts 配置文件
# 此文件用於自定義安裝行為

[general]
# 鏡像源模式: auto, china, global
mirror_mode = auto

# 安裝模式: full, minimal
install_mode = full

# 是否啟用詳細輸出
verbose = false

# 是否啟用調試模式
debug = false

[performance]
# 並行任務數量（0 = 自動檢測）
parallel_jobs = 0

# 是否啟用快取
cache_enabled = true

# 快取過期時間（秒）
cache_ttl = 86400

[backup]
# 是否備份現有配置
backup_enabled = true

# 是否自動清理舊備份
auto_cleanup = true

[urls]
# 倉庫根 URL
repo_url = https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main

# Python requirements 文件 URL（可選）
requirements_url = 

# PowerLevel10k 配置文件 URL（可選）
p10k_config_url = 
EOF
    
    log_success "配置模板已創建: $template_file"
}

# 獲取配置值
get_config() {
    local key="$1"
    local default_value="$2"
    
    echo "${CONFIG[$key]:-$default_value}"
}

# 設定配置值
set_config() {
    local key="$1"
    local value="$2"
    local persist="${3:-false}"
    
    # 驗證新值
    if ! validate_config_value "$key" "$value"; then
        log_error "配置值驗證失敗: $key = $value"
        return 1
    fi
    
    CONFIG["$key"]="$value"
    CONFIG_METADATA["${key}.source"]="runtime"
    
    if [ "$persist" = "true" ]; then
        persist_config_value "$key" "$value"
    fi
}

# 持久化配置值到文件
persist_config_value() {
    local key="$1"
    local value="$2"
    
    mkdir -p "$(dirname "$USER_CONFIG_FILE")"
    
    # 創建臨時文件
    local temp_file
    temp_file=$(mktemp)
    
    # 如果配置文件不存在，創建模板
    if [ ! -f "$USER_CONFIG_FILE" ]; then
        create_config_template "$USER_CONFIG_FILE" user
    fi
    
    # 更新或添加配置值
    local updated=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*$key[[:space:]]*= ]]; then
            echo "$key = $value"
            updated=true
        else
            echo "$line"
        fi
    done < "$USER_CONFIG_FILE" > "$temp_file"
    
    # 如果沒有更新，添加新行
    if [ "$updated" = "false" ]; then
        echo "$key = $value" >> "$temp_file"
    fi
    
    # 替換原文件
    mv "$temp_file" "$USER_CONFIG_FILE"
    log_success "配置已持久化: $key = $value"
}

# 顯示所有配置
show_config() {
    local format="${1:-table}"
    
    case "$format" in
        "json")
            show_config_json
            ;;
        "detailed")
            show_config_detailed
            ;;
        *)
            show_config_table
            ;;
    esac
}

# 表格格式顯示配置
show_config_table() {
    log_info "當前配置:"
    printf "%-25s %-15s %-30s %s\n" "配置項" "值" "來源" "描述"
    printf "%-25s %-15s %-30s %s\n" "----" "---" "----" "----"
    
    for key in $(printf '%s\n' "${!CONFIG[@]}" | sort); do
        # 跳過元數據
        [[ "$key" =~ \.source$|\.line$|\.priority$ ]] && continue
        
        local value="${CONFIG[$key]}"
        local source="${CONFIG_METADATA[${key}.source]:-unknown}"
        local description=""
        
        if [ -n "${CONFIG_SCHEMA[$key]:-}" ]; then
            IFS='|' read -r type default_value desc pattern <<< "${CONFIG_SCHEMA[$key]}"
            description="$desc"
        fi
        
        # 截斷過長的值
        if [ ${#value} -gt 15 ]; then
            value="${value:0:12}..."
        fi
        
        printf "%-25s %-15s %-30s %s\n" "$key" "$value" "$source" "$description"
    done
}

# 詳細格式顯示配置
show_config_detailed() {
    for key in $(printf '%s\n' "${!CONFIG[@]}" | sort); do
        # 跳過元數據
        [[ "$key" =~ \.source$|\.line$|\.priority$ ]] && continue
        
        echo "配置項: $key"
        echo "  值: ${CONFIG[$key]}"
        echo "  來源: ${CONFIG_METADATA[${key}.source]:-unknown}"
        
        if [ -n "${CONFIG_METADATA[${key}.line]:-}" ]; then
            echo "  行號: ${CONFIG_METADATA[${key}.line]}"
        fi
        
        if [ -n "${CONFIG_SCHEMA[$key]:-}" ]; then
            IFS='|' read -r type default_value description pattern <<< "${CONFIG_SCHEMA[$key]}"
            echo "  類型: $type"
            echo "  預設值: $default_value"
            echo "  描述: $description"
        fi
        echo ""
    done
}

# JSON 格式顯示配置
show_config_json() {
    echo "{"
    local first=true
    for key in $(printf '%s\n' "${!CONFIG[@]}" | sort); do
        # 跳過元數據
        [[ "$key" =~ \.source$|\.line$|\.priority$ ]] && continue
        
        if [ "$first" = "true" ]; then
            first=false
        else
            echo ","
        fi
        
        printf "  \"%s\": \"%s\"" "$key" "${CONFIG[$key]}"
    done
    echo ""
    echo "}"
}

# 驗證配置
validate_config() {
    local errors=0
    
    # 檢查必需的配置
    local required_keys=(
        "repo_url"
        "python_min_version"
        "download_timeout"
    )
    
    for key in "${required_keys[@]}"; do
        if [ -z "${CONFIG[$key]}" ]; then
            log_error "缺少必需的配置: $key"
            errors=$((errors + 1))
        fi
    done
    
    # 檢查版本格式
    if [[ ! "${CONFIG[python_min_version]}" =~ ^[0-9]+\.[0-9]+$ ]]; then
        log_error "Python 版本格式錯誤: ${CONFIG[python_min_version]}"
        errors=$((errors + 1))
    fi
    
    # 檢查超時值
    if [[ ! "${CONFIG[download_timeout]}" =~ ^[0-9]+$ ]]; then
        log_error "下載超時值格式錯誤: ${CONFIG[download_timeout]}"
        errors=$((errors + 1))
    fi
    
    return $errors
}

# 重置配置
reset_config() {
    local backup_file="$USER_CONFIG_FILE.backup.$(date +%s)"
    
    if [ -f "$USER_CONFIG_FILE" ]; then
        mv "$USER_CONFIG_FILE" "$backup_file"
        log_info "用戶配置已備份到: $backup_file"
    fi
    
    unset CONFIG
    declare -A CONFIG
    load_config "$CONFIG_FILE"
    
    log_success "配置已重置為預設值"
}

# 外部配置功能
export_config() {
    local export_file="$1"
    local format="${2:-conf}"
    
    case "$format" in
        "json")
            show_config_json > "$export_file"
            ;;
        "env")
            export_env_format > "$export_file"
            ;;
        *)
            export_conf_format > "$export_file"
            ;;
    esac
    
    log_success "配置已導出到: $export_file"
}

# 導出環境變數格式
export_env_format() {
    for key in $(printf '%s\n' "${!CONFIG[@]}" | sort); do
        # 跳過元數據
        [[ "$key" =~ \.source$|\.line$|\.priority$ ]] && continue
        
        local env_var="LINUX_SETTING_$(echo "$key" | tr '[:lower:]' '[:upper:]')"
        echo "export $env_var=\"${CONFIG[$key]}\""
    done
}

# 導出配置文件格式
export_conf_format() {
    echo "# Linux Setting Scripts 配置文件"
    echo "# 導出時間: $(date)"
    echo ""
    
    for key in $(printf '%s\n' "${!CONFIG[@]}" | sort); do
        # 跳過元數據
        [[ "$key" =~ \.source$|\.line$|\.priority$ ]] && continue
        
        if [ -n "${CONFIG_SCHEMA[$key]:-}" ]; then
            IFS='|' read -r type default_value description pattern <<< "${CONFIG_SCHEMA[$key]}"
            echo "# $description"
        fi
        echo "$key = ${CONFIG[$key]}"
        echo ""
    done
}

# 命令行接口
case "${1:-help}" in
    "init")
        init_config_system
        ;;
    "get")
        if [ -z "$2" ]; then
            log_error "請指定配置鍵"
            exit 1
        fi
        init_config_system
        get_config "$2" "$3"
        ;;
    "set")
        if [ -z "$2" ] || [ -z "$3" ]; then
            log_error "請指定配置鍵和值"
            exit 1
        fi
        init_config_system
        set_config "$2" "$3" "true"
        ;;
    "show")
        init_config_system
        show_config "${2:-table}"
        ;;
    "validate")
        init_config_system
        if validate_all_configs; then
            log_success "配置驗證通過"
        else
            log_error "配置驗證失敗"
            exit 1
        fi
        ;;
    "template")
        local template_file="${2:-$USER_CONFIG_FILE}"
        create_config_template "$template_file" user
        ;;
    "export")
        if [ -z "$2" ]; then
            log_error "請指定導出文件"
            exit 1
        fi
        init_config_system
        export_config "$2" "${3:-conf}"
        ;;
    "schema")
        log_info "配置模式定義:"
        for key in $(printf '%s\n' "${!CONFIG_SCHEMA[@]}" | sort); do
            IFS='|' read -r type default_value description pattern <<< "${CONFIG_SCHEMA[$key]}"
            printf "%-20s %-10s %-15s %s\n" "$key" "$type" "$default_value" "$description"
        done
        ;;
    *)
        echo "進階配置管理系統"
        echo ""
        echo "用法: $0 <command> [選項]"
        echo ""
        echo "命令:"
        echo "  init                     初始化配置系統"
        echo "  get <key> [default]      獲取配置值"
        echo "  set <key> <value>        設定配置值（自動持久化）"
        echo "  show [table|json|detailed] 顯示配置"
        echo "  validate                 驗證所有配置"
        echo "  template [file]          創建配置模板"
        echo "  export <file> [format]   導出配置（conf/json/env）"
        echo "  schema                   顯示配置模式定義"
        echo ""
        echo "配置文件優先級 (低到高):"
        echo "  1. 內建預設值"
        echo "  2. $DEFAULT_CONFIG_FILE"
        echo "  3. $SYSTEM_CONFIG_FILE"
        echo "  4. $USER_CONFIG_FILE"
        echo "  5. 環境變數 (LINUX_SETTING_*)"
        echo "  6. 命令行參數"
        echo ""
        echo "範例:"
        echo "  $0 set mirror_mode china      # 設置鏡像模式"
        echo "  $0 show detailed              # 詳細顯示配置"
        echo "  $0 export /tmp/config.json json # 導出JSON格式"
        ;;
esac

log_success "########## 配置管理系統執行完成 ##########"