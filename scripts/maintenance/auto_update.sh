#!/usr/bin/env bash

# 自動更新機制 - 系統和工具自動更新

# 載入共用函數庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || exit 1
if [ -f "$SCRIPT_DIR/config_manager_simple.sh" ]; then
    source "$SCRIPT_DIR/config_manager_simple.sh" 2>/dev/null || true
fi

log_info "########## 自動更新機制 ##########"

readonly UPDATE_LOG_FILE="$HOME/.local/log/linux-setting/auto_update_$(date +%Y%m%d).log"
readonly UPDATE_CACHE_DIR="$HOME/.cache/linux-setting/updates"
readonly UPDATE_CONFIG_FILE="$HOME/.config/linux-setting/auto_update.conf"
readonly UPDATE_LOCK_FILE="$UPDATE_CACHE_DIR/update.lock"

# 確保目錄存在
mkdir -p "$UPDATE_CACHE_DIR"
mkdir -p "$(dirname "$UPDATE_LOG_FILE")"
mkdir -p "$(dirname "$UPDATE_CONFIG_FILE")"

# 更新配置
AUTO_UPDATE_ENABLED="${AUTO_UPDATE_ENABLED:-false}"
SYSTEM_UPDATE_ENABLED="${SYSTEM_UPDATE_ENABLED:-true}"
SECURITY_UPDATE_ENABLED="${SECURITY_UPDATE_ENABLED:-true}"
PACKAGE_UPDATE_ENABLED="${PACKAGE_UPDATE_ENABLED:-true}"
SCRIPT_UPDATE_ENABLED="${SCRIPT_UPDATE_ENABLED:-true}"
UPDATE_CHECK_INTERVAL="${UPDATE_CHECK_INTERVAL:-86400}"  # 24小時
REBOOT_REQUIRED_NOTIFY="${REBOOT_REQUIRED_NOTIFY:-true}"
BACKUP_BEFORE_UPDATE="${BACKUP_BEFORE_UPDATE:-true}"

# 更新級別
readonly UPDATE_LEVEL_INFO=0
readonly UPDATE_LEVEL_WARNING=1
readonly UPDATE_LEVEL_ERROR=2
readonly UPDATE_LEVEL_CRITICAL=3

# 更新組件定義
declare -A UPDATE_COMPONENTS

# 初始化更新組件
init_update_components() {
    # 系統組件
    UPDATE_COMPONENTS["system"]="update_system_packages"
    UPDATE_COMPONENTS["security"]="update_security_patches"
    UPDATE_COMPONENTS["kernel"]="update_kernel"
    
    # 應用程序
    UPDATE_COMPONENTS["python"]="update_python_packages"
    UPDATE_COMPONENTS["nodejs"]="update_nodejs_packages"
    UPDATE_COMPONENTS["docker"]="update_docker"
    UPDATE_COMPONENTS["git"]="update_git"
    
    # 開發工具
    UPDATE_COMPONENTS["uv"]="update_uv"
    UPDATE_COMPONENTS["zsh"]="update_zsh_plugins"
    UPDATE_COMPONENTS["vim"]="update_vim_plugins"
    
    # Linux Setting Scripts
    UPDATE_COMPONENTS["linux_setting"]="update_linux_setting_scripts"
    
    log_update $UPDATE_LEVEL_INFO "更新組件初始化完成: ${#UPDATE_COMPONENTS[@]} 個組件"
}

# 記錄更新日誌
log_update() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    local level_text
    case "$level" in
        $UPDATE_LEVEL_INFO) level_text="INFO" ;;
        $UPDATE_LEVEL_WARNING) level_text="WARN" ;;
        $UPDATE_LEVEL_ERROR) level_text="ERROR" ;;
        $UPDATE_LEVEL_CRITICAL) level_text="CRITICAL" ;;
        *) level_text="UNKNOWN" ;;
    esac
    
    echo "[$timestamp] [$level_text] $message" >> "$UPDATE_LOG_FILE"
    
    case "$level" in
        $UPDATE_LEVEL_WARNING) log_warning "$message" ;;
        $UPDATE_LEVEL_ERROR) log_error "$message" ;;
        $UPDATE_LEVEL_CRITICAL) log_error "🚨 CRITICAL: $message" ;;
        *) log_info "$message" ;;
    esac
}

