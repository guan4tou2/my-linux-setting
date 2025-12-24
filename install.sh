#!/usr/bin/env bash

# ==============================================================================
# Linux Setting Scripts - Enhanced Installation Script
# ==============================================================================

# 解析命令行參數
# 鏡像模式固定為全球官方源（不再提供 --mirror 選項）
MIRROR_MODE="global"
INSTALL_MODE="full"
UPDATE_MODE=false
VERBOSE=false

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

# 導出變數供子腳本使用
export REPO_URL SCRIPTS_URL P10K_CONFIG_URL REQUIREMENTS_URL
export MIRROR_MODE INSTALL_MODE UPDATE_MODE VERBOSE DEBUG

# 載入共用函數庫
SCRIPT_DIR="$PWD/scripts"
if [ -f "$SCRIPT_DIR/common.sh" ]; then
    source "$SCRIPT_DIR/common.sh"
elif [ -f "./scripts/common.sh" ]; then
    source "./scripts/common.sh"
else
    # 遠程下載共用函數庫
    TEMP_DIR=$(mktemp -d)
    SCRIPT_DIR="$TEMP_DIR/scripts"
    mkdir -p "$SCRIPT_DIR"
    curl -fsSL "$SCRIPTS_URL/common.sh" -o "$SCRIPT_DIR/common.sh"
    source "$SCRIPT_DIR/common.sh"
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
  -v, --verbose                   顯示詳細日誌
  -h, --help                      顯示此幫助訊息

範例:
  $0                             # 標準安裝
  $0 --mirror china              # 使用中國鏡像源
  $0 --minimal                   # 最小安裝
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
    
    # 檢查系統類型
    if [ ! -f /etc/os-release ] || ! grep -q 'Ubuntu\|Debian' /etc/os-release; then
        log_error "此腳本僅支持 Ubuntu/Debian 系統"
        exit 1
    fi
    
    # 檢查系統版本
    local os_version
    os_version=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
    log_info "檢測到系統版本: $os_version"
    
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
        if run_as_root apt-get update && run_as_root apt-get install -y python3 python3-venv python3-pip; then
            log_success "Python 3 安裝完成"
            # Try the check again, but don't fail if it still doesn't pass
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
    
    # 檢查必要命令
    local required_commands="curl apt-get"
    local optional_commands="wget"
    
    # Check if running as root or if sudo is available
    if [ "$EUID" -ne 0 ] && ! check_command "sudo"; then
        log_error "找不到必要的命令：sudo（或請以 root 身份運行）"
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
            # Try to install wget if missing
            if command -v apt-get >/dev/null 2>&1; then
                run_as_root apt-get update && run_as_root apt-get install -y wget >/dev/null 2>&1 || log_warning "無法安裝 $cmd"
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
        if [ -f "$SCRIPT_DIR/update_tools.sh" ]; then
            bash "$SCRIPT_DIR/update_tools.sh"
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
        
        # 下載所有模組腳本（common.sh 已經在初始化時下載）
        for script in python_setup.sh docker_setup.sh terminal_setup.sh base_tools.sh dev_tools.sh monitoring_tools.sh; do
            printf "${BLUE}下載 $script...${NC}\n"
            curl -fsSL "$SCRIPTS_URL/$script" -o "$SCRIPT_DIR/$script"
            chmod +x "$SCRIPT_DIR/$script"
        done
    fi
    
    # 進入主循環
    while true; do
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
    printf "\n${CYAN}########## 安裝報告 ##########${NC}\n"
    printf "${GREEN}已安裝的模組：${NC}\n"
    
    if echo "$installed_modules" | grep -q "base"; then
        printf "✓ 基礎工具\n"
        printf "    git, curl, wget, lsd, bat 等\n"
    fi
    
    if echo "$installed_modules" | grep -q "terminal"; then
        printf "✓ 終端機設定\n"
        printf "    zsh, oh-my-zsh, powerlevel10k\n"
        printf "    zsh 插件：autosuggestions, syntax-highlighting, history-substring-search, you-should-use\n"
    fi
    
    if echo "$installed_modules" | grep -q "dev"; then
        printf "✓ 開發工具\n"
        printf "    neovim (LazyVim)\n"
        printf "    lazygit\n"
        printf "    nodejs, npm, cargo, lua\n"
    fi
    
    if echo "$installed_modules" | grep -q "monitoring"; then
        printf "✓ 系統監控工具\n"
        printf "    btop, iftop, nethogs, fail2ban\n"
    fi
    
    if echo "$installed_modules" | grep -q "python"; then
        printf "✓ Python 環境\n"
        printf "    python3, pip, venv, uv\n"
        printf "    ranger-fm, s-tui\n"
    fi
    
    if echo "$installed_modules" | grep -q "docker"; then
        printf "✓ Docker 相關工具\n"
        printf "    docker\n"
        printf "    lazydocker\n"
    fi
    
    printf "\n${BLUE}設定檔位置：${NC}\n"
    printf "zsh 配置：%s\n" "~/.zshrc"
    printf "powerlevel10k 配置：%s\n" "~/.p10k.zsh"
    printf "neovim 配置：%s\n" "~/.config/nvim"
    
    printf "\n${BLUE}別名設定：${NC}\n"
    printf "nvim -> nv\n"
    printf "lazydocker -> lzd\n"
    
    printf "\n${BLUE}備份位置：${NC}\n"
    printf "%s\n" "$BACKUP_DIR"
    
    printf "\n${BLUE}日誌文件：${NC}\n"
    printf "%s\n" "$LOG_FILE"
    
    printf "\n${CYAN}########## 安裝完成 ##########${NC}\n"
    printf "${GREEN}請重新開啟終端機以套用所有更改${NC}\n"
}

# 安裝選中的模組
install_selected_modules() {
    if [ -z "$selected_modules" ]; then
        printf "${RED}未選擇任何模組${NC}\n"
        return
    fi

    printf "${CYAN}開始安裝以下模組：$selected_modules${NC}\n"

    # 為了確保依賴順序，實際安裝順序固定為：
    # 1. base       - 提供 git/curl/wget 等基礎工具與 APT 相關套件
    # 2. dev        - 安裝 cargo / nodejs 等開發工具，供後續模組使用
    # 3. python     - 建立 Python/uv/虛擬環境，供終端工具使用
    # 4. terminal   - 依賴前面模組提供的工具（例如 thefuck、uv）
    # 5. monitoring - 最後安裝監控與安全工具
    # 6. docker     - 可選的 Docker 工具，放在最末
    for module in base dev python terminal monitoring docker; do
        case " $selected_modules " in
            *" $module "*) ;;
            *) continue ;;
        esac

        case $module in
            base) execute_script "base_tools.sh" "base" ;;
            dev) execute_script "dev_tools.sh" "dev" ;;
            python) execute_script "python_setup.sh" "python" ;;
            terminal) execute_script "terminal_setup.sh" "terminal" ;;
            monitoring) execute_script "monitoring_tools.sh" "monitoring" ;;
            docker) execute_script "docker_setup.sh" "docker" ;;
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


