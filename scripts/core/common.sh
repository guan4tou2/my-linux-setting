#!/usr/bin/env bash

# ==============================================================================
# Common Library - Linux Setting Scripts
# Author: Linux Setting Scripts Team
# Version: 2.0.0
# Description: Common functions library for Linux environment setup
# ==============================================================================

# Set strict mode
set -euo pipefail

# ==============================================================================
# Configuration Loading
# ==============================================================================

# Load user configuration file if exists
CONFIG_FILE="${CONFIG_FILE:-$HOME/.config/linux-setting/config}"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# ==============================================================================
# Constants
# ==============================================================================

readonly SCRIPT_VERSION="2.0.0"
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly YELLOW='\033[0;33m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'

# Security constants
readonly MAX_SCRIPT_SIZE="${MAX_SCRIPT_SIZE:-1048576}"
readonly DOWNLOAD_TIMEOUT="${DOWNLOAD_TIMEOUT:-30}"
readonly DOWNLOAD_RETRIES="${DOWNLOAD_RETRIES:-3}"

# Logging constants
readonly LOG_DIR="${LOG_DIR:-$HOME/.local/log/linux-setting}"
readonly MAX_LOG_SIZE="${MAX_LOG_SIZE:-10}"
readonly MAX_LOG_AGE="${MAX_LOG_AGE:-30}"
readonly MAX_LOG_COUNT="${MAX_LOG_COUNT:-10}"

# Cache constants
readonly CACHE_DIR="${CACHE_DIR:-$HOME/.cache/linux-setting}"
readonly CACHE_TTL="${CACHE_TTL:-86400}"

# Performance constants
readonly PARALLEL_JOBS="${PARALLEL_JOBS:-$(nproc 2>/dev/null || echo 4)}"
readonly MIN_PACKAGES_FOR_PARALLEL="${MIN_PACKAGES_FOR_PARALLEL:-3}"

# Global variables
readonly SCRIPT_START_TIME=$(date +%s)
TOTAL_STEPS=0
CURRENT_STEP=0

# 統一處理 root 權限執行
run_as_root() {
    # 統一處理提權邏輯，並在 TUI_MODE=quiet 時自動壓縮 apt 輸出
    local cmd="$1"
    shift || true

    # 在安靜模式下，針對 apt / apt-get 自動加上 -qq，並隱藏標準輸出（保留錯誤訊息）
    if [ "${TUI_MODE:-quiet}" = "quiet" ] && { [ "$cmd" = "apt" ] || [ "$cmd" = "apt-get" ]; }; then
        if [ "$EUID" -eq 0 ]; then
            "$cmd" -qq "$@" >/dev/null
        else
            sudo "$cmd" -qq "$@" >/dev/null
        fi
        return $?
    fi

    # 其他命令維持原本行為
    if [ "$EUID" -eq 0 ]; then
        "$cmd" "$@"
    else
        sudo "$cmd" "$@"
    fi
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

    # Set log file path
    LOG_FILE="${LOG_FILE:-$LOG_DIR/$log_prefix}"

    # Rotate old logs
    rotate_logs

    # Set global logging flag
    ENABLE_LOGGING="${ENABLE_LOGGING:-true}"
}

