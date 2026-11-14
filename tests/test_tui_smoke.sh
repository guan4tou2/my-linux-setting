#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ "$(uname -s)" != Linux ]; then
    echo '略過：TUI 冒煙測試需要 Linux。'
    [ "${CI:-false}" != true ]
    exit $?
fi
# 要測試的 TUI 後端；可用 TUI_SMOKE_BACKENDS="fzf gum" 指定子集合
read -r -a backends <<<"${TUI_SMOKE_BACKENDS:-whiptail fzf gum}"
if [ "${#backends[@]}" -eq 0 ]; then
    echo 'TUI_SMOKE_BACKENDS 不可為空。' >&2
    exit 2
fi
for backend in "${backends[@]}"; do
    case "$backend" in
        whiptail|fzf|gum) ;;
        *) echo "未知的 TUI 後端：$backend（可用：whiptail fzf gum）" >&2; exit 2 ;;
    esac
done
# 缺少 tmux 時整個測試無法進行；缺少某個後端只影響該後端。
# CI=true 先嘗試用 apt 安裝，仍缺少就失敗；非 CI 則略過並說明。
missing=()
command -v tmux >/dev/null 2>&1 || missing+=(tmux)
for backend in "${backends[@]}"; do
    command -v "$backend" >/dev/null 2>&1 || missing+=("$backend")
done
if [ "${#missing[@]}" -gt 0 ] && [ "${CI:-false}" = true ]; then
    echo "CI 安裝測試依賴：${missing[*]}"
    sudo apt-get update
    # 逐一安裝：某個套件在此發行版不存在時，不影響其他套件
    for dep in "${missing[@]}"; do
        sudo apt-get install -y "$dep" || echo "無法安裝 $dep" >&2
    done
    missing=()
    command -v tmux >/dev/null 2>&1 || missing+=(tmux)
    for backend in "${backends[@]}"; do
        command -v "$backend" >/dev/null 2>&1 || missing+=("$backend")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        echo "CI 環境仍缺少：${missing[*]}" >&2
        exit 1
    fi
elif [ "${#missing[@]}" -gt 0 ]; then
    if command -v tmux >/dev/null 2>&1; then
        run_backends=()
        for backend in "${backends[@]}"; do
            if command -v "$backend" >/dev/null 2>&1; then
                run_backends+=("$backend")
            else
                echo "略過後端 $backend：未安裝（請用 apt 安裝；CI=true 時會自動安裝）。"
            fi
        done
        backends=("${run_backends[@]+"${run_backends[@]}"}")
        if [ "${#backends[@]}" -eq 0 ]; then
            echo '略過：沒有可測試的後端。'
            exit 0
        fi
    else
        echo "略過：缺少 ${missing[*]}，請先用 apt 安裝。"
        exit 0
    fi
