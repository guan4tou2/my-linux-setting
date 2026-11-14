#!/bin/bash
# shellcheck shell=bash
# 日誌：初始化與輪替、各等級的輸出函式、步驟進度顯示。
# 由 scripts/core/common.sh 載入（source），不可單獨執行。

# ==============================================================================
# Logging Functions
# ==============================================================================

# Initialize logging with rotation
init_logging() {
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local log_prefix="common_$timestamp.log"

    # Create log directory
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    chmod 0700 "$LOG_DIR" 2>/dev/null || true

    # Set log file path
    LOG_FILE="${LOG_FILE:-$LOG_DIR/$log_prefix}"

    # Rotate old logs
    rotate_logs

    # Set global logging flag
    ENABLE_LOGGING="${ENABLE_LOGGING:-true}"
}

# Rotate log files based on size, age, and count
rotate_logs() {
    [ "${ENABLE_LOGGING:-true}" != "true" ] && return 0 || true

    # Clean logs older than MAX_LOG_AGE days
    find "$LOG_DIR" -type f -name "*.log" -mtime +$MAX_LOG_AGE -delete 2>/dev/null || true

    # Check log sizes and rotate if needed
    for log_file in "$LOG_DIR"/*.log; do
        [ -f "$log_file" ] || continue

        local file_size_mb
        file_size_mb=$(du -m "$log_file" 2>/dev/null | cut -f1)

        if [ "$file_size_mb" -ge "$MAX_LOG_SIZE" ]; then
            local new_name
            new_name="${log_file%.log}.$(date +%Y%m%d_%H%M%S).old"
            mv "$log_file" "$new_name" 2>/dev/null || true
        fi
    done

    # Keep only MAX_LOG_COUNT log files
    local log_count
    log_count=$(find "$LOG_DIR" -type f -name "*.log" | wc -l 2>/dev/null || echo 0)

    if [ "$log_count" -gt "$MAX_LOG_COUNT" ]; then
        find "$LOG_DIR" -type f -name "*.log" -printf '%T@%p\n' | \
            sort -n | head -n "$((log_count - MAX_LOG_COUNT))" | \
            cut -d@ -f2- | xargs rm -f 2>/dev/null || true
    fi
}

# Structured logging helper - 只寫入日誌文件
log_entry() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date -Iseconds 2>/dev/null || date +"%Y-%m-%dT%H:%M:%S")
    local pid=$$

    # 確保日誌文件存在
    [ -z "${LOG_FILE:-}" ] && return 0 || true

    case "${LOG_FORMAT:-text}" in
        json)
            printf '{"timestamp":"%s","level":"%s","pid":%d,"message":"%s"}\n' \
                "$timestamp" "$level" "$pid" "$message" >> "$LOG_FILE" 2>/dev/null || true
            ;;
        *)
            printf '%s [%s] [%d] %s\n' \
                "$timestamp" "$level" "$pid" "$message" >> "$LOG_FILE" 2>/dev/null || true
            ;;
    esac
}

_log_should_print_status_to_terminal() {
    case "${TUI_LOG_TO_TERMINAL:-auto}" in
        true) return 0 ;;
        false) return 1 ;;
    esac

    if [ "${NON_INTERACTIVE:-false}" = "true" ]; then
        return 0
    fi

    if [ "${TUI_MODE:-quiet}" = "quiet" ] && [ "${USE_TUI:-auto}" != "false" ]; then
        return 1
    fi

    return 0
}

log_error() {
    local message="$1"
    # 總是輸出到終端（錯誤訊息）
    printf "${RED}ERROR: %s${NC}\n" "$message" >&2
    # 如果啟用日誌，同時寫入日誌文件
    [ "${ENABLE_LOGGING:-false}" = "true" ] && log_entry "ERROR" "$message"
    return 1
}

log_info() {
    local message="$1"
    # TUI quiet 模式下只寫入日誌，避免狀態訊息刷在 TUI 背後
    if _log_should_print_status_to_terminal; then
        printf "${CYAN}INFO: %s${NC}\n" "$message"
    fi
    # 如果啟用日誌，同時寫入日誌文件
    [ "${ENABLE_LOGGING:-false}" = "true" ] && log_entry "INFO" "$message" || true
}

log_success() {
    local message="$1"
    # TUI quiet 模式下只寫入日誌，避免狀態訊息刷在 TUI 背後
    if _log_should_print_status_to_terminal; then
        printf "${GREEN}SUCCESS: %s${NC}\n" "$message"
    fi
    # 如果啟用日誌，同時寫入日誌文件
    [ "${ENABLE_LOGGING:-false}" = "true" ] && log_entry "SUCCESS" "$message" || true
}

log_warning() {
    local message="$1"
    # TUI quiet 模式下只寫入日誌，避免狀態訊息刷在 TUI 背後
    if _log_should_print_status_to_terminal; then
        printf "${YELLOW}WARNING: %s${NC}\n" "$message"
    fi
    # 如果啟用日誌，同時寫入日誌文件
    [ "${ENABLE_LOGGING:-false}" = "true" ] && log_entry "WARNING" "$message" || true
}

log_debug() {
    local message="$1"
    # DEBUG 模式未啟用時直接返回
    [ "${DEBUG:-false}" != "true" ] && return 0 || true
    # TUI quiet 模式下只寫入日誌，避免狀態訊息刷在 TUI 背後
    if _log_should_print_status_to_terminal; then
        printf "${BLUE}DEBUG: %s${NC}\n" "$message"
    fi
    # 如果啟用日誌，同時寫入日誌文件
    [ "${ENABLE_LOGGING:-false}" = "true" ] && log_entry "DEBUG" "$message" || true
}

# ==============================================================================
# 進度顯示函數
# ==============================================================================

TOTAL_STEPS=0
CURRENT_STEP=0

init_progress() {
    local total="$1"
    TOTAL_STEPS="$total"
    CURRENT_STEP=0
}

show_progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local message="${1:-Processing...}"
    local percent=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    local bar_length=50
    local filled_length=$((percent * bar_length / 100))
    
    local bar=""
    for _ in $(seq 1 $filled_length); do bar="${bar}#"; done
    for _ in $(seq $((filled_length + 1)) $bar_length); do bar="${bar}-"; done
    
    printf "\r${CYAN}[%s] %d%% - %s${NC}" "$bar" "$percent" "$message"
    if [ "$CURRENT_STEP" -eq "$TOTAL_STEPS" ]; then
        printf "\n"
    fi
}
