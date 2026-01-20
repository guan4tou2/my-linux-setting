# 自訂指南 (Customization Guide)

本文檔說明如何 Fork 並自訂這個 Linux 環境配置專案。

## 模板文件

專案提供以下模板，方便快速新增自訂內容：

| 模板文件 | 用途 |
|---------|------|
| `config/modules.conf.template` | 模組配置模板（含完整範例）|
| `scripts/core/custom_module.sh.template` | 自訂安裝腳本模板 |

## 快速開始

### 1. Fork 專案

```bash
# Fork 後 clone 你的版本
git clone https://github.com/YOUR_USERNAME/my-linux-setting.git
cd my-linux-setting
```

### 2. 使用模板自訂

```bash
# 方法 A: 從模板開始（推薦新手）
cp config/modules.conf.template config/modules.conf
vim config/modules.conf

# 方法 B: 直接編輯現有配置
vim config/modules.conf
```

### 3. 新增自訂安裝腳本（可選）

```bash
# 複製腳本模板
cp scripts/core/custom_module.sh.template scripts/core/mytools_setup.sh

# 編輯腳本
vim scripts/core/mytools_setup.sh

# 在 modules.conf 中引用
# [mytools]
# script=mytools_setup.sh
```

## 配置文件格式

### modules.conf 結構

```ini
# 模組定義
[模組ID]
name=顯示名稱
description=簡短描述（顯示在選單中）
packages=APT 套件（空格分隔）
brew_packages=Homebrew 套件（可選）
apt_fallback=當 Homebrew 不可用時的替代套件
pip_packages=Python 套件（使用 uv tool 安裝）
cargo_packages=Rust 套件
npm_packages=Node.js 套件
script=自訂安裝腳本（放在 scripts/core/ 目錄）
post_install=安裝後執行的命令
```

### 範例：新增模組

```ini
# 新增資料庫工具模組
[database]
name=資料庫工具
description=postgresql, redis, mongodb
packages=postgresql postgresql-contrib redis-server
brew_packages=mongosh
pip_packages=pgcli redis-cli
script=
post_install=sudo systemctl enable postgresql
```

## 常見自訂操作

### 新增套件到現有模組

在 `modules.conf` 中找到對應模組，新增套件：

```ini
[base]
name=基礎工具
description=git, lsd, bat, ripgrep, fzf
# 在這裡新增你要的套件
packages=git curl wget unzip tar build-essential htop tree
brew_packages=lsd bat ripgrep fd fzf tealdeer eza  # 新增 eza
```

### 移除套件

直接從對應的列表中刪除套件名稱即可。

### 新增自訂模組

1. 在 `modules.conf` 新增模組定義：

```ini
[mytools]
name=我的工具
description=自訂工具集
packages=tmux screen
brew_packages=
pip_packages=httpie
```

2. 如果需要複雜安裝邏輯，建立腳本 `scripts/core/mytools_setup.sh`：

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

log_info "安裝我的自訂工具..."

# 你的安裝邏輯
install_package tmux
install_package screen

# 配置
cat >> ~/.tmux.conf << 'EOF'
set -g mouse on
set -g history-limit 10000
EOF

log_success "我的工具安裝完成"
```

3. 在 `modules.conf` 中引用腳本：

```ini
[mytools]
script=mytools_setup.sh
```

### 停用模組

在模組定義前加上 `#` 註解：

```ini
# [docker]
# name=Docker 工具
# ...
```

## 環境變數

| 變數 | 說明 | 預設值 |
|------|------|--------|
| `MODULES_CONF` | 配置文件路徑 | `config/modules.conf` |
| `PREFER_HOMEBREW` | 優先使用 Homebrew | `true` |
| `ENABLE_PARALLEL_INSTALL` | 啟用並行安裝 | `true` |
| `TUI_MODE` | TUI 輸出模式 | `quiet` |

## Homebrew 環境說明

為了避免 Homebrew Python 與系統 Python 的路徑衝突，Homebrew 環境 **預設不自動啟用**。

### 切換 Homebrew 環境

```bash
# 啟用 Homebrew 環境
brew-on

# 停用 Homebrew 環境
brew-off

# 直接使用 brew 命令（不影響 PATH）
brew install something
```

### 何時需要 brew-on？

- 需要使用 Homebrew 安裝的 Python 時
- 需要使用 Homebrew 的其他工具版本時

## Python 工具安裝

所有 Python 命令行工具統一使用 `uv tool` 安裝：

```bash
# 安裝 Python 工具
uv tool install ranger-fm
uv tool install httpie

# 列出已安裝的工具
uv tool list

# 更新工具
uv tool upgrade ranger-fm
```

這樣可以避免：
- 系統 Python 的權限問題
- pip 全域安裝的依賴衝突
- Homebrew Python 的路徑衝突

## 目錄結構

```
my-linux-setting/
├── install.sh              # 主安裝腳本
├── config/
│   └── modules.conf        # ⭐ 模組配置（主要自訂文件）
├── scripts/
│   ├── core/
│   │   ├── common.sh       # 共用函數庫
│   │   ├── module_manager.sh  # 模組管理器
│   │   ├── base_tools.sh   # 基礎工具安裝
│   │   ├── dev_tools.sh    # 開發工具安裝
│   │   ├── python_setup.sh # Python 環境
│   │   ├── terminal_setup.sh  # 終端設定
│   │   ├── docker_setup.sh # Docker 安裝
│   │   └── monitoring_tools.sh  # 監控工具
│   ├── maintenance/        # 維護腳本
│   └── utils/              # 工具腳本
└── CUSTOMIZATION.md        # 本文件
```

## 進階自訂

### 修改安裝順序

模組按照 `modules.conf` 中的定義順序安裝。調整順序只需移動模組定義的位置。

### 新增安裝方法

在 `scripts/core/module_manager.sh` 的 `install_module()` 函數中新增：

```bash
# 例如：新增 snap 套件支援
if [ -n "$snap_packages" ] && command -v snap >/dev/null 2>&1; then
    for pkg in $snap_packages; do
        sudo snap install "$pkg"
    done
fi
```

然後在 `modules.conf` 中使用：

```ini
[mymodule]
snap_packages=code slack
```

### 自訂 TUI 選單

修改 `install.sh` 中的 `show_menu()` 函數，或使用 `module_manager.sh` 中的 `generate_cli_menu()` 函數。

## 測試變更

```bash
# 預覽模式（不實際安裝）
./install.sh --dry-run

# 詳細輸出
./install.sh --verbose

# 語法檢查
bash -n install.sh
bash -n scripts/core/common.sh
bash -n scripts/core/module_manager.sh
```

## 貢獻

歡迎提交 Pull Request！請確保：

1. 通過 `bash -n` 語法檢查
2. 在 `--dry-run` 模式下測試
3. 更新相關文檔

## 問題回報

如果遇到問題，請提交 Issue 並附上：

1. 系統資訊（`cat /etc/os-release`）
2. 錯誤訊息
3. 日誌文件（`~/.local/log/linux-setting/`）
