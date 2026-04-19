#!/usr/bin/env bash

# 測試報告生成器 - 生成綜合測試報告

# 載入共用函數庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" || exit 1

readonly REPORT_DIR="$HOME/.local/log/test-reports"
readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 初始化報告目錄
init_report_dir() {
    mkdir -p "$REPORT_DIR"
    log_success "報告目錄已創建: $REPORT_DIR"
}

# 生成系統信息報告
generate_system_report() {
    local report_file="$REPORT_DIR/system_info_$TIMESTAMP.json"
    
    {
        echo "{"
        echo "  \"timestamp\": \"$(date -Iseconds)\","
        echo "  \"hostname\": \"$(hostname)\","
        echo "  \"os\": {"
        if [ -f /etc/os-release ]; then
            echo "    \"name\": \"$(grep '^NAME=' /etc/os-release | cut -d'=' -f2 | tr -d '\"')\","
            echo "    \"version\": \"$(grep '^VERSION=' /etc/os-release | cut -d'=' -f2 | tr -d '\"')\","
            echo "    \"id\": \"$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '\"')\""
        else
            echo "    \"name\": \"Unknown\","
            echo "    \"version\": \"Unknown\","
            echo "    \"id\": \"unknown\""
        fi
        echo "  },"
        echo "  \"architecture\": \"$(uname -m)\","
        echo "  \"kernel\": \"$(uname -r)\","
        echo "  \"python\": {"
        if command -v python3 >/dev/null; then
            echo "    \"version\": \"$(python3 --version 2>&1 | cut -d' ' -f2)\","
            echo "    \"executable\": \"$(command -v python3)\""
        else
            echo "    \"version\": null,"
            echo "    \"executable\": null"
        fi
        echo "  },"
        echo "  \"environment\": {"
        echo "    \"test_mode\": \"${TEST_ENVIRONMENT:-native}\","
        echo "    \"skip_network\": \"${SKIP_NETWORK_TESTS:-false}\","
        echo "    \"user\": \"$(whoami)\","
        echo "    \"home\": \"$HOME\","
        echo "    \"path\": \"$PATH\""
        echo "  }"
        echo "}"
    } > "$report_file"
    
    echo "$report_file"
}

# 分析測試結果
analyze_test_results() {
    local test_logs=("$@")
    local summary_file="$REPORT_DIR/test_summary_$TIMESTAMP.json"
    
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    local warnings=0
    
    {
        echo "{"
        echo "  \"test_summary\": {"
        echo "    \"timestamp\": \"$(date -Iseconds)\","
        echo "    \"total_suites\": ${#test_logs[@]},"
        echo "    \"results\": ["
        
        local first=true
        for log_file in "${test_logs[@]}"; do
            [ "$first" = true ] && first=false || echo ","
            
            local suite_name
            suite_name=$(basename "$log_file" .log)
            
            local suite_passed suite_failed suite_warnings
            suite_passed=$(grep -c "\\[PASS\\]" "$log_file" 2>/dev/null || echo 0)
            suite_failed=$(grep -c "\\[FAIL\\]" "$log_file" 2>/dev/null || echo 0)
            suite_warnings=$(grep -c "\\[WARN\\]" "$log_file" 2>/dev/null || echo 0)
            
            total_tests=$((total_tests + suite_passed + suite_failed))
            passed_tests=$((passed_tests + suite_passed))
            failed_tests=$((failed_tests + suite_failed))
            warnings=$((warnings + suite_warnings))
            
            echo "      {"
            echo "        \"suite\": \"$suite_name\","
            echo "        \"passed\": $suite_passed,"
            echo "        \"failed\": $suite_failed,"
            echo "        \"warnings\": $suite_warnings"
            echo -n "      }"
        done
        
        echo ""
        echo "    ],"
        echo "    \"totals\": {"
        echo "      \"tests\": $total_tests,"
        echo "      \"passed\": $passed_tests,"
        echo "      \"failed\": $failed_tests,"
        echo "      \"warnings\": $warnings,"
        
        local success_rate=0
        [ $total_tests -gt 0 ] && success_rate=$((passed_tests * 100 / total_tests))
        
        echo "      \"success_rate\": $success_rate"
        echo "    }"
        echo "  }"
        echo "}"
    } > "$summary_file"
    
    echo "$summary_file"
}

