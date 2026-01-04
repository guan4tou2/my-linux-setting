#!/usr/bin/env bash
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

# 安裝 Neovim
# 優先使用 Homebrew 安裝（避免 PPA 複雜性）
if ! command -v nvim >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
        log_info "使用 Homebrew 安裝 Neovim（最新版本）"
        if command -v install_brew_package >/dev/null 2>&1; then
            install_brew_package "neovim" || BREW_FAILED=1
        else
            brew install neovim >/dev/null 2>&1 || BREW_FAILED=1
        fi
    else
        BREW_FAILED=1
    fi

    # 如果 Homebrew 失敗或不可用，使用 PPA
    if [ "${BREW_FAILED:-0}" = "1" ]; then
        log_info "Homebrew 不可用，使用 PPA 安裝 Neovim..."
        if command -v run_as_root >/dev/null 2>&1; then
            run_as_root add-apt-repository ppa:neovim-ppa/unstable -y
            run_as_root apt-get update
        else
            sudo add-apt-repository ppa:neovim-ppa/unstable -y
            sudo apt-get update
        fi
    fi
fi

# 安裝開發工具（從列表中移除 cargo 和 neovim，已單獨處理）
dev_packages="vim nodejs npm unzip gem lua5.3 pipx httpie"

show_progress "安裝基礎開發工具"
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

# 安裝 Rust 和 cargo
# 優先使用 Homebrew 安裝（快速且易於管理）
show_progress "安裝 Rust 和 cargo"
if ! command -v cargo >/dev/null 2>&1; then
    # 方法 1: 優先使用 Homebrew 安裝
    if command -v brew >/dev/null 2>&1; then
        log_info "使用 Homebrew 安裝 Rust（快速且易於管理）"
        if command -v install_brew_package >/dev/null 2>&1; then
            if install_brew_package "rust"; then
                log_success "Rust 和 cargo 安裝成功 (brew)"
                log_info "已安裝版本：$(rustc --version 2>/dev/null || echo '未知')"
            else
                log_warning "Homebrew 安裝失敗，嘗試使用 rustup..."
                BREW_FAILED=1
            fi
        else
            if brew install rust >/dev/null 2>&1; then
                log_success "Rust 和 cargo 安裝成功 (brew)"
                log_info "已安裝版本：$(rustc --version 2>/dev/null || echo '未知')"
            else
                log_warning "Homebrew 安裝失敗，嘗試使用 rustup..."
                BREW_FAILED=1
            fi
        fi
    else
        log_info "Homebrew 未安裝，使用 rustup..."
        BREW_FAILED=1
    fi

    # 方法 2: 如果 Homebrew 失敗或不可用，使用 rustup
    if [ "${BREW_FAILED:-0}" = "1" ]; then
        log_info "使用 rustup 安裝 Rust 和 cargo（官方推薦方式）"
        log_info "這比通過 APT 安裝快得多，且版本更新"

        # 下載並安裝 rustup（非互動模式）
        if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path; then
            # 載入 cargo 環境
            if [ -f "$HOME/.cargo/env" ]; then
                source "$HOME/.cargo/env"
            fi
            export PATH="$HOME/.cargo/bin:$PATH"

            log_success "Rust 和 cargo 安裝成功 (rustup)"
            log_info "已安裝版本：$(rustc --version 2>/dev/null || echo '未知')"
        else
            log_warning "Rust 安裝失敗，如需手動安裝請訪問：https://rustup.rs"
        fi
    fi
else
    log_success "cargo 已安裝，跳過"
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

# 安裝 Lazygit
# 優先使用 Homebrew 安裝（避免手動下載）
if ! command -v lazygit > /dev/null 2>&1; then
    # 方法 1: 優先使用 Homebrew 安裝
    if command -v brew >/dev/null 2>&1; then
        log_info "使用 Homebrew 安裝 Lazygit"
        if command -v install_brew_package >/dev/null 2>&1; then
            if install_brew_package "lazygit"; then
                log_success "Lazygit 安裝成功 (brew)"
            else
                log_warning "Homebrew 安裝失敗，嘗試從 GitHub 下載..."
                BREW_FAILED=1
            fi
        else
            if brew install lazygit >/dev/null 2>&1; then
                log_success "Lazygit 安裝成功 (brew)"
            else
                log_warning "Homebrew 安裝失敗，嘗試從 GitHub 下載..."
                BREW_FAILED=1
            fi
        fi
    else
        log_info "Homebrew 未安裝，從 GitHub 下載 Lazygit..."
        BREW_FAILED=1
    fi

    # 方法 2: 如果 Homebrew 失敗或不可用，從 GitHub 下載
    if [ "${BREW_FAILED:-0}" = "1" ]; then
        printf "\033[36m從 GitHub 下載 Lazygit\033[0m\n"
        LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
        curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
        tar xf lazygit.tar.gz lazygit
        sudo install lazygit /usr/local/bin
        rm -rf lazygit lazygit.tar.gz
        log_success "Lazygit 安裝成功 (GitHub)"
    fi
fi

printf "\033[36m########## 開發工具安裝完成 ##########\n\033[m" 