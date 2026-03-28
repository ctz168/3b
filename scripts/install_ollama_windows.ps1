# ============================================================================
#  Ollama + Nanbeige4.1-3B-q4_K_M 一键部署脚本 (Windows)
#  支持: Windows 10/11 / x86_64
#  用法: 以管理员身份运行 PowerShell，然后:
#        Set-ExecutionPolicy Bypass -Scope Process -Force
#        .\install_ollama_windows.ps1
# ============================================================================

# ======================== 配置区 ========================
$ModelName = "softw8/Nanbeige4.1-3B-q4_K_M"
$OllamaVersion = "0.18.3"
$InstallDir = "$env:USERPROFILE\.local\ollama"
$ModelDir = "$InstallDir\models"
$Port = "11434"
# ========================================================

function Write-Info    { Write-Host "[INFO] $args" -ForegroundColor Blue }
function Write-Ok      { Write-Host "[OK]   $args" -ForegroundColor Green }
function Write-Warn    { Write-Host "[WARN] $args" -ForegroundColor Yellow }
function Write-Err     { Write-Host "[ERROR] $args" -ForegroundColor Red; exit 1 }

# -------------------- 系统检测 --------------------
function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warn "未以管理员身份运行，部分功能可能受限"
        Write-Warn "建议右键 PowerShell -> 以管理员身份运行"
    }
}

function Get-SystemArch {
    if ([Environment]::Is64BitOperatingSystem) {
        return "amd64"
    } else {
        Write-Err "不支持 32 位系统，请使用 64 位 Windows"
    }
}

# -------------------- 安装 Ollama --------------------
function Install-Ollama {
    $arch = Get-SystemArch

    $ollamaExe = "$InstallDir\bin\ollama.exe"
    if (Test-Path $ollamaExe) {
        Write-Info "Ollama 已安装，跳过安装"
        return
    }

    Write-Info "下载 Ollama v$OllamaVersion ($arch)..."

    $zipName = "Ollama-windows-$arch.zip"
    $url = "https://github.com/ollama/ollama/releases/download/v$OllamaVersion/$zipName"
    $tmpZip = "$env:TEMP\ollama.zip"

    try {
        # 使用 TLS 1.2
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $tmpZip -UseBasicParsing
    } catch {
        Write-Err "下载失败: $url`n错误: $_"
    }

    Write-Info "解压 Ollama..."
    New-Item -ItemType Directory -Force -Path "$InstallDir\bin" | Out-Null
    New-Item -ItemType Directory -Force -Path "$InstallDir\lib" | Out-Null

    try {
        Expand-Archive -Path $tmpZip -DestinationPath $InstallDir -Force
    } catch {
        # 回退: 使用 COM 对象解压
        Write-Warn "Expand-Archive 失败，尝试备用解压方式..."
        $shell = New-Object -ComObject Shell.Application
        $zip = $shell.NameSpace($tmpZip)
        $dest = $shell.NameSpace($InstallDir)
        $dest.CopyHere($zip.Items(), 0x10)
    }
    Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path $ollamaExe)) {
        # 查找解压后的 ollama.exe
        $found = Get-ChildItem -Path $InstallDir -Filter "ollama.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            New-Item -ItemType Directory -Force -Path "$InstallDir\bin" | Out-Null
            Copy-Item $found.FullName "$InstallDir\bin\ollama.exe" -Force
        } else {
            Write-Err "解压后未找到 ollama.exe"
        }
    }

    Write-Ok "Ollama v$OllamaVersion 安装完成"
}

