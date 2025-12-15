#!/bin/sh

printf "\033[36m########## 安裝基礎工具 ##########\n\033[m"

# 更新套件庫
echo "deb [trusted=yes] https://ppa.ipinfo.net/ /" | sudo tee  "/etc/apt/sources.list.d/ipinfo.ppa.list" # ipinfo
sudo apt update

# 基礎套件
base_packages="git curl wget ca-certificates gnupg2 software-properties-common lsd bat tldr lnav fzf ripgrep ipinfo"

for pkg in $base_packages; do
    if ! dpkg -l | grep -q "^ii  $pkg"; then
        sudo apt install -y "$pkg"
    else
        printf "\033[36m$pkg 已安裝\033[0m\n"
    fi
done

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
