#!/bin/bash
# shellcheck shell=bash
# TUI：後端選擇（whiptail／fzf／gum）、對話框尺寸計算與各種對話框。
# 由 scripts/core/common.sh 載入（source），不可單獨執行。

# ==============================================================================
# TUI (Text User Interface) 函數
# ==============================================================================

# 全局變數：控制是否使用 TUI
USE_TUI="${USE_TUI:-auto}"  # auto/true/false
TUI_BACKEND="${TUI_BACKEND:-auto}"  # auto/gum/fzf/whiptail

_set_tui_backend() {
    export USE_TUI="true"
    export TUI_BACKEND="$1"
}

_select_tui_backend() {
    case "${TUI_BACKEND:-auto}" in
        gum)
            command -v gum >/dev/null 2>&1 && _set_tui_backend "gum" && return 0
            return 1
            ;;
        fzf)
            command -v fzf >/dev/null 2>&1 && _set_tui_backend "fzf" && return 0
            return 1
            ;;
        whiptail)
            command -v whiptail >/dev/null 2>&1 && _set_tui_backend "whiptail" && return 0
            return 1
            ;;
        auto|"")
            if command -v gum >/dev/null 2>&1; then
                _set_tui_backend "gum"
                return 0
            fi
            if command -v fzf >/dev/null 2>&1; then
                _set_tui_backend "fzf"
                return 0
            fi
            if command -v whiptail >/dev/null 2>&1; then
                TUI_BACKEND="whiptail"
                _set_tui_backend "whiptail"
                return 0
            fi
            return 1
            ;;
        *)
            log_warning "未知 TUI_BACKEND=${TUI_BACKEND}，改用自動偵測"
            TUI_BACKEND="auto"
            _select_tui_backend
            ;;
    esac
}

_tui_backend_supports_state_checklist() {
    [ "${TUI_BACKEND:-whiptail}" = "whiptail" ]
}

_tui_emit_tags_from_tsv() {
    local line
    local out=""
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        out="$out ${line%%	*}"
    done
    echo "${out# }"
}

_log_tui_backend_hint() {
    [ "${TUI_BACKEND_HINT_SHOWN:-false}" = "true" ] && return 0
    export TUI_BACKEND_HINT_SHOWN="true"

    if ! command -v fzf >/dev/null 2>&1 && ! command -v gum >/dev/null 2>&1; then
        log_info "提示：安裝 fzf 或 gum 可使用更順手的互動選單；可用 TUI_BACKEND=fzf ./install.sh 或 TUI_BACKEND=gum ./install.sh 指定"
    fi
}

# 僅判斷實際尺寸，不套用對話框尺寸的預設值。
_tui_terminal_too_small() {
    local rows="${1:-}" cols="${2:-}"
    case "$rows" in ''|*[!0-9]*) return 1 ;; esac
    case "$cols" in ''|*[!0-9]*) return 1 ;; esac
    [ "$rows" -lt 15 ] || [ "$cols" -lt 50 ]
}

