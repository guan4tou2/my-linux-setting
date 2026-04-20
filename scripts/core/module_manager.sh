#!/usr/bin/env bash

# ==============================================================================
# Module Manager - 模組管理器
# ==============================================================================
#
# 提供模組配置的讀取、解析和安裝功能
# 讓用戶可以透過修改 config/modules.conf 來自訂安裝內容
#
# 注意：此腳本需要 Bash 4.0+ 支持關聯陣列
#
# ==============================================================================

# 檢查 Bash 版本（需要 4.0+ 支持關聯陣列）
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "WARNING: module_manager.sh 需要 Bash 4.0+，當前版本: ${BASH_VERSION:-unknown}" >&2
    echo "建議安裝新版 Bash: brew install bash" >&2
    return 1 2>/dev/null || exit 1
fi

# 配置文件路徑
MODULES_CONF="${MODULES_CONF:-}"

# 模組資料存儲（使用關聯陣列）
declare -A MODULE_NAMES
declare -A MODULE_DESCRIPTIONS
declare -A MODULE_PACKAGES
declare -A MODULE_BREW_PACKAGES
declare -A MODULE_APT_FALLBACK
declare -A MODULE_PIP_PACKAGES
declare -A MODULE_CARGO_PACKAGES
declare -A MODULE_NPM_PACKAGES
declare -A MODULE_SCRIPTS
declare -A MODULE_POST_INSTALL

# 模組列表（保持順序）
MODULE_LIST=()

# ==============================================================================
# 進階模式：每個模組的 per-package 覆寫（由互動 filter 設定）
# 鍵：模組 ID；值：對應類型「實際要安裝」的套件清單（空格分隔）
# 若某模組未在 override 中出現，則該模組仍走預設（裝全部）
# 若 override 值為空字串，代表「該類型一個都不裝」
# 同時保留 MODULE_RUN_SCRIPT 控制 script= 是否要執行
# ==============================================================================
declare -A MODULE_PKG_OVERRIDE_APT
declare -A MODULE_PKG_OVERRIDE_BREW
declare -A MODULE_PKG_OVERRIDE_PIP
declare -A MODULE_PKG_OVERRIDE_CARGO
declare -A MODULE_PKG_OVERRIDE_NPM
declare -A MODULE_PKG_OVERRIDE_APT_FALLBACK
declare -A MODULE_RUN_SCRIPT
declare -A MODULE_HAS_OVERRIDE

# ==============================================================================
# 配置文件定位
# ==============================================================================

find_modules_conf() {
    local search_paths=(
        "$MODULES_CONF"
        "$PWD/config/modules.conf"
        "$SCRIPT_DIR/../config/modules.conf"
        "$SCRIPT_DIR/../../config/modules.conf"
        "$HOME/.config/linux-setting/modules.conf"
    )

    for path in "${search_paths[@]}"; do
        if [ -n "$path" ] && [ -f "$path" ]; then
            echo "$path"
            return 0
        fi
    done

    return 1
}

# ==============================================================================
# 配置文件解析
# ==============================================================================

parse_modules_conf() {
    local conf_file
    conf_file=$(find_modules_conf) || {
        log_warning "找不到模組配置文件，使用預設配置"
        return 1
    }

    log_info "載入模組配置: $conf_file"

    local current_module=""
    local line_number=0

    while IFS= read -r line || [ -n "$line" ]; do
        line_number=$((line_number + 1))

        # 跳過空行和註解
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # 去除首尾空白
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # 檢測模組標頭 [module_name]
        if [[ "$line" =~ ^\[([a-zA-Z0-9_-]+)\]$ ]]; then
            current_module="${BASH_REMATCH[1]}"
            MODULE_LIST+=("$current_module")
            log_debug "發現模組: $current_module"
            continue
        fi

        # 解析鍵值對
        if [[ -n "$current_module" && "$line" =~ ^([a-zA-Z_]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            case "$key" in
                name)
                    MODULE_NAMES["$current_module"]="$value"
                    ;;
                description)
                    MODULE_DESCRIPTIONS["$current_module"]="$value"
                    ;;
                packages)
                    MODULE_PACKAGES["$current_module"]="$value"
                    ;;
                brew_packages)
                    MODULE_BREW_PACKAGES["$current_module"]="$value"
                    ;;
                apt_fallback)
                    MODULE_APT_FALLBACK["$current_module"]="$value"
                    ;;
                pip_packages)
                    MODULE_PIP_PACKAGES["$current_module"]="$value"
                    ;;
                cargo_packages)
                    MODULE_CARGO_PACKAGES["$current_module"]="$value"
                    ;;
                npm_packages)
                    MODULE_NPM_PACKAGES["$current_module"]="$value"
                    ;;
                script)
                    MODULE_SCRIPTS["$current_module"]="$value"
                    ;;
                post_install)
                    MODULE_POST_INSTALL["$current_module"]="$value"
                    ;;
            esac
        fi
    done < "$conf_file"

    log_success "已載入 ${#MODULE_LIST[@]} 個模組"
    return 0
}

