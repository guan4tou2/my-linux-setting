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
# 網站根目錄只放兩個檔案：install.sh（目前工作樹）與 repo.tar.gz（由目前工作樹打包，
# 頂層一層目錄，模擬 GitHub archive；不依賴 git，排除 .git 與大型本機檔案）
mkdir -p "$work/www" "$work/stage/my-linux-setting-main"
cp "$REPO_ROOT/install.sh" "$work/www/install.sh"
(cd "$REPO_ROOT" && tar -cf - --exclude=.git --exclude='*.db' --exclude='*.log' --exclude=logs .) \
    | tar -xf - -C "$work/stage/my-linux-setting-main"
tar -czf "$work/www/repo.tar.gz" -C "$work/stage" my-linux-setting-main
# 使用標準庫 CLI 的埠 0，由作業系統分配埠，避免先探測後綁定的競爭。
python3 -u -m http.server "${LOCAL_HTTP_PORT:-0}" --bind 127.0.0.1 --directory "$work/www" >"$work/http.log" 2>&1 &
server_pid=$!
deadline=$((SECONDS + 30))
url=''
while [ "$SECONDS" -lt "$deadline" ]; do
    port=$(sed -n 's/.* port \([0-9][0-9]*\) .*/\1/p' "$work/http.log" | head -n 1)
    if [ -n "$port" ] && curl -fsS "http://127.0.0.1:$port/install.sh" >/dev/null 2>&1; then
        url="http://127.0.0.1:$port"
        break
    fi
    kill -0 "$server_pid" 2>/dev/null || { echo 'HTTP 伺服器啟動失敗。'; exit 1; }
    sleep 0.2
done
[ -n "$url" ] || { echo '等待 HTTP 伺服器逾時。'; exit 1; }
mkdir "$work/empty" "$work/tmp"
cd "$work/empty"
installer=$(curl -fsSL "$url/install.sh")
status=0
printf '1 3 4 5 6\ni\n' | TMPDIR="$work/tmp" LINUX_SETTING_ARCHIVE_URL="$url/repo.tar.gz" TUI_MODE=quiet bash -c "$installer" >"$work/install.log" 2>&1 || status=$?
cat "$work/install.log"
[ "$status" -eq 0 ] || { echo "安裝程式結束碼：$status"; exit "$status"; }
# 伺服器紀錄只能有 /install.sh（上面取得安裝腳本的兩次，含探測）與 /repo.tar.gz 的 GET，沒有逐檔下載
bad=$(grep -F '"GET ' "$work/http.log" | grep -vF '"GET /install.sh HTTP' | grep -vF '"GET /repo.tar.gz HTTP' || true)
if [ -n "$bad" ]; then
    echo '伺服器紀錄出現預期以外的請求（疑似逐檔下載）：'
    echo "$bad"
    exit 1
fi
grep -Fq '"GET /repo.tar.gz HTTP/1.1" 200' "$work/http.log" || { echo '缺少 GET /repo.tar.gz'; exit 1; }
echo '通過 | 伺服器只收到 /install.sh 與 /repo.tar.gz 的 GET'
[ ! -e "$work/empty/scripts" ] || { echo '空目錄出現 scripts/，無法證明遠端載入。'; exit 1; }
echo '通過 | 空目錄沒有 scripts/'
leftover=$(find "$work/tmp" -maxdepth 1 -name 'linux-setting-bootstrap.*' | head -n 1)
[ -z "$leftover" ] || { echo "bootstrap 暫存目錄未清除：$leftover"; exit 1; }
echo '通過 | bootstrap 暫存目錄已清除'
uninstaller="${XDG_CONFIG_HOME:-$HOME/.config}/linux-setting/uninstall.sh"
[ -x "$uninstaller" ] || { echo "缺少可執行的卸載腳本：$uninstaller"; exit 1; }
echo "通過 | 已保存卸載腳本 $uninstaller"
bash "$REPO_ROOT/tests/verify_install.sh" python base terminal dev monitoring
echo '遠端安裝與成果驗證全部通過。'
