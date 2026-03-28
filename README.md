# Ollama + Nanbeige4.1-3B-q4_K_M 一键部署脚本

一键部署 [Ollama](https://ollama.com/) 和 [南壁鸽4.1-3B](https://ollama.com/softw8/Nanbeige4.1-3B-q4_K_M) 大语言模型，支持 Windows、Linux 和 macOS 三大平台。

## 模型简介

| 属性 | 值 |
|------|-----|
| 模型名称 | Nanbeige4.1-3B-q4_K_M |
| 参数量 | 3.9B |
| 量化方式 | Q4_K_M (4-bit) |
| 模型大小 | ~2.5 GB |
| 模型格式 | GGUF |
| 基座架构 | LLaMA |
| 支持语言 | 中文、英文 |

## 系统要求

| 平台 | 最低要求 |
|------|---------|
| **Linux** | Ubuntu 20.04+ / CentOS 8+ / Arch Linux, x86_64 或 ARM64, 4GB+ RAM |
| **macOS** | macOS 12+, Apple Silicon 或 Intel, 4GB+ RAM |
| **Windows** | Windows 10/11 x64, 4GB+ RAM |

> **注意**: CPU 推理速度约 3-15 tok/s（取决于 CPU 性能）。如有 NVIDIA GPU，Ollama 会自动启用 CUDA 加速。

## 快速开始

### Linux

```bash
# 下载并运行
curl -fsSL https://raw.githubusercontent.com/ctz168/3b/main/scripts/install_ollama_linux.sh | bash

# 或手动下载后运行
bash install_ollama_linux.sh
```

### macOS

```bash
# 下载并运行
curl -fsSL https://raw.githubusercontent.com/ctz168/3b/main/scripts/install_ollama_macos.sh | bash

# 或手动下载后运行
bash install_ollama_macos.sh
```

### Windows

```powershell
# 以管理员身份打开 PowerShell，执行：
Set-ExecutionPolicy Bypass -Scope Process -Force
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ctz168/3b/main/scripts/install_ollama_windows.ps1" -OutFile "install_ollama_windows.ps1"
.\install_ollama_windows.ps1
```

## 脚本功能

所有平台脚本均提供以下功能：

1. **自动检测系统环境** - 架构、OS 版本、依赖检查
2. **自动安装 Ollama** - 从 GitHub Releases 下载最新版
3. **自动安装依赖** - zstd 解压工具等
4. **拉取模型** - 自动下载 Nanbeige4.1-3B-q4_K_M 模型（~2.5GB）
5. **配置环境变量** - PATH、LD_LIBRARY_PATH 等
6. **注册系统服务** - systemd (Linux) / launchd (macOS) / 后台进程 (Windows)
7. **安装验证** - 自动运行推理测试确认部署成功
8. **手动下载回退** - 当 `ollama pull` 不可用时，直接从 registry 下载

## 速度测试

部署完成后，使用内置基准测试脚本测试推理速度：

```bash
# 基本测试 (5 轮)
python3 scripts/bench.py

# 自定义参数
python3 scripts/bench.py --rounds 10 --max-tokens 512

# 指定模型和服务地址
python3 scripts/bench.py --model softw8/Nanbeige4.1-3B-q4_K_M --host http://127.0.0.1:11434

# 输出 JSON 结果
python3 scripts/bench.py --output result.json
```

### 性能参考 (CPU 推理)

| 设备 | TTFT | 生成速度 |
|------|------|---------|
| 现代 8 核 CPU | ~1-3s | 8-15 tok/s |
| 4 核 CPU | ~2-5s | 3-8 tok/s |
| Apple M1/M2 | ~0.5-2s | 10-20 tok/s |
| NVIDIA GPU (如 RTX 3060) | ~0.1-0.5s | 30-80 tok/s |

## 日常使用

### 启动 / 停止服务

```bash
# Linux
systemctl --user start ollama    # 启动
systemctl --user stop ollama     # 停止
systemctl --user status ollama   # 状态

# macOS
launchctl load ~/Library/LaunchAgents/com.user.ollama.plist   # 启动
launchctl unload ~/Library/LaunchAgents/com.user.ollama.plist # 停止

# Windows
start_server.cmd   # 启动
stop_server.cmd    # 停止
```

### 命令行对话

```bash
ollama run softw8/Nanbeige4.1-3B-q4_K_M
```

### API 调用

```bash
curl http://127.0.0.1:11434/api/generate \
  -d '{"model": "softw8/Nanbeige4.1-3B-q4_K_M", "prompt": "你好"}'
```

```python
# Python 示例
import requests

response = requests.post("http://127.0.0.1:11434/api/chat", json={
    "model": "softw8/Nanbeige4.1-3B-q4_K_M",
    "messages": [{"role": "user", "content": "你好"}],
    "stream": False
})
print(response.json()["message"]["content"])
```

## 文件结构

```
├── scripts/
│   ├── install_ollama_linux.sh      # Linux 部署脚本
│   ├── install_ollama_macos.sh      # macOS 部署脚本
│   ├── install_ollama_windows.ps1   # Windows 部署脚本 (PowerShell)
│   └── bench.py                     # 跨平台速度基准测试
└── README.md
```

## 安装目录

脚本将 Ollama 安装到用户目录下，无需 root 权限：

| 路径 | 说明 |
|------|------|
| `~/.local/ollama/bin/` | Ollama 可执行文件 |
| `~/.local/ollama/lib/` | 运行库 (CPU/Vulkan/CUDA) |
| `~/.local/ollama/models/` | 模型文件 |
| `~/.local/ollama/ollama_env.sh` | 环境变量配置 |

## 常见问题

### Q: 下载速度慢怎么办？
脚本支持断点续传。如果 `ollama pull` 失败，会自动回退到从 registry 直接下载。你也可以手动设置代理：

```bash
export HTTP_PROXY=http://your-proxy:port
export HTTPS_PROXY=http://your-proxy:port
```

### Q: 如何卸载？
```bash
# Linux / macOS
rm -rf ~/.local/ollama
# 然后从 ~/.bashrc 或 ~/.zshrc 中移除 ollama_env.sh 的 source 行

# Windows
Remove-Item -Recurse -Force "$env:USERPROFILE\.local\ollama"
# 然后从系统环境变量中移除相关路径
```

### Q: 如何使用 GPU 加速？
如果你有 NVIDIA GPU，Ollama 会自动检测并使用 CUDA。确保已安装 NVIDIA 驱动：

```bash
nvidia-smi  # 检查驱动是否正常
```

### Q: 端口被占用怎么办？
修改脚本顶部的 `PORT` 变量为其他端口（如 `8080`）。

## 许可证

- 部署脚本: MIT License
- Ollama: [MIT License](https://github.com/ollama/ollama/blob/main/LICENSE)
- Nanbeige4.1-3B: 请参考 [模型页面](https://ollama.com/softw8/Nanbeige4.1-3B-q4_K_M) 的许可协议
