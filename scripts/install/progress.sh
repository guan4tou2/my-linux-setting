#!/bin/bash
# shellcheck shell=bash
# 安裝進度顯示：每個模組一行的轉圈動畫與定案狀態。
# 由 install.sh 載入（source），不可單獨執行。

# ==============================================================================
# 安裝進度顯示（TUI quiet 模式）
# - 每個模組一行：轉圈動畫 + 已耗時 + 日誌最新訊息；完成後改寫為定案狀態
# - 動畫只寫終端（不寫日誌），非 tty 或 sudo 可能要密碼時改用靜態行
# ==============================================================================

PROGRESS_ACTIVE=false
PROGRESS_TTY_OPEN=false
PROGRESS_SPINNER_PID=""
PROGRESS_HEADER_TOTAL=0
PROGRESS_LINES=()

_progress_fmt_elapsed() {
    local secs="${1:-0}"
    [[ "$secs" =~ ^[0-9]+$ ]] || secs=0
    printf '%02d:%02d' $((secs / 60)) $((secs % 60))
}

# 清理一行日誌：去掉 ANSI 色碼、\r 覆寫、時間戳前綴與控制字元，結果放在 PROGRESS_CLEANED
_progress_clean_log_line() {
    local s="${1:-}"
    s="${s//$'\t'/ }"

    # apt/curl 進度列以 \r 覆寫：取最後一段非空內容
    if [[ "$s" == *$'\r'* ]]; then
        local last="${s##*$'\r'}"
        if [ -z "${last// /}" ]; then
            s="${s%$'\r'*}"
            last="${s##*$'\r'}"
        fi
        s="$last"
    fi

    local ansi_re=$'\e''\[[0-9;?]*[A-Za-z]'
    while [[ "$s" =~ $ansi_re ]]; do
        s="${s/"${BASH_REMATCH[0]}"/}"
    done
    s="${s//$'\e'/}"

    local ts_re='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+([+-][0-9:]+|Z)? \[[A-Z]+\] \[[0-9]+\] '
    if [[ "$s" =~ $ts_re ]]; then
        s="${s:${#BASH_REMATCH[0]}}"
    fi
    case "$s" in
        "INFO: "*) s="${s#INFO: }" ;;
        "SUCCESS: "*) s="${s#SUCCESS: }" ;;
        "WARNING: "*) s="${s#WARNING: }" ;;
        "ERROR: "*) s="${s#ERROR: }" ;;
        "DEBUG: "*) s="${s#DEBUG: }" ;;
    esac

    s="${s//[[:cntrl:]]/}"
    # 去頭尾空白
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    PROGRESS_CLEANED="$s"
}

# 測試／除錯用：輸出清理後的日誌行
progress_clean_log_line() {
    _progress_clean_log_line "${1:-}"
    printf '%s' "$PROGRESS_CLEANED"
}

