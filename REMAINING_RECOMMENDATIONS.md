# 剩餘建議 - 待改進建議

以下是原代碼審查中提及但尚未完全實現的改進建議，以及進一步優化的方向。

---

## 📋 待改進清單

### 高優先級

#### 1. API 文檔
**狀態**: 部分完成
**建議**: 為所有公共函數添加完整的 API 文檔

**實現方案**:
```bash
# 在 common.sh 中添加完整的函數文檔頭格式

# ==============================================================================
# 函數: install_package
# 描述: 通用包安裝函數，支援多種包管理器
# 參數:
#   $1 (package): 要安裝的包名
#   $2 (force): 是否強制重新安裝 [true|false], 默認 false
# 回傳值:
#   0 - 安裝成功或已存在
#   1 - 安裝失敗
# 副作用:
#   - 修改系統包管理器數據庫
#   - 可能更新快取
# 環境變數使用:
#   - PKG_MANAGER: 包管理器類型
#   - TUI_MODE: 顯示模式
# 範例:
#   install_package "curl"              # 安裝 curl
#   install_package "git" true          # 強制重新安裝 git
#   install_package "docker-ce" false     # 正常安裝（如果不存在）
# 相依函數:
#   - check_command()
#   - log_info(), log_success(), log_error()
# 另見:
#   - install_packages_batch()
#   - install_brew_package()
# ==============================================================================
install_package() {
    ...
}
```

**需要添加文檔的函數**:
- [ ] 所有 logging 函數
- [ ] 所有 system check 函數
- [ ] 所有 install 函數
- [ ] 所有 download 函數
- [ ] 所有 TUI 函數
- [ ] 所有 cache 函數
- [ ] 所有 validation 函數

---

#### 2. 架構圖和文檔
**狀態**: 未實現
**建議**: 添加系統架構圖和模組依賴關係圖

**實現方案**:

**docs/ARCHITECTURE.md**:
```markdown
# Linux Setting Scripts - 系統架構

## 模組依賴關係

```
install.sh (主入口)
    │
    ├─→ common.sh (核心庫)
    │       │
    │       ├─→ logging (日誌系統)
    │       ├─→ security (安全驗證)
    │       ├─→ package_install (包安裝)
    │       ├─→ download (下載管理)
    │       ├─→ cache (快取系統)
    │       └─→ TUI (文字界面)
    │
    ├─→ base_tools.sh (基礎工具)
    │       └─→ lsd, tealdeer, bat, ripgrep, fzf
    │
    ├─→ python_setup.sh (Python 環境)
    │       └─→ uv, pip, ranger, s-tui, thefuck
    │
    ├─→ docker_setup.sh (Docker)
    │       └─→ docker-ce, lazydocker
    │
    ├─→ terminal_setup.sh (終端環境)
    │       └─→ zsh, oh-my-zsh, p10k, 插件
    │
    ├─→ dev_tools.sh (開發工具)
    │       └─→ neovim, lazygit, cargo, nodejs
    │
    └─→ monitoring_tools.sh (監控工具)
            └─→ btop, htop, iftop, nethogs, fail2ban
```

## 數據流

```
使用者輸入
    │
    ├─→ install.sh
    │       │
    │       ├─→ 載入設定檔
    │       │       │
    │       │       ├─→ 設定環境變數
    │       │       ├─→ 設定預設值
    │       │       └─→ 載出變數
    │       │
    │       ├─→ 環境檢查
    │       │       │
    │       │       ├─→ 檢測發行版
    │       │       ├─→ 檢測套件管理器
    │       │       ├─→ 檢查權限
    │       │       ├─→ 檢查依賴
    │       │       └─→ 檢查磁碟空間
    │       │
    │       ├─→ 備份現有設定
    │       │       │
    │       │       ├─→ 複製 .zshrc
    │       │       ├─→ 複製 .p10k.zsh
    │       │       ├─→ 複製 .config/nvim
    │       │       └─→ 保存到 BACKUP_DIR
    │       │
    │       ├─→ 顯示 TUI 選單
    │       │       │
    │       │       ├─→ 使用者選擇模組
    │       │       └─→ 確認安裝
    │       │
    │       ├─→ 順序安裝模組
    │       │       │
    │       │       ├─→ base (依賴)
    │       │       ├─→ dev
    │       │       ├─→ python
    │       │       ├─→ monitoring
    │       │       ├─→ docker
    │       │       └─→ terminal
    │       │
    │       ├─→ 產生安裝報告
    │       │       │
    │       │       └─→ 顯示下一步操作
    │               │
    │               └─→ 顯示成功訊息
