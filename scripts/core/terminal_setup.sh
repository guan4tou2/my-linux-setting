#!/usr/bin/env bash

# 載入共用函數庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || {
    echo "錯誤: 無法載入共用函數庫"
    exit 1
}

# 如果未定義 URL，使用默認值
P10K_CONFIG_URL="${P10K_CONFIG_URL:-https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main/.p10k.zsh}"

log_info "########## 設定終端機環境 ##########"

# 將登入 shell 改為 zsh（與是否「首次」安裝 Oh My Zsh 無關；舊版只在新裝 omz 時 chsh，已存在 ~/.oh-my-zsh 時會永遠跳過）
ensure_login_shell_zsh() {
    local target_user="${USER:-$(id -un 2>/dev/null || whoami)}"
    local target_shell
    target_shell="$(command -v zsh 2>/dev/null)" || true
    if [ -z "$target_shell" ] || [ ! -x "$target_shell" ]; then
        log_warning "找不到可執行的 zsh，跳過 chsh"
        return 0
    fi

    local current_shell
    current_shell=$(getent passwd "$target_user" 2>/dev/null | cut -d: -f7 || echo "")
    if [ "$current_shell" = "$target_shell" ]; then
        log_info "登入 shell 已是 zsh（$target_shell），無需 chsh"
        return 0
    fi

    if [ "${NON_INTERACTIVE:-false}" = "true" ] && ! sudo -n true 2>/dev/null; then
        log_warning "非互動模式且無 NOPASSWD sudo，略過 chsh；請之後手動執行："
        log_warning "    sudo chsh -s \"$target_shell\" \"$target_user\""
        return 0
    fi

    log_info "將登入 shell 設為 zsh（$target_shell）…"
    if command -v run_as_root >/dev/null 2>&1; then
        run_as_root chsh -s "$target_shell" "$target_user" \
            || log_warning "chsh 失敗，請手動：sudo chsh -s $target_shell $target_user"
    else
        sudo chsh -s "$target_shell" "$target_user" \
            || log_warning "chsh 失敗，請手動：sudo chsh -s $target_shell $target_user"
    fi
}

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
    log_success "Oh-my-zsh 安裝完成"
else
    log_info "Oh-my-zsh 已安裝"
fi

# 統一在這裡設 ZSH_CUSTOM；若 oh-my-zsh 安裝失敗（目錄不存在）就直接結束，避免後續步驟誤用空路徑
ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
export ZSH_CUSTOM

if [ ! -d "$HOME/.oh-my-zsh" ]; then
    log_error "Oh-my-zsh 似乎沒有正確安裝（找不到 $HOME/.oh-my-zsh）"
    log_error "後續的 zsh 插件 / Powerlevel10k 步驟需要它，先中止本模組以免污染環境"
    log_info "可以稍後重跑：bash $SCRIPT_DIR/terminal_setup.sh"
    exit 1
fi

show_progress "設定登入預設 shell 為 zsh"
ensure_login_shell_zsh

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
# 使用 safe_append_to_file 的 pattern 檢查（# linux-setting:path-block）
# 避免原本 sed 搭配含 $HOME 混合展開導致 idempotent 檢查誤判
if command -v safe_append_to_file >/dev/null 2>&1; then
    safe_append_to_file \
        '# linux-setting:path-block
export PATH="$HOME/bin:$HOME/.local/bin:/usr/local/bin:$HOME/go/bin:$PATH"' \
        ~/.zshrc \
        '# linux-setting:path-block'
elif ! grep -q 'linux-setting:path-block' ~/.zshrc 2>/dev/null; then
    printf '\n%s\n%s\n' \
        '# linux-setting:path-block' \
        'export PATH="$HOME/bin:$HOME/.local/bin:/usr/local/bin:$HOME/go/bin:$PATH"' \
        >> ~/.zshrc
fi

# 設定終端環境變數（修復 nvim 顯示問題）
if ! grep -q 'export TERM=' ~/.zshrc; then
    cat >> ~/.zshrc << 'EOF'

# 終端環境設定
export TERM=xterm-256color
export COLORTERM=truecolor
EOF
fi

# ==============================================================================
# 安裝 Powerlevel10k
# ==============================================================================
# 過去用 `[ ! -f ~/.p10k.zsh ]` 判斷是否要裝，但這個檔案上次跑可能已下載成功，
# 但實際的主題目錄 (themes/powerlevel10k) 卻 git clone 失敗（被 `|| true` 吞掉）。
# 改為：分別處理「主題目錄」、「.p10k.zsh 配置」、「.zshrc 的 ZSH_THEME」、
# 「POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD 註記」四件事，每件事都 idempotent。
P10K_THEME_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"