# -------------------- 配置环境 --------------------
function Set-OllamaEnv {
    Write-Info "配置运行环境..."

    # 设置系统环境变量 (永久)
    $envPaths = @(
        "$InstallDir\bin",
        "$InstallDir\lib\ollama",
        "$InstallDir\lib\ollama\cpu",
        "$InstallDir\lib\ollama\vulkan"
    )

    # PATH
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    foreach ($p in $envPaths) {
        if ($currentPath -notlike "*$p*") {
            $currentPath = "$p;$currentPath"
        }
    }
    [Environment]::SetEnvironmentVariable("Path", $currentPath, "User")
    $env:Path = $currentPath

    # OLLAMA_HOST
    [Environment]::SetEnvironmentVariable("OLLAMA_HOST", "127.0.0.1:$Port", "User")
    $env:OLLAMA_HOST = "127.0.0.1:$Port"

    # OLLAMA_MODELS
    [Environment]::SetEnvironmentVariable("OLLAMA_MODELS", $ModelDir, "User")
    $env:OLLAMA_MODELS = $ModelDir

    # 创建环境变量脚本
    $envScript = @"
@echo off
REM Ollama 环境变量
set PATH=$InstallDir\bin;%PATH%
set OLLAMA_HOST=127.0.0.1:$Port
set OLLAMA_MODELS=$ModelDir
"@
    $envScript | Out-File -FilePath "$InstallDir\ollama_env.cmd" -Encoding ASCII

    # 创建启动/停止脚本
    $startScript = @"
@echo off
echo Starting Ollama server...
start /B "" "$InstallDir\bin\ollama.exe" serve > "$InstallDir\ollama.log" 2>&1
echo Ollama server started. Log: $InstallDir\ollama.log
timeout /t 3 >nul
curl -s http://127.0.0.1:$Port/api/tags
"@
    $startScript | Out-File -FilePath "$InstallDir\start_server.cmd" -Encoding ASCII

    $stopScript = @"
@echo off
echo Stopping Ollama server...
taskkill /F /IM ollama.exe 2>nul
echo Ollama server stopped.
"@
    $stopScript | Out-File -FilePath "$InstallDir\stop_server.cmd" -Encoding ASCII

    Write-Ok "环境配置完成"
}

# -------------------- 拉取模型 --------------------
function Pull-Model {
    $env:OLLAMA_HOST = "127.0.0.1:$Port"
    $env:OLLAMA_MODELS = $ModelDir

    # 检查模型是否已存在
    $listOutput = & "$InstallDir\bin\ollama.exe" list 2>&1
    if ($listOutput -match "nanbeige") {
        Write-Info "模型 $ModelName 已存在，跳过下载"
        return
    }

    Write-Info "拉取模型 $ModelName (约 2.5GB，请耐心等待)..."
    & "$InstallDir\bin\ollama.exe" pull $ModelName
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "ollama pull 失败，尝试手动下载..."
        Pull-Model-Manual
    }
    Write-Ok "模型下载完成"
}

function Pull-Model-Manual {
    $registry = "registry.ollama.com"
    $repo = "softw8/nanbeige4.1-3b-q4_k_m"
    $manifestUrl = "https://${registry}/v2/${repo}/manifests/latest"

    Write-Info "从 $manifestUrl 获取模型清单..."

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $manifest = Invoke-RestMethod -Uri $manifestUrl -UseBasicParsing
    } catch {
        Write-Err "无法获取模型清单: $_"
    }

    New-Item -ItemType Directory -Force -Path "$ModelDir\blobs" | Out-Null
    New-Item -ItemType Directory -Force -Path "$ModelDir\manifests\$registry\$repo" | Out-Null

    # 保存 manifest
    $manifest | ConvertTo-Json -Depth 10 | Out-File -FilePath "$ModelDir\manifests\$registry\$repo\latest" -Encoding UTF8

    # 下载所有 blob
    $allBlobs = @()
    $allBlobs += $manifest.layers | ForEach-Object { $_.digest }
    if ($manifest.config.digest) {
        $allBlobs += $manifest.config.digest
    }

    foreach ($blob in $allBlobs) {
        $filename = $blob -replace ':', '-'
        $filepath = "$ModelDir\blobs\$filename"
        $blobUrl = "https://${registry}/v2/${repo}/blobs/$blob"

        if (Test-Path $filepath) {
            Write-Info "  [跳过] 已存在: $filename"
            continue
        }

        Write-Info "  [下载] $filename..."
        try {
            Invoke-WebRequest -Uri $blobUrl -OutFile $filepath -UseBasicParsing -MaximumRedirection 5
            Write-Ok "  [完成] $filename"
        } catch {
            Write-Warn "  [错误] 下载失败: $filename"
        }
    }

    Write-Ok "手动下载完成"
}

