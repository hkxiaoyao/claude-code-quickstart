#Requires -Version 7.0
# build.ps1 - 安装器单文件打包构建脚本
# 作者: 哈雷酱 (本小姐的构建工具杰作！)
# 功能: 将多文件安装器打包成独立可分发的单文件脚本

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── 构建顺序定义 ──────────────────────────────────────────────────────────────

function Get-BuildManifest {
    <#
    .SYNOPSIS
    读取跨平台构建清单，统一 artifact 名称、入口与 core 顺序。
    #>
    param()

    $manifestPath = Join-Path $PSScriptRoot 'contracts\build.json'
    if (-not (Test-Path $manifestPath -PathType Leaf)) {
        throw "构建清单不存在: $manifestPath"
    }

    return (Get-Content -Path $manifestPath -Encoding UTF8 -Raw | ConvertFrom-Json -AsHashtable)
}

function Get-BuildArtifactConfig {
    <#
    .SYNOPSIS
    从构建清单中获取指定平台与角色的 artifact 配置。
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Windows', 'MacOS')]
        [string]$Platform,

        [Parameter(Mandatory)]
        [string]$Role
    )

    $manifest = Get-BuildManifest
    $artifacts = @($manifest[$Platform]['Artifacts'])
    foreach ($artifact in $artifacts) {
        if ([string]$artifact['Role'] -eq $Role) {
            return $artifact
        }
    }
    throw "未找到构建 artifact 配置: $Platform/$Role"
}

function Get-BuildArtifactPathList {
    <#
    .SYNOPSIS
    从 artifact 配置字段读取路径数组。
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Artifact,

        [Parameter(Mandatory)]
        [string]$FieldName
    )

    if (-not $Artifact.ContainsKey($FieldName)) {
        return @()
    }
    return @($Artifact[$FieldName] | ForEach-Object { [string]$_ })
}

function ConvertTo-WindowsBuildPath {
    <#
    .SYNOPSIS
    将 Registry 返回的 Windows 步骤路径归一化为 installer/ 相对 canonical 路径。
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $normalized = $Path -replace '\\', '/'
    if ($normalized -like 'windows/*') {
        return $normalized
    }
    return "windows/$normalized"
}

function Get-BootstrapBuildOrder {
    <#
    .SYNOPSIS
    返回 Bootstrap 脚本构建时需要按顺序拼接的文件路径数组
    .RETURNS
    string[] - 相对于 installer/ 目录的文件路径数组
    #>
    $artifact = Get-BuildArtifactConfig -Platform Windows -Role Bootstrap
    return @((Get-BuildArtifactPathList -Artifact $artifact -FieldName 'CoreFiles') + @([string]$artifact['EntryFile']))
}

function Get-InstallBuildOrder {
    <#
    .SYNOPSIS
    返回安装入口脚本构建时需要按顺序拼接的文件路径数组
    .RETURNS
    string[] - 相对于 installer/ 目录的文件路径数组
    #>
    $artifact = Get-BuildArtifactConfig -Platform Windows -Role Install
    $coreFiles = Get-BuildArtifactPathList -Artifact $artifact -FieldName 'CoreFiles'

    # 步骤文件从 Registry 动态获取
    . "$PSScriptRoot\windows\core\Registry.ps1"
    $stepFiles = @(Get-StepFiles | ForEach-Object { ConvertTo-WindowsBuildPath -Path $_ })

    return @($coreFiles + $stepFiles + @([string]$artifact['EntryFile']))
}

function Get-ManageBuildOrder {
    <#
    .SYNOPSIS
    返回管理入口脚本构建时需要按顺序拼接的文件路径数组
    .RETURNS
    string[] - 相对于 installer/ 目录的文件路径数组
    #>
    $artifact = Get-BuildArtifactConfig -Platform Windows -Role Manage
    $coreFiles = Get-BuildArtifactPathList -Artifact $artifact -FieldName 'CoreFiles'

    . "$PSScriptRoot\windows\core\Registry.ps1"
    $stepFiles = @(Get-StepFiles | ForEach-Object { ConvertTo-WindowsBuildPath -Path $_ })

    return @($coreFiles + $stepFiles + @([string]$artifact['EntryFile']))
}

