#!/usr/bin/env bash

# ==============================================================================
# Linux 環境設定腳本 - 卸載工具
#
# 依據 install.sh 寫下的安裝清單移除「本工具實際新增」的內容：
#   package:<名稱>      本工具新安裝的系統套件
#   path:<絕對路徑>     本工具建立的檔案或目錄（只允許 $HOME 或 /usr/local/bin 之下，
#                       另加 /etc/apt/apt.conf.d/ 下 APT 優化的三個確切檔名）
#   file:<絕對路徑>     安裝前已存在、被修改且有備份的設定檔（從最早的備份還原）
#   backup:<目錄>       對應的備份目錄（需位於 ~/.config/linux-setting-backup 之下）
# 安裝清單：${XDG_CONFIG_HOME:-$HOME/.config}/linux-setting/installed.manifest
# ==============================================================================

set -uo pipefail

# 顏色定義
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

MANIFEST_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/linux-setting"
MANIFEST_FILE="$MANIFEST_DIR/installed.manifest"
BACKUP_DIR="$HOME/.config/linux-setting-backup"

# 顯示幫助
show_help() {
    cat << EOF
Linux Setting Scripts - 卸載工具

用法: $0 [選項]

依據安裝清單（$MANIFEST_FILE）
移除本工具新安裝的套件與檔案，並從最早的備份還原被修改的設定檔。

選項:
  --packages-only     僅移除套件，保留其他內容
  --configs-only      僅移除本工具建立的檔案並還原設定檔，保留套件
  --full              完全卸載（預設）
  --dry-run           只列出將要執行的動作，不實際執行
  -y, --yes           自動確認，不詢問
  -h, --help          顯示此幫助訊息

範例:
  $0 --dry-run        # 預覽將要執行的動作
  $0                  # 完全卸載（互動式）
  $0 --packages-only  # 僅移除套件
  $0 -y               # 自動確認卸載

EOF
}

# 解析參數
PACKAGES_ONLY=false
CONFIGS_ONLY=false
AUTO_YES=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --packages-only)
            PACKAGES_ONLY=true
            shift
            ;;
        --configs-only)
            CONFIGS_ONLY=true
            shift
            ;;
        --full)
            # 預設就是 full，這個參數只是為了明確性
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -y|--yes)
            AUTO_YES=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "未知參數: $1"
            show_help
            exit 1
            ;;
    esac
done

if [ "$PACKAGES_ONLY" = true ] && [ "$CONFIGS_ONLY" = true ]; then
    printf "${RED}--packages-only 與 --configs-only 不能同時使用${NC}\n"
    exit 1
fi

# 檢查是否有安裝記錄
if [ ! -f "$MANIFEST_FILE" ]; then
    printf "${YELLOW}未找到安裝記錄${NC}\n"
    printf "看起來尚未通過 install.sh 安裝過，或記錄文件已被刪除\n"
    printf "\n你仍然可以手動執行以下操作：\n"
    printf "  1. 移除套件: sudo apt remove zsh neovim docker-ce ...\n"
    printf "  2. 刪除設定: rm -rf ~/.p10k.zsh ~/.oh-my-zsh ~/.config/nvim\n"
    printf "  3. 還原備份: 備份在 %s/<時間>/，可執行 ./install.sh --rollback\n" "$BACKUP_DIR"
    exit 1
fi

# ------------------------------------------------------------------------------
# 讀取安裝清單（相容 bash 3.2；去除重複、保留出現順序）
# ------------------------------------------------------------------------------
PACKAGES=()
PATHS=()
FILES=()
BACKUPS=()

array_has() {
    local needle="$1" item
    shift
    for item in "$@"; do
        [ "$item" = "$needle" ] && return 0
    done
    return 1
}