# 依顯示寬度截斷文字（保守估計：非 ASCII 一律視為雙寬），結果放在 PROGRESS_FIT / PROGRESS_FIT_WIDTH
_progress_fit_text() {
    local text="${1:-}"
    local max="${2:-0}"
    [[ "$max" =~ ^[0-9]+$ ]] || max=0
    # 避免超長行拖慢逐字計算
    text="${text:0:400}"

    local len=${#text}
    local i ch code cw
    local width=0 cut="" cut_width=0 overflow=false
    local budget=$((max - 2))  # 截斷時預留「…」的寬度（保守算 2）
    for ((i = 0; i < len; i++)); do
        ch="${text:i:1}"
        code=200
        printf -v code '%d' "'$ch" 2>/dev/null || code=200
        # 非 UTF-8 locale 下多位元組字元會逐 byte 處理，且可能得到負值：一律視為寬字元
        if [ "$code" -ge 0 ] 2>/dev/null && [ "$code" -lt 32 ] 2>/dev/null; then
            continue
        fi
        if [ "$code" -ge 32 ] 2>/dev/null && [ "$code" -lt 127 ] 2>/dev/null; then
            cw=1
        else
            cw=2
        fi
        if [ $((width + cw)) -le "$budget" ]; then
            cut+="$ch"
            cut_width=$((width + cw))
        fi
        width=$((width + cw))
        if [ "$width" -gt "$max" ]; then
            overflow=true
            break
        fi
    done

    if [ "$overflow" = "true" ]; then
        if [ "$budget" -gt 0 ]; then
            PROGRESS_FIT="${cut}…"
            PROGRESS_FIT_WIDTH=$((cut_width + 2))
        else
            PROGRESS_FIT=""
            PROGRESS_FIT_WIDTH=0
        fi
    else
        PROGRESS_FIT="${text//[[:cntrl:]]/}"
        PROGRESS_FIT_WIDTH="$width"
    fi
}

# 測試／除錯用：輸出截斷結果
progress_fit_text() {
    _progress_fit_text "${1:-}" "${2:-0}"
    printf '%s' "$PROGRESS_FIT"
}

# 估算顯示寬度（與 _progress_fit_text 同一套保守規則）
progress_text_width() {
    _progress_fit_text "${1:-}" 100000
    printf '%s' "$PROGRESS_FIT_WIDTH"
}

_progress_term_cols() {
    local size="" cols=""
    size="$(stty size < /dev/tty 2>/dev/null)" || size=""
    cols="${size##* }"
    if ! [[ "$cols" =~ ^[0-9]+$ ]] || [ "$cols" -lt 20 ]; then
        cols="$(tput cols 2>/dev/null)" || cols=""
    fi
    if ! [[ "$cols" =~ ^[0-9]+$ ]] || [ "$cols" -lt 20 ]; then
        cols=80
    fi
    printf '%s' "$cols"
}

# 日誌最新一則有內容的訊息（已清理）
# shellcheck disable=SC2120 # 參數為可選，預設讀 LOG_FILE；測試會傳入檔案
progress_last_log_message() {
    local file="${1:-${LOG_FILE:-}}"
    [ -n "$file" ] && [ -f "$file" ] || return 0
    local line result=""
    while IFS= read -r line || [ -n "$line" ]; do
        _progress_clean_log_line "$line"
        if [ -n "$PROGRESS_CLEANED" ]; then
            result="$PROGRESS_CLEANED"
        fi
    done < <(tail -n 5 "$file" 2>/dev/null || true)
    printf '%s' "$result"
}

# 組出一行進度文字（不含色碼），結果放在 PROGRESS_FIT；寬度保證 <= cols-1
_progress_compose_line() {
    local frame="$1" tag="$2" label="$3" elapsed="$4" msg="$5" cols="$6"
    local max=$((cols - 1))
    local head
    head="${tag:+$tag }$label  $(_progress_fmt_elapsed "$elapsed")" || true
    # 前綴「  X 」佔 4 欄
    _progress_fit_text "$head" $((max - 4))
    local head_fit="$PROGRESS_FIT"
    local remain=$((max - 4 - PROGRESS_FIT_WIDTH))
    local line="$head_fit"
    # 分隔符「 │ 」的直線可能被當成雙寬字元，保守算 4 欄
    if [ -n "$msg" ] && [ "$remain" -gt 8 ]; then
        _progress_fit_text "$msg" $((remain - 4))
        if [ -n "$PROGRESS_FIT" ]; then
            line="$line │ $PROGRESS_FIT"
        fi
    fi
    PROGRESS_FIT="  $frame $line"
}

_progress_spinner_loop() {
    local tag="$1" label="$2" start="$3" parent_pid="$4"
    trap - ERR
    set +e
    trap 'exit 0' TERM
    trap '' INT

    local frames
    case "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" in
        *UTF-8*|*utf8*|*UTF8*|*utf-8*) frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏") ;;
        *) frames=("|" "/" "-" "\\") ;;
    esac
    local cyan nc
    cyan="$(_ansi "${CYAN:-}")"
    nc="$(_ansi "${NC:-}")"
    local tick=0 msg="" cols=80 frame line_body
    while :; do
        kill -0 "$parent_pid" 2>/dev/null || exit 0
        if [ $((tick % 5)) -eq 0 ]; then
            msg="$(progress_last_log_message)"
            cols="$(_progress_term_cols)"
        fi
        # 每分鐘延長一次 sudo 憑證，避免長時間安裝途中跳出密碼提示而被動畫行覆蓋
        if [ $((tick % 300)) -eq 299 ] && [ "${EUID:-$(id -u)}" -ne 0 ]; then
            sudo -n -v >/dev/null 2>&1 || true
        fi
        frame="${frames[$((tick % ${#frames[@]}))]}"
        _progress_compose_line "$frame" "$tag" "$label" $((SECONDS - start)) "$msg" "$cols"
        line_body="${PROGRESS_FIT:4}"
        printf '\r\033[K  %s%s%s %s' "$cyan" "$frame" "$nc" "$line_body"
        tick=$((tick + 1))
        sleep 0.2
    done
}

# 動畫只在 stdout 是 tty，且不會被 sudo 密碼提示打斷時啟用
progress_can_animate() {
    [ "${PROGRESS_TTY_OPEN:-false}" = "true" ] || return 1
    [ -t 8 ] || return 1
    [ "${PROGRESS_ANIMATION:-auto}" != "false" ] || return 1
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        return 0
    fi
    sudo -n true >/dev/null 2>&1
}

_progress_stop_spinner() {
    local pid="${PROGRESS_SPINNER_PID:-}"
    [ -n "$pid" ] || return 0
    PROGRESS_SPINNER_PID=""
    kill "$pid" 2>/dev/null || true
    # 動畫行程不是本 shell 的子行程（避免被裸 wait 卡住），以輪詢確認已結束
    local tries=0
    while _progress_pid_alive "$pid" && [ "$tries" -lt 40 ]; do
        sleep 0.05
        tries=$((tries + 1))
    done
    if _progress_pid_alive "$pid"; then
        kill -9 "$pid" 2>/dev/null || true
    fi
    if _progress_tty_is_terminal; then
        _progress_out '\r\033[K'
    fi
    return 0
}

