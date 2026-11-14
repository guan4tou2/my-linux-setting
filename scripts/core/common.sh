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
: "${REMOTE_INSTALL:=false}"
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
readonly MIN_PACKAGES_FOR_PARALLEL="${MIN_PACKAGES_FOR_PARALLEL:-3}"

# Global variables
SCRIPT_START_TIME=$(command -v date >/dev/null 2>&1 && date +%s) || true
readonly SCRIPT_START_TIME
TOTAL_STEPS=0
CURRENT_STEP=0

# 判斷 LOG_FILE 是否已設定且可寫入（用於 quiet 模式保留指令輸出）
_log_file_writable() {
    [ -n "${LOG_FILE:-}" ] || return 1
    if [ -e "$LOG_FILE" ]; then
        [ -f "$LOG_FILE" ] && [ -w "$LOG_FILE" ]
    else
        [ -d "$(dirname "$LOG_FILE")" ] && [ -w "$(dirname "$LOG_FILE")" ]
    fi
}

# 依輸出模式執行指令：_pkg_run <quiet|normal> cmd [args...]
# quiet：終端機保持安靜；LOG_FILE 可寫時 stdout/stderr 附加到日誌（保留失敗原因），否則丟棄。
# normal：直接輸出到終端機。
_pkg_run() {
    local mode="$1"
    shift
    if [ "$mode" = "quiet" ]; then
        if _log_file_writable; then
            # 日誌中只記實際指令，不含內部包裝函式名稱
            local shown_cmd="$*"
            shown_cmd="${shown_cmd#_root_exec_apt }"
            shown_cmd="${shown_cmd#_root_exec }"
            printf '%s [CMD] %s\n' "$(date +%Y-%m-%dT%H:%M:%S 2>/dev/null)" "$shown_cmd" >> "$LOG_FILE" 2>/dev/null || true
            "$@" >> "$LOG_FILE" 2>&1
        else
            "$@" >/dev/null 2>&1
        fi
    else
        "$@"
    fi
}

# 以 root 身分執行（已是 root 時不經 sudo，沒有 sudo 的環境也可用）
_root_exec() {
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# 以 root 身分執行 apt 類指令，強制非互動
_root_exec_apt() {
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        env DEBIAN_FRONTEND=noninteractive "$@"
    else
        sudo DEBIAN_FRONTEND=noninteractive "$@"
    fi
}

# 以 root 身分執行套件管理器指令並依 mode 處理輸出：_pkg_root_exec <quiet|normal> cmd [args...]
_pkg_root_exec() {
    local mode="$1"
    shift
    case "$1" in
        apt|apt-get) _pkg_run "$mode" _root_exec_apt "$@" ;;
        *) _pkg_run "$mode" _root_exec "$@" ;;
    esac
}

