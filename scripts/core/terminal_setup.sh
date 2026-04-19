#!/usr/bin/env bash
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
    if [ -f "$HOME/.zshrc" ]; then
        backup_file "$HOME/.zshrc"
    else
        log_info "未找到 ~/.zshrc，略過備份"
    fi
    # 在部分容器 / 非互動環境中，$USER 可能為空，改用 whoami 作為後備
    target_user="${USER:-$(id -un 2>/dev/null || whoami)}"

    # 若使用者已經是 zsh 了就跳過，避免再呼叫 chsh（可能觸發密碼 prompt）
    current_shell=$(getent passwd "$target_user" 2>/dev/null | cut -d: -f7 || echo "")
    target_shell="$(command -v zsh)"
    if [ "$current_shell" = "$target_shell" ]; then
        log_info "預設 shell 已是 zsh ($target_shell)，跳過 chsh"
    elif [ "${NON_INTERACTIVE:-false}" = "true" ] && ! sudo -n true 2>/dev/null; then
        log_warning "非互動模式且無 NOPASSWD sudo，跳過 chsh；請事後手動執行："
        log_warning "    sudo chsh -s \"$target_shell\" \"$target_user\""
    else
        # 使用 run_as_root 會走 sudo（若需要）；避免 -k 立即清空憑證快取
        if command -v run_as_root >/dev/null 2>&1; then
            run_as_root chsh -s "$target_shell" "$target_user" \
                || log_warning "chsh 失敗，請手動執行 sudo chsh -s $target_shell $target_user"
        else
            sudo chsh -s "$target_shell" "$target_user" \
                || log_warning "chsh 失敗，請手動執行 sudo chsh -s $target_shell $target_user"
        fi
    fi
    if [ -f "$SCRIPT_DIR/../utils/secure_download.sh" ]; then
        bash "$SCRIPT_DIR/../utils/secure_download.sh" oh-my-zsh
    elif [ -f "$SCRIPT_DIR/utils/secure_download.sh" ]; then
        bash "$SCRIPT_DIR/utils/secure_download.sh" oh-my-zsh
    elif [ -f "$SCRIPT_DIR/secure_download.sh" ]; then
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

# 安裝 zsh 插件（idempotent：已存在時 pull，不存在時 clone）
printf "\033[36m安裝 / 更新 zsh 插件\033[0m\n"
_zsh_plugins_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"
mkdir -p "$_zsh_plugins_dir"
_clone_or_pull() {
    local url="$1" dest="$2"
    if [ -d "$dest/.git" ]; then
        git -C "$dest" pull --ff-only --quiet 2>/dev/null || log_warning "更新 $(basename "$dest") 失敗，沿用舊版"
    elif [ -d "$dest" ]; then
        log_warning "$dest 已存在但不是 git repo，跳過（可手動刪除後重裝）"
    else
        git clone --depth=1 "$url" "$dest" 2>/dev/null || log_warning "安裝 $(basename "$dest") 失敗"
    fi
}
_clone_or_pull https://github.com/zsh-users/zsh-autosuggestions                  "$_zsh_plugins_dir/zsh-autosuggestions"
_clone_or_pull https://github.com/zsh-users/zsh-syntax-highlighting.git          "$_zsh_plugins_dir/zsh-syntax-highlighting"
_clone_or_pull https://github.com/zsh-users/zsh-history-substring-search         "$_zsh_plugins_dir/zsh-history-substring-search"
_clone_or_pull https://github.com/MichaelAquilina/zsh-you-should-use.git         "$_zsh_plugins_dir/you-should-use"

# 設定 plugins
if ! grep -q "zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search you-should-use" ~/.zshrc; then
    sed -i 's/^plugins=(.*)/plugins=(git thefuck zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search you-should-use)/g' ~/.zshrc
fi

# 設定 PATH
if ! grep -q "export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$HOME/go/bin:$PATH" ~/.zshrc; then
    sed -i -e 's|# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH|export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$HOME/go/bin:$PATH|' ~/.zshrc
fi

# 設定終端環境變數（修復 nvim 顯示問題）
if ! grep -q 'export TERM=' ~/.zshrc; then
    cat >> ~/.zshrc << 'EOF'

# 終端環境設定
export TERM=xterm-256color
export COLORTERM=truecolor
EOF
fi

