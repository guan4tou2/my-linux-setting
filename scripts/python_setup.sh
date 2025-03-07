#!/bin/sh

printf "\033[36m########## 設定 Python 環境 ##########\n\033[m"

# 安裝 Python 相關套件
python_packages="python3 python-is-python3 python3-pip python3-venv python3-dev python3-setuptools python3-neovim"
for pkg in $python_packages; do
    if ! dpkg -l | grep -q "^ii  $pkg"; then
        sudo apt install -y "$pkg"
    else
        printf "\033[36m$pkg 已安裝\033[0m\n"
    fi
done

# 安裝 Python 工具
pip_packages="ranger-fm s-tui"
for pip_pkg in $pip_packages; do
    if ! pip list --format=columns | grep -q "$pip_pkg"; then
        pip install "$pip_pkg"
    else
        printf "\033[36m$pip_pkg 已安裝\033[0m\n"
    fi
done

printf "\033[36m########## Python 環境設定完成 ##########\n\033[m" 