#!/bin/bash

# == Bambu FIFO Feeder (Guardian) Script ==
#
# 功能:
# 1. 持续监控并运行 bambu_source 进程
# 2. 在每次启动 bambu_source 前，动态获取最新的串流 URL
# 3. 如果 bambu_source 退出 (例如 URL 过期)，脚本会自动获取新 URL 并重启它
# 4. 将所有日志输出到标准输出，方便 Docker 容器日志收集

# --- 配置 ---
INSTALL_DIR="/config/.config/BambuStudio/cameratools"
BAMBU_SOURCE_BIN="$INSTALL_DIR/bambu_source"
URL_GENERATOR_SCRIPT="$INSTALL_DIR/bambu_url_generator.py"
FIFO_PATH="/tmp/bambu_video.fifo"

# --- 脚本主体 ---
log() {
    echo "[Feeder] [$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "🎥 Bambu FIFO Feeder 守护脚本启动..."

# 智能获取打印机序列号
TARGET_SERIAL=""
if [ -n "$PRINTER_SERIAL" ]; then
    log "ℹ️ 使用环境变量中指定的打印机序列号: $PRINTER_SERIAL"
    TARGET_SERIAL="$PRINTER_SERIAL"
else
    log "🔎 未指定打印机序列号，正在自动检测..."
    # 调用 python 脚本获取设备列表并选择
    # 使用一种特殊模式让 python 脚本输出可解析的设备信息
    PRINTER_INFO=$(python3 "$URL_GENERATOR_SCRIPT" --discover)
    
    if [ $? -ne 0 ]; then
        log "❌ 自动发现打印机失败。请检查登录状态或网络。"
        exit 1
    fi

    NUM_PRINTERS=$(echo "$PRINTER_INFO" | wc -l)
    
    if [ "$NUM_PRINTERS" -eq 1 ]; then
        TARGET_SERIAL=$(echo "$PRINTER_INFO" | cut -d' ' -f1)
        PRINTER_NAME=$(echo "$PRINTER_INFO" | cut -d' ' -f2-)
        log "✅ 自动发现唯一的打印机: $PRINTER_NAME (序列号: $TARGET_SERIAL)"
    elif [ "$NUM_PRINTERS" -gt 1 ]; then
        log "❌ 错误：您的账户下有多台打印机，请设置 'PRINTER_SERIAL' 环境变量来指定一台。"
        log "   可用打印机:"
        echo "$PRINTER_INFO" | while IFS= read -r line; do log "     - $line"; done
        exit 1
    else
        log "❌ 错误：未在您的账户下找到任何打印机。"
        exit 1
    fi
fi

# 创建 FIFO (如果不存在)
if [ ! -p "$FIFO_PATH" ]; then
    mkfifo "$FIFO_PATH"
    log "✅ 已创建 FIFO: $FIFO_PATH"
fi

# 清理函数
cleanup() {
    log "🛑 正在停止 Feeder..."
    # kill a bambu_source 子进程
    if [ ! -z "$BAMBU_SOURCE_PID" ] && kill -0 "$BAMBU_SOURCE_PID" 2>/dev/null; then
        kill "$BAMBU_SOURCE_PID"
    fi
    rm -f "$FIFO_PATH"
    log "✅ Feeder 已停止。"
    exit 0
}

trap cleanup SIGINT SIGTERM

# 主循环: 监控和运行 bambu_source
RETRY_COUNT=0
while true; do
    log "🔄 [尝试 #$((RETRY_COUNT + 1))] 正在获取新的串流 URL..."

    # 1. 动态获取 URL
    #    使用 -s (serial) 和 -q (quiet) 参数来直接获取 URL
    URL=$(python3 "$URL_GENERATOR_SCRIPT" -s "$TARGET_SERIAL" -q)

    # 检查 URL 是否有效
    if [[ -z "$URL" || ! "$URL" == bambu://* ]]; then
        log "❌ 获取 URL 失败。可能是登录凭证过期或网络问题。"
        log "   请尝试使用 '--login' 选项重新登录: ./start_bambu_fifo.sh --login"
        log "   将在 60 秒后重试..."
        sleep 60
        continue
    fi
    
    # 隐藏日志中的敏感信息
    SAFE_URL=$(echo "$URL" | sed -e 's/passwd=[^&]*/passwd=*****/g' -e 's/authkey=[^&]*/authkey=*****/g')
    log "✅ 成功获取 URL: $SAFE_URL"
    log "🚀 正在启动 bambu_source..."

    # 2. 启动 bambu_source
    #    - 使用 gosu 以 'abc' 用户身份运行
    #    - 将标准输出重定向到 FIFO
    #    - 将标准错误重定向到此脚本的标准输出，以便 docker logs 捕获
    gosu abc "$BAMBU_SOURCE_BIN" "$URL" > "$FIFO_PATH" 2>&1 &
    BAMBU_SOURCE_PID=$!

    # 等待子进程结束
    wait "$BAMBU_SOURCE_PID"
    EXIT_CODE=$?
    
    log "⚠️ bambu_source 进程已退出 (退出码: $EXIT_CODE)。可能是 URL 过期，将自动刷新。"
    RETRY_COUNT=$((RETRY_COUNT + 1))
    
    # 失败退避策略
    if [ $RETRY_COUNT -gt 5 ]; then
        SLEEP_TIME=30
    elif [ $RETRY_COUNT -gt 2 ]; then
        SLEEP_TIME=10
    else
        SLEEP_TIME=3
    fi
    
    log "⏳ 等待 $SLEEP_TIME 秒后重试..."
    sleep $SLEEP_TIME
done