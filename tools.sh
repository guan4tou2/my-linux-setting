#!/bin/sh

sudo -v

packages="zsh git fail2ban ca-certificates curl 
        gnupg nodejs npm unzip cargo gem fd-find ripgrep lnav tldr fzf ncdu lua5.3 pipx
        net-tools iftop nethogs iptraf nload  vnstat            
        fonts-firacode vim httpie neovim 
        python-is-python3 python3-pip python3-neovim 
        python3-venv python3-dev python3-pip python3-setuptools"

for pkg in $packages; do
    if ! dpkg -l | grep -q "^ii  $pkg"; then
        sudo apt install -y "$pkg"
    else
        echo "$pkg is already installed."
    fi
done

# 安裝 Python 套件
pip_packages="ranger-fm s-tui"
for pip_pkg in $pip_packages; do
    if ! pip list --format=columns | grep -q "$pip_pkg"; then
        pip install "$pip_pkg"
    else
        echo "$pip_pkg is already installed."
    fi
done

# 檢查並使用 snap 安裝的特殊套件
if ! command -v btop > /dev/null 2>&1; then
    sudo snap install btop
else
    echo "btop is already installed."
fi