# 檢查更新鎖
check_update_lock() {
    if [ -f "$UPDATE_LOCK_FILE" ]; then
        local lock_pid
        lock_pid=$(cat "$UPDATE_LOCK_FILE")
        if kill -0 "$lock_pid" 2>/dev/null; then
            log_update $UPDATE_LEVEL_WARNING "更新正在進行中 (PID: $lock_pid)"
            return 1
        else
            log_update $UPDATE_LEVEL_WARNING "發現僵屍鎖文件，正在清理..."
            rm -f "$UPDATE_LOCK_FILE"
        fi
    fi
    return 0
}

# 創建更新鎖
create_update_lock() {
    echo $$ > "$UPDATE_LOCK_FILE"
}

# 移除更新鎖
remove_update_lock() {
    rm -f "$UPDATE_LOCK_FILE"
}

# 檢查是否需要重啟
check_reboot_required() {
    if [ -f "/var/run/reboot-required" ]; then
        log_update $UPDATE_LEVEL_WARNING "系統需要重啟以完成更新"
        
        if [ "$REBOOT_REQUIRED_NOTIFY" = "true" ]; then
            send_update_notification "需要重啟" "系統更新後需要重啟以完成安裝"
        fi
        
        return 0
    fi
    return 1
}

# 創建系統備份
create_system_backup() {
    if [ "$BACKUP_BEFORE_UPDATE" != "true" ]; then
        return 0
    fi
    
    log_update $UPDATE_LEVEL_INFO "創建系統備份..."
    
    local backup_dir="$UPDATE_CACHE_DIR/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # 備份重要配置文件
    local config_files=(
        "/etc/apt/sources.list"
        "/etc/hosts"
        "/etc/resolv.conf"
        "/etc/fstab"
        "/etc/crontab"
    )
    
    for config_file in "${config_files[@]}"; do
        if [ -f "$config_file" ]; then
            local target_dir="$backup_dir/$(dirname "$config_file")"
            mkdir -p "$target_dir"
            cp "$config_file" "$target_dir/"
        fi
    done
    
    # 備份用戶配置
    local user_configs=(
        "$HOME/.bashrc"
        "$HOME/.zshrc"
        "$HOME/.gitconfig"
        "$HOME/.config/linux-setting"
    )
    
    for user_config in "${user_configs[@]}"; do
        if [ -e "$user_config" ]; then
            local target_dir="$backup_dir/$user_config"
            mkdir -p "$(dirname "$target_dir")"
            cp -r "$user_config" "$target_dir" 2>/dev/null || true
        fi
    done
    
    # 記錄已安裝的套件
    dpkg -l > "$backup_dir/installed_packages.list" 2>/dev/null || true
    
    log_update $UPDATE_LEVEL_INFO "系統備份已創建: $backup_dir"
    echo "$backup_dir"
}

# 更新系統套件
update_system_packages() {
    log_update $UPDATE_LEVEL_INFO "更新系統套件..."
    
    # 更新套件列表
    if ! sudo DEBIAN_FRONTEND=noninteractive apt-get update; then
        log_update $UPDATE_LEVEL_ERROR "更新套件列表失敗"
        return 1
    fi

    # 檢查可更新的套件
    local upgradeable
    upgradeable=$(apt list --upgradeable 2>/dev/null | grep -c upgradeable || true)

    if [ "$upgradeable" -gt 0 ]; then
        log_update $UPDATE_LEVEL_INFO "發現 $upgradeable 個可更新的套件"

        # 執行更新（保留舊設定檔，避免 dpkg 互動 prompt 造成腳本卡住）
        if sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
                -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold; then
            log_update $UPDATE_LEVEL_INFO "系統套件更新成功"

            # 清理無用的套件
            sudo DEBIAN_FRONTEND=noninteractive apt-get autoremove -y
            sudo DEBIAN_FRONTEND=noninteractive apt-get autoclean

            return 0
        else
            log_update $UPDATE_LEVEL_ERROR "系統套件更新失敗"
            return 1
        fi
    else
        log_update $UPDATE_LEVEL_INFO "系統套件已是最新版本"
        return 0
    fi
}

