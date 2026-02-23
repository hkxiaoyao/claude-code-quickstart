#Requires -Version 7.0
# Manage-ClaudeEnv.ps1 - CCQ（分组安装入口）
# 功能: 两级分组安装（基础环境 / 进阶扩展），支持一键、多选、断点续传

param(
    [switch]$Resume,
    [switch]$ListSteps,
    [ValidateSet("Basic", "Advanced", "")]
    [string]$Group = "",
    [ValidateSet("OneClick", "Select", "")]
    [string]$Mode = "",
    [switch]$Staged
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

# ─── 步骤分组定义（从共享 Registry 获取）─────────────────────────────────────

$script:StepGroups = Get-StepGroups

# ─── 核心函数 ───────────────────────────────────────────────────────────────

function Get-GroupStatus {
    <#
    .SYNOPSIS
    获取分组的安装状态统计
    .PARAMETER GroupName
    分组名称（Basic / Advanced）
    .RETURNS
    @{ Total; Installed; StepStatuses }
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupName
    )

    $group = $script:StepGroups[$GroupName]
    $total = $group.StepIds.Count
    $installed = 0
    $stepStatuses = @{}

    foreach ($stepId in $group.StepIds) {
        $stepConfig = $script:StepRegistry | Where-Object { $_.StepId -eq $stepId } | Select-Object -First 1
        if (-not $stepConfig) { continue }

        # 静默检测：抑制 TestFunction 的所有输出
        $testResult = $null
        try {
            # 保存原始 Preference 设置
            $originalVerbose = $VerbosePreference
            $originalDebug = $DebugPreference
            $originalInfo = $InformationPreference
            $originalWarning = $WarningPreference

            # 设置为静默模式
            $VerbosePreference = 'SilentlyContinue'
            $DebugPreference = 'SilentlyContinue'
            $InformationPreference = 'SilentlyContinue'
            $WarningPreference = 'SilentlyContinue'

            # 调用 TestFunction 并抑制所有输出流（不使用 Out-Null 以保留返回值）
            $testResult = & $stepConfig.TestFunction 2>$null 3>$null 4>$null 5>$null 6>$null *>&1 |
                Where-Object { $_ -isnot [string] -and $_ -isnot [System.Management.Automation.InformationRecord] } |
                Select-Object -First 1

            # 恢复原始设置
            $VerbosePreference = $originalVerbose
            $DebugPreference = $originalDebug
            $InformationPreference = $originalInfo
            $WarningPreference = $originalWarning
        } catch {
            # 忽略检测错误，视为未安装
            $testResult = $null
        }

        $isInstalled = if ($testResult -is [bool]) { $testResult }
                       elseif ($testResult) { [bool]$testResult.IsInstalled }
                       else { $false }

        $stepStatuses[$stepId] = $isInstalled
        if ($isInstalled) { $installed++ }
    }

    return @{
        Total        = $total
        Installed    = $installed
        StepStatuses = $stepStatuses
    }
}

function Get-DependencyClosure {
    <#
    .SYNOPSIS
    计算选定步骤的完整依赖闭包（保留完整依赖链，已安装步骤由生命周期自动跳过）
    .PARAMETER SelectedStepIds
    用户选择的步骤 ID 数组
    .RETURNS
    @{ OriginalSelection; AutoAdded; FinalPlan }
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$SelectedStepIds
    )

    $dependencies = Get-StepDependencies
    $allRequired = [System.Collections.Generic.HashSet[string]]::new()

    # 递归收集传递依赖
    function Collect-Deps {
        param([string]$StepId)
        if ($allRequired.Contains($StepId)) { return }
        [void]$allRequired.Add($StepId)
        if ($dependencies.ContainsKey($StepId)) {
            foreach ($dep in $dependencies[$StepId]) {
                Collect-Deps -StepId $dep
            }
        }
    }

    foreach ($id in $SelectedStepIds) {
        Collect-Deps -StepId $id
    }

    # 不在此处过滤已安装步骤，避免与 Test-StepDependencies 的状态判定冲突
    # 已安装步骤由 Invoke-StepLifecycle 的 SkipIfInstalled 机制自动处理
    $finalPlan = Get-ExecutionOrder -StepIds @($allRequired)

    # 识别自动补齐的依赖
    $autoAdded = @($finalPlan | Where-Object { $_ -notin $SelectedStepIds })

    return @{
        OriginalSelection = $SelectedStepIds
        AutoAdded         = $autoAdded
        FinalPlan         = $finalPlan
    }
}

