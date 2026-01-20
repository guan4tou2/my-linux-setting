#!/usr/bin/env bash

# ==============================================================================
# Linux Environment Setup - Main Installation Script
# Version: 2.0.1
# ==============================================================================

# 自動切換到 Homebrew bash (macOS 需要 bash 4+ 支持關聯陣列)
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    # 嘗試找到 Homebrew 安裝的 bash
    for brew_bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        if [ -x "$brew_bash" ] && "$brew_bash" --version 2>/dev/null | grep -q "version [4-9]"; then
            exec "$brew_bash" "$0" "$@"
        fi
    done
    # 如果沒有找到新版 bash，顯示警告但繼續執行（使用備用邏輯）
    echo -e "\033[0;33mWARNING: Bash 版本 ($BASH_VERSION) 較舊，部分功能可能受限\033[0m"
    echo -e "\033[0;33m建議安裝新版 Bash: brew install bash\033[0m"
fi

# 跟踪最後執行的命令
LAST_COMMAND=""

# 幫助函數（必須在參數解析之前定義）
show_help() {
    cat << 'EOF'
Linux Setting Scripts - 自動安裝腳本 v2.0.1

用法: ./install.sh [選項]

選項:
  --minimal                       最小安裝模式
  --update                        更新已安裝的組件
  --dry-run                       預覽模式（不實際安裝）
  -v, --verbose                   顯示詳細日誌
  -h, --help                      顯示此幫助訊息
  --config <file>                 指定配置文件路徑

範例:
  ./install.sh                    # 標準安裝（互動式選單）
  ./install.sh --minimal          # 最小安裝
  ./install.sh --dry-run          # 預覽將要安裝的內容
  ./install.sh --update           # 更新模式
  ./install.sh --verbose          # 詳細模式

更多資訊請參閱 README.md
EOF
}

# 顯示歡迎信息
show_welcome() {
    # 使用 printf 確保跨平台兼容性
    printf "\n"
    printf "╔════════════════════════════════════════════════════════╗\n"
    printf "║                                                        ║\n"
    printf "║          Linux Setting Scripts  v2.0.1                 ║\n"
    printf "║            自動化開發環境配置工具                      ║\n"
    printf "║                                                        ║\n"
    printf "╠════════════════════════════════════════════════════════╣\n"
    printf "║  快速開始:                                             ║\n"
    printf "║    ./install.sh             互動式安裝 (推薦)          ║\n"
    printf "║    ./install.sh --minimal   最小安裝                   ║\n"
    printf "║    ./install.sh --dry-run   預覽安裝內容               ║\n"
    printf "║    ./install.sh --help      查看完整幫助               ║\n"
    printf "╚════════════════════════════════════════════════════════╝\n"
    printf "\n"
}

show_welcome


# Set strict error handling
set -euo pipefail

# 統一的錯誤捕獲
trap 'handle_error $? $LINENO "$BASH_COMMAND"' ERR

# ==============================================================================
# Argument Parsing
# ==============================================================================

INSTALL_MODE="${INSTALL_MODE:-full}"
UPDATE_MODE="${UPDATE_MODE:-false}"
VERBOSE="${VERBOSE:-false}"
DEBUG="${DEBUG:-false}"
DRY_RUN="${DRY_RUN:-false}"
SKIP_PYTHON_CHECK="${SKIP_PYTHON_CHECK:-false}"

while [[ $# -gt 0 ]]; do
    case "$1" in
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
        --config)
            if [ -n "$2" ]; then
                export CONFIG_FILE="$2"
                shift 2
            else
                echo "Error: --config requires a file path"
                exit 1
            fi
            ;;
        *)
            echo "Unknown parameter: $1"
            show_help
            exit 1
            ;;
    esac
done

# Export variables for child scripts
export INSTALL_MODE UPDATE_MODE VERBOSE DEBUG DRY_RUN SKIP_PYTHON_CHECK

