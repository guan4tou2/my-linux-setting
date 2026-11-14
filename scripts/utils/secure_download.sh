#!/usr/bin/env bash

# 下載並執行官方安裝程式的輔助工具
# 提供 https、網域白名單、大小上限與（有提供時）雜湊比對；不替上游內容背書

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

# 下載限制與網域白名單
readonly SECURE_DOWNLOAD_TIMEOUT=30
readonly SECURE_MAX_SCRIPT_SIZE=1048576  # 1MB
readonly SECURE_ALLOWED_DOMAINS=(
    "raw.githubusercontent.com"
    "get.docker.com"
    "astral.sh"
    "superfile.netlify.app"
)

# 驗證網址：只接受 https，且主機必須「完全等於」允許清單中的網域。
# 以純 bash 解析授權段（scheme 之後、第一個 / ? # 之前），含 userinfo（@）、
# 反斜線或空白的網址一律拒絕，避免 https://allowed.example@evil.example/ 之類的繞過；
# 埠號只接受預設的 443。
verify_domain() {
    local url="${1:-}"

    case "$url" in
        https://*) ;;
        *)
            log_error "只允許 https 網址: $url"
            return 1
            ;;
    esac

    local rest="${url#https://}"
    local authority="${rest%%[/?#]*}"
    case "$authority" in
        ""|*[@\\[:space:]]*)
            log_error "網址格式不被接受: $url"
            return 1
            ;;
    esac
    authority="${authority%:443}"
    case "$authority" in
        *:*)
            log_error "不接受自訂埠號: $url"
            return 1
            ;;
    esac

    local domain allowed_domain
    domain=$(printf '%s' "$authority" | tr '[:upper:]' '[:lower:]')
    for allowed_domain in "${SECURE_ALLOWED_DOMAINS[@]}"; do
        if [[ "$domain" == "$allowed_domain" ]]; then
            return 0
        fi
    done

    log_error "不被信任的域名: $domain"
    return 1
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

# 下載並執行官方安裝程式。
# 網域白名單只檢查最初的網址；上游安裝程式會轉址，所以允許轉址但限制只能轉到 https。
# 保護僅限於：只允許 https、網域白名單、大小上限、私有暫存檔，以及（有提供時）雜湊比對。
# checksum 為 skip 時不驗證內容，實際信任的是 TLS 與上游網站本身。
# 用法: secure_download_and_execute <url> <checksum|skip> <description> [額外參數...]
#       額外參數會原樣傳給下載回來的腳本，例如 "--unattended"。
secure_download_and_execute() {
    local url="$1"
    local expected_checksum="$2"
    local description="$3"
    shift 3 || true

    if [ -n "$expected_checksum" ] && [ "$expected_checksum" != "skip" ]; then
        log_info "下載並執行: $description（TLS、網域白名單與 SHA-256 驗證）"
    else
        log_info "下載並執行官方安裝程式: $description（僅以 TLS 與網域白名單保護，未驗證雜湊）"
    fi

    # 驗證網址（https 與網域白名單）
    if ! verify_domain "$url"; then
        return 1
    fi

    # 私有暫存檔（mktemp 預設權限 0600）；不設 trap，以免覆蓋呼叫端的 EXIT trap，
    # 改在這裡明確清理。
    local temp_script rc=0
    if ! temp_script=$(mktemp); then
        log_error "無法建立暫存檔"
        return 1
    fi
    _secure_download_run "$temp_script" "$url" "$expected_checksum" "$description" "$@" || rc=$?
    rm -f "$temp_script"
    return "$rc"
}

_secure_download_run() {
    local temp_script="$1" url="$2" expected_checksum="$3" description="$4"
    shift 4
    local script_args=("$@")

    # 下載腳本
    log_info "正在下載腳本..."
    if ! timeout "$SECURE_DOWNLOAD_TIMEOUT" curl -fsSL --proto '=https' --proto-redir '=https' --max-filesize "$SECURE_MAX_SCRIPT_SIZE" "$url" -o "$temp_script"; then
        log_error "下載失敗: $url"
        return 1
    fi

    # 檢查文件大小
    local file_size
    file_size=$(stat -f%z "$temp_script" 2>/dev/null || stat -c%s "$temp_script" 2>/dev/null)
    if [ "$file_size" -gt "$SECURE_MAX_SCRIPT_SIZE" ]; then
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

    # 顯示腳本預覽
    if [ "${VERBOSE:-false}" = "true" ]; then
        log_info "腳本內容預覽（前20行）:"
        head -20 "$temp_script" | sed 's/^/  | /'
        echo ""
    fi

    # 執行腳本（把額外參數傳給下載的腳本）
    log_info "執行腳本: $description${script_args[*]:+ (args: ${script_args[*]})}"
    # 使用 ${arr[@]+"${arr[@]}"} 慣用法避免 set -u 下空陣列報錯
    # 某些安裝腳本（例如 Docker）需要 root；用環境變數控制是否以 root 執行
    local run_rc=0
    if [ "${SECURE_DOWNLOAD_RUN_AS_ROOT:-0}" = "1" ] && [ "${EUID:-$(id -u)}" -ne 0 ]; then
        if command -v run_as_root >/dev/null 2>&1; then
            run_as_root bash "$temp_script" ${script_args[@]+"${script_args[@]}"} || run_rc=$?
        else
            sudo bash "$temp_script" ${script_args[@]+"${script_args[@]}"} || run_rc=$?
        fi
    else
        bash "$temp_script" ${script_args[@]+"${script_args[@]}"} || run_rc=$?
    fi

    if [ "$run_rc" -eq 0 ]; then
        log_success "$description 安裝成功"
        return 0
    else
        log_error "$description 安裝失敗"
        return 1
    fi
}