function Show-ExecutionPlan {
    <#
    .SYNOPSIS
    当存在自动补齐的依赖时，显示执行计划并请求确认
    .RETURNS
    $true = 用户确认执行，$false = 取消
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$OriginalSelection,

        [Parameter(Mandatory = $true)]
        [string[]]$AutoAdded,

        [Parameter(Mandatory = $true)]
        [string[]]$FinalPlan
    )

    if ($AutoAdded.Count -eq 0) {
        return $true
    }

    Write-Host ""
    Write-UiWarn "以下依赖将自动纳入执行计划（已安装项会自动跳过）："
    foreach ($stepId in $AutoAdded) {
        $stepConfig = $script:StepRegistry | Where-Object { $_.StepId -eq $stepId } | Select-Object -First 1
        $name = if ($stepConfig) { $stepConfig.StepName } else { $stepId }
        Write-UiInfo "  + $name（自动补齐）"
    }

    Write-Host ""
    Write-UiInfo "完整执行计划："

    $orderedPlan = Get-ExecutionOrder -StepIds $FinalPlan
    $index = 0
    foreach ($stepId in $orderedPlan) {
        $index++
        $stepConfig = $script:StepRegistry | Where-Object { $_.StepId -eq $stepId } | Select-Object -First 1
        $name = if ($stepConfig) { $stepConfig.StepName } else { $stepId }
        $tag = if ($stepId -in $AutoAdded) { "(依赖补齐)" } else { "" }
        Write-UiInfo "  $index. $name $tag"
    }

    Write-Host ""
    $confirmIndex = Show-SingleSelectMenu `
        -Title "确认执行以上计划？" `
        -Options @("是，开始执行", "否，取消")

    return ($confirmIndex -eq 0)
}