# ==============================================================================
# Configuration
# ==============================================================================

REPO_URL="${REPO_URL:-https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main}"
SCRIPTS_URL="${SCRIPTS_URL:-$REPO_URL/scripts}"
P10K_CONFIG_URL="${P10K_CONFIG_URL:-$REPO_URL/.p10k.zsh}"
REQUIREMENTS_URL="${REQUIREMENTS_URL:-$REPO_URL/requirements.txt}"

# Performance options
ENABLE_PARALLEL_INSTALL="${ENABLE_PARALLEL_INSTALL:-true}"
PARALLEL_JOBS="${PARALLEL_JOBS:-auto}"

# Auto-detect parallel jobs if set to auto
if [ "$PARALLEL_JOBS" = "auto" ]; then
    PARALLEL_JOBS=$(nproc 2>/dev/null || echo 4)
fi

# Export configuration
export REPO_URL SCRIPTS_URL P10K_CONFIG_URL REQUIREMENTS_URL
export ENABLE_PARALLEL_INSTALL PARALLEL_JOBS

# ==============================================================================
# Remote Installation with Security Verification
# ==============================================================================

SCRIPT_DIR="$PWD/scripts"
REMOTE_INSTALL=false

# Try local common.sh first
if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
elif [ -f "./scripts/core/common.sh" ]; then
    source "./scripts/core/common.sh"
else
    # Remote installation - bootstrap without common.sh functions
    TEMP_DIR=$(mktemp -d)
    SCRIPT_DIR="$TEMP_DIR/scripts"
    mkdir -p "$SCRIPT_DIR/core"

    echo -e "\033[0;36mINFO: Downloading common library from remote source...\033[0m"

    # Download common.sh (without using safe_download since it's not loaded yet)
    COMMON_URL="$SCRIPTS_URL/core/common.sh"
    COMMON_OUTPUT="$SCRIPT_DIR/core/common.sh"

    if curl -fsSL --max-time 30 "$COMMON_URL" -o "$COMMON_OUTPUT" 2>/dev/null; then
        # Basic validation before sourcing
        if [ -s "$COMMON_OUTPUT" ] && head -1 "$COMMON_OUTPUT" | grep -q "^#!/"; then
            source "$COMMON_OUTPUT"
            REMOTE_INSTALL=true
            echo -e "\033[0;32mSUCCESS: Common library loaded\033[0m"
        else
            echo -e "\033[0;31mERROR: Downloaded file appears invalid\033[0m"
            rm -rf "$TEMP_DIR"
            exit 1
        fi
    else
        echo -e "\033[0;31mERROR: Failed to download common library\033[0m"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
fi

# Initialize environment
init_common_env

# 載入模組管理器（需要 bash 4.0+ 支持關聯陣列）
USE_MODULE_MANAGER=false
if [ -f "$SCRIPT_DIR/core/module_manager.sh" ]; then
    # 檢查 bash 版本是否支持關聯陣列 (需要 4.0+)
    if [ "${BASH_VERSINFO[0]:-0}" -ge 4 ]; then
        source "$SCRIPT_DIR/core/module_manager.sh"
        init_module_manager
        USE_MODULE_MANAGER=true
    else
        log_warning "Bash 版本 ($BASH_VERSION) 不支持關聯陣列，使用內建配置"
        log_info "建議安裝 Bash 4+: brew install bash"
    fi
else
    log_info "模組管理器不可用，使用內建配置"
fi

