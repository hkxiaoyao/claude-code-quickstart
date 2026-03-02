# ClaudeCode.ps1 - Claude Code npm 全局安装
# 作者: 哈雷酱 (本小姐的 Claude Code 安装杰作！)
# 功能: 通过 npm 全局安装 Claude Code CLI 工具

#Requires -Version 5.1

# 严格模式
Set-StrictMode -Version Latest

# 导入依赖模块
$scriptRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$scriptRoot\core\Process.ps1"
. "$scriptRoot\core\Ui.ps1"

# 全局配置
$script:ClaudeCodePackage = "@anthropic-ai/claude-code"
$script:MinNodeVersion = "18"

function Test-ClaudeCodeInstalled {
    <#
    .SYNOPSIS
    检测 Claude Code 安装状态
    .RETURNS
    标准检测结果 hashtable（IsInstalled, Version, Data, Message）
    #>
    param()

    return Invoke-UnifiedCheck -StepId "ClaudeCode" -DisplayName "Claude Code" `
        -Command "claude" `
        -CustomVerify {
            # 验证 Claude Code 基本功能
            $helpResult = Invoke-ExternalCommand -Command "claude" -Arguments @("--help") -SuppressOutput -TimeoutSeconds 10
            return $helpResult.Success
        } -UseCache
}