# 更新安全補丁
update_security_patches() {
    log_update $UPDATE_LEVEL_INFO "更新安全補丁..."
    
    # 檢查安全更新
    local security_updates
    security_updates=$(apt list --upgradeable 2>/dev/null | grep -i security | wc -l)
    
    if [ "$security_updates" -gt 0 ]; then
        log_update $UPDATE_LEVEL_WARNING "發現 $security_updates 個安全更新"
        
        # 只更新安全相關套件
        if sudo DEBIAN_FRONTEND=noninteractive unattended-upgrade -d 2>/dev/null \
            || sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
                   -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
                   $(apt list --upgradeable 2>/dev/null | grep -i security | cut -d'/' -f1); then
            log_update $UPDATE_LEVEL_INFO "安全補丁更新成功"
            return 0
        else
            log_update $UPDATE_LEVEL_ERROR "安全補丁更新失敗"
            return 1
        fi
    else
        log_update $UPDATE_LEVEL_INFO "沒有可用的安全更新"
        return 0
    fi
}

# 更新核心
update_kernel() {
    log_update $UPDATE_LEVEL_INFO "檢查核心更新..."
    
    local current_kernel
    current_kernel=$(uname -r)
    
    # 檢查是否有可用的核心更新
    local available_kernels
    available_kernels=$(apt list --upgradeable 2>/dev/null | grep -E "(linux-image|linux-headers|linux-modules)" | wc -l)
    
    if [ "$available_kernels" -gt 0 ]; then
        log_update $UPDATE_LEVEL_WARNING "發現核心更新，當前版本: $current_kernel"
        
        # 更新核心（需要小心處理）
        if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
                -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
                linux-image-generic linux-headers-generic; then
            log_update $UPDATE_LEVEL_INFO "核心更新成功，需要重啟生效"
            touch "/var/run/reboot-required"
            return 0
        else
            log_update $UPDATE_LEVEL_ERROR "核心更新失敗"
            return 1
        fi
    else
        log_update $UPDATE_LEVEL_INFO "核心已是最新版本: $current_kernel"
        return 0
    fi
}

# 更新 Python 套件
update_python_packages() {
    log_update $UPDATE_LEVEL_INFO "更新 Python 套件..."
    
    local updated=0
    
    # 更新 pip
    if command -v pip3 >/dev/null 2>&1; then
        if pip3 install --upgrade pip; then
            log_update $UPDATE_LEVEL_INFO "pip 更新成功"
            updated=$((updated + 1))
        fi
    fi
    
    # 更新 uv（如果安裝）
    if command -v uv >/dev/null 2>&1; then
        update_uv
        updated=$((updated + 1))
    fi
    
    # 更新常用 Python 套件
    local python_packages=("setuptools" "wheel" "virtualenv")
    
    for package in "${python_packages[@]}"; do
        if pip3 install --upgrade "$package" 2>/dev/null; then
            log_update $UPDATE_LEVEL_INFO "Python 套件 $package 更新成功"
            updated=$((updated + 1))
        fi
    done
    
    log_update $UPDATE_LEVEL_INFO "Python 套件更新完成: $updated 個套件"
    return 0
}