# Rotate log files based on size, age, and count
rotate_logs() {
    [ "$ENABLE_LOGGING" != "true" ] && return 0

    # Clean logs older than MAX_LOG_AGE days
    find "$LOG_DIR" -type f -name "*.log" -mtime +$MAX_LOG_AGE -delete 2>/dev/null || true

    # Check log sizes and rotate if needed
    for log_file in "$LOG_DIR"/*.log; do
        [ -f "$log_file" ] || continue

        local file_size_mb
        file_size_mb=$(du -m "$log_file" 2>/dev/null | cut -f1)

        if [ "$file_size_mb" -ge "$MAX_LOG_SIZE" ]; then
            local new_name="${log_file%.log}.$(date +%Y%m%d_%H%M%S).old"
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
    [ -z "${LOG_FILE:-}" ] && return 0

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
    # 總是輸出到終端
    printf "${CYAN}INFO: %s${NC}\n" "$message"
    # 如果啟用日誌，同時寫入日誌文件
    [ "${ENABLE_LOGGING:-false}" = "true" ] && log_entry "INFO" "$message"
}

log_success() {
    local message="$1"
    # 總是輸出到終端
    printf "${GREEN}SUCCESS: %s${NC}\n" "$message"
    # 如果啟用日誌，同時寫入日誌文件
    [ "${ENABLE_LOGGING:-false}" = "true" ] && log_entry "SUCCESS" "$message"
}

log_warning() {
    local message="$1"
    # 總是輸出到終端
    printf "${YELLOW}WARNING: %s${NC}\n" "$message"
    # 如果啟用日誌，同時寫入日誌文件
    [ "${ENABLE_LOGGING:-false}" = "true" ] && log_entry "WARNING" "$message"
}

log_debug() {
    local message="$1"
    # DEBUG 模式未啟用時直接返回
    [ "${DEBUG:-false}" != "true" ] && return 0
    # 輸出到終端
    printf "${BLUE}DEBUG: %s${NC}\n" "$message"
    # 如果啟用日誌，同時寫入日誌文件
    [ "${ENABLE_LOGGING:-false}" = "true" ] && log_entry "DEBUG" "$message"
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
            dpkg -l | grep -q "^ii  $package" 2>/dev/null
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

# 並行安裝多個 APT 套件
install_apt_packages_parallel() {
    local packages=("$@")
    local max_jobs="${PARALLEL_JOBS:-4}"
    local temp_dir
    temp_dir=$(mktemp -d)
    local pids=()
    local failed_packages=()
    
    log_info "並行安裝 ${#packages[@]} 個套件（最多 $max_jobs 個並發任務）"
    
    # 函數：安裝單個套件
    install_single_package() {
        local package="$1"
        local log_file="$2"
        {
            if install_apt_package "$package"; then
                echo "SUCCESS:$package"
            else
                echo "FAILED:$package"
            fi
        } > "$log_file" 2>&1
    }
    
    # 導出函數供子 shell 使用
    for func in install_single_package install_apt_package check_package_installed log_info log_success log_error; do
        if declare -f "$func" > /dev/null 2>&1; then
            export -f "$func" 2>/dev/null || true
        fi
    done
    
    # 啟動並行任務
    local job_count=0
    for package in "${packages[@]}"; do
        local log_file="$temp_dir/$package.log"
        
        # 等待任務槽位可用
        while [ ${#pids[@]} -ge $max_jobs ]; do
            for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[i]}" 2>/dev/null; then
                    unset pids[i]
                fi
            done
            pids=("${pids[@]}") # 重新索引數組
            sleep 0.1
        done
        
        # 啟動新任務
        install_single_package "$package" "$log_file" &
        pids+=($!)
        job_count=$((job_count + 1))
        
        log_debug "啟動安裝任務 $job_count/${#packages[@]}: $package (PID: ${pids[-1]})"
    done
    
    # 等待所有任務完成
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    # 收集結果
    local success_count=0
    for package in "${packages[@]}"; do
        local log_file="$temp_dir/$package.log"
        if [ -f "$log_file" ]; then
            local result
            result=$(tail -n1 "$log_file" 2>/dev/null)
            if [[ "$result" == SUCCESS:* ]]; then
                success_count=$((success_count + 1))
                log_success "✓ $package"
            else
                failed_packages+=("$package")
                log_error "✗ $package"
            fi
        fi
    done
    
    # 清理臨時文件
    rm -rf "$temp_dir"
    
    log_info "並行安裝完成: $success_count/${#packages[@]} 成功"
    
    if [ ${#failed_packages[@]} -gt 0 ]; then
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
            export -f "$func" 2>/dev/null || true
        fi
    done
    
    # 啟動並行下載任務
    for url in "${!url_file_map[@]}"; do
        local output="${url_file_map[$url]}"
        local log_file="$temp_dir/$(basename "$output").log"
        
        # 等待任務槽位可用
        while [ ${#pids[@]} -ge $max_jobs ]; do
            for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[i]}" 2>/dev/null; then
                    unset pids[i]
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
        local log_file="$temp_dir/$(basename "$output").log"
        
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
    local fallback_func="${3:-}"

    [ "${PREFER_HOMEBREW:-true}" != "true" ] && return 1

    if command -v brew >/dev/null 2>&1 && ! check_command "$binary_name"; then
        log_info "Attempting Homebrew installation: $package"

        if install_brew_package "$package"; then
            log_success "$package installed via Homebrew"
            return 0
        else
            log_debug "Homebrew installation failed for $package, will try fallback"
            return 1
        fi
    fi

    return 0
}

# Unified pattern: Try Homebrew, then call fallback function
try_homebrew_then() {
    local package="$1"
    local binary_name="${2:-$package}"
    local fallback_function="$3"
    shift 3
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
    local success=0

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
                log_info "Installing $package via pip"
                if pip install "$package" 2>/dev/null; then
                    log_success "$package installed via pip"
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

    log_info "安裝 $package (使用 ${PKG_MANAGER:-apt})"

    # 根據包管理器選擇安裝命令
    local install_cmd
    case "${PKG_MANAGER:-apt}" in
        apt)
            install_cmd="sudo apt install -y"
            ;;
        dnf)
            install_cmd="sudo dnf install -y"
            ;;
        yum)
            install_cmd="sudo yum install -y"
            ;;
        pacman)
            install_cmd="sudo pacman -S --noconfirm"
            ;;
        zypper)
            install_cmd="sudo zypper install -y"
            ;;
        *)
            log_error "不支援的包管理器: ${PKG_MANAGER}"
            return 1
            ;;
    esac

    # 根據 TUI_MODE 控制輸出詳細程度
    if [ "${TUI_MODE:-normal}" = "quiet" ]; then
        # 靜默模式：隱藏詳細輸出
        if $install_cmd "$package" >/dev/null 2>&1; then
            log_success "$package 安裝成功"
            return 0
        else
            log_error "$package 安裝失敗"
            return 1
        fi
    fi

    # 一般模式：顯示完整安裝輸出
    if $install_cmd "$package"; then
        log_success "$package 安裝成功"
        return 0
    else
        log_error "$package 安裝失敗"
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

    # 如果啟用並行安裝且包數量 >= 3，使用並行模式
    if [ "${ENABLE_PARALLEL_INSTALL:-false}" = "true" ] && [ ${#to_install[@]} -ge 3 ]; then
        log_info "使用並行模式安裝 ${#to_install[@]} 個套件"
        # 對於 Debian 系列，使用並行安裝
        if [ "$DISTRO_FAMILY" = "debian" ] && command -v install_apt_packages_parallel >/dev/null 2>&1; then
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

# 通用系統更新函數
update_system() {
    log_info "更新系統套件列表 (使用 ${PKG_MANAGER:-apt})"

    case "${PKG_MANAGER:-apt}" in
        apt)
            if [ "${TUI_MODE:-normal}" = "quiet" ]; then
                sudo apt-get update >/dev/null 2>&1
            else
                sudo apt-get update
            fi
            ;;
        dnf)
            if [ "${TUI_MODE:-normal}" = "quiet" ]; then
                sudo dnf check-update >/dev/null 2>&1 || true
            else
                sudo dnf check-update || true
            fi
            ;;
        yum)
            if [ "${TUI_MODE:-normal}" = "quiet" ]; then
                sudo yum check-update >/dev/null 2>&1 || true
            else
                sudo yum check-update || true
            fi
            ;;
        pacman)
            if [ "${TUI_MODE:-normal}" = "quiet" ]; then
                sudo pacman -Sy >/dev/null 2>&1
            else
                sudo pacman -Sy
            fi
            ;;
        zypper)
            if [ "${TUI_MODE:-normal}" = "quiet" ]; then
                sudo zypper refresh >/dev/null 2>&1
            else
                sudo zypper refresh
            fi
            ;;
        *)
            log_warning "不支援的包管理器，無法更新系統"
            return 1
            ;;
    esac
}

# ==============================================================================
# Homebrew 包管理函數 (Linux)
# ==============================================================================

# 確保 Homebrew 已安裝（Linux 上的 Homebrew/Linuxbrew）
ensure_homebrew_installed() {
    # 檢查是否已安裝 Homebrew
    if command -v brew >/dev/null 2>&1; then
        log_success "Homebrew 已安裝: $(brew --version | head -n1)"
        return 0
    fi

    log_info "檢測到系統未安裝 Homebrew，開始安裝..."
    log_info "Homebrew 可以提供更新的軟體版本，並避免編譯耗時的工具"

    # 安裝 Homebrew 所需的依賴
    log_info "安裝 Homebrew 依賴項..."
    local brew_deps="build-essential procps curl file git"

    case "${PKG_MANAGER:-apt}" in
        apt)
            if [ "${TUI_MODE:-normal}" = "quiet" ]; then
                sudo apt-get install -y $brew_deps >/dev/null 2>&1 || log_warning "部分依賴安裝失敗"
            else
                sudo apt-get install -y $brew_deps || log_warning "部分依賴安裝失敗"
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

        # 配置 Homebrew 環境變量
        local brew_shellenv=""
        if [ -d "/home/linuxbrew/.linuxbrew" ]; then
            brew_shellenv="/home/linuxbrew/.linuxbrew/bin/brew shellenv"
        elif [ -d "$HOME/.linuxbrew" ]; then
            brew_shellenv="$HOME/.linuxbrew/bin/brew shellenv"
        fi

        if [ -n "$brew_shellenv" ]; then
            # 載入到當前會話（僅供安裝時使用）
            eval "$($brew_shellenv)"

            # 添加 alias 到 shell 配置文件（預設不自動載入 Homebrew 環境）
            # 這樣可以避免 Homebrew Python 與系統 Python 的路徑衝突
            for rcfile in "$HOME/.bashrc" "$HOME/.zshrc"; do
                if [ -f "$rcfile" ] || [ "$(basename "$rcfile")" = ".zshrc" ]; then
                    if ! grep -q "brew-on" "$rcfile"; then
                        cat >> "$rcfile" << 'BREW_ALIAS'

# ==============================================================================
# Homebrew 環境切換（預設不啟用，避免 Python 路徑衝突）
# ==============================================================================
# 使用 brew-on 啟用 Homebrew 環境
# 使用 brew-off 停用 Homebrew 環境
# ==============================================================================
BREW_ALIAS
                        if [ -d "/home/linuxbrew/.linuxbrew" ]; then
                            cat >> "$rcfile" << 'BREW_FUNC'
brew-on() {
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    echo "Homebrew 環境已啟用"
}
brew-off() {
    export PATH=$(echo "$PATH" | sed 's|/home/linuxbrew/.linuxbrew/[^:]*:||g')
    unset HOMEBREW_PREFIX HOMEBREW_CELLAR HOMEBREW_REPOSITORY
    echo "Homebrew 環境已停用"
}
# 直接使用 brew 命令的 alias（不影響 PATH）
alias brew='/home/linuxbrew/.linuxbrew/bin/brew'
BREW_FUNC
                        else
                            cat >> "$rcfile" << BREW_FUNC
brew-on() {
    eval "\$($HOME/.linuxbrew/bin/brew shellenv)"
    echo "Homebrew 環境已啟用"
}
brew-off() {
    export PATH=\$(echo "\$PATH" | sed 's|$HOME/.linuxbrew/[^:]*:||g')
    unset HOMEBREW_PREFIX HOMEBREW_CELLAR HOMEBREW_REPOSITORY
    echo "Homebrew 環境已停用"
}
# 直接使用 brew 命令的 alias（不影響 PATH）
alias brew='$HOME/.linuxbrew/bin/brew'
BREW_FUNC
                        fi
                        log_info "已添加 Homebrew alias 到 $rcfile"
                    fi
                fi
            done

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

# ==============================================================================
# 文件操作函數
# ==============================================================================

backup_file() {
    local file="$1"
    local backup_dir="${2:-$BACKUP_DIR}"
    
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
        cp -r "$file" "$backup_dir/$backup_name"
        log_info "已備份 $file 到 $backup_dir/$backup_name"
        return 0
    else
        log_warning "文件不存在，跳過備份: $file"
        return 1
    fi
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
    export CACHE_DIR="${CACHE_DIR:-$HOME/.cache/linux-setting}"
    export CACHE_ENABLED="${CACHE_ENABLED:-true}"
    export CACHE_TTL="${CACHE_TTL:-86400}"  # 24小時
    
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
    local cleaned_count=0
    
    find "$CACHE_DIR/downloads" -type f -mtime +1 -exec rm -f {} \; 2>/dev/null
    find "$CACHE_DIR/metadata" -type f -mtime +1 -exec rm -f {} \; 2>/dev/null
    
    log_info "快取清理完成"
}

# ==============================================================================
# Security Functions
# ==============================================================================

# Verify GPG signature of a file
verify_gpg_signature() {
    local file="$1"
    local sig_file="${2:-$file.sig}"
    local keyring="${3:-$HOME/.cache/linux-setting/trusted.gpg}"

    [ "${ENABLE_GPG_VERIFY:-true}" != "true" ] && return 0
    [ ! -f "$file" ] && { log_error "File not found: $file"; return 1; }

    # Import key if keyring doesn't exist
    if [ ! -f "$keyring" ] && [ -n "${GPG_KEY:-}" ]; then
        log_info "Importing GPG key..."
        echo "$GPG_KEY" | gpg --dearmor > "$keyring" 2>/dev/null || {
            log_warning "Failed to import GPG key, skipping verification"
            return 0
        }
    fi

    # Verify signature if available
    if [ -f "$sig_file" ]; then
        if gpg --verify --keyring "$keyring" "$sig_file" "$file" >/dev/null 2>&1; then
            log_success "GPG signature verified"
            return 0
        else
            log_error "GPG signature verification failed"
            return 1
        fi
    fi

    # No signature file, warn but continue
    log_warning "No signature file found for $file, skipping GPG verification"
    return 0
}

# Validate script content safely
validate_script_content() {
    local script_file="$1"
    local max_size="${2:-$MAX_SCRIPT_SIZE}"

    # Check file size
    [ ! -f "$script_file" ] && return 1

    local file_size
    file_size=$(stat -c%s "$script_file" 2>/dev/null || stat -f%z "$script_file" 2>/dev/null || echo 0)

    if [ "$file_size" -gt "$max_size" ]; then
        log_error "Script too large: $file_size bytes (max: $max_size)"
        return 1
    fi

    # Check for dangerous patterns
    local dangerous_patterns=(
        "rm[[:space:]]+-rf[[:space:]]+/"
        "dd[[:space:]]+if="
        "mkfs\."
        "echo[[:space:]]*>[[:space:]]*/etc/passwd"
        "echo[[:space:]]*>[[:space:]]*/etc/shadow"
        ":(){ :|:& };:"
        ">[[:space:]]*\$(command)"
    )

    for pattern in "${dangerous_patterns[@]}"; do
        if grep -qE "$pattern" "$script_file" 2>/dev/null; then
            log_error "Dangerous pattern detected: $pattern"
            return 1
        fi
    done

    # Check for excessive sudo operations
    local sudo_count
    sudo_count=$(grep -cE "^\s*(sudo|su)\s" "$script_file" 2>/dev/null || echo 0)

    if [ "$sudo_count" -gt 20 ]; then
        log_warning "Script contains excessive sudo operations: $sudo_count"
        # Ask in interactive mode
        if [ -t 0 ] && [ -z "${SKIP_SECURITY_PROMPT:-}" ]; then
            printf "${YELLOW}This script makes $sudo_count sudo operations. Continue? (y/N): ${NC}"
            read -r -n 1 -p "" answer
            echo
            [[ ! "$answer" =~ ^[Yy]$ ]] && return 1
        fi
    fi

    return 0
}