# 錯誤處理函數
handle_error() {
    local exit_code=$1
    local line_number="$2"
    local last_command="${3:-}"

    printf "\n"
    printf "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${RED}║                       安裝失敗                                ║${NC}\n"
    printf "${RED}╠═══════════════════════════════════════════════════════════════╣${NC}\n"
    printf "${RED}║${NC}  位置: install.sh:%-44s${RED}║${NC}\n" "$line_number"
    printf "${RED}║${NC}  代碼: %-54s${RED}║${NC}\n" "$exit_code"
    printf "${RED}║${NC}  命令: %-54s${RED}║${NC}\n" "${last_command:0:54}"
    printf "${RED}╠═══════════════════════════════════════════════════════════════╣${NC}\n"
    printf "${RED}║${NC}  ${YELLOW}可能原因:${NC}                                                  ${RED}║${NC}\n"
    printf "${RED}║${NC}    - 網路連線問題                                            ${RED}║${NC}\n"
    printf "${RED}║${NC}    - 套件來源無法存取                                        ${RED}║${NC}\n"
    printf "${RED}║${NC}    - 磁碟空間不足                                            ${RED}║${NC}\n"
    printf "${RED}║${NC}    - 權限不足                                                ${RED}║${NC}\n"
    printf "${RED}╠═══════════════════════════════════════════════════════════════╣${NC}\n"
    printf "${RED}║${NC}  ${GREEN}建議操作:${NC}                                                  ${RED}║${NC}\n"
    printf "${RED}║${NC}    1. 檢查網路: ping -c 1 github.com                         ${RED}║${NC}\n"
    printf "${RED}║${NC}    2. 更新來源: sudo apt update                              ${RED}║${NC}\n"
    printf "${RED}║${NC}    3. 檢查空間: df -h /                                      ${RED}║${NC}\n"

    # 顯示日誌文件位置
    if [ -n "${LOG_FILE:-}" ] && [ -f "$LOG_FILE" ]; then
        printf "${RED}║${NC}    4. 查看日誌: tail -50 \$LOG_FILE                          ${RED}║${NC}\n"
    fi

    printf "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}\n"

    # 詢問是否查看日誌
    if [ -t 0 ]; then
        printf "\n"
        printf "${CYAN}[l]${NC} 查看日誌  ${CYAN}[r]${NC} 重試  ${CYAN}[q]${NC} 退出: "
        read -r -n 1 choice
        printf "\n"
        case $choice in
            l|L)
                if [ -f "${LOG_FILE:-}" ]; then
                    tail -100 "$LOG_FILE" | less
                else
                    printf "${YELLOW}找不到日誌文件${NC}\n"
                fi
                ;;
            r|R)
                printf "${CYAN}請重新執行安裝腳本${NC}\n"
                ;;
        esac
    fi

    printf "\n${BLUE}需要幫助？${NC}\n"
    printf "  README: README.md\n"
    printf "  Issues: https://github.com/guan4tou2/my-linux-setting/issues\n\n"

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
    if [ "${SKIP_PYTHON_CHECK:-false}" = "true" ]; then
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
    # LOG_DIR 可能已在 common.sh 中定義為 readonly，使用局部變數
    local log_dir="${LOG_DIR:-$HOME/.local/log/linux-setting}"
    mkdir -p "$log_dir"
    LOG_FILE="$log_dir/install_$(date +%Y%m%d_%H%M%S).log"
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
            # 動態生成 TUI checklist 項目（包含安裝狀態）
            local checklist_items=()
            if [ "$USE_MODULE_MANAGER" = "true" ] && [ ${#MODULE_LIST[@]} -gt 0 ]; then
                for module_id in "${MODULE_LIST[@]}"; do
                    local name="${MODULE_NAMES[$module_id]:-$module_id}"
                    local desc="${MODULE_DESCRIPTIONS[$module_id]:-}"
                    local status_mark=""

                    # 獲取安裝狀態標記
                    if command -v check_module_status >/dev/null 2>&1; then
                        local status
                        status=$(check_module_status "$module_id" 2>/dev/null)
                        case "$status" in
                            installed)     status_mark="[✓] " ;;
                            partial)       status_mark="[◐] " ;;
                            not_installed) status_mark="[ ] " ;;
                        esac
                    fi

                    checklist_items+=("${module_id}|${status_mark}${name} (${desc})")
                done
            else
                # 備用靜態選項
                checklist_items=(
                    "python|Python開發環境(python3,pip,uv,ranger)"
                    "docker|Docker相關工具(docker-ce,lazydocker)"
                    "base|基礎工具(git,lsd,bat,ripgrep,fzf)"
                    "terminal|終端設定(zsh,oh-my-zsh,p10k)"
                    "dev|開發工具(neovim,lazygit,rust,nodejs)"
                    "monitoring|系統監控工具(btop,htop,fail2ban)"
                )
            fi

            # 添加查看詳情選項
            local action_selection
            action_selection=$(tui_menu "Linux 環境設定安裝程序" \
                "[✓]=已安裝 [◐]=部分安裝 [ ]=未安裝\n\n請選擇操作：" \
                "選擇模組安裝" "查看模組詳情" "退出")

            case "$action_selection" in
                "查看模組詳情")
                    show_detail_selection_menu
                    continue
                    ;;
                "退出")
                    cleanup
                    printf "${CYAN}退出安裝程序${NC}\n"
                    exit 0
                    ;;
                "選擇模組安裝"|*)
                    # 繼續進行模組選擇
                    ;;
            esac

            # 使用 TUI checklist 選擇模組
            local module_selection
            module_selection=$(tui_checklist "Linux 環境設定安裝程序" \
                "[✓]=已安裝 [◐]=部分安裝 [ ]=未安裝\n\n請使用空格鍵選擇要安裝的模組，方向鍵移動，Enter 確認：" \
                "${checklist_items[@]}")

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
                d|D)
                    # 查看詳情：提供選擇單個模組或全部查看
                    if [ "$USE_MODULE_MANAGER" = "true" ] && [ ${#MODULE_LIST[@]} -gt 0 ]; then
                        printf "\n${CYAN}查看模組詳情${NC}\n"
                        printf "輸入模組編號查看單一模組，或按 Enter 查看全部: "
                        read -r detail_num
                        if [ -n "$detail_num" ] && [ "$detail_num" -ge 1 ] 2>/dev/null && [ "$detail_num" -le ${#MODULE_LIST[@]} ] 2>/dev/null; then
                            local module_id="${MODULE_LIST[$((detail_num - 1))]}"
                            show_module_detail_dialog "$module_id"
                        else
                            show_module_details
                        fi
                    else
                        show_module_details
                    fi
                    ;;
                q|Q|0)
                    cleanup
                    printf "${CYAN}退出安裝程序${NC}\n"
                    exit 0
                    ;;
                "")
                    # 空輸入，繼續顯示選單
                    ;;
                *)
                    printf "${RED}無效的輸入，請重試${NC}\n"
                    ;;
            esac
        fi
    done
}

