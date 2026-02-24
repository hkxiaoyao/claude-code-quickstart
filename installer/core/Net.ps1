# 网络和代理检测 - CCQ
# 功能: 提供网络连通性检测、代理配置快照、网络健康评估等功能

#Requires -Version 5.1

Set-StrictMode -Version Latest

# 需要测试的关键端点
$script:KeyEndpoints = @{
    NpmRegistry = "https://registry.npmjs.org"
    GitHub      = "https://github.com"
    ClaudeApi   = "https://api.anthropic.com"
    WingetSrc   = "https://cdn.winget.microsoft.com"
}

function Test-EndpointReachable {
    <#
    .SYNOPSIS
    测试单个端点的可达性
    .PARAMETER Url
    要测试的 URL
    .PARAMETER TimeoutSeconds
    超时时间（秒，默认 8）
    .RETURNS
    包含 Url, Reachable, StatusCode, ErrorMessage 的对象
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [int]$TimeoutSeconds = 8
    )

    $result = [PSCustomObject]@{
        Url          = $Url
        Reachable    = $false
        StatusCode   = $null
        ErrorMessage = ""
        LatencyMs    = -1
    }

    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.Method = "HEAD"
        $request.Timeout = $TimeoutSeconds * 1000
        $request.AllowAutoRedirect = $true
        $request.UserAgent = "ClaudeEnvInstaller/1.0"

        # 应用系统代理（如果已配置）
        $request.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
        $request.Proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials

        $response = $request.GetResponse()
        $sw.Stop()

        $result.Reachable = $true
        $result.StatusCode = [int]$response.StatusCode
        $result.LatencyMs = $sw.ElapsedMilliseconds
        $response.Close()

    } catch [System.Net.WebException] {
        $sw.Stop()
        $result.LatencyMs = $sw.ElapsedMilliseconds

        $webEx = $_.Exception
        if ($webEx.Response) {
            $result.StatusCode = [int]$webEx.Response.StatusCode
            # 4xx/5xx 也算可达（服务器有响应）
            if ($result.StatusCode -ge 200 -and $result.StatusCode -lt 600) {
                $result.Reachable = $true
            }
        }
        $result.ErrorMessage = $webEx.Message
    } catch {
        $sw.Stop()
        $result.ErrorMessage = $_.Exception.Message
    }

    return $result
}

function Test-NetworkPrerequisites {
    <#
    .SYNOPSIS
    检测安装所需的全部网络连通性
    .RETURNS
    包含各端点结果和整体评级的对象
    #>
    param()

    Write-Host "正在检测网络连通性..." -ForegroundColor Cyan

    $endpointResults = @{}
    foreach ($key in $script:KeyEndpoints.Keys) {
        $url = $script:KeyEndpoints[$key]
        Write-Host "  检测 $key ($url)..." -ForegroundColor Gray -NoNewline
        $r = Test-EndpointReachable -Url $url
        $endpointResults[$key] = $r

        if ($r.Reachable) {
            Write-Host " ✓ ($($r.LatencyMs)ms)" -ForegroundColor Green
        } else {
            Write-Host " ✗ $($r.ErrorMessage)" -ForegroundColor Red
        }
    }

    $reachableCount = @($endpointResults.Values | Where-Object { $_.Reachable }).Count
    $totalCount = $endpointResults.Count

    # 评级：全部可达=绿，部分可达=黄，全部不通=红
    $health = switch ($reachableCount) {
        { $_ -eq $totalCount } { "Green" }
        { $_ -gt 0 }           { "Yellow" }
        default                 { "Red" }
    }

    return [PSCustomObject]@{
        Endpoints      = $endpointResults
        ReachableCount = $reachableCount
        TotalCount     = $totalCount
        Health         = $health
    }
}

