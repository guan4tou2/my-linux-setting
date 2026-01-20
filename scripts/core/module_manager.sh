#!/usr/bin/env bash

# ==============================================================================
# Module Manager - 模組管理器
# ==============================================================================
#
# 提供模組配置的讀取、解析和安裝功能
# 讓用戶可以透過修改 config/modules.conf 來自訂安裝內容
#
# ==============================================================================

# 配置文件路徑
MODULES_CONF="${MODULES_CONF:-}"

# 模組資料存儲（使用關聯陣列）
declare -A MODULE_NAMES
declare -A MODULE_DESCRIPTIONS
declare -A MODULE_PACKAGES
declare -A MODULE_BREW_PACKAGES
declare -A MODULE_APT_FALLBACK
declare -A MODULE_PIP_PACKAGES
declare -A MODULE_CARGO_PACKAGES
declare -A MODULE_NPM_PACKAGES
declare -A MODULE_SCRIPTS
declare -A MODULE_POST_INSTALL

# 模組列表（保持順序）
MODULE_LIST=()

# ==============================================================================
# 配置文件定位
# ==============================================================================

find_modules_conf() {
    local search_paths=(
        "$MODULES_CONF"
        "$PWD/config/modules.conf"
        "$SCRIPT_DIR/../config/modules.conf"
        "$SCRIPT_DIR/../../config/modules.conf"
        "$HOME/.config/linux-setting/modules.conf"
    )

    for path in "${search_paths[@]}"; do
        if [ -n "$path" ] && [ -f "$path" ]; then
            echo "$path"
            return 0
        fi
    done

    return 1
}

# ==============================================================================
# 配置文件解析
# ==============================================================================

parse_modules_conf() {
    local conf_file
    conf_file=$(find_modules_conf) || {
        log_warning "找不到模組配置文件，使用預設配置"
        return 1
    }

    log_info "載入模組配置: $conf_file"

    local current_module=""
    local line_number=0

    while IFS= read -r line || [ -n "$line" ]; do
        line_number=$((line_number + 1))

        # 跳過空行和註解
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # 去除首尾空白
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # 檢測模組標頭 [module_name]
        if [[ "$line" =~ ^\[([a-zA-Z0-9_-]+)\]$ ]]; then
            current_module="${BASH_REMATCH[1]}"
            MODULE_LIST+=("$current_module")
            log_debug "發現模組: $current_module"
            continue
        fi

        # 解析鍵值對
        if [[ -n "$current_module" && "$line" =~ ^([a-zA-Z_]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            case "$key" in
                name)
                    MODULE_NAMES["$current_module"]="$value"
                    ;;
                description)
                    MODULE_DESCRIPTIONS["$current_module"]="$value"
                    ;;
                packages)
                    MODULE_PACKAGES["$current_module"]="$value"
                    ;;
                brew_packages)
                    MODULE_BREW_PACKAGES["$current_module"]="$value"
                    ;;
                apt_fallback)
                    MODULE_APT_FALLBACK["$current_module"]="$value"
                    ;;
                pip_packages)
                    MODULE_PIP_PACKAGES["$current_module"]="$value"
                    ;;
                cargo_packages)
                    MODULE_CARGO_PACKAGES["$current_module"]="$value"
                    ;;
                npm_packages)
                    MODULE_NPM_PACKAGES["$current_module"]="$value"
                    ;;
                script)
                    MODULE_SCRIPTS["$current_module"]="$value"
                    ;;
                post_install)
                    MODULE_POST_INSTALL["$current_module"]="$value"
                    ;;
            esac
        fi
    done < "$conf_file"

    log_success "已載入 ${#MODULE_LIST[@]} 個模組"
    return 0
}

# ==============================================================================
# 模組資訊查詢
# ==============================================================================

# 取得所有模組 ID
get_module_ids() {
    echo "${MODULE_LIST[@]}"
}

# 取得模組數量
get_module_count() {
    echo "${#MODULE_LIST[@]}"
}

# 取得模組顯示名稱
get_module_name() {
    local module_id="$1"
    echo "${MODULE_NAMES[$module_id]:-$module_id}"
}

