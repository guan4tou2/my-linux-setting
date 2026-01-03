#!/bin/bash

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
show_progress "安裝 btop"
if ! check_command btop; then
    log_info "安裝 btop"
    # 嘗試多種安裝方式
    if command -v snap >/dev/null 2>&1; then
        sudo snap install btop || install_apt_package btop
    else
        install_apt_package btop
    fi
else
    log_info "btop 已安裝"
fi

show_progress "監控工具安裝完成"

# 啟動 fail2ban
printf "\033[36m設定 fail2ban\033[0m\n"
sudo systemctl enable --now fail2ban

printf "\033[36m########## 系統監控工具安裝完成 ##########\n\033[m" 