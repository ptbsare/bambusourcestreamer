#!/bin/bash
set -e

# == Bambu Streamer Service Script ==
#
# 功能:
# 1. 自动安装脚本和依赖 (go2rtc, git repos, etc.)
# 2. 校验用户是否已安装 Bambu Studio 插件
# 3. 提供 --login 选项进行云端认证
# 4. 启动和管理 bambu_source 和 go2rtc 服务
# 5. 实现 URL 自动刷新机制

# --- 全局配置 ---
INSTALL_DIR="/config/.config/BambuStudio/cameratools"
BAMBU_STREAMER_REPO="https://github.com/ptbsare/bambusourcestreamer.git"
BAMBU_CLOUD_API_REPO="https://github.com/coelacant1/Bambu-Lab-Cloud-API.git"
GO2RTC_REPO="AlexxIT/go2rtc"

# 派生路径
BAMBU_STREAMER_SRC_DIR="$INSTALL_DIR/bambusourcestreamer_src" # 临时克隆目录
BAMBU_CLOUD_API_DIR="$INSTALL_DIR/Bambu-Lab-Cloud-API"
FEEDER_SCRIPT="$INSTALL_DIR/bambu_fifo_feeder.sh"
URL_GENERATOR_SCRIPT="$INSTALL_DIR/bambu_url_generator.py"
GO2RTC_BIN="$INSTALL_DIR/go2rtc"
BAMBU_SOURCE_BIN="$INSTALL_DIR/bambu_source"
CONFIG_FILE="$INSTALL_DIR/go2rtc_fifo.yaml"
FEEDER_PID_FILE="/tmp/bambu_fifo_feeder.pid"

# --- 模块化函数 ---

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# 依赖检查与安装模块
install_and_verify_dependencies() {
    log "🔎 正在检查和安装依赖项..."
    mkdir -p "$INSTALL_DIR"

    # 1. 检查核心工具 (git, curl, unzip, jq)
    for cmd in git curl unzip jq gosu; do
        if ! command -v $cmd &> /dev/null; then
            log "📦 未找到 '$cmd'，正在尝试使用 apt 安装..."
            if command -v apt-get &> /dev/null; then
                apt-get update && apt-get install -y $cmd
            else
                log "❌ 无法自动安装 '$cmd'。请手动安装后重试。"
                exit 1
            fi
        fi
    done

    # 2. 校验用户是否已安装 Bambu Studio 插件
    if [ ! -f "$BAMBU_SOURCE_BIN" ]; then
        log "❌ 错误：核心组件 '$BAMBU_SOURCE_BIN' 未找到。"
        log "   请打开 Bambu Studio，进入打印机设置页面，点击 'Go Live' (直播推流)，"
        log "   并根据提示下载安装 '虚拟摄像头工具' (Virtual Camera Tools) 插件。"
        exit 1
    else
        log "✅ bambu_source 已由用户安装。"
    fi

    # 3. 下载并安装 go2rtc
    if [ ! -f "$GO2RTC_BIN" ]; then
        log "📦 正在下载最新版 go2rtc..."
        CPU_ARCH=$(uname -m)
        case $CPU_ARCH in
            "x86_64") GO2RTC_ARCH="linux_amd64";;
            "aarch64") GO2RTC_ARCH="linux_arm64";;
            "armv7l") GO2RTC_ARCH="linux_armv7";;
            *) log "❌ 不支持的 CPU 架构: $CPU_ARCH"; exit 1;;
        esac
        API_URL="https://api.github.com/repos/$GO2RTC_REPO/releases/latest"
        DOWNLOAD_URL=$(curl -s $API_URL | jq -r ".assets[] | select(.name | endswith(\"$GO2RTC_ARCH\")) | .browser_download_url")
        if [ -z "$DOWNLOAD_URL" ]; then log "❌ 无法找到 go2rtc 下载链接。" && exit 1; fi
        curl -sL "$DOWNLOAD_URL" -o "$GO2RTC_BIN"
        chmod +x "$GO2RTC_BIN"
        log "✅ go2rtc 下载完成。"
    else
        log "✅ go2rtc 已存在。"
    fi

    # 4. 克隆 bambusourcestreamer 仓库以获取脚本和配置
    if [ ! -d "$BAMBU_STREAMER_SRC_DIR" ]; then
        log "📦 克隆 bambusourcestreamer (depth=1)..."
        git clone --depth=1 "$BAMBU_STREAMER_REPO" "$BAMBU_STREAMER_SRC_DIR"
    else
        log "✅ bambusourcestreamer 仓库已存在。"
    fi
    log "正在从源码同步脚本和配置..."
    cp "$BAMBU_STREAMER_SRC_DIR/bambu_fifo_feeder.sh" "$FEEDER_SCRIPT"
    cp "$BAMBU_STREAMER_SRC_DIR/bambu_url_generator.py" "$URL_GENERATOR_SCRIPT"
    cp "$BAMBU_STREAMER_SRC_DIR/go2rtc_fifo.yaml" "$CONFIG_FILE"
    chmod +x "$FEEDER_SCRIPT"

    # 5. 克隆并安装 Bambu-Lab-Cloud-API 库
    if [ ! -d "$BAMBU_CLOUD_API_DIR" ]; then
        log "📦 克隆 Bambu-Lab-Cloud-API (depth=1)..."
        git clone --depth=1 "$BAMBU_CLOUD_API_REPO" "$BAMBU_CLOUD_API_DIR"
    else
        log "✅ Bambu-Lab-Cloud-API 仓库已存在。"
    fi
    log "🐍 正在将 Bambu-Lab-Cloud-API 安装为 Python 包..."
    pip install "$BAMBU_CLOUD_API_DIR"

    log "✅ 所有依赖项均已满足。"
}

