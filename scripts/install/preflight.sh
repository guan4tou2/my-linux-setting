#!/bin/bash
# shellcheck shell=bash
# 安裝前的準備：環境檢查、設定檔備份、安裝清單記錄、卸載腳本保存、日誌設定。
# 由 install.sh 載入（source），不可單獨執行。

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

# 把 uninstall.sh 複製到固定位置，讓一鍵遠端安裝（暫存的專案副本用完即刪）之後仍能卸載。
# 只在有寫入卸載清單時進行；失敗只警告。成功時路徑放在 UNINSTALLER_COPY。
UNINSTALLER_COPY=""
install_uninstaller_copy() {
    UNINSTALLER_COPY=""
    [ "${DRY_RUN:-false}" != "true" ] || return 0
    [ -n "${INSTALL_MANIFEST_FILE:-}" ] && [ -f "$INSTALL_MANIFEST_FILE" ] || return 0

    local source_file="$INSTALL_SH_DIR/uninstall.sh"
    local dest_dir="${XDG_CONFIG_HOME:-$HOME/.config}/linux-setting"
    local dest="$dest_dir/uninstall.sh"
    if [ ! -f "$source_file" ]; then
        log_warning "找不到 uninstall.sh，未保存卸載腳本"
        return 0
    fi
    if mkdir -p "$dest_dir" \
       && cp "$source_file" "$dest.tmp" \
       && chmod 0700 "$dest.tmp" \
       && mv -f "$dest.tmp" "$dest"; then
        # shellcheck disable=SC2034 # 由 scripts/install/report.sh 的安裝報告讀取
        UNINSTALLER_COPY="$dest"
    else
        rm -f "$dest.tmp"
        log_warning "無法保存卸載腳本到 $dest；之後可從專案取得 uninstall.sh"
    fi
    return 0
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
