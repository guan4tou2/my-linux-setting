#!/bin/bash
# shellcheck shell=bash
# 套件安裝：以 root 執行指令、APT 批次安裝、Homebrew、安裝狀態檢查、APT 優化與架構判斷。
# 由 scripts/core/common.sh 載入（source），不可單獨執行。

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
