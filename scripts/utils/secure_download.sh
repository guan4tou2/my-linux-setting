#!/usr/bin/env bash
#!/bin/bash

# 安全下載與執行腳本工具
# 用於替換直接執行遠程腳本的危險做法

# 載入共用函數庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || {
    echo "錯誤: 無法載入共用函數庫"
    exit 1
}

# 安全配置
readonly DOWNLOAD_TIMEOUT=30
readonly MAX_SCRIPT_SIZE=1048576  # 1MB
readonly ALLOWED_DOMAINS=(
    "raw.githubusercontent.com"
    "get.docker.com"
    "astral.sh"
    "superfile.netlify.app"
)

# 驗證域名是否在允許列表中
verify_domain() {
    local url="$1"
    local domain
    domain=$(echo "$url" | sed -e 's/[^/]*\/\/\([^@]*@\)\?\([^:/]*\).*/\2/')
    
    for allowed_domain in "${ALLOWED_DOMAINS[@]}"; do
        if [[ "$domain" == "$allowed_domain" ]]; then
            return 0
        fi
    done
    
    log_error "不被信任的域名: $domain"
    return 1
}

# 檢查腳本內容安全性
check_script_safety() {
    local script_file="$1"
    local suspicious_patterns=(
        "rm -rf /"
        "dd if="
        "mkfs\."
        "> /etc/passwd"
        "> /etc/shadow"
        "wget.*|.*sh"
        "curl.*|.*sh"
        "nc -l"
        "backdoor"
        "reverse shell"
    )
    
    for pattern in "${suspicious_patterns[@]}"; do
        # 允許在特定受信任情境下出現 curl ... | sh（例如 uv / oh-my-zsh 官方安裝腳本）
        if [ "$pattern" = "curl.*|.*sh" ] && [ "${SECURE_DOWNLOAD_ALLOW_PIPE:-0}" = "1" ]; then
            continue
        fi
        if grep -qi "$pattern" "$script_file"; then
            log_warning "發現可疑內容: $pattern"
            return 1
        fi
    done
    
    # 檢查是否包含過多的權限提升操作
    local sudo_count
    sudo_count=$(grep -c "sudo\|su " "$script_file" 2>/dev/null || echo 0)
    # 對受信任腳本（例如 uv / oh-my-zsh 官方安裝腳本）放寬 sudo 次數限制
    if [ "${SECURE_DOWNLOAD_ALLOW_PIPE:-0}" != "1" ] && [ "$sudo_count" -gt 10 ]; then
        log_warning "腳本包含過多 sudo 操作 ($sudo_count 次)"
        return 1
    fi
    
    return 0
}

# 計算文件 checksum
calculate_checksum() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | cut -d' ' -f1
    else
        log_warning "無法計算 checksum，請安裝 sha256sum 或 shasum"
        echo "no-checksum"
    fi
}