# 統一處理 root 權限執行
# 對 apt/apt-get 一律注入 DEBIAN_FRONTEND=noninteractive 與 --force-confold，
# 避免 dpkg 設定檔 prompt 在非互動環境下卡死。
# quiet 模式下 apt 輸出不顯示在終端機，但會附加到 LOG_FILE（若可寫）以便診斷。
run_as_root() {
    local cmd="$1"
    shift || true

    # apt / apt-get 特殊處理：一律非互動
    if [ "$cmd" = "apt" ] || [ "$cmd" = "apt-get" ]; then
        local apt_opts=(-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
        if [ "${TUI_MODE:-quiet}" = "quiet" ]; then
            _pkg_root_exec quiet "$cmd" -qq "${apt_opts[@]}" "$@"
        else
            _pkg_root_exec normal "$cmd" "${apt_opts[@]}" "$@"
        fi
        return $?
    fi

    # 其他命令維持原本行為
    _root_exec "$cmd" "$@"
}

# ==============================================================================
# Logging Functions
# ==============================================================================

# Initialize logging with rotation
init_logging() {
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local log_prefix="common_$timestamp.log"

    # Create log directory
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    chmod 0700 "$LOG_DIR" 2>/dev/null || true

    # Set log file path
    LOG_FILE="${LOG_FILE:-$LOG_DIR/$log_prefix}"

    # Rotate old logs
    rotate_logs

    # Set global logging flag
    ENABLE_LOGGING="${ENABLE_LOGGING:-true}"
}

# Rotate log files based on size, age, and count
rotate_logs() {
    [ "${ENABLE_LOGGING:-true}" != "true" ] && return 0 || true

    # Clean logs older than MAX_LOG_AGE days
    find "$LOG_DIR" -type f -name "*.log" -mtime +$MAX_LOG_AGE -delete 2>/dev/null || true

    # Check log sizes and rotate if needed
    for log_file in "$LOG_DIR"/*.log; do
        [ -f "$log_file" ] || continue

        local file_size_mb
        file_size_mb=$(du -m "$log_file" 2>/dev/null | cut -f1)

        if [ "$file_size_mb" -ge "$MAX_LOG_SIZE" ]; then
            local new_name
            new_name="${log_file%.log}.$(date +%Y%m%d_%H%M%S).old"
            mv "$log_file" "$new_name" 2>/dev/null || true
        fi
    done

    # Keep only MAX_LOG_COUNT log files
    local log_count
    log_count=$(find "$LOG_DIR" -type f -name "*.log" | wc -l 2>/dev/null || echo 0)

    if [ "$log_count" -gt "$MAX_LOG_COUNT" ]; then
        find "$LOG_DIR" -type f -name "*.log" -printf '%T@%p\n' | \
            sort -n | head -n "$((log_count - MAX_LOG_COUNT))" | \
            cut -d@ -f2- | xargs rm -f 2>/dev/null || true
    fi
}

# Structured logging helper - 只寫入日誌文件
log_entry() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date -Iseconds 2>/dev/null || date +"%Y-%m-%dT%H:%M:%S")
    local pid=$$

    # 確保日誌文件存在
    [ -z "${LOG_FILE:-}" ] && return 0 || true

    case "${LOG_FORMAT:-text}" in
        json)
            printf '{"timestamp":"%s","level":"%s","pid":%d,"message":"%s"}\n' \
                "$timestamp" "$level" "$pid" "$message" >> "$LOG_FILE" 2>/dev/null || true
            ;;
        *)
            printf '%s [%s] [%d] %s\n' \
                "$timestamp" "$level" "$pid" "$message" >> "$LOG_FILE" 2>/dev/null || true
            ;;
    esac
}

_log_should_print_status_to_terminal() {
    case "${TUI_LOG_TO_TERMINAL:-auto}" in
        true) return 0 ;;
        false) return 1 ;;
    esac

    if [ "${NON_INTERACTIVE:-false}" = "true" ]; then
        return 0
    fi

    if [ "${TUI_MODE:-quiet}" = "quiet" ] && [ "${USE_TUI:-auto}" != "false" ]; then
        return 1
    fi

    return 0
}

log_error() {
    local message="$1"
    # 總是輸出到終端（錯誤訊息）
    printf "${RED}ERROR: %s${NC}\n" "$message" >&2
    # 如果啟用日誌，同時寫入日誌文件
    [ "${ENABLE_LOGGING:-false}" = "true" ] && log_entry "ERROR" "$message"
    return 1
}

log_info() {
    local message="$1"
    # TUI quiet 模式下只寫入日誌，避免狀態訊息刷在 TUI 背後
    if _log_should_print_status_to_terminal; then
        printf "${CYAN}INFO: %s${NC}\n" "$message"
    fi
    # 如果啟用日誌，同時寫入日誌文件
    [ "${ENABLE_LOGGING:-false}" = "true" ] && log_entry "INFO" "$message" || true
}

log_success() {
    local message="$1"
    # TUI quiet 模式下只寫入日誌，避免狀態訊息刷在 TUI 背後
    if _log_should_print_status_to_terminal; then
        printf "${GREEN}SUCCESS: %s${NC}\n" "$message"
    fi
    # 如果啟用日誌，同時寫入日誌文件
    [ "${ENABLE_LOGGING:-false}" = "true" ] && log_entry "SUCCESS" "$message" || true
}

log_warning() {
    local message="$1"
    # TUI quiet 模式下只寫入日誌，避免狀態訊息刷在 TUI 背後
    if _log_should_print_status_to_terminal; then
        printf "${YELLOW}WARNING: %s${NC}\n" "$message"
    fi
    # 如果啟用日誌，同時寫入日誌文件
    [ "${ENABLE_LOGGING:-false}" = "true" ] && log_entry "WARNING" "$message" || true
}

log_debug() {
    local message="$1"
    # DEBUG 模式未啟用時直接返回
    [ "${DEBUG:-false}" != "true" ] && return 0 || true
    # TUI quiet 模式下只寫入日誌，避免狀態訊息刷在 TUI 背後
    if _log_should_print_status_to_terminal; then
        printf "${BLUE}DEBUG: %s${NC}\n" "$message"
    fi
    # 如果啟用日誌，同時寫入日誌文件
    [ "${ENABLE_LOGGING:-false}" = "true" ] && log_entry "DEBUG" "$message" || true
}

# ==============================================================================
# 進度顯示函數
# ==============================================================================

init_progress() {
    local total="$1"
    TOTAL_STEPS="$total"
    CURRENT_STEP=0
}

show_progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local message="${1:-Processing...}"
    local percent=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    local bar_length=50
    local filled_length=$((percent * bar_length / 100))
    
    local bar=""
    for i in $(seq 1 $filled_length); do bar="${bar}#"; done
    for i in $(seq $((filled_length + 1)) $bar_length); do bar="${bar}-"; done
    
    printf "\r${CYAN}[%s] %d%% - %s${NC}" "$bar" "$percent" "$message"
    if [ "$CURRENT_STEP" -eq "$TOTAL_STEPS" ]; then
        printf "\n"
    fi
}

# ==============================================================================
# 系統檢查函數
# ==============================================================================

# 發行版檢測
# 支援的發行版：Ubuntu, Debian, Kali, Fedora, CentOS, Rocky, Alma, Arch, Manjaro
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        echo "$DISTRIB_ID" | tr '[:upper:]' '[:lower:]'
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "rhel"
    elif [ -f /etc/arch-release ]; then
        echo "arch"
    else
        echo "unknown"
    fi
}

# 獲取發行版系列（用於判斷包管理器）
get_distro_family() {
    local distro="${1:-$(detect_distro)}"
    case "$distro" in
        ubuntu|debian|kali|linuxmint|pop|elementary)
            echo "debian"
            ;;
        fedora|centos|rhel|rocky|alma|amazonlinux)
            echo "rhel"
            ;;
        arch|manjaro|endeavouros|garuda)
            echo "arch"
            ;;
        opensuse*|sles)
            echo "suse"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# 獲取包管理器
get_package_manager() {
    local family="${1:-$(get_distro_family)}"
    case "$family" in
        debian)
            echo "apt"
            ;;
        rhel)
            if command -v dnf >/dev/null 2>&1; then
                echo "dnf"
            else
                echo "yum"
            fi
            ;;
        arch)
            echo "pacman"
            ;;
        suse)
            echo "zypper"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# 檢測當前系統
DISTRO=$(detect_distro)
DISTRO_FAMILY=$(get_distro_family "$DISTRO")
PKG_MANAGER=$(get_package_manager "$DISTRO_FAMILY")

check_command() {
    command -v "$1" >/dev/null 2>&1
}

check_package_installed() {
    local package="$1"
    case "${PKG_MANAGER:-apt}" in
        apt)
            # 使用 dpkg-query 比 `dpkg -l | grep` 穩定：
            # - 正確處理多架構（libfoo:amd64 vs libfoo:i386）
            # - 不會被包名內的 regex 特殊字符誤判
            # - 不依賴 locale 下的欄位寬度
            dpkg-query -W -f='${Status}\n' "$package" 2>/dev/null \
                | grep -q '^install ok installed$'
            ;;
        dnf|yum)
            rpm -q "$package" >/dev/null 2>&1
            ;;
        pacman)
            pacman -Q "$package" >/dev/null 2>&1
            ;;
        zypper)
            rpm -q "$package" >/dev/null 2>&1
            ;;
        *)
            log_warning "不支援的包管理器，無法檢查套件"
            return 1
            ;;
    esac
}

check_python_version() {
    local min_version="$1"
    if ! check_command python3; then
        return 1
    fi
    
    local current_version
    current_version=$(python3 -c "import sys; print('.'.join(map(str, sys.version_info[:2])))")
    
    if [ "$(printf '%s\n' "$min_version" "$current_version" | sort -V | head -n1)" = "$min_version" ]; then
        return 0
    else
        return 1
    fi
}

check_disk_space() {
    local required_gb="$1"
    local available_gb
    available_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [ "$available_gb" -ge "$required_gb" ]; then
        return 0
    else
        return 1
    fi
}

check_network() {
    local timeout="${1:-5}"
    # 優先使用 curl（在容器中更可靠）
    if command -v curl >/dev/null 2>&1; then
        curl -s --max-time "$timeout" --connect-timeout "$timeout" https://www.google.com >/dev/null 2>&1 ||
        curl -s --max-time "$timeout" --connect-timeout "$timeout" https://www.baidu.com >/dev/null 2>&1
    else
        # 若 curl 不可用則使用 ping
        timeout "$timeout" ping -c 1 google.com >/dev/null 2>&1 ||
        timeout "$timeout" ping -c 1 baidu.com >/dev/null 2>&1
    fi
}

check_internet_speed() {
    local url="http://cachefly.cachefly.net/1mb.test"
    local start_time end_time duration speed
    
    start_time=$(date +%s.%N)
    if curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" | grep -q "200"; then
        end_time=$(date +%s.%N)
        # 使用 awk 進行浮點運算
        duration=$(awk "BEGIN {print $end_time - $start_time}")
        speed=$(awk "BEGIN {printf \"%.2f\", 1 / $duration}")
        echo "$speed"
    else
        echo "0"
    fi
}

# ==============================================================================
# 並行安裝函數
# ==============================================================================

# 批次安裝多個 APT 套件（使用單一 apt 呼叫，避免 dpkg lock 競爭與 sudo 提示卡死）
#
# 設計考量：
# - 不再用「多個並行 sudo apt-get install」，因為 dpkg 用獨佔鎖，平行只會互相等鎖；
#   且背景 sudo 的 stdin 被導向 log file 時，若需要密碼或互動 prompt 會永久卡住。
# - 改用 `apt-get install -y pkg1 pkg2 ...` 一次性安裝，apt 內部本來就會平行下載。
# - 強制 DEBIAN_FRONTEND=noninteractive，避免 dpkg 跳出設定視窗。
# - 仍保留逐套件 fallback：批次失敗時逐個重試以隔離有問題的套件。
install_apt_packages_parallel() {
    local packages=("$@")
    local failed_packages=()
    # 供呼叫端取得「實際失敗的套件」（批次失敗後逐一重試的結果）
    APT_BATCH_FAILED_PACKAGES=()

    if [ ${#packages[@]} -eq 0 ]; then
        return 0
    fi

    log_info "批次安裝 ${#packages[@]} 個 APT 套件: ${packages[*]}"

    # 只有「安裝前尚未存在」的套件才記入安裝清單（呼叫端通常已先過濾，這裡再確認一次）
    local new_packages=() pkg
    for pkg in "${packages[@]}"; do
        if ! check_package_installed "$pkg" 2>/dev/null; then
            new_packages+=("$pkg")
        fi
    done

    local apt_opts=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
    local mode="normal"
    [ "${TUI_MODE:-normal}" = "quiet" ] && mode="quiet" || true

    # 步驟 1：嘗試一次性批次安裝（quiet 模式輸出寫入日誌）
    if _pkg_root_exec "$mode" apt-get install "${apt_opts[@]}" "${packages[@]}"; then
        log_success "批次安裝完成: ${#packages[@]}/${#packages[@]} 成功"
        for pkg in ${new_packages[@]+"${new_packages[@]}"}; do
            manifest_record package "$pkg"
        done
        return 0
    fi

    # 步驟 2：批次失敗時，逐個重試以找出真正壞掉的套件（輸出一律寫入日誌）
    log_warning "批次安裝失敗，改為逐個安裝以隔離問題套件..."
    local success_count=0
    local package
    for package in "${packages[@]}"; do
        if _pkg_root_exec quiet apt-get install "${apt_opts[@]}" "$package"; then
            success_count=$((success_count + 1))
            log_success "✓ $package"
            if [[ " ${new_packages[*]:-} " == *" $package "* ]]; then
                manifest_record package "$package"
            fi
        else
            failed_packages+=("$package")
            log_error "✗ $package" || true
        fi
    done

    log_info "安裝完成: $success_count/${#packages[@]} 成功"

    if [ ${#failed_packages[@]} -gt 0 ]; then
        # shellcheck disable=SC2034 # module_manager.sh 的 install_module 讀取失敗套件陣列。
        APT_BATCH_FAILED_PACKAGES=("${failed_packages[@]}")
        log_warning "失敗的套件: ${failed_packages[*]}"
        return 1
    fi

    return 0
}

# 並行下載多個文件
download_files_parallel() {
    local -A url_file_map
    while [[ $# -gt 0 ]]; do
        url_file_map["$1"]="$2"
        shift 2
    done
    
    local max_jobs="${PARALLEL_JOBS:-3}"
    local temp_dir
    temp_dir=$(mktemp -d)
    local pids=()
    local failed_downloads=()
    
    log_info "並行下載 ${#url_file_map[@]} 個文件"
    
    # 下載單個文件的函數
    download_single_file() {
        local url="$1"
        local output="$2"
        local log_file="$3"
        
        {
            if safe_download "$url" "$output"; then
                echo "SUCCESS:$url"
            else
                echo "FAILED:$url"
            fi
        } > "$log_file" 2>&1
    }
    
    # 導出函數供子 shell 使用
    for func in download_single_file safe_download log_info log_success log_error; do
        if declare -f "$func" > /dev/null 2>&1; then
            export -f "${func?}" 2>/dev/null || true
        fi
    done
    
    # 啟動並行下載任務
    for url in "${!url_file_map[@]}"; do
        local output="${url_file_map[$url]}"
        local log_file
        log_file="$temp_dir/$(basename "$output").log" || true
        
        # 等待任務槽位可用
        while [ ${#pids[@]} -ge $max_jobs ]; do
            for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[i]}" 2>/dev/null; then
                    unset 'pids[i]'
                fi
            done
            pids=("${pids[@]}") # 重新索引數組
            sleep 0.1
        done
        
        # 創建輸出目錄
        mkdir -p "$(dirname "$output")"
        
        # 啟動下載任務
        download_single_file "$url" "$output" "$log_file" &
        pids+=($!)
        
        log_debug "啟動下載任務: $url"
    done
    
    # 等待所有下載完成
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    # 收集結果
    local success_count=0
    for url in "${!url_file_map[@]}"; do
        local output="${url_file_map[$url]}"
        local log_file
        log_file="$temp_dir/$(basename "$output").log" || true
        
        if [ -f "$log_file" ]; then
            local result
            result=$(tail -n1 "$log_file" 2>/dev/null)
            if [[ "$result" == SUCCESS:* ]]; then
                success_count=$((success_count + 1))
                log_success "✓ $(basename "$output")"
            else
                failed_downloads+=("$url")
                log_error "✗ $(basename "$output")"
            fi
        fi
    done
    
    # 清理臨時文件
    rm -rf "$temp_dir"
    
    log_info "並行下載完成: $success_count/${#url_file_map[@]} 成功"
    
    if [ ${#failed_downloads[@]} -gt 0 ]; then
        log_warning "失敗的下載: ${failed_downloads[*]}"
        return 1
    fi
    
    return 0
}

# ==============================================================================
# Unified Package Installation Functions
# ==============================================================================

# Try Homebrew installation with fallback
install_with_homebrew_fallback() {
    local package="$1"
    local binary_name="${2:-$package}"

    [ "${PREFER_HOMEBREW:-true}" != "true" ] && return 1 || true

    if check_command "$binary_name"; then
        return 0
    fi

    if ! command -v brew >/dev/null 2>&1; then
        return 1
    fi

    log_info "Attempting Homebrew installation: $package"

    if install_brew_package "$package"; then
        log_success "$package installed via Homebrew"
        return 0
    else
        log_debug "Homebrew installation failed for $package, will try fallback"
        return 1
    fi
}

# Unified pattern: Try Homebrew, then call fallback function
try_homebrew_then() {
    local package="$1"
    local binary_name="${2:-$package}"
    local fallback_function="$3"
    shift 3
    # shellcheck disable=SC2124 # 既有介面刻意將所有參數以空白串成單一引數傳給 fallback。
    local fallback_args="$@"

    if ! install_with_homebrew_fallback "$package" "$binary_name"; then
        # Homebrew not available or failed, use fallback
        if [ -n "$fallback_function" ]; then
            log_info "Using fallback method: $fallback_function"
            "$fallback_function" "$fallback_args"
        else
            log_warning "No fallback method available for $package"
            return 1
        fi
    fi
    return $?
}

# Install with multiple fallback methods
install_with_fallback() {
    local package="$1"
    local install_method="${2:-uv,pip,binary}"

    IFS=',' read -ra methods <<< "$install_method"

    for method in "${methods[@]}"; do
        case "$method" in
            uv)
                if [ "${PREFER_UV:-true}" = "true" ] && check_command uv; then
                    log_info "Installing $package via uv"
                    if uv tool install "$package"; then
                        log_success "$package installed via uv"
                        return 0
                    fi
                fi
                ;;
            pip)
                # 明確呼叫 python3 -m pip 避免 `pip` 指到 Python 2 或錯 venv
                log_info "Installing $package via python3 -m pip"
                if command -v python3 >/dev/null 2>&1 \
                   && python3 -m pip install --user "$package" 2>/dev/null; then
                    log_success "$package installed via python3 -m pip --user"
                    return 0
                fi
                ;;
            brew)
                if command -v brew >/dev/null 2>&1; then
                    log_info "Installing $package via brew"
                    if install_brew_package "$package"; then
                        log_success "$package installed via brew"
                        return 0
                    fi
                fi
                ;;
            cargo)
                if command -v cargo >/dev/null 2>&1; then
                    log_info "Installing $package via cargo"
                    if cargo install "$package" 2>/dev/null; then
                        log_success "$package installed via cargo"
                        return 0
                    fi
                fi
                ;;
        esac
    done

    log_error "All installation methods failed for $package"
    return 1
}

# 通用包安裝函數（支援多種包管理器）
install_package() {
    local package="$1"
    local force="${2:-false}"

    if [ "$force" = "false" ] && check_package_installed "$package"; then
        log_info "$package 已安裝"
        return 0
    fi

    # 強制重裝時，安裝前就存在的套件不算「本工具新安裝」，不記入安裝清單
    local pre_installed=false
    if [ "$force" != "false" ] && check_package_installed "$package" 2>/dev/null; then
        pre_installed=true
    fi

    log_info "安裝 $package (使用 ${PKG_MANAGER:-apt})"

    # 根據包管理器選擇安裝命令（一律經 _pkg_root_exec：已是 root 時不依賴 sudo，
    # apt 一律加上 DEBIAN_FRONTEND=noninteractive，避免 dpkg 跳出設定視窗造成卡死）
    local install_cmd=()
    case "${PKG_MANAGER:-apt}" in
        apt)
            install_cmd=(apt-get install -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
            ;;
        dnf)
            install_cmd=(dnf install -y)
            ;;
        yum)
            install_cmd=(yum install -y)
            ;;
        pacman)
            install_cmd=(pacman -S --noconfirm)
            ;;
        zypper)
            install_cmd=(zypper install -y)
            ;;
        *)
            log_error "不支援的包管理器: ${PKG_MANAGER}"
            return 1
            ;;
    esac

    # 根據 TUI_MODE 控制輸出詳細程度
    # 靜默模式：終端機不顯示，但指令輸出會附加到 LOG_FILE，失敗時可查原因
    local mode="normal"
    [ "${TUI_MODE:-normal}" = "quiet" ] && mode="quiet" || true

    if _pkg_root_exec "$mode" "${install_cmd[@]}" "$package"; then
        log_success "$package 安裝成功"
        if [ "$pre_installed" != "true" ]; then
            manifest_record package "$package"
        fi
        return 0
    else
        log_error "$package 安裝失敗" || true
        return 1
    fi
}

# 保留 install_apt_package 以保持向後兼容
install_apt_package() {
    install_package "$@"
}

# 批量安裝包（支持並行模式）
install_packages_batch() {
    local packages=("$@")
    local failed_packages=()

    # 過濾已安裝的包
    local to_install=()
    for pkg in "${packages[@]}"; do
        if check_package_installed "$pkg" 2>/dev/null; then
            log_info "$pkg 已安裝，跳過"
        else
            to_install+=("$pkg")
        fi
    done

    # 如果沒有需要安裝的包，直接返回
    if [ ${#to_install[@]} -eq 0 ]; then
        log_info "所有包都已安裝"
        return 0
    fi

    # 對於 Debian 系列，使用批次安裝（單一 apt 呼叫，避免 dpkg lock 競爭）
    # 注意：保留 ENABLE_PARALLEL_INSTALL 變數名向後相容，實際底層改用單次 apt batch
    if [ "${ENABLE_PARALLEL_INSTALL:-false}" = "true" ] && [ ${#to_install[@]} -ge 3 ]; then
        if [ "$DISTRO_FAMILY" = "debian" ] && command -v install_apt_packages_parallel >/dev/null 2>&1; then
            log_info "使用批次模式安裝 ${#to_install[@]} 個套件"
            install_apt_packages_parallel "${to_install[@]}"
            return $?
        fi
    fi

    # 串行安裝（默認或不支持並行）
    for pkg in "${to_install[@]}"; do
        if ! install_package "$pkg"; then
            log_warning "$pkg 安裝失敗，記錄並繼續"
            failed_packages+=("$pkg")
        fi
    done

    # 報告失敗的包
    if [ ${#failed_packages[@]} -gt 0 ]; then
        log_warning "以下包安裝失敗: ${failed_packages[*]}"
        return 1
    fi

    return 0
}

# 通用系統更新函數（更新套件索引）
# 本次執行（含子行程，透過 export 的環境變數）已成功更新過就直接略過；
# 傳入 "force" 可強制重新更新。
# shellcheck disable=SC2120 # 可選參數 "force" 用於強制重新更新，目前由測試與維護情境使用
update_system() {
    local force="${1:-}"

    if [ "$force" != "force" ] && [ "${LINUX_SETTING_PKG_INDEX_UPDATED:-}" = "1" ]; then
        log_info "本次執行已更新過套件索引，略過重複更新"
        return 0
    fi

    log_info "更新系統套件列表 (使用 ${PKG_MANAGER:-apt})"

    local mode="normal"
    [ "${TUI_MODE:-normal}" = "quiet" ] && mode="quiet" || true
    local rc=0

    case "${PKG_MANAGER:-apt}" in
        apt)
            # Error-Mode=any：來源抓取失敗時回傳非 0（預設只印 W: 警告並回傳 0，
            # 會讓「索引更新成功」的判斷失準）；舊版 apt 不認得此選項時會直接忽略
            _pkg_root_exec "$mode" apt-get update -o APT::Update::Error-Mode=any || rc=$?
            ;;
        dnf)
            _pkg_root_exec "$mode" dnf check-update || rc=$?
            [ "$rc" -ne 100 ] || rc=0
            ;;
        yum)
            _pkg_root_exec "$mode" yum check-update || rc=$?
            [ "$rc" -ne 100 ] || rc=0
            ;;
        pacman)
            _pkg_root_exec "$mode" pacman -Sy || rc=$?
            ;;
        zypper)
            _pkg_root_exec "$mode" zypper refresh || rc=$?
            ;;
        *)
            log_warning "不支援的包管理器，無法更新系統"
            return 1
            ;;
    esac

    if [ "$rc" -eq 0 ]; then
        export LINUX_SETTING_PKG_INDEX_UPDATED="1"
    fi
    return "$rc"
}

# 取得檔案修改時間（epoch 秒）；失敗輸出 0
_file_mtime() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

# 判斷套件索引是否需要更新（需要更新回傳 0）
# apt：/var/lib/apt/lists 沒有套件索引，或索引／快取超過 PKG_INDEX_MAX_AGE 秒（預設 86400）未更新。
# 可用 APT_LISTS_DIR、APT_PKGCACHE_FILE、APT_UPDATE_STAMP_FILE 覆寫路徑（測試用）。
_pkg_index_needs_update() {
    case "${PKG_MANAGER:-apt}" in
        apt)
            local lists_dir="${APT_LISTS_DIR:-/var/lib/apt/lists}"
            local pkgcache="${APT_PKGCACHE_FILE:-/var/cache/apt/pkgcache.bin}"
            local stamp="${APT_UPDATE_STAMP_FILE:-/var/lib/apt/periodic/update-success-stamp}"
            local max_age="${PKG_INDEX_MAX_AGE:-86400}"

            # 索引不存在或為空：需要更新
            local newest_list=0 f m found=0
            for f in "$lists_dir"/*Packages* "$lists_dir"/*Sources*; do
                [ -f "$f" ] && [ -s "$f" ] || continue
                found=1
                m=$(_file_mtime "$f")
                [ "$m" -gt "$newest_list" ] && newest_list=$m || true
            done
            [ "$found" -eq 1 ] || return 0

            # 取索引檔、pkgcache、update stamp 中最新的時間判斷是否過舊
            local newest="$newest_list"
            for f in "$pkgcache" "$stamp"; do
                [ -f "$f" ] || continue
                m=$(_file_mtime "$f")
                [ "$m" -gt "$newest" ] && newest=$m || true
            done
            local now
            now=$(date +%s)
            [ $((now - newest)) -gt "$max_age" ]
            ;;
        pacman)
            # pacman 資料庫過舊時安裝會 404，每次執行同步一次
            return 0
            ;;
        *)
            # dnf / yum / zypper 安裝時會自動重新整理 metadata
            return 1
            ;;
    esac
}

# 安裝系統套件前確保套件索引可用：每次執行（含子行程）最多真正更新一次。
# 全新機器／容器沒有套件索引時，不先更新會讓所有 apt 套件安裝失敗。
# 更新失敗只警告，不中斷流程。
ensure_package_index_fresh() {
    if [ "${LINUX_SETTING_PKG_INDEX_CHECKED:-}" = "1" ]; then
        return 0
    fi
    export LINUX_SETTING_PKG_INDEX_CHECKED="1"

    if [ "${LINUX_SETTING_PKG_INDEX_UPDATED:-}" = "1" ]; then
        return 0
    fi

    if ! _pkg_index_needs_update; then
        log_info "套件索引仍然新鮮，略過更新"
        return 0
    fi

    log_info "套件索引不存在或已過舊，先更新一次"
    if ! update_system; then
        log_warning "套件索引更新失敗，後續套件安裝可能失敗；詳細原因請查看日誌"
        return 0
    fi
    return 0
}

# ==============================================================================
# Homebrew 包管理函數 (Linux)
# ==============================================================================

# 確保 Homebrew shell helper 已寫入 rc 檔
ensure_brew_shell_aliases() {
    local brew_bin="${1:-}"
    local rcfile=""
    local brew_prefix=""

    if [ -z "$brew_bin" ] && command -v brew >/dev/null 2>&1; then
        brew_bin="$(command -v brew)"
    fi

    if [ -z "$brew_bin" ]; then
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
    fi

    if [ -z "$brew_bin" ] || [ ! -x "$brew_bin" ]; then
        return 1
    fi

    brew_prefix="$(dirname "$(dirname "$brew_bin")")"

    for rcfile in "$HOME/.bashrc" "$HOME/.zshrc"; do
        # 既有 rc 檔一律更新；若是 zsh 使用者則允許建立 ~/.zshrc 來注入 brew helper。
        if [ -f "$rcfile" ] || { [ "$(basename "$rcfile")" = ".zshrc" ] && [ "${SHELL##*/}" = "zsh" ]; }; then
            if [ ! -f "$rcfile" ] && ! touch "$rcfile" 2>/dev/null; then
                log_warning "無法建立 $rcfile，略過 Homebrew helper 寫入"
                continue
            fi
            if ! grep -q "brew-on()" "$rcfile" 2>/dev/null; then
                cat >> "$rcfile" <<EOF

# ==============================================================================
# Homebrew 環境切換（預設不啟用，避免 Python 路徑衝突）
# ==============================================================================
# 使用 brew-on 啟用 Homebrew 環境
# 使用 brew-off 停用 Homebrew 環境
# ==============================================================================
brew-on() {
    eval "\$("$brew_bin" shellenv)"
    echo "Homebrew 環境已啟用"
}
brew-off() {
    export PATH=\$(echo "\$PATH" | sed 's|$brew_prefix/[^:]*:||g')
    unset HOMEBREW_PREFIX HOMEBREW_CELLAR HOMEBREW_REPOSITORY
    echo "Homebrew 環境已停用"
}
# 直接使用 brew 命令的 alias（不影響 PATH）
alias brew="$brew_bin"
EOF
                log_info "已添加 Homebrew alias 到 $rcfile"
            fi
        fi
    done

    return 0
}