# 檢測並確保 TUI backend 可用
ensure_tui_available() {
    # 如果明確禁用 TUI，直接返回失敗
    if [ "$USE_TUI" = "false" ]; then
        return 1
    fi

    local actual_size rows cols
    if actual_size=$(stty size 2>/dev/null </dev/tty); then
        read -r rows cols <<< "$actual_size"
        if _tui_terminal_too_small "$rows" "$cols"; then
            log_info "終端機太小（實際尺寸：${rows} 列 × ${cols} 欄），改用命令行模式"
            export USE_TUI=false
            return 1
        fi
    fi

    local requested_backend="${TUI_BACKEND:-auto}"
    if _select_tui_backend; then
        log_debug "啟用 TUI backend: $TUI_BACKEND"
        if [ "$requested_backend" = "auto" ] && [ "$TUI_BACKEND" = "whiptail" ]; then
            _log_tui_backend_hint
        fi
        return 0
    fi

    # 嘗試安裝 whiptail（通常在 newt 包中）作為保守 fallback
    log_info "檢測到 whiptail 未安裝，嘗試安裝..."
    if [ "${TUI_BACKEND:-auto}" != "gum" ] && [ "${TUI_BACKEND:-auto}" != "fzf" ] && [ "$DISTRO_FAMILY" = "debian" ]; then
        if install_package "whiptail" 2>/dev/null || install_package "newt" 2>/dev/null; then
            if command -v whiptail >/dev/null 2>&1; then
                log_success "whiptail 安裝成功，啟用 TUI 模式"
                TUI_BACKEND="whiptail"
                _set_tui_backend "whiptail"
                return 0
            fi
        fi
    fi

    # 如果是 auto 模式且安裝失敗，降級到命令行
    if [ "$USE_TUI" = "auto" ]; then
        log_info "TUI 不可用，使用命令行模式"
        _log_tui_backend_hint
        export USE_TUI="false"
        return 1
    fi

    # 明確要求 TUI 但不可用
    log_warning "TUI 模式不可用，降級到命令行模式"
    _log_tui_backend_hint
    export USE_TUI="false"
    return 1
}

# ==============================================================================
# TUI 對話框尺寸計算
# ==============================================================================

# 展開提示文字中的跳脫序列（呼叫端以 \n 表示換行；whiptail 會自行解讀，
# fzf / gum 不會，因此統一先展開再交給各 backend）
_tui_expand_text() {
    printf '%b' "${1:-}"
}

# 估算單行文字的顯示寬度（欄數）。中文等多位元組字元為雙寬，
# 以「非 ASCII 字元一律視為 3 bytes、寬度 2」保守估計（寧可略寬、不可被截斷）。
_tui_display_width() {
    local s="${1:-}"
    local chars=${#s}
    local bytes
    bytes=$(LC_ALL=C; printf '%s' "${#s}")
    if [ "$bytes" -le "$chars" ] 2>/dev/null; then
        echo "$chars"
    else
        echo $((chars + (bytes - chars) / 2))
    fi
}

# 取得多個字串中最大的顯示寬度
_tui_max_display_width() {
    local max=0 w item
    for item in "$@"; do
        w=$(_tui_display_width "$item")
        [ "$w" -gt "$max" ] && max=$w || true
    done
    echo "$max"
}

# 取得終端機實際大小，輸出「列數 欄數」。
# 優先序：TUI_TERM_ROWS/TUI_TERM_COLS（測試／覆寫用）> stty > tput > LINES/COLUMNS > 24x80
_tui_term_size() {
    local rows="${TUI_TERM_ROWS:-}"
    local cols="${TUI_TERM_COLS:-}"
    local sz=""

    if [ -z "$rows" ] || [ -z "$cols" ]; then
        sz=$(stty size 2>/dev/null </dev/tty) || sz=""
        if [ -n "$sz" ]; then
            [ -n "$rows" ] || rows="${sz% *}"
            [ -n "$cols" ] || cols="${sz#* }"
        fi
    fi
    if [ -z "$rows" ] || [ -z "$cols" ]; then
        [ -n "$rows" ] || rows=$(tput lines 2>/dev/null </dev/tty || true)
        [ -n "$cols" ] || cols=$(tput cols 2>/dev/null </dev/tty || true)
    fi
    [ -n "$rows" ] || rows="${LINES:-}"
    [ -n "$cols" ] || cols="${COLUMNS:-}"

    case "$rows" in ''|*[!0-9]*) rows=24 ;; esac
    case "$cols" in ''|*[!0-9]*) cols=80 ;; esac
    [ "$rows" -ge 10 ] || rows=24
    [ "$cols" -ge 30 ] || cols=80
    echo "$rows $cols"
}