# 安全下載並執行腳本
secure_download_and_execute() {
    local url="$1"
    local expected_checksum="$2"
    local description="$3"
    local temp_script
    
    log_info "安全下載: $description"
    
    # 驗證域名
    if ! verify_domain "$url"; then
        return 1
    fi
    
    # 創建臨時文件
    temp_script=$(mktemp)
    trap "rm -f '$temp_script'" EXIT
    
    # 下載腳本
    log_info "正在下載腳本..."
    if ! timeout "$DOWNLOAD_TIMEOUT" curl -fsSL --max-filesize "$MAX_SCRIPT_SIZE" "$url" -o "$temp_script"; then
        log_error "下載失敗: $url"
        return 1
    fi
    
    # 檢查文件大小
    local file_size
    file_size=$(stat -f%z "$temp_script" 2>/dev/null || stat -c%s "$temp_script" 2>/dev/null)
    if [ "$file_size" -gt "$MAX_SCRIPT_SIZE" ]; then
        log_error "腳本文件過大: ${file_size} bytes"
        return 1
    fi
    
    # 驗證 checksum（如果提供）
    if [ -n "$expected_checksum" ] && [ "$expected_checksum" != "skip" ]; then
        local actual_checksum
        actual_checksum=$(calculate_checksum "$temp_script")
        if [ "$actual_checksum" != "$expected_checksum" ]; then
            log_error "Checksum 驗證失敗"
            log_error "預期: $expected_checksum"
            log_error "實際: $actual_checksum"
            return 1
        fi
        log_success "Checksum 驗證通過"
    fi
    
    # 檢查腳本安全性
    log_info "檢查腳本安全性..."
    if ! check_script_safety "$temp_script"; then
        log_error "腳本安全檢查失敗"
        
        # 詢問用戶是否繼續（僅在互動模式下）
        if [ -t 0 ]; then
            echo ""
            log_warning "腳本可能包含危險操作，是否仍要執行？"
            read -p "輸入 'yes' 繼續執行，其他任意鍵取消: " -r
            if [ "$REPLY" != "yes" ]; then
                log_info "用戶取消執行"
                return 1
            fi
        else
            log_error "非互動模式下不執行可疑腳本"
            return 1
        fi
    fi
    
    # 顯示腳本預覽
    if [ "$VERBOSE" = "true" ]; then
        log_info "腳本內容預覽（前20行）:"
        head -20 "$temp_script" | sed 's/^/  | /'
        echo ""
    fi
    
    # 執行腳本
    log_info "執行腳本: $description"
    if bash "$temp_script"; then
        log_success "$description 安裝成功"
        return 0
    else
        log_error "$description 安裝失敗"
        return 1
    fi
}

# 預定義的安全安裝函數
install_docker() {
    secure_download_and_execute \
        "https://get.docker.com" \
        "skip" \
        "Docker 安裝腳本"
}

install_uv() {
    SECURE_DOWNLOAD_ALLOW_PIPE=1 secure_download_and_execute \
        "https://astral.sh/uv/install.sh" \
        "skip" \
        "UV Python 包管理器"
}

install_superfile() {
    secure_download_and_execute \
        "https://superfile.netlify.app/install.sh" \
        "skip" \
        "Superfile 文件管理器"
}

install_lazydocker() {
    # lazydocker 使用更安全的 GitHub releases 安裝方式
    log_info "安裝 lazydocker"
    local version
    version=$(curl -s https://api.github.com/repos/jesseduffield/lazydocker/releases/latest | grep tag_name | cut -d '"' -f 4)
    
    if [ -n "$version" ]; then
        local url="https://github.com/jesseduffield/lazydocker/releases/download/$version/lazydocker_${version#v}_Linux_x86_64.tar.gz"
        local temp_file
        temp_file=$(mktemp)
        
        if curl -fsSL "$url" -o "$temp_file"; then
            tar -xzf "$temp_file" -C /tmp/
            sudo mv /tmp/lazydocker /usr/local/bin/
            chmod +x /usr/local/bin/lazydocker
            log_success "lazydocker 安裝成功"
        else
            log_error "lazydocker 下載失敗"
        fi
        
        rm -f "$temp_file"
    else
        log_error "無法獲取 lazydocker 版本信息"
    fi
}

install_oh_my_zsh() {
    SECURE_DOWNLOAD_ALLOW_PIPE=1 secure_download_and_execute \
        "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh" \
        "skip" \
        "Oh My Zsh shell 框架" \
        "--unattended"
}

# 命令行接口
case "${1:-help}" in
    "docker")
        install_docker
        ;;
    "uv")
        install_uv
        ;;
    "superfile")
        install_superfile
        ;;
    "lazydocker")
        install_lazydocker
        ;;
    "oh-my-zsh")
        install_oh_my_zsh
        ;;
    "test-download")
        if [ -z "$2" ]; then
            log_error "請提供要測試的 URL"
            exit 1
        fi
        secure_download_and_execute "$2" "skip" "測試腳本"
        ;;
    *)
        echo "用法: $0 <command>"
        echo ""
        echo "命令:"
        echo "  docker      安全安裝 Docker"
        echo "  uv          安全安裝 UV"
        echo "  superfile   安全安裝 Superfile"
        echo "  lazydocker  安全安裝 Lazydocker"
        echo "  oh-my-zsh   安全安裝 Oh My Zsh"
        echo "  test-download <url>  測試下載指定 URL"
        ;;
esac