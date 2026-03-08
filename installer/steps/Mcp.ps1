# MCP Server 安装步骤 - CCQ
# 作者: 哈雷酱 (本小姐的专业 MCP 管理！)
# 功能: MCP Server 安装、配置和 API Key 管理

#Requires -Version 5.1

# 严格模式
Set-StrictMode -Version Latest

# 依赖: Ui.ps1, Profile.ps1, Process.ps1, Net.ps1（由入口脚本 dot-source 加载）

# 注: $script:DefaultMcpRuntimeDeps 和 $script:McpServers 已迁移到 core/McpManager.ps1
# 通过 dot-source 共享作用域，$script: 变量在此文件内仍可访问

# ============================================================
# 辅助函数
# ============================================================

function Test-ObjectProperty {
    <#
    .SYNOPSIS
    安全检查对象属性是否存在（StrictMode 兼容）
    #>
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,
        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )

    return $null -ne $InputObject -and
        $null -ne $InputObject.PSObject -and
        ($InputObject.PSObject.Properties.Name -contains $PropertyName)
}

# 注: ConvertTo-NormalizedVersion, Read-McpCredentialValue, Install-McpRuntimeDeps,
# Invoke-McpPreInstall, Get-McpCredentials, New-McpSettingsEntry, Install-McpSoftware,
# Write-McpEnvFile 已迁移到 core/McpManager.ps1

# ============================================================
# 主要函数
# ============================================================

