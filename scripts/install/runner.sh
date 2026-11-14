#!/bin/bash
# shellcheck shell=bash
# 安裝流程：套件索引準備、逐模組安裝、失敗處理與收尾。
# 由 install.sh 載入（source），不可單獨執行。

# ==============================================================================
# 安裝流程
# ==============================================================================

run_install_with_tui() {
    local install_rc=0
    if install_selected_modules; then
        install_rc=0
    else
        install_rc=$?
    fi
    return "$install_rc"
}


# 執行單一模組
run_module_install() {
    local module="$1"
    run_logged_command install_module "$module"
}

# 模組失敗策略：
# - 預設 ABORT_ON_FAILURE=false：記錄失敗，繼續下一個模組
# - --abort-on-failure：立即中止整段安裝
# - 互動模式且非 abort：詢問是否繼續
_handle_module_failure() {
    local mod="$1"
    local remaining="${2:-1}"
    local name
    name="$(module_display_name "$mod")"
    # 安全初始化（兼容 set -u）
    FAILED_MODULES=(${FAILED_MODULES[@]+"${FAILED_MODULES[@]}"} "$mod")
    if [ "${PROGRESS_ACTIVE:-false}" = "true" ]; then
        # 進度行已顯示失敗，錯誤訊息只寫入日誌
        log_error "模組 $mod 安裝失敗" 2>/dev/null || true
    else
        log_error "模組 $mod 安裝失敗" || true
    fi

    if [ "${ABORT_ON_FAILURE:-false}" = "true" ]; then
        log_warning "--abort-on-failure 已啟用，中止安裝"
        return 1
    fi

    # 已是最後一個模組：沒有「其餘模組」可問，直接進入報告
    if [ "$remaining" -le 0 ] 2>/dev/null; then
        return 0
    fi

    if [ -t 0 ] && [ "${NON_INTERACTIVE:-false}" != "true" ]; then
        if [ "${USE_TUI:-false}" = "true" ] && command -v tui_yesno >/dev/null 2>&1; then
            if ! tui_yesno "模組安裝失敗" "「$name」安裝失敗。\n\n還有 $remaining 個模組未安裝，要繼續嗎？" "yes"; then
                log_warning "使用者選擇中止"
                return 1
            fi
        else
            printf "${YELLOW:-}「%s」安裝失敗，是否繼續安裝其餘模組？${NC:-} [Y/n]: " "$name"
            local ans=""
            read -r ans || true
            case "${ans,,}" in
                n|no) log_warning "使用者選擇中止"; return 1 ;;
            esac
        fi
    fi
    log_warning "繼續安裝下一個模組（失敗模組會在最後報告）"
    return 0
}

# 所選模組安裝時是否會用到套件管理器（決定要不要先更新套件索引）。
# 保守判斷：有模組管理器資料時，只要所選模組有設定腳本（腳本內常會 apt install）、
# 有尚未安裝的系統套件（packages／apt_fallback／brew_packages），或使用 --force 就需要；
# 沒有模組管理器資料時一律需要。
# shellcheck disable=SC2120 # 參數為可選，預設用 selected_modules；測試會傳入清單
selected_modules_need_package_index() {
    local modules="${1:-$selected_modules}"
    if [[ "$(declare -p MODULE_SCRIPTS 2>/dev/null)" != "declare -A"* ]] \
       || ! command -v _module_pkg_is_installed >/dev/null 2>&1; then
        return 0
    fi
    [ "${FORCE_REINSTALL:-false}" != "true" ] || return 0

    local module_id pkg
    for module_id in $modules; do
        if [ -n "${MODULE_SCRIPTS[$module_id]:-}" ]; then
            return 0
        fi
        for pkg in ${MODULE_PACKAGES[$module_id]:-}; do
            _module_pkg_is_installed apt "$pkg" || return 0
        done
        for pkg in ${MODULE_APT_FALLBACK[$module_id]:-}; do
            _module_pkg_is_installed apt_fallback "$pkg" || return 0
        done
        for pkg in ${MODULE_BREW_PACKAGES[$module_id]:-}; do
            _module_pkg_is_installed brew "$pkg" || return 0
        done
    done
    return 1
}

# 第一個模組開始前先更新套件索引，並以獨立的一行進度顯示（耗時不再算在第一個模組頭上）。
# 更新失敗只顯示警示並繼續安裝。ensure_package_index_fresh 每次執行只會真正更新一次。
prepare_package_index() {
    local use_progress="${1:-false}"
    command -v ensure_package_index_fresh >/dev/null 2>&1 || return 0
    [ "${LINUX_SETTING_PKG_INDEX_CHECKED:-}" != "1" ] || return 0
    selected_modules_need_package_index || return 0

    # 索引仍然新鮮（或不需要更新）時，讓 ensure_package_index_fresh 只做記號與日誌，不顯示進度行
    if [ "$use_progress" != "true" ] \
       || ! command -v _pkg_index_needs_update >/dev/null 2>&1 \
       || ! _pkg_index_needs_update; then
        ensure_package_index_fresh || true
        return 0
    fi

    local label="更新套件索引"
    local started=$SECONDS
    progress_run "" "$label" run_logged_command ensure_package_index_fresh || true
    local elapsed=$((SECONDS - started))
    if [ "${LINUX_SETTING_PKG_INDEX_UPDATED:-}" = "1" ]; then
        progress_finish_line "" "$label" ok "" "$elapsed"
    else
        progress_finish_line "" "$label" partial "更新失敗，繼續安裝" "$elapsed"
    fi
    return 0
}

