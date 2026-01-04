#!/usr/bin/env bash

# 載入共用函數庫（使用與其他模組一致的 TUI / 日誌 / 安裝行為）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" 2>/dev/null || {
    # 在極簡環境下找不到 common.sh 時，仍然盡量完成基礎安裝
    printf "\033[33m警告: 無法載入共用函數庫，將使用簡化模式安裝基礎工具\033[0m\n"
}

log_info "########## 安裝基礎工具 ##########"
log_info "檢測到系統：$DISTRO ($DISTRO_FAMILY) - 包管理器：$PKG_MANAGER"

# 更新套件庫
if [ "$DISTRO_FAMILY" = "debian" ]; then
    # 僅在 Debian 系列（包括 Kali）上添加 ipinfo PPA
    if command -v run_as_root >/dev/null 2>&1; then
        run_as_root sh -c 'echo "deb [trusted=yes] https://ppa.ipinfo.net/ /" > /etc/apt/sources.list.d/ipinfo.ppa.list' 2>/dev/null || true
    else
        echo "deb [trusted=yes] https://ppa.ipinfo.net/ /" | sudo tee "/etc/apt/sources.list.d/ipinfo.ppa.list" >/dev/null 2>&1 || true
    fi
fi

# 使用通用更新函數
if command -v update_system >/dev/null 2>&1; then
    update_system
else
    # 後備：直接更新
    case "${PKG_MANAGER:-apt}" in
        apt)
            sudo apt-get update
            ;;
        dnf|yum)
            sudo ${PKG_MANAGER} check-update || true
            ;;
        pacman)
            sudo pacman -Sy
            ;;
    esac
fi

# 基礎套件（根據發行版系列調整）
# 這些是核心工具，lsd 和 tealdeer 會透過 cargo 單獨處理
case "$DISTRO_FAMILY" in
    debian)
        # Debian/Ubuntu/Kali
        base_packages="git curl wget ca-certificates gnupg2 build-essential pkg-config libssl-dev bat lnav fzf ripgrep"
        # Kali 特殊處理：通常已包含很多工具
        if [ "$DISTRO" != "kali" ]; then
            base_packages="$base_packages software-properties-common ipinfo"
        fi
        ;;
    rhel)
        # Fedora/CentOS/RHEL
        base_packages="git curl wget ca-certificates gnupg2 gcc gcc-c++ make pkgconfig openssl-devel bat fzf ripgrep"
        ;;
    arch)
        # Arch/Manjaro
        base_packages="git curl wget ca-certificates gnupg base-devel pkg-config openssl bat fzf ripgrep"
        ;;
    *)
        # 未知系統，使用最小集合
        base_packages="git curl wget"
        log_warning "未知的發行版系列，僅安裝基本工具"
        ;;
esac

# 安裝基礎套件（使用批量安裝支持並行）
if command -v install_packages_batch >/dev/null 2>&1; then
    # 將空格分隔的字符串轉換為數組
    IFS=' ' read -r -a packages_array <<< "$base_packages"
    install_packages_batch "${packages_array[@]}" || log_warning "部分基礎套件安裝失敗"
else
    # 後備：逐個安裝
    for pkg in $base_packages; do
        if check_package_installed "$pkg" 2>/dev/null; then
            printf "\033[36m$pkg 已安裝\033[0m\n"
            continue
        fi

        if command -v install_package >/dev/null 2>&1; then
            install_package "$pkg" || true
        else
            case "${PKG_MANAGER:-apt}" in
                apt) sudo apt-get install -y "$pkg" || true ;;
                dnf|yum) sudo ${PKG_MANAGER} install -y "$pkg" || true ;;
                pacman) sudo pacman -S --noconfirm "$pkg" || true ;;
            esac
        fi
    done
fi

# 安裝 lsd（next-gen ls）
# 優先使用 Homebrew 安裝（避免 cargo 編譯耗時）
if ! command -v lsd >/dev/null 2>&1; then
    log_info "安裝 lsd (下一代 ls 指令，來源: github.com/lsd-rs/lsd)"

    # 方法 1: 優先使用 Homebrew 安裝（快速且無需編譯）
    if command -v brew >/dev/null 2>&1; then
        if command -v install_brew_package >/dev/null 2>&1; then
            if install_brew_package "lsd"; then
                log_success "lsd 安裝成功 (brew)"
            else
                log_warning "Homebrew 安裝失敗，嘗試使用 APT..."
                BREW_FAILED=1
            fi
        else
            if brew install lsd >/dev/null 2>&1; then
                log_success "lsd 安裝成功 (brew)"
            else
                log_warning "Homebrew 安裝失敗，嘗試使用 APT..."
                BREW_FAILED=1
            fi
        fi
    else
        log_info "Homebrew 未安裝，嘗試使用 APT..."
        BREW_FAILED=1
    fi

    # 方法 2: 如果 Homebrew 失敗或不可用，嘗試 APT
    if [ "${BREW_FAILED:-0}" = "1" ]; then
        if command -v install_apt_package >/dev/null 2>&1; then
            if install_apt_package "lsd" 2>/dev/null; then
                log_success "lsd 安裝成功 (apt)"
            else
                log_warning "lsd 安裝失敗，建議安裝 Homebrew 以獲取更好的支援"
                log_info "安裝 Homebrew: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            fi
        else
            if sudo apt-get install -y lsd 2>/dev/null; then
                log_success "lsd 安裝成功 (apt)"
            else
                log_warning "lsd 安裝失敗，建議安裝 Homebrew 以獲取更好的支援"
            fi
        fi
    fi
