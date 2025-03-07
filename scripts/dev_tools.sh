#!/bin/sh

printf "\033[36m########## 安裝開發工具 ##########\n\033[m"

# 添加 neovim ppa
sudo add-apt-repository ppa:neovim-ppa/unstable -y
sudo apt update

# 安裝開發工具
dev_packages="vim neovim nodejs npm unzip cargo gem lua5.3 pipx httpie"
for pkg in $dev_packages; do
    if ! dpkg -l | grep -q "^ii  $pkg"; then
        sudo apt install -y "$pkg"
    else
        printf "\033[36m$pkg 已安裝\033[0m\n"
    fi
done

# 安裝 lazyvim
if ! command -v nvim > /dev/null 2>&1; then
    printf "\033[36m安裝 LazyVim\033[0m\n"
    git clone https://github.com/LazyVim/starter ~/.config/nvim
    rm -rf ~/.config/nvim/.git
    npm install -g neovim
    echo 'alias nv="nvim"' >> ~/.zshrc
fi

# 安裝 lazygit
if ! command -v lazygit > /dev/null 2>&1; then
    printf "\033[36m安裝 Lazygit\033[0m\n"
    LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
    curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
    tar xf lazygit.tar.gz lazygit
    sudo install lazygit /usr/local/bin
    rm -rf lazygit lazygit.tar.gz
fi

printf "\033[36m########## 開發工具安裝完成 ##########\n\033[m" 