# 預定義的安裝函數（皆來自上游官方安裝程式，未驗證雜湊）
install_docker() {
    SECURE_DOWNLOAD_RUN_AS_ROOT=1 secure_download_and_execute \
        "https://get.docker.com" \
        "skip" \
        "Docker 安裝腳本"
}

install_uv() {
    secure_download_and_execute \
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

# lazydocker：從 GitHub releases 下載對應架構的壓縮檔，
# 以同一版本的 checksums.txt 驗證 SHA-256 後才安裝到 /usr/local/bin。
install_lazydocker() {
    log_info "安裝 lazydocker"

    local arch
    arch=$(linux_release_arch) || arch=""
    case "$arch" in
        x86_64) arch=x86_64 ;;
        aarch64) arch=arm64 ;;
        armv7l) arch=armv7 ;;
        armv6l) arch=armv6 ;;
        *)
            log_error "lazydocker 不支援架構: $arch"
            return 1
            ;;
    esac

    local version
    if ! version=$(github_latest_release_tag jesseduffield/lazydocker); then
        log_error "無法獲取 lazydocker 版本信息"
        return 1
    fi

    local asset="lazydocker_${version#v}_Linux_${arch}.tar.gz"
    local base="https://github.com/jesseduffield/lazydocker/releases/download/$version"
    local tmp_dir rc=0
    if ! tmp_dir=$(mktemp -d); then
        log_error "無法建立暫存目錄"
        return 1
    fi

    if ! curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 120 -o "$tmp_dir/$asset" "$base/$asset"; then
        log_error "lazydocker 下載失敗"
        rc=1
    elif ! curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 60 -o "$tmp_dir/checksums.txt" "$base/checksums.txt"; then
        log_error "lazydocker checksums.txt 下載失敗，不安裝未驗證的執行檔"
        rc=1
    elif ! verify_sha256_in_list "$tmp_dir/$asset" "$tmp_dir/checksums.txt" "$asset"; then
        log_error "lazydocker 雜湊驗證失敗，不安裝"
        rc=1
    elif ! tar -xzf "$tmp_dir/$asset" -C "$tmp_dir" lazydocker; then
        log_error "lazydocker 解壓縮失敗"
        rc=1
    else
        local preexisting=false
        if [ -e /usr/local/bin/lazydocker ] || [ -L /usr/local/bin/lazydocker ]; then
            preexisting=true
        fi
        if sudo install -m 0755 "$tmp_dir/lazydocker" /usr/local/bin/lazydocker; then
            log_success "lazydocker 安裝成功（雜湊驗證通過）"
            if [ "$preexisting" != "true" ]; then
                manifest_record path /usr/local/bin/lazydocker
            fi
        else
            log_error "lazydocker 安裝失敗"
            rc=1
        fi
    fi

    rm -rf "$tmp_dir" || log_warning "無法清除 lazydocker 暫存目錄"
    return "$rc"
}

install_oh_my_zsh() {
    secure_download_and_execute \
        "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh" \
        "skip" \
        "Oh My Zsh shell 框架" \
        "--unattended"
}

main() {
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
            if [ -z "${2:-}" ]; then
                log_error "請提供要測試的 URL"
                exit 1
            fi
            secure_download_and_execute "${2}" "skip" "測試腳本"
            ;;
        *)
            echo "用法: $0 <command>"
            echo ""
            echo "命令:"
            echo "  docker      下載並安裝 Docker"
            echo "  uv          下載並安裝 UV"
            echo "  superfile   下載並安裝 Superfile"
            echo "  lazydocker  下載並安裝 Lazydocker"
            echo "  oh-my-zsh   下載並安裝 Oh My Zsh"
            echo "  test-download <url>  測試下載指定 URL"
            ;;
    esac
}

# 僅在直接執行時處理 CLI；被 source 時只提供函數。
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
