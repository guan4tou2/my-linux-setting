#!/bin/bash
# shellcheck shell=bash
# 系統偵測：發行版、套件管理器、指令與套件是否存在、磁碟與網路檢查。
# 由 scripts/core/common.sh 載入（source），不可單獨執行。

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
