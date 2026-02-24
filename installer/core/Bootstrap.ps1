# 步骤契约和状态模型 - CCQ
# 作者: 哈雷酱 (本小姐的架构设计杰作！)
# 功能: 定义统一步骤接口、状态模型、调度骨架和恢复逻辑

#Requires -Version 5.1

# 严格模式
Set-StrictMode -Version Latest

# 导入依赖模块
. "$PSScriptRoot\Process.ps1"

# 全局配置
$script:StateFilePath = "$env:TEMP\ClaudeEnvInstaller\install-state.json"
$script:StepTimeout = 300  # 步骤超时时间（秒）

# 步骤状态枚举
enum StepStatus {
    Pending = 0
    Running = 1
    Success = 2
    Failed = 3
    Skipped = 4
}

# 步骤结果类型
class StepResult {
    [string]$StepId
    [string]$StepName
    [StepStatus]$Status
    [string]$Message
    [hashtable]$Data
    [datetime]$StartTime
    [datetime]$EndTime
    [string]$ErrorDetails

    StepResult([string]$stepId, [string]$stepName) {
        $this.StepId = $stepId
        $this.StepName = $stepName
        $this.Status = [StepStatus]::Pending
        $this.Message = ""
        $this.Data = @{}
        $this.StartTime = [datetime]::MinValue
        $this.EndTime = [datetime]::MinValue
        $this.ErrorDetails = ""
    }
}

# 安装状态类型
class InstallState {
    [string]$Version
    [datetime]$StartTime
    [datetime]$LastUpdateTime
    [string]$Mode  # "OneClick" 或 "Staged"
    [hashtable]$StepResults
    [hashtable]$GlobalData
    [string]$CurrentStep
    [bool]$IsCompleted
    [string]$InstallationId

    InstallState() {
        $this.Version = "1.0"
        $this.StartTime = Get-Date
        $this.LastUpdateTime = Get-Date
        $this.Mode = ""
        $this.StepResults = @{}
        $this.GlobalData = @{}
        $this.CurrentStep = ""
        $this.IsCompleted = $false
        $this.InstallationId = [System.Guid]::NewGuid().ToString()
    }
}