function Invoke-GroupedInstall {
    <#
    .SYNOPSIS
    执行分组安装（依赖闭包 + 确认 + 拓扑排序 + 执行）
    .PARAMETER StepIds
    目标步骤 ID 数组
    .PARAMETER State
    安装状态对象
    .RETURNS
    执行结果统计
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$StepIds,

        [Parameter(Mandatory = $true)]
        [InstallState]$State
    )

    # 计算依赖闭包
    $closure = Get-DependencyClosure -SelectedStepIds $StepIds

    if ($closure.FinalPlan.Count -eq 0) {
        Write-Host ""
        Write-UiSuccess "所有选定步骤已安装，无需操作"
        return @{ Total = 0; Success = 0; Failed = 0; Skipped = 0 }
    }

    # 需要自动补齐时请求确认
    if ($closure.AutoAdded.Count -gt 0) {
        $confirmed = Show-ExecutionPlan `
            -OriginalSelection $closure.OriginalSelection `
            -AutoAdded $closure.AutoAdded `
            -FinalPlan $closure.FinalPlan

        if (-not $confirmed) {
            Write-UiWarn "安装已取消"
            return @{ Total = 0; Success = 0; Failed = 0; Skipped = 0 }
        }
    }

    # 拓扑排序
    $orderedStepIds = Get-ExecutionOrder -StepIds $closure.FinalPlan

    $results = @{
        Total           = $orderedStepIds.Count
        Success         = 0
        Failed          = 0
        Skipped         = 0
        ExecutedStepIds = $orderedStepIds
    }

    $stepIndex = 0
    foreach ($stepId in $orderedStepIds) {
        $stepIndex++

        $stepConfig = $script:StepRegistry | Where-Object { $_.StepId -eq $stepId } | Select-Object -First 1
        if (-not $stepConfig) {
            Write-UiWarn "未找到步骤配置: $stepId，跳过"
            $results.Skipped++
            continue
        }

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

        $stepResult = Invoke-StepLifecycle @stepParams

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

function Show-AdvancedSelectMenu {
    <#
    .SYNOPSIS
    显示进阶步骤的多选菜单（带状态标签）
    .RETURNS
    用户选择的 StepId 数组
    #>
    param()

    Write-Host ""
    Write-UiInfo "正在检测进阶扩展组件状态..."
    Write-Host ""

    $advancedGroup = $script:StepGroups["Advanced"]
    $options = @()
    $stepIdMap = @()
    $defaultSelected = @()

    for ($i = 0; $i -lt $advancedGroup.StepIds.Count; $i++) {
        $stepId = $advancedGroup.StepIds[$i]
        $stepConfig = $script:StepRegistry | Where-Object { $_.StepId -eq $stepId } | Select-Object -First 1
        if (-not $stepConfig) { continue }

        $stepNum = $i + 1

        # 静默获取安装状态
        $testResult = $null
        try {
            # 保存原始 Preference 设置
            $originalVerbose = $VerbosePreference
            $originalDebug = $DebugPreference
            $originalInfo = $InformationPreference
            $originalWarning = $WarningPreference

            # 设置为静默模式
            $VerbosePreference = 'SilentlyContinue'
            $DebugPreference = 'SilentlyContinue'
            $InformationPreference = 'SilentlyContinue'
            $WarningPreference = 'SilentlyContinue'

            # 调用 TestFunction 并抑制所有输出流（不使用 Out-Null 以保留返回值）
            $testResult = & $stepConfig.TestFunction 2>$null 3>$null 4>$null 5>$null 6>$null *>&1 |
                Where-Object { $_ -isnot [string] -and $_ -isnot [System.Management.Automation.InformationRecord] } |
                Select-Object -First 1

            # 恢复原始设置
            $VerbosePreference = $originalVerbose
            $DebugPreference = $originalDebug
            $InformationPreference = $originalInfo
            $WarningPreference = $originalWarning
        } catch {
            # 忽略检测错误，视为未安装
            $testResult = $null
        }

        $isInstalled = if ($testResult -is [bool]) { $testResult }
                       elseif ($testResult) { [bool]$testResult.IsInstalled }
                       else { $false }

        $tag = if ($isInstalled) { "[PASS]" } else { "[    ]" }
        $displayText = "$tag $($stepNum). $($stepConfig.StepName) - $($stepConfig.Description)"

        $options += $displayText
        $stepIdMap += $stepId

        # 默认勾选策略：未安装 + 非可选 → 勾选
        if (-not $isInstalled -and -not $stepConfig.IsOptional) {
            $defaultSelected += $i
        }
    }

    $selectedIndices = @(Show-MultiSelectMenu `
        -Title "进阶扩展 - 选择要安装的组件：" `
        -Options $options `
        -DefaultSelected $defaultSelected)

    if ($selectedIndices.Count -eq 0) {
        return @()
    }

    $selectedStepIds = @()
    foreach ($idx in $selectedIndices) {
        $selectedStepIds += $stepIdMap[$idx]
    }

    return $selectedStepIds
}

# ─── 菜单函数 ───────────────────────────────────────────────────────────────

function Select-TopLevelAction {
    <#
    .SYNOPSIS
    显示顶层分组选择菜单
    .RETURNS
    选中的索引（0=基础, 1=进阶, -1=Esc）
    #>
    param()

    $options = @(
        "基础环境 - Node.js, Git, Claude Code, API Key"
        "进阶扩展 - 增强工具, 配置, 工作流, 多模型"
    )

    return Show-SingleSelectMenu -Title "请选择操作：" -Options $options -DefaultIndex 0
}

