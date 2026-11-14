#!/usr/bin/env bash

# ==============================================================================
# Linux Environment Setup - Main Installation Script
# Version: 2.2.9
# ==============================================================================

# 幫助函數（必須在參數解析之前定義）
show_help() {
    cat << 'EOF'
Linux Setting Scripts - 自動安裝腳本 v2.2.9

用法: ./install.sh [選項]

選項:
  --minimal                       最小安裝模式
  --non-interactive               無人值守模式（不進入互動選單）
  --update                        更新已安裝的組件
  --dry-run                       預覽模式（不實際安裝）
  --force, --force-reinstall      強制重新安裝（不跳過已安裝的模組）
  -a, --advanced                  進階模式：每個模組進去再選具體要裝的套件
  --abort-on-failure              單一模組失敗就中斷（預設僅警告並繼續）
  --rollback                      把最近一次安裝前的備份（~/.zshrc、~/.p10k.zsh、
                                  ~/.config/nvim）還原到原位置；不需要 sudo，也不下載任何東西
  -y, --yes                       搭配 --rollback 時不詢問、直接還原
  -v, --verbose                   顯示詳細日誌
  -h, --help                      顯示此幫助訊息
  --config <file>                 指定配置文件路徑

環境變數:
  TUI_BACKEND=auto|gum|fzf|whiptail  指定互動選單後端（預設 auto）
  TUI_MODE=quiet|normal              控制安裝輸出詳細程度
  TUI_LOG_LINES=300                  TUI 查看安裝日誌時顯示的尾端行數

遠端安裝（bash -c "$(curl ...)"）會下載整包專案壓縮檔再執行，可用以下變數調整來源：
  LINUX_SETTING_REPO=擁有者/名稱     GitHub 儲存庫（預設 guan4tou2/my-linux-setting）
  LINUX_SETTING_REF=main             分支、tag 或 commit（預設 main；釘選版本請用 tag 或 commit）
  LINUX_SETTING_ARCHIVE_URL=<網址>   直接指定壓縮檔網址（優先於上兩者；必須是 https）
  LINUX_SETTING_ARCHIVE_SHA256=<雜湊> 下載後以 SHA-256 驗證壓縮檔（建議搭配固定的 tag 或 commit）
  （舊的 REPO_URL=https://raw.githubusercontent.com/<擁有者>/<名稱>/<ref> 仍相容）

範例:
  ./install.sh                    # 標準安裝（互動式選單）
  ./install.sh --minimal          # 最小安裝
  ./install.sh --non-interactive --minimal  # 無人值守最小安裝
  ./install.sh --dry-run          # 預覽將要安裝的內容
  ./install.sh --update           # 更新模式
  ./install.sh --rollback         # 還原最近一次安裝前的設定檔備份
  ./install.sh --verbose          # 詳細模式
  TUI_BACKEND=fzf ./install.sh     # 使用 fzf 互動選單
  TUI_BACKEND=gum ./install.sh     # 使用 gum 互動選單
  TUI_LOG_LINES=500 ./install.sh   # TUI 中顯示最近 500 行日誌

更多資訊請參閱 README.md
EOF
}

# 顯示歡迎信息（精簡標題；--help 與參數錯誤時不顯示）
show_welcome() {
    printf "\n  \033[1mLinux Setting Scripts  v2.2.9\033[0m\n"
    printf "  自動化開發環境配置工具\n\n"
}

# ==============================================================================
# --rollback：還原最近一次安裝前的設定檔備份
# 這段在 common.sh 載入之前執行（遠端執行時專案壓縮檔尚未下載），
# 因此不可使用 common.sh 的函式或顏色變數，也不會下載任何東西。
# ==============================================================================

# 備份目錄內的名稱 -> 原位置（只認 backup_config_files 會備份的三項）
rollback_dest_for() {
    case "$1" in
        .zshrc|.p10k.zsh) printf '%s\n' "$HOME/$1" ;;
        nvim) printf '%s\n' "$HOME/.config/nvim" ;;
        *) return 1 ;;
    esac
}

