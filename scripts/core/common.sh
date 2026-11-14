#!/usr/bin/env bash

# ==============================================================================
# Common Library - Linux Setting Scripts
# Author: Linux Setting Scripts Team
# Version: 2.0.0
# Description: Common functions library for Linux environment setup
# ==============================================================================

# Guard against repeated sourcing to avoid readonly redefinition errors.
if [ "${COMMON_SH_LOADED:-0}" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi
COMMON_SH_LOADED=1

# Set strict mode
set -euo pipefail

# ==============================================================================
# 預設環境變數（避免 set -u 下任何裸用 $VAR 直接 crash）
# 這些變數都可能在 install.sh / 子腳本執行流程中被使用，
# 為了讓 common.sh 也能單獨被其他工具腳本 source，先在此提供預設值。
# ==============================================================================
: "${VERBOSE:=false}"
: "${DEBUG:=false}"
: "${TUI_MODE:=quiet}"
# 注意：USE_TUI 預設 "auto"（不是 false），讓 ensure_tui_available 有機會偵測 whiptail；
# 這份檔案後段 line ~1804 也有同樣設定，這裡早設一次是為了 set -u 安全
: "${USE_TUI:=auto}"
: "${NON_INTERACTIVE:=false}"
: "${INSTALL_MODE:=full}"
: "${UPDATE_MODE:=false}"
: "${DRY_RUN:=false}"
: "${FORCE_REINSTALL:=false}"
: "${ADVANCED_MODE:=false}"
: "${ABORT_ON_FAILURE:=false}"
: "${SKIP_PYTHON_CHECK:=false}"
: "${ENABLE_PARALLEL_INSTALL:=false}"
: "${PREFER_HOMEBREW:=false}"
: "${PREFER_UV:=true}"
: "${SKIP_NETWORK_TESTS:=false}"

# ==============================================================================
# Configuration Loading
# ==============================================================================

# Load user configuration file if exists
CONFIG_FILE="${CONFIG_FILE:-$HOME/.config/linux-setting/config}"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# ==============================================================================
# Constants
# ==============================================================================

# shellcheck disable=SC2034 # SCRIPT_VERSION 由 tests/test_scripts.sh 字面比對以驗證版本一致性。
readonly SCRIPT_VERSION="2.2.9"
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly YELLOW='\033[0;33m'
readonly NC='\033[0m'

# Security constants
readonly MAX_SCRIPT_SIZE="${MAX_SCRIPT_SIZE:-1048576}"
readonly DOWNLOAD_TIMEOUT="${DOWNLOAD_TIMEOUT:-30}"
readonly DOWNLOAD_RETRIES="${DOWNLOAD_RETRIES:-3}"

# 安裝清單：記錄本工具實際新增的套件、路徑與被修改的設定檔，供 uninstall.sh 使用。
# 以 export 傳給子行程，讓各模組腳本寫入同一份清單。
export INSTALL_MANIFEST_FILE="${INSTALL_MANIFEST_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/linux-setting/installed.manifest}"

# Logging constants
readonly LOG_DIR="${LOG_DIR:-$HOME/.local/log/linux-setting}"
readonly MAX_LOG_SIZE="${MAX_LOG_SIZE:-10}"
readonly MAX_LOG_AGE="${MAX_LOG_AGE:-30}"
readonly MAX_LOG_COUNT="${MAX_LOG_COUNT:-10}"

# Cache constants
readonly CACHE_DIR="${CACHE_DIR:-$HOME/.cache/linux-setting}"
readonly CACHE_TTL="${CACHE_TTL:-86400}"

# Performance constants
readonly PARALLEL_JOBS="${PARALLEL_JOBS:-$(command -v nproc >/dev/null 2>&1 && nproc 2>/dev/null || echo 4)}"

# ==============================================================================
# 函式庫依職責拆在 common/ 下；載入順序即相依順序
#   logging   日誌與步驟進度        system  發行版與環境偵測
#   packages  套件安裝與 Homebrew   files   安裝清單、備份、快取、下載
#   tui       TUI 後端與對話框
# ==============================================================================

# 只用 bash 內建功能取得目錄：極簡系統上可能連 dirname 都沒有
_COMMON_LIB_DIR="${BASH_SOURCE[0]%/*}"
[ "$_COMMON_LIB_DIR" != "${BASH_SOURCE[0]}" ] || _COMMON_LIB_DIR="."
_COMMON_LIB_DIR="$_COMMON_LIB_DIR/common"
# shellcheck source=scripts/core/common/logging.sh
source "$_COMMON_LIB_DIR/logging.sh"
# shellcheck source=scripts/core/common/system.sh
source "$_COMMON_LIB_DIR/system.sh"
# shellcheck source=scripts/core/common/packages.sh
source "$_COMMON_LIB_DIR/packages.sh"
# shellcheck source=scripts/core/common/files.sh
source "$_COMMON_LIB_DIR/files.sh"
# shellcheck source=scripts/core/common/tui.sh
source "$_COMMON_LIB_DIR/tui.sh"

# ==============================================================================
# 權限檢查函數
# ==============================================================================

check_sudo_access() {
    if sudo -n true 2>/dev/null; then
        return 0
    fi

    # 非互動 / 無 tty 環境不允許等密碼，否則會永久卡住
    if [ "${NON_INTERACTIVE:-false}" = "true" ] || [ ! -t 0 ]; then
        log_error "需要 sudo 權限但當前為非互動環境（無法輸入密碼）"
        log_error "請先在 shell 中執行 'sudo -v'，或設定 NOPASSWD sudo，再重跑此腳本"
        return 1
    fi

    log_warning "需要 sudo 權限，請輸入密碼"
    sudo -v
    return $?
}

# ==============================================================================
# 初始化函數
# ==============================================================================

# 探測並把語言工具 PATH 注入目前 session
# 解決非互動 shell（bash -c / curl|bash）下不 source .bashrc 導致的誤判「未安裝」。
# 回傳值恆為 0，只是印出探測到的工具，不強制安裝。
detect_and_inject_tool_paths() {
    local injected=()

    # Homebrew / Linuxbrew
    if ! command -v brew >/dev/null 2>&1; then
        for cand in \
            /home/linuxbrew/.linuxbrew/bin/brew \
            "$HOME/.linuxbrew/bin/brew" \
            /opt/homebrew/bin/brew \
            /usr/local/bin/brew; do
            if [ -x "$cand" ]; then
                eval "$("$cand" shellenv)" 2>/dev/null || {
                    PATH="$(dirname "$cand"):$PATH" || true
                    export PATH
                }
                injected+=("brew@$cand")
                break
            fi
        done
    fi

    # Cargo / rustup
    if ! command -v cargo >/dev/null 2>&1 && [ -x "$HOME/.cargo/bin/cargo" ]; then
        export PATH="$HOME/.cargo/bin:$PATH"
        injected+=("cargo@$HOME/.cargo/bin")
    fi

    # uv / pipx / 其他 pip tool
    if ! command -v uv >/dev/null 2>&1 && [ -x "$HOME/.local/bin/uv" ]; then
        export PATH="$HOME/.local/bin:$PATH"
        injected+=("uv@$HOME/.local/bin")
    fi

    # pyenv
    if ! command -v pyenv >/dev/null 2>&1 && [ -x "$HOME/.pyenv/bin/pyenv" ]; then
        export PATH="$HOME/.pyenv/bin:$PATH"
        injected+=("pyenv@$HOME/.pyenv/bin")
    fi

    # nvm / node（只確保 ~/.nvm/current 或最新 default 的 bin 被加進 PATH）
    if ! command -v node >/dev/null 2>&1; then
        if [ -s "$HOME/.nvm/nvm.sh" ]; then
            # nvm.sh 會定義 node 預設版本
            # shellcheck disable=SC1091
            . "$HOME/.nvm/nvm.sh" >/dev/null 2>&1 || true
            command -v node >/dev/null 2>&1 && injected+=("node@nvm")
        elif [ -x "$HOME/.fnm/fnm" ]; then
            export PATH="$HOME/.fnm:$PATH"
            injected+=("fnm@$HOME/.fnm")
        fi
    fi

    # Go
    if ! command -v go >/dev/null 2>&1 && [ -x "/usr/local/go/bin/go" ]; then
        export PATH="/usr/local/go/bin:$PATH"
        injected+=("go@/usr/local/go/bin")
    fi

    if [ ${#injected[@]} -gt 0 ]; then
        log_debug "注入工具 PATH: ${injected[*]}"
    fi
    return 0
}

init_common_env() {
    # 設置錯誤處理
    # 只啟用 errtrace 旗標，不在這裡註冊 ERR trap：
    # - install.sh 會自己設 `trap 'handle_error ...' ERR`，過去這裡會覆蓋掉它，
    #   導致使用者看不到錯誤 menu / 自動 cleanup / rollback。
    # - 對於直接執行 `scripts/core/*.sh` 的情境，bash 的 `set -e` 已足夠。
    # - 如仍想要預設 ERR 訊息，可在呼叫端自行 `trap 'log_error ...' ERR`。
    set -eE

    # 創建必要目錄
    mkdir -p "$HOME/.local/bin"
    mkdir -p "$HOME/.config"

    # 初始化快取系統
    init_cache_system

    # 基本 PATH 擴充
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

    # 偵測已存在於常見安裝位置但不在 PATH 的工具並注入，
    # 這樣 `command -v brew/cargo/uv/...` 後續才能正確判定已安裝。
    detect_and_inject_tool_paths

    # PARALLEL_JOBS 已在檔案頂部定義為 readonly
    log_info "共用環境初始化完成（並行任務: $PARALLEL_JOBS）"
}

# 取得 GitHub 最新發行版，優先使用網頁轉址以避免 API 配額限制。
github_latest_release_tag() {
    local repo="$1" url tag payload
    if url=$(curl -fsSLI --connect-timeout 10 --max-time 30 -o /dev/null \
        -w '%{url_effective}' "https://github.com/$repo/releases/latest" 2>/dev/null); then
        tag="${url##*/}"
        if [[ "$url" == */releases/tag/* ]] && [ -n "$tag" ] && [ "$tag" != latest ]; then
            printf '%s\n' "$tag"
            return 0
        fi
    fi
    if payload=$(curl -fsSL --connect-timeout 10 --max-time 30 \
        "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null); then
        tag=$(printf '%s\n' "$payload" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p') || return 1
        if [ -n "$tag" ] && [ "$tag" != latest ]; then
            printf '%s\n' "$tag"
            return 0
        fi
    fi
    return 1
}

linux_release_arch() {
    local arch
    arch=$(uname -m) || return 1
    case "$arch" in
        x86_64|amd64) printf '%s\n' x86_64 ;;
        aarch64|arm64) printf '%s\n' aarch64 ;;
        *) printf '%s\n' "$arch" ;;
    esac
}

# ==============================================================================
# 導出所有函數
# ==============================================================================

# 安全導出所有函數供子 shell 使用
func_list="_log_should_print_status_to_terminal log_error log_info log_success log_warning log_debug init_progress show_progress run_as_root"
func_list="$func_list check_command check_package_installed check_python_version check_disk_space check_network"
func_list="$func_list check_pip_package_installed check_cargo_package_installed check_npm_package_installed"
func_list="$func_list install_with_fallback install_with_homebrew_fallback install_package install_apt_package install_apt_packages_parallel install_packages_batch"
func_list="$func_list install_brew_package check_brew_package_installed ensure_brew_shell_aliases ensure_homebrew_installed update_system"
func_list="$func_list ensure_package_index_fresh _pkg_index_needs_update _file_mtime _log_file_writable _pkg_run _root_exec _root_exec_apt _pkg_root_exec"
func_list="$func_list github_latest_release_tag linux_release_arch"
func_list="$func_list verify_sha256_in_list manifest_record"
func_list="$func_list backup_file safe_append_to_file"
func_list="$func_list init_cache_system is_cache_valid get_from_cache save_to_cache"
func_list="$func_list safe_download"
func_list="$func_list optimize_apt_performance"
func_list="$func_list version_greater_equal check_architecture_compatibility install_arch_specific_package"
func_list="$func_list ensure_tui_available tui_checklist tui_checklist_with_state tui_menu tui_yesno tui_msgbox tui_log_viewer tui_gauge"
func_list="$func_list _tui_terminal_too_small"
func_list="$func_list check_sudo_access init_common_env detect_and_inject_tool_paths"
func_list="$func_list is_non_interactive safe_read ensure_npm_user_prefix"
func_list="$func_list _tui_expand_text _tui_display_width _tui_max_display_width _tui_term_size _tui_dialog_size _tui_menu_fits_text _tui_fzf_height"

for func in $func_list; do
    if declare -f "$func" > /dev/null 2>&1; then
        export -f "${func?}" 2>/dev/null || true
    fi
done
