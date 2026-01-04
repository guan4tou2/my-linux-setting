# Linux 環境設定腳本

快速建立多種 Linux 發行版開發環境的自動化安裝腳本，支援互動式選單、模組化安裝、錯誤回滾與詳細日誌。

## 🛡️ Security Notice

**This project has undergone comprehensive security improvements:**

- ✅ GPG signature verification for remote scripts
- ✅ Input validation and sandboxing
- ✅ Secure download mechanisms with timeout limits
- ✅ GPG key verification for all PPAs (no `trusted=yes`)
- ✅ Comprehensive security audit scripts
- ✅ Structured logging with rotation

**To run security audit:**
```bash
./tests/security_audit.sh
```

## 🐧 支援的 Linux 發行版

- **Debian 系列**：Ubuntu、Debian、Kali Linux、Linux Mint、Pop!_OS、Elementary OS
- **RHEL 系列**：Fedora、CentOS、RHEL、Rocky Linux、AlmaLinux
- **Arch 系列**：Arch Linux、Manjaro、EndeavourOS、Garuda Linux
- **SUSE 系列**：openSUSE、SLES（基本支援）

腳本會自動檢測系統並使用對應的包管理器（apt、dnf、yum、pacman、zypper）。

## ✅ 主要特色

- 一行指令遠端安裝
- 自動檢測並適配不同 Linux 發行版
- 互動式選單自由選擇模組
- 完整開發環境：Python / Docker / 終端 / 編輯器 / 監控工具
- 自動備份與失敗回滾機制
- 使用 uv 作為預設 Python 包管理器
- **GPG 簽名驗證**與安全下載機制
- **結構化日誌**與自動日誌輪轉
- **多方法備份安裝**（Homebrew → Cargo → APT）

---

## 🚀 快速開始

### 標準安裝（推薦）

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main/install.sh)"
```

啟動互動式選單，選擇要安裝的模組（Python、Docker、基礎工具、終端機、開發工具、監控工具）。

---

## ⚙️ 指令列選項

### 基本選項

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

### 使用配置文件

```bash
# 使用自定義配置文件
bash -c "$(curl -fsSL https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main/install.sh)" --config ~/.config/linux-setting/custom-config
```

### 性能優化選項

透過環境變數控制性能優化功能：

```bash
# 啟用並行安裝（預設啟用）
ENABLE_PARALLEL_INSTALL=true ./install.sh

# 調整並行任務數（預設 4，設為 auto 自動偵測）
PARALLEL_JOBS=8 ./install.sh

# 關閉並行安裝
ENABLE_PARALLEL_INSTALL=false ./install.sh
```

### 安全選項

```bash
# 啟用 GPG 簽名驗證（預設啟用）
ENABLE_GPG_VERIFY=true ./install.sh

# 啟用安全下載驗證（預設啟用）
ENABLE_SECURE_DOWNLOAD=true ./install.sh

# 下載超時時間（預設 30 秒）
DOWNLOAD_TIMEOUT=60 ./install.sh

# 最大下載文件大小（預設 1MB）
MAX_SCRIPT_SIZE=2097152 ./install.sh
```

---

## 🧩 安裝模組

- **Python 開發環境**：python3, pip, uv, ranger-fm, s-tui
- **Docker 工具**：docker-ce, docker-compose, lazydocker
- **基礎工具**：git, curl, wget, lsd, bat, ripgrep, fd-find, fzf
- **終端機設定**：zsh, oh-my-zsh, powerlevel10k, zsh-autosuggestions, zsh-syntax-highlighting
- **開發工具**：neovim (LazyVim), lazygit, nodejs, cargo, lua
- **監控與安全**：btop, htop, iftop, nethogs, fail2ban

---

## 🔧 配置文件

### 創建配置文件

```bash
# 複製範例配置
mkdir -p ~/.config/linux-setting
cp config/linux-setting.conf ~/.config/linux-setting/config

# 編輯配置
vim ~/.config/linux-setting/config
```

### 重要配置選項

```bash
# 偏好 Homebrew（比 apt 更新，避免編譯）
PREFER_HOMEBREW=true

# 偏好 uv（比 pip 快 10-100 倍）
PREFER_UV=true

# 日誌格式（text 或 json）
LOG_FORMAT=json

# 並行安裝啟用
ENABLE_PARALLEL_INSTALL=true
PARALLEL_JOBS=auto

