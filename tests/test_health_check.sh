#!/usr/bin/env bash

# 使用真正的健康檢查入口；所有寫入與假指令均隔離在暫存目錄。
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_PASSED=0
TESTS_FAILED=0
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ls-health-test.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
log_pass() { printf '[PASS] %s\n' "$1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
log_fail() { printf '[FAIL] %s\n' "$1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }
mkdir -p "$WORK/bin" "$WORK/home"
for cmd in bash cat grep sed awk date mkdir dirname id; do
    target=$(command -v "$cmd") || exit 1
    ln -s "$target" "$WORK/bin/$cmd"
done
# full 保留對缺少配置檔的告警；先建立使用者配置，隔離缺工具的測試。
for config in .bashrc .zshrc .gitconfig; do : > "$WORK/home/$config"; done

run_health() {
    local mode="$1" expected="$2" label="$3" marker="${4:-}" out rc=0
    out=$(env -u BASH_ENV -u ENV -u SHELLOPTS -u BASHOPTS \
        HOME="$WORK/home" PATH="$WORK/bin" CONFIG_FILE="$WORK/no-config" \
        ENABLE_LOGGING=false COMMON_SH_LOADED=0 NON_INTERACTIVE=true \
        "$WORK/bin/bash" "$SCRIPT_DIR/scripts/maintenance/health_check.sh" "$mode" 2>&1) || rc=$?
    if [ "$rc" -eq "$expected" ] && \
       [[ "$out" != *'command not found'* ]] && \
       [[ "$out" != *'integer expected'* ]] && \
       [[ "$out" != *'integer expression expected'* ]] && \
       { [ -z "$marker" ] || [[ "$out" == *"$marker"* ]]; }; then
        log_pass "$label (rc=$rc)"
    else
        log_fail "$label (rc=${rc}，預期 $expected): $out"
    fi
}

# 此受限 PATH 在 Linux 與 macOS 都不提供任何資源、網路或服務工具。
for mode in quick resources network services tools config report; do
    run_health "$mode" 0 "受限 PATH：$mode 可完成"
done
if [ -r /etc/hosts ] && [ -r /etc/resolv.conf ]; then
    run_health full 0 '受限 PATH：full 可完成（含報告）'
else
    printf '[WARN] 略過 full 的 rc=0 斷言：主機缺少系統配置檔，原設計會回報配置告警；不計入通過\n'
fi
run_health monitor 0 '缺少 sleep：monitor 回報無法檢查並返回'

# 所有指令都不存在時也不應崩潰；bash 使用明確路徑執行。
mv "$WORK/bin" "$WORK/base-bin"
mkdir "$WORK/bin"
ln -s "$WORK/base-bin/bash" "$WORK/bin/bash"
run_health quick 0 '僅有 bash：quick 不因基本指令缺失而崩潰'
rm -rf "$WORK/bin"
mv "$WORK/base-bin" "$WORK/bin"

# 數據為空、多行、格式錯誤，以及沒有 systemd 的失敗路徑。
for cmd in top free df ip systemctl; do
    cat > "$WORK/bin/$cmd" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
    chmod +x "$WORK/bin/$cmd"
done
run_health quick 0 '觀測指令失敗：quick 不崩潰'
run_health services 0 'systemctl 存在但不可用：services 可完成'
cat > "$WORK/bin/top" <<'STUB'
#!/usr/bin/env bash
printf 'Cpu(s) 1\nCpu(s) 2\n'
STUB
cat > "$WORK/bin/free" <<'STUB'
#!/usr/bin/env bash
printf 'header\nMem: 0 0 0 0 0 0\n'
STUB
cat > "$WORK/bin/df" <<'STUB'
#!/usr/bin/env bash
printf 'Filesystem Size Used Avail Use%% Mounted\n/dev/test 1 1 0 invalid /\n'
STUB
run_health quick 0 '多行 CPU、零記憶體、非數字磁盤：不做無效數值比較'
cat > "$WORK/bin/ip" <<'STUB'
#!/usr/bin/env bash
printf '1: lo: state UNKNOWN\n'
STUB
run_health quick 2 '確實沒有活躍網絡接口：保留 critical 結束碼 2'
cat > "$WORK/bin/ip" <<'STUB'
#!/usr/bin/env bash
printf '1: eth0: state UP\n'
STUB
cat > "$WORK/bin/ping" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
chmod +x "$WORK/bin/ping"
run_health quick 2 'ping 確實無法連線：保留 critical 結束碼 2'
run_health full 2 'full 有實際連線故障：保留 critical 結束碼 2'
cat > "$WORK/bin/sleep" <<'STUB'
#!/usr/bin/env bash
printf "MONITOR_SLEEP_REACHED\n"
exit 1
STUB
chmod +x "$WORK/bin/sleep"
run_health monitor 0 'monitor 完成一輪嚴重告警，再由 sleep 假指令停止迴圈' MONITOR_SLEEP_REACHED
cat > "$WORK/bin/ping" <<'STUB'
#!/usr/bin/env bash
printf 'reply time=250.5 ms\n'
STUB
run_health quick 1 '真實延遲告警：保留 warning 結束碼 1'
run_health full 1 'full 有實際延遲告警：保留 warning 結束碼 1'
cat > "$WORK/bin/ping" <<'STUB'
#!/usr/bin/env bash
printf 'reply time=invalid ms\n'
STUB
run_health quick 0 '無法解析延遲：回報無法檢查並完成'

printf '\n通過: %s\n失敗: %s\n總計: %s\n' "$TESTS_PASSED" "$TESTS_FAILED" "$((TESTS_PASSED + TESTS_FAILED))"
[ "$TESTS_FAILED" -eq 0 ]