# 生成 HTML 報告
generate_html_report() {
    local system_report="$1"
    local test_summary="$2"
    local html_file="$REPORT_DIR/test_report_$TIMESTAMP.html"
    
    {
        cat << 'EOF'
<!DOCTYPE html>
<html lang="zh-TW">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Linux Setting Scripts - 測試報告</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; line-height: 1.6; }
        .header { background: #f4f4f4; padding: 20px; border-radius: 5px; margin-bottom: 20px; }
        .section { margin-bottom: 30px; }
        .success { color: #28a745; }
        .warning { color: #ffc107; }
        .error { color: #dc3545; }
        .info { color: #17a2b8; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .progress-bar { width: 100%; background-color: #f0f0f0; border-radius: 3px; overflow: hidden; }
        .progress-fill { height: 20px; background-color: #28a745; transition: width 0.3s; }
        .badge { padding: 4px 8px; border-radius: 3px; font-size: 0.8em; color: white; }
        .badge-success { background-color: #28a745; }
        .badge-warning { background-color: #ffc107; }
        .badge-error { background-color: #dc3545; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🧪 Linux Setting Scripts 測試報告</h1>
        <p><strong>生成時間:</strong> <span id="timestamp"></span></p>
        <p><strong>測試環境:</strong> <span id="environment"></span></p>
    </div>

    <div class="section">
        <h2>📊 測試總覽</h2>
        <div id="test-overview"></div>
        <div class="progress-bar">
            <div class="progress-fill" id="progress-fill"></div>
        </div>
        <p style="text-align: center; margin-top: 10px;">
            成功率: <span id="success-rate" class="success"></span>
        </p>
    </div>

    <div class="section">
        <h2>🖥️ 系統信息</h2>
        <div id="system-info"></div>
    </div>

    <div class="section">
        <h2>📋 測試詳情</h2>
        <div id="test-details"></div>
    </div>

    <div class="section">
        <h2>💡 建議</h2>
        <div id="recommendations"></div>
    </div>

    <script>
EOF

        # 內嵌 JavaScript 處理數據
        echo "        const systemData = "
        cat "$system_report"
        echo ";"
        echo "        const testData = "
        cat "$test_summary"
        echo ";"
        
        cat << 'EOF'
        
        // 渲染報告
        document.getElementById('timestamp').textContent = new Date(systemData.timestamp).toLocaleString();
        document.getElementById('environment').textContent = systemData.environment.test_mode;
        
        const totals = testData.test_summary.totals;
        const successRate = totals.success_rate;
        
        document.getElementById('success-rate').textContent = successRate + '%';
        document.getElementById('progress-fill').style.width = successRate + '%';
        
        // 測試總覽
        document.getElementById('test-overview').innerHTML = `
            <table>
                <tr><th>項目</th><th>數量</th></tr>
                <tr><td>總測試數</td><td>${totals.tests}</td></tr>
                <tr><td class="success">通過</td><td>${totals.passed}</td></tr>
                <tr><td class="error">失敗</td><td>${totals.failed}</td></tr>
                <tr><td class="warning">警告</td><td>${totals.warnings}</td></tr>
            </table>
        `;
        
        // 系統信息
        document.getElementById('system-info').innerHTML = `
            <table>
                <tr><th>屬性</th><th>值</th></tr>
                <tr><td>主機名</td><td>${systemData.hostname}</td></tr>
                <tr><td>作業系統</td><td>${systemData.os.name} ${systemData.os.version}</td></tr>
                <tr><td>架構</td><td>${systemData.architecture}</td></tr>
                <tr><td>核心版本</td><td>${systemData.kernel}</td></tr>
                <tr><td>Python 版本</td><td>${systemData.python.version || 'N/A'}</td></tr>
                <tr><td>用戶</td><td>${systemData.environment.user}</td></tr>
            </table>
        `;
        
        // 測試詳情
        let detailsHtml = '<table><tr><th>測試套件</th><th>通過</th><th>失敗</th><th>警告</th><th>狀態</th></tr>';
        testData.test_summary.results.forEach(result => {
            const status = result.failed > 0 ? 'error' : (result.warnings > 0 ? 'warning' : 'success');
            const badge = result.failed > 0 ? 'badge-error' : (result.warnings > 0 ? 'badge-warning' : 'badge-success');
            const statusText = result.failed > 0 ? '失敗' : (result.warnings > 0 ? '警告' : '通過');
            
            detailsHtml += `
                <tr>
                    <td>${result.suite}</td>
                    <td class="success">${result.passed}</td>
                    <td class="error">${result.failed}</td>
                    <td class="warning">${result.warnings}</td>
                    <td><span class="badge ${badge}">${statusText}</span></td>
                </tr>
            `;
        });
        detailsHtml += '</table>';
        document.getElementById('test-details').innerHTML = detailsHtml;
        
        // 建議
        let recommendations = '<ul>';
        if (totals.failed > 0) {
            recommendations += '<li class="error">🔴 發現測試失敗，請檢查相關組件</li>';
        }
        if (totals.warnings > 5) {
            recommendations += '<li class="warning">⚠️ 警告較多，建議檢查系統配置</li>';
        }
        if (successRate >= 95) {
            recommendations += '<li class="success">✅ 測試通過率高，系統狀態良好</li>';
        }
        if (systemData.architecture === 'aarch64') {
            recommendations += '<li class="info">📱 ARM64 架構檢測到，某些功能可能需要特殊處理</li>';
        }
        recommendations += '</ul>';
        document.getElementById('recommendations').innerHTML = recommendations;
    </script>
</body>
</html>
EOF
    } > "$html_file"
    
    echo "$html_file"
}

# 主要報告生成流程
generate_comprehensive_report() {
    init_report_dir
    
    log_info "生成綜合測試報告..."
    
    # 查找測試日誌
    local test_logs=()
    if [ -d "$HOME/.local/log/linux-setting" ]; then
        while IFS= read -r -d '' file; do
            test_logs+=("$file")
        done < <(find "$HOME/.local/log/linux-setting" -name "*.log" -type f -print0 2>/dev/null)
    fi
    
    # 生成系統信息報告
    local system_report
    system_report=$(generate_system_report)
    log_success "系統信息報告: $system_report"
    
    # 分析測試結果
    local test_summary
    test_summary=$(analyze_test_results "${test_logs[@]}")
    log_success "測試摘要報告: $test_summary"
    
    # 生成 HTML 報告
    local html_report
    html_report=$(generate_html_report "$system_report" "$test_summary")
    log_success "HTML 報告: $html_report"
    
    echo ""
    echo "📊 報告生成完成！"
    echo "📁 報告目錄: $REPORT_DIR"
    echo "🌐 HTML 報告: $html_report"
    echo ""
    echo "要查看 HTML 報告，請在瀏覽器中打開上述文件"
}

# 命令行接口
case "${1:-help}" in
    "generate")
        generate_comprehensive_report
        ;;
    "system")
        init_report_dir
        generate_system_report
        ;;
    "analyze")
        init_report_dir
        shift
        analyze_test_results "$@"
        ;;
    *)
        echo "測試報告生成器"
        echo ""
        echo "用法: $0 <command>"
        echo ""
        echo "命令:"
        echo "  generate    生成綜合測試報告"
        echo "  system      僅生成系統信息報告"
        echo "  analyze     分析指定的測試日誌"
        echo ""
        echo "範例:"
        echo "  $0 generate                    # 生成完整報告"
        echo "  $0 analyze test1.log test2.log # 分析特定日誌"
        ;;
esac