#!/bin/bash

# 性能優化工具 - 提升安裝腳本性能

# 載入共用函數庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || exit 1

log_info "########## 系統性能優化工具 ##########"

# 性能配置
readonly MAX_PARALLEL_JOBS="${PARALLEL_JOBS:-$(nproc 2>/dev/null || echo 4)}"

# 性能基準測試
run_performance_benchmark() {
    log_info "運行性能基準測試..."
    
    local test_results=()
    
    # CPU 性能測試
    local cpu_start=$(date +%s.%N)
    dd if=/dev/zero bs=1M count=100 of=/tmp/test_cpu 2>/dev/null
    local cpu_end=$(date +%s.%N)
    local cpu_time=$(echo "$cpu_end - $cpu_start" | bc)
    rm -f /tmp/test_cpu
    test_results+=("CPU: ${cpu_time}s")
    
    # 網絡性能測試
    local net_start=$(date +%s.%N)
    curl -o /dev/null -s --max-time 5 http://www.google.com >/dev/null 2>&1
    local net_end=$(date +%s.%N)
    local net_time=$(echo "$net_end - $net_start" | bc)
    test_results+=("Network: ${net_time}s")
    
    # 磁盤性能測試
    local disk_start=$(date +%s.%N)
    sync
    local disk_end=$(date +%s.%N)
    local disk_time=$(echo "$disk_end - $disk_start" | bc)
    test_results+=("Disk: ${disk_time}s")
    
    log_info "性能基準測試結果:"
    for result in "${test_results[@]}"; do
        log_info "  - $result"
    done
}

# 全系統優化
optimize_system_performance() {
    log_info "開始系統性能優化..."
    
    # 優化 APT 性能
    optimize_apt_performance
    
    # 清理系統
    cleanup_apt_system
    
    # 選擇最快的鏡像源
    local mirror_region="${MIRROR_MODE:-auto}"
    select_fastest_apt_mirror "$mirror_region" > /dev/null
    
    # 優化網絡設置
    optimize_network_settings
    
    log_success "系統性能優化完成"
}

# 優化網絡設置
optimize_network_settings() {
    log_info "優化網絡設置..."
    
    # 增加網絡連接數限制
    local net_config="/etc/security/limits.d/99-network-optimization.conf"
    if [ ! -f "$net_config" ]; then
        sudo tee "$net_config" > /dev/null << 'EOF'
# 網絡優化設置
* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768
EOF
        log_success "網絡連接數限制優化完成"
    fi
    
    # 優化 TCP 設置
    local sysctl_config="/etc/sysctl.d/99-network-performance.conf"
    if [ ! -f "$sysctl_config" ]; then
        sudo tee "$sysctl_config" > /dev/null << 'EOF'
# 網絡性能優化
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.netdev_max_backlog = 5000
EOF
        sudo sysctl --system >/dev/null 2>&1
        log_success "TCP 網絡性能優化完成"
    fi
}

# 智能並行任務管理
smart_parallel_execution() {
    local tasks=("$@")
    local optimal_jobs
    
    # 根據系統負載調整並行任務數
    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{ print $2 }' | awk '{ print $1 }' | sed 's/,//')
    local cpu_cores
    cpu_cores=$(nproc 2>/dev/null || echo 4)
    
    if (( $(echo "$load_avg > $cpu_cores" | bc -l 2>/dev/null || echo 0) )); then
        optimal_jobs=$((cpu_cores / 2))
    else
        optimal_jobs=$cpu_cores
    fi
    
    export PARALLEL_JOBS="$optimal_jobs"
    log_info "智能調整並行任務數: $optimal_jobs (CPU核心: $cpu_cores, 負載: $load_avg)"
    
    # 執行任務
    for task in "${tasks[@]}"; do
        eval "$task" &
        
        # 控制並行任務數量
        while [ $(jobs -r | wc -l) -ge "$optimal_jobs" ]; do
            sleep 0.1
        done
    done
    
    # 等待所有任務完成
    wait
}

# 緩存 apt update 結果
cache_apt_update() {
    local cache_file="$CACHE_DIR/apt_update_cache"
    
    if is_cache_valid "$cache_file" 1; then  # 1小時有效期
        log_info "使用緩存的 apt update 結果"
        return 0
    fi
    
    log_info "執行 apt update 並緩存結果"
    if sudo apt update; then
        touch "$cache_file"
        return 0
    else
        return 1
    fi
}