fi

# 安裝 tealdeer (快速 TLDR 客戶端)
# 優先使用 Homebrew 安裝（避免 cargo 編譯耗時）
if ! command -v tldr >/dev/null 2>&1; then
    log_info "安裝 tealdeer (快速 TLDR 客戶端，來源: github.com/dbrgn/tealdeer)"

    # 方法 1: 優先使用 Homebrew 安裝（快速且無需編譯）
    if command -v brew >/dev/null 2>&1; then
        if command -v install_brew_package >/dev/null 2>&1; then
            if install_brew_package "tealdeer"; then
                log_success "tealdeer 安裝成功 (brew)"
                # 初始化 tldr 緩存
                if command -v tldr >/dev/null 2>&1; then
                    tldr --update 2>/dev/null || log_warning "tealdeer 緩存更新失敗，首次使用時會自動下載"
                fi
            else
                log_warning "Homebrew 安裝失敗，嘗試使用 cargo..."
                BREW_FAILED=1
            fi
        else
            if brew install tealdeer >/dev/null 2>&1; then
                log_success "tealdeer 安裝成功 (brew)"
                # 初始化 tldr 緩存
                if command -v tldr >/dev/null 2>&1; then
                    tldr --update 2>/dev/null || log_warning "tealdeer 緩存更新失敗，首次使用時會自動下載"
                fi
            else
                log_warning "Homebrew 安裝失敗，嘗試使用 cargo..."
                BREW_FAILED=1
            fi
        fi
    else
        log_info "Homebrew 未安裝，嘗試使用 cargo..."
        BREW_FAILED=1
    fi

    # 方法 2: 如果 Homebrew 失敗或不可用，嘗試使用 cargo
    if [ "${BREW_FAILED:-0}" = "1" ]; then
        if command -v cargo >/dev/null 2>&1; then
            log_info "偵測到 cargo，開始安裝 tealdeer..."
            if cargo install tealdeer 2>&1; then
                log_success "tealdeer 安裝成功 (cargo)"
                # 初始化 tldr 緩存
                if command -v tldr >/dev/null 2>&1; then
                    tldr --update 2>/dev/null || log_warning "tealdeer 緩存更新失敗，首次使用時會自動下載"
                fi
            else
                log_warning "tealdeer 安裝失敗"
            fi
        else
            log_warning "找不到 cargo 且 Homebrew 不可用，跳過 tealdeer 安裝"
            log_info "建議安裝 Homebrew 以獲取更好的支援"
            log_info "安裝命令: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        fi
    fi
else
    log_success "tldr 命令已存在，跳過 tealdeer 安裝"
fi

# 設定 bat 別名
if command -v batcat > /dev/null 2>&1; then
    mkdir -p ~/.local/bin
    # 使用 -f 強制覆蓋已存在的符號連結，避免警告訊息
    ln -sf /usr/bin/batcat ~/.local/bin/bat
fi

# 安裝 superfile（使用安全下載機制）
if ! command -v spf > /dev/null 2>&1; then
    printf "\033[36m安裝 superfile\033[0m\n"
    # 嘗試多個可能的路徑查找 secure_download.sh
    # SCRIPT_DIR 通常是 scripts/core/，所以需要往上一層找 utils/
    if [ -f "$SCRIPT_DIR/../utils/secure_download.sh" ]; then
        bash "$SCRIPT_DIR/../utils/secure_download.sh" superfile
    elif [ -f "$SCRIPT_DIR/utils/secure_download.sh" ]; then
        bash "$SCRIPT_DIR/utils/secure_download.sh" superfile
    elif [ -f "$SCRIPT_DIR/secure_download.sh" ]; then
        bash "$SCRIPT_DIR/secure_download.sh" superfile
    else
        printf "\033[33m警告: 安全下載工具不可用，跳過 superfile 安裝\033[0m\n"
    fi
fi

printf "\033[36m########## 基礎工具安裝完成 ##########\n\033[m" 