# ==============================================================================
# Download Functions
# ==============================================================================

safe_download() {
    local url="$1"
    local output="$2"
    local max_retries="${3:-$DOWNLOAD_RETRIES}"
    local use_cache="${4:-true}"
    local verify_gpg="${5:-true}"

    log_debug "Downloading: $url"

    # Try to get from cache first
    if [ "$use_cache" = "true" ] && [ "$CACHE_ENABLED" = "true" ]; then
        if get_from_cache "$url" "$output"; then
            log_debug "Retrieved from cache"
            return 0
        fi
    fi

    # Download with retries
    local retry=0
    local temp_output
    temp_output="${output}.tmp.$$"

    while [ $retry -lt $max_retries ]; do
        if curl -fsSL \
            --max-time "$DOWNLOAD_TIMEOUT" \
            --connect-timeout "${CONNECTION_TIMEOUT:-10}" \
            --max-filesize "$MAX_SCRIPT_SIZE" \
            "$url" -o "$temp_output" 2>/dev/null; then

            # Validate downloaded content
            if ! validate_script_content "$temp_output"; then
                rm -f "$temp_output"
                retry=$((retry + 1))
                log_warning "Validation failed, retry $retry/$max_retries"
                sleep 2
                continue
            fi

            # Move to final location
            mv "$temp_output" "$output"

            # Verify GPG signature if enabled and available
            if [ "$verify_gpg" = "true" ]; then
                local sig_file
                sig_file="${url}.sig"
                if curl -fsSL "$sig_file" -o "${output}.sig" 2>/dev/null; then
                    verify_gpg_signature "$output" "${output}.sig" || {
                        rm -f "$output" "${output}.sig"
                        return 1
                    }
                    rm -f "${output}.sig"
                fi
            fi

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
optimize_apt_performance() {
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
    fi
    
    log_success "APT 性能優化配置完成"
}

# 清理 APT 快取和無用套件
cleanup_apt_system() {
    log_info "清理 APT 系統..."
    
    # 清理套件快取
    sudo apt autoclean
    
    # 移除不需要的套件
    sudo apt autoremove -y
    
    # 清理孤立套件
    if check_command deborphan; then
        local orphaned
        orphaned=$(deborphan)
        if [ -n "$orphaned" ]; then
            echo "$orphaned" | sudo xargs apt remove -y
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
            sudo apt update
            sudo apt install apt-fast -y
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

# 檢測並確保 whiptail 可用
ensure_tui_available() {
    # 如果明確禁用 TUI，直接返回失敗
    if [ "$USE_TUI" = "false" ]; then
        return 1
    fi

    # 檢查 whiptail 是否可用
    if command -v whiptail >/dev/null 2>&1; then
        export USE_TUI="true"
        return 0
    fi

    # 嘗試安裝 whiptail（通常在 newt 包中）
    log_info "檢測到 whiptail 未安裝，嘗試安裝..."
    if [ "$DISTRO_FAMILY" = "debian" ]; then
        if install_package "whiptail" 2>/dev/null || install_package "newt" 2>/dev/null; then
            if command -v whiptail >/dev/null 2>&1; then
                log_success "whiptail 安裝成功，啟用 TUI 模式"
                export USE_TUI="true"
                return 0
            fi
        fi
    fi

    # 如果是 auto 模式且安裝失敗，降級到命令行
    if [ "$USE_TUI" = "auto" ]; then
        log_info "TUI 不可用，使用命令行模式"
        export USE_TUI="false"
        return 1
    fi

    # 明確要求 TUI 但不可用
    log_warning "TUI 模式不可用，降級到命令行模式"
    export USE_TUI="false"
    return 1
}

# TUI 多選菜單（返回選中的項目，以空格分隔）
tui_checklist() {
    local title="$1"
    local prompt="$2"
    shift 2
    local items=("$@")

    # 檢查 TUI 是否可用
    if [ "$USE_TUI" != "true" ]; then
        return 1
    fi

    # 構建 whiptail checklist 參數
    local checklist_args=()
    local index=0
    local default_state="ON"  # 預設全部選中

    for item in "${items[@]}"; do
        # 每個項目格式: "tag" "description" "status"
        checklist_args+=("$item" "" "$default_state")
        index=$((index + 1))
    done

    # 計算窗口大小
    local height=$((${#items[@]} + 10))
    [ $height -gt 25 ] && height=25
    local width=70

    # 顯示 checklist 並捕獲結果
    local result
    result=$(whiptail --title "$title" --checklist "$prompt" $height $width $((${#items[@]})) "${checklist_args[@]}" 3>&1 1>&2 2>&3)
    local exit_code=$?

    # 返回選中的項目（去除引號）
    if [ $exit_code -eq 0 ]; then
        echo "$result" | tr -d '"'
        return 0
    else
        return 1
    fi
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

    # 計算窗口大小
    local height=$((${#items[@]} + 10))
    [ $height -gt 25 ] && height=25
    local width=70

    # 顯示 menu 並捕獲結果
    local result
    result=$(whiptail --title "$title" --menu "$prompt" $height $width $((${#items[@]})) "${menu_args[@]}" 3>&1 1>&2 2>&3)
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

    # 計算窗口大小
    local height=10
    local width=60

    # 設置預設按鈕
    local defaultno=""
    [ "$default" = "no" ] && defaultno="--defaultno"

    # 顯示 yesno 對話框
    if whiptail --title "$title" $defaultno --yesno "$prompt" $height $width 3>&1 1>&2 2>&3; then
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

    # 計算窗口大小（根據消息長度）
    local height=15
    local width=70

    whiptail --title "$title" --msgbox "$message" $height $width 3>&1 1>&2 2>&3
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
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
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
    else
        log_warning "需要 sudo 權限，請輸入密碼"
        sudo -v
        return $?
    fi
}

# ==============================================================================
# 初始化函數
# ==============================================================================

init_common_env() {
    # 設置錯誤處理
    set -eE
    trap 'log_error "腳本在第 $LINENO 行出錯"' ERR
    
    # 創建必要目錄
    mkdir -p "$HOME/.local/bin"
    mkdir -p "$HOME/.config"
    
    # 初始化快取系統
    init_cache_system
    
    # 設置 PATH
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
    
    # 設置並行任務數量（根據CPU核心數）
    export PARALLEL_JOBS="${PARALLEL_JOBS:-$(nproc 2>/dev/null || echo 4)}"
    
    log_info "共用環境初始化完成（並行任務: $PARALLEL_JOBS）"
}

# ==============================================================================
# 導出所有函數
# ==============================================================================

# 安全導出所有函數供子 shell 使用
func_list="log_error log_info log_success log_warning log_debug init_progress show_progress run_as_root"
func_list="$func_list check_command check_package_installed check_python_version check_disk_space check_network check_internet_speed"
func_list="$func_list install_with_fallback install_apt_package install_apt_packages_parallel"
func_list="$func_list backup_file safe_append_to_file"
func_list="$func_list init_cache_system is_cache_valid get_from_cache save_to_cache cleanup_cache"
func_list="$func_list safe_download download_files_parallel get_best_mirror"
func_list="$func_list optimize_apt_performance cleanup_apt_system select_fastest_apt_mirror"
func_list="$func_list version_greater_equal check_architecture_compatibility install_arch_specific_package"
func_list="$func_list ensure_tui_available tui_checklist tui_menu tui_yesno tui_msgbox tui_gauge tui_inputbox"
func_list="$func_list cleanup_temp_files get_elapsed_time check_sudo_access init_common_env"

for func in $func_list; do
    if declare -f "$func" > /dev/null 2>&1; then
        export -f "$func" 2>/dev/null || true
    fi
done