# 安裝 Powerlevel10k
if [ ! -f ~/.p10k.zsh ]; then
    printf "\033[36m安裝 Powerlevel10k\033[0m\n"
    if [ "${TUI_MODE:-quiet}" = "quiet" ]; then
        wget -q "$P10K_CONFIG_URL" -O ~/.p10k.zsh >/dev/null 2>&1
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
            "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" >/dev/null 2>&1 || true
    else
        wget "$P10K_CONFIG_URL" -O ~/.p10k.zsh
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
            "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" || true
    fi
    sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/g' ~/.zshrc
    echo 'POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true' >> ~/.zshrc
fi

# 安裝 thefuck（若尚未安裝）
# 注意: 使用 'thefuck' 二進位檔案檢查，而非 'fuck'（'fuck' 是別名，不是命令）
if ! command -v thefuck > /dev/null 2>&1; then
    printf "\033[36m安裝 thefuck (使用 uv)\033[0m\n"
    
    # 確保 uv 在 PATH 中
    if [ -f "$HOME/.cargo/env" ]; then
        . "$HOME/.cargo/env"
    fi
    
    # 使用 uv 安裝 thefuck，如果失敗則使用 pip
    if command -v uv > /dev/null 2>&1; then
        if [ "${TUI_MODE:-quiet}" = "quiet" ]; then
            uv pip install --python "$HOME/.local/venv/system-tools/bin/python" \
                git+https://github.com/nvbn/thefuck >/dev/null 2>&1 || \
                pip install git+https://github.com/nvbn/thefuck >/dev/null 2>&1
        else
            uv pip install --python "$HOME/.local/venv/system-tools/bin/python" \
                git+https://github.com/nvbn/thefuck || \
                pip install git+https://github.com/nvbn/thefuck
        fi
    else
        printf "\033[33muv 未找到，使用 pip 安裝 thefuck\033[0m\n"
        if [ "${TUI_MODE:-quiet}" = "quiet" ]; then
            pip install git+https://github.com/nvbn/thefuck >/dev/null 2>&1
        else
            pip install git+https://github.com/nvbn/thefuck
        fi
    fi

    # 創建軟連結到 ~/.local/bin（無論安裝方式為何）
    if [ -f "$HOME/.local/venv/system-tools/bin/thefuck" ]; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$HOME/.local/venv/system-tools/bin/thefuck" "$HOME/.local/bin/thefuck"
    fi
fi

# 添加 thefuck alias 到配置文件（無論安裝方式為何）
if ! grep -q 'eval $(thefuck --alias)' ~/.zshrc; then
    echo 'eval $(thefuck --alias)' >> ~/.zshrc
fi

# 設定 lsd 別名（若已安裝 lsd）
if command -v lsd > /dev/null 2>&1; then
    log_info "設定 lsd 別名 (ls / ll / la)"
    safe_append_to_file 'alias ls="lsd"' "$HOME/.zshrc" 'alias ls="lsd"'
    safe_append_to_file 'alias ll="lsd -l"' "$HOME/.zshrc" 'alias ll="lsd -l"'
    safe_append_to_file 'alias la="lsd -a"' "$HOME/.zshrc" 'alias la="lsd -a"'
    safe_append_to_file 'alias ls="lsd"' "$HOME/.bashrc" 'alias ls="lsd"'
    safe_append_to_file 'alias ll="lsd -l"' "$HOME/.bashrc" 'alias ll="lsd -l"'
    safe_append_to_file 'alias la="lsd -a"' "$HOME/.bashrc" 'alias la="lsd -a"'
fi

printf "\033[36m########## 終端機環境設定完成 ##########\n\033[m"

# 提示用戶切換到 zsh（不自動執行 exec，避免中斷安裝流程）
log_success "終端機設定已完成！"
log_info ""
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "  ${GREEN}✓${NC} Zsh + Oh-My-Zsh + Powerlevel10k 已安裝"
log_info "  ${GREEN}✓${NC} 插件已配置 (autosuggestions, syntax-highlighting 等)"
log_info "  ${GREEN}✓${NC} 別名已設定 (lsd, bat 等)"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info ""
log_info "${CYAN}下一步：${NC}請在所有模組安裝完成後，執行以下命令切換到 zsh："
printf "\n    ${GREEN}exec zsh -l${NC}\n\n"
log_info "或者重新登入系統以應用更改。"
log_info "" 
