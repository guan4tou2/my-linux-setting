#!/usr/bin/env bash

# 載入共用函數庫（使用與其他模組一致的 TUI / 日誌 / 安裝行為）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" 2>/dev/null || {
    # 在極簡環境下找不到 common.sh 時，仍然盡量完成基礎安裝
    printf "\033[33m警告: 無法載入共用函數庫，將使用簡化模式安裝基礎工具\033[0m\n"
}

log_info "########## 安裝基礎工具 ##########"

# 更新套件庫（使用 run_as_root + apt-get，TUI_MODE=quiet 時將自動隱藏細節）
if command -v run_as_root >/dev/null 2>&1; then
    # 寫入 ipinfo PPA（避免 sudo 直接出現在腳本裡）
    run_as_root sh -c 'echo "deb [trusted=yes] https://ppa.ipinfo.net/ /" > /etc/apt/sources.list.d/ipinfo.ppa.list'
    run_as_root apt-get update
else
    echo "deb [trusted=yes] https://ppa.ipinfo.net/ /" | sudo tee "/etc/apt/sources.list.d/ipinfo.ppa.list"
    sudo apt-get update
fi

# 基礎套件（不再透過 APT 安裝 lsd，改用專門流程處理）
base_packages="git curl wget ca-certificates gnupg2 software-properties-common build-essential pkg-config bat tldr lnav fzf ripgrep ipinfo"

for pkg in $base_packages; do
    if dpkg -l | grep -q "^ii  $pkg"; then
        printf "\033[36m$pkg 已安裝\033[0m\n"
        continue
    fi

    if command -v install_apt_package >/dev/null 2>&1; then
        # 使用共用安裝函數（會自動尊重 TUI_MODE）
        install_apt_package "$pkg" || true
    else
        # 後備路徑：直接用 apt-get 安裝
        sudo apt-get install -y "$pkg"
    fi
done

# 安裝 lsd（next-gen ls）。
# 流程：
#   1. 若系統尚未安裝 cargo，先透過 APT 安裝 cargo
#   2. 使用 cargo install lsd
if ! command -v lsd >/dev/null 2>&1; then
    log_info "安裝 lsd (下一代 ls 指令，來源: github.com/lsd-rs/lsd)"

    # 若沒有 cargo，先安裝
    if ! command -v cargo >/dev/null 2>&1; then
        log_info "找不到 cargo，嘗試透過 APT 安裝 cargo..."
        if command -v install_apt_package >/dev/null 2>&1; then
            install_apt_package "cargo" || log_warning "cargo 安裝可能失敗，稍後再檢查"
        else
            sudo apt-get install -y cargo || log_warning "cargo 安裝可能失敗，稍後再檢查"
        fi
        
        # 嘗試載入 cargo 環境導出
        if [ -f "$HOME/.cargo/env" ]; then
            source "$HOME/.cargo/env"
        fi
        export PATH="$HOME/.cargo/bin:$PATH"
    fi

    # 再次檢查 cargo 是否可用
    if command -v cargo >/dev/null 2>&1; then
        if cargo install lsd >/dev/null 2>&1; then
            log_success "lsd 安裝成功 (cargo)"
        else
            log_warning "lsd 安裝失敗 (cargo)，可參考官方安裝說明：github.com/lsd-rs/lsd"
        fi
    else
        log_warning "仍然找不到 cargo，略過自動安裝 lsd，可之後手動安裝：參考 github.com/lsd-rs/lsd"
    fi
fi

# 設定 bat 別名
if command -v batcat > /dev/null 2>&1; then
    mkdir -p ~/.local/bin
    ln -s /usr/bin/batcat ~/.local/bin/bat
fi

# 安裝 superfile（使用安全下載機制）
if ! command -v spf > /dev/null 2>&1; then
    printf "\033[36m安裝 superfile\033[0m\n"
    if [ -f "$SCRIPT_DIR/secure_download.sh" ]; then
        bash "$SCRIPT_DIR/secure_download.sh" superfile
    else
        printf "\033[33m警告: 安全下載工具不可用，跳過 superfile 安裝\033[0m\n"
    fi
fi

printf "\033[36m########## 基礎工具安裝完成 ##########\n\033[m" 
