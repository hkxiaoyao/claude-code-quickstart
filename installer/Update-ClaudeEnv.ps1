#Requires -Version 7.0
# Update-ClaudeEnv.ps1 - CCQ（统一更新入口）
# 功能: 声明式更新已安装组件，支持交互多选 / CLI 指定 / 全量更新

param(
    [switch]$ListUpdates,
    [switch]$All,
    [string[]]$Steps,
    [ValidateSet("Ask", "Skip", "Install", "Fail")]
    [string]$OnMissing,
    [ValidateSet("Normal", "Developer")]
    [string]$OutputMode = "Normal"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── PS5 中文编码修复 ──────────────────────────────────────────────────────────
try {
    if (-not ([System.Management.Automation.PSTypeName]'_UpdateKernel32Cp').Type) {
        Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public class _UpdateKernel32Cp {
    [DllImport("kernel32.dll")] public static extern bool SetConsoleOutputCP(uint cp);
    [DllImport("kernel32.dll")] public static extern bool SetConsoleCP(uint cp);
}
'@ -ErrorAction SilentlyContinue
    }
    [_UpdateKernel32Cp]::SetConsoleOutputCP(65001) | Out-Null
    [_UpdateKernel32Cp]::SetConsoleCP(65001) | Out-Null
} catch { }
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ─── PS 版本运行时拦截 ─────────────────────────────────────────────────────────
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host ""
    Write-Host "  [ERROR] Update-ClaudeEnv.ps1 需要 PowerShell 7.0 或更高版本" -ForegroundColor Red
    Write-Host "  当前版本: PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Red
    Write-Host ""
    exit 1
}

# ─── 参数互斥验证 ──────────────────────────────────────────────────────────────
if ($All -and $Steps -and $Steps.Count -gt 0) {
    Write-Host "[ERROR] -All 和 -Steps 不能同时使用" -ForegroundColor Red
    exit 1
}

# ─── OnMissing 默认值推导 ──────────────────────────────────────────────────────
if (-not $OnMissing) {
    $OnMissing = if ($All -or ($Steps -and $Steps.Count -gt 0)) { "Skip" } else { "Ask" }
}

$script:InstallerRoot = $PSScriptRoot

# ─── Dot-source 核心模块 ──────────────────────────────────────────────────────
. "$script:InstallerRoot\core\Ui.ps1"
. "$script:InstallerRoot\core\Process.ps1"
. "$script:InstallerRoot\core\Profile.ps1"
. "$script:InstallerRoot\core\Admin.ps1"
. "$script:InstallerRoot\core\Net.ps1"
. "$script:InstallerRoot\core\Registry.ps1"
. "$script:InstallerRoot\core\Bootstrap.ps1"
. "$script:InstallerRoot\core\McpManager.ps1"

# ─── Dot-source 所有步骤模块 ──────────────────────────────────────────────────
$stepFiles = Get-StepFiles
foreach ($stepFile in $stepFiles) {
    . "$script:InstallerRoot\$stepFile"
}

# ─── 初始化输出模式 ───────────────────────────────────────────────────────────
Set-CcqOutputMode -Mode ([CcqOutputMode]$OutputMode)

# ─── 步骤注册表 ───────────────────────────────────────────────────────────────
$script:StepRegistry = Get-StepRegistry

# ─── 内容指纹管理（跳过模板未变更的步骤）─────────────────────────────────

$script:FingerprintManagedSteps = @("ClaudeMd", "ClaudeConfig", "Mcp", "CcgWorkflow")