# 更新 Node.js 套件
update_nodejs_packages() {
    if ! command -v npm >/dev/null 2>&1; then
        log_update $UPDATE_LEVEL_INFO "Node.js/npm 未安裝，跳過更新"
        return 0
    fi
    
    log_update $UPDATE_LEVEL_INFO "更新 Node.js 套件..."
    
    # 更新 npm 自身
    if npm install -g npm; then
        log_update $UPDATE_LEVEL_INFO "npm 更新成功"
    fi
    
    # 檢查過期的全域套件
    local outdated
    outdated=$(npm outdated -g --parseable 2>/dev/null | wc -l)
    
    if [ "$outdated" -gt 0 ]; then
        log_update $UPDATE_LEVEL_INFO "發現 $outdated 個過期的全域 Node.js 套件"
        
        # 更新全域套件
        if npm update -g; then
            log_update $UPDATE_LEVEL_INFO "全域 Node.js 套件更新成功"
            return 0
        else
            log_update $UPDATE_LEVEL_WARNING "全域 Node.js 套件更新失敗"
            return 1
        fi
    else
        log_update $UPDATE_LEVEL_INFO "全域 Node.js 套件已是最新版本"
        return 0
    fi
}

# 更新 Docker
update_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        log_update $UPDATE_LEVEL_INFO "Docker 未安裝，跳過更新"
        return 0
    fi
    
    log_update $UPDATE_LEVEL_INFO "更新 Docker..."
    
    # Docker 通常通過系統套件管理器更新
    # 這裡主要檢查 Docker 組件的狀態
    
    local docker_version
    docker_version=$(docker --version 2>/dev/null | cut -d' ' -f3 | sed 's/,//')
    
    log_update $UPDATE_LEVEL_INFO "當前 Docker 版本: $docker_version"
    
    # 清理無用的 Docker 資源
    if docker system prune -f >/dev/null 2>&1; then
        log_update $UPDATE_LEVEL_INFO "Docker 系統清理完成"
    fi
    
    return 0
}

# 更新 Git
update_git() {
    log_update $UPDATE_LEVEL_INFO "檢查 Git 版本..."
    
    local git_version
    git_version=$(git --version 2>/dev/null | cut -d' ' -f3)
    
    log_update $UPDATE_LEVEL_INFO "當前 Git 版本: $git_version"
    
    # Git 通常通過系統套件管理器更新，這裡只做檢查
    return 0
}

# 更新 UV
update_uv() {
    if ! command -v uv >/dev/null 2>&1; then
        log_update $UPDATE_LEVEL_INFO "UV 未安裝，跳過更新"
        return 0
    fi
    
    log_update $UPDATE_LEVEL_INFO "更新 UV..."
    
    # 檢查當前版本
    local current_version
    current_version=$(uv --version 2>/dev/null | cut -d' ' -f2)
    
    # 嘗試自更新（如果支援）
    if uv self update 2>/dev/null; then
        local new_version
        new_version=$(uv --version 2>/dev/null | cut -d' ' -f2)
        
        if [ "$current_version" != "$new_version" ]; then
            log_update $UPDATE_LEVEL_INFO "UV 更新成功: $current_version -> $new_version"
        else
            log_update $UPDATE_LEVEL_INFO "UV 已是最新版本: $current_version"
        fi
        
        return 0
    else
        # 如果自更新失敗，嘗試重新安裝
        log_update $UPDATE_LEVEL_WARNING "UV 自更新失敗，嘗試重新安裝..."
        
        if curl -LsSf --connect-timeout 15 --max-time 180 https://astral.sh/uv/install.sh | sh; then
            log_update $UPDATE_LEVEL_INFO "UV 重新安裝成功"
            return 0
        else
            log_update $UPDATE_LEVEL_ERROR "UV 重新安裝失敗"
            return 1
        fi
    fi
}

