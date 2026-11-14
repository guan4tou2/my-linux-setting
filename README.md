## Linux 環境設定腳本

快速建立 Debian 系列 Linux 開發環境的自動化安裝腳本，支援互動式選單、模組化安裝與詳細日誌。

### 🐧 支援的平台

每次變更都會在 CI 上對下列平台執行完整安裝並驗證結果，只測各發行版的**最新版本**：

| 發行版 | 測試對象 | 架構 |
|---|---|---|
| Ubuntu | 最新 LTS（`ubuntu:latest`） | x86_64、arm64 |
| Debian | 目前的 stable（`debian:stable`） | x86_64、arm64 |
| Kali Linux | rolling（實驗性，失敗不擋合併） | x86_64 |

- 較舊的版本（例如 Ubuntu 22.04）沒有 CI 覆蓋；針對它們的備援邏輯仍保留，但不保證可用。
- 其他 Debian 系列（Linux Mint、Pop!_OS 等）理論上可用，未經測試。
- RHEL、Arch、SUSE 系列**目前不支援**：程式會偵測套件管理器，但模組的套件名稱是 apt 的，實際安裝不會成功。

### ✅ 主要特色

- 一行指令遠端安裝
- 在 x86_64 與 arm64 上皆可使用
- 互動式選單自由選擇模組
- 完整開發環境：Python / Docker / 終端 / 編輯器 / 監控工具
- 自動備份與失敗回滾機制
- 使用 uv 作為預設 Python 包管理器

---

## 🚀 快速開始

### 標準安裝（推薦）

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main/install.sh)"
```

啟動互動式選單，選擇要安裝的模組（Python、Docker、基礎工具、終端機、開發工具、監控工具）。

---

## ⚙️ 指令列選項

```bash
# 最小安裝
bash -c "$(curl -fsSL https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main/install.sh)" --minimal

# 更新模式
bash -c "$(curl -fsSL https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main/install.sh)" --update

# 預覽模式
bash -c "$(curl -fsSL https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main/install.sh)" --dry-run

# 詳細模式
bash -c "$(curl -fsSL https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main/install.sh)" --verbose
```

**參數說明：**

- `--minimal`：最小安裝模式
- `--update`：更新已安裝工具
- `--dry-run`：預覽將要安裝的內容
- `-v / --verbose`：顯示詳細日誌
- `-h / --help`：顯示幫助訊息

### 性能優化選項

透過環境變數控制性能優化功能：

```bash
# 停用並行安裝（預設啟用）
ENABLE_PARALLEL_INSTALL=false ./install.sh

# 調整並行任務數（預設 4）
PARALLEL_JOBS=8 ./install.sh
```

**優化功能：**

- 並行安裝：同時安裝多個套件（提升速度約 30%）
- APT 優化：自動配置 APT 並行下載與快取（提升速度約 20%）

---

## 🧩 安裝模組

- **Python 開發環境**：python3, pip, uv, ranger-fm, s-tui
- **Docker 工具**：docker-ce, docker-compose, lazydocker
- **基礎工具**：git, curl, wget, lsd, bat, ripgrep, fd-find, fzf
- **終端機設定**：zsh, oh-my-zsh, powerlevel10k, zsh-autosuggestions, zsh-syntax-highlighting
- **開發工具**：neovim (LazyVim), lazygit, nodejs, cargo, lua
- **監控與安全**：btop, htop, iftop, nethogs, fail2ban

---

## 📸 安裝畫面預覽

![img](img/SCR-20250310-mmxt.png)

---

## 🧪 測試與開發

### 本地測試

```bash
./tests/run_all_tests.sh            # 測試入口（依賴/功能測試僅 Linux CI 預設執行）
./tests/test_dependencies.sh        # 依賴檢查
./tests/test_functionality.sh       # 功能測試
./tests/run_shellcheck.sh           # 受版控腳本：錯誤阻擋 CI，警告僅摘要
./tests/verify_install.sh python base terminal dev monitoring  # 安裝成果斷言
./scripts/config/preview_config.sh  # 預覽配置
```

```bash
FORCE_LINUX_TESTS=true ./tests/run_all_tests.sh   # 本機強制執行 Linux-only 測試
```

### Docker 測試

```bash
./docker-test.sh build && ./docker-test.sh test    # 快速測試
BASE_IMAGE=debian:stable ./docker-test.sh build                # 指定其他基底映像（預設 ubuntu:latest）
./tests/test_full_simulation.sh                             # 新容器內 HTTP 遠端安裝與成果驗證
./docker-test.sh run "CI=true bash tests/test_tui_smoke.sh"    # whiptail 成功／失敗操作流程
# tests/simulate_remote_install.sh 在 Linux 容器內服務專案並從空目錄安裝
```

---

## 🛠️ 系統維護

```bash
./scripts/maintenance/health_check.sh # 健康檢查
./scripts/maintenance/update_tools.sh # 更新工具
./uninstall.sh                        # 卸載腳本
```

---

## 🧾 顯示模式

透過 `TUI_MODE` 環境變數控制輸出詳細程度：

- `quiet`（預設）：只顯示關鍵步驟
- `normal`：顯示完整安裝輸出
- TUI 使用導覽式流程：勾選模組 → 確認摘要 → 安裝（顯示每個模組的進度）→ 結果畫面
- 勾選清單預設只選尚未安裝的模組；最後一列可開啟進階模式，逐模組挑選套件
- 結果畫面可「重試失敗的模組」、「查看安裝日誌」或重新選擇
- 終端機小於 15 列或 50 欄時自動改用純文字選單
- `TUI_LOG_LINES` 可控制 TUI 日誌檢視器顯示的尾端行數（預設 300）

```bash
TUI_MODE=normal ./install.sh --verbose
TUI_LOG_LINES=500 ./install.sh
```

### 互動選單後端

透過 `TUI_BACKEND` 指定互動選單工具：

- `auto`（預設）：優先使用 `gum`，其次 `fzf`，最後 `whiptail`
- `gum`：較現代的 shell TUI，適合選單、確認、輸入
- `fzf`：適合大量項目搜尋與多選
- `whiptail`：傳統 fallback，系統相容性較高

```bash
TUI_BACKEND=fzf ./install.sh
TUI_BACKEND=gum ./install.sh
TUI_BACKEND=whiptail ./install.sh
```

可選工具安裝：

```bash
# Kali / Debian / Ubuntu
sudo apt install -y fzf

# 若已有 Homebrew / Linuxbrew
brew install gum
```

---

## 📁 重要檔案位置

- Shell：`~/.zshrc`, `~/.p10k.zsh`
- Neovim：`~/.config/nvim`
- Python 虛擬環境：`~/.local/venv/system-tools`

---

## 💾 備份與日誌

- 備份目錄：`~/.config/linux-setting-backup/`
- 日誌位置：`~/.local/log/linux-setting/`
- 錯誤時自動詢問是否回滾

---

## 🔬 技術特點

- 使用 uv 作為 Python 包管理器（比 pip 快 10-100 倍）
- 強化錯誤處理與詳細日誌
- 自動檢查網路、磁碟空間、sudo 權限
- 互動式選單與彩色輸出

---

## 🔧 客製化

Fork 此專案後，修改 `install.sh` 中的 `REPO_URL`：

```bash
export REPO_URL="https://raw.githubusercontent.com/<your-name>/<your-repo>/main"
```