fi
work=$(mktemp -d)
socket="ci-tui-$$-${RANDOM}"
pane=''
scenario='初始化'
capture() { tmux -L "$socket" capture-pane -p -t "$pane"; }
cleanup() {
    local status=$?
    if [ "$status" -ne 0 ]; then
        echo "TUI 冒煙測試失敗：$scenario；結束碼：$status" >&2
        echo '=== 當下畫面擷取 ===' >&2
        capture >&2 2>/dev/null || true
        echo '=== 終端機歷史 ===' >&2
        tmux -L "$socket" capture-pane -p -S -150 -t "$pane" >&2 2>/dev/null || true
        while IFS= read -r -d '' log; do
            echo "=== $log（尾端）===" >&2
            tail -n 80 "$log" >&2
        done < <(find "$work" -type f -name '*.log' -print0)
    fi
    tmux -L "$socket" kill-server 2>/dev/null || true
    rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
wait_screen() {
    local text="$1" timeout="${2:-60}" deadline needle matched
    local needles=("$1" "${@:3}")
    deadline=$((SECONDS + timeout))
    while [ "$SECONDS" -lt "$deadline" ]; do
        if capture >"$work/screen.txt"; then
            matched=true
            for needle in "${needles[@]}"; do
                if ! grep -Fq -- "$needle" "$work/screen.txt"; then matched=false; break; fi
            done
            if [ "$matched" = true ]; then
                echo "通過 | $scenario | 畫面：${needles[*]}"
                return 0
            fi
        fi
        if [[ "$text" != TUI_EXIT=* ]] && [ -f "$work/$scenario/exit-code" ]; then
            echo "安裝程式提早結束，尚未出現：$text" >&2
            return 1
        fi
        # 僅作為輪詢間隔；同步條件永遠是畫面文字。
        sleep 0.2
    done
    echo "等待畫面逾時（${timeout} 秒）：${needles[*]}" >&2
    return 1
}
assert_screen() {
    if ! capture | grep -Fq -- "$1"; then
        echo "當下畫面缺少：$1" >&2
        return 1
    fi
    echo "通過 | $scenario | 畫面包含：$1"
}
# 全新容器沒有套件索引，apt-cache 查不到候選版本；先更新一次（失敗只警告）
ensure_apt_index() {
    local policy
    policy=$(apt-cache policy tree sl cowsay 2>/dev/null || true)
    if grep -Eq 'Candidate: [^(]' <<<"$policy"; then
        return 0
    fi
    echo '套件索引不存在，先執行 apt-get update'
    sudo -n apt-get update -qq || echo '警告：apt-get update 失敗，可能找不到測試用的小套件' >&2
}
pick_package() {
    local pkg policy
    # 每個情境用不同的小套件；跳過已安裝、或此發行版沒有候選版本的套件
    # （toilet 會連帶裝 figlet，所以兩者不同時列入）
    for pkg in tree sl toilet cowsay cmatrix lolcat; do
        if [ -e "$work/used-$pkg" ]; then continue; fi
        policy=$(apt-cache policy "$pkg" 2>/dev/null || true)
        if ! grep -Eq 'Candidate: [^(]' <<<"$policy"; then continue; fi
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q '^install ok installed$'; then
            : >"$work/used-$pkg"
            printf '%s' "$pkg"
            return 0
        fi
    done
    echo '找不到尚未安裝的小套件，請使用全新的測試容器。' >&2
    return 1
}
# 所有測試修改只發生在複本，原專案的設定與安裝腳本不變。
cp -R "$REPO_ROOT" "$work/project"
cat >"$work/project/scripts/core/smoke_fail.sh" <<'FAIL'
#!/usr/bin/env bash
set -euo pipefail
echo 'TUI 冒煙測試：刻意讓設定腳本失敗。' >&2
exit 3
FAIL
ensure_apt_index
send_keys() { tmux -L "$socket" send-keys -t "$pane" "$@"; }
# 各後端的畫面文字與按鍵（fzf 與 gum 不支援初始勾選，勾選清單最後一列是 +advanced）。
# 勾選畫面：whiptail 預先勾選全部模組，Enter 即可；fzf 與 gum 用空白鍵勾選目前列，
# Down 移到下一列（空白鍵不會移動游標）。
select_modules() {
    local backend="$1" expected="$2"
    case "$backend" in
        whiptail) wait_screen '模組選擇' 60 '冒煙成功模組' ;;
        fzf) wait_screen '模組選擇>' 60 '冒煙成功模組' ;;
        gum) wait_screen 'Choose:' 60 '冒煙成功模組' ;;
    esac
    assert_screen '冒煙成功模組'
    if [ "$backend" != whiptail ]; then
        send_keys Space
        if [ "$expected" -ne 0 ]; then send_keys Down Space; fi
    fi
    send_keys Enter
}
confirm_install() {
    local backend="$1" expected="$2"
    # gum confirm 不顯示標題，所以三個後端都以摘要內的固定文字同步
    case "$backend" in
        whiptail) wait_screen '確認安裝' 60 '確認後開始安裝' ;;
        fzf) wait_screen '確認安裝>' 60 '確認後開始安裝' ;;
        gum) wait_screen '確認後開始安裝' 60 'Yes' 'No' ;;
    esac
    assert_screen '冒煙成功模組'
    if [ "$expected" -ne 0 ]; then assert_screen '冒煙失敗模組'; fi
    send_keys Enter
}
wait_result() {
    local backend="$1"
    case "$backend" in
        whiptail) wait_screen '安裝完成' 600 '✓ 冒煙成功模組' '退出' ;;
        fzf) wait_screen '安裝完成' 600 '✓ 冒煙成功模組' '退出' ;;
        gum) wait_screen 'Choose:' 600 '✓ 冒煙成功模組' '退出' ;;
    esac
}
# 結果選單的「退出」總是最後一列
choose_exit() {
    local backend="$1" expected="$2"
    case "$backend" in
        whiptail) send_keys End Enter ;;
        fzf|gum)
            # 選項：[重試失敗的模組] 查看安裝日誌、重新選擇、退出；游標從第一列開始往下移
            # （fzf 的過濾輸入是非同步比對，Enter 可能搶在過濾完成前送出，所以不用）
            if [ "$expected" -ne 0 ]; then send_keys Down Down Down Enter; else send_keys Down Down Enter; fi
            ;;
    esac
}
run_scenario() {
    local backend="$1" outcome="$2" expected=0
    [ "$outcome" = success ] || expected=1
    scenario="$backend-$outcome"
    local package dir command
    package=$(pick_package)
    dir="$work/$scenario"
    mkdir -p "$dir/home" "$dir/logs"
    cat >"$dir/modules.conf" <<CONF
[smoke_ok]
name=冒煙成功模組
description=小套件 $package
packages=$package
CONF
    if [ "$expected" -ne 0 ]; then
        cat >>"$dir/modules.conf" <<'CONF'
[smoke_fail]
name=冒煙失敗模組
description=設定腳本固定失敗
packages=
script=smoke_fail.sh
CONF
    fi
    # 外層 shell 保持 pane 存在，讓終止標記和最後的報告可擷取。
    {
        printf '#!/usr/bin/env bash\nset -euo pipefail\n'
        printf 'cd %q\n' "$work/project"
        printf 'export HOME=%q LOG_DIR=%q MODULES_CONF=%q\n' "$dir/home" "$dir/logs" "$dir/modules.conf"
        printf 'export TERM=xterm-256color LANG=C.UTF-8 LC_ALL=C.UTF-8 TUI_BACKEND=%q TUI_MODE=quiet NON_INTERACTIVE=false USE_TUI=auto\n' "$backend"
        printf 'status=0\nbash ./install.sh || status=$?\nprintf "%%s\\n" "$status" > %q\nprintf "\\nTUI_EXIT=%%s\\n" "$status"\n' "$dir/exit-code"
    } >"$dir/driver.sh"
    printf -v command 'bash %q; exec bash --noprofile --norc' "$dir/driver.sh"
    pane=$(tmux -L "$socket" -f /dev/null new-session -d -P -F '#{pane_id}' -s "$scenario" -x 100 -y 32 "$command")
    select_modules "$backend" "$expected"
    confirm_install "$backend" "$expected"
    wait_result "$backend"
    assert_screen '✓ 冒煙成功模組'
    if [ "$expected" -ne 0 ]; then
        assert_screen '重試失敗的模組'
        assert_screen '✗ 冒煙失敗模組'
    fi
    assert_screen '退出'
    choose_exit "$backend" "$expected"
    wait_screen "TUI_EXIT=$expected"
    [ "$(cat "$dir/exit-code")" = "$expected" ] || { echo '結束碼檔案與畫面不符。'; return 1; }
    # 專案複本位於暫存目錄；安裝程式必須直接使用複本裡的腳本，不可走 bootstrap 重新下載
    # 壓縮檔，否則這個測試驗證的會是遠端的版本而不是目前的程式碼。
    if grep -rqs '下載專案壓縮檔\|專案已解壓縮\|linux-setting-bootstrap' "$dir/logs"; then
        echo '安裝程式在本地專案上仍走了 bootstrap（下載壓縮檔）路徑。'
        return 1
    fi
    echo "通過 | $scenario | 使用本地腳本，未走 bootstrap 下載"
    dpkg-query -W -f='${Status}\n' "$package" | grep -q '^install ok installed$'
    echo "通過 | $scenario | 套件 $package 已安裝，結束碼 $expected"
    tmux -L "$socket" kill-session -t "$scenario"
}
for backend in "${backends[@]}"; do
    run_scenario "$backend" success
    run_scenario "$backend" failure
done
echo "TUI 冒煙測試：後端 ${backends[*]} 的成功與失敗情境全部通過。"
