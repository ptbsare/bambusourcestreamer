#!/bin/bash
set -e

# == Bambu Streamer Service Script ==
#
# v2.2 - 增强了 cleanup 功能
#
# 功能:
# 1. 自动安装/校验依赖 (go2rtc, git repos, user plugins)
# 2. --login: 交互式登录 Bambu Cloud
# 3. --update: 从 Git 更新脚本
# 4. --cleanup: 清理所有由本脚本生成的文件
# 5. (默认) 启动和管理 bambu_source 和 go2rtc 服务, 实现 URL 自动刷新

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

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"; }

install_and_verify_dependencies() {
    log "🔎 正在检查和安装依赖项..."
    mkdir -p "$INSTALL_DIR"

    for cmd in git curl unzip jq gosu; do
        if ! command -v $cmd &> /dev/null; then
            log "📦 未找到 '$cmd'，正在尝试使用 apt 安装..."
            if command -v apt-get &> /dev/null; then apt-get update && apt-get install -y $cmd; else
                log "❌ 无法自动安装 '$cmd'。请手动安装后重试。"; exit 1; fi
        fi
    done

    if [ ! -f "$BAMBU_SOURCE_BIN" ]; then
        log "❌ 错误：核心组件 '$BAMBU_SOURCE_BIN' 未找到。";
        log "   请打开 Bambu Studio -> Go Live -> 安装 '虚拟摄像头工具' 插件。"; exit 1;
    else log "✅ bambu_source 已由用户安装。"; fi

    if [ ! -f "$GO2RTC_BIN" ]; then
        log "📦 正在下载最新版 go2rtc..."; CPU_ARCH=$(uname -m);
        case $CPU_ARCH in "x86_64") GO2RTC_ARCH="linux_amd64";; "aarch64") GO2RTC_ARCH="linux_arm64";;
            "armv7l") GO2RTC_ARCH="linux_armv7";; *) log "❌ 不支持的 CPU 架构: $CPU_ARCH"; exit 1;; esac
        API_URL="https://api.github.com/repos/$GO2RTC_REPO/releases/latest"
        DOWNLOAD_URL=$(curl -s $API_URL | jq -r ".assets[] | select(.name | endswith(\"$GO2RTC_ARCH\")) | .browser_download_url")
        if [ -z "$DOWNLOAD_URL" ]; then log "❌ 无法找到 go2rtc 下载链接。" && exit 1; fi
        curl -sL "$DOWNLOAD_URL" -o "$GO2RTC_BIN"; chmod +x "$GO2RTC_BIN"; log "✅ go2rtc 下载完成。";
    else log "✅ go2rtc 已存在。"; fi

    if [ ! -d "$BAMBU_STREAMER_SRC_DIR" ]; then
        log "📦 克隆 bambusourcestreamer (depth=1)..."
        git clone --depth=1 "$BAMBU_STREAMER_REPO" "$BAMBU_STREAMER_SRC_DIR"
    else log "✅ bambusourcestreamer 仓库已存在。"; fi
    log "正在从源码同步脚本和配置...";
    cp "$BAMBU_STREAMER_SRC_DIR/bambu_fifo_feeder.sh" "$FEEDER_SCRIPT"
    cp "$BAMBU_STREAMER_SRC_DIR/bambu_url_generator.py" "$URL_GENERATOR_SCRIPT"
    cp "$BAMBU_STREAMER_SRC_DIR/go2rtc_fifo.yaml" "$CONFIG_FILE"
    chmod +x "$FEEDER_SCRIPT"

    if [ ! -d "$BAMBU_CLOUD_API_DIR" ]; then
        log "📦 克隆 Bambu-Lab-Cloud-API (depth=1)..."
        git clone --depth=1 "$BAMBU_CLOUD_API_REPO" "$BAMBU_CLOUD_API_DIR"
    else log "✅ Bambu-Lab-Cloud-API 仓库已存在。"; fi
    log "🐍 正在将 Bambu-Lab-Cloud-API 安装为 Python 包..."; pip install "$BAMBU_CLOUD_API_DIR"
    log "✅ 所有依赖项均已满足。"
}

login_to_bambu_cloud() {
    install_and_verify_dependencies
    log "🔑 切换到 'abc' 用户进行交互式登录..."; log "   请根据接下来的提示操作。"
    gosu abc python3 "$URL_GENERATOR_SCRIPT" --login
    log "✅ 登录流程完成。"; exit 0
}

