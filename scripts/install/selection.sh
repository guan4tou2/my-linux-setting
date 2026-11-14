#!/bin/bash
# shellcheck shell=bash
# 模組選擇：顯示名稱、勾選清單、選擇解析、安裝計畫與確認摘要。
# 由 install.sh 載入（source），不可單獨執行。

# 定義模組陣列
MINIMAL_MODULES="base python terminal"
selected_modules=""

# 模組顯示名稱：優先使用 modules.conf 的 name，否則用內建名稱，最後退回 id
module_display_name() {
    local module_id="$1"
    if [[ "$(declare -p MODULE_NAMES 2>/dev/null)" == "declare -A"* ]] \
       && [ -n "${MODULE_NAMES[$module_id]:-}" ]; then
        printf '%s' "${MODULE_NAMES[$module_id]}"
        return 0
    fi
    case "$module_id" in
        python) printf '%s' "Python 開發環境" ;;
        docker) printf '%s' "Docker 工具" ;;
        base) printf '%s' "基礎工具" ;;
        terminal) printf '%s' "終端設定" ;;
        dev) printf '%s' "開發工具" ;;
        monitoring) printf '%s' "監控工具" ;;
        *) printf '%s' "$module_id" ;;
    esac
}

# 將 id 清單轉成「顯示名稱」清單，以「、」分隔
module_display_names() {
    local out="" module_id
    for module_id in $1; do
        if [ -n "$out" ]; then
            out="${out}、"
        fi
        out="${out}$(module_display_name "$module_id")"
    done
    printf '%s' "$out"
}

# 勾選清單項目文字：名稱 — 內容（狀態），不使用方括號以免與勾選框混淆
module_checklist_label() {
    local name="$1"
    local desc="${2:-}"
    local status="${3:-}"
    local label="$name"
    if [ -n "$desc" ]; then
        label="$label — $desc"
    fi
    case "$status" in
        installed) label="$label（已安裝）" ;;
        partial) label="$label（部分安裝）" ;;
    esac
    printf '%s' "$label"
}

# 勾選清單最後一列的虛擬項目：進階模式（tag 不是模組 id，解析結果時會剔除）
ADVANCED_CHECKLIST_TAG="+advanced"
ADVANCED_CHECKLIST_LABEL="進階：安裝前逐模組挑選套件"

# 組出勾選清單：checklist_items（tag 與標籤成對）與 checklist_states（ON/OFF，順序同模組）。
# 預設只勾選尚未安裝或部分安裝的模組；已安裝的不勾（標籤仍顯示「已安裝」，可手動勾選以重跑設定）。
# 呼叫端須先宣告 local checklist_items=() checklist_states=()。
build_module_checklist_items() {
    checklist_items=()
    checklist_states=()
    local module_id
    for module_id in "${MODULE_LIST[@]}"; do
        local name="${MODULE_NAMES[$module_id]:-$module_id}"
        local desc="${MODULE_DESCRIPTIONS[$module_id]:-}"
        local status=""

        if command -v check_module_status >/dev/null 2>&1; then
            status=$(check_module_status "$module_id" 2>/dev/null || true)
        fi

        checklist_items+=("$module_id" "$(module_checklist_label "$name" "$desc" "$status")")
        case "$status" in
            installed) checklist_states+=("OFF") ;;
            *) checklist_states+=("ON") ;;
        esac
    done
}

parse_module_selection() {
    local module_selection="$1"
    selected_modules=""
    local _seen=" "
    local item

    for item in $module_selection; do
        item=$(echo "$item" | tr -d '"')
        [ -z "$item" ] && continue
        case "$_seen" in
            *" $item "*) continue ;;
        esac
        _seen+=" $item "
        selected_modules="$selected_modules $item"
    done

    selected_modules=$(echo "$selected_modules" | xargs)
    [ -n "$selected_modules" ]
}