# 行程是否仍在執行（殭屍行程視為已結束：容器內 PID 1 不一定會回收孤兒）
_progress_pid_alive() {
    local pid="$1"
    kill -0 "$pid" 2>/dev/null || return 1
    if [ -r "/proc/$pid/stat" ]; then
        local stat=""
        read -r stat < "/proc/$pid/stat" 2>/dev/null || return 0
        stat="${stat##*) }"
        [ "${stat%% *}" != "Z" ] || return 1
    fi
    return 0
}

# 進度輸出一律寫到進度開始時保存的終端機 fd 8，
# 即使目前 stdout 已被導向日誌（例如在 run_logged_command 內收到 Ctrl-C）
_progress_out() {
    local fmt="$1"
    shift
    if [ "${PROGRESS_TTY_OPEN:-false}" = "true" ]; then
        # shellcheck disable=SC2059
        printf "$fmt" "$@" >&8
    else
        # shellcheck disable=SC2059
        printf "$fmt" "$@"
    fi
}

_progress_tty_is_terminal() {
    if [ "${PROGRESS_TTY_OPEN:-false}" = "true" ]; then
        [ -t 8 ]
    else
        [ -t 1 ]
    fi
}

_progress_interrupted() {
    _progress_stop_spinner
    trap - INT TERM
    _progress_out '\n  %s已中斷安裝。%s詳細日誌：%s\n\n' "$(_ansi "${YELLOW:-}")" "$(_ansi "${NC:-}")" "${LOG_FILE:-未設定}"
    exit 130
}

_progress_draw_header() {
    if [ -t 1 ]; then
        printf '\033[H\033[2J'
    fi
    printf '\n  %s正在安裝 %s 個模組%s\n' "$(_ansi "${CYAN:-}")" "$PROGRESS_HEADER_TOTAL" "$(_ansi "${NC:-}")"
    local shown_log="${LOG_FILE:-未設定}"
    case "$shown_log" in "$HOME"/*) shown_log="~${shown_log#"$HOME"}" ;; esac
    printf '  詳細輸出寫入日誌：%s\n' "$shown_log"
    printf '  按 Ctrl-C 可中斷安裝\n\n'
}

progress_begin() {
    PROGRESS_HEADER_TOTAL="${1:-0}"
    PROGRESS_LINES=()
    PROGRESS_ACTIVE=true
    exec 8>&1
    PROGRESS_TTY_OPEN=true
    trap '_progress_interrupted' INT TERM
    _progress_draw_header
}

# 對話框（例如模組失敗詢問）關閉後重畫進度畫面
progress_redraw() {
    [ "${PROGRESS_ACTIVE:-false}" = "true" ] || return 0
    _progress_draw_header
    local i
    for ((i = 0; i < ${#PROGRESS_LINES[@]}; i++)); do
        printf '%s\n' "${PROGRESS_LINES[$i]}"
    done
}

progress_end() {
    [ "${PROGRESS_ACTIVE:-false}" = "true" ] || return 0
    _progress_stop_spinner
    trap - INT TERM
    PROGRESS_ACTIVE=false
    printf '\n'
    if [ "${PROGRESS_TTY_OPEN:-false}" = "true" ]; then
        exec 8>&-
        PROGRESS_TTY_OPEN=false
    fi
}

# 執行一個步驟並顯示進度；回傳該步驟的結束碼
progress_run() {
    local tag="$1" label="$2"
    shift 2
    local rc=0

    if progress_can_animate; then
        # 透過額外一層 subshell 讓動畫行程脫離本 shell 的子行程清單，
        # 避免安裝函式中的裸 `wait` 等待它而卡住
        PROGRESS_SPINNER_PID="$(
            _progress_spinner_loop "$tag" "$label" "$SECONDS" "$$" </dev/null >&8 2>/dev/null &
            printf '%s' "$!"
        )"
    else
        printf '  %s·%s %s%s 安裝中…（詳細輸出見日誌）\n' "$(_ansi "${CYAN:-}")" "$(_ansi "${NC:-}")" "${tag:+$tag }" "$label"
    fi

    "$@" || rc=$?
    _progress_stop_spinner
    return "$rc"
}

# 寫出某步驟的定案狀態行
progress_finish_line() {
    local tag="$1" label="$2" status="$3" text="${4:-}" elapsed="${5:-0}"
    local icon color
    case "$status" in
        ok) icon="✓"; color="$(_ansi "${GREEN:-}")"; text="${text:-完成}" ;;
        partial) icon="!"; color="$(_ansi "${YELLOW:-}")"; text="${text:-部分套件失敗}" ;;
        failed) icon="✗"; color="$(_ansi "${RED:-}")"; text="${text:-失敗}" ;;
        *) icon="-"; color=""; text="${text:-略過}" ;;
    esac
    local cols=80
    if [ -t 1 ]; then
        cols="$(_progress_term_cols)"
    fi
    _progress_fit_text "${tag:+$tag }$label  $text  $(_progress_fmt_elapsed "$elapsed")" $((cols - 5))
    local line
    line="  ${color}${icon}$(_ansi "${NC:-}") ${PROGRESS_FIT}"
    PROGRESS_LINES+=("$line")
    printf '%s\n' "$line"
}
