#Requires -Version 7.0
# Install-ClaudeEnv.ps1 - Claude Code 环境安装器主脚本
# 作者: 哈雷酱 (本小姐的架构设计杰作！)
# 功能: PS7+ 主安装脚本，提供一键和分阶段安装模式，支持断点续传

param(
    [switch]$Resume,
    [switch]$OneClick,
    [switch]$Staged,
    [switch]$ListSteps
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 安装器根目录（使用 $PSScriptRoot 避免被 dot-source 覆盖）
$script:InstallerRoot = $PSScriptRoot

# ─── Dot-source 核心模块 ────────────────────────────────────────────────────

. "$script:InstallerRoot\core\Ui.ps1"
. "$script:InstallerRoot\core\Process.ps1"
. "$script:InstallerRoot\core\Profile.ps1"
. "$script:InstallerRoot\core\Admin.ps1"
. "$script:InstallerRoot\core\Net.ps1"
. "$script:InstallerRoot\core\Bootstrap.ps1"

# ─── Dot-source 所有步骤模块（顺序无强制要求，依赖由 Bootstrap 管理）──────

. "$script:InstallerRoot\steps\Step01.Proxy.ps1"
. "$script:InstallerRoot\steps\Step02.NodeFnm.ps1"
. "$script:InstallerRoot\steps\Step03.Git.ps1"
. "$script:InstallerRoot\steps\Step04.ClaudeCode.ps1"
. "$script:InstallerRoot\steps\Step05.Ccline.ps1"
. "$script:InstallerRoot\steps\Step06.CcSwitch.ps1"
. "$script:InstallerRoot\steps\Step07.ApiKey.ps1"
. "$script:InstallerRoot\steps\Step08.ClaudeConfig.ps1"
. "$script:InstallerRoot\steps\Step09.ClaudeMd.ps1"
. "$script:InstallerRoot\steps\Step10.Mcp.ps1"
. "$script:InstallerRoot\steps\Step11.CcgWorkflow.ps1"
. "$script:InstallerRoot\steps\Step12.CodexCli.ps1"
. "$script:InstallerRoot\steps\Step13.GeminiCli.ps1"

# ─── 步骤注册表 ─────────────────────────────────────────────────────────────
# 每条记录定义一个安装步骤的完整元数据

$script:StepRegistry = @(
    @{
        StepId          = "Step01.Proxy"
        StepName        = "代理配置检测"
        Description     = "检测网络代理配置，确保后续安装可以正常访问网络"
        TestFunction    = "Test-Step01Installed"
        InstallFunction = "Install-Step01"
        VerifyFunction  = ""
        RollbackFunction = ""
        SkipIfInstalled = $false
        IsOptional      = $false
    },
    @{
        StepId          = "Step02.NodeFnm"
        StepName        = "Node.js (fnm)"
        Description     = "通过 fnm 安装 Node.js，为 npm 包安装提供运行时支持"
        TestFunction    = "Test-Step02Installed"
        InstallFunction = "Install-Step02"
        VerifyFunction  = "Verify-Step02"
        RollbackFunction = "Rollback-Step02"
        SkipIfInstalled = $true
        IsOptional      = $false
    },
    @{
        StepId          = "Step03.Git"
        StepName        = "Git"
        Description     = "安装 Git 版本控制系统"
        TestFunction    = "Test-Step03Installed"
        InstallFunction = "Install-Step03"
        VerifyFunction  = "Verify-Step03"
        RollbackFunction = "Rollback-Step03"
        SkipIfInstalled = $true
        IsOptional      = $false
    },
    @{
        StepId          = "Step04.ClaudeCode"
        StepName        = "Claude Code"
        Description     = "通过 npm 全局安装 Claude Code CLI"
        TestFunction    = "Test-Step04Installed"
        InstallFunction = "Install-Step04"
        VerifyFunction  = "Verify-Step04"
        RollbackFunction = "Rollback-Step04"
        SkipIfInstalled = $true
        IsOptional      = $false
    },
    @{
        StepId          = "Step05.Ccline"
        StepName        = "ccline"
        Description     = "安装 ccline 命令行工具"
        TestFunction    = "Test-Step05Installed"
        InstallFunction = "Install-Step05"
        VerifyFunction  = "Verify-Step05"
        RollbackFunction = "Rollback-Step05"
        SkipIfInstalled = $true
        IsOptional      = $false
    },
    @{
        StepId          = "Step06.CcSwitch"
        StepName        = "cc-switch"
        Description     = "安装 cc-switch，用于切换 Claude Code 版本"
        TestFunction    = "Test-Step06Installed"
        InstallFunction = "Install-Step06"
        VerifyFunction  = "Verify-Step06"
        RollbackFunction = "Rollback-Step06"
        SkipIfInstalled = $true
        IsOptional      = $false
    },
    @{
        StepId          = "Step07.ApiKey"
        StepName        = "API Key 配置"
        Description     = "配置 AI 提供商 API Key 到 ~/.claude/settings.json (env.ANTHROPIC_AUTH_TOKEN)"
        TestFunction    = "Test-Step07Installed"
        InstallFunction = "Install-Step07"
        VerifyFunction  = "Verify-Step07"
        RollbackFunction = "Rollback-Step07"
        SkipIfInstalled = $false
        IsOptional      = $false
    },
    @{
        StepId          = "Step08.ClaudeConfig"
        StepName        = "Claude 基础配置"
        Description     = "写入 Claude Code 基础配置（语言、模型、权限、状态栏等）"
        TestFunction    = "Test-Step08Installed"
        InstallFunction = "Install-Step08"
        VerifyFunction  = "Verify-Step08"
        RollbackFunction = "Rollback-Step08"
        SkipIfInstalled = $true
        IsOptional      = $false
    },
    @{
        StepId          = "Step09.ClaudeMd"
        StepName        = "CLAUDE.md 配置"
        Description     = "创建全局 CLAUDE.md 配置文件，定义 Claude Code 工作规范"
        TestFunction    = "Test-Step09Installed"
        InstallFunction = "Install-Step09"
        VerifyFunction  = "Verify-Step09"
        RollbackFunction = "Rollback-Step09"
        SkipIfInstalled = $true
        IsOptional      = $false
    },
    @{
        StepId          = "Step10.Mcp"
        StepName        = "MCP Server 配置"
        Description     = "配置 MCP (Model Context Protocol) 插件服务器"
        TestFunction    = "Test-Step10Installed"
        InstallFunction = "Install-Step10"
        VerifyFunction  = "Verify-Step10"
        RollbackFunction = "Rollback-Step10"
        SkipIfInstalled = $true
        IsOptional      = $false
    },
    @{
        StepId          = "Step11.CcgWorkflow"
        StepName        = "CCG 工作流"
        Description     = "安装 Claude Code Generator 工作流脚本和 Slash Commands"
        TestFunction    = "Test-Step11Installed"
        InstallFunction = "Install-Step11"
        VerifyFunction  = "Verify-Step11"
        RollbackFunction = "Rollback-Step11"
        SkipIfInstalled = $true
        IsOptional      = $false
    },
    @{
        StepId          = "Step12.CodexCli"
        StepName        = "Codex CLI [可选]"
        Description     = "安装 OpenAI Codex CLI（多模型协作可选工具）"
        TestFunction    = "Test-Step12Installed"
        InstallFunction = "Install-Step12"
        VerifyFunction  = "Verify-Step12"
        RollbackFunction = "Rollback-Step12"
        SkipIfInstalled = $true
        IsOptional      = $true
    },
    @{
        StepId          = "Step13.GeminiCli"
        StepName        = "Gemini CLI [可选]"
        Description     = "安装 Google Gemini CLI（多模型协作可选工具）"
        TestFunction    = "Test-Step13Installed"
        InstallFunction = "Install-Step13"
        VerifyFunction  = "Verify-Step13"
        RollbackFunction = "Rollback-Step13"
        SkipIfInstalled = $true
        IsOptional      = $true
    }
)

# ─── 安装模式选择 ────────────────────────────────────────────────────────────

function Select-InstallMode {
    <#
    .SYNOPSIS
    让用户交互式选择安装模式
    .RETURNS
    安装模式字符串："OneClick" 或 "Staged"
    #>
    param()

    $options = @(
        "一键安装（推荐）- 自动完成所有核心步骤",
        "分阶段安装 - 手动选择要安装的组件"
    )

    $choice = Show-SingleSelectMenu -Title "请选择安装模式：" -Options $options -DefaultIndex 0

    switch ($choice) {
        0       { return "OneClick" }
        1       { return "Staged" }
        default {
            Write-UiWarn "安装已取消"
            exit 0
        }
    }
}

# ─── 分阶段步骤选择 ──────────────────────────────────────────────────────────

function Select-StagedSteps {
    <#
    .SYNOPSIS
    让用户在分阶段模式下选择要安装的步骤
    .RETURNS
    选中的步骤 ID 数组
    #>
    param()

    $options = @()
    $defaultSelected = @()

    for ($i = 0; $i -lt $script:StepRegistry.Count; $i++) {
        $step = $script:StepRegistry[$i]
        $options += "$($step.StepName) - $($step.Description)"
        if (-not $step.IsOptional) {
            $defaultSelected += $i
        }
    }

    $selectedIndices = Show-MultiSelectMenu `
        -Title "选择要安装的组件（空格 选择/取消，Enter 确认，Esc 退出）：" `
        -Options $options `
        -DefaultSelected $defaultSelected

    if ($selectedIndices.Count -eq 0) {
        Write-UiWarn "未选择任何组件，安装已取消"
        exit 0
    }

    $selectedStepIds = @()
    foreach ($index in $selectedIndices) {
        $selectedStepIds += $script:StepRegistry[$index].StepId
    }

    return $selectedStepIds
}

# ─── 步骤列表输出 ────────────────────────────────────────────────────────────

function Show-StepList {
    <#
    .SYNOPSIS
    列出所有注册步骤（供 -ListSteps 使用）
    #>
    param()

    Write-UiInfo "已注册的安装步骤："
    Write-Host ""

    $index = 0
    foreach ($step in $script:StepRegistry) {
        $index++
        $tag = if ($step.IsOptional) { "[可选]" } else { "[必选]" }
        Write-UiInfo "  $index. $tag $($step.StepName)"
        Write-Host "       $($step.Description)" -ForegroundColor Gray
        Write-Host "       依赖: $(if ((Get-StepDependencies)[$step.StepId].Count -eq 0) { '无' } else { (Get-StepDependencies)[$step.StepId] -join ', ' })" -ForegroundColor Gray
        Write-Host ""
    }
}

# ─── 核心执行引擎 ────────────────────────────────────────────────────────────

function Invoke-AllSteps {
    <#
    .SYNOPSIS
    按依赖顺序执行所有选定步骤
    .PARAMETER SelectedStepIds
    要执行的步骤 ID 数组
    .PARAMETER State
    安装状态对象
    .RETURNS
    执行结果统计哈希表
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$SelectedStepIds,

        [Parameter(Mandatory = $true)]
        [InstallState]$State
    )

    # 按依赖关系拓扑排序
    $orderedStepIds = Get-ExecutionOrder -StepIds $SelectedStepIds

    $results = @{
        Total   = $orderedStepIds.Count
        Success = 0
        Failed  = 0
        Skipped = 0
    }

    $stepIndex = 0
    foreach ($stepId in $orderedStepIds) {
        $stepIndex++

        # 查找步骤配置
        $stepConfig = $script:StepRegistry | Where-Object { $_.StepId -eq $stepId } | Select-Object -First 1

        if (-not $stepConfig) {
            Write-UiWarn "未找到步骤配置: $stepId，跳过"
            $results.Skipped++
            continue
        }

        # 显示分隔线和进度
        Write-Host ""
        Write-UiInfo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        Write-UiInfo "步骤 $stepIndex / $($results.Total)：$($stepConfig.StepName)"
        Write-Host "     $($stepConfig.Description)" -ForegroundColor Gray
        Write-UiInfo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        # 检查前置依赖
        $depCheck = Test-StepDependencies -StepId $stepId -State $State

        if (-not $depCheck.CanExecute) {
            if ($depCheck.FailedDependencies.Count -gt 0) {
                Write-UiError "前置依赖失败，跳过此步骤: $($depCheck.FailedDependencies -join ', ')"
            } else {
                Write-UiWarn "前置依赖未完成，跳过此步骤: $($depCheck.MissingDependencies -join ', ')"
            }
            $results.Skipped++
            continue
        }

        # 构建步骤执行参数
        $stepParams = @{
            StepId          = $stepConfig.StepId
            StepName        = $stepConfig.StepName
            TestFunction    = $stepConfig.TestFunction
            InstallFunction = $stepConfig.InstallFunction
            State           = $State
        }

        if ($stepConfig.VerifyFunction) {
            $stepParams.VerifyFunction = $stepConfig.VerifyFunction
        }

        if ($stepConfig.RollbackFunction) {
            $stepParams.RollbackFunction = $stepConfig.RollbackFunction
        }

        if ($stepConfig.SkipIfInstalled) {
            $stepParams.SkipIfInstalled = $true
        }

        # 执行步骤生命周期
        $stepResult = Invoke-StepLifecycle @stepParams

        # 汇总计数
        switch ($stepResult.Status) {
            ([StepStatus]::Success) { $results.Success++ }
            ([StepStatus]::Skipped) { $results.Skipped++ }
            ([StepStatus]::Failed)  {
                $results.Failed++
                Write-UiError "步骤 [$($stepConfig.StepName)] 执行失败，错误已记录"
            }
        }
    }

    return $results
}

# ─── 最终摘要展示 ────────────────────────────────────────────────────────────

function Show-FinalSummary {
    <#
    .SYNOPSIS
    在安装完成后展示详细摘要表格和建议
    .PARAMETER State
    安装状态对象
    .PARAMETER Results
    执行结果统计
    #>
    param(
        [Parameter(Mandatory = $true)]
        [InstallState]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Results
    )

    Write-Host ""
    Show-AsciiBanner -Title "Claude Code 环境安装完成"

    # 构建摘要表格
    $summaryItems = @()

    $orderedResults = $State.StepResults.Values | Sort-Object StepId
    foreach ($stepResult in $orderedResults) {
        $statusText = switch ($stepResult.Status) {
            ([StepStatus]::Success) { "成功" }
            ([StepStatus]::Skipped) { "跳过" }
            ([StepStatus]::Failed)  { "失败" }
            ([StepStatus]::Pending) { "未执行" }
            default                 { "未知" }
        }

        $version = if ($stepResult.Data -and $stepResult.Data.ContainsKey("Version") -and $stepResult.Data["Version"]) {
            [string]$stepResult.Data["Version"]
        } else {
            "-"
        }

        $summaryItems += [PSCustomObject]@{
            Name    = $stepResult.StepName
            Status  = $statusText
            Version = $version
        }
    }

    if ($summaryItems.Count -gt 0) {
        Show-InstallSummary -Items $summaryItems
    }

    # 统计摘要
    Write-Host ""
    Write-UiInfo "安装统计："
    Write-UiSuccess "  成功: $($Results.Success)"

    if ($Results.Skipped -gt 0) {
        Write-UiWarn "  跳过: $($Results.Skipped)"
    }

    if ($Results.Failed -gt 0) {
        Write-UiError "  失败: $($Results.Failed)"
    }

    Write-Host ""

    if ($Results.Failed -eq 0) {
        Write-UiSuccess "Claude Code 环境安装完成！"
        Write-Host ""
        Write-UiInfo "快速开始："
        Write-UiInfo "  claude          - 启动 Claude Code"
        Write-UiInfo "  claude --help   - 查看帮助信息"
        if ($State.StepResults.ContainsKey("Step06.CcSwitch") -and
            $State.StepResults["Step06.CcSwitch"].Status -eq [StepStatus]::Success) {
            Write-UiInfo "  cc-switch       - 切换 Claude Code 版本"
        }
        if ($State.StepResults.ContainsKey("Step12.CodexCli") -and
            $State.StepResults["Step12.CodexCli"].Status -eq [StepStatus]::Success) {
            Write-UiInfo "  codex --help    - Codex CLI 帮助"
        }
        if ($State.StepResults.ContainsKey("Step13.GeminiCli") -and
            $State.StepResults["Step13.GeminiCli"].Status -eq [StepStatus]::Success) {
            Write-UiInfo "  gemini --help   - Gemini CLI 帮助"
        }
    } else {
        Write-UiWarn "安装完成，但有 $($Results.Failed) 个步骤失败"
        Write-Host ""
        Write-UiInfo "失败步骤列表："
        foreach ($stepResult in $orderedResults) {
            if ($stepResult.Status -eq [StepStatus]::Failed) {
                Write-UiError "  $($stepResult.StepName): $($stepResult.ErrorDetails)"
            }
        }
        Write-Host ""
        Write-UiInfo "使用 -Resume 参数重试失败步骤："
        Write-UiInfo "  pwsh -File `"$PSCommandPath`" -Resume"
    }

    Write-Host ""

    # 标记安装完成状态
    $State.IsCompleted = ($Results.Failed -eq 0)
    Save-InstallState -State $State
}

