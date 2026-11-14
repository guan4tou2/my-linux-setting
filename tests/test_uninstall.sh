#!/usr/bin/env bash

# ==============================================================================
# 行為測試：uninstall.sh、install.sh --rollback、安裝清單、下載與設定檔加固
# 全部使用暫存 HOME；套件管理器與 sudo 以 PATH 上的假指令取代，不會動到系統。
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_PASSED=0
TESTS_FAILED=0
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ls-uninstall-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

pass() { echo "[PASS] $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
fail() { echo "[FAIL] $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }
check() { # check <說明> <命令...>
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi
}
contains() { printf '%s' "$1" | grep -Fq -- "$2"; }

new_home() {
    local h
    h="$(mktemp -d "$WORK/home.XXXXXX")"
    mkdir -p "$h/.config"
    printf '%s' "$h"
}

# 在暫存 HOME 下執行 uninstall.sh（不繼承 XDG_CONFIG_HOME / NON_INTERACTIVE）
run_uninstall() {
    local h="$1"
    shift
    env -u XDG_CONFIG_HOME -u NON_INTERACTIVE HOME="$h" bash "$SCRIPT_DIR/uninstall.sh" "$@" </dev/null 2>&1
}

write_manifest() { # write_manifest <home>，內容從 stdin
    mkdir -p "$1/.config/linux-setting"
    cat > "$1/.config/linux-setting/installed.manifest"
}

# ------------------------------------------------------------------------------
echo "== uninstall.sh =="

test_uninstall_no_manifest() {
    local h out rc=0
    h="$(new_home)"
    out="$(run_uninstall "$h" -y)" || rc=$?
    if [ "$rc" -ne 0 ] && contains "$out" "未找到安裝記錄"; then
        pass "沒有安裝清單時友善提示並以非 0 結束"
    else
        fail "沒有安裝清單時應以非 0 結束（rc=$rc）"
    fi
}

test_uninstall_dry_run() {
    local h out rc=0 bk
    h="$(new_home)"
    mkdir -p "$h/.local/bin" "$h/bk/20240101_000000"
    : > "$h/.local/bin/lsd"
    bk="$h/.config/linux-setting-backup/20240101_000000"
    mkdir -p "$bk"
    echo original > "$bk/.zshrc"
    echo modified > "$h/.zshrc"
    write_manifest "$h" <<EOF
package:htop
path:$h/.local/bin/lsd
path:/etc/passwd
path:/etc/apt/apt.conf.d/99-timeout
path:/etc/apt/apt.conf.d/evil
file:$h/.zshrc
backup:$bk
EOF
    out="$(run_uninstall "$h" --dry-run)" || rc=$?
    [ "$rc" -eq 0 ] && pass "--dry-run 結束碼為 0" || fail "--dry-run 結束碼應為 0（rc=$rc）"
    contains "$out" "$h/.local/bin/lsd" && pass "--dry-run 列出將移除的路徑" || fail "--dry-run 未列出路徑"
    contains "$out" "$h/.zshrc  <-  $bk/.zshrc" && pass "--dry-run 列出設定檔與備份來源" || fail "--dry-run 未列出設定檔還原來源"
    contains "$out" "htop" && pass "--dry-run 列出將移除的套件" || fail "--dry-run 未列出套件"
    contains "$out" "拒絕移除 /etc/passwd" && pass "--dry-run 對 \$HOME 之外的路徑警告" || fail "--dry-run 未拒絕 /etc/passwd"
    contains "$out" "拒絕移除 /etc/apt/apt.conf.d/evil" && pass "/etc/apt/apt.conf.d/ 下非指定檔名被拒絕" || fail "未拒絕 /etc/apt/apt.conf.d/evil"
    contains "$out" "/etc/apt/apt.conf.d/99-timeout" && ! contains "$out" "拒絕移除 /etc/apt/apt.conf.d/99-timeout" \
        && pass "APT 優化的 99-timeout 允許移除" || fail "99-timeout 應被允許"
    if [ -e "$h/.local/bin/lsd" ] && [ "$(cat "$h/.zshrc")" = modified ] \
       && [ -f "$h/.config/linux-setting/installed.manifest" ]; then
        pass "--dry-run 不變更任何東西"
    else
        fail "--dry-run 不應變更任何東西"
    fi
}

test_uninstall_requires_yes_when_non_interactive() {
    local h out rc=0
    h="$(new_home)"
    : > "$h/victim"
    write_manifest "$h" <<EOF
path:$h/victim
EOF
    out="$(run_uninstall "$h")" || rc=$?
    if [ "$rc" -ne 0 ] && [ -e "$h/victim" ] && contains "$out" "未指定 -y"; then
        pass "非互動且沒有 -y 時拒絕執行"
    else
        fail "非互動且沒有 -y 應拒絕（rc=$rc）"
    fi
    rc=0
    out="$(NON_INTERACTIVE=true run_uninstall "$h")" || rc=$?
    if [ "$rc" -ne 0 ] && [ -e "$h/victim" ]; then
        pass "NON_INTERACTIVE=true 且沒有 -y 時拒絕執行"
    else
        fail "NON_INTERACTIVE=true 且沒有 -y 應拒絕"
    fi
}

test_uninstall_rejects_paths_outside_home() {
    local h outside rc=0 out
    h="$(new_home)"
    outside="$(mktemp -d "$WORK/outside.XXXXXX")"
    : > "$outside/victim"
    : > "$h/mine"
    ln -s "$outside" "$h/linkdir"
    : > "$outside/target"
    ln -s "$outside/target" "$h/lnk"
    write_manifest "$h" <<EOF
path:$outside/victim
path:$h/../$(basename "$outside")/victim
path:$h/linkdir/victim
path:relative/path
path:$h
path:$h/mine
path:$h/lnk
EOF
    out="$(run_uninstall "$h" -y)" || rc=$?
    [ -e "$outside/victim" ] && pass "拒絕刪除 \$HOME 之外的路徑（含 .. 與經符號連結的父目錄）" || fail "\$HOME 之外的檔案被刪除了"
    [ ! -e "$h/mine" ] && pass "\$HOME 之下的路徑被移除" || fail "\$HOME 之下的路徑未被移除"
    if [ ! -L "$h/lnk" ] && [ -e "$outside/target" ]; then
        pass "符號連結只移除連結本身，不追蹤到目標"
    else
        fail "符號連結的處理不正確"
    fi
    [ -d "$h" ] && pass "\$HOME 本身不會被移除" || fail "\$HOME 被移除了"
}

test_uninstall_restores_earliest_backup() {
    local h out rc=0 root b1 b2
    h="$(new_home)"
    root="$h/.config/linux-setting-backup"
    b1="$root/20240101_000000"
    b2="$root/20240202_000000"
    mkdir -p "$b1/nvim" "$b2/nvim"
    echo original > "$b1/.zshrc"
    echo second > "$b2/.zshrc"
    echo original-init > "$b1/nvim/init.lua"
    echo second-init > "$b2/nvim/init.lua"
    echo tool-modified > "$h/.zshrc"
    mkdir -p "$h/.config/nvim"
    echo tool-init > "$h/.config/nvim/init.lua"
    echo extra > "$h/.config/nvim/extra.lua"
    write_manifest "$h" <<EOF
file:$h/.zshrc
file:$h/.config/nvim
backup:$b1
backup:$b2
backup:/tmp/not-under-backup-root
EOF
    out="$(run_uninstall "$h" -y)" || rc=$?
    if [ "$rc" -eq 0 ] && [ "$(cat "$h/.zshrc")" = original ]; then
        pass "設定檔從最早的備份還原"
    else
        fail "設定檔未從最早的備份還原（rc=$rc）"
    fi
    if [ "$(cat "$h/.config/nvim/init.lua")" = original-init ] && [ ! -e "$h/.config/nvim/extra.lua" ]; then
        pass "目錄型設定也完整還原"
    else
        fail "目錄型設定未正確還原"
    fi
    [ ! -f "$h/.config/linux-setting/installed.manifest" ] && pass "完成後刪除安裝清單" || fail "完成後應刪除安裝清單"
    [ -d "$b1" ] && [ -d "$b2" ] && pass "備份目錄保留" || fail "備份目錄不應被刪除"
}

make_fake_bin() { # make_fake_bin <目錄>：假的 sudo / apt-get，記錄呼叫
    local d="$1"
    mkdir -p "$d"
    cat > "$d/sudo" <<'EOF'
#!/usr/bin/env bash
echo "sudo $*" >> "$FAKE_LOG"
exec env "$@"
EOF
    cat > "$d/apt-get" <<'EOF'
#!/usr/bin/env bash
echo "apt-get $*" >> "$FAKE_LOG"
case "$*" in *badpkg*) exit 1 ;; esac
exit 0
EOF
    chmod +x "$d/sudo" "$d/apt-get"
}

test_uninstall_packages() {
    local h bin log out rc=0
    h="$(new_home)"
    bin="$WORK/fakebin"
    log="$WORK/fake.log"
    make_fake_bin "$bin"
    : > "$log"
    write_manifest "$h" <<EOF
package:htop
package:badpkg
package:btop
package:-yes
package:bad name
EOF
    out="$(PATH="$bin:$PATH" FAKE_LOG="$log" run_uninstall "$h" -y)" || rc=$?
    local calls
    calls="$(cat "$log")"
    if contains "$calls" "apt-get remove -y htop" && contains "$calls" "apt-get remove -y btop"; then
        pass "以 apt-get remove -y 逐一移除套件"
    else
        fail "未以 apt-get remove -y 移除套件：$calls"
    fi
    if contains "$calls" "apt-get remove -y badpkg" && contains "$calls" "apt-get remove -y btop"; then
        pass "單一套件失敗不中止後續套件"
    else
        fail "單一套件失敗不應中止"
    fi
    if ! contains "$calls" "-yes" && ! contains "$calls" "bad name"; then
        pass "不合法的套件名稱不會傳給套件管理器"
    else
        fail "不合法的套件名稱被傳給套件管理器"
    fi
    if [ "$(id -u)" -eq 0 ] || contains "$calls" "sudo env DEBIAN_FRONTEND=noninteractive apt-get remove"; then
        pass "非 root 時經由 sudo 移除套件"
    else
        fail "非 root 時應使用 sudo"
    fi
    if [ "$rc" -ne 0 ] && [ -f "$h/.config/linux-setting/installed.manifest" ]; then
        pass "有失敗時保留安裝清單並以非 0 結束"
    else
        fail "有失敗時應保留安裝清單（rc=$rc）"
    fi
}

test_uninstall_partial_modes() {
    local h bin log rc=0
    h="$(new_home)"
    bin="$WORK/fakebin"
    log="$WORK/fake2.log"
    make_fake_bin "$bin"
    : > "$log"
    : > "$h/keepme"
    write_manifest "$h" <<EOF
package:htop
path:$h/keepme
EOF
    PATH="$bin:$PATH" FAKE_LOG="$log" run_uninstall "$h" -y --packages-only >/dev/null || rc=$?
    if [ "$rc" -eq 0 ] && [ -e "$h/keepme" ] && ! grep -q '^package:' "$h/.config/linux-setting/installed.manifest" \
       && grep -q "^path:$h/keepme" "$h/.config/linux-setting/installed.manifest"; then
        pass "--packages-only 只處理套件並保留其餘清單"
    else
        fail "--packages-only 行為不正確（rc=$rc）"
    fi
    : > "$log"
    PATH="$bin:$PATH" FAKE_LOG="$log" run_uninstall "$h" -y --configs-only >/dev/null || true
    if [ ! -e "$h/keepme" ] && [ ! -s "$log" ]; then
        pass "--configs-only 不呼叫套件管理器"
    else
        fail "--configs-only 行為不正確"
    fi
}

test_uninstall_no_manifest
test_uninstall_dry_run
test_uninstall_requires_yes_when_non_interactive
test_uninstall_rejects_paths_outside_home
test_uninstall_restores_earliest_backup
test_uninstall_packages
test_uninstall_partial_modes

# ------------------------------------------------------------------------------
echo
echo "== install.sh --rollback =="

run_rollback() {
    local h="$1"
    shift
    env -u XDG_CONFIG_HOME -u NON_INTERACTIVE HOME="$h" bash "$SCRIPT_DIR/install.sh" "$@" </dev/null 2>&1
}

test_rollback() {
    local h out rc=0 root
    h="$(new_home)"
    root="$h/.config/linux-setting-backup"
    mkdir -p "$root/20240101_000000" "$root/20240202_000000/nvim"
    echo old-old > "$root/20240101_000000/.zshrc"
    echo previous > "$root/20240202_000000/.zshrc"
    echo p10k-backup > "$root/20240202_000000/.p10k.zsh"
    echo init-backup > "$root/20240202_000000/nvim/init.lua"
    echo stray > "$root/20240202_000000/.zshrc.backup.20240202_000001"
    echo current > "$h/.zshrc"
    mkdir -p "$h/.config/nvim"
    echo current-init > "$h/.config/nvim/init.lua"

    out="$(run_rollback "$h" --rollback)" || rc=$?
    if [ "$rc" -ne 0 ] && [ "$(cat "$h/.zshrc")" = current ]; then
        pass "--rollback 在非互動且沒有 -y 時不會動作"
    else
        fail "--rollback 沒有 -y 時應拒絕（rc=$rc）"
    fi

    rc=0
    out="$(run_rollback "$h" --rollback --non-interactive)" || rc=$?
    if [ "$rc" -eq 0 ] && [ "$(cat "$h/.zshrc")" = previous ] && [ "$(cat "$h/.p10k.zsh")" = p10k-backup ] \
       && [ "$(cat "$h/.config/nvim/init.lua")" = init-backup ]; then
        pass "--rollback 從最新的備份還原"
    else
        fail "--rollback 未正確還原（rc=$rc）：$out"
    fi
    if [ "$(cat "$h/.zshrc.before-rollback")" = current ] && [ "$(cat "$h/.config/nvim.before-rollback/init.lua")" = current-init ]; then
        pass "--rollback 留下 .before-rollback 副本"
    else
        fail "--rollback 未留下 .before-rollback 副本"
    fi
    [ ! -e "$h/.p10k.zsh.before-rollback" ] && pass "原本不存在的檔案不會產生副本" || fail "不應產生 .p10k.zsh.before-rollback"

    # -y 與遠端執行形式（BASH_SOURCE 為空、目前目錄沒有專案檔案）
    echo changed-again > "$h/.zshrc"
    rc=0
    out="$(cd "$(mktemp -d "$WORK/empty.XXXXXX")" && env -u XDG_CONFIG_HOME -u NON_INTERACTIVE HOME="$h" bash -c "$(cat "$SCRIPT_DIR/install.sh")" -- --rollback -y </dev/null 2>&1)" || rc=$?
    if [ "$rc" -eq 0 ] && [ "$(cat "$h/.zshrc")" = previous ]; then
        pass "遠端執行形式（bash -c \"\$(...)\" -- --rollback -y）可用且不需要專案檔案"
    else
        fail "遠端執行形式的 --rollback 失敗（rc=$rc）：$out"
    fi
}

test_rollback_without_backup() {
    local h out rc=0
    h="$(new_home)"
    out="$(run_rollback "$h" --rollback --non-interactive)" || rc=$?
    if [ "$rc" -ne 0 ] && contains "$out" "沒有可還原的備份"; then
        pass "沒有備份時說明原因並以非 0 結束"
    else
        fail "沒有備份時應以非 0 結束（rc=$rc）"
    fi
    mkdir -p "$h/.config/linux-setting-backup/20240101_000000"
    rc=0
    out="$(run_rollback "$h" --rollback --non-interactive)" || rc=$?
    [ "$rc" -ne 0 ] && pass "備份目錄是空的時以非 0 結束" || fail "空備份目錄應以非 0 結束"
}

test_rollback
test_rollback_without_backup

# ------------------------------------------------------------------------------
echo
echo "== install.sh 下載網址檢查 =="

test_url_validation() {
    local fns
    fns="$(awk '/^_download_url_allowed\(\)/,/^}/ {print} /^validate_download_urls\(\)/,/^}/ {print}' "$SCRIPT_DIR/install.sh")"
    local url
    for url in \
        "https://raw.githubusercontent.com/x/y/main" \
        "http://127.0.0.1:8000" "http://localhost" "http://localhost:9/a" "http://[::1]:8080/x"; do
        if bash -c "$fns"$'\n''_download_url_allowed "$1"' _ "$url"; then pass "允許 $url"; else fail "應允許 $url"; fi
    done
    for url in \
        "http://example.com" "http://example.com/127.0.0.1" "http://localhost@evil.example/x" \
        "http://127.0.0.1.evil.example/" "http://localhost.evil.example" "ftp://localhost" "file:///etc/passwd" \
        "http://evil.example/?x=localhost"; do
        if bash -c "$fns"$'\n''_download_url_allowed "$1"' _ "$url"; then fail "應拒絕 $url"; else pass "拒絕 $url"; fi
    done
    local out rc=0
    if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
        # Bash 3 會先被版本檢查拒絕，直接驗證相同的下載前網址檢查。
        out="$(REPO_URL=http://example.com bash -c "$fns"$'\n''validate_download_urls' 2>&1)" || rc=$?
    else
    out="$(env HOME="$(new_home)" REPO_URL=http://example.com bash "$SCRIPT_DIR/install.sh" --dry-run --non-interactive </dev/null 2>&1)" || rc=$?
    fi
    if [ "$rc" -ne 0 ] && contains "$out" "必須是 https://"; then
        pass "REPO_URL=http://example.com 時下載前網址檢查以非 0 結束"
    else
        fail "REPO_URL=http://example.com 應被拒絕（rc=$rc）"
    fi
}

test_url_validation

# ------------------------------------------------------------------------------
echo
echo "== secure_download.sh =="

test_verify_domain() {
    local url
    local fn='source "$1/scripts/utils/secure_download.sh"; verify_domain "$2"'
    for url in "https://get.docker.com/" "https://astral.sh/uv/install.sh" "https://GET.docker.com:443/x"; do
        if bash -c "$fn" _ "$SCRIPT_DIR" "$url" >/dev/null 2>&1; then pass "verify_domain 接受 $url"; else fail "verify_domain 應接受 $url"; fi
    done
    for url in "https://allowed.example@evil.example/x" "https://astral.sh@evil.example/x" \
        "https://evil.example/?x=astral.sh" "https://evil.example/astral.sh" "http://astral.sh/uv/install.sh" \
        "https://astral.sh.evil.example/" "https://astral.sh:8443/x" "https://evil.example#@astral.sh" "ftp://astral.sh/x"; do
        if bash -c "$fn" _ "$SCRIPT_DIR" "$url" >/dev/null 2>&1; then fail "verify_domain 應拒絕 $url"; else pass "verify_domain 拒絕 $url"; fi
    done
    if ! grep -q 'check_script_safety\|SECURE_DOWNLOAD_ALLOW_PIPE\|trap ' "$SCRIPT_DIR/scripts/utils/secure_download.sh"; then
        pass "secure_download.sh 已移除無效的內容黑名單，也不設全域 trap"
    else
        fail "secure_download.sh 仍含 check_script_safety / SECURE_DOWNLOAD_ALLOW_PIPE / trap"
    fi
}

test_secure_download_keeps_caller_trap() {
    local out
    out="$(bash -c '
        trap "echo CALLER_TRAP_RAN" EXIT
        source "$1/scripts/utils/secure_download.sh"
        secure_download_and_execute "https://evil.example/x" skip test >/dev/null 2>&1 || true
    ' _ "$SCRIPT_DIR" 2>&1)"
    contains "$out" CALLER_TRAP_RAN && pass "secure_download.sh 不覆蓋呼叫端的 EXIT trap" || fail "呼叫端的 EXIT trap 被覆蓋"
}

test_verify_domain
test_secure_download_keeps_caller_trap

# ------------------------------------------------------------------------------
echo
echo "== common.sh：雜湊驗證、安裝清單 =="

test_sha256_and_manifest() {
    local h f list sum
    h="$(new_home)"
    f="$WORK/asset.tar.gz"
    list="$WORK/checksums.txt"
    echo payload > "$f"
    if command -v sha256sum >/dev/null 2>&1; then sum="$(sha256sum "$f" | cut -d' ' -f1)"; else sum="$(shasum -a 256 "$f" | cut -d' ' -f1)"; fi
    printf '%s  asset.tar.gz\n%s  other.tar.gz\n' "$sum" "0000000000000000000000000000000000000000000000000000000000000000" > "$list"
    local run='source "$1/scripts/core/common.sh"; set +e; verify_sha256_in_list "$2" "$3" "$4"'
    HOME="$h" bash -c "$run" _ "$SCRIPT_DIR" "$f" "$list" asset.tar.gz && pass "雜湊相符時通過" || fail "雜湊相符應通過"
    HOME="$h" bash -c "$run" _ "$SCRIPT_DIR" "$f" "$list" other.tar.gz && fail "雜湊不符應失敗" || pass "雜湊不符時失敗"
    HOME="$h" bash -c "$run" _ "$SCRIPT_DIR" "$f" "$list" missing.tar.gz && fail "清單中找不到檔名應失敗" || pass "清單中找不到檔名時失敗"
    HOME="$h" bash -c "$run" _ "$SCRIPT_DIR" "$f" "$WORK/nonexistent" asset.tar.gz && fail "清單不存在應失敗" || pass "清單不存在時失敗"

    local m="$h/.config/linux-setting/installed.manifest"
    env -u XDG_CONFIG_HOME -u NON_INTERACTIVE HOME="$h" bash -c '
        source "$1/scripts/core/common.sh"
        manifest_record package htop
        manifest_record package htop
        manifest_record path /tmp/x
        manifest_record bogus x
        manifest_record path relative
        DRY_RUN=true manifest_record package dry
    ' _ "$SCRIPT_DIR" >/dev/null 2>&1
    if [ "$(cat "$m" 2>/dev/null)" = "$(printf 'package:htop\npath:/tmp/x')" ]; then
        pass "manifest_record 只追加、不重複，忽略不合法類型與 dry-run"
    else
        fail "manifest_record 內容不符：$(cat "$m" 2>/dev/null)"
    fi
    local perm_file perm_dir
    perm_file="$(stat -c %a "$m" 2>/dev/null || stat -f %Lp "$m")"
    perm_dir="$(stat -c %a "$(dirname "$m")" 2>/dev/null || stat -f %Lp "$(dirname "$m")")"
    [ "$perm_file" = 600 ] && [ "$perm_dir" = 700 ] && pass "安裝清單權限為 0600、目錄為 0700" || fail "權限不符：$perm_file / $perm_dir"
}

test_install_package_records() {
    local h bin log m
    h="$(new_home)"
    bin="$WORK/pkgbin"
    log="$WORK/pkg.log"
    mkdir -p "$bin"
    : > "$log"
    # 假 dpkg-query：只有 $FAKE_STATE 目錄裡有同名檔案才算已安裝
    cat > "$bin/dpkg-query" <<'EOF'
#!/usr/bin/env bash
pkg="${@: -1}"
if [ -e "$FAKE_STATE/$pkg" ]; then echo "install ok installed"; exit 0; fi
exit 1
EOF
    cat > "$bin/apt-get" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do [ "$a" = failpkg ] && exit 1; done
for a in "$@"; do
    case "$a" in -*|-o|install|Dpkg::Options::=*) ;; *) touch "$FAKE_STATE/$a" ;; esac
