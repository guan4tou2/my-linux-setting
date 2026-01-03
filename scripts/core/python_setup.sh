#!/bin/bash

# 載入共用函數庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || {
    echo "錯誤: 無法載入共用函數庫"
    exit 1
}

log_info "########## 設定 Python 環境 ##########"

# 初始化進度
init_progress 6

# 安裝 Python 相關套件
show_progress "安裝 Python 基礎套件"
python_packages="python3 python-is-python3 python3-pip python3-venv python3-dev python3-setuptools python3-neovim"

# 使用批量安裝（支持並行）
if command -v install_packages_batch >/dev/null 2>&1; then
    IFS=' ' read -r -a py_packages_array <<< "$python_packages"
    install_packages_batch "${py_packages_array[@]}" || log_warning "部分 Python 套件安裝失敗"
else
    # 後備：逐個安裝
    for pkg in $python_packages; do
        install_apt_package "$pkg"
    done
fi

# 安裝 uv (現代 Python 包管理器)
show_progress "安裝 uv Python 包管理器"
if ! check_command uv; then
    log_info "安裝 uv (Python 包管理器)"
    if [ -f "$SCRIPT_DIR/utils/secure_download.sh" ]; then
        bash "$SCRIPT_DIR/utils/secure_download.sh" uv
    elif [ -f "$SCRIPT_DIR/secure_download.sh" ]; then
        bash "$SCRIPT_DIR/secure_download.sh" uv
    else
        log_warning "找不到安全下載腳本，使用傳統安裝方式"
        if curl -LsSf https://astral.sh/uv/install.sh | sh; then
            log_success "uv 安裝成功"
        else
            log_error "uv 安裝失敗"
            exit 1
        fi
    fi
    
    # 將 uv 添加到 PATH
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
    fi
    
    # 添加 uv 到 shell 配置文件
    safe_append_to_file 'export PATH="$HOME/.cargo/bin:$PATH"' ~/.zshrc
    safe_append_to_file 'export PATH="$HOME/.cargo/bin:$PATH"' ~/.bashrc
else
    log_info "uv 已安裝"
fi

# 配置 uv 鏡像源（簡化為固定使用官方 PyPI）
show_progress "配置 uv 鏡像源"
log_info "使用全球鏡像源 (https://pypi.org/simple/)"
# 注意: uv 不再提供單獨的 'config' 子命令來設置 index-url，
# 相關配置應透過 ~/.uv/config.toml 或環境變數處理。
# 此處略過無效命令，uv 預設即使用 PyPI。

# 創建系統工具虛擬環境
show_progress "創建虛擬環境"
VENV_DIR="$HOME/.local/venv/system-tools"
if [ ! -d "$VENV_DIR" ]; then
    log_info "創建系統工具虛擬環境"
    if check_command uv; then
        uv venv "$VENV_DIR"
    else
        python3 -m venv "$VENV_DIR"
    fi
    # 安裝基礎依賴（包含 setuptools 用於 thefuck）
    "$VENV_DIR/bin/pip" install setuptools
    log_success "虛擬環境創建成功: $VENV_DIR"
fi

# 強制確保基礎依賴存在（處理已存在的 venv）
if [ -x "$VENV_DIR/bin/pip" ]; then
    "$VENV_DIR/bin/pip" install setuptools >/dev/null 2>&1 || true
fi

# 下載 requirements.txt (不使用快取以確保獲取最新版本)
show_progress "下載套件需求文件"
if [ -n "$REQUIREMENTS_URL" ]; then
    safe_download "$REQUIREMENTS_URL" "/tmp/requirements.txt" 3 false
    REQUIREMENTS_FILE="/tmp/requirements.txt"
elif [ -f "$(dirname "$SCRIPT_DIR")/requirements.txt" ]; then
    REQUIREMENTS_FILE="$(dirname "$SCRIPT_DIR")/requirements.txt"
else
    log_warning "未找到 requirements.txt，使用預設套件"
    REQUIREMENTS_FILE=""
fi

# 安裝 Python 工具
show_progress "安裝 Python 工具"
if [ -n "$REQUIREMENTS_FILE" ] && [ -f "$REQUIREMENTS_FILE" ]; then
    log_info "使用 requirements.txt 安裝套件"

    # 在安靜模式下，隱藏 uv / pip 的詳細輸出，只保留錯誤碼與我們自己的 log
    if [ "${TUI_MODE:-quiet}" = "quiet" ]; then
        if check_command uv; then
            if ! uv pip install -r "$REQUIREMENTS_FILE" --python "$VENV_DIR/bin/python"; then
                log_warning "uv 安裝失敗，使用傳統方式"
                "$VENV_DIR/bin/pip" install -r "$REQUIREMENTS_FILE"
            fi
        else
            "$VENV_DIR/bin/pip" install -r "$REQUIREMENTS_FILE"
        fi
    else
        # 一般模式下保留完整輸出，方便除錯
        if check_command uv; then
            uv pip install -r "$REQUIREMENTS_FILE" --python "$VENV_DIR/bin/python" || {
                log_warning "uv 安裝失敗，使用傳統方式"
                "$VENV_DIR/bin/pip" install -r "$REQUIREMENTS_FILE"
            }
        else
            "$VENV_DIR/bin/pip" install -r "$REQUIREMENTS_FILE"
        fi
    fi
else
    # 回退到單個套件安裝
    uv_packages="thefuck ranger-fm s-tui"
    for uv_pkg in $uv_packages; do
        install_with_fallback "$uv_pkg"
    done
fi

# 創建工具軟連結
show_progress "創建工具軟連結"
mkdir -p "$HOME/.local/bin"
for tool in ranger s-tui thefuck; do
    if [ -f "$VENV_DIR/bin/$tool" ]; then
        ln -sf "$VENV_DIR/bin/$tool" "$HOME/.local/bin/$tool"
        log_info "創建軟連結: $tool"
    fi
done

log_success "########## Python 環境設定完成 ##########" 