while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
        ""|"#"*) ;;
        package:*)
            value="${line#package:}"
            if ! array_has "$value" ${PACKAGES[@]+"${PACKAGES[@]}"}; then PACKAGES+=("$value"); fi
            ;;
        path:*)
            value="${line#path:}"
            if ! array_has "$value" ${PATHS[@]+"${PATHS[@]}"}; then PATHS+=("$value"); fi
            ;;
        file:*)
            value="${line#file:}"
            if ! array_has "$value" ${FILES[@]+"${FILES[@]}"}; then FILES+=("$value"); fi
            ;;
        backup:*)
            value="${line#backup:}"
            if ! array_has "$value" ${BACKUPS[@]+"${BACKUPS[@]}"}; then BACKUPS+=("$value"); fi
            ;;
        *)
            printf "${YELLOW}⚠${NC}  忽略無法辨識的清單行: %s\n" "$line"
            ;;
    esac
done < "$MANIFEST_FILE"

# ------------------------------------------------------------------------------
# 路徑安全檢查
#   allowed_target <路徑> <是否允許 /usr/local/bin: yes|no>
#   通過回傳 0；否則回傳 1 並把原因放進 REJECT_REASON。
#   - 必須是絕對路徑，且位於 $HOME 或 /usr/local/bin 之下（不含根目錄本身）
#   - 不得含 . 或 .. 路徑段
#   - 若該路徑已存在，其「父目錄」解析符號連結後仍須在允許範圍內
#     （路徑本身若是符號連結，只會移除連結，不會追蹤到目標）
# ------------------------------------------------------------------------------
REJECT_REASON=""
HOME_TRIMMED="${HOME%/}"
HOME_REAL="$(cd -P "$HOME" 2>/dev/null && pwd -P || printf '%s' "$HOME_TRIMMED")"
BIN_REAL="$(cd -P /usr/local/bin 2>/dev/null && pwd -P || printf '%s' /usr/local/bin)"

under_dir() {
    # under_dir <路徑> <根目錄>：路徑是否位於根目錄之下（不含根目錄本身）
    case "$1" in
        "$2"/?*) return 0 ;;
    esac
    return 1
}

allowed_target() {
    local p="$1" allow_bin="${2:-no}" root="" root_real=""
    REJECT_REASON=""

    case "$p" in
        /*) ;;
        *) REJECT_REASON="不是絕對路徑"; return 1 ;;
    esac
    case "$p" in
        *$'\n'*|*/./*|*/.|*/../*|*/..|*//*)
            REJECT_REASON="含有不安全的路徑段"
            return 1
            ;;
    esac
    p="${p%/}"

    # 例外：install.sh 的 APT 優化會建立的三個確切檔名（其他 /etc 路徑一律拒絕）
    if [ "$allow_bin" = "yes" ]; then
        case "$p" in
            /etc/apt/apt.conf.d/99-parallel-downloads|/etc/apt/apt.conf.d/99-cache-optimization|/etc/apt/apt.conf.d/99-timeout)
                return 0
                ;;
        esac
    fi

    if under_dir "$p" "$HOME_TRIMMED"; then
        root="$HOME_TRIMMED"
        root_real="$HOME_REAL"
    elif [ "$allow_bin" = "yes" ] && under_dir "$p" "/usr/local/bin"; then
        root="/usr/local/bin"
        root_real="$BIN_REAL"
    else
        REJECT_REASON="不在允許範圍（僅限 \$HOME$([ "$allow_bin" = "yes" ] && printf ' 或 /usr/local/bin')之下）"
        return 1
    fi

    if [ -e "$p" ] || [ -L "$p" ]; then
        local parent_real
        parent_real="$(cd -P "$(dirname "$p")" 2>/dev/null && pwd -P)" || parent_real=""
        if [ -z "$parent_real" ]; then
            REJECT_REASON="無法解析上層目錄"
            return 1
        fi
        if [ "$parent_real" != "$root_real" ] && ! under_dir "$parent_real/x" "$root_real"; then
            REJECT_REASON="上層目錄經由符號連結指向 $root 之外"
            return 1
        fi
    fi
    return 0
}

