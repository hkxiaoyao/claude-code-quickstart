# Gemini CLI 安装步骤 - CCQ
# 作者: 哈雷酱 (本小姐的专业 CLI 管理！)
# 功能: Gemini CLI npm 全局安装

#Requires -Version 5.1

# 严格模式
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 依赖: Ui.ps1, Process.ps1（由入口脚本 dot-source 加载）

function Get-GeminiCliVersionFromNpm {
    <#
    .SYNOPSIS
    通过 npm list 获取 Gemini CLI 版本（避免执行 gemini 命令）
    .DESCRIPTION
    fnm multishell 环境下 gemini.ps1 wrapper 在子进程中可能挂起，
    因此不通过执行命令获取版本，而是通过 npm list 查询。
    .RETURNS
    版本字符串，未安装时返回空字符串
    #>
    try {
        $npmResult = Invoke-ExternalCommand -Command "npm" `
            -Arguments @("list", "-g", "@google/gemini-cli", "--depth=0") `
            -SuppressOutput -TimeoutSeconds 30 -RetryCount 0
        if ($npmResult.Success -and $npmResult.Output -match '@google/gemini-cli@(\S+)') {
            return $matches[1]
        }
    } catch {
        # npm list 失败，返回空
    }
    return ""
}

function Get-GeminiCliVersionFromCommand {
    <#
    .SYNOPSIS
    通过 gemini --version 获取 Gemini CLI 版本（fallback）
    .DESCRIPTION
    仅在 npm list 无法获取版本时调用。首次执行 gemini 可能需要下载依赖，极慢。
    超时或失败时返回空字符串，不抛异常。
    .RETURNS
    版本字符串，超时/失败/未安装时返回空字符串
    #>
    try {
        if (-not (Test-CommandAvailable -Command "gemini")) {
            return ""
        }
        Write-UiInfo "npm 全局列表检测失败，尝试命令行检测（首次可能需要 1-2 分钟）..." -Level Detail
        $cmdResult = Invoke-ExternalCommand -Command "gemini" `
            -Arguments @("--version") `
            -SuppressOutput -TimeoutSeconds 120 -RetryCount 0
        if ($cmdResult.Success -and $cmdResult.Output -match '(\d+\.\d+\.\d+)') {
            return $matches[1]
        }
    } catch {
        # gemini --version 超时或失败，静默返回空
    }
    return ""
}

function Resolve-GeminiCliVersion {
    <#
    .SYNOPSIS
    统一解析 Gemini CLI 版本
    .DESCRIPTION
    优先使用 npm list 快速查询；失败时 fallback 到 gemini --version。
    .RETURNS
    版本字符串，无法获取时返回空字符串
    #>
    $ver = Get-GeminiCliVersionFromNpm
    if (-not [string]::IsNullOrWhiteSpace($ver)) {
        return $ver
    }
    return Get-GeminiCliVersionFromCommand
}

function Test-GeminiCliInstalled {
    <#
    .SYNOPSIS
    检测 Gemini CLI 是否已安装
    .DESCRIPTION
    优先通过 npm list 检测（快速），失败时 fallback 到 gemini --version（首次可能需 1-2 分钟）。
    .RETURNS
    标准检测结果 hashtable（IsInstalled, Version, Data, Message）
    #>

    return Invoke-UnifiedCheck -StepId "GeminiCli" -DisplayName "Gemini CLI" -CustomVerify {
        $ver = Resolve-GeminiCliVersion
        if (-not [string]::IsNullOrWhiteSpace($ver)) {
            return $ver
        }
        return $false
    } -UseCache
}

function Install-GeminiCli {
    <#
    .SYNOPSIS
    安装 Gemini CLI
    .RETURNS
    包含 Success 字段的结果对象
    #>

    $result = @{
        Success      = $false
        ErrorMessage = ""
        Data         = @{}
    }

    try {
        Write-UiPrimary "安装 Gemini CLI..." -Level Detail

        # 检查 Node.js 是否可用
        $npmDetails = Test-CommandAvailable -Command "npm" -ReturnDetails
        if (-not $npmDetails.Available) {
            $errorMsg = "npm 不可用，请先安装 Node.js"
            if ($npmDetails.ResolvedPath) {
                $errorMsg += "`n  解析路径: $($npmDetails.ResolvedPath)"
            }
            if ($npmDetails.ErrorMessage) {
                $errorMsg += "`n  错误详情: $($npmDetails.ErrorMessage)"
            }
            throw $errorMsg
        }

        # 全局安装 Gemini CLI（HC-2: 无 -DisplayName 参数）
        Write-UiPrimary "正在通过 npm 全局安装 Gemini CLI..." -Level Detail
        $installOut = Invoke-NpmGlobalInstall -PackageName "@google/gemini-cli"

        if (-not $installOut.Success) {
            throw "安装失败: $($installOut.Error)"
        }

        # 刷新 PATH
        Write-UiPrimary "刷新环境变量..." -Level Detail
        Refresh-SessionPath

        # 验证安装（优先 npm list，失败时 fallback 到 gemini --version）
        Start-Sleep -Seconds 2
        $version = Resolve-GeminiCliVersion
        if ([string]::IsNullOrWhiteSpace($version)) {
            throw "安装后未检测到 Gemini CLI，请重新启动 PowerShell 后重试"
        }

        Write-UiSuccess "✓ Gemini CLI 安装成功" -Level Detail
        Write-UiInfo "版本: $version" -Level Detail
        Write-UiInfo "命令: gemini --help" -Level Detail

        $result.Success          = $true
        $result.Data["Version"] = $version
    }
    catch {
        $result.ErrorMessage = "安装 Gemini CLI 失败: $($_.Exception.Message)"
        Write-UiDanger $result.ErrorMessage
    }

    return $result
}

