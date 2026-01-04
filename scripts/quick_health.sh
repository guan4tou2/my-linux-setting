#!/usr/bin/env bash

# 快速健康檢查腳本
# 用途：快速診斷系統狀態，便於故障排除

set -euo pipefail

# 嘗色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "🔍 快速健康檢查"
echo "═══════════════"

# 嘗載核心函數
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../core/common.sh" ]; then
    source "$SCRIPT_DIR/../core/common.sh"
else
    echo "⚠️  警告: 無法載入核心函數，使用基本檢查"
fi

# 1. 檢查操作系統
echo ""
echo "📦 操作系統: $(detect_distro 2>/dev/null || echo "未檢測到") $(uname -m)"

# 2. 檢查網絡連接
echo ""
echo -n "🌐 網絡連接: "
if command -v ping >/dev/null 2>&1; then
    if ping -c 1 -W 2 github.com >/dev/null 2>&1; then
        echo -e "${GREEN}正常${NC}"
    elif ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        echo -e "${GREEN}正常${NC} (可能受限制)"
    else
        echo -e "${RED}異常${NC}"
    fi
else
    if curl -s --max-time 3 https://www.google.com >/dev/null 2>&1; then
        echo -e "${GREEN}正常${NC}"
    else
        echo -e "${RED}異常${NC}"
    fi
fi

# 3. 檢查磁碟空間
echo ""
DISK_AVAIL=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
echo -n "💾 磁碟空間: "
if [ "$DISK_AVAIL" -ge 5 ]; then
    echo -e "${GREEN}$DISK_AVAIL GB${NC}"
elif [ "$DISK_AVAIL" -ge 2 ]; then
    echo -e "${YELLOW}$DISK_AVAIL GB${NC} (偏低)"
else
    echo -e "${RED}$DISK_AVAIL GB${NC} (不足)"
fi

# 4. 檢查 sudo 權限
echo ""
echo -n "🔑 sudo 權限: "
if sudo -n true 2>/dev/null; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${YELLOW}需要密碼${NC}"
fi

# 5. 檢查關鍵工具
echo ""
echo "🔧 關鍵工具:"
for tool in git curl wget bash zsh python3 docker; do
    echo -n "  $tool: "
    if command -v "$tool" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
    fi
done

# 6. 檢查最新日誌
echo ""
if [ -d "$HOME/.local/log/linux-setting" ]; then
    LATEST_LOG=$(ls -t "$HOME/.local/log/linux-setting"/*.log 2>/dev/null | head -1)
    if [ -n "$LATEST_LOG" ]; then
        echo "📄 最新日誌: $LATEST_LOG"
        ERROR_COUNT=$(grep -c "^ERROR:" "$LATEST_LOG" 2>/dev/null || echo 0)
        if [ "$ERROR_COUNT" -gt 0 ]; then
            echo -e "  ${YELLOW}⚠️  發現 $ERROR_COUNT 個錯誤${NC}"
        else
            echo -e "  ${GREEN}✓ 無錯誤${NC}"
        fi
    fi
else
    echo "📄 日誌目錄: 不存在"
fi

# 7. 檢查備份目錄
echo ""
if [ -d "$HOME/.config/linux-setting-backup" ]; then
    BACKUP_COUNT=$(ls -d "$HOME/.config/linux-setting-backup"/* 2>/dev/null | wc -l)
    LATEST_BACKUP=$(ls -td "$HOME/.config/linux-setting-backup"/*/ 2>/dev/null | head -1 | xargs basename)
    echo "🗂  備份目錄: $BACKUP_COUNT 個備份"
    echo "  最新備份: $LATEST_BACKUP"
else
    echo "🗂  備份目錄: 無備份"
fi

# 8. 檢查配置文件
echo ""
CONFIG_FILE="$HOME/.config/linux-setting/config"
if [ -f "$CONFIG_FILE" ]; then
    echo -e "📝 配置文件: ${GREEN}存在${NC} ($CONFIG_FILE)"
    # 檢查關鍵配置
    if grep -q "INSTALL_MODE=full" "$CONFIG_FILE" 2>/dev/null; then
        echo "  安裝模式: 完整"
    else
        echo "  安裝模式: $(grep "^INSTALL_MODE=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2)"
    fi
else
    echo -e "📝 配置文件: ${YELLOW}不存在${NC} (可選)"
fi

echo ""
echo "═══════════════"
echo -e "${GREEN}✅ 健康檢查完成${NC}"
echo ""