# 確保 Homebrew 已安裝（Linux 上的 Homebrew/Linuxbrew）
ensure_homebrew_installed() {
    # 檢查是否已安裝 Homebrew
    if command -v brew >/dev/null 2>&1; then
        ensure_brew_shell_aliases "$(command -v brew)" || true
        log_success "Homebrew 已安裝: $(brew --version | head -n1)"
        return 0
    fi

    # 非互動 shell 下 PATH 不含 brew 時，檢查常見安裝路徑
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
    if [ -n "$brew_bin" ] && [ -x "$brew_bin" ]; then
        eval "$("$brew_bin" shellenv)" 2>/dev/null || {
            PATH="$(dirname "$brew_bin"):$PATH" || true
            export PATH
        }
        if command -v brew >/dev/null 2>&1; then
            ensure_brew_shell_aliases "$brew_bin" || true
            log_success "Homebrew 已安裝 (從 $brew_bin 注入 PATH): $(brew --version | head -n1)"
            return 0
        fi
    fi

    log_info "檢測到系統未安裝 Homebrew，開始安裝..."
    log_info "Homebrew 可以提供更新的軟體版本，並避免編譯耗時的工具"

    # 安裝 Homebrew 所需的依賴
    log_info "安裝 Homebrew 依賴項..."
    local brew_deps="build-essential procps curl file git"

    case "${PKG_MANAGER:-apt}" in
        apt)
            if [ "${TUI_MODE:-normal}" = "quiet" ]; then
                sudo DEBIAN_FRONTEND=noninteractive apt-get install -y $brew_deps >/dev/null 2>&1 || log_warning "部分依賴安裝失敗"
            else
                sudo DEBIAN_FRONTEND=noninteractive apt-get install -y $brew_deps || log_warning "部分依賴安裝失敗"
            fi
            ;;
        dnf|yum)
            sudo ${PKG_MANAGER} groupinstall -y 'Development Tools' || true
            sudo ${PKG_MANAGER} install -y procps-ng curl file git || true
            ;;
        pacman)
            sudo pacman -S --noconfirm base-devel procps-ng curl file git || true
            ;;
    esac

    # 下載並安裝 Homebrew
    log_info "下載並安裝 Homebrew（可能需要幾分鐘）..."

    # 使用官方安裝腳本（非互動模式）
    if NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
        log_success "Homebrew 安裝成功"

        local brew_shellenv=""
        if [ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
            brew_shellenv="/home/linuxbrew/.linuxbrew/bin/brew shellenv"
        elif [ -x "$HOME/.linuxbrew/bin/brew" ]; then
            brew_shellenv="$HOME/.linuxbrew/bin/brew shellenv"
        fi

        if [ -n "$brew_shellenv" ]; then
            # 載入到當前會話（僅供安裝時使用）
            eval "$($brew_shellenv)"
            ensure_brew_shell_aliases "$(command -v brew)" || true
            log_success "Homebrew 環境配置完成"
            log_info "已安裝版本：$(brew --version | head -n1)"
            log_info "使用 'brew-on' 啟用 Homebrew 環境，'brew-off' 停用"
            log_info "預設不啟用 Homebrew 環境，避免 Python 路徑衝突"
        else
            log_warning "找不到 Homebrew 安裝目錄，可能需要手動配置環境變量"
        fi

        return 0
    else
        log_error "Homebrew 安裝失敗"
        log_info "您可以稍後手動安裝：https://brew.sh"
        return 1
    fi
}

