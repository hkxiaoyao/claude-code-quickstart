# Claude Code 常用配置步骤 - CCQ
# 功能: 声明式字段管理，仅补缺失项，不覆盖 ApiKey/Ccline/用户已有配置

#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 依赖: Ui.ps1, Profile.ps1（由入口脚本 dot-source 加载）

# ─── ClaudeConfig 字段归属声明 ──────────────────────────────────────────────────────

# ClaudeConfig 负责的 env 默认值（仅补齐缺失项，不覆盖已有配置）
$script:ClaudeConfigEnvDefaults = @{
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE"          = "90"
    "CLAUDE_CODE_ATTRIBUTION_HEADER"           = "0"
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" = "1"
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"     = "1"
    "DISABLE_INSTALLATION_CHECKS"              = "1"
    "MAX_THINKING_TOKENS"                      = "31999"
}

# ClaudeConfig 废弃的 env 键（Update 时从 settings.env 中删除）
$script:ClaudeConfigDeprecatedEnvKeys = @()

# ClaudeConfig 负责的基础权限列表（合并策略：只添加缺失项，不删除已有项）
$script:ClaudeConfigBasePermissions = @(
    "Bash",
    "BashOutput",
    "Edit",
    "Glob",
    "Grep",
    "KillShell",
    "NotebookEdit",
    "Read",
    "SlashCommand",
    "Task",
    "TodoWrite",
    "WebFetch",
    "WebSearch",
    "Write"
)

# ─── Fingerprint（供 Manage 更新指纹预检使用）─────────────────────────────────

function Get-ClaudeConfigFingerprint {
    <#
    .SYNOPSIS
    计算 ClaudeConfig 步骤的内容指纹（基于 env defaults + deprecated keys + permissions）
    .RETURNS
    string - SHA-256 指纹
    #>
    $parts = @()
    foreach ($key in ($script:ClaudeConfigEnvDefaults.Keys | Sort-Object)) {
        $parts += "${key}=$($script:ClaudeConfigEnvDefaults[$key])"
    }
    $parts += "deprecated:" + (($script:ClaudeConfigDeprecatedEnvKeys | Sort-Object) -join ",")
    $parts += "permissions:" + (($script:ClaudeConfigBasePermissions | Sort-Object) -join ",")
    $parts += "top-level:language"
    $parts += "top-level:alwaysThinkingEnabled"
    $parts += "top-level:plansDirectory=.claude/plan"
    return Get-StringFingerprint -Text ($parts -join "`n")
}

# ─── Drift Analysis ─────────────────────────────────────────────────────────

