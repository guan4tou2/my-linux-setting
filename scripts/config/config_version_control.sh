#!/bin/bash

# 配置版本控制系統 - Git-based 配置文件版本管理

# 載入共用函數庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || exit 1
if [ -f "$SCRIPT_DIR/config_manager_simple.sh" ]; then
    source "$SCRIPT_DIR/config_manager_simple.sh" 2>/dev/null || true
fi

log_info "########## 配置版本控制系統 ##########"

readonly VERSION_CONTROL_DIR="$HOME/.config/linux-setting/version-control"
readonly CONFIG_REPO_DIR="$VERSION_CONTROL_DIR/config-repo"
readonly VERSION_LOG_FILE="$HOME/.local/log/linux-setting/version_control_$(date +%Y%m%d).log"
readonly VERSION_CACHE_DIR="$HOME/.cache/linux-setting/version-control"

# 確保目錄存在
mkdir -p "$VERSION_CONTROL_DIR"
mkdir -p "$VERSION_CACHE_DIR"
mkdir -p "$(dirname "$VERSION_LOG_FILE")"

# 版本控制配置
VERSION_CONTROL_ENABLED="${VERSION_CONTROL_ENABLED:-true}"
AUTO_COMMIT_ENABLED="${AUTO_COMMIT_ENABLED:-true}"
REMOTE_BACKUP_ENABLED="${REMOTE_BACKUP_ENABLED:-false}"
CONFIG_REPO_URL="${CONFIG_REPO_URL:-}"
COMMIT_MESSAGE_PREFIX="${COMMIT_MESSAGE_PREFIX:-[auto]}"

# 受版本控制的配置文件和目錄
TRACKED_CONFIGS=(
    "$HOME/.bashrc"
    "$HOME/.zshrc"
    "$HOME/.gitconfig"
    "$HOME/.vimrc"
    "$HOME/.profile"
    "$HOME/.bash_aliases"
    "$HOME/.ssh/config"
    "$HOME/.config/linux-setting"
)

# 記錄版本控制日誌
log_version_control() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" >> "$VERSION_LOG_FILE"
    
    case "$level" in
        "ERROR") log_error "$message" ;;
        "WARN") log_warning "$message" ;;
        "INFO") log_info "$message" ;;
        *) log_debug "$message" ;;
    esac
}