# ==============================================================================
# 模組資訊查詢
# ==============================================================================

# 取得所有模組 ID
get_module_ids() {
    echo "${MODULE_LIST[@]}"
}

# 取得模組數量
get_module_count() {
    echo "${#MODULE_LIST[@]}"
}

# 取得模組顯示名稱
get_module_name() {
    local module_id="$1"
    echo "${MODULE_NAMES[$module_id]:-$module_id}"
}

# 取得模組描述
get_module_description() {
    local module_id="$1"
    echo "${MODULE_DESCRIPTIONS[$module_id]:-}"
}

# 取得模組套件列表
get_module_packages() {
    local module_id="$1"
    echo "${MODULE_PACKAGES[$module_id]:-}"
}

# 取得模組 Homebrew 套件
get_module_brew_packages() {
    local module_id="$1"
    echo "${MODULE_BREW_PACKAGES[$module_id]:-}"
}

# 取得模組安裝腳本
get_module_script() {
    local module_id="$1"
    echo "${MODULE_SCRIPTS[$module_id]:-}"
}

# 檢查模組是否存在
module_exists() {
    local module_id="$1"
    [ -n "${MODULE_NAMES[$module_id]+x}" ]
}

# ==============================================================================
# 模組狀態檢查
# ==============================================================================

# 檢查模組安裝狀態
# 返回: "installed" | "partial" | "not_installed"
check_module_status() {
    local module_id="$1"
    local total=0
    local installed=0

    # 檢查 APT/系統套件
    local packages="${MODULE_PACKAGES[$module_id]:-}"
    if [ -n "$packages" ]; then
        for pkg in $packages; do
            total=$((total + 1))
            if check_package_installed "$pkg" 2>/dev/null; then
                installed=$((installed + 1))
            fi
        done
    fi

    # 檢查 Homebrew 套件
    local brew_packages="${MODULE_BREW_PACKAGES[$module_id]:-}"
    local apt_fallback="${MODULE_APT_FALLBACK[$module_id]:-}"
    if [ -n "$brew_packages" ]; then
        if command -v brew >/dev/null 2>&1; then
            # brew 存在，檢查 brew 套件
            for pkg in $brew_packages; do
                total=$((total + 1))
                if check_brew_package_installed "$pkg" 2>/dev/null; then
                    installed=$((installed + 1))
                fi
            done
        elif [ -n "$apt_fallback" ]; then
            # brew 不存在但有 apt fallback，檢查 fallback 套件
            for pkg in $apt_fallback; do
                total=$((total + 1))
                if check_package_installed "$pkg" 2>/dev/null; then
                    installed=$((installed + 1))
                fi
            done
        else
            # brew 不存在且無 fallback，將 brew 套件計為未安裝
            for pkg in $brew_packages; do
                total=$((total + 1))
                # 不增加 installed，視為未安裝
            done
        fi
    fi

    # 檢查 Python 套件
    local pip_packages="${MODULE_PIP_PACKAGES[$module_id]:-}"
    if [ -n "$pip_packages" ]; then
        for pkg in $pip_packages; do
            total=$((total + 1))
            if check_pip_package_installed "$pkg" 2>/dev/null; then
                installed=$((installed + 1))
            fi
        done
    fi

    # 檢查 Cargo 套件
    local cargo_packages="${MODULE_CARGO_PACKAGES[$module_id]:-}"
    if [ -n "$cargo_packages" ] && command -v cargo >/dev/null 2>&1; then
        for pkg in $cargo_packages; do
            total=$((total + 1))
            if check_cargo_package_installed "$pkg" 2>/dev/null; then
                installed=$((installed + 1))
            fi
        done
    fi

    # 檢查 NPM 套件
    local npm_packages="${MODULE_NPM_PACKAGES[$module_id]:-}"
    if [ -n "$npm_packages" ] && command -v npm >/dev/null 2>&1; then
        for pkg in $npm_packages; do
            total=$((total + 1))
            if check_npm_package_installed "$pkg" 2>/dev/null; then
                installed=$((installed + 1))
            fi
        done
    fi

    # 返回狀態
    if [ $total -eq 0 ]; then
        # 沒有套件定義，檢查是否有腳本
        local script="${MODULE_SCRIPTS[$module_id]:-}"
        if [ -n "$script" ]; then
            echo "not_installed"
        else
            echo "not_installed"
        fi
    elif [ $installed -eq $total ]; then
        echo "installed"
    elif [ $installed -gt 0 ]; then
        echo "partial"
    else
        echo "not_installed"
    fi
}