# 計算對話框尺寸，輸出「height width list_height scroll」
# 用法：_tui_dialog_size <yesno|msgbox|menu|checklist> <提示文字> [項目數] [項目內容寬度] [標題寬度]
#   - 依訊息行數、長行折行後的行數、以及終端機實際列數/欄數上限計算
#   - 內容超過終端機高度時 scroll=1（yesno/msgbox 應加 --scrolltext）
#   - menu/checklist 至少保留 3 個清單列（項目少於 3 個則全部保留），提示文字過長時才截短
_tui_dialog_size() {
    local kind="${1:-yesno}"
    local text
    text=$(_tui_expand_text "${2:-}")
    local item_count="${3:-0}"
    local content_w="${4:-0}"
    local title_w="${5:-0}"

    local rows cols
    read -r rows cols <<< "$(_tui_term_size)"

    local min_w
    case "$kind" in
        yesno) min_w=60 ;;
        menu) min_w=70 ;;
        msgbox) min_w=76 ;;
        checklist) min_w=78 ;;
        *) min_w=60 ;;
    esac

    local max_w=$((cols - 4))
    [ "$max_w" -gt 120 ] && max_w=120 || true
    [ "$max_w" -lt 30 ] && max_w=30 || true
    local max_h=$((rows - 2))

    # 最長一行的顯示寬度
    local longest=0 w line
    while IFS= read -r line || [ -n "$line" ]; do
        w=$(_tui_display_width "$line")
        [ "$w" -gt "$longest" ] && longest=$w || true
    done <<< "$text"

    local width=$longest
    [ "$content_w" -gt "$width" ] && width=$content_w || true
    width=$((width + 8))
    [ $((title_w + 8)) -gt "$width" ] && width=$((title_w + 8)) || true
    [ "$width" -lt "$min_w" ] && width=$min_w || true
    [ "$width" -gt "$max_w" ] && width=$max_w || true

    # 折行後的實際行數（whiptail 文字區約為 width - 6）
    local text_w=$((width - 6))
    [ "$text_w" -lt 10 ] && text_w=10 || true
    local text_rows=0
    while IFS= read -r line || [ -n "$line" ]; do
        w=$(_tui_display_width "$line")
        if [ "$w" -le "$text_w" ]; then
            text_rows=$((text_rows + 1))
        else
            text_rows=$((text_rows + (w + text_w - 1) / text_w))
        fi
    done <<< "$text"
    [ "$text_rows" -lt 1 ] && text_rows=1 || true

    local height list_height=0 scroll=0
    case "$kind" in
        menu|checklist)
            local min_list=$item_count
            [ "$min_list" -gt 3 ] && min_list=3 || true
            # 提示文字過長時截短，確保清單至少保留 min_list 列
            local text_cap=$((max_h - 7 - min_list))
            [ "$text_cap" -lt 1 ] && text_cap=1 || true
            [ "$text_rows" -gt "$text_cap" ] && text_rows=$text_cap || true
            list_height=$((max_h - text_rows - 7))
            [ "$list_height" -gt "$item_count" ] && list_height=$item_count || true
            [ "$list_height" -lt "$min_list" ] && list_height=$min_list || true
            height=$((text_rows + list_height + 7))
            ;;
        *)
            height=$((text_rows + 7))
            [ "$height" -lt 9 ] && height=9 || true
            if [ "$height" -gt "$max_h" ]; then
                height=$max_h
                scroll=1
            fi
            ;;
    esac

    echo "$height $width $list_height $scroll"
}