# 安全設定
ENABLE_GPG_VERIFY=true
ENABLE_SECURE_DOWNLOAD=true
```

---

## 📸 安裝畫面預覽

![img](img/SCR-20250310-mmxt.png)

---

## 🧪 測試與開發

### 本地測試

```bash
# 執行所有測試
./tests/run_all_tests.sh

# 單元測試
./tests/test_dependencies.sh      # 依賴檢查
./tests/test_functionality.sh     # 功能測試
./tests/test_common_library.sh     # 單元測試

# 安全審計
./tests/security_audit.sh          # 安全檢查
```

### Docker 測試

```bash
# 快速測試
./docker-test.sh build && ./docker-test.sh test

# 多系統測試
docker-compose -f docker-compose.test.yml up ubuntu-test

# 完整模擬測試
./tests/test_full_simulation.sh
```

---

## 🛠️ 系統維護

### 健康檢查

```bash
./scripts/health_check.sh
```

輸出示例：
```
✓ System: Ubuntu 22.04
✓ Disk Space: 25GB available
✓ Network: Connected
✓ Sudo Access: OK
✓ Python: 3.10.12 installed
✓ Docker: Running
```

### 更新工具

```bash
./scripts/update_tools.sh
```

### 卸載

```bash
# 完全卸載（互動式）
./uninstall.sh

# 自動卸載（無確認）
./uninstall.sh -y

# 只卸載套件
./uninstall.sh --packages-only

# 只恢復配置
./uninstall.sh --configs-only
```

---

## 🔬 故障排除

### 網路問題

**問題**：下載失敗或速度很慢

**解決方案**：
```bash
# 1. 檢查網絡連接
ping -c 3 github.com

# 2. 使用代理
export HTTP_PROXY=http://proxy.example.com:8080
export HTTPS_PROXY=http://proxy.example.com:8080

# 3. 增加超時時間
DOWNLOAD_TIMEOUT=120 ./install.sh

# 4. 使用本地文件（如果已下載）
SKIP_NETWORK_TESTS=true ./tests/run_all_tests.sh
```

### Python 安裝失敗

**問題**：Python 3 安裝失敗或版本不符

**解決方案**：
```bash
# 1. 跳過版本檢查
SKIP_PYTHON_CHECK=true ./install.sh

# 2. 手動安裝 Python
sudo apt update
sudo apt install -y python3 python3-pip python3-venv

# 3. 使用 pyenv 管理多個 Python 版本
curl https://pyenv.run | bash
```

### Docker 安裝失敗

**問題**：Docker 安裝失敗或無法執行

**解決方案**：
```bash
# 1. 檢查系統架構
uname -m

# 2. 如果是 ARM64，使用特定的 Docker 安裝方法
# 腳本會自動處理，但可以手動檢查：
cat /etc/os-release

# 3. 重新配置 Docker daemon
sudo systemctl restart docker

# 4. 檢查用戶權限
sudo usermod -aG docker $USER
newgrp docker
```

### GPG 驗證失敗

**問題**：GPG 簽名驗證失敗

**解決方案**：
```bash
# 1. 禁用 GPG 驗證（不推薦）
ENABLE_GPG_VERIFY=false ./install.sh

# 2. 更新 GPG 密鑰環
sudo apt update
sudo apt install -y gnupg2

# 3. 清理並重新導入密鑰
rm -rf ~/.cache/linux-setting/trusted.gpg
./install.sh
```

### 權限問題

**問題**：腳本要求 sudo 權限但用戶不在 sudoers

**解決方案**：
```bash
# 1. 確認 sudo 權限
sudo -v

# 2. 將用戶添加到 sudo 組（需要 root 權限）
sudo usermod -aG sudo $username

# 3. 以 root 身份運行
su root
./install.sh
```

### 磁盤空間不足

**問題**：安裝失敗，提示磁盤空間不足

**解決方案**：
```bash
# 1. 檢查磁盤空間
df -h /

# 2. 清理 APT 快取
sudo apt clean
sudo apt autoremove

# 3. 清理 Docker 系統（如果已安裝）
docker system prune -a

# 4. 清理日誌
find ~/.local/log/linux-setting -type f -name "*.log" -mtime +7 -delete
```

### Homebrew 安裝失敗

**問題**：Homebrew 無法安裝

**解決方案**：
```bash
# 1. 檢查 Homebrew 依賴
sudo apt install -y build-essential procps curl file git

# 2. 手動安裝 Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 3. 配置環境變數
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