function Initialize-StateDirectory {
    <#
    .SYNOPSIS
    初始化状态目录
    #>
    param()

    try {
        $stateDir = Split-Path $script:StateFilePath -Parent
        if (-not (Test-Path $stateDir)) {
            New-Item -Path $stateDir -ItemType Directory -Force | Out-Null
            Write-Host "✓ 状态目录已创建: $stateDir" -ForegroundColor Green
        }
    } catch {
        Write-Host "警告: 无法创建状态目录: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Save-InstallState {
    <#
    .SYNOPSIS
    保存安装状态到文件
    .PARAMETER State
    要保存的安装状态对象
    .RETURNS
    保存成功返回 $true，失败返回 $false
    #>
    param(
        [Parameter(Mandatory = $true)]
        [InstallState]$State
    )

    try {
        # 确保状态目录存在
        Initialize-StateDirectory

        # 更新最后修改时间
        $State.LastUpdateTime = Get-Date

        # 序列化状态对象
        $stateJson = $State | ConvertTo-Json -Depth 10

        # 原子写入状态文件
        $tempFile = "$script:StateFilePath.tmp"
        $stateJson | Out-File -FilePath $tempFile -Encoding UTF8 -Force

        # 移动到最终位置
        Move-Item -Path $tempFile -Destination $script:StateFilePath -Force

        Write-Host "✓ 安装状态已保存" -ForegroundColor Green
        return $true

    } catch {
        Write-Host "✗ 保存安装状态失败: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Load-InstallState {
    <#
    .SYNOPSIS
    从文件加载安装状态
    .RETURNS
    安装状态对象，如果文件不存在或加载失败则返回新的状态对象
    #>
    param()

    # 辅助函数：将 PSCustomObject 转换为 Hashtable
    function ConvertTo-HashtableDeep {
        param([Parameter(ValueFromPipeline)]$InputObject)

        if ($null -eq $InputObject) {
            return @{}
        }

        if ($InputObject -is [hashtable]) {
            return $InputObject
        }

        if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
            $hash = @{}
            foreach ($property in $InputObject.PSObject.Properties) {
                $value = $property.Value
                if ($value -is [System.Management.Automation.PSCustomObject]) {
                    $hash[$property.Name] = ConvertTo-HashtableDeep $value
                } else {
                    $hash[$property.Name] = $value
                }
            }
            return $hash
        }

        return @{}
    }

    try {
        if (Test-Path $script:StateFilePath) {
            Write-Host "📂 加载现有安装状态..." -ForegroundColor Cyan

            $stateJson = Get-Content $script:StateFilePath -Raw -Encoding UTF8
            $stateData = $stateJson | ConvertFrom-Json

            # 创建状态对象
            $state = [InstallState]::new()
            $state.Version = $stateData.Version
            $state.StartTime = [datetime]$stateData.StartTime
            $state.LastUpdateTime = [datetime]$stateData.LastUpdateTime
            $state.Mode = $stateData.Mode
            $state.CurrentStep = $stateData.CurrentStep
            $state.IsCompleted = $stateData.IsCompleted
            $state.InstallationId = $stateData.InstallationId

            # 重建步骤结果
            foreach ($stepId in $stateData.StepResults.PSObject.Properties.Name) {
                $stepData = $stateData.StepResults.$stepId
                $stepResult = [StepResult]::new($stepId, $stepData.StepName)
                $stepResult.Status = [StepStatus]$stepData.Status
                $stepResult.Message = $stepData.Message
                $stepResult.Data = ConvertTo-HashtableDeep $stepData.Data
                $stepResult.StartTime = [datetime]$stepData.StartTime
                $stepResult.EndTime = [datetime]$stepData.EndTime
                $stepResult.ErrorDetails = $stepData.ErrorDetails

                $state.StepResults[$stepId] = $stepResult
            }

            # 重建全局数据
            if ($stateData.GlobalData) {
                $state.GlobalData = ConvertTo-HashtableDeep $stateData.GlobalData
            }

            # ── 迁移旧 StepId 到新格式（静默执行）──────────────────────────────
            $legacyMap = Get-LegacyStepIdMap
            $migratedResults = @{}
            $needsSave = $false

            foreach ($oldId in @($state.StepResults.Keys)) {
                if ($legacyMap.ContainsKey($oldId)) {
                    $newId = $legacyMap[$oldId]

                    # 检测键冲突
                    if ($migratedResults.ContainsKey($newId)) {
                        # 冲突解决策略：优先保留 Success 状态，或优先保留较新的 EndTime
                        $existing = $migratedResults[$newId]
                        $migrating = $state.StepResults[$oldId]

                        if ($existing.Status -eq [StepStatus]::Success) {
                            continue
                        } elseif ($migrating.EndTime -gt $existing.EndTime) {
                            # 覆盖现有状态
                        } else {
                            continue
                        }
                    }

                    $stepResult = $state.StepResults[$oldId]
                    $stepResult.StepId = $newId
                    $migratedResults[$newId] = $stepResult
                    $needsSave = $true
                } else {
                    $migratedResults[$oldId] = $state.StepResults[$oldId]
                }
            }

            $state.StepResults = $migratedResults

            # 迁移 CurrentStep
            if ($state.CurrentStep -and $legacyMap.ContainsKey($state.CurrentStep)) {
                $state.CurrentStep = $legacyMap[$state.CurrentStep]
                $needsSave = $true
            }

            # 静默保存迁移后的状态
            if ($needsSave) {
                $null = Save-InstallState -State $state
            }

            Write-Host "✓ 安装状态加载成功 (ID: $($state.InstallationId))" -ForegroundColor Green
            return $state

        } else {
            Write-Host "📝 创建新的安装状态" -ForegroundColor Cyan
            return [InstallState]::new()
        }

    } catch {
        Write-Host "⚠ 加载安装状态失败，创建新状态: $($_.Exception.Message)" -ForegroundColor Yellow
        return [InstallState]::new()
    }
}

function Invoke-StepLifecycle {
    <#
    .SYNOPSIS
    执行步骤生命周期（Test -> Install -> Verify）
    .PARAMETER StepId
    步骤 ID
    .PARAMETER StepName
    步骤显示名称
    .PARAMETER TestFunction
    测试函数名
    .PARAMETER InstallFunction
    安装函数名
    .PARAMETER VerifyFunction
    验证函数名（可选）
    .PARAMETER State
    安装状态对象
    .PARAMETER SkipIfInstalled
    如果已安装是否跳过
    .RETURNS
    步骤执行结果对象
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$StepId,

        [Parameter(Mandatory = $true)]
        [string]$StepName,

        [Parameter(Mandatory = $true)]
        [string]$TestFunction,

        [Parameter(Mandatory = $true)]
        [string]$InstallFunction,

        [string]$VerifyFunction,

        [Parameter(Mandatory = $true)]
        [InstallState]$State,

        [switch]$SkipIfInstalled
    )

    Write-UiOutput "🔄 执行步骤: $StepName" -Level Essential -Type Info

    # 创建或获取步骤结果
    if ($State.StepResults.ContainsKey($StepId)) {
        $stepResult = $State.StepResults[$StepId]
    } else {
        $stepResult = [StepResult]::new($StepId, $StepName)
        $State.StepResults[$StepId] = $stepResult
    }

    # 如果步骤已成功完成且允许跳过，则跳过
    if ($SkipIfInstalled -and $stepResult.Status -eq [StepStatus]::Success) {
        Write-UiOutput "⏭ 步骤已完成，跳过: $StepName" -Level Essential -Type Success
        return $stepResult
    }

    try {
        $stepResult.Status = [StepStatus]::Running
        $stepResult.StartTime = Get-Date
        $State.CurrentStep = $StepId

        # 保存状态（使用 $null 赋值避免返回值污染）
        $null = Save-InstallState -State $State

        # 1. 执行测试阶段
        Write-UiOutput "  🔍 测试阶段: $TestFunction" -Level Debug -Type Info
        $testResult = & $TestFunction

        # 兼容 bool 和 hashtable 两种返回类型
        $isInstalled = if ($testResult -is [bool]) { $testResult } elseif ($testResult) { [bool]$testResult.IsInstalled } else { $false }
        if ($isInstalled -and $SkipIfInstalled) {
            $stepResult.Status = [StepStatus]::Skipped
            $stepResult.Message = "组件已安装，跳过安装"
            $stepResult.EndTime = Get-Date
            Write-UiOutput "  ✓ 组件已安装，跳过" -Level Essential -Type Warn
            return $stepResult
        }

        # 2. 执行安装阶段
        Write-UiOutput "  🔧 安装阶段: $InstallFunction" -Level Debug -Type Info
        $installResult = & $InstallFunction

        # 兼容 bool 和 hashtable 两种返回类型
        $installSuccess = if ($installResult -is [bool]) { $installResult } elseif ($installResult) { [bool]$installResult.Success } else { $false }
        if (-not $installSuccess) {
            $installError = if ($installResult -is [bool]) { "安装函数返回失败" } elseif ($installResult -and $installResult.ErrorMessage) { $installResult.ErrorMessage } else { "未知错误" }
            throw "安装阶段失败: $installError"
        }

        # 3. 执行验证阶段（如果提供）
        if ($VerifyFunction) {
            Write-UiOutput "  ✅ 验证阶段: $VerifyFunction" -Level Debug -Type Info
            $verifyResult = & $VerifyFunction

            # 兼容 bool 和 hashtable 两种返回类型
            $verifySuccess = if ($verifyResult -is [bool]) { $verifyResult } elseif ($verifyResult) { [bool]$verifyResult.Success } else { $false }
            if (-not $verifySuccess) {
                $verifyError = if ($verifyResult -is [bool]) { "验证函数返回失败" } elseif ($verifyResult -and $verifyResult.ErrorMessage) { $verifyResult.ErrorMessage } else { "未知错误" }
                throw "验证阶段失败: $verifyError"
            }
        }

        # 步骤成功完成
        $stepResult.Status = [StepStatus]::Success
        $stepResult.Message = "步骤执行成功"
        $stepResult.EndTime = Get-Date

        # 合并结果数据（加固类型安全检查，兼容不规范的返回结构）
        foreach ($candidate in @($testResult, $installResult)) {
            if (-not $candidate -or $candidate -is [bool]) {
                continue
            }

            $dataObject = $null

            # 检查 hashtable 类型
            if ($candidate -is [hashtable] -and $candidate.ContainsKey("Data")) {
                $dataObject = $candidate["Data"]
            }
            # 检查 PSCustomObject 类型
            elseif ($candidate.PSObject.Properties.Name -contains "Data") {
                $dataObject = $candidate.Data
            }

            if (-not $dataObject) {
                continue
            }

            # 安全复制 Data 内容
            if ($dataObject -is [hashtable]) {
                foreach ($key in $dataObject.Keys) {
                    $stepResult.Data[$key] = $dataObject[$key]
                }
            }
            elseif ($dataObject -is [System.Collections.IDictionary]) {
                foreach ($key in $dataObject.Keys) {
                    $stepResult.Data[[string]$key] = $dataObject[$key]
                }
            }
            elseif ($dataObject -is [System.Management.Automation.PSCustomObject]) {
                foreach ($prop in $dataObject.PSObject.Properties) {
                    $stepResult.Data[$prop.Name] = $prop.Value
                }
            }
        }

        Write-UiOutput "  ✓ $StepName 执行成功" -Level Essential -Type Success

    } catch {
        $stepResult.Status = [StepStatus]::Failed
        $stepResult.Message = "步骤执行失败"
        $stepResult.ErrorDetails = $_.Exception.Message
        $stepResult.EndTime = Get-Date

        Write-UiOutput "  ✗ $StepName 执行失败: $($_.Exception.Message)" -Level Essential -Type Error
    } finally {
        # 保存状态（使用 $null 赋值避免返回值污染）
        Write-UiOutput "  💾 保存安装状态..." -Level Debug -Type Info
        $null = Save-InstallState -State $State
    }

    return $stepResult
}

