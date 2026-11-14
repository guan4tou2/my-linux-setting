#!/bin/bash
# shellcheck shell=bash
# 安裝結果：結果追蹤、結束碼、安裝報告與導覽式流程的結果畫面。
# 由 install.sh 載入（source），不可單獨執行。

# ==============================================================================
# 安裝結果追蹤（兩條安裝路徑共用）
# 狀態：ok（成功）/ partial（部分套件失敗）/ failed（失敗）/ not_run（中止後未執行）
# ==============================================================================

INSTALL_RESULT_IDS=()
INSTALL_RESULT_STATUS=()
INSTALL_RESULT_DETAIL=()
INSTALL_ABORTED=false

reset_install_results() {
    INSTALL_RESULT_IDS=()
    INSTALL_RESULT_STATUS=()
    INSTALL_RESULT_DETAIL=()
    INSTALL_ABORTED=false
}

record_module_result() {
    INSTALL_RESULT_IDS+=("$1")
    INSTALL_RESULT_STATUS+=("$2")
    INSTALL_RESULT_DETAIL+=("${3:-}")
}

# 查詢某模組的結果狀態（找不到時輸出空字串）
module_result_status() {
    local module_id="$1"
    local i
    for ((i = 0; i < ${#INSTALL_RESULT_IDS[@]}; i++)); do
        if [ "${INSTALL_RESULT_IDS[$i]}" = "$module_id" ]; then
            printf '%s' "${INSTALL_RESULT_STATUS[$i]}"
            return 0
        fi
    done
    return 0
}

# 模組是否實際裝好（成功或僅部分套件失敗）
module_result_succeeded() {
    case "$(module_result_status "$1")" in
        ok|partial) return 0 ;;
    esac
    return 1
}

# 依安裝結果決定程序結束碼（輸出 0 或 1）：
# 已中止、或有任何模組失敗／未執行 → 1；全部成功或只有部分套件失敗 → 0。
# 導覽式 TUI、非互動（--non-interactive）與 stdin 非 tty 三條路徑共用，結束碼才會一致。
install_results_exit_code() {
    if [ "${INSTALL_ABORTED:-false}" = "true" ]; then
        printf '%s' 1
        return 0
    fi
    local status
    for status in ${INSTALL_RESULT_STATUS[@]+"${INSTALL_RESULT_STATUS[@]}"}; do
        case "$status" in
            failed|not_run)
                printf '%s' 1
                return 0
                ;;
        esac
    done
    printf '%s' 0
}

# 整體結果：success / partial / failed / none
install_results_overall() {
    local i ok=0 partial=0 failed=0 not_run=0
    for ((i = 0; i < ${#INSTALL_RESULT_STATUS[@]}; i++)); do
        case "${INSTALL_RESULT_STATUS[$i]}" in
            ok) ok=$((ok + 1)) ;;
            partial) partial=$((partial + 1)) ;;
            failed) failed=$((failed + 1)) ;;
            *) not_run=$((not_run + 1)) ;;
        esac
    done

    if [ $((ok + partial + failed + not_run)) -eq 0 ]; then
        printf '%s' "none"
    elif [ "$partial" -eq 0 ] && [ "$failed" -eq 0 ] && [ "$not_run" -eq 0 ]; then
        printf '%s' "success"
    elif [ "$ok" -eq 0 ] && [ "$partial" -eq 0 ]; then
        printf '%s' "failed"
    else
        printf '%s' "partial"
    fi
}

install_report_title() {
    local overall
    overall="$(install_results_overall)"
    if [ "${INSTALL_ABORTED:-false}" = "true" ] && [ "$overall" != "failed" ]; then
        printf '%s' "安裝已中止"
        return 0
    fi
    case "$overall" in
        success) printf '%s' "安裝完成" ;;
        partial) printf '%s' "安裝完成（部分失敗）" ;;
        failed) printf '%s' "安裝失敗" ;;
        *) printf '%s' "未安裝任何模組" ;;
    esac
}

