#!/bin/sh

printf "\033[36m########## 安裝 Docker 相關工具 ##########\n\033[m"

# 安裝 Docker
if ! command -v docker > /dev/null 2>&1; then
    printf "\033[36m安裝 Docker\033[0m\n"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    
    # 將當前用戶加入 docker 群組
    sudo usermod -aG docker "$USER"
fi

# 安裝 lazydocker
if ! command -v lazydocker > /dev/null 2>&1; then
    printf "\033[36m安裝 Lazydocker\033[0m\n"
    curl https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash
    echo 'alias lzd="lazydocker"' >> ~/.zshrc
fi

printf "\033[36m########## Docker 相關工具安裝完成 ##########\n\033[m" 