# Get-StepDependencies 已迁移到 Registry.ps1，由入口脚本 dot-source Registry.ps1 提供

function Test-StepDependencies {
    <#
    .SYNOPSIS
    检查步骤依赖是否满足
    .PARAMETER StepId
    要检查的步骤 ID
    .PARAMETER State
    安装状态对象
    .RETURNS
    依赖检查结果对象
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$StepId,

        [Parameter(Mandatory = $true)]
        [InstallState]$State
    )

    $result = @{
        CanExecute = $true
        MissingDependencies = @()
        FailedDependencies = @()
    }

    $dependencies = Get-StepDependencies
    if ($dependencies.ContainsKey($StepId)) {
        foreach ($depStepId in $dependencies[$StepId]) {
            if ($State.StepResults.ContainsKey($depStepId)) {
                $depResult = $State.StepResults[$depStepId]
                if ($depResult.Status -eq [StepStatus]::Failed) {
                    $result.CanExecute = $false
                    $result.FailedDependencies += $depStepId
                } elseif ($depResult.Status -ne [StepStatus]::Success -and
                      $depResult.Status -ne [StepStatus]::Skipped) {
                    $result.CanExecute = $false
                    $result.MissingDependencies += $depStepId
                }
            } else {
                $result.CanExecute = $false
                $result.MissingDependencies += $depStepId
            }
        }
    }

    return $result
}