# 取得模組描述
get_module_description() {
    local module_id="$1"
    echo "${MODULE_DESCRIPTIONS[$module_id]:-}"
}

# 取得模組套件列表
get_module_packages() {
    local module_id="$1"
    echo "${MODULE_PACKAGES[$module_id]:-}"
}

# 取得模組 Homebrew 套件
get_module_brew_packages() {
    local module_id="$1"
    echo "${MODULE_BREW_PACKAGES[$module_id]:-}"
}

# 取得模組安裝腳本
get_module_script() {
    local module_id="$1"
    echo "${MODULE_SCRIPTS[$module_id]:-}"
}

# 檢查模組是否存在
module_exists() {
    local module_id="$1"
    [ -n "${MODULE_NAMES[$module_id]+x}" ]
}

# ==============================================================================
# 模組狀態檢查
# ==============================================================================

# 檢查模組安裝狀態
# 返回: "installed" | "partial" | "not_installed"
check_module_status() {
    local module_id="$1"
    local total=0
    local installed=0

    # 檢查 APT/系統套件
    local packages="${MODULE_PACKAGES[$module_id]:-}"
    if [ -n "$packages" ]; then
        for pkg in $packages; do
            total=$((total + 1))
            if check_package_installed "$pkg" 2>/dev/null; then
                installed=$((installed + 1))
            fi
        done
    fi

    # 檢查 Homebrew 套件
    local brew_packages="${MODULE_BREW_PACKAGES[$module_id]:-}"
    local apt_fallback="${MODULE_APT_FALLBACK[$module_id]:-}"
    if [ -n "$brew_packages" ]; then
        if command -v brew >/dev/null 2>&1; then
            # brew 存在，檢查 brew 套件
            for pkg in $brew_packages; do
                total=$((total + 1))
                if check_brew_package_installed "$pkg" 2>/dev/null; then
                    installed=$((installed + 1))
                fi
            done
        elif [ -n "$apt_fallback" ]; then
            # brew 不存在但有 apt fallback，檢查 fallback 套件
            for pkg in $apt_fallback; do
                total=$((total + 1))
                if check_package_installed "$pkg" 2>/dev/null; then
                    installed=$((installed + 1))
                fi
            done
        else
            # brew 不存在且無 fallback，將 brew 套件計為未安裝
            for pkg in $brew_packages; do
                total=$((total + 1))
                # 不增加 installed，視為未安裝
            done
        fi
    fi

    # 檢查 Python 套件
    local pip_packages="${MODULE_PIP_PACKAGES[$module_id]:-}"
    if [ -n "$pip_packages" ]; then
        for pkg in $pip_packages; do
            total=$((total + 1))
            if check_pip_package_installed "$pkg" 2>/dev/null; then
                installed=$((installed + 1))
            fi
        done
    fi

    # 檢查 Cargo 套件
    local cargo_packages="${MODULE_CARGO_PACKAGES[$module_id]:-}"
    if [ -n "$cargo_packages" ] && command -v cargo >/dev/null 2>&1; then
        for pkg in $cargo_packages; do
            total=$((total + 1))
            if check_cargo_package_installed "$pkg" 2>/dev/null; then
                installed=$((installed + 1))
            fi
        done
    fi

    # 檢查 NPM 套件
    local npm_packages="${MODULE_NPM_PACKAGES[$module_id]:-}"
    if [ -n "$npm_packages" ] && command -v npm >/dev/null 2>&1; then
        for pkg in $npm_packages; do
            total=$((total + 1))
            if check_npm_package_installed "$pkg" 2>/dev/null; then
                installed=$((installed + 1))
            fi
        done
    fi

    # 返回狀態
    if [ $total -eq 0 ]; then
        # 沒有套件定義，檢查是否有腳本
        local script="${MODULE_SCRIPTS[$module_id]:-}"
        if [ -n "$script" ]; then
            echo "not_installed"
        else
            echo "not_installed"
        fi
    elif [ $installed -eq $total ]; then
        echo "installed"
    elif [ $installed -gt 0 ]; then
        echo "partial"
    else
        echo "not_installed"
    fi
}