# 顯示菜單函數（動態生成，包含安裝狀態標記）
show_menu() {
    printf "\n"
    printf "${CYAN}┌─ 選擇安裝模組 ─────────────────────────────────────────────┐${NC}\n"
    printf "${CYAN}│                                                             │${NC}\n"

    # 動態生成模組選項
    if [ "$USE_MODULE_MANAGER" = "true" ] && [ ${#MODULE_LIST[@]} -gt 0 ]; then
        local index=1
        for module_id in "${MODULE_LIST[@]}"; do
            local name="${MODULE_NAMES[$module_id]:-$module_id}"
            local desc="${MODULE_DESCRIPTIONS[$module_id]:-}"
            local status_icon=" "

            # 獲取安裝狀態標記
            if command -v check_module_status >/dev/null 2>&1; then
                local status
                status=$(check_module_status "$module_id" 2>/dev/null)
                case "$status" in
                    installed)     status_icon="✓" ;;
                    partial)       status_icon="◐" ;;
                    not_installed) status_icon=" " ;;
                esac
            fi

            # 根據狀態顯示不同顏色
            if [ "$status_icon" = "✓" ]; then
                printf "${CYAN}│${NC}  ${GREEN}[%d]${NC} [${GREEN}%s${NC}] %-17s %-26s${CYAN}│${NC}\n" "$index" "$status_icon" "$name" "$desc"
            elif [ "$status_icon" = "◐" ]; then
                printf "${CYAN}│${NC}  ${GREEN}[%d]${NC} [${YELLOW}%s${NC}] %-17s %-26s${CYAN}│${NC}\n" "$index" "$status_icon" "$name" "$desc"
            else
                printf "${CYAN}│${NC}  ${GREEN}[%d]${NC} [ ] %-17s %-26s${CYAN}│${NC}\n" "$index" "$name" "$desc"
            fi
            index=$((index + 1))
        done
        printf "${CYAN}│${NC}  ${GREEN}[%d]${NC}     %-17s %-26s${CYAN}│${NC}\n" "$index" "全部安裝" ""
    else
        # 備用靜態選單
        printf "${CYAN}│${NC}  ${GREEN}[1]${NC} Python 開發環境     python3, pip, uv, ranger         ${CYAN}│${NC}\n"
        printf "${CYAN}│${NC}  ${GREEN}[2]${NC} Docker 工具         docker-ce, lazydocker            ${CYAN}│${NC}\n"
        printf "${CYAN}│${NC}  ${GREEN}[3]${NC} 基礎工具           git, lsd, bat, ripgrep, fzf      ${CYAN}│${NC}\n"
        printf "${CYAN}│${NC}  ${GREEN}[4]${NC} 終端設定           zsh, oh-my-zsh, powerlevel10k    ${CYAN}│${NC}\n"
        printf "${CYAN}│${NC}  ${GREEN}[5]${NC} 開發工具           neovim, lazygit, nodejs, rust    ${CYAN}│${NC}\n"
        printf "${CYAN}│${NC}  ${GREEN}[6]${NC} 監控工具           btop, htop, iftop, fail2ban      ${CYAN}│${NC}\n"
        printf "${CYAN}│${NC}  ${GREEN}[7]${NC} 全部安裝                                            ${CYAN}│${NC}\n"
    fi

    printf "${CYAN}│                                                             │${NC}\n"
    printf "${CYAN}├─────────────────────────────────────────────────────────────┤${NC}\n"

    # 顯示狀態圖例
    printf "${CYAN}│${NC}  ${GREEN}[✓]${NC} 已安裝  ${YELLOW}[◐]${NC} 部分安裝  [ ] 未安裝               ${CYAN}│${NC}\n"
    printf "${CYAN}├─────────────────────────────────────────────────────────────┤${NC}\n"

    # 顯示當前選擇
    if [ -n "$selected_modules" ]; then
        printf "${CYAN}│${NC}  ${YELLOW}已選擇:${NC}%-46s${CYAN}│${NC}\n" "$selected_modules"
    else
        printf "${CYAN}│${NC}  ${YELLOW}已選擇:${NC} (尚未選擇)                                    ${CYAN}│${NC}\n"
    fi

    printf "${CYAN}│                                                             │${NC}\n"
    printf "${CYAN}│${NC}  ${BLUE}[i]${NC} 開始安裝  ${BLUE}[c]${NC} 清除  ${BLUE}[d]${NC} 詳細說明  ${BLUE}[q]${NC} 退出        ${CYAN}│${NC}\n"
    printf "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}\n"
    printf "\n輸入選項 (例如: 1 3 4): "
}