function Get-ExecutionOrder {
    <#
    .SYNOPSIS
    根据依赖关系计算步骤执行顺序（优先级拓扑排序：每轮取 Order 最小的可执行步骤）
    .PARAMETER StepIds
    要排序的步骤 ID 数组
    .RETURNS
    按依赖关系排序的步骤 ID 数组
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$StepIds
    )

    $dependencies = Get-StepDependencies
    $ordered = @()
    $remaining = $StepIds.Clone()

    # 预加载 Order 映射（避免循环内重复调用）
    $registry = Get-StepRegistry
    $orderMap = @{}
    foreach ($step in $registry) {
        $orderMap[$step.StepId] = $step.Order
    }

    # 优先级拓扑排序：每轮仅取 Order 最小的可执行步骤，保证全局 Order 顺序
    while ($remaining.Count -gt 0) {
        $canExecute = @()

        foreach ($stepId in $remaining) {
            $deps = if ($dependencies.ContainsKey($stepId)) { $dependencies[$stepId] } else { @() }
            $allDepsSatisfied = $true

            foreach ($dep in $deps) {
                if ($dep -in $remaining) {
                    $allDepsSatisfied = $false
                    break
                }
            }

            if ($allDepsSatisfied) {
                $canExecute += $stepId
            }
        }

        if ($canExecute.Count -eq 0) {
            # 检测到循环依赖
            Write-Host "⚠ 检测到循环依赖，剩余步骤: $($remaining -join ', ')" -ForegroundColor Yellow
            $ordered += $remaining
            break
        }

        # 取 Order 最小的单个步骤，确保全局按 Order 递增输出
        $next = $canExecute | Sort-Object { if ($orderMap.ContainsKey($_)) { $orderMap[$_] } else { [int]::MaxValue } } | Select-Object -First 1
        $ordered += $next

        # 从剩余列表中移除（@() 确保 StrictMode 下结果始终为数组）
        $remaining = @($remaining | Where-Object { $_ -ne $next })
    }

    return $ordered
}