# 獲取模組詳細狀態（返回格式化的詳細狀態）
get_module_detail_status() {
    local module_id="$1"
    local detail=""

    local name="${MODULE_NAMES[$module_id]:-$module_id}"
    local desc="${MODULE_DESCRIPTIONS[$module_id]:-}"
    local status
    status=$(check_module_status "$module_id")

    # 狀態標記
    case "$status" in
        installed)     detail+="[✓] $name (已安裝)\n" ;;
        partial)       detail+="[◐] $name (部分安裝)\n" ;;
        not_installed) detail+="[ ] $name (未安裝)\n" ;;
    esac

    [ -n "$desc" ] && detail+="    $desc\n" || true
    detail+="\n"

    # APT/系統套件
    local packages="${MODULE_PACKAGES[$module_id]:-}"
    if [ -n "$packages" ]; then
        detail+="系統套件:\n"
        for pkg in $packages; do
            if check_package_installed "$pkg" 2>/dev/null; then
                detail+="  ✓ $pkg\n"
            else
                detail+="  ✗ $pkg\n"
            fi
        done
        detail+="\n"
    fi

    # Homebrew 套件
    local brew_packages="${MODULE_BREW_PACKAGES[$module_id]:-}"
    local apt_fallback="${MODULE_APT_FALLBACK[$module_id]:-}"
    if [ -n "$brew_packages" ]; then
        if command -v brew >/dev/null 2>&1; then
            detail+="Homebrew 套件:\n"
            for pkg in $brew_packages; do
                if check_brew_package_installed "$pkg" 2>/dev/null; then
                    detail+="  ✓ $pkg\n"
                else
                    detail+="  ✗ $pkg\n"
                fi
            done
        elif [ -n "$apt_fallback" ]; then
            detail+="Homebrew 套件 (使用 APT 替代):\n"
            for pkg in $apt_fallback; do
                if check_package_installed "$pkg" 2>/dev/null; then
                    detail+="  ✓ $pkg (apt)\n"
                else
                    detail+="  ✗ $pkg (apt)\n"
                fi
            done
        else
            detail+="Homebrew 套件 (brew 未安裝):\n"
            for pkg in $brew_packages; do
                detail+="  ✗ $pkg (需要 brew)\n"
            done
        fi
        detail+="\n"
    fi

    # Python 套件
    local pip_packages="${MODULE_PIP_PACKAGES[$module_id]:-}"
    if [ -n "$pip_packages" ]; then
        detail+="Python 套件 (uv tool):\n"
        for pkg in $pip_packages; do
            if check_pip_package_installed "$pkg" 2>/dev/null; then
                detail+="  ✓ $pkg\n"
            else
                detail+="  ✗ $pkg\n"
            fi
        done
        detail+="\n"
    fi

    # Cargo 套件
    local cargo_packages="${MODULE_CARGO_PACKAGES[$module_id]:-}"
    if [ -n "$cargo_packages" ]; then
        detail+="Rust 套件 (cargo):\n"
        for pkg in $cargo_packages; do
            if command -v cargo >/dev/null 2>&1 && check_cargo_package_installed "$pkg" 2>/dev/null; then
                detail+="  ✓ $pkg\n"
            else
                detail+="  ✗ $pkg\n"
            fi
        done
        detail+="\n"
    fi

    # NPM 套件
    local npm_packages="${MODULE_NPM_PACKAGES[$module_id]:-}"
    if [ -n "$npm_packages" ]; then
        detail+="Node.js 套件 (npm):\n"
        for pkg in $npm_packages; do
            if command -v npm >/dev/null 2>&1 && check_npm_package_installed "$pkg" 2>/dev/null; then
                detail+="  ✓ $pkg\n"
            else
                detail+="  ✗ $pkg\n"
            fi
        done
        detail+="\n"
    fi

    # 安裝腳本
    local script="${MODULE_SCRIPTS[$module_id]:-}"
    if [ -n "$script" ]; then
        detail+="安裝腳本: $script\n"
    fi

    echo -e "$detail"
}

