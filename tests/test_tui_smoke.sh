#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ "$(uname -s)" != Linux ]; then
    echo '略過：TUI 冒煙測試需要 Linux。'
    [ "${CI:-false}" != true ]
    exit $?
fi
missing=()
for cmd in tmux whiptail; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if [ "${#missing[@]}" -gt 0 ]; then
    if [ "${CI:-false}" != true ]; then
        echo "略過：缺少 ${missing[*]}，請先用 apt 安裝。"
        exit 0
    fi
    echo "CI 安裝測試依賴：${missing[*]}"
    sudo apt-get update
    sudo apt-get install -y "${missing[@]}"
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
pick_package() {
    local pkg
    for pkg in tree sl toilet cowsay; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q '^install ok installed$'; then
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
run_scenario() {
    scenario="$1"
    local expected="$2" package dir command
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
        printf 'export TERM=xterm-256color LANG=C.UTF-8 LC_ALL=C.UTF-8 TUI_BACKEND=whiptail TUI_MODE=quiet NON_INTERACTIVE=false USE_TUI=auto\n'
        printf 'status=0\nbash ./install.sh || status=$?\nprintf "%%s\\n" "$status" > %q\nprintf "\\nTUI_EXIT=%%s\\n" "$status"\n' "$dir/exit-code"
    } >"$dir/driver.sh"
    printf -v command 'bash %q; exec bash --noprofile --norc' "$dir/driver.sh"
    pane=$(tmux -L "$socket" -f /dev/null new-session -d -P -F '#{pane_id}' -s "$scenario" -x 100 -y 32 "$command")
    wait_screen '模組選擇'
    assert_screen '冒煙成功模組'
    tmux -L "$socket" send-keys -t "$pane" Enter
    wait_screen '確認安裝'
    assert_screen '冒煙成功模組'
    tmux -L "$socket" send-keys -t "$pane" Enter
    wait_screen '安裝完成' 600 '✓ 冒煙成功模組' '退出'
    assert_screen '✓ 冒煙成功模組'
    if [ "$expected" -ne 0 ]; then
        assert_screen '重試失敗的模組'
        assert_screen '✗ 冒煙失敗模組'
    fi
    assert_screen '退出'
    # 結果選單的「退出」總是最後一列；End 選末列後 Enter。
    tmux -L "$socket" send-keys -t "$pane" End Enter
    wait_screen "TUI_EXIT=$expected"
    [ "$(cat "$dir/exit-code")" = "$expected" ] || { echo '結束碼檔案與畫面不符。'; return 1; }
    # 專案複本位於暫存目錄；安裝程式必須使用複本裡的腳本，不可再從遠端下載覆蓋，
    # 否則這個測試驗證的會是 $REPO_URL 上的版本而不是目前的程式碼。
    if grep -rqs '下載安裝腳本\|已下載 core/' "$dir/logs"; then
        echo '安裝程式在本地專案上仍走了遠端下載路徑。'
        return 1
    fi
    echo "通過 | $scenario | 使用本地腳本，未從遠端下載"
    dpkg-query -W -f='${Status}\n' "$package" | grep -q '^install ok installed$'
    echo "通過 | $scenario | 套件 $package 已安裝，結束碼 $expected"
    tmux -L "$socket" kill-session -t "$scenario"
}
run_scenario success 0
run_scenario failure 1
echo 'TUI 冒煙測試：成功與失敗情境全部通過。'
