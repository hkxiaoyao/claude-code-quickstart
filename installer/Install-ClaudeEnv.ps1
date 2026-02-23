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
. "$script:InstallerRoot\core\Registry.ps1"
. "$script:InstallerRoot\core\Bootstrap.ps1"

# ─── Dot-source 所有步骤模块（从 Registry 动态加载）──────────────────────────

$stepFiles = Get-StepFiles
foreach ($stepFile in $stepFiles) {
    . "$script:InstallerRoot\$stepFile"
}

# ─── 步骤注册表（从共享 Registry 获取，消除重复定义）─────────────────────────

$script:StepRegistry = Get-StepRegistry

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

# ─── 分阶段迭代式安装 ─────────────────────────────────────────────────────────

function Invoke-StagedMode {
    <#
    .SYNOPSIS
    分阶段单选迭代式安装模式
    .DESCRIPTION
    循环展示步骤列表，用户每次选择一个步骤执行，执行后返回列表。
    按 Esc 退出循环。
    .PARAMETER State
    安装状态对象
    .RETURNS
    执行结果统计哈希表 @{ Total; Success; Failed; Skipped }
    #>
    param(
        [Parameter(Mandatory = $true)]
        [InstallState]$State
    )

    $results = @{
        Total   = 0
        Success = 0
        Failed  = 0
        Skipped = 0
    }

    $dependencies = Get-StepDependencies

    while ($true) {
        # ── 构建步骤选项列表（每次循环重新构建以反映最新状态）
        $options = @()
        $stepMap = @()  # 选项索引 → StepRegistry 索引映射

        for ($i = 0; $i -lt $script:StepRegistry.Count; $i++) {
            $step = $script:StepRegistry[$i]
            $stepId = $step.StepId
            $stepNum = $i + 1

            # 确定状态标签
            $tag = "[    ]"
            $tagDesc = ""

            if ($State.StepResults.ContainsKey($stepId)) {
                $status = $State.StepResults[$stepId].Status
                if ($status -eq [StepStatus]::Success) {
                    $tag = "[PASS]"
                    $tagDesc = "- 已安装"
                } elseif ($status -eq [StepStatus]::Skipped) {
                    $tag = "[PASS]"
                    $tagDesc = "- 已安装"
                } elseif ($status -eq [StepStatus]::Failed) {
                    $tag = "[FAIL]"
                    $tagDesc = "- 上次失败，可重试"
                }
            }

            # 检查依赖是否满足（仅对未完成的步骤）
            if ($tag -eq "[    ]") {
                $depCheck = Test-StepDependencies -StepId $stepId -State $State
                if (-not $depCheck.CanExecute) {
                    $tag = "[LOCK]"
                    $missingNames = @()
                    foreach ($depId in @(@($depCheck.MissingDependencies) + @($depCheck.FailedDependencies))) {
                        $depStep = $script:StepRegistry | Where-Object { $_.StepId -eq $depId } | Select-Object -First 1
                        if ($depStep) { $missingNames += $depStep.StepName }
                        else { $missingNames += $depId }
                    }
                    $tagDesc = "- 需要: $($missingNames -join ', ')"
                } else {
                    $tagDesc = "- $($step.Description)"
                }
            }

            $displayText = "$tag $stepNum. $($step.StepName)  $tagDesc"
            $options += $displayText
            $stepMap += $i
        }

        # ── 展示单选菜单
        Write-Host ""
        $selectedIndex = Show-SingleSelectMenu `
            -Title "请选择要执行的步骤（Esc 退出）：" `
            -Options $options

        # Esc 退出
        if ($selectedIndex -eq -1) {
            Write-Host ""
            Write-UiInfo "退出分阶段安装模式"
            break
        }

        # ── 获取选中的步骤
        $registryIndex = $stepMap[$selectedIndex]
        $stepConfig = $script:StepRegistry[$registryIndex]
        $stepId = $stepConfig.StepId
        $stepNum = $registryIndex + 1

        Write-Host ""
        Write-UiInfo "━━━ 步骤 $($stepNum)/$($script:StepRegistry.Count): $($stepConfig.StepName) ━━━"

        # ── 检查依赖状态并展示
        $depCheck = Test-StepDependencies -StepId $stepId -State $State
        $depIds = @()
        if ($dependencies.ContainsKey($stepId)) {
            $depIds = @($dependencies[$stepId])
        }

        if ($depIds.Count -gt 0) {
            foreach ($depId in $depIds) {
                $depStep = $script:StepRegistry | Where-Object { $_.StepId -eq $depId } | Select-Object -First 1
                $depName = if ($depStep) { $depStep.StepName } else { $depId }

                if ($State.StepResults.ContainsKey($depId)) {
                    $depStatus = $State.StepResults[$depId].Status
                    if ($depStatus -eq [StepStatus]::Success -or $depStatus -eq [StepStatus]::Skipped) {
                        Write-UiSuccess "  依赖: $depName [PASS]"
                    } elseif ($depStatus -eq [StepStatus]::Failed) {
                        Write-UiError "  依赖: $depName [FAIL]"
                    } else {
                        Write-UiWarn "  依赖: $depName [未完成]"
                    }
                } else {
                    Write-UiWarn "  依赖: $depName [未完成]"
                }
            }
        } else {
            Write-UiInfo "  依赖: 无"
        }

        # ── 依赖未满足 → 提示并返回
        if (-not $depCheck.CanExecute) {
            Write-Host ""
            Write-UiError "  无法执行：请先完成依赖步骤"
            Write-Host ""
            Write-Host "  按任意键返回..." -ForegroundColor Gray
            $null = [Console]::ReadKey($true)
            continue
        }

        # ── 依赖满足 → 确认执行
        Write-Host ""
        Write-UiInfo "  状态: 依赖已满足，可以执行"

        $confirmIndex = Show-SingleSelectMenu `
            -Title "  确认执行 步骤 $($stepNum): $($stepConfig.StepName)？" `
            -Options @("是，执行", "否，返回")

        if ($confirmIndex -ne 0) {
            continue
        }

        # ── 执行步骤
        $results.Total++

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

        if ($stepConfig.SkipIfInstalled) {
            $stepParams.SkipIfInstalled = $true
        }

        $stepResult = Invoke-StepLifecycle @stepParams

        # ── 统计并展示结果
        switch ($stepResult.Status) {
            ([StepStatus]::Success) {
                $results.Success++
                Write-Host ""
                Write-UiSuccess "步骤 $($stepNum): $($stepConfig.StepName) 执行成功！"
            }
            ([StepStatus]::Skipped) {
                $results.Skipped++
                Write-Host ""
                Write-UiInfo "步骤 $($stepNum): $($stepConfig.StepName) 已安装，跳过"
            }
            ([StepStatus]::Failed) {
                $results.Failed++
                Write-Host ""
                Write-UiError "步骤 $($stepNum): $($stepConfig.StepName) 执行失败"
                if ($stepResult.ErrorDetails) {
                    Show-ErrorDetails `
                        -FriendlyMessage "步骤执行失败" `
                        -TechnicalDetails $stepResult.ErrorDetails
                }
            }
        }

        Write-Host ""
        Write-Host "  按任意键继续选择下一步骤..." -ForegroundColor Gray
        $null = [Console]::ReadKey($true)
    }

    return $results
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

    # 分离必选和可选步骤，确保可选步骤在所有必选步骤之后执行
    $mandatoryIds = @()
    $optionalIds = @()

    foreach ($stepId in $SelectedStepIds) {
        $config = $script:StepRegistry | Where-Object { $_.StepId -eq $stepId } | Select-Object -First 1
        if ($config -and $config.IsOptional) {
            $optionalIds += $stepId
        } else {
            $mandatoryIds += $stepId
        }
    }

    # 分别对必选和可选步骤进行拓扑排序
    $orderedMandatoryIds = if ($mandatoryIds.Count -gt 0) { Get-ExecutionOrder -StepIds $mandatoryIds } else { @() }
    $orderedOptionalIds = if ($optionalIds.Count -gt 0) { Get-ExecutionOrder -StepIds $optionalIds } else { @() }

    # 合并：必选步骤在前，可选步骤在后
    $orderedStepIds = @($orderedMandatoryIds + $orderedOptionalIds)

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
        if ($State.StepResults.ContainsKey("CcSwitch") -and
            $State.StepResults["CcSwitch"].Status -eq [StepStatus]::Success) {
            Write-UiInfo "  cc-switch       - 切换 Claude Code 版本"
        }
        if ($State.StepResults.ContainsKey("CodexCli") -and
            $State.StepResults["CodexCli"].Status -eq [StepStatus]::Success) {
            Write-UiInfo "  codex --help    - Codex CLI 帮助"
        }
        if ($State.StepResults.ContainsKey("GeminiCli") -and
            $State.StepResults["GeminiCli"].Status -eq [StepStatus]::Success) {
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
    $null = Save-InstallState -State $State
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

        # ── 按模式执行
        if ($installMode -eq "OneClick") {
            # 一键安装：执行全部步骤
            $allStepIds = $script:StepRegistry | ForEach-Object { $_.StepId }
            Write-UiInfo "一键安装模式：将执行全部 $($allStepIds.Count) 个步骤"
            Write-Host ""

            $results = Invoke-AllSteps -SelectedStepIds $allStepIds -State $state

            # 显示最终摘要
            Show-FinalSummary -State $state -Results $results
        } else {
            # 分阶段安装：单选迭代式交互
            $results = Invoke-StagedMode -State $state

            # 仅在有执行过步骤时显示摘要
            if ($results.Total -gt 0) {
                Show-FinalSummary -State $state -Results $results
            }
        }

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