function Get-MacOSCoreBuildOrder {
    <#
    .SYNOPSIS
    返回 macOS core zsh 文件构建顺序。
    .RETURNS
    string[] - 相对于 installer/ 目录的文件路径数组
    #>
    $manifest = Get-BuildManifest
    return @($manifest['MacOS']['CoreFiles'] | ForEach-Object { [string]$_ })
}

function Get-MacOSStepBuildOrder {
    <#
    .SYNOPSIS
    返回已存在的 macOS step zsh 文件构建顺序。
    .RETURNS
    string[] - 相对于 installer/ 目录的文件路径数组
    #>
    $stepsContractPath = Join-Path $PSScriptRoot 'contracts\steps.json'
    if (-not (Test-Path $stepsContractPath -PathType Leaf)) {
        return @()
    }

    $contract = Get-Content -Path $stepsContractPath -Encoding UTF8 -Raw | ConvertFrom-Json -AsHashtable
    $manifest = Get-BuildManifest
    $stepFiles = @()
    $commonStepFile = [string]$manifest['MacOS']['CommonStepFile']
    $commonStepPath = Join-Path (Resolve-Path $PSScriptRoot).Path $commonStepFile
    if (Test-Path $commonStepPath -PathType Leaf) {
        $stepFiles += $commonStepFile
    }

    foreach ($step in @($contract.Steps | Sort-Object { [int]$_['Order'] })) {
        $macOSStepFile = [string]$step['MacOSStepFile']
        if ([string]::IsNullOrWhiteSpace($macOSStepFile)) { continue }

        $fullPath = Join-Path (Resolve-Path $PSScriptRoot).Path $macOSStepFile
        if (Test-Path $fullPath -PathType Leaf) {
            $stepFiles += $macOSStepFile
        }
    }

    return @($stepFiles)
}

function Get-MacOSInstallBuildOrder {
    <#
    .SYNOPSIS
    返回 macOS Install zsh 构建顺序。
    .RETURNS
    string[] - 相对于 installer/ 目录的文件路径数组
    #>
    $artifact = Get-BuildArtifactConfig -Platform MacOS -Role Install
    return @((Get-MacOSCoreBuildOrder) + (Get-MacOSStepBuildOrder) + @([string]$artifact['EntryFile']))
}

function Get-MacOSManageBuildOrder {
    <#
    .SYNOPSIS
    返回 macOS Manage zsh 构建顺序。
    .RETURNS
    string[] - 相对于 installer/ 目录的文件路径数组
    #>
    $artifact = Get-BuildArtifactConfig -Platform MacOS -Role Manage
    return @((Get-MacOSCoreBuildOrder) + (Get-MacOSStepBuildOrder) + @([string]$artifact['EntryFile']))
}

