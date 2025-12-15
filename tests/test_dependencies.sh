#!/bin/bash

# 依賴測試工具
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/common.sh" 2>/dev/null || {
    # 基礎顏色定義（如果無法載入 common.sh）
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    NC='\033[0m'
}

TESTS_PASSED=0
TESTS_FAILED=0

log_test() {
    echo -e "${GREEN}[TEST]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# 測試系統相容性
test_system_compatibility() {
    log_test "測試系統相容性..."
    
    # 檢查 Linux 發行版
    if [ -f /etc/os-release ]; then
        local os_info
        os_info=$(grep -E '^(NAME|VERSION)=' /etc/os-release | head -2 | cut -d'=' -f2 | tr -d '"')
        
        if grep -q 'Ubuntu\|Debian' /etc/os-release; then
            log_pass "支援的 Linux 發行版: $os_info"
        else
            log_fail "不支援的 Linux 發行版: $os_info"
        fi
    else
        log_fail "無法檢測 Linux 發行版"
    fi
    
    # 檢查架構
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)
            log_pass "支援的系統架構: $arch"
            ;;
        aarch64|arm64)
            log_warn "ARM 架構可能有兼容性問題: $arch"
            ;;
        *)
            log_fail "不支援的系統架構: $arch"
            ;;
    esac
}

# 測試網路連接性
test_network_connectivity() {
    log_test "測試網路連接性..."
    
    # 關鍵網站連接測試
    local sites=(
        "google.com"
        "github.com"
        "pypi.org"
        "raw.githubusercontent.com"
    )
    
    for site in "${sites[@]}"; do
        if timeout 5 ping -c 1 "$site" >/dev/null 2>&1; then
            log_pass "可連接到 $site"
        else
            log_warn "無法連接到 $site"
        fi
    done
    
    # 檢查 DNS 解析
    if nslookup google.com >/dev/null 2>&1; then
        log_pass "DNS 解析正常"
    else
        log_fail "DNS 解析失敗"
    fi
}

# 測試必要命令可用性
test_required_commands() {
    log_test "測試必要命令可用性..."
    
    local required_commands=(
        "curl"
        "wget"
        "sudo"
        "apt-get"
        "python3"
        "pip3"
        "git"
        "bash"
        "zsh"
        "grep"
        "sed"
        "awk"
    )
    
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            local version
            case "$cmd" in
                "python3")
                    version=$(python3 --version 2>&1 | cut -d' ' -f2)
                    ;;
                "git")
                    version=$(git --version 2>&1 | cut -d' ' -f3)
                    ;;
                "bash")
                    version=$(bash --version 2>&1 | head -1 | cut -d' ' -f4)
                    ;;
                "zsh")
                    version=$(zsh --version 2>&1 | cut -d' ' -f2)
                    ;;
                *)
                    version="已安裝"
                    ;;
            esac
            log_pass "$cmd ($version)"
        else
            log_fail "$cmd 未安裝"
        fi
    done
}

# 測試 Python 環境
test_python_environment() {
    log_test "測試 Python 環境..."
    
    # Python 版本檢查
    if command -v python3 >/dev/null 2>&1; then
        local py_version
        py_version=$(python3 -c "import sys; print('.'.join(map(str, sys.version_info[:2])))")
        
        if python3 -c "import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)"; then
            log_pass "Python 版本符合要求: $py_version"
        else
            log_fail "Python 版本過舊: $py_version (需要 >= 3.8)"
        fi
        
        # pip 檢查
        if command -v pip3 >/dev/null 2>&1; then
            local pip_version
            pip_version=$(pip3 --version | cut -d' ' -f2)
            log_pass "pip3 可用: $pip_version"
        else
            log_fail "pip3 不可用"
        fi
        
        # 虛擬環境支援
        if python3 -c "import venv" 2>/dev/null; then
            log_pass "venv 模組可用"
        else
            log_fail "venv 模組不可用"
        fi
        
        # 重要 Python 模組
        local modules=("ssl" "urllib" "json" "subprocess" "os" "sys")
        for module in "${modules[@]}"; do
            if python3 -c "import $module" 2>/dev/null; then
                log_pass "Python 模組 $module 可用"
            else
                log_fail "Python 模組 $module 不可用"
            fi
        done
    else
        log_fail "Python3 未安裝"
    fi
}

