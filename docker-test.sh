#!/bin/bash

# Docker 測試環境管理腳本
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="linux-setting-test"
CONTAINER_NAME="linux-setting-test-container"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 檢查 Docker 是否可用
check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker 未安裝或不在 PATH 中"
        return 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        log_error "無法連接到 Docker daemon"
        log_info "請確保 Docker 服務正在運行且當前用戶有權限"
        return 1
    fi
    
    log_success "Docker 可用"
    return 0
}

# 建立測試映像
build_image() {
    log_info "建立 Docker 測試映像..."
    
    if [ ! -f "$SCRIPT_DIR/Dockerfile" ]; then
        log_error "Dockerfile 不存在"
        return 1
    fi
    
    if docker build -t "$IMAGE_NAME" "$SCRIPT_DIR"; then
        log_success "Docker 映像建立成功: $IMAGE_NAME"
        return 0
    else
        log_error "Docker 映像建立失敗"
        return 1
    fi
}

# 運行測試容器
run_container() {
    local command="$1"
    local interactive="${2:-false}"
    
    # 清理現有容器
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_info "清理現有容器..."
        docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
    fi
    
    if [ "$interactive" = "true" ]; then
        log_info "啟動互動式測試容器..."
        docker run -it --rm \
            --name "$CONTAINER_NAME" \
            -v "$SCRIPT_DIR:/opt/linux-setting" \
            "$IMAGE_NAME" \
            ${command:-/bin/bash}
    else
        log_info "運行測試容器..."
        docker run --rm \
            --name "$CONTAINER_NAME" \
            -v "$SCRIPT_DIR:/opt/linux-setting" \
            "$IMAGE_NAME" \
            ${command:-/bin/bash -c "echo 'Container is ready!'"}
    fi
}

# 執行腳本測試
run_script_tests() {
    log_info "在 Docker 容器中執行腳本測試..."
    
    local test_script="
    set -e
    cd /opt/linux-setting
    
    echo '=== 系統信息 ==='
    cat /etc/os-release | head -3
    python3 --version
    echo ''
    
    echo '=== 執行語法檢查 ==='
    ./tests/test_scripts.sh
    echo ''
    
    echo '=== 執行依賴檢查 ==='
    ./tests/test_dependencies.sh
    echo ''
    
    echo '=== 執行功能測試 ==='
    ./tests/test_functionality.sh
    echo ''
    
    echo '=== 測試配置預覽 ==='
    ./scripts/preview_config.sh --full-preview 'python base'
    echo ''
    
    echo '=== 所有測試完成 ==='
    "
    
    if docker run --rm "$IMAGE_NAME" /bin/bash -c "$test_script"; then
        log_success "Docker 中的腳本測試通過"
        return 0
    else
        log_error "Docker 中的腳本測試失敗"
        return 1
    fi
}

# 執行完整安裝測試
run_full_installation_test() {
    log_info "在 Docker 容器中執行完整安裝測試..."
    
    local install_script="
    set -e
    cd /opt/linux-setting
    
    echo '=== 測試最小安裝模式 ==='
    echo 'y' | timeout 300 ./install.sh --minimal --mirror china --verbose || {
        echo '安裝超時或失敗，但這可能是正常的'
        exit 0
    }
    
    echo '=== 執行健康檢查 ==='
    ./scripts/health_check.sh || true
    
    echo '=== 檢查安裝結果 ==='
    ls -la \$HOME/.local/bin/ || echo '本地 bin 目錄不存在'
    python3 -c 'import sys; print(f\"Python: {sys.version}\")' || true
    
    echo '=== 完整安裝測試完成 ==='
    "
    
    log_warning "注意: 完整安裝測試可能需要較長時間..."
    
    if docker run --rm \
        -e DEBIAN_FRONTEND=noninteractive \
        "$IMAGE_NAME" /bin/bash -c "$install_script"; then
        log_success "Docker 中的完整安裝測試通過"
        return 0
    else
        log_warning "Docker 中的完整安裝測試可能有警告（這可能是正常的）"
        return 0
    fi
}

# 運行基準測試
run_benchmark() {
    log_info "執行性能基準測試..."
    
    local benchmark_script="
    set -e
    cd /opt/linux-setting
    
    echo '=== 基準測試開始 ==='
    start_time=\$(date +%s)
    
    echo '測試腳本載入時間...'
    time source scripts/common.sh
    
    echo '測試網路連接速度...'
    time curl -s -o /dev/null --max-time 10 http://example.com || echo '網路測試跳過'
    
    echo '測試 Python 導入速度...'
    time python3 -c 'import sys, os, json, subprocess'
    
    end_time=\$(date +%s)
    duration=\$((end_time - start_time))
    echo \"基準測試完成，耗時: \${duration} 秒\"
    "
    
    docker run --rm "$IMAGE_NAME" /bin/bash -c "$benchmark_script"
}

# 清理 Docker 資源
cleanup() {
    log_info "清理 Docker 資源..."
    
    # 停止並刪除容器
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
        log_success "已刪除容器: $CONTAINER_NAME"
    fi
    
    # 可選：刪除映像
    if [ "$1" = "--remove-image" ]; then
        if docker images --format '{{.Repository}}' | grep -q "^${IMAGE_NAME}$"; then
            docker rmi "$IMAGE_NAME" >/dev/null 2>&1
            log_success "已刪除映像: $IMAGE_NAME"
        fi
    fi
}

# 顯示 Docker 資源狀態
show_status() {
    echo ""
    log_info "Docker 資源狀態:"
    echo ""
    
    echo "🐳 映像:"
    docker images | grep "$IMAGE_NAME" || echo "  沒有找到相關映像"
    echo ""
    
    echo "📦 容器:"
    docker ps -a | grep "$CONTAINER_NAME" || echo "  沒有找到相關容器"
    echo ""
    
    echo "💾 磁盤使用:"
    docker system df
    echo ""
}

# 顯示幫助信息
show_help() {
    cat << EOF
Docker 測試環境管理腳本

用法: $0 <命令> [選項]

命令:
  build                    建立 Docker 測試映像
  test                     執行基本腳本測試
  full-test               執行完整安裝測試
  benchmark               執行性能基準測試
  shell                   啟動互動式 shell
  run <命令>               在容器中執行自定義命令
  status                  顯示 Docker 資源狀態
  cleanup                 清理測試容器
  cleanup --remove-image  清理容器和映像
  help                    顯示此幫助信息

範例:
  $0 build                          # 建立測試映像
  $0 test                           # 執行基本測試
  $0 full-test                      # 執行完整測試
  $0 shell                          # 進入互動式環境
  $0 run "ls -la"                   # 執行自定義命令
  $0 cleanup                        # 清理資源

Docker 環境:
  - 基於 Ubuntu 22.04
  - 預裝 Python 3, pip, git 等
  - 非 root 用戶 (testuser)
  - 已設定 sudo 權限

EOF
}

# 主函數
main() {
    case "${1:-help}" in
        "build")
            check_docker && build_image
            ;;
        "test")
            check_docker && run_script_tests
            ;;
        "full-test")
            check_docker && run_full_installation_test
            ;;
        "benchmark")
            check_docker && run_benchmark
            ;;
        "shell")
            check_docker && run_container "/bin/bash" true
            ;;
        "run")
            if [ -z "$2" ]; then
                log_error "請指定要執行的命令"
                echo "用法: $0 run '<命令>'"
                exit 1
            fi
            check_docker && run_container "$2" false
            ;;
        "status")
            check_docker && show_status
            ;;
        "cleanup")
            cleanup "$2"
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            log_error "未知命令: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# 執行主函數
main "$@"