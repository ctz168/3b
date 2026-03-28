#!/bin/bash
# ============================================================================
#  Ollama + Nanbeige4.1-3B-q4_K_M 一键部署脚本 (Linux)
#  支持: Ubuntu/Debian/CentOS/RHEL/Arch Linux / x86_64 & ARM64
#  用法: bash install_ollama_linux.sh
# ============================================================================

set -e

# ======================== 配置区 ========================
MODEL_NAME="softw8/Nanbeige4.1-3B-q4_K_M"
OLLAMA_VERSION="0.18.3"
INSTALL_DIR="$HOME/.local/ollama"
MODEL_DIR="$INSTALL_DIR/models"
PORT="11434"
# ========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# -------------------- 系统检测 --------------------
detect_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)  echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) error "不支持的架构: $arch (仅支持 x86_64 和 aarch64)" ;;
    esac
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    elif command -v sw_vers &>/dev/null; then
        echo "macos"
    else
        echo "unknown"
    fi
}

check_dependencies() {
    info "检查系统依赖..."
    local missing=()

    for cmd in curl tar; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        warn "缺少依赖: ${missing[*]}，尝试自动安装..."
        local os=$(detect_os)
        case "$os" in
            ubuntu|debian)
                sudo apt-get update -qq && sudo apt-get install -y -qq "${missing[@]}" ;;
            centos|rhel|fedora|rocky|alma)
                sudo yum install -y "${missing[@]}" 2>/dev/null || sudo dnf install -y "${missing[@]}" ;;
            arch|manjaro)
                sudo pacman -S --noconfirm "${missing[@]}" ;;
            *)
                error "无法自动安装依赖，请手动安装: ${missing[*]}" ;;
        esac
    fi
    success "依赖检查通过"
}

# -------------------- 安装 zstd --------------------
install_zstd() {
    if command -v zstd &>/dev/null; then
        success "zstd 已安装: $(zstd --version 2>&1 | head -1)"
        return 0
    fi

    info "zstd 未安装，尝试从包管理器安装..."
    local os=$(detect_os)
    case "$os" in
        ubuntu|debian)
            sudo apt-get install -y -qq zstd 2>/dev/null && return 0 ;;
        centos|rhel|fedora|rocky|alma)
            sudo yum install -y zstd 2>/dev/null || sudo dnf install -y zstd 2>/dev/null && return 0 ;;
        arch|manjaro)
            sudo pacman -S --noconfirm zstd 2>/dev/null && return 0 ;;
    esac

    # 回退: 从源码编译
    warn "包管理器安装失败，从源码编译 zstd..."
    local zstd_tmp=$(mktemp -d)
    curl -fsSL -o "$zstd_tmp/zstd.tar.gz" "https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz"
    tar xzf "$zstd_tmp/zstd.tar.gz" -C "$zstd_tmp"
    make -C "$zstd_tmp/zstd-1.5.7" -j$(nproc) zstd 2>&1 | tail -1
    sudo cp "$zstd_tmp/zstd-1.5.7/zstd" /usr/local/bin/zstd
    rm -rf "$zstd_tmp"
    success "zstd 编译安装完成"
}

# -------------------- 安装 Ollama --------------------
install_ollama() {
    local arch=$(detect_arch)

    if [ -x "$INSTALL_DIR/bin/ollama" ]; then
        local installed_ver=$("$INSTALL_DIR/bin/ollama" --version 2>&1 | grep -oP 'v[\d.]+' || echo "unknown")
        info "Ollama 已安装 ($installed_ver)，跳过安装"
        return 0
    fi

    info "下载 Ollama v${OLLAMA_VERSION} (${arch})..."
    mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/lib"

    local tarball="ollama-linux-${arch}.tar.zst"
    local url="https://github.com/ollama/ollama/releases/download/v${OLLAMA_VERSION}/${tarball}"
    local tmpfile=$(mktemp)

    curl -fsSL -o "$tmpfile" "$url" || error "下载失败: $url"

    info "解压 Ollama..."
    tar --zstd -xf "$tmpfile" -C "$INSTALL_DIR" 2>/dev/null || {
        # 如果系统 tar 不支持 --zstd，手动解压
        zstd -d "$tmpfile" -o "${tmpfile%.zst}" 2>/dev/null
        tar xf "${tmpfile%.zst}" -C "$INSTALL_DIR"
        rm -f "${tmpfile%.zst}"
    }
    rm -f "$tmpfile"

    chmod +x "$INSTALL_DIR/bin/ollama"
    success "Ollama v${OLLAMA_VERSION} 安装完成"
}

