#!/usr/bin/env bash
#!/bin/bash

# 載入共用函數庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_SH="$SCRIPT_DIR/../core/common.sh"
if [ ! -f "$COMMON_SH" ]; then
    COMMON_SH="$SCRIPT_DIR/common.sh"
fi

source "$COMMON_SH" || {
    echo "錯誤: 無法載入共用函數庫"
    exit 1
}

# 在嚴格 shell（set -u）環境下提供安全預設值
MIRROR_MODE="${MIRROR_MODE:-auto}"
INSTALL_MODE="${INSTALL_MODE:-full}"

log_info "########## 配置預覽工具 ##########"

# 預計安裝時間（分鐘）
declare -A INSTALL_TIMES
INSTALL_TIMES[python]=5
INSTALL_TIMES[docker]=10
INSTALL_TIMES[base]=8
INSTALL_TIMES[terminal]=7
INSTALL_TIMES[dev]=15
INSTALL_TIMES[monitoring]=6

# 預計磁盤空間（MB）
declare -A DISK_USAGE
DISK_USAGE[python]=150
DISK_USAGE[docker]=500
DISK_USAGE[base]=200
DISK_USAGE[terminal]=100
DISK_USAGE[dev]=800
DISK_USAGE[monitoring]=80

# 配置文件預覽
show_config_preview() {
    local module="$1"
    
    echo ""
    log_info "=============== $module 模組配置預覽 ==============="
    
    case "$module" in
        "python")
            cat << 'EOF'
📦 Python 開發環境配置：

🔧 將要安裝的套件：
  - python3, python3-pip, python3-venv
  - python3-dev, python3-setuptools
  - uv (現代 Python 包管理器)

🐍 Python 工具：
  - thefuck==3.32 (命令糾錯工具)
  - ranger-fm==1.9.3 (終端文件管理器)
  - s-tui==1.1.4 (系統壓力測試工具)

📁 配置文件：
  - 虛擬環境: ~/.local/venv/system-tools/
  - uv 配置: ~/.config/uv/
  - 工具軟連結: ~/.local/bin/

🌐 鏡像源配置：
EOF
            if [ "$MIRROR_MODE" = "china" ]; then
                echo "  - 主要: https://pypi.tuna.tsinghua.edu.cn/simple/"
                echo "  - 備用: https://pypi.org/simple/"
            else
                echo "  - 主要: https://pypi.org/simple/"
            fi
            ;;
            
        "terminal")
            cat << 'EOF'
🖥️ 終端環境配置：

🐚 Shell 配置：
  - zsh (現代 Shell)
  - oh-my-zsh (zsh 框架)
  - powerlevel10k (美化主題)

🔌 Zsh 插件：
  - zsh-autosuggestions (自動建議)
  - zsh-syntax-highlighting (語法高亮)
  - zsh-history-substring-search (歷史搜尋)
  - you-should-use (別名提醒)

📝 配置文件：
  - ~/.zshrc (zsh 配置)
  - ~/.p10k.zsh (主題配置)
  - ~/.oh-my-zsh/ (框架目錄)

🎨 字體：
  - FiraCode (支援編程字體)
EOF
            ;;
            
        "base")
            cat << 'EOF'
⚙️ 基礎工具配置：

🔧 系統工具：
  - git, curl, wget, unzip, tar
  - build-essential, pkg-config

🚀 現代化工具：
  - lsd (現代 ls 替代品)
  - bat (現代 cat 替代品)
  - ripgrep (現代 grep 替代品)
  - fd-find (現代 find 替代品)
  - fzf (模糊搜尋工具)

📁 配置：
  - 工具別名將添加到 ~/.zshrc
  - 二進制文件位於 /usr/local/bin/
EOF
            ;;
            
        "dev")
            cat << 'EOF'
💻 開發工具配置：

📝 編輯器：
  - Neovim (現代編輯器)
  - LazyVim (預配置的 Neovim 設定)

🌐 Runtime 環境：
  - Node.js + npm (JavaScript)
  - Cargo (Rust 包管理器)
  - Lua + LuaRocks (Lua 環境)

🔀 版本控制：
  - lazygit (Git TUI 工具)

📁 配置目錄：
  - ~/.config/nvim/ (Neovim 配置)
  - ~/.cargo/ (Rust 工具)
  - ~/.npm/ (npm 緩存)
EOF
            ;;
            
        "docker")
            cat << 'EOF'
🐳 Docker 環境配置：

🏗️ Docker 組件：
  - docker-ce (Docker 引擎)
  - docker-ce-cli (命令行工具)
  - containerd.io (容器運行時)
  - docker-buildx-plugin (構建工具)
  - docker-compose-plugin (編排工具)

