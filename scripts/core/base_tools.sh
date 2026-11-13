#!/usr/bin/env bash

# 載入共用函數庫（使用與其他模組一致的 TUI / 日誌 / 安裝行為）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! source "$SCRIPT_DIR/common.sh" 2>/dev/null; then
    # 極簡環境 fallback：提供最低限度的 log_* / 系統變數，讓後續流程仍能跑
    printf "\033[33m警告: 無法載入共用函數庫，啟用簡化模式\033[0m\n"
    log_info()    { printf "\033[36mINFO:\033[0m %s\n" "$*"; }
    log_success() { printf "\033[32mSUCCESS:\033[0m %s\n" "$*"; }
    log_warning() { printf "\033[33mWARNING:\033[0m %s\n" "$*"; }
    log_error()   { printf "\033[31mERROR:\033[0m %s\n" "$*" >&2; }
    log_debug()   { [ "${DEBUG:-false}" = "true" ] && printf "DEBUG: %s\n" "$*" || true; }
    # 粗略偵測包管理器
    if command -v apt-get >/dev/null 2>&1; then
        PKG_MANAGER="apt";    DISTRO_FAMILY="debian"; DISTRO="${DISTRO:-ubuntu}"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf";    DISTRO_FAMILY="rhel";   DISTRO="${DISTRO:-fedora}"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum";    DISTRO_FAMILY="rhel";   DISTRO="${DISTRO:-centos}"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MANAGER="pacman"; DISTRO_FAMILY="arch";   DISTRO="${DISTRO:-arch}"
    else
        PKG_MANAGER="unknown"; DISTRO_FAMILY="unknown"; DISTRO="${DISTRO:-unknown}"
    fi
fi

log_info "########## 安裝基礎工具 ##########"
log_info "檢測到系統：$DISTRO ($DISTRO_FAMILY) - 包管理器：$PKG_MANAGER"

# 更新套件庫
if [ "$DISTRO_FAMILY" = "debian" ] && [ "${ENABLE_IPINFO_REPO:-false}" = "true" ]; then
    # 僅在明確 opt-in 時添加 ipinfo APT source，避免預設流程被第三方源影響
    if command -v run_as_root >/dev/null 2>&1; then
        run_as_root curl -fsSL https://ppa.ipinfo.net/ipinfo.gpg -o /usr/share/keyrings/ipinfo.gpg 2>/dev/null || true
        run_as_root sh -c 'echo "deb https://ppa.ipinfo.net/ /" > /etc/apt/sources.list.d/ipinfo.ppa.list' 2>/dev/null || true
    else
        sudo curl -fsSL https://ppa.ipinfo.net/ipinfo.gpg -o /usr/share/keyrings/ipinfo.gpg 2>/dev/null || true
        echo "deb https://ppa.ipinfo.net/ /" | sudo tee "/etc/apt/sources.list.d/ipinfo.ppa.list" >/dev/null 2>&1 || true
    fi
elif [ "$DISTRO_FAMILY" = "debian" ]; then
    log_info "預設不啟用 ipinfo 第三方套件源（設 ENABLE_IPINFO_REPO=true 可啟用）"
fi

# 基礎套件（根據發行版系列調整）
# 這些是核心工具，lsd 和 tealdeer 會另外處理
case "$DISTRO_FAMILY" in
    debian)
        # Debian/Ubuntu/Kali
        base_packages="git curl wget ca-certificates gnupg2 build-essential pkg-config libssl-dev bat lnav fzf ripgrep"
        # Kali 特殊處理：通常已包含很多工具。ipinfo 改為明確 opt-in。
        if [ "$DISTRO" != "kali" ] && [ "${ENABLE_IPINFO_REPO:-false}" = "true" ]; then
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

# 預先檢查哪些套件還沒裝；全部已安裝時跳過 apt update（節省時間）
need_install=0
if command -v check_package_installed >/dev/null 2>&1; then
    for pkg in $base_packages; do
        if ! check_package_installed "$pkg" 2>/dev/null; then
            need_install=1
            break
        fi
    done
else
    need_install=1
fi

