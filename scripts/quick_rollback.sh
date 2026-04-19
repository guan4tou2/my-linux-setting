#!/usr/bin/env bash

# 快速回滾腳本
# 用途：快速回滾到之前的安裝狀態

set -euo pipefail

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "🔄 快速回滾工具"
echo "═════════════"

BACKUP_DIR="$HOME/.config/linux-setting-backup"

# 檢查備份目錄
if [ ! -d "$BACKUP_DIR" ]; then
    echo -e "${RED}❌ 找不到備份目錄: $BACKUP_DIR${NC}"
    echo ""
    echo -e "${YELLOW}💡 第一次運行安裝腳本？還是備份已被刪除？${NC}"
    exit 1
fi

echo -e "${BLUE}📂 備份目錄: $BACKUP_DIR${NC}"
echo ""

# 列出所有備份
echo "可用的備份（從新到舊）："
echo ""

backup_count=0
for backup_path in $(ls -td "$BACKUP_DIR"/*/ 2>/dev/null); do
    ((backup_count++))
    backup_name=$(basename "$backup_path")
    
    # 顯示備份時間和文件數量
    file_count=$(find "$backup_path" -type f 2>/dev/null | wc -l)
    echo -e "${CYAN}[$backup_count] $backup_name${NC}  ($file_count 個文件)"
done

echo ""
echo "═════════════"

if [ $backup_count -eq 0 ]; then
    echo -e "${YELLOW}⚠️  沒有找到備份${NC}"
    exit 0
fi

echo ""
# 非互動模式：可用環境變數 ROLLBACK_INDEX=N 指定備份編號（沒設定就終止）
if [ "${NON_INTERACTIVE:-false}" = "true" ] || [ ! -t 0 ]; then
    if [ -n "${ROLLBACK_INDEX:-}" ]; then
        backup_choice="$ROLLBACK_INDEX"
        echo -e "${BLUE}非互動模式：使用 ROLLBACK_INDEX=$backup_choice${NC}"
    else
        echo -e "${RED}非互動模式且未設定 ROLLBACK_INDEX，安全起見終止回滾${NC}"
        echo -e "${YELLOW}用法：ROLLBACK_INDEX=1 ROLLBACK_CONFIRM=yes $0${NC}"
        exit 1
    fi
else
    read -p "選擇要回滾的備份編號 (或按 Ctrl+C 取消): " backup_choice
fi

if [ -z "$backup_choice" ]; then
    echo ""
    echo -e "${YELLOW}已取消回滾${NC}"
    exit 0
fi

# 驗證輸入
if ! [[ "$backup_choice" =~ ^[0-9]+$ ]] || [ "$backup_choice" -lt 1 ] || [ "$backup_choice" -gt $backup_count ]; then
    echo -e "${RED}❌ 無效的選擇: $backup_choice${NC}"
    exit 1
fi

# 獲取選擇的備份路徑
backup_path=$(ls -td "$BACKUP_DIR"/*/ 2>/dev/null | sed -n "${backup_choice}p")

echo ""
echo -e "${BLUE}選中的備份: $(basename "$backup_path")${NC}"
echo ""
echo -e "${YELLOW}將恢復的文件：${NC}"
echo ""

# 顯示要恢復的文件列表
for backup_file in "$backup_path"/*; do
    if [ -f "$backup_file" ]; then
        original_name=$(basename "$backup_file" | sed 's/\.backup\.[0-9_]*$//')
        echo -e "  ${GREEN}• $original_name${NC}"
    fi
done

echo ""
if [ "${NON_INTERACTIVE:-false}" = "true" ] || [ ! -t 0 ]; then
    confirm="${ROLLBACK_CONFIRM:-no}"
    echo -e "${BLUE}非互動模式：ROLLBACK_CONFIRM=$confirm${NC}"
else
    read -p "確認要回滾嗎？(yes/no): " confirm
fi

if [[ ! $confirm =~ ^[Yy][Ee][Ss]$ ]]; then
    echo ""
    echo -e "${YELLOW}已取消回滾${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}🔄 開始回滾...${NC}"
echo ""

# 執行回滾
success_count=0
failure_count=0

for backup_file in "$backup_path"/*; do
    if [ -f "$backup_file" ]; then
        original_name=$(basename "$backup_file" | sed 's/\.backup\.[0-9_]*$//')
        
        # 確定原路徑
        if [[ "$original_name" == .* ]]; then
            original_path="$HOME/$original_name"
        else
            original_path="$HOME/.$original_name"
        fi
        
        # 檢查原文件是否存在
        if [ -e "$original_path" ]; then
            # 如果原文件存在，備份它
            backup_existing "$original_path"
        fi
        
        # 恢復備份文件
        if cp "$backup_file" "$original_path" 2>/dev/null; then
            echo -e "${GREEN}✓ 已恢復: $original_name${NC}"
            ((success_count++))
        else
            echo -e "${RED}✗ 恢復失敗: $original_name${NC}"
            ((failure_count++))
        fi
    fi
done

echo ""
echo -e "${BLUE}回滾完成${NC}"
echo ""
echo -e "${GREEN}成功: $success_count 個文件${NC}"
echo -e "${RED}失敗: $failure_count 個文件${NC}"
echo ""

if [ $failure_count -eq 0 ]; then
    echo -e "${GREEN}✅ 回滾成功完成！${NC}"
    echo ""
    echo -e "${YELLOW}💡 提示: 可能需要重新載入配置或重新登入${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠️  部分文件恢復失敗${NC}"
    exit 1
fi