# 檢查 Homebrew 包是否已安裝
check_brew_package_installed() {
    local package="$1"

    if ! command -v brew >/dev/null 2>&1; then
        return 1
    fi

    # 使用 brew list 檢查包是否已安裝
    brew list "$package" >/dev/null 2>&1
}

# ==============================================================================
# 套件安裝狀態檢查函數
# ==============================================================================

# 檢查 pip/uv 套件是否已安裝
check_pip_package_installed() {
    local package="$1"

    # 優先檢查 uv tool
    if command -v uv >/dev/null 2>&1; then
        if uv tool list 2>/dev/null | grep -q "^$package "; then
            return 0
        fi
    fi

    # 檢查 pipx
    if command -v pipx >/dev/null 2>&1; then
        if pipx list 2>/dev/null | grep -q "package $package"; then
            return 0
        fi
    fi

    # 檢查 pip3
    if command -v pip3 >/dev/null 2>&1; then
        if pip3 show "$package" >/dev/null 2>&1; then
            return 0
        fi
    fi

    # 嘗試 import（針對 Python 模組）
    local import_name="${package//-/_}"  # 將 - 轉為 _
    if python3 -c "import $import_name" 2>/dev/null; then
        return 0
    fi

    return 1
}

# 檢查 cargo 套件是否已安裝
check_cargo_package_installed() {
    local package="$1"

    if ! command -v cargo >/dev/null 2>&1; then
        return 1
    fi

    # 使用 cargo install --list 檢查
    cargo install --list 2>/dev/null | grep -q "^$package v"
}

# 檢查 npm 全域套件是否已安裝
check_npm_package_installed() {
    local package="$1"

    if ! command -v npm >/dev/null 2>&1; then
        return 1
    fi

    # 使用 npm list -g 檢查
    npm list -g "$package" >/dev/null 2>&1
}

# 安裝單個 Homebrew 包
install_brew_package() {
    local package="$1"
    local force="${2:-false}"

    # 確保 Homebrew 已安裝
    if ! command -v brew >/dev/null 2>&1; then
        log_warning "Homebrew 未安裝，無法安裝 $package"
        return 1
    fi

    # 檢查是否已安裝
    if [ "$force" = "false" ] && check_brew_package_installed "$package"; then
        log_info "$package 已安裝 (brew)"
        return 0
    fi

    log_info "安裝 $package (使用 Homebrew)"

    # 根據 TUI_MODE 控制輸出詳細程度
    if [ "${TUI_MODE:-normal}" = "quiet" ]; then
        if brew install "$package" >/dev/null 2>&1; then
            log_success "$package 安裝成功 (brew)"
            return 0
        else
            log_error "$package 安裝失敗 (brew)"
            return 1
        fi
    else
        if brew install "$package"; then
            log_success "$package 安裝成功 (brew)"
            return 0
        else
            log_error "$package 安裝失敗 (brew)"
            return 1
        fi
    fi
}

# 批量安裝 Homebrew 包
install_brew_packages_batch() {
    local packages=("$@")
    local failed_packages=()

    # 確保 Homebrew 已安裝
    if ! command -v brew >/dev/null 2>&1; then
        log_error "Homebrew 未安裝，無法批量安裝套件"
        return 1
    fi

    # 過濾已安裝的包
    local to_install=()
    for pkg in "${packages[@]}"; do
        if check_brew_package_installed "$pkg" 2>/dev/null; then
            log_info "$pkg 已安裝，跳過 (brew)"
        else
            to_install+=("$pkg")
        fi
    done

    # 如果沒有需要安裝的包，直接返回
    if [ ${#to_install[@]} -eq 0 ]; then
        log_info "所有 Homebrew 包都已安裝"
        return 0
    fi

    log_info "批量安裝 ${#to_install[@]} 個 Homebrew 套件"

    # Homebrew 自身支持批量安裝，一次性安裝所有包
    if [ "${TUI_MODE:-normal}" = "quiet" ]; then
        if brew install "${to_install[@]}" >/dev/null 2>&1; then
            log_success "批量安裝成功 (brew)"
            return 0
        else
            # 批量安裝失敗，逐個重試
            log_warning "批量安裝失敗，嘗試逐個安裝..."
            for pkg in "${to_install[@]}"; do
                if ! install_brew_package "$pkg"; then
                    failed_packages+=("$pkg")
                fi
            done
        fi
    else
        if brew install "${to_install[@]}"; then
            log_success "批量安裝成功 (brew)"
            return 0
        else
            # 批量安裝失敗，逐個重試
            log_warning "批量安裝失敗，嘗試逐個安裝..."
            for pkg in "${to_install[@]}"; do
                if ! install_brew_package "$pkg"; then
                    failed_packages+=("$pkg")
                fi
            done
        fi
    fi

    # 報告失敗的包
    if [ ${#failed_packages[@]} -gt 0 ]; then
        log_warning "以下 Homebrew 包安裝失敗: ${failed_packages[*]}"
        return 1
    fi

    return 0
}

# 追加一筆安裝記錄到安裝清單（只追加、不重複）。
# 用法: manifest_record <package|path|file|backup> <值>
# 任何失敗都安靜略過，絕不影響安裝；--dry-run 不寫入。
manifest_record() {
    local kind="${1:-}" value="${2:-}"
    [ "${DRY_RUN:-false}" != "true" ] || return 0
    case "$kind" in package|path|file|backup) ;; *) return 0 ;; esac
    [ -n "$value" ] || return 0
    case "$value" in *$'\n'*|*$'\r'*) return 0 ;; esac
    case "$kind" in
        path|file|backup) case "$value" in /*) ;; *) return 0 ;; esac ;;
    esac
    local manifest="${INSTALL_MANIFEST_FILE:-}"
    [ -n "$manifest" ] || return 0
    (
        umask 077
        mkdir -p "$(dirname "$manifest")" || exit 0
        chmod 0700 "$(dirname "$manifest")" || true
        [ -f "$manifest" ] || : > "$manifest" || exit 0
        chmod 0600 "$manifest" || true
        if ! grep -qxF -- "$kind:$value" "$manifest"; then
            printf '%s:%s\n' "$kind" "$value" >> "$manifest"
        fi
    ) 2>/dev/null || true
    return 0
}

# ==============================================================================
# 文件操作函數
# ==============================================================================

backup_file() {
    local file="$1"
    local backup_dir="${2:-${BACKUP_DIR:-}}"
    
    if [ -f "$file" ] || [ -d "$file" ]; then
        local backup_name
        backup_name="$(basename "$file").backup.$(date +%Y%m%d_%H%M%S)"
        # 如果沒有預設備份目錄，使用 ~/.config/linux-setting-backup/<當前時間>
        if [ -z "$backup_dir" ]; then
            local ts
            ts="$(date +%Y%m%d_%H%M%S)"
            backup_dir="$HOME/.config/linux-setting-backup/$ts"
        fi
        mkdir -p "$backup_dir"
        chmod 0700 "$backup_dir" 2>/dev/null || true
        cp -r "$file" "$backup_dir/$backup_name"
        log_info "已備份 $file 到 $backup_dir/$backup_name"
        return 0
    else
        log_warning "文件不存在，跳過備份: $file"
        return 1
    fi
}

# 確保 npm 使用使用者層級 prefix（~/.npm-global），避免 `npm install -g` 因
# /usr/local/lib/node_modules 沒寫權限而 EACCES。
# 已正確設定（prefix 在 $HOME 下）就直接 return 0。
# 第一次設定時：建立 ~/.npm-global、寫入 npm config、注入 PATH，並 idempotent
# 寫一行到 ~/.bashrc / ~/.zshrc。
ensure_npm_user_prefix() {
    if ! command -v npm >/dev/null 2>&1; then
        return 1
    fi

    local current_prefix
    current_prefix=$(npm config get prefix 2>/dev/null || true)

    # 已經是使用者目錄底下就不動
    case "$current_prefix" in
        "$HOME"/*) export PATH="$current_prefix/bin:$PATH"; return 0 ;;
    esac

    local target="$HOME/.npm-global"
    log_info "設定 npm 使用者級 prefix → $target（避免需要 sudo）"
    mkdir -p "$target"

    if ! npm config set prefix "$target" 2>/dev/null; then
        log_warning "npm config set prefix 失敗"
        return 1
    fi

    export PATH="$target/bin:$PATH"

    # 寫一行 PATH 到 shell rc（idempotent）
    local rc_line='export PATH="$HOME/.npm-global/bin:$PATH"  # linux-setting:npm-prefix'
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [ -f "$rc" ] && ! grep -Fq 'linux-setting:npm-prefix' "$rc"; then
            printf '\n%s\n' "$rc_line" >> "$rc"
            log_debug "已注入 npm-prefix PATH 到 $rc"
        fi
    done

    return 0
}

# 統一判斷是否為非互動模式
# - NON_INTERACTIVE=true 環境變數
# - stdin 不是 tty（curl|bash、CI、cron 等）
# 任一條件成立即視為非互動。
is_non_interactive() {
    [ "${NON_INTERACTIVE:-false}" = "true" ] || [ ! -t 0 ]
}

# 互動安全 read
# 用法：safe_read <提示文字> <預設答案> <變數名> [read 額外參數...]
# 在非互動模式下不阻塞，直接把預設答案寫進指定變數並回 0
safe_read() {
    local prompt="$1"
    local default_value="$2"
    local var_name="$3"
    shift 3 || true

    if is_non_interactive; then
        printf -v "$var_name" '%s' "$default_value"
        log_debug "non-interactive: $var_name=$default_value (prompt='$prompt')"
        return 0
    fi

    # 互動模式：照常 read
    read ${1+"$@"} -p "$prompt" "${var_name?}"
}

safe_append_to_file() {
    local content="$1"
    local file="$2"
    local check_pattern="${3:-$content}"
    
    if [ ! -f "$file" ]; then
        echo "$content" > "$file"
        log_info "創建文件並添加內容: $file"
        return 0
    fi
    
    if ! grep -Fq "$check_pattern" "$file"; then
        echo "$content" >> "$file"
        log_info "添加內容到文件: $file"
        return 0
    else
        log_info "內容已存在，跳過: $file"
        return 0
    fi
}

# ==============================================================================
# 快取機制
# ==============================================================================

# 初始化快取系統
init_cache_system() {
    # CACHE_DIR 和 CACHE_TTL 已在檔案頂部定義為 readonly，這裡只設定 CACHE_ENABLED
    export CACHE_ENABLED="${CACHE_ENABLED:-true}"

    if [ "$CACHE_ENABLED" = "true" ]; then
        mkdir -p "$CACHE_DIR/downloads"
        mkdir -p "$CACHE_DIR/metadata"
        log_debug "快取系統已初始化: $CACHE_DIR"
    fi
}

# 檢查快取是否有效
is_cache_valid() {
    local cache_file="$1"
    local ttl="${2:-$CACHE_TTL}"
    
    if [ ! -f "$cache_file" ]; then
        return 1
    fi
    
    local file_age
    local current_time
    file_age=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)
    current_time=$(date +%s)
    
    if [ $((current_time - file_age)) -lt "$ttl" ]; then
        return 0
    else
        return 1
    fi
}

# 從快取獲取文件
get_from_cache() {
    local url="$1"
    local output="$2"
    
    if [ "$CACHE_ENABLED" != "true" ]; then
        return 1
    fi
    
    local cache_key
    cache_key=$(echo "$url" | sha256sum | cut -d' ' -f1)
    local cache_file="$CACHE_DIR/downloads/$cache_key"
    
    if is_cache_valid "$cache_file"; then
        cp "$cache_file" "$output"
        log_info "從快取獲取: $(basename "$output")"
        return 0
    else
        return 1
    fi
}

# 保存到快取
save_to_cache() {
    local url="$1"
    local file="$2"
    
    if [ "$CACHE_ENABLED" != "true" ] || [ ! -f "$file" ]; then
        return 1
    fi
    
    local cache_key
    cache_key=$(echo "$url" | sha256sum | cut -d' ' -f1)
    local cache_file="$CACHE_DIR/downloads/$cache_key"
    
    cp "$file" "$cache_file"
    echo "$url" > "$CACHE_DIR/metadata/$cache_key.url"
    log_debug "保存到快取: $cache_file"
}

# 清理過期快取
cleanup_cache() {
    if [ "$CACHE_ENABLED" != "true" ] || [ ! -d "$CACHE_DIR" ]; then
        return 0
    fi
    
    log_info "清理過期快取..."
    
    find "$CACHE_DIR/downloads" -type f -mtime +1 -exec rm -f {} \; 2>/dev/null
    find "$CACHE_DIR/metadata" -type f -mtime +1 -exec rm -f {} \; 2>/dev/null
    
    log_info "快取清理完成"
}

# ==============================================================================
# Security Functions
# ==============================================================================

# 驗證檔案的 SHA-256 是否與 checksums 清單（每行「sha256␠␠檔名」）中指定資產一致。
# 用法: verify_sha256_in_list <檔案> <checksums 檔> <資產檔名>
# 找不到該檔名、清單格式不合或無法計算雜湊都視為失敗（回傳 1）。
verify_sha256_in_list() {
    local file="${1:-}" list="${2:-}" asset="${3:-}"
    [ -f "$file" ] && [ -f "$list" ] && [ -n "$asset" ] || return 1

    local expected
    expected=$(awk -v name="$asset" '
        { n = $2; sub(/^\*/, "", n) }
        n == name && $1 ~ /^[0-9A-Fa-f]{64}$/ { print tolower($1); exit }
    ' "$list" 2>/dev/null) || return 1
    [ -n "$expected" ] || return 1

    local actual=""
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$file" 2>/dev/null) || return 1
    elif command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 256 "$file" 2>/dev/null) || return 1
    else
        return 1
    fi
    actual="${actual%% *}"
    actual=$(printf '%s' "$actual" | tr '[:upper:]' '[:lower:]')
    [ -n "$actual" ] && [ "$actual" = "$expected" ]
}