# -------------------- 配置环境 --------------------
setup_env() {
    info "配置运行环境..."

    # 创建启动脚本
    cat > "$INSTALL_DIR/ollama_env.sh" << ENVEOF
#!/bin/bash
# Ollama 环境变量 - source 此文件使用: source ~/.local/ollama/ollama_env.sh
export PATH="$INSTALL_DIR/bin:\$PATH"
export LD_LIBRARY_PATH="$INSTALL_DIR/lib/ollama:$INSTALL_DIR/lib/ollama/cpu:$INSTALL_DIR/lib/ollama/vulkan:\${LD_LIBRARY_PATH:-}"
export OLLAMA_HOST="127.0.0.1:${PORT}"
export OLLAMA_MODELS="$MODEL_DIR"
export OLLAMA_NUM_PARALLEL="1"
ENVEOF

    # 创建 systemd 用户服务
    mkdir -p "$HOME/.config/systemd/user"
    cat > "$HOME/.config/systemd/user/ollama.service" << SVCEOF
[Unit]
Description=Ollama LLM Server
After=network.target

[Service]
Type=simple
EnvironmentFile=$INSTALL_DIR/ollama_env.sh
ExecStart=$INSTALL_DIR/bin/ollama serve
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
SVCEOF

    # 添加到 shell profile
    local shell_rc=""
    if [ -n "$ZSH_VERSION" ] || [ "$(basename "$SHELL")" = "zsh" ]; then
        shell_rc="$HOME/.zshrc"
    else
        shell_rc="$HOME/.bashrc"
    fi

    if ! grep -q "ollama_env.sh" "$shell_rc" 2>/dev/null; then
        echo "" >> "$shell_rc"
        echo "# Ollama environment" >> "$shell_rc"
        echo "[ -f \"$INSTALL_DIR/ollama_env.sh\" ] && source \"$INSTALL_DIR/ollama_env.sh\"" >> "$shell_rc"
    fi

    success "环境配置完成"
}

# -------------------- 拉取模型 --------------------
pull_model() {
    source "$INSTALL_DIR/ollama_env.sh"

    # 检查模型是否已存在
    if "$INSTALL_DIR/bin/ollama" list 2>/dev/null | grep -q "nanbeige"; then
        info "模型 $MODEL_NAME 已存在，跳过下载"
        return 0
    fi

    info "拉取模型 $MODEL_NAME (约 2.5GB，请耐心等待)..."
    "$INSTALL_DIR/bin/ollama" pull "$MODEL_NAME" || {
        warn "ollama pull 失败，尝试手动下载..."
        manual_pull_model
    }
    success "模型下载完成"
}

manual_pull_model() {
    # 手动从 registry 下载模型文件（当 ollama pull 不可用时）
    source "$INSTALL_DIR/ollama_env.sh"
    local registry="registry.ollama.com"
    local repo="softw8/nanbeige4.1-3b-q4_k_m"
    local manifest_url="https://${registry}/v2/${repo}/manifests/latest"

    info "从 $manifest_url 获取模型清单..."

    local manifest
    manifest=$(curl -fsSL "$manifest_url") || error "无法获取模型清单"

    mkdir -p "$MODEL_DIR/blobs"
    mkdir -p "$MODEL_DIR/manifests/${registry}/${repo}"

    # 保存 manifest
    echo "$manifest" > "$MODEL_DIR/manifests/${registry}/${repo}/latest"

    # 提取并下载所有 blob
    echo "$manifest" | python3 -c "
import json, sys, subprocess, os

data = json.load(sys.stdin)
blobs_dir = os.environ.get('OLLAMA_MODELS', '$MODEL_DIR') + '/blobs'
registry = '$registry'
repo = '$repo'

for layer in data.get('layers', []):
    digest = layer['digest']
    filename = digest.replace(':', '-')
    filepath = os.path.join(blobs_dir, filename)
    size = layer.get('size', 0)

    if os.path.exists(filepath) and os.path.getsize(filepath) == size:
        print(f'  [跳过] 已存在: {filename} ({size} bytes)')
        continue

    url = f'https://{registry}/v2/{repo}/blobs/{digest}'
    print(f'  [下载] {filename} ({size} bytes)...')
    result = subprocess.run(
        ['curl', '-sL', '--max-time', '1800', '-o', filepath, url],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f'  [错误] 下载失败: {filename}')
    else:
        actual = os.path.getsize(filepath)
        print(f'  [完成] {filename} ({actual} bytes)')

# Also download config blob
config_digest = data.get('config', {}).get('digest', '')
if config_digest:
    filename = config_digest.replace(':', '-')
    filepath = os.path.join(blobs_dir, filename)
    if not os.path.exists(filepath):
        url = f'https://{registry}/v2/{repo}/blobs/{config_digest}'
        print(f'  [下载] {filename} (config)...')
        subprocess.run(['curl', '-sL', '-o', filepath, url], check=True)
" 2>&1

    success "手动下载完成"
}