# ─── 主函数 ──────────────────────────────────────────────────────────────────

function Main {
    <#
    .SYNOPSIS
    安装器主入口
    #>
    param()

    try {
        # ── 仅列出步骤时快速退出
        if ($ListSteps) {
            Show-StepList
            return
        }

        # ── 欢迎横幅
        Show-AsciiBanner -Title "Claude Code 环境安装器 v1.0"

        Write-UiInfo "欢迎使用 Claude Code 环境安装器！"
        Write-UiInfo "此脚本将自动安装和配置完整的 Claude Code 开发环境"
        Write-Host ""

        # ── 加载安装状态（支持断点续传）
        $state = Load-InstallState

        if ($Resume) {
            $state = Resume-Installation
            Write-Host ""
        }

        # ── 确定安装模式
        $installMode = ""

        if ($OneClick) {
            $installMode = "OneClick"
            Write-UiInfo "使用命令行参数：一键安装模式"
        } elseif ($Staged) {
            $installMode = "Staged"
            Write-UiInfo "使用命令行参数：分阶段安装模式"
        } elseif ($Resume -and $state.Mode -ne "") {
            # 恢复模式复用上次的安装模式
            $installMode = $state.Mode
            Write-UiInfo "恢复安装，沿用上次模式: $installMode"
        } else {
            $installMode = Select-InstallMode
        }

        $state.Mode = $installMode

        # ── 确定要执行的步骤
        $allStepIds = $script:StepRegistry | ForEach-Object { $_.StepId }

        $selectedStepIds = if ($installMode -eq "OneClick") {
            Write-UiInfo "一键安装模式：将执行全部 $($allStepIds.Count) 个步骤"
            $allStepIds
        } else {
            Write-Host ""
            Select-StagedSteps
        }

        Write-Host ""
        Write-UiInfo "准备执行 $($selectedStepIds.Count) 个步骤，按依赖顺序排列..."
        Write-Host ""

        # ── 执行所有选定步骤
        $results = Invoke-AllSteps -SelectedStepIds $selectedStepIds -State $state

        # ── 显示最终摘要
        Show-FinalSummary -State $state -Results $results

    } catch {
        Write-UiError "安装过程中发生严重错误: $($_.Exception.Message)"
        Write-Host ""
        Show-ErrorDetails `
            -FriendlyMessage "安装器遇到未预期的错误，请查看技术详情" `
            -TechnicalDetails "$($_.Exception.Message)`n$($_.ScriptStackTrace)"
        exit 1
    }
}

# ─── 脚本入口点 ──────────────────────────────────────────────────────────────

Main