# 4. 如果 Homebrew 失敗，腳本會自動使用 APT
PREFER_HOMEBREW=false ./install.sh
```

### 終端機問題

**問題**：zsh 配置出錯或無法載入

**解決方案**：
```bash
# 1. 檢查 zsh 版本
zsh --version

# 2. 檢查 .zshrc 語法
zsh -n ~/.zshrc

# 3. 檢查 oh-my-zsh 安裝
ls -la ~/.oh-my-zsh

# 4. 重新安裝 zsh（如果版本不符）
sudo apt install -y zsh

# 5. 使用 bash 作為備份
exec bash
```

### 腳本卡住

**問題**：腳本在執行過程中卡住

**解決方案**：
```bash
# 1. 使用詳細模式查看卡住位置
./install.sh --verbose

# 2. 檢查運行中的進程
ps aux | grep install

# 3. 殺死卡住的進程
killall install

# 4. 清理臨時文件
rm -rf /tmp/linux-setting-*

# 5. 檢查日誌查看錯誤
cat ~/.local/log/linux-setting/common_*.log
```

---

## 🔬 技術特點

### 安全特性

- **GPG 簽名驗證**：所有遠端腳本在下載後進行簽名驗證
- **內容驗證**：檢查下載的腳本是否包含危險命令
- **大小限制**：防止下載過大的惡意腳本
- **超時機制**：防止長時間無響應的網絡請求
- **安全 PPA**：所有倉庫使用 GPG 密鑰驗證

### 性能優化

- **並行安裝**：同時安裝多個套件（提升速度約 30%）
- **APT 優化**：自動配置 APT 並行下載與快取（提升速度約 20%）
- **智能備份**：Homebrew 優先（避免編譯），APT/Cargo 備份
- **快取系統**：減少重複下載

### 錯誤處理

- **自動回滾**：失敗時可回滾到安裝前狀態
- **詳細日誌**：結構化日誌便於調試
- **日誌輪轉**：自動清理舊日誌，避免磁盤空間問題
- **進度顯示**：實時顯示安裝進度

### 開發者體驗

- **模組化設計**：每個工具類型獨立模組
- **統一配置**：通過配置文件自定義所有選項
- **多平台支援**：支援多種 Linux 發行版
- **容器測試**：完整的 Docker 測試環境

---

## 📝 重要檔案位置

### 配置文件
- `~/.config/linux-setting/config` - 用戶配置文件
- `~/.config/linux-setting.conf` - 舊版配置（已棄用）

### Shell 配置
- `~/.zshrc` - Zsh 配置
- `~/.p10k.zsh` - Powerlevel10k 主題配置
- `~/.bashrc` - Bash 配置（部分工具別名）

### 工具配置
- `~/.config/nvim` - Neovim 配置（LazyVim）
- `~/.oh-my-zsh` - Oh My Zsh 框架
- `~/.local/bin/` - 自定義二進制文件和符號連結
- `~/.local/venv/` - Python 虛擬環境

### 備份和日誌
- `~/.config/linux-setting-backup/` - 備份目錄
- `~/.local/log/linux-setting/` - 日誌目錄
- `~/.cache/linux-setting/` - 快取目錄

---

## 💾 備份與日誌

### 備份目錄
```bash
ls -la ~/.config/linux-setting-backup/
# 輸出：
# 20240101_120000/  - 備份時間戳
# ├── .zshrc.backup.20240101_120000
# ├── .p10k.zsh.backup.20240101_120000
# └── nvim.backup.20240101_120000
```

### 日誌文件
```bash
# 查看最新日誌
tail -f ~/.local/log/linux-setting/common_$(date +%Y%m%d).log

