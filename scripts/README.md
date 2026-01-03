# Scripts 目錄結構

安裝和維護腳本，按功能分類至子目錄。

## 目錄結構

```
scripts/
├── core/          # 核心安裝腳本
├── maintenance/   # 維護與管理腳本
├── config/        # 配置管理腳本
├── testing/       # 測試與診斷腳本
└── utils/         # 工具與輔助腳本
```

---

## 📦 core/ - 核心安裝腳本

由 `install.sh` 直接調用的核心模組腳本：

| 腳本 | 說明 | 對應模組 |
|------|------|----------|
| `common.sh` | 共用函數庫，提供日誌、檢查等基礎功能 | - |
| `base_tools.sh` | 基礎工具安裝（git, curl, lsd, bat 等） | base |
| `dev_tools.sh` | 開發工具安裝（neovim, lazygit, nodejs 等） | dev |
| `python_setup.sh` | Python 環境設置（uv, venv, ranger 等） | python |
| `terminal_setup.sh` | 終端機設定（zsh, oh-my-zsh, p10k 等） | terminal |
| `monitoring_tools.sh` | 監控工具安裝（btop, htop, fail2ban 等） | monitoring |
| `docker_setup.sh` | Docker 相關工具安裝 | docker |

---

## 🔧 maintenance/ - 維護與管理腳本

系統維護和自動化管理腳本：

| 腳本 | 說明 |
|------|------|
| `update_tools.sh` | 更新所有已安裝的工具和套件 |
| `health_check.sh` | 健康檢查，驗證系統和工具狀態 |
| `auto_update.sh` | 自動更新腳本（定期執行） |
| `auto_recovery.sh` | 自動恢復系統到正常狀態 |
| `auto_repair.sh` | 自動修復常見問題 |

---

## ⚙️ config/ - 配置管理腳本

配置文件的管理、同步和版本控制：

| 腳本 | 說明 |
|------|------|
| `config_manager.sh` | 配置管理主腳本（完整版） |
| `config_manager_simple.sh` | 配置管理簡化版 |
| `config_sync.sh` | 配置文件同步工具 |
| `config_version_control.sh` | 配置版本控制 |
| `preview_config.sh` | 預覽配置變更 |
| `auto_sync.sh` | 自動同步配置 |
| `remote_sync.sh` | 遠程配置同步 |

---

## 🧪 testing/ - 測試與診斷腳本

測試和系統診斷工具：

| 腳本 | 說明 |
|------|------|
| `system_test.sh` | 系統完整性測試 |
| `diagnostic_system.sh` | 系統診斷工具 |
| `test_reporter.sh` | 測試報告生成器 |

---

## 🛠️ utils/ - 工具與輔助腳本

通用工具和輔助功能：

| 腳本 | 說明 |
|------|------|
| `secure_download.sh` | 安全下載工具（驗證 checksum） |
| `security_audit.sh` | 安全審計腳本 |
| `performance_optimizer.sh` | 性能優化工具 |
| `privilege_manager.sh` | 權限管理工具 |

---

## 使用說明

```bash
# 載入共用函數庫
source "$SCRIPT_DIR/core/common.sh"

# 執行模組安裝
bash "$SCRIPT_DIR/core/base_tools.sh"

# 維護腳本
bash scripts/maintenance/update_tools.sh

# 測試腳本
bash scripts/testing/system_test.sh
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
