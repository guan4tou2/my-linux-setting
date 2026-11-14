#!/usr/bin/env bash

# ==============================================================================
# Linux Environment Setup - Main Installation Script
# Version: 2.2.9
# ==============================================================================

# 自動切換到 Homebrew bash (需要 bash 4+ 支持關聯陣列)
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    # 嘗試找到 Homebrew 安裝的 bash
    # macOS: /opt/homebrew/bin (Apple Silicon), /usr/local/bin (Intel)
    # Linux: /home/linuxbrew/.linuxbrew/bin, $HOME/.linuxbrew/bin
    for brew_bash in \
        /opt/homebrew/bin/bash \
        /usr/local/bin/bash \
        /home/linuxbrew/.linuxbrew/bin/bash \
        "$HOME/.linuxbrew/bin/bash"; do
        if [ -x "$brew_bash" ] && "$brew_bash" --version 2>/dev/null | grep -q "version [4-9]"; then
            exec "$brew_bash" "$0" "$@"
        fi
    done
    # 如果沒有找到新版 bash，顯示警告但繼續執行（使用備用邏輯）
    echo -e "\033[0;33mWARNING: Bash 版本 ($BASH_VERSION) 較舊，部分功能可能受限\033[0m"
    echo -e "\033[0;33m建議安裝新版 Bash: brew install bash\033[0m"
fi

# 幫助函數（必須在參數解析之前定義）
show_help() {
    cat << 'EOF'
Linux Setting Scripts - 自動安裝腳本 v2.2.9

用法: ./install.sh [選項]

選項:
  --minimal                       最小安裝模式
  --non-interactive               無人值守模式（不進入互動選單）
  --update                        更新已安裝的組件
  --dry-run                       預覽模式（不實際安裝）
  --force, --force-reinstall      強制重新安裝（不跳過已安裝的模組）
  -a, --advanced                  進階模式：每個模組進去再選具體要裝的套件
  --abort-on-failure              單一模組失敗就中斷（預設僅警告並繼續）
  --rollback                      把最近一次安裝前的備份（~/.zshrc、~/.p10k.zsh、
                                  ~/.config/nvim）還原到原位置；不需要 sudo，也不下載任何東西
  -y, --yes                       搭配 --rollback 時不詢問、直接還原
  -v, --verbose                   顯示詳細日誌
  -h, --help                      顯示此幫助訊息
  --config <file>                 指定配置文件路徑

環境變數:
  TUI_BACKEND=auto|gum|fzf|whiptail  指定互動選單後端（預設 auto）
  TUI_MODE=quiet|normal              控制安裝輸出詳細程度
  TUI_LOG_LINES=300                  TUI 查看安裝日誌時顯示的尾端行數

範例:
  ./install.sh                    # 標準安裝（互動式選單）
  ./install.sh --minimal          # 最小安裝
  ./install.sh --non-interactive --minimal  # 無人值守最小安裝
  ./install.sh --dry-run          # 預覽將要安裝的內容
  ./install.sh --update           # 更新模式
  ./install.sh --rollback         # 還原最近一次安裝前的設定檔備份
  ./install.sh --verbose          # 詳細模式
  TUI_BACKEND=fzf ./install.sh     # 使用 fzf 互動選單
  TUI_BACKEND=gum ./install.sh     # 使用 gum 互動選單
  TUI_LOG_LINES=500 ./install.sh   # TUI 中顯示最近 500 行日誌

更多資訊請參閱 README.md
EOF
}

# 顯示歡迎信息（精簡標題；--help 與參數錯誤時不顯示）
show_welcome() {
    printf "\n  \033[1mLinux Setting Scripts  v2.2.9\033[0m\n"
    printf "  自動化開發環境配置工具\n\n"
}


# ==============================================================================
# --rollback：還原最近一次安裝前的設定檔備份
# 這段在 common.sh 載入之前執行（遠端執行時 common.sh 尚未下載），
# 因此不可使用 common.sh 的函式或顏色變數，也不會下載任何東西。
# ==============================================================================

# 備份目錄內的名稱 -> 原位置（只認 backup_config_files 會備份的三項）
rollback_dest_for() {
    case "$1" in
        .zshrc|.p10k.zsh) printf '%s\n' "$HOME/$1" ;;
        nvim) printf '%s\n' "$HOME/.config/nvim" ;;
        *) return 1 ;;
    esac
}

