# Step04.ClaudeCode.ps1 - Claude Code npm 全局安装
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

function Test-Step04Installed {
    <#
    .SYNOPSIS
    测试步骤 04 是否已完成（Claude Code 安装）
    .RETURNS
    测试结果对象
    #>
    param()

    $result = @{
        IsInstalled = $false
        Version = ""
        Data = @{}
        Message = ""
    }

    try {
        Write-UiInfo "🔍 检查 Claude Code 安装状态..."

        # 检查 Node.js 前置条件
        if (-not (Test-CommandAvailable -Command "node")) {
            $result.Message = "Node.js 未安装，无法安装 Claude Code"
            Write-UiWarn "⚠ $($result.Message)"
            return $result
        }

        if (-not (Test-CommandAvailable -Command "npm")) {
            $result.Message = "npm 未安装，无法安装 Claude Code"
            Write-UiWarn "⚠ $($result.Message)"
            return $result
        }

        # 检查 Node.js 版本
        $nodeVersion = Get-CommandVersion -Command "node"
        $result.Data["NodeVersion"] = $nodeVersion
        $versionNumber = $nodeVersion -replace '^v?(\d+)\..*$', '$1'

        if ([int]$versionNumber -lt [int]$script:MinNodeVersion) {
            $result.Message = "Node.js 版本过低 (当前: $nodeVersion, 需要: v$script:MinNodeVersion+)"
            Write-UiWarn "⚠ $($result.Message)"
            return $result
        }

        # 检查 Claude Code 是否可用
        $claudeAvailable = Test-CommandAvailable -Command "claude"
        $result.Data["ClaudeAvailable"] = $claudeAvailable

        if ($claudeAvailable) {
            $claudeVersion = Get-CommandVersion -Command "claude"
            $result.Data["ClaudeVersion"] = $claudeVersion
            $result.Version = $claudeVersion
            Write-UiSuccess "✓ Claude Code 已安装 (版本: $claudeVersion)"

            # 验证 Claude Code 基本功能
            try {
                $helpResult = Invoke-ExternalCommand -Command "claude" -Arguments @("--help") -SuppressOutput -TimeoutSeconds 10
                if ($helpResult.Success) {
                    Write-UiSuccess "✓ Claude Code 功能验证通过"
                    $result.IsInstalled = $true
                    $result.Message = "Claude Code 已完全安装并可用"
                } else {
                    Write-UiWarn "⚠ Claude Code 安装但功能异常"
                    $result.Message = "Claude Code 安装但功能验证失败"
                }
            } catch {
                Write-UiWarn "⚠ Claude Code 功能验证异常: $($_.Exception.Message)"
                $result.Message = "Claude Code 功能验证异常"
            }
        } else {
            Write-UiWarn "⚠ Claude Code 未安装"
            $result.Message = "Claude Code 未安装"
        }

        # 检查 npm 全局包列表中是否存在
        try {
            $npmListResult = Invoke-ExternalCommand -Command "npm" -Arguments @("list", "-g", "--depth=0", $script:ClaudeCodePackage) -SuppressOutput -TimeoutSeconds 30
            if ($npmListResult.Success -and $npmListResult.Output -match $script:ClaudeCodePackage) {
                $result.Data["NpmPackageInstalled"] = $true
                Write-UiSuccess "✓ Claude Code npm 包已安装"
            } else {
                $result.Data["NpmPackageInstalled"] = $false
                Write-UiWarn "⚠ Claude Code npm 包未在全局列表中找到"
            }
        } catch {
            $result.Data["NpmPackageInstalled"] = $false
            Write-UiWarn "⚠ 无法检查 npm 全局包状态: $($_.Exception.Message)"
        }

    } catch {
        $result.Message = "Claude Code 安装状态检查失败: $($_.Exception.Message)"
        Write-UiWarn "⚠ $($result.Message)"
    }

    return $result
}