# 獲取模組詳細狀態（返回格式化的詳細狀態）
get_module_detail_status() {
    local module_id="$1"
    local detail=""

    local name="${MODULE_NAMES[$module_id]:-$module_id}"
    local desc="${MODULE_DESCRIPTIONS[$module_id]:-}"
    local status
    status=$(check_module_status "$module_id")

    # 狀態標記
    case "$status" in
        installed)     detail+="[✓] $name (已安裝)\n" ;;
        partial)       detail+="[◐] $name (部分安裝)\n" ;;
        not_installed) detail+="[ ] $name (未安裝)\n" ;;
    esac

    [ -n "$desc" ] && detail+="    $desc\n" || true
    detail+="\n"

    # APT/系統套件
    local packages="${MODULE_PACKAGES[$module_id]:-}"
    if [ -n "$packages" ]; then
        detail+="系統套件:\n"
        for pkg in $packages; do
            if check_package_installed "$pkg" 2>/dev/null; then
                detail+="  ✓ $pkg\n"
            else
                detail+="  ✗ $pkg\n"
            fi
        done
        detail+="\n"
    fi

    # Homebrew 套件
    local brew_packages="${MODULE_BREW_PACKAGES[$module_id]:-}"
    local apt_fallback="${MODULE_APT_FALLBACK[$module_id]:-}"
    if [ -n "$brew_packages" ]; then
        if command -v brew >/dev/null 2>&1; then
            detail+="Homebrew 套件:\n"
            for pkg in $brew_packages; do
                if check_brew_package_installed "$pkg" 2>/dev/null; then
                    detail+="  ✓ $pkg\n"
                else
                    detail+="  ✗ $pkg\n"
                fi
            done
        elif [ -n "$apt_fallback" ]; then
            detail+="Homebrew 套件 (使用 APT 替代):\n"
            for pkg in $apt_fallback; do
                if check_package_installed "$pkg" 2>/dev/null; then
                    detail+="  ✓ $pkg (apt)\n"
                else
                    detail+="  ✗ $pkg (apt)\n"
                fi
            done
        else
            detail+="Homebrew 套件 (brew 未安裝):\n"
            for pkg in $brew_packages; do
                detail+="  ✗ $pkg (需要 brew)\n"
            done
        fi
        detail+="\n"
    fi

    # Python 套件
    local pip_packages="${MODULE_PIP_PACKAGES[$module_id]:-}"
    if [ -n "$pip_packages" ]; then
        detail+="Python 套件 (uv tool):\n"
        for pkg in $pip_packages; do
            if check_pip_package_installed "$pkg" 2>/dev/null; then
                detail+="  ✓ $pkg\n"
            else
                detail+="  ✗ $pkg\n"
            fi
        done
        detail+="\n"
    fi

    # Cargo 套件
    local cargo_packages="${MODULE_CARGO_PACKAGES[$module_id]:-}"
    if [ -n "$cargo_packages" ]; then
        detail+="Rust 套件 (cargo):\n"
        for pkg in $cargo_packages; do
            if command -v cargo >/dev/null 2>&1 && check_cargo_package_installed "$pkg" 2>/dev/null; then
                detail+="  ✓ $pkg\n"
            else
                detail+="  ✗ $pkg\n"
            fi
        done
        detail+="\n"
    fi

    # NPM 套件
    local npm_packages="${MODULE_NPM_PACKAGES[$module_id]:-}"
    if [ -n "$npm_packages" ]; then
        detail+="Node.js 套件 (npm):\n"
        for pkg in $npm_packages; do
            if command -v npm >/dev/null 2>&1 && check_npm_package_installed "$pkg" 2>/dev/null; then
                detail+="  ✓ $pkg\n"
            else
                detail+="  ✗ $pkg\n"
            fi
        done
        detail+="\n"
    fi

    # 安裝腳本
    local script="${MODULE_SCRIPTS[$module_id]:-}"
    if [ -n "$script" ]; then
        detail+="安裝腳本: $script\n"
    fi

    echo -e "$detail"
}

# 獲取模組狀態標記符號
get_module_status_icon() {
    local module_id="$1"
    local status
    status=$(check_module_status "$module_id")

    case "$status" in
        installed)     echo "✓" ;;
        partial)       echo "◐" ;;
        not_installed) echo " " ;;
    esac
}

# ==============================================================================
# 動態選單生成
# ==============================================================================

