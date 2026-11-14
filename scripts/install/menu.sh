#!/bin/bash
# shellcheck shell=bash
# 純文字選單（沒有 TUI 時使用）：主選單、模組詳細內容、加入模組。
# 由 install.sh 載入（source），不可單獨執行。

# 顯示菜單函數（動態生成，包含安裝狀態標記）
show_menu() {
    # 不畫右框線：中文是雙寬字元，printf 的欄寬以位元組計算，右框線必然對不齊
    local rule="────────────────────────────────────────────────────────────────"
    printf "\n${CYAN}%s${NC}\n" "$rule"
    printf "  ${CYAN}選擇安裝模組${NC}\n"
    printf "${CYAN}%s${NC}\n\n" "$rule"

    # 動態生成模組選項
    local index=1
    local module_id
    for module_id in "${MODULE_LIST[@]}"; do
        local name="${MODULE_NAMES[$module_id]:-$module_id}"
        local desc="${MODULE_DESCRIPTIONS[$module_id]:-}"
        local status=""
        local mark="[ ]"

        # 獲取安裝狀態標記
        if command -v check_module_status >/dev/null 2>&1; then
            status=$(check_module_status "$module_id" 2>/dev/null || true)
        fi
        case "$status" in
            installed) mark="[${GREEN}✓${NC}]" ;;
            partial)   mark="[${YELLOW}◐${NC}]" ;;
        esac

        printf "  ${GREEN}[%d]${NC} %b %s" "$index" "$mark" "$name"
        if [ -n "$desc" ]; then
            printf " — %s" "$desc"
        fi
        printf "\n"
        index=$((index + 1))
    done
    printf "  ${GREEN}[%d]${NC}     全部安裝\n" "$index"

    # 顯示狀態圖例
    printf "\n  [${GREEN}✓${NC}] 已安裝  [${YELLOW}◐${NC}] 部分安裝  [ ] 未安裝\n"
    printf "${CYAN}%s${NC}\n" "$rule"

    # 顯示當前選擇
    if [ -n "$selected_modules" ]; then
        printf "  ${YELLOW}已選擇：${NC}%s\n" "${selected_modules# }"
    else
        printf "  ${YELLOW}已選擇：${NC}（尚未選擇）\n"
    fi

    # 進階模式狀態
    if [ "${ADVANCED_MODE:-false}" = "true" ]; then
        printf "  ${YELLOW}進階模式：開${NC}（按 [a] 關閉；安裝時會逐模組選套件）\n"
    else
        printf "  進階模式：關（按 [a] 開啟；可逐模組挑套件）\n"
    fi
    printf "  ${BLUE}[i]${NC} 開始安裝  ${BLUE}[c]${NC} 清除  ${BLUE}[d]${NC} 詳細  ${BLUE}[a]${NC} 進階  ${BLUE}[q]${NC} 退出\n"
    printf "${CYAN}%s${NC}\n" "$rule"
    printf "\n輸入選項（例如：1 3 4）："
}


# 顯示單個模組詳細資訊（TUI 對話框）
show_module_detail_dialog() {
    local module_id="$1"

    if ! module_exists "$module_id" 2>/dev/null; then
        log_warning "模組不存在: $module_id"
        return 1
    fi

    local detail
    detail=$(get_module_detail_status "$module_id" 2>/dev/null || true)

    if [ -z "$detail" ]; then
        detail="（無法產生詳細狀態，可能缺少設定或檢查函數失敗）\n模組 ID：$module_id"
    fi

    if [ "$USE_TUI" = "true" ] && command -v tui_msgbox >/dev/null 2>&1; then
        local name="${MODULE_NAMES[$module_id]:-$module_id}"
        tui_msgbox "模組詳情: $name" "$detail"
    else
        printf "\n%s\n" "$detail"
        printf "\n按 Enter 返回..."
        read -r
    fi
}

# 顯示模組選擇選單（用於查看詳情）
show_detail_selection_menu() {
    if [ "$USE_TUI" = "true" ] && command -v tui_menu >/dev/null 2>&1; then
        # 並行維護「顯示標籤」與「模組 ID」，避免只靠字串剥離狀態圖示導致對應失敗
        local menu_labels=()
        local menu_ids=()

        for module_id in "${MODULE_LIST[@]}"; do
            local name="${MODULE_NAMES[$module_id]:-$module_id}"
            local status_icon=""
            if command -v check_module_status >/dev/null 2>&1; then
                local status
                status=$(check_module_status "$module_id" 2>/dev/null || true)
                case "$status" in
                    installed)     status_icon="[✓] " ;;
                    partial)       status_icon="[◐] " ;;
                    not_installed) status_icon="[ ] " ;;
                esac
            fi
            menu_labels+=("${status_icon}${name}")
            menu_ids+=("$module_id")
        done

        menu_labels+=("返回主選單")
        menu_ids+=("RETURN")

        local selection
        selection=$(tui_menu "查看模組詳情" "選擇要查看的模組：" "${menu_labels[@]}") || return 0

        if [ -z "$selection" ] || [ "$selection" = "返回主選單" ]; then
            return 0
        fi

        local _i=0
        local picked_id=""
        for lbl in "${menu_labels[@]}"; do
            if [ "$lbl" = "$selection" ]; then
                picked_id="${menu_ids[_i]}"
                break
            fi
            _i=$((_i + 1))
        done

        if [ -z "$picked_id" ] || [ "$picked_id" = "RETURN" ]; then
            return 0
        fi

        show_module_detail_dialog "$picked_id" || true
        return 0
    else
        # 命令行模式：顯示完整的模組詳情
        show_module_details
    fi
}