function Verify-GeminiCli {
    <#
    .SYNOPSIS
    验证 Gemini CLI 安装
    .DESCRIPTION
    通过 npm list + Get-Command 验证，不执行 gemini 命令本身。
    .RETURNS
    包含 Success 字段的结果对象
    #>

    $result = @{
        Success      = $false
        ErrorMessage = ""
        Data         = @{}
    }

    try {
        # 验证版本信息可获取
        $version = Resolve-GeminiCliVersion
        if ([string]::IsNullOrWhiteSpace($version)) {
            throw "未检测到 Gemini CLI 版本信息"
        }

        # 验证命令可解析（仅检查路径，不执行）
        $cmdInfo = Get-Command "gemini" -ErrorAction SilentlyContinue
        $cmdResolved = if ($cmdInfo) { "✓ ($($cmdInfo.Source))" } else { "- (PATH 未就绪，重启 Shell 后可用)" }

        Write-UiSuccess "✓ Gemini CLI 验证通过" -Level Detail
        Write-UiInfo "  - npm 包状态: ✓" -Level Detail
        Write-UiInfo "  - 版本信息: $version" -Level Detail
        Write-UiInfo "  - 命令解析: $cmdResolved" -Level Detail

        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = "验证 Gemini CLI 失败: $($_.Exception.Message)"
        Write-UiDanger $result.ErrorMessage
    }

    return $result
}

function Update-GeminiCli {
    <#
    .SYNOPSIS
    更新 Gemini CLI 到最新版本
    .RETURNS
    @{ Success; ErrorMessage; Data; UpdatedItems }
    #>

    $result = @{
        Success      = $false
        ErrorMessage = ""
        Data         = @{}
        UpdatedItems = @()
    }

    try {
        Write-UiPrimary "更新 Gemini CLI..." -Level Detail

        # 获取当前版本（优先 npm list，失败时 fallback 到 gemini --version）
        $oldVersion = Resolve-GeminiCliVersion
        if ([string]::IsNullOrWhiteSpace($oldVersion)) {
            throw "无法获取当前 Gemini CLI 版本，请确认已安装"
        }
        Write-UiInfo "当前版本: $oldVersion" -Level Detail

        # 检测是否有新版本（使用 npm outdated -g 批量缓存）
        $updateCheck = Test-NpmUpdateAvailable -PackageName "@google/gemini-cli" -CurrentVersion $oldVersion
        if ($updateCheck.LatestVersion) {
            Write-UiInfo "最新版本: $($updateCheck.LatestVersion)" -Level Detail
        }
        if ($updateCheck.Available -eq $false) {
            Write-UiDim "Gemini CLI 已是最新版本 ($oldVersion)" -Level Debug
            $result.UpdatedItems = @("noop::GeminiCli::no-change")
            $result.Data["OldVersion"] = $oldVersion
            $result.Data["NewVersion"] = $oldVersion
            $result.Success = $true
            return $result
        }

        # 执行 npm install -g @latest
        $installSuccess = $false
        $lastError = ""
        for ($attempt = 0; $attempt -lt 3; $attempt++) {
            if ($attempt -gt 0) {
                $waitSec = [math]::Pow(2, $attempt)
                Write-UiDim "等待 ${waitSec}s 后重试 (第 $($attempt + 1) 次)..." -Level Debug
                Start-Sleep -Seconds $waitSec
            }
            $installResult = Invoke-ExternalCommand -Command "npm" `
                -Arguments @("install", "-g", "@google/gemini-cli@latest") `
                -TimeoutSeconds 300 -SuppressOutput -RetryCount 0
            if ($installResult.ExitCode -eq 0) {
                $installSuccess = $true
                break
            }
            $lastError = $installResult.Error
        }

        if (-not $installSuccess) {
            Write-UiWarning "更新失败，尝试回退到 $oldVersion..."
            Invoke-ExternalCommand -Command "npm" `
                -Arguments @("install", "-g", "@google/gemini-cli@$oldVersion") `
                -TimeoutSeconds 300 -SuppressOutput -RetryCount 0 | Out-Null
            throw "npm install @latest 失败 (已尝试 3 次): $lastError"
        }

        Refresh-SessionPath

        $newVersion = Resolve-GeminiCliVersion
        $result.Data["OldVersion"] = $oldVersion
        $result.Data["NewVersion"] = $newVersion

        if ($oldVersion -eq $newVersion) {
            $result.UpdatedItems = @("noop::GeminiCli::no-change")
            Write-UiDim "Gemini CLI 已是最新版本 ($newVersion)" -Level Debug
        } else {
            $result.UpdatedItems = @("npm::gemini-cli::${oldVersion}->${newVersion}")
            Write-UiSuccess "✓ Gemini CLI 已更新: $oldVersion -> $newVersion" -Level Detail
        }

        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = "更新 Gemini CLI 失败: $($_.Exception.Message)"
        Write-UiDanger $result.ErrorMessage
    }

    return $result
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用
