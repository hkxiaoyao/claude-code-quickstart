# 步骤契约和状态模型 - Claude Code 环境安装器
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
                $stepResult.Data = $stepData.Data
                $stepResult.StartTime = [datetime]$stepData.StartTime
                $stepResult.EndTime = [datetime]$stepData.EndTime
                $stepResult.ErrorDetails = $stepData.ErrorDetails

                $state.StepResults[$stepId] = $stepResult
            }

            # 重建全局数据
            if ($stateData.GlobalData) {
                $state.GlobalData = $stateData.GlobalData
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
    执行步骤生命周期（Test -> Install -> Verify -> Rollback on failure）
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
    .PARAMETER RollbackFunction
    回滚函数名（可选）
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

        [string]$RollbackFunction,

        [Parameter(Mandatory = $true)]
        [InstallState]$State,

        [switch]$SkipIfInstalled
    )

    Write-Host "🔄 执行步骤: $StepName" -ForegroundColor Cyan

    # 创建或获取步骤结果
    if ($State.StepResults.ContainsKey($StepId)) {
        $stepResult = $State.StepResults[$StepId]
    } else {
        $stepResult = [StepResult]::new($StepId, $StepName)
        $State.StepResults[$StepId] = $stepResult
    }

    # 如果步骤已成功完成且允许跳过，则跳过
    if ($SkipIfInstalled -and $stepResult.Status -eq [StepStatus]::Success) {
        Write-Host "⏭ 步骤已完成，跳过: $StepName" -ForegroundColor Green
        return $stepResult
    }

    try {
        $stepResult.Status = [StepStatus]::Running
        $stepResult.StartTime = Get-Date
        $State.CurrentStep = $StepId

        # 保存状态
        Save-InstallState -State $State

        # 1. 执行测试阶段
        Write-Host "  🔍 测试阶段: $TestFunction" -ForegroundColor Gray
        $testResult = & $TestFunction

        # 兼容 bool 和 hashtable 两种返回类型
        $isInstalled = if ($testResult -is [bool]) { $testResult } elseif ($testResult) { [bool]$testResult.IsInstalled } else { $false }
        if ($isInstalled -and $SkipIfInstalled) {
            $stepResult.Status = [StepStatus]::Skipped
            $stepResult.Message = "组件已安装，跳过安装"
            $stepResult.EndTime = Get-Date
            Write-Host "  ✓ 组件已安装，跳过" -ForegroundColor Yellow
            return $stepResult
        }

        # 2. 执行安装阶段
        Write-Host "  🔧 安装阶段: $InstallFunction" -ForegroundColor Gray
        $installResult = & $InstallFunction

        # 兼容 bool 和 hashtable 两种返回类型
        $installSuccess = if ($installResult -is [bool]) { $installResult } elseif ($installResult) { [bool]$installResult.Success } else { $false }
        if (-not $installSuccess) {
            $installError = if ($installResult -is [bool]) { "安装函数返回失败" } elseif ($installResult -and $installResult.ErrorMessage) { $installResult.ErrorMessage } else { "未知错误" }
            throw "安装阶段失败: $installError"
        }

        # 3. 执行验证阶段（如果提供）
        if ($VerifyFunction) {
            Write-Host "  ✅ 验证阶段: $VerifyFunction" -ForegroundColor Gray
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

        # 合并结果数据
        if ($testResult -and $testResult.Data) {
            foreach ($key in $testResult.Data.Keys) {
                $stepResult.Data[$key] = $testResult.Data[$key]
            }
        }
        if ($installResult -and $installResult.Data) {
            foreach ($key in $installResult.Data.Keys) {
                $stepResult.Data[$key] = $installResult.Data[$key]
            }
        }

        Write-Host "  ✓ $StepName 执行成功" -ForegroundColor Green

    } catch {
        $stepResult.Status = [StepStatus]::Failed
        $stepResult.Message = "步骤执行失败"
        $stepResult.ErrorDetails = $_.Exception.Message
        $stepResult.EndTime = Get-Date

        Write-Host "  ✗ $StepName 执行失败: $($_.Exception.Message)" -ForegroundColor Red

        # 尝试回滚（如果提供回滚函数）
        if ($RollbackFunction) {
            try {
                Write-Host "  🔄 执行回滚: $RollbackFunction" -ForegroundColor Yellow
                $rollbackResult = & $RollbackFunction
                # 兼容 bool 和 hashtable 两种返回类型
                $rollbackSuccess = if ($rollbackResult -is [bool]) { $rollbackResult } elseif ($rollbackResult) { [bool]$rollbackResult.Success } else { $false }
                if ($rollbackSuccess) {
                    Write-Host "  ✓ 回滚成功" -ForegroundColor Green
                } else {
                    $rollbackError = if ($rollbackResult -is [bool]) { "回滚函数返回失败" } elseif ($rollbackResult -and $rollbackResult.ErrorMessage) { $rollbackResult.ErrorMessage } else { "未知错误" }
                    Write-Host "  ⚠ 回滚失败: $rollbackError" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "  ⚠ 回滚过程中发生错误: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    } finally {
        # 保存状态
        Save-InstallState -State $State
    }

    return $stepResult
}

function Get-StepDependencies {
    <#
    .SYNOPSIS
    获取步骤依赖关系定义
    .RETURNS
    步骤依赖关系哈希表
    #>
    param()

    return @{
        "Step01.Proxy" = @()
        "Step02.NodeFnm" = @("Step01.Proxy")
        "Step03.Git" = @("Step01.Proxy")
        "Step04.ClaudeCode" = @("Step02.NodeFnm")
        "Step05.Ccline" = @("Step04.ClaudeCode")
        "Step06.CcSwitch" = @("Step04.ClaudeCode")
        "Step07.ApiKey" = @("Step04.ClaudeCode")
        "Step08.ClaudeConfig" = @("Step07.ApiKey")
        "Step09.ClaudeMd" = @("Step08.ClaudeConfig")
        "Step10.Mcp" = @("Step08.ClaudeConfig")
        "Step11.CcgWorkflow" = @("Step03.Git", "Step08.ClaudeConfig")
        "Step12.CodexCli" = @("Step02.NodeFnm")
        "Step13.GeminiCli" = @("Step02.NodeFnm")
    }
}

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
                } elseif ($depResult.Status -ne [StepStatus]::Success) {
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
    根据依赖关系计算步骤执行顺序
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

    # 拓扑排序
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

        # 按字母顺序排序同级步骤
        $canExecute = $canExecute | Sort-Object
        $ordered += $canExecute

        # 从剩余列表中移除
        $remaining = $remaining | Where-Object { $_ -notin $canExecute }
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
        $completedSteps = ($state.StepResults.Values | Where-Object { $_.Status -eq [StepStatus]::Success }).Count
        $failedSteps = ($state.StepResults.Values | Where-Object { $_.Status -eq [StepStatus]::Failed }).Count
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