function Compare-ClaudeConfigDrift {
    <#
    .SYNOPSIS
    逐项对比 settings.json 实际内容与 ClaudeConfig 声明式模板，返回漂移分析结果
    .RETURNS
    hashtable — { HasDrift, NeedsInstallCompletion, NeedsUpdateAlignment, Details }
    #>

    $result = @{
        HasDrift               = $false
        NeedsInstallCompletion = $false
        NeedsUpdateAlignment   = $false
        Details                = @{
            MissingEnvKeys               = @()
            DriftedEnvKeys               = @()
            MissingPermissions           = @()
            DeprecatedEnvKeys            = @()
            MissingLanguage              = $false
            MissingAlwaysThinkingEnabled = $false
            MissingPlansDirectory        = $false
        }
    }

    $settingsPath = Get-ClaudeSettingsPath
    if (-not (Test-Path $settingsPath)) {
        $result.HasDrift                             = $true
        $result.NeedsInstallCompletion               = $true
        $result.Details.MissingLanguage              = $true
        $result.Details.MissingAlwaysThinkingEnabled = $true
        $result.Details.MissingPlansDirectory        = $true
        $result.Details.MissingEnvKeys               = @($script:ClaudeConfigEnvDefaults.Keys)
        $result.Details.MissingPermissions           = @($script:ClaudeConfigBasePermissions)
        return $result
    }

    try {
        $content  = Get-Content $settingsPath -Raw -Encoding UTF8
        $settings = $content | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        if (-not $settings) { $settings = @{} }
    } catch {
        $result.HasDrift               = $true
        $result.NeedsInstallCompletion = $true
        return $result
    }

    # 1. language / thinking 顶层配置检查
    if (-not $settings.ContainsKey("language") -or [string]::IsNullOrWhiteSpace([string]$settings["language"])) {
        $result.Details.MissingLanguage = $true
        $result.NeedsInstallCompletion  = $true
    }
    if (-not $settings.ContainsKey("alwaysThinkingEnabled")) {
        $result.Details.MissingAlwaysThinkingEnabled = $true
        $result.NeedsInstallCompletion               = $true
    }
    if (-not $settings.ContainsKey("plansDirectory") -or [string]::IsNullOrWhiteSpace([string]$settings["plansDirectory"])) {
        $result.Details.MissingPlansDirectory = $true
        $result.NeedsInstallCompletion        = $true
    } elseif ([string]$settings["plansDirectory"] -ne ".claude/plan") {
        $result.NeedsUpdateAlignment = $true
    }

    # 2. env 键检查
    $envSection = if ($settings.ContainsKey("env") -and $settings["env"]) { $settings["env"] } else { @{} }
    foreach ($entry in $script:ClaudeConfigEnvDefaults.GetEnumerator()) {
        if (-not $envSection.ContainsKey($entry.Key) -or [string]::IsNullOrWhiteSpace([string]$envSection[$entry.Key])) {
            $result.Details.MissingEnvKeys += $entry.Key
            $result.NeedsInstallCompletion  = $true
        } elseif ([string]$envSection[$entry.Key] -ne [string]$entry.Value) {
            $result.Details.DriftedEnvKeys += @{ Key = $entry.Key; Expected = $entry.Value; Actual = [string]$envSection[$entry.Key] }
            $result.NeedsUpdateAlignment    = $true
        }
    }

    # 3. 废弃键检查
    foreach ($deprecatedKey in $script:ClaudeConfigDeprecatedEnvKeys) {
        if ($envSection.ContainsKey($deprecatedKey)) {
            $result.Details.DeprecatedEnvKeys += $deprecatedKey
            $result.NeedsUpdateAlignment       = $true
        }
    }

    # 4. permissions 检查
    $allowList = @()
    if ($settings.ContainsKey("permissions") -and $settings["permissions"] -and
        $settings["permissions"].ContainsKey("allow") -and $settings["permissions"]["allow"]) {
        $allowList = @($settings["permissions"]["allow"])
    }
    foreach ($perm in $script:ClaudeConfigBasePermissions) {
        if ($allowList -notcontains $perm) {
            $result.Details.MissingPermissions += $perm
            $result.NeedsInstallCompletion      = $true
        }
    }

    $result.HasDrift = $result.NeedsInstallCompletion -or $result.NeedsUpdateAlignment
    return $result
}

# ─── Test / Install / Verify ─────────────────────────────────────────────────

function Test-ClaudeConfigInstalled {
    <#
    .SYNOPSIS
    检测 ClaudeConfig 是否完整安装（声明式逐项对比，替代原 Exists 浅检测）
    .DESCRIPTION
    调用 Compare-ClaudeConfigDrift 进行完整漂移分析。
    NeedsInstallCompletion=true（缺失 env 键/permissions/language）→ IsInstalled=false。
    NeedsUpdateAlignment=true（值偏移/废弃键）→ IsInstalled=true，触发 Update 对齐。
    .RETURNS
    标准检测结果 hashtable（IsInstalled, Version, Data, Message）
    #>

    $result = @{ IsInstalled = $false; Version = ""; Data = @{}; Message = "" }

    $settingsPath = Get-ClaudeSettingsPath
    if (-not (Test-Path $settingsPath)) {
        $result.Message = "Claude Code 常用配置未安装: settings.json 不存在"
        return $result
    }

    $drift = Compare-ClaudeConfigDrift
    $result.Data["Drift"]                      = $drift
    $result.Data["MissingEnvKeys"]             = @($drift.Details.MissingEnvKeys)
    $result.Data["DriftedEnvKeys"]             = @($drift.Details.DriftedEnvKeys)
    $result.Data["MissingPermissions"]         = @($drift.Details.MissingPermissions)
    $result.Data["DeprecatedEnvKeys"]          = @($drift.Details.DeprecatedEnvKeys)
    $result.Data["MissingLanguage"]            = [bool]$drift.Details.MissingLanguage
    $result.Data["MissingAlwaysThinkingEnabled"] = [bool]$drift.Details.MissingAlwaysThinkingEnabled
    $result.Data["MissingPlansDirectory"]      = [bool]$drift.Details.MissingPlansDirectory

    if (-not $drift.NeedsInstallCompletion) {
        $result.IsInstalled = $true
        $result.Message = if ($drift.NeedsUpdateAlignment) {
            "Claude Code 常用配置已安装（检测到可对齐漂移）"
        } else {
            "Claude Code 常用配置已安装"
        }
        return $result
    }

    $issues = [System.Collections.ArrayList]::new()
    if (@($drift.Details.MissingEnvKeys).Count -gt 0) {
        [void]$issues.Add("env 缺少: $(@($drift.Details.MissingEnvKeys) -join ', ')")
    }
    if (@($drift.Details.MissingPermissions).Count -gt 0) {
        [void]$issues.Add("permissions.allow 缺少: $(@($drift.Details.MissingPermissions).Count) 项")
    }
    if ($drift.Details.MissingLanguage) {
        [void]$issues.Add("language 配置缺失")
    }
    if ($drift.Details.MissingAlwaysThinkingEnabled) {
        [void]$issues.Add("alwaysThinkingEnabled 配置缺失")
    }
    if ($drift.Details.MissingPlansDirectory) {
        [void]$issues.Add("plansDirectory 配置缺失")
    }
    $result.Message = if ($issues.Count -gt 0) {
        "Claude Code 常用配置不完整: $(@($issues) -join '; ')"
    } else {
        "Claude Code 常用配置未完成安装"
    }

    return $result
}

