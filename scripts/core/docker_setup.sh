#!/bin/bash

# 載入共用函數庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || {
    echo "錯誤: 無法載入共用函數庫"
    exit 1
}

# 載入安全下載工具
if [ -f "$SCRIPT_DIR/../utils/secure_download.sh" ]; then
    source "$SCRIPT_DIR/../utils/secure_download.sh"
elif [ -f "$SCRIPT_DIR/utils/secure_download.sh" ]; then
    source "$SCRIPT_DIR/utils/secure_download.sh"
elif [ -f "$SCRIPT_DIR/secure_download.sh" ]; then
    source "$SCRIPT_DIR/secure_download.sh"
else
    log_error "安全下載工具不可用，無法安全安裝"
    exit 1
fi

log_info "########## 安裝 Docker 相關工具 ##########"

# 初始化進度
init_progress 3

# 安全安裝 Docker
show_progress "安裝 Docker"
if ! check_command docker; then
    log_info "安裝 Docker（使用安全下載機制）"
    install_docker || {
        log_error "Docker 安裝失敗"
        exit 1
    }
    
    # 將當前用戶加入 docker 群組
    log_info "將用戶加入 docker 群組"
    if ! groups "$USER" | grep -q docker; then
        sudo usermod -aG docker "$USER"
        log_warning "請重新登入以套用 docker 群組權限"
    fi
else
    log_info "Docker 已安裝"
fi

# 安裝 lazydocker
# 優先使用 Homebrew 安裝（避免手動下載）
show_progress "安裝 Lazydocker"
if ! check_command lazydocker; then
    # 方法 1: 優先使用 Homebrew 安裝
    if command -v brew >/dev/null 2>&1; then
        log_info "使用 Homebrew 安裝 Lazydocker"
        if command -v install_brew_package >/dev/null 2>&1; then
            if install_brew_package "lazydocker"; then
                log_success "Lazydocker 安裝成功 (brew)"
            else
                log_warning "Homebrew 安裝失敗，嘗試使用安全下載..."
                BREW_FAILED=1
            fi
        else
            if brew install lazydocker >/dev/null 2>&1; then
                log_success "Lazydocker 安裝成功 (brew)"
            else
                log_warning "Homebrew 安裝失敗，嘗試使用安全下載..."
                BREW_FAILED=1
            fi
        fi
    else
        log_info "Homebrew 未安裝，使用安全下載方式..."
        BREW_FAILED=1
    fi

    # 方法 2: 如果 Homebrew 失敗或不可用，使用安全下載
    if [ "${BREW_FAILED:-0}" = "1" ]; then
        log_info "安裝 Lazydocker（使用安全下載方式）"
        install_lazydocker || {
            log_warning "Lazydocker 安裝失敗，但不影響 Docker 使用"
        }
    fi

    # 添加別名
    if command -v lazydocker >/dev/null 2>&1; then
        safe_append_to_file 'alias lzd="lazydocker"' ~/.zshrc
    fi
else
    log_info "Lazydocker 已安裝"
fi

show_progress "Docker 安裝完成"
log_success "########## Docker 相關工具安裝完成 ##########"

printf "\033[36m########## Docker 相關工具安裝完成 ##########\n\033[m" 