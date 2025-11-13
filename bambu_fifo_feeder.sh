#!/bin/bash

# == Bambu FIFO Feeder (Guardian) Script ==
#
# v3.0 - 实现了动态 URL 刷新、智能发现和错误日志捕获
#
# 功能:
# 1. 持续监控并运行 bambu_source 进程
# 2. 在每次启动前，以 'abc' 用户身份动态获取最新的串流 URL
# 3. 如果 bambu_source 退出，脚本会自动获取新 URL 并重启它
# 4. 捕获 bambu_source 的错误日志并输出到容器日志中

# --- 配置 ---
INSTALL_DIR="/config/.config/BambuStudio/cameratools"
BAMBU_SOURCE_BIN="$INSTALL_DIR/bambu_source"
URL_GENERATOR_SCRIPT="$INSTALL_DIR/bambu_url_generator.py"
FIFO_PATH="/tmp/bambu_video.fifo"

# --- 日志函数 ---
log() {
    echo " feeder  [$(date +'%Y-%m-%d %H:%M:%S')] | $1"
}
log_error() {
    echo " feeder  [$(date +'%Y-%m-%d %H:%M:%S')] | ❌ 错误: $1"
}
log_info() {
    echo " feeder  [$(date +'%Y-%m-%d %H:%M:%S')] | ℹ️  $1"
}
log_warn() {
    echo " feeder  [$(date +'%Y-%m-%d %H:%M:%S')] | ⚠️  $1"
}

# --- 脚本主体 ---
log "🎥 Bambu FIFO Feeder 守护脚本启动..."

# 智能获取打印机序列号
TARGET_SERIAL=""
if [ -n "$PRINTER_SERIAL" ]; then
    log_info "使用环境变量中指定的打印机序列号: $PRINTER_SERIAL"
    TARGET_SERIAL="$PRINTER_SERIAL"
else
    log_info "未指定打印机序列号，正在以 'abc' 用户身份自动检测..."
    
    PRINTER_INFO_OUTPUT=$(gosu abc python3 "$URL_GENERATOR_SCRIPT" --discover 2>&1)
    
    if [ $? -ne 0 ] || [ -z "$PRINTER_INFO_OUTPUT" ]; then
        if [[ "$PRINTER_INFO_OUTPUT" == *"ERROR: NO_TOKEN_FOUND"* ]]; then
            log_error "未找到有效的登录凭证 (Token)。"
            log_info "请在 Docker **宿主机**上执行以下命令进行交互式登录:"
            log_info "   docker exec -it -u abc bambustudio bash -c 'python3 $URL_GENERATOR_SCRIPT --login'"
        else
            log_error "自动发现打印机失败。详情: $PRINTER_INFO_OUTPUT"
        fi
        log_info "将在 60 秒后重试..."
        sleep 60
        exec "$0"
    fi

    NUM_PRINTERS=$(echo "$PRINTER_INFO_OUTPUT" | wc -l)
    
    if [ "$NUM_PRINTERS" -eq 1 ]; then
        TARGET_SERIAL=$(echo "$PRINTER_INFO_OUTPUT" | cut -d' ' -f1)
        PRINTER_NAME=$(echo "$PRINTER_INFO_OUTPUT" | cut -d' ' -f2-)
        log "✅ 自动发现唯一的打印机: $PRINTER_NAME (序列号: $TARGET_SERIAL)"
    else
        log_error "您的账户下有多台打印机，请在 Docker 环境变量中设置 'PRINTER_SERIAL' 来指定一台。"
        log_info "可用打印机:"
        echo "$PRINTER_INFO_OUTPUT" | while IFS= read -r line; do log_info "     - $line"; done
        exit 1
    fi
fi

if [ ! -p "$FIFO_PATH" ]; then
    mkfifo "$FIFO_PATH"
    log "✅ 已创建 FIFO: $FIFO_PATH"
fi

cleanup() {
    log "🛑 正在停止 Feeder..."
    if [ ! -z "$BAMBU_SOURCE_PID" ] && kill -0 "$BAMBU_SOURCE_PID" 2>/dev/null; then kill -TERM "$BAMBU_SOURCE_PID"; fi
    rm -f "$FIFO_PATH"
    log "✅ Feeder 已停止。"
    exit 0
}
trap cleanup SIGINT SIGTERM

RETRY_COUNT=0
while true; do
    log "🔄 [尝试 #$((RETRY_COUNT + 1))] 正在获取新的串流 URL..."
    
    URL=$(gosu abc python3 "$URL_GENERATOR_SCRIPT" -s "$TARGET_SERIAL" -q)

    if [[ -z "$URL" || ! "$URL" == bambu://* ]]; then
        log_error "获取 URL 失败。可能是登录凭证已过期。"
        log_info "将在 60 秒后重试..."
        sleep 60
        continue
    fi
    
    SAFE_URL=$(echo "$URL" | sed -e 's/passwd=[^&]*/passwd=*****/g' -e 's/authkey=[^&]*/authkey=*****/g')
    log "✅ 成功获取 URL: $SAFE_URL"
    log "🚀 正在以 'abc' 用户身份启动 bambu_source..."

    # 创建一个临时文件来捕获 stderr
    ERR_LOG=$(mktemp)
    
    # 使用 gosu 运行，stdout 重定向到 FIFO，stderr 重定向到临时文件
    gosu abc "$BAMBU_SOURCE_BIN" "$URL" > "$FIFO_PATH" 2> "$ERR_LOG" &
    BAMBU_SOURCE_PID=$!
    wait "$BAMBU_SOURCE_PID"
    EXIT_CODE=$?
    
    # 读取并打印错误日志
    BAMBU_SOURCE_ERROR=$(cat "$ERR_LOG")
    rm -f "$ERR_LOG"

    log_warn "bambu_source 进程已退出 (退出码: $EXIT_CODE)。"
    if [ -n "$BAMBU_SOURCE_ERROR" ]; then
        log_warn "错误日志如下:"
        # 逐行打印错误日志，增加缩进，使其更美观
        echo "$BAMBU_SOURCE_ERROR" | while IFS= read -r line; do log_warn "   | $line"; done
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    
    SLEEP_TIME=3
    if [ $RETRY_COUNT -gt 5 ]; then SLEEP_TIME=30;
    elif [ $RETRY_COUNT -gt 2 ]; then SLEEP_TIME=10; fi
    
    log "⏳ 等待 $SLEEP_TIME 秒后重试..."
    sleep $SLEEP_TIME
done