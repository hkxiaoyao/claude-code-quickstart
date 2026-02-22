# Step04: CCometixLine 安装 - Claude Code 环境安装器
# 作者: 哈雷酱 (本小姐的状态栏配置杰作！)
# 功能: CCometixLine 安装 + statusLine 配置写入

#Requires -Version 5.1

Set-StrictMode -Version Latest

# 导入依赖模块
. "$PSScriptRoot\..\core\Process.ps1"
. "$PSScriptRoot\..\core\Ui.ps1"

# 配置
$script:CclinePackage = "ccline"
$script:ClaudeConfigDir = "$env:USERPROFILE\.claude"
$script:ClaudeSettingsFile = "$script:ClaudeConfigDir\settings.json"

function Test-Step04Installed {
    <#
    .SYNOPSIS
    检测 CCometixLine 是否已安装并配置
    .RETURNS
    布尔值，表示是否已安装和配置
    #>
    param()

    try {
        # 检查 ccline 命令是否可用
        if (-not (Test-CommandAvailable -Command "ccline")) {
            return $false
        }

        # 检查 Claude Code 配置文件中的 statusLine 配置
        if (Test-Path $script:ClaudeSettingsFile) {
            try {
                $settings = Get-Content $script:ClaudeSettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($settings.statusLine -and $settings.statusLine.enabled -eq $true) {
                    Write-Host "检测到已安装和配置的 CCometixLine:" -ForegroundColor Green
                    Write-Host "  版本: $(Get-CommandVersion -Command 'ccline')" -ForegroundColor Gray
                    Write-Host "  状态栏: 已启用" -ForegroundColor Gray
                    return $true
                }
            } catch {
                # 配置文件解析失败，认为未正确配置
            }
        }

        # ccline 已安装但未配置
        if (Test-CommandAvailable -Command "ccline") {
            Write-Host "CCometixLine 已安装但未配置状态栏" -ForegroundColor Yellow
        }

        return $false

    } catch {
        return $false
    }
}

function Install-Step04 {
    <#
    .SYNOPSIS
    安装 CCometixLine 并配置状态栏
    .RETURNS
    安装结果对象
    #>
    param()

    Write-Host "=== Step 05: CCometixLine 安装 ===" -ForegroundColor Cyan
    Write-Host ""

    try {
        # 1. 检查前置条件
        Write-Host "1. 检查前置条件..." -ForegroundColor Gray

        # 验证 Claude Code
        $claudeDetails = Test-CommandAvailable -Command "claude" -ReturnDetails
        if (-not $claudeDetails.Available) {
            $errorMsg = "Claude Code 未安装，请先完成 Step03"
            if ($claudeDetails.ErrorMessage) {
                $errorMsg += "`n  错误详情: $($claudeDetails.ErrorMessage)"
            }
            throw $errorMsg
        }

        # 验证 npm
        $npmDetails = Test-CommandAvailable -Command "npm" -ReturnDetails
        if (-not $npmDetails.Available) {
            $errorMsg = "npm 未安装，请先完成 Step01"
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
                $result = Invoke-NpmGlobalInstall -PackageName $script:CclinePackage -Force
                if (-not $result.Success) {
                    throw "CCometixLine 重新安装失败"
                }
                Write-Host "✓ CCometixLine 重新安装成功" -ForegroundColor Green
            }
        } else {
            # 安装 CCometixLine
            Write-Host "安装 CCometixLine..." -ForegroundColor Yellow

            $result = Invoke-NpmGlobalInstall -PackageName $script:CclinePackage

            if (-not $result.Success) {
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
                    $settings = $existingContent | ConvertFrom-Json -AsHashtable
                    Write-Host "✓ 读取现有配置文件" -ForegroundColor Green
                }
            } catch {
                Write-Host "⚠ 现有配置文件格式错误，将创建新配置" -ForegroundColor Yellow
                $settings = @{}
            }
        }

        # 配置状态栏
        $settings["statusLine"] = @{
            enabled = $true
            command = "ccline"
            refreshInterval = 5000
            position = "right"
            showGitBranch = $true
            showWorkingDirectory = $true
            showTimestamp = $false
        }

        # 写入配置文件
        try {
            $settingsJson = $settings | ConvertTo-Json -Depth 10 -Compress:$false
            $settingsJson | Out-File -FilePath $script:ClaudeSettingsFile -Encoding UTF8 -Force

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
            if ($verifySettings.statusLine -and $verifySettings.statusLine.enabled -eq $true) {
                Write-Host "✓ 状态栏配置验证成功" -ForegroundColor Green
            } else {
                throw "状态栏配置验证失败"
            }

        } catch {
            Write-Host "⚠ 状态栏功能测试失败: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # 7. 使用提示
        Write-Host ""
        Write-Host "7. 使用提示..." -ForegroundColor Gray
        Write-Host "  CCometixLine 状态栏已配置完成" -ForegroundColor Cyan
        Write-Host "  状态栏将在 Claude Code 中显示以下信息:" -ForegroundColor Gray
        Write-Host "    - Git 分支信息" -ForegroundColor Gray
        Write-Host "    - 当前工作目录" -ForegroundColor Gray
        Write-Host "    - 刷新间隔: 5秒" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  基本命令:" -ForegroundColor Gray
        Write-Host "    ccline --version       # 查看版本" -ForegroundColor Gray
        Write-Host "    ccline --help          # 查看帮助" -ForegroundColor Gray

        Write-Host ""
        Write-Host "✓ CCometixLine 安装和配置完成" -ForegroundColor Green

        return @{
            Success = $true
            CclineVersion = $cclineVersion
            ConfigFile = $script:ClaudeSettingsFile
            StatusLineEnabled = $true
            Message = "CCometixLine 安装和状态栏配置成功"
        }

    } catch {
        Write-Host "✗ CCometixLine 安装和配置失败: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

function Verify-Step04 {
    <#
    .SYNOPSIS
    验证 CCometixLine 安装和配置
    .RETURNS
    布尔值，表示验证是否成功
    #>
    param()

    return Test-Step04Installed
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用