function Get-StepDesiredFingerprint {
    <#
    .SYNOPSIS
    计算步骤的"期望"内容指纹（基于源模板 SHA256 或工具版本号）
    .PARAMETER StepId
    步骤 ID（仅支持 FingerprintManagedSteps 中的步骤）
    .RETURNS
    string - 指纹值；空字符串表示无法计算
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$StepId
    )

    try {
        switch ($StepId) {
            "ClaudeMd" {
                # 主模板 + 所有 ccq- rules 模板的拼接哈希
                $parts = @($script:ClaudeMdTemplate)
                foreach ($key in ($script:RulesTemplates.Keys | Sort-Object)) {
                    $parts += "${key}:$($script:RulesTemplates[$key])"
                }
                return Get-StringFingerprint -Text ($parts -join "`n---`n")
            }
            "ClaudeConfig" {
                # env 默认值 + 废弃键 + 基础权限的拼接哈希
                $parts = @()
                foreach ($key in ($script:ClaudeConfigEnvDefaults.Keys | Sort-Object)) {
                    $parts += "${key}=$($script:ClaudeConfigEnvDefaults[$key])"
                }
                $parts += "deprecated:" + (($script:ClaudeConfigDeprecatedEnvKeys | Sort-Object) -join ",")
                $parts += "permissions:" + (($script:ClaudeConfigBasePermissions | Sort-Object) -join ",")
                return Get-StringFingerprint -Text ($parts -join "`n")
            }
            "Mcp" {
                # MCP Server 定义的结构化哈希（排除元数据字段）
                $parts = @()
                $configKeys = @("McpType", "Command", "Args", "Url", "UrlTemplate", "CredentialType", "Credentials", "EnvFile", "PreInstall")
                foreach ($serverId in ($script:McpServers.Keys | Sort-Object)) {
                    $server = $script:McpServers[$serverId]
                    $serverParts = @("server:$serverId")
                    foreach ($ck in $configKeys) {
                        if ($server.ContainsKey($ck) -and $null -ne $server[$ck]) {
                            $val = $server[$ck]
                            if ($val -is [array] -or $val -is [hashtable] -or $val -is [System.Collections.Specialized.OrderedDictionary]) {
                                $serverParts += "${ck}=" + ($val | ConvertTo-Json -Depth 5 -Compress)
                            } else {
                                $serverParts += "${ck}=$val"
                            }
                        }
                    }
                    $parts += ($serverParts -join "|")
                }
                return Get-StringFingerprint -Text ($parts -join "`n")
            }
            "CcgWorkflow" {
                # 使用 codeagent-wrapper 版本号作为指纹
                if (Test-CommandAvailable "codeagent-wrapper") {
                    return Get-CommandVersion -Command "codeagent-wrapper"
                }
                return ""
            }
            default { return "" }
        }
    } catch {
        Write-UiWarn "指纹计算失败 (${StepId}): $($_.Exception.Message)"
        return ""
    }
}

# ─── 更新摘要显示 ─────────────────────────────────────────────────────────────

