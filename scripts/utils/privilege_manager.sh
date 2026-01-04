#!/usr/bin/env bash
#!/bin/bash

# 權限管理工具 - 安全的 sudo 操作管理

# 載入共用函數庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || exit 1

# 權限檢查緩存
SUDO_CHECKED=false
SUDO_AVAILABLE=false

# 檢查並緩存 sudo 權限
check_sudo_permission() {
    if [ "$SUDO_CHECKED" = true ]; then
        [ "$SUDO_AVAILABLE" = true ]
        return $?
    fi
    
    SUDO_CHECKED=true
    
    if sudo -n true 2>/dev/null; then
        SUDO_AVAILABLE=true
        log_info "Sudo 權限可用（無需密碼）"
        return 0
    elif sudo -v 2>/dev/null; then
        SUDO_AVAILABLE=true
        log_info "Sudo 權限可用"
        return 0
    else
        SUDO_AVAILABLE=false
        log_warning "Sudo 權限不可用"
        return 1
    fi
}

# 安全的 sudo 執行
safe_sudo() {
    local command="$*"
    
    if ! check_sudo_permission; then
        log_error "需要 sudo 權限才能執行: $command"
        return 1
    fi
    
    log_info "執行 sudo 命令: $command"
    
    # 記錄 sudo 操作（用於審計）
    echo "$(date '+%Y-%m-%d %H:%M:%S') - sudo $command" >> "$HOME/.local/log/sudo_operations.log"
    
    sudo "$@"
}

# 最小權限包安裝
install_package_minimal_privilege() {
    local package="$1"
    
    # 首先嘗試無需 sudo 的安裝方式
    if command -v snap >/dev/null 2>&1; then
        if snap info "$package" >/dev/null 2>&1; then
            log_info "使用 snap 安裝 $package（無需 sudo）"
            snap install "$package" --classic 2>/dev/null && return 0
        fi
    fi
    
    # 嘗試用戶級安裝（如果支持）
    case "$package" in
        python3-*|pip*|pipx)
            log_info "使用用戶級安裝 $package"
            pip install --user "$package" && return 0
            ;;
    esac
    
    # 最後使用 apt（需要 sudo）
    log_info "使用 apt 安裝 $package（需要 sudo）"
    safe_sudo apt install -y "$package"
}

# 驗證 sudo 操作的必要性
validate_sudo_necessity() {
    local operation="$1"
    shift
    local args=("$@")
    
    case "$operation" in
        "chsh")
            # 檢查是否真的需要改變 shell
            current_shell=$(getent passwd "$USER" | cut -d: -f7)
            target_shell="${args[1]}"
            
            if [ "$current_shell" = "$target_shell" ]; then
                log_info "Shell 已經是 $target_shell，跳過 chsh"
                return 1  # 不需要執行
            fi
            ;;
        "apt")
            # 檢查包是否已經安裝
            if [ "${args[0]}" = "install" ]; then
                local package="${args[2]}"
                if dpkg -l | grep -q "^ii  $package "; then
                    log_info "$package 已安裝，跳過"
                    return 1
                fi
            fi
            ;;
    esac
    
    return 0  # 需要執行
}

# 安全的 chsh 操作
safe_chsh() {
    local target_shell="$1"
    
    if ! validate_sudo_necessity "chsh" "-s" "$target_shell" "$USER"; then
        return 0
    fi
    
    # 檢查目標 shell 是否存在
    if [ ! -x "$target_shell" ]; then
        log_error "目標 shell 不存在或不可執行: $target_shell"
        return 1
    fi
    
    # 檢查 shell 是否在允許列表中
    if ! grep -q "^$target_shell$" /etc/shells; then
        log_error "Shell 不在允許列表中: $target_shell"
        return 1
    fi
    
    log_info "切換 shell 到 $target_shell"
    safe_sudo chsh -s "$target_shell" "$USER"
}

# 導出函數
export -f check_sudo_permission safe_sudo install_package_minimal_privilege safe_chsh