done
exit 0
EOF
    printf '#!/usr/bin/env bash\nexec env "$@"\n' > "$bin/sudo"
    chmod +x "$bin"/*
    mkdir -p "$WORK/state"
    touch "$WORK/state/already"
    PATH="$bin:$PATH" FAKE_STATE="$WORK/state" env -u XDG_CONFIG_HOME -u NON_INTERACTIVE HOME="$h" LOG_DIR="$h/log" bash -c '
        source "$1/scripts/core/common.sh"; set +e
        PKG_MANAGER=apt
        install_package newpkg
        install_package already
        install_package already true
        install_apt_packages_parallel pa pb
        install_apt_packages_parallel pc failpkg
    ' _ "$SCRIPT_DIR" >/dev/null 2>&1
    m="$h/.config/linux-setting/installed.manifest"
    local got
    got="$(sort "$m" 2>/dev/null | tr '\n' ' ')"
    if [ "$got" = "package:newpkg package:pa package:pb package:pc " ]; then
        pass "install_package / install_apt_packages_parallel 只記錄新安裝成功的套件（含批次失敗後逐一重試）"
    else
        fail "安裝清單內容不符：$got"
    fi
}

test_sha256_and_manifest
test_install_package_records

# ------------------------------------------------------------------------------
echo
echo "== module_manager.sh：設定檔來源與驗證 =="

test_module_manager_hardening() {
    if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
        echo "[SKIP] 需要 bash 4+"
        return
    fi
    local h evil marker out
    h="$(new_home)"
    evil="$(mktemp -d "$WORK/evil.XXXXXX")"
    marker="$evil/PWNED"
    mkdir -p "$evil/config"
    cat > "$evil/config/modules.conf" <<EOF
[evilmod]
name=Evil
packages=curl
post_install=touch $marker
EOF
    out="$(cd "$evil" && env -u MODULES_CONF HOME="$h" LOG_DIR="$h/log" SCRIPT_DIR="$SCRIPT_DIR/scripts" bash -c '
        source "$SCRIPT_DIR/core/common.sh"; set +e
        source "$SCRIPT_DIR/core/module_manager.sh"
        init_module_manager >/dev/null 2>&1
        echo "CONF=$(find_modules_conf)"
        echo "MODULES=${MODULE_LIST[*]}"
        install_module evilmod >/dev/null 2>&1
    ' 2>&1)"
    if contains "$out" "CONF=$SCRIPT_DIR/scripts/../config/modules.conf" && ! contains "$out" "evilmod" && [ ! -e "$marker" ]; then
        pass "不採用目前目錄下的 config/modules.conf，也不會執行其 post_install"
    else
        fail "目前目錄的 config/modules.conf 被採用了：$out"
    fi

    local conf="$WORK/custom.conf"
    cat > "$conf" <<EOF
[m1]
name=M1
packages=goodpkg -oBad::Option=1 --purge
script=../../tmp/evil.sh
[m2]
name=M2
script=ok_setup.sh
[m3]
name=M3
script=..
EOF
    out="$(env HOME="$h" LOG_DIR="$h/log" MODULES_CONF="$conf" SCRIPT_DIR="$SCRIPT_DIR/scripts" bash -c '
        source "$SCRIPT_DIR/core/common.sh"; set +e
        source "$SCRIPT_DIR/core/module_manager.sh"
        init_module_manager >/dev/null 2>&1
        echo "P1=[${MODULE_PACKAGES[m1]}]"
        echo "S1=[${MODULE_SCRIPTS[m1]:-}]"
        echo "S2=[${MODULE_SCRIPTS[m2]:-}]"
        echo "S3=[${MODULE_SCRIPTS[m3]:-}]"
        echo "INVALID=[${MODULE_INVALID_PKGS[m1]:-}]"
    ' 2>&1)"
    contains "$out" "P1=[goodpkg]" && pass "以 - 開頭的套件名稱被略過" || fail "以 - 開頭的套件名稱未被略過：$out"
    contains "$out" "INVALID=[ -oBad::Option=1 --purge]" && pass "不合法的套件名稱記錄為失敗項目" || fail "未記錄不合法套件：$out"
    if contains "$out" "S1=[]" && contains "$out" "S2=[ok_setup.sh]" && contains "$out" "S3=[]"; then
        pass "script= 只接受單純檔名（含路徑或 .. 的被略過）"
    else
        fail "script= 驗證不正確：$out"
    fi
}

test_module_manager_hardening

# ------------------------------------------------------------------------------
echo
echo "== 其他加固 =="

test_optimize_apt_not_in_dry_run() {
    local h bin log
    h="$(new_home)"
    bin="$WORK/sudobin"
    log="$WORK/sudo.log"
    mkdir -p "$bin"
    : > "$log"
    printf '#!/usr/bin/env bash\necho "sudo $*" >> "$FAKE_LOG"\nexit 0\n' > "$bin/sudo"
    chmod +x "$bin/sudo"
    PATH="$bin:$PATH" FAKE_LOG="$log" HOME="$h" LOG_DIR="$h/log" bash -c '
        source "$1/scripts/core/common.sh"; set +e
        DRY_RUN=true optimize_apt_performance
    ' _ "$SCRIPT_DIR" >/dev/null 2>&1
    [ ! -s "$log" ] && pass "DRY_RUN=true 時 optimize_apt_performance 不呼叫 sudo" || fail "dry-run 不應呼叫 sudo"

    local installer="$SCRIPT_DIR/install.sh" call_line start_line env_start env_end
    call_line="$(grep -n 'optimize_apt_performance ||' "$installer" | cut -d: -f1 | head -n 1)"
    start_line="$(grep -n 'log_info "開始安裝以下模組' "$installer" | cut -d: -f1 | head -n 1)"
    env_start="$(grep -n '^check_environment()' "$installer" | cut -d: -f1)"
    env_end="$(grep -n '^backup_config_files\|^_manifest_has()' "$installer" | cut -d: -f1 | head -n 1)"
    if [ "$(grep -c 'optimize_apt_performance ||' "$installer")" -eq 1 ] && [ -n "$call_line" ] && [ -n "$start_line" ] \
       && [ "$call_line" -gt "$start_line" ] && ! { [ "$call_line" -gt "$env_start" ] && [ "$call_line" -lt "$env_end" ]; }; then
        pass "optimize_apt_performance 只在 dry-run 返回之後的實際安裝流程中呼叫"
    else
        fail "optimize_apt_performance 的呼叫位置不正確"
    fi
}

test_thefuck_pin_consistent() {
    local req term upd
    req="$(sed -n 's|.*nvbn/thefuck.git@\([0-9a-f]\{40\}\).*|\1|p' "$SCRIPT_DIR/requirements.txt" | head -n 1)"
    term="$(sed -n 's/^THEFUCK_PINNED_COMMIT="\([0-9a-f]*\)".*/\1/p' "$SCRIPT_DIR/scripts/core/terminal_setup.sh")"
    upd="$(sed -n 's/^THEFUCK_PINNED_COMMIT="\([0-9a-f]*\)".*/\1/p' "$SCRIPT_DIR/scripts/maintenance/update_tools.sh")"
    if [ -n "$req" ] && [ "$req" = "$term" ] && [ "$req" = "$upd" ]; then
        pass "requirements.txt、terminal_setup.sh、update_tools.sh 的 thefuck commit 一致"
    else
        fail "thefuck commit 不一致：$req / $term / $upd"
    fi
}

test_chsh_and_docker_group_use_id() {
    if ! grep -q 'target_user="${USER' "$SCRIPT_DIR/scripts/core/terminal_setup.sh" \
       && grep -q 'target_user="$(id -un)"' "$SCRIPT_DIR/scripts/core/terminal_setup.sh" \
       && ! grep -q '\$USER' "$SCRIPT_DIR/scripts/core/docker_setup.sh" \
       && grep -q 'ADD_USER_TO_DOCKER_GROUP' "$SCRIPT_DIR/scripts/core/docker_setup.sh"; then
        pass "chsh 與 docker 群組都以 id -un 取得使用者，且 docker 群組可由 ADD_USER_TO_DOCKER_GROUP 關閉"
    else
        fail "chsh / docker 群組仍使用 \$USER 或沒有開關"
    fi
}

test_optimize_apt_not_in_dry_run
test_thefuck_pin_consistent
test_chsh_and_docker_group_use_id

echo
echo "========================================"
echo "測試結果"
echo "========================================"
echo "通過: $TESTS_PASSED"
echo "失敗: $TESTS_FAILED"
echo "總計: $((TESTS_PASSED + TESTS_FAILED))"
[ "$TESTS_FAILED" -eq 0 ]