function Select-AdvancedAction {
    <#
    .SYNOPSIS
    显示进阶扩展的子菜单
    .RETURNS
    选中的索引（0=一键, 1=可选, -1=Esc）
    #>
    param()

    $options = @(
        "一键安装 - 安装全部 8 个进阶组件"
        "可选安装 - 选择要安装的组件"
    )

    return Show-SingleSelectMenu -Title "进阶扩展 - 请选择安装模式：" -Options $options -DefaultIndex 0
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

    $stepIndex = 0
    foreach ($groupName in @("Basic", "Advanced")) {
        $group = $script:StepGroups[$groupName]
        Write-UiInfo "─── $($group.Label)（$($group.Description)）───"
        Write-Host ""

        foreach ($stepId in $group.StepIds) {
            $step = $script:StepRegistry | Where-Object { $_.StepId -eq $stepId } | Select-Object -First 1
            if (-not $step) { continue }

            $stepIndex++
            $tag = if ($step.IsOptional) { "[可选]" } else { "[必选]" }
            Write-UiInfo "  $stepIndex. $tag $($step.StepName)"
            Write-Host "       $($step.Description)" -ForegroundColor Gray
            $deps = (Get-StepDependencies)[$stepId]
            Write-Host "       依赖: $(if ($deps.Count -eq 0) { '无' } else { $deps -join ', ' })" -ForegroundColor Gray
            Write-Host ""
        }
    }
}

# ─── 最终摘要展示 ────────────────────────────────────────────────────────────

