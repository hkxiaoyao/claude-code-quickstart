# CcSwitch.ps1 - CC-Switch 安装 - CCQ
# 作者: 哈雷酱 (本小姐的 CC-Switch 安装杰作！)
# 功能: CC-Switch GitHub Release 下载 + MSI 静默安装

#Requires -Version 5.1

Set-StrictMode -Version Latest

# 导入依赖模块
. "$PSScriptRoot\..\core\Process.ps1"
. "$PSScriptRoot\..\core\Ui.ps1"
. "$PSScriptRoot\..\core\Admin.ps1"
. "$PSScriptRoot\..\core\Net.ps1"

# 配置
$script:CcSwitchRepo = "farion1231/cc-switch"
$script:CcSwitchApiUrl = "https://api.github.com/repos/$script:CcSwitchRepo/releases/latest"
# 解析 $env:TEMP 为长路径，避免 8.3 短路径导致 msiexec 失败
$script:TempDownloadDir = try {
    # 多重策略解析长路径，避免 8.3 短路径
    $tempLong = $env:TEMP
    try {
        if (Test-Path $tempLong) {
            $tempLong = (Get-Item $tempLong).FullName
        }
    } catch { }
    # 回退：通过 GetFullPath 解析
    if ($tempLong -match '~') {
        try {
            $tempLong = [System.IO.Path]::GetFullPath($tempLong)
        } catch { }
    }
    # 最终回退：构建无短路径的临时目录
    if ($tempLong -match '~') {
        $tempLong = Join-Path $env:LOCALAPPDATA "Temp"
        if (-not (Test-Path $tempLong)) {
            $tempLong = $env:TEMP
        }
    }
    Join-Path $tempLong "CcSwitchInstall"
} catch {
    "$env:TEMP\CcSwitchInstall"
}