```

## 錯誤處理流

```
錯誤發生
    │
    ├─→ 捕獲
    │       │
    │       ├─→ 記錯日誌
    │       │       └─→ LOG_FILE
    │       │
    │       ├─→ 顯示錯誤訊息
    │       │       │
    │       │       └─→ 使用者介面
    │       │
    │       ├─→ 詢問使用者是否回滾
    │       │       │
    │       │       ├─→ 是: rollback_installation()
    │       │       └─→ 否: 清理臨時檔案
    │       │
    │       ├─→ 清理臨時檔案
    │       │       │
    │       │       └─→ cleanup_temp_files()
    │       │
    │       └─→ 退出 (exit $exit_code)
```

## 設定載入優先級

```
1. 命令行參數（最高優先級）
2. 環境變數
3. 設定檔案 (~/.config/linux-setting/config)
4. 預設值（最低優先級）
```

## 檔案佈局

```
~/.config/linux-setting/
    ├── config                 # 主設定檔案
    └── logs/                  # 日誌目錄（已廢棄，使用 ~/.local/log）

~/.local/
    ├── bin/                   # 自訂二進制檔案
    ├── log/linux-setting/     # 日誌目錄
    ├── venv/                  # Python 虛擬環境
    └── cache/linux-setting/    # 下載快取

~/.config/
    ├── linux-setting-backup/   # 設定備份
    ├── nvim/                  # Neovim 設定
    └── oh-my-zsh/            # Zsh 框架
```
```
```

---

#### 3. Dockerfile 安全加固
**狀態**: 部分完成
**建議**: 進一步加固 Dockerfile 以提高容器安全性

**實現方案**:

**Dockerfile 安全改進**:
```dockerfile
# Linux Setting Scripts - Docker 測試環境
FROM ubuntu:22.04

# 安全改進 1: 使用非 root 使用者
# ARG USERNAME=testuser
# ARG USERGROUP=testgroup
# ARG UID=1000
# ARG GID=1000

# 安全改進 2: 不要以 root 執行
# RUN groupadd -r --gid $GID $USERGROUP && \
#     useradd -r -m -g $USERGROUP -u $UID $USERNAME

# 環境變數
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Taipei
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV TEST_ENVIRONMENT=docker
ENV SKIP_NETWORK_TESTS=true

# 安全改進 3: 最小化鏡像層級
RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        wget \
        bc \
        git \
        sudo \
        python3 \
        python3-pip \
        python3-venv \
        build-essential \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg2 \
        lsb-release \
        tzdata && \
    # 設定時區
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone && \
    # 清理
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 安全改進 4: 使用 COPY --chown 而不是 USER 指令
WORKDIR /opt/linux-setting
COPY --chown=testuser:testuser . /opt/linux-setting/

# 安全改進 5: 僅設必要的執行權限
RUN find /opt/linux-setting -type f -name "*.sh" -exec chmod 750 {} \;

# 設定環境變數
ENV HOME=/home/testuser
ENV PATH="/home/testuser/.local/bin:/home/testuser/.cargo/bin:$PATH"

# 建立必要目錄
RUN mkdir -p $HOME/.config && \
    mkdir -p $HOME/.local/log && \
    mkdir -p $HOME/.local/bin

# 設定預設命令
CMD ["/bin/bash"]

# 健康檢查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python3 --version || exit 1

# 元數據標籤
LABEL maintainer="Linux Setting Scripts" \
      description="測試環境 for Linux Setting Scripts" \
      version="2.0.0" \
      architecture="amd64"
```

---

### 中優先級

#### 4. 更完善的單元測試
**狀態**: 基礎單元測試已實現
**建議**: 添加更多測試用例，提高覆蓋率

**實現方案**:

**tests/test_all_functions.sh**:
```bash
#!/usr/bin/env bash

# 完整的單元測試套件
# 涵蓋 common.sh 的所有函數