# 顯示單個模組詳細資訊（TUI 對話框）
show_module_detail_dialog() {
    local module_id="$1"

    if [ "$USE_MODULE_MANAGER" != "true" ] || ! module_exists "$module_id" 2>/dev/null; then
        log_warning "模組不存在: $module_id"
        return 1
    fi

    local detail
    detail=$(get_module_detail_status "$module_id" 2>/dev/null)

    if [ "$USE_TUI" = "true" ] && command -v tui_msgbox >/dev/null 2>&1; then
        local name="${MODULE_NAMES[$module_id]:-$module_id}"
        tui_msgbox "模組詳情: $name" "$detail"
    else
        printf "\n%s\n" "$detail"
        printf "\n按 Enter 返回..."
        read -r
    fi
}

# 顯示模組選擇選單（用於查看詳情）
show_detail_selection_menu() {
    if [ "$USE_TUI" = "true" ] && command -v tui_menu >/dev/null 2>&1; then
        # TUI 模式：使用選單選擇模組
        local menu_items=()
        for module_id in "${MODULE_LIST[@]}"; do
            local name="${MODULE_NAMES[$module_id]:-$module_id}"
            local status_icon=""
            if command -v check_module_status >/dev/null 2>&1; then
                local status
                status=$(check_module_status "$module_id" 2>/dev/null)
                case "$status" in
                    installed)     status_icon="[✓] " ;;
                    partial)       status_icon="[◐] " ;;
                    not_installed) status_icon="[ ] " ;;
                esac
            fi
            menu_items+=("${status_icon}${name}")
        done
        menu_items+=("返回主選單")

        local selection
        selection=$(tui_menu "查看模組詳情" "選擇要查看的模組：" "${menu_items[@]}")

        if [ -n "$selection" ] && [ "$selection" != "返回主選單" ]; then
            # 從選單項目反查模組 ID
            local selected_name="${selection#\[*\] }"  # 去除狀態標記
            for module_id in "${MODULE_LIST[@]}"; do
                local name="${MODULE_NAMES[$module_id]:-$module_id}"
                if [ "$name" = "$selected_name" ]; then
                    show_module_detail_dialog "$module_id"
                    return 0
                fi
            done
        fi
    else
        # 命令行模式：顯示完整的模組詳情
        show_module_details
    fi
}