function Get-ProxySnapshot {
    <#
    .SYNOPSIS
    快照当前系统中所有代理配置（仅读取，不写入）
    .RETURNS
    包含各来源代理配置的对象
    #>
    param()

    $snapshot = [PSCustomObject]@{
        EnvHttpProxy  = $env:HTTP_PROXY
        EnvHttpsProxy = $env:HTTPS_PROXY
        EnvNoProxy    = $env:NO_PROXY
        WinHttpProxy  = $null
        GitHttpProxy  = $null
        GitHttpsProxy = $null
        NpmProxy      = $null
        HasAnyProxy   = $false
    }

    # 读取 WinHTTP 代理（netsh winhttp show proxy）
    try {
        $netshOut = & netsh winhttp show proxy 2>&1
        $proxyLine = $netshOut | Where-Object { $_ -match "Proxy Server\(s\)|代理服务器" } | Select-Object -First 1
        if ($proxyLine -and $proxyLine -notmatch "Direct|直接") {
            $snapshot.WinHttpProxy = ($proxyLine -replace ".*:\s*", "").Trim()
        }
    } catch { }

    # 读取 git 代理配置
    try {
        $gitHttpProxy = & git config --global http.proxy 2>&1
        if ($LASTEXITCODE -eq 0 -and $gitHttpProxy) {
            $snapshot.GitHttpProxy = $gitHttpProxy.Trim()
        }
    } catch { }

    try {
        $gitHttpsProxy = & git config --global https.proxy 2>&1
        if ($LASTEXITCODE -eq 0 -and $gitHttpsProxy) {
            $snapshot.GitHttpsProxy = $gitHttpsProxy.Trim()
        }
    } catch { }

    # 读取 npm 代理
    try {
        $npmProxy = & npm config get proxy 2>&1
        if ($LASTEXITCODE -eq 0 -and $npmProxy -and $npmProxy -ne "null") {
            $snapshot.NpmProxy = $npmProxy.Trim()
        }
    } catch { }

    # 判断是否存在任何代理
    $snapshot.HasAnyProxy = (
        $snapshot.EnvHttpProxy -or
        $snapshot.EnvHttpsProxy -or
        $snapshot.WinHttpProxy -or
        $snapshot.GitHttpProxy -or
        $snapshot.NpmProxy
    )

    return $snapshot
}

function Get-NetworkHealth {
    <#
    .SYNOPSIS
    综合评估网络健康度，输出分级结果
    .RETURNS
    Green / Yellow / Red 及建议说明
    #>
    param()

    $prereq = Test-NetworkPrerequisites
    $proxy  = Get-ProxySnapshot

    $advice = @()

    switch ($prereq.Health) {
        "Green"  {
            Write-Host "✓ 网络状态：绿色（所有端点可达）" -ForegroundColor Green
        }
        "Yellow" {
            Write-Host "⚠ 网络状态：黄色（部分端点不可达，$($prereq.ReachableCount)/$($prereq.TotalCount)）" -ForegroundColor Yellow
            $advice += "建议检查防火墙或代理配置，部分安装步骤可能受影响"
        }
        "Red" {
            Write-Host "✗ 网络状态：红色（所有端点不可达）" -ForegroundColor Red
            $advice += "请确认网络连接正常后再继续安装"
        }
    }

    if ($proxy.HasAnyProxy) {
        Write-Host "  检测到代理配置：" -ForegroundColor Cyan
        if ($proxy.EnvHttpProxy)  { Write-Host "    HTTP_PROXY  = $($proxy.EnvHttpProxy)"  -ForegroundColor Gray }
        if ($proxy.EnvHttpsProxy) { Write-Host "    HTTPS_PROXY = $($proxy.EnvHttpsProxy)" -ForegroundColor Gray }
        if ($proxy.WinHttpProxy)  { Write-Host "    WinHTTP     = $($proxy.WinHttpProxy)"  -ForegroundColor Gray }
        if ($proxy.GitHttpProxy)  { Write-Host "    git http    = $($proxy.GitHttpProxy)"  -ForegroundColor Gray }
        if ($proxy.NpmProxy)      { Write-Host "    npm proxy   = $($proxy.NpmProxy)"      -ForegroundColor Gray }
    }

    return [PSCustomObject]@{
        Health        = $prereq.Health
        Prerequisite  = $prereq
        ProxySnapshot = $proxy
        Advice        = $advice
    }
}