function Install-ClaudeConfig {
    <#
    .SYNOPSIS
    写入 Claude Code 常用配置（读取 -> 补缺失 -> 原子写入）
    .DESCRIPTION
    仅管理 ClaudeConfig 自有字段，不覆盖 ApiKey（供应商配置）、Ccline（statusLine）或用户自定义配置
    .RETURNS
    包含 Success 字段的结果对象
    #>

    $result = @{
        Success      = $false
        ErrorMessage = ""
        Data         = @{}
        UpdatedItems = @()
    }

    try {
        Write-UiPrimary "配置 Claude Code 常用设置..." -Level Detail

        $settingsPath = Get-ClaudeSettingsPath
        $settings = @{}
        $updatedItems = [System.Collections.ArrayList]::new()

        if (Test-Path $settingsPath) {
            try {
                $existingContent = Get-Content $settingsPath -Raw
                $settings = $existingContent | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
                if (-not $settings) { $settings = @{} }
                Write-UiInfo "已读取现有配置，将按缺失项补全" -Level Detail
            }
            catch {
                throw "无法解析现有 settings.json，已停止写入以避免覆盖用户配置: $($_.Exception.Message)"
            }
        }

        # 确保 env 节存在
        if (-not $settings.ContainsKey("env")) {
            $settings["env"] = @{}
            [void]$updatedItems.Add("config::env::section-added")
        }

        # 补齐 ClaudeConfig 管辖的 env 键（仅缺失时写入）
        foreach ($entry in $script:ClaudeConfigEnvDefaults.GetEnumerator()) {
            if (-not $settings["env"].ContainsKey($entry.Key)) {
                $settings["env"][$entry.Key] = $entry.Value
                [void]$updatedItems.Add("config::env.$($entry.Key)::added")
            } elseif ([string]::IsNullOrWhiteSpace([string]$settings["env"][$entry.Key])) {
                $settings["env"][$entry.Key] = $entry.Value
                [void]$updatedItems.Add("config::env.$($entry.Key)::filled")
            }
        }

        # 语言与 thinking 设置（仅缺失时填充）
        if (-not $settings.ContainsKey("language") -or [string]::IsNullOrWhiteSpace([string]$settings["language"])) {
            $settings["language"] = "简体中文"
            [void]$updatedItems.Add("config::language::added")
        }
        if (-not $settings.ContainsKey("alwaysThinkingEnabled")) {
            $settings["alwaysThinkingEnabled"] = $true
            [void]$updatedItems.Add("config::alwaysThinkingEnabled::added")
        }
        if (-not $settings.ContainsKey("plansDirectory") -or [string]::IsNullOrWhiteSpace([string]$settings["plansDirectory"])) {
            $settings["plansDirectory"] = ".claude/plan"
            [void]$updatedItems.Add("config::plansDirectory::added")
        }

        # 模型设置：不自动填充，由用户自行选择

        # 权限配置：保留用户已有项，补齐基础权限，保留 deny
        if (-not $settings.ContainsKey("permissions") -or -not $settings["permissions"]) {
            $settings["permissions"] = @{}
            [void]$updatedItems.Add("config::permissions::section-added")
        }
        if (-not $settings["permissions"].ContainsKey("allow") -or -not $settings["permissions"]["allow"]) {
            $settings["permissions"]["allow"] = @()
            [void]$updatedItems.Add("config::permissions.allow::section-added")
        }
        if (-not $settings["permissions"].ContainsKey("deny") -or $null -eq $settings["permissions"]["deny"]) {
            $settings["permissions"]["deny"] = @()
        }

        $allowList = [System.Collections.ArrayList]::new()
        foreach ($perm in @($settings["permissions"]["allow"])) {
            if (-not [string]::IsNullOrWhiteSpace([string]$perm) -and ($allowList -notcontains [string]$perm)) {
                [void]$allowList.Add([string]$perm)
            }
        }
        foreach ($perm in $script:ClaudeConfigBasePermissions) {
            if ($allowList -notcontains $perm) {
                [void]$allowList.Add($perm)
                [void]$updatedItems.Add("config::permissions.allow.$perm::added")
            }
        }
        $settings["permissions"]["allow"] = @($allowList)

        # 归因配置（仅缺失时填充）
        if (-not $settings.ContainsKey("attribution") -or -not $settings["attribution"]) {
            $settings["attribution"] = @{
                "commit" = ""
                "pr"     = ""
            }
            [void]$updatedItems.Add("config::attribution::added")
        }

        # 确保目录存在
        $settingsDir = Split-Path $settingsPath -Parent
        if (-not (Test-Path $settingsDir)) {
            New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
        }

        # 原子写入
        $tempPath = "$settingsPath.tmp"
        $settings | ConvertTo-Json -Depth 10 | Set-Content $tempPath -Encoding UTF8
        Move-Item $tempPath $settingsPath -Force

        Write-UiSuccess "✓ Claude Code 常用配置已写入 ~/.claude/settings.json" -Level Detail
        Write-UiInfo "配置路径: $settingsPath" -Level Detail
        Write-UiInfo "配置摘要:" -Level Detail
        Write-UiInfo "  - 语言: $($settings['language'])" -Level Detail
        Write-UiInfo "  - 默认模型: $($settings['model'])" -Level Detail
        Write-UiInfo "  - 权限项: $($settings['permissions']['allow'].Count) 项" -Level Detail
        Write-UiInfo "  - 环境变量: $($script:ClaudeConfigEnvDefaults.Count) 项" -Level Detail

        if ($updatedItems.Count -eq 0) {
            $result.UpdatedItems = @("noop::ClaudeConfig::no-change")
        } else {
            $result.UpdatedItems = @($updatedItems)
        }
        $result.Data["UpdatedItems"] = @($result.UpdatedItems)
        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = "配置 Claude Code 常用配置失败: $($_.Exception.Message)"
        Write-UiDanger $result.ErrorMessage
    }

    return $result
}

