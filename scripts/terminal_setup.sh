#!/bin/sh

# 如果未定義 URL，使用默認值
if [ -z "$P10K_CONFIG_URL" ]; then
    P10K_CONFIG_URL="https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main/.p10k.zsh"
fi

printf "\033[36m########## 設定終端機環境 ##########\n\033[m"

# 安裝必要套件
terminal_packages="zsh fonts-firacode"
for pkg in $terminal_packages; do
    if ! dpkg -l | grep -q "^ii  $pkg"; then
        sudo apt install -y "$pkg"
    else
        printf "\033[36m$pkg 已安裝\033[0m\n"
    fi
done

# 檢查 Zsh 版本
ZSH_VERSION=$(zsh --version | awk '{print $2}')
REQUIRED_VERSION="5.0.8"

if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$ZSH_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]; then
    printf "\033[31mZsh 版本 $ZSH_VERSION 不符合要求，請升級到 $REQUIRED_VERSION 或更新版本\033[0m\n"
    exit 1
fi

# 安裝 oh-my-zsh
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    printf "\033[36m安裝 oh-my-zsh\033[0m\n"
    sudo -k chsh -s "$(command -v zsh)" "$USER"
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
    export ZSH_CUSTOM
fi

# 安裝 zsh 插件
printf "\033[36m安裝 zsh 插件\033[0m\n"
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions 2>/dev/null || true
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting 2>/dev/null || true
git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search 2>/dev/null || true
git clone https://github.com/MichaelAquilina/zsh-you-should-use.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/you-should-use 2>/dev/null || true

# 設定 plugins
if ! grep -q "zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search you-should-use" ~/.zshrc; then
    sed -i 's/^plugins=(.*)/plugins=(git thefuck zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search you-should-use)/g' ~/.zshrc
fi

# 設定 PATH
if ! grep -q "export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$HOME/go/bin:$PATH" ~/.zshrc; then
    sed -i -e 's|# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH|export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$HOME/go/bin:$PATH|' ~/.zshrc
fi

# 安裝 Powerlevel10k
if [ ! -f ~/.p10k.zsh ]; then
    printf "\033[36m安裝 Powerlevel10k\033[0m\n"
    wget "$P10K_CONFIG_URL" -O ~/.p10k.zsh
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
    sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/g' ~/.zshrc
    echo 'POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true' >> ~/.zshrc
fi

# 安裝 thefuck
if ! command -v fuck > /dev/null 2>&1; then
    printf "\033[36m安裝 thefuck\033[0m\n"
    pip install git+https://github.com/nvbn/thefuck
    echo 'eval $(thefuck --alias)' >> ~/.zshrc
fi

printf "\033[36m########## 終端機環境設定完成 ##########\n\033[m"

# 重新載入設定
exec zsh -l 