🎛️ 管理工具：
  - lazydocker (Docker TUI 管理器)

👥 用戶配置：
  - 將用戶添加到 docker 群組
  - 啟動 Docker 服務

📁 數據目錄：
  - /var/lib/docker/ (Docker 數據)
EOF
            ;;
            
        "monitoring")
            cat << 'EOF'
📊 監控工具配置：

🖥️ 系統監控：
  - btop (現代系統監控器)
  - htop (進程監控器)

🌐 網路監控：
  - iftop (網路流量監控)
  - nethogs (進程網路監控)

🛡️ 安全工具：
  - fail2ban (入侵防護系統)

📁 配置文件：
  - /etc/fail2ban/ (fail2ban 配置)
  - 工具別名添加到 ~/.zshrc
EOF
            ;;
    esac
    
    echo ""
    echo "⏱️  預計安裝時間: ${INSTALL_TIMES[$module]} 分鐘"
    echo "💾 預計磁盤用量: ${DISK_USAGE[$module]} MB"
    echo "==============================================="
}

# 顯示完整安裝預覽
show_full_preview() {
    local selected_modules="$1"
    local total_time=0
    local total_space=0
    
    echo ""
    log_info "########## 完整安裝計劃預覽 ##########"
    echo ""
    
    # 系統需求檢查
    echo "🔍 系統需求檢查："
    echo "  - 作業系統: Ubuntu/Debian"
    echo "  - Python 版本: >= 3.8"
    echo "  - 可用磁盤空間: >= 3GB"
    echo "  - 網路連接: 需要"
    echo "  - sudo 權限: 需要"
    echo ""
    
    # 鏡像源設定
    echo "🌐 鏡像源設定："
    case "$MIRROR_MODE" in
        "china")
            echo "  - 模式: 中國鏡像源 (提升下載速度)"
            echo "  - PyPI: https://pypi.tuna.tsinghua.edu.cn/simple/"
            ;;
        "global")
            echo "  - 模式: 全球鏡像源"
            echo "  - PyPI: https://pypi.org/simple/"
            ;;
        "auto")
            echo "  - 模式: 自動選擇 (根據網速)"
            ;;
    esac
    echo ""
    
    # 安裝模式
    echo "🎯 安裝模式："
    case "$INSTALL_MODE" in
        "minimal")
            echo "  - 最小安裝模式 (僅基礎工具)"
            selected_modules="base python"
            ;;
        "full")
            echo "  - 完整安裝模式 (所有組件)"
            ;;
    esac
    echo ""
    
    # 將要安裝的模組
    echo "📦 將要安裝的模組："
    for module in $selected_modules; do
        echo "  ✓ $module (${INSTALL_TIMES[$module]} 分鐘, ${DISK_USAGE[$module]} MB)"
        total_time=$((total_time + ${INSTALL_TIMES[$module]}))
        total_space=$((total_space + ${DISK_USAGE[$module]}))
    done
    echo ""
    
    # 總計資源需求
    echo "📊 總計資源需求："
    echo "  ⏱️  總安裝時間: 約 $total_time 分鐘"
    echo "  💾 總磁盤空間: 約 $total_space MB"
    echo ""
    
    # 備份與日誌
    echo "💾 備份與日誌："
    echo "  - 配置備份: ~/.config/linux-setting-backup/$(date +%Y%m%d_%H%M%S)/"
    echo "  - 安裝日誌: ~/.local/log/linux-setting/install_$(date +%Y%m%d_%H%M%S).log"
    echo "  - 自動回滾: 安裝失敗時可選擇回滾"
    echo ""
    
    # 安裝後配置
    echo "⚡ 安裝後配置："
    echo "  - PATH 環境變數將自動更新"
    echo "  - Shell 別名將自動配置"
    echo "  - 服務將自動啟動 (如 Docker)"
    echo "  - 建議重新啟動終端或重新登入"
    echo ""
    
    # 可用的管理命令
    echo "🛠️  可用的管理命令："
    echo "  - ./scripts/health_check.sh     # 系統健康檢查"
    echo "  - ./scripts/update_tools.sh     # 更新所有工具"
    echo "  - ./install.sh --update         # 快速更新模式"
    echo "  - ./tests/test_scripts.sh       # 運行測試套件"
    echo ""
    
    echo "########################################"
}