function Resume-Installation {
    <#
    .SYNOPSIS
    从状态文件恢复安装进程
    .PARAMETER StateFilePath
    状态文件路径（可选，使用默认路径）
    .RETURNS
    恢复的安装状态对象
    #>
    param(
        [string]$StateFilePath = $script:StateFilePath
    )

    try {
        if ($StateFilePath -ne $script:StateFilePath) {
            $script:StateFilePath = $StateFilePath
        }

        Write-Host "🔄 恢复安装进程..." -ForegroundColor Cyan

        $state = Load-InstallState

        if ($state.IsCompleted) {
            Write-Host "✓ 安装已完成，无需恢复" -ForegroundColor Green
            return $state
        }

        Write-Host "📊 安装状态摘要:" -ForegroundColor Cyan
        Write-Host "  安装 ID: $($state.InstallationId)" -ForegroundColor Gray
        Write-Host "  开始时间: $($state.StartTime)" -ForegroundColor Gray
        Write-Host "  安装模式: $($state.Mode)" -ForegroundColor Gray
        Write-Host "  当前步骤: $($state.CurrentStep)" -ForegroundColor Gray

        # 显示步骤状态
        $completedSteps = @($state.StepResults.Values | Where-Object { $_.Status -eq [StepStatus]::Success }).Count
        $failedSteps = @($state.StepResults.Values | Where-Object { $_.Status -eq [StepStatus]::Failed }).Count
        $totalSteps = $state.StepResults.Count

        Write-Host "  步骤进度: $completedSteps/$totalSteps 完成, $failedSteps 失败" -ForegroundColor Gray

        if ($failedSteps -gt 0) {
            Write-Host "⚠ 发现失败的步骤:" -ForegroundColor Yellow
            foreach ($stepResult in $state.StepResults.Values) {
                if ($stepResult.Status -eq [StepStatus]::Failed) {
                    Write-Host "    ✗ $($stepResult.StepName): $($stepResult.ErrorDetails)" -ForegroundColor Red
                }
            }
        }

        return $state

    } catch {
        Write-Host "✗ 恢复安装进程失败: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

function Clear-InstallState {
    <#
    .SYNOPSIS
    清除安装状态文件
    .PARAMETER Confirm
    是否需要确认
    #>
    param(
        [switch]$Confirm
    )

    if (-not $Confirm) {
        Write-Host "⚠ 此操作将清除所有安装状态，是否继续？(y/N)" -ForegroundColor Yellow -NoNewline
        $response = Read-Host " "
        if ($response -ne "y" -and $response -ne "Y") {
            Write-Host "操作已取消" -ForegroundColor Gray
            return
        }
    }

    try {
        if (Test-Path $script:StateFilePath) {
            Remove-Item $script:StateFilePath -Force
            Write-Host "✓ 安装状态已清除" -ForegroundColor Green
        } else {
            Write-Host "ℹ 没有找到安装状态文件" -ForegroundColor Gray
        }
    } catch {
        Write-Host "✗ 清除安装状态失败: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用