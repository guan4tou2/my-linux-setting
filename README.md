# Linux 環境設定腳本 - 增強版

這個腳本可以幫助你快速設定 Linux 開發環境，現在具有更強大的功能：

## 🚀 核心功能
- 基礎工具（git, curl, wget, lsd, bat, ripgrep 等）
- 終端機設定（zsh + oh-my-zsh + powerlevel10k）
- 開發工具（neovim + lazyvim + lazygit）
- 系統監控工具（btop, htop, iftop, nethogs）
- Python 開發環境（包含 uv 現代包管理器）
- Docker 相關工具

## ✨ 新增特性
- 🛡️ **增強錯誤處理**：智能錯誤檢測與回滾機制
- 🏃‍♂️ **進度顯示**：實時安裝進度與時間估計
- 🌐 **智能鏡像源**：自動選擇最佳下載源
- 📦 **虛擬環境管理**：隔離的 Python 工具環境
- 🔄 **自動更新**：一鍵更新所有工具
- 🩺 **健康檢查**：系統配置驗證工具
- 📝 **詳細日誌**：完整的安裝記錄
- 🎯 **版本鎖定**：確保套件版本一致性

## 快速安裝

### 標準安裝
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main/install.sh)"
```

### 進階選項
```bash
# 使用中國鏡像源（提升下載速度）
./install.sh --mirror china

# 最小安裝（僅安裝基礎工具）
./install.sh --minimal

# 更新模式（更新已安裝的工具）
./install.sh --update

# 詳細模式（顯示詳細日誌）
./install.sh --verbose

# 顯示幫助
./install.sh --help
```

![img](img/SCR-20250310-mmxt.png)

## 如果你想 fork：

1. 記得修改 install.sh：
```bash
export REPO_URL="https://raw.githubusercontent.com/{github name}/{repo name}/main"
```


## 🛠️ 系統管理

### 健康檢查
```bash
./scripts/health_check.sh
```

### 更新所有工具
```bash
./scripts/update_tools.sh
```

### 運行測試
```bash
# 基本測試
./tests/test_scripts.sh

# 完整測試套件
./tests/run_all_tests.sh

# Docker 環境測試
./docker-test.sh build     # 建立測試映像
./docker-test.sh test      # 執行測試
./docker-test.sh full-test # 完整安裝測試
```

## 📁 配置文件位置

- zsh：`~/.zshrc`
- powerlevel10k：`~/.p10k.zsh`
- neovim：`~/.config/nvim`
- Python 虛擬環境：`~/.local/venv/system-tools`

## 💾 備份與日誌

- **備份位置**：`~/.config/linux-setting-backup/`
- **日誌位置**：`~/.local/log/linux-setting/`
- **自動回滾**：安裝失敗時可自動回滾到之前狀態

## 🔧 技術改進

### 包管理優化
- 使用 **uv** 作為主要 Python 包管理器（比 pip 快 10-100 倍）
- 智能鏡像源選擇（自動檢測網速）
- 版本鎖定確保安裝一致性

### 錯誤處理
- 詳細的錯誤日誌記錄
- 智能回滾機制
- 網路連接檢測
- 磁盤空間檢查

### 用戶體驗
- 實時進度顯示
- 彩色輸出與狀態圖示
- 模組化安裝選項
- 詳細的安裝報告

## 🧪 測試與開發

### 本地測試
```bash
# 執行所有測試
./tests/run_all_tests.sh

# 單獨測試
./tests/test_dependencies.sh    # 依賴檢查
./tests/test_functionality.sh   # 功能測試

# 配置預覽
./scripts/preview_config.sh
```

### Docker 測試環境
```bash
# 快速測試
./docker-test.sh build && ./docker-test.sh test

# 多系統測試
docker-compose -f docker-compose.test.yml up ubuntu-test
docker-compose -f docker-compose.test.yml --profile legacy up ubuntu20-test
docker-compose -f docker-compose.test.yml --profile debian up debian-test

# 自動測試
docker-compose -f docker-compose.test.yml --profile test up test-runner
```

### CI/CD 支援
- GitHub Actions 工作流程
- 多版本 Ubuntu/Debian 測試
- 自動化安裝驗證
- 性能基準測試
