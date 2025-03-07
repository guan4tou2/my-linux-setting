#!/bin/sh

printf "\033[36m########## 安裝系統監控工具 ##########\n\033[m"

# 安裝系統監控工具
monitoring_packages="net-tools iftop nethogs iptraf nload vnstat fail2ban"
for pkg in $monitoring_packages; do
    if ! dpkg -l | grep -q "^ii  $pkg"; then
        sudo apt install -y "$pkg"
    else
        printf "\033[36m$pkg 已安裝\033[0m\n"
    fi
done

# 安裝 btop
if ! command -v btop > /dev/null 2>&1; then
    printf "\033[36m安裝 btop\033[0m\n"
    sudo snap install btop
fi

# 啟動 fail2ban
printf "\033[36m設定 fail2ban\033[0m\n"
sudo systemctl enable --now fail2ban

printf "\033[36m########## 系統監控工具安裝完成 ##########\n\033[m" 