# 初始化配置倉庫
init_config_repo() {
    log_version_control "INFO" "初始化配置版本控制倉庫..."
    
    if [ -d "$CONFIG_REPO_DIR/.git" ]; then
        log_version_control "INFO" "配置倉庫已存在"
        return 0
    fi
    
    # 創建倉庫目錄
    mkdir -p "$CONFIG_REPO_DIR"
    cd "$CONFIG_REPO_DIR"
    
    # 初始化 Git 倉庫
    if ! git init; then
        log_version_control "ERROR" "Git 倉庫初始化失敗"
        return 1
    fi
    
    # 設置 Git 配置
    git config user.name "${GIT_USER_NAME:-Linux Setting Scripts}"
    git config user.email "${GIT_USER_EMAIL:-noreply@linux-setting.local}"
    git config init.defaultBranch main
    
    # 創建 .gitignore
    cat > .gitignore << 'EOF'
# 忽略敏感文件
*.log
*.tmp
*.cache
.DS_Store
Thumbs.db

# SSH 私鑰
**/ssh/*_rsa
**/ssh/*_ed25519
**/ssh/*_ecdsa
**/ssh/id_*
!**/ssh/*.pub

# 其他敏感信息
*password*
*secret*
*token*
.env
EOF
    
    # 創建 README
    cat > README.md << 'EOF'
# Linux Setting 配置文件版本控制

此倉庫用於管理 Linux Setting Scripts 相關的配置文件版本。

## 包含的配置文件

- Shell 配置 (.bashrc, .zshrc, .profile, .bash_aliases)
- Git 配置 (.gitconfig)
- Vim 配置 (.vimrc)
- SSH 配置 (.ssh/config)
- Linux Setting 專用配置 (.config/linux-setting/)

## 自動提交

配置文件的變更會自動檢測並提交到版本控制系統。

## 安全性

敏感文件（如 SSH 私鑰）已被排除在版本控制之外。
EOF
    
    # 初始提交
    git add .gitignore README.md
    git commit -m "Initial commit: Setup config version control"
    
    log_version_control "INFO" "配置倉庫初始化完成"
    
    # 如果有遠程倉庫，設置 remote
    if [ -n "$CONFIG_REPO_URL" ]; then
        setup_remote_repo "$CONFIG_REPO_URL"
    fi
    
    return 0
}

# 設置遠程倉庫
setup_remote_repo() {
    local repo_url="$1"
    
    log_version_control "INFO" "設置遠程倉庫: $repo_url"
    
    cd "$CONFIG_REPO_DIR"
    
    # 檢查是否已經設置了遠程倉庫
    if git remote get-url origin >/dev/null 2>&1; then
        git remote set-url origin "$repo_url"
    else
        git remote add origin "$repo_url"
    fi
    
    # 嘗試推送到遠程倉庫
    if git push -u origin main 2>/dev/null; then
        log_version_control "INFO" "遠程倉庫設置成功"
        return 0
    else
        log_version_control "WARN" "無法推送到遠程倉庫，可能需要認證"
        return 1
    fi
}

# 計算文件哈希
calculate_config_hash() {
    local config_path="$1"
    
    if [ ! -e "$config_path" ]; then
        echo "missing"
        return
    fi
    
    if [ -f "$config_path" ]; then
        sha256sum "$config_path" 2>/dev/null | cut -d' ' -f1
    elif [ -d "$config_path" ]; then
        # 對目錄計算內容哈希
        find "$config_path" -type f -exec sha256sum {} \; 2>/dev/null | sort | sha256sum | cut -d' ' -f1
    else
        echo "unknown"
    fi
}

# 複製配置到倉庫
copy_config_to_repo() {
    local config_path="$1"
    local relative_path="${config_path#$HOME/}"
    local repo_path="$CONFIG_REPO_DIR/$relative_path"
    
    # 跳過不存在的文件
    if [ ! -e "$config_path" ]; then
        return 0
    fi
    
    # 創建目標目錄
    mkdir -p "$(dirname "$repo_path")"
    
    if [ -f "$config_path" ]; then
        # 複製文件
        if cp "$config_path" "$repo_path"; then
            log_version_control "DEBUG" "已複製: $relative_path"
            return 0
        else
            log_version_control "ERROR" "複製失敗: $relative_path"
            return 1
        fi
    elif [ -d "$config_path" ]; then
        # 複製目錄（排除敏感文件）
        if rsync -av --exclude='*.log' --exclude='*.cache' --exclude='*.tmp' \
               --exclude='*_rsa' --exclude='*_ed25519' --exclude='*_ecdsa' \
               --exclude='id_*' --include='*.pub' \
               "$config_path/" "$repo_path/"; then
            log_version_control "DEBUG" "已複製目錄: $relative_path"
            return 0
        else
            log_version_control "ERROR" "複製目錄失敗: $relative_path"
            return 1
        fi
    fi
}

# 從倉庫恢復配置
restore_config_from_repo() {
    local config_path="$1"
    local relative_path="${config_path#$HOME/}"
    local repo_path="$CONFIG_REPO_DIR/$relative_path"
    
    # 檢查倉庫中是否存在該配置
    if [ ! -e "$repo_path" ]; then
        log_version_control "WARN" "倉庫中不存在: $relative_path"
        return 1
    fi
    
    # 備份現有配置
    if [ -e "$config_path" ]; then
        local backup_path="${config_path}.backup.$(date +%s)"
        mv "$config_path" "$backup_path"
        log_version_control "INFO" "已備份現有配置: $backup_path"
    fi
    
    # 創建目標目錄
    mkdir -p "$(dirname "$config_path")"
    
    if [ -f "$repo_path" ]; then
        # 恢復文件
        if cp "$repo_path" "$config_path"; then
            log_version_control "INFO" "已恢復: $relative_path"
            return 0
        else
            log_version_control "ERROR" "恢復失敗: $relative_path"
            return 1
        fi
    elif [ -d "$repo_path" ]; then
        # 恢復目錄
        if rsync -av "$repo_path/" "$config_path/"; then
            log_version_control "INFO" "已恢復目錄: $relative_path"
            return 0
        else
            log_version_control "ERROR" "恢復目錄失敗: $relative_path"
            return 1
        fi
    fi
}

# 檢查配置變更
check_config_changes() {
    log_version_control "INFO" "檢查配置文件變更..."
    
    if [ ! -d "$CONFIG_REPO_DIR/.git" ]; then
        log_version_control "WARN" "配置倉庫未初始化"
        return 1
    fi
    
    local changes_detected=false
    local change_summary=()
    
    for config_path in "${TRACKED_CONFIGS[@]}"; do
        local relative_path="${config_path#$HOME/}"
        local repo_path="$CONFIG_REPO_DIR/$relative_path"
        
        if [ -e "$config_path" ]; then
            local current_hash
            local repo_hash
            
            current_hash=$(calculate_config_hash "$config_path")
            
            if [ -e "$repo_path" ]; then
                repo_hash=$(calculate_config_hash "$repo_path")
            else
                repo_hash="missing"
            fi
            
            if [ "$current_hash" != "$repo_hash" ]; then
                changes_detected=true
                if [ "$repo_hash" = "missing" ]; then
                    change_summary+=("NEW: $relative_path")
                else
                    change_summary+=("MODIFIED: $relative_path")
                fi
                log_version_control "INFO" "檢測到變更: $relative_path"
            fi
        elif [ -e "$repo_path" ]; then
            changes_detected=true
            change_summary+=("DELETED: $relative_path")
            log_version_control "INFO" "檢測到刪除: $relative_path"
        fi
    done
    
    if [ "$changes_detected" = "true" ]; then
        log_version_control "INFO" "發現 ${#change_summary[@]} 個變更: ${change_summary[*]}"
        return 0
    else
        log_version_control "INFO" "未發現配置變更"
        return 1
    fi
}

# 提交配置變更
commit_config_changes() {
    local commit_message="$1"
    
    if [ -z "$commit_message" ]; then
        commit_message="$COMMIT_MESSAGE_PREFIX Auto-commit configuration changes"
    fi
    
    log_version_control "INFO" "提交配置變更..."
    
    cd "$CONFIG_REPO_DIR"
    
    # 複製所有追蹤的配置到倉庫
    local copied=0
    for config_path in "${TRACKED_CONFIGS[@]}"; do
        if copy_config_to_repo "$config_path"; then
            copied=$((copied + 1))
        fi
    done
    
    # 檢查是否有變更
    if ! git diff --quiet || ! git diff --cached --quiet; then
        # 添加所有變更
        git add .
        
        # 檢查是否有東西要提交
        if ! git diff --cached --quiet; then
            # 創建提交
            if git commit -m "$commit_message"; then
                local commit_hash
                commit_hash=$(git rev-parse HEAD)
                log_version_control "INFO" "配置變更已提交: $commit_hash"
                
                # 推送到遠程倉庫
                if [ "$REMOTE_BACKUP_ENABLED" = "true" ] && git remote get-url origin >/dev/null 2>&1; then
                    push_to_remote
                fi
                
                return 0
            else
                log_version_control "ERROR" "提交失敗"
                return 1
            fi
        else
            log_version_control "INFO" "沒有變更需要提交"
            return 0
        fi
    else
        log_version_control "INFO" "沒有檢測到變更"
        return 0
    fi
}

# 推送到遠程倉庫
push_to_remote() {
    log_version_control "INFO" "推送到遠程倉庫..."
    
    cd "$CONFIG_REPO_DIR"
    
    if git push origin main; then
        log_version_control "INFO" "成功推送到遠程倉庫"
        return 0
    else
        log_version_control "WARN" "推送到遠程倉庫失敗"
        return 1
    fi
}

# 從遠程倉庫拉取
pull_from_remote() {
    log_version_control "INFO" "從遠程倉庫拉取..."
    
    cd "$CONFIG_REPO_DIR"
    
    # 檢查是否有未提交的變更
    if ! git diff --quiet || ! git diff --cached --quiet; then
        log_version_control "WARN" "有未提交的變更，先提交本地變更"
        commit_config_changes "Save local changes before pull"
    fi
    
    if git pull origin main; then
        log_version_control "INFO" "成功從遠程倉庫拉取"
        return 0
    else
        log_version_control "ERROR" "從遠程倉庫拉取失敗"
        return 1
    fi
}

# 創建配置分支
create_config_branch() {
    local branch_name="$1"
    
    if [ -z "$branch_name" ]; then
        log_version_control "ERROR" "請指定分支名稱"
        return 1
    fi
    
    cd "$CONFIG_REPO_DIR"
    
    if git checkout -b "$branch_name"; then
        log_version_control "INFO" "已創建並切換到分支: $branch_name"
        return 0
    else
        log_version_control "ERROR" "創建分支失敗: $branch_name"
        return 1
    fi
}

# 切換配置分支
switch_config_branch() {
    local branch_name="$1"
    
    if [ -z "$branch_name" ]; then
        log_version_control "ERROR" "請指定分支名稱"
        return 1
    fi
    
    cd "$CONFIG_REPO_DIR"
    
    # 檢查分支是否存在
    if ! git show-ref --verify --quiet "refs/heads/$branch_name"; then
        log_version_control "ERROR" "分支不存在: $branch_name"
        return 1
    fi
    
    # 保存當前變更
    if ! git diff --quiet || ! git diff --cached --quiet; then
        commit_config_changes "Auto-save before branch switch"
    fi
    
    if git checkout "$branch_name"; then
        log_version_control "INFO" "已切換到分支: $branch_name"
        
        # 恢復該分支的配置到系統
        restore_all_configs
        
        return 0
    else
        log_version_control "ERROR" "切換分支失敗: $branch_name"
        return 1
    fi
}

# 恢復所有配置
restore_all_configs() {
    log_version_control "INFO" "恢復所有配置文件..."
    
    local restored=0
    local failed=0
    
    for config_path in "${TRACKED_CONFIGS[@]}"; do
        if restore_config_from_repo "$config_path"; then
            restored=$((restored + 1))
        else
            failed=$((failed + 1))
        fi
    done
    
    log_version_control "INFO" "配置恢復完成: 成功 $restored 個，失敗 $failed 個"
    return $failed
}

# 列出版本歷史
list_version_history() {
    local count="${1:-10}"
    
    if [ ! -d "$CONFIG_REPO_DIR/.git" ]; then
        log_version_control "ERROR" "配置倉庫未初始化"
        return 1
    fi
    
    cd "$CONFIG_REPO_DIR"
    
    log_info "配置版本歷史（最近 $count 個提交）："
    git log --oneline --graph --decorate -n "$count"
}

# 列出分支
list_branches() {
    if [ ! -d "$CONFIG_REPO_DIR/.git" ]; then
        log_version_control "ERROR" "配置倉庫未初始化"
        return 1
    fi
    
    cd "$CONFIG_REPO_DIR"
    
    log_info "配置分支列表："
    git branch -a
}

# 顯示配置差異
show_config_diff() {
    local target="${1:-HEAD~1}"
    
    if [ ! -d "$CONFIG_REPO_DIR/.git" ]; then
        log_version_control "ERROR" "配置倉庫未初始化"
        return 1
    fi
    
    cd "$CONFIG_REPO_DIR"
    
    log_info "配置差異 (vs $target)："
    git diff "$target"
}

# 回滾到指定版本
rollback_to_version() {
    local commit_hash="$1"
    
    if [ -z "$commit_hash" ]; then
        log_version_control "ERROR" "請指定提交哈希"
        return 1
    fi
    
    cd "$CONFIG_REPO_DIR"
    
    # 檢查提交是否存在
    if ! git cat-file -e "$commit_hash" 2>/dev/null; then
        log_version_control "ERROR" "提交不存在: $commit_hash"
        return 1
    fi
    
    # 保存當前狀態
    commit_config_changes "Save before rollback to $commit_hash"
    
    # 創建回滾分支
    local rollback_branch="rollback-$(date +%Y%m%d-%H%M%S)"
    git checkout -b "$rollback_branch" "$commit_hash"
    
    # 恢復配置
    restore_all_configs
    
    log_version_control "INFO" "已回滾到版本 $commit_hash，當前分支: $rollback_branch"
    return 0
}

# 自動版本控制守護進程
start_auto_versioning() {
    local check_interval="${1:-300}"  # 5分鐘
    
    log_info "啟動自動版本控制守護進程，檢查間隔: $check_interval 秒"
    
    # 檢查是否已在運行
    if [ -f "$VERSION_CACHE_DIR/versioning.pid" ]; then
        local daemon_pid
        daemon_pid=$(cat "$VERSION_CACHE_DIR/versioning.pid")
        if kill -0 "$daemon_pid" 2>/dev/null; then
            log_warning "自動版本控制守護進程已在運行 (PID: $daemon_pid)"
            return 1
        fi
    fi
    
    # 初始化倉庫
    if ! init_config_repo; then
        return 1
    fi
    
    # 後台運行守護進程
    (
        echo $$ > "$VERSION_CACHE_DIR/versioning.pid"
        log_version_control "INFO" "自動版本控制守護進程已啟動 (PID: $$)"
        
        while true; do
            if [ "$VERSION_CONTROL_ENABLED" = "true" ] && [ "$AUTO_COMMIT_ENABLED" = "true" ]; then
                log_version_control "INFO" "檢查配置文件變更..."
                
                if check_config_changes; then
                    commit_config_changes
                fi
            fi
            
            sleep "$check_interval"
        done
    ) &
    
    log_success "自動版本控制守護進程已在後台啟動"
}

# 停止自動版本控制守護進程
stop_auto_versioning() {
    if [ -f "$VERSION_CACHE_DIR/versioning.pid" ]; then
        local daemon_pid
        daemon_pid=$(cat "$VERSION_CACHE_DIR/versioning.pid")
        if kill -0 "$daemon_pid" 2>/dev/null; then
            kill "$daemon_pid"
            rm -f "$VERSION_CACHE_DIR/versioning.pid"
            log_success "自動版本控制守護進程已停止"
        else
            log_warning "自動版本控制守護進程未在運行"
            rm -f "$VERSION_CACHE_DIR/versioning.pid"
        fi
    else
        log_warning "未找到自動版本控制守護進程"
    fi
}

# 顯示版本控制狀態
show_version_status() {
    log_info "配置版本控制狀態"
    
    echo "=== 版本控制配置 ==="
    echo "啟用狀態: $VERSION_CONTROL_ENABLED"
    echo "自動提交: $AUTO_COMMIT_ENABLED"
    echo "遠程備份: $REMOTE_BACKUP_ENABLED"
    echo "倉庫目錄: $CONFIG_REPO_DIR"
    echo "遠程倉庫: ${CONFIG_REPO_URL:-未設定}"
    echo ""
    
    # 顯示倉庫狀態
    if [ -d "$CONFIG_REPO_DIR/.git" ]; then
        cd "$CONFIG_REPO_DIR"
        echo "=== Git 倉庫狀態 ==="
        echo "當前分支: $(git branch --show-current 2>/dev/null || echo '未知')"
        echo "最新提交: $(git log -1 --oneline 2>/dev/null || echo '無提交')"
        
        if git status --porcelain | grep -q .; then
            echo "未提交變更: ⚠️"
            git status --short
        else
            echo "工作目錄: 乾淨 ✅"
        fi
        echo ""
    else
        echo "=== Git 倉庫狀態 ==="
        echo "倉庫未初始化"
        echo ""
    fi
    
    # 顯示追蹤的配置文件
    echo "=== 追蹤的配置文件 ==="
    for config_path in "${TRACKED_CONFIGS[@]}"; do
        local relative_path="${config_path#$HOME/}"
        local status="❌ 不存在"
        
        if [ -f "$config_path" ]; then
            status="📄 文件"
        elif [ -d "$config_path" ]; then
            status="📁 目錄"
        fi
        
        echo "  $relative_path: $status"
    done
    echo ""
    
    # 顯示最近的版本控制記錄
    if [ -f "$VERSION_LOG_FILE" ]; then
        echo "=== 最近的版本控制記錄 ==="
        tail -10 "$VERSION_LOG_FILE"
    fi
}

# 清理版本控制緩存
cleanup_version_cache() {
    log_info "清理版本控制緩存..."
    
    # 停止守護進程
    stop_auto_versioning
    
    # 清理舊的日誌（保留最近7天）
    if [ -d "$(dirname "$VERSION_LOG_FILE")" ]; then
        find "$(dirname "$VERSION_LOG_FILE")" -name "version_control_*.log" -mtime +7 -delete 2>/dev/null || true
    fi
    
    # 清理 Git GC
    if [ -d "$CONFIG_REPO_DIR/.git" ]; then
        cd "$CONFIG_REPO_DIR"
        git gc --prune=now
        log_version_control "INFO" "Git 倉庫已清理"
    fi
    
    log_success "版本控制緩存清理完成"
}

# 命令行接口
case "${1:-help}" in
    "init")
        init_config_repo
        ;;
    "status")
        show_version_status
        ;;
    "check")
        if check_config_changes; then
            echo "發現配置變更 ⚠️"
            exit 1
        else
            echo "配置無變更 ✅"
            exit 0
        fi
        ;;
    "commit")
        commit_config_changes "$2"
        ;;
    "history")
        list_version_history "$2"
        ;;
    "diff")
        show_config_diff "$2"
        ;;
    "rollback")
        if [ -z "$2" ]; then
            log_error "請指定提交哈希"
            exit 1
        fi
        rollback_to_version "$2"
        ;;
    "branch")
        case "${2:-list}" in
            "list")
                list_branches
                ;;
            "create")
                if [ -z "$3" ]; then
                    log_error "請指定分支名稱"
                    exit 1
                fi
                create_config_branch "$3"
                ;;
            "switch")
                if [ -z "$3" ]; then
                    log_error "請指定分支名稱"
                    exit 1
                fi
                switch_config_branch "$3"
                ;;
            *)
                echo "用法: $0 branch {list|create|switch} [分支名稱]"
                ;;
        esac
        ;;
    "restore")
        restore_all_configs
        ;;
    "remote")
        case "${2:-}" in
            "add")
                if [ -z "$3" ]; then
                    log_error "請指定遠程倉庫 URL"
                    exit 1
                fi
                setup_remote_repo "$3"
                ;;
            "push")
                push_to_remote
                ;;
            "pull")
                pull_from_remote
                ;;
            *)
                echo "用法: $0 remote {add|push|pull} [URL]"
                ;;
        esac
        ;;
    "auto")
        case "${2:-start}" in
            "start")
                start_auto_versioning "$3"
                ;;
            "stop")
                stop_auto_versioning
                ;;
            "restart")
                stop_auto_versioning
                sleep 2
                start_auto_versioning "$3"
                ;;
            *)
                echo "用法: $0 auto {start|stop|restart} [間隔秒數]"
                ;;
        esac
        ;;
    "cleanup")
        cleanup_version_cache
        ;;
    *)
        echo "配置版本控制系統"
        echo ""
        echo "用法: $0 <command> [選項]"
        echo ""
        echo "命令:"
        echo "  init                 初始化配置倉庫"
        echo "  status               顯示版本控制狀態"
        echo "  check                檢查配置變更"
        echo "  commit [訊息]        提交配置變更"
        echo "  history [數量]       顯示版本歷史"
        echo "  diff [目標]          顯示配置差異"
        echo "  rollback <哈希>      回滾到指定版本"
        echo "  branch list          列出分支"
        echo "  branch create <名稱> 創建分支"
        echo "  branch switch <名稱> 切換分支"
        echo "  restore              恢復所有配置"
        echo "  remote add <URL>     添加遠程倉庫"
        echo "  remote push          推送到遠程"
        echo "  remote pull          從遠程拉取"
        echo "  auto start [間隔]    啟動自動版本控制"
        echo "  auto stop            停止自動版本控制"
        echo "  auto restart [間隔]  重啟自動版本控制"
        echo "  cleanup              清理版本控制緩存"
        echo ""
        echo "環境變數:"
        echo "  VERSION_CONTROL_ENABLED  啟用版本控制"
        echo "  AUTO_COMMIT_ENABLED      啟用自動提交"
        echo "  REMOTE_BACKUP_ENABLED    啟用遠程備份"
        echo "  CONFIG_REPO_URL          遠程倉庫 URL"
        echo "  COMMIT_MESSAGE_PREFIX    提交訊息前綴"
        echo ""
        echo "範例:"
        echo "  $0 init              # 初始化倉庫"
        echo "  $0 commit            # 手動提交變更"
        echo "  $0 branch create dev # 創建開發分支"
        echo "  $0 auto start 300    # 5分鐘間隔自動版本控制"
        echo ""
        echo "倉庫目錄: $CONFIG_REPO_DIR"
        echo "日誌文件: $VERSION_LOG_FILE"
        ;;
esac

log_success "########## 配置版本控制系統執行完成 ##########"