function Get-ScriptParamBlockInfo {
    <#
    .SYNOPSIS
    解析脚本的顶层 param 块，并返回其行号范围与原始文本行
    .PARAMETER ScriptPath
    脚本绝对路径
    .RETURNS
    hashtable 或 $null（无 param 块时）
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )

    if (-not (Test-Path $ScriptPath -PathType Leaf)) {
        return $null
    }

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $ScriptPath, [ref]$tokens, [ref]$errors
    )

    if (-not $ast.ParamBlock) {
        return $null
    }

    $startLine = $ast.ParamBlock.Extent.StartLineNumber
    $endLine = $ast.ParamBlock.Extent.EndLineNumber
    $allLines = Get-Content -Path $ScriptPath -Encoding UTF8

    if ($allLines.Count -lt $startLine) {
        return $null
    }

    $paramLines = $allLines[($startLine - 1)..($endLine - 1)]

    return @{
        StartLine = $startLine
        EndLine = $endLine
        Lines = $paramLines
    }
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
        [string]$RequiresHeader,

        # 需要被提升到单文件顶部的 param 来源文件（相对 installer/）
        [string]$HoistParamFromRelativePath = '',

        # PS5 读脚本默认用 ANSI，需要 BOM 才能识别 UTF-8；PS7 无此限制
        [string]$OutputEncoding = 'UTF8'
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
    $buffer.Add("# 本文件由 build.ps1 自动生成，请勿手动编辑")
    $buffer.Add("# 生成时间: $timestamp")
    $buffer.Add("# 原始文件:")
    foreach ($relPath in $FileOrder) {
        $buffer.Add("#   - $relPath")
    }
    $buffer.Add("# ═══════════════════════════════════════════════════════════════════════════════")

    # #Requires 声明
    $buffer.Add($RequiresHeader)
    $buffer.Add("")

    # 需要时将入口脚本 param 块提升到最顶部（#Requires 之后）
    $hoistedParamInfo = $null
    if ($HoistParamFromRelativePath) {
        $paramSourcePath = Join-Path $InstallerRoot $HoistParamFromRelativePath
        $hoistedParamInfo = Get-ScriptParamBlockInfo -ScriptPath $paramSourcePath
        if (-not $hoistedParamInfo) {
            throw "未找到可提升的 param 块: $paramSourcePath"
        }

        foreach ($paramLine in $hoistedParamInfo.Lines) {
            $buffer.Add($paramLine)
        }
        $buffer.Add("")
    }

    # dot-source 行匹配模式（已内联的依赖无需再 dot-source）
    # 注意：本过滤基于行文本，覆盖 `. "path"`、`. 'path'`、`. $var` 等所有常见形式。
    # 约束：不适用于 here-string 内含有 `. ` 开头的普通文本行（当前源文件中不存在此情况）。
    $dotSourcePattern = '^\s*\.\s+'

    # $scriptRoot 计算行匹配模式（单文件模式下不需要，且 irm|iex 时会失败）
    # 匹配形如: $scriptRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
    $scriptRootPattern = '^\s*\$scriptRoot\s*=\s*Split-Path\s+.*\$MyInvocation\.MyCommand\.Path'

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
        $lineNumber = 0
        foreach ($line in $lines) {
            $lineNumber++

            # 跳过已提升到脚本顶部的 param 块，避免重复定义
            if ($hoistedParamInfo -and
                $relPath -eq $HoistParamFromRelativePath -and
                $lineNumber -ge $hoistedParamInfo.StartLine -and
                $lineNumber -le $hoistedParamInfo.EndLine) {
                continue
            }

            # 剥离 dot-source 行（已内联）
            if ($line -match $dotSourcePattern) {
                continue
            }
            # 剥离 #Requires 行（已在头部统一声明）
            if ($line -match '^\s*#Requires\s') {
                continue
            }
            # 剥离 $scriptRoot 计算行（单文件模式下不需要，且 irm|iex 时会失败）
            if ($line -match $scriptRootPattern) {
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
        $buffer -join "`r`n" | Set-Content -Path $tempPath -Encoding $OutputEncoding -NoNewline
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

function Build-ZshSingleFileScript {
    <#
    .SYNOPSIS
    将多个 zsh 源文件合并为兼容 curl | bash 的 macOS 单文件脚本。
    .PARAMETER InstallerRoot
    installer/ 目录的绝对路径
    .PARAMETER FileOrder
    文件相对路径数组（来自 Get-MacOS*BuildOrder）
    .PARAMETER OutputPath
    输出文件的绝对路径
    #>
    param(
        [Parameter(Mandatory)]
        [string]$InstallerRoot,

        [Parameter(Mandatory)]
        [string[]]$FileOrder,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    foreach ($relPath in $FileOrder) {
        $fullPath = Join-Path $InstallerRoot $relPath
        if (-not (Test-Path $fullPath -PathType Leaf)) {
            throw "源文件不存在: $fullPath"
        }
    }

    $buffer = [System.Collections.Generic.List[string]]::new()
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    $buffer.Add('#!/usr/bin/env bash')
    $buffer.Add('# ═══════════════════════════════════════════════════════════════════════════════')
    $buffer.Add('# 本文件由 build.ps1 自动生成，请勿手动编辑')
    $buffer.Add("# 生成时间: $timestamp")
    $buffer.Add('# 原始文件:')
    foreach ($relPath in $FileOrder) {
        $buffer.Add("#   - $relPath")
    }
    $buffer.Add('# ═══════════════════════════════════════════════════════════════════════════════')
    $buffer.Add('if [ -z "${ZSH_VERSION:-}" ]; then')
    $buffer.Add('  if [ -x "/bin/zsh" ]; then')
    $buffer.Add('    if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then')
    $buffer.Add('      exec /bin/zsh "${BASH_SOURCE[0]}" "$@"')
    $buffer.Add('    fi')
    $buffer.Add('    ccq_streamed_script="$(mktemp "${TMPDIR:-/tmp}/ccq-built.XXXXXX.zsh")" || exit 1')
    $buffer.Add('    cat > "${ccq_streamed_script}"')
    $buffer.Add('    export CCQ_STREAMED_SCRIPT_PATH="${ccq_streamed_script}"')
    $buffer.Add('    exec /bin/zsh "${ccq_streamed_script}" "$@"')
    $buffer.Add('  fi')
    $buffer.Add("  printf '%s\n' 'CCQ macOS built script requires /bin/zsh.' >&2")
    $buffer.Add('  exit 1')
    $buffer.Add('fi')
    $buffer.Add('export CCQ_BUILT_MODE=1')
    $buffer.Add('ccq_cleanup_built_artifacts() {')
    $buffer.Add('  if [ -n "${CCQ_STREAMED_SCRIPT_PATH:-}" ]; then rm -f "${CCQ_STREAMED_SCRIPT_PATH}"; fi')
    $buffer.Add('  if [ -n "${CCQ_BUILT_CONTRACTS_DIR:-}" ]; then rm -rf "${CCQ_BUILT_CONTRACTS_DIR}"; fi')
    $buffer.Add('}')
    $buffer.Add('trap ccq_cleanup_built_artifacts EXIT')
    $buffer.Add('CCQ_BUILT_CONTRACTS_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ccq-contracts.XXXXXX")" || exit 1')
    $buffer.Add('export CCQ_BUILT_CONTRACTS_DIR')
    $buffer.Add('export CCQ_CONTRACTS_DIR="${CCQ_BUILT_CONTRACTS_DIR}"')
    $buffer.Add('export CCQ_STEPS_CONTRACT="${CCQ_BUILT_CONTRACTS_DIR}/steps.json"')
    $buffer.Add('export CCQ_PROVIDER_CONTRACT="${CCQ_BUILT_CONTRACTS_DIR}/providers.json"')
    $buffer.Add('export CCQ_MCP_CONTRACT="${CCQ_BUILT_CONTRACTS_DIR}/mcp-servers.json"')
    $buffer.Add('export CCQ_CLAUDE_CONFIG_CONTRACT="${CCQ_BUILT_CONTRACTS_DIR}/claude-config.json"')

    $embeddedContracts = @(
        @{ Name = 'steps.json'; Marker = 'CCQ_CONTRACT_STEPS_JSON' }
        @{ Name = 'providers.json'; Marker = 'CCQ_CONTRACT_PROVIDERS_JSON' }
        @{ Name = 'mcp-servers.json'; Marker = 'CCQ_CONTRACT_MCP_SERVERS_JSON' }
        @{ Name = 'claude-config.json'; Marker = 'CCQ_CONTRACT_CLAUDE_CONFIG_JSON' }
    )
    foreach ($contract in $embeddedContracts) {
        $contractPath = Join-Path $InstallerRoot (Join-Path 'contracts' ([string]$contract.Name))
        if (-not (Test-Path $contractPath -PathType Leaf)) {
            throw "契约文件不存在，无法生成自包含 macOS artifact: $contractPath"
        }
        $buffer.Add("cat > ""`${CCQ_BUILT_CONTRACTS_DIR}/$($contract.Name)"" <<'$($contract.Marker)'")
        $buffer.Add((Get-Content -Path $contractPath -Encoding UTF8 -Raw).TrimEnd([char[]]@("`r", "`n")))
        $buffer.Add([string]$contract.Marker)
    }
    $buffer.Add('')

    foreach ($relPath in $FileOrder) {
        $fullPath = Join-Path $InstallerRoot $relPath
        $buffer.Add('')
        $buffer.Add("# ─── 来自: $relPath ────────────────────────────────────────")
        $buffer.Add('')

        $lines = Get-Content -Path $fullPath -Encoding UTF8
        $skipUntilSetOpt = $false
        $skipStreamedTrapBlock = $false
        foreach ($line in $lines) {
            if ($line -match '^\s*#!') { continue }
            if ($line -match '^\s*if \[ -z "\$\{ZSH_VERSION:-\}" \]; then\s*$') {
                $skipUntilSetOpt = $true
                continue
            }
            if ($skipUntilSetOpt) {
                if ($line -match '^\s*setopt\s+') {
                    $skipUntilSetOpt = $false
                } else {
                    continue
                }
            }
            if ($line -match '^\s*if \[ -n "\$\{CCQ_STREAMED_SCRIPT_PATH:-\}" \]; then\s*$') {
                $skipStreamedTrapBlock = $true
                continue
            }
            if ($skipStreamedTrapBlock) {
                if ($line -match '^\s*fi\s*$') {
                    $skipStreamedTrapBlock = $false
                }
                continue
            }
            if ($line -match '^\s*(source|\.)\s+') { continue }
            if ($line -match '^\s*ccq_main "\$@"\s*$') { continue }
            if ($line -match '^\s*ccq_manage_main "\$@"\s*$') { continue }
            $buffer.Add($line)
        }
    }

    $entryFile = if ($FileOrder.Count -gt 0) { $FileOrder[$FileOrder.Count - 1] } else { '' }
    $buffer.Add('')
    if ($entryFile -match 'macos/Install-ClaudeEnv\.zsh$') {
        $buffer.Add('ccq_main "$@"')
    } elseif ($entryFile -match 'macos/Manage-ClaudeEnv\.zsh$') {
        $buffer.Add('ccq_manage_main "$@"')
    } else {
        throw "无法识别 macOS artifact 入口文件: $entryFile"
    }

    $outputDir = Split-Path -Parent $OutputPath
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    $tempPath = Join-Path $outputDir ("_tmp_" + [System.IO.Path]::GetRandomFileName() + ".zsh")
    try {
        $buffer -join "`n" | Set-Content -Path $tempPath -Encoding utf8 -NoNewline
        Move-Item -Path $tempPath -Destination $OutputPath -Force
    } catch {
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
    构建入口：生成 Windows PowerShell 与 macOS zsh 单文件版本。
    .PARAMETER InstallerRoot
    installer/ 目录的绝对路径。
    .PARAMETER OutputDir
    输出目录路径。
    .PARAMETER Platform
    构建平台：All / Windows / MacOS。
    #>
    param(
        [string]$InstallerRoot = (Resolve-Path $PSScriptRoot).Path,
        [string]$OutputDir = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'dist'),
        [ValidateSet('All', 'Windows', 'MacOS')]
        [string]$Platform = 'All'
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
    Write-Host "构建平台:     $Platform"
    Write-Host ""

    # 确保输出目录存在
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
        Write-Host "已创建输出目录: $OutputDir"
    }

    $builtItems = [System.Collections.Generic.List[hashtable]]::new()
    $allOk = $true

    if ($Platform -in @('All', 'Windows')) {
        # 构建 Bootstrap 单文件版本
        Write-Host ""
        Write-Host "─── 构建 Windows Bootstrap 单文件版本 ──────────────────────" -ForegroundColor Yellow
        $bootstrapArtifact = Get-BuildArtifactConfig -Platform Windows -Role Bootstrap
        $bootstrapOrder = Get-BootstrapBuildOrder
        $bootstrapOutput = Join-Path $OutputDir ([string]$bootstrapArtifact['OutputFile'])
        Build-SingleFileScript `
            -InstallerRoot $InstallerRoot `
            -FileOrder $bootstrapOrder `
            -OutputPath $bootstrapOutput `
            -RequiresHeader ([string]$bootstrapArtifact['RequiresHeader']) `
            -OutputEncoding ([string]$bootstrapArtifact['OutputEncoding'])

        # 构建 Install 单文件版本
        Write-Host ""
        Write-Host "─── 构建 Windows Install 单文件版本 ───────────────────────" -ForegroundColor Yellow
        $installArtifact = Get-BuildArtifactConfig -Platform Windows -Role Install
        $installOrder = Get-InstallBuildOrder
        $installOutput = Join-Path $OutputDir ([string]$installArtifact['OutputFile'])
        Build-SingleFileScript `
            -InstallerRoot $InstallerRoot `
            -FileOrder $installOrder `
            -OutputPath $installOutput `
            -RequiresHeader ([string]$installArtifact['RequiresHeader']) `
            -HoistParamFromRelativePath ([string]$installArtifact['HoistParamFrom']) `
            -OutputEncoding ([string]$installArtifact['OutputEncoding'])

        # 构建 Manage 单文件版本
        Write-Host ""
        Write-Host "─── 构建 Windows Manage 单文件版本 ────────────────────────" -ForegroundColor Yellow
        $manageArtifact = Get-BuildArtifactConfig -Platform Windows -Role Manage
        $manageOrder = Get-ManageBuildOrder
        $manageOutput = Join-Path $OutputDir ([string]$manageArtifact['OutputFile'])
        Build-SingleFileScript `
            -InstallerRoot $InstallerRoot `
            -FileOrder $manageOrder `
            -OutputPath $manageOutput `
            -RequiresHeader ([string]$manageArtifact['RequiresHeader']) `
            -HoistParamFromRelativePath ([string]$manageArtifact['HoistParamFrom']) `
            -OutputEncoding ([string]$manageArtifact['OutputEncoding'])

        Write-Host ""
        Write-Host "─── Windows 语法检查 ──────────────────────────────────────" -ForegroundColor Yellow
        $bootstrapOk = Test-BuiltScriptSyntax -ScriptPath $bootstrapOutput
        $installOk = Test-BuiltScriptSyntax -ScriptPath $installOutput
        $manageOk = Test-BuiltScriptSyntax -ScriptPath $manageOutput
        $allOk = $allOk -and $bootstrapOk -and $installOk -and $manageOk

        $builtItems.Add(@{ Name = 'Windows Bootstrap'; Path = $bootstrapOutput; Ok = $bootstrapOk })
        $builtItems.Add(@{ Name = 'Windows Install'; Path = $installOutput; Ok = $installOk })
        $builtItems.Add(@{ Name = 'Windows Manage'; Path = $manageOutput; Ok = $manageOk })
    }

    if ($Platform -in @('All', 'MacOS')) {
        Write-Host ""
        Write-Host "─── 构建 macOS Install 单文件版本 ─────────────────────────" -ForegroundColor Yellow
        $macOSInstallArtifact = Get-BuildArtifactConfig -Platform MacOS -Role Install
        $macOSInstallOrder = Get-MacOSInstallBuildOrder
        $macOSInstallOutput = Join-Path $OutputDir ([string]$macOSInstallArtifact['OutputFile'])
        Build-ZshSingleFileScript `
            -InstallerRoot $InstallerRoot `
            -FileOrder $macOSInstallOrder `
            -OutputPath $macOSInstallOutput

        Write-Host ""
        Write-Host "─── 构建 macOS Manage 单文件版本 ──────────────────────────" -ForegroundColor Yellow
        $macOSManageArtifact = Get-BuildArtifactConfig -Platform MacOS -Role Manage
        $macOSManageOrder = Get-MacOSManageBuildOrder
        $macOSManageOutput = Join-Path $OutputDir ([string]$macOSManageArtifact['OutputFile'])
        Build-ZshSingleFileScript `
            -InstallerRoot $InstallerRoot `
            -FileOrder $macOSManageOrder `
            -OutputPath $macOSManageOutput

        $builtItems.Add(@{ Name = 'macOS Install'; Path = $macOSInstallOutput; Ok = $true })
        $builtItems.Add(@{ Name = 'macOS Manage'; Path = $macOSManageOutput; Ok = $true })
    }

    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  构建摘要" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

    foreach ($item in $builtItems) {
        $size = if (Test-Path $item.Path) { (Get-Item $item.Path).Length } else { 0 }
        Write-Host "  $($item.Name): $($item.Path)"
        Write-Host "              大小: $([math]::Round($size / 1KB, 1)) KB | 语法: $(if ($item.Ok) { '[PASS]' } else { '[FAIL]' })"
    }
    Write-Host ""

    if ($allOk) {
        Write-Host "  构建完成！所有已校验文件通过。" -ForegroundColor Green
    } else {
        Write-Host "  构建完成，但存在语法错误，请检查。" -ForegroundColor Red
        exit 1
    }
}

# 执行入口
Main @args
