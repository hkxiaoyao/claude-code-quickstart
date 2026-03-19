# Provider.ps1 - 供应商管理核心模块（CRUD + 同步 + 菜单）
# 功能: 统一管理 AI 供应商配置，支持完整 CRUD、自动同步、交互式管理

#Requires -Version 7.0

Set-StrictMode -Version Latest

# ─── 内置供应商模板（单一数据源，ApiKey.ps1 也引用此处）───────────────────────

$script:BuiltinProviders = @{
    "zhipu" = @{
        Name        = "智谱 GLM"
        Description = "智谱 AI，服务端自动路由到最新 GLM 模型"
        BaseUrl     = "https://open.bigmodel.cn/api/anthropic"
        PlatformUrl = "https://bigmodel.cn/usercenter/proj-mgmt/apikeys"
    }
    "minimax" = @{
        Name        = "MiniMax"
        Description = "MiniMax API，支持 M2.5 系列模型"
        BaseUrl     = "https://api.minimaxi.com/anthropic"
        PlatformUrl = "https://platform.minimaxi.com/user-center/basic-information/interface-key"
        ModelMapping = @{
            "opus"   = "MiniMax-M2.5"
            "sonnet" = "MiniMax-M2.5"
            "haiku"  = "MiniMax-M2.5"
        }
    }
    "moonshot" = @{
        Name        = "Kimi (Moonshot)"
        Description = "月之暗面 Kimi，支持 K2.5 系列模型"
        BaseUrl     = "https://api.moonshot.cn/anthropic"
        PlatformUrl = "https://platform.moonshot.cn/console/api-keys"
        ModelMapping = @{
            "opus"   = "kimi-k2.5"
            "sonnet" = "kimi-k2.5"
            "haiku"  = "kimi-k2.5"
        }
    }
    "custom" = @{
        Name        = "自定义供应商"
        Description = "手动配置 Base URL 和 API Key"
        BaseUrl     = ""
        PlatformUrl = ""
    }
}

# ─── 辅助函数 ──────────────────────────────────────────────────────────────────

function Get-ProviderSettingsPath {
    return "$(Get-UserHome)\.claude\settings.json"
}

function Get-ProviderProfilesDir {
    return "$(Get-UserHome)\.claude\providers"
}

function Read-SettingsJson {
    <#
    .SYNOPSIS
    安全读取 settings.json 并返回 hashtable
    #>
    $path = Get-ProviderSettingsPath
    if (-not (Test-Path $path)) { return @{} }
    try {
        $content = Get-Content $path -Raw -Encoding UTF8
        $settings = $content | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        if (-not $settings) { return @{} }
        return $settings
    } catch {
        return @{}
    }
}

function Write-SettingsJsonAtomic {
    <#
    .SYNOPSIS
    原子写入 settings.json（临时文件 + Move-Item）
    #>
    param([Parameter(Mandatory)] [hashtable]$Settings)

    $path = Get-ProviderSettingsPath
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $tempPath = "$path.tmp"
    $Settings | ConvertTo-Json -Depth 10 | Set-Content $tempPath -Encoding UTF8
    Move-Item $tempPath $path -Force
}

function Get-MaskedApiKey {
    <#
    .SYNOPSIS
    脱敏 API Key（前 4 位 + ... + 后 2 位）
    #>
    param([string]$Key)
    if ([string]::IsNullOrWhiteSpace($Key)) { return "-" }
    if ($Key.Length -le 8) { return "***" }
    return $Key.Substring(0, 4) + "..." + $Key.Substring($Key.Length - 2)
}

function Test-ProviderKey {
    <#
    .SYNOPSIS
    校验 Provider Key 合法性（防止路径穿越和非法字符）
    #>
    param([string]$Key)
    return (-not [string]::IsNullOrWhiteSpace($Key) -and $Key -match '^[A-Za-z0-9._-]+$')
}

function New-CustomProviderKey {
    <#
    .SYNOPSIS
    生成自定义供应商 Key：优先名称，其次 URL（host + 可选路径哈希）
    .PARAMETER Name
    用户输入的供应商名称（可选）
    .PARAMETER BaseUrl
    供应商 Base URL（必填）
    .RETURNS
    string — ASCII 安全的 provider key（如 custom-aether / custom-api-example-com-1a2b）
    #>
    param(
        [string]$Name,
        [Parameter(Mandatory)] [string]$BaseUrl
    )

    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        $sanitized = $Name.Trim().ToLower() -replace '[^a-z0-9\-]', '-' -replace '-{2,}', '-' -replace '^-|-$', ''
        if ($sanitized) { return "custom-$sanitized" }
    }

    try {
        $uri = [System.Uri]::new($BaseUrl.TrimEnd('/'))
        $hostPart = $uri.Host.ToLower() -replace '\.', '-'
        if ($uri.AbsolutePath -and $uri.AbsolutePath -ne "/") {
            $pathHash = (Get-StringFingerprint -Text $uri.AbsolutePath).Substring(0, 4)
            return "custom-${hostPart}-${pathHash}"
        }
        return "custom-${hostPart}"
    } catch {
        return "custom-manual"
    }
}

function Get-NextAvailableKey {
    <#
    .SYNOPSIS
    计算 baseKey 的下一个可用递增 key（如 zhipu → zhipu-2 → zhipu-3）
    .PARAMETER BaseKey
    基础 key（如 zhipu / minimax / moonshot）
    .RETURNS
    string — 下一个可用 key
    #>
    param([Parameter(Mandatory)] [string]$BaseKey)

    $profilesDir = Get-ProviderProfilesDir
    if (-not (Test-Path $profilesDir)) { return "$BaseKey-2" }

    # HC-13: @() 包裹
    $files = @(Get-ChildItem $profilesDir -Filter "*.json" -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) { return "$BaseKey-2" }

    $pattern = '^' + [regex]::Escape($BaseKey) + '(?:-(\d+))?$'
    $maxNum = 1  # 基础 key 视为序号 1
    foreach ($f in $files) {
        $k = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $m = [regex]::Match($k, $pattern)
        if (-not $m.Success) { continue }
        if ($m.Groups[1].Success) {
            $n = 0
            if ([int]::TryParse($m.Groups[1].Value, [ref]$n) -and $n -gt $maxNum) {
                $maxNum = $n
            }
        }
    }
    return "$BaseKey-$($maxNum + 1)"
}

function Find-BuiltinProviderProfiles {
    <#
    .SYNOPSIS
    从 profiles 列表中查找属于指定内置供应商的所有实例
    .PARAMETER BuiltinKey
    内置供应商基础 key（zhipu / minimax / moonshot）
    .PARAMETER Profiles
    Get-ProviderProfiles 返回的 hashtable 数组
    .RETURNS
    hashtable[] — 匹配的 profile 列表
    #>
    param(
        [Parameter(Mandatory)] [string]$BuiltinKey,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$Profiles
    )

    # 精确匹配 key 或前缀匹配 key-N（仅数字后缀）
    return @($Profiles | Where-Object { $_.Key -eq $BuiltinKey -or $_.Key -match "^$([regex]::Escape($BuiltinKey))-\d+$" })
}

# ─── Sync（自动同步）──────────────────────────────────────────────────────────