# 生成 CLI 選單
generate_cli_menu() {
    local index=1

    printf "\n"
    printf "${CYAN}┌─ 選擇安裝模組 ─────────────────────────────────────────────┐${NC}\n"
    printf "${CYAN}│                                                             │${NC}\n"

    for module_id in "${MODULE_LIST[@]}"; do
        local name="${MODULE_NAMES[$module_id]}"
        local desc="${MODULE_DESCRIPTIONS[$module_id]}"
        printf "${CYAN}│${NC}  ${GREEN}[%d]${NC} %-20s %-30s${CYAN}│${NC}\n" "$index" "$name" "$desc"
        index=$((index + 1))
    done

    printf "${CYAN}│${NC}  ${GREEN}[%d]${NC} %-20s %-30s${CYAN}│${NC}\n" "$index" "全部安裝" ""
    printf "${CYAN}│                                                             │${NC}\n"
    printf "${CYAN}├─────────────────────────────────────────────────────────────┤${NC}\n"

    # 顯示當前選擇
    if [ -n "${selected_modules:-}" ]; then
        printf "${CYAN}│${NC}  ${YELLOW}已選擇:${NC} %-48s${CYAN}│${NC}\n" "$selected_modules"
    else
        printf "${CYAN}│${NC}  ${YELLOW}已選擇:${NC} (尚未選擇)                                    ${CYAN}│${NC}\n"
    fi

    printf "${CYAN}│                                                             │${NC}\n"
    printf "${CYAN}│${NC}  ${BLUE}[i]${NC} 開始安裝  ${BLUE}[c]${NC} 清除  ${BLUE}[d]${NC} 詳細說明  ${BLUE}[q]${NC} 退出        ${CYAN}│${NC}\n"
    printf "${CYAN}└─────────────────────────────────────────────────────────────┘${NC}\n"
    printf "\n輸入選項 (例如: 1 3 4): "
}

# 生成 TUI checklist 項目
generate_tui_checklist_items() {
    local items=""
    for module_id in "${MODULE_LIST[@]}"; do
        local name="${MODULE_NAMES[$module_id]}"
        local desc="${MODULE_DESCRIPTIONS[$module_id]}"
        items+="$module_id|$name ($desc) "
    done
    echo "$items"
}

# 生成詳細說明
generate_module_details() {
    printf "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"

    local index=1
    for module_id in "${MODULE_LIST[@]}"; do
        local name="${MODULE_NAMES[$module_id]}"
        local packages="${MODULE_PACKAGES[$module_id]}"
        local brew_packages="${MODULE_BREW_PACKAGES[$module_id]:-}"
        local pip_packages="${MODULE_PIP_PACKAGES[$module_id]:-}"

        printf "${GREEN}[%d] %s${NC}\n" "$index" "$name"

        [ -n "$packages" ] && printf "    APT: %s\n" "$packages"
        [ -n "$brew_packages" ] && printf "    Brew: %s\n" "$brew_packages"
        [ -n "$pip_packages" ] && printf "    Pip: %s\n" "$pip_packages"
        printf "\n"

        index=$((index + 1))
    done

    printf "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
    # 非互動模式不要求 Enter，避免阻塞
    if ! { [ "${NON_INTERACTIVE:-false}" = "true" ] || [ ! -t 0 ]; }; then
        printf "\n按 Enter 返回選單..."
        read -r
    fi
}

# ==============================================================================
# 進階模式：互動式套件選擇
# ==============================================================================

# 內部 helper：根據包安裝狀態回報 ON/OFF（已裝 → OFF，未裝 → ON）
_module_pkg_default_state() {
    local kind="$1" pkg="$2"
    case "$kind" in
        apt|apt_fallback) check_package_installed "$pkg" 2>/dev/null && echo "OFF" || echo "ON" ;;
        brew)             check_brew_package_installed "$pkg" 2>/dev/null && echo "OFF" || echo "ON" ;;
        pip)              check_pip_package_installed "$pkg" 2>/dev/null && echo "OFF" || echo "ON" ;;
        cargo)            check_cargo_package_installed "$pkg" 2>/dev/null && echo "OFF" || echo "ON" ;;
        npm)              check_npm_package_installed "$pkg" 2>/dev/null && echo "OFF" || echo "ON" ;;
        *)                echo "ON" ;;
    esac
}

_module_pkg_status_label() {
    local kind="$1" pkg="$2"
    if [ "$(_module_pkg_default_state "$kind" "$pkg")" = "OFF" ]; then
        echo "已安裝"
    else
        echo "未安裝"
    fi
}