# 備份來源目錄必須位於 ~/.config/linux-setting-backup 之下，且實際位置也在其中
BACKUP_ROOT_REAL="$(cd -P "$BACKUP_DIR" 2>/dev/null && pwd -P || printf '%s' "$BACKUP_DIR")"

backup_dir_ok() {
    local d="${1%/}"
    case "$d" in
        "$BACKUP_DIR"/?*) ;;
        *) return 1 ;;
    esac
    case "$d" in
        */./*|*/../*|*/..|*/.|*//*) return 1 ;;
    esac
    [ -d "$d" ] || return 1
    local real
    real="$(cd -P "$d" 2>/dev/null && pwd -P)" || return 1
    under_dir "$real" "$BACKUP_ROOT_REAL"
}

# 找出某個設定檔最早的備份（依清單中 backup 的順序）
find_backup_for() {
    local file="$1" name dir
    name="$(basename "$file")"
    for dir in ${BACKUPS[@]+"${BACKUPS[@]}"}; do
        if backup_dir_ok "$dir" && { [ -e "${dir%/}/$name" ] || [ -L "${dir%/}/$name" ]; }; then
            printf '%s\n' "${dir%/}/$name"
            return 0
        fi
    done
    return 1
}

# ------------------------------------------------------------------------------
# 規劃動作
# ------------------------------------------------------------------------------
PLAN_PATHS=()          # 將移除的路徑
PLAN_FILES=()          # 將還原的設定檔
PLAN_FILE_SRCS=()      # 對應的備份來源
PLAN_PACKAGES=()       # 將移除的套件
SKIPPED_NOTES=()       # 被拒絕或無法處理的項目說明

if [ "$PACKAGES_ONLY" != true ]; then
    for p in ${PATHS[@]+"${PATHS[@]}"}; do
        if allowed_target "$p" yes; then
            PLAN_PATHS+=("${p%/}")
        else
            SKIPPED_NOTES+=("拒絕移除 $p：$REJECT_REASON")
        fi
    done

    for f in ${FILES[@]+"${FILES[@]}"}; do
        if ! allowed_target "$f" no; then
            SKIPPED_NOTES+=("拒絕還原 $f：$REJECT_REASON")
            continue
        fi
        if src="$(find_backup_for "$f")"; then
            PLAN_FILES+=("${f%/}")
            PLAN_FILE_SRCS+=("$src")
        else
            SKIPPED_NOTES+=("找不到 $f 的備份，保留目前內容")
        fi
    done
fi

if [ "$CONFIGS_ONLY" != true ]; then
    for pkg in ${PACKAGES[@]+"${PACKAGES[@]}"}; do
        # 套件名稱只允許常見字元，避免被當成選項或夾帶指令
        if [[ "$pkg" =~ ^[A-Za-z0-9][A-Za-z0-9+._:-]*$ ]]; then
            PLAN_PACKAGES+=("$pkg")
        else
            SKIPPED_NOTES+=("拒絕移除套件 '$pkg'：名稱不合法")
        fi
    done
fi

# 顯示將要執行的動作
printf "\n${CYAN}========== 卸載預覽 ==========${NC}\n\n"
if [ "$DRY_RUN" = true ]; then
    printf "${YELLOW}（--dry-run：只列出動作，不會變更任何東西）${NC}\n\n"
fi

if [ "$PACKAGES_ONLY" != true ]; then
    printf "${YELLOW}將移除以下路徑 (%d 個):${NC}\n" "${#PLAN_PATHS[@]}"
    for p in ${PLAN_PATHS[@]+"${PLAN_PATHS[@]}"}; do
        if [ -e "$p" ] || [ -L "$p" ]; then
            printf "  - %s\n" "$p"
        else
            printf "  - %s（已不存在，略過）\n" "$p"
        fi
    done
    printf "\n"

    printf "${YELLOW}將還原以下設定檔 (%d 個):${NC}\n" "${#PLAN_FILES[@]}"
    for i in ${PLAN_FILES[@]+"${!PLAN_FILES[@]}"}; do
        printf "  - %s  <-  %s\n" "${PLAN_FILES[$i]}" "${PLAN_FILE_SRCS[$i]}"
    done
    printf "\n"
