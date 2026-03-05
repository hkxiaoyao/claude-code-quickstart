# 第三方供应商配置步骤 - CCQ
# 功能: 供应商选择（智谱 GLM / MiniMax / Kimi / 自定义）、API Key 输入、settings.json 写入
# 更新: 2026-02-22 - 更新供应商配置，添加 ~/.claude.json 配置

#Requires -Version 5.1

# 严格模式
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 导入依赖模块
. "$PSScriptRoot\..\core\Ui.ps1"
. "$PSScriptRoot\..\core\Profile.ps1"

# API 供应商配置（HC-12：智谱 GLM / MiniMax / Kimi + 自定义）
# 最后更新：2026-02-22，基于最新官方文档
$script:ApiProviders = @{
    "zhipu" = @{
        Name        = "智谱 GLM"
        Description = "智谱 AI，服务端自动路由到最新 GLM 模型"
        BaseUrl     = "https://open.bigmodel.cn/api/anthropic"
        PlatformUrl = "https://bigmodel.cn/usercenter/proj-mgmt/apikeys"
        SettingsKey = "zhipu"
    }
    "minimax" = @{
        Name        = "MiniMax"
        Description = "MiniMax API，支持 M2.5 系列模型"
        BaseUrl     = "https://api.minimaxi.com/anthropic"
        PlatformUrl = "https://platform.minimaxi.com/user-center/basic-information/interface-key"
        SettingsKey = "minimax"
        ModelMapping = @{
            "opus"   = "MiniMax-M2.5"  # 官方推荐：最新 M2.5 系列
            "sonnet" = "MiniMax-M2.5"  # 官方推荐：统一使用 M2.5
            "haiku"  = "MiniMax-M2.5"  # 官方推荐：统一使用 M2.5
        }
    }
    "moonshot" = @{
        Name        = "Kimi (Moonshot)"
        Description = "月之暗面 Kimi，支持 K2.5 系列模型"
        BaseUrl     = "https://api.moonshot.cn/anthropic"
        PlatformUrl = "https://platform.moonshot.cn/console/api-keys"
        SettingsKey = "moonshot"
        ModelMapping = @{
            "opus"   = "kimi-k2.5"  # 官方推荐：最新多模态模型
            "sonnet" = "kimi-k2.5"  # 官方推荐：统一使用 k2.5
            "haiku"  = "kimi-k2.5"  # 官方推荐：统一使用 k2.5
        }
    }
    "custom" = @{
        Name        = "自定义供应商"
        Description = "手动配置 Base URL 和 API Key"
        BaseUrl     = ""  # 用户输入
        PlatformUrl = ""
        SettingsKey = "custom"
    }
}

