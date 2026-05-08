#!/usr/bin/env bash

# 載入共用函數庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || {
    echo "錯誤: 無法載入共用函數庫"
    exit 1
}

log_info "########## 安裝系統監控工具 ##########"

# 初始化進度
init_progress 3

# 安裝系統監控工具
show_progress "安裝基礎監控套件"
monitoring_packages="net-tools iftop nethogs iptraf nload vnstat fail2ban htop"

# 使用批量安裝（支持並行）
if command -v install_packages_batch >/dev/null 2>&1; then
    IFS=' ' read -r -a mon_packages_array <<< "$monitoring_packages"
    install_packages_batch "${mon_packages_array[@]}" || log_warning "部分監控工具安裝失敗"
else
    # 後備：逐個安裝
    for pkg in $monitoring_packages; do
        install_arch_specific_package "$pkg"
    done
fi

# 安裝 btop（現代系統監控工具）
# 順序：apt -> brew fallback -> snap fallback
# 過去先 snap 會在 minimal server / 沒 snapd 的環境報錯；
# 現在優先用發行版套件管理器，最後才 fallback。
show_progress "安裝 btop"
if ! check_command btop; then
    log_info "安裝 btop"
    if install_apt_package btop 2>/dev/null; then
        log_success "btop 已透過 APT 安裝"
    elif command -v install_with_homebrew_fallback >/dev/null 2>&1 \
       && install_with_homebrew_fallback btop 2>/dev/null; then
        log_success "btop 已透過 Homebrew 安裝"
    elif command -v snap >/dev/null 2>&1 && sudo snap install btop 2>/dev/null; then
        log_success "btop 已透過 snap 安裝"
    else
        log_warning "btop 安裝失敗，可手動嘗試 'sudo apt install btop' 或 'snap install btop'"
    fi
else
    log_info "btop 已安裝"
fi

show_progress "監控工具安裝完成"

# 啟動 fail2ban
printf "\033[36m設定 fail2ban\033[0m\n"
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    sudo systemctl enable --now fail2ban || log_warning "fail2ban 服務啟動失敗，請稍後手動檢查"
else
    log_warning "偵測不到 systemd，略過 fail2ban 服務啟動"
fi

printf "\033[36m########## 系統監控工具安裝完成 ##########\n\033[m"
