# _NpmToolCommon.ps1 - Windows npm 工具步骤公共辅助
# 作者: 哈雷酱 (对齐 macOS _NpmToolCommon.zsh 功能！)
# 功能: npm 包检测、安装、更新与结果格式化

#Requires -Version 7.0

# 严格模式
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================
# 前置检查
# ============================================================

function Test-NpmAvailable {
    <#
    .SYNOPSIS
    检查 npm 命令是否可用
    .RETURNS
    bool
    #>
    Refresh-SessionPath
    return (Test-CommandAvailable -Command 'npm')
}

function Test-NpxAvailable {
    <#
    .SYNOPSIS
    检查 npx 命令是否可用
    .RETURNS
    bool
    #>
    Refresh-SessionPath
    return (Test-CommandAvailable -Command 'npx')
}

# ============================================================
# 版本检测
# ============================================================

function Get-NpmToolVersionFromCommand {
    <#
    .SYNOPSIS
    通过命令 --version 获取版本号
    .PARAMETER CommandName
    命令名称（如 claude、ccline）
    .RETURNS
    string - 版本号，失败返回空字符串
    #>
    param(
        [Parameter(Mandatory)]
        [string]$CommandName
    )

    if (-not (Test-CommandAvailable -Command $CommandName)) {
        return ""
    }

    try {
        $versionResult = Invoke-ExternalCommand `
            -Command $CommandName `
            -Arguments @("--version") `
            -TimeoutSeconds 10 `
            -RetryCount 0 `
            -SuppressOutput

        if ($versionResult.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($versionResult.Output)) {
            return $versionResult.Output.Trim().Split("`n")[0].Trim()
        }
    } catch {
        # 静默失败
    }

    return ""
}

function Get-NpmToolVersionFromNpmList {
    <#
    .SYNOPSIS
    通过 npm list -g 获取已安装包的版本号
    .PARAMETER PackageName
    npm 包名（如 @anthropic-ai/claude-code）
    .RETURNS
    string - 版本号，失败返回空字符串
    #>
    param(
        [Parameter(Mandatory)]
        [string]$PackageName
    )

    if (-not (Test-NpmAvailable)) {
        return ""
    }

    try {
        $listResult = Invoke-ExternalCommand `
            -Command 'npm' `
            -Arguments @('list', '-g', $PackageName, '--depth=0') `
            -TimeoutSeconds 30 `
            -RetryCount 0 `
            -SuppressOutput

        if ($listResult.ExitCode -eq 0) {
            # 匹配 "package-name@version" 格式
            $pattern = [regex]::Escape($PackageName) + '@([\d\.\-\w]+)'
            if ($listResult.Output -match $pattern) {
                return $matches[1]
            }
        }
    } catch {
        # 静默失败
    }

    return ""
}

# ============================================================
# 安装与更新
# ============================================================

function Test-NpmToolCommandInstalled {
    <#
    .SYNOPSIS
    检测命令是否已安装且可执行
    .PARAMETER CommandName
    命令名称
    .RETURNS
    bool
    #>
    param(
        [Parameter(Mandatory)]
        [string]$CommandName
    )

    Refresh-SessionPath

    if (-not (Test-CommandAvailable -Command $CommandName)) {
        return $false
    }

    # 尝试执行 --version 或 --help 验证命令可用
    try {
        $versionCheck = Invoke-ExternalCommand `
            -Command $CommandName `
            -Arguments @("--version") `
            -TimeoutSeconds 10 `
            -RetryCount 0 `
            -SuppressOutput

        if ($versionCheck.ExitCode -eq 0) {
            return $true
        }

        # --version 失败时尝试 --help
        $helpCheck = Invoke-ExternalCommand `
            -Command $CommandName `
            -Arguments @("--help") `
            -TimeoutSeconds 10 `
            -RetryCount 0 `
            -SuppressOutput

        return ($helpCheck.ExitCode -eq 0)
    } catch {
        return $false
    }
}

function Invoke-NpmToolInstallLatest {
    <#
    .SYNOPSIS
    全局安装 npm 包的最新版本（含重试 + 缓存清理）
    .PARAMETER PackageName
    npm 包名
    .RETURNS
    hashtable - @{Success; ErrorMessage}
    #>
    param(
        [Parameter(Mandatory)]
        [string]$PackageName
    )

    $result = @{ Success = $false; ErrorMessage = "" }

    if (-not (Test-NpmAvailable)) {
        $result.ErrorMessage = "npm 不可用，请先完成 NodeJS 步骤"
        return $result
    }

    try {
        Write-UiPrimary "通过 npm 安装 $PackageName ..." -Level Detail

        $installResult = Invoke-ExternalCommand `
            -Command 'npm' `
            -Arguments @('install', '-g', "${PackageName}@latest") `
            -TimeoutSeconds 300 `
            -RetryCount 3

        if ($installResult.ExitCode -eq 0) {
            Refresh-SessionPath
            $result.Success = $true
            return $result
        }

        # 首次失败，清理缓存后重试
        Write-UiWarning "首次安装失败，清理 npm 缓存后重试..." -Level Detail

        $cacheCleanResult = Invoke-ExternalCommand `
            -Command 'npm' `
            -Arguments @('cache', 'clean', '--force') `
            -TimeoutSeconds 60 `
            -RetryCount 0 `
            -SuppressOutput

        $retryResult = Invoke-ExternalCommand `
            -Command 'npm' `
            -Arguments @('install', '-g', "${PackageName}@latest") `
            -TimeoutSeconds 300 `
            -RetryCount 3

        if ($retryResult.ExitCode -eq 0) {
            Refresh-SessionPath
            $result.Success = $true
            return $result
        }

        $result.ErrorMessage = "npm 全局安装失败: $PackageName`n$($retryResult.Error)"
    } catch {
        $result.ErrorMessage = "安装过程异常: $($_.Exception.Message)"
    }

    return $result
}

function Test-NpmPackageHasUpdate {
    <#
    .SYNOPSIS
    检查 npm 包是否有可用更新
    .PARAMETER PackageName
    npm 包名
    .RETURNS
    bool - $true 有更新，$false 无更新或检测失败
    #>
    param(
        [Parameter(Mandatory)]
        [string]$PackageName
    )

    if (-not (Test-NpmAvailable)) {
        return $false
    }

    try {
        $outdatedResult = Invoke-ExternalCommand `
            -Command 'npm' `
            -Arguments @('outdated', '-g', '--json') `
            -TimeoutSeconds 60 `
            -RetryCount 0 `
            -SuppressOutput

        if ($outdatedResult.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($outdatedResult.Output)) {
            $outdatedObj = $outdatedResult.Output | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
            if ($outdatedObj -and $outdatedObj.ContainsKey($PackageName)) {
                return $true
            }
        }
    } catch {
        # 静默失败
    }

    return $false
}