function Invoke-FileDownload {
    <#
    .SYNOPSIS
    统一的文件下载函数，带进度条显示
    .DESCRIPTION
    使用 HttpWebRequest + 异步轮询（APM 模式）实现带实时进度条的文件下载。
    所有网络 I/O 均为异步发起 + Start-Sleep 轮询，确保 CTRL+C 可随时中断。
    .PARAMETER Url
    下载地址
    .PARAMETER OutputPath
    输出文件路径
    .PARAMETER Description
    下载描述（可选，用于显示）
    .PARAMETER TimeoutSeconds
    超时时间（秒，默认 300）
    .RETURNS
    @{Success; FilePath; ErrorMessage; FileSize}
    .EXAMPLE
    $result = Invoke-FileDownload -Url "https://example.com/file.zip" -OutputPath "C:\temp\file.zip"
    if ($result.Success) {
        Write-Host "下载成功: $($result.FilePath)"
    }
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string] $Url,

        [Parameter(Mandatory = $true)]
        [string] $OutputPath,

        [Parameter(Mandatory = $false)]
        [string] $Description = "",

        [Parameter(Mandatory = $false)]
        [int] $TimeoutSeconds = 300
    )

    $result = @{
        Success      = $false
        FilePath     = $OutputPath
        ErrorMessage = ""
        FileSize     = 0
    }

    try {
        # 确保输出目录存在
        $outputDir = Split-Path -Path $OutputPath -Parent
        if ($outputDir -and -not (Test-Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }

        # 显示下载信息
        $fileName = Split-Path -Path $OutputPath -Leaf
        if ($Description) {
            Write-Host "  正在下载: $Description" -ForegroundColor Gray
        } else {
            Write-Host "  正在下载: $fileName" -ForegroundColor Gray
        }
        Write-Host "  下载地址: $Url" -ForegroundColor Gray

        # 仅允许 TLS 1.2+，禁用不安全的旧协议
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13

        # 使用 HttpWebRequest + 异步轮询（CTRL+C 可中断）
        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.Method = "GET"
        $request.Timeout = $TimeoutSeconds * 1000
        $request.ReadWriteTimeout = $TimeoutSeconds * 1000
        $request.AllowAutoRedirect = $true
        $request.UserAgent = "ClaudeEnvInstaller/1.0"
        $request.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
        $request.Proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials

        $response = $null
        $responseStream = $null
        $fileStream = $null
        $downloadSuccess = $false

        try {
            # ── 阶段 1：异步连接（CTRL+C 可中断） ──
            Write-Host "  正在连接..." -NoNewline -ForegroundColor Gray
            $asyncConnect = $request.BeginGetResponse($null, $null)
            $connectDeadline = (Get-Date).AddSeconds($TimeoutSeconds)

            while (-not $asyncConnect.IsCompleted) {
                if ((Get-Date) -gt $connectDeadline) {
                    $request.Abort()
                    throw "连接超时 ($TimeoutSeconds 秒)"
                }
                Start-Sleep -Milliseconds 300
            }

            $response = $request.EndGetResponse($asyncConnect)
            Write-Host " 已连接" -ForegroundColor Green

            $totalBytes = $response.ContentLength  # -1 if unknown
            $responseStream = $response.GetResponseStream()
            $fileStream = [System.IO.File]::Create($OutputPath)

            $buffer = New-Object byte[] 8192
            $totalRead = [long]0
            $lastPercent = -1
            $lastProgressTime = [DateTime]::MinValue
            $startTime = Get-Date

            # ── 阶段 2：异步读取 + 进度显示（CTRL+C 可中断） ──
            while ($true) {
                $asyncRead = $responseStream.BeginRead($buffer, 0, $buffer.Length, $null, $null)

                while (-not $asyncRead.IsCompleted) {
                    Start-Sleep -Milliseconds 50
                }

                $bytesRead = $responseStream.EndRead($asyncRead)
                if ($bytesRead -le 0) { break }

                $fileStream.Write($buffer, 0, $bytesRead)
                $totalRead += $bytesRead

                # 主线程更新进度条
                $now = Get-Date
                $elapsed = $now - $startTime
                $speed = if ($elapsed.TotalSeconds -gt 0) { $totalRead / $elapsed.TotalSeconds } else { 0 }
                $speedMB = [math]::Round($speed / 1MB, 2)
                $receivedMB = [math]::Round($totalRead / 1MB, 2)

                if ($totalBytes -gt 0) {
                    # 已知总大小：显示百分比进度条
                    $percent = [math]::Min([math]::Floor($totalRead * 100 / $totalBytes), 100)
                    if ($percent -ne $lastPercent) {
                        $lastPercent = $percent
                        $totalMB = [math]::Round($totalBytes / 1MB, 2)

                        $barLength = 40
                        $completed = [math]::Floor($barLength * $percent / 100)
                        $remaining = $barLength - $completed
                        $bar = "[" + ("=" * $completed) + (">" * [math]::Min(1, $remaining)) + (" " * [math]::Max(0, $remaining - 1)) + "]"

                        Write-Host "`r  $bar $percent% ($receivedMB/$totalMB MB) $speedMB MB/s    " -NoNewline -ForegroundColor Cyan
                    }
                } else {
                    # 未知总大小：节流刷新（每 500ms 更新一次）
                    if (($now - $lastProgressTime).TotalMilliseconds -ge 500) {
                        $lastProgressTime = $now
                        Write-Host "`r  正在下载... $receivedMB MB | $speedMB MB/s    " -NoNewline -ForegroundColor Cyan
                    }
                }
            }

            $fileStream.Flush()
            $fileStream.Close()
            $fileStream = $null

            # 下载完成后换行
            Write-Host ""

            # 完整性校验：已知长度时验证实际字节数
            if ($totalBytes -gt 0 -and $totalRead -ne $totalBytes) {
                throw "下载不完整: 预期 $totalBytes 字节，实际接收 $totalRead 字节"
            }

            # 验证下载文件
            if (-not (Test-Path $OutputPath)) {
                throw "下载的文件不存在"
            }

            $fileInfo = Get-Item $OutputPath
            if ($fileInfo.Length -eq 0) {
                throw "下载的文件为空"
            }

            $downloadSuccess = $true
            $result.Success = $true
            $result.FileSize = $fileInfo.Length
            Write-Host "  ✓ 下载完成: $([math]::Round($fileInfo.Length / 1MB, 2)) MB" -ForegroundColor Green

        } finally {
            # 中止请求，取消任何挂起的异步操作
            try { $request.Abort() } catch { }
            if ($fileStream)     { $fileStream.Close() }
            if ($responseStream) { $responseStream.Close() }
            if ($response)       { $response.Close() }

            # 失败时清理残留的部分文件，防止污染后续重试
            if (-not $downloadSuccess -and (Test-Path $OutputPath)) {
                try { Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue } catch { }
            }
        }

    } catch {
        $result.ErrorMessage = $_.Exception.Message
        Write-Host ""
        Write-Host "  下载失败: $($result.ErrorMessage)" -ForegroundColor Red

        # 清理失败的文件（兜底）
        if (Test-Path $OutputPath) {
            try {
                Remove-Item $OutputPath -Force -ErrorAction SilentlyContinue
            } catch { }
        }
    }

    return $result
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用