# 安裝選中的模組
install_selected_modules() {
    reset_install_results
    if [ -z "$selected_modules" ]; then
        printf "${RED}未選擇任何模組${NC}\n"
        return
    fi

    local install_order=()
    install_order=("${MODULE_LIST[@]}")

    # 無論 modules.conf 定義順序為何，都將 terminal 放到最後執行，
    # 以便在全部模組完成後再套用 zsh/提示符相關設定。
    local module
    local has_terminal=false
    for module in "${install_order[@]}"; do
        if [ "$module" = "terminal" ]; then
            has_terminal=true
            break
        fi
    done
    if [ "$has_terminal" = "true" ]; then
        local reordered_install_order=()
        for module in "${install_order[@]}"; do
            [ "$module" = "terminal" ] && continue
            reordered_install_order+=("$module")
        done
        reordered_install_order+=("terminal")
        install_order=("${reordered_install_order[@]}")
    fi

    # 計算要安裝的模組數量
    local total_modules=0
    local current_module=0
    for module in "${install_order[@]}"; do
        case " $selected_modules " in
            *" $module "*) total_modules=$((total_modules + 1)) ;;
        esac
    done

    # 干運行模式：僅顯示將要安裝的內容
    if [ "$DRY_RUN" = true ]; then
        printf "\n${CYAN}========== 預覽模式 (Dry Run) ==========${NC}\n"
        printf "${BLUE}將安裝以下 $total_modules 個模組：${NC}\n\n"

        for module in "${install_order[@]}"; do
            case " $selected_modules " in
                *" $module "*) ;;
                *) continue ;;
            esac

            local module_name="${MODULE_NAMES[$module]:-$module}"
            printf "${GREEN}[$module]${NC} %s\n" "$module_name"
            [ -n "${MODULE_PACKAGES[$module]:-}" ] && printf "  • packages: %s\n" "${MODULE_PACKAGES[$module]}" || true
            [ -n "${MODULE_BREW_PACKAGES[$module]:-}" ] && printf "  • brew: %s\n" "${MODULE_BREW_PACKAGES[$module]}" || true
            [ -n "${MODULE_PIP_PACKAGES[$module]:-}" ] && printf "  • pip: %s\n" "${MODULE_PIP_PACKAGES[$module]}" || true
            [ -n "${MODULE_CARGO_PACKAGES[$module]:-}" ] && printf "  • cargo: %s\n" "${MODULE_CARGO_PACKAGES[$module]}" || true
            [ -n "${MODULE_NPM_PACKAGES[$module]:-}" ] && printf "  • npm: %s\n" "${MODULE_NPM_PACKAGES[$module]}" || true
            printf "\n"
        done

        printf "\n${GREEN}提示：${NC}移除 --dry-run 參數即可開始實際安裝\n\n"
        return 0
    fi

    log_info "開始安裝以下模組：$selected_modules"
    log_info "總共 $total_modules 個模組"

    # 進階模式：在開始安裝前，逐模組讓使用者再選具體要裝的套件
    if [ "${ADVANCED_MODE:-false}" = "true" ] \
       && command -v module_interactive_package_filter >/dev/null 2>&1 \
       && [ "${NON_INTERACTIVE:-false}" != "true" ]; then
        log_info "進階模式：逐模組選擇套件"
        for module in "${install_order[@]}"; do
            case " $selected_modules " in
                *" $module "*) ;;
                *) continue ;;
            esac
            module_interactive_package_filter "$module" || {
                log_warning "使用者取消模組 $module，將從清單移除"
                selected_modules=$(echo " $selected_modules " | sed "s/ $module / /g" | xargs)
                total_modules=$((total_modules - 1))
            }
        done
        log_info "進階選擇完成"
        if [ -z "$selected_modules" ] || [ "$total_modules" -le 0 ]; then
            log_warning "所有模組都被取消，結束安裝"
            return 0
        fi
    fi

    # CLI 互動模式在此詢問 Homebrew（TUI 導覽流程已在選完模組後問過）
    offer_homebrew_if_needed

    local use_progress=false
    if installer_tui_quiet; then
        use_progress=true
        progress_begin "$total_modules"
    fi

    # 優化 APT 性能（Debian 系列）：會寫入 /etc/apt/apt.conf.d/，
    # 所以只在 dry-run 返回與使用者確認之後、第一次用到套件管理器之前執行
    if [ "${DISTRO_FAMILY:-}" = "debian" ] && command -v optimize_apt_performance >/dev/null 2>&1; then
        optimize_apt_performance || log_warning "APT 優化失敗，繼續安裝"
    fi

    prepare_package_index "$use_progress"
    install_homebrew_if_requested

    # 為了確保依賴順序，實際安裝順序固定為：
    # 1. base       - 提供 git/curl/wget 等基礎工具與 APT 相關套件
    # 2. dev        - 安裝 cargo / nodejs 等開發工具，供後續模組使用
    # 3. python     - 建立 Python/uv/虛擬環境，供終端工具使用
    # 4. monitoring - 安裝監控與安全工具
    # 5. docker     - 可選的 Docker 工具
    # 6. terminal   - 最後安裝（不再自動 exec zsh）
    local aborted=false
    for module in "${install_order[@]}"; do
        case " $selected_modules " in
            *" $module "*) ;;
            *) continue ;;
        esac

        if [ "$aborted" = "true" ]; then
            record_module_result "$module" not_run ""
            continue
        fi

        current_module=$((current_module + 1))
        log_info "進度 [$current_module/$total_modules] 安裝模組: $module"

        # 模組層級「已安裝偵測」：印出訊息；實際「跳過套件但仍跑 script / post_install」
        # 的邏輯由 module_manager.sh::install_module 處理。
        # 設 FORCE_REINSTALL=true 或 --force 可強制重裝所有套件。
        if [ "${FORCE_REINSTALL:-false}" != "true" ] \
           && command -v check_module_status >/dev/null 2>&1; then
            module_status=$(check_module_status "$module" 2>/dev/null || echo "not_installed")
            if [ "$module_status" = "installed" ]; then
                log_success "模組 $module 套件已全部安裝，將跳過套件階段並執行設定腳本"
                log_info "如需強制重裝套件，請加 --force 或設定 FORCE_REINSTALL=true"
            fi
        fi

        local label tag
        label="$(module_display_name "$module")"
        tag="[$current_module/$total_modules]"

        # install_module 在部分套件失敗時回傳 0，但會在 MODULE_INSTALL_FAILURES 附加一筆
        local failures_before=0
        if declare -p MODULE_INSTALL_FAILURES >/dev/null 2>&1; then
            failures_before=${#MODULE_INSTALL_FAILURES[@]}
        fi

        local started=$SECONDS
        local rc=0
        if [ "$use_progress" = "true" ]; then
            progress_run "$tag" "$label" run_module_install "$module" || rc=$?
        else
            run_module_install "$module" || rc=$?
        fi
        local elapsed=$((SECONDS - started))

        local status="ok" detail="" status_text=""
        if [ "$rc" -ne 0 ]; then
            status="failed"
            status_text="失敗"
        elif declare -p MODULE_INSTALL_FAILURES >/dev/null 2>&1 \
             && [ "${#MODULE_INSTALL_FAILURES[@]}" -gt "$failures_before" ]; then
            status="partial"
            detail="$(module_failure_packages "${MODULE_INSTALL_FAILURES[$((${#MODULE_INSTALL_FAILURES[@]} - 1))]}")"
            status_text="部分套件失敗（$(count_words "$detail") 個）"
        else
            status_text="完成"
        fi
        record_module_result "$module" "$status" "$detail"

        if [ "$use_progress" = "true" ]; then
            progress_finish_line "$tag" "$label" "$status" "$status_text" "$elapsed"
        fi

        if [ "$status" = "failed" ]; then
            if ! _handle_module_failure "$module" $((total_modules - current_module)); then
                aborted=true
                # shellcheck disable=SC2034 # 由 scripts/install/report.sh 的結束碼與報告讀取
                INSTALL_ABORTED=true
            fi
            if [ "$use_progress" = "true" ]; then
                progress_redraw
            fi
        fi
    done

    if [ "$use_progress" = "true" ]; then
        progress_end
    fi

    record_created_configs
    install_uninstaller_copy

    show_installation_report
    selected_modules=""
    if [ "${GUIDED_RESULT_SCREEN:-false}" != "true" ] \
       && declare -F reset_module_overrides >/dev/null 2>&1; then
        reset_module_overrides
    fi

    # 如果是在「非互動環境」（例如：管線 / here-doc / Docker 自動化測試），
    # 完成一次安裝後就直接結束腳本，避免迴圈再次 read 造成 EOF 而觸發錯誤處理。
    if [ ! -t 0 ]; then
        printf "${CYAN}偵測到非互動環境，自動結束安裝流程${NC}\n"
        if [ "$aborted" = "true" ]; then
            exit 1
        fi
        # 有模組失敗或未執行時以非 0 結束，讓 CI 與自動化腳本能察覺
        exit "$(install_results_exit_code)"
    fi

    if [ "$aborted" = "true" ]; then
        return 1
    fi
    return 0
}
