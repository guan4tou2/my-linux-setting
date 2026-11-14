#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ "$(uname -s)" != Linux ]; then
    echo '錯誤：遠端安裝模擬必須在 Linux 測試容器內執行。' >&2
    exit 1
fi
work=$(mktemp -d)
server_pid=''
cleanup() {
    local status=$?
    if [ "$status" -ne 0 ]; then
        echo "遠端安裝驗證失敗，結束碼：$status" >&2
        for log in "$work/http.log" "$work/install.log" "$HOME"/.local/log/linux-setting/install_*.log; do
            [ ! -f "$log" ] || { echo "=== $log（尾端）==="; tail -n 80 "$log"; }
        done
    fi
    if [ -n "$server_pid" ]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi
    rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# 使用標準庫 CLI 的埠 0，由作業系統分配埠，避免先探測後綁定的競爭。
python3 -u -m http.server "${LOCAL_HTTP_PORT:-0}" --bind 127.0.0.1 --directory "$REPO_ROOT" >"$work/http.log" 2>&1 &
server_pid=$!
deadline=$((SECONDS + 30))
url=''
while [ "$SECONDS" -lt "$deadline" ]; do
    port=$(sed -n 's/.* port \([0-9][0-9]*\) .*/\1/p' "$work/http.log" | head -n 1)
    if [ -n "$port" ] && curl -fsS "http://127.0.0.1:$port/" >/dev/null 2>&1; then
        url="http://127.0.0.1:$port"
        break
    fi
    kill -0 "$server_pid" 2>/dev/null || { echo 'HTTP 伺服器啟動失敗。'; exit 1; }
    sleep 0.2
done
[ -n "$url" ] || { echo '等待 HTTP 伺服器逾時。'; exit 1; }
mkdir "$work/empty"
cd "$work/empty"
installer=$(curl -fsSL "$url/install.sh")
status=0
printf '1 3 4 5 6\ni\n' | REPO_URL="$url" TUI_MODE=quiet bash -c "$installer" >"$work/install.log" 2>&1 || status=$?
cat "$work/install.log"
[ "$status" -eq 0 ] || { echo "安裝程式結束碼：$status"; exit "$status"; }
missing=0
for path in install.sh scripts/core/common.sh scripts/core/module_manager.sh config/modules.conf \
    scripts/core/python_setup.sh scripts/core/base_tools.sh scripts/core/terminal_setup.sh \
    scripts/core/dev_tools.sh scripts/core/monitoring_tools.sh; do
    if grep -Fq "\"GET /$path HTTP/1.1\" 200" "$work/http.log"; then
        echo "通過 | 遠端 GET /$path"
    else
        echo "缺少 | 遠端 GET /$path"
        missing=$((missing + 1))
    fi
done
[ ! -e "$work/empty/scripts" ] || { echo '空目錄出現 scripts/，無法證明遠端載入。'; exit 1; }
echo '通過 | 空目錄沒有 scripts/'
[ "$missing" -eq 0 ] || exit 1
bash "$REPO_ROOT/tests/verify_install.sh" python base terminal dev monitoring
echo '遠端安裝與成果驗證全部通過。'
