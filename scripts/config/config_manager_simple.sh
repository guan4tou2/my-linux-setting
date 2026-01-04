#!/usr/bin/env bash
#!/bin/bash

# 簡化配置管理器 - 兼容舊版 bash

# 載入共用函數庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || exit 1

log_info "########## 配置管理系統 ##########"

# 配置文件路徑
readonly CONFIG_DIR="$HOME/.config/linux-setting"
readonly CONFIG_FILE="$CONFIG_DIR/user.conf"
readonly CACHE_DIR="$HOME/.cache/linux-setting"

# 初始化配置系統
init_config_system() {
    log_info "初始化配置管理系統..."
    
    # 創建必要目錄
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$CACHE_DIR"
    
    # 如果配置文件不存在，創建預設配置
    if [ ! -f "$CONFIG_FILE" ]; then
        create_default_config
    fi
    
    log_success "配置管理系統初始化完成"
}

# 創建預設配置文件
create_default_config() {
    cat > "$CONFIG_FILE" << 'EOF'
# Linux Setting Scripts 配置文件

# 鏡像源模式: auto, china, global
mirror_mode=auto

# 安裝模式: full, minimal
install_mode=full

# 並行任務數量（0 = 自動檢測）
parallel_jobs=0

# 是否啟用快取
cache_enabled=true

# 快取過期時間（秒）
cache_ttl=86400

# 是否啟用詳細輸出
verbose=false

# 是否啟用調試模式
debug=false

# 倉庫根 URL
repo_url=https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main
EOF
    
    log_success "預設配置文件已創建: $CONFIG_FILE"
}

# 讀取配置值
get_config() {
    local key="$1"
    local default_value="$2"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "$default_value"
        return
    fi
    
    local value
    value=$(grep "^$key=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    if [ -n "$value" ]; then
        echo "$value"
    else
        echo "$default_value"
    fi
}

# 設置配置值
set_config() {
    local key="$1"
    local value="$2"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        init_config_system
    fi
    
    # 創建臨時文件
    local temp_file
    temp_file=$(mktemp)
    
    # 更新或添加配置值
    local updated=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*$key[[:space:]]*= ]]; then
            echo "$key=$value"
            updated=true
        else
            echo "$line"
        fi
    done < "$CONFIG_FILE" > "$temp_file"
    
    # 如果沒有更新，添加新行
    if [ "$updated" = "false" ]; then
        echo "$key=$value" >> "$temp_file"
    fi
    
    # 替換原文件
    mv "$temp_file" "$CONFIG_FILE"
    log_success "配置已更新: $key=$value"
}

# 顯示所有配置
show_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_warning "配置文件不存在"
        return 1
    fi
    
    log_info "當前配置:"
    echo "============="
    
    while IFS= read -r line; do
        # 跳過空行和註釋行
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        if [[ "$line" =~ ^[[:space:]]*([^=]+)=[[:space:]]*(.*) ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            printf "%-20s = %s\n" "$key" "$value"
        fi
    done < "$CONFIG_FILE"
}

# 驗證配置
validate_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "配置文件不存在"
        return 1
    fi
    
    log_info "驗證配置..."
    
    local errors=0
    
    # 檢查鏡像模式
    local mirror_mode
    mirror_mode=$(get_config "mirror_mode" "auto")
    if [[ ! "$mirror_mode" =~ ^(auto|china|global)$ ]]; then
        log_error "invalid mirror_mode: $mirror_mode (must be auto/china/global)"
        errors=$((errors + 1))
    fi
    
    # 檢查安裝模式
    local install_mode
    install_mode=$(get_config "install_mode" "full")
    if [[ ! "$install_mode" =~ ^(full|minimal)$ ]]; then
        log_error "invalid install_mode: $install_mode (must be full/minimal)"
        errors=$((errors + 1))
    fi
    
    # 檢查並行任務數
    local parallel_jobs
    parallel_jobs=$(get_config "parallel_jobs" "0")
    if [[ ! "$parallel_jobs" =~ ^[0-9]+$ ]]; then
        log_error "invalid parallel_jobs: $parallel_jobs (must be a number)"
        errors=$((errors + 1))
    fi
    
    if [ $errors -eq 0 ]; then
        log_success "配置驗證通過"
        return 0
    else
        log_error "配置驗證失敗: $errors 個錯誤"
        return 1
    fi
}

# 重置配置
reset_config() {
    if [ -f "$CONFIG_FILE" ]; then
        local backup_file="$CONFIG_FILE.backup.$(date +%s)"
        mv "$CONFIG_FILE" "$backup_file"
        log_info "配置已備份到: $backup_file"
    fi
    
    create_default_config
    log_success "配置已重置為預設值"
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
        get_config "$2" "$3"
        ;;
    "set")
        if [ -z "$2" ] || [ -z "$3" ]; then
            log_error "請指定配置鍵和值"
            exit 1
        fi
        set_config "$2" "$3"
        ;;
    "show")
        show_config
        ;;
    "validate")
        if validate_config; then
            log_success "配置驗證通過"
        else
            log_error "配置驗證失敗"
            exit 1
        fi
        ;;
    "reset")
        reset_config
        ;;
    *)
        echo "簡化配置管理器"
        echo ""
        echo "用法: $0 <command> [選項]"
        echo ""
        echo "命令:"
        echo "  init                  初始化配置系統"
        echo "  get <key> [default]   獲取配置值"
        echo "  set <key> <value>     設置配置值"
        echo "  show                  顯示所有配置"
        echo "  validate              驗證配置"
        echo "  reset                 重置配置為預設值"
        echo ""
        echo "配置文件: $CONFIG_FILE"
        echo ""
        echo "支援的配置項:"
        echo "  mirror_mode          鏡像源模式 (auto/china/global)"
        echo "  install_mode         安裝模式 (full/minimal)"
        echo "  parallel_jobs        並行任務數量"
        echo "  cache_enabled        是否啟用快取 (true/false)"
        echo "  verbose              詳細輸出 (true/false)"
        echo "  debug                調試模式 (true/false)"
        echo ""
        echo "範例:"
        echo "  $0 set mirror_mode china"
        echo "  $0 get parallel_jobs 4"
        ;;
esac

log_success "########## 配置管理系統執行完成 ##########"