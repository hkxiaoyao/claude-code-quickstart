# 外部命令执行封装 - Claude Code 环境安装器
# 作者: 哈雷酱 (本小姐的专业封装！)
# 功能: 提供外部命令执行、PATH 刷新、版本检测等核心功能

#Requires -Version 5.1

# 严格模式
Set-StrictMode -Version Latest

# 全局配置
$script:DefaultRetryCount = 3
$script:DefaultTimeoutSeconds = 300

function Invoke-ExternalCommand {
    <#
    .SYNOPSIS
    通用外部命令执行函数，支持重试和详细错误处理
    .PARAMETER Command
    要执行的命令
    .PARAMETER Arguments
    命令参数数组
    .PARAMETER WorkingDirectory
    工作目录
    .PARAMETER TimeoutSeconds
    超时时间（秒）
    .PARAMETER RetryCount
    重试次数
    .PARAMETER SuppressOutput
    抑制输出
    .RETURNS
    包含 ExitCode, Output, Error 的对象
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [string[]]$Arguments = @(),

        [string]$WorkingDirectory = $PWD,

        [int]$TimeoutSeconds = $script:DefaultTimeoutSeconds,

        [int]$RetryCount = $script:DefaultRetryCount,

        [switch]$SuppressOutput
    )

    $result = @{
        ExitCode = -1
        Output = ""
        Error = ""
        Success = $false
        Command = "$Command $($Arguments -join ' ')"
    }

    for ($attempt = 1; $attempt -le ($RetryCount + 1); $attempt++) {
        try {
            if (-not $SuppressOutput -and $attempt -gt 1) {
                Write-Host "重试第 $($attempt - 1) 次: $($result.Command)" -ForegroundColor Yellow
            }

            # 构建进程启动信息
            $processInfo = New-Object System.Diagnostics.ProcessStartInfo
            $processInfo.FileName = $Command
            $processInfo.Arguments = $Arguments -join ' '
            $processInfo.WorkingDirectory = $WorkingDirectory
            $processInfo.UseShellExecute = $false
            $processInfo.RedirectStandardOutput = $true
            $processInfo.RedirectStandardError = $true
            $processInfo.CreateNoWindow = $true

            # 启动进程
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $processInfo

            # 输出和错误收集（通过 -MessageData 传递共享状态，避免事件处理器作用域隔离问题）
            $sharedState = @{
                Output = New-Object System.Text.StringBuilder
                Error  = New-Object System.Text.StringBuilder
            }

            # 注册事件处理器
            $outputEvent = Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -MessageData $sharedState -Action {
                if ($Event.SourceEventArgs.Data) {
                    [void]$Event.MessageData.Output.AppendLine($Event.SourceEventArgs.Data)
                }
            }

            $errorEvent = Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -MessageData $sharedState -Action {
                if ($Event.SourceEventArgs.Data) {
                    [void]$Event.MessageData.Error.AppendLine($Event.SourceEventArgs.Data)
                }
            }

            try {
                # 启动进程并开始异步读取
                [void]$process.Start()
                $process.BeginOutputReadLine()
                $process.BeginErrorReadLine()

                # 等待进程完成或超时（循环轮询 + 延迟心跳输出）
                $elapsed = 0
                $heartbeatInterval = 1
                $heartbeatDelaySeconds = 2
                $heartbeatShown = $false
                while (-not $process.WaitForExit($heartbeatInterval * 1000)) {
                    $elapsed += $heartbeatInterval
                    if (-not $SuppressOutput -and $elapsed -ge $heartbeatDelaySeconds) {
                        Write-Host "`r  等待中... ($elapsed 秒)" -NoNewline
                        $heartbeatShown = $true
                    }
                    if ($elapsed -ge $TimeoutSeconds) {
                        if ($heartbeatShown) { Write-Host "" }
                        $process.Kill()
                        throw "命令执行超时 ($TimeoutSeconds 秒): $($result.Command)"
                    }
                }
                if ($heartbeatShown) { Write-Host "" }

                # 等待异步读取完成
                $process.WaitForExit()

                # 收集结果
                $result.ExitCode = $process.ExitCode
                $result.Output = $sharedState.Output.ToString().Trim()
                $result.Error = $sharedState.Error.ToString().Trim()
                $result.Success = ($process.ExitCode -eq 0)

                if ($result.Success) {
                    if (-not $SuppressOutput -and $result.Output) {
                        Write-Host $result.Output
                    }
                    return $result
                } else {
                    $errorMessage = "命令执行失败 (退出码: $($result.ExitCode)): $($result.Command)"
                    if ($result.Error) {
                        $errorMessage += "`n错误输出: $($result.Error)"
                    }

                    if ($attempt -le $RetryCount) {
                        Write-Host $errorMessage -ForegroundColor Yellow
                        Start-Sleep -Seconds (2 * $attempt)  # 递增延迟
                        continue
                    } else {
                        throw $errorMessage
                    }
                }
            } finally {
                # 清理事件处理器和关联的后台作业
                if ($outputEvent) {
                    Unregister-Event -SourceIdentifier $outputEvent.Name -ErrorAction SilentlyContinue
                    Remove-Job -Id $outputEvent.Id -Force -ErrorAction SilentlyContinue
                }
                if ($errorEvent) {
                    Unregister-Event -SourceIdentifier $errorEvent.Name -ErrorAction SilentlyContinue
                    Remove-Job -Id $errorEvent.Id -Force -ErrorAction SilentlyContinue
                }

                # 确保进程被清理
                if (-not $process.HasExited) {
                    try { $process.Kill() } catch { }
                }
                $process.Dispose()
            }
        } catch {
            $result.Error = $_.Exception.Message

            if ($attempt -le $RetryCount) {
                Write-Host "执行失败，准备重试: $($_.Exception.Message)" -ForegroundColor Yellow
                Start-Sleep -Seconds (2 * $attempt)
                continue
            } else {
                throw
            }
        }
    }

    return $result
}

