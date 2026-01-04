#!/usr/bin/env bash

# ==============================================================================
# Linux 環境設定腳本 - 安裝工具
# ==============================================================================

# 解析命令行參數
INSTALL_MODE="full"
UPDATE_MODE=false
VERBOSE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --minimal)
            INSTALL_MODE="minimal"
            shift
            ;;
        --update)
            UPDATE_MODE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            DEBUG=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "未知參數: $1"
            show_help
            exit 1
            ;;
    esac
done

# 錯誤處理
set -eE
trap 'handle_error $? $LINENO' ERR

# 配置下載網址（可根據需要修改）
REPO_URL=${REPO_URL:-"https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main"}
SCRIPTS_URL=${SCRIPTS_URL:-"$REPO_URL/scripts"}
P10K_CONFIG_URL=${P10K_CONFIG_URL:-"$REPO_URL/.p10k.zsh"}
REQUIREMENTS_URL=${REQUIREMENTS_URL:-"$REPO_URL/requirements.txt"}

# 性能優化選項
ENABLE_PARALLEL_INSTALL=${ENABLE_PARALLEL_INSTALL:-true}
PARALLEL_JOBS=${PARALLEL_JOBS:-4}

# 導出變數供子腳本使用
export REPO_URL SCRIPTS_URL P10K_CONFIG_URL REQUIREMENTS_URL
export INSTALL_MODE UPDATE_MODE VERBOSE DEBUG DRY_RUN
export ENABLE_PARALLEL_INSTALL PARALLEL_JOBS

# 載入共用函數庫
SCRIPT_DIR="$PWD/scripts"
if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
elif [ -f "./scripts/core/common.sh" ]; then
    source "./scripts/core/common.sh"
else
    # 遠程下載共用函數庫
    TEMP_DIR=$(mktemp -d)
    SCRIPT_DIR="$TEMP_DIR/scripts"
    mkdir -p "$SCRIPT_DIR/core"
    curl -fsSL "$SCRIPTS_URL/core/common.sh" -o "$SCRIPT_DIR/core/common.sh"
    source "$SCRIPT_DIR/core/common.sh"
    REMOTE_INSTALL=true
fi

# 初始化環境
init_common_env

# 幫助函數
show_help() {
    cat << EOF
Linux Setting Scripts - 自動安裝腳本

用法: $0 [選項]

選項:
  --minimal                       最小安裝模式
  --update                        更新已安裝的組件
  --dry-run                       預覽模式（不實際安裝）
  -v, --verbose                   顯示詳細日誌
  -h, --help                      顯示此幫助訊息

範例:
  $0                             # 標準安裝（互動式選單）
  $0 --minimal                   # 最小安裝
  $0 --dry-run                   # 預覽將要安裝的內容
  $0 --update                    # 更新模式
  $0 --verbose                   # 詳細模式

EOF
}

# 錯誤處理函數
handle_error() {
    local exit_code=$1
    local line_number=$2
    log_error "腳本在第 $line_number 行出錯（錯誤碼：$exit_code）"
    log_error "請檢查日誌文件：${LOG_FILE:-/tmp/install.log}"
    
    # 嘗試回滾
    if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
        read -p "是否要回滾到安裝前狀態？(y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rollback_installation
        fi
    fi
    
    cleanup_temp_files
    exit $exit_code
}