function Sync-ProviderFromSettings {
    <#
    .SYNOPSIS
    检测 settings.json 中的活跃供应商是否在 providers/ 中有对应 Profile
    如果没有，自动创建（迁移旧用户场景）
    #>

    $settings = Read-SettingsJson

    # 提取当前配置的供应商信息
    $authToken = ""
    $baseUrl = ""
    if ($settings.ContainsKey("env") -and $settings["env"]) {
        $env = $settings["env"]
        if ($env.ContainsKey("ANTHROPIC_AUTH_TOKEN")) { $authToken = $env["ANTHROPIC_AUTH_TOKEN"] }
        if ($env.ContainsKey("ANTHROPIC_BASE_URL")) { $baseUrl = $env["ANTHROPIC_BASE_URL"] }
    }

    # 两者都必须非空才视为有效供应商配置（防止半配置状态触发同步）
    if ([string]::IsNullOrWhiteSpace($authToken) -or [string]::IsNullOrWhiteSpace($baseUrl)) {
        return
    }

    # 扫描现有 Profile → 匹配 BaseUrl
    $profilesDir = Get-ProviderProfilesDir
    if (Test-Path $profilesDir) {
        # HC-13: 必须用 @() 包裹
        $existingProfiles = @(Get-ChildItem $profilesDir -Filter "*.json" -ErrorAction SilentlyContinue)
        foreach ($pf in $existingProfiles) {
            try {
                $profile = Get-Content $pf.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable -ErrorAction Stop
                if ($profile -and $profile.ContainsKey("env") -and $profile["env"]) {
                    $pfBaseUrl = if ($profile["env"].ContainsKey("ANTHROPIC_BASE_URL")) { $profile["env"]["ANTHROPIC_BASE_URL"] } else { "" }
                    if (-not [string]::IsNullOrWhiteSpace($pfBaseUrl) -and -not [string]::IsNullOrWhiteSpace($baseUrl) -and
                        $baseUrl -like "$pfBaseUrl*") {
                        # 已有匹配 Profile → 无需同步
                        return
                    }
                }
            } catch { }
        }
    }

    # 无匹配 Profile → 自动创建
    $migrateKey = "custom"
    $providerName = "自定义供应商"
    foreach ($k in $script:BuiltinProviders.Keys) {
        if ($k -eq "custom") { continue }
        $p = $script:BuiltinProviders[$k]
        if (-not [string]::IsNullOrWhiteSpace($p.BaseUrl) -and
            -not [string]::IsNullOrWhiteSpace($baseUrl) -and
            $baseUrl -like "$($p.BaseUrl)*") {
            $migrateKey = $k
            $providerName = $p.Name
            break
        }
    }

    # 自定义供应商: 统一 key 生成（名称/URL 回退，含路径哈希消歧）
    if ($migrateKey -eq "custom" -and -not [string]::IsNullOrWhiteSpace($baseUrl)) {
        $migrateKey = New-CustomProviderKey -Name "" -BaseUrl $baseUrl
        if (-not (Test-ProviderKey -Key $migrateKey)) {
            $migrateKey = "custom-unknown"
        }
    }

    $newProfile = @{
        "_meta" = @{
            "provider"     = $providerName
            "key"          = $migrateKey
            "baseUrl"      = $baseUrl
            "configuredAt" = (Get-Date -Format "o")
        }
        "env" = @{
            "ANTHROPIC_AUTH_TOKEN" = $authToken
            "ANTHROPIC_BASE_URL"  = $baseUrl
        }
    }

    # 检查是否有 modelMapping
    if ($settings.ContainsKey("modelMapping") -and $settings["modelMapping"]) {
        $newProfile["modelMapping"] = $settings["modelMapping"]
    }

    # 原子写入 Profile
    if (-not (Test-Path $profilesDir)) {
        New-Item -ItemType Directory -Path $profilesDir -Force | Out-Null
    }
    $profilePath = Join-Path $profilesDir "$migrateKey.json"
    $tempPath = "$profilePath.tmp"
    $newProfile | ConvertTo-Json -Depth 10 | Set-Content $tempPath -Encoding UTF8
    Move-Item $tempPath $profilePath -Force

    Write-UiSuccess "已从当前配置自动同步供应商 Profile: $migrateKey.json"
}

# ─── Read ──────────────────────────────────────────────────────────────────────

