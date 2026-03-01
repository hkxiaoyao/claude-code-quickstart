# Python.ps1 - Python 安装和配置
# 作者: 哈雷酱 (本小姐的 Python 自动化！)
# 功能: 安装 Python 3.12+ 并配置基础环境 (UTF-8 增强)

#Requires -Version 5.1

# 严格模式
Set-StrictMode -Version Latest

# 导入依赖模块
$scriptRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$scriptRoot\core\Process.ps1"
. "$scriptRoot\core\Ui.ps1"
. "$scriptRoot\core\Profile.ps1"

# 全局配置
$script:MinPythonVersion = [Version]"3.10.0"

function Test-PythonInstalled {
    <#
    .SYNOPSIS
    测试 Python 是否已安装
    #>
    $result = @{
        IsInstalled = $false
        Version     = ""
        Data        = @{}
        Message     = ""
    }

    try {
        Write-UiInfo "🔍 检查 Python 安装状态..."

        # 检查 python 是否可用
        $pythonAvailable = Test-CommandAvailable -Command "python"
        $result.Data["PythonAvailable"] = $pythonAvailable

        if ($pythonAvailable) {
            $versionText = Get-CommandVersion -Command "python"
            $result.Data["PythonVersionText"] = $versionText

            # 提取版本号 (如 "Python 3.12.2")
            $versionMatch = [regex]::Match($versionText, '\d+\.\d+(\.\d+)?')
            if ($versionMatch.Success) {
                $versionStr = $versionMatch.Value
                if ($versionStr -notmatch '\.\d+\.\d+') { $versionStr += ".0" } # 补齐为 x.y.z
                
                try {
                    $currentVersion = [Version]$versionStr
                    $result.Version = $versionStr

                    if ($currentVersion -ge $script:MinPythonVersion) {
                        $result.IsInstalled = $true
                        $result.Message = "Python 已安装 (版本: $versionText)"
                        Write-UiSuccess "✓ $result.Message"
                    } else {
                        $result.Message = "Python 版本过低 (当前: $versionText, 需要: $script:MinPythonVersion+)"
                        Write-UiWarn "⚠ $result.Message"
                    }
                } catch {
                    Write-UiWarn "⚠ 无法解析 Python 版本号: $versionStr"
                    $result.Version = $versionStr
                }
            }
        } else {
            Write-UiWarn "⚠ Python 未安装"
            $result.Message = "Python 未安装"
        }

        # 检查环境变量配置 (哨兵)
        if ($result.IsInstalled) {
            $profilePath = $PROFILE
            if (Test-Path $profilePath) {
                $content = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
                if ($content -and $content.Contains("# >>> Claude Code Quickstart >>>") -and $content.Contains("PYTHONUTF8")) {
                    Write-UiSuccess "✓ Python 环境变量已在 Profile 中配置"
                } else {
                    $result.IsInstalled = $false
                    $result.Message = "Python 环境已安装但配置不完整"
                }
            } else {
                $result.IsInstalled = $false
                $result.Message = "PowerShell Profile 未配置"
            }
        }

    } catch {
        $result.Message = "Python 状态检查失败: $($_.Exception.Message)"
        Write-UiWarn "⚠ $($result.Message)"
    }

    return $result
}

function Install-Python {
    <#
    .SYNOPSIS
    执行 Python 安装和配置
    #>
    $result = @{
        Success      = $false
        Data         = @{}
        ErrorMessage = ""
    }

    try {
        Write-UiInfo "📦 开始安装 Python 3.12..."

        $needsInstall = $true
        if (Test-CommandAvailable -Command "python") {
            $testResult = Test-PythonInstalled
            if ($testResult.IsInstalled) {
                Write-UiSuccess "✓ Python 已安装且配置完整，跳过安装"
                $needsInstall = $false
            }
        }

        if ($needsInstall) {
            if (Test-CommandAvailable -Command "winget") {
                Write-UiInfo "使用 winget 安装 Python.Python.3.12..."
                $installOut = Invoke-WingetInstall -PackageId "Python.Python.3.12" -PackageName "Python 3.12" -Silent -AcceptLicense
                if (-not $installOut.Success) {
                    throw "winget 安装 Python 失败: $($installOut.ErrorMessage)"
                }
                Write-UiSuccess "✓ Python 安装成功"
            } else {
                throw "winget 不可用，无法自动安装 Python。请访问 https://www.python.org/ 手动安装。"
            }

            # 刷新 PATH
            Refresh-SessionPath

            if (-not (Test-CommandAvailable -Command "python")) {
                throw "Python 安装后仍无法在当前会话中找到，可能需要重新启动终端"
            }
        }

        # 配置环境变量 (PowerShell Profile)
        Write-UiInfo "⚙️ 配置 Python UTF-8 增强环境..."
        $profilePath = $PROFILE
        $pythonConfig = @(
            "# Python UTF-8 增强配置",
            "`$env:PYTHONUTF8 = 1",
            "`$env:PYTHONIOENCODING = 'utf-8'"
        )

        $success = Set-ManagedBlockInFile -FilePath $profilePath -Content $pythonConfig -CreateIfNotExists -AppendIfNoBlock
        if ($success) {
            Write-UiSuccess "✓ Python UTF-8 配置已应用到 PowerShell Profile"
        } else {
            Write-UiWarn "⚠ Profile 配置写入失败"
        }

        $result.Success = $true
        Write-UiSuccess "✅ Python 步骤处理完成"

    } catch {
        $result.ErrorMessage = "Python 安装失败: $($_.Exception.Message)"
        Write-UiError $result.ErrorMessage
    }

    return $result
}

function Verify-Python {
    <#
    .SYNOPSIS
    验证 Python 安装
    #>
    $result = @{ Success = $false; ErrorMessage = "" }

    try {
        if (-not (Test-CommandAvailable -Command "python")) {
            throw "python 命令不可用"
        }

        $version = Get-CommandVersion -Command "python"
        Write-UiSuccess "✓ Python 验证通过: $version"

        # 验证 pip
        if (Test-CommandAvailable -Command "pip") {
            $pipVersion = Get-CommandVersion -Command "pip"
            Write-UiSuccess "✓ pip 验证通过: $pipVersion"
        } else {
            Write-UiWarn "⚠ pip 命令不可用，可能需要手动配置 Python Scripts 目录到 PATH"
        }

        $result.Success = $true
    } catch {
        $result.ErrorMessage = "Python 验证失败: $($_.Exception.Message)"
        Write-UiError $result.ErrorMessage
    }

    return $result
}