function Test-ApiKeyInstalled {
    <#
    .SYNOPSIS
    检测 API Key 是否已配置，并识别当前供应商
    .RETURNS
    标准检测结果 hashtable（IsInstalled, Version, Data, Message）
    #>

    $settingsPath = Get-ClaudeSettingsPath
    return Invoke-UnifiedCheck -StepId "ApiKey" -DisplayName "第三方供应商配置" `
        -ConfigFile $settingsPath `
        -RequiredFields @(
            @{ Path = "env.ANTHROPIC_AUTH_TOKEN"; MatchMode = "Exists" }
        ) `
        -CustomVerify {
            # 识别当前供应商
            $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($settings) {
                $providerName = Resolve-CurrentProvider -Settings $settings
                if ($providerName) {
                    Write-UiInfo "  当前供应商: $providerName"
                }
                $envSection = if ($settings.PSObject.Properties.Name -contains "env") { $settings.env } else { $null }
                if ($envSection -and ($envSection.PSObject.Properties.Name -contains "ANTHROPIC_BASE_URL")) {
                    $baseUrl = $envSection.ANTHROPIC_BASE_URL
                    if (-not [string]::IsNullOrWhiteSpace($baseUrl)) {
                        Write-UiInfo "  Base URL: $baseUrl"
                    }
                }
            }
            return $true
        } -UseCache
}

# 辅助函数：从 settings.json 识别当前配置的供应商
function Resolve-CurrentProvider {
    param([Parameter(Mandatory)] $Settings)

    # 策略 1：查找供应商标记字段（兼容历史安装，新安装不再写入此字段）
    foreach ($key in $script:ApiProviders.Keys) {
        $provider = $script:ApiProviders[$key]
        $settingsKey = $provider.SettingsKey
        if ($Settings.PSObject.Properties.Name -contains $settingsKey) {
            $entry = $Settings.$settingsKey
            if ($entry -and $entry.PSObject.Properties.Name -contains "selected" -and $entry.selected -eq $true) {
                return $provider.Name
            }
        }
    }

    # 策略 2：匹配 ANTHROPIC_BASE_URL（兜底，适用于手动编辑的情况）
    $baseUrl = $null
    if ($Settings.PSObject.Properties.Name -contains "env" -and $Settings.env -and
        $Settings.env.PSObject.Properties.Name -contains "ANTHROPIC_BASE_URL") {
        $baseUrl = $Settings.env.ANTHROPIC_BASE_URL
    }
    if (-not [string]::IsNullOrWhiteSpace($baseUrl)) {
        foreach ($key in $script:ApiProviders.Keys) {
            $provider = $script:ApiProviders[$key]
            if ($key -eq "custom") { continue }
            if (-not [string]::IsNullOrWhiteSpace($provider.BaseUrl) -and
                $baseUrl -like "$($provider.BaseUrl)*") {
                return $provider.Name
            }
        }
        # 未匹配到已知供应商，标记为自定义
        return "自定义供应商"
    }

    return $null
}

function Install-ApiKey {
    <#
    .SYNOPSIS
    安装第三方供应商配置（供应商选择 + Key 输入 + 写入 settings.json）
    .RETURNS
    包含 Success 字段的结果对象
    #>

    $result = @{
        Success      = $false
        ErrorMessage = ""
        Data         = @{}
    }

    try {
        # 检测是否已配置（重入支持）
        $existingConfig = Test-ApiKeyInstalled
        if ($existingConfig.IsInstalled) {
            $providerName = if ($existingConfig.Data["Provider"]) { $existingConfig.Data["Provider"] } else { "未知" }
            $baseUrl = if ($existingConfig.Data["BaseUrl"]) { $existingConfig.Data["BaseUrl"] } else { "" }

            Write-Host ""
            Write-UiInfo "当前供应商配置："
            Write-UiInfo "  供应商: $providerName"
            if (-not [string]::IsNullOrWhiteSpace($baseUrl)) {
                Write-UiInfo "  Base URL: $baseUrl"
            }

            $providersDir = Join-Path (Get-UserHome) ".claude\providers"
            if (Test-Path $providersDir) {
                # HC-13: 必须用 @() 包裹，防止 $null.Count 抛异常
                $profiles = @(Get-ChildItem $providersDir -Filter "*.json" -ErrorAction SilentlyContinue)
                if ($profiles.Count -gt 0) {
                    Write-UiInfo "  已保存的供应商 Profile: $($profiles.Count) 个"
                }
            }
            Write-Host ""

            $actionIndex = Show-SingleSelectMenu `
                -Title "供应商已配置，请选择操作：" `
                -Options @(
                    "保持当前配置（跳过）",
                    "重新配置（选择供应商 + 输入 API Key）"
                )

            if ($actionIndex -ne 1) {
                Write-UiSuccess "保持当前供应商配置"

                # 检查并补生成 profile（迁移旧用户）
                $providersDir = Join-Path (Get-UserHome) ".claude\providers"
                $hasProfiles = (Test-Path $providersDir) -and
                    @(Get-ChildItem $providersDir -Filter "*.json" -ErrorAction SilentlyContinue).Count -gt 0
                if (-not $hasProfiles) {
                    try {
                        $settingsPath = Get-ClaudeSettingsPath
                        if (Test-Path $settingsPath) {
                            $curSettings = Get-Content $settingsPath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
                            if ($curSettings -and $curSettings.ContainsKey("env") -and $curSettings["env"]["ANTHROPIC_AUTH_TOKEN"]) {
                                if (-not (Test-Path $providersDir)) {
                                    New-Item -ItemType Directory -Path $providersDir -Force | Out-Null
                                }
                                $curBaseUrl = if ($curSettings["env"]["ANTHROPIC_BASE_URL"]) { $curSettings["env"]["ANTHROPIC_BASE_URL"] } else { "" }

                                # 识别供应商 key
                                $migrateKey = "custom"
                                foreach ($k in $script:ApiProviders.Keys) {
                                    if ($k -eq "custom") { continue }
                                    $p = $script:ApiProviders[$k]
                                    if (-not [string]::IsNullOrWhiteSpace($p.BaseUrl) -and $curBaseUrl -like "$($p.BaseUrl)*") {
                                        $migrateKey = $k
                                        break
                                    }
                                }

                                $migrateProfile = @{
                                    "_meta" = @{
                                        "provider"     = $providerName
                                        "key"          = $migrateKey
                                        "baseUrl"      = $curBaseUrl
                                        "configuredAt" = (Get-Date -Format "o")
                                    }
                                    "env" = @{
                                        "ANTHROPIC_AUTH_TOKEN" = $curSettings["env"]["ANTHROPIC_AUTH_TOKEN"]
                                        "ANTHROPIC_BASE_URL"  = $curBaseUrl
                                    }
                                }
                                if ($curSettings.ContainsKey("modelMapping") -and $curSettings["modelMapping"]) {
                                    $migrateProfile["modelMapping"] = $curSettings["modelMapping"]
                                }

                                $migrateProfileKey = if ($migrateKey -eq "custom" -and -not [string]::IsNullOrWhiteSpace($curBaseUrl)) {
                                    try {
                                        $uri = [System.Uri]$curBaseUrl
                                        "custom-$($uri.Host -replace '\.', '-')"
                                    } catch { "custom" }
                                } else { $migrateKey }

                                $migratePath = Join-Path $providersDir "$migrateProfileKey.json"
                                $migrateTmp = "$migratePath.tmp"
                                $migrateProfile | ConvertTo-Json -Depth 10 | Set-Content $migrateTmp -Encoding UTF8
                                Move-Item $migrateTmp $migratePath -Force
                                Write-UiInfo "已从当前配置自动生成供应商 Profile: $migrateProfileKey.json"
                            }
                        }
                    } catch {
                        # 静默失败，不影响主流程
                    }
                }

                # 确保 ccp 注入（迁移旧用户也能获得切换命令）
                Invoke-ProviderSwitcherInjection

                $result.Success = $true
                $result.Data["Skipped"] = $true
                $result.Data["Provider"] = $providerName
                return $result
            }

            Write-UiInfo "进入供应商配置..."
            Write-Host ""
        }

        Write-UiInfo "配置第三方 AI 供应商..."

        # 构建菜单选项（Show-SingleSelectMenu 接受 [string[]]，返回索引）
        $providerLabels = @(
            "智谱 GLM       - 智谱 AI，服务端自动路由最新 GLM 模型"
            "MiniMax        - MiniMax API，支持 M2.5 系列"
            "Kimi (Moonshot) - 月之暗面 Kimi，支持 K2.5 系列"
            "自定义供应商    - 手动配置 Base URL 和 API Key"
        )
        $providerKeys = @("zhipu", "minimax", "moonshot", "custom")

        # 菜单重试机制（最多 3 次）
        $selectedIndex = -1
        $maxMenuAttempts = 3
        for ($attempt = 1; $attempt -le $maxMenuAttempts; $attempt++) {
            Write-UiInfo "请选择 API 供应商（仅供 Claude Code 中转使用）:"
            $selectedIndex = Show-SingleSelectMenu -Options $providerLabels -Title "API 供应商选择"

            if ($selectedIndex -ge 0) {
                break
            }

            if ($attempt -lt $maxMenuAttempts) {
                Write-UiWarn "未检测到有效选择，请重试 ($attempt/$maxMenuAttempts)"
            }
        }

        if ($selectedIndex -lt 0 -or $selectedIndex -ge $providerKeys.Count) {
            throw "未选择 API 供应商（已重试 $maxMenuAttempts 次）"
        }

        $selectedKey = $providerKeys[$selectedIndex]
        $provider = $script:ApiProviders[$selectedKey]
        Write-UiSuccess "已选择: $($provider.Name)"

        # 处理自定义供应商的名称和 Base URL 输入
        if ($selectedKey -eq "custom") {
            Write-UiInfo "请输入供应商名称（可选，直接回车跳过）:"
            $customName = (Read-Host -Prompt "供应商名称").Trim()

            if (-not [string]::IsNullOrWhiteSpace($customName)) {
                $provider.Name = $customName
                Write-UiSuccess "供应商名称已设置: $customName"
            }

            Write-UiInfo "请输入自定义 API Base URL（例如: https://api.example.com）:"
            do {
                $customBaseUrl = Read-Host -Prompt "Base URL"
                if ([string]::IsNullOrWhiteSpace($customBaseUrl)) {
                    Write-UiError "Base URL 不能为空，请重新输入"
                    continue
                }
                if ($customBaseUrl -notmatch '^https?://') {
                    Write-UiError "Base URL 必须以 http:// 或 https:// 开头，请重新输入"
                    continue
                }
                break
            } while ($true)

            $provider.BaseUrl = $customBaseUrl.TrimEnd('/')
            Write-UiSuccess "Base URL 已设置: $($provider.BaseUrl)"
        } else {
            Write-UiInfo "请前往以下平台获取 API Key: $($provider.PlatformUrl)"
        }

        # 安全输入 API Key
        Write-UiInfo "请粘贴 $($provider.Name) 的 API Key（输入不会回显）:"
        Write-UiWarn "注意: API Key 将仅写入 ~/.claude/settings.json，不写入环境变量"

        do {
            $apiKeySecure = Read-Host -Prompt "API Key" -AsSecureString
            $apiKeyPlain  = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($apiKeySecure)
            )

            if ([string]::IsNullOrWhiteSpace($apiKeyPlain)) {
                Write-UiError "API Key 不能为空，请重新输入"
                continue
            }
            if ($apiKeyPlain.Length -lt 10) {
                Write-UiError "API Key 长度过短，请检查后重新输入"
                continue
            }
            break
        } while ($true)

        # 显示配置摘要并确认
        Write-Host ""
        Write-UiWarn "即将写入以下配置："
        Write-UiInfo "  供应商: $($provider.Name)"
        Write-UiInfo "  Base URL: $($provider.BaseUrl)"
        Write-UiInfo "  配置文件: ~/.claude/settings.json"
        Write-Host ""

        $confirmIndex = Show-SingleSelectMenu `
            -Title "确认写入配置？" `
            -Options @("是，写入", "否，取消")

        if ($confirmIndex -ne 0) {
            throw "用户取消配置"
        }

        # 读取现有 settings.json
        $settingsPath = Get-ClaudeSettingsPath
        $settings = @{}

        if (Test-Path $settingsPath) {
            try {
                $existingContent = Get-Content $settingsPath -Raw
                $settings = $existingContent | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
                if (-not $settings) { $settings = @{} }
                Write-UiInfo "已读取现有配置，将合并写入"
            }
            catch {
                Write-UiWarn "无法解析现有 settings.json，将创建新配置"
                $settings = @{}
            }
        }

        # HC-12: 写入 env.ANTHROPIC_AUTH_TOKEN + ANTHROPIC_BASE_URL
        if (-not $settings.ContainsKey("env")) {
            $settings["env"] = @{}
        }
        $settings["env"]["ANTHROPIC_AUTH_TOKEN"] = $apiKeyPlain
        $settings["env"]["ANTHROPIC_BASE_URL"]   = $provider.BaseUrl

        # 写入模型映射配置（仅当供应商定义了 ModelMapping 时）
        if ($provider.ContainsKey("ModelMapping") -and $provider.ModelMapping) {
            $settings["modelMapping"] = $provider.ModelMapping
            Write-UiInfo "已写入模型映射配置:"
            Write-UiInfo "  - opus   → $($provider.ModelMapping['opus'])"
            Write-UiInfo "  - sonnet → $($provider.ModelMapping['sonnet'])"
            Write-UiInfo "  - haiku  → $($provider.ModelMapping['haiku'])"
        } elseif ($settings.ContainsKey("modelMapping")) {
            # 切换到无映射的供应商时，清理旧配置（避免残留）
            $settings.Remove("modelMapping")
            Write-UiInfo "已清理旧模型映射配置（当前供应商由服务端自动路由）"
        }

        # 确保目录存在
        $settingsDir = Split-Path $settingsPath -Parent
        if (-not (Test-Path $settingsDir)) {
            New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
        }

        # 原子写入（临时文件 + Move-Item）
        $tempPath = "$settingsPath.tmp"
        $settings | ConvertTo-Json -Depth 10 | Set-Content $tempPath -Encoding UTF8
        Move-Item $tempPath $settingsPath -Force

        Write-UiSuccess "✓ 供应商配置已安全写入 ~/.claude/settings.json（env.ANTHROPIC_AUTH_TOKEN）"
        Write-UiInfo "配置路径: $settingsPath"

        # 显示脱敏信息（前 8 位 + 后 4 位）
        if ($apiKeyPlain.Length -gt 12) {
            $masked = $apiKeyPlain.Substring(0, 8) + "..." + $apiKeyPlain.Substring($apiKeyPlain.Length - 4)
        } else {
            $masked = "***"
        }
        Write-UiInfo "Key 摘要: $masked（已脱敏）"

        # 保存供应商 Profile 文件
        try {
            $providersDir = Join-Path (Get-UserHome) ".claude\providers"
            if (-not (Test-Path $providersDir)) {
                New-Item -ItemType Directory -Path $providersDir -Force | Out-Null
            }

            $profileKey = $selectedKey
            if ($selectedKey -eq "custom") {
                if (-not [string]::IsNullOrWhiteSpace($customName)) {
                    # 使用供应商名称作为文件名（替换文件系统非法字符）
                    $profileKey = "custom-$($customName -replace '[\\/:*?\"<>|\s]', '-')"
                } else {
                    # 未输入名称，自动编号 custom-1, custom-2, ...
                    $num = 1
                    while (Test-Path (Join-Path $providersDir "custom-$num.json")) {
                        $num++
                    }
                    $profileKey = "custom-$num"
                }
            }

            $providerProfile = @{
                "_meta" = @{
                    "provider"     = $provider.Name
                    "key"          = $selectedKey
                    "baseUrl"      = $provider.BaseUrl
                    "configuredAt" = (Get-Date -Format "o")
                }
                "env" = @{
                    "ANTHROPIC_AUTH_TOKEN" = $apiKeyPlain
                    "ANTHROPIC_BASE_URL"  = $provider.BaseUrl
                }
            }

            if ($provider.ContainsKey("ModelMapping") -and $provider.ModelMapping) {
                $providerProfile["modelMapping"] = $provider.ModelMapping
            }

            $profilePath = Join-Path $providersDir "$profileKey.json"
            $profileTempPath = "$profilePath.tmp"
            $providerProfile | ConvertTo-Json -Depth 10 | Set-Content $profileTempPath -Encoding UTF8
            Move-Item $profileTempPath $profilePath -Force

            Write-UiSuccess "✓ 供应商 Profile 已保存: ~/.claude/providers/$profileKey.json"
            Write-UiInfo "提示: 重新打开终端后，使用 ccp 命令可快速切换供应商"
        } catch {
            Write-UiWarn "保存供应商 Profile 失败: $($_.Exception.Message)"
            Write-UiWarn "此错误不影响当前配置，供应商切换功能可能受限"
        }

        # 创建/更新 ~/.claude.json 配置（添加 hasCompletedOnboarding）
        try {
            $claudeJsonPath = "$(Get-UserHome)\.claude.json"
            $claudeJsonConfig = @{}

            # 如果文件已存在，读取并合并
            if (Test-Path $claudeJsonPath) {
                try {
                    $existingJsonContent = Get-Content $claudeJsonPath -Raw
                    $claudeJsonConfig = $existingJsonContent | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
                    if (-not $claudeJsonConfig) { $claudeJsonConfig = @{} }
                    Write-UiInfo "已读取现有 ~/.claude.json，将合并写入"
                }
                catch {
                    Write-UiWarn "无法解析现有 ~/.claude.json，将创建新配置"
                    $claudeJsonConfig = @{}
                }
            }

            # 添加 hasCompletedOnboarding 配置
            $claudeJsonConfig["hasCompletedOnboarding"] = $true

            # 原子写入
            $tempJsonPath = "$claudeJsonPath.tmp"
            $claudeJsonConfig | ConvertTo-Json -Depth 10 | Set-Content $tempJsonPath -Encoding UTF8
            Move-Item $tempJsonPath $claudeJsonPath -Force

            Write-UiSuccess "✓ ~/.claude.json 配置已更新（hasCompletedOnboarding: true）"
            Write-UiInfo "配置路径: $claudeJsonPath"
        }
        catch {
            Write-UiWarn "更新 ~/.claude.json 失败: $($_.Exception.Message)"
            Write-UiWarn "此错误不影响安装流程"
        }

        $result.Data["Provider"]   = $selectedKey
        $result.Data["BaseUrl"]    = $provider.BaseUrl
        $result.Success            = $true

        # 注入 Switch-ClaudeProvider 函数到 $PROFILE
        Invoke-ProviderSwitcherInjection

        # 立即清除敏感变量
        $apiKeyPlain  = $null
        $apiKeySecure = $null
    }
    catch {
        $result.ErrorMessage = "配置供应商失败: $($_.Exception.Message)"
        Write-UiError $result.ErrorMessage
    }
    finally {
        # 确保清除敏感变量
        $apiKeyPlain  = $null
    }

    return $result
}

function Verify-ApiKey {
    <#
    .SYNOPSIS
    验证第三方供应商配置
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

        $hasEnv = $settings.PSObject.Properties.Name -contains "env" -and $settings.env

        # 验证 env.ANTHROPIC_AUTH_TOKEN 已写入
        if (-not $hasEnv -or
            -not ($settings.env.PSObject.Properties.Name -contains "ANTHROPIC_AUTH_TOKEN") -or
            [string]::IsNullOrWhiteSpace($settings.env.ANTHROPIC_AUTH_TOKEN)) {
            throw "env.ANTHROPIC_AUTH_TOKEN 未配置或为空"
        }

        # 验证 env.ANTHROPIC_BASE_URL 已写入
        if (-not $hasEnv -or
            -not ($settings.env.PSObject.Properties.Name -contains "ANTHROPIC_BASE_URL") -or
            [string]::IsNullOrWhiteSpace($settings.env.ANTHROPIC_BASE_URL)) {
            throw "env.ANTHROPIC_BASE_URL 未配置或为空"
        }

        # 验证模型映射配置（可选，部分供应商服务端自动路由）
        if ($settings.PSObject.Properties.Name -contains "modelMapping" -and $settings.modelMapping) {
            $requiredModels = @("opus", "sonnet", "haiku")
            $missingModels = @()
            foreach ($model in $requiredModels) {
                if (-not $settings.modelMapping.$model) {
                    $missingModels += $model
                }
            }
            if ($missingModels.Count -gt 0) {
                Write-UiWarn "⚠ 模型映射不完整，缺少: $($missingModels -join ', ')"
            } else {
                Write-UiSuccess "✓ 模型映射配置完整"
            }
        }

        # 验证环境变量未被污染（HC-12 合规检查）
        $sensitiveEnvVars = @("ANTHROPIC_API_KEY", "OPENAI_API_KEY", "ZHIPU_API_KEY", "MINIMAX_API_KEY", "MOONSHOT_API_KEY")
        foreach ($envVar in $sensitiveEnvVars) {
            $envValue = [Environment]::GetEnvironmentVariable($envVar, "User")
            if (-not [string]::IsNullOrWhiteSpace($envValue)) {
                Write-UiWarn "⚠ 检测到用户级环境变量 $envVar，建议清理（API Key 应仅存于 settings.json）"
            }
        }

        Write-UiSuccess "✓ 供应商配置验证通过（env.ANTHROPIC_AUTH_TOKEN）"
        Write-UiSuccess "✓ Base URL 配置验证通过（env.ANTHROPIC_BASE_URL）"
        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = "验证供应商配置失败: $($_.Exception.Message)"
        Write-UiError $result.ErrorMessage
    }

    return $result
}

# 辅助函数：注入 Switch-ClaudeProvider 到 $PROFILE（keep/reconfigure 共用）
function Invoke-ProviderSwitcherInjection {
    try {
        $ccpFunction = @(
            '# Claude Code Provider Switcher (CCQ)'
            'function Switch-ClaudeProvider {'
            '    param([string]$Provider)'
            '    $homeDir = $env:USERPROFILE'
            '    try { if (Test-Path $homeDir) { $homeDir = (Get-Item $homeDir).FullName } } catch {}'
            '    $providersDir = Join-Path $homeDir ".claude\providers"'
            ''
            '    if (-not $Provider) {'
            '        # HC-13: 必须用 @() 包裹，防止 $null.Count 抛异常'
            '        $profiles = @(Get-ChildItem $providersDir -Filter "*.json" -ErrorAction SilentlyContinue)'
            '        if ($profiles.Count -eq 0) {'
            '            Write-Host "未找到供应商 Profile，请先运行安装器配置供应商" -ForegroundColor Yellow'
            '            return'
            '        }'
            '        Write-Host "可用的供应商 Profile:" -ForegroundColor Cyan'
            '        for ($i = 0; $i -lt $profiles.Count; $i++) {'
            '            try {'
            '                $p = Get-Content $profiles[$i].FullName -Raw | ConvertFrom-Json'
            '                $name = if ($p._meta.provider) { $p._meta.provider } else { $profiles[$i].BaseName }'
            '            } catch {'
            '                $name = $profiles[$i].BaseName'
            '            }'
            '            Write-Host "  [$i] $name ($($profiles[$i].BaseName))" -ForegroundColor White'
            '        }'
            '        $sel = Read-Host "选择编号"'
            '        if ($sel -match ''^\d+$'' -and [int]$sel -lt $profiles.Count) {'
            '            $Provider = $profiles[[int]$sel].BaseName'
            '        } else { return }'
            '    }'
            ''
            '    # 防御路径遍历'
            '    if ($Provider -notmatch ''^[\w._-]+$'') {'
            '        Write-Host "无效的供应商名称: $Provider" -ForegroundColor Red'
            '        return'
            '    }'
            ''
            '    $profilePath = Join-Path $providersDir "$Provider.json"'
            '    if (-not (Test-Path $profilePath)) {'
            '        Write-Host "供应商 Profile 不存在: $profilePath" -ForegroundColor Red'
            '        return'
            '    }'
            ''
            '    try {'
            '        $profile = Get-Content $profilePath -Raw | ConvertFrom-Json -AsHashtable'
            '    } catch {'
            '        Write-Host "供应商 Profile 解析失败: $($_.Exception.Message)" -ForegroundColor Red'
            '        return'
            '    }'
            ''
            '    # 校验 Profile 必要字段'
            '    if (-not $profile -or -not $profile.ContainsKey("env") -or'
            '        -not $profile["env"]["ANTHROPIC_AUTH_TOKEN"] -or -not $profile["env"]["ANTHROPIC_BASE_URL"]) {'
            '        Write-Host "供应商 Profile 格式无效（缺少 env.ANTHROPIC_AUTH_TOKEN 或 ANTHROPIC_BASE_URL）" -ForegroundColor Red'
            '        return'
            '    }'
            ''
            '    $settingsPath = Join-Path $homeDir ".claude\settings.json"'
            '    $settings = @{}'
            '    if (Test-Path $settingsPath) {'
            '        try {'
            '            $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json -AsHashtable'
            '            if (-not $settings) { $settings = @{} }'
            '        } catch { $settings = @{} }'
            '    }'
            ''
            '    if (-not $settings.ContainsKey("env")) { $settings["env"] = @{} }'
            '    $settings["env"]["ANTHROPIC_AUTH_TOKEN"] = $profile["env"]["ANTHROPIC_AUTH_TOKEN"]'
            '    $settings["env"]["ANTHROPIC_BASE_URL"]  = $profile["env"]["ANTHROPIC_BASE_URL"]'
            ''
            '    if ($profile.ContainsKey("modelMapping") -and $profile["modelMapping"]) {'
            '        $settings["modelMapping"] = $profile["modelMapping"]'
            '    } elseif ($settings.ContainsKey("modelMapping")) {'
            '        $settings.Remove("modelMapping")'
            '    }'
            ''
            '    $tempPath = "$settingsPath.tmp"'
            '    $settings | ConvertTo-Json -Depth 10 | Set-Content $tempPath -Encoding UTF8'
            '    Move-Item $tempPath $settingsPath -Force'
            ''
            '    $providerName = if ($profile["_meta"]["provider"]) { $profile["_meta"]["provider"] } else { $Provider }'
            '    Write-Host "已切换到: $providerName" -ForegroundColor Green'
            '}'
            'Set-Alias ccp Switch-ClaudeProvider'
        )

        $profileSuccess = Set-ManagedBlockInFile `
            -FilePath $PROFILE `
            -Content $ccpFunction `
            -StartMarker "# >>> Claude Code Provider Switcher >>>" `
            -EndMarker "# <<< Claude Code Provider Switcher <<<" `
            -CreateIfNotExists -AppendIfNoBlock

        if ($profileSuccess) {
            Write-UiSuccess "✓ 供应商切换函数已注入 PowerShell Profile（ccp 命令）"
        } else {
            Write-UiWarn "供应商切换函数注入失败，ccp 命令可能不可用"
        }
    } catch {
        Write-UiWarn "注入供应商切换函数失败: $($_.Exception.Message)"
        Write-UiWarn "此错误不影响当前配置"
    }
}

# 辅助函数：获取 Claude Code settings.json 路径（HC-12: ~/.claude/settings.json）
function Get-ClaudeSettingsPath {
    return "$(Get-UserHome)\.claude\settings.json"
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用
