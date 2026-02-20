#Requires -Version 7.0
# Build-SingleFile.ps1 - 安装器单文件打包构建脚本
# 作者: 哈雷酱 (本小姐的构建工具杰作！)
# 功能: 将多文件安装器打包成独立可分发的单文件脚本

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── 构建顺序定义 ──────────────────────────────────────────────────────────────

function Get-BootstrapBuildOrder {
    <#
    .SYNOPSIS
    返回 Bootstrap 脚本构建时需要按顺序拼接的文件路径数组
    .RETURNS
    string[] - 相对于 installer/ 目录的文件路径数组
    #>
    return @(
        'core/Admin.ps1'
        'core/Ui.ps1'
        'core/Process.ps1'
        'Bootstrap-ClaudeEnv.ps1'
    )
}

function Get-MainInstallerBuildOrder {
    <#
    .SYNOPSIS
    返回主安装脚本构建时需要按顺序拼接的文件路径数组
    .RETURNS
    string[] - 相对于 installer/ 目录的文件路径数组
    .NOTES
    ⚠️  新增步骤文件（如 Step14.*.ps1）时，必须同步更新此函数，否则产物将缺失该步骤！
    #>
    return @(
        'core/Ui.ps1'
        'core/Process.ps1'
        'core/Profile.ps1'
        'core/Admin.ps1'
        'core/Net.ps1'
        'core/Bootstrap.ps1'
        'steps/Step01.Proxy.ps1'
        'steps/Step02.NodeFnm.ps1'
        'steps/Step03.Git.ps1'
        'steps/Step04.ClaudeCode.ps1'
        'steps/Step05.Ccline.ps1'
        'steps/Step06.CcSwitch.ps1'
        'steps/Step07.ApiKey.ps1'
        'steps/Step08.ClaudeConfig.ps1'
        'steps/Step09.ClaudeMd.ps1'
        'steps/Step10.Mcp.ps1'
        'steps/Step11.CcgWorkflow.ps1'
        'steps/Step12.CodexCli.ps1'
        'steps/Step13.GeminiCli.ps1'
        'Install-ClaudeEnv.ps1'
    )
}

# ─── 核心构建函数 ──────────────────────────────────────────────────────────────

function Build-SingleFileScript {
    <#
    .SYNOPSIS
    将多个源文件合并为单个可分发脚本
    .PARAMETER InstallerRoot
    installer/ 目录的绝对路径
    .PARAMETER FileOrder
    文件相对路径数组（来自 Get-*BuildOrder）
    .PARAMETER OutputPath
    输出文件的绝对路径
    .PARAMETER RequiresHeader
    文件头部的 #Requires 声明（如 "#Requires -Version 5.1"）
    #>
    param(
        [Parameter(Mandatory)]
        [string]$InstallerRoot,

        [Parameter(Mandatory)]
        [string[]]$FileOrder,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter(Mandatory)]
        [string]$RequiresHeader
    )

    # 验证所有源文件存在
    foreach ($relPath in $FileOrder) {
        $fullPath = Join-Path $InstallerRoot $relPath
        if (-not (Test-Path $fullPath)) {
            throw "源文件不存在: $fullPath"
        }
    }

    # 构建输出缓冲区
    $buffer = [System.Collections.Generic.List[string]]::new()

    # 文件头注释
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $buffer.Add("# ═══════════════════════════════════════════════════════════════════════════════")
    $buffer.Add("# 本文件由 Build-SingleFile.ps1 自动生成，请勿手动编辑")
    $buffer.Add("# 生成时间: $timestamp")
    $buffer.Add("# 原始文件:")
    foreach ($relPath in $FileOrder) {
        $buffer.Add("#   - $relPath")
    }
    $buffer.Add("# ═══════════════════════════════════════════════════════════════════════════════")

    # #Requires 声明
    $buffer.Add($RequiresHeader)
    $buffer.Add("")

    # dot-source 行匹配模式（已内联的依赖无需再 dot-source）
    # 注意：本过滤基于行文本，覆盖 `. "path"`、`. 'path'`、`. $var` 等所有常见形式。
    # 约束：不适用于 here-string 内含有 `. ` 开头的普通文本行（当前源文件中不存在此情况）。
    $dotSourcePattern = '^\s*\.\s+'

    # 逐文件读取并拼接
    foreach ($relPath in $FileOrder) {
        $fullPath = Join-Path $InstallerRoot $relPath

        # 分隔注释
        $buffer.Add("")
        $separator = "# " + [string]::new([char]0x2500, 3) + " 来自: $relPath " + [string]::new([char]0x2500, 40)
        $buffer.Add($separator)
        $buffer.Add("")

        # 读取并过滤内容
        $lines = Get-Content -Path $fullPath -Encoding UTF8
        foreach ($line in $lines) {
            # 剥离 dot-source 行（已内联）
            if ($line -match $dotSourcePattern) {
                continue
            }
            # 剥离 #Requires 行（已在头部统一声明）
            if ($line -match '^\s*#Requires\s') {
                continue
            }
            $buffer.Add($line)
        }
    }

    # 原子写入：先写临时文件，再移动到目标路径
    $outputDir = Split-Path -Parent $OutputPath
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    $tempPath = Join-Path $outputDir ("_tmp_" + [System.IO.Path]::GetRandomFileName() + ".ps1")
    try {
        # 必须用 utf8BOM（带 BOM 的 UTF-8）：
        # GitHub Release 以 application/octet-stream 下发，无 charset 信息。
        # PS5 的 irm 遇到无 BOM 的 UTF-8 文件会按 Latin-1 解码，导致中文乱码。
        # 写入 BOM (EF BB BF) 后，PS5 可正确识别为 UTF-8 并解码中文字符串。
        $buffer -join "`r`n" | Set-Content -Path $tempPath -Encoding utf8BOM -NoNewline
        # 原子替换：Move-Item -Force 在 Windows 上可直接覆盖同卷文件，
        # 无需先删除旧文件（避免"删除成功 + 移动失败"导致产物丢失的窗口）
        Move-Item -Path $tempPath -Destination $OutputPath -Force
    } catch {
        # 清理临时文件
        if (Test-Path $tempPath) {
            Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }

    Write-Host "[PASS] 已生成: $OutputPath" -ForegroundColor Green
}