# ==============================================================================
# Download Functions
# ==============================================================================

safe_download() {
    local url="$1"
    local output="$2"
    local max_retries="${3:-$DOWNLOAD_RETRIES}"
    local use_cache="${4:-true}"

    log_debug "Downloading: $url"

    # Try to get from cache first
    if [ "$use_cache" = "true" ] && [ "$CACHE_ENABLED" = "true" ]; then
        if get_from_cache "$url" "$output"; then
            log_debug "Retrieved from cache"
            return 0
        fi
    fi

    # Download with retries（只做大小上限與重試；內容是否可信取決於來源與 TLS）
    local retry=0
    local temp_output
    temp_output="${output}.tmp.$$"

    # https 網址：跟隨轉址時也只允許 https；本機測試用的 http://127.0.0.1 不加限制
    local proto_opts=()
    case "$url" in
        https://*) proto_opts=(--proto '=https' --proto-redir '=https') ;;
    esac

    while [ $retry -lt $max_retries ]; do
        if curl -fsSL ${proto_opts[@]+"${proto_opts[@]}"} \
            --max-time "$DOWNLOAD_TIMEOUT" \
            --connect-timeout "${CONNECTION_TIMEOUT:-10}" \
            --max-filesize "$MAX_SCRIPT_SIZE" \
            "$url" -o "$temp_output" 2>/dev/null; then

            # --max-filesize 在伺服器未提供長度時不一定生效，下載後再檢查一次
            local file_size
            file_size=$(stat -c%s "$temp_output" 2>/dev/null || stat -f%z "$temp_output" 2>/dev/null || echo 0)
            if [ "$file_size" -gt "$MAX_SCRIPT_SIZE" ]; then
                rm -f "$temp_output"
                log_error "Download too large: $file_size bytes (max: $MAX_SCRIPT_SIZE)"
                return 1
            fi

            mv "$temp_output" "$output"

            # Save to cache
            if [ "$use_cache" = "true" ] && [ "$CACHE_ENABLED" = "true" ]; then
                save_to_cache "$url" "$output"
            fi

            log_success "Download successful: $(basename "$output")"
            return 0
        else
            rm -f "$temp_output"
            retry=$((retry + 1))
            log_debug "Download failed, retry $retry/$max_retries: $url"
            sleep $((retry * 2))  # Exponential backoff
        fi
    done

    log_error "Download failed after $max_retries attempts: $url"
    return 1
}

# ==============================================================================
# APT 優化函數
# ==============================================================================

# 優化 APT 配置以提高性能
# 會用 sudo 在 /etc/apt/apt.conf.d/ 新增三個設定檔；--dry-run 時絕不執行。
# 這次新建立的檔案會記入安裝清單，卸載時移除。
optimize_apt_performance() {
    if [ "${DRY_RUN:-false}" = "true" ]; then
        log_info "--dry-run：略過 APT 性能配置"
        return 0
    fi
    log_info "優化 APT 性能配置..."
    
    # 創建 APT 配置目錄
    sudo mkdir -p /etc/apt/apt.conf.d/
    
    # 配置並行下載
    local apt_config="/etc/apt/apt.conf.d/99-parallel-downloads"
    if [ ! -f "$apt_config" ]; then
        sudo tee "$apt_config" > /dev/null << 'EOF'
# 並行下載配置
Acquire::Queue-Mode "host";
Acquire::http::Dl-Limit "1000";
APT::Acquire::Max-Default-Sec "10";
Acquire::Retries "3";
EOF
        log_success "APT 並行下載配置已啟用"
        manifest_record path "$apt_config"
    fi
    
    # 配置快取優化
    local cache_config="/etc/apt/apt.conf.d/99-cache-optimization"
    if [ ! -f "$cache_config" ]; then
        sudo tee "$cache_config" > /dev/null << 'EOF'
# 快取優化配置
Dir::Cache::pkgcache "";
Dir::Cache::srcpkgcache "";
APT::Cache-Start "32505856";
APT::Cache-Grow "2097152";
APT::Cache-Limit "134217728";
EOF
        log_success "APT 快取優化配置已啟用"
        manifest_record path "$cache_config"
    fi
    
    # 配置網絡超時
    local timeout_config="/etc/apt/apt.conf.d/99-timeout"
    if [ ! -f "$timeout_config" ]; then
        sudo tee "$timeout_config" > /dev/null << 'EOF'
# 網絡超時配置
Acquire::http::Timeout "10";
Acquire::https::Timeout "10";
Acquire::ftp::Timeout "10";
EOF
        log_success "APT 網絡超時配置已啟用"
        manifest_record path "$timeout_config"
    fi
    
    log_success "APT 性能優化配置完成"
}

# 清理 APT 快取和無用套件
cleanup_apt_system() {
    log_info "清理 APT 系統..."
    
    # 清理套件快取
    sudo DEBIAN_FRONTEND=noninteractive apt-get autoclean

    # 移除不需要的套件
    sudo DEBIAN_FRONTEND=noninteractive apt-get autoremove -y

    # 清理孤立套件
    if check_command deborphan; then
        local orphaned
        orphaned=$(deborphan)
        if [ -n "$orphaned" ]; then
            echo "$orphaned" | sudo xargs DEBIAN_FRONTEND=noninteractive apt-get remove -y
            log_info "已清理孤立套件"
        fi
    fi
    
    log_success "APT 系統清理完成"
}