# 更新 Zsh 插件
update_zsh_plugins() {
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        log_update $UPDATE_LEVEL_INFO "Oh My Zsh 未安裝，跳過更新"
        return 0
    fi
    
    log_update $UPDATE_LEVEL_INFO "更新 Zsh 插件..."
    
    # 更新 Oh My Zsh
    if [ -f "$HOME/.oh-my-zsh/tools/upgrade.sh" ]; then
        if sh "$HOME/.oh-my-zsh/tools/upgrade.sh"; then
            log_update $UPDATE_LEVEL_INFO "Oh My Zsh 更新成功"
        fi
    fi
    
    # 更新自定義插件目錄
    if [ -d "$HOME/.oh-my-zsh/custom/plugins" ]; then
        find "$HOME/.oh-my-zsh/custom/plugins" -name ".git" -type d | while read -r git_dir; do
            local plugin_dir=$(dirname "$git_dir")
            local plugin_name=$(basename "$plugin_dir")
            
            log_update $UPDATE_LEVEL_INFO "更新 Zsh 插件: $plugin_name"
            (cd "$plugin_dir" && git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || true)
        done
    fi
    
    return 0
}

# 更新 Vim 插件
update_vim_plugins() {
    log_update $UPDATE_LEVEL_INFO "檢查 Vim 插件..."
    
    # 如果使用 vim-plug
    if [ -f "$HOME/.vim/autoload/plug.vim" ]; then
        log_update $UPDATE_LEVEL_INFO "更新 Vim 插件 (vim-plug)..."
        vim +PlugUpdate +qall 2>/dev/null || true
        return 0
    fi
    
    # 如果使用 Vundle
    if [ -d "$HOME/.vim/bundle/Vundle.vim" ]; then
        log_update $UPDATE_LEVEL_INFO "更新 Vim 插件 (Vundle)..."
        vim +PluginUpdate +qall 2>/dev/null || true
        return 0
    fi
    
    log_update $UPDATE_LEVEL_INFO "未檢測到 Vim 插件管理器"
    return 0
}

# 更新 Linux Setting Scripts
update_linux_setting_scripts() {
    log_update $UPDATE_LEVEL_INFO "更新 Linux Setting Scripts..."
    
    local script_dir="$SCRIPT_DIR/.."
    
    # 檢查是否是 Git 倉庫
    if [ -d "$script_dir/.git" ]; then
        log_update $UPDATE_LEVEL_INFO "檢測到 Git 倉庫，拉取最新版本..."
        
        cd "$script_dir"
        
        # 暫存本地變更
        local has_changes=false
        if ! git diff --quiet || ! git diff --cached --quiet; then
            git stash push -m "Auto-stash before update $(date)"
            has_changes=true
        fi
        
        # 拉取最新版本
        if git pull origin main 2>/dev/null || git pull origin master 2>/dev/null; then
            log_update $UPDATE_LEVEL_INFO "Linux Setting Scripts 更新成功"
            
            # 如果有暫存的變更，恢復它們
            if [ "$has_changes" = "true" ]; then
                git stash pop 2>/dev/null || true
            fi
            
            return 0
        else
            log_update $UPDATE_LEVEL_ERROR "Linux Setting Scripts 更新失敗"
            return 1
        fi
    else
        log_update $UPDATE_LEVEL_INFO "Linux Setting Scripts 不是 Git 倉庫，無法自動更新"
        return 0
    fi
}