function Verify-ClaudeConfig {
    <#
    .SYNOPSIS
    验证 ClaudeConfig 自有字段（不验证 ApiKey 的 ANTHROPIC_AUTH_TOKEN）
    .RETURNS
    包含 Success 字段的结果对象
    #>

    $result = @{
        Success      = $false
        ErrorMessage = ""
        Data         = @{}
    }

    try {
        $settingsPath = Get-ClaudeSettingsPath
        if (-not (Test-Path $settingsPath)) {
            throw "settings.json 文件不存在"
        }

        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json

        # 验证 language / thinking 顶层配置
        if (-not ($settings.PSObject.Properties.Name -contains "language") -or
            [string]::IsNullOrWhiteSpace([string]$settings.language)) {
            throw "language 配置缺失"
        }
        if (-not ($settings.PSObject.Properties.Name -contains "alwaysThinkingEnabled")) {
            throw "alwaysThinkingEnabled 配置缺失"
        }
        if ($settings.alwaysThinkingEnabled -isnot [bool]) {
            throw "alwaysThinkingEnabled 必须为布尔值，当前值: $($settings.alwaysThinkingEnabled)"
        }
        if (-not ($settings.PSObject.Properties.Name -contains "plansDirectory") -or
            [string]::IsNullOrWhiteSpace([string]$settings.plansDirectory)) {
            throw "plansDirectory 配置缺失"
        }

        # plansDirectory 的精确值对齐由 Update-ClaudeConfig 负责

        # 验证 permissions.allow 存在且包含基础权限
        if (-not $settings.permissions -or
            -not ($settings.permissions.PSObject.Properties.Name -contains "allow") -or
            -not ($settings.permissions.allow -is [System.Array])) {
            throw "permissions.allow 配置缺失"
        }

        $missingPerms = @()
        foreach ($perm in $script:ClaudeConfigBasePermissions) {
            if ($settings.permissions.allow -notcontains $perm) {
                $missingPerms += $perm
            }
        }
        if ($missingPerms.Count -gt 0) {
            throw "permissions.allow 缺少: $($missingPerms -join ', ')"
        }

        # 验证 ClaudeConfig 管辖 env 键已存在
        if (-not $settings.env) {
            throw "env 配置缺失"
        }
        $missingEnvKeys = @()
        foreach ($key in $script:ClaudeConfigEnvDefaults.Keys) {
            if (-not ($settings.env.PSObject.Properties.Name -contains $key) -or
                [string]::IsNullOrWhiteSpace([string]$settings.env.$key)) {
                $missingEnvKeys += $key
            }
        }
        if ($missingEnvKeys.Count -gt 0) {
            throw "env 缺少: $($missingEnvKeys -join ', ')"
        }

        Write-UiSuccess "✓ Claude Code 常用配置验证通过" -Level Detail
        Write-UiInfo "  - language: $($settings.language)" -Level Detail
        Write-UiInfo "  - alwaysThinkingEnabled: $($settings.alwaysThinkingEnabled)" -Level Detail
        Write-UiInfo "  - permissions.allow: $($settings.permissions.allow.Count) 项" -Level Detail
        Write-UiInfo "  - env: $($script:ClaudeConfigEnvDefaults.Count) 项" -Level Detail

        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = "验证 Claude Code 常用配置失败: $($_.Exception.Message)"
        Write-UiDanger $result.ErrorMessage
    }

    return $result
}

