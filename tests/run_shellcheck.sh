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
# 除了已加入版控的檔案，也涵蓋「尚未提交但沒有被 .gitignore 忽略」的新腳本，
# 否則新檔案在提交前永遠不會被檢查到，本機顯示 0 個警告而 CI 卻失敗。
while IFS= read -r -d '' file; do
    if [ -f "$file" ]; then files+=("$file"); fi
done < <(git ls-files -z --cached --others --exclude-standard -- '*.sh')
if [ "${#files[@]}" -eq 0 ]; then echo '沒有受版控的 Bash 腳本。'; exit 0; fi
report=$(mktemp)
trap 'rm -f "$report"' EXIT
status=0
shellcheck -S warning -f gcc -- "${files[@]}" >"$report" 2>&1 || status=$?
# 警告等級門檻：warning/error 都列出完整位置與 SC 編號，並使檢查失敗。
awk '/: error: / {print; errors++} /: warning: / {print; file=$0; sub(/:[0-9]+:[0-9]+: warning:.*/, "", file); counts[file]++; warnings++}
END {print "警告摘要（各檔案筆數）："; for (file in counts) printf "%s: %d\n", file, counts[file]; printf "錯誤總數：%d；警告總數：%d\n", errors, warnings}' "$report"
if [ "$status" -gt 1 ]; then
    echo "shellcheck 執行失敗，結束碼：$status" >&2
    cat "$report" >&2
    exit 1
fi
if grep -Eq ': (error|warning): ' "$report"; then exit 1; fi
if [ "$status" -ne 0 ] && ! grep -q ': warning: ' "$report"; then
    cat "$report" >&2
    exit 1
fi
