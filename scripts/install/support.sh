#!/bin/bash
# shellcheck shell=bash
# 安裝程式共用的小工具：日誌檢視、quiet 模式判斷、錯誤處理與錯誤摘要。
# 由 install.sh 載入（source），不可單獨執行。

show_install_log_dialog() {
    local tail_lines="${1:-${TUI_LOG_LINES:-300}}"

    if [ -z "${LOG_FILE:-}" ] || [ ! -f "${LOG_FILE:-}" ]; then
        if [ "${USE_TUI:-false}" = "true" ] && command -v tui_msgbox >/dev/null 2>&1; then
            tui_msgbox "安裝日誌" "目前尚未建立日誌文件。" || true
        else
            printf "${YELLOW}目前尚未建立日誌文件${NC}\n"
        fi
        return 0
    fi

    if [ "${USE_TUI:-false}" = "true" ] && command -v tui_log_viewer >/dev/null 2>&1; then
        # 先把日誌尾端整理成可讀版本（去掉 \r 進度覆寫與 ANSI 色碼），原日誌不變
        local view_file=""
        view_file="$(mktemp "${TMPDIR:-/tmp}/linux-setting-view.XXXXXX" 2>/dev/null)" || view_file=""
        if [ -n "$view_file" ] \
           && tail -n "$tail_lines" "$LOG_FILE" 2>/dev/null \
              | sed -e 's/\r$//' -e 's/.*\r//' -e 's/\x1b\[[0-9;?]*[A-Za-z]//g' > "$view_file" 2>/dev/null; then
            tui_log_viewer "安裝日誌" "$view_file" all || true
        else
            tui_log_viewer "安裝日誌" "$LOG_FILE" "$tail_lines" || true
        fi
        if [ -n "$view_file" ]; then
            rm -f "$view_file"
        fi
    else
        printf "\n${CYAN}########## 最新安裝日誌 ##########${NC}\n"
        tail -n "$tail_lines" "$LOG_FILE" 2>/dev/null || true
        printf "${CYAN}########## 日誌結束 ##########${NC}\n"
    fi
}

installer_tui_quiet() {
    [ "${NON_INTERACTIVE:-false}" != "true" ] || return 1
    [ "${TUI_MODE:-quiet}" = "quiet" ] || return 1
    [ "${TUI_LOG_TO_TERMINAL:-auto}" != "true" ] || return 1
    [ "${USE_TUI:-auto}" != "false" ] || return 1
}

prepare_initial_tui_backend() {
    [ -t 0 ] || return 0
    [ "${INSTALL_MODE:-full}" != "minimal" ] || return 0
    [ "${NON_INTERACTIVE:-false}" != "true" ] || return 0
    [ "${USE_TUI:-auto}" != "false" ] || return 0

    if command -v _select_tui_backend >/dev/null 2>&1; then
        _select_tui_backend >/dev/null 2>&1 || true
    fi
}

run_logged_command() {
    if installer_tui_quiet && [ -n "${LOG_FILE:-}" ]; then
        "$@" >> "$LOG_FILE" 2>&1
    else
        "$@"
    fi
}

# common.sh 的顏色變數是字面 '\033[...' 字串（給 printf 格式用）；
# 當作 %s 參數輸出前需先轉成真正的跳脫字元
_ansi() {
    printf '%b' "${1:-}"
}

# 錯誤處理函數
handle_error() {
    local exit_code=$1
    local line_number="$2"
    local last_command="${3:-}"

    # 避免錯誤處理本身再觸發 ERR trap / set -e 而遞迴
    trap - ERR
    set +e

    # 安裝進度動畫若仍在跑，先停掉，避免與錯誤訊息交錯
    if declare -F _progress_stop_spinner >/dev/null 2>&1; then
        _progress_stop_spinner
    fi

    print_error_summary "$exit_code" "$line_number" "$last_command"

    # 詢問是否查看日誌
    if [ -t 0 ] && [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        if [ "${USE_TUI:-false}" = "true" ] && command -v tui_yesno >/dev/null 2>&1; then
            if tui_yesno "安裝失敗" "安裝流程已中止。\n\n要查看最新的安裝日誌嗎？" "yes"; then
                show_install_log_dialog 300
            fi
        else
            local choice=""
            printf "${CYAN:-}[l]${NC:-} 查看日誌  ${CYAN:-}[q]${NC:-} 退出: "
            read -r -n 1 choice || true
            printf "\n"
            case "$choice" in
                l|L) show_install_log_dialog 300 ;;
            esac
        fi
    fi

    exit "$exit_code"
}

# 依套件管理器給出「更新套件索引」的建議指令
package_index_update_hint() {
    case "${1:-${PKG_MANAGER:-}}" in
        apt) printf '%s' "sudo apt update" ;;
        dnf) printf '%s' "sudo dnf makecache" ;;
        yum) printf '%s' "sudo yum makecache" ;;
        pacman) printf '%s' "sudo pacman -Sy" ;;
        zypper) printf '%s' "sudo zypper refresh" ;;
        *) printf '%s' "" ;;
    esac
}

# 錯誤摘要（純輸出，不讀輸入；可在測試中直接呼叫）
print_error_summary() {
    local exit_code="$1"
    local line_number="$2"
    local last_command="${3:-}"
    local red yellow green nc
    red="$(_ansi "${RED:-}")"
    yellow="$(_ansi "${YELLOW:-}")"
    green="$(_ansi "${GREEN:-}")"
    nc="$(_ansi "${NC:-}")"

    printf "\n%s✗ 安裝失敗%s\n\n" "$red" "$nc"
    printf "  位置：install.sh 第 %s 行（結束碼 %s）\n" "$line_number" "$exit_code"
    if [ -n "$last_command" ]; then
        printf "  命令：%s\n" "${last_command:0:120}"
    fi
    if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        printf "  日誌：%s\n" "$LOG_FILE"
    fi

    printf "\n%s可能原因%s：網路連線、套件來源無法存取、磁碟空間不足或權限不足。\n" "$yellow" "$nc"
    printf "\n%s建議操作%s：\n" "$green" "$nc"
    local step=1
    if [ -n "${LOG_FILE:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        printf "  %d. 查看日誌：tail -n 50 %q\n" "$step" "$LOG_FILE"
        step=$((step + 1))
    fi
    printf "  %d. 檢查網路：ping -c 1 github.com\n" "$step"
    step=$((step + 1))
    local update_hint
    update_hint="$(package_index_update_hint "${PKG_MANAGER:-}")"
    if [ -n "$update_hint" ]; then
        printf "  %d. 更新套件索引：%s\n" "$step" "$update_hint"
        step=$((step + 1))
    fi
    printf "  %d. 檢查空間：df -h /\n" "$step"
    printf "  修正後重新執行安裝程式即可；已安裝的模組會自動略過套件階段。\n"
    printf "\n需要幫助？https://github.com/guan4tou2/my-linux-setting/issues\n\n"
}