# 測試覆蓋目標
TOTAL_FUNCTIONS=50  # 估算
TARGET_COVERAGE=80%   # 目標覆蓋率

# 測試函數列表
TEST_FUNCTIONS=(
    # Logging (5 個函數)
    "test_log_functions"
    "test_log_rotation"
    "test_json_logging"
    
    # System Checks (8 個函數)
    "test_distro_detection"
    "test_distro_family"
    "test_package_manager"
    "test_command_check"
    "test_python_version"
    "test_disk_space"
    "test_network"
    "test_architecture"
    
    # Installation (10 個函數)
    "test_install_package"
    "test_install_packages_batch"
    "test_install_apt_package"
    "test_install_brew_package"
    "test_install_with_fallback"
    "test_install_with_homebrew_fallback"
    
    # Download (5 個函數)
    "test_safe_download"
    "test_validate_script_content"
    "test_verify_gpg_signature"
    
    # Cache (4 個函數)
    "test_init_cache_system"
    "test_is_cache_valid"
    "test_get_from_cache"
    "test_save_to_cache"
    
    # File Operations (3 個函數)
    "test_backup_file"
    "test_safe_append_to_file"
    
    # TUI (5 個函數)
    "test_ensure_tui_available"
    "test_tui_menu"
    "test_tui_checklist"
    "test_tui_yesno"
    "test_tui_msgbox"
    
    # Version (1 個函數)
    "test_version_comparison"
    
    # Security (2 個函數)
    "test_validate_script_content"
    "test_verify_gpg_signature"
)

# 執行所有測試
run_all_tests() {
    local passed=0
    local failed=0
    local total=${#TEST_FUNCTIONS[@]}
    
    for test_func in "${TEST_FUNCTIONS[@]}"; do
        if $test_func; then
            ((passed++))
            echo "✓ $test_func"
        else
            ((failed++))
            echo "✗ $test_func"
        fi
    done
    
    echo ""
    echo "========================================"
    echo "測試覆蓋率: $((passed * 100 / total))%"
    echo "通過: $passed / $total"
    echo "失敗: $failed / $total"
    echo "========================================"
    
    if [ $((passed * 100 / total)) -ge $TARGET_COVERAGE ]; then
        echo "✓ 達成目標覆蓋率: $TARGET_COVERAGE%"
        return 0
    else
        echo "✗ 低於目標覆蓋率: $TARGET_COVERAGE%"
        return 1
    fi
}

# 啟用
run_all_tests
```

---

#### 5. 整合測試改進
**狀態**: 基礎測試腳本存在
**建議**: 添加更完整的整合測試流程

**實現方案**:

**tests/integration/full_install_test.sh**:
```bash
#!/usr/bin/env bash

# 完整的整合測試
# 測試完整的安裝流程

# 測試場景
TEST_SCENARIOS=(
    "minimal_install"
    "full_install"
    "update_mode"
    "dry_run"
    "with_config_file"
    "arm64_platform"
    "wsl_platform"
)

# 測試函數
test_minimal_install() {
    echo "測試最小安裝..."
    DRY_RUN=true ./install.sh --minimal || return 1
    echo "✓ 最小安裝測試通過"
}

test_full_install() {
    echo "測試完整安裝..."
    # 只在 CI 環境中執行完整安裝
    if [ "${CI:-}" = "true" ]; then
        ./install.sh --minimal || return 1
        echo "✓ 完整安裝測試通過"
    else
        echo "- SKIP: 完整安裝測試（非在 CI 環境）"
    fi
}

test_update_mode() {
    echo "測試更新模式..."
    ./install.sh --update || return 1
    echo "✓ 更新模式測試通過"
}

test_dry_run() {
    echo "測試預覽模式..."
    DRY_RUN=true ./install.sh || return 1
    echo "✓ 預覽模式測試通過"
}

test_with_config_file() {
    echo "測試使用設定檔..."
    cat > /tmp/test_config.conf << 'EOF'
INSTALL_MODE=minimal
ENABLE_PARALLEL_INSTALL=false
EOF
    CONFIG_FILE=/tmp/test_config.conf ./install.sh --dry-run || return 1
    echo "✓ 設定檔測試通過"
}

test_arm64_platform() {
    # 需要模擬 ARM64 環境
    echo "測試 ARM64 平台..."
    ARCH=aarch64 ./install.sh --dry-run || return 1
    echo "✓ ARM64 測試通過"
}

test_wsl_platform() {
    # 需要 WSL 環境
    if grep -qi microsoft /proc/version; then
        echo "測試 WSL 平台..."
        PLATFORM=wsl ./install.sh --dry-run || return 1
        echo "✓ WSL 測試通過"
    else
        echo "- SKIP: 非 WSL 環境"
    fi
}

# 執行所有整合測試
run_integration_tests() {
    local passed=0
    local failed=0
    
    for scenario in "${TEST_SCENARIOS[@]}"; do
        if test_$scenario; then
            ((passed++))
        else
            ((failed++))
        fi
    done
    
    echo ""
    echo "========================================"
    echo "整合測試摘要"
    echo "========================================"
    echo "通過: $passed / ${#TEST_SCENARIOS[@]}"
    echo "失敗: $failed / ${#TEST_SCENARIOS[@]}"
    echo "========================================"
    
    [ $failed -eq 0 ]
}

run_integration_tests
```

---

#### 6. CI/CD 配置
**狀態**: 未實現
**建議**: 添加 GitHub Actions 工作流程

**實現方案**:

**.github/workflows/ci.yml**:
```yaml
name: CI

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  security-audit:
    name: 安全審計
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: 執行安全審計
        run: |
          bash tests/security_audit.sh
          
      - name: 上傳審計結果
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: security-audit-results
          path: security-audit-results.txt

  unit-tests:
    name: 單元測試
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: 執行單元測試
        run: |
          bash tests/test_common_library.sh
          
      - name: 上傳測試結果
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: unit-test-results
          path: test-results.txt

  docker-test:
    name: Docker 測試
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: 建置 Docker 鏡像
        run: |
          docker build -t linux-setting:test .
          
      - name: 在 Docker 中執行測試
        run: |
          docker run --rm linux-setting:test bash tests/run_all_tests.sh

  integration-test:
    name: 整合測試
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-20.04, ubuntu-22.04]
        mode: [minimal, update]
    steps:
      - uses: actions/checkout@v4
      
      - name: 執行整合測試
        run: |
          bash tests/integration/full_install_test.sh
          
      - name: 上傳整合測試結果
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: integration-results-${{ matrix.os }}-${{ matrix.mode }}
          path: integration-results.txt