# 獲取模組狀態標記符號
get_module_status_icon() {
    local module_id="$1"
    local status
    status=$(check_module_status "$module_id")

    case "$status" in
        installed)     echo "✓" ;;
        partial)       echo "◐" ;;
        not_installed) echo " " ;;
    esac
}

# ==============================================================================
# 動態選單生成
# ==============================================================================

# 生成 CLI 選單
generate_cli_menu() {
    local index=1

    printf "\n"
    printf "${CYAN}┌─ 選擇安裝模組 ─────────────────────────────────────────────┐${NC}\n"
    printf "${CYAN}│                                                             │${NC}\n"

    for module_id in "${MODULE_LIST[@]}"; do
        local name="${MODULE_NAMES[$module_id]}"
        local desc="${MODULE_DESCRIPTIONS[$module_id]}"
        printf "${CYAN}│${NC}  ${GREEN}[%d]${NC} %-20s %-30s${CYAN}│${NC}\n" "$index" "$name" "$desc"
        index=$((index + 1))
    done

    printf "${CYAN}│${NC}  ${GREEN}[%d]${NC} %-20s %-30s${CYAN}│${NC}\n" "$index" "全部安裝" ""
    printf "${CYAN}│                                                             │${NC}\n"
    printf "${CYAN}├─────────────────────────────────────────────────────────────┤${NC}\n"

    # 顯示當前選擇
    if [ -n "${selected_modules:-}" ]; then
        printf "${CYAN}│${NC}  ${YELLOW}已選擇:${NC} %-48s${CYAN}│${NC}\n" "$selected_modules"
    else
        printf "${CYAN}│${NC}  ${YELLOW}已選擇:${NC} (尚未選擇)                                    ${CYAN}│${NC}\n"
    fi

    printf "${CYAN}│                                                             │${NC}\n"
    printf "${CYAN}│${NC}  ${BLUE}[i]${NC} 開始安裝  ${BLUE}[c]${NC} 清除  ${BLUE}[d]${NC} 詳細說明  ${BLUE}[q]${NC} 退出        ${CYAN}│${NC}\n"
    printf "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}\n"
    printf "\n輸入選項 (例如: 1 3 4): "
}

# 生成 TUI checklist 項目
generate_tui_checklist_items() {
    local items=""
    for module_id in "${MODULE_LIST[@]}"; do
        local name="${MODULE_NAMES[$module_id]}"
        local desc="${MODULE_DESCRIPTIONS[$module_id]}"
        items+="$module_id|$name ($desc) "
    done
    echo "$items"
}

# 生成詳細說明
generate_module_details() {
    printf "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"

    local index=1
    for module_id in "${MODULE_LIST[@]}"; do
        local name="${MODULE_NAMES[$module_id]}"
        local packages="${MODULE_PACKAGES[$module_id]}"
        local brew_packages="${MODULE_BREW_PACKAGES[$module_id]}"
        local pip_packages="${MODULE_PIP_PACKAGES[$module_id]}"

        printf "${GREEN}[%d] %s${NC}\n" "$index" "$name"

        [ -n "$packages" ] && printf "    APT: %s\n" "$packages"
        [ -n "$brew_packages" ] && printf "    Brew: %s\n" "$brew_packages"
        [ -n "$pip_packages" ] && printf "    Pip: %s\n" "$pip_packages"
        printf "\n"

        index=$((index + 1))
    done

    printf "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
    printf "\n按 Enter 返回選單..."
    read -r
}

# ==============================================================================
# 模組安裝
# ==============================================================================

# 透過編號取得模組 ID
get_module_id_by_number() {
    local num="$1"
    local index=1

    for module_id in "${MODULE_LIST[@]}"; do
        if [ "$index" -eq "$num" ]; then
            echo "$module_id"
            return 0
        fi
        index=$((index + 1))
    done

    # 如果是最後一個數字（全部安裝）
    if [ "$num" -eq "$index" ]; then
        echo "all"
        return 0
    fi

    return 1
}