run_rollback() {
    local c_y=$'\033[0;33m' c_g=$'\033[0;32m' c_r=$'\033[0;31m' c_n=$'\033[0m'
    local backup_root="$HOME/.config/linux-setting-backup"
    local latest="" d

    if [ -d "$backup_root" ]; then
        # 目錄名稱為 YYYYmmdd_HHMMSS，字串排序即時間排序
        while IFS= read -r d; do
            latest="$d"
        done < <(find "$backup_root" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)
    fi

    local srcs=() dests=() src name dest
    if [ -n "$latest" ]; then
        for src in "$latest"/.[!.]* "$latest"/*; do
            if [ ! -e "$src" ] && [ ! -L "$src" ]; then
                continue
            fi
            name="$(basename "$src")"
            if dest="$(rollback_dest_for "$name")"; then
                srcs+=("$src")
                dests+=("$dest")
            fi
        done
    fi

    if [ "${#srcs[@]}" -eq 0 ]; then
        printf '%s沒有可還原的備份%s（%s）\n' "$c_y" "$c_n" "$backup_root" >&2
        printf '備份由 install.sh 在每次安裝開始時自動建立。\n' >&2
        return 1
    fi

    printf '\n將從備份 %s 還原以下設定檔：\n' "$latest"
    local i
    for i in "${!srcs[@]}"; do
        printf '  %s -> %s\n' "$(basename "${srcs[$i]}")" "${dests[$i]}"
    done
    printf '目前的檔案會先另存為同目錄下的 .before-rollback 副本。\n\n'

    if [ "$ASSUME_YES" != "true" ] && [ "$NON_INTERACTIVE" != "true" ]; then
        if [ ! -t 0 ]; then
            printf '%s非互動環境且未指定 -y / --non-interactive，終止還原%s\n' "$c_r" "$c_n" >&2
            return 1
        fi
        local answer=""
        read -r -p "確認還原？(y/N) " answer || true
        if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
            printf '已取消\n'
            return 0
        fi
    fi

    local failed=0 saved
    for i in "${!srcs[@]}"; do
        src="${srcs[$i]}"
        dest="${dests[$i]}"
        saved="$dest.before-rollback"
        mkdir -p "$(dirname "$dest")" || { failed=$((failed + 1)); continue; }
        if [ -e "$dest" ] || [ -L "$dest" ]; then
            rm -rf "$saved"
            if ! mv "$dest" "$saved"; then
                printf '%s無法保存目前的 %s，略過%s\n' "$c_r" "$dest" "$c_n" >&2
                failed=$((failed + 1))
                continue
            fi
        fi
        if cp -a "$src" "$dest"; then
            printf '%s已還原%s %s\n' "$c_g" "$c_n" "$dest"
        else
            printf '%s還原失敗%s %s\n' "$c_r" "$c_n" "$dest" >&2
            rm -rf "$dest"
            if [ -e "$saved" ] || [ -L "$saved" ]; then
                mv "$saved" "$dest" || true
            fi
            failed=$((failed + 1))
        fi
    done

    if [ "$failed" -gt 0 ]; then
        printf '%s有 %d 項還原失敗%s\n' "$c_r" "$failed" "$c_n" >&2
        return 1
    fi
    printf '%s還原完成%s\n' "$c_g" "$c_n"
    return 0
}

# ==============================================================================
# 遠端安裝（bootstrap）：下載整包專案壓縮檔、解壓，再以解出來的 install.sh 重新執行
# 這一段在 common.sh 載入之前執行，只能使用這裡自己定義的函式，不可使用 common.sh
# 的函式或顏色變數。bootstrap 之後一律是「本地流程」。
# ==============================================================================

# bootstrap 暫存目錄的名稱樣式（mktemp 產生）；只有符合樣式的目錄才會被清除
BOOTSTRAP_DIR_PREFIX="linux-setting-bootstrap"

bootstrap_status() {
    local level="$1"
    local message="$2"

    if [ "$level" != "ERROR" ] && [ "${TUI_MODE:-quiet}" = "quiet" ] && [ "${TUI_LOG_TO_TERMINAL:-auto}" != "true" ]; then
        return 0
    fi

    case "$level" in
        INFO) printf "\033[0;36mINFO: %s\033[0m\n" "$message" ;;
        SUCCESS) printf "\033[0;32mSUCCESS: %s\033[0m\n" "$message" ;;
        ERROR) printf "\033[0;31mERROR: %s\033[0m\n" "$message" >&2 ;;
        *) printf "%s: %s\n" "$level" "$message" ;;
    esac
}

# 下載網址檢查：必須是 https://；唯一例外是主機為 localhost、127.0.0.1 或 [::1] 的
# http://（本機測試伺服器）。含 userinfo（@）的 http 網址一律拒絕。
_download_url_allowed() {
    local url="$1" rest authority host
    case "$url" in
        https://*) return 0 ;;
        http://*)
            rest="${url#http://}"
            authority="${rest%%[/?#]*}"
            case "$authority" in
                *@*|*\\*|*[[:space:]]*) return 1 ;;
            esac
            case "$authority" in
                \[*) host="${authority%%]*}]" ;;
                *) host="${authority%%:*}" ;;
            esac
            case "$host" in
                localhost|127.0.0.1|"[::1]") return 0 ;;
            esac
            return 1
            ;;
    esac
    return 1
}

# repo 必須是「擁有者/名稱」，ref 可為分支、tag 或 commit（允許 /）；兩者都不可含 ..
_bootstrap_valid_repo() {
    local re='^[A-Za-z0-9_][A-Za-z0-9._-]*/[A-Za-z0-9_][A-Za-z0-9._-]*$'
    [[ "$1" =~ $re ]] && [[ "$1" != *..* ]]
}

