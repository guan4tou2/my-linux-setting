#!/usr/bin/env bash

# ==============================================================================
# 行為測試：install.sh 的遠端安裝 bootstrap（下載整包壓縮檔）
# 只使用本機檔案與 127.0.0.1 的 http 伺服器，不連外；全部使用暫存 HOME 與 TMPDIR。
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_PASSED=0
TESTS_FAILED=0

pass() { echo "[PASS] $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
fail() { echo "[FAIL] $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }
log_warn() { echo "[WARN] $1"; }
contains() { printf '%s' "$1" | grep -Fq -- "$2"; }

finish() {
    echo
    echo "========================================"
    echo "測試結果"
    echo "========================================"
    echo "通過: $TESTS_PASSED"
    echo "失敗: $TESTS_FAILED"
    echo "總計: $((TESTS_PASSED + TESTS_FAILED))"
    [ "$TESTS_FAILED" -eq 0 ]
}

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    log_warn "install.sh 需要 Bash 4 以上，略過 bootstrap 行為測試（目前 $BASH_VERSION）"
    finish
    exit $?
fi
if ! command -v python3 >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
    log_warn "缺少 python3、curl 或 tar，略過 bootstrap 行為測試"
    finish
    exit $?
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/ls-bootstrap-test.XXXXXX")"
server_pid=""
cleanup() {
    if [ -n "$server_pid" ]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi
    rm -rf "$WORK"
}
trap cleanup EXIT

INSTALLER="$(cat "$SCRIPT_DIR/install.sh")"

# --- 測試用壓縮檔 ------------------------------------------------------------
WWW="$WORK/www"
STAGE="$WORK/stage"
mkdir -p "$WWW" "$STAGE/proj-main"
# 由目前工作樹打包（不依賴 git），模擬 GitHub archive 的單層頂層目錄
(cd "$SCRIPT_DIR" && tar -cf - --exclude=.git --exclude='*.db' --exclude=logs .) | tar -xf - -C "$STAGE/proj-main"
tar -czf "$WWW/good.tar.gz" -C "$STAGE" proj-main

# 缺少 module_manager.sh 的壓縮檔
mkdir -p "$WORK/stage2"
cp -R "$STAGE/proj-main" "$WORK/stage2/proj-main"
rm -f "$WORK/stage2/proj-main/scripts/core/module_manager.sh"
tar -czf "$WWW/incomplete.tar.gz" -C "$WORK/stage2" proj-main

# 惡意壓縮檔：含 ../ 的項目、指向絕對路徑的符號連結
python3 -I - "$WWW" <<'PY'
import io, sys, tarfile
www = sys.argv[1]
def add_file(t, name, data=b"x"):
    ti = tarfile.TarInfo(name); ti.size = len(data); t.addfile(ti, io.BytesIO(data))
with tarfile.open(www + "/traversal.tar.gz", "w:gz") as t:
    add_file(t, "proj-main/install.sh", b"#!/bin/sh\n")
    add_file(t, "proj-main/../escape.txt", b"pwned")
with tarfile.open(www + "/symlink.tar.gz", "w:gz") as t:
    add_file(t, "proj-main/install.sh", b"#!/bin/sh\n")
    ti = tarfile.TarInfo("proj-main/link"); ti.type = tarfile.SYMTYPE; ti.linkname = "/etc"; t.addfile(ti)
with tarfile.open(www + "/absolute.tar.gz", "w:gz") as t:
    add_file(t, "/tmp/ls-bootstrap-absolute.txt", b"pwned")
PY
echo "<html>not a tarball</html>" > "$WWW/notatar.tar.gz"

# --- 本機 HTTP 伺服器 ----------------------------------------------------------
python3 -u -m http.server 0 --bind 127.0.0.1 --directory "$WWW" >"$WORK/http.log" 2>&1 &
server_pid=$!
PORT=""
deadline=$((SECONDS + 30))
while [ "$SECONDS" -lt "$deadline" ]; do
    PORT="$(sed -n 's/.* port \([0-9][0-9]*\) .*/\1/p' "$WORK/http.log" | head -n 1)"
    if [ -n "$PORT" ] && curl -fsS "http://127.0.0.1:$PORT/good.tar.gz" -o /dev/null 2>/dev/null; then break; fi
    PORT=""
    sleep 0.2
done
if [ -z "$PORT" ]; then
    fail "本機 HTTP 伺服器啟動失敗"
    finish
    exit $?
fi
BASE="http://127.0.0.1:$PORT"

# --- 工具函式 ------------------------------------------------------------------
fn_src() { # 從 install.sh 取出頂層函式
    awk -v n="$1" 'index($0, n "() {") == 1 {p = 1} p {print} p && /^}/ {p = 0}' "$SCRIPT_DIR/install.sh"
}
RESOLVE_FNS="$(for f in bootstrap_status _download_url_allowed _bootstrap_valid_repo _bootstrap_valid_ref bootstrap_resolve_archive_url; do fn_src "$f"; done)"

# resolve <KEY=VALUE...>：以乾淨環境執行網址解析，輸出 "rc|網址|訊息"
resolve() {
    env -i PATH="$PATH" "$@" bash -c "$RESOLVE_FNS"$'\n''bootstrap_resolve_archive_url; rc=$?; printf "%s|%s\n" "$rc" "$BOOTSTRAP_ARCHIVE_URL"' 2>&1
}

new_home() { mktemp -d "$WORK/home.XXXXXX"; }
new_tmp() { mktemp -d "$WORK/tmp.XXXXXX"; }
leftovers() { find "$1" -maxdepth 1 -name 'linux-setting-bootstrap.*' 2>/dev/null | head -n 1; }

# bs_run <工作目錄> <TMPDIR> <環境變數...> -- <install.sh 參數...>；以 bash -c 形式執行
bs_run() {
    local cwd="$1" tmp="$2"
    shift 2
    local envs=()
    while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
    shift
    (cd "$cwd" && env -u NON_INTERACTIVE -u CI -u TUI_MODE -u USE_TUI HOME="$(new_home)" TMPDIR="$tmp" "${envs[@]}" bash -c "$INSTALLER" -- "$@" 2>&1)
}

# ------------------------------------------------------------------------------
echo "== 壓縮檔網址組成 =="

test_url_resolution() {
    local out
    out="$(resolve)"
    [ "$out" = "0|https://github.com/guan4tou2/my-linux-setting/archive/main.tar.gz" ] \
        && pass "預設值為本專案 main 分支的 GitHub archive" || fail "預設網址不正確：$out"
    out="$(resolve LINUX_SETTING_REPO=foo/bar LINUX_SETTING_REF=v1.2.3)"
    [ "$out" = "0|https://github.com/foo/bar/archive/v1.2.3.tar.gz" ] \
        && pass "LINUX_SETTING_REPO／REF 組成網址" || fail "REPO／REF 網址不正確：$out"
    out="$(resolve LINUX_SETTING_REF=feature/x-1.0)"
    [ "$out" = "0|https://github.com/guan4tou2/my-linux-setting/archive/feature/x-1.0.tar.gz" ] \
        && pass "只設 REF 時沿用預設 repo，REF 可含 /" || fail "只設 REF 的網址不正確：$out"
    out="$(resolve LINUX_SETTING_ARCHIVE_URL=https://example.com/a.tar.gz LINUX_SETTING_REPO=foo/bar LINUX_SETTING_REF=x)"
    [ "$out" = "0|https://example.com/a.tar.gz" ] \
        && pass "LINUX_SETTING_ARCHIVE_URL 優先於 REPO／REF" || fail "ARCHIVE_URL 應優先：$out"
    out="$(resolve LINUX_SETTING_ARCHIVE_URL=http://127.0.0.1:9/a.tar.gz)"
    [ "$out" = "0|http://127.0.0.1:9/a.tar.gz" ] \
        && pass "loopback 的 http 壓縮檔網址可用（測試用）" || fail "loopback http 應允許：$out"

    out="$(resolve REPO_URL=https://raw.githubusercontent.com/foo/bar/dev)"
    if contains "$out" "0|https://github.com/foo/bar/archive/dev.tar.gz" && contains "$out" "REPO_URL 已被"; then
        pass "舊 REPO_URL 解析出 repo 與 ref 並提示改用新變數"
    else
        fail "舊 REPO_URL 相容解析不正確：$out"
    fi
    out="$(resolve REPO_URL=https://raw.githubusercontent.com/foo/bar/main/)"
    contains "$out" "0|https://github.com/foo/bar/archive/main.tar.gz" \
        && pass "舊 REPO_URL 結尾的 / 可容忍" || fail "舊 REPO_URL 結尾 / 解析失敗：$out"
    out="$(resolve REPO_URL=https://raw.githubusercontent.com/foo/bar/dev LINUX_SETTING_REF=v2)"
    [ "$out" = "0|https://github.com/guan4tou2/my-linux-setting/archive/v2.tar.gz" ] \
        && pass "設了新變數時忽略舊 REPO_URL" || fail "新變數應使舊 REPO_URL 失效：$out"
    out="$(resolve REPO_URL=https://example.com/raw/main)"
    if contains "$out" "LINUX_SETTING_ARCHIVE_URL" && ! contains "$out" "0|https"; then
        pass "不相容的 REPO_URL 印出錯誤並說明改用 LINUX_SETTING_ARCHIVE_URL"
    else
        fail "不相容的 REPO_URL 應被拒絕：$out"
    fi

    local repo
    for repo in foo foo/bar/baz ../x/y a/.. "foo/b ar" 'foo/bar;x' '/foo/bar' 'foo/$(id)'; do
        out="$(resolve "LINUX_SETTING_REPO=$repo")"
        if contains "$out" "LINUX_SETTING_REPO 格式不正確" && ! contains "$out" "0|https"; then
            pass "拒絕不合法的 repo：$repo"
        else
            fail "應拒絕 repo：$repo（$out）"
        fi
    done
    local ref
    for ref in ../main a/../b "a b" -x 'a;b' 'main$(id)' a//b a/ '/abs'; do
        out="$(resolve "LINUX_SETTING_REF=$ref")"
        if contains "$out" "LINUX_SETTING_REF 格式不正確" && ! contains "$out" "0|https"; then
            pass "拒絕不合法的 ref：$ref"
        else
            fail "應拒絕 ref：$ref（$out）"
        fi
    done

    for url in http://example.com/a.tar.gz http://localhost@evil.example/a.tar.gz http://127.0.0.1.evil.example/a ftp://localhost/a file:///etc/passwd; do
        out="$(resolve "LINUX_SETTING_ARCHIVE_URL=$url")"
        if contains "$out" "必須是 https://" && ! contains "$out" "0|"; then
            pass "拒絕壓縮檔網址：$url"
        else
            fail "應拒絕壓縮檔網址：$url（$out）"
        fi
    done
}
test_url_resolution

# ------------------------------------------------------------------------------
echo
echo "== 壓縮檔處理 =="

test_good_archive_and_sha() {
    local tmp out rc=0 sum
    tmp="$(new_tmp)"
    sum="$(sha256sum "$WWW/good.tar.gz" | awk '{print $1}')"
    out="$(bs_run "$WORK" "$tmp" "LINUX_SETTING_ARCHIVE_URL=$BASE/good.tar.gz" "LINUX_SETTING_ARCHIVE_SHA256=$sum" -- --dry-run --non-interactive </dev/null)" || rc=$?
    [ "$rc" -eq 0 ] && contains "$out" "預覽模式" && pass "SHA-256 相符時可正常 bootstrap（結束碼 0）" || { fail "SHA-256 相符應成功（rc=$rc）"; echo "$out" | tail -n 8; }
    [ -z "$(leftovers "$tmp")" ] && pass "成功結束後 bootstrap 暫存目錄已清除" || fail "bootstrap 暫存目錄殘留"

    tmp="$(new_tmp)"
    rc=0
    out="$(bs_run "$WORK" "$tmp" "LINUX_SETTING_ARCHIVE_URL=$BASE/good.tar.gz" "LINUX_SETTING_ARCHIVE_SHA256=$(printf '%064d' 0)" -- --dry-run --non-interactive </dev/null)" || rc=$?
    if [ "$rc" -ne 0 ] && contains "$out" "SHA-256 不符" && [ -z "$(leftovers "$tmp")" ] && ! contains "$out" "預覽模式"; then
        pass "SHA-256 不符時中止並清除暫存目錄"
    else
        fail "SHA-256 不符應中止（rc=$rc）"
    fi

    tmp="$(new_tmp)"
    rc=0
    out="$(bs_run "$WORK" "$tmp" "LINUX_SETTING_ARCHIVE_URL=$BASE/good.tar.gz" "LINUX_SETTING_ARCHIVE_SHA256=abc" -- --dry-run --non-interactive </dev/null)" || rc=$?
    [ "$rc" -ne 0 ] && contains "$out" "64 個十六進位字元" && [ -z "$(leftovers "$tmp")" ] \
        && pass "SHA-256 格式不正確時中止" || fail "SHA-256 格式不正確應中止（rc=$rc）"
}
test_good_archive_and_sha

test_bad_archives() {
    local name want tmp out rc
    for spec in "traversal:不安全的路徑" "absolute:不安全的路徑" "symlink:指向外部的連結" "incomplete:缺少：scripts/core/module_manager.sh" "notatar:無法讀取壓縮檔"; do
        name="${spec%%:*}"
        want="${spec#*:}"
        tmp="$(new_tmp)"
        rc=0
        out="$(bs_run "$WORK" "$tmp" "LINUX_SETTING_ARCHIVE_URL=$BASE/$name.tar.gz" -- --dry-run --non-interactive </dev/null)" || rc=$?
        if [ "$rc" -ne 0 ] && contains "$out" "$want" && [ -z "$(leftovers "$tmp")" ]; then
            pass "拒絕壓縮檔 $name 並清除暫存目錄"
        else
            fail "壓縮檔 $name 應被拒絕（rc=$rc）"
            echo "$out" | tail -n 5
        fi
    done
    [ ! -e "$WORK/escape.txt" ] && [ ! -e /tmp/ls-bootstrap-absolute.txt ] \
        && pass "惡意壓縮檔沒有在目標之外寫入任何檔案" || fail "惡意壓縮檔寫出了檔案"
}
test_bad_archives

test_download_failure() {
    local tmp out rc=0
    tmp="$(new_tmp)"
    out="$(bs_run "$WORK" "$tmp" "LINUX_SETTING_ARCHIVE_URL=$BASE/missing.tar.gz" -- --dry-run --non-interactive </dev/null)" || rc=$?
    [ "$rc" -ne 0 ] && contains "$out" "下載壓縮檔失敗" && [ -z "$(leftovers "$tmp")" ] \
        && pass "下載失敗（404）時以非 0 結束並清除暫存目錄" || fail "404 應失敗並清理（rc=$rc）"
    tmp="$(new_tmp)"
    rc=0
    out="$(bs_run "$WORK" "$tmp" "LINUX_SETTING_ARCHIVE_URL=http://127.0.0.1:1/x.tar.gz" -- --dry-run --non-interactive </dev/null)" || rc=$?
    [ "$rc" -ne 0 ] && contains "$out" "下載壓縮檔失敗" && [ -z "$(leftovers "$tmp")" ] \
        && pass "連線被拒時以非 0 結束並清除暫存目錄" || fail "連線失敗應中止並清理（rc=$rc）"
}
test_download_failure

# ------------------------------------------------------------------------------
echo
echo "== 目前目錄不可被信任 =="

test_cwd_not_trusted() {
    local evil="$WORK/evil" tmp out rc=0
    mkdir -p "$evil/scripts/core" "$evil/config"
    printf '#!/usr/bin/env bash\ntouch %q\necho PWNED-COMMON\n' "$WORK/pwned-common" > "$evil/scripts/core/common.sh"
    printf '[evil]\nname=PWNED-MODULE\nscript=%q\n' "$WORK/pwned-module" > "$evil/config/modules.conf"
    cp "$evil/scripts/core/common.sh" "$evil/scripts/core/module_manager.sh"
    tmp="$(new_tmp)"
    out="$(bs_run "$evil" "$tmp" "LINUX_SETTING_ARCHIVE_URL=$BASE/good.tar.gz" -- --dry-run --non-interactive </dev/null)" || rc=$?
    if [ "$rc" -eq 0 ] && [ ! -e "$WORK/pwned-common" ] && ! contains "$out" "PWNED"; then
        pass "目前目錄內的惡意 common.sh／modules.conf 沒有被載入或執行"
    else
        fail "目前目錄的檔案被信任了（rc=$rc）"
    fi
    # 來源下載失敗時也不可退而使用目前目錄
    tmp="$(new_tmp)"
    rc=0
    out="$(bs_run "$evil" "$tmp" "LINUX_SETTING_ARCHIVE_URL=$BASE/missing.tar.gz" -- --dry-run --non-interactive </dev/null)" || rc=$?
    [ "$rc" -ne 0 ] && [ ! -e "$WORK/pwned-common" ] && ! contains "$out" "PWNED" \
        && pass "下載失敗時不會退而載入目前目錄的檔案" || fail "下載失敗時不應使用目前目錄（rc=$rc）"
}
test_cwd_not_trusted

# ------------------------------------------------------------------------------
echo
echo "== bootstrap 與本地執行一致 =="

modules_of() { printf '%s\n' "$1" | sed 's/\x1b\[[0-9;]*m//g' | grep -E '^\[[a-z_]+\]|^將安裝以下' ; }

test_bootstrap_parity() {
    local tmp out_bs out_local rc=0 rc_local=0
    tmp="$(new_tmp)"
    out_bs="$(bs_run "$WORK" "$tmp" "LINUX_SETTING_ARCHIVE_URL=$BASE/good.tar.gz" -- --dry-run --non-interactive </dev/null)" || rc=$?
    out_local="$(cd "$WORK" && env -u NON_INTERACTIVE -u CI HOME="$(new_home)" TMPDIR="$(new_tmp)" bash "$SCRIPT_DIR/install.sh" --dry-run --non-interactive </dev/null 2>&1)" || rc_local=$?
    if [ "$rc" -eq 0 ] && [ "$rc_local" -eq 0 ] && [ -n "$(modules_of "$out_bs")" ] \
       && [ "$(modules_of "$out_bs")" = "$(modules_of "$out_local")" ]; then
        pass "bootstrap 的 --dry-run 模組清單與從專案直接執行一致"
    else
        fail "bootstrap 與本地的模組清單不一致（rc=$rc／$rc_local）"
    fi
    [ -z "$(leftovers "$tmp")" ] && pass "bootstrap 後暫存目錄已清除" || fail "bootstrap 暫存目錄殘留"

    # stdin 與參數原樣傳給子程序：管線輸入選第 1 個模組後預覽
    tmp="$(new_tmp)"
    rc=0
    out_bs="$(printf '1\ni\nq\n' | bs_run "$WORK" "$tmp" "LINUX_SETTING_ARCHIVE_URL=$BASE/good.tar.gz" TUI_MODE=quiet -- --dry-run)" || rc=$?
    if [ "$rc" -eq 0 ] && contains "$out_bs" "預覽模式" && contains "$out_bs" "將安裝以下 1 個模組"; then
        pass "管線 stdin 與參數有傳給 exec 後的子程序"
    else
        fail "stdin／參數未正確傳遞（rc=$rc）"
        echo "$out_bs" | tail -n 8
    fi
    [ -z "$(leftovers "$tmp")" ] && pass "互動選單流程結束後暫存目錄已清除" || fail "互動流程後暫存目錄殘留"
}
test_bootstrap_parity

test_bootstrap_dir_guard() {
    # 環境變數指向不符合樣式的目錄時，絕不可被刪除
    local victim="$WORK/victim" out rc=0
    mkdir -p "$victim"
    touch "$victim/keep"
    out="$(cd "$WORK" && env HOME="$(new_home)" LINUX_SETTING_BOOTSTRAP_DIR="$victim" bash "$SCRIPT_DIR/install.sh" --dry-run --non-interactive </dev/null 2>&1)" || rc=$?
    [ "$rc" -eq 0 ] && [ -e "$victim/keep" ] \
        && pass "LINUX_SETTING_BOOTSTRAP_DIR 指向任意目錄時不會被清除" || fail "任意目錄被清除或安裝失敗（rc=$rc）"
    # 已 bootstrap 過、但找不到完整專案：不可再次下載
    rc=0
    mkdir -p "$WORK/linux-setting-bootstrap.AbCdEf"
    out="$(cd "$WORK" && env HOME="$(new_home)" LINUX_SETTING_BOOTSTRAP_DIR="$WORK/linux-setting-bootstrap.AbCdEf" LINUX_SETTING_ARCHIVE_URL="$BASE/good.tar.gz" bash -c "$INSTALLER" -- --dry-run --non-interactive </dev/null 2>&1)" || rc=$?
    [ "$rc" -ne 0 ] && contains "$out" "不完整" && [ ! -e "$WORK/linux-setting-bootstrap.AbCdEf" ] \
        && pass "子程序不會再次 bootstrap，並清掉自己的暫存目錄" || fail "不可再次 bootstrap（rc=$rc）"
}
test_bootstrap_dir_guard

finish