function Test-McpInstalled {
    <#
    .SYNOPSIS
    检测 MCP Server 是否已安装配置（支持 stdio/http/software）
    .RETURNS
    标准检测结果 hashtable（IsInstalled, Version, Data, Message）
    #>

    $claudeJsonPath = "$(Get-UserHome)\.claude.json"
    return Invoke-UnifiedCheck -StepId "Mcp" -DisplayName "MCP Server 配置" `
        -CustomVerify {
            if (-not (Test-Path $claudeJsonPath)) { return $false }

            $claudeJson = Get-Content -Path $claudeJsonPath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
            if (-not $claudeJson) { return $false }

            $hasMcpServers = $claudeJson.ContainsKey("mcpServers") -and $claudeJson["mcpServers"]

            $stdioCount = 0
            $httpCount = 0
            if ($hasMcpServers) {
                foreach ($serverId in @($claudeJson["mcpServers"].Keys)) {
                    $serverConfig = $claudeJson["mcpServers"][$serverId]
                    $hasType = $serverConfig -is [hashtable] -and $serverConfig.ContainsKey("type")
                    $hasUrl = $serverConfig -is [hashtable] -and $serverConfig.ContainsKey("url")
                    $hasCommand = $serverConfig -is [hashtable] -and $serverConfig.ContainsKey("command")
                    $hasArgs = $serverConfig -is [hashtable] -and $serverConfig.ContainsKey("args")

                    if ($hasType -and [string]$serverConfig["type"] -eq "http" -and $hasUrl -and -not [string]::IsNullOrWhiteSpace([string]$serverConfig["url"])) {
                        $httpCount++
                        continue
                    }
                    if ($hasCommand -and $hasArgs -and -not [string]::IsNullOrWhiteSpace([string]$serverConfig["command"]) -and $serverConfig["args"]) {
                        $stdioCount++
                    }
                }
            }

            # 检查 settings.json 中的权限配置
            $settingsPath = Get-ClaudeSettingsPath
            $hasPermissions = $false
            if (Test-Path $settingsPath) {
                $settings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
                if ($settings) {
                    $hasPermissions = $settings -is [hashtable] -and $settings.ContainsKey("permissions") -and
                        $settings["permissions"] -is [hashtable] -and $settings["permissions"].ContainsKey("allow") -and
                        $settings["permissions"]["allow"]
                }
            }

            if (($stdioCount + $httpCount) -gt 0 -and $hasPermissions) {
                Write-UiInfo "  stdio: $stdioCount, http: $httpCount" -Level Detail
                return $true
            }
            return $false
        } -UseCache
}

function Install-Mcp {
    <#
    .SYNOPSIS
    安装 MCP Server 配置（管道模式：依赖 → 预安装 → 凭据 → 软件 → 配置）
    #>

    try {
        Write-UiPrimary "配置 MCP Server..."

        # 检测已安装的 MCP Server
        $claudeJsonPath = "$(Get-UserHome)\.claude.json"
        $existingServers = @()
        if (Test-Path $claudeJsonPath) {
            try {
                $claudeJson = Get-Content -Path $claudeJsonPath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
                if ($claudeJson -and $claudeJson.ContainsKey("mcpServers") -and $claudeJson["mcpServers"]) {
                    $existingServers = @($claudeJson["mcpServers"].Keys)
                    if ($existingServers.Count -gt 0) {
                        Write-UiInfo "已安装的 MCP Server: $($existingServers -join ', ')" -Level Detail
                    }
                }
            }
            catch {
                Write-UiWarning "读取现有 MCP 配置时出错: $($_.Exception.Message)" -Level Debug
            }
        }

        $modeOptions = @(
            "一键模式 (推荐) - 自动安装核心 4 个 MCP Server",
            "自定义模式 - 手动选择需要的 MCP Server"
        )
        $modeIndex = Show-SingleSelectMenu -Options $modeOptions -Title "MCP Server 安装模式"
        if ($modeIndex -lt 0) {
            Write-UiInfo "已取消 MCP Server 安装模式选择"
            return $true
        }
        $selectedMode = if ($modeIndex -eq 0) { "quick" } else { "custom" }

        $orderedServerIds = @($script:McpServers.Keys | Sort-Object { [int]$script:McpServers[$_].Priority })
        if ($selectedMode -eq "quick") {
            $selectedServers = @($orderedServerIds | Where-Object {
                $script:McpServers[$_].Recommended
            })

            # 一键模式：选中所有推荐的 MCP Server（后续统一在确认环节显示详情）
        }
        else {
            $displayOptions = @()
            $serverMap = @()
            $defaultSelected = @()

            for ($i = 0; $i -lt $orderedServerIds.Count; $i++) {
                $serverId = $orderedServerIds[$i]
                $server = $script:McpServers[$serverId]
                $recommendedTag = if ($server.Recommended) { " (推荐)" } else { "" }
                $credentialTag = if ($server.CredentialType -ne "none") { " | 需凭据" } else { "" }
                $installedTag = if ($existingServers -contains $serverId) { "[已安装] " } else { "" }
                $displayOptions += "$installedTag$($server.Name)$recommendedTag$credentialTag - $($server.Description)"
                $serverMap += $serverId
                # 默认选中推荐的且未安装的
                if ($server.Recommended -and $existingServers -notcontains $serverId) {
                    $defaultSelected += $i
                }
            }

            Write-UiPrimary "请选择要安装的 MCP Server:"
            $selectedIndices = Show-MultiSelectMenu -Options $displayOptions -DefaultSelected $defaultSelected -Title "MCP Server 选择"

            # $null = 用户按 Esc 取消，优雅退出
            if ($null -eq $selectedIndices) {
                Write-UiInfo "已取消 MCP Server 选择"
                return $true
            }

            if (@($selectedIndices).Count -eq 0) {
                throw "未选择任何 MCP Server"
            }

            $selectedServers = @()
            foreach ($selectedIndex in $selectedIndices) {
                $selectedServers += $serverMap[[int]$selectedIndex]
            }
        }

        # 过滤掉已安装的 MCP Server（可选：用户可以选择重新安装）
        $newServers = @()
        $skippedServers = @()
        foreach ($serverId in $selectedServers) {
            if ($existingServers -contains $serverId) {
                Write-UiInfo "$($script:McpServers[$serverId].Name) 已安装，将跳过" -Level Detail
                $skippedServers += $serverId
            } else {
                $newServers += $serverId
            }
        }

        if ($newServers.Count -eq 0) {
            Write-UiSuccess "所有选择的 MCP Server 均已安装，无需重复安装" -Level Detail
            return $true
        }

        Write-UiInfo "将安装 $($newServers.Count) 个新的 MCP Server" -Level Detail
        $selectedServers = $newServers

        # 显示安装摘要并确认
        Write-Host ""
        Write-UiWarning "即将安装以下 MCP Server："
        foreach ($serverId in $selectedServers) {
            $server = $script:McpServers[$serverId]
            Write-UiInfo "  - $($server.Name): $($server.Description)" -Level Detail
        }
        Write-Host ""

        $confirmIndex = Show-SingleSelectMenu `
            -Title "确认安装？" `
            -Options @("是，开始安装", "否，取消")

        if ($confirmIndex -ne 0) {
            Write-UiInfo "已取消 MCP Server 安装"
            return $true
        }

        $serverStatus = @{}
        $successCount = 0
        $failureCount = 0

        # 使用 Install-McpSingleServer 逐个安装（已迁移到 core/McpManager.ps1）
        foreach ($serverId in $selectedServers) {
            $server = $script:McpServers[$serverId]
            Write-UiPrimary "安装 $($server.Name)..." -Level Detail

            $result = Install-McpSingleServer -ServerId $serverId
            $serverStatus[$serverId] = $result

            if ($result.Success) {
                $successCount++
            }
            else {
                $failureCount++
                Write-UiWarning "跳过 $($server.Name): $($result.ErrorMessage)" -Level Detail
            }
        }

        if ($successCount -eq 0) {
            throw "所有 MCP Server 均安装失败"
        }

        # 安装摘要
        Write-Host ""
        Write-UiPrimary "安装摘要:"
        Write-UiInfo "  - 选择: $($selectedServers.Count), 成功: $successCount, 失败: $failureCount"
        foreach ($serverId in $selectedServers) {
            $server = $script:McpServers[$serverId]
            $r = $serverStatus[$serverId]
            $statusText = if ($r.Success) { "✓ $($r.Status)" } else { "✗ $($r.ErrorMessage)" }
            Write-UiInfo "  - $($server.Name): $statusText"
        }

        return $true
    }
    catch {
        Write-UiDanger "配置 MCP Server 失败: $($_.Exception.Message)"
        return $false
    }
}

function Verify-Mcp {
    <#
    .SYNOPSIS
    验证 MCP Server 配置（stdio/http/software 多类型）
    #>

    try {
        # 验证 ~/.claude.json 中的 MCP Server 配置
        $claudeJsonPath = "$(Get-UserHome)\.claude.json"
        if (-not (Test-Path $claudeJsonPath)) {
            throw ".claude.json 不存在"
        }

        $claudeJson = Get-Content -Path $claudeJsonPath -Raw | ConvertFrom-Json -AsHashtable
        if (-not $claudeJson.ContainsKey("mcpServers") -or -not $claudeJson["mcpServers"]) {
            throw "缺少 MCP Server 配置"
        }

        $configuredServers = @($claudeJson["mcpServers"].Keys)
        if ($configuredServers.Count -eq 0) {
            throw "未配置任何 MCP Server"
        }

        $stdioCount = 0
        $httpCount = 0

        foreach ($serverId in $configuredServers) {
            $serverConfig = $claudeJson["mcpServers"][$serverId]
            if (-not $serverConfig) {
                Write-UiWarning "跳过空配置: $serverId" -Level Debug
                continue
            }

            $hasType = $serverConfig -is [hashtable] -and $serverConfig.ContainsKey("type")
            $hasUrl = $serverConfig -is [hashtable] -and $serverConfig.ContainsKey("url")
            $hasCommand = $serverConfig -is [hashtable] -and $serverConfig.ContainsKey("command")
            $hasArgs = $serverConfig -is [hashtable] -and $serverConfig.ContainsKey("args")
            $typeValue = if ($hasType) { [string]$serverConfig["type"] } else { "" }

            if ($typeValue -eq "http") {
                $httpCount++
                if (-not $hasUrl -or [string]::IsNullOrWhiteSpace([string]$serverConfig["url"])) {
                    throw "MCP Server '$serverId' 缺少 http.url"
                }
                if ([string]$serverConfig["url"] -match "\{[A-Za-z0-9_]+\}") {
                    throw "MCP Server '$serverId' URL 仍包含占位符: $($serverConfig["url"])"
                }
            }
            elseif ($hasCommand -and -not [string]::IsNullOrWhiteSpace([string]$serverConfig["command"])) {
                $stdioCount++
                if (-not $hasArgs -or -not $serverConfig["args"]) {
                    throw "MCP Server '$serverId' 缺少 stdio.args"
                }
            }
            else {
                Write-UiWarning "MCP Server '$serverId' 不是标准 stdio/http 配置，已跳过严格校验" -Level Debug
                continue
            }

            if (-not $script:McpServers.Contains($serverId)) {
                continue
            }

            $serverDef = $script:McpServers[$serverId]
            $credentialType = if ($serverDef.CredentialType) { [string]$serverDef.CredentialType } else { "none" }
            $argsList = if ($hasArgs) { @($serverConfig["args"]) } else { @() }

            switch ($credentialType) {
                "single-key" {
                    # 检查 settings.json 中的 API Key
                    $settingsPath = Get-ClaudeSettingsPath
                    if (Test-Path $settingsPath) {
                        $settings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json -AsHashtable
                        $apiKeyName = [string]$serverDef.ApiKeyName
                        $hasServerEnv = $serverConfig -is [hashtable] -and $serverConfig.ContainsKey("env") -and
                            $serverConfig["env"] -is [hashtable] -and
                            $serverConfig["env"].ContainsKey($apiKeyName) -and
                            -not [string]::IsNullOrWhiteSpace([string]$serverConfig["env"][$apiKeyName])
                        $hasGlobalEnv = $settings -is [hashtable] -and $settings.ContainsKey("env") -and
                            $settings["env"] -is [hashtable] -and
                            $settings["env"].ContainsKey($apiKeyName) -and
                            -not [string]::IsNullOrWhiteSpace([string]$settings["env"][$apiKeyName])
                        if (-not ($hasServerEnv -or $hasGlobalEnv)) {
                            Write-UiWarning "MCP Server '$serverId' 缺少 API Key: $apiKeyName" -Level Detail
                        }
                    }
                }
                "args-multi" {
                    foreach ($argCredential in @($serverDef.ArgsCredentials)) {
                        $argName = [string]$argCredential.ArgName
                        $required = if ($argCredential.ContainsKey("Required")) { [bool]$argCredential.Required } else { $false }
                        if (-not $required) {
                            continue
                        }

                        $argIndex = [array]::IndexOf($argsList, $argName)
                        if ($argIndex -lt 0 -or $argIndex -ge ($argsList.Count - 1)) {
                            throw "MCP Server '$serverId' 缺少必需参数: $argName"
                        }
                        if ([string]::IsNullOrWhiteSpace([string]$argsList[$argIndex + 1])) {
                            throw "MCP Server '$serverId' 参数值为空: $argName"
                        }
                    }
                }
                "args-token" {
                    $tokenPrefix = "$($serverDef.TokenArg)="
                    $hasToken = @($argsList | Where-Object {
                        $_ -is [string] -and $_.StartsWith($tokenPrefix) -and $_.Length -gt $tokenPrefix.Length
                    }).Count -gt 0
                    if (-not $hasToken) {
                        throw "MCP Server '$serverId' 缺少 token 参数: $($serverDef.TokenArg)"
                    }
                }
                "url-embedded" {
                    if ($serverConfig["type"] -ne "http") {
                        throw "MCP Server '$serverId' 应为 http 配置"
                    }
                    if ([string]$serverConfig["url"] -match "\{[A-Za-z0-9_]+\}") {
                        throw "MCP Server '$serverId' URL 占位符未替换: $($serverConfig["url"])"
                    }
                }
                "env-file" {
                    $envPath = [string]$serverDef.EnvFile.Path
                    if (-not (Test-Path $envPath)) {
                        throw "MCP Server '$serverId' 缺少 .env 文件: $envPath"
                    }

                    $envContent = Get-Content -Path $envPath -Raw
                    foreach ($sharedField in @($serverDef.EnvFile.SharedKeyFields)) {
                        if ($envContent -notmatch "(?m)^\s*$([regex]::Escape([string]$sharedField))\s*=\s*.+$") {
                            throw "MCP Server '$serverId' .env 缺少必填字段: $sharedField"
                        }
                    }
                    foreach ($field in @($serverDef.EnvFile.Fields)) {
                        if ($field.ContainsKey("Required") -and [bool]$field.Required) {
                            $fieldKey = [string]$field.Key
                            if ($envContent -notmatch "(?m)^\s*$([regex]::Escape($fieldKey))\s*=\s*.+$") {
                                throw "MCP Server '$serverId' .env 缺少必填字段: $fieldKey"
                            }
                        }
                    }
                }
            }
        }

        # 验证 settings.json 中的权限配置
        $settingsPath = Get-ClaudeSettingsPath
        if (-not (Test-Path $settingsPath)) {
            throw "settings.json 不存在"
        }

        $settings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json -AsHashtable
        if (-not $settings.ContainsKey("permissions") -or
            -not ($settings["permissions"] -is [hashtable]) -or
            -not $settings["permissions"].ContainsKey("allow") -or
            -not $settings["permissions"]["allow"]) {
            throw "缺少权限配置"
        }
        # 检查已安装的 MCP Server 是否有对应的 mcp__ 权限
        foreach ($serverId in $configuredServers) {
            $mcpPerm = "mcp__${serverId}"
            if ($settings["permissions"]["allow"] -notcontains $mcpPerm) {
                Write-UiWarning "⚠ 缺少 MCP 权限: $mcpPerm" -Level Detail
            }
        }

        Write-UiSuccess "✓ MCP Server 配置验证通过"
        Write-UiInfo "  - MCP 数量: $($configuredServers.Count)" -Level Detail
        Write-UiInfo "  - stdio: $stdioCount" -Level Detail
        Write-UiInfo "  - http: $httpCount" -Level Detail

        # TODO: ContextWeaver 验证逻辑，待 Python 环境支持后启用
        # if ($claudeJson.mcpServers.PSObject.Properties.Name -contains "contextweaver") {
        #     $envPath = $script:McpServers["contextweaver"].EnvFile.Path
        #     if (Test-Path $envPath) {
        #         Write-UiInfo "  - contextweaver .env: ✓ ($envPath)"
        #     }
        #     else {
        #         throw "contextweaver 已配置但缺少 .env 文件: $envPath"
        #     }
        # }

        return $true
    }
    catch {
        Write-UiDanger "验证 MCP Server 配置失败: $($_.Exception.Message)"
        return $false
    }
}

# 注: Get-ClaudeSettingsPath 已迁移到 core/McpManager.ps1

function Clear-NpxCache {
    <#
    .SYNOPSIS
    清理 npx 缓存目录（_npx）
    .DESCRIPTION
    主路径：删除 npm cache 下的 _npx 子目录
    回退：npm cache clean --force（仅主路径失败时执行）
    .RETURNS
    @{ Success; Skipped; Fallback; NoOp; Reason }
    #>

    # HC-13: 初始化完整属性集，防止 StrictMode 下访问缺失属性
    $base = @{ Success = $false; Skipped = $false; Fallback = $false; NoOp = $false; Reason = "" }

    # 1. 检测 npm 可用性
    if (-not (Test-CommandAvailable "npm")) {
        $base.Skipped = $true; $base.Reason = "npm-missing"
        return $base
    }

    # 2. 获取缓存路径
    $cacheResult = Invoke-ExternalCommand -Command "npm" -Arguments @("config", "get", "cache") -SuppressOutput
    if ($cacheResult.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($cacheResult.Output)) {
        $base.Skipped = $true; $base.Reason = "cache-path-unavailable"
        return $base
    }

    $cacheDir = $cacheResult.Output.Trim()
    $npxDir = Join-Path $cacheDir "_npx"

    # 3. 主路径：删除 _npx 目录
    if (Test-Path $npxDir) {
        try {
            Remove-Item $npxDir -Recurse -Force
            $base.Success = $true
            return $base
        }
        catch {
            # 4. Fallback：npm cache clean --force
            $cleanResult = Invoke-ExternalCommand -Command "npm" -Arguments @("cache", "clean", "--force") -SuppressOutput
            $base.Success = ($cleanResult.ExitCode -eq 0); $base.Fallback = $true
            return $base
        }
    }

    $base.Success = $true; $base.NoOp = $true
    return $base
}

function Update-Mcp {
    <#
    .SYNOPSIS
    更新已安装的 MCP Server 配置到最新定义
    .DESCRIPTION
    - Phase 0: npx 缓存清理 + PreInstall npm-global 更新
    - 已存在的 Server：对比 args/url/配置，变更则更新
    - 不存在的 Server：不自动添加（由 -OnMissing 控制）
    - 不删除用户手动添加的 Server
    - 同步更新 permissions.allow
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
        $updatedItems = [System.Collections.ArrayList]::new()

        # ── Phase 0: npx 缓存清理 + PreInstall npm-global 更新 ──
        $cacheResult = Clear-NpxCache
        if ($cacheResult.Skipped) {
            [void]$updatedItems.Add("skipped::npm-missing")
        }
        elseif ($cacheResult.Success -and -not $cacheResult.NoOp) {
            Write-UiSuccess "npx 缓存已清理" -Level Detail
            [void]$updatedItems.Add("cache::npx::cleared")
        }
        elseif (-not $cacheResult.Success) {
            Write-UiWarning "npx 缓存清理失败，继续更新..." -Level Debug
            [void]$updatedItems.Add("cache::npx::clear-failed")
        }

        # PreInstall npm-global 更新
        foreach ($serverId in $script:McpServers.Keys) {
            $serverDef = $script:McpServers[$serverId]
            if (-not $serverDef.ContainsKey("PreInstall") -or -not $serverDef["PreInstall"]) { continue }
            $pre = [hashtable]$serverDef["PreInstall"]
            if ($pre.Type -ne "npm-global") { continue }

            Write-UiPrimary "正在更新 $($pre.Package)..." -Level Detail
            $installResult = Invoke-NpmGlobalInstall -PackageName $pre.Package -Force
            if ($installResult.Success) {
                [void]$updatedItems.Add("npm::$($pre.Package)::updated")
            }
            else {
                Write-UiWarning "更新 $($pre.Package) 失败: $($installResult.Error)" -Level Debug
            }
        }

        # ── Phase 1+: 配置对齐（原有逻辑）──

        # 读取 .claude.json
        $claudeJsonPath = "$(Get-UserHome)\.claude.json"
        if (-not (Test-Path $claudeJsonPath)) {
            $result.UpdatedItems = @("noop::Mcp::no-change")
            $result.Success = $true
            Write-UiInfo "Mcp 配置文件不存在，跳过更新" -Level Detail
            return $result
        }

        # R-09: Mutex 保护配置文件读-改-写（防止与 Disable/Enable/Remove 并发冲突）
        $null = Invoke-WithMcpLock {

        $claudeJson = Get-Content -Path $claudeJsonPath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        if (-not $claudeJson) { $claudeJson = @{} }
        if (-not $claudeJson.ContainsKey("mcpServers")) {
            $claudeJson["mcpServers"] = @{}
        }

        $configChanged = $false

        # 遍历 CCQ 定义的 MCP Servers
        foreach ($serverId in $script:McpServers.Keys) {
            $serverDef = $script:McpServers[$serverId]

            # 仅更新已安装的 Server
            if (-not $claudeJson["mcpServers"].ContainsKey($serverId)) {
                continue
            }

            $existingConfig = $claudeJson["mcpServers"][$serverId]
            $needsUpdate = $false

            # 比较配置
            switch ($serverDef.McpType) {
                "stdio" {
                    $expectedArgs = @($serverDef.Args)
                    $currentArgs = if ($existingConfig.ContainsKey("args")) { @($existingConfig["args"]) } else { @() }
                    $expectedCommand = $serverDef.Command

                    # 只比较非凭据部分的 args（凭据部分保留用户原值）
                    if ($existingConfig.ContainsKey("command") -and [string]$existingConfig["command"] -ne $expectedCommand) {
                        $needsUpdate = $true
                    }

                    # 比较基础 args（不含凭据注入的部分）
                    $baseArgsChanged = $false
                    if ($expectedArgs.Count -ne $currentArgs.Count) {
                        if ($serverDef.CredentialType -eq "none") {
                            $baseArgsChanged = $true
                        } else {
                            # IDEM-1: 凭据型 Server args 数量漂移，记录警告以便排查
                            Write-UiWarning "MCP '$serverId' args 数量漂移 (期望 $($expectedArgs.Count), 实际 $($currentArgs.Count))，凭据型跳过自动更新" -Level Debug
                        }
                    } else {
                        for ($i = 0; $i -lt $expectedArgs.Count; $i++) {
                            if ($expectedArgs[$i] -ne $currentArgs[$i]) {
                                $baseArgsChanged = $true
                                break
                            }
                        }
                    }

                    if ($baseArgsChanged) { $needsUpdate = $true }
                }
                "http" {
                    # url-embedded 类型使用 UrlTemplate（含用户凭据），不比较 URL
                    if ($serverDef.CredentialType -ne "url-embedded") {
                        $expectedUrl = $serverDef.Url
                        $currentUrl = if ($existingConfig.ContainsKey("url")) { [string]$existingConfig["url"] } else { "" }
                        if ($currentUrl -ne $expectedUrl) {
                            $needsUpdate = $true
                        }
                    }
                }
            }

            if ($needsUpdate) {
                # 重新生成配置条目（保留已有凭据）
                $existingCredentials = @{}

                # 提取已有凭据
                if ($existingConfig.ContainsKey("env") -and $existingConfig["env"]) {
                    $existingCredentials = $existingConfig["env"]
                }

                # 生成新的基础配置（无凭据）
                try {
                    $newEntry = New-McpSettingsEntry -ServerId $serverId -Server $serverDef -Credentials @{}

                    # 恢复已有凭据
                    if ($existingCredentials.Count -gt 0 -and $newEntry) {
                        if (-not $newEntry.ContainsKey("env")) {
                            $newEntry["env"] = @{}
                        }
                        foreach ($key in $existingCredentials.Keys) {
                            $newEntry["env"][$key] = $existingCredentials[$key]
                        }
                    }

                    $claudeJson["mcpServers"][$serverId] = $newEntry
                    [void]$updatedItems.Add("config::mcpServers.${serverId}::updated")
                    $configChanged = $true
                } catch {
                    Write-UiWarning "更新 MCP Server '$serverId' 失败: $($_.Exception.Message)" -Level Debug
                }
            }
        }

        # 写入 .claude.json（如有变更）— 原子写入
        if ($configChanged) {
            $claudeJsonContent = $claudeJson | ConvertTo-Json -Depth 10
            $writeOk = Write-FileAtomically -FilePath $claudeJsonPath -Content @($claudeJsonContent)
            if (-not $writeOk) {
                throw ".claude.json 原子写入失败"
            }

            # CONS-2: 同步 vault 中已安装 Server 的 definitionHash
            try {
                $meta = Read-McpMeta
                $hashUpdated = $false
                foreach ($sid in $script:McpServers.Keys) {
                    if ($claudeJson["mcpServers"].ContainsKey($sid) -and $meta["servers"].ContainsKey($sid)) {
                        $newHash = Get-McpDefinitionHash -ServerDef $script:McpServers[$sid]
                        if ($meta["servers"][$sid]["definitionHash"] -ne $newHash) {
                            $meta["servers"][$sid]["definitionHash"] = $newHash
                            $meta["servers"][$sid]["updatedAt"] = (Get-Date).ToUniversalTime().ToString("o")
                            $hashUpdated = $true
                        }
                    }
                }
                if ($hashUpdated) {
                    Write-McpMeta $meta
                }
            } catch {
                Write-UiWarning "vault definitionHash 同步失败: $($_.Exception.Message)" -Level Debug
            }
        }

        # 同步 settings.json 权限
        $settingsPath = Get-ClaudeSettingsPath
        if (Test-Path $settingsPath) {
            $settings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
            if ($settings) {
                if (-not $settings.ContainsKey("permissions")) { $settings["permissions"] = @{} }
                if (-not $settings["permissions"].ContainsKey("allow")) { $settings["permissions"]["allow"] = @() }

                # 为已安装的 MCP Server 补齐 mcp__<serverId> 权限（存量自愈）
                $permChanged = $false
                foreach ($serverId in @($claudeJson["mcpServers"].Keys)) {
                    $mcpPerm = "mcp__${serverId}"
                    if ($settings["permissions"]["allow"] -notcontains $mcpPerm) {
                        $settings["permissions"]["allow"] += $mcpPerm
                        [void]$updatedItems.Add("config::permissions.allow.${mcpPerm}::added")
                        $permChanged = $true
                    }
                }

                if ($permChanged) {
                    $settingsJson = $settings | ConvertTo-Json -Depth 10
                    Write-FileAtomically -FilePath $settingsPath -Content @($settingsJson)
                }
            }
        }

        }  # End Invoke-WithMcpLock

        # 结果
        if ($updatedItems.Count -eq 0) {
            $result.UpdatedItems = @("noop::Mcp::no-change")
            Write-UiInfo "Mcp 配置已是最新，无需更新" -Level Detail
        } else {
            $result.UpdatedItems = @($updatedItems)
            Write-UiSuccess "✓ Mcp 已更新 ($($updatedItems.Count) 项变更)"
        }

        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = "更新 Mcp 失败: $($_.Exception.Message)"
        Write-UiDanger $result.ErrorMessage
    }

    return $result
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
