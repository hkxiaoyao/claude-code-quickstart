# OpenSpec CLI 安装步骤 - CCQ
# 作者: 哈雷酱 (本小姐的专业 CLI 管理！)
# 功能: OpenSpec CLI npm 全局安装

#Requires -Version 5.1

# 严格模式
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 依赖: Ui.ps1, Process.ps1（由入口脚本 dot-source 加载）

function Test-OpenSpecInstalled {
    <#
    .SYNOPSIS
    检测 OpenSpec CLI 是否已安装
    .RETURNS
    标准检测结果 hashtable（IsInstalled, Version, Data, Message）
    #>

    return Invoke-UnifiedCheck -StepId "OpenSpec" -DisplayName "OpenSpec CLI" -Command "openspec" -UseCache
}

function Install-OpenSpec {
    <#
    .SYNOPSIS
    安装 OpenSpec CLI
    .RETURNS
    包含 Success 字段的结果对象
    #>

    $result = @{
        Success      = $false
        ErrorMessage = ""
        Data         = @{}
    }

    try {
        Write-UiPrimary "安装 OpenSpec CLI..."

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

        # 全局安装 OpenSpec CLI
        Write-UiPrimary "正在通过 npm 全局安装 OpenSpec CLI..." -Level Detail
        $installOut = Invoke-NpmGlobalInstall -PackageName "@fission-ai/openspec"

        if (-not $installOut.Success) {
            throw "安装失败: $($installOut.Error)"
        }

        # 刷新 PATH
        Write-UiPrimary "刷新环境变量..." -Level Detail
        Refresh-SessionPath

        # 验证安装
        Start-Sleep -Seconds 2
        $openspecDetails = Test-CommandAvailable -Command "openspec" -ReturnDetails
        if (-not $openspecDetails.Available) {
            $errorMsg = "安装后 openspec 命令仍不可用"
            if ($openspecDetails.ResolvedPath) {
                $errorMsg += "`n  解析路径: $($openspecDetails.ResolvedPath)"
            }
            if ($openspecDetails.ErrorMessage) {
                $errorMsg += "`n  错误详情: $($openspecDetails.ErrorMessage)"
            }
            $errorMsg += "`n  建议: 请重新启动 PowerShell 后重试"
            throw $errorMsg
        }

        $version = Get-CommandVersion -Command "openspec"
        Write-UiSuccess "✓ OpenSpec CLI 安装成功"
        Write-UiInfo "版本: $version" -Level Detail
        Write-UiInfo "命令: openspec --help" -Level Detail

        $result.Success          = $true
        $result.Data["Version"] = $version
    }
    catch {
        $result.ErrorMessage = "安装 OpenSpec CLI 失败: $($_.Exception.Message)"
        Write-UiDanger $result.ErrorMessage
    }

    return $result
}

function Verify-OpenSpec {
    <#
    .SYNOPSIS
    验证 OpenSpec CLI 安装
    .RETURNS
    包含 Success 字段的结果对象
    #>

    $result = @{
        Success      = $false
        ErrorMessage = ""
        Data         = @{}
    }

    try {
        # 验证命令可用性
        if (-not (Test-CommandAvailable -Command "openspec")) {
            throw "openspec 命令不可用"
        }

        # 验证版本信息
        $version = Get-CommandVersion -Command "openspec"
        if ([string]::IsNullOrWhiteSpace($version)) {
            throw "无法获取 openspec 版本信息"
        }

        # 验证帮助信息
        $helpResult = Invoke-ExternalCommand -Command "openspec" -Arguments @("--help") -SuppressOutput
        if ($helpResult.ExitCode -ne 0) {
            throw "openspec --help 执行失败"
        }

        Write-UiSuccess "✓ OpenSpec CLI 验证通过"
        Write-UiInfo "  - 命令可用性: ✓" -Level Detail
        Write-UiInfo "  - 版本信息: $version" -Level Detail
        Write-UiInfo "  - 帮助信息: ✓" -Level Detail

        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = "验证 OpenSpec CLI 失败: $($_.Exception.Message)"
        Write-UiDanger $result.ErrorMessage
    }

    return $result
}

function Update-OpenSpec {
    <#
    .SYNOPSIS
    更新 OpenSpec CLI 到最新版本
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
        Write-UiPrimary "更新 OpenSpec CLI..."

        # 获取当前版本
        $oldVersion = Get-CommandVersion -Command "openspec"
        if ([string]::IsNullOrWhiteSpace($oldVersion)) {
            throw "无法获取当前 OpenSpec CLI 版本，请确认已安装"
        }
        Write-UiInfo "当前版本: $oldVersion" -Level Detail

        # 检测是否有新版本（使用 npm outdated -g 批量缓存）
        $updateCheck = Test-NpmUpdateAvailable -PackageName "@fission-ai/openspec" -CurrentVersion $oldVersion
        if ($updateCheck.LatestVersion) {
            Write-UiInfo "最新版本: $($updateCheck.LatestVersion)" -Level Detail
        }
        if ($updateCheck.Available -eq $false) {
            Write-UiDim "OpenSpec CLI 已是最新版本 ($oldVersion)" -Level Debug
            $result.UpdatedItems = @("noop::OpenSpec::no-change")
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
                -Arguments @("install", "-g", "@fission-ai/openspec@latest") `
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
                -Arguments @("install", "-g", "@fission-ai/openspec@$oldVersion") `
                -TimeoutSeconds 300 -SuppressOutput -RetryCount 0 | Out-Null
            throw "npm install @latest 失败 (已尝试 3 次): $lastError"
        }

        Refresh-SessionPath

        $newVersion = Get-CommandVersion -Command "openspec"
        $result.Data["OldVersion"] = $oldVersion
        $result.Data["NewVersion"] = $newVersion

        if ($oldVersion -eq $newVersion) {
            $result.UpdatedItems = @("noop::OpenSpec::no-change")
            Write-UiDim "OpenSpec CLI 已是最新版本 ($newVersion)" -Level Debug
        } else {
            $result.UpdatedItems = @("npm::openspec-cli::${oldVersion}->${newVersion}")
            Write-UiSuccess "✓ OpenSpec CLI 已更新: $oldVersion -> $newVersion"
        }

        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = "更新 OpenSpec CLI 失败: $($_.Exception.Message)"
        Write-UiDanger $result.ErrorMessage
    }

    return $result
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用