# 查看錯誤日誌
grep ERROR ~/.local/log/linux-setting/*.log

# 使用 JSON 格式日誌進行分析
LOG_FORMAT=json ./install.sh 2>&1 | jq '.'
```

### 回滾機制

```bash
# 自動回滾（腳本失敗時會提示）
./install.sh

# 手動回滾
cp -r ~/.config/linux-setting-backup/20240101_120000/* ~/
```

---

## 🧾 顯示模式

透過 `TUI_MODE` 環境變數控制輸出詳細程度：

- `quiet`（預設）：只顯示關鍵步驟與結果
- `normal`：顯示完整安裝輸出

```bash
# 安靜模式
TUI_MODE=quiet ./install.sh

# 詳細模式
TUI_MODE=normal ./install.sh --verbose
```

---

## 🔬 高級用法

### 自定義安裝順序

```bash
# 修改 install.sh 中的 install_selected_modules() 函數
# 調整模組安裝順序以滿足特定依賴
```

### 集成到 CI/CD

```bash
#!/bin/bash
# .github/workflows/setup.yml 示例

# 設置環境
export INSTALL_MODE=full
export TUI_MODE=quiet
export ENABLE_PARALLEL_INSTALL=true
export ENABLE_GPG_VERIFY=false  # CI 環境可能禁用 GPG

# 執行安裝
bash -c "$(curl -fsSL https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main/install.sh)" --minimal

# 驗證安裝
command -v nvim && echo "Neovim installed"
command -v docker && echo "Docker installed"
```

### 自動化腳本

```bash
#!/bin/bash
# 僅安裝指定的工具

export INSTALL_MODE=custom
export INSTALL_BASE=true
export INSTALL_DEV_TOOLS=true
export INSTALL_DOCKER=false

./install.sh --minimal --verbose
```

---

## 🤝 客製化

修改 `install.sh` 中的 `REPO_URL`：

```bash
export REPO_URL="https://raw.githubusercontent.com/<your-name>/<your-repo>/main"
```

或創建 fork 並修改：

```bash
# 1. Fork 此專案到你的 GitHub
# 2. 克隆到本地
git clone https://github.com/<your-name>/my-linux-setting.git
cd my-linux-setting

# 3. 修改 install.sh
vim install.sh
# REPO_URL="https://raw.githubusercontent.com/<your-name>/my-linux-setting/main"

# 4. 提交並推送
git add .
git commit -m "Customize repository URL"
git push origin main

# 5. 使用你的版本
bash -c "$(curl -fsSL https://raw.githubusercontent.com/<your-name>/my-linux-setting/main/install.sh)"
```

---

## 📊 性能基準

### 安裝時間（Ubuntu 22.04，Intel i7，16GB RAM）

| 模組 | 時間 | 空間 |
|------|------|------|
| 基礎工具 | 2-3 分鐘 | ~200MB |
| Python | 3-5 分鐘 | ~150MB |
| 終端機 | 1-2 分鐘 | ~50MB |
| Docker | 3-5 分鐘 | ~300MB |
| 開發工具 | 5-8 分鐘 | ~250MB |
| 監控工具 | 1-2 分鐘 | ~100MB |
| **全部** | **15-25 分鐘** | **~1GB** |

### 性能優化效果

- **並行安裝**：提升速度約 30%
- **APT 優化**：提升速度約 20%
- **Homebrew 優先**：Rust 工具安裝速度提升約 80%
- **uv vs pip**：Python 包安裝速度提升約 10-100 倍

---

## 📚 相關文檔

### 內部文檔

- `config/linux-setting.conf` - 配置選項完整列表
- `scripts/core/common.sh` - 公共庫文檔（包含函數註釋）
- `tests/README.md` - 測試說明

### 外部資源

- [Oh My Zsh](https://ohmyz.sh/)
- [Powerlevel10k](https://github.com/romkatv/powerlevel10k)
- [LazyVim](https://github.com/LazyVim/LazyVim)
- [Docker Documentation](https://docs.docker.com/)
- [Homebrew Documentation](https://docs.brew.sh/)

---

## 🤝 貢獻與支持

### 報告 Bug

```bash
# 生成問題報告
./tests/health_check.sh > issue_report.txt
./tests/security_audit.sh >> issue_report.txt
```

然後在 GitHub 創建 issue，附上：
- 系統信息（`cat /etc/os-release`）
- 錯誤日誌（`~/.local/log/linux-setting/*.log`）
- 問題報告文件

### 功能請求

1. Fork 專案
2. 創建功能分支（`git checkout -b feature/amazing-feature`）
3. 提交更改（`git commit -m 'Add amazing feature'`）
4. 推送到分支（`git push origin feature/amazing-feature`）
5. 創建 Pull Request

### 代碼規範

- 遵循現有代碼風格
- 添加適當的註釋
- 更新相關文檔
- 添加測試用例
- 確保通過所有測試

---

## 📄 授權

MIT License - 詳見 LICENSE 文件

---

## 👥 貢獻者

感謝所有貢獻者！

---

## 📞 聯繫

- [GitHub Repository](https://github.com/guan4tou2/my-linux-setting)
- [Issues](https://github.com/guan4tou2/my-linux-setting/issues)
- [Pull Requests](https://github.com/guan4tou2/my-linux-setting/pulls)

---

**Made with ❤️ by Linux Setting Scripts Team**
