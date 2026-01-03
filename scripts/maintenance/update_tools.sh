#!/bin/bash

# 載入共用函數庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || {
    echo "錯誤: 無法載入共用函數庫"
    exit 1
}

log_info "########## 更新系統工具 ##########"

# 初始化進度
init_progress 10

update_apt_packages() {
    show_progress "更新 APT 套件庫"
    log_info "更新 APT 套件庫..."
    if sudo apt update; then
        log_success "APT 套件庫更新成功"
    else
        log_error "APT 套件庫更新失敗"
        return 1
    fi
    
    show_progress "升級系統套件"
    log_info "升級可更新的套件..."
    if sudo apt upgrade -y; then
        log_success "系統套件升級完成"
    else
        log_error "系統套件升級失敗"
        return 1
    fi
}

update_uv_packages() {
    show_progress "更新 uv 管理的套件"
    if check_command uv; then
        log_info "更新 uv 工具..."
        if [ -f "$SCRIPT_DIR/utils/secure_download.sh" ]; then
            bash "$SCRIPT_DIR/utils/secure_download.sh" uv
        elif [ -f "$SCRIPT_DIR/../utils/secure_download.sh" ]; then
            bash "$SCRIPT_DIR/../utils/secure_download.sh" uv
        elif [ -f "$SCRIPT_DIR/secure_download.sh" ]; then
            bash "$SCRIPT_DIR/secure_download.sh" uv
        else
            log_warning "找不到安全下載腳本，跳過 uv 更新"
        fi
        
        log_info "更新 uv 管理的套件..."
        if uv tool upgrade --all; then
            log_success "uv 套件更新完成"
        else
            log_warning "部分 uv 套件更新失敗"
        fi
    else
        log_warning "uv 未安裝，跳過 uv 套件更新"
    fi
}

update_pip_packages() {
    show_progress "更新 pip 套件"
    if check_command pip3; then
        log_info "更新 pip..."
        pip3 install --upgrade pip || log_warning "pip 更新失敗"
        
        # 更新虛擬環境中的套件
        VENV_DIR="$HOME/.local/venv/system-tools"
        if [ -d "$VENV_DIR" ]; then
            log_info "更新虛擬環境套件..."
            "$VENV_DIR/bin/pip" install --upgrade pip || log_warning "虛擬環境 pip 更新失敗"
            
            # 如果有 requirements.txt，使用它來更新
            if [ -f "$(dirname "$SCRIPT_DIR")/requirements.txt" ]; then
                "$VENV_DIR/bin/pip" install --upgrade -r "$(dirname "$SCRIPT_DIR")/requirements.txt" || log_warning "虛擬環境套件更新失敗"
            else
                # 手動更新關鍵套件
                "$VENV_DIR/bin/pip" install --upgrade thefuck ranger-fm s-tui || log_warning "部分套件更新失敗"
            fi
            log_success "虛擬環境套件更新完成"
        fi
    else
        log_warning "pip 未安裝，跳過 pip 套件更新"
    fi
}

update_oh_my_zsh() {
    show_progress "更新 Oh-my-zsh"
    if [ -d "$HOME/.oh-my-zsh" ]; then
        log_info "更新 Oh-my-zsh..."
        cd "$HOME/.oh-my-zsh" || return 1
        if git pull; then
            log_success "Oh-my-zsh 更新成功"
        else
            log_warning "Oh-my-zsh 更新失敗"
        fi
        cd - > /dev/null || return 1
    else
        log_warning "Oh-my-zsh 未安裝，跳過更新"
    fi
}

update_oh_my_zsh_plugins() {
    show_progress "更新 Zsh 插件"
    local plugin_dir="$HOME/.oh-my-zsh/custom/plugins"
    local theme_dir="$HOME/.oh-my-zsh/custom/themes"
    
    if [ -d "$plugin_dir" ]; then
        log_info "更新 Zsh 插件..."
        
        # 更新各個插件
        for plugin in zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search you-should-use; do
            if [ -d "$plugin_dir/$plugin" ]; then
                log_info "更新插件: $plugin"
                cd "$plugin_dir/$plugin" || continue
                if git pull; then
                    log_success "$plugin 更新成功"
                else
                    log_warning "$plugin 更新失敗"
                fi
                cd - > /dev/null || continue
            fi
        done
    fi
    
    # 更新 Powerlevel10k 主題
    if [ -d "$theme_dir/powerlevel10k" ]; then
        log_info "更新 Powerlevel10k 主題..."
        cd "$theme_dir/powerlevel10k" || return 1
        if git pull; then
            log_success "Powerlevel10k 更新成功"
        else
            log_warning "Powerlevel10k 更新失敗"
        fi
        cd - > /dev/null || return 1
    fi
}