function Test-CcSwitchInstalled {
    <#
    .SYNOPSIS
    检测 CC-Switch 是否已安装
    .RETURNS
    标准检测结果 hashtable（IsInstalled, Version, Data, Message）
    #>

    return Invoke-UnifiedCheck -StepId "CcSwitch" -DisplayName "CC-Switch" `
        -CustomVerify {
            # 检查注册表中的 CC-Switch 安装信息
            $uninstallKeys = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
                "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
            )

            foreach ($keyPath in $uninstallKeys) {
                try {
                    $items = @(Get-ItemProperty $keyPath -ErrorAction SilentlyContinue | Where-Object {
                        $_.DisplayName -like "*CC-Switch*" -or
                        $_.DisplayName -like "*CC Switch*" -or
                        $_.DisplayName -like "*Claude Code Switch*" -or
                        $_.Publisher -like "*ccswitch*" -or
                        $_.Publisher -like "*Anthropic*"
                    })

                    if ($items.Count -gt 0) {
                        $item = $items[0]
                        Write-UiInfo "  名称: $($item.DisplayName)"
                        if ($item.DisplayVersion) {
                            Write-UiInfo "  版本: $($item.DisplayVersion)"
                            return $item.DisplayVersion
                        }
                        return $true
                    }
                } catch { }
            }

            # 检查常见安装路径
            $commonPaths = @(
                "$env:LOCALAPPDATA\Programs\CC Switch",
                "$env:LOCALAPPDATA\Programs\CC-Switch",
                "$env:ProgramFiles\CC-Switch",
                "$env:ProgramFiles\CC Switch",
                "$env:ProgramFiles\Anthropic\CC-Switch",
                "${env:ProgramFiles(x86)}\CC-Switch",
                "${env:ProgramFiles(x86)}\CC Switch",
                "${env:ProgramFiles(x86)}\Anthropic\CC-Switch",
                "$env:LOCALAPPDATA\Programs\cc-switch"
            )

            foreach ($path in $commonPaths) {
                if (Test-Path $path) {
                    $exeFiles = @(Get-ChildItem -Path $path -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue)
                    if ($exeFiles.Count -gt 0) {
                        Write-UiInfo "  安装目录: $path"
                        return $true
                    }
                }
            }

            return $false
        } -UseCache
}

function Install-CcSwitch {
    <#
    .SYNOPSIS
    安装 CC-Switch
    .RETURNS
    安装结果对象
    #>
    param()

    Write-Host "=== CC-Switch 安装 ===" -ForegroundColor Cyan
    Write-Host ""

    $result = @{
        Success      = $false
        ErrorMessage = ""
        Data         = @{}
    }

    try {
        # 1. 检查前置条件
        Write-Host "1. 检查前置条件..." -ForegroundColor Gray

        if (-not (Test-CommandAvailable -Command "claude")) {
            throw "Claude Code 未安装，请先完成 ClaudeCode 步骤"
        }

        Write-Host "✓ 前置条件检查完成" -ForegroundColor Green

        # 2. 检查 CC-Switch 是否已安装
        Write-Host ""
        Write-Host "2. 检查 CC-Switch 安装状态..." -ForegroundColor Gray

        $ccSwitchTest = Test-CcSwitchInstalled
        if ($ccSwitchTest.IsInstalled) {
            Write-Host "✓ CC-Switch 已安装，跳过" -ForegroundColor Green
            $result.Success = $true
            $result.Data["Skipped"] = $true
            return $result
        } else {
            # 未检测到安装，提醒用户检测机制的限制
            Write-Host "  未检测到 CC-Switch 安装" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  注意: 当前仅支持检测 MSI 安装方式" -ForegroundColor DarkGray
            Write-Host "  如果您已通过便携版/自定义方式安装，可选择跳过" -ForegroundColor DarkGray
            Write-Host ""
            $response = Read-Host "是否继续安装 CC-Switch？[Y/n]"
            if ($response -match "^[Nn]") {
                Write-Host "跳过 CC-Switch 安装" -ForegroundColor Gray
                $result.Success = $true
                $result.Data["Skipped"] = $true
                return $result
            }
        }

        # 3. 检查安装权限（非硬性要求，per-user 安装不需要管理员）
        Write-Host ""
        Write-Host "3. 检查安装权限..." -ForegroundColor Gray

        $isAdmin = Test-IsAdministrator
        if (-not $isAdmin) {
            Write-Host "  当前非管理员权限，将优先尝试 per-user 安装" -ForegroundColor Gray
        } else {
            Write-Host "✓ 管理员权限确认" -ForegroundColor Green
        }

        # 4. 获取最新版本信息
        Write-Host ""
        Write-Host "4. 获取 CC-Switch 最新版本信息..." -ForegroundColor Gray

        $releaseInfo = Get-LatestCcSwitchRelease
        if (-not $releaseInfo) {
            throw "无法获取 CC-Switch 最新版本信息"
        }

        Write-Host "✓ 最新版本: $($releaseInfo.Version)" -ForegroundColor Green
        Write-Host "  发布时间: $($releaseInfo.PublishedAt)" -ForegroundColor Gray
        Write-Host "  下载地址: $($releaseInfo.DownloadUrl)" -ForegroundColor Gray

        # 5. 下载 CC-Switch 安装包
        Write-Host ""
        Write-Host "5. 下载 CC-Switch 安装包..." -ForegroundColor Gray

        $installerPath = Download-CcSwitchInstaller -DownloadUrl $releaseInfo.DownloadUrl -Version $releaseInfo.Version

        if (-not $installerPath -or -not (Test-Path $installerPath)) {
            throw "CC-Switch 安装包下载失败"
        }

        Write-Host "✓ 安装包下载成功: $installerPath" -ForegroundColor Green

        # 6. 验证安装包
        Write-Host ""
        Write-Host "6. 验证安装包..." -ForegroundColor Gray

        $fileInfo = Get-Item $installerPath
        Write-Host "  文件大小: $([math]::Round($fileInfo.Length / 1MB, 2)) MB" -ForegroundColor Gray

        # 检查文件类型
        if ($installerPath -notmatch "\.(msi|exe)$") {
            throw "不支持的安装包格式: $installerPath"
        }

        Write-Host "✓ 安装包验证通过" -ForegroundColor Green

        # 7. 执行静默安装
        Write-Host ""
        Write-Host "7. 执行 CC-Switch 静默安装..." -ForegroundColor Gray

        $installResult = Install-CcSwitchPackage -InstallerPath $installerPath

        if (-not $installResult.Success) {
            throw "CC-Switch 安装失败: $($installResult.ErrorMessage)"
        }

        Write-Host "✓ CC-Switch 安装成功" -ForegroundColor Green

        # 8. 验证安装
        Write-Host ""
        Write-Host "8. 验证 CC-Switch 安装..." -ForegroundColor Gray

        # 等待安装完成
        Start-Sleep -Seconds 3

        $verifyTest = Test-CcSwitchInstalled
        if (-not $verifyTest.IsInstalled) {
            Write-Host "⚠ CC-Switch 安装验证失败，但安装过程成功" -ForegroundColor Yellow
            Write-Host "  可能需要重启系统或重新登录才能完全生效" -ForegroundColor Gray
        } else {
            Write-Host "✓ CC-Switch 安装验证成功" -ForegroundColor Green
        }

        # 9. 清理临时文件
        Write-Host ""
        Write-Host "9. 清理临时文件..." -ForegroundColor Gray

        try {
            if (Test-Path $script:TempDownloadDir) {
                Remove-Item $script:TempDownloadDir -Recurse -Force
                Write-Host "✓ 临时文件清理完成" -ForegroundColor Green
            }
        } catch {
            Write-Host "⚠ 临时文件清理失败，但不影响使用: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # 10. 使用提示
        Write-Host ""
        Write-Host "10. 使用提示..." -ForegroundColor Gray
        Write-Host "  CC-Switch 已安装完成" -ForegroundColor Cyan
        Write-Host "  CC-Switch 是 Claude Code 的辅助工具，提供以下功能:" -ForegroundColor Gray
        Write-Host "    - 快速切换 Claude Code 配置" -ForegroundColor Gray
        Write-Host "    - 项目环境管理" -ForegroundColor Gray
        Write-Host "    - 工作流程优化" -ForegroundColor Gray
        Write-Host ""
        Write-Host "✓ CC-Switch 安装完成" -ForegroundColor Green

        $result.Success = $true
        $result.Data["Version"] = $releaseInfo.Version
        $result.Data["InstallerPath"] = $installerPath

        return $result

    } catch {
        $result.ErrorMessage = "CC-Switch 安装失败: $($_.Exception.Message)"
        Write-Host "✗ $($result.ErrorMessage)" -ForegroundColor Red

        # 清理临时文件
        try {
            if (Test-Path $script:TempDownloadDir) {
                Remove-Item $script:TempDownloadDir -Recurse -Force
            }
        } catch { }

        return $result
    }
}

function Get-LatestCcSwitchRelease {
    <#
    .SYNOPSIS
    获取 CC-Switch 最新版本信息
    .RETURNS
    包含版本信息的对象
    #>
    param()

    try {
        Write-Host "  正在获取 GitHub Release 信息..." -ForegroundColor Gray

        # 强制使用 TLS 1.2+（GitHub API 要求，防止 PS 5.1 默认 TLS 1.0 导致连接失败）
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13

        # 使用 Invoke-RestMethod 获取最新版本信息
        $headers = @{
            "User-Agent" = "ClaudeEnvInstaller/1.0"
            "Accept" = "application/vnd.github.v3+json"
        }

        $release = Invoke-RestMethod -Uri $script:CcSwitchApiUrl -Headers $headers -TimeoutSec 30

        if (-not $release) {
            throw "无法获取 Release 信息"
        }

        # 查找 Windows MSI 安装包
        $msiAsset = $release.assets | Where-Object {
            $_.name -match "\.(msi|exe)$" -and
            $_.name -match "(windows|win|x64|amd64)" -and
            $_.content_type -match "(application/x-msi|application/octet-stream|application/x-msdownload)"
        } | Select-Object -First 1

        if (-not $msiAsset) {
            # 如果没找到明确的 Windows 安装包，尝试查找任何 MSI/EXE 文件
            $msiAsset = $release.assets | Where-Object {
                $_.name -match "\.(msi|exe)$"
            } | Select-Object -First 1
        }

        if (-not $msiAsset) {
            throw "未找到适用于 Windows 的安装包"
        }

        return @{
            Version = $release.tag_name -replace '^v', ''
            TagName = $release.tag_name
            PublishedAt = $release.published_at
            DownloadUrl = $msiAsset.browser_download_url
            FileName = $msiAsset.name
            FileSize = $msiAsset.size
        }

    } catch {
        Write-Host "  获取版本信息失败: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Download-CcSwitchInstaller {
    <#
    .SYNOPSIS
    下载 CC-Switch 安装包
    .PARAMETER DownloadUrl
    下载地址
    .PARAMETER Version
    版本号
    .RETURNS
    下载的文件路径
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string] $DownloadUrl,

        [Parameter(Mandatory = $true)]
        [string] $Version
    )

    try {
        # 创建临时下载目录
        if (Test-Path $script:TempDownloadDir) {
            Remove-Item $script:TempDownloadDir -Recurse -Force
        }
        New-Item -Path $script:TempDownloadDir -ItemType Directory -Force | Out-Null

        # 确定文件名和路径
        $fileName = Split-Path $DownloadUrl -Leaf
        if (-not $fileName -or $fileName -notmatch "\.(msi|exe)$") {
            $fileName = "cc-switch-$Version.msi"
        }

        $filePath = Join-Path $script:TempDownloadDir $fileName

        # 使用统一的下载函数
        $downloadResult = Invoke-FileDownload -Url $DownloadUrl -OutputPath $filePath -Description "CC-Switch $Version"

        if (-not $downloadResult.Success) {
            throw $downloadResult.ErrorMessage
        }

        return $filePath

    } catch {
        Write-Host "  下载失败: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Get-MsiLogErrors {
    <#
    .SYNOPSIS
    从 MSI 安装日志中提取错误信息
    #>
    $errorDetails = ""
    $logFiles = @(
        "$script:TempDownloadDir\install.log",
        "$script:TempDownloadDir\install-peruser.log"
    )
    foreach ($logPath in $logFiles) {
        if (Test-Path $logPath) {
            try {
                $logContent = Get-Content $logPath -Tail 30 -ErrorAction SilentlyContinue
                $errorLines = $logContent | Where-Object { $_ -match "(error|failed|exception)" }
                if ($errorLines) {
                    $errorDetails += "`n$([System.IO.Path]::GetFileName($logPath)): $($errorLines[-3..-1] -join '; ')"
                }
            } catch { }
        }
    }
    return $errorDetails
}