# -------------------- 启动服务 --------------------
function Start-Server {
    $env:OLLAMA_HOST = "127.0.0.1:$Port"
    $env:OLLAMA_MODELS = $ModelDir

    try {
        $response = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/api/tags" -UseBasicParsing -TimeoutSec 5
        Write-Info "Ollama 服务已在运行"
        return
    } catch {
        # 服务未运行
    }

    Write-Info "启动 Ollama 服务..."

    # 检查是否已有 ollama 进程
    $existing = Get-Process -Name "ollama" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Warn "发现已有 ollama 进程，先停止..."
        Stop-Process -Name "ollama" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    Start-Process -FilePath "$InstallDir\bin\ollama.exe" `
        -ArgumentList "serve" `
        -WindowStyle Hidden `
        -RedirectStandardOutput "$InstallDir\ollama.log" `
        -RedirectStandardError "$InstallDir\ollama_err.log"

    Start-Sleep -Seconds 5

    try {
        $response = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/api/tags" -UseBasicParsing -TimeoutSec 5
        Write-Ok "Ollama 服务已启动"
    } catch {
        Write-Err "Ollama 服务启动失败，查看日志: $InstallDir\ollama.log"
    }
}

# -------------------- 验证安装 --------------------
function Test-Installation {
    $env:OLLAMA_HOST = "127.0.0.1:$Port"
    $env:OLLAMA_MODELS = $ModelDir

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  安装验证" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan

    # 版本
    $ver = & "$InstallDir\bin\ollama.exe" --version 2>&1
    Write-Host "  Ollama 版本: $ver"

    # 模型列表
    Write-Host ""
    Write-Host "  已安装模型:"
    & "$InstallDir\bin\ollama.exe" list 2>&1 | ForEach-Object { Write-Host "    $_" }

    # 快速推理测试
    Write-Host ""
    Write-Info "执行快速推理测试..."
    try {
        $body = @{
            model  = $ModelName
            prompt = "你好"
            stream = $false
        } | ConvertTo-Json

        $response = Invoke-RestMethod `
            -Uri "http://127.0.0.1:$Port/api/generate" `
            -Method Post `
            -Body $body `
            -ContentType "application/json" `
            -UseBasicParsing `
            -TimeoutSec 120

        $reply = $response.response
        if ($reply) {
            Write-Host "  模型回复: $($reply.Substring(0, [Math]::Min(100, $reply.Length)))"
            Write-Ok "推理测试通过！"
        } else {
            Write-Warn "推理测试未通过：模型未返回内容"
        }
    } catch {
        Write-Warn "推理测试未通过: $_"
    }

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  使用方法" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  1. 启动服务:  $InstallDir\start_server.cmd"
    Write-Host "  2. 停止服务:  $InstallDir\stop_server.cmd"
    Write-Host "  3. 命令行对话: ollama run $ModelName"
    Write-Host "  4. 速度测试:  python $InstallDir\bench.py"
    Write-Host "==========================================" -ForegroundColor Cyan
}

# -------------------- 主流程 --------------------
function Main {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  Ollama + Nanbeige4.1-3B 部署脚本 (Windows)" -ForegroundColor Cyan
    Write-Host "  模型: $ModelName" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    Test-Admin
    Install-Ollama
    Set-OllamaEnv
    Start-Server
    Pull-Model
    Test-Installation

    Write-Host ""
    Write-Ok "部署完成！"
}

Main
