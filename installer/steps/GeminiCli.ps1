# Gemini CLI 安装步骤 - CCQ
# 作者: 哈雷酱 (本小姐的专业 CLI 管理！)
# 功能: Gemini CLI npm 全局安装

#Requires -Version 5.1

# 严格模式
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 导入依赖模块
. "$PSScriptRoot\..\core\Ui.ps1"
. "$PSScriptRoot\..\core\Process.ps1"

function Test-GeminiCliInstalled {
    <#
    .SYNOPSIS
    检测 Gemini CLI 是否已安装
    .RETURNS
    包含 IsInstalled 字段的结果对象
    #>

    return Test-CliToolInstalled -Command "gemini" -DisplayName "Gemini CLI"
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
        Write-UiInfo "安装 Gemini CLI..."

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
        Write-UiInfo "正在通过 npm 全局安装 Gemini CLI..."
        $installOut = Invoke-NpmGlobalInstall -PackageName "@google/gemini-cli"

        if (-not $installOut.Success) {
            throw "安装失败: $($installOut.Error)"
        }

        # 刷新 PATH
        Write-UiInfo "刷新环境变量..."
        Refresh-SessionPath

        # 验证安装
        Start-Sleep -Seconds 2
        $geminiDetails = Test-CommandAvailable -Command "gemini" -ReturnDetails
        if (-not $geminiDetails.Available) {
            $errorMsg = "安装后 gemini 命令仍不可用"
            if ($geminiDetails.ResolvedPath) {
                $errorMsg += "`n  解析路径: $($geminiDetails.ResolvedPath)"
            }
            if ($geminiDetails.ErrorMessage) {
                $errorMsg += "`n  错误详情: $($geminiDetails.ErrorMessage)"
            }
            $errorMsg += "`n  建议: 请重新启动 PowerShell 后重试"
            throw $errorMsg
        }

        $version = Get-CommandVersion -Command "gemini"
        Write-UiSuccess "✓ Gemini CLI 安装成功"
        Write-UiInfo "版本: $version"
        Write-UiInfo "命令: gemini --help"

        $result.Success          = $true
        $result.Data["Version"] = $version
    }
    catch {
        $result.ErrorMessage = "安装 Gemini CLI 失败: $($_.Exception.Message)"
        Write-UiError $result.ErrorMessage
    }

    return $result
}

function Verify-GeminiCli {
    <#
    .SYNOPSIS
    验证 Gemini CLI 安装
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
        if (-not (Test-CommandAvailable -Command "gemini")) {
            throw "gemini 命令不可用"
        }

        # 验证版本信息
        $version = Get-CommandVersion -Command "gemini"
        if ([string]::IsNullOrWhiteSpace($version)) {
            throw "无法获取 gemini 版本信息"
        }

        # 验证帮助信息
        $helpResult = Invoke-ExternalCommand -Command "gemini" -Arguments @("--help") -SuppressOutput
        if ($helpResult.ExitCode -ne 0) {
            throw "gemini --help 执行失败"
        }

        Write-UiSuccess "✓ Gemini CLI 验证通过"
        Write-UiInfo "  - 命令可用性: ✓"
        Write-UiInfo "  - 版本信息: $version"
        Write-UiInfo "  - 帮助信息: ✓"

        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = "验证 Gemini CLI 失败: $($_.Exception.Message)"
        Write-UiError $result.ErrorMessage
    }

    return $result
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用