login_to_bambu_cloud() {
    install_and_verify_dependencies
    log "🔑 请根据提示进行交互式登录..."
    python3 "$URL_GENERATOR_SCRIPT" --login
    exit 0
}

start_service() {
    cd "$INSTALL_DIR" || (log "❌ 无法进入安装目录: $INSTALL_DIR" && exit 1)
    log "🚀 Bambu FIFO + go2rtc 服务启动..."
    
    cleanup() {
        log "🛑 正在停止所有服务..."
        if [ -f "$FEEDER_PID_FILE" ]; then
            FEEDER_PID=$(cat "$FEEDER_PID_FILE")
            if kill -0 "$FEEDER_PID" 2>/dev/null; then
                log "停止 FIFO feeder (PID: $FEEDER_PID)..."
                kill -TERM "$FEEDER_PID"
                for i in {1..5}; do
                    if ! kill -0 "$FEEDER_PID" 2>/dev/null; then break; fi
                    sleep 1
                done
                if kill -0 "$FEEDER_PID" 2>/dev/null; then kill -KILL "$FEEDER_PID"; fi
            fi
            rm -f "$FEEDER_PID_FILE"
        fi
        rm -f /tmp/bambu_video.fifo
        log "✅ 所有服务已停止。"
        exit 0
    }

    trap cleanup SIGINT SIGTERM

    if [ -f "$FEEDER_PID_FILE" ]; then
        OLD_PID=$(cat "$FEEDER_PID_FILE")
        if kill -0 "$OLD_PID" 2>/dev/null; then
            log "⚠️ FIFO feeder 已在运行 (PID: $OLD_PID)。"
            SKIP_FEEDER=true
        else
            rm -f "$FEEDER_PID_FILE"
        fi
    fi

    if [ "$SKIP_FEEDER" != "true" ]; then
        log "🎥 启动 FIFO feeder..."
        "$FEEDER_SCRIPT" &
        FEEDER_PID=$!
        echo $FEEDER_PID > "$FEEDER_PID_FILE"
        log "✅ FIFO feeder 已启动 (PID: $FEEDER_PID)"
        sleep 2
    fi

    log "🌐 启动 go2rtc 服务器..."
    log "访问方式:"
    log "  Web UI:  http://localhost:1984/"
    log "  RTSP:    rtsp://localhost:8554/bambulabx1c"
    log "按 Ctrl+C 停止所有服务"

    "$GO2RTC_BIN" -config "$CONFIG_FILE"
    cleanup
}

# --- 主逻辑：参数解析 ---
# 将此脚本自身复制到服务目录，以便 docker-mods 调用
if [[ -d "/custom-services.d" && ! -f "/custom-services.d/bambu-streamer" ]]; then
    log "正在安装服务以便容器启动时自动运行..."
    cp "${BASH_SOURCE[0]}" /custom-services.d/bambu-streamer
    chmod +x /custom-services.d/bambu-streamer
fi

if [ "$1" == "--login" ]; then
    login_to_bambu_cloud
elif [ "$1" == "--install" ]; then
    install_and_verify_dependencies
    log "✅ 安装/校验完成。"
    exit 0
else
    install_and_verify_dependencies
    start_service
fi