# 由 MODULE_INSTALL_FAILURES 的一筆「名稱: apt:x brew:y」取出套件清單
module_failure_packages() {
    local entry="$1"
    if [[ "$entry" == *": "* ]]; then
        printf '%s' "${entry#*: }"
    else
        printf '%s' "$entry"
    fi
}

# 計算以空白分隔的項目數
count_words() {
    local -a _words=()
    read -r -a _words <<< "${1:-}" || true
    printf '%s' "${#_words[@]}"
}

# 產生安裝報告文字（純函式：只讀結果陣列與 $HOME 下的檔案，輸出含實際換行的純文字）
build_install_report_text() {
    local i ok=0 partial=0 failed=0 not_run=0
    local total=${#INSTALL_RESULT_IDS[@]}
    for ((i = 0; i < total; i++)); do
        case "${INSTALL_RESULT_STATUS[$i]}" in
            ok) ok=$((ok + 1)) ;;
            partial) partial=$((partial + 1)) ;;
            failed) failed=$((failed + 1)) ;;
            *) not_run=$((not_run + 1)) ;;
        esac
    done

    local overall
    overall="$(install_results_overall)"
    local nl=$'\n'
    local report=""

    case "$overall" in
        success) report+="全部 $total 個模組安裝成功。${nl}" ;;
        none) report+="這次沒有執行任何模組。${nl}" ;;
        *)
            report+="成功 $ok 個、部分失敗 $partial 個、失敗 $failed 個"
            if [ "$not_run" -gt 0 ]; then
                report+="、未執行 $not_run 個"
            fi
            report+="。${nl}"
            ;;
    esac

    if [ "$total" -gt 0 ]; then
        report+="${nl}模組：${nl}"
        for ((i = 0; i < total; i++)); do
            local name detail
            name="$(module_display_name "${INSTALL_RESULT_IDS[$i]}")"
            detail="${INSTALL_RESULT_DETAIL[$i]}"
            case "${INSTALL_RESULT_STATUS[$i]}" in
                ok)
                    report+="  ✓ $name${nl}"
                    ;;
                partial)
                    report+="  ⚠ $name — $(count_words "$detail") 個套件失敗：$detail${nl}"
                    ;;
                failed)
                    report+="  ✗ $name — 安裝失敗${detail:+（$detail）}${nl}"
                    ;;
                *)
                    report+="  - $name — 未執行（安裝已中止）${nl}"
                    ;;
            esac
        done
    fi

    # 設定檔與別名：只列出對應模組確實裝好、且檔案確實存在的項目
    local hints=""
    if module_result_succeeded terminal; then
        if [ -f "$HOME/.zshrc" ]; then
            hints+="  zsh 設定：~/.zshrc${nl}"
        fi
        if [ -f "$HOME/.p10k.zsh" ]; then
            hints+="  p10k 設定：~/.p10k.zsh${nl}"
        fi
    fi
    if module_result_succeeded dev; then
        if [ -d "$HOME/.config/nvim" ]; then
            hints+="  Neovim 設定：~/.config/nvim${nl}"
        fi
        if grep -qs "alias nv=" "$HOME/.zshrc"; then
            hints+="  別名：nv → nvim${nl}"
        fi
    fi
    if module_result_succeeded docker && grep -qs "alias lzd=" "$HOME/.zshrc"; then
        hints+="  別名：lzd → lazydocker${nl}"
    fi
    if [ -n "$hints" ]; then
        report+="${nl}設定檔與別名：${nl}${hints}"
    fi

    report+="${nl}"
    if [ -n "${BACKUP_DIR:-}" ]; then
        local shown_backup="$BACKUP_DIR"
        case "$shown_backup" in "$HOME"/*) shown_backup="~${shown_backup#"$HOME"}" ;; esac
        report+="備份：${shown_backup}${nl}"
    fi
    local shown_log="${LOG_FILE:-未設定}"
    case "$shown_log" in "$HOME"/*) shown_log="~${shown_log#"$HOME"}" ;; esac
    report+="日誌：${shown_log}${nl}"
    if [ -n "${UNINSTALLER_COPY:-}" ]; then
        local shown_uninstaller="$UNINSTALLER_COPY"
        case "$shown_uninstaller" in "$HOME"/*) shown_uninstaller="~${shown_uninstaller#"$HOME"}" ;; esac
        report+="卸載：bash ${shown_uninstaller}${nl}"
    fi

    if [ "$failed" -gt 0 ] || [ "$partial" -gt 0 ]; then
        report+="${nl}建議：查看日誌找出失敗原因，修正後重新執行；已安裝的套件會自動略過。${nl}"
        if [ -n "${BACKUP_DIR:-}" ] && [ -n "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
            report+="如需還原安裝前的設定檔，可執行 install.sh --rollback（一鍵安裝請在指令後加 -- --rollback）。${nl}"
        fi
    fi

    if module_result_succeeded terminal; then
        report+="${nl}下一步：執行 exec zsh -l 載入新的 shell 設定。${nl}"
    elif [ $((ok + partial)) -gt 0 ]; then
        report+="${nl}下一步：重新開啟終端機以套用環境變更。${nl}"
    fi

    printf '%s' "$report"
}

# 顯示安裝報告
show_installation_report() {
    # 導覽式流程由 show_install_result_tui 統一顯示結果
    if [ "${GUIDED_RESULT_SCREEN:-false}" = "true" ]; then
        return 0
    fi

    local title report
    title="$(install_report_title)"
    report="$(build_install_report_text)"

    if [ "${USE_TUI:-false}" = "true" ] && command -v tui_msgbox >/dev/null 2>&1; then
        tui_msgbox "$title" "$report" || true
    else
        print_installation_report_plain
    fi
}

# 純文字報告（CLI、無人值守，以及 TUI 結束後留在終端機上的紀錄）
print_installation_report_plain() {
    local title color
    color="$(_ansi "${GREEN:-}")"
    title="$(install_report_title)"
    case "$(install_results_overall)" in
        partial) color="$(_ansi "${YELLOW:-}")" ;;
        failed|none) color="$(_ansi "${RED:-}")" ;;
    esac
    if [ "${INSTALL_ABORTED:-false}" = "true" ]; then
        color="$(_ansi "${YELLOW:-}")"
    fi
    printf "\n%s========== %s ==========%s\n" "$color" "$title" "$(_ansi "${NC:-}")"
    printf '%s\n' "$(build_install_report_text)"
}

# 安裝結果統計，輸出「成功 部分失敗 失敗 未執行」
install_result_counts() {
    local i ok=0 partial=0 failed=0 not_run=0
    for ((i = 0; i < ${#INSTALL_RESULT_STATUS[@]}; i++)); do
        case "${INSTALL_RESULT_STATUS[$i]}" in
            ok) ok=$((ok + 1)) ;;
            partial) partial=$((partial + 1)) ;;
            failed) failed=$((failed + 1)) ;;
            *) not_run=$((not_run + 1)) ;;
        esac
    done
    printf '%s %s %s %s' "$ok" "$partial" "$failed" "$not_run"
}

# 一行總結
install_result_summary_line() {
    local ok partial failed not_run
    read -r ok partial failed not_run <<< "$(install_result_counts)"
    local total=$((ok + partial + failed + not_run))
    local message
    if [ "${DRY_RUN:-false}" = "true" ]; then
        message="預覽模式（--dry-run）：沒有實際安裝任何套件。"
    elif [ "$total" -eq 0 ]; then
        message="沒有執行任何模組。"
    elif [ "$partial" -eq 0 ] && [ "$failed" -eq 0 ] && [ "$not_run" -eq 0 ]; then
        message="全部 $total 個模組安裝完成。"
    else
        message="成功 $ok 個、部分失敗 $partial 個、失敗 $failed 個"
        if [ "$not_run" -gt 0 ]; then
            message+="、未執行 $not_run 個"
        fi
        message+="。"
    fi
    if [ "${INSTALL_ABORTED:-false}" = "true" ]; then
        message="${message%。}（已中止）。"
    fi
    printf '%s' "$message"
}

# 結果選單提示文字：只有一行總結與日誌路徑（完整報告放不進選單、先以訊息框顯示時使用）
install_result_menu_text() {
    local shown_log="${LOG_FILE:-未設定}"
    case "$shown_log" in "$HOME"/*) shown_log="~${shown_log#"$HOME"}" ;; esac
    printf '%s\n\n日誌：%s' "$(install_result_summary_line)" "$shown_log"
}

# 精簡報告（合併畫面用）：一行總結、逐模組狀態行、日誌路徑；不含備份路徑與建議文字
build_install_report_compact_text() {
    local nl=$'\n'
    local text
    text="$(install_result_summary_line)${nl}" || true
    local total=${#INSTALL_RESULT_IDS[@]} i name detail
    if [ "$total" -gt 0 ]; then
        text+="${nl}"
        for ((i = 0; i < total; i++)); do
            name="$(module_display_name "${INSTALL_RESULT_IDS[$i]}")"
            detail="${INSTALL_RESULT_DETAIL[$i]:-}"
            case "${INSTALL_RESULT_STATUS[$i]}" in
                ok) text+="  ✓ $name${nl}" ;;
                partial) text+="  ⚠ $name — $(count_words "$detail") 個套件失敗${nl}" ;;
                failed) text+="  ✗ $name — 安裝失敗${nl}" ;;
                *) text+="  - $name — 未執行${nl}" ;;
            esac
        done
    fi
    local shown_log="${LOG_FILE:-未設定}"
    case "$shown_log" in "$HOME"/*) shown_log="~${shown_log#"$HOME"}" ;; esac
    text+="${nl}日誌：${shown_log}"
    printf '%s' "$text"
}

# 需要重試的模組（失敗、部分失敗、未執行），依結果記錄順序，以空白分隔
install_retry_modules() {
    local i out=""
    for ((i = 0; i < ${#INSTALL_RESULT_IDS[@]}; i++)); do
        case "${INSTALL_RESULT_STATUS[$i]}" in
            failed|partial|not_run) out+="${out:+ }${INSTALL_RESULT_IDS[$i]}" ;;
        esac
    done
    printf '%s' "$out"
}

# 精簡報告加上 n 個選項，在目前終端機高度下能否放進同一個選單
install_result_fits_one_screen() {
    local n_options="${1:-4}"
    if ! declare -F _tui_menu_fits_text >/dev/null 2>&1; then
        return 1
    fi
    _tui_menu_fits_text "$(build_install_report_compact_text)" "$n_options" 24
}

# 結果畫面：精簡報告與選項合併在同一個選單；放不下時先用可捲動的訊息框顯示完整報告，
# 再顯示只有一行總結的選單。
# 回傳：0 退出、2 重新選擇、3 重試失敗的模組
show_install_result_tui() {
    local title
    title="$(install_report_title)"

    local retry_label="重試失敗的模組"
    local -a options=()
    if [ -n "$(install_retry_modules)" ]; then
        options+=("$retry_label")
    fi
    options+=("查看安裝日誌" "重新選擇" "退出")

    local message
    if install_result_fits_one_screen "${#options[@]}"; then
        message="$(build_install_report_compact_text)"
    else
        tui_msgbox "$title" "$(build_install_report_text)" || true
        message="$(install_result_menu_text)"
    fi

    local action
    while :; do
        action=$(tui_menu "$title" "$message" "${options[@]}" || true)
        case "$action" in
            "$retry_label")
                return 3
                ;;
            "查看安裝日誌")
                show_install_log_dialog
                ;;
            "重新選擇")
                return 2
                ;;
            "退出"|"")
                return 0
                ;;
        esac
    done
}
