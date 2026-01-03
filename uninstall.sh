#!/usr/bin/env bash

# ==============================================================================
# Linux 環境設定腳本 - 卸載工具
# ==============================================================================

set -e

# 顏色定義
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

MANIFEST_DIR="$HOME/.config/linux-setting"
MANIFEST_FILE="$MANIFEST_DIR/installed.manifest"
BACKUP_DIR="$HOME/.config/linux-setting-backup"

# 顯示幫助
show_help() {
    cat << EOF
Linux Setting Scripts - 卸載工具

用法: $0 [選項]

選項:
  --packages-only     僅卸載包，保留配置文件
  --configs-only      僅恢復配置文件，保留包
  --full              完全卸載（默認）
  -y, --yes           自動確認，不詢問
  -h, --help          顯示此幫助訊息

範例:
  $0                  # 完全卸載（互動式）
  $0 --packages-only  # 僅卸載包
  $0 -y               # 自動確認卸載

EOF
}

# 解析參數
PACKAGES_ONLY=false
CONFIGS_ONLY=false
AUTO_YES=false

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
            # 默認就是 full，這個參數只是為了明確性
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

# 檢查是否有安裝記錄
if [ ! -f "$MANIFEST_FILE" ]; then
    printf "${YELLOW}未找到安裝記錄${NC}\n"
    printf "看起來尚未通過 install.sh 安裝過，或記錄文件已被刪除\n"
    printf "\n你仍然可以手動執行以下操作：\n"
    printf "  1. 卸載包: sudo apt remove zsh neovim docker-ce ...\n"
    printf "  2. 刪除配置: rm -rf ~/.zshrc ~/.p10k.zsh ~/.config/nvim\n"
    printf "  3. 恢復備份: cp -r $BACKUP_DIR/latest/* ~/\n"
    exit 1
fi

# 讀取已安裝的包列表
mapfile -t INSTALLED_PACKAGES < <(grep '^package:' "$MANIFEST_FILE" | cut -d: -f2)
mapfile -t MODIFIED_FILES < <(grep '^file:' "$MANIFEST_FILE" | cut -d: -f2)

# 顯示將要卸載的內容
printf "\n${CYAN}========== 卸載預覽 ==========${NC}\n\n"

if [ "$CONFIGS_ONLY" != true ]; then
    printf "${YELLOW}將卸載以下包 (${#INSTALLED_PACKAGES[@]} 個):${NC}\n"
    for pkg in "${INSTALLED_PACKAGES[@]}"; do
        printf "  - %s\n" "$pkg"
    done | head -20
    if [ ${#INSTALLED_PACKAGES[@]} -gt 20 ]; then
        printf "  ... 還有 %d 個包\n" $((${#INSTALLED_PACKAGES[@]} - 20))
    fi
    printf "\n"
fi

if [ "$PACKAGES_ONLY" != true ]; then
    printf "${YELLOW}將恢復以下配置文件:${NC}\n"
    for file in "${MODIFIED_FILES[@]}"; do
        printf "  - %s\n" "$file"
    done
    printf "\n"

    # 檢查備份是否存在
    LATEST_BACKUP=$(find "$BACKUP_DIR" -maxdepth 1 -type d | sort -r | head -2 | tail -1)
    if [ -n "$LATEST_BACKUP" ] && [ -d "$LATEST_BACKUP" ]; then
        printf "${GREEN}✓${NC} 找到備份: %s\n" "$(basename "$LATEST_BACKUP")"
    else
        printf "${YELLOW}⚠${NC}  未找到備份，配置文件將被刪除而非恢復\n"
    fi
    printf "\n"
fi

# 確認
if [ "$AUTO_YES" != true ]; then
    printf "${RED}警告: 此操作將移除已安裝的組件！${NC}\n"
    read -p "確認繼續？(y/N) " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        printf "${GREEN}已取消${NC}\n"
        exit 0
    fi
fi

# 執行卸載
printf "\n${CYAN}開始卸載...${NC}\n\n"

# 卸載包
if [ "$CONFIGS_ONLY" != true ] && [ ${#INSTALLED_PACKAGES[@]} -gt 0 ]; then
    printf "${YELLOW}[1/2]${NC} 卸載包...\n"

    # 檢測包管理器
    if command -v apt >/dev/null 2>&1; then
        PKG_MANAGER="apt"
        REMOVE_CMD="sudo apt remove -y"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
        REMOVE_CMD="sudo dnf remove -y"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MANAGER="pacman"
        REMOVE_CMD="sudo pacman -R --noconfirm"
    else
        printf "${RED}錯誤: 未找到支持的包管理器${NC}\n"
        exit 1
    fi

    for pkg in "${INSTALLED_PACKAGES[@]}"; do
        printf "  卸載 %s... " "$pkg"
        if $REMOVE_CMD "$pkg" >/dev/null 2>&1; then
            printf "${GREEN}✓${NC}\n"
        else
            printf "${YELLOW}跳過${NC}\n"
        fi
    done
fi

# 恢復配置文件
if [ "$PACKAGES_ONLY" != true ]; then
    printf "\n${YELLOW}[2/2]${NC} 恢復配置文件...\n"

    if [ -n "$LATEST_BACKUP" ] && [ -d "$LATEST_BACKUP" ]; then
        # 從備份恢復
        for file in "${MODIFIED_FILES[@]}"; do
            backup_file="$LATEST_BACKUP/$(basename "$file")"
            if [ -f "$backup_file" ] || [ -d "$backup_file" ]; then
                printf "  恢復 %s... " "$(basename "$file")"
                rm -rf "$file"
                cp -r "$backup_file" "$file"
                printf "${GREEN}✓${NC}\n"
            fi
        done
    else
        # 直接刪除（無備份）
        for file in "${MODIFIED_FILES[@]}"; do
            if [ -e "$file" ]; then
                printf "  刪除 %s... " "$(basename "$file")"
                rm -rf "$file"
                printf "${GREEN}✓${NC}\n"
            fi
        done
    fi

    # 刪除安裝記錄
    rm -f "$MANIFEST_FILE"
fi

printf "\n${GREEN}✓ 卸載完成！${NC}\n"
printf "\n${CYAN}提示：${NC}\n"
printf "  - 備份文件保留在: %s\n" "$BACKUP_DIR"
printf "  - 如需完全清除，請刪除: %s\n" "$MANIFEST_DIR"
printf "\n"
