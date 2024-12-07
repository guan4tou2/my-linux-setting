#!/bin/bash

ARCH=$(uname -m)
case $ARCH in
    i386|i686|armv6*|armv7*|aarch64*) ARCH=match ;;
    *) ARCH=$(uname -m) ;;
esac

# 設定時區
echo -e "\033[36m##########\nSetting date\n##########\n\033[m"
sudo timedatectl set-timezone "Asia/Taipei"
timedatectl

# 更新並安裝套件
echo -e "\033[36m##########\nInstalling packages\n##########\n\033[m"
sudo apt update

# 檢查並安裝必要的套件
packages=(zsh fail2ban ca-certificates curl gnupg nodejs npm python-is-python3 unzip cargo gem fd-find ripgrep net-tools tldr fzf ncdu lua5.3 stress pipx iftop lnav logwatch fonts-firacode python3-pip)
for pkg in "${packages[@]}"; do
    if ! dpkg -l | grep -q "^ii  $pkg"; then
        sudo apt install -y "$pkg"
    else
        echo "$pkg is already installed."
    fi
done

echo 'export PATH=$PATH:$HOME/.local/bin' >> ~/.zshrc
echo 'export PATH=$PATH:$HOME/go/bin' >> ~/.zshrc

# 檢查並使用 snap 安裝的特殊套件
if ! command -v btop &> /dev/null; then
    sudo snap install btop
else
    echo "btop is already installed."
fi

# 安裝 Python 套件
pip_packages=(ranger-fm s-tui)
for pip_pkg in "${pip_packages[@]}"; do
    if ! pip list --format=columns | grep -q "$pip_pkg"; then
        pip install "$pip_pkg"
    else
        echo "$pip_pkg is already installed."
    fi
done

# 啟動 fail2ban
echo -e "\033[36m##########\nSetting fail2ban\n##########\n\033[m"
sudo systemctl enable --now fail2ban

# 安裝 oh-my-zsh
echo -e "\033[36m##########\nInstalling oh-my-zsh\n##########\n\033[m"
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sudo -k chsh -s $(command -v zsh) "$USER"
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --skip-chsh
fi

# 安裝 zsh 插件
plugins=("romkatv/powerlevel10k" "zsh-users/zsh-autosuggestions" "zsh-users/zsh-syntax-highlighting" "agkozak/zsh-z")
for plugin in "${plugins[@]}"; do
    repo_name=$(basename "$plugin")
    plugin_dir=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/$(basename "$repo_name")
    if [ ! -d "$plugin_dir" ]; then
        sudo git clone https://github.com/$plugin.git "$plugin_dir"
    else
        echo "$repo_name plugin is already installed."
    fi
done

# 設定主題和插件
sed -i -e 's/ZSH_THEME="robbyrussell"/ZSH_THEME="powerlevel10k\/powerlevel10k"/g' ~/.zshrc
sed -i -e 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-z)/g' ~/.zshrc

# 設定 Powerlevel10k
if [ ! -f ~/.p10k.zsh ]; then
    wget https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main/.p10k.zsh -O ~/.p10k.zsh
    echo 'POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true' >> ~/.zshrc
fi

# 安裝 neovim
if ! command -v nvim &> /dev/null; then
    echo -e "\033[36m##########\nInstalling nvim\n##########\n\033[m"
    sudo apt remove -y nvim
    sudo add-apt-repository ppa:neovim-ppa/unstable -y
    sudo apt update
    sudo apt install -y neovim python3-neovim python3-venv
    git clone https://github.com/LazyVim/starter ~/.config/nvim
    rm -rf ~/.config/nvim/.git
    sudo npm install -g neovim
    echo 'alias nv="nvim"' >> ~/.zshrc
else
    echo "nvim is already installed."
fi

# 安裝 lazygit
if ! command -v lazygit &> /dev/null; then
    echo -e "\033[36m##########\nInstalling lazygit\n##########\n\033[m"
    LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
    curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
    tar xf lazygit.tar.gz lazygit
    sudo install lazygit /usr/local/bin
    rm -rf lazygit lazygit.tar.gz
else
    echo "lazygit is already installed."
fi

# 安裝 Docker
if ! command -v docker &> /dev/null; then
    echo -e "\033[36m##########\nInstalling Docker\n##########\n\033[m"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
else
    echo "Docker is already installed."
fi

# 安裝 lazydocker
if ! command -v lazydocker &> /dev/null; then
    echo -e "\033[36m##########\nInstalling lazydocker\n##########\n\033[m"
    curl https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash
    echo 'alias lzd="lazydocker"' >> ~/.zshrc
else
    echo "lazydocker is already installed."
fi

# 安裝 thefuck
if ! command -v thefuck &> /dev/null; then
    echo -e "\033[36m##########\nInstalling thefuck\n##########\n\033[m"
    sudo apt install -y python3-dev python3-pip python3-setuptools
    pip install git+https://github.com/nvbn/thefuck
    echo 'eval $(thefuck --alias)' >> ~/.zshrc
else
    echo "thefuck is already installed."
fi

# 重新載入 zsh 配置
. ~/.zshrc

echo -e "\033[36m########## Done! ##########\033[m"
