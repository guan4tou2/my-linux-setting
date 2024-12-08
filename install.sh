#!/bin/sh

INSTALL_ALL=false
while getopts "a" opt; do
    case $opt in
        a) INSTALL_DOCKER=true ;;
        *) echo "Usage: $0 [-a]" ; exit 1 ;;
    esac
done

sudo -v
# 設定時區
printf "\033[36m########## Setting date ##########\n\033[m"
sudo timedatectl set-timezone "Asia/Taipei"

# 更新並安裝套件
printf "\033[36m########## Installing packages ##########\n\033[m"
sudo add-apt-repository universe -y
sudo add-apt-repository ppa:neovim-ppa/unstable -y
sudo apt update

if command -v nvim > /dev/null 2>&1; then
    sudo apt remove -y nvim
fi

packages="zsh git fonts-firacode python3 python-is-python3 python3-pip"
for pkg in $packages; do
    if ! dpkg -l | grep -q "^ii  $pkg"; then
        sudo apt install -y "$pkg"
    else
        printf "\033[36m########## $pkg is already installed. ##########\n\033[m"
    fi
done

# Check Zsh version
ZSH_VERSION=$(zsh --version | awk '{print $2}')
REQUIRED_VERSION="5.0.8"

if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$ZSH_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]; then
    printf "\033[36m Zsh version is $ZSH_VERSION. Please upgrade to version $REQUIRED_VERSION or newer. \n\033[m"
    exit 1
else
    printf "\033[36mZsh version is $ZSH_VERSION. It meets the required version. \n\033[m"
fi

sudo -v
# 安裝 oh-my-zsh
printf "\033[36m########## Installing oh-my-zsh ##########\n\033[m"
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sudo -k chsh -s "$(command -v zsh)" "$USER"
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
    export ZSH_CUSTOM
fi

# 檢查 ~/.zshrc 是否存在
if [ -f "$HOME/.zshrc" ]; then
    printf "\033[36mFile ~/.zshrc exist. \n\033[m"
else
    printf "\033[36mFile ~/.zshrc not exist. \n\033[m"
    exit 1
fi

# 檢查 ~/.zshrc 是否已經設定過 PATH
if ! grep -q "export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$HOME/go/bin:$PATH" ~/.zshrc; then
    # 如果沒設定過，則修改 ~/.zshrc
    sed -i -e 's|# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH|export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$HOME/go/bin:$PATH|' ~/.zshrc
else
    printf "\033[36mPATH is already set in ~/.zshrc. \n\033[m"
fi

# 安裝 zsh 插件
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search
git clone https://github.com/MichaelAquilina/zsh-you-should-use.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/you-should-use

# 檢查 plugins 設定是否已經包含所需插件
if ! grep -q "zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search you-should-use" ~/.zshrc; then
    sed -i 's/^plugins=(.*)/plugins=(git thefuck zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search you-should-use)/g' ~/.zshrc
else
    printf "\033[36mPlugins are already set in ~/.zshrc. \n\033[m"
fi

# 設定 Powerlevel10k
if [ ! -f ~/.p10k.zsh ]; then
    wget https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main/.p10k.zsh -O ~/.p10k.zsh
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
    sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/g' ~/.zshrc
    echo 'POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true' >> ~/.zshrc
fi

# 安裝 thefuck ###

# 檢查 ~/.zshrc 是否已經設定過 PATH
if ! grep -q "eval $(thefuck --alias)" ~/.zshrc; then
    printf "\033[36m########## Installing thefuck ##########\n\033[m"
    pip install git+https://github.com/nvbn/thefuck
    echo 'eval $(thefuck --alias)' >> ~/.zshrc
else
    printf "\033[36mthefuck is already installed. \n\033[m"
fi

if [ "$INSTALL_ALL" = true ]; then
printf "\033[31m########## lazydocker is already installed. ##########\n\033[m"

    # 檢查並安裝必要的套件
    packages="zsh git fail2ban curl 
            nodejs npm unzip cargo gem lua5.3 pipx
            fonts-firacode vim neovim 
            python3-neovim python3-venv python3-dev python3-setuptools"
    for pkg in $packages; do
        if ! dpkg -l | grep -q "^ii  $pkg"; then
            sudo apt install -y "$pkg"
        else
            printf "\033[36m########## $pkg is already installed. ##########\n\033[m"
        fi
    done
    
    # 安裝 Python 套件
    pip_packages="ranger-fm"
    for pip_pkg in $pip_packages; do
        if ! pip list --format=columns | grep -q "$pip_pkg"; then
            pip install "$pip_pkg"
        else
            printf "\033[36m########## $pkg is already installed. ##########\n\033[m"
        fi
    done
    
    # 啟動 fail2ban
    printf "\033[36m##########\nSetting fail2ban\n##########\n\033[m"
    sudo systemctl enable --now fail2ban
    
    # 安裝 lzayvim
    if ! command -v nvim > /dev/null 2>&1; then
        printf "\033[36m##########\nInstalling nvim\n##########\n\033[m"
        git clone https://github.com/LazyVim/starter ~/.config/nvim
        rm -rf ~/.config/nvim/.git
        npm install -g neovim
        echo 'alias nv="nvim"' >> ~/.zshrc
    else
        printf "\033[36m##########lzayvim is already installed. ##########\n\033[m"
    fi

    # 安裝 lazygit
    if ! command -v lazygit > /dev/null 2>&1; then
        printf "\033[36m##########\nInstalling lazygit\n##########\n\033[m"
        LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
        curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
        tar xf lazygit.tar.gz lazygit
        sudo install lazygit /usr/local/bin
        rm -rf lazygit lazygit.tar.gz
    else
        printf "\033[36m##########lazygit is already installed. ##########\n\033[m"
    fi
    
    # 安裝 Docker
    if ! command -v docker > /dev/null 2>&1; then
        printf "\033[36m##########\nInstalling Docker\n##########\n\033[m"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
    else
        printf "\033[36m##########Docker is already installed. ##########\n\033[m"
    fi
    
    # 安裝 lazydocker
    if ! command -v lazydocker > /dev/null 2>&1; then
        printf "\033[36m##########\nInstalling lazydocker\n##########\n\033[m"
        curl https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | sh
        echo 'alias lzd="lazydocker"' >> ~/.zshrc
    else
        printf "\033[36m##########lazydocker is already installed. ##########\n\033[m"
    fi
fi
printf "\033[36m########## Done! ##########\033[m"

# 切換到 zsh 並載入配置
exec zsh
source ~/.zshrc