function Install-ClaudeCode {
    <#
    .SYNOPSIS
    执行步骤 03 安装（Claude Code npm 全局安装）
    .RETURNS
    安装结果对象
    #>
    param()

    $result = @{
        Success = $false
        Data = @{}
        ErrorMessage = ""
        Message = ""
    }

    try {
        Write-UiInfo "📦 开始安装 Claude Code..."

        # 1. 验证前置条件
        Write-UiInfo "🔍 验证前置条件..."

        # 先刷新 PATH 确保能找到 node 和 npm
        Refresh-SessionPath

        # 验证 Node.js
        $nodeDetails = Test-CommandAvailable -Command "node" -ReturnDetails
        if (-not $nodeDetails.Available) {
            Write-UiError "✗ Node.js 未找到"
            if ($nodeDetails.ErrorMessage) {
                Write-UiInfo "  错误详情: $($nodeDetails.ErrorMessage)"
            }
            Write-UiInfo "💡 这可能是因为 fnm 环境变量尚未在当前会话中生效"
            Write-UiInfo "💡 请尝试以下操作之一："
            Write-UiInfo "   1. 重新启动 PowerShell 后重新运行安装器"
            Write-UiInfo "   2. 在当前窗口执行: . `$PROFILE 然后重新运行安装器"
            throw "Node.js 未安装或不可用，请先完成 NodeFnm 步骤并重新启动 PowerShell"
        }

        # 验证 npm
        $npmDetails = Test-CommandAvailable -Command "npm" -ReturnDetails
        if (-not $npmDetails.Available) {
            Write-UiError "✗ npm 未找到"
            if ($npmDetails.ResolvedPath) {
                Write-UiInfo "  解析路径: $($npmDetails.ResolvedPath)"
            }
            if ($npmDetails.ErrorMessage) {
                Write-UiInfo "  错误详情: $($npmDetails.ErrorMessage)"
            }
            throw "npm 未安装，请先完成 NodeFnm 步骤并重新启动 PowerShell"
        }

        $nodeVersion = Get-CommandVersion -Command "node"
        $versionNumber = $nodeVersion -replace '^v?(\d+)\..*$', '$1'

        if ([int]$versionNumber -lt [int]$script:MinNodeVersion) {
            throw "Node.js 版本过低 (当前: $nodeVersion, 需要: v$script:MinNodeVersion+)"
        }

        Write-UiSuccess "✓ 前置条件验证通过"
        $result.Data["NodeVersion"] = $nodeVersion

        # 2. 检查是否已安装
        if (Test-CommandAvailable -Command "claude") {
            $existingVersion = Get-CommandVersion -Command "claude"
            Write-UiInfo "检测到已安装的 Claude Code (版本: $existingVersion)"

            # 询问是否重新安装或更新
            $options = @("保持现有版本", "重新安装最新版本")
            $choice = Show-SingleSelectMenu -Title "Claude Code 已安装，选择操作：" -Options $options

            if ($choice -eq 0) {
                $result.Success = $true
                $result.Message = "保持现有 Claude Code 安装"
                $result.Data["ClaudeVersion"] = $existingVersion
                Write-UiSuccess "✓ 保持现有 Claude Code 安装"
                return $result
            } else {
                Write-UiInfo "将重新安装 Claude Code..."
            }
        }

        # 3. 使用 npm 全局安装 Claude Code
        Write-UiInfo "🚀 通过 npm 全局安装 Claude Code..."

        try {
            $installResult = Invoke-NpmGlobalInstall -PackageName $script:ClaudeCodePackage -Force
            if (-not $installResult.Success) {
                throw "npm 安装 Claude Code 失败"
            }

            Write-UiSuccess "✓ Claude Code npm 包安装成功"
            $result.Data["NpmInstallSuccess"] = $true

        } catch {
            # 如果标准安装失败，尝试其他方法
            Write-UiWarn "⚠ 标准 npm 安装失败，尝试备用方法..."

            try {
                # 尝试清理 npm 缓存后重新安装
                Write-UiInfo "清理 npm 缓存..."
                $cleanResult = Invoke-ExternalCommand -Command "npm" -Arguments @("cache", "clean", "--force") -TimeoutSeconds 60 -SuppressOutput

                if ($cleanResult.Success) {
                    Write-UiInfo "重新尝试安装..."
                    $retryResult = Invoke-ExternalCommand -Command "npm" -Arguments @("install", "-g", $script:ClaudeCodePackage, "--force") -TimeoutSeconds 300

                    if (-not $retryResult.Success) {
                        throw "重试安装失败: $($retryResult.Error)"
                    }
                } else {
                    throw "npm 缓存清理失败: $($cleanResult.Error)"
                }

            } catch {
                throw "Claude Code 安装失败: $($_.Exception.Message)"
            }
        }

        # 4. 刷新 PATH 并验证安装
        Write-UiInfo "🔄 刷新环境变量并验证安装..."

        Refresh-SessionPath

        # 等待一下让系统更新 PATH
        Start-Sleep -Seconds 2

        # 验证 claude 命令是否可用
        $claudeDetails = Test-CommandAvailable -Command "claude" -ReturnDetails
        if (-not $claudeDetails.Available) {
            # 尝试手动添加 npm 全局路径
            try {
                $npmGlobalPath = & npm config get prefix 2>$null
                if ($npmGlobalPath -and (Test-Path $npmGlobalPath)) {
                    $env:PATH = "$npmGlobalPath;$env:PATH"
                    Write-UiInfo "已手动添加 npm 全局路径到 PATH"
                }
            } catch {
                Write-UiWarn "⚠ 无法获取 npm 全局路径"
            }

            # 再次验证
            $claudeDetails = Test-CommandAvailable -Command "claude" -ReturnDetails
            if (-not $claudeDetails.Available) {
                $errorMsg = "Claude Code 安装后仍不可用"
                if ($claudeDetails.ResolvedPath) {
                    $errorMsg += "`n  解析路径: $($claudeDetails.ResolvedPath)"
                }
                if ($claudeDetails.ErrorMessage) {
                    $errorMsg += "`n  错误详情: $($claudeDetails.ErrorMessage)"
                }
                $errorMsg += "`n  建议: 请重新启动终端后重试"
                throw $errorMsg
            }
        }

        $claudeVersion = Get-CommandVersion -Command "claude"
        $result.Data["ClaudeVersion"] = $claudeVersion
        Write-UiSuccess "✓ Claude Code 验证成功 (版本: $claudeVersion)"

        # 5. 验证基本功能
        Write-UiInfo "✅ 验证 Claude Code 基本功能..."

        try {
            # 测试 --version 命令
            $versionResult = Invoke-ExternalCommand -Command "claude" -Arguments @("--version") -SuppressOutput -TimeoutSeconds 15
            if ($versionResult.Success) {
                Write-UiSuccess "✓ Claude Code 版本命令正常"
            } else {
                Write-UiWarn "⚠ Claude Code 版本命令异常，但不影响基本使用"
            }

            # 测试 --help 命令
            $helpResult = Invoke-ExternalCommand -Command "claude" -Arguments @("--help") -SuppressOutput -TimeoutSeconds 15
            if ($helpResult.Success) {
                Write-UiSuccess "✓ Claude Code 帮助命令正常"
            } else {
                Write-UiWarn "⚠ Claude Code 帮助命令异常，但不影响基本使用"
            }

        } catch {
            Write-UiWarn "⚠ Claude Code 功能验证异常: $($_.Exception.Message)"
        }

        # 安装成功
        $result.Success = $true
        $result.Message = "Claude Code 安装完成"

        Write-UiSuccess "✅ ClaudeCode 安装完成！"
        Write-UiInfo "💡 提示: Claude Code 现在可以通过 'claude' 命令使用"

    } catch {
        $result.ErrorMessage = "Claude Code 安装失败: $($_.Exception.Message)"
        Write-UiError "✗ $($result.ErrorMessage)"
    }

    return $result
}

