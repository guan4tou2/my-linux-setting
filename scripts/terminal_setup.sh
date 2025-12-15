#!/bin/bash

# 載入共用函數庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || {
    echo "錯誤: 無法載入共用函數庫"
    exit 1
}

# 如果未定義 URL，使用默認值
if [ -z "$P10K_CONFIG_URL" ]; then
    P10K_CONFIG_URL="https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main/.p10k.zsh"
fi

log_info "########## 設定終端機環境 ##########"

# 初始化進度
init_progress 8

# 安裝必要套件
show_progress "安裝終端基礎套件"
terminal_packages="zsh fonts-firacode"

for pkg in $terminal_packages; do
    install_apt_package "$pkg"
done

# 檢查 Zsh 版本
show_progress "檢查 Zsh 版本"
ZSH_VERSION=$(zsh --version | awk '{print $2}')
REQUIRED_VERSION="5.0.8"

if ! version_greater_equal "$ZSH_VERSION" "$REQUIRED_VERSION"; then
    log_error "Zsh 版本 $ZSH_VERSION 不符合要求，請升級到 $REQUIRED_VERSION 或更新版本"
    exit 1
fi
log_success "Zsh 版本檢查通過: $ZSH_VERSION"

# 安裝 oh-my-zsh
show_progress "安裝 Oh-my-zsh"
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    log_info "安裝 oh-my-zsh"
    backup_file "$HOME/.zshrc"
    sudo -k chsh -s "$(command -v zsh)" "$USER"
    if [ -f "$SCRIPT_DIR/secure_download.sh" ]; then
        bash "$SCRIPT_DIR/secure_download.sh" oh-my-zsh
    else
        log_warning "找不到安全下載腳本，使用傳統安裝方式"
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi
    ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
    export ZSH_CUSTOM
    log_success "Oh-my-zsh 安裝完成"
else
    log_info "Oh-my-zsh 已安裝"
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
    printf "\033[36m安裝 thefuck (使用 uv)\033[0m\n"
    
    # 確保 uv 在 PATH 中
    if [ -f "$HOME/.cargo/env" ]; then
        . "$HOME/.cargo/env"
    fi
    
    # 使用 uv 安裝 thefuck，如果失敗則使用 pip
    if command -v uv > /dev/null 2>&1; then
        uv tool install thefuck || pip install git+https://github.com/nvbn/thefuck
    else
        printf "\033[33muv 未找到，使用 pip 安裝 thefuck\033[0m\n"
        pip install git+https://github.com/nvbn/thefuck
    fi
    
    # 添加 thefuck alias 到配置文件
    if ! grep -q 'eval $(thefuck --alias)' ~/.zshrc; then
        echo 'eval $(thefuck --alias)' >> ~/.zshrc
    fi
fi

printf "\033[36m########## 終端機環境設定完成 ##########\n\033[m"

# 重新載入設定
exec zsh -l 