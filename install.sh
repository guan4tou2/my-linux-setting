#!/usr/bin/env bash

# 錯誤處理
set -e
trap 'handle_error $?' ERR

# 定義顏色
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 配置下載網址（可根據需要修改）
REPO_URL=${REPO_URL:-"https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main"}
SCRIPTS_URL=${SCRIPTS_URL:-"$REPO_URL/scripts"}
P10K_CONFIG_URL=${P10K_CONFIG_URL:-"$REPO_URL/.p10k.zsh"}

# 導出變數供子腳本使用
export REPO_URL
export SCRIPTS_URL
export P10K_CONFIG_URL

# 錯誤處理函數
handle_error() {
    printf "${RED}安裝過程出錯（錯誤碼：$1）\n"
    printf "請檢查日誌文件：$LOG_FILE${NC}\n"
    cleanup
    exit 1
}

# 清理函數
cleanup() {
    if [ "$REMOTE_INSTALL" = true ] && [ -d "$TEMP_DIR" ]; then
        printf "${BLUE}清理臨時文件...${NC}\n"
        rm -rf "$TEMP_DIR"
    fi
}

# 環境檢查函數
check_environment() {
    printf "${BLUE}檢查系統環境...${NC}\n"
    
    # 檢查系統類型
    if [ ! -f /etc/os-release ] || ! grep -q 'Ubuntu\|Debian' /etc/os-release; then
        printf "${RED}錯誤：此腳本僅支持 Ubuntu/Debian 系統${NC}\n"
    exit 1
fi

    # 檢查網絡連接
    if ! ping -c 1 google.com >/dev/null 2>&1; then
        printf "${RED}錯誤：無法連接到網絡${NC}\n"
        exit 1
    fi
    
    # 檢查磁盤空間（至少需要 5GB 可用空間）
    available_space=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$available_space" -lt 2 ]; then
        printf "${RED}錯誤：磁盤空間不足，至少需要 2GB 可用空間${NC}\n"
        exit 1
    fi
    
    # 檢查必要命令
    for cmd in curl wget sudo apt-get; do
        if ! command -v $cmd >/dev/null 2>&1; then
            printf "${RED}錯誤：找不到必要的命令：$cmd${NC}\n"
            exit 1
        fi
    done
    
    printf "${GREEN}環境檢查通過${NC}\n"
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

# 檢查是否為遠程安裝
REMOTE_INSTALL=false
SCRIPT_DIR="$PWD/scripts"

# 主要安裝函數
main() {
    # 初始化
    setup_logging
    check_environment
    backup_config_files
    
    if [ ! -d "$SCRIPT_DIR" ]; then
        REMOTE_INSTALL=true
        TEMP_DIR=$(mktemp -d)
        SCRIPT_DIR="$TEMP_DIR/scripts"
        
        printf "${CYAN}########## 下載安裝腳本 ##########${NC}\n"
        mkdir -p "$SCRIPT_DIR"
        
        # 下載所有腳本
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
    printf "1) Python 開發環境\n"
    printf "2) Docker 相關工具\n"
    printf "3) 基礎工具 (git, curl, wget 等)\n"
    printf "4) 終端機設定 (zsh, oh-my-zsh, powerlevel10k)\n"
    printf "5) 開發工具 (neovim, lazyvim, lazygit 等)\n"
    printf "6) 系統監控工具 (btop, iftop, nethogs 等)\n"
    printf "7) 安裝所有組件\n"
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
        printf "    python3, pip, venv\n"
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
    for module in $selected_modules; do
        case $module in
            base) execute_script "base_tools.sh" "base" ;;
            terminal) execute_script "terminal_setup.sh" "terminal" ;;
            dev) execute_script "dev_tools.sh" "dev" ;;
            monitoring) execute_script "monitoring_tools.sh" "monitoring" ;;
            python) execute_script "python_setup.sh" "python" ;;
            docker) execute_script "docker_setup.sh" "docker" ;;
        esac || {
            printf "${RED}安裝過程中出現錯誤，中止安裝${NC}\n"
            return 1
        }
    done
    
    show_installation_report
    selected_modules=""
}

# 執行主函數
main