if [ "$need_install" = "1" ]; then
    # 使用通用更新函數
    if command -v update_system >/dev/null 2>&1; then
        update_system || log_warning "系統套件列表更新失敗，將繼續安裝流程"
    else
        # 後備：直接更新
        case "${PKG_MANAGER:-apt}" in
            apt)
                sudo DEBIAN_FRONTEND=noninteractive apt-get update || log_warning "APT 套件列表更新失敗，將繼續安裝流程"
                ;;
            dnf|yum)
                sudo ${PKG_MANAGER} check-update || true
                ;;
            pacman)
                sudo pacman -Sy
                ;;
        esac
    fi
else
    log_info "所有基礎 APT 套件皆已安裝，跳過 apt update"
fi

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
                apt) sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" || true ;;
                dnf|yum) sudo ${PKG_MANAGER} install -y "$pkg" || true ;;
                pacman) sudo pacman -S --noconfirm "$pkg" || true ;;
            esac
        fi
    done
fi

# 安裝 lsd（next-gen ls）
if ! command -v lsd >/dev/null 2>&1; then
    log_info "安裝 lsd（來源: github.com/lsd-rs/lsd）"
    if ! install_with_homebrew_fallback "lsd"; then
        if command -v install_apt_package >/dev/null 2>&1; then
            install_apt_package "lsd" 2>/dev/null || log_warning "lsd APT 安裝失敗"
        else
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y lsd 2>/dev/null \
                || log_warning "lsd APT 安裝失敗"
        fi
    fi
    if ! command -v lsd >/dev/null 2>&1; then
        lsd_arch=$(linux_release_arch) || lsd_arch=""
        case "$lsd_arch" in
            x86_64|aarch64)
                lsd_tmp_dir=""
                if lsd_tag=$(github_latest_release_tag lsd-rs/lsd) && \
                   lsd_tmp_dir="$(mktemp -d)" && \
                   curl -fsSL --connect-timeout 15 --max-time 120 \
                       -o "$lsd_tmp_dir/lsd.tar.gz" \
                       "https://github.com/lsd-rs/lsd/releases/download/$lsd_tag/lsd-$lsd_tag-$lsd_arch-unknown-linux-musl.tar.gz" && \
                   tar -xzf "$lsd_tmp_dir/lsd.tar.gz" -C "$lsd_tmp_dir" && \
                   mkdir -p "$HOME/.local/bin" && \
                   install -m 0755 "$lsd_tmp_dir/lsd-$lsd_tag-$lsd_arch-unknown-linux-musl/lsd" "$HOME/.local/bin/lsd"; then
                    export PATH="$HOME/.local/bin:$PATH"
                    log_success "lsd 安裝成功 (GitHub)"
                else
                    log_warning "lsd GitHub 備援安裝失敗，將繼續其他安裝方式"
                fi
                if [ -n "$lsd_tmp_dir" ]; then
                    rm -rf "$lsd_tmp_dir" || log_warning "無法清除 lsd 暫存目錄"
                fi
                ;;
            *) log_warning "lsd GitHub 備援不支援架構: $lsd_arch" ;;
        esac
    fi
    if ! command -v lsd >/dev/null 2>&1 && command -v cargo >/dev/null 2>&1; then
        cargo install lsd || log_warning "lsd cargo 安裝失敗"
    fi
    if ! command -v lsd >/dev/null 2>&1; then
        log_warning "lsd 所有安裝方式皆失敗"
    fi
else
    log_debug "lsd 已安裝，跳過"
fi

# 安裝 fd（modern find，Ubuntu/Debian 套件名為 fd-find，二進位為 fdfind）
if ! command -v fd >/dev/null 2>&1 && ! command -v fdfind >/dev/null 2>&1; then
    log_info "Installing fd (modern find, source: github.com/sharkdp/fd)"

    if ! install_with_homebrew_fallback "fd" "fd"; then
        log_info "Attempting APT installation (fd-find)..."
        if command -v install_apt_package >/dev/null 2>&1; then
            install_apt_package "fd-find" 2>/dev/null \
                && log_success "fd-find installed via APT" \
                || log_warning "fd installation failed"
        else
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y fd-find 2>/dev/null \
                && log_success "fd-find installed via APT" \
                || log_warning "fd installation failed"
        fi
    fi
else
    log_debug "fd already installed, skipping"
fi