# 提示文字加上全部 item_count 個選項，能否完整放進同一個選單（不必截短提示文字或捲動清單）。
# 用法：_tui_menu_fits_text <提示文字> <選項數> [項目內容寬度] [標題寬度]
# 版面與 _tui_dialog_size 的 menu 計算一致：文字列數 + 選項數 + 7（邊框、按鈕與空白）<= 終端機列數 - 2
_tui_menu_fits_text() {
    local text
    text=$(_tui_expand_text "${1:-}")
    local item_count="${2:-0}"
    local content_w="${3:-0}"
    local title_w="${4:-0}"

    local rows cols
    read -r rows cols <<< "$(_tui_term_size)"

    local max_w=$((cols - 4))
    [ "$max_w" -gt 120 ] && max_w=120 || true
    [ "$max_w" -lt 30 ] && max_w=30 || true

    local longest=0 w line
    while IFS= read -r line || [ -n "$line" ]; do
        w=$(_tui_display_width "$line")
        [ "$w" -gt "$longest" ] && longest=$w || true
    done <<< "$text"

    local width=$longest
    [ "$content_w" -gt "$width" ] && width=$content_w || true
    width=$((width + 8))
    [ $((title_w + 8)) -gt "$width" ] && width=$((title_w + 8)) || true
    [ "$width" -lt 70 ] && width=70 || true
    [ "$width" -gt "$max_w" ] && width=$max_w || true

    local text_w=$((width - 6))
    [ "$text_w" -lt 10 ] && text_w=10 || true
    local text_rows=0
    while IFS= read -r line || [ -n "$line" ]; do
        w=$(_tui_display_width "$line")
        if [ "$w" -le "$text_w" ]; then
            text_rows=$((text_rows + 1))
        else
            text_rows=$((text_rows + (w + text_w - 1) / text_w))
        fi
    done <<< "$text"

    [ $((text_rows + item_count + 7)) -le $((rows - 2)) ]
}

# fzf 用的高度（行數）：依提示文字行數估算，不超過終端機高度
_tui_fzf_height() {
    local text
    text=$(_tui_expand_text "${1:-}")
    local extra="${2:-6}"
    local rows cols
    read -r rows cols <<< "$(_tui_term_size)"
    local n
    n=$(printf '%s\n' "$text" | wc -l)
    n=$((n + extra))
    [ "$n" -gt $((rows - 1)) ] && n=$((rows - 1)) || true
    echo "$n"
}

