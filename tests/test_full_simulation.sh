#!/bin/bash

# 完整安裝流程模擬（使用本機 HTTP server + Docker）
#
# 功能：
# 1. 在本機啟動一個簡單的 HTTP server，直接服務目前專案目錄
# 2. Docker 容器內用 curl 從本機抓取 install.sh（模擬遠端 curl | bash 安裝）
# 3. 在容器裡實際執行互動式安裝（自動輸入：安裝所有模組）
# 4. 測試結束後自動關閉本機 HTTP server
#
# 重要：
# - 預設容器內透過 host.docker.internal 存取本機（Docker Desktop for macOS/Windows 支援）
# - 如果是在 Linux 上，可自行設定 HOST_FOR_CONTAINER=宿主機IP 來覆蓋

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# 顏色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}   $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERR]${NC}  $*"; }

HTTP_PORT="${LOCAL_HTTP_PORT:-8000}"
HOST_FOR_CONTAINER="${HOST_FOR_CONTAINER:-host.docker.internal}"
SERVER_PID=""

cleanup() {
    if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        log_info "停止本機 HTTP server (PID=$SERVER_PID)"
        kill "$SERVER_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

check_prerequisites() {
    if ! command -v python3 >/dev/null 2>&1; then
        log_error "找不到 python3，無法啟動本機 HTTP server"
        exit 1
    fi

    if ! command -v docker >/dev/null 2>&1; then
        log_error "找不到 docker，無法執行容器測試"
        exit 1
    fi

    if [[ ! -f "$REPO_ROOT/docker-test.sh" ]]; then
        log_error "找不到 docker-test.sh，請在專案根目錄下執行此腳本"
        exit 1
    fi

    log_ok "前置條件檢查通過"
}

start_local_server() {
    log_info "在本機啟動 HTTP server 服務專案目錄: $REPO_ROOT"
    log_info "URL: http://0.0.0.0:${HTTP_PORT}/install.sh"

    # 使用 python3 標準庫啟動簡單 HTTP server
    python3 -m http.server "$HTTP_PORT" --bind 0.0.0.0 >/tmp/linux_setting_http_${HTTP_PORT}.log 2>&1 &
    SERVER_PID=$!

    # 等待 server 啟動
    sleep 2

    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        log_error "HTTP server 啟動失敗，請查看日誌：/tmp/linux_setting_http_${HTTP_PORT}.log"
        exit 1
    fi

    log_ok "HTTP server 已啟動 (PID=$SERVER_PID)"
}

run_simulation_in_docker() {
    local url="http://${HOST_FOR_CONTAINER}:${HTTP_PORT}/install.sh"

    log_info "容器內將從本機網址安裝：$url"
    log_info "模擬輸入：安裝所有模組 (7)，然後開始安裝 (i)"

    # 先確保測試映像已建立
    log_info "確認 Docker 測試映像存在（必要時會自動 build）"
    ./docker-test.sh build

    # 在容器中執行實際安裝流程
    # 步驟：
    #   1. 先用 curl 把目前本機版本的 install.sh 下載到容器內 /tmp
    #   2. 用 bash 執行 /tmp/install.sh，並透過 here-doc 傳入選單輸入
    #      這裡刻意「略過 Docker 模組 (2)」，只安裝：python/base/terminal/dev/monitoring
    ./docker-test.sh run "
export TUI_MODE=quiet
cd /opt/linux-setting && \
curl -fsSL '$url' -o /tmp/install.sh && \
bash /tmp/install.sh --verbose << 'EOF'
# 選擇要安裝的模組（不含 2: docker）
1 3 4 5 6
# 開始安裝
i
EOF
"

    log_ok "容器內完整安裝流程模擬已完成"
}

main() {
    log_info "===== 完整安裝流程模擬（本機 HTTP server + Docker）====="
    check_prerequisites
    start_local_server
    run_simulation_in_docker
    log_info "===== 模擬流程結束 ====="
}

main "$@"