```

---

### 低優先級

#### 7. Web 介面
**狀態**: 未實現
**建議**: 添加基於 Web 的設定介面

**實現方案**:
創建一個簡單的 HTML/JavaScript 設定生成器，使用者可以透過網頁選擇選項並下載設定檔案。

#### 8. 插件系統
**狀態**: 未實現
**建議**: 添加模組化插件系統，允許社群貢獻額外的安裝模組

**實現方案**:
定義插件介面規範，允許第三方開發獨立的安裝腳本。

#### 9. 遠端日誌
**狀態**: 未實現
**建議**: 添加遠端日誌收集和分析功能（可選）

**實現方案**:
透過設定檔案啟用，將日誌發送到遠端伺服器進行分析。

---

## 📊 實施優先級

### 立即實施（1-2 週）
- [ ] 完善核心函數的 API 文檔
- [ ] 添加基礎架構文檔

### 短期實施（1 個月）
- [ ] 提升單元測試覆蓋率到 80%
- [ ] 實現整合測試套件
- [ ] 設置 CI/CD 流程

### 中期實施（3 個月）
- [ ] 完善 Dockerfile 安全加固
- [ ] 實現插件系統框架

### 長期實施（6 個月+）
- [ ] 開發 Web 設定介面
- [ ] 實現遠端日誌收集（可選）

---

## 🎯 目標品質指標

| 指標 | 當前 | 目標 | 差距 |
|------|------|------|------|
| API 文檔覆蓋率 | 10% | 90% | -80% |
| 單元測試覆蓋率 | 30% | 80% | -50% |
| 整合測試覆蓋率 | 0% | 60% | -60% |
| CI/CD 自動化 | 0% | 100% | -100% |
| 架構文檔完整性 | 0% | 100% | -100% |

---

**最後更新**: 2024-01-04
**版本**: 2.0.0
