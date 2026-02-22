# API Key 配置步骤 - Claude Code 环境安装器
# 功能: 供应商选择（智谱 GLM / MiniMax / Kimi）、API Key 输入和 settings.json 写入

#Requires -Version 5.1

# 严格模式
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 导入依赖模块
. "$PSScriptRoot\..\core\Ui.ps1"
. "$PSScriptRoot\..\core\Profile.ps1"

# API 供应商配置（HC-12：智谱 GLM / MiniMax / Kimi 三选一）
$script:ApiProviders = @{
    "zhipu" = @{
        Name        = "智谱 GLM"
        Description = "智谱 AI，支持 GLM-4 系列模型"
        BaseUrl     = "https://open.bigmodel.cn/api/paas/v4/"
        PlatformUrl = "https://open.bigmodel.cn"
        SettingsKey = "zhipu"
    }
    "minimax" = @{
        Name        = "MiniMax"
        Description = "MiniMax API，支持 abab6.5 等系列模型"
        BaseUrl     = "https://api.minimax.chat/v1/"
        PlatformUrl = "https://platform.minimaxi.com"
        SettingsKey = "minimax"
    }
    "moonshot" = @{
        Name        = "Kimi (Moonshot)"
        Description = "月之暗面 Kimi，支持 moonshot-v1 系列模型"
        BaseUrl     = "https://api.moonshot.cn/v1/"
        PlatformUrl = "https://platform.moonshot.cn"
        SettingsKey = "moonshot"
    }
}

function Test-Step06Installed {
    <#
    .SYNOPSIS
    检测 API Key 是否已配置
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
        $envSection = $settings.env
        $hasAuthToken = $envSection -and
            $envSection.PSObject.Properties.Name -contains "ANTHROPIC_AUTH_TOKEN" -and
            -not [string]::IsNullOrWhiteSpace($envSection.ANTHROPIC_AUTH_TOKEN)

        if ($hasAuthToken) {
            Write-UiSuccess "✓ API Key 已配置（env.ANTHROPIC_AUTH_TOKEN）"
            $result.IsInstalled = $true
            $result.Message = "API Key 已配置"
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

function Install-Step06 {
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

        # 构建菜单选项
        $providerOptions = @(
            @{ Label = "智谱 GLM";        Description = "智谱 AI，支持 GLM-4 系列模型";              Value = "zhipu" }
            @{ Label = "MiniMax";          Description = "MiniMax API，支持 abab6.5 系列模型";        Value = "minimax" }
            @{ Label = "Kimi (Moonshot)";  Description = "月之暗面 Kimi，支持 moonshot-v1 系列模型"; Value = "moonshot" }
        )

        Write-UiInfo "请选择 API 供应商（仅供 Claude Code 中转使用）:"
        $selectedKey = Show-SingleSelectMenu -Options $providerOptions -Title "API 供应商选择"

        if (-not $selectedKey) {
            throw "未选择 API 供应商"
        }

        $provider = $script:ApiProviders[$selectedKey]
        Write-UiSuccess "已选择: $($provider.Name)"
        Write-UiInfo "请前往以下平台获取 API Key: $($provider.PlatformUrl)"

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

        # 同时记录所选供应商（用于后续步骤判断）
        $settings[$provider.SettingsKey] = @{ selected = $true }

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

function Verify-Step06 {
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

        # 验证 env.ANTHROPIC_AUTH_TOKEN 已写入
        if (-not $settings.env -or [string]::IsNullOrWhiteSpace($settings.env.ANTHROPIC_AUTH_TOKEN)) {
            throw "env.ANTHROPIC_AUTH_TOKEN 未配置或为空"
        }

        # 验证 env.ANTHROPIC_BASE_URL 已写入
        if (-not $settings.env -or [string]::IsNullOrWhiteSpace($settings.env.ANTHROPIC_BASE_URL)) {
            throw "env.ANTHROPIC_BASE_URL 未配置或为空"
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
