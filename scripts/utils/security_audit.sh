#!/usr/bin/env bash

# 安全審計工具 - 檢查安裝腳本的安全問題

# 載入共用函數庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || exit 1

mkdir -p "$HOME/.local/log"
readonly AUDIT_REPORT="$HOME/.local/log/security_audit_$(date +%Y%m%d_%H%M%S).txt"
export LOG_FILE="${LOG_FILE:-$AUDIT_REPORT}"

# 危險模式列表
readonly DANGEROUS_PATTERNS=(
    "curl.*|.*sh"
    "wget.*|.*sh"
    "bash -c.*curl"
    "sh -c.*curl"
    "eval.*curl"
    "eval.*wget"
    "rm -rf /"
    "chmod 777"
    "chown.*root"
    "> /etc/passwd"
    "> /etc/shadow"
    "mkfs\."
    "dd if="
)

# 可疑權限操作
readonly PRIVILEGE_PATTERNS=(
    "sudo.*without.*password"
    "NOPASSWD:ALL"
    "usermod -aG.*sudo"
    "chmod.*u+s"
    "chown.*root.*suid"
)

# 網路操作模式
readonly NETWORK_PATTERNS=(
    "curl.*-o.*sh"
    "wget.*-O.*sh"
    "nc -l"
    "netcat.*-l"
    "python.*-m.*http.server"
    "python.*SimpleHTTPServer"
)

# 檢查單個文件
check_file_security() {
    local file="$1"
    local findings=0
    
    if [ ! -f "$file" ]; then
        return 0
    fi
    
    echo "檢查文件: $file" >> "$AUDIT_REPORT"
    echo "======================================" >> "$AUDIT_REPORT"
    
    # 檢查危險模式
    for pattern in "${DANGEROUS_PATTERNS[@]}"; do
        if grep -n -i "$pattern" "$file" >> "$AUDIT_REPORT" 2>/dev/null; then
            echo "🔴 危險模式: $pattern" >> "$AUDIT_REPORT"
            findings=$((findings + 1))
        fi
    done
    
    # 檢查權限操作
    for pattern in "${PRIVILEGE_PATTERNS[@]}"; do
        if grep -n -i "$pattern" "$file" >> "$AUDIT_REPORT" 2>/dev/null; then
            echo "🟡 權限操作: $pattern" >> "$AUDIT_REPORT"
            findings=$((findings + 1))
        fi
    done
    
    # 檢查網路操作
    for pattern in "${NETWORK_PATTERNS[@]}"; do
        if grep -n -i "$pattern" "$file" >> "$AUDIT_REPORT" 2>/dev/null; then
            echo "🟠 網路操作: $pattern" >> "$AUDIT_REPORT"
            findings=$((findings + 1))
        fi
    done
    
    # 檢查硬編碼 URL
    local urls
    urls=$(grep -o 'https\?://[^[:space:]]*' "$file" 2>/dev/null)
    if [ -n "$urls" ]; then
        echo "🔵 發現 URL:" >> "$AUDIT_REPORT"
        echo "$urls" >> "$AUDIT_REPORT"
    fi
    
    # 檢查 sudo 使用
    local sudo_count
    sudo_count=$(grep -c "sudo" "$file" 2>/dev/null || echo 0)
    if [ "$sudo_count" -gt 0 ] && [ "$sudo_count" -gt 5 ]; then
        echo "⚠️  過多 sudo 操作 ($sudo_count 次)" >> "$AUDIT_REPORT"
        findings=$((findings + 1))
    fi
    
    echo "" >> "$AUDIT_REPORT"
    echo "$findings"
}

# 檢查腳本權限
check_script_permissions() {
    local file="$1"
    local issues=0
    
    # 檢查是否可執行
    if [ ! -x "$file" ]; then
        echo "⚠️  腳本不可執行: $file" >> "$AUDIT_REPORT"
        issues=$((issues + 1))
    fi
    
    # 檢查擁有者
    local owner
    owner=$(stat -c "%U" "$file" 2>/dev/null || stat -f "%Su" "$file" 2>/dev/null)
    if [ "$owner" = "root" ]; then
        echo "🔴 root 擁有的腳本: $file" >> "$AUDIT_REPORT"
        issues=$((issues + 1))
    fi
    
    # 檢查權限
    local perms
    perms=$(stat -c "%a" "$file" 2>/dev/null || stat -f "%A" "$file" 2>/dev/null)
    if [[ "$perms" =~ 7[0-9][0-9] ]]; then
        echo "🟡 過寬權限 ($perms): $file" >> "$AUDIT_REPORT"
        issues=$((issues + 1))
    fi
    
    echo "$issues"
}