# 檢查更新
check_updates() {
    log_update $UPDATE_LEVEL_INFO "檢查系統更新..."
    
    init_update_components
    
    local updates_available=false
    local update_summary=()
    
    # 檢查系統套件更新
    if [ "$SYSTEM_UPDATE_ENABLED" = "true" ]; then
        sudo DEBIAN_FRONTEND=noninteractive apt-get update >/dev/null 2>&1
        local upgradeable
        upgradeable=$(apt list --upgradeable 2>/dev/null | grep -c upgradeable || true)
        
        if [ "$upgradeable" -gt 0 ]; then
            updates_available=true
            update_summary+=("系統套件: $upgradeable 個")
        fi
    fi
    
    # 檢查安全更新
    if [ "$SECURITY_UPDATE_ENABLED" = "true" ]; then
        local security_updates
        security_updates=$(apt list --upgradeable 2>/dev/null | grep -i security | wc -l)
        
        if [ "$security_updates" -gt 0 ]; then
            updates_available=true
            update_summary+=("安全更新: $security_updates 個")
        fi
    fi
    
    # 檢查其他組件更新（簡化檢查）
    local components_with_updates=()
    
    # Python 套件
    if command -v pip3 >/dev/null 2>&1; then
        if pip3 list --outdated 2>/dev/null | grep -q .; then
            components_with_updates+=("Python套件")
        fi
    fi
    
    # Node.js 套件
    if command -v npm >/dev/null 2>&1; then
        if npm outdated -g 2>/dev/null | grep -q .; then
            components_with_updates+=("Node.js套件")
        fi
    fi
    
    if [ ${#components_with_updates[@]} -gt 0 ]; then
        updates_available=true
        update_summary+=("應用程序: ${components_with_updates[*]}")
    fi
    
    if [ "$updates_available" = "true" ]; then
        log_update $UPDATE_LEVEL_INFO "發現可用更新: ${update_summary[*]}"
        return 0
    else
        log_update $UPDATE_LEVEL_INFO "系統已是最新狀態"
        return 1
    fi
}

# 執行自動更新
auto_update() {
    log_update $UPDATE_LEVEL_INFO "開始自動更新..."
    
    # 檢查更新鎖
    if ! check_update_lock; then
        return 1
    fi
    
    # 創建更新鎖
    create_update_lock
    trap 'remove_update_lock' EXIT
    
    # 創建系統備份
    create_system_backup
    
    # 初始化組件
    init_update_components
    
    local updated=0
    local failed=0
    
    # 更新各組件
    for component in "${!UPDATE_COMPONENTS[@]}"; do
        local update_function="${UPDATE_COMPONENTS[$component]}"
        
        # 檢查組件是否啟用
        case "$component" in
            "system"|"security"|"kernel")
                [ "$SYSTEM_UPDATE_ENABLED" != "true" ] && continue
                ;;
            "linux_setting")
                [ "$SCRIPT_UPDATE_ENABLED" != "true" ] && continue
                ;;
            *)
                [ "$PACKAGE_UPDATE_ENABLED" != "true" ] && continue
                ;;
        esac
        
        log_update $UPDATE_LEVEL_INFO "更新組件: $component"
        
        if $update_function; then
            log_update $UPDATE_LEVEL_INFO "組件 $component 更新成功"
            updated=$((updated + 1))
        else
            log_update $UPDATE_LEVEL_WARNING "組件 $component 更新失敗"
            failed=$((failed + 1))
        fi
    done
    
    # 檢查是否需要重啟
    check_reboot_required
    
    # 發送更新通知
    send_update_notification "自動更新完成" "成功更新 $updated 個組件，失敗 $failed 個"
    
    log_update $UPDATE_LEVEL_INFO "自動更新完成: 成功 $updated 個，失敗 $failed 個"
    
    return $failed
}

# 發送更新通知
send_update_notification() {
    local title="$1"
    local message="$2"
    
    # 嘗試使用系統通知
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "$title" "$message"
    elif command -v osascript >/dev/null 2>&1; then
        # macOS
        osascript -e "display notification \"$message\" with title \"$title\""
    fi
    
    log_update $UPDATE_LEVEL_INFO "通知: $title - $message"
}

# 啟動自動更新守護進程
start_auto_update_daemon() {
    local interval="${1:-$UPDATE_CHECK_INTERVAL}"
    
    log_info "啟動自動更新守護進程，檢查間隔: $interval 秒"
    
    # 檢查是否已在運行
    if [ -f "$UPDATE_CACHE_DIR/daemon.pid" ]; then
        local daemon_pid
        daemon_pid=$(cat "$UPDATE_CACHE_DIR/daemon.pid")
        if kill -0 "$daemon_pid" 2>/dev/null; then
            log_warning "自動更新守護進程已在運行 (PID: $daemon_pid)"
            return 1
        fi
    fi
    
    # 後台運行守護進程
    (
        echo $$ > "$UPDATE_CACHE_DIR/daemon.pid"
        log_update $UPDATE_LEVEL_INFO "自動更新守護進程已啟動 (PID: $$)"
        
        while true; do
            if [ "$AUTO_UPDATE_ENABLED" = "true" ]; then
                log_update $UPDATE_LEVEL_INFO "執行定期更新檢查..."
                
                if check_updates; then
                    auto_update
                fi
            fi
            
            sleep "$interval"
        done
    ) &
    
    log_success "自動更新守護進程已在後台啟動"
}