function Install-CcSwitchPackage {
    <#
    .SYNOPSIS
    安装 CC-Switch 安装包
    .PARAMETER InstallerPath
    安装包路径
    .RETURNS
    安装结果对象
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string] $InstallerPath
    )

    try {
        # 解析 InstallerPath 为长路径，避免 8.3 短路径导致 msiexec 失败
        $InstallerPath = try {
            if (Test-Path $InstallerPath) {
                (Get-Item $InstallerPath).FullName
            } else {
                [System.IO.Path]::GetFullPath($InstallerPath)
            }
        } catch {
            $InstallerPath
        }

        $fileExtension = [System.IO.Path]::GetExtension($InstallerPath).ToLower()

        switch ($fileExtension) {
            ".msi" {
                Write-Host "  正在执行 MSI 安装..." -ForegroundColor Gray

                # 策略 1：per-user 安装（不需要管理员权限）
                Write-Host "  尝试 per-user 安装模式..." -ForegroundColor Gray
                $perUserArgs = @(
                    "/i", "`"$InstallerPath`"",
                    "/qn",
                    "ALLUSERS=2",
                    "MSIINSTALLPERUSER=1",
                    "REBOOT=ReallySuppress",
                    "/norestart",
                    "/l*v", "`"$script:TempDownloadDir\install-peruser.log`""
                )
                $perUserResult = Invoke-ExternalCommand -Command "msiexec" -Arguments $perUserArgs -TimeoutSeconds 300

                if ($perUserResult.Success -or $perUserResult.ExitCode -eq 3010) {
                    $rebootHint = if ($perUserResult.ExitCode -eq 3010) { "（需重启生效）" } else { "" }
                    Write-Host "  ✓ MSI per-user 安装完成$rebootHint" -ForegroundColor Green
                } else {
                    # 策略 2：全局静默安装（需要管理员）
                    Write-Host "  per-user 安装失败 (退出码: $($perUserResult.ExitCode))，尝试全局安装..." -ForegroundColor Yellow
                    $globalArgs = @(
                        "/i", "`"$InstallerPath`"",
                        "/quiet",
                        "/norestart",
                        "/l*v", "`"$script:TempDownloadDir\install.log`""
                    )
                    $globalResult = Invoke-ExternalCommand -Command "msiexec" -Arguments $globalArgs -TimeoutSeconds 300

                    if ($globalResult.Success -or $globalResult.ExitCode -eq 3010) {
                        $rebootHint = if ($globalResult.ExitCode -eq 3010) { "（需重启生效）" } else { "" }
                        Write-Host "  ✓ MSI 全局安装完成$rebootHint" -ForegroundColor Green
                    } else {
                        # 策略 3：GUI 安装降级（让用户手动操作）
                        Write-Host "  静默安装均失败，启动 GUI 安装..." -ForegroundColor Yellow
                        Write-Host "  请在弹出的安装向导中手动完成安装" -ForegroundColor Cyan
                        $guiResult = Invoke-ExternalCommand -Command "msiexec" -Arguments @("/i", "`"$InstallerPath`"") -TimeoutSeconds 600

                        if (-not $guiResult.Success -and $guiResult.ExitCode -ne 3010) {
                            $errorDetails = Get-MsiLogErrors
                            throw "MSI 安装失败（per-user: $($perUserResult.ExitCode), 全局: $($globalResult.ExitCode), GUI: $($guiResult.ExitCode)）$errorDetails"
                        }
                    }
                }
            }

            ".exe" {
                Write-Host "  正在执行 EXE 静默安装..." -ForegroundColor Gray

                # 尝试常见的静默安装参数
                $silentArgs = @("/S", "/SILENT", "/VERYSILENT", "/quiet", "/q")
                $installSuccess = $false

                foreach ($arg in $silentArgs) {
                    try {
                        Write-Host "    尝试参数: $arg" -ForegroundColor Gray
                        $result = Invoke-ExternalCommand -Command $InstallerPath -Arguments @($arg) -TimeoutSeconds 300

                        if ($result.Success) {
                            Write-Host "  ✓ EXE 安装完成 (参数: $arg)" -ForegroundColor Green
                            $installSuccess = $true
                            break
                        }
                    } catch {
                        continue
                    }
                }

                if (-not $installSuccess) {
                    throw "EXE 静默安装失败，尝试了所有常见参数"
                }
            }

            default {
                throw "不支持的安装包格式: $fileExtension"
            }
        }

        return @{
            Success = $true
            InstallerType = $fileExtension
            Message = "安装成功"
        }

    } catch {
        return @{
            Success = $false
            ErrorMessage = $_.Exception.Message
        }
    }
}

function Verify-CcSwitch {
    <#
    .SYNOPSIS
    验证 CC-Switch 安装
    .RETURNS
    布尔值，表示验证是否成功
    #>
    param()

    $testResult = Test-CcSwitchInstalled
    return @{ Success = [bool]$testResult.IsInstalled; ErrorMessage = if (-not $testResult.IsInstalled) { $testResult.Message } else { "" } }
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用