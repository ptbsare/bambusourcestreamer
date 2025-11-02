# Bambu Source Streamer

[中文](#中文) | [English](#english)

---

## 中文

### 简介

Bambu Source Streamer 是一个用于 Bambu Lab 3D 打印机视频流的解决方案，专为 LinuxServer.io 的 Bambu Studio Docker 容器设计。它通过 FIFO（命名管道）和 go2rtc 实现单连接多客户端的高效视频流传输。

**⚠️ 重要提示**：此项目是为了**解决 Bambu Studio 在 Linux Docker 环境中 Go Live 功能失败的 Bug**（ffmpeg 和 bambu_source 变成僵尸进程）。如果您的 Bambu Studio 推流功能正常工作，则不需要使用此脚本。

### 前置条件

在使用此脚本之前，您需要：

1. **在 Bambu Studio 客户端中启用 Go Live**：
   - 打开 Bambu Studio
   - 进入打印机设置页面
   - 找到并点击 "Go Live" 或 "直播推流" 选项
   - 按照提示下载并安装"虚拟摄像头工具插件"（Virtual Camera Tools）
   - 这一步会下载 `bambu_source` 和 `ffmpeg` 等必要工具到 `/config/.config/BambuStudio/cameratools/` 目录

2. **配置 LinuxServer.io 容器依赖**：
   
   添加以下环境变量到您的 Docker 配置中以安装必要的依赖包：
   
   ```yaml
   environment:
     - DOCKER_MODS=linuxserver/mods:universal-package-install
     - INSTALL_PACKAGES=gosu ffmpeg
   ```
   
   这些包的作用：
   - `gosu`: 用于在容器中切换用户（类似 sudo，但更适合容器环境）
   - `ffmpeg`: 用于视频流处理

### 特点

- ✅ **单连接模式**：无论多少客户端连接，只保持一个到打印机的连接
- ✅ **自动重连**：bambu_source 进程崩溃时自动重启
- ✅ **多协议支持**：通过 go2rtc 支持 RTSP、WebRTC、HLS 等多种协议
- ✅ **容器友好**：专为 Docker 环境优化
- ✅ **开机自启**：支持容器启动时自动运行

### 工作原理

```
打印机 ← (单连接) ← bambu_source → FIFO → go2rtc (ffmpeg) → 多个客户端
                                              ↓
                                    RTSP/WebRTC/HLS/...
```

### 安装步骤

#### 1. 下载 go2rtc

从 [go2rtc releases](https://github.com/AlexxIT/go2rtc/releases) 下载适合您系统的二进制文件。

#### 2. 部署到容器

将文件复制到 Bambu Studio Docker 容器的配置目录：

```bash
# 假设您的容器挂载 /config 到宿主机的某个目录
# 目标目录：/config/.config/BambuStudio/cameratools/

# 复制文件
cp go2rtc /path/to/config/.config/BambuStudio/cameratools/
cp go2rtc_fifo.yaml /path/to/config/.config/BambuStudio/cameratools/
cp bambu_fifo_feeder.sh /path/to/config/.config/BambuStudio/cameratools/
cp start_bambu_fifo.sh /path/to/config/.config/BambuStudio/cameratools/

# 添加执行权限
chmod +x /path/to/config/.config/BambuStudio/cameratools/go2rtc
chmod +x /path/to/config/.config/BambuStudio/cameratools/bambu_fifo_feeder.sh
chmod +x /path/to/config/.config/BambuStudio/cameratools/start_bambu_fifo.sh
```

#### 3. 配置开机自启（可选）

将启动脚本复制到 LinuxServer.io 容器的自定义启动目录：

```bash
# 创建自定义服务目录（如果不存在）
mkdir -p /custom-cont-init.d/

# 复制启动脚本
cp start_bambu_fifo.sh /custom-cont-init.d/99-bambu-streamer.sh

# 添加执行权限
chmod +x /path/to/config/custom-cont-init.d/99-bambu-streamer.sh
```

LinuxServer.io 容器会在启动时自动执行 `/custom-cont-init.d/` 目录中的脚本。

### 使用方法

#### 方式 1：手动启动

进入容器后执行：

```bash
cd /config/.config/BambuStudio/cameratools
./start_bambu_fifo.sh
```

#### 方式 2：使用环境变量

在 Docker Compose 或 Docker 命令中设置 `BAMBU_URL` 环境变量：

**Docker Compose 示例**：

```yaml
services:
  bambustudio:
    image: lscr.io/linuxserver/bambustudio:latest
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Shanghai
      # 安装必要的依赖包
      - DOCKER_MODS=linuxserver/mods:universal-package-install
      - INSTALL_PACKAGES=gosu|ffmpeg
      # Bambu 打印机连接 URL（可选）
      - BAMBU_URL=bambu:///tutk?uid=YOUR_PRINTER_UID&authkey=YOUR_AUTH_KEY
    volumes:
      - /path/to/config:/config
    ports:
      - 3000:3000      # Bambu Studio Web UI
      - 1984:1984      # go2rtc Web UI
      - 8554:8554      # RTSP 端口
```

**Docker CLI 示例**：

```bash
docker run -d \
  --name=bambustudio \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=Asia/Shanghai \
  -e DOCKER_MODS=linuxserver/mods:universal-package-install \
  -e INSTALL_PACKAGES=gosu|ffmpeg \
  -e BAMBU_URL="bambu:///tutk?uid=YOUR_PRINTER_UID&authkey=YOUR_AUTH_KEY" \
  -p 3000:3000 \
  -p 1984:1984 \
  -p 8554:8554 \
  -v /path/to/config:/config \
  lscr.io/linuxserver/bambustudio:latest
```

### BAMBU_URL 环境变量

`BAMBU_URL` 环境变量用于指定 Bambu Lab 打印机的连接 URL。

**格式**：

```
bambu:///tutk?uid=PRINTER_UID&authkey=AUTH_KEY&passwd=ACCESS_CODE&region=REGION
```

**参数说明**：

- `uid`: 打印机的唯一标识符（在打印机设置中查看）
- `authkey`: 认证密钥
- `passwd`: 访问码（LAN 模式下的访问码）
- `region`: 区域（如 `us`, `cn`, `eu`）

**优先级**：

1. 环境变量 `BAMBU_URL`（最高优先级）
2. `/config/.config/BambuStudio/cameratools/url.txt` 文件内容
3. 脚本中的默认值（需要手动修改）

### 访问视频流

服务启动后，可以通过以下方式访问：

- **Web UI**: http://localhost:1984/
- **RTSP 流**: `rtsp://localhost:8554/bambulabx1c`
- **WebRTC**: 在 Web UI 中选择 `bambulabx1c` 流

### 故障排除

**问题：bambu_source 不断重启**

检查 `BAMBU_URL` 是否正确，确保：
- UID 正确
- 认证密钥有效
- 网络连接正常

**问题：go2rtc 无法读取 FIFO**

确保：
- FIFO feeder 正在运行
- FIFO 文件已创建：`ls -l /tmp/bambu_video.fifo`

**问题：无法访问 Web UI**

检查端口映射是否正确，确保 Docker 容器的 1984 端口已映射到宿主机。

---

## English

### Introduction

Bambu Source Streamer is a video streaming solution for Bambu Lab 3D printers, specifically designed for LinuxServer.io's Bambu Studio Docker container. It uses FIFO (named pipe) and go2rtc to achieve efficient single-connection multi-client video streaming.

**⚠️ Important Note**: This project is designed to **fix the Bambu Studio Go Live bug in Linux Docker environments** (where ffmpeg and bambu_source become zombie processes). If your Bambu Studio streaming works properly, you don't need this script.

### Prerequisites

Before using this script, you need to:

1. **Enable Go Live in Bambu Studio Client**:
   - Open Bambu Studio
   - Go to printer settings page
   - Find and click "Go Live" or streaming option
   - Follow the prompts to download and install the "Virtual Camera Tools" plugin
   - This step downloads necessary tools like `bambu_source` and `ffmpeg` to `/config/.config/BambuStudio/cameratools/`

2. **Configure LinuxServer.io Container Dependencies**:
   
   Add the following environment variables to your Docker configuration to install required packages:
   
   ```yaml
   environment:
     - DOCKER_MODS=linuxserver/mods:universal-package-install
     - INSTALL_PACKAGES=gosu|ffmpeg
   ```
   
   Package purposes:
   - `gosu`: For switching users in containers (like sudo, but container-friendly)
   - `ffmpeg`: For video stream processing

### Features

- ✅ **Single Connection Mode**: Only one connection to the printer regardless of client count
- ✅ **Auto Reconnect**: Automatically restarts bambu_source on crashes
- ✅ **Multi-Protocol Support**: RTSP, WebRTC, HLS, etc. via go2rtc
- ✅ **Container Friendly**: Optimized for Docker environments
- ✅ **Auto-Start**: Supports automatic startup with container

### How It Works

```
Printer ← (single connection) ← bambu_source → FIFO → go2rtc (ffmpeg) → Multiple Clients
                                                        ↓
                                              RTSP/WebRTC/HLS/...
```

### Installation

#### 1. Download go2rtc

Download the appropriate binary from [go2rtc releases](https://github.com/AlexxIT/go2rtc/releases).

#### 2. Deploy to Container

Copy files to Bambu Studio Docker container's configuration directory:

```bash
# Assuming your container mounts /config to a host directory
# Target directory: /config/.config/BambuStudio/cameratools/

# Copy files
cp go2rtc /path/to/config/.config/BambuStudio/cameratools/
cp go2rtc_fifo.yaml /path/to/config/.config/BambuStudio/cameratools/
cp bambu_fifo_feeder.sh /path/to/config/.config/BambuStudio/cameratools/
cp start_bambu_fifo.sh /path/to/config/.config/BambuStudio/cameratools/

# Set permissions
chmod +x /path/to/config/.config/BambuStudio/cameratools/go2rtc
chmod +x /path/to/config/.config/BambuStudio/cameratools/bambu_fifo_feeder.sh
chmod +x /path/to/config/.config/BambuStudio/cameratools/start_bambu_fifo.sh
```

#### 3. Configure Auto-Start (Optional)

Copy the startup script to LinuxServer.io container's custom init directory:

```bash
# Create custom service directory if it doesn't exist
mkdir -p /path/to/config/custom-cont-init.d/

# Copy startup script
cp start_bambu_fifo.sh /path/to/config/custom-cont-init.d/99-bambu-streamer.sh

# Set permissions
chmod +x /path/to/config/custom-cont-init.d/99-bambu-streamer.sh
```

LinuxServer.io containers automatically execute scripts in `/config/custom-cont-init.d/` on startup.

### Usage

#### Method 1: Manual Start

Execute inside the container:

```bash
cd /config/.config/BambuStudio/cameratools
./start_bambu_fifo.sh
```

#### Method 2: Using Environment Variables

Set the `BAMBU_URL` environment variable in Docker Compose or Docker command:

**Docker Compose Example**:

```yaml
services:
  bambustudio:
    image: lscr.io/linuxserver/bambustudio:latest
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Shanghai
      # Install required dependencies
      - DOCKER_MODS=linuxserver/mods:universal-package-install
      - INSTALL_PACKAGES=gosu|ffmpeg
      # Bambu printer connection URL (optional)
      - BAMBU_URL=bambu:///tutk?uid=YOUR_PRINTER_UID&authkey=YOUR_AUTH_KEY
    volumes:
      - /path/to/config:/config
    ports:
      - 3000:3000      # Bambu Studio Web UI
      - 1984:1984      # go2rtc Web UI
      - 8554:8554      # RTSP Port
```

**Docker CLI Example**:

```bash
docker run -d \
  --name=bambustudio \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=Asia/Shanghai \
  -e DOCKER_MODS=linuxserver/mods:universal-package-install \
  -e INSTALL_PACKAGES=gosu|ffmpeg \
  -e BAMBU_URL="bambu:///tutk?uid=YOUR_PRINTER_UID&authkey=YOUR_AUTH_KEY" \
  -p 3000:3000 \
  -p 1984:1984 \
  -p 8554:8554 \
  -v /path/to/config:/config \
  lscr.io/linuxserver/bambustudio:latest
```

### BAMBU_URL Environment Variable

The `BAMBU_URL` environment variable specifies the connection URL for Bambu Lab printers.

**Format**:

```
bambu:///tutk?uid=PRINTER_UID&authkey=AUTH_KEY&passwd=ACCESS_CODE&region=REGION
```

**Parameters**:

- `uid`: Printer's unique identifier (check printer settings)
- `authkey`: Authentication key
- `passwd`: Access code (for LAN mode)
- `region`: Region (e.g., `us`, `cn`, `eu`)

**Priority**:

1. `BAMBU_URL` environment variable (highest priority)
2. Contents of `/config/.config/BambuStudio/cameratools/url.txt`
3. Default value in script (requires manual modification)

### Accessing Video Stream

Once started, access via:

- **Web UI**: http://localhost:1984/
- **RTSP Stream**: `rtsp://localhost:8554/bambulabx1c`
- **WebRTC**: Select `bambulabx1c` stream in Web UI

### Troubleshooting

**Issue: bambu_source keeps restarting**

Check if `BAMBU_URL` is correct:
- UID is correct
- Auth key is valid
- Network connection is stable

**Issue: go2rtc cannot read FIFO**

Ensure:
- FIFO feeder is running
- FIFO file exists: `ls -l /tmp/bambu_video.fifo`

**Issue: Cannot access Web UI**

Check port mapping, ensure Docker container's port 1984 is mapped to host.

---

## License

MIT License

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.