_bootstrap_valid_ref() {
    local re='^[A-Za-z0-9_][A-Za-z0-9._/-]*$'
    [[ "$1" =~ $re ]] && [[ "$1" != *..* ]] && [[ "$1" != *//* ]] && [[ "$1" != */ ]]
}

# 決定壓縮檔網址，結果放在 BOOTSTRAP_ARCHIVE_URL。優先順序：
#   LINUX_SETTING_ARCHIVE_URL > LINUX_SETTING_REPO / LINUX_SETTING_REF > 舊的 REPO_URL > 預設值
bootstrap_resolve_archive_url() {
    local repo="${LINUX_SETTING_REPO:-}" ref="${LINUX_SETTING_REF:-}"
    BOOTSTRAP_ARCHIVE_URL=""

    if [ -n "${LINUX_SETTING_ARCHIVE_URL:-}" ]; then
        BOOTSTRAP_ARCHIVE_URL="$LINUX_SETTING_ARCHIVE_URL"
    else
        if [ -z "$repo" ] && [ -z "$ref" ] && [ -n "${REPO_URL:-}" ]; then
            # 向下相容：REPO_URL=https://raw.githubusercontent.com/<擁有者>/<名稱>/<ref>
            local legacy="${REPO_URL%/}"
            local legacy_re='^https://raw\.githubusercontent\.com/([A-Za-z0-9_][A-Za-z0-9._-]*)/([A-Za-z0-9_][A-Za-z0-9._-]*)/(.+)$'
            if [[ "$legacy" =~ $legacy_re ]]; then
                repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
                ref="${BASH_REMATCH[3]}"
                printf '提示：REPO_URL 已被 LINUX_SETTING_REPO 與 LINUX_SETTING_REF 取代，已解析為 %s@%s，建議改用新變數。\n' "$repo" "$ref" >&2
            else
                bootstrap_status "ERROR" "無法從 REPO_URL（$REPO_URL）推得壓縮檔網址。請改用 LINUX_SETTING_REPO 與 LINUX_SETTING_REF，或直接設定 LINUX_SETTING_ARCHIVE_URL。"
                return 1
            fi
        fi
        repo="${repo:-guan4tou2/my-linux-setting}"
        ref="${ref:-main}"
        if ! _bootstrap_valid_repo "$repo"; then
            bootstrap_status "ERROR" "LINUX_SETTING_REPO 格式不正確（需為 擁有者/名稱，只允許英數與 ._-）：$repo"
            return 1
        fi
        if ! _bootstrap_valid_ref "$ref"; then
            bootstrap_status "ERROR" "LINUX_SETTING_REF 格式不正確（只允許英數與 ._-/，且不可含 ..）：$ref"
            return 1
        fi
        BOOTSTRAP_ARCHIVE_URL="https://github.com/$repo/archive/$ref.tar.gz"
    fi

    if ! _download_url_allowed "$BOOTSTRAP_ARCHIVE_URL"; then
        bootstrap_status "ERROR" "壓縮檔網址必須是 https://（僅 localhost、127.0.0.1、[::1] 允許 http://），目前為：$BOOTSTRAP_ARCHIVE_URL"
        return 1
    fi
    return 0
}

# 只刪除「確實是目錄、不是符號連結、名稱符合 mktemp 樣式」的 bootstrap 暫存目錄
bootstrap_remove_dir() {
    local dir="${1:-}"
    local re="^${BOOTSTRAP_DIR_PREFIX//./\\.}\\.[A-Za-z0-9]{6}\$"
    [ -n "$dir" ] || return 0
    [[ "${dir##*/}" =~ $re ]] || return 0
    [ -d "$dir" ] && [ ! -L "$dir" ] || return 0
    rm -rf -- "$dir"
}

_bootstrap_signal() {
    bootstrap_remove_dir "${BOOTSTRAP_ACTIVE_DIR:-}"
    exit "$1"
}

_bootstrap_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        return 1
    fi
}

# 列出壓縮檔內容並拒絕不安全的項目：絕對路徑、含 .. 的路徑、指向外部的連結、裝置檔
bootstrap_check_archive_entries() {
    local archive="$1" entry line target
    local dotdot_re='(^|/)\.\.(/|$)'
    if ! tar -tzf "$archive" >/dev/null 2>&1; then
        bootstrap_status "ERROR" "無法讀取壓縮檔內容（檔案損毀或不是 tar.gz）"
        return 1
    fi
    while IFS= read -r entry; do
        if [[ "$entry" == /* ]] || [[ "$entry" =~ $dotdot_re ]]; then
            bootstrap_status "ERROR" "壓縮檔含有不安全的路徑，已中止：$entry"
            return 1
        fi
    done < <(tar -tzf "$archive" 2>/dev/null)
    while IFS= read -r line; do
        case "${line:0:1}" in
            -|d) ;;
            l|h)
                target="${line##* -> }"
                [ "$target" != "$line" ] || target="${line##* link to }"
                if [[ "$target" == /* ]] || [[ "$target" =~ $dotdot_re ]]; then
                    bootstrap_status "ERROR" "壓縮檔含有指向外部的連結，已中止：$line"
                    return 1
                fi
                ;;
            *)
                bootstrap_status "ERROR" "壓縮檔含有不允許的檔案類型，已中止：$line"
                return 1
                ;;
        esac
    done < <(tar -tvzf "$archive" 2>/dev/null)
    return 0
}

# 下載、驗證、解壓，並以解出來的 install.sh 重新執行（成功時不會返回）
# 失敗時印出原因、清除暫存目錄並回傳非 0。
run_bootstrap() {
    bootstrap_resolve_archive_url || return 1

    local tool
    for tool in curl tar mktemp; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            bootstrap_status "ERROR" "遠端安裝需要 $tool，請先安裝後再執行。"
            return 1
        fi
    done

    local url="$BOOTSTRAP_ARCHIVE_URL" max_bytes="${LINUX_SETTING_MAX_ARCHIVE_BYTES:-52428800}"
    local dir="" tmp_root="${TMPDIR:-/tmp}"
    dir="$(mktemp -d "${tmp_root%/}/${BOOTSTRAP_DIR_PREFIX}.XXXXXX")" || {
        bootstrap_status "ERROR" "無法建立暫存目錄"
        return 1
    }
    chmod 0700 "$dir" || true
    # 中斷時一併清掉暫存目錄（exec 成功後由子程序自己接手清理）
    BOOTSTRAP_ACTIVE_DIR="$dir"
    trap '_bootstrap_signal 130' INT
    trap '_bootstrap_signal 143' TERM
    trap '_bootstrap_signal 129' HUP

    local archive="$dir/archive.tar.gz" src="$dir/src"
    local curl_opts=(-fsS --connect-timeout 15 --max-time "${LINUX_SETTING_DOWNLOAD_TIMEOUT:-300}" --max-filesize "$max_bytes")
    case "$url" in
        https://*) curl_opts+=(-L --max-redirs 5 --proto '=https' --proto-redir '=https') ;;
        *) curl_opts+=(--proto '=http') ;;
    esac

    bootstrap_status "INFO" "下載專案壓縮檔：$url"
    if ! curl "${curl_opts[@]}" "$url" -o "$archive"; then
        bootstrap_status "ERROR" "下載壓縮檔失敗：$url"
        bootstrap_remove_dir "$dir"
        return 1
    fi
    local size=0
    size="$(wc -c < "$archive" | tr -d '[:space:]')" || size=0
    if [ "${size:-0}" -le 0 ] || [ "$size" -gt "$max_bytes" ]; then
        bootstrap_status "ERROR" "壓縮檔大小不合理（$size bytes，上限 $max_bytes）"
        bootstrap_remove_dir "$dir"
        return 1
    fi

    if [ -n "${LINUX_SETTING_ARCHIVE_SHA256:-}" ]; then
        local expected actual
        expected="$(printf '%s' "$LINUX_SETTING_ARCHIVE_SHA256" | tr '[:upper:]' '[:lower:]')"
        if ! [[ "$expected" =~ ^[0-9a-f]{64}$ ]]; then
            bootstrap_status "ERROR" "LINUX_SETTING_ARCHIVE_SHA256 必須是 64 個十六進位字元"
            bootstrap_remove_dir "$dir"
            return 1
        fi
        if ! actual="$(_bootstrap_sha256 "$archive")" || [ -z "$actual" ]; then
            bootstrap_status "ERROR" "找不到 sha256sum 或 shasum，無法驗證壓縮檔"
            bootstrap_remove_dir "$dir"
            return 1
        fi
        if [ "$actual" != "$expected" ]; then
            bootstrap_status "ERROR" "壓縮檔 SHA-256 不符，已中止（預期 $expected，實際 $actual）"
            bootstrap_remove_dir "$dir"
            return 1
        fi
        bootstrap_status "SUCCESS" "壓縮檔 SHA-256 驗證通過"
    fi

    if ! bootstrap_check_archive_entries "$archive"; then
        bootstrap_remove_dir "$dir"
        return 1
    fi

    if ! mkdir -p "$src" || ! tar -xzf "$archive" -C "$src" --strip-components=1 --no-same-owner 2>/dev/null; then
        bootstrap_status "ERROR" "解壓縮失敗"
        bootstrap_remove_dir "$dir"
        return 1
    fi
    rm -f "$archive"

    local required
    for required in install.sh scripts/core/common.sh scripts/core/module_manager.sh config/modules.conf; do
        if [ ! -f "$src/$required" ]; then
            bootstrap_status "ERROR" "壓縮檔內容不完整，缺少：$required"
            bootstrap_remove_dir "$dir"
            return 1
        fi
    done
    bootstrap_status "SUCCESS" "專案已解壓縮，重新執行安裝程式"

    # 用環境變數告知子程序：這是 bootstrap 啟動的，結束時要清掉這個目錄、也不可再次 bootstrap
    export LINUX_SETTING_BOOTSTRAP_DIR="$dir"
    shopt -s execfail
    # execfail 讓 exec 失敗時繼續往下清理，所以 exec 之後的程式碼是刻意保留的
    # shellcheck disable=SC2093
    exec "${BASH:-bash}" "$src/install.sh" ${INSTALL_ORIG_ARGS[@]+"${INSTALL_ORIG_ARGS[@]}"}
    bootstrap_status "ERROR" "無法重新執行解出來的 install.sh"
    bootstrap_remove_dir "$dir"
    return 1
}

# Set strict error handling
set -euo pipefail

# 統一的錯誤捕獲
trap 'handle_error $? $LINENO "$BASH_COMMAND"' ERR

# ==============================================================================
# Argument Parsing
# ==============================================================================

# 原始參數：bootstrap 後要原樣傳給解出來的 install.sh（解析迴圈會 shift 掉它們）
INSTALL_ORIG_ARGS=("$@")

INSTALL_MODE="${INSTALL_MODE:-full}"
UPDATE_MODE="${UPDATE_MODE:-false}"
VERBOSE="${VERBOSE:-false}"
DEBUG="${DEBUG:-false}"
DRY_RUN="${DRY_RUN:-false}"
SKIP_PYTHON_CHECK="${SKIP_PYTHON_CHECK:-false}"
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
FORCE_REINSTALL="${FORCE_REINSTALL:-false}"
ADVANCED_MODE="${ADVANCED_MODE:-false}"
ABORT_ON_FAILURE="${ABORT_ON_FAILURE:-false}"
ROLLBACK_MODE=false
ASSUME_YES=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --minimal)
            INSTALL_MODE="minimal"
            shift
            ;;
        --non-interactive)
            NON_INTERACTIVE=true
            USE_TUI=false
            shift
            ;;
        --update)
            UPDATE_MODE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force|--force-reinstall)
            FORCE_REINSTALL=true
            shift
            ;;
        --advanced|-a)
            ADVANCED_MODE=true
            shift
            ;;
        --abort-on-failure)
            ABORT_ON_FAILURE=true
            shift
            ;;
        --rollback)
            ROLLBACK_MODE=true
            shift
            ;;
        -y|--yes)
            ASSUME_YES=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            DEBUG=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        --config)
            if [ -n "${2:-}" ]; then
                export CONFIG_FILE="$2"
                shift 2
            else
                echo "Error: --config requires a file path"
                exit 1
            fi
            ;;
        *)
            echo "Unknown parameter: $1"
            show_help
            exit 1
            ;;
    esac
done

# 強烈建議不要用 sudo 直接跑整支安裝（會把設定/工具裝到 /root，且 brew 會失敗）
if [ "${EUID:-$(id -u)}" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "${ALLOW_ROOT:-false}" != "true" ]; then
    # 此時 common.sh 尚未載入，使用區塊內專用的跳脫碼變數（不可與 common.sh 的 readonly 名稱衝突）
    _sudo_y=$'\033[0;33m'
    _sudo_g=$'\033[0;32m'
    _sudo_c=$'\033[0;36m'
    _sudo_n=$'\033[0m'
    printf '\n%s偵測到你用 sudo 以 root 執行。%s\n' "$_sudo_y" "$_sudo_n"
    printf '%s- 這會把 ~/.zshrc、uv、nvim 等安裝到 /root%s\n' "$_sudo_y" "$_sudo_n"
    printf '%s- 且 Homebrew 套件多半會因 root 而失敗%s\n\n' "$_sudo_y" "$_sudo_n"
    printf '%s請改用一般使用者執行：%s\n' "$_sudo_g" "$_sudo_n"
    printf '%s\n\n' '  bash -c "$(curl -fsSL https://raw.githubusercontent.com/guan4tou2/my-linux-setting/main/install.sh)"'
    printf '%s若你真的要用 root 跑（例如容器），請加：%s ALLOW_ROOT=true\n\n' "$_sudo_c" "$_sudo_n"
    exit 1
fi

# --rollback：只還原本機備份，不需要 sudo、不做環境檢查、不下載任何東西
if [ "$ROLLBACK_MODE" = true ]; then
    trap - ERR
    rollback_rc=0
    run_rollback || rollback_rc=$?
    exit "$rollback_rc"
fi

# 參數解析與本機備份還原不依賴 bash 4；安裝流程需要關聯陣列。
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    printf 'ERROR: 需要 Bash 4 以上（目前為 %s）。本工具支援 Ubuntu 最新 LTS、Debian stable、Kali rolling。\n' "$BASH_VERSION" >&2
    exit 1
fi

# ==============================================================================
# 啟動：判斷是否「從完整專案執行」
# 條件：BASH_SOURCE[0] 是存在的檔案，且其所在目錄下有 scripts/core/common.sh。
# 不查找目前目錄（$PWD）——在別人準備好的目錄裡執行一鍵安裝不可載入該目錄的檔案。
# 否則進入 bootstrap：下載整包壓縮檔、解壓，再以解出來的 install.sh 重新執行。
# ==============================================================================

INSTALL_SH_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    INSTALL_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || INSTALL_SH_DIR=""
fi
if [ -n "$INSTALL_SH_DIR" ] && [ -f "$INSTALL_SH_DIR/scripts/core/common.sh" ]; then
    SCRIPT_DIR="$INSTALL_SH_DIR/scripts"
    # 由 bootstrap 啟動：記下暫存根目錄，結束時（正常、失敗、中斷）清除。
    # 環境變數只認名稱符合樣式、確實是目錄、且 install.sh 就在其 src/ 底下的路徑。
    BOOTSTRAP_CLEANUP_DIR=""
    if [ -n "${LINUX_SETTING_BOOTSTRAP_DIR:-}" ]; then
        _bs_root="$(cd "$LINUX_SETTING_BOOTSTRAP_DIR" 2>/dev/null && pwd -P)" || _bs_root=""
        if [ -n "$_bs_root" ] && [ "$INSTALL_SH_DIR" = "$_bs_root/src" ]; then
            BOOTSTRAP_CLEANUP_DIR="$_bs_root"
        fi
        unset LINUX_SETTING_BOOTSTRAP_DIR _bs_root
    fi
    if [ -n "$BOOTSTRAP_CLEANUP_DIR" ]; then
        trap 'bootstrap_remove_dir "$BOOTSTRAP_CLEANUP_DIR"' EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM
        trap 'exit 129' HUP
    fi
else
    if [ -n "${LINUX_SETTING_BOOTSTRAP_DIR:-}" ]; then
        # 已經 bootstrap 過卻仍找不到完整專案：不可再次下載，避免無限迴圈
        bootstrap_status "ERROR" "bootstrap 解出來的目錄不完整，已中止。"
        bootstrap_remove_dir "$LINUX_SETTING_BOOTSTRAP_DIR"
        exit 1
    fi
    trap - ERR
    run_bootstrap || exit 1
    exit 1
fi

show_welcome

# Export variables for child scripts
export INSTALL_MODE UPDATE_MODE VERBOSE DEBUG DRY_RUN SKIP_PYTHON_CHECK NON_INTERACTIVE FORCE_REINSTALL ADVANCED_MODE ABORT_ON_FAILURE

# ==============================================================================
# Configuration
# ==============================================================================

# Performance options
ENABLE_PARALLEL_INSTALL="${ENABLE_PARALLEL_INSTALL:-true}"
PARALLEL_JOBS="${PARALLEL_JOBS:-auto}"

# Auto-detect parallel jobs if set to auto
if [ "$PARALLEL_JOBS" = "auto" ]; then
    PARALLEL_JOBS=$(nproc 2>/dev/null || echo 4)
fi

# Export configuration
export ENABLE_PARALLEL_INSTALL PARALLEL_JOBS

# ==============================================================================
# 載入共用函式庫（此時一定是完整專案：本地執行，或 bootstrap 解壓後的副本）
# ==============================================================================

# shellcheck source=scripts/core/common.sh
source "$SCRIPT_DIR/core/common.sh"

# Initialize environment
init_common_env

# 模組管理器在啟動階段載入
load_module_manager() {
    if [ ! -f "$SCRIPT_DIR/core/module_manager.sh" ]; then
        log_error "找不到必要的模組管理器: $SCRIPT_DIR/core/module_manager.sh" || true
        exit 1
    fi
    # shellcheck source=/dev/null
    if ! source "$SCRIPT_DIR/core/module_manager.sh"; then
        log_error "無法載入 module_manager.sh" || true
        exit 1
    fi
    if ! init_module_manager; then
        log_error "模組管理器初始化失敗" || true
        exit 1
    fi
    if [ ${#MODULE_LIST[@]} -eq 0 ]; then
        log_error "模組管理器未載入任何模組" || true
        exit 1
    fi
}

load_module_manager

# ==============================================================================
# 安裝程式的其餘部分依職責拆在 scripts/install/ 下（只定義函式與初始狀態）
#   support    共用小工具與錯誤處理      preflight  環境檢查、備份、日誌
#   selection  模組選擇與安裝計畫        homebrew   Homebrew 詢問與安裝
#   menu       純文字選單                report     結果追蹤與安裝報告
#   progress   安裝進度顯示              runner     逐模組安裝流程
# ==============================================================================

# shellcheck source=scripts/install/support.sh
source "$SCRIPT_DIR/install/support.sh"
# shellcheck source=scripts/install/preflight.sh
source "$SCRIPT_DIR/install/preflight.sh"
# shellcheck source=scripts/install/selection.sh
source "$SCRIPT_DIR/install/selection.sh"
# shellcheck source=scripts/install/homebrew.sh
source "$SCRIPT_DIR/install/homebrew.sh"
# shellcheck source=scripts/install/menu.sh
source "$SCRIPT_DIR/install/menu.sh"
# shellcheck source=scripts/install/report.sh
source "$SCRIPT_DIR/install/report.sh"
# shellcheck source=scripts/install/progress.sh
source "$SCRIPT_DIR/install/progress.sh"
# shellcheck source=scripts/install/runner.sh
source "$SCRIPT_DIR/install/runner.sh"

# 導覽式流程：模組勾選（含進階列）→ Homebrew → 確認摘要 → 安裝 → 結果（可重試／重新選擇）
run_guided_tui_flow() {
    # 結果由 show_install_result_tui 統一顯示，安裝函式不再自己彈出報告訊息框
    GUIDED_RESULT_SCREEN=true
    GUIDED_ADVANCED_DEFAULT="${ADVANCED_MODE:-false}"
    local retry=false

    while :; do
        if [ "$retry" = "true" ]; then
            retry=false
            # 重試只針對上次沒成功的模組；進階模式的套件選擇已保留，不再逐模組詢問
            selected_modules="$(install_retry_modules)"
            ADVANCED_MODE=false
            if [ "${LINUX_SETTING_PKG_INDEX_UPDATED:-}" != "1" ]; then
                unset LINUX_SETTING_PKG_INDEX_CHECKED
            fi
            log_info "重試未成功的模組：$selected_modules"
        else
            if declare -F reset_module_overrides >/dev/null 2>&1; then
                reset_module_overrides
            fi
            selected_modules=""
            HOMEBREW_DECISION=""

            select_modules_tui || return 0
            offer_homebrew_if_needed
            # 確認畫面選「否」回到模組勾選（要離開請在勾選畫面取消）
            confirm_install_summary_tui || continue
        fi

        local install_rc=0
        if run_install_with_tui; then
            install_rc=0
        else
            install_rc=$?
        fi
        log_info "安裝流程結束（rc=$install_rc）"
        [ "${#INSTALL_RESULT_IDS[@]}" -gt 0 ] || continue

        local result_action=0
        show_install_result_tui || result_action=$?
        if [ "$result_action" -eq 2 ]; then
            continue
        fi
        if [ "$result_action" -eq 3 ]; then
            retry=true
            continue
        fi
        # 對話框關閉後，把報告留在終端機上方便事後查閱
        if [ "${#INSTALL_RESULT_IDS[@]}" -gt 0 ]; then
            if [ -t 1 ]; then
                printf '\033[H\033[2J'
            fi
            print_installation_report_plain
        fi
        # 使用者已看過報告；不再讓 set -e 觸發錯誤畫面，改以結束碼反映結果
        GUIDED_EXIT_CODE="$(install_results_exit_code)"
        return 0
    done
}

# 主要安裝函數
main() {
    # 檢查更新模式
    if [ "$UPDATE_MODE" = true ]; then
        log_info "更新模式：執行系統更新"
        if [ -f "$SCRIPT_DIR/maintenance/update_tools.sh" ]; then
            bash "$SCRIPT_DIR/maintenance/update_tools.sh"
            exit $?
        else
            log_error "找不到更新腳本"
            exit 1
        fi
    fi
    
    # 初始化
    prepare_initial_tui_backend
    setup_logging
    check_environment
    backup_config_files
    
    # 無人值守模式：自動選擇模組並直接執行，不進入互動選單
    if [ "$NON_INTERACTIVE" = "true" ]; then
        USE_TUI=false
        if [ "$INSTALL_MODE" = "minimal" ]; then
            selected_modules="$MINIMAL_MODULES"
        else
            selected_modules="${MODULE_LIST[*]}"
        fi

        local ni_rc=0
        install_selected_modules || ni_rc=$?
        if [ "$ni_rc" -eq 0 ]; then
            ni_rc="$(install_results_exit_code)"
        fi
        if [ "$ni_rc" -ne 0 ]; then
            # 報告已說明失敗原因，直接以非 0 結束，不再顯示錯誤畫面
            exit "$ni_rc"
        fi
        return 0
    fi

    if [ "$USE_TUI" = "true" ] && command -v tui_checklist >/dev/null 2>&1; then
        GUIDED_EXIT_CODE=0
        run_guided_tui_flow
        exit "${GUIDED_EXIT_CODE:-0}"
    fi

    # 命令行模式：使用原有的菜單邏輯
    while :; do
        show_menu
        read -r input
        case $input in
            [0-9]*)
                for num in $input; do
                    add_module "$num"
                done
                ;;
            i|I)
                install_selected_modules || log_warning "安裝已中止，可重新選擇模組後再試"
                ;;
            c|C)
                selected_modules=""
                printf "${CYAN}已清除所有選擇${NC}\n"
                ;;
            d|D)
                # 查看詳情：提供選擇單個模組或全部查看
                printf "\n${CYAN}查看模組詳情${NC}\n"
                printf "輸入模組編號查看單一模組，或按 Enter 查看全部: "
                read -r detail_num
                if [ -n "$detail_num" ] && [ "$detail_num" -ge 1 ] 2>/dev/null && [ "$detail_num" -le ${#MODULE_LIST[@]} ] 2>/dev/null; then
                    local module_id="${MODULE_LIST[$((detail_num - 1))]}"
                    show_module_detail_dialog "$module_id"
                else
                    show_module_details
                fi
                ;;
            a|A)
                # 切換進階模式
                if [ "${ADVANCED_MODE:-false}" = "true" ]; then
                    ADVANCED_MODE=false
                    printf "${CYAN}進階模式已關閉${NC}\n"
                else
                    ADVANCED_MODE=true
                    printf "${YELLOW}進階模式已開啟${NC}（按 [i] 開始安裝時，會逐模組讓你挑套件）\n"
                fi
                ;;
            q|Q|0)
                printf "${CYAN}退出安裝程序${NC}\n"
                exit 0
                ;;
            "")
                # 空輸入，繼續顯示選單
                ;;
            *)
                printf "${RED}無效的輸入，請重試${NC}\n"
                ;;
        esac
    done
}

# 執行主函數
main