fi

if [ "$CONFIGS_ONLY" != true ]; then
    printf "${YELLOW}將移除以下套件 (%d 個):${NC}\n" "${#PLAN_PACKAGES[@]}"
    for pkg in ${PLAN_PACKAGES[@]+"${PLAN_PACKAGES[@]}"}; do
        printf "  - %s\n" "$pkg"
    done
    if [ "${#PLAN_PACKAGES[@]}" -gt 0 ]; then
        printf "${YELLOW}⚠${NC}  移除套件時，套件管理器可能一併移除依賴它們的其他套件。\n"
    fi
    printf "\n"
fi

for note in ${SKIPPED_NOTES[@]+"${SKIPPED_NOTES[@]}"}; do
    printf "${YELLOW}⚠${NC}  %s\n" "$note"
done
if [ "${#SKIPPED_NOTES[@]}" -gt 0 ]; then
    printf "\n"
fi

if [ "$DRY_RUN" = true ]; then
    printf "${GREEN}預覽結束，未做任何變更。${NC}\n"
    exit 0
fi

# 確認
if [ "$AUTO_YES" != true ]; then
    # 非互動模式：除非明確 -y / --yes，否則直接拒絕執行（避免誤刪）
    if [ "${NON_INTERACTIVE:-false}" = "true" ] || [ ! -t 0 ]; then
        printf "${RED}非互動模式且未指定 -y / --yes，安全起見終止卸載${NC}\n"
        printf "${YELLOW}如需自動卸載，請加上 --yes 參數${NC}\n"
        exit 1
    fi
    printf "${RED}警告: 此操作將移除已安裝的組件！${NC}\n"
    read -r -p "確認繼續？(y/N) " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        printf "${GREEN}已取消${NC}\n"
        exit 0
    fi
fi

# ------------------------------------------------------------------------------
# 執行
# ------------------------------------------------------------------------------
FAILURES=0

as_root() {
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

remove_path() {
    local p="$1"
    if [ ! -e "$p" ] && [ ! -L "$p" ]; then
        printf "  略過 %s（已不存在）\n" "$p"
        return 0
    fi
    printf "  移除 %s... " "$p"
    local rc=0
    if ! under_dir "$p" "$HOME_TRIMMED"; then
        as_root rm -rf -- "$p" || rc=$?
    else
        rm -rf -- "$p" || rc=$?
    fi
    if [ "$rc" -eq 0 ] && [ ! -e "$p" ] && [ ! -L "$p" ]; then
        printf "${GREEN}✓${NC}\n"
        return 0
    fi
    printf "${RED}失敗${NC}\n"
    return 1
}

restore_file() {
    local dest="$1" src="$2" tmp="$1.restore.$$"
    printf "  還原 %s... " "$dest"
    if mkdir -p "$(dirname "$dest")" \
       && rm -rf -- "$tmp" \
       && cp -a "$src" "$tmp" \
       && rm -rf -- "$dest" \
       && mv "$tmp" "$dest"; then
        printf "${GREEN}✓${NC}\n"
        return 0
    fi
    rm -rf -- "$tmp" 2>/dev/null
    printf "${RED}失敗${NC}\n"
    return 1
}

detect_pkg_manager() {
    local pm
    for pm in apt-get dnf yum pacman zypper; do
        if command -v "$pm" >/dev/null 2>&1; then
            printf '%s\n' "$pm"
            return 0
        fi
    done
    return 1
}

remove_package() {
    local pm="$1" pkg="$2"
    case "$pm" in
        apt-get) as_root env DEBIAN_FRONTEND=noninteractive apt-get remove -y "$pkg" ;;
        dnf) as_root dnf remove -y "$pkg" ;;
        yum) as_root yum remove -y "$pkg" ;;
        pacman) as_root pacman -R --noconfirm "$pkg" ;;
        zypper) as_root zypper --non-interactive remove "$pkg" ;;
        *) return 1 ;;
    esac
}

