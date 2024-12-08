#!/bin/sh

sudo -v
# 設定時區
printf "\033[36m##########\nSetting date\n##########\n\033[m"
sudo timedatectl set-timezone "Asia/Taipei"

# 更新並安裝套件
printf "\033[36m##########\nInstalling packages\n##########\n\033[m"
sduo add-apt-repository universe -y
sudo add-apt-repository ppa:neovim-ppa/unstable -y
sudo apt update
sudo apt remove -y nvim
    
# 檢查並安裝必要的套件
packages="zsh git fail2ban ca-certificates curl 
        gnupg nodejs npm unzip cargo gem fd-find ripgrep 
        net-tools tldr fzf ncdu lua5.3 stress pipx iftop lnav logwatch 
        fonts-firacode vim httpie neovim 
        python-is-python3 python3-pip python3-neovim 
        python3-venv python3-dev python3-pip python3-setuptools"
for pkg in $packages; do
    if ! dpkg -l | grep -q "^ii  $pkg"; then
        apt install -y "$pkg"
    else
        echo "$pkg is already installed."
    fi
done

# 檢查並使用 snap 安裝的特殊套件
if ! command -v btop > /dev/null 2>&1; then
    sudo snap install btop
else
    echo "btop is already installed."
fi

# 安裝 Python 套件
pip_packages="ranger-fm s-tui"
for pip_pkg in $pip_packages; do
    if ! pip list --format=columns | grep -q "$pip_pkg"; then
        pip install "$pip_pkg"
    else
        echo "$pip_pkg is already installed."
    fi
done

# 啟動 fail2ban
printf "\033[36m##########\nSetting fail2ban\n##########\n\033[m"
systemctl enable --now fail2ban

# Check Zsh version
ZSH_VERSION=$(zsh --version | awk '{print $2}')
REQUIRED_VERSION="5.0.8"

if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$ZSH_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]; then
    echo "Zsh version is $ZSH_VERSION. Please upgrade to version $REQUIRED_VERSION or newer."
    exit 1
else
    echo "Zsh version is $ZSH_VERSION. It meets the required version."
fi

# 安裝 neovim
if ! command -v nvim > /dev/null 2>&1; then
    printf "\033[36m##########\nInstalling nvim\n##########\n\033[m"
    git clone https://github.com/LazyVim/starter ~/.config/nvim
    rm -rf ~/.config/nvim/.git
    npm install -g neovim
    echo 'alias nv="nvim"' >> ~/.zshrc
else
    printf "nvim is already installed."
fi

# 安裝 lazygit
if ! command -v lazygit > /dev/null 2>&1; then
    printf "\033[36m##########\nInstalling lazygit\n##########\n\033[m"
    LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
    curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
    tar xf lazygit.tar.gz lazygit
    install lazygit /usr/local/bin
    rm -rf lazygit lazygit.tar.gz
else
    printf "lazygit is already installed."
fi

# 安裝 Docker
if ! command -v docker > /dev/null 2>&1; then
    printf "\033[36m##########\nInstalling Docker\n##########\n\033[m"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
else
    echo "Docker is already installed."
fi

# 安裝 lazydocker
if ! command -v lazydocker > /dev/null 2>&1; then
    printf "\033[36m##########\nInstalling lazydocker\n##########\n\033[m"
    curl https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | sh
    echo 'alias lzd="lazydocker"' >> ~/.zshrc
else
    printf "lazydocker is already installed."
fi


# 安裝 oh-my-zsh
printf "\033[36m##########\nInstalling oh-my-zsh\n##########\n\033[m"
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    chsh -s "$(command -v zsh)" 
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
    export ZSH_CUSTOM
fi

# 檢查 ~/.zshrc 是否存在
if [ -f "$HOME/.zshrc" ]; then
    echo "檔案 ~/.zshrc 存在。"
else
    echo "檔案 ~/.zshrc 不存在。"
    exit 1
fi

# 修改 PATH
sed -i -e 's|# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH|export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$HOME/go/bin:$PATH|' ~/.zshrc

# 安裝 zsh 插件
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search
git clone https://github.com/MichaelAquilina/zsh-you-should-use.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/you-should-use
sed -i 's/^plugins=.*/plugins=(git\n thefuck\n zsh-autosuggestions\n zsh-syntax-highlighting\n zsh-history-substring-search\n you-should-use\n nvm\n debian)/g' ~/.zshrc

# 設定 Powerlevel10k
if [ ! -f ~/.p10k.zsh ]; then
    wget https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main/.p10k.zsh -O ~/.p10k.zsh
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
    sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/g' ~/.zshrc
    printf 'POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true' >> ~/.zshrc
fi

# 安裝 thefuck
if ! command -v fuck > /dev/null 2>&1; then
    printf "\033[36m##########\nInstalling thefuck\n##########\n\033[m"
    pip install git+https://github.com/nvbn/thefuck
    echo 'eval $(thefuck --alias)' >> ~/.zshrc
else
    printf "thefuck is already installed."
fi

# 切換到 zsh 並載入配置
exec zsh
source ~/.zshrc

printf "\033[36m########## Done! ##########\033[m"