# 進階模式：對單一模組互動選擇要安裝的套件
# 設定 MODULE_PKG_OVERRIDE_* / MODULE_RUN_SCRIPT[$module_id] / MODULE_HAS_OVERRIDE[$module_id]
# 回傳 0 = 已選；1 = 使用者取消整個模組
module_interactive_package_filter() {
    local module_id="$1"
    local name="${MODULE_NAMES[$module_id]:-$module_id}"

    local apt_pkgs="${MODULE_PACKAGES[$module_id]:-}"
    local brew_pkgs="${MODULE_BREW_PACKAGES[$module_id]:-}"
    local apt_fb_pkgs="${MODULE_APT_FALLBACK[$module_id]:-}"
    local pip_pkgs="${MODULE_PIP_PACKAGES[$module_id]:-}"
    local cargo_pkgs="${MODULE_CARGO_PACKAGES[$module_id]:-}"
    local npm_pkgs="${MODULE_NPM_PACKAGES[$module_id]:-}"
    local script="${MODULE_SCRIPTS[$module_id]:-}"

    # 構建 checklist 項目：tag = "kind:pkgname"
    local items=()
    local _kind _list _p _state _label
    # helper: 將 (_kind, _list) 加進 items
    _add_kind_to_items() {
        _kind="$1"; _list="$2"
        [ -z "$_list" ] && return 0
        for _p in $_list; do
            _state=$(_module_pkg_default_state "$_kind" "$_p")
            _label=$(_module_pkg_status_label "$_kind" "$_p")
            items+=("${_kind}:${_p}" "[$_kind] $_p ($_label)" "$_state")
        done
    }
    _add_kind_to_items apt          "$apt_pkgs"
    # brew 只有在 brew 可用時才列；否則列 apt_fallback
    if command -v brew >/dev/null 2>&1; then
        _add_kind_to_items brew         "$brew_pkgs"
    elif [ -n "$apt_fb_pkgs" ]; then
        _add_kind_to_items apt_fallback "$apt_fb_pkgs"
    fi
    _add_kind_to_items pip          "$pip_pkgs"
    _add_kind_to_items cargo        "$cargo_pkgs"
    _add_kind_to_items npm          "$npm_pkgs"
    unset -f _add_kind_to_items 2>/dev/null || true

    # script= 也讓使用者選是否執行
    local has_script_item=0
    if [ -n "$script" ]; then
        items+=("__script__:$script" "[script] 執行 $script (額外配置)" "ON")
        has_script_item=1
    fi

    # 沒任何項目可選（純空 module）→ 視為走預設
    if [ ${#items[@]} -eq 0 ]; then
        MODULE_HAS_OVERRIDE[$module_id]=""
        return 0
    fi

    # 嘗試 TUI 模式
    local selected=""
    local rc=1
    if [ "${USE_TUI:-false}" = "true" ] && command -v tui_checklist_with_state >/dev/null 2>&1; then
        rc=0
        selected=$(tui_checklist_with_state \
            "進階：選擇 [$name] 要安裝的套件" \
            "空白鍵切換、方向鍵移動、Enter 確認；已安裝者預設不勾選" \
            "${items[@]}") || rc=$?
    else
        # CLI fallback
        printf "\n\033[36m=== 進階：選擇 [%s] 要安裝的套件 ===\033[0m\n" "$name"
        local idx=0
        local -a tag_arr=()
        local -a desc_arr=()
        local -a state_arr=()
        local i=0
        while [ $i -lt ${#items[@]} ]; do
            tag_arr+=("${items[$i]}")
            desc_arr+=("${items[$((i+1))]}")
            state_arr+=("${items[$((i+2))]}")
            i=$((i + 3))
        done
        local n=${#tag_arr[@]}
        for ((idx=0; idx<n; idx++)); do
            local mark="[ ]"
            [ "${state_arr[$idx]}" = "ON" ] && mark="[x]"
            printf "  %2d) %s %s\n" "$((idx+1))" "$mark" "${desc_arr[$idx]}"
        done
        printf "\n輸入要 \033[33m取消\033[0m勾選的編號（空白分隔，輸入 a 全選、n 全不選、Enter 套用預設）：\n> "
        local input
        if [ "${NON_INTERACTIVE:-false}" = "true" ] || [ ! -t 0 ]; then
            input=""
        else
            read -r input
        fi
        case "$input" in
            a|A) for ((idx=0; idx<n; idx++)); do state_arr[$idx]="ON"; done ;;
            n|N) for ((idx=0; idx<n; idx++)); do state_arr[$idx]="OFF"; done ;;
            "")  : ;; # 套用預設
            *)   for num in $input; do
                     if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "$n" ]; then
                         state_arr[$((num-1))]="OFF"
                     fi
                 done ;;
        esac
        local sel_list=()
        for ((idx=0; idx<n; idx++)); do
            [ "${state_arr[$idx]}" = "ON" ] && sel_list+=("${tag_arr[$idx]}")
        done
        selected="${sel_list[*]}"
        rc=0
    fi

    if [ $rc -ne 0 ]; then
        log_warning "使用者取消模組 $name 的進階選擇"
        return 1
    fi

    # 將選中的 tag 拆回各類型 override
    local out_apt="" out_brew="" out_pip="" out_cargo="" out_npm="" out_apt_fb=""
    local run_script=0
    for tag in $selected; do
        case "$tag" in
            apt:*)          out_apt+=" ${tag#apt:}" ;;
            brew:*)         out_brew+=" ${tag#brew:}" ;;
            apt_fallback:*) out_apt_fb+=" ${tag#apt_fallback:}" ;;
            pip:*)          out_pip+=" ${tag#pip:}" ;;
            cargo:*)        out_cargo+=" ${tag#cargo:}" ;;
            npm:*)          out_npm+=" ${tag#npm:}" ;;
            __script__:*)   run_script=1 ;;
        esac
    done

    MODULE_PKG_OVERRIDE_APT[$module_id]="${out_apt# }"
    MODULE_PKG_OVERRIDE_BREW[$module_id]="${out_brew# }"
    MODULE_PKG_OVERRIDE_APT_FALLBACK[$module_id]="${out_apt_fb# }"
    MODULE_PKG_OVERRIDE_PIP[$module_id]="${out_pip# }"
    MODULE_PKG_OVERRIDE_CARGO[$module_id]="${out_cargo# }"
    MODULE_PKG_OVERRIDE_NPM[$module_id]="${out_npm# }"
    if [ "$has_script_item" = "1" ]; then
        MODULE_RUN_SCRIPT[$module_id]="$run_script"
    fi
    MODULE_HAS_OVERRIDE[$module_id]="1"

    log_info "[$name] 進階選擇完成（apt:$(echo $out_apt | wc -w) brew:$(echo $out_brew | wc -w) pip:$(echo $out_pip | wc -w) cargo:$(echo $out_cargo | wc -w) npm:$(echo $out_npm | wc -w) script:${run_script:-1}）"
    return 0
}

