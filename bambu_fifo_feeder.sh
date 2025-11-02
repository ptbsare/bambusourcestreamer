#!/bin/bash

# == Bambu FIFO Feeder 脚本 ==
#
# 功能:
# 1. 创建一个 named pipe (FIFO)
# 2. 持续运行 bambu_source 并将输出写入 FIFO
# 3. 多个客户端可以从同一个 FIFO 读取，但只有一个 bambu_source 连接到打印机
# 4. 如果 bambu_source 崩溃，自动重启

# --- 配置 ---
PLUGIN_DIR="/config/.config/BambuStudio/plugins"
TOOL_DIR="/config/.config/BambuStudio/cameratools"
URL_FILE="$TOOL_DIR/url.txt"
FIFO_PATH="/tmp/bambu_video.fifo"
DEFAULT_URL="bambu:///tutk?uid=YOUR_UID_HERE"

# --- 脚本主体 ---
echo "🎥 Bambu FIFO Feeder 启动..."

# 获取 URL
if [ -n "$BAMBU_URL" ]; then
    URL="$BAMBU_URL"
    echo "✅ 使用环境变量 BAMBU_URL"
elif [ -f "$URL_FILE" ]; then
    URL=$(cat "$URL_FILE" 2>/dev/null || echo "")
    if [[ "$URL" != "bambu:///"* ]]; then
        URL="$DEFAULT_URL"
        echo "⚠️  url.txt 无效，使用默认 URL"
    else
        echo "✅ 从 url.txt 读取 URL"
    fi
else
    URL="$DEFAULT_URL"
    echo "ℹ️  使用默认 URL"
fi

echo "URL: $URL"
echo "FIFO: $FIFO_PATH"
echo ""

# 创建 FIFO（如果不存在）
if [ ! -p "$FIFO_PATH" ]; then
    mkfifo "$FIFO_PATH"
    echo "✅ 已创建 FIFO: $FIFO_PATH"
fi

# 清理函数
cleanup() {
    echo ""
    echo "🛑 正在停止..."
    rm -f "$FIFO_PATH"
    exit 0
}

trap cleanup SIGINT SIGTERM

# 主循环：持续运行 bambu_source
RETRY_COUNT=0
while true; do
    echo "🚀 启动 bambu_source (尝试 #$((RETRY_COUNT + 1)))..."
    
    # 以 abc 用户身份运行 bambu_source，输出到 FIFO
    # 注意：写入 FIFO 会阻塞直到有读取者
    su abc -c "LD_LIBRARY_PATH='$PLUGIN_DIR' '$TOOL_DIR/bambu_source' '$URL'" > "$FIFO_PATH" 2>&1
    
    EXIT_CODE=$?
    echo "⚠️  bambu_source 退出 (退出码: $EXIT_CODE)"
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    
    # 如果连续失败太多次，增加等待时间
    if [ $RETRY_COUNT -gt 5 ]; then
        SLEEP_TIME=30
    elif [ $RETRY_COUNT -gt 2 ]; then
        SLEEP_TIME=10
    else
        SLEEP_TIME=5
    fi
    
    echo "⏳ 等待 $SLEEP_TIME 秒后重试..."
    sleep $SLEEP_TIME
done