# 回滾機制
rollback_installation() {
    log_info "開始回滾安裝..."
    
    if [ -d "$BACKUP_DIR" ]; then
        for backup_file in "$BACKUP_DIR"/*; do
            if [ -f "$backup_file" ]; then
                local original_name
                original_name=$(basename "$backup_file" | sed 's/\.backup\.[0-9_]*$//')
                local original_path="$HOME/$original_name"
                
                if [[ "$original_name" == .* ]]; then
                    original_path="$HOME/$original_name"
                else
                    original_path="$HOME/.$original_name"
                fi
                
                cp "$backup_file" "$original_path"
                log_info "已回滾: $original_path"
            fi
        done
        log_success "回滾完成"
    else
        log_warning "找不到備份目錄，無法回滾"
    fi
}

# 清理函數  
cleanup() {
    cleanup_temp_files
}

# 增強的環境檢查函數
check_environment() {
    log_info "檢查系統環境..."

    # 檢測發行版（如果 common.sh 已載入，變數已設定）
    if [ -z "$DISTRO" ]; then
        DISTRO=$(detect_distro 2>/dev/null || echo "unknown")
        DISTRO_FAMILY=$(get_distro_family "$DISTRO" 2>/dev/null || echo "unknown")
        PKG_MANAGER=$(get_package_manager "$DISTRO_FAMILY" 2>/dev/null || echo "apt")
    fi

    log_info "檢測到系統：$DISTRO ($DISTRO_FAMILY) - 包管理器：$PKG_MANAGER"

    # 檢查是否為支援的發行版
    if [ "$DISTRO_FAMILY" = "unknown" ]; then
        log_warning "無法檢測 Linux 發行版，將嘗試使用預設設定"
    fi

    # 優化 APT 性能（Debian 系列）
    if [ "$DISTRO_FAMILY" = "debian" ] && command -v optimize_apt_performance >/dev/null 2>&1; then
        optimize_apt_performance || log_warning "APT 優化失敗，繼續安裝"
    fi

    # 檢測並啟用 TUI（如果可用）
    if [ -t 0 ] && [ "${INSTALL_MODE}" != "minimal" ]; then
        if command -v ensure_tui_available >/dev/null 2>&1; then
            ensure_tui_available && log_success "TUI 模式已啟用" || log_info "使用命令行模式"
        fi
    fi

    # 檢查並提示安裝 Homebrew（可選）
    if ! command -v brew >/dev/null 2>&1; then
        log_info "檢測到系統未安裝 Homebrew"
        log_info "Homebrew 可以簡化某些工具的安裝（如 lsd、tealdeer、lazygit 等）"

        # 如果不是非互動模式，詢問用戶
        if [ -t 0 ] && [ "${INSTALL_MODE}" != "minimal" ]; then
            local install_brew_answer=""

            # 嘗試使用 TUI 對話框
            if [ "$USE_TUI" = "true" ] && command -v tui_yesno >/dev/null 2>&1; then
                if tui_yesno "Homebrew 安裝" "Homebrew 可以簡化工具安裝並節省編譯時間。\n\n是否要安裝 Homebrew？\n\n建議：如果您要安裝 lsd、tealdeer、Rust、Neovim、Lazygit 等工具，建議安裝 Homebrew。" "no"; then
                    install_brew_answer="y"
                else
                    install_brew_answer="n"
                fi
            else
                # 命令行模式
                printf "${YELLOW}是否要安裝 Homebrew？${NC} [y/N]: "
                read -r install_brew_answer
            fi

            if [[ "$install_brew_answer" =~ ^[Yy]$ ]]; then
                if command -v ensure_homebrew_installed >/dev/null 2>&1; then
                    ensure_homebrew_installed || log_warning "Homebrew 安裝失敗，將使用其他方式安裝工具"
                else
                    log_warning "找不到 Homebrew 安裝函數，跳過"
                fi
            else
                log_info "跳過 Homebrew 安裝，將使用傳統方式安裝工具"
            fi
        fi
    else
        log_success "檢測到 Homebrew 已安裝，將優先使用 brew 安裝工具"
    fi

    # 檢查系統版本
    if [ -f /etc/os-release ]; then
        local os_version
        os_version=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2 2>/dev/null || echo "unknown")
        log_info "系統版本: $os_version"
    fi
    
    # 檢查系統架構兼容性
    if ! check_architecture_compatibility; then
        log_error "系統架構不受支援"
        exit 1
    fi
    
    # 檢查 Python 版本，如果不滿足要求則嘗試安裝
    if [ "$SKIP_PYTHON_CHECK" = "true" ]; then
        log_info "跳過 Python 版本檢查（環境變數設定）"
    elif ! check_python_version "3.8"; then
        log_warning "Python 版本不滿足要求，嘗試安裝 Python 3+"
        # 使用通用安裝方式
        if command -v update_system >/dev/null 2>&1; then
            update_system
        fi
        if command -v install_package >/dev/null 2>&1; then
            install_package python3 && install_package python3-pip
        else
            case "$PKG_MANAGER" in
                apt) run_as_root apt-get install -y python3 python3-venv python3-pip ;;
                dnf|yum) run_as_root $PKG_MANAGER install -y python3 python3-pip ;;
                pacman) run_as_root pacman -S --noconfirm python python-pip ;;
            esac
        fi
        if [ $? -eq 0 ]; then
            log_success "Python 3 安裝完成"
            # 再次檢查，即使未通過也不中斷
            if check_python_version "3.8"; then
                log_success "Python 版本現在滿足要求"
            else
                log_warning "Python 版本仍不滿足要求，但繼續安裝"
            fi
        else
            log_warning "無法安裝 Python 3，繼續使用系統 Python"
        fi
    else
        log_success "Python 版本檢查通過"
    fi
    
    # 檢查網絡連接
    if ! check_network; then
        log_warning "網絡連接檢查失敗，但繼續安裝（可能是容器環境限制）"
    else
        log_success "網絡連接正常"
    fi
    
    # 檢查磁盤空間
    if ! check_disk_space 3; then
        log_error "磁盤空間不足，至少需要 3GB 可用空間"
        exit 1
    fi
    log_success "磁盤空間充足"
    
    # 檢查必要命令（curl 是必須的，包管理器根據系統而定）
    local required_commands="curl"
    local optional_commands="wget"

    # 檢查是否為 root 或 sudo 可用
    if [ "$EUID" -ne 0 ] && ! check_command "sudo"; then
        log_error "找不到必要的命令：sudo（或請以 root 身份運行）"
        exit 1
    fi

    # 檢查包管理器是否可用
    if ! check_command "${PKG_MANAGER:-apt}"; then
        log_error "找不到包管理器：${PKG_MANAGER}"
        exit 1
    fi

    for cmd in $required_commands; do
        if ! check_command "$cmd"; then
            log_error "找不到必要的命令：$cmd"
            exit 1
        fi
    done

    for cmd in $optional_commands; do
        if ! check_command "$cmd"; then
            log_warning "建議安裝的命令未找到：$cmd（將嘗試自動安裝）"
            # 使用通用安裝方式
            if command -v install_package >/dev/null 2>&1; then
                install_package wget 2>/dev/null || log_warning "無法安裝 $cmd"
            fi
        fi
    done
    
    log_success "必要命令檢查通過"
    
    # 檢查 sudo 權限
    if [ "$EUID" -eq 0 ]; then
        log_success "以 root 身份運行，跳過 sudo 檢查"
    elif ! check_sudo_access; then
        log_error "無法獲取 sudo 權限"
        exit 1
    else
        log_success "sudo 權限檢查通過"
    fi
    
    log_success "環境檢查完成"
}

# 備份配置文件
backup_config_files() {
    printf "${BLUE}備份配置文件...${NC}\n"
    BACKUP_DIR="$HOME/.config/linux-setting-backup/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # 備份現有的配置文件
    for file in ~/.zshrc ~/.p10k.zsh ~/.config/nvim; do
        if [ -e "$file" ]; then
            cp -r "$file" "$BACKUP_DIR/"
            printf "${GREEN}已備份：$file${NC}\n"
        fi
    done
}

# 設置日誌
setup_logging() {
    LOG_DIR="$HOME/.local/log/linux-setting"
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/install_$(date +%Y%m%d_%H%M%S).log"
    exec 1> >(tee -a "$LOG_FILE") 2>&1
    printf "${GREEN}安裝日誌將保存到：$LOG_FILE${NC}\n"
}

# 定義模組陣列
MODULES="python docker base terminal dev monitoring"
selected_modules=""
installed_modules=""

# 確保遠程安裝標記正確（如果 SCRIPT_DIR 在 /tmp 下也視為遠程安裝）
if [[ "$SCRIPT_DIR" == /tmp/* ]]; then
    REMOTE_INSTALL=true
fi
REMOTE_INSTALL=${REMOTE_INSTALL:-false}

# 主要安裝函數
main() {
    # 檢查更新模式
    if [ "$UPDATE_MODE" = true ]; then
        log_info "更新模式：執行系統更新"
        if [ -f "$SCRIPT_DIR/maintenance/update_tools.sh" ]; then
            bash "$SCRIPT_DIR/maintenance/update_tools.sh"
            exit $?
        else
            log_error "找不到更新腳本"
            exit 1
        fi
    fi
    
    # 初始化
    setup_logging
    check_environment
    backup_config_files
    
    if [ "$REMOTE_INSTALL" = true ]; then
        printf "${CYAN}########## 下載安裝腳本 ##########${NC}\n"

        # 創建必要的子目錄
        mkdir -p "$SCRIPT_DIR/core" "$SCRIPT_DIR/utils" "$SCRIPT_DIR/maintenance"

        # 下載核心模組腳本（common.sh 已經在初始化時下載）
        for script in python_setup.sh docker_setup.sh terminal_setup.sh base_tools.sh dev_tools.sh monitoring_tools.sh; do
            printf "${BLUE}下載 core/$script...${NC}\n"
            curl -fsSL "$SCRIPTS_URL/core/$script" -o "$SCRIPT_DIR/core/$script"
            chmod +x "$SCRIPT_DIR/core/$script"
        done

        # 下載工具腳本
        printf "${BLUE}下載 utils/secure_download.sh...${NC}\n"
        curl -fsSL "$SCRIPTS_URL/utils/secure_download.sh" -o "$SCRIPT_DIR/utils/secure_download.sh"
        chmod +x "$SCRIPT_DIR/utils/secure_download.sh"

        # 下載維護腳本
        printf "${BLUE}下載 maintenance/update_tools.sh...${NC}\n"
        curl -fsSL "$SCRIPTS_URL/maintenance/update_tools.sh" -o "$SCRIPT_DIR/maintenance/update_tools.sh"
        chmod +x "$SCRIPT_DIR/maintenance/update_tools.sh"
    fi
    
    # 進入主循環
    while true; do
        # 如果啟用 TUI，使用 checklist 進行模組選擇
        if [ "$USE_TUI" = "true" ] && command -v tui_checklist >/dev/null 2>&1; then
            # 使用 TUI checklist 選擇模組
            local module_selection
            module_selection=$(tui_checklist "Linux 環境設定安裝程序" \
                "請使用空格鍵選擇要安裝的模組，方向鍵移動，Enter 確認：" \
                "python|Python開發環境(python3,pip,uv,ranger)" \
                "docker|Docker相關工具(docker-ce,lazydocker)" \
                "base|基礎工具(git,lsd,bat,ripgrep,fzf)" \
                "terminal|終端設定(zsh,oh-my-zsh,p10k)" \
                "dev|開發工具(neovim,lazygit,rust,nodejs)" \
                "monitoring|系統監控工具(btop,htop,fail2ban)")

            # 如果用戶取消，詢問是否退出
            if [ -z "$module_selection" ]; then
                if tui_yesno "確認退出" "確定要退出安裝程序嗎？" "no"; then
                    cleanup
                    printf "${CYAN}退出安裝程序${NC}\n"
                    exit 0
                else
                    continue
                fi
            fi

            # 解析選擇的模組（whiptail 返回格式: "python docker base"）
            selected_modules=""
            for item in $module_selection; do
                # 去除可能的引號和提取模組名（在|之前）
                module_name=$(echo "$item" | cut -d'|' -f1 | tr -d '"')
                selected_modules="$selected_modules $module_name"
            done

            # 顯示選擇的模組
            printf "\n${GREEN}已選擇的模組：$selected_modules${NC}\n\n"

            # 確認安裝
            if tui_yesno "確認安裝" "確定要安裝以下模組嗎？\n\n$selected_modules\n\n預估時間：10-15分鐘\n預估空間：500MB-1GB" "yes"; then
                install_selected_modules
            else
                selected_modules=""
                printf "${CYAN}已取消安裝${NC}\n"
                continue
            fi
        else
            # 命令行模式：使用原有的菜單邏輯
            show_menu
            read -r input
            case $input in
                [0-9]*)
                    for num in $input; do
                        add_module "$num"
                    done
                    ;;
                i|I)
                    install_selected_modules
                    ;;
                c|C)
                    selected_modules=""
                    printf "${CYAN}已清除所有選擇${NC}\n"
                    ;;
                q|Q)
                    cleanup
                    printf "${CYAN}退出安裝程序${NC}\n"
                    exit 0
                    ;;
                *)
                    printf "${RED}無效的輸入，請重試${NC}\n"
                    ;;
            esac
        fi
    done
}

# 顯示菜單函數
show_menu() {
    printf "\n${CYAN}請選擇要安裝的組件（可多選，用空格分隔）：${NC}\n"
    printf "\n1) Python 開發環境：\n"
    printf "   • Python3 與相關工具：\n"
    printf "     - python3, pip, python3-venv\n"
    printf "     - python3-dev, python3-setuptools\n"
    printf "     - uv (現代 Python 包管理器)\n"
    printf "   • 檔案管理器與系統工具：\n"
    printf "     - ranger-fm (終端檔案管理器)\n"
    printf "     - s-tui (系統監控工具)\n"
    
    printf "\n2) Docker 相關工具：\n"
    printf "   • Docker 引擎與工具：\n"
    printf "     - docker-ce, docker-ce-cli\n"
    printf "     - containerd.io, docker-buildx-plugin\n"
    printf "     - docker-compose-plugin\n"
    printf "   • Docker 管理工具：\n"
    printf "     - lazydocker (終端 Docker 管理器)\n"
    
    printf "\n3) 基礎工具：\n"
    printf "   • 系統工具：\n"
    printf "     - git, curl, wget, unzip, tar\n"
    printf "     - build-essential, pkg-config\n"
    printf "   • 終端增強工具：\n"
    printf "     - lsd (更好的 ls)\n"
    printf "     - bat (更好的 cat)\n"
    printf "     - ripgrep (更好的 grep)\n"
    printf "     - fd-find (更好的 find)\n"
    printf "     - fzf (模糊搜尋工具)\n"
    
    printf "\n4) 終端機設定：\n"
    printf "   • Shell 與主題：\n"
    printf "     - zsh (Shell)\n"
    printf "     - oh-my-zsh (zsh 框架)\n"
    printf "     - powerlevel10k (主題)\n"
    printf "   • ZSH 插件：\n"
    printf "     - zsh-autosuggestions\n"
    printf "     - zsh-syntax-highlighting\n"
    printf "     - zsh-history-substring-search\n"
    printf "     - you-should-use\n"
    
    printf "\n5) 開發工具：\n"
    printf "   • 編輯器與版本控制：\n"
    printf "     - neovim (終端編輯器)\n"
    printf "     - lazyvim (neovim 配置)\n"
    printf "     - lazygit (git 終端介面)\n"
    printf "   • 開發環境：\n"
    printf "     - nodejs, npm (Node.js)\n"
    printf "     - cargo (Rust 包管理器)\n"
    printf "     - lua, luarocks (Lua)\n"
    
    printf "\n6) 系統監控工具：\n"
    printf "   • 系統資源監控：\n"
    printf "     - btop (系統監控)\n"
    printf "     - htop (處理程序監控)\n"
    printf "   • 網路監控：\n"
    printf "     - iftop (網路流量監控)\n"
    printf "     - nethogs (程序網路監控)\n"
    printf "   • 安全工具：\n"
    printf "     - fail2ban (入侵防護)\n"
    
    printf "\n7) 安裝所有組件\n"
    printf "0) 退出\n"
    
    printf "\n${GREEN}當前選擇的模組：$selected_modules${NC}\n"
    printf "\n請輸入選項 (例如: 1 3 4 表示選擇1,3,4號模組)\n"
    printf "輸入 'c' 清除選擇，輸入 'i' 開始安裝，輸入 'q' 退出: "
}

# 執行安裝腳本函數
execute_script() {
    local script=$1
    local module_name=$2
    if [ -f "$SCRIPT_DIR/$script" ]; then
        printf "${CYAN}########## 開始安裝 $module_name ##########${NC}\n"
        if bash "$SCRIPT_DIR/$script"; then
            installed_modules="$installed_modules $module_name"
            printf "${GREEN}$module_name 安裝完成${NC}\n"
        else
            printf "${RED}$module_name 安裝失敗${NC}\n"
            return 1
        fi
    else
        printf "${RED}錯誤：找不到腳本 $SCRIPT_DIR/$script${NC}\n"
        return 1
    fi
}

# 添加模組到選擇列表
add_module() {
    local num=$1
    case $num in
        1) selected_modules="$selected_modules python" ;;
        2) selected_modules="$selected_modules docker" ;;
        3) selected_modules="$selected_modules base" ;;
        4) selected_modules="$selected_modules terminal" ;;
        5) selected_modules="$selected_modules dev" ;;
        6) selected_modules="$selected_modules monitoring" ;;
        7) selected_modules="$MODULES" ;;
        *) printf "${RED}無效的選項：$num${NC}\n" ;;
    esac
}

# 顯示安裝報告
show_installation_report() {
    # 構建報告內容
    local report=""
    report+="========== 安裝報告 ==========\n\n"
    report+="已安裝的模組：\n"

    if echo "$installed_modules" | grep -q "base"; then
        report+="✓ 基礎工具\n"
        report+="    git, curl, wget, lsd, bat, ripgrep, fzf\n\n"
    fi

    if echo "$installed_modules" | grep -q "terminal"; then
        report+="✓ 終端機設定\n"
        report+="    zsh, oh-my-zsh, powerlevel10k\n"
        report+="    插件: autosuggestions, syntax-highlighting等\n\n"
    fi

    if echo "$installed_modules" | grep -q "dev"; then
        report+="✓ 開發工具\n"
        report+="    neovim (LazyVim), lazygit\n"
        report+="    nodejs, npm, cargo, lua\n\n"
    fi

    if echo "$installed_modules" | grep -q "monitoring"; then
        report+="✓ 系統監控工具\n"
        report+="    btop, htop, iftop, nethogs, fail2ban\n\n"
    fi

    if echo "$installed_modules" | grep -q "python"; then
        report+="✓ Python 環境\n"
        report+="    python3, pip, venv, uv\n"
        report+="    ranger-fm, s-tui\n\n"
    fi

    if echo "$installed_modules" | grep -q "docker"; then
        report+="✓ Docker 相關工具\n"
        report+="    docker-ce, lazydocker\n\n"
    fi

    report+="設定檔位置：\n"
    report+="  zsh: ~/.zshrc\n"
    report+="  p10k: ~/.p10k.zsh\n"
    report+="  neovim: ~/.config/nvim\n\n"

    report+="別名設定：\n"
    report+="  nvim -> nv\n"
    report+="  lazydocker -> lzd\n\n"

    report+="備份位置：$BACKUP_DIR\n"
    report+="日誌文件：$LOG_FILE\n\n"

    # 添加提示信息
    if ! echo "$installed_modules" | grep -q "terminal"; then
        report+="注意：請重新開啟終端機以套用所有更改"
    fi

    # 使用 TUI 或命令行顯示報告
    if [ "$USE_TUI" = "true" ] && command -v tui_msgbox >/dev/null 2>&1; then
        tui_msgbox "安裝完成" "$report"
    else
        # 命令行模式：使用原有的格式化輸出
        printf "\n${CYAN}########## 安裝報告 ##########${NC}\n"
        echo -e "$report" | sed 's/\\n/\n/g'
        printf "${CYAN}########## 安裝完成 ##########${NC}\n"

        if ! echo "$installed_modules" | grep -q "terminal"; then
            printf "${GREEN}請重新開啟終端機以套用所有更改${NC}\n"
        fi
    fi
}

# 安裝選中的模組
install_selected_modules() {
    if [ -z "$selected_modules" ]; then
        printf "${RED}未選擇任何模組${NC}\n"
        return
    fi

    # 計算要安裝的模組數量
    local total_modules=0
    local current_module=0
    for module in base dev python monitoring docker terminal; do
        case " $selected_modules " in
            *" $module "*) total_modules=$((total_modules + 1)) ;;
        esac
    done

    # 干運行模式：僅顯示將要安裝的內容
    if [ "$DRY_RUN" = true ]; then
        printf "\n${CYAN}========== 預覽模式 (Dry Run) ==========${NC}\n"
        printf "${BLUE}將安裝以下 $total_modules 個模組：${NC}\n\n"

        for module in base dev python monitoring docker terminal; do
            case " $selected_modules " in
                *" $module "*) ;;
                *) continue ;;
            esac

            printf "${GREEN}[$module]${NC}\n"
            case $module in
                base)
                    printf "  • git, curl, wget, build-essential\n"
                    printf "  • lsd, bat, fzf, ripgrep\n"
                    printf "  • tealdeer, superfile\n"
                    ;;
                dev)
                    printf "  • neovim + lazyvim\n"
                    printf "  • lazygit\n"
                    printf "  • nodejs, cargo\n"
                    ;;
                python)
                    printf "  • python3, pip\n"
                    printf "  • uv (快速包管理器)\n"
                    printf "  • ranger-fm, s-tui\n"
                    ;;
                terminal)
                    printf "  • zsh + oh-my-zsh\n"
                    printf "  • powerlevel10k 主題\n"
                    printf "  • 多個 zsh 插件\n"
                    ;;
                monitoring)
                    printf "  • btop, htop\n"
                    printf "  • iftop, nethogs\n"
                    printf "  • fail2ban\n"
                    ;;
                docker)
                    printf "  • docker-ce\n"
                    printf "  • lazydocker\n"
                    ;;
            esac
            printf "\n"
        done

        printf "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        printf "${BLUE}預估時間：${NC}約 10-15 分鐘\n"
        printf "${BLUE}預估空間：${NC}約 500MB-1GB\n"
        printf "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        printf "\n${GREEN}提示：${NC}移除 --dry-run 參數即可開始實際安裝\n\n"
        return 0
    fi

    printf "${CYAN}開始安裝以下模組：$selected_modules${NC}\n"
    printf "${BLUE}總共 $total_modules 個模組${NC}\n\n"

    # 為了確保依賴順序，實際安裝順序固定為：
    # 1. base       - 提供 git/curl/wget 等基礎工具與 APT 相關套件
    # 2. dev        - 安裝 cargo / nodejs 等開發工具，供後續模組使用
    # 3. python     - 建立 Python/uv/虛擬環境，供終端工具使用
    # 4. monitoring - 安裝監控與安全工具
    # 5. docker     - 可選的 Docker 工具
    # 6. terminal   - 最後安裝（不再自動 exec zsh）
    for module in base dev python monitoring docker terminal; do
        case " $selected_modules " in
            *" $module "*) ;;
            *) continue ;;
        esac

        current_module=$((current_module + 1))
        printf "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        printf "${GREEN}進度: [$current_module/$total_modules]${NC} 安裝模組: ${BLUE}$module${NC}\n"
        printf "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n\n"

        case $module in
            base) execute_script "core/base_tools.sh" "base" ;;
            dev) execute_script "core/dev_tools.sh" "dev" ;;
            python) execute_script "core/python_setup.sh" "python" ;;
            terminal) execute_script "core/terminal_setup.sh" "terminal" ;;
            monitoring) execute_script "core/monitoring_tools.sh" "monitoring" ;;
            docker) execute_script "core/docker_setup.sh" "docker" ;;
        esac || {
            printf "${RED}安裝過程中出現錯誤，中止安裝${NC}\n"
            return 1
        }
    done
    
    show_installation_report
    selected_modules=""

    # 如果是在「非互動環境」（例如：管線 / here-doc / Docker 自動化測試），
    # 完成一次安裝後就直接結束腳本，避免迴圈再次 read 造成 EOF 而觸發錯誤處理。
    if [ ! -t 0 ]; then
        printf "${CYAN}偵測到非互動環境，自動結束安裝流程${NC}\n"
        exit 0
    fi
}

# 執行主函數
main