update_scripts() {
    log "🔄 正在从 Git 更新脚本..."
    if [ -d "$BAMBU_STREAMER_SRC_DIR" ]; then
        cd "$BAMBU_STREAMER_SRC_DIR"; git pull; cd - > /dev/null;
        log "正在从源码同步脚本和配置...";
        cp "$BAMBU_STREAMER_SRC_DIR/bambu_fifo_feeder.sh" "$FEEDER_SCRIPT"
        cp "$BAMBU_STREAMER_SRC_DIR/bambu_url_generator.py" "$URL_GENERATOR_SCRIPT"
        cp "$BAMBU_STREAMER_SRC_DIR/go2rtc_fifo.yaml" "$CONFIG_FILE"
        chmod +x "$FEEDER_SCRIPT"
        log "✅ 脚本更新完成。"
    else
        log "⚠️  未找到源码目录，请先运行一次安装。"; exit 1;
    fi
    if [ -d "$BAMBU_CLOUD_API_DIR" ]; then
        cd "$BAMBU_CLOUD_API_DIR"; git pull; cd - > /dev/null;
        log "🐍 正在更新 Python 包..."; pip install --upgrade "$BAMBU_CLOUD_API_DIR"
        log "✅ Python 包更新完成。"
    else
        log "⚠️  未找到 API 库目录，请先运行一次安装。"; exit 1;
    fi
    exit 0
}

cleanup_files() {
    log "🧹 正在进行彻底清理..."
    rm -f "$FEEDER_SCRIPT" "$URL_GENERATOR_SCRIPT" "$CONFIG_FILE" "$GO2RTC_BIN"
    rm -rf "$BAMBU_STREAMER_SRC_DIR" "$BAMBU_CLOUD_API_DIR"
    log "✅ 清理完成。"
    log "   保留的内容: $BAMBU_SOURCE_BIN (由用户通过 Bambu Studio 插件安装)。"
    exit 0
}

start_service() {
    cd "$INSTALL_DIR" || (log "❌ 无法进入安装目录: $INSTALL_DIR" && exit 1)
    log "🚀 Bambu FIFO + go2rtc 服务启动..."
    
    cleanup_processes() {
        log "🛑 正在停止所有服务...";
        if [ -f "$FEEDER_PID_FILE" ]; then
            FEEDER_PID=$(cat "$FEEDER_PID_FILE" 2>/dev/null)
            if [ -n "$FEEDER_PID" ] && kill -0 "$FEEDER_PID" 2>/dev/null; then
                log "向 FIFO feeder (PID: $FEEDER_PID) 发送 SIGTERM 信号...";
                kill -TERM "$FEEDER_PID"; wait "$FEEDER_PID"; log "✅ FIFO feeder 已停止。";
            fi; rm -f "$FEEDER_PID_FILE"
        fi
        rm -f /tmp/bambu_video.fifo; log "✅ 所有服务已清理完毕。"
    }
    trap 'cleanup_processes' SIGINT SIGTERM

    if [ -f "$FEEDER_PID_FILE" ] && kill -0 "$(cat $FEEDER_PID_FILE 2>/dev/null)" 2>/dev/null; then
        log "⚠️ FIFO feeder 已在运行 (PID: $(cat $FEEDER_PID_FILE))。"; SKIP_FEEDER=true;
    else rm -f "$FEEDER_PID_FILE"; fi

    if [ "$SKIP_FEEDER" != "true" ]; then
        log "🎥 启动 FIFO feeder..."; "$FEEDER_SCRIPT" &
        FEEDER_PID=$!; echo $FEEDER_PID > "$FEEDER_PID_FILE";
        log "✅ FIFO feeder 已启动 (PID: $FEEDER_PID)"; sleep 2;
    fi

    log "🌐 启动 go2rtc 服务器...";
    log "  Web UI:  http://localhost:1984/"; log "  RTSP:    rtsp://localhost:8554/bambulabx1c"

    "$GO2RTC_BIN" -config "$CONFIG_FILE" &
    GO2RTC_PID=$!; wait "$GO2RTC_PID";
    cleanup_processes
}

# --- 主逻辑 ---
if [[ -d "/custom-services.d" && ! -f "/custom-services.d/bambu-streamer" ]]; then
    log "正在安装服务以便容器启动时自动运行..."
    cp "${BASH_SOURCE[0]}" /custom-services.d/bambu-streamer
    chmod +x /custom-services.d/bambu-streamer
fi

case "$1" in
    --login)    login_to_bambu_cloud;;
    --install)  install_and_verify_dependencies; log "✅ 安装/校验完成。"; exit 0;;
    --update)   update_scripts;;
    --cleanup)  cleanup_files;;
    *)          install_and_verify_dependencies; start_service;;
esac