run_rollback() {
    local c_y=$'\033[0;33m' c_g=$'\033[0;32m' c_r=$'\033[0;31m' c_n=$'\033[0m'
    local backup_root="$HOME/.config/linux-setting-backup"
    local latest="" d

    if [ -d "$backup_root" ]; then
        # 目錄名稱為 YYYYmmdd_HHMMSS，字串排序即時間排序
        while IFS= read -r d; do
            latest="$d"
        done < <(find "$backup_root" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)
    fi

    local srcs=() dests=() src name dest
    if [ -n "$latest" ]; then
        for src in "$latest"/.[!.]* "$latest"/*; do
            if [ ! -e "$src" ] && [ ! -L "$src" ]; then
                continue
            fi
            name="$(basename "$src")"
            if dest="$(rollback_dest_for "$name")"; then
                srcs+=("$src")
                dests+=("$dest")
            fi
        done
    fi

    if [ "${#srcs[@]}" -eq 0 ]; then
        printf '%s沒有可還原的備份%s（%s）\n' "$c_y" "$c_n" "$backup_root" >&2
        printf '備份由 install.sh 在每次安裝開始時自動建立。\n' >&2
        return 1
    fi

    printf '\n將從備份 %s 還原以下設定檔：\n' "$latest"
    local i
    for i in "${!srcs[@]}"; do
        printf '  %s -> %s\n' "$(basename "${srcs[$i]}")" "${dests[$i]}"
    done
    printf '目前的檔案會先另存為同目錄下的 .before-rollback 副本。\n\n'

    if [ "$ASSUME_YES" != "true" ] && [ "$NON_INTERACTIVE" != "true" ]; then
        if [ ! -t 0 ]; then
            printf '%s非互動環境且未指定 -y / --non-interactive，終止還原%s\n' "$c_r" "$c_n" >&2
            return 1
        fi
        local answer=""
        read -r -p "確認還原？(y/N) " answer || true
        if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
            printf '已取消\n'
            return 0
        fi
    fi

    local failed=0 saved
    for i in "${!srcs[@]}"; do
        src="${srcs[$i]}"
        dest="${dests[$i]}"
        saved="$dest.before-rollback"
        mkdir -p "$(dirname "$dest")" || { failed=$((failed + 1)); continue; }
        if [ -e "$dest" ] || [ -L "$dest" ]; then
            rm -rf "$saved"
            if ! mv "$dest" "$saved"; then
                printf '%s無法保存目前的 %s，略過%s\n' "$c_r" "$dest" "$c_n" >&2
                failed=$((failed + 1))
                continue
            fi
        fi
        if cp -a "$src" "$dest"; then
            printf '%s已還原%s %s\n' "$c_g" "$c_n" "$dest"
        else
            printf '%s還原失敗%s %s\n' "$c_r" "$c_n" "$dest" >&2
            rm -rf "$dest"
            if [ -e "$saved" ] || [ -L "$saved" ]; then
                mv "$saved" "$dest" || true
            fi
            failed=$((failed + 1))
        fi
    done

    if [ "$failed" -gt 0 ]; then
        printf '%s有 %d 項還原失敗%s\n' "$c_r" "$failed" "$c_n" >&2
        return 1
    fi
    printf '%s還原完成%s\n' "$c_g" "$c_n"
    return 0
}

# 下載網址檢查：必須是 https://；唯一例外是主機為 localhost、127.0.0.1 或 [::1] 的
# http://（本機測試伺服器）。含 userinfo（@）的 http 網址一律拒絕。
# 這些網址會用來下載並執行腳本，且此段在 common.sh 載入之前執行，所以自成一體。
_download_url_allowed() {
    local url="$1" rest authority host
    case "$url" in
        https://*) return 0 ;;
        http://*)
            rest="${url#http://}"
            authority="${rest%%[/?#]*}"
            case "$authority" in
                *@*|*\\*|*[[:space:]]*) return 1 ;;
            esac
            case "$authority" in
                \[*) host="${authority%%]*}]" ;;
                *) host="${authority%%:*}" ;;
            esac
            case "$host" in
                localhost|127.0.0.1|"[::1]") return 0 ;;
            esac
            return 1
            ;;
    esac
    return 1
}

validate_download_urls() {
    local name value bad=0
    for name in REPO_URL SCRIPTS_URL P10K_CONFIG_URL REQUIREMENTS_URL; do
        value="${!name:-}"
        [ -n "$value" ] || continue
        if ! _download_url_allowed "$value"; then
            printf '\033[0;31mERROR: %s 必須是 https:// 網址（僅 localhost、127.0.0.1、[::1] 允許 http://），目前為：%s\033[0m\n' "$name" "$value" >&2
            bad=1
        fi
    done
    [ "$bad" -eq 0 ]
}

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
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
FORCE_REINSTALL="${FORCE_REINSTALL:-false}"
ADVANCED_MODE="${ADVANCED_MODE:-false}"
ABORT_ON_FAILURE="${ABORT_ON_FAILURE:-false}"
ROLLBACK_MODE=false
ASSUME_YES=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --minimal)
            INSTALL_MODE="minimal"
            shift
            ;;
        --non-interactive)
            NON_INTERACTIVE=true
            USE_TUI=false
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
        --force|--force-reinstall)
            FORCE_REINSTALL=true
            shift
            ;;
        --advanced|-a)
            ADVANCED_MODE=true
            shift
            ;;
        --abort-on-failure)
            ABORT_ON_FAILURE=true
            shift
            ;;
        --rollback)
            ROLLBACK_MODE=true
            shift
            ;;
        -y|--yes)
            ASSUME_YES=true
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
            if [ -n "${2:-}" ]; then
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

# 強烈建議不要用 sudo 直接跑整支安裝（會把設定/工具裝到 /root，且 brew 會失敗）
if [ "${EUID:-$(id -u)}" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "${ALLOW_ROOT:-false}" != "true" ]; then
    # 此時 common.sh 尚未載入，使用區塊內專用的跳脫碼變數（不可與 common.sh 的 readonly 名稱衝突）
    _sudo_y=$'\033[0;33m'
    _sudo_g=$'\033[0;32m'
    _sudo_c=$'\033[0;36m'
    _sudo_n=$'\033[0m'
    printf '\n%s偵測到你用 sudo 以 root 執行。%s\n' "$_sudo_y" "$_sudo_n"
    printf '%s- 這會把 ~/.zshrc、uv、nvim 等安裝到 /root%s\n' "$_sudo_y" "$_sudo_n"
    printf '%s- 且 Homebrew 套件多半會因 root 而失敗%s\n\n' "$_sudo_y" "$_sudo_n"
    printf '%s請改用一般使用者執行：%s\n' "$_sudo_g" "$_sudo_n"
    printf '%s\n\n' '  bash -c "$(curl -fsSL https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main/install.sh)"'
    printf '%s若你真的要用 root 跑（例如容器），請加：%s ALLOW_ROOT=true\n\n' "$_sudo_c" "$_sudo_n"
    exit 1
fi

# --rollback：只還原本機備份，不需要 sudo、不做環境檢查、不下載任何東西
if [ "$ROLLBACK_MODE" = true ]; then
    trap - ERR
    rollback_rc=0
    run_rollback || rollback_rc=$?
    exit "$rollback_rc"
fi

show_welcome

# Export variables for child scripts
export INSTALL_MODE UPDATE_MODE VERBOSE DEBUG DRY_RUN SKIP_PYTHON_CHECK NON_INTERACTIVE FORCE_REINSTALL ADVANCED_MODE ABORT_ON_FAILURE

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

# 這些網址會被用來下載並執行腳本：在任何下載之前先確認是 https（或本機測試伺服器）
validate_download_urls || exit 1

# Export configuration
export REPO_URL SCRIPTS_URL P10K_CONFIG_URL REQUIREMENTS_URL
export ENABLE_PARALLEL_INSTALL PARALLEL_JOBS

# ==============================================================================
# Remote Installation with Security Verification
# ==============================================================================

# 以 install.sh 所在目錄推導 SCRIPT_DIR，避免使用者 `cd /tmp && bash ~/repo/install.sh`
# 或透過絕對路徑執行時被誤判為「找不到本地檔案」而走遠端下載。
# 注意：`bash -c "$(curl ... install.sh)"` 時 BASH_SOURCE[0] 為空，這種情況才會走遠端。
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    INSTALL_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SCRIPT_DIR="$INSTALL_SH_DIR/scripts"
else
    SCRIPT_DIR="$PWD/scripts"
fi
REMOTE_INSTALL=false
# 遠端安裝才會建立暫存目錄；先給預設值，避免 cleanup_temp_files 在 set -u 下讀到未定義變數
TEMP_DIR="${TEMP_DIR:-}"

bootstrap_status() {
    local level="$1"
    local message="$2"

    if [ "$level" != "ERROR" ] && [ "${TUI_MODE:-quiet}" = "quiet" ] && [ "${TUI_LOG_TO_TERMINAL:-auto}" != "true" ]; then
        return 0
    fi

    case "$level" in
        INFO) printf "\033[0;36mINFO: %s\033[0m\n" "$message" ;;
        SUCCESS) printf "\033[0;32mSUCCESS: %s\033[0m\n" "$message" ;;
        ERROR) printf "\033[0;31mERROR: %s\033[0m\n" "$message" >&2 ;;
        *) printf "%s: %s\n" "$level" "$message" ;;
    esac
}

# Try local common.sh first
if [ -f "$SCRIPT_DIR/core/common.sh" ]; then
    source "$SCRIPT_DIR/core/common.sh"
elif [ -f "./scripts/core/common.sh" ]; then
    SCRIPT_DIR="$PWD/scripts"
    source "./scripts/core/common.sh"
else
    # Remote installation - bootstrap without common.sh functions
    TEMP_DIR=$(mktemp -d)
    SCRIPT_DIR="$TEMP_DIR/scripts"
    mkdir -p "$SCRIPT_DIR/core"

    bootstrap_status "INFO" "Downloading common library from remote source..."

    # Download common.sh (without using safe_download since it's not loaded yet)
    COMMON_URL="$SCRIPTS_URL/core/common.sh"
    COMMON_OUTPUT="$SCRIPT_DIR/core/common.sh"

    if curl -fsSL --max-time 30 "$COMMON_URL" -o "$COMMON_OUTPUT" 2>/dev/null; then
        # Basic validation before sourcing
        if [ -s "$COMMON_OUTPUT" ] && head -1 "$COMMON_OUTPUT" | grep -q "^#!/"; then
            # shellcheck source=/dev/null
            source "$COMMON_OUTPUT"
            REMOTE_INSTALL=true
            bootstrap_status "SUCCESS" "Common library loaded"
        else
            bootstrap_status "ERROR" "Downloaded file appears invalid"
            rm -rf "$TEMP_DIR"
            exit 1
        fi
    else
        bootstrap_status "ERROR" "Failed to download common library"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
fi

# common.sh 可能載入了使用者設定檔並改寫上述網址；後續下載前再檢查一次
if ! validate_download_urls; then
    if [ -n "${TEMP_DIR:-}" ]; then
        rm -rf "$TEMP_DIR"
    fi
    exit 1
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

show_install_log_dialog() {
    local tail_lines="${1:-${TUI_LOG_LINES:-300}}"

    if [ -z "${LOG_FILE:-}" ] || [ ! -f "${LOG_FILE:-}" ]; then
        if [ "${USE_TUI:-false}" = "true" ] && command -v tui_msgbox >/dev/null 2>&1; then
            tui_msgbox "安裝日誌" "目前尚未建立日誌文件。" || true
        else
            printf "${YELLOW}目前尚未建立日誌文件${NC}\n"
        fi
        return 0
    fi

    if [ "${USE_TUI:-false}" = "true" ] && command -v tui_log_viewer >/dev/null 2>&1; then
        # 先把日誌尾端整理成可讀版本（去掉 \r 進度覆寫與 ANSI 色碼），原日誌不變
        local view_file=""
        view_file="$(mktemp "${TMPDIR:-/tmp}/linux-setting-view.XXXXXX" 2>/dev/null)" || view_file=""
        if [ -n "$view_file" ] \
           && tail -n "$tail_lines" "$LOG_FILE" 2>/dev/null \
              | sed -e 's/\r$//' -e 's/.*\r//' -e 's/\x1b\[[0-9;?]*[A-Za-z]//g' > "$view_file" 2>/dev/null; then
            tui_log_viewer "安裝日誌" "$view_file" all || true
        else
            tui_log_viewer "安裝日誌" "$LOG_FILE" "$tail_lines" || true
        fi
        if [ -n "$view_file" ]; then
            rm -f "$view_file"
        fi
    else
        printf "\n${CYAN}########## 最新安裝日誌 ##########${NC}\n"
        tail -n "$tail_lines" "$LOG_FILE" 2>/dev/null || true
        printf "${CYAN}########## 日誌結束 ##########${NC}\n"
    fi
}

installer_tui_quiet() {
    [ "${NON_INTERACTIVE:-false}" != "true" ] || return 1
    [ "${TUI_MODE:-quiet}" = "quiet" ] || return 1
    [ "${TUI_LOG_TO_TERMINAL:-auto}" != "true" ] || return 1
    [ "${USE_TUI:-auto}" != "false" ] || return 1
}

prepare_initial_tui_backend() {
    [ -t 0 ] || return 0
    [ "${INSTALL_MODE:-full}" != "minimal" ] || return 0
    [ "${NON_INTERACTIVE:-false}" != "true" ] || return 0
    [ "${USE_TUI:-auto}" != "false" ] || return 0

    if command -v _select_tui_backend >/dev/null 2>&1; then
        _select_tui_backend >/dev/null 2>&1 || true
    fi
}

run_logged_command() {
    if installer_tui_quiet && [ -n "${LOG_FILE:-}" ]; then
        "$@" >> "$LOG_FILE" 2>&1
    else
        "$@"
    fi
}

# common.sh 的顏色變數是字面 '\033[...' 字串（給 printf 格式用）；
# 當作 %s 參數輸出前需先轉成真正的跳脫字元
_ansi() {
    printf '%b' "${1:-}"
}

# 錯誤處理函數
handle_error() {
    local exit_code=$1
    local line_number="$2"
    local last_command="${3:-}"

    # 避免錯誤處理本身再觸發 ERR trap / set -e 而遞迴
    trap - ERR
    set +e

    # 安裝進度動畫若仍在跑，先停掉，避免與錯誤訊息交錯
    if declare -F _progress_stop_spinner >/dev/null 2>&1; then
        _progress_stop_spinner
    fi

    print_error_summary "$exit_code" "$line_number" "$last_command"

    # 詢問是否查看日誌
    if [ -t 0 ] && [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        if [ "${USE_TUI:-false}" = "true" ] && command -v tui_yesno >/dev/null 2>&1; then
            if tui_yesno "安裝失敗" "安裝流程已中止。\n\n要查看最新的安裝日誌嗎？" "yes"; then
                show_install_log_dialog 300
            fi
        else
            local choice=""
            printf "${CYAN:-}[l]${NC:-} 查看日誌  ${CYAN:-}[q]${NC:-} 退出: "
            read -r -n 1 choice || true
            printf "\n"
            case "$choice" in
                l|L) show_install_log_dialog 300 ;;
            esac
        fi
    fi

    if command -v cleanup_temp_files >/dev/null 2>&1; then
        cleanup_temp_files || true
    fi
    exit "$exit_code"
}

# 依套件管理器給出「更新套件索引」的建議指令
package_index_update_hint() {
    case "${1:-${PKG_MANAGER:-}}" in
        apt) printf '%s' "sudo apt update" ;;
        dnf) printf '%s' "sudo dnf makecache" ;;
        yum) printf '%s' "sudo yum makecache" ;;
        pacman) printf '%s' "sudo pacman -Sy" ;;
        zypper) printf '%s' "sudo zypper refresh" ;;
        *) printf '%s' "" ;;
    esac
}

# 錯誤摘要（純輸出，不讀輸入；可在測試中直接呼叫）
print_error_summary() {
    local exit_code="$1"
    local line_number="$2"
    local last_command="${3:-}"
    local red yellow green nc
    red="$(_ansi "${RED:-}")"
    yellow="$(_ansi "${YELLOW:-}")"
    green="$(_ansi "${GREEN:-}")"
    nc="$(_ansi "${NC:-}")"

    printf "\n%s✗ 安裝失敗%s\n\n" "$red" "$nc"
    printf "  位置：install.sh 第 %s 行（結束碼 %s）\n" "$line_number" "$exit_code"
    if [ -n "$last_command" ]; then
        printf "  命令：%s\n" "${last_command:0:120}"
    fi
    if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        printf "  日誌：%s\n" "$LOG_FILE"
    fi

    printf "\n%s可能原因%s：網路連線、套件來源無法存取、磁碟空間不足或權限不足。\n" "$yellow" "$nc"
    printf "\n%s建議操作%s：\n" "$green" "$nc"
    local step=1
    if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        printf "  %d. 查看日誌：tail -n 50 %q\n" "$step" "$LOG_FILE"
        step=$((step + 1))
    fi
    printf "  %d. 檢查網路：ping -c 1 github.com\n" "$step"
    step=$((step + 1))
    local update_hint
    update_hint="$(package_index_update_hint "${PKG_MANAGER:-}")"
    if [ -n "$update_hint" ]; then
        printf "  %d. 更新套件索引：%s\n" "$step" "$update_hint"
        step=$((step + 1))
    fi
    printf "  %d. 檢查空間：df -h /\n" "$step"
    printf "  修正後重新執行安裝程式即可；已安裝的模組會自動略過套件階段。\n"
    printf "\n需要幫助？https://github.com/guan4tou2/my-linux-setting/issues\n\n"
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

    # 檢測並啟用 TUI（如果可用）
    # NON_INTERACTIVE 與 minimal 模式不嘗試啟用 TUI，也不安裝 whiptail/dialog
    if [ -t 0 ] \
       && [ "${INSTALL_MODE}" != "minimal" ] \
       && [ "${NON_INTERACTIVE:-false}" != "true" ]; then
        if command -v ensure_tui_available >/dev/null 2>&1; then
            ensure_tui_available && log_success "TUI 模式已啟用" || log_info "使用命令行模式"
        fi
    fi

    # 檢查並提示安裝 Homebrew（可選）
    # 先試 PATH，失敗時再檢查 Linuxbrew/macOS 的常見安裝路徑，
    # 因為 Homebrew 的 `brew-on` alias 只在互動 shell 生效，
    # `bash -c` 這類非互動入口會誤判為「未安裝」。
    if ! command -v brew >/dev/null 2>&1; then
        local brew_bin=""
        for candidate in \
            /home/linuxbrew/.linuxbrew/bin/brew \
            "$HOME/.linuxbrew/bin/brew" \
            /opt/homebrew/bin/brew \
            /usr/local/bin/brew; do
            if [ -x "$candidate" ]; then
                brew_bin="$candidate"
                break
            fi
        done
        if [ -n "$brew_bin" ]; then
            log_success "檢測到 Homebrew 已安裝於 $brew_bin"
            eval "$("$brew_bin" shellenv)" 2>/dev/null || {
                PATH="$(dirname "$brew_bin"):$PATH" || true
                export PATH
            }
            log_info "已將 Homebrew 注入當前 session 的 PATH"
        fi
    fi

    if command -v brew >/dev/null 2>&1 && command -v ensure_brew_shell_aliases >/dev/null 2>&1; then
        ensure_brew_shell_aliases "$(command -v brew)" || true
    fi

    # 是否安裝 Homebrew 改在選完模組後才詢問（見 offer_homebrew_if_needed），
    # 這裡只偵測既有安裝並注入 PATH。
    if ! command -v brew >/dev/null 2>&1; then
        log_info "系統未安裝 Homebrew（APT 優先；若所選模組需要備援，選完模組後會再詢問）"
    else
        log_success "檢測到 Homebrew 已安裝（APT 優先，brew 僅作備援）"
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
        # 使用通用安裝方式；避免原本依賴 "$?" 在複合 if/case 結構下的歧義
        if command -v update_system >/dev/null 2>&1; then
            update_system || true
        fi

        local py_rc=0
        if command -v install_package >/dev/null 2>&1; then
            install_package python3 && install_package python3-pip || py_rc=$?
        else
            case "$PKG_MANAGER" in
                apt) run_as_root apt-get install -y python3 python3-venv python3-pip || py_rc=$? ;;
                dnf|yum) run_as_root $PKG_MANAGER install -y python3 python3-pip || py_rc=$? ;;
                pacman) run_as_root pacman -S --noconfirm python python-pip || py_rc=$? ;;
                *) py_rc=1 ;;
            esac
        fi

        if [ "$py_rc" -eq 0 ]; then
            log_success "Python 3 安裝完成"
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

# 安裝清單是否已有某一行（供備份時判斷，不依賴 common.sh 的內部細節）
_manifest_has() {
    local manifest="${INSTALL_MANIFEST_FILE:-}"
    [ -n "$manifest" ] && [ -f "$manifest" ] && grep -qxF -- "$1:$2" "$manifest" 2>/dev/null
}

# 備份配置文件
# 自動保留最新 N 份（預設 10），透過 BACKUP_RETENTION 環境變數調整
# 備份可能含有憑證，根目錄與備份目錄都設為 0700
backup_config_files() {
    log_info "備份配置文件..."
    local backup_root="$HOME/.config/linux-setting-backup"
    mkdir -p "$backup_root"
    chmod 0700 "$backup_root" 2>/dev/null || true
    BACKUP_DIR="$backup_root/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    chmod 0700 "$BACKUP_DIR" 2>/dev/null || true
    # 讓子行程的 backup_file 也寫進同一個備份目錄，而不是另建一個較新的目錄
    export BACKUP_DIR

    # 備份現有的配置文件；安裝前不存在的記下來，安裝結束後若已出現就是本工具建立的
    BACKUP_ABSENT_PATHS=()
    local file recorded=false
    for file in ~/.zshrc ~/.p10k.zsh ~/.config/nvim; do
        if [ -e "$file" ]; then
            cp -r "$file" "$BACKUP_DIR/"
            log_success "已備份：$file"
            # 已列為「本工具建立」的檔案，還原到先前安裝的狀態沒有意義；
            # 已列為 file 的檔案，最早的那一份備份才是安裝前的狀態，不再記新的
            if ! _manifest_has path "$file" && ! _manifest_has file "$file"; then
                manifest_record file "$file"
                recorded=true
            fi
        else
            BACKUP_ABSENT_PATHS+=("$file")
        fi
    done
    if [ "$recorded" = true ]; then
        manifest_record backup "$BACKUP_DIR"
    fi

    # Retention：保留最新 N 份，刪除更舊的（安裝清單引用的備份一律保留）
    local retention="${BACKUP_RETENTION:-10}"
    if [ -d "$backup_root" ] && [ "$retention" -gt 0 ] 2>/dev/null; then
        # 列出所有備份子目錄（依日期格式排序）並移除超出 retention 的舊者
        local old_backups
        old_backups=$(ls -1t "$backup_root" 2>/dev/null | tail -n +$((retention + 1)))
        if [ -n "$old_backups" ]; then
            while IFS= read -r dir; do
                if [ -n "$dir" ] && _manifest_has backup "$backup_root/$dir"; then
                    continue
                fi
                [ -n "$dir" ] && rm -rf "${backup_root:?}/$dir" \
                    && log_info "已清理舊備份：$dir"
            done <<< "$old_backups"
        fi
    fi
}

# 安裝結束後，把「安裝前不存在、現在存在」的設定檔記為本工具建立的路徑
record_created_configs() {
    local f
    for f in ${BACKUP_ABSENT_PATHS[@]+"${BACKUP_ABSENT_PATHS[@]}"}; do
        if [ -e "$f" ]; then
            manifest_record path "$f"
        fi
    done
}

# 設置日誌
setup_logging() {
    # LOG_DIR 可能已在 common.sh 中定義為 readonly，使用局部變數
    local log_dir="${LOG_DIR:-$HOME/.local/log/linux-setting}"
    mkdir -p "$log_dir"
    chmod 0700 "$log_dir" 2>/dev/null || true
    LOG_FILE="$log_dir/install_$(date +%Y%m%d_%H%M%S).log"
    export LOG_FILE
    export ENABLE_LOGGING=true
    : > "$LOG_FILE"

    if installer_tui_quiet; then
        log_success "安裝日誌將保存到：$LOG_FILE"
    else
        exec > >(tee -a "$LOG_FILE") 2>&1
        printf "${GREEN}安裝日誌將保存到：$LOG_FILE${NC}\n"
    fi
}

remote_download_progress() {
    local enabled="$1"
    local percent="$2"
    local message="$3"

    [ "$enabled" = "true" ] || return 0
    printf '%s\n' "$percent"
    printf 'XXX\n%s\nXXX\n' "$message"
}

download_remote_file() {
    local label="$1"
    local url="$2"
    local output="$3"
    local mode="${4:-}"
    local curl_opts=(-fsSL --connect-timeout 15 --max-time "${DOWNLOAD_TIMEOUT:-60}")

    log_info "下載 $label..."
    curl "${curl_opts[@]}" "$url" -o "$output"
    if [ -n "$mode" ]; then
        chmod "$mode" "$output"
    fi
    log_success "已下載 $label"
}

download_remote_scripts() {
    local show_progress="${1:-false}"
    local total=10
    local current=0

    mkdir -p "$SCRIPT_DIR/core" "$SCRIPT_DIR/utils" "$SCRIPT_DIR/maintenance"

    local script=""
    for script in python_setup.sh docker_setup.sh terminal_setup.sh base_tools.sh dev_tools.sh monitoring_tools.sh; do
        current=$((current + 1))
        remote_download_progress "$show_progress" "$((current * 100 / total))" "下載 core/$script..."
        download_remote_file "core/$script" "$SCRIPTS_URL/core/$script" "$SCRIPT_DIR/core/$script" "+x"
    done

    current=$((current + 1))
    remote_download_progress "$show_progress" "$((current * 100 / total))" "下載 utils/secure_download.sh..."
    download_remote_file "utils/secure_download.sh" "$SCRIPTS_URL/utils/secure_download.sh" "$SCRIPT_DIR/utils/secure_download.sh" "+x"

    current=$((current + 1))
    remote_download_progress "$show_progress" "$((current * 100 / total))" "下載 maintenance/update_tools.sh..."
    download_remote_file "maintenance/update_tools.sh" "$SCRIPTS_URL/maintenance/update_tools.sh" "$SCRIPT_DIR/maintenance/update_tools.sh" "+x"

    current=$((current + 1))
    remote_download_progress "$show_progress" "$((current * 100 / total))" "下載 core/module_manager.sh..."
    download_remote_file "core/module_manager.sh" "$SCRIPTS_URL/core/module_manager.sh" "$SCRIPT_DIR/core/module_manager.sh" "+x"

    current=$((current + 1))
    remote_download_progress "$show_progress" "$((current * 100 / total))" "下載 config/modules.conf..."
    mkdir -p "$SCRIPT_DIR/../config"
    download_remote_file "config/modules.conf" "$REPO_URL/config/modules.conf" "$SCRIPT_DIR/../config/modules.conf"
}

run_remote_script_downloads() {
    log_info "下載安裝腳本..."

    if installer_tui_quiet \
       && [ "${USE_TUI:-false}" = "true" ] \
       && [ "${TUI_BACKEND:-}" = "whiptail" ] \
       && command -v tui_gauge >/dev/null 2>&1; then
        download_remote_scripts true | tui_gauge "下載安裝腳本" "正在下載必要腳本..." 0
    else
        download_remote_scripts false
        if installer_tui_quiet \
           && [ "${USE_TUI:-false}" = "true" ] \
           && command -v tui_msgbox >/dev/null 2>&1; then
            tui_msgbox "下載安裝腳本" "必要腳本已下載完成。\n\n詳細內容已寫入安裝日誌。" || true
        fi
    fi

    log_success "安裝腳本下載完成"
}

# 定義模組陣列
MODULES="python docker base terminal dev monitoring"
MINIMAL_MODULES="base python terminal"
selected_modules=""
installed_modules=""

# REMOTE_INSTALL 只由上方的遠端 bootstrap 設定（找不到本地 common.sh 時）。
# 過去這裡還會把「SCRIPT_DIR 位於 /tmp」當成遠端安裝，結果在 /tmp 下的完整專案
# （例如 git clone 到 /tmp）執行時，本地腳本會被 $REPO_URL 的版本覆蓋。
REMOTE_INSTALL=${REMOTE_INSTALL:-false}

# 模組顯示名稱：優先使用 modules.conf 的 name，否則用內建名稱，最後退回 id
module_display_name() {
    local module_id="$1"
    if [[ "$(declare -p MODULE_NAMES 2>/dev/null)" == "declare -A"* ]] \
       && [ -n "${MODULE_NAMES[$module_id]:-}" ]; then
        printf '%s' "${MODULE_NAMES[$module_id]}"
        return 0
    fi
    case "$module_id" in
        python) printf '%s' "Python 開發環境" ;;
        docker) printf '%s' "Docker 工具" ;;
        base) printf '%s' "基礎工具" ;;
        terminal) printf '%s' "終端設定" ;;
        dev) printf '%s' "開發工具" ;;
        monitoring) printf '%s' "監控工具" ;;
        *) printf '%s' "$module_id" ;;
    esac
}

# 將 id 清單轉成「顯示名稱」清單，以「、」分隔
module_display_names() {
    local out="" module_id
    for module_id in $1; do
        if [ -n "$out" ]; then
            out="${out}、"
        fi
        out="${out}$(module_display_name "$module_id")"
    done
    printf '%s' "$out"
}

# 勾選清單項目文字：名稱 — 內容（狀態），不使用方括號以免與勾選框混淆
module_checklist_label() {
    local name="$1"
    local desc="${2:-}"
    local status="${3:-}"
    local label="$name"
    if [ -n "$desc" ]; then
        label="$label — $desc"
    fi
    case "$status" in
        installed) label="$label（已安裝）" ;;
        partial) label="$label（部分安裝）" ;;
    esac
    printf '%s' "$label"
}

# 勾選清單最後一列的虛擬項目：進階模式（tag 不是模組 id，解析結果時會剔除）
ADVANCED_CHECKLIST_TAG="+advanced"
ADVANCED_CHECKLIST_LABEL="進階：安裝前逐模組挑選套件"

# 組出勾選清單：checklist_items（tag 與標籤成對）與 checklist_states（ON/OFF，順序同模組）。
# 預設只勾選尚未安裝或部分安裝的模組；已安裝的不勾（標籤仍顯示「已安裝」，可手動勾選以重跑設定）。
# 呼叫端須先宣告 local checklist_items=() checklist_states=()。
build_module_checklist_items() {
    checklist_items=()
    checklist_states=()
    if [ "$USE_MODULE_MANAGER" = "true" ] && [ ${#MODULE_LIST[@]} -gt 0 ]; then
        local module_id
        for module_id in "${MODULE_LIST[@]}"; do
            local name="${MODULE_NAMES[$module_id]:-$module_id}"
            local desc="${MODULE_DESCRIPTIONS[$module_id]:-}"
            local status=""

            if command -v check_module_status >/dev/null 2>&1; then
                status=$(check_module_status "$module_id" 2>/dev/null || true)
            fi

            checklist_items+=("$module_id" "$(module_checklist_label "$name" "$desc" "$status")")
            case "$status" in
                installed) checklist_states+=("OFF") ;;
                *) checklist_states+=("ON") ;;
            esac
        done
    else
        checklist_items=(
            "python"     "$(module_checklist_label "Python 開發環境" "python3, pip, uv, ranger")"
            "docker"     "$(module_checklist_label "Docker 工具" "docker-ce, lazydocker")"
            "base"       "$(module_checklist_label "基礎工具" "git, lsd, bat, ripgrep, fzf")"
            "terminal"   "$(module_checklist_label "終端設定" "zsh, oh-my-zsh, powerlevel10k")"
            "dev"        "$(module_checklist_label "開發工具" "neovim, lazygit, nodejs, rust")"
            "monitoring" "$(module_checklist_label "監控工具" "btop, htop, iftop, fail2ban")"
        )
        checklist_states=(ON ON ON ON ON ON)
    fi
}

parse_module_selection() {
    local module_selection="$1"
    selected_modules=""
    local _seen=" "
    local item

    for item in $module_selection; do
        item=$(echo "$item" | tr -d '"')
        [ -z "$item" ] && continue
        case "$_seen" in
            *" $item "*) continue ;;
        esac
        _seen+=" $item "
        selected_modules="$selected_modules $item"
    done

    selected_modules=$(echo "$selected_modules" | xargs)
    [ -n "$selected_modules" ]
}

# 解析勾選清單結果：把虛擬的進階項目剔除並設定 ADVANCED_MODE；
# 只勾了進階而沒有任何模組時視為未選擇（回傳 1）。
parse_checklist_selection() {
    local selection="${1:-}" item rest=""
    ADVANCED_MODE=false
    for item in $selection; do
        item="${item//\"/}"
        if [ "$item" = "$ADVANCED_CHECKLIST_TAG" ]; then
            ADVANCED_MODE=true
        else
            rest+=" $item"
        fi
    done
    parse_module_selection "$rest"
}

select_modules_tui() {
    if [ "$INSTALL_MODE" = "minimal" ]; then
        selected_modules="$MINIMAL_MODULES"
        tui_msgbox "模組選擇" "最小安裝將安裝：\n\n$(module_display_names "$selected_modules")" || true
        return 0
    fi

    local checklist_items=() checklist_states=()
    build_module_checklist_items

    # 進階模式預設關閉；使用者帶了 --advanced 時預設勾選
    local advanced_state="OFF"
    if [ "${GUIDED_ADVANCED_DEFAULT:-${ADVANCED_MODE:-false}}" = "true" ]; then
        advanced_state="ON"
    fi

    # fzf 後端的 tui_checklist 會自行附上按鍵說明，避免重複
    local key_hint=""
    case "${TUI_BACKEND:-whiptail}" in
        fzf) key_hint="" ;;
        *) key_hint="\n空白鍵勾選／取消，Enter 確認。" ;;
    esac
    local prompt="請勾選要安裝的模組（已安裝的預設不勾選）：${key_hint}"

    local state_items=() plain_items=() i
    for ((i = 0; i < ${#checklist_items[@]}; i += 2)); do
        state_items+=("${checklist_items[$i]}" "${checklist_items[$((i + 1))]}" "${checklist_states[$((i / 2))]}")
    done
    local advanced_locked=false
    if [ "${GUIDED_ADVANCED_DEFAULT:-false}" = "true" ] \
       && ! { declare -F _tui_backend_supports_state_checklist >/dev/null 2>&1 \
              && _tui_backend_supports_state_checklist; }; then
        advanced_locked=true
        prompt+="\n進階模式已由 --advanced 啟用。"
    fi
    plain_items=("${checklist_items[@]}")
    if [ "$advanced_locked" != "true" ]; then
        plain_items+=("$ADVANCED_CHECKLIST_TAG" "$ADVANCED_CHECKLIST_LABEL")
    fi
    state_items+=("$ADVANCED_CHECKLIST_TAG" "$ADVANCED_CHECKLIST_LABEL" "$advanced_state")

    local module_selection rc
    while :; do
        rc=0
        # whiptail 可指定預設勾選；其他後端（fzf／gum）沿用 tui_checklist 既有行為
        if declare -F _tui_backend_supports_state_checklist >/dev/null 2>&1 \
           && _tui_backend_supports_state_checklist; then
            module_selection=$(tui_checklist_with_state "模組選擇" "$prompt" "${state_items[@]}") || rc=$?
        else
            module_selection=$(tui_checklist "模組選擇" "$prompt" "${plain_items[@]}") || rc=$?
        fi

        # 取消勾選清單即退出
        [ "$rc" -eq 0 ] || return 1

        if parse_checklist_selection "$module_selection"; then
            [ "$advanced_locked" != "true" ] || ADVANCED_MODE=true
            return 0
        fi
        tui_msgbox "模組選擇" "請至少勾選一個模組。" || true
    done
}

# 單一模組安裝時會做的事（一行文字）。
# 套件數依 modules.conf 宣告的套件統計，算法與 check_module_status 一致；
# 設定腳本裡另外安裝的套件不在統計內，所以有 script 時另外註明。
# 沒有模組管理器資料時輸出空字串。
module_install_plan_text() {
    local module_id="$1"
    [[ "$(declare -p MODULE_NAMES 2>/dev/null)" == "declare -A"* ]] || return 0
    [ -n "${MODULE_NAMES[$module_id]:-}" ] || return 0
    command -v _module_pkg_is_installed >/dev/null 2>&1 || return 0

    local -a entries=()
    local pkg
    for pkg in ${MODULE_PACKAGES[$module_id]:-}; do entries+=("apt:$pkg"); done
    if [ -n "${MODULE_APT_FALLBACK[$module_id]:-}" ]; then
        for pkg in ${MODULE_APT_FALLBACK[$module_id]}; do entries+=("apt_fallback:$pkg"); done
    else
        for pkg in ${MODULE_BREW_PACKAGES[$module_id]:-}; do entries+=("brew:$pkg"); done
    fi
    for pkg in ${MODULE_PIP_PACKAGES[$module_id]:-}; do entries+=("pip:$pkg"); done
    if command -v cargo >/dev/null 2>&1; then
        for pkg in ${MODULE_CARGO_PACKAGES[$module_id]:-}; do entries+=("cargo:$pkg"); done
    fi
    if command -v npm >/dev/null 2>&1; then
        for pkg in ${MODULE_NPM_PACKAGES[$module_id]:-}; do entries+=("npm:$pkg"); done
    fi

    local total=0 todo=0 entry kind
    local -A seen=()
    for entry in ${entries[@]+"${entries[@]}"}; do
        kind="${entry%%:*}"
        pkg="${entry#*:}"
        # packages 與 apt_fallback 都走系統套件，同名只算一次（install_module 也是如此）
        case "$kind" in
            apt|apt_fallback)
                [ -z "${seen[$pkg]:-}" ] || continue
                seen[$pkg]=1
                ;;
        esac
        total=$((total + 1))
        if ! _module_pkg_is_installed "$kind" "$pkg"; then
            todo=$((todo + 1))
        fi
    done

    local has_script=false
    if [ -n "${MODULE_SCRIPTS[$module_id]:-}" ]; then
        has_script=true
    fi

    local text=""
    if [ "$todo" -gt 0 ]; then
        text="安裝 $todo 個套件"
        if [ $((total - todo)) -gt 0 ]; then
            text+="、略過 $((total - todo)) 個已安裝"
        fi
        if [ "$has_script" = "true" ]; then
            text+="，並執行設定腳本"
        fi
    elif [ "$total" -gt 0 ]; then
        text="套件皆已安裝"
        if [ "$has_script" = "true" ]; then
            text+="，只執行設定腳本"
        fi
    elif [ "$has_script" = "true" ]; then
        text="只執行設定腳本"
    else
        text="沒有宣告套件"
    fi
    printf '%s' "$text"
}

# 確認摘要文字（純函式，輸出含字面 \n，交給 whiptail/printf %b 解讀）
build_install_summary_text() {
    local summary=""
    if [ "${INSTALL_MODE:-full}" = "minimal" ]; then
        summary+="最小安裝（--minimal）\n\n"
    fi
    summary+="模組："
    if declare -F _module_pkg_status_cache_clear >/dev/null 2>&1; then
        _module_pkg_status_cache_clear
    fi
    local module_id plan
    for module_id in $selected_modules; do
        plan="$(module_install_plan_text "$module_id")"
        summary+="\n  • $(module_display_name "$module_id")${plan:+：$plan}"
    done
    if [ "${ADVANCED_MODE:-false}" = "true" ]; then
        summary+="\n\n進階模式：確認後會逐模組挑選要安裝的套件（以上為全部套件的數量）。"
    fi
    if [ "${HOMEBREW_DECISION:-}" = "yes" ]; then
        summary+="\n\nHomebrew：會先安裝（APT 裝不到時的備援）"
    fi
    local shown_log="${LOG_FILE:-未設定}"
    case "$shown_log" in "$HOME"/*) shown_log="~${shown_log#"$HOME"}" ;; esac
    summary+="\n\n日誌：${shown_log}\n\n確認後開始安裝，進度會顯示在終端機。"
    printf '%s' "$summary"
}

confirm_install_summary_tui() {
    tui_yesno "確認安裝" "$(build_install_summary_text)" "yes"
}

# 安裝結果統計，輸出「成功 部分失敗 失敗 未執行」
install_result_counts() {
    local i ok=0 partial=0 failed=0 not_run=0
    for ((i = 0; i < ${#INSTALL_RESULT_STATUS[@]}; i++)); do
        case "${INSTALL_RESULT_STATUS[$i]}" in
            ok) ok=$((ok + 1)) ;;
            partial) partial=$((partial + 1)) ;;
            failed) failed=$((failed + 1)) ;;
            *) not_run=$((not_run + 1)) ;;
        esac
    done
    printf '%s %s %s %s' "$ok" "$partial" "$failed" "$not_run"
}

# 一行總結
install_result_summary_line() {
    local ok partial failed not_run
    read -r ok partial failed not_run <<< "$(install_result_counts)"
    local total=$((ok + partial + failed + not_run))
    local message
    if [ "${DRY_RUN:-false}" = "true" ]; then
        message="預覽模式（--dry-run）：沒有實際安裝任何套件。"
    elif [ "$total" -eq 0 ]; then
        message="沒有執行任何模組。"
    elif [ "$partial" -eq 0 ] && [ "$failed" -eq 0 ] && [ "$not_run" -eq 0 ]; then
        message="全部 $total 個模組安裝完成。"
    else
        message="成功 $ok 個、部分失敗 $partial 個、失敗 $failed 個"
        if [ "$not_run" -gt 0 ]; then
            message+="、未執行 $not_run 個"
        fi
        message+="。"
    fi
    if [ "${INSTALL_ABORTED:-false}" = "true" ]; then
        message="${message%。}（已中止）。"
    fi
    printf '%s' "$message"
}

# 結果選單提示文字：只有一行總結與日誌路徑（完整報告放不進選單、先以訊息框顯示時使用）
install_result_menu_text() {
    local shown_log="${LOG_FILE:-未設定}"
    case "$shown_log" in "$HOME"/*) shown_log="~${shown_log#"$HOME"}" ;; esac
    printf '%s\n\n日誌：%s' "$(install_result_summary_line)" "$shown_log"
}

# 精簡報告（合併畫面用）：一行總結、逐模組狀態行、日誌路徑；不含備份路徑與建議文字
build_install_report_compact_text() {
    local nl=$'\n'
    local text
    text="$(install_result_summary_line)${nl}" || true
    local total=${#INSTALL_RESULT_IDS[@]} i name detail
    if [ "$total" -gt 0 ]; then
        text+="${nl}"
        for ((i = 0; i < total; i++)); do
            name="$(module_display_name "${INSTALL_RESULT_IDS[$i]}")"
            detail="${INSTALL_RESULT_DETAIL[$i]:-}"
            case "${INSTALL_RESULT_STATUS[$i]}" in
                ok) text+="  ✓ $name${nl}" ;;
                partial) text+="  ⚠ $name — $(count_words "$detail") 個套件失敗${nl}" ;;
                failed) text+="  ✗ $name — 安裝失敗${nl}" ;;
                *) text+="  - $name — 未執行${nl}" ;;
            esac
        done
    fi
    local shown_log="${LOG_FILE:-未設定}"
    case "$shown_log" in "$HOME"/*) shown_log="~${shown_log#"$HOME"}" ;; esac
    text+="${nl}日誌：${shown_log}"
    printf '%s' "$text"
}

# 需要重試的模組（失敗、部分失敗、未執行），依結果記錄順序，以空白分隔
install_retry_modules() {
    local i out=""
    for ((i = 0; i < ${#INSTALL_RESULT_IDS[@]}; i++)); do
        case "${INSTALL_RESULT_STATUS[$i]}" in
            failed|partial|not_run) out+="${out:+ }${INSTALL_RESULT_IDS[$i]}" ;;
        esac
    done
    printf '%s' "$out"
}

# 精簡報告加上 n 個選項，在目前終端機高度下能否放進同一個選單
install_result_fits_one_screen() {
    local n_options="${1:-4}"
    if ! declare -F _tui_menu_fits_text >/dev/null 2>&1; then
        return 1
    fi
    _tui_menu_fits_text "$(build_install_report_compact_text)" "$n_options" 24
}

# 結果畫面：精簡報告與選項合併在同一個選單；放不下時先用可捲動的訊息框顯示完整報告，
# 再顯示只有一行總結的選單。
# 回傳：0 退出、2 重新選擇、3 重試失敗的模組
show_install_result_tui() {
    local title
    title="$(install_report_title)"

    local retry_label="重試失敗的模組"
    local -a options=()
    if [ -n "$(install_retry_modules)" ]; then
        options+=("$retry_label")
    fi
    options+=("查看安裝日誌" "重新選擇" "退出")

    local message
    if install_result_fits_one_screen "${#options[@]}"; then
        message="$(build_install_report_compact_text)"
    else
        tui_msgbox "$title" "$(build_install_report_text)" || true
        message="$(install_result_menu_text)"
    fi

    local action
    while :; do
        action=$(tui_menu "$title" "$message" "${options[@]}" || true)
        case "$action" in
            "$retry_label")
                return 3
                ;;
            "查看安裝日誌")
                show_install_log_dialog
                ;;
            "重新選擇")
                return 2
                ;;
            "退出"|"")
                return 0
                ;;
        esac
    done
}

# 導覽式流程：模組勾選（含進階列）→ Homebrew → 確認摘要 → 安裝 → 結果（可重試／重新選擇）
run_guided_tui_flow() {
    # 結果由 show_install_result_tui 統一顯示，安裝函式不再自己彈出報告訊息框
    GUIDED_RESULT_SCREEN=true
    GUIDED_ADVANCED_DEFAULT="${ADVANCED_MODE:-false}"
    local retry=false

    while :; do
        if [ "$retry" = "true" ]; then
            retry=false
            # 重試只針對上次沒成功的模組；進階模式的套件選擇已保留，不再逐模組詢問
            selected_modules="$(install_retry_modules)"
            ADVANCED_MODE=false
            if [ "${LINUX_SETTING_PKG_INDEX_UPDATED:-}" != "1" ]; then
                unset LINUX_SETTING_PKG_INDEX_CHECKED
            fi
            log_info "重試未成功的模組：$selected_modules"
        else
            if declare -F reset_module_overrides >/dev/null 2>&1; then
                reset_module_overrides
            fi
            selected_modules=""
            HOMEBREW_DECISION=""

            select_modules_tui || return 0
            offer_homebrew_if_needed
            # 確認畫面選「否」回到模組勾選（要離開請在勾選畫面取消）
            confirm_install_summary_tui || continue
        fi

        local install_rc=0
        if run_install_with_tui; then
            install_rc=0
        else
            install_rc=$?
        fi
        log_info "安裝流程結束（rc=$install_rc）"
        [ "${#INSTALL_RESULT_IDS[@]}" -gt 0 ] || continue

        local result_action=0
        show_install_result_tui || result_action=$?
        if [ "$result_action" -eq 2 ]; then
            continue
        fi
        if [ "$result_action" -eq 3 ]; then
            retry=true
            continue
        fi
        # 對話框關閉後，把報告留在終端機上方便事後查閱
        if [ "${#INSTALL_RESULT_IDS[@]}" -gt 0 ]; then
            if [ -t 1 ]; then
                printf '\033[H\033[2J'
            fi
            print_installation_report_plain
        fi
        # 使用者已看過報告；不再讓 set -e 觸發錯誤畫面，改以結束碼反映結果
        GUIDED_EXIT_CODE="$(install_results_exit_code)"
        return 0
    done
}

# ==============================================================================
# Homebrew（選完模組後才詢問；APT 優先，brew 僅作備援）
# ==============================================================================

HOMEBREW_DECISION="${HOMEBREW_DECISION:-}"

# 所選模組是否宣告了 brew_packages
selected_modules_need_homebrew() {
    local modules="${1:-$selected_modules}"
    [[ "$(declare -p MODULE_BREW_PACKAGES 2>/dev/null)" == "declare -A"* ]] || return 1
    local module_id
    for module_id in $modules; do
        if [ -n "${MODULE_BREW_PACKAGES[$module_id]:-}" ]; then
            return 0
        fi
    done
    return 1
}

# 是否該詢問 Homebrew（不含互動本身，方便測試）
# shellcheck disable=SC2120 # 參數為可選，供測試指定模組清單
homebrew_offer_needed() {
    [ "${NON_INTERACTIVE:-false}" != "true" ] || return 1
    [ "${INSTALL_MODE:-full}" != "minimal" ] || return 1
    [ "${DRY_RUN:-false}" != "true" ] || return 1
    [ -z "${HOMEBREW_DECISION:-}" ] || return 1
    # brew 不建議以 root 執行，install_module 也會略過 brew
    [ "${EUID:-$(id -u)}" -ne 0 ] || return 1
    ! command -v brew >/dev/null 2>&1 || return 1
    selected_modules_need_homebrew "${1:-$selected_modules}"
}

offer_homebrew_if_needed() {
    if ! homebrew_offer_needed || [ ! -t 0 ]; then
        return 0
    fi

    local prompt="所選模組有些工具在 APT 裝不到時，\n會改用 Homebrew 安裝（備援）。\n\n要先安裝 Homebrew 嗎？（約數分鐘）"
    if [ "${USE_TUI:-false}" = "true" ] && command -v tui_yesno >/dev/null 2>&1; then
        if tui_yesno "Homebrew" "$prompt" "no"; then
            HOMEBREW_DECISION="yes"
        else
            HOMEBREW_DECISION="no"
        fi
    else
        local answer=""
        printf '%b [y/N]: ' "$prompt"
        read -r answer || true
        case "$answer" in
            y|Y|yes|YES) HOMEBREW_DECISION="yes" ;;
            *) HOMEBREW_DECISION="no" ;;
        esac
    fi
    log_info "Homebrew 詢問結果：$HOMEBREW_DECISION"
    return 0
}

# 依先前決定安裝 Homebrew；失敗不中斷（APT 仍是主要來源）
install_homebrew_if_requested() {
    [ "${HOMEBREW_DECISION:-}" = "yes" ] || return 0
    if command -v brew >/dev/null 2>&1; then
        return 0
    fi
    if ! command -v ensure_homebrew_installed >/dev/null 2>&1; then
        log_warning "找不到 Homebrew 安裝函數，跳過"
        return 0
    fi

    local rc=0
    if [ "${PROGRESS_ACTIVE:-false}" = "true" ]; then
        local started=$SECONDS
        progress_run "" "安裝 Homebrew" run_logged_command ensure_homebrew_installed || rc=$?
        if [ "$rc" -eq 0 ]; then
            progress_finish_line "" "安裝 Homebrew" ok "" $((SECONDS - started))
        else
            progress_finish_line "" "安裝 Homebrew" failed "改用 APT 繼續" $((SECONDS - started))
        fi
    else
        run_logged_command ensure_homebrew_installed || rc=$?
    fi
    if [ "$rc" -ne 0 ]; then
        log_warning "Homebrew 安裝失敗，將只使用 APT 等其他方式安裝工具"
    fi
    return 0
}

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
    prepare_initial_tui_backend
    setup_logging
    check_environment
    backup_config_files
    
    if [ "$REMOTE_INSTALL" = true ]; then
        run_remote_script_downloads
    fi

    # 遠端流程下載完成後補載入 module_manager（啟用進階模式、模組詳情、動態 checklist）
    if [ -f "$SCRIPT_DIR/core/module_manager.sh" ] \
       && [ "${BASH_VERSINFO[0]:-0}" -ge 4 ] \
       && [ "${USE_MODULE_MANAGER:-false}" != "true" ]; then
        # shellcheck source=/dev/null
        if source "$SCRIPT_DIR/core/module_manager.sh"; then
            if init_module_manager; then
                USE_MODULE_MANAGER=true
                log_success "模組管理器已啟用（${#MODULE_LIST[@]} 個模組）"
            else
                log_warning "模組管理器初始化失敗，進階模式與詳情將使用備援顯示"
            fi
        else
            log_warning "無法載入 module_manager.sh，進階模式與詳情將使用備援顯示"
        fi
    fi

    # 無人值守模式：自動選擇模組並直接執行，不進入互動選單
    if [ "$NON_INTERACTIVE" = "true" ]; then
        USE_TUI=false
        if [ "$INSTALL_MODE" = "minimal" ]; then
            selected_modules="$MINIMAL_MODULES"
        elif [ "$USE_MODULE_MANAGER" = "true" ] && [ ${#MODULE_LIST[@]} -gt 0 ]; then
            selected_modules="${MODULE_LIST[*]}"
        else
            selected_modules="$MODULES"
        fi

        local ni_rc=0
        install_selected_modules || ni_rc=$?
        if [ "$ni_rc" -eq 0 ]; then
            ni_rc="$(install_results_exit_code)"
        fi
        cleanup
        if [ "$ni_rc" -ne 0 ]; then
            # 報告已說明失敗原因，直接以非 0 結束，不再顯示錯誤畫面
            exit "$ni_rc"
        fi
        return 0
    fi

    if [ "$USE_TUI" = "true" ] && command -v tui_checklist >/dev/null 2>&1; then
        GUIDED_EXIT_CODE=0
        run_guided_tui_flow
        cleanup
        exit "${GUIDED_EXIT_CODE:-0}"
    fi

    # 命令行模式：使用原有的菜單邏輯
    while :; do
        show_menu
        read -r input
        case $input in
            [0-9]*)
                for num in $input; do
                    add_module "$num"
                done
                ;;
            i|I)
                install_selected_modules || log_warning "安裝已中止，可重新選擇模組後再試"
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
            a|A)
                # 切換進階模式
                if [ "${ADVANCED_MODE:-false}" = "true" ]; then
                    ADVANCED_MODE=false
                    printf "${CYAN}進階模式已關閉${NC}\n"
                else
                    ADVANCED_MODE=true
                    printf "${YELLOW}進階模式已開啟${NC}（按 [i] 開始安裝時，會逐模組讓你挑套件）\n"
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
    done
}

# 顯示菜單函數（動態生成，包含安裝狀態標記）
show_menu() {
    # 不畫右框線：中文是雙寬字元，printf 的欄寬以位元組計算，右框線必然對不齊
    local rule="────────────────────────────────────────────────────────────────"
    printf "\n${CYAN}%s${NC}\n" "$rule"
    printf "  ${CYAN}選擇安裝模組${NC}\n"
    printf "${CYAN}%s${NC}\n\n" "$rule"

    # 動態生成模組選項
    if [ "$USE_MODULE_MANAGER" = "true" ] && [ ${#MODULE_LIST[@]} -gt 0 ]; then
        local index=1
        local module_id
        for module_id in "${MODULE_LIST[@]}"; do
            local name="${MODULE_NAMES[$module_id]:-$module_id}"
            local desc="${MODULE_DESCRIPTIONS[$module_id]:-}"
            local status=""
            local mark="[ ]"

            # 獲取安裝狀態標記
            if command -v check_module_status >/dev/null 2>&1; then
                status=$(check_module_status "$module_id" 2>/dev/null || true)
            fi
            case "$status" in
                installed) mark="[${GREEN}✓${NC}]" ;;
                partial)   mark="[${YELLOW}◐${NC}]" ;;
            esac

            printf "  ${GREEN}[%d]${NC} %b %s" "$index" "$mark" "$name"
            if [ -n "$desc" ]; then
                printf " — %s" "$desc"
            fi
            printf "\n"
            index=$((index + 1))
        done
        printf "  ${GREEN}[%d]${NC}     全部安裝\n" "$index"
    else
        # 備用靜態選單
        printf "  ${GREEN}[1]${NC} Python 開發環境 — python3, pip, uv, ranger\n"
        printf "  ${GREEN}[2]${NC} Docker 工具 — docker-ce, lazydocker\n"
        printf "  ${GREEN}[3]${NC} 基礎工具 — git, lsd, bat, ripgrep, fzf\n"
        printf "  ${GREEN}[4]${NC} 終端設定 — zsh, oh-my-zsh, powerlevel10k\n"
        printf "  ${GREEN}[5]${NC} 開發工具 — neovim, lazygit, nodejs, rust\n"
        printf "  ${GREEN}[6]${NC} 監控工具 — btop, htop, iftop, fail2ban\n"
        printf "  ${GREEN}[7]${NC} 全部安裝\n"
    fi

    # 顯示狀態圖例
    printf "\n  [${GREEN}✓${NC}] 已安裝  [${YELLOW}◐${NC}] 部分安裝  [ ] 未安裝\n"
    printf "${CYAN}%s${NC}\n" "$rule"

    # 顯示當前選擇
    if [ -n "$selected_modules" ]; then
        printf "  ${YELLOW}已選擇：${NC}%s\n" "${selected_modules# }"
    else
        printf "  ${YELLOW}已選擇：${NC}（尚未選擇）\n"
    fi

    # 進階模式狀態
    if [ "${ADVANCED_MODE:-false}" = "true" ]; then
        printf "  ${YELLOW}進階模式：開${NC}（按 [a] 關閉；安裝時會逐模組選套件）\n"
    else
        printf "  進階模式：關（按 [a] 開啟；可逐模組挑套件）\n"
    fi
    printf "  ${BLUE}[i]${NC} 開始安裝  ${BLUE}[c]${NC} 清除  ${BLUE}[d]${NC} 詳細  ${BLUE}[a]${NC} 進階  ${BLUE}[q]${NC} 退出\n"
    printf "${CYAN}%s${NC}\n" "$rule"
    printf "\n輸入選項（例如：1 3 4）："
}

# 無 module_manager 設定檔時的單一模組說明（與靜態 checklist 一致）
_show_static_module_detail_msg() {
    local mid="$1"
    local title="模組詳情"
    local body=""
    case "$mid" in
        python)
            title="模組詳情: Python 開發環境"
            body="內容概覽：python3、pip、venv、uv、ranger、s-t-ui 等。\n\n若看不到套件級狀態，請確認已下載 config/modules.conf 並成功載入模組管理器。"
            ;;
        docker)
            title="模組詳情: Docker 工具"
            body="內容概覽：Docker CE、lazydocker（安裝流程由 docker_setup.sh 處理）。"
            ;;
        base)
            title="模組詳情: 基礎工具"
            body="內容概覽：git、curl、wget、建置工具、lsd/bat/ripgrep/fzf 等 CLI（依系統與 Homebrew 可用性）。"
            ;;
        terminal)
            title="模組詳情: 終端設定"
            body="內容概覽：zsh、Oh My Zsh、Powerlevel10k 與常用插件。"
            ;;
        dev)
            title="模組詳情: 開發工具"
            body="內容概覽：Neovim/LazyVim、lazygit、Node.js、Rust 工具鏈等。"
            ;;
        monitoring)
            title="模組詳情: 監控工具"
            body="內容概覽：btop、htop、iftop、nethogs、fail2ban 等。"
            ;;
        *)
            title="模組詳情"
            body="未知模組 ID：$mid"
            ;;
    esac
    if [ "$USE_TUI" = "true" ] && command -v tui_msgbox >/dev/null 2>&1; then
        tui_msgbox "$title" "$(printf '%b' "$body")"
    else
        printf '%b\n\n' "$body"
        printf "按 Enter 返回..."
        read -r
    fi
}

# 顯示單個模組詳細資訊（TUI 對話框）
show_module_detail_dialog() {
    local module_id="$1"

    if [ "$USE_MODULE_MANAGER" != "true" ] || ! module_exists "$module_id" 2>/dev/null; then
        log_warning "模組不存在: $module_id"
        _show_static_module_detail_msg "$module_id"
        return 1
    fi

    local detail
    detail=$(get_module_detail_status "$module_id" 2>/dev/null || true)

    if [ -z "$detail" ]; then
        detail="（無法產生詳細狀態，可能缺少設定或檢查函數失敗）\n模組 ID：$module_id"
    fi

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
        # 並行維護「顯示標籤」與「模組 ID」，避免只靠字串剥離狀態圖示導致對應失敗
        local menu_labels=()
        local menu_ids=()

        if [ "$USE_MODULE_MANAGER" = "true" ] && [ ${#MODULE_LIST[@]} -gt 0 ]; then
            for module_id in "${MODULE_LIST[@]}"; do
                local name="${MODULE_NAMES[$module_id]:-$module_id}"
                local status_icon=""
                if command -v check_module_status >/dev/null 2>&1; then
                    local status
                    status=$(check_module_status "$module_id" 2>/dev/null || true)
                    case "$status" in
                        installed)     status_icon="[✓] " ;;
                        partial)       status_icon="[◐] " ;;
                        not_installed) status_icon="[ ] " ;;
                    esac
                fi
                menu_labels+=("${status_icon}${name}")
                menu_ids+=("$module_id")
            done
        else
            local _static_ids=(python docker base terminal dev monitoring)
            local _static_labels=(
                "Python 開發環境"
                "Docker 工具"
                "基礎工具"
                "終端設定"
                "開發工具"
                "監控工具"
            )
            local _si=0
            for module_id in "${_static_ids[@]}"; do
                local name="${_static_labels[$_si]}"
                _si=$((_si + 1))
                local status_icon=""
                if command -v check_module_status >/dev/null 2>&1; then
                    local status
                    status=$(check_module_status "$module_id" 2>/dev/null || true)
                    case "$status" in
                        installed)     status_icon="[✓] " ;;
                        partial)       status_icon="[◐] " ;;
                        not_installed) status_icon="[ ] " ;;
                    esac
                fi
                menu_labels+=("${status_icon}${name}")
                menu_ids+=("$module_id")
            done
        fi

        menu_labels+=("返回主選單")
        menu_ids+=("RETURN")

        local selection
        selection=$(tui_menu "查看模組詳情" "選擇要查看的模組：" "${menu_labels[@]}") || return 0

        if [ -z "$selection" ] || [ "$selection" = "返回主選單" ]; then
            return 0
        fi

        local _i=0
        local picked_id=""
        for lbl in "${menu_labels[@]}"; do
            if [ "$lbl" = "$selection" ]; then
                picked_id="${menu_ids[_i]}"
                break
            fi
            _i=$((_i + 1))
        done

        if [ -z "$picked_id" ] || [ "$picked_id" = "RETURN" ]; then
            return 0
        fi

        if [ "$USE_MODULE_MANAGER" = "true" ] && command -v module_exists >/dev/null 2>&1 \
            && module_exists "$picked_id" 2>/dev/null; then
            show_module_detail_dialog "$picked_id" || true
        else
            _show_static_module_detail_msg "$picked_id"
        fi
        return 0
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
            if command -v _module_pkg_status_cache_clear >/dev/null 2>&1; then
                _module_pkg_status_cache_clear
            fi

            local name="${MODULE_NAMES[$module_id]:-$module_id}"
            local system_packages="${MODULE_PACKAGES[$module_id]:-}"
            local brew_packages="${MODULE_BREW_PACKAGES[$module_id]:-}"
            local pip_packages="${MODULE_PIP_PACKAGES[$module_id]:-}"
            local cargo_packages="${MODULE_CARGO_PACKAGES[$module_id]:-}"
            local npm_packages="${MODULE_NPM_PACKAGES[$module_id]:-}"

            # 獲取安裝狀態
            local status_icon=" "
            local status_text="未安裝"
            if command -v check_module_status >/dev/null 2>&1; then
                local status
                status=$(check_module_status "$module_id" true 2>/dev/null)
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
            if [ -n "$system_packages" ]; then
                printf "    ${BLUE}系統套件:${NC} "
                local first=true
                for pkg in $system_packages; do
                    [ "$first" = true ] || printf ", " || true
                    first=false
                    if _module_pkg_is_installed apt "$pkg"; then
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
                    if command -v brew >/dev/null 2>&1 && _module_pkg_is_installed brew "$pkg"; then
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
                    if _module_pkg_is_installed pip "$pkg"; then
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
                    if command -v cargo >/dev/null 2>&1 && _module_pkg_is_installed cargo "$pkg"; then
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
                    if command -v npm >/dev/null 2>&1 && _module_pkg_is_installed npm "$pkg"; then
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
        log_info "開始安裝 $module_name"
        if run_logged_command bash "$SCRIPT_DIR/$script"; then
            installed_modules="$installed_modules $module_name"
            log_success "$module_name 安裝完成"
        else
            log_error "$module_name 安裝失敗" || true
            return 1
        fi
    else
        log_error "找不到腳本 $SCRIPT_DIR/$script" || true
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
            if [[ " $selected_modules " != *" $module_id "* ]]; then
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


# ==============================================================================
# 安裝結果追蹤（兩條安裝路徑共用）
# 狀態：ok（成功）/ partial（部分套件失敗）/ failed（失敗）/ not_run（中止後未執行）
# ==============================================================================

INSTALL_RESULT_IDS=()
INSTALL_RESULT_STATUS=()
INSTALL_RESULT_DETAIL=()
INSTALL_ABORTED=false

reset_install_results() {
    INSTALL_RESULT_IDS=()
    INSTALL_RESULT_STATUS=()
    INSTALL_RESULT_DETAIL=()
    INSTALL_ABORTED=false
}

record_module_result() {
    INSTALL_RESULT_IDS+=("$1")
    INSTALL_RESULT_STATUS+=("$2")
    INSTALL_RESULT_DETAIL+=("${3:-}")
}

# 查詢某模組的結果狀態（找不到時輸出空字串）
module_result_status() {
    local module_id="$1"
    local i
    for ((i = 0; i < ${#INSTALL_RESULT_IDS[@]}; i++)); do
        if [ "${INSTALL_RESULT_IDS[$i]}" = "$module_id" ]; then
            printf '%s' "${INSTALL_RESULT_STATUS[$i]}"
            return 0
        fi
    done
    return 0
}

# 模組是否實際裝好（成功或僅部分套件失敗）
module_result_succeeded() {
    case "$(module_result_status "$1")" in
        ok|partial) return 0 ;;
    esac
    return 1
}

# 依安裝結果決定程序結束碼（輸出 0 或 1）：
# 已中止、或有任何模組失敗／未執行 → 1；全部成功或只有部分套件失敗 → 0。
# 導覽式 TUI、非互動（--non-interactive）與 stdin 非 tty 三條路徑共用，結束碼才會一致。
install_results_exit_code() {
    if [ "${INSTALL_ABORTED:-false}" = "true" ]; then
        printf '%s' 1
        return 0
    fi
    local status
    for status in ${INSTALL_RESULT_STATUS[@]+"${INSTALL_RESULT_STATUS[@]}"}; do
        case "$status" in
            failed|not_run)
                printf '%s' 1
                return 0
                ;;
        esac
    done
    printf '%s' 0
}

# 整體結果：success / partial / failed / none
install_results_overall() {
    local i ok=0 partial=0 failed=0 not_run=0
    for ((i = 0; i < ${#INSTALL_RESULT_STATUS[@]}; i++)); do
        case "${INSTALL_RESULT_STATUS[$i]}" in
            ok) ok=$((ok + 1)) ;;
            partial) partial=$((partial + 1)) ;;
            failed) failed=$((failed + 1)) ;;
            *) not_run=$((not_run + 1)) ;;
        esac
    done

    if [ $((ok + partial + failed + not_run)) -eq 0 ]; then
        printf '%s' "none"
    elif [ "$partial" -eq 0 ] && [ "$failed" -eq 0 ] && [ "$not_run" -eq 0 ]; then
        printf '%s' "success"
    elif [ "$ok" -eq 0 ] && [ "$partial" -eq 0 ]; then
        printf '%s' "failed"
    else
        printf '%s' "partial"
    fi
}

install_report_title() {
    local overall
    overall="$(install_results_overall)"
    if [ "${INSTALL_ABORTED:-false}" = "true" ] && [ "$overall" != "failed" ]; then
        printf '%s' "安裝已中止"
        return 0
    fi
    case "$overall" in
        success) printf '%s' "安裝完成" ;;
        partial) printf '%s' "安裝完成（部分失敗）" ;;
        failed) printf '%s' "安裝失敗" ;;
        *) printf '%s' "未安裝任何模組" ;;
    esac
}

# 由 MODULE_INSTALL_FAILURES 的一筆「名稱: apt:x brew:y」取出套件清單
module_failure_packages() {
    local entry="$1"
    if [[ "$entry" == *": "* ]]; then
        printf '%s' "${entry#*: }"
    else
        printf '%s' "$entry"
    fi
}

# 計算以空白分隔的項目數
count_words() {
    local -a _words=()
    read -r -a _words <<< "${1:-}" || true
    printf '%s' "${#_words[@]}"
}

# 產生安裝報告文字（純函式：只讀結果陣列與 $HOME 下的檔案，輸出含實際換行的純文字）
build_install_report_text() {
    local i ok=0 partial=0 failed=0 not_run=0
    local total=${#INSTALL_RESULT_IDS[@]}
    for ((i = 0; i < total; i++)); do
        case "${INSTALL_RESULT_STATUS[$i]}" in
            ok) ok=$((ok + 1)) ;;
            partial) partial=$((partial + 1)) ;;
            failed) failed=$((failed + 1)) ;;
            *) not_run=$((not_run + 1)) ;;
        esac
    done

    local overall
    overall="$(install_results_overall)"
    local nl=$'\n'
    local report=""

    case "$overall" in
        success) report+="全部 $total 個模組安裝成功。${nl}" ;;
        none) report+="這次沒有執行任何模組。${nl}" ;;
        *)
            report+="成功 $ok 個、部分失敗 $partial 個、失敗 $failed 個"
            if [ "$not_run" -gt 0 ]; then
                report+="、未執行 $not_run 個"
            fi
            report+="。${nl}"
            ;;
    esac

    if [ "$total" -gt 0 ]; then
        report+="${nl}模組：${nl}"
        for ((i = 0; i < total; i++)); do
            local name detail
            name="$(module_display_name "${INSTALL_RESULT_IDS[$i]}")"
            detail="${INSTALL_RESULT_DETAIL[$i]}"
            case "${INSTALL_RESULT_STATUS[$i]}" in
                ok)
                    report+="  ✓ $name${nl}"
                    ;;
                partial)
                    report+="  ⚠ $name — $(count_words "$detail") 個套件失敗：$detail${nl}"
                    ;;
                failed)
                    report+="  ✗ $name — 安裝失敗${detail:+（$detail）}${nl}"
                    ;;
                *)
                    report+="  - $name — 未執行（安裝已中止）${nl}"
                    ;;
            esac
        done
    fi

    # 設定檔與別名：只列出對應模組確實裝好、且檔案確實存在的項目
    local hints=""
    if module_result_succeeded terminal; then
        if [ -f "$HOME/.zshrc" ]; then
            hints+="  zsh 設定：~/.zshrc${nl}"
        fi
        if [ -f "$HOME/.p10k.zsh" ]; then
            hints+="  p10k 設定：~/.p10k.zsh${nl}"
        fi
    fi
    if module_result_succeeded dev; then
        if [ -d "$HOME/.config/nvim" ]; then
            hints+="  Neovim 設定：~/.config/nvim${nl}"
        fi
        if grep -qs "alias nv=" "$HOME/.zshrc"; then
            hints+="  別名：nv → nvim${nl}"
        fi
    fi
    if module_result_succeeded docker && grep -qs "alias lzd=" "$HOME/.zshrc"; then
        hints+="  別名：lzd → lazydocker${nl}"
    fi
    if [ -n "$hints" ]; then
        report+="${nl}設定檔與別名：${nl}${hints}"
    fi

    report+="${nl}"
    if [ -n "${BACKUP_DIR:-}" ]; then
        local shown_backup="$BACKUP_DIR"
        case "$shown_backup" in "$HOME"/*) shown_backup="~${shown_backup#"$HOME"}" ;; esac
        report+="備份：${shown_backup}${nl}"
    fi
    local shown_log="${LOG_FILE:-未設定}"
    case "$shown_log" in "$HOME"/*) shown_log="~${shown_log#"$HOME"}" ;; esac
    report+="日誌：${shown_log}${nl}"

    if [ "$failed" -gt 0 ] || [ "$partial" -gt 0 ]; then
        report+="${nl}建議：查看日誌找出失敗原因，修正後重新執行；已安裝的套件會自動略過。${nl}"
        if [ -n "${BACKUP_DIR:-}" ] && [ -n "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
            report+="如需還原安裝前的設定檔，可執行 ./install.sh --rollback。${nl}"
        fi
    fi

    if module_result_succeeded terminal; then
        report+="${nl}下一步：執行 exec zsh -l 載入新的 shell 設定。${nl}"
    elif [ $((ok + partial)) -gt 0 ]; then
        report+="${nl}下一步：重新開啟終端機以套用環境變更。${nl}"
    fi

    printf '%s' "$report"
}

# 顯示安裝報告
show_installation_report() {
    # 導覽式流程由 show_install_result_tui 統一顯示結果
    if [ "${GUIDED_RESULT_SCREEN:-false}" = "true" ]; then
        return 0
    fi

    local title report
    title="$(install_report_title)"
    report="$(build_install_report_text)"

    if [ "${USE_TUI:-false}" = "true" ] && command -v tui_msgbox >/dev/null 2>&1; then
        tui_msgbox "$title" "$report" || true
    else
        print_installation_report_plain
    fi
}

# 純文字報告（CLI、無人值守，以及 TUI 結束後留在終端機上的紀錄）
print_installation_report_plain() {
    local title color
    color="$(_ansi "${GREEN:-}")"
    title="$(install_report_title)"
    case "$(install_results_overall)" in
        partial) color="$(_ansi "${YELLOW:-}")" ;;
        failed|none) color="$(_ansi "${RED:-}")" ;;
    esac
    if [ "${INSTALL_ABORTED:-false}" = "true" ]; then
        color="$(_ansi "${YELLOW:-}")"
    fi
    printf "\n%s========== %s ==========%s\n" "$color" "$title" "$(_ansi "${NC:-}")"
    printf '%s\n' "$(build_install_report_text)"
}

# ==============================================================================
# 安裝進度顯示（TUI quiet 模式）
# - 每個模組一行：轉圈動畫 + 已耗時 + 日誌最新訊息；完成後改寫為定案狀態
# - 動畫只寫終端（不寫日誌），非 tty 或 sudo 可能要密碼時改用靜態行
# ==============================================================================

PROGRESS_ACTIVE=false
PROGRESS_TTY_OPEN=false
PROGRESS_SPINNER_PID=""
PROGRESS_HEADER_TOTAL=0
PROGRESS_LINES=()

_progress_fmt_elapsed() {
    local secs="${1:-0}"
    [[ "$secs" =~ ^[0-9]+$ ]] || secs=0
    printf '%02d:%02d' $((secs / 60)) $((secs % 60))
}

# 清理一行日誌：去掉 ANSI 色碼、\r 覆寫、時間戳前綴與控制字元，結果放在 PROGRESS_CLEANED
_progress_clean_log_line() {
    local s="${1:-}"
    s="${s//$'\t'/ }"

    # apt/curl 進度列以 \r 覆寫：取最後一段非空內容
    if [[ "$s" == *$'\r'* ]]; then
        local last="${s##*$'\r'}"
        if [ -z "${last// /}" ]; then
            s="${s%$'\r'*}"
            last="${s##*$'\r'}"
        fi
        s="$last"
    fi

    local ansi_re=$'\e''\[[0-9;?]*[A-Za-z]'
    while [[ "$s" =~ $ansi_re ]]; do
        s="${s/"${BASH_REMATCH[0]}"/}"
    done
    s="${s//$'\e'/}"

    local ts_re='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+([+-][0-9:]+|Z)? \[[A-Z]+\] \[[0-9]+\] '
    if [[ "$s" =~ $ts_re ]]; then
        s="${s:${#BASH_REMATCH[0]}}"
    fi
    case "$s" in
        "INFO: "*) s="${s#INFO: }" ;;
        "SUCCESS: "*) s="${s#SUCCESS: }" ;;
        "WARNING: "*) s="${s#WARNING: }" ;;
        "ERROR: "*) s="${s#ERROR: }" ;;
        "DEBUG: "*) s="${s#DEBUG: }" ;;
    esac

    s="${s//[[:cntrl:]]/}"
    # 去頭尾空白
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    PROGRESS_CLEANED="$s"
}

# 測試／除錯用：輸出清理後的日誌行
progress_clean_log_line() {
    _progress_clean_log_line "${1:-}"
    printf '%s' "$PROGRESS_CLEANED"
}

# 依顯示寬度截斷文字（保守估計：非 ASCII 一律視為雙寬），結果放在 PROGRESS_FIT / PROGRESS_FIT_WIDTH
_progress_fit_text() {
    local text="${1:-}"
    local max="${2:-0}"
    [[ "$max" =~ ^[0-9]+$ ]] || max=0
    # 避免超長行拖慢逐字計算
    text="${text:0:400}"

    local len=${#text}
    local i ch code cw
    local width=0 cut="" cut_width=0 overflow=false
    local budget=$((max - 2))  # 截斷時預留「…」的寬度（保守算 2）
    for ((i = 0; i < len; i++)); do
        ch="${text:i:1}"
        code=200
        printf -v code '%d' "'$ch" 2>/dev/null || code=200
        # 非 UTF-8 locale 下多位元組字元會逐 byte 處理，且可能得到負值：一律視為寬字元
        if [ "$code" -ge 0 ] 2>/dev/null && [ "$code" -lt 32 ] 2>/dev/null; then
            continue
        fi
        if [ "$code" -ge 32 ] 2>/dev/null && [ "$code" -lt 127 ] 2>/dev/null; then
            cw=1
        else
            cw=2
        fi
        if [ $((width + cw)) -le "$budget" ]; then
            cut+="$ch"
            cut_width=$((width + cw))
        fi
        width=$((width + cw))
        if [ "$width" -gt "$max" ]; then
            overflow=true
            break
        fi
    done

    if [ "$overflow" = "true" ]; then
        if [ "$budget" -gt 0 ]; then
            PROGRESS_FIT="${cut}…"
            PROGRESS_FIT_WIDTH=$((cut_width + 2))
        else
            PROGRESS_FIT=""
            PROGRESS_FIT_WIDTH=0
        fi
    else
        PROGRESS_FIT="${text//[[:cntrl:]]/}"
        PROGRESS_FIT_WIDTH="$width"
    fi
}

# 測試／除錯用：輸出截斷結果
progress_fit_text() {
    _progress_fit_text "${1:-}" "${2:-0}"
    printf '%s' "$PROGRESS_FIT"
}

# 估算顯示寬度（與 _progress_fit_text 同一套保守規則）
progress_text_width() {
    _progress_fit_text "${1:-}" 100000
    printf '%s' "$PROGRESS_FIT_WIDTH"
}

_progress_term_cols() {
    local size="" cols=""
    size="$(stty size < /dev/tty 2>/dev/null)" || size=""
    cols="${size##* }"
    if ! [[ "$cols" =~ ^[0-9]+$ ]] || [ "$cols" -lt 20 ]; then
        cols="$(tput cols 2>/dev/null)" || cols=""
    fi
    if ! [[ "$cols" =~ ^[0-9]+$ ]] || [ "$cols" -lt 20 ]; then
        cols=80
    fi
    printf '%s' "$cols"
}

# 日誌最新一則有內容的訊息（已清理）
# shellcheck disable=SC2120 # 參數為可選，預設讀 LOG_FILE；測試會傳入檔案
progress_last_log_message() {
    local file="${1:-${LOG_FILE:-}}"
    [ -n "$file" ] && [ -f "$file" ] || return 0
    local line result=""
    while IFS= read -r line || [ -n "$line" ]; do
        _progress_clean_log_line "$line"
        if [ -n "$PROGRESS_CLEANED" ]; then
            result="$PROGRESS_CLEANED"
        fi
    done < <(tail -n 5 "$file" 2>/dev/null || true)
    printf '%s' "$result"
}

# 組出一行進度文字（不含色碼），結果放在 PROGRESS_FIT；寬度保證 <= cols-1
_progress_compose_line() {
    local frame="$1" tag="$2" label="$3" elapsed="$4" msg="$5" cols="$6"
    local max=$((cols - 1))
    local head
    head="${tag:+$tag }$label  $(_progress_fmt_elapsed "$elapsed")" || true
    # 前綴「  X 」佔 4 欄
    _progress_fit_text "$head" $((max - 4))
    local head_fit="$PROGRESS_FIT"
    local remain=$((max - 4 - PROGRESS_FIT_WIDTH))
    local line="$head_fit"
    # 分隔符「 │ 」的直線可能被當成雙寬字元，保守算 4 欄
    if [ -n "$msg" ] && [ "$remain" -gt 8 ]; then
        _progress_fit_text "$msg" $((remain - 4))
        if [ -n "$PROGRESS_FIT" ]; then
            line="$line │ $PROGRESS_FIT"
        fi
    fi
    PROGRESS_FIT="  $frame $line"
}

_progress_spinner_loop() {
    local tag="$1" label="$2" start="$3" parent_pid="$4"
    trap - ERR
    set +e
    trap 'exit 0' TERM
    trap '' INT

    local frames
    case "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" in
        *UTF-8*|*utf8*|*UTF8*|*utf-8*) frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏") ;;
        *) frames=("|" "/" "-" "\\") ;;
    esac
    local cyan nc
    cyan="$(_ansi "${CYAN:-}")"
    nc="$(_ansi "${NC:-}")"
    local tick=0 msg="" cols=80 frame line_body
    while :; do
        kill -0 "$parent_pid" 2>/dev/null || exit 0
        if [ $((tick % 5)) -eq 0 ]; then
            msg="$(progress_last_log_message)"
            cols="$(_progress_term_cols)"
        fi
        # 每分鐘延長一次 sudo 憑證，避免長時間安裝途中跳出密碼提示而被動畫行覆蓋
        if [ $((tick % 300)) -eq 299 ] && [ "${EUID:-$(id -u)}" -ne 0 ]; then
            sudo -n -v >/dev/null 2>&1 || true
        fi
        frame="${frames[$((tick % ${#frames[@]}))]}"
        _progress_compose_line "$frame" "$tag" "$label" $((SECONDS - start)) "$msg" "$cols"
        line_body="${PROGRESS_FIT:4}"
        printf '\r\033[K  %s%s%s %s' "$cyan" "$frame" "$nc" "$line_body"
        tick=$((tick + 1))
        sleep 0.2
    done
}

# 動畫只在 stdout 是 tty，且不會被 sudo 密碼提示打斷時啟用
progress_can_animate() {
    [ "${PROGRESS_TTY_OPEN:-false}" = "true" ] || return 1
    [ -t 8 ] || return 1
    [ "${PROGRESS_ANIMATION:-auto}" != "false" ] || return 1
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        return 0
    fi
    sudo -n true >/dev/null 2>&1
}

_progress_stop_spinner() {
    local pid="${PROGRESS_SPINNER_PID:-}"
    [ -n "$pid" ] || return 0
    PROGRESS_SPINNER_PID=""
    kill "$pid" 2>/dev/null || true
    # 動畫行程不是本 shell 的子行程（避免被裸 wait 卡住），以輪詢確認已結束
    local tries=0
    while _progress_pid_alive "$pid" && [ "$tries" -lt 40 ]; do
        sleep 0.05
        tries=$((tries + 1))
    done
    if _progress_pid_alive "$pid"; then
        kill -9 "$pid" 2>/dev/null || true
    fi
    if _progress_tty_is_terminal; then
        _progress_out '\r\033[K'
    fi
    return 0
}

# 行程是否仍在執行（殭屍行程視為已結束：容器內 PID 1 不一定會回收孤兒）
_progress_pid_alive() {
    local pid="$1"
    kill -0 "$pid" 2>/dev/null || return 1
    if [ -r "/proc/$pid/stat" ]; then
        local stat=""
        read -r stat < "/proc/$pid/stat" 2>/dev/null || return 0
        stat="${stat##*) }"
        [ "${stat%% *}" != "Z" ] || return 1
    fi
    return 0
}

# 進度輸出一律寫到進度開始時保存的終端機 fd 8，
# 即使目前 stdout 已被導向日誌（例如在 run_logged_command 內收到 Ctrl-C）
_progress_out() {
    local fmt="$1"
    shift
    if [ "${PROGRESS_TTY_OPEN:-false}" = "true" ]; then
        # shellcheck disable=SC2059
        printf "$fmt" "$@" >&8
    else
        # shellcheck disable=SC2059
        printf "$fmt" "$@"
    fi
}

_progress_tty_is_terminal() {
    if [ "${PROGRESS_TTY_OPEN:-false}" = "true" ]; then
        [ -t 8 ]
    else
        [ -t 1 ]
    fi
}

_progress_interrupted() {
    _progress_stop_spinner
    trap - INT TERM
    _progress_out '\n  %s已中斷安裝。%s詳細日誌：%s\n\n' "$(_ansi "${YELLOW:-}")" "$(_ansi "${NC:-}")" "${LOG_FILE:-未設定}"
    exit 130
}

_progress_draw_header() {
    if [ -t 1 ]; then
        printf '\033[H\033[2J'
    fi
    printf '\n  %s正在安裝 %s 個模組%s\n' "$(_ansi "${CYAN:-}")" "$PROGRESS_HEADER_TOTAL" "$(_ansi "${NC:-}")"
    local shown_log="${LOG_FILE:-未設定}"
    case "$shown_log" in "$HOME"/*) shown_log="~${shown_log#"$HOME"}" ;; esac
    printf '  詳細輸出寫入日誌：%s\n' "$shown_log"
    printf '  按 Ctrl-C 可中斷安裝\n\n'
}

progress_begin() {
    PROGRESS_HEADER_TOTAL="${1:-0}"
    PROGRESS_LINES=()
    PROGRESS_ACTIVE=true
    exec 8>&1
    PROGRESS_TTY_OPEN=true
    trap '_progress_interrupted' INT TERM
    _progress_draw_header
}

# 對話框（例如模組失敗詢問）關閉後重畫進度畫面
progress_redraw() {
    [ "${PROGRESS_ACTIVE:-false}" = "true" ] || return 0
    _progress_draw_header
    local i
    for ((i = 0; i < ${#PROGRESS_LINES[@]}; i++)); do
        printf '%s\n' "${PROGRESS_LINES[$i]}"
    done
}

progress_end() {
    [ "${PROGRESS_ACTIVE:-false}" = "true" ] || return 0
    _progress_stop_spinner
    trap - INT TERM
    PROGRESS_ACTIVE=false
    printf '\n'
    if [ "${PROGRESS_TTY_OPEN:-false}" = "true" ]; then
        exec 8>&-
        PROGRESS_TTY_OPEN=false
    fi
}

# 執行一個步驟並顯示進度；回傳該步驟的結束碼
progress_run() {
    local tag="$1" label="$2"
    shift 2
    local rc=0

    if progress_can_animate; then
        # 透過額外一層 subshell 讓動畫行程脫離本 shell 的子行程清單，
        # 避免安裝函式中的裸 `wait` 等待它而卡住
        PROGRESS_SPINNER_PID="$(
            _progress_spinner_loop "$tag" "$label" "$SECONDS" "$$" </dev/null >&8 2>/dev/null &
            printf '%s' "$!"
        )"
    else
        printf '  %s·%s %s%s 安裝中…（詳細輸出見日誌）\n' "$(_ansi "${CYAN:-}")" "$(_ansi "${NC:-}")" "${tag:+$tag }" "$label"
    fi

    "$@" || rc=$?
    _progress_stop_spinner
    return "$rc"
}

# 寫出某步驟的定案狀態行
progress_finish_line() {
    local tag="$1" label="$2" status="$3" text="${4:-}" elapsed="${5:-0}"
    local icon color
    case "$status" in
        ok) icon="✓"; color="$(_ansi "${GREEN:-}")"; text="${text:-完成}" ;;
        partial) icon="!"; color="$(_ansi "${YELLOW:-}")"; text="${text:-部分套件失敗}" ;;
        failed) icon="✗"; color="$(_ansi "${RED:-}")"; text="${text:-失敗}" ;;
        *) icon="-"; color=""; text="${text:-略過}" ;;
    esac
    local cols=80
    if [ -t 1 ]; then
        cols="$(_progress_term_cols)"
    fi
    _progress_fit_text "${tag:+$tag }$label  $text  $(_progress_fmt_elapsed "$elapsed")" $((cols - 5))
    local line
    line="  ${color}${icon}$(_ansi "${NC:-}") ${PROGRESS_FIT}"
    PROGRESS_LINES+=("$line")
    printf '%s\n' "$line"
}

# ==============================================================================
# 安裝流程
# ==============================================================================

run_install_with_tui() {
    local install_rc=0
    if install_selected_modules; then
        install_rc=0
    else
        install_rc=$?
    fi
    return "$install_rc"
}

# 無模組管理器時，各模組對應的安裝腳本
module_fallback_script() {
    case "$1" in
        base) printf '%s' "core/base_tools.sh" ;;
        dev) printf '%s' "core/dev_tools.sh" ;;
        python) printf '%s' "core/python_setup.sh" ;;
        terminal) printf '%s' "core/terminal_setup.sh" ;;
        monitoring) printf '%s' "core/monitoring_tools.sh" ;;
        docker) printf '%s' "core/docker_setup.sh" ;;
        *) printf '%s' "" ;;
    esac
}

# 執行單一模組（模組管理器或備援腳本）
run_module_install() {
    local module="$1"
    if [ "$USE_MODULE_MANAGER" = "true" ] && command -v install_module >/dev/null 2>&1; then
        run_logged_command install_module "$module"
    else
        local script
        script="$(module_fallback_script "$module")"
        if [ -z "$script" ]; then
            log_error "未知模組：$module" || true
            return 1
        fi
        execute_script "$script" "$module"
    fi
}

# 模組失敗策略：
# - 預設 ABORT_ON_FAILURE=false：記錄失敗，繼續下一個模組
# - --abort-on-failure：立即中止整段安裝
# - 互動模式且非 abort：詢問是否繼續
_handle_module_failure() {
    local mod="$1"
    local remaining="${2:-1}"
    local name
    name="$(module_display_name "$mod")"
    # 安全初始化（兼容 set -u）
    FAILED_MODULES=(${FAILED_MODULES[@]+"${FAILED_MODULES[@]}"} "$mod")
    if [ "${PROGRESS_ACTIVE:-false}" = "true" ]; then
        # 進度行已顯示失敗，錯誤訊息只寫入日誌
        log_error "模組 $mod 安裝失敗" 2>/dev/null || true
    else
        log_error "模組 $mod 安裝失敗" || true
    fi

    if [ "${ABORT_ON_FAILURE:-false}" = "true" ]; then
        log_warning "--abort-on-failure 已啟用，中止安裝"
        return 1
    fi

    # 已是最後一個模組：沒有「其餘模組」可問，直接進入報告
    if [ "$remaining" -le 0 ] 2>/dev/null; then
        return 0
    fi

    if [ -t 0 ] && [ "${NON_INTERACTIVE:-false}" != "true" ]; then
        if [ "${USE_TUI:-false}" = "true" ] && command -v tui_yesno >/dev/null 2>&1; then
            if ! tui_yesno "模組安裝失敗" "「$name」安裝失敗。\n\n還有 $remaining 個模組未安裝，要繼續嗎？" "yes"; then
                log_warning "使用者選擇中止"
                return 1
            fi
        else
            printf "${YELLOW:-}「%s」安裝失敗，是否繼續安裝其餘模組？${NC:-} [Y/n]: " "$name"
            local ans=""
            read -r ans || true
            case "${ans,,}" in
                n|no) log_warning "使用者選擇中止"; return 1 ;;
            esac
        fi
    fi
    log_warning "繼續安裝下一個模組（失敗模組會在最後報告）"
    return 0
}

# 所選模組安裝時是否會用到套件管理器（決定要不要先更新套件索引）。
# 保守判斷：有模組管理器資料時，只要所選模組有設定腳本（腳本內常會 apt install）、
# 有尚未安裝的系統套件（packages／apt_fallback／brew_packages），或使用 --force 就需要；
# 沒有模組管理器資料時一律需要。
# shellcheck disable=SC2120 # 參數為可選，預設用 selected_modules；測試會傳入清單
selected_modules_need_package_index() {
    local modules="${1:-$selected_modules}"
    if [ "${USE_MODULE_MANAGER:-false}" != "true" ] \
       || [[ "$(declare -p MODULE_SCRIPTS 2>/dev/null)" != "declare -A"* ]] \
       || ! command -v _module_pkg_is_installed >/dev/null 2>&1; then
        return 0
    fi
    [ "${FORCE_REINSTALL:-false}" != "true" ] || return 0

    local module_id pkg
    for module_id in $modules; do
        if [ -n "${MODULE_SCRIPTS[$module_id]:-}" ]; then
            return 0
        fi
        for pkg in ${MODULE_PACKAGES[$module_id]:-}; do
            _module_pkg_is_installed apt "$pkg" || return 0
        done
        for pkg in ${MODULE_APT_FALLBACK[$module_id]:-}; do
            _module_pkg_is_installed apt_fallback "$pkg" || return 0
        done
        for pkg in ${MODULE_BREW_PACKAGES[$module_id]:-}; do
            _module_pkg_is_installed brew "$pkg" || return 0
        done
    done
    return 1
}

# 第一個模組開始前先更新套件索引，並以獨立的一行進度顯示（耗時不再算在第一個模組頭上）。
# 更新失敗只顯示警示並繼續安裝。ensure_package_index_fresh 每次執行只會真正更新一次。
prepare_package_index() {
    local use_progress="${1:-false}"
    command -v ensure_package_index_fresh >/dev/null 2>&1 || return 0
    [ "${LINUX_SETTING_PKG_INDEX_CHECKED:-}" != "1" ] || return 0
    selected_modules_need_package_index || return 0

    # 索引仍然新鮮（或不需要更新）時，讓 ensure_package_index_fresh 只做記號與日誌，不顯示進度行
    if [ "$use_progress" != "true" ] \
       || ! command -v _pkg_index_needs_update >/dev/null 2>&1 \
       || ! _pkg_index_needs_update; then
        ensure_package_index_fresh || true
        return 0
    fi

    local label="更新套件索引"
    local started=$SECONDS
    progress_run "" "$label" run_logged_command ensure_package_index_fresh || true
    local elapsed=$((SECONDS - started))
    if [ "${LINUX_SETTING_PKG_INDEX_UPDATED:-}" = "1" ]; then
        progress_finish_line "" "$label" ok "" "$elapsed"
    else
        progress_finish_line "" "$label" partial "更新失敗，繼續安裝" "$elapsed"
    fi
    return 0
}

# 安裝選中的模組
install_selected_modules() {
    reset_install_results
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

    # 無論 modules.conf 定義順序為何，都將 terminal 放到最後執行，
    # 以便在全部模組完成後再套用 zsh/提示符相關設定。
    local module
    local has_terminal=false
    for module in "${install_order[@]}"; do
        if [ "$module" = "terminal" ]; then
            has_terminal=true
            break
        fi
    done
    if [ "$has_terminal" = "true" ]; then
        local reordered_install_order=()
        for module in "${install_order[@]}"; do
            [ "$module" = "terminal" ] && continue
            reordered_install_order+=("$module")
        done
        reordered_install_order+=("terminal")
        install_order=("${reordered_install_order[@]}")
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

        printf "\n${GREEN}提示：${NC}移除 --dry-run 參數即可開始實際安裝\n\n"
        return 0
    fi

    log_info "開始安裝以下模組：$selected_modules"
    log_info "總共 $total_modules 個模組"

    # 進階模式：在開始安裝前，逐模組讓使用者再選具體要裝的套件
    if [ "${ADVANCED_MODE:-false}" = "true" ] \
       && [ "$USE_MODULE_MANAGER" = "true" ] \
       && command -v module_interactive_package_filter >/dev/null 2>&1 \
       && [ "${NON_INTERACTIVE:-false}" != "true" ]; then
        log_info "進階模式：逐模組選擇套件"
        for module in "${install_order[@]}"; do
            case " $selected_modules " in
                *" $module "*) ;;
                *) continue ;;
            esac
            module_interactive_package_filter "$module" || {
                log_warning "使用者取消模組 $module，將從清單移除"
                selected_modules=$(echo " $selected_modules " | sed "s/ $module / /g" | xargs)
                total_modules=$((total_modules - 1))
            }
        done
        log_info "進階選擇完成"
        if [ -z "$selected_modules" ] || [ "$total_modules" -le 0 ]; then
            log_warning "所有模組都被取消，結束安裝"
            return 0
        fi
    fi

    # CLI 互動模式在此詢問 Homebrew（TUI 導覽流程已在選完模組後問過）
    offer_homebrew_if_needed

    local use_progress=false
    if installer_tui_quiet; then
        use_progress=true
        progress_begin "$total_modules"
    fi

    # 優化 APT 性能（Debian 系列）：會寫入 /etc/apt/apt.conf.d/，
    # 所以只在 dry-run 返回與使用者確認之後、第一次用到套件管理器之前執行
    if [ "${DISTRO_FAMILY:-}" = "debian" ] && command -v optimize_apt_performance >/dev/null 2>&1; then
        optimize_apt_performance || log_warning "APT 優化失敗，繼續安裝"
    fi

    prepare_package_index "$use_progress"
    install_homebrew_if_requested

    # 為了確保依賴順序，實際安裝順序固定為：
    # 1. base       - 提供 git/curl/wget 等基礎工具與 APT 相關套件
    # 2. dev        - 安裝 cargo / nodejs 等開發工具，供後續模組使用
    # 3. python     - 建立 Python/uv/虛擬環境，供終端工具使用
    # 4. monitoring - 安裝監控與安全工具
    # 5. docker     - 可選的 Docker 工具
    # 6. terminal   - 最後安裝（不再自動 exec zsh）
    local aborted=false
    for module in "${install_order[@]}"; do
        case " $selected_modules " in
            *" $module "*) ;;
            *) continue ;;
        esac

        if [ "$aborted" = "true" ]; then
            record_module_result "$module" not_run ""
            continue
        fi

        current_module=$((current_module + 1))
        log_info "進度 [$current_module/$total_modules] 安裝模組: $module"

        # 模組層級「已安裝偵測」：印出訊息；實際「跳過套件但仍跑 script / post_install」
        # 的邏輯由 module_manager.sh::install_module 處理。
        # 設 FORCE_REINSTALL=true 或 --force 可強制重裝所有套件。
        if [ "${FORCE_REINSTALL:-false}" != "true" ] \
           && [ "$USE_MODULE_MANAGER" = "true" ] \
           && command -v check_module_status >/dev/null 2>&1; then
            module_status=$(check_module_status "$module" 2>/dev/null || echo "not_installed")
            if [ "$module_status" = "installed" ]; then
                log_success "模組 $module 套件已全部安裝，將跳過套件階段並執行設定腳本"
                log_info "如需強制重裝套件，請加 --force 或設定 FORCE_REINSTALL=true"
            fi
        fi

        local label tag
        label="$(module_display_name "$module")"
        tag="[$current_module/$total_modules]"

        # install_module 在部分套件失敗時回傳 0，但會在 MODULE_INSTALL_FAILURES 附加一筆
        local failures_before=0
        if declare -p MODULE_INSTALL_FAILURES >/dev/null 2>&1; then
            failures_before=${#MODULE_INSTALL_FAILURES[@]}
        fi

        local started=$SECONDS
        local rc=0
        if [ "$use_progress" = "true" ]; then
            progress_run "$tag" "$label" run_module_install "$module" || rc=$?
        else
            run_module_install "$module" || rc=$?
        fi
        local elapsed=$((SECONDS - started))

        local status="ok" detail="" status_text=""
        if [ "$rc" -ne 0 ]; then
            status="failed"
            status_text="失敗"
        elif declare -p MODULE_INSTALL_FAILURES >/dev/null 2>&1 \
             && [ "${#MODULE_INSTALL_FAILURES[@]}" -gt "$failures_before" ]; then
            status="partial"
            detail="$(module_failure_packages "${MODULE_INSTALL_FAILURES[$((${#MODULE_INSTALL_FAILURES[@]} - 1))]}")"
            status_text="部分套件失敗（$(count_words "$detail") 個）"
        else
            status_text="完成"
        fi
        record_module_result "$module" "$status" "$detail"

        if [ "$use_progress" = "true" ]; then
            progress_finish_line "$tag" "$label" "$status" "$status_text" "$elapsed"
        fi

        if [ "$status" = "failed" ]; then
            if ! _handle_module_failure "$module" $((total_modules - current_module)); then
                aborted=true
                INSTALL_ABORTED=true
            fi
            if [ "$use_progress" = "true" ]; then
                progress_redraw
            fi
        fi
    done

    if [ "$use_progress" = "true" ]; then
        progress_end
    fi

    record_created_configs

    show_installation_report
    selected_modules=""
    if [ "${GUIDED_RESULT_SCREEN:-false}" != "true" ] \
       && declare -F reset_module_overrides >/dev/null 2>&1; then
        reset_module_overrides
    fi

    # 如果是在「非互動環境」（例如：管線 / here-doc / Docker 自動化測試），
    # 完成一次安裝後就直接結束腳本，避免迴圈再次 read 造成 EOF 而觸發錯誤處理。
    if [ ! -t 0 ]; then
        printf "${CYAN}偵測到非互動環境，自動結束安裝流程${NC}\n"
        if [ "$aborted" = "true" ]; then
            exit 1
        fi
        # 有模組失敗或未執行時以非 0 結束，讓 CI 與自動化腳本能察覺
        exit "$(install_results_exit_code)"
    fi

    if [ "$aborted" = "true" ]; then
        return 1
    fi
    return 0
}

# 執行主函數
main