function Show-FinalSummary {
    param(
        [Parameter(Mandatory = $true)]
        [InstallState]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Results
    )

    Write-Host ""
    Show-CcqLogo -Subtitle "安装完成"

    # 仅展示本次执行计划中涉及的步骤
    $summaryItems = @()

    foreach ($stepId in $Results.ExecutedStepIds) {
        $stepConfig = $script:StepRegistry | Where-Object { $_.StepId -eq $stepId } | Select-Object -First 1
        $stepName = if ($stepConfig) { $stepConfig.StepName } else { $stepId }

        if ($State.StepResults.ContainsKey($stepId)) {
            $stepResult = $State.StepResults[$stepId]
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
        } else {
            # 在执行计划中但未进入生命周期（如依赖检查失败）
            $statusText = "跳过"
            $version = "-"
        }

        $summaryItems += [PSCustomObject]@{
            Name    = $stepName
            Status  = $statusText
            Version = $version
        }
    }

    if ($summaryItems.Count -gt 0) {
        Show-InstallSummary -Items $summaryItems
    }

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
        Write-UiSuccess "安装完成！"
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
        $executedResults = $State.StepResults.Values | Sort-Object StepId
        foreach ($stepResult in $executedResults) {
            if ($stepResult.Status -eq [StepStatus]::Failed) {
                Write-UiError "  $($stepResult.StepName): $($stepResult.ErrorDetails)"
            }
        }
        Write-Host ""
        Write-UiInfo "使用 -Resume 参数重试失败步骤："
        Write-UiInfo "  pwsh -File `"$PSCommandPath`" -Resume"
    }

    Write-Host ""

    $State.IsCompleted = ($Results.Failed -eq 0)
    $null = Save-InstallState -State $State
}

# ─── 主函数 ──────────────────────────────────────────────────────────────────

function Main {
    param()

    try {
        # 仅列出步骤时快速退出
        if ($ListSteps) {
            Show-StepList
            return
        }

        # 欢迎横幅
        Show-CcqLogo -Subtitle "Claude Code Quickstart"

        Write-UiInfo "支持一键搭建 Claude Code 的开发环境及进阶功能"
        Write-Host ""

        # 加载安装状态
        $state = Load-InstallState

        if ($Resume) {
            $state = Resume-Installation
            Write-Host ""
        }

        # ── 参数组合校验
        if ($Mode -ne "" -and $Group -eq "") {
            Write-UiError "参数错误：-Mode 必须与 -Group 一起使用"
            return
        }
        if ($Group -eq "Basic" -and $Mode -eq "Select") {
            Write-UiError "参数错误：基础环境仅支持一键安装（-Group Basic），不支持 -Mode Select"
            return
        }

        # ── CLI 参数模式
        if ($Group -ne "") {
            $state.Mode = "Manage-$Group"

            if ($Group -eq "Basic") {
                # 基础环境：直接一键安装
                Write-UiInfo "基础环境一键安装模式"
                Write-Host ""
                $basicStepIds = $script:StepGroups["Basic"].StepIds
                $results = Invoke-GroupedInstall -StepIds $basicStepIds -State $state
                if ($results.Total -gt 0) {
                    Show-FinalSummary -State $state -Results $results
                }
            }
            elseif ($Group -eq "Advanced") {
                if ($Mode -eq "Select") {
                    # 进阶：多选模式
                    Write-UiInfo "进阶扩展可选安装模式"
                    Write-Host ""
                    $selectedIds = @(Show-AdvancedSelectMenu)
                    if ($selectedIds.Count -gt 0) {
                        $results = Invoke-GroupedInstall -StepIds $selectedIds -State $state
                        if ($results.Total -gt 0) {
                            Show-FinalSummary -State $state -Results $results
                        }
                    } else {
                        Write-UiWarn "未选择任何步骤"
                    }
                }
                else {
                    # 进阶：一键安装（默认）
                    Write-UiInfo "进阶扩展一键安装模式"
                    Write-Host ""
                    $advancedStepIds = $script:StepGroups["Advanced"].StepIds
                    $results = Invoke-GroupedInstall -StepIds $advancedStepIds -State $state
                    if ($results.Total -gt 0) {
                        Show-FinalSummary -State $state -Results $results
                    }
                }
            }

            return
        }

        # ── -Staged 参数：进入交互菜单
        # ── 无参数：也进入交互菜单

        $state.Mode = "Manage-Interactive"

        while ($true) {
            $topChoice = Select-TopLevelAction

            if ($topChoice -eq -1) {
                Write-Host ""
                Write-UiInfo "退出 CCQ"
                break
            }

            if ($topChoice -eq 0) {
                # 基础环境：直接一键安装
                Write-Host ""
                Write-UiInfo "基础环境一键安装"
                Write-Host ""

                $basicStepIds = $script:StepGroups["Basic"].StepIds
                $results = Invoke-GroupedInstall -StepIds $basicStepIds -State $state

                if ($results.Total -gt 0) {
                    Show-FinalSummary -State $state -Results $results
                }

                Write-Host ""
                Write-Host "按任意键返回主菜单..." -ForegroundColor Gray
                $null = [Console]::ReadKey($true)
            }
            elseif ($topChoice -eq 1) {
                # 进阶扩展：显示子菜单
                $advChoice = Select-AdvancedAction

                if ($advChoice -eq -1) {
                    continue
                }

                if ($advChoice -eq 0) {
                    # 一键安装
                    Write-Host ""
                    Write-UiInfo "进阶扩展一键安装"
                    Write-Host ""

                    $advancedStepIds = $script:StepGroups["Advanced"].StepIds
                    $results = Invoke-GroupedInstall -StepIds $advancedStepIds -State $state

                    if ($results.Total -gt 0) {
                        Show-FinalSummary -State $state -Results $results
                    }

                    Write-Host ""
                    Write-Host "按任意键返回主菜单..." -ForegroundColor Gray
                    $null = [Console]::ReadKey($true)
                }
                elseif ($advChoice -eq 1) {
                    # 可选安装
                    Write-Host ""
                    $selectedIds = @(Show-AdvancedSelectMenu)

                    if ($selectedIds.Count -gt 0) {
                        $results = Invoke-GroupedInstall -StepIds $selectedIds -State $state

                        if ($results.Total -gt 0) {
                            Show-FinalSummary -State $state -Results $results
                        }
                    } else {
                        Write-UiWarn "未选择任何步骤"
                    }

                    Write-Host ""
                    Write-Host "按任意键返回主菜单..." -ForegroundColor Gray
                    $null = [Console]::ReadKey($true)
                }
            }
        }

    } catch {
        Write-UiError "CCQ 运行中发生严重错误: $($_.Exception.Message)"
        Write-Host ""
        Show-ErrorDetails `
            -FriendlyMessage "CCQ 遇到未预期的错误，请查看技术详情" `
            -TechnicalDetails "$($_.Exception.Message)`n$($_.ScriptStackTrace)"
        exit 1
    }
}

# ─── 脚本入口点 ──────────────────────────────────────────────────────────────

Main