function Show-UpdateSummary {
    <#
    .SYNOPSIS
    显示更新结果摘要（分四类：已更新/已最新/失败/跳过）
    #>
    param(
        [InstallState]$State,
        [string[]]$ExecutedStepIds,
        [string[]]$SkippedStepIds = @(),
        [string]$SnapshotDir = ""
    )

    $updated = @()
    $upToDate = @()
    $failed = @()

    foreach ($stepId in $ExecutedStepIds) {
        $stepConfig = $script:StepRegistry | Where-Object { $_.StepId -eq $stepId } | Select-Object -First 1
        $stepName = if ($stepConfig) { $stepConfig.StepName } else { $stepId }

        if ($State.StepResults.ContainsKey($stepId)) {
            $stepResult = $State.StepResults[$stepId]
            $items = @()
            if ($stepResult.Data -and $stepResult.Data.ContainsKey("UpdatedItems")) {
                $items = @($stepResult.Data["UpdatedItems"])
            }

            if ($stepResult.Status -eq [StepStatus]::Failed) {
                $failed += @{ Name = $stepName; Detail = $stepResult.ErrorDetails }
            } elseif ($items.Count -gt 0 -and @($items | Where-Object { $_ -match "^noop::" }).Count -eq $items.Count) {
                $upToDate += @{ Name = $stepName; Items = ($items -join ", ") }
            } elseif ($stepResult.Status -eq [StepStatus]::Skipped) {
                # Skipped 由生命周期标记（OnMissing=Skip 等）
            } else {
                $realChanges = @($items | Where-Object { $_ -notmatch "^noop::" })
                if ($realChanges.Count -gt 0) {
                    $updated += @{ Name = $stepName; Items = ($realChanges -join ", ") }
                } else {
                    $upToDate += @{ Name = $stepName; Items = "no-change" }
                }
            }
        }
    }

    Write-Host ""
    Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  更新结果摘要" -ForegroundColor Cyan
    Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan

    # 已更新
    Write-Host ""
    if ($updated.Count -gt 0) {
        Write-Host "  Updated ($($updated.Count)):" -ForegroundColor Green
        foreach ($item in $updated) {
            Write-Host "    $($item.Name)" -ForegroundColor White -NoNewline
            Write-Host "  $($item.Items)" -ForegroundColor Gray
        }
    } else {
        Write-Host "  Updated (0)" -ForegroundColor Green
    }

    # 已最新
    if ($upToDate.Count -gt 0) {
        Write-Host ""
        Write-Host "  Already Up-to-Date ($($upToDate.Count)):" -ForegroundColor DarkGray
        foreach ($item in $upToDate) {
            Write-Host "    $($item.Name)" -ForegroundColor DarkGray -NoNewline
            if ($item.Items -match "fingerprint-match") {
                Write-Host "  (指纹一致)" -ForegroundColor DarkGray
            } else {
                Write-Host "  (内容无变更)" -ForegroundColor DarkGray
            }
        }
    }

    # 失败
    if ($failed.Count -gt 0) {
        Write-Host ""
        Write-Host "  Failed ($($failed.Count)):" -ForegroundColor Red
        foreach ($item in $failed) {
            Write-Host "    $($item.Name)" -ForegroundColor Red -NoNewline
            Write-Host "  $($item.Detail)" -ForegroundColor DarkRed
        }
    }

    # 跳过
    if ($SkippedStepIds.Count -gt 0) {
        Write-Host ""
        Write-Host "  Skipped ($($SkippedStepIds.Count)):" -ForegroundColor Yellow
        foreach ($stepId in $SkippedStepIds) {
            $stepConfig = $script:StepRegistry | Where-Object { $_.StepId -eq $stepId } | Select-Object -First 1
            $stepName = if ($stepConfig) { $stepConfig.StepName } else { $stepId }
            Write-Host "    $stepName" -ForegroundColor Yellow -NoNewline
            Write-Host "  (未安装, OnMissing=$OnMissing)" -ForegroundColor DarkYellow
        }
    }

    # 备份路径
    if ($SnapshotDir -and (Test-Path $SnapshotDir)) {
        Write-Host ""
        Write-Host "  备份路径: $SnapshotDir" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
}

# ─── 更新状态检测（统一入口，一次性完成）────────────────────────────────────

# StepId → npm 包名映射
$script:NpmPackageMap = @{
    "ClaudeCode"  = "@anthropic-ai/claude-code"
    "Ccline"      = "@cometix/ccline"
    "CodexCli"    = "@openai/codex"
    "GeminiCli"   = "@google/gemini-cli"
    "OpenSpec"    = "@fission-ai/openspec"
}

function Get-UpdateStatus {
    <#
    .SYNOPSIS
    一次性检测所有可更新步骤的安装状态 + 远程版本
    .RETURNS
    hashtable[] — 每项包含 StepId/StepName/IsOptional/IsInstalled/CurrentVersion/LatestVersion/HasUpdate
    HasUpdate: $true=有更新, $false=已最新, $null=无法判定(非npm步骤)
    #>

    $registry = Get-StepRegistry
    $updatableSteps = @($registry | Where-Object { $_.UpdateFunction -ne "" })

    Write-Host ""
    Write-Host "正在检测组件状态与远程版本..." -ForegroundColor Gray

    # 批量查询 npm 全局过期包（1 次网络请求）
    $outdated = Get-NpmOutdatedGlobal -Force

    # CcgWorkflow 单独查询（非全局包）
    $ccgLatest = ""
    try {
        $ccgViewResult = Invoke-ExternalCommand `
            -Command "npm" `
            -Arguments @("view", "ccg-workflow", "version") `
            -TimeoutSeconds 30 -RetryCount 0 -SuppressOutput
        if ($ccgViewResult.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($ccgViewResult.Output)) {
            $ccgLatest = $ccgViewResult.Output.Trim()
        }
    } catch { }

    $statusList = @()

    foreach ($step in $updatableSteps) {
        $entry = @{
            StepId         = $step.StepId
            StepName       = $step.StepName
            IsOptional     = $step.IsOptional
            IsInstalled    = $false
            CurrentVersion = ""
            LatestVersion  = ""
            HasUpdate      = $null   # $true/$false/$null
        }

        # 本地安装状态检测
        try {
            $testResult = & $step.TestFunction
            if ($testResult -is [hashtable] -and $testResult.IsInstalled) {
                $entry.IsInstalled = $true
                $entry.CurrentVersion = if ($testResult.Version) { $testResult.Version } else { "" }
            } elseif ($testResult -is [bool] -and $testResult) {
                $entry.IsInstalled = $true
            }
        } catch { }

        # 远程版本检测（仅已安装的步骤）
        if ($entry.IsInstalled) {
            $npmPkg = $script:NpmPackageMap[$step.StepId]
            if ($npmPkg) {
                # 全局 npm 包：从 outdated 缓存查
                if ($outdated.ContainsKey($npmPkg)) {
                    $entry.LatestVersion = $outdated[$npmPkg].Latest
                    $entry.HasUpdate = $true
                }
                else {
                    $entry.LatestVersion = $entry.CurrentVersion
                    $entry.HasUpdate = $false
                }
            }
            elseif ($step.StepId -eq "CcgWorkflow" -and $ccgLatest) {
                # npx 安装包：从 npm view 查
                $entry.LatestVersion = $ccgLatest
                $entry.HasUpdate = ($entry.CurrentVersion -and $entry.CurrentVersion -ne $ccgLatest)
            }
            # 其余非 npm 步骤（ClaudeConfig/ClaudeMd/Mcp），HasUpdate 保持 $null
        }

        $statusList += $entry
    }

    return $statusList
}

function Show-UpdateStatus {
    <#
    .SYNOPSIS
    展示组件状态表（统一格式）
    .PARAMETER StatusList
    Get-UpdateStatus 返回的状态数组
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$StatusList
    )

    Write-Host ""
    Write-Host "组件状态:" -ForegroundColor Cyan
    Write-Host ""

    foreach ($entry in $StatusList) {
        $stepIdDisplay = $entry.StepId.PadRight(15)
        $stepNameDisplay = $entry.StepName.PadRight(20)

        if (-not $entry.IsInstalled) {
            Write-Host "  $stepIdDisplay" -ForegroundColor White -NoNewline
            Write-Host "$stepNameDisplay" -ForegroundColor Gray -NoNewline
            Write-Host "[未安装]" -ForegroundColor DarkGray
            continue
        }

        $versionDisplay = if ($entry.CurrentVersion) { " ($($entry.CurrentVersion))" } else { "" }

        if ($entry.HasUpdate -eq $true) {
            Write-Host "  $stepIdDisplay" -ForegroundColor White -NoNewline
            Write-Host "$stepNameDisplay" -ForegroundColor Gray -NoNewline
            Write-Host "[有更新]$versionDisplay" -ForegroundColor Yellow -NoNewline
            Write-Host " -> $($entry.LatestVersion)" -ForegroundColor Cyan
        }
        elseif ($entry.HasUpdate -eq $false) {
            Write-Host "  $stepIdDisplay" -ForegroundColor White -NoNewline
            Write-Host "$stepNameDisplay" -ForegroundColor Gray -NoNewline
            Write-Host "[已是最新]$versionDisplay" -ForegroundColor Green
        }
        else {
            # 非 npm 步骤，无法判定远程版本
            Write-Host "  $stepIdDisplay" -ForegroundColor White -NoNewline
            Write-Host "$stepNameDisplay" -ForegroundColor Gray -NoNewline
            Write-Host "[已安装]" -ForegroundColor Green
        }
    }

    $updatesCount = @($StatusList | Where-Object { $_.HasUpdate -eq $true }).Count
    $installedCount = @($StatusList | Where-Object { $_.IsInstalled }).Count

    Write-Host ""
    if ($updatesCount -gt 0) {
        Write-Host "  $installedCount 个组件已安装，其中 $updatesCount 个有可用更新" -ForegroundColor Yellow
    }
    else {
        Write-Host "  $installedCount 个组件已安装，所有 npm 组件均为最新版本" -ForegroundColor Green
    }
    Write-Host ""
}

# ─── 交互式步骤选择 ───────────────────────────────────────────────────────────

function Select-UpdateSteps {
    <#
    .SYNOPSIS
    交互式多选可更新步骤（使用预计算的状态数据）
    .PARAMETER StatusList
    Get-UpdateStatus 返回的状态数组
    .RETURNS
    选中的 StepId 数组
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$StatusList
    )

    if ($StatusList.Count -eq 0) {
        Write-UiWarn "没有可更新的步骤"
        return @()
    }

    # 构建选项列表
    $options = @()
    $defaultSelected = @()

    for ($i = 0; $i -lt $StatusList.Count; $i++) {
        $entry = $StatusList[$i]
        $label = "$($entry.StepName)"
        if ($entry.IsOptional) { $label += " [可选]" }

        if ($entry.IsInstalled) {
            if ($entry.HasUpdate -eq $true) {
                # 有更新：显示版本变化，默认勾选
                $label += if ($entry.CurrentVersion) {
                    " ($($entry.CurrentVersion) -> $($entry.LatestVersion))"
                } else {
                    " (有更新 -> $($entry.LatestVersion))"
                }
                $defaultSelected += $i
            }
            elseif ($entry.HasUpdate -eq $false) {
                # npm 包已最新：不勾选
                $label += if ($entry.CurrentVersion) { " (已是最新 $($entry.CurrentVersion))" } else { " (已是最新)" }
            }
            else {
                # 非 npm 步骤：默认勾选
                $label += " (已安装)"
                $defaultSelected += $i
            }
        }
        else {
            $label += " (未安装)"
        }
        $options += $label
    }

    Write-Host ""
    Write-Host "选择要更新的组件（空格切换选择，Enter 确认，Esc 取消）:" -ForegroundColor Cyan
    Write-Host ""

    $selectedIndices = Show-MultiSelectMenu -Title "可更新组件" -Options $options -DefaultSelected $defaultSelected

    if ($null -eq $selectedIndices -or $selectedIndices.Count -eq 0) {
        Write-UiInfo "未选择任何步骤，退出更新"
        return @()
    }

    $selectedStepIds = @()
    foreach ($idx in $selectedIndices) {
        $selectedStepIds += $StatusList[$idx].StepId
    }

    return $selectedStepIds
}

# ─── 主流程 ───────────────────────────────────────────────────────────────────

function Main {
    # ─── 统一检测（所有模式共享）──────────────────────────────────────────
    $updateStatus = Get-UpdateStatus
    Show-UpdateStatus -StatusList $updateStatus

    # ─── ListUpdates 模式：仅展示，不执行 ────────────────────────────────
    if ($ListUpdates) {
        $hasUpdates = @($updateStatus | Where-Object { $_.HasUpdate -eq $true }).Count -gt 0
        if ($hasUpdates) {
            Write-Host "提示: 运行 " -ForegroundColor Gray -NoNewline
            Write-Host "pwsh -File installer/Update-ClaudeEnv.ps1" -ForegroundColor Cyan -NoNewline
            Write-Host " 选择并更新组件" -ForegroundColor Gray
            Write-Host ""
        }
        return
    }

    # ─── Mutex 获取 ────────────────────────────────────────────────────────
    $mutex = $null
    $acquired = $false

    try {
        $mutex = [System.Threading.Mutex]::new($false, "Global\CCQ.Update.Lock")
        $acquired = $mutex.WaitOne(0)

        if (-not $acquired) {
            Write-Host ""
            Write-Host "[ERROR] 另一个更新实例正在运行，请等待其完成后再试" -ForegroundColor Red
            Write-Host ""
            exit 1
        }

        # ─── 构建执行计划 ──────────────────────────────────────────────────
        $planStepIds = @()

        if ($All) {
            # 全量更新
            $planStepIds = @()  # Build-UpdatePlan -All 会自动处理
        } elseif ($Steps -and $Steps.Count -gt 0) {
            # CLI 指定步骤
            $planStepIds = $Steps
        } else {
            # 交互模式（使用预计算的状态数据）
            $selectedIds = @(Select-UpdateSteps -StatusList $updateStatus)
            if ($selectedIds.Count -eq 0) {
                return
            }
            $planStepIds = $selectedIds
        }

        $plan = if ($All) {
            Build-UpdatePlan -All
        } else {
            Build-UpdatePlan -RequestedSteps $planStepIds
        }

        if ($plan.Count -eq 0) {
            Write-UiInfo "没有需要更新的步骤"
            return
        }

        # ─── 指纹预检（跳过模板未变更的步骤）─────────────────────────────
        $manifest = Read-UpdateManifest
        $fingerprintSkips = @{}

        foreach ($stepConfig in $plan) {
            $sid = $stepConfig.StepId
            if ($sid -notin $script:FingerprintManagedSteps) { continue }

            $desiredFp = Get-StepDesiredFingerprint -StepId $sid
            if (-not $desiredFp) { continue }

            $storedEntry = $manifest["steps"][$sid]
            if ($storedEntry -and $storedEntry["fingerprint"] -eq $desiredFp) {
                # C-1: 指纹匹配仍需确认组件健康（防止目标文件被删除/损坏时误跳过）
                $testFn = $stepConfig.TestFunction
                $isHealthy = $false
                try {
                    $testResult = & $testFn
                    if ($testResult -is [hashtable]) {
                        $isHealthy = [bool]$testResult.IsInstalled
                    } elseif ($testResult -is [bool]) {
                        $isHealthy = $testResult
                    }
                } catch { }

                if ($isHealthy) {
                    $fingerprintSkips[$sid] = $desiredFp
                }
            }
        }

        # 显示执行计划
        Write-Host ""
        Write-Host "更新执行计划:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $plan.Count; $i++) {
            $sid = $plan[$i].StepId
            if ($fingerprintSkips.ContainsKey($sid)) {
                Write-Host "  $($i + 1). $($plan[$i].StepName) ($sid)" -ForegroundColor DarkGray -NoNewline
                Write-Host "  [指纹一致, 跳过]" -ForegroundColor DarkGray
            } else {
                Write-Host "  $($i + 1). $($plan[$i].StepName) ($sid)" -ForegroundColor White
            }
        }
        if ($fingerprintSkips.Count -gt 0) {
            Write-Host ""
            Write-UiInfo "指纹预检: $($fingerprintSkips.Count) 个步骤模板未变更，将跳过"
        }
        Write-Host ""

        # ─── 条件快照（仅当有步骤需要实际执行时创建）─────────────────────
        $stepsNeedingExecution = @($plan | Where-Object { -not $fingerprintSkips.ContainsKey($_.StepId) })
        $snapshotDir = ""

        if ($stepsNeedingExecution.Count -gt 0) {
            $filesToBackup = @(
                "$(Get-UserHome)\.claude\settings.json",
                "$(Get-UserHome)\.claude.json",
                "$(Get-UserHome)\.claude\CLAUDE.md",
                (Get-McpMetaPath)
            )
            # 添加 rules 目录下的 ccq- 和 ccg- 文件
            $rulesDir = "$(Get-UserHome)\.claude\rules"
            if (Test-Path $rulesDir) {
                $ruleFiles = Get-ChildItem $rulesDir -Include "ccq-*.md", "ccg-*.md" -ErrorAction SilentlyContinue
                if ($ruleFiles) {
                    foreach ($rf in $ruleFiles) {
                        $filesToBackup += $rf.FullName
                    }
                }
            }
            # 过滤只存在的文件
            $existingFiles = @($filesToBackup | Where-Object { Test-Path $_ })

            if ($existingFiles.Count -gt 0) {
                $snapshotDir = New-UpdateSnapshot -FilePaths $existingFiles
                Write-UiInfo "备份快照已创建: $snapshotDir"
            } else {
                Write-UiWarn "没有找到需要备份的文件，跳过快照"
            }
        } else {
            Write-UiInfo "所有步骤均为指纹命中，跳过备份快照"
        }

        # ─── 创建安装状态 ──────────────────────────────────────────────────
        $state = [InstallState]::new()
        $state.Mode = "Update"

        $executedStepIds = @()
        $skippedStepIds = @()
        $successCount = 0
        $failCount = 0

        # ─── 遍历执行计划 ──────────────────────────────────────────────────
        foreach ($stepConfig in $plan) {
            $stepId = $stepConfig.StepId

            # 指纹命中 → 直接记录为 noop，跳过实际执行
            if ($fingerprintSkips.ContainsKey($stepId)) {
                Write-Host ""
                Write-Host "─── 更新: $($stepConfig.StepName) ───" -ForegroundColor DarkGray
                Write-UiInfo "模板指纹一致，跳过"

                $skipResult = [StepResult]::new($stepId, $stepConfig.StepName)
                $skipResult.Status = [StepStatus]::Success
                $skipResult.Message = "fingerprint-match"
                $skipResult.Data = @{ UpdatedItems = @("noop::${stepId}::fingerprint-match") }
                $skipResult.StartTime = Get-Date
                $skipResult.EndTime = Get-Date
                $state.StepResults[$stepId] = $skipResult

                $executedStepIds += $stepId
                $successCount++
                continue
            }

            Write-Host ""
            Write-Host "─── 更新: $($stepConfig.StepName) ───" -ForegroundColor Cyan

            $stepResult = Invoke-UpdateLifecycle -StepConfig $stepConfig -State $state -OnMissing $OnMissing

            $executedStepIds += $stepId

            if ($stepResult.Status -eq [StepStatus]::Success) {
                $successCount++

                # 指纹管理步骤更新成功 → 回写清单
                if ($stepId -in $script:FingerprintManagedSteps) {
                    $newFp = Get-StepDesiredFingerprint -StepId $stepId
                    if ($newFp) {
                        $manifest["steps"][$stepId] = @{
                            fingerprint = $newFp
                            appliedAt   = (Get-Date).ToUniversalTime().ToString("o")
                        }
                        try {
                            Write-UpdateManifest -Manifest $manifest
                        } catch {
                            Write-UiWarn "清单回写失败: $($_.Exception.Message)"
                        }
                    }
                }
            } elseif ($stepResult.Status -eq [StepStatus]::Failed) {
                $failCount++
            } elseif ($stepResult.Status -eq [StepStatus]::Skipped) {
                $skippedStepIds += $stepId
            }
        }

        # ─── 清理旧快照 ───────────────────────────────────────────────────
        try {
            Clear-OldUpdateSnapshots -CurrentSnapshotDir $snapshotDir
        } catch {
            Write-UiWarn "旧快照清理失败: $($_.Exception.Message)"
        }

        # ─── 显示结果摘要 ──────────────────────────────────────────────────
        Show-UpdateSummary -State $state -ExecutedStepIds $executedStepIds `
            -SkippedStepIds $skippedStepIds -SnapshotDir $snapshotDir

        if ($failCount -gt 0) {
            exit 1
        }

    } finally {
        if ($acquired -and $mutex) {
            try {
                $mutex.ReleaseMutex()
            } catch { }
        }
        if ($mutex) {
            $mutex.Dispose()
        }
    }
}

# ─── 异常保护 ──────────────────────────────────────────────────────────────
trap {
    Write-Host ""
    if ($_.Exception -is [System.Management.Automation.PipelineStoppedException] -or
        $_.Exception -is [System.OperationCanceledException]) {
        Write-UiWarn "更新被用户中断 (Ctrl+C)"
    } else {
        Write-UiError "更新异常中断: $($_.Exception.Message)"
    }
    Write-UiInfo "已完成的更新将保留，未完成的步骤可重新运行"
    break
}

# ─── 入口 ─────────────────────────────────────────────────────────────────────
Main
