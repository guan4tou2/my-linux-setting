#!/bin/bash

# 載入共用函數庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || {
    echo "錯誤: 無法載入共用函數庫"
    exit 1
}

log_info "########## 安裝開發工具 ##########"

# 初始化進度
init_progress 8

# 添加 neovim ppa（使用 run_as_root，quiet 模式下自動壓縮輸出）
if command -v run_as_root >/dev/null 2>&1; then
    run_as_root add-apt-repository ppa:neovim-ppa/unstable -y
    run_as_root apt-get update
else
    sudo add-apt-repository ppa:neovim-ppa/unstable -y
    sudo apt-get update
fi

# 安裝開發工具
dev_packages="vim neovim nodejs npm unzip cargo gem lua5.3 pipx httpie"

# 使用批量安裝（支持並行）
if command -v install_packages_batch >/dev/null 2>&1; then
    IFS=' ' read -r -a dev_packages_array <<< "$dev_packages"
    install_packages_batch "${dev_packages_array[@]}" || log_warning "部分開發工具安裝失敗"
else
    # 後備：逐個安裝
    for pkg in $dev_packages; do
        if dpkg -l | grep -q "^ii  $pkg"; then
            printf "\033[36m$pkg 已安裝\033[0m\n"
            continue
        fi

        if command -v install_apt_package >/dev/null 2>&1; then
            install_apt_package "$pkg" || true
        else
            sudo apt-get install -y "$pkg"
        fi
    done
fi

# 安裝 LazyVim 配置
if [ ! -d ~/.config/nvim ]; then
    printf "\033[36m安裝 LazyVim 配置\033[0m\n"

    # 備份現有配置（如果存在）
    if [ -d ~/.config/nvim ]; then
        mv ~/.config/nvim ~/.config/nvim.bak.$(date +%Y%m%d_%H%M%S)
    fi

    # 克隆 LazyVim starter
    git clone https://github.com/LazyVim/starter ~/.config/nvim
    rm -rf ~/.config/nvim/.git

    # 安裝 neovim npm 包（用於某些插件）
    if command -v npm > /dev/null 2>&1; then
        npm install -g neovim
    fi

    # 添加 nvim 函數包裝器（修復目錄切換問題）
    if ! grep -q 'function nvim_wrapper' ~/.zshrc 2>/dev/null; then
        cat >> ~/.zshrc << 'EOF'

# Nvim 包裝器：保持當前工作目錄
function nvim_wrapper() {
    local current_dir="$PWD"
    command nvim "$@"
    local exit_code=$?
    cd "$current_dir" 2>/dev/null || true
    return $exit_code
}
alias nvim='nvim_wrapper'
alias nv='nvim_wrapper'
EOF
    fi

    log_success "LazyVim 配置安裝完成"
fi

# 安裝 lazygit
if ! command -v lazygit > /dev/null 2>&1; then
    printf "\033[36m安裝 Lazygit\033[0m\n"
    LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
    curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
    tar xf lazygit.tar.gz lazygit
    sudo install lazygit /usr/local/bin
    rm -rf lazygit lazygit.tar.gz
fi

printf "\033[36m########## 開發工具安裝完成 ##########\n\033[m" 