# 主要安全審計
run_security_audit() {
    log_info "開始安全審計..."
    
    # 初始化報告文件
    {
        echo "Linux Setting Scripts 安全審計報告"
        echo "生成時間: $(date)"
        echo "審計主機: $(hostname)"
        echo "審計用戶: $(whoami)"
        echo "========================================"
        echo ""
    } > "$AUDIT_REPORT"
    
    local total_findings=0
    local total_files=0
    
    # 檢查所有腳本文件
    log_info "檢查腳本安全性..."
    for script in "$SCRIPT_DIR"/../*.sh "$SCRIPT_DIR"/*.sh; do
        if [ -f "$script" ]; then
            total_files=$((total_files + 1))
            local findings
            findings=$(check_file_security "$script")
            total_findings=$((total_findings + findings))
            
            local perm_issues
            perm_issues=$(check_script_permissions "$script")
            total_findings=$((total_findings + perm_issues))
            
            if [ "$findings" -eq 0 ] && [ "$perm_issues" -eq 0 ]; then
                echo "✅ $(basename "$script"): 安全" >> "$AUDIT_REPORT"
            fi
        fi
    done
    
    # 生成摘要
    {
        echo ""
        echo "========================================"
        echo "安全審計摘要"
        echo "========================================"
        echo "檢查文件數: $total_files"
        echo "發現問題數: $total_findings"
        echo ""
        
        if [ "$total_findings" -eq 0 ]; then
            echo "🎉 恭喜！未發現安全問題"
        elif [ "$total_findings" -le 5 ]; then
            echo "⚠️  發現少量安全問題，建議修復"
        else
            echo "🔴 發現多個安全問題，需要立即處理"
        fi
        
        echo ""
        echo "建議："
        echo "1. 檢查所有標記為危險的模式"
        echo "2. 驗證所有外部 URL 的可信度"
        echo "3. 限制 sudo 操作的使用"
        echo "4. 使用安全下載機制替代直接執行"
        echo ""
        echo "詳細報告: $AUDIT_REPORT"
        
    } >> "$AUDIT_REPORT"
    
    # 顯示結果
    cat "$AUDIT_REPORT"
    
    echo ""
    log_success "安全審計完成"
    echo "📄 完整報告: $AUDIT_REPORT"
    
    # 返回適當的退出碼
    if [ "$total_findings" -gt 10 ]; then
        return 2  # 嚴重問題
    elif [ "$total_findings" -gt 0 ]; then
        return 1  # 一般問題
    else
        return 0  # 無問題
    fi
}

# 修復建議生成器
generate_fix_recommendations() {
    log_info "生成安全修復建議..."
    
    local fix_file="${AUDIT_REPORT%.txt}_fixes.txt"
    
    {
        echo "安全修復建議"
        echo "===================="
        echo ""
        
        echo "1. 替換危險的遠程執行："
        echo "   將 'curl ... | sh' 替換為安全下載機制"
        echo "   使用 secure_download.sh 進行驗證下載"
        echo ""
        
        echo "2. 限制權限操作："
        echo "   避免使用 NOPASSWD:ALL"
        echo "   使用最小權限原則"
        echo "   驗證 sudo 操作的必要性"
        echo ""
        
        echo "3. 驗證外部資源："
        echo "   檢查所有外部 URL 的可信度"
        echo "   添加 checksum 驗證"
        echo "   使用 HTTPS 而非 HTTP"
        echo ""
        
        echo "4. 改進錯誤處理："
        echo "   添加適當的錯誤檢查"
        echo "   實施回滾機制"
        echo "   記錄詳細的操作日誌"
        echo ""
        
        echo "5. 代碼審查："
        echo "   定期運行安全審計"
        echo "   代碼審查新增腳本"
        echo "   使用靜態分析工具"
        
    } > "$fix_file"
    
    echo "$fix_file"
}

# 快速安全檢查
quick_security_check() {
    local script="$1"
    
    if [ ! -f "$script" ]; then
        log_error "文件不存在: $script"
        return 1
    fi
    
    log_info "快速安全檢查: $(basename "$script")"
    
    local issues=0
    
    # 檢查直接遠程執行
    if grep -q "curl.*|.*sh\|wget.*|.*sh" "$script"; then
        log_warning "發現直接遠程執行模式"
        issues=$((issues + 1))
    fi
    
    # 檢查危險命令
    if grep -q "rm -rf /\|mkfs\.\|dd if=" "$script"; then
        log_error "發現極危險命令"
        issues=$((issues + 1))
    fi
    
    # 檢查權限操作
    local sudo_count
    sudo_count=$(grep -c "sudo" "$script" 2>/dev/null || echo 0)
    if [ "$sudo_count" -gt 0 ] && [ "$sudo_count" -gt 10 ]; then
        log_warning "過多 sudo 操作 ($sudo_count 次)"
        issues=$((issues + 1))
    fi
    
    if [ "$issues" -eq 0 ]; then
        log_success "快速檢查通過"
    else
        log_warning "發現 $issues 個潛在問題"
    fi
    
    return $issues
}

# 命令行接口
case "${1:-help}" in
    "audit")
        run_security_audit
        ;;
    "quick")
        if [ -z "$2" ]; then
            log_error "請指定要檢查的腳本文件"
            exit 1
        fi
        quick_security_check "$2"
        ;;
    "fix-recommendations")
        generate_fix_recommendations
        ;;
    "check-all")
        exit_code=0
        for script in "$SCRIPT_DIR"/../*.sh "$SCRIPT_DIR"/*.sh; do
            if [ -f "$script" ]; then
                quick_security_check "$script" || exit_code=1
            fi
        done
        exit $exit_code
        ;;
    *)
        echo "安全審計工具"
        echo ""
        echo "用法: $0 <command> [選項]"
        echo ""
        echo "命令:"
        echo "  audit                     完整安全審計"
        echo "  quick <script>           快速檢查單個腳本"
        echo "  fix-recommendations     生成修復建議"
        echo "  check-all               檢查所有腳本"
        echo ""
        echo "範例:"
        echo "  $0 audit                 # 完整審計"
        echo "  $0 quick install.sh      # 快速檢查"
        echo "  $0 check-all            # 檢查所有腳本"
        ;;
esac