#!/usr/bin/env bash
# Docker 模組安裝測試（需在 Linux 容器內執行）：
# 以純文字選單安裝 Docker 模組，確認報告顯示成功、docker 與 lazydocker 可執行，
# 且安裝後 apt-get update 仍成功（沒有留下壞掉的 apt 來源）。
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ "$(uname -s)" != Linux ]; then
    echo '略過：Docker 模組測試會實際安裝套件，只能在 Linux 容器內執行。'
    exit 0
fi

work=$(mktemp -d)
log="$work/install.out"
cleanup() {
    local status=$?
    if [ "$status" -ne 0 ]; then
        echo "Docker 模組測試失敗；結束碼：$status" >&2
        if [ -f "$log" ]; then
            echo '=== 安裝輸出（尾端）===' >&2
            tail -n 60 "$log" >&2
        fi
        while IFS= read -r -d '' f; do
            echo "=== $f（尾端）===" >&2
            tail -n 60 "$f" >&2
        done < <(find "$work/logs" -type f -name '*.log' -print0 2>/dev/null)
    fi
    rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# 所有修改只發生在複本與暫存 HOME，原專案不變。
cp -R "$REPO_ROOT" "$work/project"
mkdir -p "$work/home" "$work/logs"

echo '安裝 Docker 模組（純文字選單：第 2 個模組，i 開始安裝）...'
rc=0
(
    cd "$work/project"
    export HOME="$work/home" LOG_DIR="$work/logs"
    export TUI_MODE=quiet NON_INTERACTIVE=false USE_TUI=false
    printf '2\ni\n' | bash ./install.sh
) >"$log" 2>&1 || rc=$?

if [ "$rc" -ne 0 ]; then
    echo "安裝程式結束碼應為 0，實際為 $rc" >&2
    exit 1
fi
echo '通過 | 安裝程式結束碼 0'

if ! grep -Fq '全部 1 個模組安裝成功' "$log"; then
    echo '報告沒有顯示「全部 1 個模組安裝成功」' >&2
    exit 1
fi
echo '通過 | 報告顯示 Docker 模組安裝成功'

# Linux 容器沒有 systemd，daemon 不會啟動；只確認指令可執行，不檢查 docker info。
bash "$work/project/tests/verify_install.sh" docker

# 安裝失敗時若留下壞掉的 apt 來源，之後每次 apt-get update 都會報錯。
if ! apt_out=$(sudo apt-get update -o APT::Update::Error-Mode=any 2>&1); then
    echo 'apt-get update 在安裝後失敗（可能留下壞掉的來源）：' >&2
    printf '%s\n' "$apt_out" | tail -n 20 >&2
    exit 1
fi
echo '通過 | 安裝後 apt-get update 仍然成功'
echo 'Docker 模組測試：全部通過。'
