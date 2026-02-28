# 步骤契约和状态模型 - CCQ
# 作者: 哈雷酱 (本小姐的架构设计杰作！)
# 功能: 定义统一步骤接口、状态模型、调度骨架（纯内存，实时检测）

#Requires -Version 5.1

# 严格模式
Set-StrictMode -Version Latest

# 导入依赖模块
. "$PSScriptRoot\Process.ps1"

# 全局配置
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

# 安装状态类型（纯内存，不持久化）
class InstallState {
    [datetime]$StartTime
    [string]$Mode  # "OneClick" 或 "Staged" 或 "Manage-Basic" 或 "Manage-Advanced"
    [hashtable]$StepResults
    [hashtable]$GlobalData
    [string]$CurrentStep
    [bool]$IsCompleted

    InstallState() {
        $this.StartTime = Get-Date
        $this.Mode = ""
        $this.StepResults = @{}
        $this.GlobalData = @{}
        $this.CurrentStep = ""
        $this.IsCompleted = $false
    }
}

function Resolve-TestResultBool {
    <#
    .SYNOPSIS
    统一解析步骤函数返回值为布尔值（兼容 bool 和 hashtable 两种返回类型）
    .PARAMETER TestResult
    步骤函数的返回值（可能是 bool 或 hashtable）
    .PARAMETER PropertyName
    要提取的属性名（Test 函数用 "IsInstalled"，Install/Verify 函数用 "Success"）
    .RETURNS
    布尔值
    #>
    param(
        $TestResult,

        [string]$PropertyName = "IsInstalled"
    )

    if ($TestResult -is [bool]) { return $TestResult }
    elseif ($TestResult) { return [bool]$TestResult.$PropertyName }
    else { return $false }
}

function Invoke-StepLifecycle {
    <#
    .SYNOPSIS
    执行步骤生命周期（Test -> Install -> Verify）
    .DESCRIPTION
    完全基于实时检测，不依赖缓存状态。每次都执行 Test 函数检测当前环境。
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
    安装状态对象（仅用于本次会话内的结果记录）
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

    try {
        $stepResult.Status = [StepStatus]::Running
        $stepResult.StartTime = Get-Date
        $State.CurrentStep = $StepId

        # 1. 执行测试阶段（实时检测，不依赖缓存）
        Write-UiOutput "  🔍 测试阶段: $TestFunction" -Level Debug -Type Info
        $testResult = & $TestFunction

        $isInstalled = Resolve-TestResultBool -TestResult $testResult -PropertyName "IsInstalled"

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

        $installSuccess = Resolve-TestResultBool -TestResult $installResult -PropertyName "Success"

        if (-not $installSuccess) {
            $installError = if ($installResult -is [bool]) { "安装函数返回失败" }
                            elseif ($installResult -and $installResult.ErrorMessage) { $installResult.ErrorMessage }
                            else { "未知错误" }
            throw "安装阶段失败: $installError"
        }

        # 3. 执行验证阶段（如果提供）
        if ($VerifyFunction) {
            Write-UiOutput "  ✅ 验证阶段: $VerifyFunction" -Level Debug -Type Info
            $verifyResult = & $VerifyFunction

            $verifySuccess = Resolve-TestResultBool -TestResult $verifyResult -PropertyName "Success"

            if (-not $verifySuccess) {
                $verifyError = if ($verifyResult -is [bool]) { "验证函数返回失败" }
                               elseif ($verifyResult -and $verifyResult.ErrorMessage) { $verifyResult.ErrorMessage }
                               else { "未知错误" }
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
    }

    return $stepResult
}

function Test-StepDependencies {
    <#
    .SYNOPSIS
    检查步骤依赖是否满足（实时检测 + 会话状态）
    .DESCRIPTION
    优先检查本次会话内的失败状态（阻止执行），然后实时检测依赖是否真的已安装。
    .PARAMETER StepId
    要检查的步骤 ID
    .PARAMETER State
    安装状态对象（仅用于本次会话内的结果记录）
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
            # 优先检查本次会话内的状态
            if ($State.StepResults.ContainsKey($depStepId)) {
                $depResult = $State.StepResults[$depStepId]
                if ($depResult.Status -eq [StepStatus]::Failed) {
                    # 本次会话内失败 → 阻止执行
                    $result.CanExecute = $false
                    $result.FailedDependencies += $depStepId
                    continue
                } elseif ($depResult.Status -eq [StepStatus]::Success -or
                          $depResult.Status -eq [StepStatus]::Skipped) {
                    # 本次会话内成功 → 通过
                    continue
                }
            }

            # 实时检测依赖是否真的已安装
            $depStepConfig = $script:StepRegistry | Where-Object { $_.StepId -eq $depStepId } | Select-Object -First 1
            if ($depStepConfig) {
                try {
                    # 静默调用 TestFunction，抑制所有输出流（移除 *>&1 避免 WarningRecord/ErrorRecord 污染）
                    $depTestResult = & $depStepConfig.TestFunction 2>$null 3>$null 4>$null 5>$null 6>$null

                    $depInstalled = Resolve-TestResultBool -TestResult $depTestResult -PropertyName "IsInstalled"

                    if (-not $depInstalled) {
                        $result.CanExecute = $false
                        $result.MissingDependencies += $depStepId
                    }
                } catch {
                    # 检测失败视为未安装
                    $result.CanExecute = $false
                    $result.MissingDependencies += $depStepId
                }
            } else {
                # 找不到依赖配置 → 视为未满足
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

    # 使用 , 操作符防止 PowerShell 自动解包单元素数组
    # 这确保即使只有一个元素，返回值仍然是数组类型
    return ,$ordered
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用
