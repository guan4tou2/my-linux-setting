#!/bin/bash
# shellcheck shell=bash
# Homebrew：選完模組後才詢問是否安裝（APT 優先，brew 僅作備援）。
# 由 install.sh 載入（source），不可單獨執行。

# ==============================================================================
# Homebrew（選完模組後才詢問；APT 優先，brew 僅作備援）
# ==============================================================================

HOMEBREW_DECISION="${HOMEBREW_DECISION:-}"

# 所選模組是否宣告了 brew_packages
selected_modules_need_homebrew() {
    local modules="${1:-$selected_modules}"
    [[ "$(declare -p MODULE_BREW_PACKAGES 2>/dev/null)" == "declare -A"* ]] || return 1
    local module_id
    for module_id in $modules; do
        if [ -n "${MODULE_BREW_PACKAGES[$module_id]:-}" ]; then
            return 0
        fi
    done
    return 1
}

# 是否該詢問 Homebrew（不含互動本身，方便測試）
# shellcheck disable=SC2120 # 參數為可選，供測試指定模組清單
homebrew_offer_needed() {
    [ "${NON_INTERACTIVE:-false}" != "true" ] || return 1
    [ "${INSTALL_MODE:-full}" != "minimal" ] || return 1
    [ "${DRY_RUN:-false}" != "true" ] || return 1
    [ -z "${HOMEBREW_DECISION:-}" ] || return 1
    # brew 不建議以 root 執行，install_module 也會略過 brew
    [ "${EUID:-$(id -u)}" -ne 0 ] || return 1
    ! command -v brew >/dev/null 2>&1 || return 1
    selected_modules_need_homebrew "${1:-$selected_modules}"
}

offer_homebrew_if_needed() {
    if ! homebrew_offer_needed || [ ! -t 0 ]; then
        return 0
    fi

    local prompt="所選模組有些工具在 APT 裝不到時，\n會改用 Homebrew 安裝（備援）。\n\n要先安裝 Homebrew 嗎？（約數分鐘）"
    if [ "${USE_TUI:-false}" = "true" ] && command -v tui_yesno >/dev/null 2>&1; then
        if tui_yesno "Homebrew" "$prompt" "no"; then
            HOMEBREW_DECISION="yes"
        else
            HOMEBREW_DECISION="no"
        fi
    else
        local answer=""
        printf '%b [y/N]: ' "$prompt"
        read -r answer || true
        case "$answer" in
            y|Y|yes|YES) HOMEBREW_DECISION="yes" ;;
            *) HOMEBREW_DECISION="no" ;;
        esac
    fi
    log_info "Homebrew 詢問結果：$HOMEBREW_DECISION"
    return 0
}

# 依先前決定安裝 Homebrew；失敗不中斷（APT 仍是主要來源）
install_homebrew_if_requested() {
    [ "${HOMEBREW_DECISION:-}" = "yes" ] || return 0
    if command -v brew >/dev/null 2>&1; then
        return 0
    fi
    if ! command -v ensure_homebrew_installed >/dev/null 2>&1; then
        log_warning "找不到 Homebrew 安裝函數，跳過"
        return 0
    fi

    local rc=0
    if [ "${PROGRESS_ACTIVE:-false}" = "true" ]; then
        local started=$SECONDS
        progress_run "" "安裝 Homebrew" run_logged_command ensure_homebrew_installed || rc=$?
        if [ "$rc" -eq 0 ]; then
            progress_finish_line "" "安裝 Homebrew" ok "" $((SECONDS - started))
        else
            progress_finish_line "" "安裝 Homebrew" failed "改用 APT 繼續" $((SECONDS - started))
        fi
    else
        run_logged_command ensure_homebrew_installed || rc=$?
    fi
    if [ "$rc" -ne 0 ]; then
        log_warning "Homebrew 安裝失敗，將只使用 APT 等其他方式安裝工具"
    fi
    return 0
}