# 並行安裝包
install_packages_parallel() {
    local packages=("$@")
    local batch_size="${MAX_PARALLEL_JOBS}"
    
    # 確保 apt 緩存是最新的
    cache_apt_update || return 1
    
    log_info "並行安裝 ${#packages[@]} 個包（批次大小：$batch_size）"
    
    for ((i=0; i<${#packages[@]}; i+=batch_size)); do
        local batch=("${packages[@]:i:batch_size}")
        local pids=()
        
        log_info "安裝批次 $((i/batch_size + 1)): ${batch[*]}"
        
        for pkg in "${batch[@]}"; do
            (
                if ! dpkg -l | grep -q "^ii  $pkg "; then
                    sudo apt install -y "$pkg" 2>/dev/null
                    echo "✓ $pkg" >&2
                else
                    echo "- $pkg (已安裝)" >&2
                fi
            ) &
            pids+=($!)
        done
        
        # 等待當前批次完成
        for pid in "${pids[@]}"; do
            wait "$pid"
        done
        
        log_info "批次 $((i/batch_size + 1)) 完成"
    done
    
    log_success "並行安裝完成"
}

# 優化的 git clone
optimized_git_clone() {
    local repo_url="$1"
    local target_dir="$2"
    local branch="${3:-main}"
    
    if [ -d "$target_dir" ]; then
        log_info "$target_dir 已存在，執行更新"
        cd "$target_dir" && git pull --ff-only
        return $?
    fi
    
    log_info "優化 clone: $repo_url"
    git clone \
        --depth=1 \
        --single-branch \
        --branch="$branch" \
        "$repo_url" \
        "$target_dir"
}

# 網路速度緩存
get_cached_network_speed() {
    local cache_file="$CACHE_DIR/network_speed_cache"
    
    if is_cache_valid "$cache_file" 1; then
        cat "$cache_file"
        return 0
    fi
    
    log_info "測試網路速度並緩存結果"
    local speed
    speed=$(check_internet_speed)
    echo "$speed" > "$cache_file"
    echo "$speed"
}

# 智能鏡像選擇（基於緩存的網路速度）
select_optimal_mirror() {
    local speed
    speed=$(get_cached_network_speed)
    
    if (( $(echo "$speed < 0.5" | bc -l 2>/dev/null || echo 0) )); then
        echo "china"
    else
        echo "global"
    fi
}

# 預下載關鍵文件
predownload_assets() {
    local assets=(
        "$REPO_URL/.p10k.zsh"
        "$REPO_URL/requirements.txt"
        "https://astral.sh/uv/install.sh"
    )
    
    log_info "預下載關鍵資源文件"
    
    for asset in "${assets[@]}"; do
        local filename
        filename=$(basename "$asset")
        local cache_file="$CACHE_DIR/$filename"
        
        if ! is_cache_valid "$cache_file"; then
            log_info "下載 $filename"
            curl -fsSL "$asset" -o "$cache_file" &
        fi
    done
    
    wait  # 等待所有下載完成
    log_success "資源預下載完成"
}

# 並行健康檢查
parallel_health_check() {
    local commands=(
        "python3 --version"
        "git --version"
        "curl --version"
        "sudo -n true"
    )
    
    log_info "並行執行健康檢查"
    
    for cmd in "${commands[@]}"; do
        (
            if eval "$cmd" >/dev/null 2>&1; then
                echo "✓ $cmd"
            else
                echo "✗ $cmd"
            fi
        ) &
    done
    
    wait
}

# 優化的包搜索
optimized_package_search() {
    local package="$1"
    local cache_file="$CACHE_DIR/package_search_$package"
    
    if is_cache_valid "$cache_file" 6; then  # 6小時有效期
        cat "$cache_file"
        return 0
    fi
    
    log_info "搜索包信息: $package"
    apt-cache show "$package" > "$cache_file" 2>/dev/null
    cat "$cache_file"
}

# 清理過期緩存
cleanup_expired_cache() {
    if [ ! -d "$CACHE_DIR" ]; then
        return 0
    fi
    
    log_info "清理過期緩存"
    find "$CACHE_DIR" -type f -mtime +1 -delete
    
    # 清理空目錄
    find "$CACHE_DIR" -type d -empty -delete 2>/dev/null || true
}

# 性能統計
show_performance_stats() {
    log_info "=== 性能統計 ==="
    echo "緩存目錄: $CACHE_DIR"
    
    if [ -d "$CACHE_DIR" ]; then
        local cache_size
        cache_size=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)
        echo "緩存大小: $cache_size"
        
        local cache_files
        cache_files=$(find "$CACHE_DIR" -type f | wc -l)
        echo "緩存文件數: $cache_files"
    else
        echo "緩存目錄不存在"
    fi
    
    echo "最大並行任務: $MAX_PARALLEL_JOBS"
    echo "緩存過期時間: $CACHE_EXPIRE_HOURS 小時"
}

# 命令行接口
case "${1:-help}" in
    "benchmark")
        run_performance_benchmark
        ;;
    "optimize")
        optimize_system_performance
        ;;
    "network")
        optimize_network_settings
        ;;
    "parallel")
        shift
        smart_parallel_execution "$@"
        ;;
    "apt-optimize")
        optimize_apt_performance
        ;;
    "cleanup")
        cleanup_cache
        ;;
    "stats")
        show_performance_stats
        ;;
    "all")
        log_info "執行完整性能優化..."
        run_performance_benchmark
        optimize_system_performance
        cleanup_cache
        log_success "完整性能優化完成"
        ;;
    *)
        echo "系統性能優化工具"
        echo ""
        echo "用法: $0 <command>"
        echo ""
        echo "命令:"
        echo "  benchmark          運行性能基準測試"
        echo "  optimize           全系統性能優化"
        echo "  network            優化網絡設置"
        echo "  parallel <tasks>   智能並行任務執行"
        echo "  apt-optimize       優化 APT 包管理器"
        echo "  cleanup            清理快取系統"
        echo "  stats              顯示快取統計"
        echo "  all                執行完整優化流程"
        echo ""
        echo "範例:"
        echo "  $0 benchmark       # 測試系統性能"
        echo "  $0 optimize        # 優化整個系統"
        echo "  $0 all            # 完整優化流程"
        ;;
esac

log_success "########## 性能優化工具執行完成 ##########"