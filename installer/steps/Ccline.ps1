# Ccline.ps1 - CCometixLine 安装 - CCQ
# 作者: 哈雷酱 (本小姐的状态栏配置杰作！)
# 功能: CCometixLine 安装 + statusLine 配置写入

#Requires -Version 5.1

Set-StrictMode -Version Latest

# 导入依赖模块
. "$PSScriptRoot\..\core\Process.ps1"
. "$PSScriptRoot\..\core\Ui.ps1"
. "$PSScriptRoot\..\core\Profile.ps1"

# 配置
$script:CclinePackage = "@cometix/ccline"
$script:ClaudeConfigDir = "$(Get-UserHome)\.claude"
$script:ClaudeSettingsFile = "$script:ClaudeConfigDir\settings.json"

function Test-CclineInstalled {
    <#
    .SYNOPSIS
    检测 CCometixLine 是否已安装并配置
    .RETURNS
    标准检测结果 hashtable（IsInstalled, Version, Data, Message）
    #>

    $settingsFile = $script:ClaudeSettingsFile
    return Invoke-UnifiedCheck -StepId "Ccline" -DisplayName "CCometixLine" `
        -Command "ccline" `
        -ConfigFile $settingsFile `
        -RequiredFields @(
            @{ Path = "statusLine.type"; MatchMode = "Exact"; ExpectedValue = "command" },
            @{ Path = "statusLine.command"; MatchMode = "Exact"; ExpectedValue = "ccline" }
        ) -UseCache
}

function Install-Ccline {
    <#
    .SYNOPSIS
    安装 CCometixLine 并配置状态栏
    .RETURNS
    安装结果对象
    #>
    param()

    Write-Host "=== CCometixLine 安装 ===" -ForegroundColor Cyan
    Write-Host ""

    $stepResult = @{
        Success      = $false
        ErrorMessage = ""
        Data         = @{}
    }

    try {
        # 1. 检查前置条件
        Write-Host "1. 检查前置条件..." -ForegroundColor Gray

        # 验证 Claude Code
        $claudeDetails = Test-CommandAvailable -Command "claude" -ReturnDetails
        if (-not $claudeDetails.Available) {
            $errorMsg = "Claude Code 未安装，请先完成 ClaudeCode 步骤"
            if ($claudeDetails.ErrorMessage) {
                $errorMsg += "`n  错误详情: $($claudeDetails.ErrorMessage)"
            }
            throw $errorMsg
        }

        # 验证 npm
        $npmDetails = Test-CommandAvailable -Command "npm" -ReturnDetails
        if (-not $npmDetails.Available) {
            $errorMsg = "npm 未安装，请先完成 NodeFnm 步骤"
            if ($npmDetails.ResolvedPath) {
                $errorMsg += "`n  解析路径: $($npmDetails.ResolvedPath)"
            }
            if ($npmDetails.ErrorMessage) {
                $errorMsg += "`n  错误详情: $($npmDetails.ErrorMessage)"
            }
            throw $errorMsg
        }

        Write-Host "✓ 前置条件检查完成" -ForegroundColor Green

        # 2. 检查 CCometixLine 是否已安装
        Write-Host ""
        Write-Host "2. 检查 CCometixLine 安装状态..." -ForegroundColor Gray

        if (Test-CommandAvailable -Command "ccline") {
            $cclineVersion = Get-CommandVersion -Command "ccline"
            Write-Host "✓ CCometixLine 已安装: $cclineVersion" -ForegroundColor Green

            # 询问是否重新安装
            $response = Read-Host "CCometixLine 已安装，是否重新安装最新版本？[y/N]"
            if ($response -notmatch "^[Yy]") {
                Write-Host "跳过 CCometixLine 重新安装" -ForegroundColor Gray
            } else {
                # 重新安装
                Write-Host "重新安装 CCometixLine..." -ForegroundColor Yellow
                $npmResult = Invoke-NpmGlobalInstall -PackageName $script:CclinePackage -Force
                if (-not $npmResult.Success) {
                    throw "CCometixLine 重新安装失败"
                }
                Write-Host "✓ CCometixLine 重新安装成功" -ForegroundColor Green
            }
        } else {
            # 安装 CCometixLine
            Write-Host "安装 CCometixLine..." -ForegroundColor Yellow

            $npmResult = Invoke-NpmGlobalInstall -PackageName $script:CclinePackage

            if (-not $npmResult.Success) {
                throw "CCometixLine 安装失败"
            }

            Write-Host "✓ CCometixLine 安装成功" -ForegroundColor Green
        }

        # 3. 验证安装
        Write-Host ""
        Write-Host "3. 验证 CCometixLine 安装..." -ForegroundColor Gray

        # 刷新 PATH 以确保 ccline 命令可用
        Refresh-SessionPath

        if (-not (Test-CommandAvailable -Command "ccline")) {
            throw "CCometixLine 安装后仍不可用，可能需要重启终端"
        }

        $cclineVersion = Get-CommandVersion -Command "ccline"
        Write-Host "✓ CCometixLine 验证成功: $cclineVersion" -ForegroundColor Green

        # 4. 创建 Claude Code 配置目录
        Write-Host ""
        Write-Host "4. 准备 Claude Code 配置..." -ForegroundColor Gray

        if (-not (Test-Path $script:ClaudeConfigDir)) {
            New-Item -Path $script:ClaudeConfigDir -ItemType Directory -Force | Out-Null
            Write-Host "✓ Claude Code 配置目录已创建: $script:ClaudeConfigDir" -ForegroundColor Green
        } else {
            Write-Host "✓ Claude Code 配置目录已存在: $script:ClaudeConfigDir" -ForegroundColor Green
        }

        # 5. 配置状态栏设置
        Write-Host ""
        Write-Host "5. 配置 Claude Code 状态栏..." -ForegroundColor Gray

        # 读取现有配置或创建新配置
        $settings = @{}
        if (Test-Path $script:ClaudeSettingsFile) {
            try {
                $existingContent = Get-Content $script:ClaudeSettingsFile -Raw -Encoding UTF8
                if ($existingContent.Trim()) {
                    $settings = $existingContent | ConvertFrom-Json -AsHashtable -ErrorAction Stop
                    if (-not $settings) {
                        throw "配置文件解析结果为空"
                    }
                    Write-Host "✓ 读取现有配置文件" -ForegroundColor Green
                }
            } catch {
                throw "无法解析现有 settings.json，已停止写入以避免覆盖用户配置: $($_.Exception.Message)"
            }
        }

        # 配置状态栏（Claude Code 官方 schema）
        $settings["statusLine"] = @{
            "type"    = "command"
            "command" = "ccline"
            "padding" = 0
        }

        # 写入配置文件（使用原子操作）
        try {
            $settingsJson = $settings | ConvertTo-Json -Depth 10 -Compress:$false
            $writeResult = Write-FileAtomically -FilePath $script:ClaudeSettingsFile -Content $settingsJson

            if (-not $writeResult) {
                throw "Write-FileAtomically 返回失败"
            }

            Write-Host "✓ 状态栏配置已写入: $script:ClaudeSettingsFile" -ForegroundColor Green

        } catch {
            throw "状态栏配置写入失败: $($_.Exception.Message)"
        }

        # 6. 测试状态栏功能
        Write-Host ""
        Write-Host "6. 测试状态栏功能..." -ForegroundColor Gray

        try {
            # 测试 ccline 命令
            $testResult = Invoke-ExternalCommand -Command "ccline" -Arguments @("--version") -SuppressOutput -TimeoutSeconds 10
            if ($testResult.Success) {
                Write-Host "✓ CCometixLine 命令测试成功" -ForegroundColor Green
            } else {
                Write-Host "⚠ CCometixLine 命令测试失败，但不影响配置" -ForegroundColor Yellow
            }

            # 验证配置文件
            $verifySettings = Get-Content $script:ClaudeSettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($verifySettings.statusLine -and
                $verifySettings.statusLine.type -eq "command" -and
                $verifySettings.statusLine.command -eq "ccline") {
                Write-Host "✓ 状态栏配置验证成功" -ForegroundColor Green
            } else {
                throw "状态栏配置验证失败"
            }

        } catch {
            Write-Host "⚠ 状态栏功能测试失败: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # 7. 执行 ccline patch
        Write-Host ""
        Write-Host "7. 执行 CCometixLine patch..." -ForegroundColor Gray

        $patchApplied = $false
        $claudeCliPath = $null
        try {
            # 获取 npm 全局 node_modules 路径（比 prefix 拼接更稳健）
            $npmRoot = (& npm root -g 2>$null | Select-Object -First 1)
            if ($npmRoot) { $npmRoot = $npmRoot.Trim() }
            if (-not $npmRoot -or -not (Test-Path $npmRoot)) {
                throw "无法获取 npm 全局 node_modules 路径"
            }

            # 构建 Claude Code cli.js 路径
            $claudeCliPath = Join-Path $npmRoot "@anthropic-ai\claude-code\cli.js"
            if (-not (Test-Path $claudeCliPath)) {
                throw "Claude Code cli.js 文件不存在: $claudeCliPath"
            }

            Write-Host "  Claude Code cli.js 路径: $claudeCliPath" -ForegroundColor Gray

            # 执行 ccline --patch（路径含空格时显式加引号，因 Invoke-ExternalCommand 使用 -join ' ' 拼接参数）
            $claudeCliArg = if ($claudeCliPath -match "\s") { "`"$claudeCliPath`"" } else { $claudeCliPath }
            $patchResult = Invoke-ExternalCommand -Command "ccline" -Arguments @("--patch", $claudeCliArg) -TimeoutSeconds 30
            if ($patchResult.Success) {
                $patchApplied = $true
                Write-Host "✓ CCometixLine patch 执行成功" -ForegroundColor Green
            } else {
                Write-Host "⚠ CCometixLine patch 执行失败，但不影响基本功能" -ForegroundColor Yellow
                Write-Host "  错误信息: $($patchResult.Error)" -ForegroundColor Gray
                Write-Host "  可手动执行: ccline --patch `"$claudeCliPath`"" -ForegroundColor Gray
            }
        } catch {
            Write-Host "⚠ CCometixLine patch 执行失败: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "  状态栏功能可能受限，但不影响基本使用" -ForegroundColor Gray
            if ($claudeCliPath) {
                Write-Host "  可手动执行: ccline --patch `"$claudeCliPath`"" -ForegroundColor Gray
            }
        }

        # 8. 使用提示
        Write-Host ""
        Write-Host "8. 使用提示..." -ForegroundColor Gray
        Write-Host "  CCometixLine 状态栏已配置完成" -ForegroundColor Cyan
        Write-Host "  状态栏将在 Claude Code 中自动显示自定义信息" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  基本命令:" -ForegroundColor Gray
        Write-Host "    ccline --version       # 查看版本" -ForegroundColor Gray
        Write-Host "    ccline --help          # 查看帮助" -ForegroundColor Gray
        Write-Host "    ccline --patch <path>  # Patch Claude Code" -ForegroundColor Gray

        Write-Host ""
        Write-Host "✓ CCometixLine 安装和配置完成" -ForegroundColor Green

        $resultMessage = if ($patchApplied) {
            "CCometixLine 安装、状态栏配置和 patch 全部成功"
        } else {
            "CCometixLine 安装和状态栏配置成功，但 ccline patch 未完成，请按提示手动执行"
        }

        $stepResult.Success = $true
        $stepResult.Data["Version"] = $cclineVersion
        $stepResult.Data["ConfigFile"] = $script:ClaudeSettingsFile
        $stepResult.Data["StatusLineEnabled"] = $true
        $stepResult.Data["PatchApplied"] = $patchApplied

        return $stepResult

    } catch {
        $stepResult.ErrorMessage = "CCometixLine 安装和配置失败: $($_.Exception.Message)"
        Write-Host "✗ $($stepResult.ErrorMessage)" -ForegroundColor Red
        return $stepResult
    }
}

function Verify-Ccline {
    <#
    .SYNOPSIS
    验证 CCometixLine 安装和配置
    .RETURNS
    布尔值，表示验证是否成功
    #>
    param()

    $testResult = Test-CclineInstalled
    return @{ Success = [bool]$testResult.IsInstalled; ErrorMessage = if (-not $testResult.IsInstalled) { $testResult.Message } else { "" } }
}

function Update-Ccline {
    <#
    .SYNOPSIS
    更新 CCometixLine 到最新版本并无条件重新 patch（Claude Code 更新后 cli.js 被替换）
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
        Write-UiInfo "更新 CCometixLine..."

        # 获取当前版本
        $oldVersion = ""
        if (Test-CommandAvailable -Command "ccline") {
            $oldVersion = Get-CommandVersion -Command "ccline"
        }
        if ([string]::IsNullOrWhiteSpace($oldVersion)) {
            throw "无法获取当前 CCometixLine 版本，请确认已安装"
        }
        Write-UiInfo "当前版本: $oldVersion"

        $updatedItems = [System.Collections.ArrayList]::new()
        $newVersion = $oldVersion

        # 检测是否有新版本（使用 npm outdated -g 批量缓存）
        $updateCheck = Test-NpmUpdateAvailable -PackageName $script:CclinePackage -CurrentVersion $oldVersion
        if ($updateCheck.LatestVersion) {
            Write-UiInfo "最新版本: $($updateCheck.LatestVersion)"
        }
        if ($updateCheck.Available -eq $false) {
            Write-UiInfo "CCometixLine 已是最新版本 ($oldVersion)"
            [void]$updatedItems.Add("noop::Ccline::no-change")
        } else {
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
                    -Arguments @("install", "-g", "$($script:CclinePackage)@latest") `
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
                Invoke-ExternalCommand -Command "npm" `
                    -Arguments @("install", "-g", "$($script:CclinePackage)@$oldVersion") `
                    -TimeoutSeconds 300 -SuppressOutput -RetryCount 0 | Out-Null
                throw "npm install @latest 失败 (已尝试 3 次): $lastError"
            }

            # 刷新 PATH
            Refresh-SessionPath

            # 获取新版本
            $newVersion = Get-CommandVersion -Command "ccline"

            if ($oldVersion -eq $newVersion) {
                [void]$updatedItems.Add("noop::Ccline::no-change")
                Write-UiInfo "CCometixLine 已是最新版本 ($newVersion)"
            } else {
                [void]$updatedItems.Add("npm::ccline::${oldVersion}->${newVersion}")
                Write-UiSuccess "✓ CCometixLine 已更新: $oldVersion -> $newVersion"
            }
        }

        $result.Data["OldVersion"] = $oldVersion
        $result.Data["NewVersion"] = $newVersion

        # 无条件重新执行 ccline patch（Claude Code 更新后 cli.js 被替换，必须重新 patch）
        $patchApplied = $false
        try {
            $npmRoot = (& npm root -g 2>$null | Select-Object -First 1)
            if ($npmRoot) { $npmRoot = $npmRoot.Trim() }
            if ($npmRoot -and (Test-Path $npmRoot)) {
                $claudeCliPath = Join-Path $npmRoot "@anthropic-ai\claude-code\cli.js"
                if (Test-Path $claudeCliPath) {
                    $claudeCliArg = if ($claudeCliPath -match "\s") { "`"$claudeCliPath`"" } else { $claudeCliPath }
                    $patchResult = Invoke-ExternalCommand -Command "ccline" `
                        -Arguments @("--patch", $claudeCliArg) -TimeoutSeconds 30 -SuppressOutput
                    if ($patchResult.Success) {
                        $patchApplied = $true
                        [void]$updatedItems.Add("patch::ccline::re-patched")
                        Write-UiSuccess "✓ CCometixLine patch 重新应用成功"
                    } else {
                        Write-UiWarn "CCometixLine patch 重新应用失败，不影响基本功能"
                    }
                } else {
                    Write-UiWarn "Claude Code cli.js 未找到，跳过 patch"
                }
            }
        } catch {
            Write-UiWarn "CCometixLine patch 执行异常: $($_.Exception.Message)"
        }

        $result.Data["PatchApplied"] = $patchApplied
        $result.UpdatedItems = @($updatedItems)
        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = "更新 CCometixLine 失败: $($_.Exception.Message)"
        Write-UiError $result.ErrorMessage
    }

    return $result
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用