# 1. 確保主題目錄存在（不存在就 clone，存在就 git pull）
if [ -d "$P10K_THEME_DIR/.git" ]; then
    log_info "Powerlevel10k 主題目錄已存在，嘗試更新..."
    GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=30 \
        git -C "$P10K_THEME_DIR" pull --ff-only --quiet 2>/dev/null \
        || log_warning "Powerlevel10k 主題更新失敗，沿用既有版本"
elif [ -d "$P10K_THEME_DIR" ]; then
    log_warning "$P10K_THEME_DIR 已存在但不是 git repo，跳過（可手動刪除後重裝）"
else
    printf "\033[36m安裝 Powerlevel10k 主題\033[0m\n"
    if GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=30 \
            git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
            "$P10K_THEME_DIR" 2>&1; then
        log_success "Powerlevel10k 主題安裝成功"
    else
        log_warning "Powerlevel10k 主題安裝失敗，請檢查網路後手動執行："
        log_warning "    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \"$P10K_THEME_DIR\""
    fi
fi

# 2. 下載 .p10k.zsh 配置檔（不存在才下載）
if [ ! -f ~/.p10k.zsh ]; then
    printf "\033[36m下載 .p10k.zsh 配置\033[0m\n"
    if wget --timeout=30 --tries=2 -q "$P10K_CONFIG_URL" -O ~/.p10k.zsh.tmp 2>/dev/null \
            && [ -s ~/.p10k.zsh.tmp ]; then
        mv ~/.p10k.zsh.tmp ~/.p10k.zsh
        log_success ".p10k.zsh 已下載"
    else
        rm -f ~/.p10k.zsh.tmp
        log_warning ".p10k.zsh 下載失敗，將沿用 powerlevel10k 預設並啟用首次設定精靈"
    fi
fi

# 3. 設定 .zshrc 的 ZSH_THEME（無論主題與配置是否新裝都要檢查；只在還不是 p10k 時改）
if [ -f ~/.zshrc ] && [ -d "$P10K_THEME_DIR" ]; then
    if ! grep -Eq '^[[:space:]]*ZSH_THEME=("|'"'"')?powerlevel10k/powerlevel10k' ~/.zshrc; then
        if grep -q '^[[:space:]]*ZSH_THEME=' ~/.zshrc; then
            sed -i 's|^[[:space:]]*ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' ~/.zshrc
            log_info "已將 ~/.zshrc 的 ZSH_THEME 改為 powerlevel10k"
        else
            printf '\nZSH_THEME="powerlevel10k/powerlevel10k"\n' >> ~/.zshrc
            log_info "已加入 ZSH_THEME=powerlevel10k 到 ~/.zshrc"
        fi
    fi
fi

# 4. 加入「停用 p10k 首次設定精靈」與 source ~/.p10k.zsh（idempotent）
if [ -f ~/.p10k.zsh ]; then
    if command -v safe_append_to_file >/dev/null 2>&1; then
        safe_append_to_file \
            '# linux-setting:p10k-source
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true' \
            ~/.zshrc \
            '# linux-setting:p10k-source'
    elif ! grep -q 'linux-setting:p10k-source' ~/.zshrc 2>/dev/null; then
        cat >> ~/.zshrc << 'P10KEOF'

# linux-setting:p10k-source
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
P10KEOF
    fi
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

# 添加 thefuck alias 到配置文件（runtime guard：thefuck 若未安裝不會噴錯）
# 檢查模式 'thefuck --alias' 同時匹配舊版未守護與新版已守護的寫法，避免重複附加
safe_append_to_file \
    'command -v thefuck >/dev/null 2>&1 && eval "$(thefuck --alias)"' \
    "$HOME/.zshrc" 'thefuck --alias'

# 設定 lsd 別名（runtime guard：lsd 缺失時不會讓 ls/ll/la 全部壞掉）
log_info "設定 lsd 別名 (ls / ll / la，執行期保護)"
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    safe_append_to_file 'command -v lsd >/dev/null 2>&1 && alias ls="lsd"'    "$rc" 'alias ls="lsd"'
    safe_append_to_file 'command -v lsd >/dev/null 2>&1 && alias ll="lsd -l"' "$rc" 'alias ll="lsd -l"'
    safe_append_to_file 'command -v lsd >/dev/null 2>&1 && alias la="lsd -a"' "$rc" 'alias la="lsd -a"'
done

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