# 安裝單個模組
install_module() {
    local module_id="$1"

    if ! module_exists "$module_id"; then
        log_error "模組不存在: $module_id"
        return 1
    fi

    local name="${MODULE_NAMES[$module_id]}"
    local packages="${MODULE_PACKAGES[$module_id]}"
    local brew_packages="${MODULE_BREW_PACKAGES[$module_id]}"
    local apt_fallback="${MODULE_APT_FALLBACK[$module_id]}"
    local pip_packages="${MODULE_PIP_PACKAGES[$module_id]}"
    local cargo_packages="${MODULE_CARGO_PACKAGES[$module_id]}"
    local npm_packages="${MODULE_NPM_PACKAGES[$module_id]}"
    local script="${MODULE_SCRIPTS[$module_id]}"
    local post_install="${MODULE_POST_INSTALL[$module_id]}"

    # 檢查模組安裝狀態
    local module_status
    module_status=$(check_module_status "$module_id" 2>/dev/null || echo "not_installed")

    log_info "安裝模組: $name"

    if [ "$module_status" = "installed" ]; then
        log_info "模組 $name 已完全安裝，跳過套件安裝步驟"
    else
        # 統計安裝情況
        local skipped_count=0
        local installed_count=0

        # 1. 安裝 APT 套件（跳過已安裝的）
        if [ -n "$packages" ]; then
            log_info "檢查系統套件..."
            for pkg in $packages; do
                if check_package_installed "$pkg" 2>/dev/null; then
                    log_info "✓ $pkg 已安裝，跳過"
                    skipped_count=$((skipped_count + 1))
                else
                    install_package "$pkg" || log_warning "套件安裝失敗: $pkg"
                    installed_count=$((installed_count + 1))
                fi
            done
        fi

        # 2. 安裝 Homebrew 套件（如果可用，跳過已安裝的）
        if [ -n "$brew_packages" ] && command -v brew >/dev/null 2>&1; then
            log_info "檢查 Homebrew 套件..."
            for pkg in $brew_packages; do
                if check_brew_package_installed "$pkg" 2>/dev/null; then
                    log_info "✓ $pkg 已安裝 (brew)，跳過"
                    skipped_count=$((skipped_count + 1))
                else
                    install_brew_package "$pkg" || log_warning "Brew 套件安裝失敗: $pkg"
                    installed_count=$((installed_count + 1))
                fi
            done
        elif [ -n "$apt_fallback" ]; then
            # Homebrew 不可用，使用 APT 替代
            log_info "使用 APT 替代套件..."
            for pkg in $apt_fallback; do
                if check_package_installed "$pkg" 2>/dev/null; then
                    log_info "✓ $pkg 已安裝，跳過"
                    skipped_count=$((skipped_count + 1))
                else
                    install_package "$pkg" || log_warning "套件安裝失敗: $pkg"
                    installed_count=$((installed_count + 1))
                fi
            done
        fi

        # 3. 安裝 Python 套件（統一使用 uv tool，跳過已安裝的）
        if [ -n "$pip_packages" ]; then
            log_info "檢查 Python 套件..."

            # 確保 uv 已安裝
            if ! command -v uv >/dev/null 2>&1; then
                log_info "安裝 uv..."
                curl -LsSf https://astral.sh/uv/install.sh | sh
                export PATH="$HOME/.local/bin:$PATH"
            fi

            for pkg in $pip_packages; do
                if check_pip_package_installed "$pkg" 2>/dev/null; then
                    log_info "✓ $pkg 已安裝 (pip/uv)，跳過"
                    skipped_count=$((skipped_count + 1))
                else
                    log_info "安裝 $pkg..."
                    if uv tool install "$pkg" 2>/dev/null; then
                        log_success "$pkg 安裝成功"
                        installed_count=$((installed_count + 1))
                    else
                        log_warning "$pkg 安裝失敗，嘗試使用 pipx..."
                        if pipx install "$pkg" 2>/dev/null; then
                            installed_count=$((installed_count + 1))
                        else
                            log_warning "無法安裝 $pkg"
                        fi
                    fi
                fi
            done
        fi

        # 4. 安裝 Cargo 套件（跳過已安裝的）
        if [ -n "$cargo_packages" ] && command -v cargo >/dev/null 2>&1; then
            log_info "檢查 Rust 套件..."
            for pkg in $cargo_packages; do
                if check_cargo_package_installed "$pkg" 2>/dev/null; then
                    log_info "✓ $pkg 已安裝 (cargo)，跳過"
                    skipped_count=$((skipped_count + 1))
                else
                    if cargo install "$pkg" 2>/dev/null; then
                        installed_count=$((installed_count + 1))
                    else
                        log_warning "Cargo 套件安裝失敗: $pkg"
                    fi
                fi
            done
        fi

        # 5. 安裝 NPM 套件（跳過已安裝的）
        if [ -n "$npm_packages" ] && command -v npm >/dev/null 2>&1; then
            log_info "檢查 Node.js 套件..."
            for pkg in $npm_packages; do
                if check_npm_package_installed "$pkg" 2>/dev/null; then
                    log_info "✓ $pkg 已安裝 (npm)，跳過"
                    skipped_count=$((skipped_count + 1))
                else
                    if npm install -g "$pkg" 2>/dev/null; then
                        installed_count=$((installed_count + 1))
                    else
                        log_warning "NPM 套件安裝失敗: $pkg"
                    fi
                fi
            done
        fi

        # 顯示安裝統計
        if [ $skipped_count -gt 0 ] || [ $installed_count -gt 0 ]; then
            log_info "套件安裝統計: 新安裝 $installed_count 個，跳過 $skipped_count 個（已安裝）"
        fi
    fi

    # 6. 執行自訂安裝腳本（無論狀態都執行，因為腳本可能有額外配置）
    if [ -n "$script" ]; then
        local script_path="$SCRIPT_DIR/core/$script"
        if [ -f "$script_path" ]; then
            log_info "執行安裝腳本: $script"
            bash "$script_path" || {
                log_error "腳本執行失敗: $script"
                return 1
            }
        else
            log_warning "找不到腳本: $script_path"
        fi
    fi

    # 7. 執行安裝後命令
    if [ -n "$post_install" ]; then
        log_info "執行安裝後命令..."
        eval "$post_install" || log_warning "安裝後命令執行失敗"
    fi

    log_success "模組安裝完成: $name"
    return 0
}