update_neovim_config() {
    show_progress "更新 Neovim 配置"
    if [ -d "$HOME/.config/nvim" ]; then
        log_info "更新 Neovim 配置..."
        if check_command nvim; then
            # LazyVim 更新
            nvim --headless "+Lazy! sync" +qa 2>/dev/null || log_warning "Neovim 插件更新失敗"
            log_success "Neovim 配置更新完成"
        else
            log_warning "Neovim 未安裝，跳過配置更新"
        fi
    else
        log_warning "Neovim 配置目錄不存在，跳過更新"
    fi
}

update_cargo_packages() {
    show_progress "更新 Cargo 套件"
    if check_command cargo; then
        log_info "更新 Cargo 套件..."
        
        # 更新 Rust 工具鏈
        if check_command rustup; then
            rustup update || log_warning "Rust 工具鏈更新失敗"
        fi
        
        # 更新已安裝的 Cargo 套件
        if check_command cargo-install-update; then
            cargo install-update -a || log_warning "Cargo 套件更新失敗"
        else
            log_info "安裝 cargo-update 工具..."
            cargo install cargo-update || log_warning "cargo-update 安裝失敗"
            cargo install-update -a || log_warning "Cargo 套件更新失敗"
        fi
        
        log_success "Cargo 套件更新完成"
    else
        log_warning "Cargo 未安裝，跳過 Cargo 套件更新"
    fi
}

update_npm_packages() {
    show_progress "更新 NPM 套件"
    if check_command npm; then
        log_info "更新 NPM 和全域套件..."
        
        # 更新 npm 本身
        npm install -g npm@latest || log_warning "npm 更新失敗"
        
        # 更新全域套件
        npm update -g || log_warning "NPM 全域套件更新失敗"
        
        log_success "NPM 套件更新完成"
    else
        log_warning "NPM 未安裝，跳過 NPM 套件更新"
    fi
}

update_docker() {
    show_progress "更新 Docker"
    if check_command docker; then
        log_info "清理 Docker 映像和容器..."
        
        # 清理未使用的映像
        docker image prune -f || log_warning "Docker 映像清理失敗"
        
        # 清理未使用的容器
        docker container prune -f || log_warning "Docker 容器清理失敗"
        
        # 清理未使用的網路
        docker network prune -f || log_warning "Docker 網路清理失敗"
        
        log_success "Docker 清理完成"
    else
        log_warning "Docker 未安裝，跳過 Docker 更新"
    fi
}

cleanup_system() {
    show_progress "清理系統"
    log_info "清理系統緩存和不需要的套件..."
    
    # 清理 APT 緩存
    sudo apt autoremove -y || log_warning "自動移除失敗"
    sudo apt autoclean || log_warning "自動清理失敗"
    
    # 清理 pip 緩存
    if check_command pip3; then
        pip3 cache purge 2>/dev/null || log_warning "pip 緩存清理失敗"
    fi
    
    # 清理 uv 緩存
    if check_command uv; then
        uv cache clean 2>/dev/null || log_warning "uv 緩存清理失敗"
    fi
    
    log_success "系統清理完成"
}

# 主更新流程
main() {
    log_info "開始系統更新流程..."
    local start_time
    start_time=$(date +%s)
    
    # 檢查網路連接
    if ! check_network; then
        log_error "網路連接失敗，無法執行更新"
        exit 1
    fi
    
    # 執行更新
    update_apt_packages
    update_uv_packages
    update_pip_packages
    update_oh_my_zsh
    update_oh_my_zsh_plugins
    update_neovim_config
    update_cargo_packages
    update_npm_packages
    update_docker
    cleanup_system
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_success "########## 系統更新完成 ##########"
    log_info "總耗時: $(printf '%02d:%02d' $((duration / 60)) $((duration % 60)))"
    log_info "建議重新啟動終端以載入所有更新"
    
    # 可選：執行健康檢查
    if [ -f "$SCRIPT_DIR/health_check.sh" ]; then
        read -p "是否要執行健康檢查？(y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            bash "$SCRIPT_DIR/health_check.sh"
        fi
    fi
}

# 執行主函數
main "$@"