# 停止自動更新守護進程
stop_auto_update_daemon() {
    if [ -f "$UPDATE_CACHE_DIR/daemon.pid" ]; then
        local daemon_pid
        daemon_pid=$(cat "$UPDATE_CACHE_DIR/daemon.pid")
        if kill -0 "$daemon_pid" 2>/dev/null; then
            kill "$daemon_pid"
            rm -f "$UPDATE_CACHE_DIR/daemon.pid"
            log_success "自動更新守護進程已停止"
        else
            log_warning "自動更新守護進程未在運行"
            rm -f "$UPDATE_CACHE_DIR/daemon.pid"
        fi
    else
        log_warning "未找到自動更新守護進程"
    fi
}

# 顯示更新狀態
show_update_status() {
    log_info "自動更新狀態報告"
    
    echo "=== 自動更新配置 ==="
    echo "自動更新啟用: $AUTO_UPDATE_ENABLED"
    echo "系統更新啟用: $SYSTEM_UPDATE_ENABLED"
    echo "安全更新啟用: $SECURITY_UPDATE_ENABLED"
    echo "套件更新啟用: $PACKAGE_UPDATE_ENABLED"
    echo "腳本更新啟用: $SCRIPT_UPDATE_ENABLED"
    echo "檢查間隔: $UPDATE_CHECK_INTERVAL 秒"
    echo "更新前備份: $BACKUP_BEFORE_UPDATE"
    echo "重啟通知: $REBOOT_REQUIRED_NOTIFY"
    echo ""
    
    # 顯示組件狀態
    init_update_components
    echo "=== 更新組件狀態 ==="
    for component in "${!UPDATE_COMPONENTS[@]}"; do
        case "$component" in
            "python")
                if command -v python3 >/dev/null 2>&1; then
                    echo "  ✅ $component: $(python3 --version)"
                else
                    echo "  ❌ $component: 未安裝"
                fi
                ;;
            "nodejs")
                if command -v node >/dev/null 2>&1; then
                    echo "  ✅ $component: $(node --version)"
                else
                    echo "  ❌ $component: 未安裝"
                fi
                ;;
            "docker")
                if command -v docker >/dev/null 2>&1; then
                    echo "  ✅ $component: $(docker --version | cut -d' ' -f3 | sed 's/,//')"
                else
                    echo "  ❌ $component: 未安裝"
                fi
                ;;
            "git")
                if command -v git >/dev/null 2>&1; then
                    echo "  ✅ $component: $(git --version | cut -d' ' -f3)"
                else
                    echo "  ❌ $component: 未安裝"
                fi
                ;;
            "uv")
                if command -v uv >/dev/null 2>&1; then
                    echo "  ✅ $component: $(uv --version | cut -d' ' -f2)"
                else
                    echo "  ❌ $component: 未安裝"
                fi
                ;;
            *)
                echo "  📦 $component: 可更新"
                ;;
        esac
    done
    echo ""
    
    # 檢查是否需要重啟
    if [ -f "/var/run/reboot-required" ]; then
        echo "=== 系統狀態 ==="
        echo "⚠️  系統需要重啟以完成更新"
        echo ""
    fi
    
    # 顯示最近的更新記錄
    if [ -f "$UPDATE_LOG_FILE" ]; then
        echo "=== 最近的更新記錄 ==="
        tail -10 "$UPDATE_LOG_FILE"
    fi
}