# ==============================================================================
# 模組安裝
# ==============================================================================

# 透過編號取得模組 ID
get_module_id_by_number() {
    local num="$1"
    local index=1

    for module_id in "${MODULE_LIST[@]}"; do
        if [ "$index" -eq "$num" ]; then
            echo "$module_id"
            return 0
        fi
        index=$((index + 1))
    done

    # 如果是最後一個數字（全部安裝）
    if [ "$num" -eq "$index" ]; then
        echo "all"
        return 0
    fi

    return 1
}

# 安裝單個模組
install_module() {
    local module_id="$1"

    if ! module_exists "$module_id"; then
        log_error "模組不存在: $module_id"
        return 1
    fi

    local name="${MODULE_NAMES[$module_id]}"
    local packages="${MODULE_PACKAGES[$module_id]}"
    local brew_packages="${MODULE_BREW_PACKAGES[$module_id]:-}"
    local apt_fallback="${MODULE_APT_FALLBACK[$module_id]:-}"
    local pip_packages="${MODULE_PIP_PACKAGES[$module_id]:-}"
    local cargo_packages="${MODULE_CARGO_PACKAGES[$module_id]:-}"
    local npm_packages="${MODULE_NPM_PACKAGES[$module_id]:-}"
    local script="${MODULE_SCRIPTS[$module_id]:-}"
    local post_install="${MODULE_POST_INSTALL[$module_id]:-}"

    # 進階模式 override：若該模組已被使用者經 module_interactive_package_filter 過濾，
    # 則改用 override 後的子集，並決定是否要跑 script
    local should_run_script=1
    if [ "${MODULE_HAS_OVERRIDE[$module_id]:-}" = "1" ]; then
        log_info "套用進階模式套件選擇（$name）"
        packages="${MODULE_PKG_OVERRIDE_APT[$module_id]:-}"
        brew_packages="${MODULE_PKG_OVERRIDE_BREW[$module_id]:-}"
        apt_fallback="${MODULE_PKG_OVERRIDE_APT_FALLBACK[$module_id]:-}"
        pip_packages="${MODULE_PKG_OVERRIDE_PIP[$module_id]:-}"
        cargo_packages="${MODULE_PKG_OVERRIDE_CARGO[$module_id]:-}"
        npm_packages="${MODULE_PKG_OVERRIDE_NPM[$module_id]:-}"
        should_run_script="${MODULE_RUN_SCRIPT[$module_id]:-1}"
    fi

    # 檢查模組安裝狀態
    local module_status
    module_status=$(check_module_status "$module_id" 2>/dev/null || echo "not_installed")

    # 若設定 FORCE_REINSTALL=true，視同未安裝，強制重跑所有套件安裝步驟
    if [ "${FORCE_REINSTALL:-false}" = "true" ] && [ "$module_status" = "installed" ]; then
        log_info "FORCE_REINSTALL=true，強制重新安裝模組 $name 的所有套件"
        module_status="not_installed"
    fi

    log_info "安裝模組: $name"

    # 累計每個模組的整體失敗（非單純 log warning），最後回報給 caller
    local module_failures=()

    if [ "$module_status" = "installed" ]; then
        log_info "模組 $name 套件已全部安裝，跳過套件安裝步驟（仍會執行設定腳本）"
    else
        # 統計安裝情況
        local skipped_count=0
        local installed_count=0

        # 1. 安裝 APT 套件（跳過已安裝的）
        if [ -n "$packages" ]; then
            log_info "檢查系統套件..."
            for pkg in $packages; do
                if check_package_installed "$pkg" 2>/dev/null; then
                    log_info "✓ $pkg 已安裝，跳過"
                    skipped_count=$((skipped_count + 1))
                else
                    if install_package "$pkg"; then
                        installed_count=$((installed_count + 1))
                    else
                        log_warning "套件安裝失敗: $pkg"
                        module_failures+=("apt:$pkg")
                    fi
                fi
            done
        fi

        # 2. 安裝 Homebrew 套件（如果可用，跳過已安裝的）
        # 注意：brew 不建議以 root 執行；若目前是 root，改走 apt_fallback（若有）或略過 brew
        if [ -n "$brew_packages" ] && command -v brew >/dev/null 2>&1 && [ "${EUID:-$(id -u)}" -ne 0 ]; then
            log_info "檢查 Homebrew 套件..."
            for pkg in $brew_packages; do
                if check_brew_package_installed "$pkg" 2>/dev/null; then
                    log_info "✓ $pkg 已安裝 (brew)，跳過"
                    skipped_count=$((skipped_count + 1))
                else
                    if install_brew_package "$pkg"; then
                        installed_count=$((installed_count + 1))
                    else
                        log_warning "Brew 套件安裝失敗: $pkg"
                        module_failures+=("brew:$pkg")
                    fi
                fi
            done
        elif [ -n "$brew_packages" ] && command -v brew >/dev/null 2>&1 && [ "${EUID:-$(id -u)}" -eq 0 ]; then
            log_warning "目前以 root 執行，略過 brew 套件（brew 不建議 root）。將改用 apt_fallback（若有）"
            if [ -z "$apt_fallback" ]; then
                for pkg in $brew_packages; do
                    module_failures+=("brew:$pkg")
                done
            fi
        fi

        if [ -n "$apt_fallback" ]; then
            # Homebrew 不可用，使用 APT 替代
            log_info "使用 APT 替代套件..."
            for pkg in $apt_fallback; do
                if check_package_installed "$pkg" 2>/dev/null; then
                    log_info "✓ $pkg 已安裝，跳過"
                    skipped_count=$((skipped_count + 1))
                else
                    if install_package "$pkg"; then
                        installed_count=$((installed_count + 1))
                    else
                        log_warning "套件安裝失敗: $pkg"
                        module_failures+=("apt:$pkg")
                    fi
                fi
            done
        fi

        # 3. 安裝 Python 套件（統一使用 uv tool，跳過已安裝的）
        if [ -n "$pip_packages" ]; then
            log_info "檢查 Python 套件..."

            # 確保 uv 已安裝
            if ! command -v uv >/dev/null 2>&1; then
                log_info "安裝 uv..."
                curl -LsSf --connect-timeout 15 --max-time 180 https://astral.sh/uv/install.sh | sh
                export PATH="$HOME/.local/bin:$PATH"
            fi

            for pkg in $pip_packages; do
                if check_pip_package_installed "$pkg" 2>/dev/null; then
                    log_info "✓ $pkg 已安裝 (pip/uv)，跳過"
                    skipped_count=$((skipped_count + 1))
                else
                    log_info "安裝 $pkg..."
                    if uv tool install "$pkg" 2>/dev/null; then
                        log_success "$pkg 安裝成功"
                        installed_count=$((installed_count + 1))
                    else
                        log_warning "$pkg 安裝失敗，嘗試使用 pipx..."
                        if pipx install "$pkg" 2>/dev/null; then
                            installed_count=$((installed_count + 1))
                        else
                            log_warning "無法安裝 $pkg"
                            module_failures+=("pip:$pkg")
                        fi
                    fi
                fi
            done
        fi

        # 4. 安裝 Cargo 套件（跳過已安裝的）
        if [ -n "$cargo_packages" ] && command -v cargo >/dev/null 2>&1; then
            log_info "檢查 Rust 套件..."
            for pkg in $cargo_packages; do
                if check_cargo_package_installed "$pkg" 2>/dev/null; then
                    log_info "✓ $pkg 已安裝 (cargo)，跳過"
                    skipped_count=$((skipped_count + 1))
                else
                    if cargo install "$pkg" 2>/dev/null; then
                        installed_count=$((installed_count + 1))
                    else
                        log_warning "Cargo 套件安裝失敗: $pkg"
                        module_failures+=("cargo:$pkg")
                    fi
                fi
            done
        fi

        # 5. 安裝 NPM 套件（跳過已安裝的）
        # 先確保使用者級 npm prefix 已設定（避免 /usr/local 寫權限問題）
        if [ -n "$npm_packages" ] && command -v npm >/dev/null 2>&1; then
            ensure_npm_user_prefix 2>/dev/null || true
            log_info "檢查 Node.js 套件..."
            for pkg in $npm_packages; do
                if check_npm_package_installed "$pkg" 2>/dev/null; then
                    log_info "✓ $pkg 已安裝 (npm)，跳過"
                    skipped_count=$((skipped_count + 1))
                else
                    if npm install -g "$pkg" 2>/dev/null; then
                        installed_count=$((installed_count + 1))
                    else
                        log_warning "NPM 套件安裝失敗: $pkg"
                        module_failures+=("npm:$pkg")
                    fi
                fi
            done
        fi

        # 顯示安裝統計
        if [ $skipped_count -gt 0 ] || [ $installed_count -gt 0 ]; then
            log_info "套件安裝統計: 新安裝 $installed_count 個，跳過 $skipped_count 個（已安裝）"
        fi
    fi

    # 6. 執行自訂安裝腳本
    # 一般模式：無論狀態都執行（腳本可能有額外配置）
    # 進階模式：依 should_run_script 決定（使用者可在 checklist 取消 [script] 項）
    if [ -n "$script" ] && [ "$should_run_script" = "1" ]; then
        local script_path="$SCRIPT_DIR/core/$script"
        if [ -f "$script_path" ]; then
            log_info "執行安裝腳本: $script"
            bash "$script_path" || {
                log_error "腳本執行失敗: $script"
                return 1
            }
        else
            log_warning "找不到腳本: $script_path"
        fi
    elif [ -n "$script" ] && [ "$should_run_script" != "1" ]; then
        log_info "進階模式：使用者選擇跳過 $script"
    fi

    # 7. 執行安裝後命令
    if [ -n "$post_install" ]; then
        log_info "執行安裝後命令..."
        eval "$post_install" || log_warning "安裝後命令執行失敗"
    fi

    # 若有任何套件安裝失敗，明確回報但不中斷（避免一個 transient 失敗拖垮整段安裝）
    if [ ${#module_failures[@]} -gt 0 ]; then
        log_warning "====================================================="
        log_warning "模組 $name 已完成，但有 ${#module_failures[@]} 個套件失敗："
        for f in "${module_failures[@]}"; do
            log_warning "  ✗ $f"
        done
        log_warning "  （若需強制重裝，重跑時加 --force）"
        log_warning "====================================================="
        # 紀錄到全域陣列供後續總結使用（安全初始化避免 set -u 報錯）
        MODULE_INSTALL_FAILURES=(${MODULE_INSTALL_FAILURES[@]+"${MODULE_INSTALL_FAILURES[@]}"} "$name: ${module_failures[*]}")
        return 0
    fi

    log_success "模組安裝完成: $name"
    return 0
}

# ==============================================================================
# 初始化
# ==============================================================================

init_module_manager() {
    # 解析配置文件
    parse_modules_conf || {
        # 如果找不到配置文件，使用預設模組
        log_info "使用內建預設模組"
        MODULE_LIST=(python docker base terminal dev monitoring)
        MODULE_NAMES=(
            [python]="Python 開發環境"
            [docker]="Docker 工具"
            [base]="基礎工具"
            [terminal]="終端設定"
            [dev]="開發工具"
            [monitoring]="監控工具"
        )
        MODULE_DESCRIPTIONS=(
            [python]="python3, pip, uv, ranger"
            [docker]="docker-ce, lazydocker"
            [base]="git, lsd, bat, ripgrep, fzf"
            [terminal]="zsh, oh-my-zsh, powerlevel10k"
            [dev]="neovim, lazygit, nodejs, rust"
            [monitoring]="btop, htop, iftop, fail2ban"
        )
        MODULE_SCRIPTS=(
            [python]="python_setup.sh"
            [docker]="docker_setup.sh"
            [base]="base_tools.sh"
            [terminal]="terminal_setup.sh"
            [dev]="dev_tools.sh"
            [monitoring]="monitoring_tools.sh"
        )
    }
}

# 導出函數
export -f find_modules_conf parse_modules_conf 2>/dev/null || true
export -f get_module_ids get_module_count get_module_name get_module_description 2>/dev/null || true
export -f get_module_packages get_module_brew_packages get_module_script module_exists 2>/dev/null || true
export -f generate_cli_menu generate_tui_checklist_items generate_module_details 2>/dev/null || true
export -f get_module_id_by_number install_module init_module_manager 2>/dev/null || true
export -f check_module_status get_module_detail_status get_module_status_icon 2>/dev/null || true
export -f module_interactive_package_filter _module_pkg_default_state _module_pkg_status_label 2>/dev/null || true
