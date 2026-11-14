#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v shellcheck >/dev/null 2>&1; then
    if [ "${CI:-false}" = true ]; then
        echo '錯誤：CI 找不到 shellcheck。' >&2
        exit 1
    fi
    echo '略過：找不到 shellcheck，請先安裝後再執行。'
    exit 0
fi
files=()
while IFS= read -r -d '' file; do files+=("$file"); done < <(git ls-files -z -- '*.sh')
if [ "${#files[@]}" -eq 0 ]; then echo '沒有受版控的 Bash 腳本。'; exit 0; fi
report=$(mktemp)
trap 'rm -f "$report"' EXIT
status=0
shellcheck -S warning -f gcc -- "${files[@]}" >"$report" 2>&1 || status=$?
# gcc 格式保留完整檔案位置及 SC 編號；每個診斷一行。
awk '/: error: / {print; errors++} /: warning: / {file=$0; sub(/:[0-9]+:[0-9]+: warning:.*/, "", file); counts[file]++; warnings++}
END {print "警告摘要（各檔案筆數）："; for (file in counts) printf "%s: %d\n", file, counts[file]; printf "錯誤總數：%d；警告總數：%d\n", errors, warnings}' "$report"
if [ "$status" -gt 1 ]; then
    echo "shellcheck 執行失敗，結束碼：$status" >&2
    cat "$report" >&2
    exit 1
fi
if grep -q ': error: ' "$report"; then exit 1; fi
if [ "$status" -ne 0 ] && ! grep -q ': warning: ' "$report"; then
    cat "$report" >&2
    exit 1
fi