# 選擇最快的 APT 鏡像源
select_fastest_apt_mirror() {
    local country="${1:-auto}"
    
    if ! check_command apt-fast; then
        log_info "安裝 apt-fast 以提高下載速度..."
        if [ ! -f "/etc/apt/sources.list.d/apt-fast.list" ]; then
            sudo add-apt-repository ppa:apt-fast/stable -y
            sudo DEBIAN_FRONTEND=noninteractive apt-get update
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y apt-fast
        fi
    fi
    
    log_info "配置最快的鏡像源..."
    
    # 根據地區選擇鏡像源
    case "$country" in
        "china"|"cn")
            local mirrors=(
                "https://mirrors.tuna.tsinghua.edu.cn/ubuntu/"
                "https://mirrors.ustc.edu.cn/ubuntu/"
                "https://mirrors.aliyun.com/ubuntu/"
            )
            ;;
        "us")
            local mirrors=(
                "http://archive.ubuntu.com/ubuntu/"
                "http://us.archive.ubuntu.com/ubuntu/"
            )
            ;;
        *)
            # 自動檢測最快鏡像
            local mirrors=(
                "http://archive.ubuntu.com/ubuntu/"
                "https://mirrors.tuna.tsinghua.edu.cn/ubuntu/"
                "https://mirrors.ustc.edu.cn/ubuntu/"
            )
            ;;
    esac
    
    local fastest_mirror=""
    local best_time=999
    
    for mirror in "${mirrors[@]}"; do
        local response_time
        response_time=$(curl -o /dev/null -s -w "%{time_total}" --max-time 5 "$mirror" 2>/dev/null || echo "999")
        
        if [ "$response_time" != "999" ] && [ "$(awk "BEGIN {print ($response_time < $best_time)}" )" = "1" ]; then
            best_time="$response_time"
            fastest_mirror="$mirror"
        fi
    done
    
    if [ -n "$fastest_mirror" ]; then
        log_success "選擇最快鏡像源: $fastest_mirror (響應時間: ${best_time}s)"
        echo "$fastest_mirror"
    else
        log_warning "無法檢測最快鏡像源，使用預設值"
        echo "http://archive.ubuntu.com/ubuntu/"
    fi
}

# ==============================================================================
# 鏡像源管理
# ==============================================================================

get_best_mirror() {
    local mirrors=(
        "https://pypi.org/simple/"
        "https://pypi.tuna.tsinghua.edu.cn/simple/"
        "https://pypi.douban.com/simple/"
        "https://mirrors.aliyun.com/pypi/simple/"
    )
    
    local best_mirror=""
    local best_speed=0
    
    for mirror in "${mirrors[@]}"; do
        local speed
        speed=$(curl -o /dev/null -s -w "%{time_total}" --max-time 5 "$mirror" 2>/dev/null || echo "999")
        
        if [ "$speed" != "999" ] && ([ "$best_speed" = "0" ] || [ "$(awk "BEGIN {print ($speed < $best_speed)}" )" = "1" ]); then
            best_speed="$speed"
            best_mirror="$mirror"
        fi
    done
    
    echo "${best_mirror:-https://pypi.org/simple/}"
}

# ==============================================================================
# 版本比較函數
# ==============================================================================

version_greater_equal() {
    local version1="$1"
    local version2="$2"
    [ "$(printf '%s\n' "$version1" "$version2" | sort -V | tail -n1)" = "$version1" ]
}

# 檢查系統架構兼容性
check_architecture_compatibility() {
    local arch
    arch=$(uname -m)
    
    case "$arch" in
        x86_64|amd64)
            log_info "檢測到 x86_64 架構，完全支援"
            return 0
            ;;
        aarch64|arm64)
            log_warning "檢測到 ARM64 架構，部分工具可能需要特殊處理"
            export ARCH_ARM64=true
            return 0
            ;;
        armv7l)
            log_warning "檢測到 ARMv7 架構，兼容性有限"
            export ARCH_ARM32=true
            return 0
            ;;
        *)
            log_error "不支援的架構: $arch"
            return 1
            ;;
    esac
}

# 架構特定的包安裝
install_arch_specific_package() {
    local package="$1"
    local arch
    arch=$(uname -m)
    
    case "$arch" in
        aarch64|arm64)
            # ARM64 特定處理
            case "$package" in
                "docker-ce")
                    log_info "ARM64: 安裝 Docker"
                    if [ -f "$SCRIPT_DIR/../utils/secure_download.sh" ]; then
                        bash "$SCRIPT_DIR/../utils/secure_download.sh" docker
                    elif [ -f "$SCRIPT_DIR/utils/secure_download.sh" ]; then
                        bash "$SCRIPT_DIR/utils/secure_download.sh" docker
                    elif [ -f "$SCRIPT_DIR/secure_download.sh" ]; then
                        bash "$SCRIPT_DIR/secure_download.sh" docker
                    else
                        log_warning "找不到安全下載腳本，請手動安裝 Docker"
                        log_error "為了安全起見，不執行遠程腳本安裝"
                        return 1
                    fi
                    return $?
                    ;;
                *)
                    install_apt_package "$package"
                    return $?
                    ;;
            esac
            ;;
        *)
            install_apt_package "$package"
            return $?
            ;;
    esac
}

# ==============================================================================
# TUI (Text User Interface) 函數
# ==============================================================================

# 全局變數：控制是否使用 TUI
USE_TUI="${USE_TUI:-auto}"  # auto/true/false
TUI_BACKEND="${TUI_BACKEND:-auto}"  # auto/gum/fzf/whiptail

_set_tui_backend() {
    export USE_TUI="true"
    export TUI_BACKEND="$1"
}

_select_tui_backend() {
    case "${TUI_BACKEND:-auto}" in
        gum)
            command -v gum >/dev/null 2>&1 && _set_tui_backend "gum" && return 0
            return 1
            ;;
        fzf)
            command -v fzf >/dev/null 2>&1 && _set_tui_backend "fzf" && return 0
            return 1
            ;;
        whiptail)
            command -v whiptail >/dev/null 2>&1 && _set_tui_backend "whiptail" && return 0
            return 1
            ;;
        auto|"")
            if command -v gum >/dev/null 2>&1; then
                _set_tui_backend "gum"
                return 0
            fi
            if command -v fzf >/dev/null 2>&1; then
                _set_tui_backend "fzf"
                return 0
            fi
            if command -v whiptail >/dev/null 2>&1; then
                TUI_BACKEND="whiptail"
                _set_tui_backend "whiptail"
                return 0
            fi
            return 1
            ;;
        *)
            log_warning "未知 TUI_BACKEND=${TUI_BACKEND}，改用自動偵測"
            TUI_BACKEND="auto"
            _select_tui_backend
            ;;
    esac
}

_tui_backend_supports_state_checklist() {
    [ "${TUI_BACKEND:-whiptail}" = "whiptail" ]
}

_tui_emit_tags_from_tsv() {
    local line
    local out=""
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        out="$out ${line%%	*}"
    done
    echo "${out# }"
}

_log_tui_backend_hint() {
    [ "${TUI_BACKEND_HINT_SHOWN:-false}" = "true" ] && return 0
    export TUI_BACKEND_HINT_SHOWN="true"

    if ! command -v fzf >/dev/null 2>&1 && ! command -v gum >/dev/null 2>&1; then
        log_info "提示：安裝 fzf 或 gum 可使用更順手的互動選單；可用 TUI_BACKEND=fzf ./install.sh 或 TUI_BACKEND=gum ./install.sh 指定"
    fi
}

# 僅判斷實際尺寸，不套用對話框尺寸的預設值。
_tui_terminal_too_small() {
    local rows="${1:-}" cols="${2:-}"
    case "$rows" in ''|*[!0-9]*) return 1 ;; esac
    case "$cols" in ''|*[!0-9]*) return 1 ;; esac
    [ "$rows" -lt 15 ] || [ "$cols" -lt 50 ]
}

# 檢測並確保 TUI backend 可用
ensure_tui_available() {
    # 如果明確禁用 TUI，直接返回失敗
    if [ "$USE_TUI" = "false" ]; then
        return 1
    fi

    local actual_size rows cols
    if actual_size=$(stty size 2>/dev/null </dev/tty); then
        read -r rows cols <<< "$actual_size"
        if _tui_terminal_too_small "$rows" "$cols"; then
            log_info "終端機太小（實際尺寸：${rows} 列 × ${cols} 欄），改用命令行模式"
            export USE_TUI=false
            return 1
        fi
    fi

    local requested_backend="${TUI_BACKEND:-auto}"
    if _select_tui_backend; then
        log_debug "啟用 TUI backend: $TUI_BACKEND"
        if [ "$requested_backend" = "auto" ] && [ "$TUI_BACKEND" = "whiptail" ]; then
            _log_tui_backend_hint
        fi
        return 0
    fi

    # 嘗試安裝 whiptail（通常在 newt 包中）作為保守 fallback
    log_info "檢測到 whiptail 未安裝，嘗試安裝..."
    if [ "${TUI_BACKEND:-auto}" != "gum" ] && [ "${TUI_BACKEND:-auto}" != "fzf" ] && [ "$DISTRO_FAMILY" = "debian" ]; then
        if install_package "whiptail" 2>/dev/null || install_package "newt" 2>/dev/null; then
            if command -v whiptail >/dev/null 2>&1; then
                log_success "whiptail 安裝成功，啟用 TUI 模式"
                TUI_BACKEND="whiptail"
                _set_tui_backend "whiptail"
                return 0
            fi
        fi
    fi

    # 如果是 auto 模式且安裝失敗，降級到命令行
    if [ "$USE_TUI" = "auto" ]; then
        log_info "TUI 不可用，使用命令行模式"
        _log_tui_backend_hint
        export USE_TUI="false"
        return 1
    fi

    # 明確要求 TUI 但不可用
    log_warning "TUI 模式不可用，降級到命令行模式"
    _log_tui_backend_hint
    export USE_TUI="false"
    return 1
}

# ==============================================================================
# TUI 對話框尺寸計算
# ==============================================================================

# 展開提示文字中的跳脫序列（呼叫端以 \n 表示換行；whiptail 會自行解讀，
# fzf / gum 不會，因此統一先展開再交給各 backend）
_tui_expand_text() {
    printf '%b' "${1:-}"
}

# 估算單行文字的顯示寬度（欄數）。中文等多位元組字元為雙寬，
# 以「非 ASCII 字元一律視為 3 bytes、寬度 2」保守估計（寧可略寬、不可被截斷）。
_tui_display_width() {
    local s="${1:-}"
    local chars=${#s}
    local bytes
    bytes=$(LC_ALL=C; printf '%s' "${#s}")
    if [ "$bytes" -le "$chars" ] 2>/dev/null; then
        echo "$chars"
    else
        echo $((chars + (bytes - chars) / 2))
    fi
}

# 取得多個字串中最大的顯示寬度
_tui_max_display_width() {
    local max=0 w item
    for item in "$@"; do
        w=$(_tui_display_width "$item")
        [ "$w" -gt "$max" ] && max=$w || true
    done
    echo "$max"
}

# 取得終端機實際大小，輸出「列數 欄數」。
# 優先序：TUI_TERM_ROWS/TUI_TERM_COLS（測試／覆寫用）> stty > tput > LINES/COLUMNS > 24x80
_tui_term_size() {
    local rows="${TUI_TERM_ROWS:-}"
    local cols="${TUI_TERM_COLS:-}"
    local sz=""

    if [ -z "$rows" ] || [ -z "$cols" ]; then
        sz=$(stty size 2>/dev/null </dev/tty) || sz=""
        if [ -n "$sz" ]; then
            [ -n "$rows" ] || rows="${sz% *}"
            [ -n "$cols" ] || cols="${sz#* }"
        fi
    fi
    if [ -z "$rows" ] || [ -z "$cols" ]; then
        [ -n "$rows" ] || rows=$(tput lines 2>/dev/null </dev/tty || true)
        [ -n "$cols" ] || cols=$(tput cols 2>/dev/null </dev/tty || true)
    fi
    [ -n "$rows" ] || rows="${LINES:-}"
    [ -n "$cols" ] || cols="${COLUMNS:-}"

    case "$rows" in ''|*[!0-9]*) rows=24 ;; esac
    case "$cols" in ''|*[!0-9]*) cols=80 ;; esac
    [ "$rows" -ge 10 ] || rows=24
    [ "$cols" -ge 30 ] || cols=80
    echo "$rows $cols"
}