# 顯示模組詳細資訊（動態生成，包含安裝狀態）
show_module_details() {
    printf "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
    printf "${CYAN}                    模組詳細資訊                               ${NC}\n"
    printf "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n\n"

    if [ "$USE_MODULE_MANAGER" = "true" ] && [ ${#MODULE_LIST[@]} -gt 0 ]; then
        local index=1
        for module_id in "${MODULE_LIST[@]}"; do
            local name="${MODULE_NAMES[$module_id]:-$module_id}"
            local packages="${MODULE_PACKAGES[$module_id]:-}"
            local brew_packages="${MODULE_BREW_PACKAGES[$module_id]:-}"
            local pip_packages="${MODULE_PIP_PACKAGES[$module_id]:-}"
            local cargo_packages="${MODULE_CARGO_PACKAGES[$module_id]:-}"
            local npm_packages="${MODULE_NPM_PACKAGES[$module_id]:-}"

            # 獲取安裝狀態
            local status_icon=" "
            local status_text="未安裝"
            if command -v check_module_status >/dev/null 2>&1; then
                local status
                status=$(check_module_status "$module_id" 2>/dev/null)
                case "$status" in
                    installed)
                        status_icon="✓"
                        status_text="已安裝"
                        ;;
                    partial)
                        status_icon="◐"
                        status_text="部分安裝"
                        ;;
                    not_installed)
                        status_icon=" "
                        status_text="未安裝"
                        ;;
                esac
            fi

            # 根據狀態顯示不同顏色
            if [ "$status_icon" = "✓" ]; then
                printf "${GREEN}[%d] [%s] %s (%s)${NC}\n" "$index" "$status_icon" "$name" "$status_text"
            elif [ "$status_icon" = "◐" ]; then
                printf "${YELLOW}[%d] [%s] %s (%s)${NC}\n" "$index" "$status_icon" "$name" "$status_text"
            else
                printf "[%d] [ ] %s (%s)\n" "$index" "$name" "$status_text"
            fi

            # 顯示套件清單（帶狀態標記）
            if [ -n "$packages" ]; then
                printf "    ${BLUE}系統套件:${NC} "
                local first=true
                for pkg in $packages; do
                    [ "$first" = true ] || printf ", " || true
                    first=false
                    if check_package_installed "$pkg" 2>/dev/null; then
                        printf "${GREEN}%s${NC}" "$pkg"
                    else
                        printf "${RED}%s${NC}" "$pkg"
                    fi
                done
                printf "\n"
            fi

            if [ -n "$brew_packages" ]; then
                printf "    ${BLUE}Homebrew:${NC} "
                local first=true
                for pkg in $brew_packages; do
                    [ "$first" = true ] || printf ", " || true
                    first=false
                    if command -v brew >/dev/null 2>&1 && check_brew_package_installed "$pkg" 2>/dev/null; then
                        printf "${GREEN}%s${NC}" "$pkg"
                    else
                        printf "${RED}%s${NC}" "$pkg"
                    fi
                done
                printf "\n"
            fi

            if [ -n "$pip_packages" ]; then
                printf "    ${BLUE}Python (uv):${NC} "
                local first=true
                for pkg in $pip_packages; do
                    [ "$first" = true ] || printf ", " || true
                    first=false
                    if check_pip_package_installed "$pkg" 2>/dev/null; then
                        printf "${GREEN}%s${NC}" "$pkg"
                    else
                        printf "${RED}%s${NC}" "$pkg"
                    fi
                done
                printf "\n"
            fi

            if [ -n "$cargo_packages" ]; then
                printf "    ${BLUE}Cargo:${NC} "
                local first=true
                for pkg in $cargo_packages; do
                    [ "$first" = true ] || printf ", " || true
                    first=false
                    if command -v cargo >/dev/null 2>&1 && check_cargo_package_installed "$pkg" 2>/dev/null; then
                        printf "${GREEN}%s${NC}" "$pkg"
                    else
                        printf "${RED}%s${NC}" "$pkg"
                    fi
                done
                printf "\n"
            fi

            if [ -n "$npm_packages" ]; then
                printf "    ${BLUE}NPM:${NC} "
                local first=true
                for pkg in $npm_packages; do
                    [ "$first" = true ] || printf ", " || true
                    first=false
                    if command -v npm >/dev/null 2>&1 && check_npm_package_installed "$pkg" 2>/dev/null; then
                        printf "${GREEN}%s${NC}" "$pkg"
                    else
                        printf "${RED}%s${NC}" "$pkg"
                    fi
                done
                printf "\n"
            fi

            printf "\n"
            index=$((index + 1))
        done
    else
        # 備用靜態詳細資訊
        printf "${GREEN}[1] Python 開發環境${NC}\n"
        printf "    python3, pip, uv, ranger-fm, s-tui\n\n"
        printf "${GREEN}[2] Docker 工具${NC}\n"
        printf "    docker-ce, lazydocker\n\n"
        printf "${GREEN}[3] 基礎工具${NC}\n"
        printf "    git, lsd, bat, ripgrep, fzf\n\n"
        printf "${GREEN}[4] 終端設定${NC}\n"
        printf "    zsh, oh-my-zsh, powerlevel10k\n\n"
        printf "${GREEN}[5] 開發工具${NC}\n"
        printf "    neovim, lazygit, nodejs, rust\n\n"
        printf "${GREEN}[6] 監控工具${NC}\n"
        printf "    btop, htop, iftop, fail2ban\n\n"
    fi

    printf "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
    printf "\n${YELLOW}圖例:${NC} ${GREEN}綠色${NC}=已安裝  ${RED}紅色${NC}=未安裝\n"
    printf "${YELLOW}提示:${NC} 修改 config/modules.conf 可自訂安裝內容\n"
    printf "\n按 Enter 返回選單..."
    read -r
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