# TUI 多選菜單（返回選中的 tag，以空白分隔）
# 參數：title prompt tag1 item1 tag2 item2 ...
# tag 必須為單一「模組 id」等無空白字元；描述可含空白（顯示在第二欄），否則 whiptail 回傳含空白的 tag 會被 shell 拆字而無法還原。
tui_checklist() {
    local title="$1"
    local prompt="$2"
    shift 2
    local items=("$@")

    # 檢查 TUI 是否可用
    if [ "$USE_TUI" != "true" ]; then
        return 1
    fi

    local n=${#items[@]}
    if [ $((n % 2)) -ne 0 ]; then
        log_error "tui_checklist: 參數須為偶數（tag 與描述須成對），目前 $n 個"
        return 1
    fi

    if [ "${TUI_BACKEND:-whiptail}" = "gum" ]; then
        local gum_items=()
        local gi=0
        while [ "$gi" -lt "$n" ]; do
            gum_items+=("${items[$gi]}	${items[$((gi + 1))]}")
            gi=$((gi + 2))
        done
        local gum_result
        printf '%s\n%b\n' "$title" "$prompt" >&2
        gum_result=$(printf '%s\n' "${gum_items[@]}" | gum choose --no-limit) || return 1
        _tui_emit_tags_from_tsv <<< "$gum_result"
        return 0
    fi

    if [ "${TUI_BACKEND:-whiptail}" = "fzf" ]; then
        local fzf_input=""
        local fi=0
        while [ "$fi" -lt "$n" ]; do
            fzf_input="${fzf_input}${items[$fi]}	${items[$((fi + 1))]}"$'\n'
            fi=$((fi + 2))
        done
        local fzf_result
        local fzf_header
        fzf_header="$(_tui_expand_text "$prompt")"$'\n'"Space 勾選/取消；Tab 多選；Enter 確認；Esc 取消"
        fzf_result=$(printf '%s' "$fzf_input" | fzf --multi --layout=reverse \
            --delimiter=$'\t' --with-nth=2.. \
            --bind=space:toggle --marker="✓ " \
            --height=80% --border --prompt="$title> " --header="$fzf_header") || return 1
        _tui_emit_tags_from_tsv <<< "$fzf_result"
        return 0
    fi

    # 構建 whiptail checklist 參數：每列 tag / item / status
    local checklist_args=()
    local default_state="ON"  # 預設全部選中
    local i=0
    while [ "$i" -lt "$n" ]; do
        checklist_args+=("${items[$i]}" "${items[$((i + 1))]}" "$default_state")
        i=$((i + 2))
    done

    local item_count=$((n / 2))
    # 計算窗口大小：依提示文字行數、長行折行與終端機實際大小
    local ci cw=0 w
    for ((ci = 0; ci < n; ci += 2)); do
        w=$(( $(_tui_display_width "${items[$ci]}") + $(_tui_display_width "${items[$((ci + 1))]}") + 8 ))
        [ "$w" -gt "$cw" ] && cw=$w || true
    done
    local height width list_height _scroll
    read -r height width list_height _scroll <<< "$(_tui_dialog_size checklist "$prompt" "$item_count" "$cw" "$(_tui_display_width "$title")")"
    local text
    text=$(_tui_expand_text "$prompt")

    # 顯示 checklist 並捕獲結果
    local result
    result=$(whiptail --title "$title" --checklist "$text" $height $width $list_height "${checklist_args[@]}" 3>&1 1>&2 2>&3)
    local exit_code=$?

    # 返回選中的項目（去除引號）
    if [ $exit_code -eq 0 ]; then
        echo "$result" | tr -d '"'
        return 0
    else
        return 1
    fi
}

# TUI 多選 checklist（每個項目可指定預設 ON / OFF / 文字描述）
# 用法：
#   tui_checklist_with_state "標題" "提示文字" \
#       tag1 "描述1" ON \
#       tag2 "描述2" OFF \
#       ...
# 回傳 stdout：使用者選中的 tag（用空白分隔），return 0
# 使用者取消 / 按 ESC：return 1
tui_checklist_with_state() {
    local title="$1"
    local prompt="$2"
    shift 2

    if [ "$USE_TUI" != "true" ]; then
        return 1
    fi

    # 收集 tag/description/state 為 whiptail 所需的位置參數
    local checklist_args=()
    local item_count=0
    while [ $# -ge 3 ]; do
        checklist_args+=("$1" "$2" "$3")
        item_count=$((item_count + 1))
        shift 3
    done

    if [ "$item_count" -eq 0 ]; then
        return 1
    fi

    if ! _tui_backend_supports_state_checklist; then
        return 1
    fi

    local ci cw=0 w
    local -a _cl=("${checklist_args[@]}")
    for ((ci = 0; ci < ${#_cl[@]}; ci += 3)); do
        w=$(( $(_tui_display_width "${_cl[$ci]}") + $(_tui_display_width "${_cl[$((ci + 1))]}") + 8 ))
        [ "$w" -gt "$cw" ] && cw=$w || true
    done
    local height width list_height _scroll
    read -r height width list_height _scroll <<< "$(_tui_dialog_size checklist "$prompt" "$item_count" "$cw" "$(_tui_display_width "$title")")"
    local text
    text=$(_tui_expand_text "$prompt")

    local result
    result=$(whiptail --title "$title" --checklist "$text" \
        $height $width $list_height "${checklist_args[@]}" 3>&1 1>&2 2>&3)
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo "$result" | tr -d '"'
        return 0
    fi
    return 1
}

# TUI 單選菜單（返回選中的項目）
tui_menu() {
    local title="$1"
    local prompt="$2"
    shift 2
    local items=("$@")

    # 檢查 TUI 是否可用
    if [ "$USE_TUI" != "true" ]; then
        return 1
    fi

    # 構建 whiptail menu 參數
    local menu_args=()
    local index=1

    for item in "${items[@]}"; do
        menu_args+=("$index" "$item")
        index=$((index + 1))
    done

    if [ "${TUI_BACKEND:-whiptail}" = "gum" ]; then
        local gum_result
        printf '%b\n' "$prompt" >&2
        gum_result=$(gum choose "${items[@]}") || return 1
        [ -n "$gum_result" ] && echo "$gum_result" && return 0
        return 1
    fi

    if [ "${TUI_BACKEND:-whiptail}" = "fzf" ]; then
        local fzf_result fzf_header
        fzf_header="$(_tui_expand_text "$prompt")"
        fzf_result=$(printf '%s\n' "${items[@]}" | fzf --height="$(_tui_fzf_height "$prompt" $((${#items[@]} + 5)))" --border --layout=reverse \
            --prompt="$title> " --header="$fzf_header") || return 1
        [ -n "$fzf_result" ] && echo "$fzf_result" && return 0
        return 1
    fi

    # 計算窗口大小：提示文字行數（含長行折行）+ 項目數，受終端機實際大小限制
    local item_w
    item_w=$(( $(_tui_max_display_width "${items[@]}") + 10 ))
    local height width list_height _scroll
    read -r height width list_height _scroll <<< "$(_tui_dialog_size menu "$prompt" "${#items[@]}" "$item_w" "$(_tui_display_width "$title")")"
    local text
    text=$(_tui_expand_text "$prompt")

    # 顯示 menu 並捕獲結果
    local result
    result=$(whiptail --title "$title" --menu "$text" $height $width $list_height "${menu_args[@]}" 3>&1 1>&2 2>&3)
    local exit_code=$?

    # 返回選中項目的文本（而不是索引）
    if [ $exit_code -eq 0 ] && [ -n "$result" ]; then
        echo "${items[$((result - 1))]}"
        return 0
    else
        return 1
    fi
}

# TUI 是/否對話框
tui_yesno() {
    local title="$1"
    local prompt="$2"
    local default="${3:-no}"  # yes/no

    # 檢查 TUI 是否可用
    if [ "$USE_TUI" != "true" ]; then
        return 1
    fi

    # 設置預設按鈕
    local defaultno=""
    [ "$default" = "no" ] && defaultno="--defaultno" || true

    local text
    text=$(_tui_expand_text "$prompt")

    if [ "${TUI_BACKEND:-whiptail}" = "gum" ]; then
        if [ "$default" = "yes" ]; then
            gum confirm "$text" --default=true
        else
            gum confirm "$text" --default=false
        fi
        return $?
    fi

    if [ "${TUI_BACKEND:-whiptail}" = "fzf" ]; then
        local fzf_result fzf_h
        fzf_h="$(_tui_fzf_height "$prompt" 6)"
        if [ "$default" = "yes" ]; then
            fzf_result=$(printf "Yes\nNo\n" | fzf --height="$fzf_h" --border --layout=reverse --prompt="$title> " --header="$text") || return 1
        else
            fzf_result=$(printf "No\nYes\n" | fzf --height="$fzf_h" --border --layout=reverse --prompt="$title> " --header="$text") || return 1
        fi
        [ "$fzf_result" = "Yes" ]
        return $?
    fi

    # 計算窗口大小：依內容行數、長行折行與終端機大小；超出時啟用捲動
    local height width list_height scroll
    read -r height width list_height scroll <<< "$(_tui_dialog_size yesno "$prompt" 0 0 "$(_tui_display_width "$title")")"
    local scroll_opt=()
    if [ "$scroll" = "1" ]; then
        # 可捲動時焦點在文字區，直接按 Enter 不會觸發按鈕；在標題提示操作方式
        scroll_opt=(--scrolltext)
        title="$title（↑↓ 捲動，Tab 切到按鈕）"
    fi

    # 顯示 yesno 對話框
    if whiptail --title "$title" $defaultno ${scroll_opt[@]+"${scroll_opt[@]}"} --yesno "$text" $height $width 3>&1 1>&2 2>&3; then
        return 0  # Yes
    else
        return 1  # No
    fi
}

# TUI 信息框
tui_msgbox() {
    local title="$1"
    local message="$2"

    # 檢查 TUI 是否可用
    if [ "$USE_TUI" != "true" ]; then
        return 1
    fi

    if [ "${TUI_BACKEND:-whiptail}" = "gum" ]; then
        printf '%b\n' "$message" | gum pager
        return $?
    fi

    if [ "${TUI_BACKEND:-whiptail}" = "fzf" ]; then
        if [ -t 0 ]; then
            printf '%b\n' "$message" | fzf --height=80% --border --layout=reverse --prompt="$title> " --header="Enter 返回"
        else
            printf '%b\n' "$message"
        fi
        return 0
    fi

    # 依內容行數、長行折行與終端機大小調整；超出時啟用捲動
    local height width list_height scroll
    read -r height width list_height scroll <<< "$(_tui_dialog_size msgbox "$message" 0 0 "$(_tui_display_width "$title")")"
    local scroll_opt=()
    if [ "$scroll" = "1" ]; then
        # 可捲動時焦點在文字區，直接按 Enter 不會觸發按鈕；在標題提示操作方式
        scroll_opt=(--scrolltext)
        title="$title（↑↓ 捲動，Tab 切到按鈕）"
    fi
    local text
    text=$(_tui_expand_text "$message")

    whiptail --title "$title" ${scroll_opt[@]+"${scroll_opt[@]}"} --msgbox "$text" $height $width 3>&1 1>&2 2>&3
}

# TUI 日誌檢視器（顯示最後 N 行，預設 300 行）
tui_log_viewer() {
    local title="$1"
    local log_file="$2"
    local tail_lines="${3:-300}"

    if [ "$USE_TUI" != "true" ]; then
        return 1
    fi

    if [ -z "$log_file" ] || [ ! -f "$log_file" ]; then
        tui_msgbox "$title" "找不到日誌文件：${log_file:-未設定}" 2>/dev/null || true
        return 1
    fi

    local view_file="$log_file"
    local tmp_file=""
    if [ "$tail_lines" != "all" ] && [ "$tail_lines" -gt 0 ] 2>/dev/null; then
        tmp_file="$(mktemp "${TMPDIR:-/tmp}/linux-setting-log.XXXXXX")" || return 1
        if tail -n "$tail_lines" "$log_file" > "$tmp_file" 2>/dev/null; then
            view_file="$tmp_file"
        else
            rm -f "$tmp_file"
            tmp_file=""
        fi
    fi

    local rc=0
    if [ "${TUI_BACKEND:-whiptail}" = "gum" ]; then
        gum pager < "$view_file" || rc=$?
    elif [ "${TUI_BACKEND:-whiptail}" = "fzf" ]; then
        if [ -t 0 ]; then
            fzf --height=80% --border --no-sort \
                --layout=reverse \
                --prompt="$title> " \
                --header="輸入可搜尋；Enter 選取一行；Esc 返回" \
                < "$view_file" >/dev/null || rc=$?
        else
            cat "$view_file"
        fi
    else
        # 依終端機實際大小決定檢視器尺寸（上限 40x140），小視窗不會超出畫面
        local viewer_rows viewer_cols
        read -r viewer_rows viewer_cols <<< "$(_tui_term_size)"
        viewer_rows=$((viewer_rows - 2))
        viewer_cols=$((viewer_cols - 4))
        [ "$viewer_rows" -le 40 ] || viewer_rows=40
        [ "$viewer_cols" -le 140 ] || viewer_cols=140
        whiptail --title "$title" --textbox "$view_file" "$viewer_rows" "$viewer_cols" 3>&1 1>&2 2>&3 || rc=$?
    fi

    [ -n "$tmp_file" ] && rm -f "$tmp_file"
    return $rc
}

# TUI 進度條（需要配合管道使用）
tui_gauge() {
    local title="$1"
    local prompt="$2"
    local initial_percent="${3:-0}"

    # 檢查 TUI 是否可用
    if [ "$USE_TUI" != "true" ]; then
        return 1
    fi

    # whiptail gauge 從標準輸入讀取百分比
    # 使用方式: echo "50" | tui_gauge "Title" "Message"
    whiptail --title "$title" --gauge "$prompt" 10 70 "$initial_percent"
}