# 清理更新緩存
cleanup_update_cache() {
    log_info "清理更新緩存..."
    
    # 停止守護進程
    stop_auto_update_daemon
    
    # 清理鎖文件
    rm -f "$UPDATE_LOCK_FILE"
    
    # 清理舊的備份（保留最近3個）
    if [ -d "$UPDATE_CACHE_DIR" ]; then
        find "$UPDATE_CACHE_DIR" -name "backup_*" -type d | sort -r | tail -n +4 | xargs rm -rf 2>/dev/null || true
    fi
    
    # 清理舊的日誌（保留最近7天）
    if [ -d "$(dirname "$UPDATE_LOG_FILE")" ]; then
        find "$(dirname "$UPDATE_LOG_FILE")" -name "auto_update_*.log" -mtime +7 -delete 2>/dev/null || true
    fi
    
    log_success "更新緩存清理完成"
}

# 命令行接口
case "${1:-help}" in
    "status")
        show_update_status
        ;;
    "check")
        if check_updates; then
            echo "發現可用更新 📦"
            exit 0
        else
            echo "系統已是最新狀態 ✅"
            exit 1
        fi
        ;;
    "update")
        auto_update
        ;;
    "daemon")
        case "${2:-start}" in
            "start")
                start_auto_update_daemon "$3"
                ;;
            "stop")
                stop_auto_update_daemon
                ;;
            "restart")
                stop_auto_update_daemon
                sleep 2
                start_auto_update_daemon "$3"
                ;;
            *)
                echo "用法: $0 daemon {start|stop|restart} [間隔秒數]"
                ;;
        esac
        ;;
    "cleanup")
        cleanup_update_cache
        ;;
    "reboot")
        if [ -f "/var/run/reboot-required" ]; then
            # 非互動：絕不自動重啟，只提示。互動時才詢問。
            if [ "${NON_INTERACTIVE:-false}" = "true" ] || [ ! -t 0 ]; then
                log_warning "系統需要重啟，但當前為非互動模式。請手動執行 'sudo reboot' 或 'sudo shutdown -r now'"
            else
                echo "系統需要重啟，是否現在重啟？(y/N)"
                read -r response
                if [[ "$response" =~ ^[Yy] ]]; then
                    log_info "系統將在 1 分鐘後重啟..."
                    sudo shutdown -r +1 "系統更新後自動重啟"
                fi
            fi
        else
            echo "系統不需要重啟"
        fi
        ;;
    *)
        echo "自動更新機制"
        echo ""
        echo "用法: $0 <command> [選項]"
        echo ""
        echo "命令:"
        echo "  status               顯示更新狀態"
        echo "  check                檢查可用更新"
        echo "  update               執行自動更新"
        echo "  daemon start [間隔]  啟動自動更新守護進程"
        echo "  daemon stop          停止自動更新守護進程"
        echo "  daemon restart [間隔] 重啟自動更新守護進程"
        echo "  cleanup              清理更新緩存"
        echo "  reboot               檢查並處理重啟需求"
        echo ""
        echo "環境變數:"
        echo "  AUTO_UPDATE_ENABLED      啟用自動更新"
        echo "  SYSTEM_UPDATE_ENABLED    啟用系統更新"
        echo "  SECURITY_UPDATE_ENABLED  啟用安全更新"
        echo "  PACKAGE_UPDATE_ENABLED   啟用套件更新"
        echo "  SCRIPT_UPDATE_ENABLED    啟用腳本更新"
        echo "  UPDATE_CHECK_INTERVAL    檢查間隔"
        echo "  BACKUP_BEFORE_UPDATE     更新前備份"
        echo "  REBOOT_REQUIRED_NOTIFY   重啟通知"
        echo ""
        echo "範例:"
        echo "  $0 status            # 檢查更新狀態"
        echo "  $0 check             # 檢查可用更新"
        echo "  $0 update            # 手動執行更新"
        echo "  $0 daemon start 43200 # 每12小時檢查更新"
        echo ""
        echo "日誌文件: $UPDATE_LOG_FILE"
        ;;
esac

log_success "########## 自動更新機制執行完成 ##########"