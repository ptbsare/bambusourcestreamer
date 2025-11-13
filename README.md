# Bambu Source Streamer (Automated Service)

[中文](#中文) | [English](#english)

---

## 中文

### 简介

Bambu Source Streamer 是一个为 Bambu Lab 打印机设计的、高度自动化的视频流服务。它专为在 Docker 环境（特别是 `linuxserver/bambustudio` 容器）中稳定运行而设计，解决了官方 Go Live 功能在某些情况下不稳定的问题。

### 特点

- ✅ **一键启动**：单个脚本自动处理所有依赖安装和配置。
- ✅ **URL 自动刷新**：内置凭证刷新机制，实现长期稳定串流，无需人工干预。
- ✅ **智能打印机发现**：自动检测账户下的打印机，单打印机用户无需配置序列号。
- ✅ **多协议支持**：通过 go2rtc 支持 RTSP、WebRTC、HLS 等多种现代流媒体协议。
- ✅ **容器化设计**：为 Docker 和 LinuxServer.io 的开机自启服务 (`/custom-services.d`) 优化。
- ✅ **生命周期管理**：支持 `--update` 和 `--cleanup` 参数，方便更新和清理。

### 前置条件

1.  **安装 Bambu Studio 插件**:
    - 在您的 Bambu Studio 桌面客户端或 Docker 容器的 Web UI 中，进入打印机设置页面。
    - 点击 **"Go Live"** (直播推流) 选项。
    - 按照提示，下载并安装 **"虚拟摄像头工具" (Virtual Camera Tools)** 插件。
    - **这是必须的步骤**，因为它会安装核心的 `bambu_source` 二进制文件及其依赖库。

2.  **LinuxServer.io 容器依赖**:
    - 确保您的 Docker `environment` 中包含 `DOCKER_MODS` 和 `INSTALL_PACKAGES`，以安装脚本运行所需的核心工具。
      ```yaml
      environment:
        - DOCKER_MODS=linuxserver/mods:universal-package-install
        - INSTALL_PACKAGES=git curl unzip jq gosu python3 python3-pip
      ```

### 快速开始 (一键部署)

**第 1 步：安装服务脚本**

将 `start_bambu_fifo.sh` 下载到容器的自动启动目录中。只需在**宿主机**上运行这一行命令：

```bash
mkdir -p /path/to/your/bambu/config/custom-services.d && \
curl -sL -o /path/to/your/bambu/config/custom-services.d/bambu-streamer https://raw.githubusercontent.com/ptbsare/bambusourcestreamer/main/start_bambu_fifo.sh && \
chmod +x /path/to/your/bambu/config/custom-services.d/bambu-streamer
```
> **注意**: 请将 `/path/to/your/bambu/config` 替换为您 Bambu Studio 容器实际的配置目录挂载路径。

**第 2 步：首次登录**

在**宿主机**上执行以下命令进入容器并运行登录程序，以生成 API 令牌 (token)：

```bash
docker exec -it bambustudio /custom-services.d/bambu-streamer --login
```
根据提示输入您的 Bambu Lab 账户和密码。登录成功后，令牌会保存在 `abc` 用户的 home 目录 (`/config/.bambu_token`) 中。

**第 3 步：重启容器**

现在，只需重启您的 Bambu Studio 容器，服务便会自动安装所有依赖并启动。

```bash
docker restart bambustudio
```

### 环境变量 (可选)

您可以通过环境变量来控制脚本的行为。

-   `PRINTER_SERIAL`
    -   **功能**: 指定要串流的打印机序列号。
    -   **何时使用**: 当您的 Bambu Lab 账户下有**多台打印机**时，**必须**设置此变量来选择其中一台。
    -   **示例**:
        ```yaml
        environment:
          - PRINTER_SERIAL=01S00AXXXXXXXXXX
        ```

### 脚本管理

您可以通过 `docker exec` 和特定参数来管理服务。

-   **更新脚本**: 从 GitHub 拉取最新的脚本和 Python 依赖。
    ```bash
    docker exec -it bambustudio /custom-services.d/bambu-streamer --update
    ```
-   **清理文件**: 删除所有由脚本安装的文件（脚本、配置、git缓存），保留用户安装的二进制文件。
    ```bash
    docker exec -it bambustudio /custom-services.d/bambu-streamer --cleanup
    ```

### 访问视频流

服务启动后，可以通过以下方式访问：

-   **Web UI**: `http://<您的容器IP>:1984/`
-   **RTSP 流**: `rtsp://<您的容器IP>:8554/bambulabx1c`

---

## English

### Introduction

Bambu Source Streamer is a highly automated video streaming service for Bambu Lab printers. It's designed for stable, long-term operation within Docker environments, especially the `linuxserver/bambustudio` container, fixing instability issues with the official "Go Live" feature.

### Features

- ✅ **One-Command Start**: A single script handles all dependency installation and configuration automatically.
- ✅ **Auto URL Refresh**: Built-in credential refresh mechanism for long-term, stable streaming without manual intervention.
- ✅ **Smart Printer Discovery**: Automatically detects printers under your account. No serial number configuration needed for single-printer users.
- ✅ **Multi-Protocol Support**: Supports modern streaming protocols like RTSP, WebRTC, and HLS via go2rtc.
- ✅ **Container-First Design**: Optimized for Docker and LinuxServer.io's auto-start service directory (`/custom-services.d`).
- ✅ **Lifecycle Management**: Supports `--update` and `--cleanup` for easy maintenance.

### Prerequisites

1.  **Install Bambu Studio Plugin**:
    - In your Bambu Studio desktop client or the web UI of your Docker container, navigate to the printer settings page.
    - Click the **"Go Live"** option.
    - Follow the prompts to download and install the **"Virtual Camera Tools"** plugin.
    - **This is a mandatory step**, as it installs the core `bambu_source` binary and its library dependencies.

2.  **LinuxServer.io Container Dependencies**:
    - Ensure your Docker `environment` includes `DOCKER_MODS` and `INSTALL_PACKAGES` to install the core tools required by the script.
      ```yaml
      environment:
        - DOCKER_MODS=linuxserver/mods:universal-package-install
        - INSTALL_PACKAGES=git curl unzip jq gosu python3 python3-pip
      ```

### Quick Start (One-Command Deployment)

**Step 1: Install the Service Script**

Download the `start_bambu_fifo.sh` script into the container's auto-start directory. Simply run this single command on your **host machine**:

```bash
mkdir -p /path/to/your/bambu/config/custom-services.d && \
curl -sL -o /path/to/your/bambu/config/custom-services.d/bambu-streamer https://raw.githubusercontent.com/ptbsare/bambusourcestreamer/main/start_bambu_fifo.sh && \
chmod +x /path/to/your/bambu/config/custom-services.d/bambu-streamer
```
> **Note**: Replace `/path/to/your/bambu/config` with the actual path to your Bambu Studio container's config volume mount.

**Step 2: First-Time Login**

Run the following command on your **host machine** to enter the container and perform an interactive login to generate your API token:

```bash
docker exec -it bambustudio /custom-services.d/bambu-streamer --login
```
Follow the prompts to enter your Bambu Lab account credentials. On success, the token will be saved in the `abc` user's home directory (`/config/.bambu_token`).

**Step 3: Restart the Container**

Now, just restart your Bambu Studio container. The service will automatically install all dependencies and start up.

```bash
docker restart bambustudio
```

### Environment Variables (Optional)

You can control the script's behavior with environment variables.

-   `PRINTER_SERIAL`
    -   **Function**: Specifies the serial number of the printer to stream.
    -   **When to use**: This is **mandatory** if you have **multiple printers** under your Bambu Lab account.
    -   **Example**:
        ```yaml
        environment:
          - PRINTER_SERIAL=01S00AXXXXXXXXXX
        ```

### Script Management

You can manage the service via `docker exec` and specific flags.

-   **Update Scripts**: Pull the latest scripts and Python dependencies from GitHub.
    ```bash
    docker exec -it bambustudio /custom-services.d/bambu-streamer --update
    ```
-   **Cleanup Files**: Remove all files installed by the script (scripts, configs, git cache), leaving user-installed binaries untouched.
    ```bash
    docker exec -it bambustudio /custom-services.d/bambu-streamer --cleanup
    ```

### Accessing the Stream

Once the service is running, you can access the video stream via:

-   **Web UI**: `http://<your_container_ip>:1984/`
-   **RTSP Stream**: `rtsp://<your_container_ip>:8554/bambulabx1c`