# ==============================================================================
# 初始化
# ==============================================================================

init_module_manager() {
    # 解析配置文件
    parse_modules_conf || {
        # 如果找不到配置文件，使用預設模組
        log_info "使用內建預設模組"
        MODULE_LIST=(python docker base terminal dev monitoring)
        MODULE_NAMES=(
            [python]="Python 開發環境"
            [docker]="Docker 工具"
            [base]="基礎工具"
            [terminal]="終端設定"
            [dev]="開發工具"
            [monitoring]="監控工具"
        )
        MODULE_DESCRIPTIONS=(
            [python]="python3, pip, uv, ranger"
            [docker]="docker-ce, lazydocker"
            [base]="git, lsd, bat, ripgrep, fzf"
            [terminal]="zsh, oh-my-zsh, powerlevel10k"
            [dev]="neovim, lazygit, nodejs, rust"
            [monitoring]="btop, htop, iftop, fail2ban"
        )
        MODULE_SCRIPTS=(
            [python]="python_setup.sh"
            [docker]="docker_setup.sh"
            [base]="base_tools.sh"
            [terminal]="terminal_setup.sh"
            [dev]="dev_tools.sh"
            [monitoring]="monitoring_tools.sh"
        )
    }
}

# 導出函數
export -f find_modules_conf parse_modules_conf 2>/dev/null || true
export -f get_module_ids get_module_count get_module_name get_module_description 2>/dev/null || true
export -f get_module_packages get_module_brew_packages get_module_script module_exists 2>/dev/null || true
export -f generate_cli_menu generate_tui_checklist_items generate_module_details 2>/dev/null || true
export -f get_module_id_by_number install_module init_module_manager 2>/dev/null || true
export -f check_module_status get_module_detail_status get_module_status_icon 2>/dev/null || true