# 計算對話框尺寸，輸出「height width list_height scroll」
# 用法：_tui_dialog_size <yesno|msgbox|menu|checklist> <提示文字> [項目數] [項目內容寬度] [標題寬度]
#   - 依訊息行數、長行折行後的行數、以及終端機實際列數/欄數上限計算
#   - 內容超過終端機高度時 scroll=1（yesno/msgbox 應加 --scrolltext）
#   - menu/checklist 至少保留 3 個清單列（項目少於 3 個則全部保留），提示文字過長時才截短
_tui_dialog_size() {
    local kind="${1:-yesno}"
    local text
    text=$(_tui_expand_text "${2:-}")
    local item_count="${3:-0}"
    local content_w="${4:-0}"
    local title_w="${5:-0}"

    local rows cols
    read -r rows cols <<< "$(_tui_term_size)"

    local min_w
    case "$kind" in
        yesno) min_w=60 ;;
        menu) min_w=70 ;;
        msgbox) min_w=76 ;;
        checklist) min_w=78 ;;
        *) min_w=60 ;;
    esac

    local max_w=$((cols - 4))
    [ "$max_w" -gt 120 ] && max_w=120 || true
    [ "$max_w" -lt 30 ] && max_w=30 || true
    local max_h=$((rows - 2))

    # 最長一行的顯示寬度
    local longest=0 w line
    while IFS= read -r line || [ -n "$line" ]; do
        w=$(_tui_display_width "$line")
        [ "$w" -gt "$longest" ] && longest=$w || true
    done <<< "$text"

    local width=$longest
    [ "$content_w" -gt "$width" ] && width=$content_w || true
    width=$((width + 8))
    [ $((title_w + 8)) -gt "$width" ] && width=$((title_w + 8)) || true
    [ "$width" -lt "$min_w" ] && width=$min_w || true
    [ "$width" -gt "$max_w" ] && width=$max_w || true

    # 折行後的實際行數（whiptail 文字區約為 width - 6）
    local text_w=$((width - 6))
    [ "$text_w" -lt 10 ] && text_w=10 || true
    local text_rows=0
    while IFS= read -r line || [ -n "$line" ]; do
        w=$(_tui_display_width "$line")
        if [ "$w" -le "$text_w" ]; then
            text_rows=$((text_rows + 1))
        else
            text_rows=$((text_rows + (w + text_w - 1) / text_w))
        fi
    done <<< "$text"
    [ "$text_rows" -lt 1 ] && text_rows=1 || true

    local height list_height=0 scroll=0
    case "$kind" in
        menu|checklist)
            local min_list=$item_count
            [ "$min_list" -gt 3 ] && min_list=3 || true
            # 提示文字過長時截短，確保清單至少保留 min_list 列
            local text_cap=$((max_h - 7 - min_list))
            [ "$text_cap" -lt 1 ] && text_cap=1 || true
            [ "$text_rows" -gt "$text_cap" ] && text_rows=$text_cap || true
            list_height=$((max_h - text_rows - 7))
            [ "$list_height" -gt "$item_count" ] && list_height=$item_count || true
            [ "$list_height" -lt "$min_list" ] && list_height=$min_list || true
            height=$((text_rows + list_height + 7))
            ;;
        *)
            height=$((text_rows + 7))
            [ "$height" -lt 9 ] && height=9 || true
            if [ "$height" -gt "$max_h" ]; then
                height=$max_h
                scroll=1
            fi
            ;;
    esac

    echo "$height $width $list_height $scroll"
}

# 提示文字加上全部 item_count 個選項，能否完整放進同一個選單（不必截短提示文字或捲動清單）。
# 用法：_tui_menu_fits_text <提示文字> <選項數> [項目內容寬度] [標題寬度]
# 版面與 _tui_dialog_size 的 menu 計算一致：文字列數 + 選項數 + 7（邊框、按鈕與空白）<= 終端機列數 - 2
_tui_menu_fits_text() {
    local text
    text=$(_tui_expand_text "${1:-}")
    local item_count="${2:-0}"
    local content_w="${3:-0}"
    local title_w="${4:-0}"

    local rows cols
    read -r rows cols <<< "$(_tui_term_size)"

    local max_w=$((cols - 4))
    [ "$max_w" -gt 120 ] && max_w=120 || true
    [ "$max_w" -lt 30 ] && max_w=30 || true

    local longest=0 w line
    while IFS= read -r line || [ -n "$line" ]; do
        w=$(_tui_display_width "$line")
        [ "$w" -gt "$longest" ] && longest=$w || true
    done <<< "$text"

    local width=$longest
    [ "$content_w" -gt "$width" ] && width=$content_w || true
    width=$((width + 8))
    [ $((title_w + 8)) -gt "$width" ] && width=$((title_w + 8)) || true
    [ "$width" -lt 70 ] && width=70 || true
    [ "$width" -gt "$max_w" ] && width=$max_w || true

    local text_w=$((width - 6))
    [ "$text_w" -lt 10 ] && text_w=10 || true
    local text_rows=0
    while IFS= read -r line || [ -n "$line" ]; do
        w=$(_tui_display_width "$line")
        if [ "$w" -le "$text_w" ]; then
            text_rows=$((text_rows + 1))
        else
            text_rows=$((text_rows + (w + text_w - 1) / text_w))
        fi
    done <<< "$text"

    [ $((text_rows + item_count + 7)) -le $((rows - 2)) ]
}

# fzf 用的高度（行數）：依提示文字行數估算，不超過終端機高度
_tui_fzf_height() {
    local text
    text=$(_tui_expand_text "${1:-}")
    local extra="${2:-6}"
    local rows cols
    read -r rows cols <<< "$(_tui_term_size)"
    local n
    n=$(printf '%s\n' "$text" | wc -l)
    n=$((n + extra))
    [ "$n" -gt $((rows - 1)) ] && n=$((rows - 1)) || true
    echo "$n"
}

