# 管理员权限管理 - CCQ
# 功能: 管理员检测、自提权、步骤权限断言

#Requires -Version 5.1

Set-StrictMode -Version Latest

function Test-IsAdministrator {
    <#
    .SYNOPSIS
    检测当前进程是否以管理员权限运行
    .RETURNS
    布尔值
    #>
    param()

    try {
        $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Invoke-SelfElevated {
    <#
    .SYNOPSIS
    以管理员身份重新启动当前脚本
    .PARAMETER ScriptPath
    要重新运行的脚本路径（默认 $PSCommandPath）
    .PARAMETER ArgumentList
    传递给重新运行脚本的额外参数
    .DESCRIPTION
    通过 Start-Process pwsh/powershell -Verb RunAs 实现提权。
    提权后原进程退出，新进程继承 ScriptPath + ArgumentList。
    #>
    param(
        [string]$ScriptPath = $PSCommandPath,

        [string[]]$ArgumentList = @()
    )

    if (Test-IsAdministrator) {
        Write-Host "当前已是管理员，无需提权" -ForegroundColor Gray
        return $true
    }

    Write-Host "此步骤需要管理员权限，正在请求提权..." -ForegroundColor Yellow

    # 构造传递给提权进程的参数
    $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptPath`"")

    foreach ($a in $ArgumentList) {
        $args += $a
    }

    # 优先使用 pwsh（PS7），回退到 powershell（PS5）
    $shell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }

    try {
        Start-Process $shell -ArgumentList $args -Verb RunAs -Wait:$false
        Write-Host "已启动提权进程，当前窗口将退出" -ForegroundColor Cyan
        exit 0
    } catch {
        # 用户拒绝了 UAC 提示
        if ($_.Exception.Message -match "The operation was canceled by the user|用户取消") {
            Write-Host "⚠ 用户取消了提权请求" -ForegroundColor Yellow
        } else {
            Write-Host "✗ 提权失败: $($_.Exception.Message)" -ForegroundColor Red
        }
        return $false
    }
}

function Assert-StepPrivilege {
    <#
    .SYNOPSIS
    断言某步骤所需权限，不足时引导提权或优雅降级
    .PARAMETER StepName
    步骤显示名称
    .PARAMETER RequiresAdmin
    是否必须管理员（$true = 硬性要求，$false = 软性建议）
    .PARAMETER ScriptPath
    提权时重新运行的脚本路径
    .RETURNS
    $true  = 权限满足，可继续
    $false = 权限不足且用户选择跳过
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$StepName,

        [bool]$RequiresAdmin = $true,

        [string]$ScriptPath = $PSCommandPath
    )

    if (Test-IsAdministrator) {
        return $true
    }

    if ($RequiresAdmin) {
        Write-Host "⚠ 步骤 [$StepName] 需要管理员权限" -ForegroundColor Yellow
        Write-Host "  是否以管理员身份重新启动？[Y/n] " -NoNewline -ForegroundColor Cyan

        $key = Read-Host
        if ($key -match "^[Yy]?$") {
            # 用户同意提权：重启脚本，当前进程退出
            $elevated = Invoke-SelfElevated -ScriptPath $ScriptPath
            # Invoke-SelfElevated 成功时已 exit 0；走到这里说明提权失败
            if (-not $elevated) {
                Write-Host "✗ 无法获取管理员权限，步骤 [$StepName] 已跳过" -ForegroundColor Red
                return $false
            }
        } else {
            Write-Host "⚠ 用户跳过步骤 [$StepName]（需要管理员权限）" -ForegroundColor Yellow
            return $false
        }
    } else {
        # 软性建议：给出提示但允许继续
        Write-Host "ℹ 步骤 [$StepName] 建议以管理员身份运行以获得最佳效果" -ForegroundColor Gray
        return $true
    }

    return $true
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用