# 在 Debian/Ubuntu 上 fd 以 fdfind 命名，建立 ~/.local/bin/fd 軟連結讓使用者可直接輸入 fd
if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
fi

# 安裝 tealdeer（先使用預編譯套件，最後才用 cargo 編譯）
if ! command -v tldr >/dev/null 2>&1; then
    log_info "安裝 tealdeer（快速 TLDR 客戶端，來源: github.com/tealdeer-rs/tealdeer）"
    if command -v brew >/dev/null 2>&1; then
        if command -v install_brew_package >/dev/null 2>&1; then
            install_brew_package "tealdeer" || log_warning "tealdeer Homebrew 安裝失敗"
        else
            brew install tealdeer >/dev/null 2>&1 || log_warning "tealdeer Homebrew 安裝失敗"
        fi
    fi
    if ! command -v tldr >/dev/null 2>&1; then
        if command -v install_apt_package >/dev/null 2>&1; then
            install_apt_package "tealdeer" 2>/dev/null || log_warning "tealdeer APT 安裝失敗"
        elif command -v apt-get >/dev/null 2>&1; then
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y tealdeer 2>/dev/null \
                || log_warning "tealdeer APT 安裝失敗"
        fi
    fi
    if ! command -v tldr >/dev/null 2>&1; then
        tealdeer_arch=$(linux_release_arch) || tealdeer_arch=""
        case "$tealdeer_arch" in
            x86_64|aarch64)
                tealdeer_tmp_dir=""
                if tealdeer_tmp_dir="$(mktemp -d)" && \
                   curl -fsSL --connect-timeout 15 --max-time 120 \
                       -o "$tealdeer_tmp_dir/tldr" \
                       "https://github.com/tealdeer-rs/tealdeer/releases/latest/download/tealdeer-linux-$tealdeer_arch-musl" && \
                   curl -fsSL --connect-timeout 15 --max-time 120 \
                       -o "$tealdeer_tmp_dir/tldr.sha256" \
                       "https://github.com/tealdeer-rs/tealdeer/releases/latest/download/tealdeer-linux-$tealdeer_arch-musl.sha256"; then
                    tealdeer_expected=$(awk 'NR == 1 {print $1}' "$tealdeer_tmp_dir/tldr.sha256") || tealdeer_expected=""
                    tealdeer_actual=""
                    if command -v sha256sum >/dev/null 2>&1; then
                        tealdeer_actual=$(sha256sum "$tealdeer_tmp_dir/tldr") || tealdeer_actual=""
                    elif command -v shasum >/dev/null 2>&1; then
                        tealdeer_actual=$(shasum -a 256 "$tealdeer_tmp_dir/tldr") || tealdeer_actual=""
                    fi
                    tealdeer_actual="${tealdeer_actual%% *}"
                    if [[ "$tealdeer_expected" =~ ^[[:xdigit:]]{64}$ ]] && \
                       [ "$tealdeer_actual" = "$tealdeer_expected" ] && \
                       mkdir -p "$HOME/.local/bin" && \
                       install -m 0755 "$tealdeer_tmp_dir/tldr" "$HOME/.local/bin/tldr"; then
                        export PATH="$HOME/.local/bin:$PATH"
                        log_success "tealdeer 安裝成功 (GitHub)"
                    else
                        log_warning "tealdeer 雜湊不符、無法驗證或安裝失敗，略過 GitHub 執行檔"
                    fi
                else
                    log_warning "tealdeer GitHub 備援下載失敗"
                fi
                if [ -n "$tealdeer_tmp_dir" ]; then
                    rm -rf "$tealdeer_tmp_dir" || log_warning "無法清除 tealdeer 暫存目錄"
                fi
                ;;
            *) log_warning "tealdeer GitHub 備援不支援架構: $tealdeer_arch" ;;
        esac
    fi
    if ! command -v tldr >/dev/null 2>&1 && command -v cargo >/dev/null 2>&1; then
        cargo install tealdeer || log_warning "tealdeer cargo 安裝失敗"
    fi
    if command -v tldr >/dev/null 2>&1; then
        tldr --update 2>/dev/null || log_warning "tealdeer 緩存更新失敗，首次使用時會自動下載"
    else
        log_warning "tealdeer 所有安裝方式皆失敗 (brew/apt/GitHub/cargo)"
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
