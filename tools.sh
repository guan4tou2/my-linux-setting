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