# ─── 语法检验 ──────────────────────────────────────────────────────────────────

function Test-BuiltScriptSyntax {
    <#
    .SYNOPSIS
    使用 PowerShell 解析器检验脚本语法
    .PARAMETER ScriptPath
    要检验的脚本文件路径
    .RETURNS
    bool - 语法检查是否通过
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )

    if (-not (Test-Path $ScriptPath)) {
        Write-Host "[FAIL] 文件不存在: $ScriptPath" -ForegroundColor Red
        return $false
    }

    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile(
        $ScriptPath, [ref]$null, [ref]$errors
    )

    if ($errors.Count -gt 0) {
        Write-Host "[FAIL] 语法错误 ($ScriptPath):" -ForegroundColor Red
        foreach ($err in $errors) {
            Write-Host "  行 $($err.Extent.StartLineNumber): $($err.Message)" -ForegroundColor Red
        }
        return $false
    } else {
        Write-Host "[PASS] 语法检查通过: $ScriptPath" -ForegroundColor Green
        return $true
    }
}

# ─── 入口函数 ──────────────────────────────────────────────────────────────────

function Main {
    <#
    .SYNOPSIS
    构建入口：生成 Bootstrap 和 Installer 的单文件版本
    .PARAMETER InstallerRoot
    installer/ 目录的绝对路径
    .PARAMETER OutputDir
    输出目录路径
    #>
    param(
        [string]$InstallerRoot = (Resolve-Path "$PSScriptRoot\..").Path,
        [string]$OutputDir = "$PSScriptRoot\dist"
    )

    # 验证 InstallerRoot 是否为有效目录
    if (-not (Test-Path $InstallerRoot -PathType Container)) {
        throw "InstallerRoot 不是有效目录: $InstallerRoot"
    }

    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Claude Code 安装器 - 单文件构建工具" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "安装器根目录: $InstallerRoot"
    Write-Host "输出目录:     $OutputDir"
    Write-Host ""

    # 确保输出目录存在
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
        Write-Host "已创建输出目录: $OutputDir"
    }

    # 构建 Bootstrap 单文件版本
    Write-Host ""
    Write-Host "─── 构建 Bootstrap 单文件版本 ───────────────────────────────" -ForegroundColor Yellow
    $bootstrapOrder = Get-BootstrapBuildOrder
    $bootstrapOutput = Join-Path $OutputDir "Bootstrap-ClaudeEnv.built.ps1"
    Build-SingleFileScript `
        -InstallerRoot $InstallerRoot `
        -FileOrder $bootstrapOrder `
        -OutputPath $bootstrapOutput `
        -RequiresHeader "#Requires -Version 5.1"

    # 构建 Installer 单文件版本
    Write-Host ""
    Write-Host "─── 构建 Installer 单文件版本 ──────────────────────────────" -ForegroundColor Yellow
    $installerOrder = Get-MainInstallerBuildOrder
    $installerOutput = Join-Path $OutputDir "Install-ClaudeEnv.built.ps1"
    Build-SingleFileScript `
        -InstallerRoot $InstallerRoot `
        -FileOrder $installerOrder `
        -OutputPath $installerOutput `
        -RequiresHeader "#Requires -Version 7.0"

    # 语法检查
    Write-Host ""
    Write-Host "─── 语法检查 ───────────────────────────────────────────────" -ForegroundColor Yellow
    $bootstrapOk = Test-BuiltScriptSyntax -ScriptPath $bootstrapOutput
    $installerOk = Test-BuiltScriptSyntax -ScriptPath $installerOutput

    # 构建摘要
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  构建摘要" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

    $bootstrapSize = if (Test-Path $bootstrapOutput) { (Get-Item $bootstrapOutput).Length } else { 0 }
    $installerSize = if (Test-Path $installerOutput) { (Get-Item $installerOutput).Length } else { 0 }

    Write-Host "  Bootstrap:  $bootstrapOutput"
    Write-Host "              大小: $([math]::Round($bootstrapSize / 1KB, 1)) KB | 语法: $(if ($bootstrapOk) { '[PASS]' } else { '[FAIL]' })"
    Write-Host "  Installer:  $installerOutput"
    Write-Host "              大小: $([math]::Round($installerSize / 1KB, 1)) KB | 语法: $(if ($installerOk) { '[PASS]' } else { '[FAIL]' })"
    Write-Host ""

    if ($bootstrapOk -and $installerOk) {
        Write-Host "  构建完成！所有文件语法检查通过。" -ForegroundColor Green
    } else {
        Write-Host "  构建完成，但存在语法错误，请检查。" -ForegroundColor Red
        exit 1
    }
}

# 执行入口
Main
