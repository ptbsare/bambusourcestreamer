#!/bin/bash

# == Bambu FIFO + go2rtc 启动脚本 ==
#
# 功能:
# 1. 启动 FIFO feeder（后台运行）
# 2. 启动 go2rtc 服务器
# 3. 统一管理两个进程

# --- 配置 ---
SCRIPT_DIR="/config/.config/BambuStudio/cameratools"
FEEDER_SCRIPT="$SCRIPT_DIR/bambu_fifo_feeder.sh"
GO2RTC="$SCRIPT_DIR/go2rtc"
CONFIG_FILE="$SCRIPT_DIR/go2rtc_fifo.yaml"
FEEDER_PID_FILE="/tmp/bambu_fifo_feeder.pid"

# --- 脚本主体 ---
cd "$SCRIPT_DIR" || exit 1

echo "🚀 Bambu FIFO + go2rtc 启动脚本"
echo ""

# 确保脚本有执行权限
chmod +x "$FEEDER_SCRIPT" 2>/dev/null

# 清理函数
cleanup() {
    echo ""
    echo "🛑 正在停止所有服务..."
    
    # 停止 FIFO feeder
    if [ -f "$FEEDER_PID_FILE" ]; then
        FEEDER_PID=$(cat "$FEEDER_PID_FILE")
        if kill -0 "$FEEDER_PID" 2>/dev/null; then
            echo "停止 FIFO feeder (PID: $FEEDER_PID)..."
            kill "$FEEDER_PID"
            wait "$FEEDER_PID" 2>/dev/null
        fi
        rm -f "$FEEDER_PID_FILE"
    fi
    
    # 清理 FIFO
    rm -f /tmp/bambu_video.fifo
    
    echo "✅ 所有服务已停止"
    exit 0
}

trap cleanup SIGINT SIGTERM

# 检查 FIFO feeder 是否已在运行
if [ -f "$FEEDER_PID_FILE" ]; then
    OLD_PID=$(cat "$FEEDER_PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "⚠️  FIFO feeder 已在运行 (PID: $OLD_PID)"
        echo "如需重启，请先停止: kill $OLD_PID"
        SKIP_FEEDER=true
    else
        rm -f "$FEEDER_PID_FILE"
    fi
fi

# 启动 FIFO feeder
if [ "$SKIP_FEEDER" != "true" ]; then
    echo "🎥 启动 FIFO feeder..."
    "$FEEDER_SCRIPT" &
    FEEDER_PID=$!
    echo $FEEDER_PID > "$FEEDER_PID_FILE"
    echo "✅ FIFO feeder 已启动 (PID: $FEEDER_PID)"
    
    # 等待 FIFO 创建
    sleep 2
fi

echo ""
echo "🌐 启动 go2rtc 服务器..."
echo ""
echo "访问方式:"
echo "  Web UI:  http://localhost:1984/"
echo "  RTSP:    rtsp://localhost:8554/bambulabx1c"
echo "  流名称:  bambulabx1c"
echo ""
echo "按 Ctrl+C 停止所有服务"
echo ""

# 启动 go2rtc（前台运行）
"$GO2RTC" -config "$CONFIG_FILE"

# 如果 go2rtc 退出，清理资源
cleanup