# 顯示配置文件內容預覽
show_config_files_preview() {
    echo ""
    log_info "########## 配置文件內容預覽 ##########"
    echo ""
    
    echo "📝 主要配置文件將包含以下內容："
    echo ""
    
    echo "🔸 ~/.zshrc 新增內容："
    cat << 'EOF'
# Linux Setting Scripts 配置
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# 工具別名
alias ll='lsd -la'
alias la='lsd -A'
alias l='lsd -CF'
alias cat='bat'
alias find='fd'
alias grep='rg'
alias nv='nvim'
alias lzd='lazydocker'

# thefuck 配置
eval $(thefuck --alias)

# Powerlevel10k 主題
POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
EOF
    
    echo ""
    echo "🔸 uv 配置 (~/.config/uv/config.toml)："
    if [ "$MIRROR_MODE" = "china" ]; then
        cat << 'EOF'
[global]
index-url = "https://pypi.tuna.tsinghua.edu.cn/simple/"
extra-index-url = ["https://pypi.org/simple/"]
EOF
    else
        cat << 'EOF'
[global]
index-url = "https://pypi.org/simple/"
EOF
    fi
    
    echo ""
    echo "🔸 Python 虛擬環境結構："
    echo "  ~/.local/venv/system-tools/"
    echo "  ├── bin/"
    echo "  │   ├── python -> python3"
    echo "  │   ├── pip"
    echo "  │   ├── thefuck"
    echo "  │   ├── ranger"
    echo "  │   └── s-tui"
    echo "  ├── lib/"
    echo "  └── share/"
    echo ""
    
    echo "########################################"
}

# 互動式模組選擇與預覽
interactive_preview() {
    local modules="python docker base terminal dev monitoring"
    local selected=""
    
    while true; do
        echo ""
        log_info "請選擇要預覽的模組 (可多選，用空格分隔)："
        echo ""
        echo "1) python     - Python 開發環境"
        echo "2) docker     - Docker 容器環境"  
        echo "3) base       - 基礎系統工具"
        echo "4) terminal   - 終端機環境"
        echo "5) dev        - 開發工具"
        echo "6) monitoring - 系統監控工具"
        echo "7) all        - 預覽所有模組"
        echo "8) preview    - 顯示完整安裝預覽"
        echo "9) files      - 顯示配置文件預覽"
        echo "0) exit       - 退出"
        echo ""
        read -p "請輸入選項 (例如: 1 3 4): " -r input
        
        case "$input" in
            *1*) show_config_preview "python" ;;
            *2*) show_config_preview "docker" ;;
            *3*) show_config_preview "base" ;;
            *4*) show_config_preview "terminal" ;;
            *5*) show_config_preview "dev" ;;
            *6*) show_config_preview "monitoring" ;;
            *7*) 
                for module in $modules; do
                    show_config_preview "$module"
                done
                ;;
            *8*|*preview*)
                if [ -z "$selected" ]; then
                    selected="python base terminal dev"
                fi
                show_full_preview "$selected"
                ;;
            *9*|*files*)
                show_config_files_preview
                ;;
            *0*|*exit*|"")
                log_info "退出配置預覽"
                break
                ;;
            *)
                # 解析用戶選擇的模組
                selected=""
                for choice in $input; do
                    case $choice in
                        1) selected="$selected python" ;;
                        2) selected="$selected docker" ;;
                        3) selected="$selected base" ;;
                        4) selected="$selected terminal" ;;
                        5) selected="$selected dev" ;;
                        6) selected="$selected monitoring" ;;
                    esac
                done
                
                if [ -n "$selected" ]; then
                    for module in $selected; do
                        show_config_preview "$module"
                    done
                else
                    log_warning "無效輸入，請重試"
                fi
                ;;
        esac
        
        echo ""
        read -p "按 Enter 繼續..." -r
    done
}

# 主函數
main() {
    echo ""
    echo "歡迎使用 Linux Setting Scripts 配置預覽工具！"
    echo ""
    echo "此工具可以幫助您："
    echo "• 🔍 預覽將要安裝的組件"
    echo "• ⏱️  估算安裝時間和磁盤空間"
    echo "• 📝 查看配置文件內容"
    echo "• 🛠️  了解安裝後的系統變化"
    echo ""
    
    # 檢查是否有參數
    if [ $# -gt 0 ]; then
        case "$1" in
            --all)
                local modules="python docker base terminal dev monitoring"
                for module in $modules; do
                    show_config_preview "$module"
                done
                show_full_preview "$modules"
                ;;
            --full-preview)
                show_full_preview "${2:-python base terminal dev}"
                ;;
            --files)
                show_config_files_preview
                ;;
            *)
                show_config_preview "$1"
                ;;
        esac
    else
        interactive_preview
    fi
}

# 執行主函數
main "$@"
