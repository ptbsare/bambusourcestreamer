# Bambu Source Streamer (Automated Service)

[中文](#中文) | [English](#english)

---

## 中文

### 简介

Bambu Source Streamer 是一个为 Bambu Lab 打印机设计的、高度自动化的视频流服务。它专为在 Docker 环境（特别是 `linuxserver/bambustudio` 容器）中稳定运行而设计，解决了官方 Go Live 功能在某些情况下不稳定的问题。

### 特点

- ✅ **一键启动**：单个脚本自动处理所有依赖安装和配置。
- ✅ **URL 自动刷新**：内置凭证刷新机制，实现长期稳定串流。
- ✅ **智能打印机发现**：自动检测账户下的打印机，单打印机用户无需配置序列号。
- ✅ **多协议支持**：通过 go2rtc 支持 RTSP、WebRTC、HLS 等多种流媒体协议。
- ✅ **容器化设计**：为 Docker 和 LinuxServer.io 的开机自启服务 (`/custom-services.d`) 优化。
- ✅ **生命周期管理**：支持 `--update` 和 `--cleanup` 参数，方便更新和清理。

### 快速开始

**第 1 步：运行增强版的 Bambu Studio 容器**

此服务需要一个正确配置的 `linuxserver/bambustudio` 容器。以下命令整合了所有必需的依赖安装、端口映射和目录持久化。

**请选择一种方式运行：**

**选项 A: Docker Run (推荐用于新用户)**

复制并修改以下命令。请务必将 `/path/to/your/config` 替换为您宿主机上的真实路径。

```bash
docker run -d \
  --name=bambustudio \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=Asia/Shanghai \
  -e DOCKER_MODS=linuxserver/mods:universal-package-install \
  -e INSTALL_PACKAGES="git curl unzip jq gosu python3 python3-pip ffmpeg" \
  `# -e PRINTER_SERIAL="YOUR_PRINTER_SERIAL"` \
  -p 3000:3000 \
  -p 3001:3001 \
  -p 1984:1984 \
  -p 8554:8554 \
  -p 8555:8555/udp \
  -v /path/to/your/config:/config \
  -v /path/to/your/config/custom-services.d:/custom-services.d \
  --shm-size="1gb" \
  --restart unless-stopped \
  lscr.io/linuxserver/bambustudio:latest
```

**选项 B: Docker Compose**

```yaml
version: "3.8"
services:
  bambustudio:
    image: lscr.io/linuxserver/bambustudio:latest
    container_name: bambustudio
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Shanghai
      - DOCKER_MODS=linuxserver/mods:universal-package-install
      - INSTALL_PACKAGES=git curl unzip jq gosu python3 python3-pip ffmpeg
      # - PRINTER_SERIAL=YOUR_PRINTER_SERIAL # 如果您有多台打印机，请取消此行注释并填入序列号
    ports:
      - "3000:3000" # Bambu Studio desktop gui HTTP, must be proxied.
      - "3001:3001" # Bambu Studio desktop gui HTTPS.
      - "1984:1984" # go2rtc Web UI
      - "8554:8554" # RTSP
      - "8555:8555/udp" # WebRTC
    volumes:
      - /path/to/your/config:/config
      - /path/to/your/config/custom-services.d:/custom-services.d
    shm_size: "1gb"
    restart: unless-stopped
```

> **配置说明**:
> - `INSTALL_PACKAGES`: 自动安装服务脚本运行所需的核心工具。**如果要使用外部RTSP推流功能，请确保在此处加入 `ffmpeg`**。
> - `/custom-services.d`: 这是 `linuxserver.io` 容器的**开机自启**目录。将其持久化可以确保我们的服务脚本在容器更新后依然存在。
> - **端口**: 额外映射了 `1984`, `8554`, `8555` 用于访问视频流。

**第 2 步：安装 Bambu Studio 插件 (必需)**

容器运行后，访问其 Web UI (`https://<您的IP>:3001`)：
1.  进入打印机设置页面。
2.  点击 **"Go Live"** (直播推流) 选项。
3.  按照提示，下载并安装 **"虚拟摄像头工具" (Virtual Camera Tools)** 插件。这将安装核心的 `bambu_source` 组件。

**第 3 步：安装服务并登录 (一行命令)**

在**宿主机**上执行以下命令。它会自动下载服务脚本到正确的位置、设置权限，然后启动一次交互式登录。

在登录过程中，脚本会提示您选择 **Global** 或 **China** 区域。

```bash
docker exec -it bambustudio bash -c "curl -sL -o /custom-services.d/bambu-streamer https://raw.githubusercontent.com/ptbsare/bambusourcestreamer/main/bambu-streamer && chmod +x /custom-services.d/bambu-streamer && /custom-services.d/bambu-streamer --login"
```

**第 4 步：重启容器**

登录成功后，只需重启您的容器，服务便会自动启动。

```bash
docker restart bambustudio
```

### 配置外部 RTSP 服务器（可选）

如果您希望将视频流推送到一个已有的外部 RTSP 服务器 (例如 Frigate, Shinobi, 或另一个 go2rtc 实例)，而不是使用容器内建的 go2rtc，请按以下步骤操作：

1.  **确保 `ffmpeg` 已安装**: 在您的 Docker `INSTALL_PACKAGES` 环境变量中添加 `ffmpeg`。
2.  **创建配置文件**: 在容器内的以下路径创建一个文件：
    `/config/.config/BambuStudio/cameratools/RTSP_URL.txt`
3.  **填入推流地址**: 在该文件中填入您完整的 RTSP 推流地址，例如：
    `rtsp://192.168.1.100:8554/bambu_stream`

服务启动时，脚本会自动检测该文件。如果文件存在且内容为有效的 RTSP URL，脚本将使用 `ffmpeg` 直接推流，而不会启动内置的 go2rtc 服务。如果文件不存在或内容无效，脚本将自动回退到使用内置 go2rtc 的默认模式。

### 环境变量

-   `PRINTER_SERIAL`: **仅在您有多台打印机时需要**。用于指定要串流的打印机序列号。

### 脚本管理

-   **更新**: `docker exec -it bambustudio /custom-services.d/bambu-streamer --update`
-   **清理**: `docker exec -it bambustudio /custom-services.d/bambu-streamer --cleanup`

### 访问视频流

-   **Web UI**: `http://<您的容器IP>:1984/`
-   **RTSP 流**: `rtsp://<您的容器IP>:8554/bambu`

---

## English

### Introduction

Bambu Source Streamer is a highly automated video streaming service for Bambu Lab printers, designed for stable operation within Docker environments (especially `linuxserver/bambustudio`).

### Features

- ✅ **One-Command Start**: A single script handles all dependency installation.
- ✅ **Auto URL Refresh**: Ensures long-term, stable streaming.
- ✅ **Smart Printer Discovery**: Auto-detects your printer if you only have one.
- ✅ **Multi-Protocol Support**: RTSP, WebRTC, HLS via go2rtc.
- ✅ **Container-First Design**: Optimized for `linuxserver.io`'s auto-start service (`/custom-services.d`).
- ✅ **Lifecycle Management**: Supports `--update` and `--cleanup`.

### Quick Start

**Step 1: Run the Enhanced Bambu Studio Container**

This service requires a properly configured `linuxserver/bambustudio` container. The commands below include all necessary dependencies, port mappings, and volume persistence.

**Choose one method:**

**Option A: Docker Run (Recommended for new users)**

Copy and modify the following command. **Remember to replace `/path/to/your/config` with a real path on your host machine.**

```bash
docker run -d \
  --name=bambustudio \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=Asia/Shanghai \
  -e DOCKER_MODS=linuxserver/mods:universal-package-install \
  -e INSTALL_PACKAGES="git curl unzip jq gosu python3 python3-pip ffmpeg" \
  `# -e PRINTER_SERIAL="YOUR_PRINTER_SERIAL"` \
  -p 3000:3000 \
  -p 3001:3001 \
  -p 1984:1984 \
  -p 8554:8554 \
  -p 8555:8555/udp \
  -v /path/to/your/config:/config \
  -v /path/to/your/config/custom-services.d:/custom-services.d \
  --shm-size="1gb" \
  --restart unless-stopped \
  lscr.io/linuxserver/bambustudio:latest
```

**Option B: Docker Compose**

```yaml
version: "3.8"
services:
  bambustudio:
    image: lscr.io/linuxserver/bambustudio:latest
    container_name: bambustudio
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Shanghai
      - DOCKER_MODS=linuxserver/mods:universal-package-install
      - INSTALL_PACKAGES=git curl unzip jq gosu python3 python3-pip ffmpeg
      # - PRINTER_SERIAL=YOUR_PRINTER_SERIAL # Uncomment and fill if you have multiple printers
    ports:
      - "3000:3000" # Bambu Studio desktop gui HTTP, must be proxied.
      - "3001:3001" # Bambu Studio desktop gui HTTPS.
      - "1984:1984" # go2rtc Web UI
      - "8554:8554" # RTSP
      - "8555:8555/udp" # WebRTC
    volumes:
      - /path/to/your/config:/config
      - /path/to/your/config/custom-services.d:/custom-services.d
    shm_size: "1gb"
    restart: unless-stopped
```

> **Configuration Notes**:
> - `INSTALL_PACKAGES`: Installs essential tools. **If using the external RTSP push feature, ensure `ffmpeg` is included here.**
> - `/custom-services.d`: This is the **auto-start** directory for `linuxserver.io` containers. Persisting it ensures our service script survives container updates.
> - **Ports**: Maps extra ports (`1984`, `8554`, `8555`) for accessing the video stream.

**Step 2: Install Bambu Studio Plugin (Mandatory)**

Once the container is running, access its Web UI (`https://<your_ip>:3001`):
1.  Go to the printer settings page.
2.  Click the **"Go Live"** option.
3.  Follow the prompts to download and install the **"Virtual Camera Tools"** plugin. This provides the core `bambu_source` component.

**Step 3: Install Service and Login (One Command)**

Run the following command on your **host machine**. It will download the script, set permissions, and start an interactive login.

During the login process, you will be prompted to select your region (**Global** or **China**).

```bash
docker exec -it bambustudio bash -c "curl -sL -o /custom-services.d/bambu-streamer https://raw.githubusercontent.com/ptbsare/bambusourcestreamer/main/bambu-streamer && chmod +x /custom-services.d/bambu-streamer && /custom-services.d/bambu-streamer --login"
```

**Step 4: Restart Container**

After a successful login, restart your container, and the service will start automatically.

```bash
docker restart bambustudio
```

### Configure External RTSP Server (Optional)

If you want to push the video stream to an existing external RTSP server (e.g., Frigate, Shinobi, or another go2rtc instance) instead of using the built-in one, follow these steps:

1.  **Ensure `ffmpeg` is installed**: Add `ffmpeg` to your Docker `INSTALL_PACKAGES` environment variable.
2.  **Create Config File**: Create a file inside the container at the following path:
    `/config/.config/BambuStudio/cameratools/RTSP_URL.txt`
3.  **Enter Push URL**: In that file, add your full RTSP push URL, for example:
    `rtsp://192.168.1.100:8554/bambu_stream`

The service will automatically detect this file on startup. If it exists and contains a valid RTSP URL, the script will use `ffmpeg` to push the stream directly and will not start the internal go2rtc service. If the file doesn't exist or its content is invalid, it will fall back to the default mode using the internal go2rtc.

### Environment Variables

-   `PRINTER_SERIAL`: **Only required if you have multiple printers**. Use it to specify which printer to stream.

### Script Management

-   **Update**: `docker exec -it bambustudio /custom-services.d/bambu-streamer --update`
-   **Cleanup**: `docker exec -it bambustudio /custom-services.d/bambu-streamer --cleanup`

### Accessing the Stream

-   **Web UI**: `http://<your_container_ip>:1984/`
-   **RTSP Stream**: `rtsp://<your_container_ip>:8554/bambu`