function Install-Step04 {
    <#
    .SYNOPSIS
    执行步骤 04 安装（Claude Code npm 全局安装）
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

        if (-not (Test-CommandAvailable -Command "node")) {
            throw "Node.js 未安装，请先完成 Step02"
        }

        if (-not (Test-CommandAvailable -Command "npm")) {
            throw "npm 未安装，请先完成 Step02"
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
                $cleanResult = Invoke-ExternalCommand -Command "npm" -Arguments @("cache", "clean", "--force") -TimeoutSeconds 60

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
        if (-not (Test-CommandAvailable -Command "claude")) {
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
            if (-not (Test-CommandAvailable -Command "claude")) {
                throw "Claude Code 安装后仍不可用，请重新启动终端后重试"
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

        Write-UiSuccess "✅ Step04 安装完成！"
        Write-UiInfo "💡 提示: Claude Code 现在可以通过 'claude' 命令使用"

    } catch {
        $result.ErrorMessage = "Claude Code 安装失败: $($_.Exception.Message)"
        Write-UiError "✗ $($result.ErrorMessage)"
    }

    return $result
}

function Verify-Step04 {
    <#
    .SYNOPSIS
    验证步骤 04 执行结果
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
            $npmListResult = Invoke-ExternalCommand -Command "npm" -Arguments @("list", "-g", "--depth=0") -SuppressOutput -TimeoutSeconds 30
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

function Rollback-Step04 {
    <#
    .SYNOPSIS
    回滚步骤 04（卸载 Claude Code）
    .RETURNS
    回滚结果对象
    #>
    param()

    $result = @{
        Success = $false
        Message = ""
        ErrorMessage = ""
    }

    try {
        Write-UiInfo "🔄 回滚 Claude Code 安装..."

        $rollbackActions = @()

        # 询问确认
        Write-UiWarn "⚠ 此操作将卸载 Claude Code，是否继续？"
        $options = @("确认卸载", "取消操作")
        $choice = Show-SingleSelectMenu -Title "确认回滚操作：" -Options $options

        if ($choice -eq 1) {
            $result.Success = $true
            $result.Message = "用户取消回滚操作"
            Write-UiInfo "回滚操作已取消"
            return $result
        }

        # 1. 使用 npm 卸载 Claude Code
        try {
            Write-UiInfo "通过 npm 卸载 Claude Code..."

            if (Test-CommandAvailable -Command "npm") {
                $uninstallResult = Invoke-ExternalCommand -Command "npm" -Arguments @("uninstall", "-g", $script:ClaudeCodePackage) -TimeoutSeconds 120
                if ($uninstallResult.Success) {
                    $rollbackActions += "Claude Code npm 包已卸载"
                } else {
                    $rollbackActions += "npm 卸载失败: $($uninstallResult.Error)"
                }
            } else {
                $rollbackActions += "npm 不可用，无法自动卸载"
            }

        } catch {
            $rollbackActions += "npm 卸载异常: $($_.Exception.Message)"
        }

        # 2. 清理可能的残留文件
        try {
            # 清理 npm 缓存中的相关文件
            $cleanResult = Invoke-ExternalCommand -Command "npm" -Arguments @("cache", "clean", "--force") -TimeoutSeconds 60
            if ($cleanResult.Success) {
                $rollbackActions += "npm 缓存已清理"
            }
        } catch {
            $rollbackActions += "npm 缓存清理异常: $($_.Exception.Message)"
        }

        # 3. 刷新环境变量
        try {
            Refresh-SessionPath
            $rollbackActions += "环境变量已刷新"
        } catch {
            $rollbackActions += "环境变量刷新异常: $($_.Exception.Message)"
        }

        # 4. 验证卸载结果
        if (Test-CommandAvailable -Command "claude") {
            $rollbackActions += "警告: claude 命令仍然可用，可能需要重启终端"
        } else {
            $rollbackActions += "claude 命令已不可用，卸载成功"
        }

        $result.Success = $true
        $result.Message = "Claude Code 回滚完成: $($rollbackActions -join '; ')"

        Write-UiSuccess "✓ 回滚操作完成"
        Write-UiInfo "💡 提示: 完全清理可能需要重新启动终端"

    } catch {
        $result.ErrorMessage = "Claude Code 回滚失败: $($_.Exception.Message)"
        Write-UiError "✗ $($result.ErrorMessage)"
    }

    return $result
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用