printf "\n${CYAN}開始卸載...${NC}\n\n"

if [ "$PACKAGES_ONLY" != true ]; then
    printf "${YELLOW}[1/3]${NC} 移除本工具建立的檔案...\n"
    for p in ${PLAN_PATHS[@]+"${PLAN_PATHS[@]}"}; do
        remove_path "$p" || FAILURES=$((FAILURES + 1))
    done

    printf "\n${YELLOW}[2/3]${NC} 還原設定檔...\n"
    for i in ${PLAN_FILES[@]+"${!PLAN_FILES[@]}"}; do
        restore_file "${PLAN_FILES[$i]}" "${PLAN_FILE_SRCS[$i]}" || FAILURES=$((FAILURES + 1))
    done
fi

if [ "$CONFIGS_ONLY" != true ]; then
    printf "\n${YELLOW}[3/3]${NC} 移除套件...\n"
    if [ "${#PLAN_PACKAGES[@]}" -eq 0 ]; then
        printf "  沒有需要移除的套件\n"
    elif PKG_MANAGER="$(detect_pkg_manager)"; then
        for pkg in "${PLAN_PACKAGES[@]}"; do
            printf "  移除 %s... " "$pkg"
            if remove_package "$PKG_MANAGER" "$pkg" >/dev/null 2>&1; then
                printf "${GREEN}✓${NC}\n"
            else
                printf "${RED}失敗${NC}\n"
                FAILURES=$((FAILURES + 1))
            fi
        done
    else
        printf "${RED}錯誤: 未找到支持的套件管理器，無法移除套件${NC}\n"
        FAILURES=$((FAILURES + 1))
    fi
fi

# 全部做完且沒有失敗才處理安裝清單：完整卸載就刪除；
# 只做一部分時，只拿掉已處理的那部分，保留尚未處理的記錄。
if [ "$FAILURES" -gt 0 ]; then
    printf "\n${YELLOW}有 %d 項動作失敗，安裝清單已保留：%s${NC}\n" "$FAILURES" "$MANIFEST_FILE"
    printf "修正原因後可再次執行 uninstall.sh。\n"
    exit 1
fi

if [ "$PACKAGES_ONLY" = true ] || [ "$CONFIGS_ONLY" = true ]; then
    remaining_tmp="$MANIFEST_FILE.tmp.$$"
    if [ "$PACKAGES_ONLY" = true ]; then
        grep -v '^package:' "$MANIFEST_FILE" > "$remaining_tmp" 2>/dev/null
    else
        grep '^package:' "$MANIFEST_FILE" > "$remaining_tmp" 2>/dev/null
    fi
    if [ -s "$remaining_tmp" ]; then
        chmod 0600 "$remaining_tmp" 2>/dev/null
        mv "$remaining_tmp" "$MANIFEST_FILE"
    else
        rm -f "$remaining_tmp" "$MANIFEST_FILE"
        rmdir "$MANIFEST_DIR" 2>/dev/null
    fi
else
    rm -f "$MANIFEST_FILE"
    rmdir "$MANIFEST_DIR" 2>/dev/null
fi

printf "\n${GREEN}✓ 卸載完成！${NC}\n"
printf "\n${CYAN}提示：${NC}\n"
printf "  - 備份文件保留在: %s\n" "$BACKUP_DIR"
printf "  - 日誌與快取不會被移除（~/.local/log/linux-setting、~/.cache/linux-setting）\n"
printf "\n"
exit 0
