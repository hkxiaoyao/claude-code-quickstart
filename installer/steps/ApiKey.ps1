# API Key 配置步骤 - CCQ
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
    包含 IsInstalled 字段的结果对象
    #>

    $result = @{
        IsInstalled = $false
        Version     = ""
        Data        = @{}
        Message     = ""
    }

    try {
        $settingsPath = Get-ClaudeSettingsPath
        if (-not (Test-Path $settingsPath)) {
            $result.Message = "settings.json 不存在"
            return $result
        }

        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if (-not $settings) {
            $result.Message = "settings.json 无法解析"
            return $result
        }

        # HC-12: API Key 存于 env.ANTHROPIC_AUTH_TOKEN
        $envSection = if ($settings.PSObject.Properties.Name -contains "env") { $settings.env } else { $null }
        $hasAuthToken = $envSection -and
            $envSection.PSObject.Properties.Name -contains "ANTHROPIC_AUTH_TOKEN" -and
            -not [string]::IsNullOrWhiteSpace($envSection.ANTHROPIC_AUTH_TOKEN)

        if ($hasAuthToken) {
            # 识别当前供应商
            $providerName = Resolve-CurrentProvider -Settings $settings
            $baseUrl = if ($envSection.PSObject.Properties.Name -contains "ANTHROPIC_BASE_URL") {
                $envSection.ANTHROPIC_BASE_URL
            } else { "" }

            Write-UiSuccess "✓ API Key 已配置（env.ANTHROPIC_AUTH_TOKEN）"
            if ($providerName) {
                Write-UiInfo "  当前供应商: $providerName"
            }
            if (-not [string]::IsNullOrWhiteSpace($baseUrl)) {
                Write-UiInfo "  Base URL: $baseUrl"
            }

            $result.IsInstalled = $true
            $result.Message = "API Key 已配置"
            $result.Data["Provider"] = $providerName
            $result.Data["BaseUrl"]  = $baseUrl
        } else {
            $result.Message = "env.ANTHROPIC_AUTH_TOKEN 未配置"
        }
    }
    catch {
        $result.Message = "检测 API Key 时出错: $($_.Exception.Message)"
        Write-UiError $result.Message
    }

    return $result
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
    安装 API Key 配置（供应商选择 + Key 输入 + 写入 settings.json）
    .RETURNS
    包含 Success 字段的结果对象
    #>

    $result = @{
        Success      = $false
        ErrorMessage = ""
        Data         = @{}
    }

    try {
        Write-UiInfo "配置 API Provider 和 API Key..."

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

        # 处理自定义供应商的 Base URL 输入
        if ($selectedKey -eq "custom") {
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

        Write-UiSuccess "✓ API Key 已安全写入 ~/.claude/settings.json（env.ANTHROPIC_AUTH_TOKEN）"
        Write-UiInfo "配置路径: $settingsPath"

        # 显示脱敏信息（前 8 位 + 后 4 位）
        if ($apiKeyPlain.Length -gt 12) {
            $masked = $apiKeyPlain.Substring(0, 8) + "..." + $apiKeyPlain.Substring($apiKeyPlain.Length - 4)
        } else {
            $masked = "***"
        }
        Write-UiInfo "Key 摘要: $masked（已脱敏）"

        # 创建/更新 ~/.claude.json 配置（添加 hasCompletedOnboarding）
        try {
            $claudeJsonPath = "$env:USERPROFILE\.claude.json"
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

        # 立即清除敏感变量
        $apiKeyPlain  = $null
        $apiKeySecure = $null
    }
    catch {
        $result.ErrorMessage = "配置 API Key 失败: $($_.Exception.Message)"
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
    验证 API Key 配置
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

        Write-UiSuccess "✓ API Key 配置验证通过（env.ANTHROPIC_AUTH_TOKEN）"
        Write-UiSuccess "✓ Base URL 配置验证通过（env.ANTHROPIC_BASE_URL）"
        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = "验证 API Key 配置失败: $($_.Exception.Message)"
        Write-UiError $result.ErrorMessage
    }

    return $result
}

# 辅助函数：获取 Claude Code settings.json 路径（HC-12: ~/.claude/settings.json）
function Get-ClaudeSettingsPath {
    return "$env:USERPROFILE\.claude\settings.json"
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用