# -------------------- 启动服务 --------------------
start_server() {
    source "$INSTALL_DIR/ollama_env.sh"

    # 检查是否已在运行
    if curl -s "http://127.0.0.1:${PORT}/api/tags" &>/dev/null; then
        info "Ollama 服务已在运行"
        return 0
    fi

    info "启动 Ollama 服务..."

    # 尝试 systemd
    if command -v systemctl &>/dev/null; then
        systemctl --user daemon-reload 2>/dev/null
        systemctl --user enable ollama 2>/dev/null
        systemctl --user start ollama 2>/dev/null
        sleep 3
        if curl -s "http://127.0.0.1:${PORT}/api/tags" &>/dev/null; then
            success "Ollama 服务已通过 systemd 启动"
            return 0
        fi
    fi

    # 回退: 后台启动
    nohup "$INSTALL_DIR/bin/ollama" serve > "$INSTALL_DIR/ollama.log" 2>&1 &
    local pid=$!
    sleep 3

    if kill -0 $pid 2>/dev/null && curl -s "http://127.0.0.1:${PORT}/api/tags" &>/dev/null; then
        success "Ollama 服务已启动 (PID: $pid)"
        echo "$pid" > "$INSTALL_DIR/ollama.pid"
    else
        error "Ollama 服务启动失败，查看日志: $INSTALL_DIR/ollama.log"
    fi
}

# -------------------- 验证安装 --------------------
verify() {
    source "$INSTALL_DIR/ollama_env.sh"

    echo ""
    echo "=========================================="
    echo "  安装验证"
    echo "=========================================="

    # 版本
    local ver=$("$INSTALL_DIR/bin/ollama" --version 2>&1)
    echo "  Ollama 版本: $ver"

    # 模型列表
    echo ""
    echo "  已安装模型:"
    "$INSTALL_DIR/bin/ollama" list 2>/dev/null | sed 's/^/    /'

    # 快速推理测试
    echo ""
    info "执行快速推理测试..."
    local response
    response=$(curl -s --max-time 120 "http://127.0.0.1:${PORT}/api/generate" \
        -d "{\"model\": \"$MODEL_NAME\", \"prompt\": \"你好\", \"stream\": false}" 2>/dev/null)
    if echo "$response" | python3 -c "import json,sys; d=json.load(sys.stdin); print('  模型回复:', d.get('response','')[:100])" 2>/dev/null; then
        success "推理测试通过！"
    else
        warn "推理测试未通过，请检查服务状态"
    fi

    echo ""
    echo "=========================================="
    echo "  使用方法"
    echo "=========================================="
    echo "  1. 重新加载环境:  source $INSTALL_DIR/ollama_env.sh"
    echo "  2. 启动服务:      ollama serve"
    echo "  3. 命令行对话:    ollama run $MODEL_NAME"
    echo "  4. 速度测试:      python3 $INSTALL_DIR/bench.py"
    echo "  5. 停止服务:      systemctl --user stop ollama"
    echo "                     或 kill \$(cat $INSTALL_DIR/ollama.pid)"
    echo "=========================================="
}

# -------------------- 主流程 --------------------
main() {
    echo ""
    echo "=========================================="
    echo "  Ollama + Nanbeige4.1-3B 部署脚本 (Linux)"
    echo "  模型: $MODEL_NAME"
    echo "=========================================="
    echo ""

    check_dependencies
    install_zstd
    install_ollama
    setup_env
    start_server
    pull_model
    verify

    echo ""
    success "部署完成！"
}

main "$@"