# 添加模組到選擇列表（動態支援）
add_module() {
    local num=$1

    if [ "$USE_MODULE_MANAGER" = "true" ] && [ ${#MODULE_LIST[@]} -gt 0 ]; then
        local total=${#MODULE_LIST[@]}
        local all_num=$((total + 1))

        if [ "$num" -eq "$all_num" ]; then
            # 全部安裝
            selected_modules="${MODULE_LIST[*]}"
            return
        elif [ "$num" -ge 1 ] && [ "$num" -le "$total" ]; then
            local module_id="${MODULE_LIST[$((num - 1))]}"
            # 避免重複添加
            if [[ ! " $selected_modules " =~ " $module_id " ]]; then
                selected_modules="$selected_modules $module_id"
            fi
            return
        fi
    else
        # 備用靜態邏輯
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
        return
    fi

    printf "${RED}無效的選項：$num${NC}\n"
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

    local install_order=()
    if [ "$USE_MODULE_MANAGER" = "true" ] && [ ${#MODULE_LIST[@]} -gt 0 ]; then
        install_order=("${MODULE_LIST[@]}")
    else
        install_order=(base dev python monitoring docker terminal)
    fi

    # 計算要安裝的模組數量
    local total_modules=0
    local current_module=0
    for module in "${install_order[@]}"; do
        case " $selected_modules " in
            *" $module "*) total_modules=$((total_modules + 1)) ;;
        esac
    done

    # 干運行模式：僅顯示將要安裝的內容
    if [ "$DRY_RUN" = true ]; then
        printf "\n${CYAN}========== 預覽模式 (Dry Run) ==========${NC}\n"
        printf "${BLUE}將安裝以下 $total_modules 個模組：${NC}\n\n"

        for module in "${install_order[@]}"; do
            case " $selected_modules " in
                *" $module "*) ;;
                *) continue ;;
            esac

            if [ "$USE_MODULE_MANAGER" = "true" ] && [ ${#MODULE_LIST[@]} -gt 0 ]; then
                local module_name="${MODULE_NAMES[$module]:-$module}"
                printf "${GREEN}[$module]${NC} %s\n" "$module_name"
                [ -n "${MODULE_PACKAGES[$module]:-}" ] && printf "  • packages: %s\n" "${MODULE_PACKAGES[$module]}" || true
                [ -n "${MODULE_BREW_PACKAGES[$module]:-}" ] && printf "  • brew: %s\n" "${MODULE_BREW_PACKAGES[$module]}" || true
                [ -n "${MODULE_PIP_PACKAGES[$module]:-}" ] && printf "  • pip: %s\n" "${MODULE_PIP_PACKAGES[$module]}" || true
                [ -n "${MODULE_CARGO_PACKAGES[$module]:-}" ] && printf "  • cargo: %s\n" "${MODULE_CARGO_PACKAGES[$module]}" || true
                [ -n "${MODULE_NPM_PACKAGES[$module]:-}" ] && printf "  • npm: %s\n" "${MODULE_NPM_PACKAGES[$module]}" || true
            else
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
            fi
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
    for module in "${install_order[@]}"; do
        case " $selected_modules " in
            *" $module "*) ;;
            *) continue ;;
        esac

        current_module=$((current_module + 1))
        printf "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        printf "${GREEN}進度: [$current_module/$total_modules]${NC} 安裝模組: ${BLUE}$module${NC}\n"
        printf "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n\n"

        # 跟踪最後執行的命令
        LAST_COMMAND="execute_script \"core/${module}_setup.sh\" \"$module\""
        
        if [ "$USE_MODULE_MANAGER" = "true" ] && command -v install_module >/dev/null 2>&1; then
            LAST_COMMAND="install_module \"$module\""
            install_module "$module" || {
                printf "${RED}安裝過程中出現錯誤，中止安裝${NC}\n"
                return 1
            }
        else
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
        fi
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