# TUI 多選菜單（返回選中的 tag，以空白分隔）
# 參數：title prompt tag1 item1 tag2 item2 ...
# tag 必須為單一「模組 id」等無空白字元；描述可含空白（顯示在第二欄），否則 whiptail 回傳含空白的 tag 會被 shell 拆字而無法還原。
tui_checklist() {
    local title="$1"
    local prompt="$2"
    shift 2
    local items=("$@")

    # 檢查 TUI 是否可用
    if [ "$USE_TUI" != "true" ]; then
        return 1
    fi

    local n=${#items[@]}
    if [ $((n % 2)) -ne 0 ]; then
        log_error "tui_checklist: 參數須為偶數（tag 與描述須成對），目前 $n 個"
        return 1
    fi

    if [ "${TUI_BACKEND:-whiptail}" = "gum" ]; then
        local gum_items=()
        local gi=0
        while [ "$gi" -lt "$n" ]; do
            gum_items+=("${items[$gi]}	${items[$((gi + 1))]}")
            gi=$((gi + 2))
        done
        local gum_result
        printf '%s\n%b\n' "$title" "$prompt" >&2
        gum_result=$(printf '%s\n' "${gum_items[@]}" | gum choose --no-limit) || return 1
        _tui_emit_tags_from_tsv <<< "$gum_result"
        return 0
    fi

    if [ "${TUI_BACKEND:-whiptail}" = "fzf" ]; then
        local fzf_input=""
        local fi=0
        while [ "$fi" -lt "$n" ]; do
            fzf_input="${fzf_input}${items[$fi]}	${items[$((fi + 1))]}"$'\n'
            fi=$((fi + 2))
        done
        local fzf_result
        local fzf_header
        fzf_header="$(_tui_expand_text "$prompt")"$'\n'"Space 勾選/取消；Tab 多選；Enter 確認；Esc 取消"
        fzf_result=$(printf '%s' "$fzf_input" | fzf --multi --layout=reverse \
            --delimiter=$'\t' --with-nth=2.. \
            --bind=space:toggle --marker="✓ " \
            --height=80% --border --prompt="$title> " --header="$fzf_header") || return 1
        _tui_emit_tags_from_tsv <<< "$fzf_result"
        return 0
    fi

    # 構建 whiptail checklist 參數：每列 tag / item / status
    local checklist_args=()
    local default_state="ON"  # 預設全部選中
    local i=0
    while [ "$i" -lt "$n" ]; do
        checklist_args+=("${items[$i]}" "${items[$((i + 1))]}" "$default_state")
        i=$((i + 2))
    done

    local item_count=$((n / 2))
    # 計算窗口大小：依提示文字行數、長行折行與終端機實際大小
    local ci cw=0 w
    for ((ci = 0; ci < n; ci += 2)); do
        w=$(( $(_tui_display_width "${items[$ci]}") + $(_tui_display_width "${items[$((ci + 1))]}") + 8 ))
        [ "$w" -gt "$cw" ] && cw=$w || true
    done
    local height width list_height _scroll
    read -r height width list_height _scroll <<< "$(_tui_dialog_size checklist "$prompt" "$item_count" "$cw" "$(_tui_display_width "$title")")"
    local text
    text=$(_tui_expand_text "$prompt")

    # 顯示 checklist 並捕獲結果
    local result
    result=$(whiptail --title "$title" --checklist "$text" $height $width $list_height "${checklist_args[@]}" 3>&1 1>&2 2>&3)
    local exit_code=$?

    # 返回選中的項目（去除引號）
    if [ $exit_code -eq 0 ]; then
        echo "$result" | tr -d '"'
        return 0
    else
        return 1
    fi
}

# TUI 多選 checklist（每個項目可指定預設 ON / OFF / 文字描述）
# 用法：
#   tui_checklist_with_state "標題" "提示文字" \
#       tag1 "描述1" ON \
#       tag2 "描述2" OFF \
#       ...
# 回傳 stdout：使用者選中的 tag（用空白分隔），return 0
# 使用者取消 / 按 ESC：return 1
tui_checklist_with_state() {
    local title="$1"
    local prompt="$2"
    shift 2

    if [ "$USE_TUI" != "true" ]; then
        return 1
    fi

    # 收集 tag/description/state 為 whiptail 所需的位置參數
    local checklist_args=()
    local item_count=0
    while [ $# -ge 3 ]; do
        checklist_args+=("$1" "$2" "$3")
        item_count=$((item_count + 1))
        shift 3
    done

    if [ "$item_count" -eq 0 ]; then
        return 1
    fi

    if ! _tui_backend_supports_state_checklist; then
        return 1
    fi

    local ci cw=0 w
    local -a _cl=("${checklist_args[@]}")
    for ((ci = 0; ci < ${#_cl[@]}; ci += 3)); do
        w=$(( $(_tui_display_width "${_cl[$ci]}") + $(_tui_display_width "${_cl[$((ci + 1))]}") + 8 ))
        [ "$w" -gt "$cw" ] && cw=$w || true
    done
    local height width list_height _scroll
    read -r height width list_height _scroll <<< "$(_tui_dialog_size checklist "$prompt" "$item_count" "$cw" "$(_tui_display_width "$title")")"
    local text
    text=$(_tui_expand_text "$prompt")

    local result
    result=$(whiptail --title "$title" --checklist "$text" \
        $height $width $list_height "${checklist_args[@]}" 3>&1 1>&2 2>&3)
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo "$result" | tr -d '"'
        return 0
    fi
    return 1
}

# TUI 單選菜單（返回選中的項目）
tui_menu() {
    local title="$1"
    local prompt="$2"
    shift 2
    local items=("$@")

    # 檢查 TUI 是否可用
    if [ "$USE_TUI" != "true" ]; then
        return 1
    fi

    # 構建 whiptail menu 參數
    local menu_args=()
    local index=1

    for item in "${items[@]}"; do
        menu_args+=("$index" "$item")
        index=$((index + 1))
    done

    if [ "${TUI_BACKEND:-whiptail}" = "gum" ]; then
        local gum_result
        printf '%b\n' "$prompt" >&2
        gum_result=$(gum choose "${items[@]}") || return 1
        [ -n "$gum_result" ] && echo "$gum_result" && return 0
        return 1
    fi

    if [ "${TUI_BACKEND:-whiptail}" = "fzf" ]; then
        local fzf_result fzf_header
        fzf_header="$(_tui_expand_text "$prompt")"
        fzf_result=$(printf '%s\n' "${items[@]}" | fzf --height="$(_tui_fzf_height "$prompt" $((${#items[@]} + 5)))" --border --layout=reverse \
            --prompt="$title> " --header="$fzf_header") || return 1
        [ -n "$fzf_result" ] && echo "$fzf_result" && return 0
        return 1
    fi

    # 計算窗口大小：提示文字行數（含長行折行）+ 項目數，受終端機實際大小限制
    local item_w
    item_w=$(( $(_tui_max_display_width "${items[@]}") + 10 ))
    local height width list_height _scroll
    read -r height width list_height _scroll <<< "$(_tui_dialog_size menu "$prompt" "${#items[@]}" "$item_w" "$(_tui_display_width "$title")")"
    local text
    text=$(_tui_expand_text "$prompt")

    # 顯示 menu 並捕獲結果
    local result
    result=$(whiptail --title "$title" --menu "$text" $height $width $list_height "${menu_args[@]}" 3>&1 1>&2 2>&3)
    local exit_code=$?

    # 返回選中項目的文本（而不是索引）
    if [ $exit_code -eq 0 ] && [ -n "$result" ]; then
        echo "${items[$((result - 1))]}"
        return 0
    else
        return 1
    fi
}

# TUI 是/否對話框
tui_yesno() {
    local title="$1"
    local prompt="$2"
    local default="${3:-no}"  # yes/no

    # 檢查 TUI 是否可用
    if [ "$USE_TUI" != "true" ]; then
        return 1
    fi

    # 設置預設按鈕
    local defaultno=""
    [ "$default" = "no" ] && defaultno="--defaultno" || true

    local text
    text=$(_tui_expand_text "$prompt")

    if [ "${TUI_BACKEND:-whiptail}" = "gum" ]; then
        if [ "$default" = "yes" ]; then
            gum confirm "$text" --default=true
        else
            gum confirm "$text" --default=false
        fi
        return $?
    fi

    if [ "${TUI_BACKEND:-whiptail}" = "fzf" ]; then
        local fzf_result fzf_h
        fzf_h="$(_tui_fzf_height "$prompt" 6)"
        if [ "$default" = "yes" ]; then
            fzf_result=$(printf "Yes\nNo\n" | fzf --height="$fzf_h" --border --layout=reverse --prompt="$title> " --header="$text") || return 1
        else
            fzf_result=$(printf "No\nYes\n" | fzf --height="$fzf_h" --border --layout=reverse --prompt="$title> " --header="$text") || return 1
        fi
        [ "$fzf_result" = "Yes" ]
        return $?
    fi

    # 計算窗口大小：依內容行數、長行折行與終端機大小；超出時啟用捲動
    local height width list_height scroll
    read -r height width list_height scroll <<< "$(_tui_dialog_size yesno "$prompt" 0 0 "$(_tui_display_width "$title")")"
    local scroll_opt=()
    if [ "$scroll" = "1" ]; then
        # 可捲動時焦點在文字區，直接按 Enter 不會觸發按鈕；在標題提示操作方式
        scroll_opt=(--scrolltext)
        title="$title（↑↓ 捲動，Tab 切到按鈕）"
    fi

    # 顯示 yesno 對話框
    if whiptail --title "$title" $defaultno ${scroll_opt[@]+"${scroll_opt[@]}"} --yesno "$text" $height $width 3>&1 1>&2 2>&3; then
        return 0  # Yes
    else
        return 1  # No
    fi
}

# TUI 信息框
tui_msgbox() {
    local title="$1"
    local message="$2"

    # 檢查 TUI 是否可用
    if [ "$USE_TUI" != "true" ]; then
        return 1
    fi

    if [ "${TUI_BACKEND:-whiptail}" = "gum" ]; then
        printf '%b\n' "$message" | gum pager
        return $?
    fi

    if [ "${TUI_BACKEND:-whiptail}" = "fzf" ]; then
        if [ -t 0 ]; then
            printf '%b\n' "$message" | fzf --height=80% --border --layout=reverse --prompt="$title> " --header="Enter 返回"
        else
            printf '%b\n' "$message"
        fi
        return 0
    fi

    # 依內容行數、長行折行與終端機大小調整；超出時啟用捲動
    local height width list_height scroll
    read -r height width list_height scroll <<< "$(_tui_dialog_size msgbox "$message" 0 0 "$(_tui_display_width "$title")")"
    local scroll_opt=()
    if [ "$scroll" = "1" ]; then
        # 可捲動時焦點在文字區，直接按 Enter 不會觸發按鈕；在標題提示操作方式
        scroll_opt=(--scrolltext)
        title="$title（↑↓ 捲動，Tab 切到按鈕）"
    fi
    local text
    text=$(_tui_expand_text "$message")

    whiptail --title "$title" ${scroll_opt[@]+"${scroll_opt[@]}"} --msgbox "$text" $height $width 3>&1 1>&2 2>&3
}

# TUI 日誌檢視器（顯示最後 N 行，預設 300 行）
tui_log_viewer() {
    local title="$1"
    local log_file="$2"
    local tail_lines="${3:-300}"

    if [ "$USE_TUI" != "true" ]; then
        return 1
    fi

    if [ -z "$log_file" ] || [ ! -f "$log_file" ]; then
        tui_msgbox "$title" "找不到日誌文件：${log_file:-未設定}" 2>/dev/null || true
        return 1
    fi

    local view_file="$log_file"
    local tmp_file=""
    if [ "$tail_lines" != "all" ] && [ "$tail_lines" -gt 0 ] 2>/dev/null; then
        tmp_file="$(mktemp "${TMPDIR:-/tmp}/linux-setting-log.XXXXXX")" || return 1
        if tail -n "$tail_lines" "$log_file" > "$tmp_file" 2>/dev/null; then
            view_file="$tmp_file"
        else
            rm -f "$tmp_file"
            tmp_file=""
        fi
    fi

    local rc=0
    if [ "${TUI_BACKEND:-whiptail}" = "gum" ]; then
        gum pager < "$view_file" || rc=$?
    elif [ "${TUI_BACKEND:-whiptail}" = "fzf" ]; then
        if [ -t 0 ]; then
            fzf --height=80% --border --no-sort \
                --layout=reverse \
                --prompt="$title> " \
                --header="輸入可搜尋；Enter 選取一行；Esc 返回" \
                < "$view_file" >/dev/null || rc=$?
        else
            cat "$view_file"
        fi
    else
        # 依終端機實際大小決定檢視器尺寸（上限 40x140），小視窗不會超出畫面
        local viewer_rows viewer_cols
        read -r viewer_rows viewer_cols <<< "$(_tui_term_size)"
        viewer_rows=$((viewer_rows - 2))
        viewer_cols=$((viewer_cols - 4))
        [ "$viewer_rows" -le 40 ] || viewer_rows=40
        [ "$viewer_cols" -le 140 ] || viewer_cols=140
        whiptail --title "$title" --textbox "$view_file" "$viewer_rows" "$viewer_cols" 3>&1 1>&2 2>&3 || rc=$?
    fi

    [ -n "$tmp_file" ] && rm -f "$tmp_file"
    return $rc
}

# TUI 進度條（需要配合管道使用）
tui_gauge() {
    local title="$1"
    local prompt="$2"
    local initial_percent="${3:-0}"

    # 檢查 TUI 是否可用
    if [ "$USE_TUI" != "true" ]; then
        return 1
    fi

    # whiptail gauge 從標準輸入讀取百分比
    # 使用方式: echo "50" | tui_gauge "Title" "Message"
    whiptail --title "$title" --gauge "$prompt" 10 70 "$initial_percent"
}

# TUI 輸入框
tui_inputbox() {
    local title="$1"
    local prompt="$2"
    local default="${3:-}"

    # 檢查 TUI 是否可用
    if [ "$USE_TUI" != "true" ]; then
        return 1
    fi

    local height=10
    local width=60

    if [ "${TUI_BACKEND:-whiptail}" = "gum" ]; then
        gum input --placeholder "$prompt" --value "$default"
        return $?
    fi

    local result
    result=$(whiptail --title "$title" --inputbox "$prompt" $height $width "$default" 3>&1 1>&2 2>&3)
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo "$result"
        return 0
    else
        return 1
    fi
}

# ==============================================================================
# 清理函數
# ==============================================================================

cleanup_temp_files() {
    if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        log_info "清理臨時文件: $TEMP_DIR"
    fi
}

# ==============================================================================
# 時間計算函數
# ==============================================================================

get_elapsed_time() {
    local end_time
    end_time=$(date +%s)
    local elapsed=$((end_time - SCRIPT_START_TIME))
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))
    printf "%02d:%02d" "$minutes" "$seconds"
}

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
func_list="$func_list check_command check_package_installed check_python_version check_disk_space check_network check_internet_speed"
func_list="$func_list check_pip_package_installed check_cargo_package_installed check_npm_package_installed"
func_list="$func_list install_with_fallback install_with_homebrew_fallback install_package install_apt_package install_apt_packages_parallel install_packages_batch"
func_list="$func_list install_brew_package install_brew_packages_batch check_brew_package_installed ensure_brew_shell_aliases ensure_homebrew_installed update_system"
func_list="$func_list ensure_package_index_fresh _pkg_index_needs_update _file_mtime _log_file_writable _pkg_run _root_exec _root_exec_apt _pkg_root_exec"
func_list="$func_list github_latest_release_tag linux_release_arch"
func_list="$func_list verify_sha256_in_list manifest_record"
func_list="$func_list backup_file safe_append_to_file"
func_list="$func_list init_cache_system is_cache_valid get_from_cache save_to_cache cleanup_cache"
func_list="$func_list safe_download download_files_parallel get_best_mirror"
func_list="$func_list optimize_apt_performance cleanup_apt_system select_fastest_apt_mirror"
func_list="$func_list version_greater_equal check_architecture_compatibility install_arch_specific_package"
func_list="$func_list ensure_tui_available tui_checklist tui_checklist_with_state tui_menu tui_yesno tui_msgbox tui_log_viewer tui_gauge tui_inputbox"
func_list="$func_list _tui_terminal_too_small"
func_list="$func_list cleanup_temp_files get_elapsed_time check_sudo_access init_common_env detect_and_inject_tool_paths"
func_list="$func_list is_non_interactive safe_read ensure_npm_user_prefix"
func_list="$func_list _tui_expand_text _tui_display_width _tui_max_display_width _tui_term_size _tui_dialog_size _tui_menu_fits_text _tui_fzf_height"

for func in $func_list; do
    if declare -f "$func" > /dev/null 2>&1; then
        export -f "${func?}" 2>/dev/null || true
    fi
done
