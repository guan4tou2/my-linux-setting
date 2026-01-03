#!/bin/bash

# 載入共用函數庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || {
    echo "錯誤: 無法載入共用函數庫"
    exit 1
}

# 載入安全下載工具
if [ -f "$SCRIPT_DIR/utils/secure_download.sh" ]; then
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

# 安全安裝 lazydocker  
show_progress "安裝 Lazydocker"
if ! check_command lazydocker; then
    log_info "安裝 Lazydocker（使用安全方式）"
    install_lazydocker || {
        log_warning "Lazydocker 安裝失敗，但不影響 Docker 使用"
    }
    
    # 添加別名
    safe_append_to_file 'alias lzd="lazydocker"' ~/.zshrc
else
    log_info "Lazydocker 已安裝"
fi

show_progress "Docker 安裝完成"
log_success "########## Docker 相關工具安裝完成 ##########"

printf "\033[36m########## Docker 相關工具安裝完成 ##########\n\033[m" 