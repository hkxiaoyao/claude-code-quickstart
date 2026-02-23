# 外部命令执行封装 - CCQ
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
    包含 ExitCode, Output, Error, ResolvedPath 的对象
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
        ResolvedPath = ""
    }

    # 先解析命令路径，确定执行方式
    $cmdInfo = $null
    $actualFileName = $Command
    $actualArguments = $Arguments

    try {
        $cmdInfo = Get-Command $Command -ErrorAction Stop
        $result.ResolvedPath = $cmdInfo.Source

        # 根据命令类型选择执行方式
        if ($cmdInfo.CommandType -eq 'Application' -or $cmdInfo.CommandType -eq 'ExternalScript') {
            $extension = [System.IO.Path]::GetExtension($cmdInfo.Source).ToLower()

            # 对于 .cmd/.bat 文件，需要通过 cmd.exe 执行
            if ($extension -eq '.cmd' -or $extension -eq '.bat') {
                $actualFileName = 'cmd.exe'
                # 构建完整的命令字符串（路径 + 参数）
                $cmdPath = $cmdInfo.Source
                if ($cmdPath -match '\s') {
                    $cmdPath = "`"$cmdPath`""
                }
                $fullCommand = $cmdPath
                if ($Arguments.Count -gt 0) {
                    $fullCommand += " " + ($Arguments -join ' ')
                }
                $actualArguments = @('/d', '/s', '/c', $fullCommand)
            }
            # 对于 .ps1 文件，通过 powershell 执行
            elseif ($extension -eq '.ps1') {
                $actualFileName = 'pwsh.exe'
                $actualArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $cmdInfo.Source) + $Arguments
            }
            # 对于 .exe 文件，直接使用解析后的完整路径
            elseif ($extension -eq '.exe') {
                $actualFileName = $cmdInfo.Source
            }
        }
    } catch {
        # Get-Command 失败，尝试直接执行（可能是系统命令）
        $result.ResolvedPath = "未解析"
    }

    for ($attempt = 1; $attempt -le ($RetryCount + 1); $attempt++) {
        try {
            if (-not $SuppressOutput -and $attempt -gt 1) {
                Write-Host "重试第 $($attempt - 1) 次: $($result.Command)" -ForegroundColor Yellow
            }

            # 构建进程启动信息
            $processInfo = New-Object System.Diagnostics.ProcessStartInfo
            $processInfo.FileName = $actualFileName
            $processInfo.Arguments = $actualArguments -join ' '
            $processInfo.WorkingDirectory = $WorkingDirectory
            $processInfo.UseShellExecute = $false
            $processInfo.RedirectStandardOutput = $true
            $processInfo.RedirectStandardError = $true
            $processInfo.CreateNoWindow = $true

            # 设置 UTF-8 编码避免中文乱码
            try {
                $processInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
                $processInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
            } catch {
                # 低版本运行时可能不支持，保持默认行为
            }

            # 启动进程
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $processInfo

            try {
                # 启动进程
                [void]$process.Start()

                # 同步读取输出（避免快速命令输出丢失）
                $outputBuilder = New-Object System.Text.StringBuilder
                $errorBuilder = New-Object System.Text.StringBuilder

                # 异步读取任务
                $outputTask = $process.StandardOutput.ReadToEndAsync()
                $errorTask = $process.StandardError.ReadToEndAsync()

                # 等待进程完成或超时
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

                # 确保进程完全退出
                $process.WaitForExit()

                # 等待输出读取完成
                $outputText = $outputTask.GetAwaiter().GetResult()
                $errorText = $errorTask.GetAwaiter().GetResult()

                # 收集结果
                $result.ExitCode = $process.ExitCode
                $result.Output = $outputText.Trim()
                $result.Error = $errorText.Trim()
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
                    if ($result.ResolvedPath) {
                        $errorMessage += "`n解析路径: $($result.ResolvedPath)"
                    }

                    if ($attempt -le $RetryCount) {
                        Write-Host $errorMessage -ForegroundColor Yellow
                        Start-Sleep -Seconds (2 * $attempt)
                        continue
                    } else {
                        throw $errorMessage
                    }
                }
            } finally {
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
            $proc = $null
            try {
                if ($attempt -gt 1) {
                    Write-Host "重试第 $($attempt - 1) 次安装: $PackageName" -ForegroundColor Yellow
                }

                # 使用 .NET Process 直通模式：不重定向输出，winget 进度条直接写入控制台
                $procInfo = New-Object System.Diagnostics.ProcessStartInfo
                $procInfo.FileName = "winget"
                $procInfo.Arguments = $arguments -join ' '
                $procInfo.UseShellExecute = $false
                $procInfo.RedirectStandardOutput = $false
                $procInfo.RedirectStandardError = $false
                $procInfo.CreateNoWindow = $false

                $proc = New-Object System.Diagnostics.Process
                $proc.StartInfo = $procInfo
                [void]$proc.Start()

                # 超时保护：避免 winget 异常时无限等待
                if (-not $proc.WaitForExit($timeoutSeconds * 1000)) {
                    try { $proc.Kill() } catch { }
                    throw "winget 安装超时 ($timeoutSeconds 秒)"
                }

                $exitCode = $proc.ExitCode

                if ($exitCode -eq 0) {
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
                    throw "winget 安装失败 (退出码: $exitCode)"
                }
            } catch {
                if ($attempt -lt $maxAttempts) {
                    Write-Host "安装失败，准备重试: $($_.Exception.Message)" -ForegroundColor Yellow
                    Start-Sleep -Seconds (2 * $attempt)
                    continue
                }
                throw
            } finally {
                if ($proc) { $proc.Dispose() }
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
    检测命令是否可用（验证实际可执行性）
    .PARAMETER Command
    要检测的命令名
    .PARAMETER ReturnDetails
    返回详细诊断信息而非布尔值
    .RETURNS
    布尔值（默认）或详细诊断对象（ReturnDetails=true）
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [switch]$ReturnDetails
    )

    $details = @{
        Available = $false
        ResolvedPath = ""
        CommandType = ""
        ExitCode = -1
        ErrorMessage = ""
        Output = ""
    }

    try {
        # 先用 Get-Command 检测命令路径
        $cmdInfo = Get-Command $Command -ErrorAction Stop
        $details.ResolvedPath = $cmdInfo.Source
        $details.CommandType = $cmdInfo.CommandType

        # 如果是外部命令（Application），验证文件是否真实存在
        if ($cmdInfo.CommandType -eq 'Application') {
            $exePath = $cmdInfo.Source
            if (-not (Test-Path $exePath -PathType Leaf)) {
                $details.ErrorMessage = "PATH 中有记录但文件不存在: $exePath"
                if ($ReturnDetails) { return $details }
                return $false
            }
        }

        # 如果是 PowerShell 内置命令（Cmdlet/Function/Alias），Get-Command 成功即可用
        if ($cmdInfo.CommandType -in @('Cmdlet', 'Function', 'Alias')) {
            $details.Available = $true
            if ($ReturnDetails) { return $details }
            return $true
        }

        # 对于外部命令，通过实际执行验证可用性
        try {
            $result = Invoke-ExternalCommand -Command $Command -Arguments @("--version") -SuppressOutput -TimeoutSeconds 10 -RetryCount 0
            $details.ExitCode = $result.ExitCode
            $details.Output = $result.Output
            $details.Available = $result.Success

            if ($result.Success) {
                if ($ReturnDetails) { return $details }
                return $true
            } else {
                $details.ErrorMessage = $result.Error
            }
        } catch {
            # 尝试 -v 参数
            try {
                $result = Invoke-ExternalCommand -Command $Command -Arguments @("-v") -SuppressOutput -TimeoutSeconds 10 -RetryCount 0
                $details.ExitCode = $result.ExitCode
                $details.Output = $result.Output
                $details.Available = $result.Success

                if ($result.Success) {
                    if ($ReturnDetails) { return $details }
                    return $true
                } else {
                    $details.ErrorMessage = $result.Error
                }
            } catch {
                $details.ErrorMessage = $_.Exception.Message
            }
        }

    } catch {
        # Get-Command 失败，尝试直接执行验证
        $details.ErrorMessage = "Get-Command 失败: $($_.Exception.Message)"

        try {
            $result = Invoke-ExternalCommand -Command $Command -Arguments @("--version") -SuppressOutput -TimeoutSeconds 10 -RetryCount 0
            $details.ExitCode = $result.ExitCode
            $details.Output = $result.Output
            $details.Available = $result.Success
            $details.ResolvedPath = $result.ResolvedPath

            if ($result.Success) {
                if ($ReturnDetails) { return $details }
                return $true
            } else {
                $details.ErrorMessage = $result.Error
            }
        } catch {
            try {
                $result = Invoke-ExternalCommand -Command $Command -Arguments @("-v") -SuppressOutput -TimeoutSeconds 10 -RetryCount 0
                $details.ExitCode = $result.ExitCode
                $details.Output = $result.Output
                $details.Available = $result.Success
                $details.ResolvedPath = $result.ResolvedPath

                if ($result.Success) {
                    if ($ReturnDetails) { return $details }
                    return $true
                } else {
                    $details.ErrorMessage = $result.Error
                }
            } catch {
                $details.ErrorMessage = $_.Exception.Message
            }
        }
    }

    if ($ReturnDetails) { return $details }
    return $false
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

        # 合并 PATH（保留当前进程中的 PATH，避免覆盖 fnm 等工具设置的路径）
        $currentPath = $env:PATH -split ';' | Where-Object { $_ -and $_.Trim() }
        $newPath = @()

        # 先添加当前进程的 PATH（包含 fnm use 设置的 Node.js 路径）
        if ($currentPath) { $newPath += $currentPath }

        # 再添加系统级和用户级 PATH
        if ($systemPath) { $newPath += $systemPath -split ';' }
        if ($userPath) { $newPath += $userPath -split ';' }

        # 去重并过滤空值（保持顺序，优先使用当前进程的路径）
        $seen = @{}
        $uniquePath = @()
        foreach ($path in $newPath) {
            $trimmedPath = $path.Trim()
            if ($trimmedPath -and -not $seen.ContainsKey($trimmedPath.ToLower())) {
                $seen[$trimmedPath.ToLower()] = $true
                $uniquePath += $trimmedPath
            }
        }

        # 更新当前会话的 PATH
        $env:PATH = $uniquePath -join ';'

        Write-Host "✓ PATH 环境变量已刷新" -ForegroundColor Green

        # 快速验证常见命令（仅使用 Get-Command，不实际执行）
        $commonCommands = @("node", "npm", "git", "winget", "pwsh", "claude")
        $availableCommands = @()

        foreach ($cmd in $commonCommands) {
            try {
                $cmdInfo = Get-Command $cmd -ErrorAction Stop
                $availableCommands += $cmd
            } catch {
                # 命令不可用，跳过
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