# 測試磁盤空間
test_disk_space() {
    log_test "測試磁盤空間..."
    
    local available_gb
    available_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [ "$available_gb" -ge 5 ]; then
        log_pass "可用磁盤空間充足: ${available_gb}GB"
    elif [ "$available_gb" -ge 3 ]; then
        log_warn "磁盤空間較緊張: ${available_gb}GB (建議 >= 5GB)"
    else
        log_fail "磁盤空間不足: ${available_gb}GB (最少需要 3GB)"
    fi
    
    # 檢查 /tmp 空間
    local tmp_space
    tmp_space=$(df -BG /tmp | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$tmp_space" -ge 1 ]; then
        log_pass "/tmp 空間充足: ${tmp_space}GB"
    else
        log_warn "/tmp 空間較小: ${tmp_space}GB"
    fi
}

# 測試權限
test_permissions() {
    log_test "測試權限..."
    
    # sudo 權限測試
    if sudo -n true 2>/dev/null; then
        log_pass "sudo 權限可用 (無需密碼)"
    elif sudo -v 2>/dev/null; then
        log_pass "sudo 權限可用"
    else
        log_fail "sudo 權限不可用"
    fi
    
    # 寫入權限測試
    local test_dirs=(
        "$HOME"
        "$HOME/.local"
        "$HOME/.config"
        "/tmp"
    )
    
    for dir in "${test_dirs[@]}"; do
        if [ -w "$dir" ]; then
            log_pass "$dir 可寫"
        else
            log_fail "$dir 不可寫"
        fi
    done
    
    # 執行權限測試
    if [ -x "$SCRIPT_DIR/install.sh" ]; then
        log_pass "install.sh 可執行"
    else
        log_fail "install.sh 不可執行"
    fi
}

# 測試網路速度
test_network_speed() {
    log_test "測試網路速度..."
    
    # 下載小文件測試速度
    local test_url="http://cachefly.cachefly.net/100kb.test"
    local start_time end_time duration speed
    
    if command -v curl >/dev/null 2>&1; then
        start_time=$(date +%s.%N)
        if curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$test_url" | grep -q "200"; then
            end_time=$(date +%s.%N)
            duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "1")
            
            if command -v bc >/dev/null 2>&1; then
                speed=$(echo "scale=2; 100 / $duration / 1024" | bc)
                
                if (( $(echo "$speed > 50" | bc -l 2>/dev/null || echo 0) )); then
                    log_pass "網路速度良好: ${speed} KB/s"
                elif (( $(echo "$speed > 10" | bc -l 2>/dev/null || echo 0) )); then
                    log_warn "網路速度一般: ${speed} KB/s"
                else
                    log_warn "網路速度較慢: ${speed} KB/s"
                fi
            else
                log_pass "網路連接正常 (無法計算速度)"
            fi
        else
            log_warn "網路速度測試失敗"
        fi
    else
        log_warn "curl 不可用，跳過網路速度測試"
    fi
}

# 測試套件源可用性
test_package_sources() {
    log_test "測試套件源可用性..."
    
    # APT 套件源測試
    if command -v apt-get >/dev/null 2>&1; then
        if timeout 30 sudo apt-get update -qq 2>/dev/null; then
            log_pass "APT 套件源可用"
        else
            log_fail "APT 套件源不可用或更新失敗"
        fi
    else
        log_warn "APT 不可用"
    fi
    
    # Python PyPI 測試
    if command -v pip3 >/dev/null 2>&1; then
        if timeout 10 pip3 search setuptools >/dev/null 2>&1 || \
           timeout 10 pip3 index versions setuptools >/dev/null 2>&1; then
            log_pass "PyPI 套件源可用"
        else
            log_warn "PyPI 套件源測試失敗 (可能是連接問題)"
        fi
    fi
}

# 執行所有依賴測試
run_all_tests() {
    echo "========================================"
    echo "Linux Setting Scripts - 依賴測試套件"
    echo "========================================"
    
    test_system_compatibility
    echo
    test_network_connectivity
    echo
    test_required_commands
    echo
    test_python_environment
    echo
    test_disk_space
    echo
    test_permissions
    echo
    test_network_speed
    echo
    test_package_sources
    echo
    
    echo "========================================"
    echo "依賴測試結果"
    echo "========================================"
    echo "通過: $TESTS_PASSED"
    echo "失敗: $TESTS_FAILED"
    echo "總計: $((TESTS_PASSED + TESTS_FAILED))"
    
    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "${GREEN}✅ 所有依賴測試通過！系統已準備好安裝。${NC}"
        exit 0
    elif [ "$TESTS_FAILED" -le 3 ]; then
        echo -e "${YELLOW}⚠️  有 $TESTS_FAILED 個測試失敗，但可能不影響安裝。${NC}"
        exit 0
    else
        echo -e "${RED}❌ 有 $TESTS_FAILED 個測試失敗，建議修復問題後再安裝。${NC}"
        exit 1
    fi
}

# 執行測試
run_all_tests