# 顯示模組詳細資訊（動態生成，包含安裝狀態）
show_module_details() {
    printf "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
    printf "${CYAN}                    模組詳細資訊                               ${NC}\n"
    printf "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n\n"

    local index=1
    for module_id in "${MODULE_LIST[@]}"; do
        if command -v _module_pkg_status_cache_clear >/dev/null 2>&1; then
            _module_pkg_status_cache_clear
        fi

        local name="${MODULE_NAMES[$module_id]:-$module_id}"
        local system_packages="${MODULE_PACKAGES[$module_id]:-}"
        local brew_packages="${MODULE_BREW_PACKAGES[$module_id]:-}"
        local pip_packages="${MODULE_PIP_PACKAGES[$module_id]:-}"
        local cargo_packages="${MODULE_CARGO_PACKAGES[$module_id]:-}"
        local npm_packages="${MODULE_NPM_PACKAGES[$module_id]:-}"

        # 獲取安裝狀態
        local status_icon=" "
        local status_text="未安裝"
        if command -v check_module_status >/dev/null 2>&1; then
            local status
            status=$(check_module_status "$module_id" true 2>/dev/null)
            case "$status" in
                installed)
                    status_icon="✓"
                    status_text="已安裝"
                    ;;
                partial)
                    status_icon="◐"
                    status_text="部分安裝"
                    ;;
                not_installed)
                    status_icon=" "
                    status_text="未安裝"
                    ;;
            esac
        fi

        # 根據狀態顯示不同顏色
        if [ "$status_icon" = "✓" ]; then
            printf "${GREEN}[%d] [%s] %s (%s)${NC}\n" "$index" "$status_icon" "$name" "$status_text"
        elif [ "$status_icon" = "◐" ]; then
            printf "${YELLOW}[%d] [%s] %s (%s)${NC}\n" "$index" "$status_icon" "$name" "$status_text"
        else
            printf "[%d] [ ] %s (%s)\n" "$index" "$name" "$status_text"
        fi

        # 顯示套件清單（帶狀態標記）
        if [ -n "$system_packages" ]; then
            printf "    ${BLUE}系統套件:${NC} "
            local first=true
            for pkg in $system_packages; do
                [ "$first" = true ] || printf ", " || true
                first=false
                if _module_pkg_is_installed apt "$pkg"; then
                    printf "${GREEN}%s${NC}" "$pkg"
                else
                    printf "${RED}%s${NC}" "$pkg"
                fi
            done
            printf "\n"
        fi

        if [ -n "$brew_packages" ]; then
            printf "    ${BLUE}Homebrew:${NC} "
            local first=true
            for pkg in $brew_packages; do
                [ "$first" = true ] || printf ", " || true
                first=false
                if command -v brew >/dev/null 2>&1 && _module_pkg_is_installed brew "$pkg"; then
                    printf "${GREEN}%s${NC}" "$pkg"
                else
                    printf "${RED}%s${NC}" "$pkg"
                fi
            done
            printf "\n"
        fi

        if [ -n "$pip_packages" ]; then
            printf "    ${BLUE}Python (uv):${NC} "
            local first=true
            for pkg in $pip_packages; do
                [ "$first" = true ] || printf ", " || true
                first=false
                if _module_pkg_is_installed pip "$pkg"; then
                    printf "${GREEN}%s${NC}" "$pkg"
                else
                    printf "${RED}%s${NC}" "$pkg"
                fi
            done
            printf "\n"
        fi

        if [ -n "$cargo_packages" ]; then
            printf "    ${BLUE}Cargo:${NC} "
            local first=true
            for pkg in $cargo_packages; do
                [ "$first" = true ] || printf ", " || true
                first=false
                if command -v cargo >/dev/null 2>&1 && _module_pkg_is_installed cargo "$pkg"; then
                    printf "${GREEN}%s${NC}" "$pkg"
                else
                    printf "${RED}%s${NC}" "$pkg"
                fi
            done
            printf "\n"
        fi

        if [ -n "$npm_packages" ]; then
            printf "    ${BLUE}NPM:${NC} "
            local first=true
            for pkg in $npm_packages; do
                [ "$first" = true ] || printf ", " || true
                first=false
                if command -v npm >/dev/null 2>&1 && _module_pkg_is_installed npm "$pkg"; then
                    printf "${GREEN}%s${NC}" "$pkg"
                else
                    printf "${RED}%s${NC}" "$pkg"
                fi
            done
            printf "\n"
        fi

        printf "\n"
        index=$((index + 1))
    done

    printf "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
    printf "\n${YELLOW}圖例:${NC} ${GREEN}綠色${NC}=已安裝  ${RED}紅色${NC}=未安裝\n"
    printf "${YELLOW}提示:${NC} 修改 config/modules.conf 可自訂安裝內容\n"
    printf "\n按 Enter 返回選單..."
    read -r
}


# 添加模組到選擇列表（動態支援）
add_module() {
    local num=$1

    local total=${#MODULE_LIST[@]}
    local all_num=$((total + 1))

    if [ "$num" -eq "$all_num" ]; then
        # 全部安裝
        selected_modules="${MODULE_LIST[*]}"
        return
    elif [ "$num" -ge 1 ] && [ "$num" -le "$total" ]; then
        local module_id="${MODULE_LIST[$((num - 1))]}"
        # 避免重複添加
        if [[ " $selected_modules " != *" $module_id "* ]]; then
            selected_modules="$selected_modules $module_id"
        fi
        return
    fi

    printf "${RED}無效的選項：$num${NC}\n"
}