function Update-ClaudeConfig {
    <#
    .SYNOPSIS
    声明式对齐 ClaudeConfig 管辖的 env 键到最新默认值
    .DESCRIPTION
    与 Install 的"仅补缺失"策略不同，Update 使用"声明式对齐"：
    - 白名单键：强制覆盖为最新值
    - 废弃键：从 env 中删除
    - 其他键：完全不触碰
    .RETURNS
    @{ Success; ErrorMessage; Data; UpdatedItems }
    #>

    $result = @{
        Success      = $false
        ErrorMessage = ""
        Data         = @{}
        UpdatedItems = @()
    }

    # 禁区键集合
    $forbiddenKeys = @("ANTHROPIC_AUTH_TOKEN")
    $forbiddenPattern = ".*_API_KEY$"

    try {
        $settingsPath = Get-ClaudeSettingsPath
        if (-not (Test-Path $settingsPath)) {
            throw "settings.json 不存在，请先执行安装"
        }

        $settingsRaw = Get-Content $settingsPath -Raw
        $settings = $settingsRaw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        if (-not $settings) { throw "settings.json 无法解析" }

        $updatedItems = [System.Collections.ArrayList]::new()

        # 确保 env 节存在
        if (-not $settings.ContainsKey("env")) {
            $settings["env"] = @{}
        }

        # 声明式对齐：白名单键强制覆盖
        foreach ($entry in $script:ClaudeConfigEnvDefaults.GetEnumerator()) {
            $key = $entry.Key

            # 禁区检查（区分大小写）
            if ($key -cin $forbiddenKeys -or $key -cmatch $forbiddenPattern) {
                continue
            }

            if (-not $settings["env"].ContainsKey($key)) {
                $settings["env"][$key] = $entry.Value
                [void]$updatedItems.Add("config::env.${key}::added")
            } elseif ($settings["env"][$key] -cne $entry.Value) {
                $oldVal = $settings["env"][$key]
                $settings["env"][$key] = $entry.Value
                [void]$updatedItems.Add("config::env.${key}::${oldVal}->$($entry.Value)")
            }
        }

        # 废弃键删除
        foreach ($depKey in $script:ClaudeConfigDeprecatedEnvKeys) {
            if ($depKey -cin $forbiddenKeys -or $depKey -cmatch $forbiddenPattern) {
                continue
            }
            if ($settings["env"].ContainsKey($depKey)) {
                $settings["env"].Remove($depKey)
                [void]$updatedItems.Add("config::env.${depKey}::removed")
            }
        }

        # permissions.allow：仅追加缺失项
        if (-not $settings.ContainsKey("permissions") -or -not $settings["permissions"]) {
            $settings["permissions"] = @{}
        }
        if (-not $settings["permissions"].ContainsKey("allow") -or -not $settings["permissions"]["allow"]) {
            $settings["permissions"]["allow"] = @()
        }

        $allowList = [System.Collections.ArrayList]::new()
        foreach ($perm in @($settings["permissions"]["allow"])) {
            if (-not [string]::IsNullOrWhiteSpace([string]$perm) -and ($allowList -notcontains [string]$perm)) {
                [void]$allowList.Add([string]$perm)
            }
        }
        foreach ($perm in $script:ClaudeConfigBasePermissions) {
            if ($allowList -notcontains $perm) {
                [void]$allowList.Add($perm)
                [void]$updatedItems.Add("config::permissions.allow.${perm}::added")
            }
        }
        $settings["permissions"]["allow"] = @($allowList)

        # language / thinking / plansDirectory / attribution：仅补缺失（model 不自动填充，由用户自行选择）
        if (-not $settings.ContainsKey("language") -or [string]::IsNullOrWhiteSpace([string]$settings["language"])) {
            $settings["language"] = "简体中文"
            [void]$updatedItems.Add("config::language::added")
        }
        if (-not $settings.ContainsKey("alwaysThinkingEnabled")) {
            $settings["alwaysThinkingEnabled"] = $true
            [void]$updatedItems.Add("config::alwaysThinkingEnabled::added")
        }
        if (-not $settings.ContainsKey("plansDirectory") -or
            [string]::IsNullOrWhiteSpace([string]$settings["plansDirectory"])) {
            $settings["plansDirectory"] = ".claude/plan"
            [void]$updatedItems.Add("config::plansDirectory::added")
        } elseif ([string]$settings["plansDirectory"] -ne ".claude/plan") {
            $oldPlansDirectory = [string]$settings["plansDirectory"]
            $settings["plansDirectory"] = ".claude/plan"
            [void]$updatedItems.Add("config::plansDirectory::${oldPlansDirectory}->.claude/plan")
        }
        if (-not $settings.ContainsKey("attribution") -or -not $settings["attribution"]) {
            $settings["attribution"] = @{ "commit" = ""; "pr" = "" }
            [void]$updatedItems.Add("config::attribution::added")
        }

        # 原子写入
        $tempPath = "$settingsPath.tmp_$([guid]::NewGuid().ToString('N').Substring(0,8))"
        $settings | ConvertTo-Json -Depth 10 | Set-Content $tempPath -Encoding UTF8
        for ($retry = 0; $retry -lt 3; $retry++) {
            try {
                Move-Item $tempPath $settingsPath -Force
                break
            } catch {
                if ($retry -eq 2) { throw }
                Start-Sleep -Seconds ([math]::Pow(2, $retry))
            }
        }

        # 结果
        if ($updatedItems.Count -eq 0) {
            $result.UpdatedItems = @("noop::ClaudeConfig::no-change")
            Write-UiDim "ClaudeConfig 已是最新，无需更新" -Level Debug
        } else {
            $result.UpdatedItems = @($updatedItems)
            Write-UiSuccess "✓ ClaudeConfig 已更新 ($($updatedItems.Count) 项变更)" -Level Detail
        }

        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = "更新 ClaudeConfig 失败: $($_.Exception.Message)"
        Write-UiDanger $result.ErrorMessage
    }

    return $result
}

# 辅助函数：获取 Claude Code settings.json 路径（HC-12: ~/.claude/settings.json）
function Get-ClaudeSettingsPath {
    return "$(Get-UserHome)\.claude\settings.json"
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用
