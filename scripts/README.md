# Scripts 目錄結構

安裝和維護腳本，按功能分類至子目錄。

## 目錄結構

```
scripts/
├── core/          # 核心安裝腳本
├── maintenance/   # 維護與管理腳本
├── config/        # 配置預覽腳本
└── utils/         # 工具與輔助腳本
```

---

## 📦 core/ - 核心安裝腳本

供 `install.sh` 與安裝模組使用的核心腳本，以及自訂模組模板：

| 腳本 | 說明 | 對應模組 |
|------|------|----------|
| `common.sh` | 共用函數庫，提供日誌、檢查等基礎功能 | - |
| `module_manager.sh` | 讀取模組配置並管理安裝流程 | - |
| `custom_module.sh.template` | 新增自訂安裝模組的模板 | - |
| `base_tools.sh` | 基礎工具安裝（git, curl, lsd, bat 等） | base |
| `dev_tools.sh` | 開發工具安裝（neovim, lazygit, nodejs 等） | dev |
| `python_setup.sh` | Python 環境設置（uv, venv, ranger 等） | python |
| `terminal_setup.sh` | 終端機設定（zsh, oh-my-zsh, p10k 等） | terminal |
| `monitoring_tools.sh` | 監控工具安裝（btop, htop, fail2ban 等） | monitoring |
| `docker_setup.sh` | Docker 相關工具安裝 | docker |

---

## 🔧 maintenance/ - 維護與管理腳本

工具更新與系統健康檢查腳本：

| 腳本 | 說明 |
|------|------|
| `update_tools.sh` | 更新所有已安裝的工具和套件 |
| `health_check.sh` | 健康檢查，驗證系統和工具狀態 |

---

## ⚙️ config/ - 配置預覽腳本

預覽安裝配置與模組內容：

| 腳本 | 說明 |
|------|------|
| `preview_config.sh` | 預覽配置變更 |

---

## 🛠️ utils/ - 工具與輔助腳本

通用工具和輔助功能：

| 腳本 | 說明 |
|------|------|
| `secure_download.sh` | 安全下載工具（驗證 checksum） |

---

## 使用說明

以下指令從專案根目錄執行：

```bash
# 載入共用函數庫
source scripts/core/common.sh

# 執行模組安裝
bash scripts/core/base_tools.sh

# 維護腳本
bash scripts/maintenance/update_tools.sh

# 配置預覽
bash scripts/config/preview_config.sh --help

# 測試入口（測試腳本集中在專案根目錄的 tests/）
bash tests/run_all_tests.sh
```

---

## 開發指南

### 添加新腳本

1. 確定腳本類別
2. 使用描述性名稱：`xxx_setup.sh` 或 `xxx_tools.sh`
3. 添加執行權限：`chmod +x scripts/category/new_script.sh`
4. 更新此 README

### 測試

```bash
./tests/run_all_tests.sh       # 測試所有腳本
./tests/test_scripts.sh        # 測試特定功能
```