# 解析勾選清單結果：把虛擬的進階項目剔除並設定 ADVANCED_MODE；
# 只勾了進階而沒有任何模組時視為未選擇（回傳 1）。
parse_checklist_selection() {
    local selection="${1:-}" item rest=""
    ADVANCED_MODE=false
    for item in $selection; do
        item="${item//\"/}"
        if [ "$item" = "$ADVANCED_CHECKLIST_TAG" ]; then
            ADVANCED_MODE=true
        else
            rest+=" $item"
        fi
    done
    parse_module_selection "$rest"
}

select_modules_tui() {
    if [ "$INSTALL_MODE" = "minimal" ]; then
        selected_modules="$MINIMAL_MODULES"
        tui_msgbox "模組選擇" "最小安裝將安裝：\n\n$(module_display_names "$selected_modules")" || true
        return 0
    fi

    local checklist_items=() checklist_states=()
    build_module_checklist_items

    # 進階模式預設關閉；使用者帶了 --advanced 時預設勾選
    local advanced_state="OFF"
    if [ "${GUIDED_ADVANCED_DEFAULT:-${ADVANCED_MODE:-false}}" = "true" ]; then
        advanced_state="ON"
    fi

    # fzf 後端的 tui_checklist 會自行附上按鍵說明，避免重複
    local key_hint=""
    case "${TUI_BACKEND:-whiptail}" in
        fzf) key_hint="" ;;
        *) key_hint="\n空白鍵勾選／取消，Enter 確認。" ;;
    esac
    local prompt="請勾選要安裝的模組（已安裝的預設不勾選）：${key_hint}"

    local state_items=() plain_items=() i
    for ((i = 0; i < ${#checklist_items[@]}; i += 2)); do
        state_items+=("${checklist_items[$i]}" "${checklist_items[$((i + 1))]}" "${checklist_states[$((i / 2))]}")
    done
    local advanced_locked=false
    if [ "${GUIDED_ADVANCED_DEFAULT:-false}" = "true" ] \
       && ! { declare -F _tui_backend_supports_state_checklist >/dev/null 2>&1 \
              && _tui_backend_supports_state_checklist; }; then
        advanced_locked=true
        prompt+="\n進階模式已由 --advanced 啟用。"
    fi
    plain_items=("${checklist_items[@]}")
    if [ "$advanced_locked" != "true" ]; then
        plain_items+=("$ADVANCED_CHECKLIST_TAG" "$ADVANCED_CHECKLIST_LABEL")
    fi
    state_items+=("$ADVANCED_CHECKLIST_TAG" "$ADVANCED_CHECKLIST_LABEL" "$advanced_state")

    local module_selection rc
    while :; do
        rc=0
        # whiptail 可指定預設勾選；其他後端（fzf／gum）沿用 tui_checklist 既有行為
        if declare -F _tui_backend_supports_state_checklist >/dev/null 2>&1 \
           && _tui_backend_supports_state_checklist; then
            module_selection=$(tui_checklist_with_state "模組選擇" "$prompt" "${state_items[@]}") || rc=$?
        else
            module_selection=$(tui_checklist "模組選擇" "$prompt" "${plain_items[@]}") || rc=$?
        fi

        # 取消勾選清單即退出
        [ "$rc" -eq 0 ] || return 1

        if parse_checklist_selection "$module_selection"; then
            [ "$advanced_locked" != "true" ] || ADVANCED_MODE=true
            return 0
        fi
        tui_msgbox "模組選擇" "請至少勾選一個模組。" || true
    done
}

# 單一模組安裝時會做的事（一行文字）。
# 套件數依 modules.conf 宣告的套件統計，算法與 check_module_status 一致；
# 設定腳本裡另外安裝的套件不在統計內，所以有 script 時另外註明。
# 沒有模組管理器資料時輸出空字串。
module_install_plan_text() {
    local module_id="$1"
    [[ "$(declare -p MODULE_NAMES 2>/dev/null)" == "declare -A"* ]] || return 0
    [ -n "${MODULE_NAMES[$module_id]:-}" ] || return 0
    command -v _module_pkg_is_installed >/dev/null 2>&1 || return 0

    local -a entries=()
    local pkg
    for pkg in ${MODULE_PACKAGES[$module_id]:-}; do entries+=("apt:$pkg"); done
    if [ -n "${MODULE_APT_FALLBACK[$module_id]:-}" ]; then
        for pkg in ${MODULE_APT_FALLBACK[$module_id]}; do entries+=("apt_fallback:$pkg"); done
    else
        for pkg in ${MODULE_BREW_PACKAGES[$module_id]:-}; do entries+=("brew:$pkg"); done
    fi
    for pkg in ${MODULE_PIP_PACKAGES[$module_id]:-}; do entries+=("pip:$pkg"); done
    if command -v cargo >/dev/null 2>&1; then
        for pkg in ${MODULE_CARGO_PACKAGES[$module_id]:-}; do entries+=("cargo:$pkg"); done
    fi
    if command -v npm >/dev/null 2>&1; then
        for pkg in ${MODULE_NPM_PACKAGES[$module_id]:-}; do entries+=("npm:$pkg"); done
    fi

    local total=0 todo=0 entry kind
    local -A seen=()
    for entry in ${entries[@]+"${entries[@]}"}; do
        kind="${entry%%:*}"
        pkg="${entry#*:}"
        # packages 與 apt_fallback 都走系統套件，同名只算一次（install_module 也是如此）
        case "$kind" in
            apt|apt_fallback)
                [ -z "${seen[$pkg]:-}" ] || continue
                seen[$pkg]=1
                ;;
        esac
        total=$((total + 1))
        if ! _module_pkg_is_installed "$kind" "$pkg"; then
            todo=$((todo + 1))
        fi
    done

    local has_script=false
    if [ -n "${MODULE_SCRIPTS[$module_id]:-}" ]; then
        has_script=true
    fi

    local text=""
    if [ "$todo" -gt 0 ]; then
        text="安裝 $todo 個套件"
        if [ $((total - todo)) -gt 0 ]; then
            text+="、略過 $((total - todo)) 個已安裝"
        fi
        if [ "$has_script" = "true" ]; then
            text+="，並執行設定腳本"
        fi
    elif [ "$total" -gt 0 ]; then
        text="套件皆已安裝"
        if [ "$has_script" = "true" ]; then
            text+="，只執行設定腳本"
        fi
    elif [ "$has_script" = "true" ]; then
        text="只執行設定腳本"
    else
        text="沒有宣告套件"
    fi
    printf '%s' "$text"
}

# 確認摘要文字（純函式，輸出含字面 \n，交給 whiptail/printf %b 解讀）
build_install_summary_text() {
    local summary=""
    if [ "${INSTALL_MODE:-full}" = "minimal" ]; then
        summary+="最小安裝（--minimal）\n\n"
    fi
    summary+="模組："
    if declare -F _module_pkg_status_cache_clear >/dev/null 2>&1; then
        _module_pkg_status_cache_clear
    fi
    local module_id plan
    for module_id in $selected_modules; do
        plan="$(module_install_plan_text "$module_id")"
        summary+="\n  • $(module_display_name "$module_id")${plan:+：$plan}"
    done
    if [ "${ADVANCED_MODE:-false}" = "true" ]; then
        summary+="\n\n進階模式：確認後會逐模組挑選要安裝的套件（以上為全部套件的數量）。"
    fi
    if [ "${HOMEBREW_DECISION:-}" = "yes" ]; then
        summary+="\n\nHomebrew：會先安裝（APT 裝不到時的備援）"
    fi
    local shown_log="${LOG_FILE:-未設定}"
    case "$shown_log" in "$HOME"/*) shown_log="~${shown_log#"$HOME"}" ;; esac
    summary+="\n\n日誌：${shown_log}\n\n確認後開始安裝，進度會顯示在終端機。"
    printf '%s' "$summary"
}

confirm_install_summary_tui() {
    tui_yesno "確認安裝" "$(build_install_summary_text)" "yes"
}