function Get-ProviderProfiles {
    <#
    .SYNOPSIS
    扫描 ~/.claude/providers/*.json，返回 Profile 哈希表数组
    .RETURNS
    hashtable[] — 每项包含: Key, Name, BaseUrl, ConfiguredAt, HasModelMapping, AuthToken
    #>

    $profilesDir = Get-ProviderProfilesDir
    if (-not (Test-Path $profilesDir)) { return @() }

    # HC-13: 必须用 @() 包裹
    $files = @(Get-ChildItem $profilesDir -Filter "*.json" -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) { return @() }

    $results = @()
    foreach ($f in $files) {
        try {
            $profile = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            if (-not $profile -or -not $profile.ContainsKey("_meta")) { continue }

            $meta = $profile["_meta"]
            $results += @{
                Key             = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
                Name            = if ($meta.ContainsKey("provider")) { $meta["provider"] } else { "未知" }
                BaseUrl         = if ($meta.ContainsKey("baseUrl")) { $meta["baseUrl"] } else { "" }
                ConfiguredAt    = if ($meta.ContainsKey("configuredAt")) { $meta["configuredAt"] } else { "" }
                HasModelMapping = $profile.ContainsKey("modelMapping") -and $null -ne $profile["modelMapping"]
                AuthToken       = if ($profile.ContainsKey("env") -and $profile["env"].ContainsKey("ANTHROPIC_AUTH_TOKEN")) { $profile["env"]["ANTHROPIC_AUTH_TOKEN"] } else { "" }
                ProfilePath     = $f.FullName
            }
        } catch { }
    }

    return $results
}

function Get-ActiveProvider {
    <#
    .SYNOPSIS
    从 settings.json 读取 ANTHROPIC_BASE_URL，与 providers/ 目录比对
    .RETURNS
    hashtable: @{ Key; Name; BaseUrl; ProfilePath } 或 $null
    #>

    $settings = Read-SettingsJson
    $baseUrl = ""
    if ($settings.ContainsKey("env") -and $settings["env"] -and $settings["env"].ContainsKey("ANTHROPIC_BASE_URL")) {
        $baseUrl = $settings["env"]["ANTHROPIC_BASE_URL"]
    }

    if ([string]::IsNullOrWhiteSpace($baseUrl)) { return $null }

    # HC-13: @() 包裹
    $profiles = @(Get-ProviderProfiles)
    foreach ($p in $profiles) {
        if (-not [string]::IsNullOrWhiteSpace($p.BaseUrl) -and $baseUrl -like "$($p.BaseUrl)*") {
            return @{
                Key         = $p.Key
                Name        = $p.Name
                BaseUrl     = $p.BaseUrl
                ProfilePath = $p.ProfilePath
            }
        }
    }

    return $null
}

# ─── Dashboard Data ────────────────────────────────────────────────────────────

function Get-ProviderDisplayData {
    <#
    .SYNOPSIS
    聚合供应商展示数据（合并 Profiles + ActiveKey，避免 Dashboard 循环中重复调用）
    .RETURNS
    @{ Profiles = hashtable[]; ActiveKey = string; HasProviders = bool }
    #>

    # HC-13: @() 包裹
    $profiles = @(Get-ProviderProfiles)

    # 内联 active key 查找（避免 Get-ActiveProvider 重复扫描 providers 目录）
    $settings = Read-SettingsJson
    $activeKey = ""
    $baseUrl = ""
    if ($settings.ContainsKey("env") -and $settings["env"] -and $settings["env"].ContainsKey("ANTHROPIC_BASE_URL")) {
        $baseUrl = [string]$settings["env"]["ANTHROPIC_BASE_URL"]
    }
    if (-not [string]::IsNullOrWhiteSpace($baseUrl)) {
        foreach ($p in $profiles) {
            if (-not [string]::IsNullOrWhiteSpace($p.BaseUrl) -and $baseUrl -like "$($p.BaseUrl)*") {
                $activeKey = [string]$p.Key
                break
            }
        }
    }

    # HC-13: @() 包裹
    $displayProfiles = @($profiles | ForEach-Object {
        $isActive = (-not [string]::IsNullOrWhiteSpace($activeKey)) -and ($_.Key -eq $activeKey)
        @{
            Key          = $_.Key
            Name         = $_.Name
            BaseUrl      = $_.BaseUrl
            AuthToken    = $_.AuthToken
            ProfilePath  = $_.ProfilePath
            IsActive     = $isActive
            MaskedApiKey = Get-MaskedApiKey $_.AuthToken
        }
    })

    return @{
        Profiles     = $displayProfiles
        ActiveKey    = $activeKey
        HasProviders = ($displayProfiles.Count -gt 0)
    }
}

function Show-ProviderStatus {
    <#
    .SYNOPSIS
    显示供应商状态表格（MCP 状态表视觉风格）
    #>

    # HC-13: @() 包裹
    $profiles = @(Get-ProviderProfiles)
    if ($profiles.Count -eq 0) {
        Write-UiWarning "未找到任何供应商 Profile"
        Write-UiDim "提示: 使用 [添加供应商] 配置新的供应商连接"
        return
    }

    $active = Get-ActiveProvider

    Write-Host ""
    Write-UiPrimary "供应商列表："
    Write-Host ""

    # 列宽定义
    $colWidths = @(15, 35, 15, 10)

    # 表头
    $headerLine = "  " +
        (Format-DisplayPad "供应商" $colWidths[0]) + " " +
        (Format-DisplayPad "Base URL" $colWidths[1]) + " " +
        (Format-DisplayPad "API Key" $colWidths[2]) + " " +
        (Format-DisplayPad "状态" $colWidths[3])
    Write-UiInfo $headerLine
    $sepWidth = ($colWidths | Measure-Object -Sum).Sum + $colWidths.Count - 1
    Write-UiDim ("  " + [string]::new("-", $sepWidth))

    foreach ($p in $profiles) {
        $isActive = $active -and $active.Key -eq $p.Key
        $statusText = if ($isActive) { "Active" } else { "Inactive" }
        $color = if ($isActive) { "Success" } else { "Dim" }

        # 截断 BaseUrl 以适应列宽
        $urlDisplay = $p.BaseUrl
        if ($urlDisplay.Length -gt $colWidths[1]) {
            $urlDisplay = $urlDisplay.Substring(0, $colWidths[1] - 3) + "..."
        }

        $line = "  " +
            (Format-DisplayPad $p.Name $colWidths[0]) + " " +
            (Format-DisplayPad $urlDisplay $colWidths[1]) + " " +
            (Format-DisplayPad (Get-MaskedApiKey $p.AuthToken) $colWidths[2]) + " " +
            (Format-DisplayPad $statusText $colWidths[3])
        Write-UiOutput $line -Type $color
    }
    Write-Host ""
}

# ─── Create ────────────────────────────────────────────────────────────────────

function Add-Provider {
    <#
    .SYNOPSIS
    交互式添加新供应商（安装步骤和管理菜单共用）
    .PARAMETER Activate
    添加后立即激活（安装步骤传 $true，管理菜单默认询问）
    .RETURNS
    @{ Success; Key; Name; BaseUrl; Activated }
    #>
    param([switch]$Activate)

    $result = @{ Success = $false; Key = ""; Name = ""; BaseUrl = ""; Activated = $false }

    # HC-13: @() 包裹 — 扫描已有 profiles，为内置供应商菜单标注已配置状态
    $existingProfiles = @(Get-ProviderProfiles)
    $builtinKeys = @("zhipu", "minimax", "moonshot")
    $configuredTags = @{}
    foreach ($bk in $builtinKeys) {
        $matched = @(Find-BuiltinProviderProfiles -BuiltinKey $bk -Profiles $existingProfiles)
        if ($matched.Count -eq 1) {
            $templateName = $script:BuiltinProviders[$bk].Name
            if ($matched[0].Name -eq $templateName) {
                $configuredTags[$bk] = " [已配置]"
            } else {
                $tagName = $matched[0].Name
                if ($tagName.Length -gt 10) { $tagName = $tagName.Substring(0, 10) + "..." }
                $configuredTags[$bk] = " [已配置: $tagName]"
            }
        } elseif ($matched.Count -gt 1) {
            $configuredTags[$bk] = " [已配置 x$($matched.Count)]"
        }
    }

    # 构建菜单
    $providerLabels = @(
        "智谱 GLM       - 智谱 AI，服务端自动路由最新 GLM 模型$($configuredTags['zhipu'])"
        "MiniMax        - MiniMax API，支持 M2.5 系列$($configuredTags['minimax'])"
        "Kimi (Moonshot) - 月之暗面 Kimi，支持 K2.5 系列$($configuredTags['moonshot'])"
        "自定义供应商    - 手动配置 Base URL 和 API Key"
    )
    $providerKeys = @("zhipu", "minimax", "moonshot", "custom")

    Write-UiPrimary "请选择 API 供应商:"
    $selectedIndex = Show-SingleSelectMenu -Options $providerLabels -Title "API 供应商选择"

    if ($selectedIndex -lt 0 -or $selectedIndex -ge $providerKeys.Count) {
        Write-UiWarning "未选择供应商"
        return $result
    }

    $selectedKey = $providerKeys[$selectedIndex]
    $template = $script:BuiltinProviders[$selectedKey]
    $providerName = $template.Name
    $providerBaseUrl = $template.BaseUrl

    Write-UiSuccess "已选择: $providerName"

    # 自定义供应商: 输入名称 + Base URL
    if ($selectedKey -eq "custom") {
        Write-Host ""
        $customName = Read-Host "供应商名称（可选，直接回车使用默认）"
        if (-not [string]::IsNullOrWhiteSpace($customName)) {
            $providerName = $customName
        }

        do {
            $customUrl = Read-Host "Base URL（必填，如 https://api.example.com/anthropic）"
            if ([string]::IsNullOrWhiteSpace($customUrl)) {
                Write-UiDanger "Base URL 不能为空"
                continue
            }
            if ($customUrl -notmatch '^https?://') {
                Write-UiDanger "Base URL 必须以 http:// 或 https:// 开头"
                continue
            }
            break
        } while ($true)

        $providerBaseUrl = $customUrl.TrimEnd('/')
        Write-UiSuccess "Base URL 已设置: $providerBaseUrl"

        # 统一 key 生成：名称优先，回退 URL host + path hash
        $selectedKey = New-CustomProviderKey -Name $customName -BaseUrl $providerBaseUrl
        if (-not (Test-ProviderKey -Key $selectedKey)) {
            Write-UiDanger "生成的 Provider Key 非法，取消添加"
            return $result
        }
    } else {
        Write-UiInfo "请前往以下平台获取 API Key: $($template.PlatformUrl)"
    }

    # 重复检测：内置供应商三选一（新增/覆盖/取消）；自定义供应商二选一（覆盖/取消）
    $profilesDir = Get-ProviderProfilesDir
    $existingPath = Join-Path $profilesDir "$selectedKey.json"
    $isBuiltin = $selectedKey -ne "custom" -and $providerKeys -contains $selectedKey

    if ($isBuiltin) {
        $builtinExisting = @(Find-BuiltinProviderProfiles -BuiltinKey $selectedKey -Profiles $existingProfiles)
        if ($builtinExisting.Count -gt 0) {
            Write-Host ""
            Write-UiWarning "检测到 $($template.Name) 已配置："
            foreach ($item in $builtinExisting) {
                Write-UiInfo "  - $($item.Name) ($($item.BaseUrl))"
            }

            $actionIdx = Show-SingleSelectMenu -Title "如何处理？" -Options @(
                "新增（保留现有，创建新配置）"
                "覆盖现有配置"
                "取消添加"
            )
            switch ($actionIdx) {
                0 {
                    # 新增：自动生成递增 key
                    $selectedKey = Get-NextAvailableKey -BaseKey $selectedKey
                    $existingPath = Join-Path $profilesDir "$selectedKey.json"
                    Write-UiPrimary "将创建新配置: ~/.claude/providers/$selectedKey.json"
                    # 允许用户输入自定义显示名称
                    $newDisplayName = Read-Host "显示名称（可选，直接回车使用默认）"
                    if (-not [string]::IsNullOrWhiteSpace($newDisplayName)) {
                        $providerName = $newDisplayName.Trim()
                    } else {
                        # 默认名称：追加序号（如 "智谱 GLM (2)"）
                        $num = 2
                        $numMatch = [regex]::Match($selectedKey, '-(\d+)$')
                        if ($numMatch.Success) {
                            $parsed = 0
                            if ([int]::TryParse($numMatch.Groups[1].Value, [ref]$parsed)) { $num = $parsed }
                        }
                        $providerName = "$providerName ($num)"
                    }
                }
                1 {
                    # 覆盖：基础 key 存在则覆盖，否则让用户选择实例
                    if (-not (Test-Path $existingPath)) {
                        if ($builtinExisting.Count -eq 1) {
                            $selectedKey = $builtinExisting[0].Key
                        } else {
                            $owOptions = @($builtinExisting | ForEach-Object { "$($_.Name) - $($_.BaseUrl)" })
                            $owIdx = Show-SingleSelectMenu -Title "选择要覆盖的配置：" -Options $owOptions
                            if ($owIdx -lt 0 -or $owIdx -ge $builtinExisting.Count) {
                                Write-UiDim "已取消"
                                return $result
                            }
                            $selectedKey = $builtinExisting[$owIdx].Key
                        }
                        $existingPath = Join-Path $profilesDir "$selectedKey.json"
                    }
                }
                default {
                    Write-UiDim "已取消，可通过「修改供应商」更新现有配置"
                    return $result
                }
            }
        }
    } elseif (Test-Path $existingPath) {
        # 自定义供应商：保持二选一（覆盖/取消）
        try {
            $existing = Get-Content $existingPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            $existName = if ($existing["_meta"] -and $existing["_meta"]["provider"]) { $existing["_meta"]["provider"] } else { $selectedKey }
            $existUrl  = if ($existing["_meta"] -and $existing["_meta"]["baseUrl"])  { $existing["_meta"]["baseUrl"] }  else { "未知" }
            Write-Host ""
            Write-UiWarning "检测到同名供应商已存在："
            Write-UiInfo "  名称: $existName"
            Write-UiInfo "  Base URL: $existUrl"
            Write-UiInfo "  文件: ~/.claude/providers/$selectedKey.json"
        } catch {
            Write-Host ""
            Write-UiWarning "检测到供应商 $selectedKey 已存在"
        }

        $overwriteIdx = Show-SingleSelectMenu -Title "如何处理？" -Options @("覆盖现有配置", "取消添加")
        if ($overwriteIdx -ne 0) {
            Write-UiDim "已取消，可通过「修改供应商」更新现有配置"
            return $result
        }
    }

    # 安全输入 API Key
    Write-Host ""
    Write-UiPrimary "请粘贴 $providerName 的 API Key（输入不会回显）:"
    Write-UiWarning "注意: API Key 将写入 ~/.claude/settings.json 和 ~/.claude/providers/"

    $apiKeyPlain = $null
    try {
        do {
            $apiKeySecure = Read-Host -Prompt "API Key" -AsSecureString
            $bstr = [System.IntPtr]::Zero
            try {
                $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($apiKeySecure)
                $apiKeyPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
            } finally {
                if ($bstr -ne [System.IntPtr]::Zero) {
                    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
                }
            }

            if ([string]::IsNullOrWhiteSpace($apiKeyPlain)) {
                Write-UiDanger "API Key 不能为空，请重新输入"
                continue
            }
            if ($apiKeyPlain.Length -lt 10) {
                Write-UiDanger "API Key 长度过短，请检查后重新输入"
                continue
            }
            break
        } while ($true)

        # 显示配置摘要
        Write-Host ""
        Write-UiWarning "即将写入以下配置："
        Write-UiInfo "  供应商: $providerName"
        Write-UiInfo "  Base URL: $providerBaseUrl"
        Write-UiInfo "  Key 摘要: $(Get-MaskedApiKey $apiKeyPlain)"
        Write-Host ""

        $confirmIndex = Show-SingleSelectMenu -Title "确认保存配置？" -Options @("是，保存", "否，取消")
        if ($confirmIndex -ne 0) {
            Write-UiWarning "已取消"
            return $result
        }

        # 构建 Profile
        $providerProfile = @{
            "_meta" = @{
                "provider"     = $providerName
                "key"          = $selectedKey
                "baseUrl"      = $providerBaseUrl
                "configuredAt" = (Get-Date -Format "o")
            }
            "env" = @{
                "ANTHROPIC_AUTH_TOKEN" = $apiKeyPlain
                "ANTHROPIC_BASE_URL"  = $providerBaseUrl
            }
        }

        # 内置供应商的 ModelMapping
        if ($template.ContainsKey("ModelMapping") -and $template.ModelMapping) {
            $providerProfile["modelMapping"] = $template.ModelMapping
        } elseif ($selectedKey -eq "custom" -or $selectedKey -match '^custom-') {
            # 自定义供应商：询问是否配置模型映射
            $mappingIdx = Show-SingleSelectMenu -Title "是否配置模型别名映射？(可选，大多数供应商不需要)" -Options @("跳过", "配置映射")
            if ($mappingIdx -eq 1) {
                Write-UiDim "  模型映射将 Claude 模型别名 (opus/sonnet/haiku) 映射到供应商的实际模型名称"
                $customMapping = @{}
                foreach ($alias in @("opus", "sonnet", "haiku")) {
                    $modelName = (Read-Host "  $alias 映射到 (留空跳过)").Trim()
                    if (-not [string]::IsNullOrWhiteSpace($modelName)) {
                        $customMapping[$alias] = $modelName
                    }
                }
                if ($customMapping.Count -gt 0) {
                    $providerProfile["modelMapping"] = $customMapping
                }
            }
        }

        # 保存 Profile 到 ~/.claude/providers/
        $profilesDir = Get-ProviderProfilesDir
        if (-not (Test-Path $profilesDir)) {
            New-Item -ItemType Directory -Path $profilesDir -Force | Out-Null
        }
        $profilePath = Join-Path $profilesDir "$selectedKey.json"
        $tempPath = "$profilePath.tmp"
        $providerProfile | ConvertTo-Json -Depth 10 | Set-Content $tempPath -Encoding UTF8
        Move-Item $tempPath $profilePath -Force

        Write-UiSuccess "供应商 Profile 已保存: ~/.claude/providers/$selectedKey.json"

        $result.Success = $true
        $result.Key = $selectedKey
        $result.Name = $providerName
        $result.BaseUrl = $providerBaseUrl

        # 激活逻辑
        if ($Activate) {
            Switch-Provider -Key $selectedKey
            $result.Activated = $true
        } else {
            $activateIndex = Show-SingleSelectMenu -Title "是否立即激活此供应商？" -Options @("是，立即激活", "否，稍后激活")
            if ($activateIndex -eq 0) {
                Switch-Provider -Key $selectedKey
                $result.Activated = $true
            }
        }
    }
    finally {
        # 确保清除敏感变量
        $apiKeyPlain = $null
        $apiKeySecure = $null
    }

    return $result
}

# ─── ModelMapping ─────────────────────────────────────────────────────────────

function Edit-ModelMapping {
    <#
    .SYNOPSIS
    交互式管理供应商的 modelMapping（查看/添加/修改/删除）
    .PARAMETER ProfilePath
    Profile JSON 文件路径
    .RETURNS
    hashtable|$null — 修改后的 modelMapping（$null 表示删除全部映射）
    #>
    param(
        [Parameter(Mandatory)] [string]$ProfilePath
    )

    $profileData = Get-Content $ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    $mapping = if ($profileData.ContainsKey("modelMapping") -and $profileData["modelMapping"]) {
        $clone = @{}
        foreach ($k in $profileData["modelMapping"].Keys) { $clone[$k] = $profileData["modelMapping"][$k] }
        $clone
    } else { @{} }

    $standardAliases = @("opus", "sonnet", "haiku")

    while ($true) {
        Write-Host ""
        Write-UiPrimary "模型映射管理"
        Write-Host ""

        if ($mapping.Count -eq 0) {
            Write-UiDim "  (无模型映射)"
        } else {
            foreach ($alias in $standardAliases) {
                if ($mapping.ContainsKey($alias)) { Write-UiInfo "  $alias => $($mapping[$alias])" }
            }
        }

        Write-Host ""
        $options = @(
            "设置模型映射 (opus/sonnet/haiku)"
            "清除全部映射"
            "返回"
        )
        $choice = Show-SingleSelectMenu -Title "选择操作：" -Options $options

        switch ($choice) {
            0 {
                foreach ($alias in $standardAliases) {
                    $current = if ($mapping.ContainsKey($alias)) { $mapping[$alias] } else { "(未设置)" }
                    $newVal = (Read-Host "  $alias [$current] (留空保持不变，输入 - 删除)").Trim()
                    if ($newVal -eq "-") {
                        if ($mapping.ContainsKey($alias)) { $mapping.Remove($alias) }
                    } elseif (-not [string]::IsNullOrWhiteSpace($newVal)) {
                        $mapping[$alias] = $newVal
                    }
                }
                Write-UiSuccess "模型映射已更新"
            }
            1 {
                if ($mapping.Count -eq 0) { Write-UiDim "当前无映射，无需清除"; continue }
                $confirmIdx = Show-SingleSelectMenu -Title "确认清除全部模型映射？" -Options @("是，清除", "否，取消")
                if ($confirmIdx -eq 0) { $mapping = @{}; Write-UiSuccess "已清除全部模型映射" }
            }
            default { break }
        }

        if ($choice -eq 2 -or $choice -eq -1) { break }
    }

    if ($mapping.Count -eq 0) { return $null }
    return $mapping
}

# ─── Update ────────────────────────────────────────────────────────────────────

function Edit-Provider {
    <#
    .SYNOPSIS
    修改已有供应商配置
    .PARAMETER Key
    Provider Key（如 zhipu、custom-1）
    #>
    param([Parameter(Mandatory)] [string]$Key)

    if (-not (Test-ProviderKey -Key $Key)) {
        Write-UiDanger "非法 Provider Key: $Key"
        return
    }

    $profilesDir = Get-ProviderProfilesDir
    $profilePath = Join-Path $profilesDir "$Key.json"

    if (-not (Test-Path $profilePath)) {
        Write-UiDanger "供应商 Profile 不存在: $Key"
        return
    }

    $profile = Get-Content $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable -ErrorAction Stop

    # 显示当前配置
    $meta = $profile["_meta"]
    $envData = $profile["env"]
    Write-Host ""
    Write-UiPrimary "当前配置:"
    Write-UiInfo "  供应商: $($meta["provider"])"
    Write-UiInfo "  Base URL: $($meta["baseUrl"])"
    Write-UiInfo "  API Key: $(Get-MaskedApiKey $envData["ANTHROPIC_AUTH_TOKEN"])"
    # 显示当前 modelMapping 状态
    $mappingStatus = if ($profile.ContainsKey("modelMapping") -and $profile["modelMapping"] -and $profile["modelMapping"].Count -gt 0) {
        $mappingItems = @()
        foreach ($k in @("opus", "sonnet", "haiku")) {
            if ($profile["modelMapping"].ContainsKey($k)) { $mappingItems += "$k=$($profile["modelMapping"][$k])" }
        }
        $mappingItems -join ", "
    } else { "未配置" }
    Write-UiInfo "  模型映射: $mappingStatus"
    Write-Host ""

    $editOptions = @(
        "修改 API Key"
        "修改 Base URL"
        "修改供应商名称"
        "配置模型映射"
        "全部重新配置"
    )
    $editChoice = Show-SingleSelectMenu -Title "选择修改项：" -Options $editOptions

    if ($editChoice -eq -1) { return }

    $pendingNewKey = $null

    switch ($editChoice) {
        0 {
            # 修改 API Key
            Write-UiPrimary "请输入新的 API Key（输入不会回显）:"
            $newKeySecure = Read-Host -Prompt "新 API Key" -AsSecureString
            $bstr = [System.IntPtr]::Zero
            try {
                $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($newKeySecure)
                $newKeyPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
            } finally {
                if ($bstr -ne [System.IntPtr]::Zero) {
                    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
                }
            }
            if ([string]::IsNullOrWhiteSpace($newKeyPlain) -or $newKeyPlain.Length -lt 10) {
                Write-UiDanger "API Key 无效，取消修改"
                $newKeyPlain = $null
                return
            }
            $envData["ANTHROPIC_AUTH_TOKEN"] = $newKeyPlain
            $newKeyPlain = $null
        }
        1 {
            # 修改 Base URL
            $newUrl = Read-Host "新 Base URL"
            if ([string]::IsNullOrWhiteSpace($newUrl) -or $newUrl -notmatch '^https?://') {
                Write-UiDanger "Base URL 无效，取消修改"
                return
            }
            $newUrl = $newUrl.TrimEnd('/')
            $meta["baseUrl"] = $newUrl
            $envData["ANTHROPIC_BASE_URL"] = $newUrl
        }
        2 {
            # 修改名称
            $newName = Read-Host "新供应商名称"
            if ([string]::IsNullOrWhiteSpace($newName)) {
                Write-UiDanger "名称不能为空，取消修改"
                return
            }
            $newName = $newName.Trim()
            $meta["provider"] = $newName

            # 自定义供应商：同步重命名文件（key 从名称重新派生）
            if ($Key -match '^custom-') {
                $candidateKey = New-CustomProviderKey -Name $newName -BaseUrl $meta["baseUrl"]
                if ((Test-ProviderKey -Key $candidateKey) -and $candidateKey -ne $Key) {
                    $candidatePath = Join-Path $profilesDir "$candidateKey.json"
                    if (Test-Path $candidatePath) {
                        Write-UiWarning "目标文件 $candidateKey.json 已存在，仅更新显示名称"
                    } else {
                        $pendingNewKey = $candidateKey
                    }
                }
            }
        }
        3 {
            # 配置模型映射
            $newMapping = Edit-ModelMapping -ProfilePath $profilePath
            if ($null -eq $newMapping) {
                if ($profile.ContainsKey("modelMapping")) { $profile.Remove("modelMapping") }
            } else {
                $profile["modelMapping"] = $newMapping
            }
            # 直接写入 Profile（不经过后续的 meta/env 合并路径）
            $tempPath = "$profilePath.tmp"
            $profile | ConvertTo-Json -Depth 10 | Set-Content $tempPath -Encoding UTF8
            Move-Item $tempPath $profilePath -Force
            Write-UiSuccess "模型映射已保存"
            # 若当前为活跃供应商，同步 settings.json
            $activeNow = Get-ActiveProvider
            if ($activeNow -and $activeNow.Key -eq $Key) {
                Switch-Provider -Key $Key
            }
            return
        }
        4 {
            # 全部重新配置 → 备份旧配置，添加新配置，成功后清理旧备份
            $backupPath = "$profilePath.bak"
            try {
                Copy-Item $profilePath $backupPath -Force
                $addResult = Add-Provider
                if ($addResult.Success) {
                    # 新配置已由 Add-Provider 写入（可能是新 key），安全清理旧文件
                    if (Test-Path $backupPath) { Remove-Item $backupPath -Force }
                    # 若新 key 不同于旧 key，删除旧 Profile 文件
                    if ($addResult.Key -ne $Key -and (Test-Path $profilePath)) {
                        Remove-Item $profilePath -Force
                    }
                } else {
                    # Add-Provider 失败或取消 → 恢复旧配置
                    if (Test-Path $backupPath) {
                        Move-Item $backupPath $profilePath -Force
                        Write-UiWarning "已恢复原有配置"
                    }
                }
            } catch {
                # 异常恢复
                if (Test-Path $backupPath) {
                    Move-Item $backupPath $profilePath -Force -ErrorAction SilentlyContinue
                    Write-UiWarning "操作异常，已恢复原有配置"
                }
            }
            return
        }
    }

    # 在写入 Profile 之前判断是否为当前活跃供应商
    # （写入后 BaseUrl 可能已变更，Get-ActiveProvider 将无法匹配旧 URL）
    $wasActive = $false
    $active = Get-ActiveProvider
    if ($active -and $active.Key -eq $Key) {
        $wasActive = $true
    }

    # 原子写入更新后的 Profile
    $effectiveKey = $Key
    if ($pendingNewKey) {
        $meta["key"] = $pendingNewKey
        $effectiveKey = $pendingNewKey
    }
    $profile["_meta"] = $meta
    $profile["env"] = $envData

    if ($pendingNewKey) {
        # 写入新文件 + 删除旧文件（重命名）
        $newProfilePath = Join-Path $profilesDir "$pendingNewKey.json"
        $tempPath = "$newProfilePath.tmp"
        $profile | ConvertTo-Json -Depth 10 | Set-Content $tempPath -Encoding UTF8
        Move-Item $tempPath $newProfilePath -Force
        Remove-Item $profilePath -Force
        Write-UiSuccess "供应商配置已更新: $($meta["provider"]) ($Key → $pendingNewKey)"
    } else {
        $tempPath = "$profilePath.tmp"
        $profile | ConvertTo-Json -Depth 10 | Set-Content $tempPath -Encoding UTF8
        Move-Item $tempPath $profilePath -Force
        Write-UiSuccess "供应商配置已更新: $($meta["provider"])"
    }

    # 如果修改前是活跃供应商 → 自动同步 settings.json
    if ($wasActive) {
        Write-UiPrimary "正在同步活跃供应商配置到 settings.json..."
        Switch-Provider -Key $effectiveKey
    }
}

# ─── Delete ────────────────────────────────────────────────────────────────────

function Remove-Provider {
    <#
    .SYNOPSIS
    删除供应商 Profile
    .PARAMETER Key
    Provider Key
    #>
    param([Parameter(Mandatory)] [string]$Key)

    if (-not (Test-ProviderKey -Key $Key)) {
        Write-UiDanger "非法 Provider Key: $Key"
        return
    }

    $profilesDir = Get-ProviderProfilesDir
    $profilePath = Join-Path $profilesDir "$Key.json"

    if (-not (Test-Path $profilePath)) {
        Write-UiDanger "供应商 Profile 不存在: $Key"
        return
    }

    # 安全检查: 活跃供应商不能直接删除
    $active = Get-ActiveProvider
    if ($active -and $active.Key -eq $Key) {
        Write-UiDanger "无法删除当前活跃的供应商: $($active.Name)"
        Write-UiWarning "请先切换到其他供应商后再删除"
        return
    }

    $confirmIndex = Show-SingleSelectMenu -Title "确认删除供应商 Profile: $Key？" -Options @("是，删除", "否，取消")
    if ($confirmIndex -ne 0) {
        Write-UiDim "已取消"
        return
    }

    Remove-Item $profilePath -Force
    Write-UiSuccess "已删除供应商 Profile: $Key"
}

# ─── Switch ────────────────────────────────────────────────────────────────────

function Switch-Provider {
    <#
    .SYNOPSIS
    切换活跃供应商（读 Profile → 合并 settings.json）
    .PARAMETER Key
    Provider Key（可选，不指定则交互选择）
    #>
    param([string]$Key = "")

    # HC-13: @() 包裹
    $profiles = @(Get-ProviderProfiles)
    if ($profiles.Count -eq 0) {
        Write-UiWarning "未找到供应商 Profile，请先添加供应商"
        return
    }

    # 交互选择
    if ([string]::IsNullOrWhiteSpace($Key)) {
        $active = Get-ActiveProvider
        $options = @()
        # 检测同名：同名供应商需追加 BaseUrl 消歧
        $nameCount = @{}
        foreach ($p in $profiles) {
            $n = if ([string]::IsNullOrWhiteSpace($p.Name)) { "未知" } else { $p.Name }
            if ($nameCount.ContainsKey($n)) { $nameCount[$n]++ } else { $nameCount[$n] = 1 }
        }
        foreach ($p in $profiles) {
            $tag = if ($active -and $active.Key -eq $p.Key) { " [当前]" } else { "" }
            $displayName = if ([string]::IsNullOrWhiteSpace($p.Name)) { "未知" } else { $p.Name }
            if ($nameCount[$displayName] -gt 1) {
                $options += "$displayName - $($p.BaseUrl)$tag"
            } else {
                $options += "$displayName$tag"
            }
        }

        $selectedIdx = Show-SingleSelectMenu -Title "选择要切换的供应商：" -Options $options
        if ($selectedIdx -lt 0 -or $selectedIdx -ge $profiles.Count) {
            Write-UiDim "已取消"
            return
        }
        $Key = $profiles[$selectedIdx].Key
    }

    if (-not (Test-ProviderKey -Key $Key)) {
        Write-UiDanger "非法 Provider Key: $Key"
        return
    }

    # 读取 Profile
    $profilePath = Join-Path (Get-ProviderProfilesDir) "$Key.json"
    if (-not (Test-Path $profilePath)) {
        Write-UiDanger "供应商 Profile 不存在: $Key"
        return
    }

    $profile = Get-Content $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable -ErrorAction Stop

    # 读取 settings.json → 合并供应商字段
    $settings = Read-SettingsJson

    # 确保 env 存在
    if (-not $settings.ContainsKey("env")) {
        $settings["env"] = @{}
    }

    # 仅覆盖供应商相关字段
    if ($profile.ContainsKey("env") -and $profile["env"]) {
        if ($profile["env"].ContainsKey("ANTHROPIC_AUTH_TOKEN")) {
            $settings["env"]["ANTHROPIC_AUTH_TOKEN"] = $profile["env"]["ANTHROPIC_AUTH_TOKEN"]
        }
        if ($profile["env"].ContainsKey("ANTHROPIC_BASE_URL")) {
            $settings["env"]["ANTHROPIC_BASE_URL"] = $profile["env"]["ANTHROPIC_BASE_URL"]
        }
    }

    # modelMapping 处理
    if ($profile.ContainsKey("modelMapping") -and $profile["modelMapping"]) {
        $settings["modelMapping"] = $profile["modelMapping"]
    } elseif ($settings.ContainsKey("modelMapping")) {
        $settings.Remove("modelMapping")
    }

    # 原子写入
    Write-SettingsJsonAtomic -Settings $settings

    $providerName = if ($profile.ContainsKey("_meta") -and $profile["_meta"].ContainsKey("provider")) { $profile["_meta"]["provider"] } else { $Key }
    Write-UiSuccess "已切换到: $providerName"
}

# ─── Dashboard ─────────────────────────────────────────────────────────────────

function Render-ProviderTable {
    <#
    .SYNOPSIS
    渲染供应商 Power Table（表头 + 数据行，含选中标记和颜色区分）
    #>
    param(
        [Parameter(Mandatory)] [array]$Profiles,
        [int]$SelectedIndex = 0
    )

    $colWidths = @(15, 35, 15, 10)

    # 表头
    $headerLine = "  " +
        (Format-DisplayPad "供应商" $colWidths[0]) + " " +
        (Format-DisplayPad "Base URL" $colWidths[1]) + " " +
        (Format-DisplayPad "API Key" $colWidths[2]) + " " +
        (Format-DisplayPad "状态" $colWidths[3])
    Write-UiInfo $headerLine

    $sepWidth = ($colWidths | Measure-Object -Sum).Sum + $colWidths.Count - 1
    Write-UiDim ("  " + [string]::new("-", $sepWidth))

    for ($i = 0; $i -lt $Profiles.Count; $i++) {
        $p = $Profiles[$i]
        $isSelected = $i -eq $SelectedIndex

        $marker = if ($isSelected) { "►" } else { " " }
        $color = if ($isSelected) { "Primary" }
                 elseif ($p.IsActive) { "Success" }
                 else { "Dim" }

        # URL 截断
        $urlDisplay = [string]$p.BaseUrl
        if ($urlDisplay.Length -gt $colWidths[1]) {
            $urlDisplay = $urlDisplay.Substring(0, $colWidths[1] - 3) + "..."
        }

        # Name 截断（CJK 感知）
        $nameDisplay = [string]$p.Name
        if ((Get-StringDisplayWidth $nameDisplay) -gt $colWidths[0]) {
            while ((Get-StringDisplayWidth ($nameDisplay + "...")) -gt $colWidths[0] -and $nameDisplay.Length -gt 0) {
                $nameDisplay = $nameDisplay.Substring(0, $nameDisplay.Length - 1)
            }
            $nameDisplay = $nameDisplay + "..."
        }

        $statusText = if ($p.IsActive) { "Active" } else { "Inactive" }

        $line = "$marker " +
            (Format-DisplayPad $nameDisplay $colWidths[0]) + " " +
            (Format-DisplayPad $urlDisplay $colWidths[1]) + " " +
            (Format-DisplayPad ([string]$p.MaskedApiKey) $colWidths[2]) + " " +
            (Format-DisplayPad $statusText $colWidths[3])
        Write-UiOutput $line -Type $color
    }
}

function Render-ActionBar {
    <#
    .SYNOPSIS
    渲染底部热键提示栏（热键高亮显示）
    #>
    param([bool]$HasProviders)

    Write-Host ""
    if ($HasProviders) {
        Write-UiDim " [" -NoNewline
        Write-UiInfo "↑↓" -NoNewline
        Write-UiDim "] 移动  [" -NoNewline
        Write-UiInfo "Enter" -NoNewline
        Write-UiDim "] 切换活跃  [" -NoNewline
        Write-UiInfo "A" -NoNewline
        Write-UiDim "] 添加  [" -NoNewline
        Write-UiInfo "E" -NoNewline
        Write-UiDim "] 修改  [" -NoNewline
        Write-UiInfo "M" -NoNewline
        Write-UiDim "] 映射  [" -NoNewline
        Write-UiInfo "D" -NoNewline
        Write-UiDim "] 删除  [" -NoNewline
        Write-UiInfo "Esc" -NoNewline
        Write-UiDim "] 返回"
    } else {
        Write-UiDim " [" -NoNewline
        Write-UiInfo "A" -NoNewline
        Write-UiDim "] 添加  [" -NoNewline
        Write-UiInfo "Esc" -NoNewline
        Write-UiDim "] 返回"
    }
}

function Show-ProviderDashboardFallback {
    <#
    .SYNOPSIS
    供应商 Dashboard 降级模式（非 ANSI 终端：数字输入）
    #>

    while ($true) {
        $data = Get-ProviderDisplayData
        # HC-13: @() 包裹
        $profiles = @($data.Profiles)

        Write-Host ""
        Write-UiPrimary "供应商管理"
        Write-Host ""

        if ($profiles.Count -eq 0) {
            Write-UiWarning "暂无供应商配置"
            Write-Host ""
            Write-UiInfo "操作: A=添加供应商  Q=返回上级"
        } else {
            for ($i = 0; $i -lt $profiles.Count; $i++) {
                $p = $profiles[$i]
                $statusTag = if ($p.IsActive) { "Active" } else { "Inactive" }
                Write-Host ("  [{0}] {1} - {2} ({3})" -f ($i + 1), $p.Name, $p.BaseUrl, $statusTag)
            }
            Write-Host ""
            Write-UiInfo "操作: [编号]=切换活跃  A=添加  E<编号>=修改  M<编号>=映射  D<编号>=删除  Q=返回"
        }

        $userInput = Read-Host "请输入"
        if ([string]::IsNullOrWhiteSpace($userInput)) { continue }
        $userInput = $userInput.Trim()

        if ($userInput -match '^[Qq]$') { return }
        if ($userInput -match '^[Aa]$') { Add-Provider; continue }

        if ($userInput -match '^\d+$') {
            $idx = [int]$userInput - 1
            if ($idx -ge 0 -and $idx -lt $profiles.Count) {
                Switch-Provider -Key $profiles[$idx].Key
            } else {
                Write-UiDanger "编号超出范围"
            }
            continue
        }
        if ($userInput -match '^[Ee]\s*(\d+)$') {
            $idx = [int]$Matches[1] - 1
            if ($idx -ge 0 -and $idx -lt $profiles.Count) {
                Edit-Provider -Key $profiles[$idx].Key
            } else {
                Write-UiDanger "编号超出范围"
            }
            continue
        }
        if ($userInput -match '^[Mm]\s*(\d+)$') {
            $idx = [int]$Matches[1] - 1
            if ($idx -ge 0 -and $idx -lt $profiles.Count) {
                $targetKey = $profiles[$idx].Key
                $mappingProfilePath = Join-Path (Get-ProviderProfilesDir) "$targetKey.json"
                if (Test-Path $mappingProfilePath) {
                    $newMapping = Edit-ModelMapping -ProfilePath $mappingProfilePath
                    $mappingProfile = Get-Content $mappingProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable -ErrorAction Stop
                    if ($null -eq $newMapping) {
                        if ($mappingProfile.ContainsKey("modelMapping")) { $mappingProfile.Remove("modelMapping") }
                    } else {
                        $mappingProfile["modelMapping"] = $newMapping
                    }
                    $tempMappingPath = "$mappingProfilePath.tmp"
                    $mappingProfile | ConvertTo-Json -Depth 10 | Set-Content $tempMappingPath -Encoding UTF8
                    Move-Item $tempMappingPath $mappingProfilePath -Force
                    if ($profiles[$idx].IsActive) { Switch-Provider -Key $targetKey }
                }
            } else {
                Write-UiDanger "编号超出范围"
            }
            continue
        }
        if ($userInput -match '^[Dd]\s*(\d+)$') {
            $idx = [int]$Matches[1] - 1
            if ($idx -ge 0 -and $idx -lt $profiles.Count) {
                Remove-Provider -Key $profiles[$idx].Key
            } else {
                Write-UiDanger "编号超出范围"
            }
            continue
        }

        Write-UiDanger "无效输入"
    }
}

function Show-ProviderDashboard {
    <#
    .SYNOPSIS
    供应商管理 Dashboard（单屏 Power Table，替代三级菜单）
    入口处自动调用 Sync-ProviderFromSettings
    #>

    try {
        Sync-ProviderFromSettings
    } catch {
        Write-UiWarning "供应商自动同步失败: $($_.Exception.Message)"
    }

    # ANSI 降级（防御性检查，避免 $script:SupportsAnsi 未定义时严格模式报错）
    $supportsAnsi = $false
    if (Get-Variable -Scope Script -Name SupportsAnsi -ErrorAction SilentlyContinue) {
        $supportsAnsi = [bool]$script:SupportsAnsi
    }
    if (-not $supportsAnsi) {
        Show-ProviderDashboardFallback
        return
    }

    $selectedIndex = 0

    try { [Console]::CursorVisible = $false } catch { }
    try {
        while ($true) {
            $data = Get-ProviderDisplayData
            # 嵌套菜单可能恢复光标可见，每帧确保隐藏
            try { [Console]::CursorVisible = $false } catch { }
            # HC-13: @() 包裹
            $profiles = @($data.Profiles)

            # Clamp selectedIndex
            if ($profiles.Count -eq 0) {
                $selectedIndex = 0
            } else {
                if ($selectedIndex -ge $profiles.Count) { $selectedIndex = $profiles.Count - 1 }
                if ($selectedIndex -lt 0) { $selectedIndex = 0 }
            }

            # 清屏 + 光标归位
            Clear-UiScreen

            Show-AsciiBanner "供应商管理"

            if (-not $data.HasProviders) {
                Write-UiWarning "  暂无供应商配置"
                Write-Host ""
                Write-UiDim "  按 [A] 添加第一个供应商"
            } else {
                Render-ProviderTable -Profiles $profiles -SelectedIndex $selectedIndex

                # Detail Pane：展示选中供应商的 modelMapping
                if ($profiles.Count -gt 0) {
                    $selected = $profiles[$selectedIndex]
                    $detailProfilePath = Join-Path (Get-ProviderProfilesDir) "$($selected.Key).json"
                    Write-Host ""
                    if (Test-Path $detailProfilePath) {
                        try {
                            $detailData = Get-Content $detailProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable -ErrorAction Stop
                            if ($null -ne $detailData -and $detailData.ContainsKey("modelMapping") -and
                                $null -ne $detailData["modelMapping"] -and $detailData["modelMapping"].Count -gt 0) {
                                $mappingParts = @()
                                foreach ($alias in @("opus", "sonnet", "haiku")) {
                                    if ($detailData["modelMapping"].ContainsKey($alias)) {
                                        $mappingParts += "$alias=$($detailData["modelMapping"][$alias])"
                                    }
                                }
                                foreach ($k in ($detailData["modelMapping"].Keys | Sort-Object)) {
                                    if ($k -notin @("opus", "sonnet", "haiku")) { $mappingParts += "$k=$($detailData["modelMapping"][$k])" }
                                }
                                Write-UiDim "  映射: $($mappingParts -join ' | ')"
                            } else {
                                Write-UiDim "  映射: 无"
                            }
                        } catch { Write-UiDim "  映射: (读取失败)" }
                    }
                }
            }

            Render-ActionBar -HasProviders $data.HasProviders

            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow' {
                    if ($profiles.Count -gt 0) {
                        $selectedIndex = ($selectedIndex - 1 + $profiles.Count) % $profiles.Count
                    }
                }
                'DownArrow' {
                    if ($profiles.Count -gt 0) {
                        $selectedIndex = ($selectedIndex + 1) % $profiles.Count
                    }
                }
                'Enter' {
                    if ($profiles.Count -gt 0) {
                        Switch-Provider -Key $profiles[$selectedIndex].Key
                    }
                }
                'A' {
                    Add-Provider
                }
                'E' {
                    if ($profiles.Count -gt 0) {
                        Edit-Provider -Key $profiles[$selectedIndex].Key
                    }
                }
                'M' {
                    if ($profiles.Count -gt 0) {
                        $selectedForMapping = $profiles[$selectedIndex]
                        $mappingProfilePath = Join-Path (Get-ProviderProfilesDir) "$($selectedForMapping.Key).json"
                        if (Test-Path $mappingProfilePath) {
                            $newMapping = Edit-ModelMapping -ProfilePath $mappingProfilePath
                            $mappingProfile = Get-Content $mappingProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable -ErrorAction Stop
                            if ($null -eq $newMapping) {
                                if ($mappingProfile.ContainsKey("modelMapping")) { $mappingProfile.Remove("modelMapping") }
                            } else {
                                $mappingProfile["modelMapping"] = $newMapping
                            }
                            $tempMappingPath = "$mappingProfilePath.tmp"
                            $mappingProfile | ConvertTo-Json -Depth 10 | Set-Content $tempMappingPath -Encoding UTF8
                            Move-Item $tempMappingPath $mappingProfilePath -Force
                            if ($selectedForMapping.IsActive) { Switch-Provider -Key $selectedForMapping.Key }
                        }
                    }
                }
                'D' {
                    if ($profiles.Count -gt 0) {
                        $selected = $profiles[$selectedIndex]
                        if ($selected.IsActive) {
                            Write-Host ""
                            Write-UiDanger "无法删除当前活跃的供应商: $($selected.Name)"
                            Write-UiWarning "请先切换到其他供应商后再删除"
                            Write-Host ""
                            Write-UiDim "按任意键继续..."
                            [Console]::ReadKey($true) | Out-Null
                        } else {
                            Remove-Provider -Key $selected.Key
                        }
                    }
                }
                'Escape' {
                    return
                }
            }
        }
    } finally {
        try { [Console]::CursorVisible = $true } catch { }
    }
}

function Show-ProviderManageMenu {
    <#
    .SYNOPSIS
    供应商管理兼容入口（过渡期，委托到 Dashboard）
    #>
    Show-ProviderDashboard
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用