function Verify-ClaudeCode {
    <#
    .SYNOPSIS
    验证步骤 03 执行结果
    .RETURNS
    验证结果对象
    #>
    param()

    $result = @{
        Success = $false
        Message = ""
        ErrorMessage = ""
    }

    try {
        Write-UiInfo "✅ 验证 Claude Code 安装..."

        $verificationPassed = $true
        $issues = @()

        # 验证 claude 命令可用性
        if (Test-CommandAvailable -Command "claude") {
            $claudeVersion = Get-CommandVersion -Command "claude"
            Write-UiSuccess "✓ Claude Code 命令验证通过 (版本: $claudeVersion)"
        } else {
            $verificationPassed = $false
            $issues += "claude 命令不可用"
        }

        # 验证基本命令功能
        try {
            # 测试 --version
            $versionResult = Invoke-ExternalCommand -Command "claude" -Arguments @("--version") -SuppressOutput -TimeoutSeconds 10
            if ($versionResult.Success) {
                Write-UiSuccess "✓ Claude Code --version 验证通过"
            } else {
                $issues += "claude --version 命令失败"
            }

            # 测试 --help
            $helpResult = Invoke-ExternalCommand -Command "claude" -Arguments @("--help") -SuppressOutput -TimeoutSeconds 10
            if ($helpResult.Success) {
                Write-UiSuccess "✓ Claude Code --help 验证通过"
            } else {
                $issues += "claude --help 命令失败"
            }

        } catch {
            $issues += "Claude Code 命令测试异常: $($_.Exception.Message)"
        }

        # 验证 npm 包状态
        try {
            $npmListResult = Invoke-ExternalCommand -Command "npm" -Arguments @("list", "-g", "--depth=0") -SuppressOutput -TimeoutSeconds 30 -RetryCount 0
            if ($npmListResult.Success -and $npmListResult.Output -match $script:ClaudeCodePackage) {
                Write-UiSuccess "✓ Claude Code npm 包状态验证通过"
            } else {
                $issues += "Claude Code npm 包未在全局列表中找到"
            }
        } catch {
            $issues += "npm 包状态检查异常: $($_.Exception.Message)"
        }

        if ($verificationPassed -and $issues.Count -eq 0) {
            $result.Success = $true
            $result.Message = "Claude Code 安装验证完全通过"
        } else {
            $result.Success = $false
            $result.ErrorMessage = "验证失败: $($issues -join '; ')"
            Write-UiError "✗ $($result.ErrorMessage)"
        }

    } catch {
        $result.ErrorMessage = "Claude Code 验证过程失败: $($_.Exception.Message)"
        Write-UiError "✗ $($result.ErrorMessage)"
    }

    return $result
}

function Update-ClaudeCode {
    <#
    .SYNOPSIS
    更新 Claude Code 到最新版本（npm install -g @latest + 回退）
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
        Write-UiInfo "更新 Claude Code..."

        # 获取当前版本
        $oldVersion = ""
        if (Test-CommandAvailable -Command "claude") {
            $oldVersion = Get-CommandVersion -Command "claude"
        }
        if ([string]::IsNullOrWhiteSpace($oldVersion)) {
            throw "无法获取当前 Claude Code 版本，请确认已安装"
        }
        Write-UiInfo "当前版本: $oldVersion"

        # 检测是否有新版本（使用 npm outdated -g 批量缓存）
        $updateCheck = Test-NpmUpdateAvailable -PackageName $script:ClaudeCodePackage -CurrentVersion $oldVersion
        if ($updateCheck.LatestVersion) {
            Write-UiInfo "最新版本: $($updateCheck.LatestVersion)"
        }
        if ($updateCheck.Available -eq $false) {
            Write-UiInfo "Claude Code 已是最新版本 ($oldVersion)"
            $result.UpdatedItems = @("noop::ClaudeCode::no-change")
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
                Write-UiInfo "等待 ${waitSec}s 后重试 (第 $($attempt + 1) 次)..."
                Start-Sleep -Seconds $waitSec
            }
            $installResult = Invoke-ExternalCommand -Command "npm" `
                -Arguments @("install", "-g", "$($script:ClaudeCodePackage)@latest") `
                -TimeoutSeconds 300 -SuppressOutput -RetryCount 0
            if ($installResult.ExitCode -eq 0) {
                $installSuccess = $true
                break
            }
            $lastError = $installResult.Error
        }

        if (-not $installSuccess) {
            # 回退到旧版本
            Write-UiWarn "更新失败，尝试回退到 $oldVersion..."
            $rollbackResult = Invoke-ExternalCommand -Command "npm" `
                -Arguments @("install", "-g", "$($script:ClaudeCodePackage)@$oldVersion") `
                -TimeoutSeconds 300 -SuppressOutput -RetryCount 0
            if ($rollbackResult.ExitCode -ne 0) {
                Write-UiWarn "回退也失败，当前状态可能不一致"
            }
            throw "npm install @latest 失败 (已尝试 3 次): $lastError"
        }

        # 刷新 PATH
        Refresh-SessionPath

        # 获取新版本
        $newVersion = Get-CommandVersion -Command "claude"
        $result.Data["OldVersion"] = $oldVersion
        $result.Data["NewVersion"] = $newVersion

        # 构建 UpdatedItems
        if ($oldVersion -eq $newVersion) {
            $result.UpdatedItems = @("noop::ClaudeCode::no-change")
            Write-UiInfo "Claude Code 已是最新版本 ($newVersion)"
        } else {
            $result.UpdatedItems = @("npm::claude-code::${oldVersion}->${newVersion}")
            Write-UiSuccess "✓ Claude Code 已更新: $oldVersion -> $newVersion"
        }

        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = "更新 Claude Code 失败: $($_.Exception.Message)"
        Write-UiError $result.ErrorMessage
    }

    return $result
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用