function Invoke-WingetInstall {
    <#
    .SYNOPSIS
    使用 winget 安装软件包的模板函数
    .PARAMETER PackageId
    软件包 ID
    .PARAMETER PackageName
    软件包显示名称（用于日志）
    .PARAMETER AcceptLicense
    自动接受许可证
    .PARAMETER Silent
    静默安装
    .PARAMETER Force
    强制安装
    .RETURNS
    安装结果对象
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageId,

        [string]$PackageName = $PackageId,

        [switch]$AcceptLicense,

        [switch]$Silent,

        [switch]$Force
    )

    # 检查 winget 可用性
    if (-not (Test-CommandAvailable -Command "winget")) {
        throw "winget 不可用，无法安装 $PackageName"
    }

    # 构建参数
    $arguments = @("install", "--id", $PackageId, "-e", "--source", "winget", "--disable-interactivity")

    if ($AcceptLicense) { $arguments += "--accept-package-agreements", "--accept-source-agreements" }
    if ($Silent) { $arguments += "--silent" }
    if ($Force) { $arguments += "--force" }

    Write-Host "正在安装 $PackageName..." -ForegroundColor Cyan

    $maxAttempts = 2
    $timeoutSeconds = 300

    try {
        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            $wingetProcess = $null
            try {
                if ($attempt -gt 1) {
                    Write-Host "重试第 $($attempt - 1) 次安装: $PackageName" -ForegroundColor Yellow
                }

                # 直通模式：让 winget 输出直接写入当前控制台，保留原生 ANSI 进度条
                $wingetProcess = Start-Process -FilePath "winget" -ArgumentList $arguments -NoNewWindow -PassThru -ErrorAction Stop

                # 超时保护：避免 winget 异常时无限等待
                if (-not $wingetProcess.WaitForExit($timeoutSeconds * 1000)) {
                    try { $wingetProcess.Kill() } catch { }
                    throw "winget 安装超时 ($timeoutSeconds 秒)"
                }

                if ($wingetProcess.ExitCode -eq 0) {
                    Write-Host "✓ $PackageName 安装成功" -ForegroundColor Green

                    # 刷新 PATH 以确保新安装的命令可用
                    Refresh-SessionPath

                    return @{
                        Success = $true
                        PackageId = $PackageId
                        PackageName = $PackageName
                        Output = ""
                    }
                } else {
                    throw "winget 安装失败 (退出码: $($wingetProcess.ExitCode))"
                }
            } catch {
                if ($attempt -lt $maxAttempts) {
                    Write-Host "安装失败，准备重试: $($_.Exception.Message)" -ForegroundColor Yellow
                    Start-Sleep -Seconds (2 * $attempt)
                    continue
                }
                throw
            } finally {
                if ($wingetProcess) { $wingetProcess.Dispose() }
            }
        }
    } catch {
        Write-Host "✗ $PackageName 安装失败: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

function Invoke-NpmGlobalInstall {
    <#
    .SYNOPSIS
    使用 npm 全局安装包的模板函数
    .PARAMETER PackageName
    npm 包名
    .PARAMETER Version
    指定版本
    .PARAMETER Force
    强制安装
    .RETURNS
    安装结果对象
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageName,

        [string]$Version,

        [switch]$Force
    )

    # 检查 npm 可用性
    if (-not (Test-CommandAvailable -Command "npm")) {
        throw "npm 不可用，无法安装 $PackageName"
    }

    # 构建包名和版本
    $fullPackageName = $PackageName
    if ($Version) {
        $fullPackageName += "@$Version"
    }

    # 构建参数
    $arguments = @("install", "-g", $fullPackageName)
    if ($Force) { $arguments += "--force" }

    Write-Host "正在全局安装 npm 包: $fullPackageName..." -ForegroundColor Cyan

    try {
        $result = Invoke-ExternalCommand -Command "npm" -Arguments $arguments -TimeoutSeconds 300

        if ($result.Success) {
            Write-Host "✓ $fullPackageName 安装成功" -ForegroundColor Green

            # 刷新 PATH 以确保新安装的命令可用
            Refresh-SessionPath

            return @{
                Success = $true
                PackageName = $PackageName
                Version = $Version
                FullPackageName = $fullPackageName
                Output = $result.Output
            }
        } else {
            throw "npm 安装失败: $($result.Error)"
        }
    } catch {
        Write-Host "✗ $fullPackageName 安装失败: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

function Test-CommandAvailable {
    <#
    .SYNOPSIS
    检测命令是否可用
    .PARAMETER Command
    要检测的命令名
    .RETURNS
    布尔值，表示命令是否可用
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    try {
        # 使用 Get-Command 检测命令
        $null = Get-Command $Command -ErrorAction Stop
        return $true
    } catch {
        # 如果 Get-Command 失败，尝试直接执行 --version 或 -v
        try {
            $result = Invoke-ExternalCommand -Command $Command -Arguments @("--version") -SuppressOutput -TimeoutSeconds 10 -RetryCount 0
            return $result.Success
        } catch {
            try {
                $result = Invoke-ExternalCommand -Command $Command -Arguments @("-v") -SuppressOutput -TimeoutSeconds 10 -RetryCount 0
                return $result.Success
            } catch {
                return $false
            }
        }
    }
}

function Get-CommandVersion {
    <#
    .SYNOPSIS
    获取命令的版本信息
    .PARAMETER Command
    要获取版本的命令名
    .PARAMETER VersionArgument
    版本参数（默认 --version）
    .RETURNS
    版本字符串，如果无法获取则返回 "未知"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [string]$VersionArgument = "--version"
    )

    if (-not (Test-CommandAvailable -Command $Command)) {
        return "未安装"
    }

    # 特殊处理：对于 PowerShell 命令，直接使用 Get-Command 获取版本
    if ($Command -eq "pwsh" -or $Command -eq "powershell") {
        try {
            $cmdInfo = Get-Command $Command -ErrorAction Stop
            if ($cmdInfo.Version) {
                return $cmdInfo.Version.ToString()
            }
        } catch {
            # 如果 Get-Command 失败，继续使用外部命令方式
        }
    }

    try {
        $result = Invoke-ExternalCommand -Command $Command -Arguments @($VersionArgument) -SuppressOutput -TimeoutSeconds 30 -RetryCount 0

        if ($result.Success -and $result.Output) {
            # 尝试从输出中提取版本号
            $versionPattern = '(\d+\.[\d\.]+[\w\-]*)'
            if ($result.Output -match $versionPattern) {
                return $matches[1]
            } else {
                # 如果没有匹配到标准版本格式，返回第一行
                $firstLine = ($result.Output -split "`n")[0].Trim()
                return $firstLine
            }
        } else {
            return "未知"
        }
    } catch {
        # 如果 --version 失败，尝试 -v
        if ($VersionArgument -eq "--version") {
            return Get-CommandVersion -Command $Command -VersionArgument "-v"
        } else {
            return "未知"
        }
    }
}

function Refresh-SessionPath {
    <#
    .SYNOPSIS
    从注册表读取并刷新当前会话的 PATH 环境变量
    .DESCRIPTION
    当安装新软件后，PATH 可能已在注册表中更新，但当前 PowerShell 会话还未感知到变化。
    此函数从注册表重新读取 PATH 并注入到当前会话中。
    #>
    param()

    try {
        Write-Host "正在刷新 PATH 环境变量..." -ForegroundColor Cyan

        # 读取系统级 PATH
        $systemPath = ""
        try {
            $systemPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        } catch {
            Write-Host "警告: 无法读取系统级 PATH" -ForegroundColor Yellow
        }

        # 读取用户级 PATH
        $userPath = ""
        try {
            $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        } catch {
            Write-Host "警告: 无法读取用户级 PATH" -ForegroundColor Yellow
        }

        # 合并 PATH
        $newPath = @()
        if ($systemPath) { $newPath += $systemPath -split ';' }
        if ($userPath) { $newPath += $userPath -split ';' }

        # 去重并过滤空值
        $newPath = $newPath | Where-Object { $_ -and $_.Trim() } | Select-Object -Unique

        # 更新当前会话的 PATH
        $env:PATH = $newPath -join ';'

        Write-Host "✓ PATH 环境变量已刷新" -ForegroundColor Green

        # 验证一些常见命令是否现在可用
        $commonCommands = @("node", "npm", "git", "winget", "pwsh", "claude")
        $availableCommands = @()

        foreach ($cmd in $commonCommands) {
            if (Test-CommandAvailable -Command $cmd) {
                $availableCommands += $cmd
            }
        }

        if ($availableCommands.Count -gt 0) {
            Write-Host "可用命令: $($availableCommands -join ', ')" -ForegroundColor Green
        }

    } catch {
        Write-Host "警告: PATH 刷新失败: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Test-InternetConnection {
    <#
    .SYNOPSIS
    测试网络连接
    .PARAMETER TestUrls
    要测试的 URL 数组
    .PARAMETER TimeoutSeconds
    每个测试的超时时间
    .RETURNS
    连接测试结果对象
    #>
    param(
        [string[]]$TestUrls = @(
            "https://www.google.com",
            "https://github.com",
            "https://registry.npmjs.org"
        ),

        [int]$TimeoutSeconds = 10
    )

    $results = @{
        Success = $false
        TestedUrls = @()
        FailedUrls = @()
        ErrorMessage = ""
    }

    foreach ($url in $TestUrls) {
        try {
            Write-Host "测试连接: $url" -ForegroundColor Cyan

            $request = [System.Net.WebRequest]::Create($url)
            $request.Timeout = $TimeoutSeconds * 1000
            $request.Method = "HEAD"

            $response = $request.GetResponse()
            $response.Close()

            $results.TestedUrls += $url
            Write-Host "✓ $url 连接成功" -ForegroundColor Green

        } catch {
            $results.FailedUrls += $url
            Write-Host "✗ $url 连接失败: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    $results.Success = $results.TestedUrls.Count -gt 0

    if (-not $results.Success) {
        $results.ErrorMessage = "所有网络连接测试都失败了"
    }

    return $results
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用