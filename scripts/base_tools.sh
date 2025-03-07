#!/bin/sh

printf "\033[36m########## 安裝基礎工具 ##########\n\033[m"

# 更新套件庫
sudo apt update

# 基礎套件
base_packages="git curl wget ca-certificates gnupg2 software-properties-common lsd bat tldr lnav fzf ripgrep"

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

# 安裝 superfile
if ! command -v spf > /dev/null 2>&1; then
    printf "\033[36m安裝 superfile\033[0m\n"
    bash -c "$(curl -sLo- https://superfile.netlify.app/install.sh)"
fi

printf "\033[36m########## 基礎工具安裝完成 ##########\n\033[m" 