#!/usr/bin/env bash

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

# 列出 apt 來源與金鑰目錄中與 Docker 相關的檔案（每行一個）
docker_apt_artifacts() {
    local dir
    for dir in /etc/apt/sources.list.d /etc/apt/keyrings /etc/apt/trusted.gpg.d; do
        [ -d "$dir" ] || continue
        find "$dir" -maxdepth 1 -type f -iname '*docker*' 2>/dev/null || true
    done
    return 0
}

# 移除「這次執行才新增」的 Docker apt 來源與金鑰（參數：執行前的檔案清單）。
# 官方安裝程式失敗時可能留下壞掉的來源，使之後每次 apt-get update 都報錯。
# 清理失敗只警告，不中止。
remove_new_docker_apt_artifacts() {
    local before="$1" file removed=false
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        if printf '%s\n' "$before" | grep -qxF -- "$file"; then
            continue
        fi
        if run_as_root rm -f -- "$file"; then
            log_info "已移除本次新增的 Docker apt 檔案：$file"
            removed=true
        else
            log_warning "無法移除 $file，請手動刪除以免 apt-get update 持續報錯"
        fi
    done < <(docker_apt_artifacts)
    if [ "$removed" = "true" ]; then
        update_system force || log_warning "移除 Docker apt 來源後更新套件索引失敗"
    fi
    return 0
}

# 從發行版套件庫安裝 docker.io（Kali 官方文件的做法，也是其他發行版的備援）
install_docker_io() {
    log_info "改用發行版套件庫的 docker.io"
    if [ "${PKG_MANAGER:-apt}" = "apt" ]; then
        update_system || log_warning "套件索引更新失敗，仍嘗試安裝 docker.io"
    fi
    install_package "docker.io"
}

# 安裝後刷新 shell hash，並補上常見路徑（同一 shell 內 command -v 有時找不到新二進位）
refresh_docker_path() {
    hash -r 2>/dev/null || true
    if ! check_command docker; then
        local _dp
        for _dp in /usr/bin/docker /usr/local/bin/docker; do
            if [ -x "$_dp" ]; then
                log_info "偵測到 Docker 於 $_dp，補入 PATH 供本腳本後續檢查"
                PATH="$(dirname "$_dp"):$PATH" || true
                export PATH
                break
            fi
        done
    fi
    return 0
}

# 安全安裝 Docker
show_progress "安裝 Docker"
if ! check_command docker; then
    if [ "${DISTRO:-}" = "kali" ]; then
        # get.docker.com 不支援 Kali（會留下指向 kali-rolling 的壞來源），直接用發行版套件
        log_info "Kali 不支援官方安裝程式，使用發行版套件庫的 docker.io"
        install_docker_io || log_warning "docker.io 安裝失敗"
    else
        log_info "安裝 Docker（使用安全下載機制）"
        docker_artifacts_before="$(docker_apt_artifacts)"
        install_docker || log_warning "Docker 安裝失敗，將跳過 Docker 相關配置"
        refresh_docker_path
        if ! check_command docker; then
            remove_new_docker_apt_artifacts "$docker_artifacts_before"
            install_docker_io || log_warning "docker.io 備援安裝失敗"
        fi
    fi
    refresh_docker_path

    # 僅在 Docker 安裝成功後處理群組設定
    # 加入 docker 群組等同給予該使用者 root 權限，因此可用 ADD_USER_TO_DOCKER_GROUP=false 關閉
    if check_command docker; then
        docker_user="$(id -un)"
        if [ "${ADD_USER_TO_DOCKER_GROUP:-true}" = "true" ]; then
            log_warning "將 $docker_user 加入 docker 群組：這等同給予該使用者 root 權限（可用 ADD_USER_TO_DOCKER_GROUP=false 關閉）"
            if ! id -nG "$docker_user" | tr ' ' '\n' | grep -qx docker; then
                sudo usermod -aG docker "$docker_user"
                log_warning "請重新登入以套用 docker 群組權限"
            fi
        else
            log_info "ADD_USER_TO_DOCKER_GROUP=false，不加入 docker 群組；需用 sudo 執行 docker"
        fi
    else
        log_warning "Docker 尚未可用，跳過 docker 群組設定"
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

    # 添加別名（第 3 參數為 idempotent 檢查用的 pattern，容忍引號變體）
    if command -v lazydocker >/dev/null 2>&1; then
        safe_append_to_file 'alias lzd="lazydocker"' ~/.zshrc 'alias lzd='
    fi
else
    log_info "Lazydocker 已安裝"
fi

# Docker 仍不可用時讓模組失敗，安裝報告才不會誤報成功
if ! check_command docker; then
    log_error "Docker 安裝失敗：docker 指令不存在"
    exit 1
fi

show_progress "Docker 安裝完成"
log_success "########## Docker 相關工具安裝完成 ##########"

printf "\033[36m########## Docker 相關工具安裝完成 ##########\n\033[m" 
