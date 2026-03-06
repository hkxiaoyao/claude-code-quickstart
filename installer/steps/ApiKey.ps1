# 第三方供应商配置步骤 - CCQ
# 功能: 供应商选择 → Provider.ps1 委托 + ~/.claude.json 配置 + ccp 旧标记块清理
# 重构: 2026-03-06 - 委托 Provider.ps1 的 Add-Provider 处理供应商 CRUD

#Requires -Version 7.0

# 严格模式
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 导入依赖模块
. "$PSScriptRoot\..\core\Ui.ps1"
. "$PSScriptRoot\..\core\Profile.ps1"
. "$PSScriptRoot\..\core\Provider.ps1"

function Test-ApiKeyInstalled {
    <#
    .SYNOPSIS
    检测 API Key 是否已配置，并识别当前供应商
    .RETURNS
    标准检测结果 hashtable（IsInstalled, Version, Data, Message）
    #>

    $settingsPath = Get-ProviderSettingsPath
    return Invoke-UnifiedCheck -StepId "ApiKey" -DisplayName "第三方供应商配置" `
        -ConfigFile $settingsPath `
        -RequiredFields @(
            @{ Path = "env.ANTHROPIC_AUTH_TOKEN"; MatchMode = "Exists" }
            @{ Path = "env.ANTHROPIC_BASE_URL"; MatchMode = "Exists" }
        ) `
        -CustomVerify {
            # 通过 Provider.ps1 识别当前活跃供应商
            $active = Get-ActiveProvider
            if ($active) {
                Write-UiInfo "  当前供应商: $($active.Name)"
                if (-not [string]::IsNullOrWhiteSpace($active.BaseUrl)) {
                    Write-UiInfo "  Base URL: $($active.BaseUrl)"
                }
            }
            return $true
        } -UseCache
}

function Install-ApiKey {
    <#
    .SYNOPSIS
    安装第三方供应商配置（委托 Provider.ps1 的 Add-Provider）
    .RETURNS
    包含 Success 字段的结果对象
    #>

    $result = @{
        Success      = $false
        ErrorMessage = ""
        Data         = @{}
    }

    try {
        Write-UiInfo "配置第三方 AI 供应商..."

        # 委托 Provider.ps1 的共用添加函数（安装模式: 强制激活）
        $addResult = Add-Provider -Activate

        if (-not $addResult.Success) {
            throw "供应商配置失败"
        }

        $result.Data["Provider"] = $addResult.Name
        $result.Data["BaseUrl"]  = $addResult.BaseUrl

        # 创建/更新 ~/.claude.json（hasCompletedOnboarding）
        try {
            $claudeJsonPath = "$(Get-UserHome)\.claude.json"
            $claudeJsonConfig = @{}

            if (Test-Path $claudeJsonPath) {
                try {
                    $existingJsonContent = Get-Content $claudeJsonPath -Raw
                    $claudeJsonConfig = $existingJsonContent | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
                    if (-not $claudeJsonConfig) { $claudeJsonConfig = @{} }
                } catch {
                    $claudeJsonConfig = @{}
                }
            }

            $claudeJsonConfig["hasCompletedOnboarding"] = $true

            $tempJsonPath = "$claudeJsonPath.tmp"
            $claudeJsonConfig | ConvertTo-Json -Depth 10 | Set-Content $tempJsonPath -Encoding UTF8
            Move-Item $tempJsonPath $claudeJsonPath -Force

            Write-UiSuccess "~/.claude.json 配置已更新（hasCompletedOnboarding: true）"
        } catch {
            Write-UiWarn "更新 ~/.claude.json 失败: $($_.Exception.Message)"
        }

        # 一次性清理旧版 ccp 注入（迁移旧用户）
        try {
            $null = Remove-ManagedBlockFromFile -FilePath $PROFILE `
                -StartMarker "# >>> Claude Code Provider Switcher >>>" `
                -EndMarker "# <<< Claude Code Provider Switcher <<<"
            Write-UiInfo "已清理旧版 ccp 命令（供应商管理已迁移到 Manage 脚本）"
        } catch {
            # 静默失败：可能标记块不存在或 $PROFILE 不存在
        }

        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = "配置供应商失败: $($_.Exception.Message)"
        Write-UiError $result.ErrorMessage
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
        $settingsPath = Get-ProviderSettingsPath
        if (-not (Test-Path $settingsPath)) {
            throw "settings.json 文件不存在"
        }

        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json -AsHashtable

        $hasEnv = $settings.ContainsKey("env") -and $settings["env"]

        if (-not $hasEnv -or
            -not ($settings["env"].ContainsKey("ANTHROPIC_AUTH_TOKEN")) -or
            [string]::IsNullOrWhiteSpace($settings["env"]["ANTHROPIC_AUTH_TOKEN"])) {
            throw "env.ANTHROPIC_AUTH_TOKEN 未配置或为空"
        }

        if (-not $hasEnv -or
            -not ($settings["env"].ContainsKey("ANTHROPIC_BASE_URL")) -or
            [string]::IsNullOrWhiteSpace($settings["env"]["ANTHROPIC_BASE_URL"])) {
            throw "env.ANTHROPIC_BASE_URL 未配置或为空"
        }

        # 验证模型映射配置（可选）
        if ($settings.ContainsKey("modelMapping") -and $settings["modelMapping"]) {
            $requiredModels = @("opus", "sonnet", "haiku")
            $missingModels = @()
            foreach ($model in $requiredModels) {
                if (-not $settings["modelMapping"].ContainsKey($model) -or -not $settings["modelMapping"][$model]) {
                    $missingModels += $model
                }
            }
            if ($missingModels.Count -gt 0) {
                Write-UiWarn "模型映射不完整，缺少: $($missingModels -join ', ')"
            }
        }

        # HC-12 合规检查
        $sensitiveEnvVars = @("ANTHROPIC_API_KEY", "OPENAI_API_KEY", "ZHIPU_API_KEY", "MINIMAX_API_KEY", "MOONSHOT_API_KEY")
        foreach ($envVar in $sensitiveEnvVars) {
            $envValue = [Environment]::GetEnvironmentVariable($envVar, "User")
            if (-not [string]::IsNullOrWhiteSpace($envValue)) {
                Write-UiWarn "检测到用户级环境变量 $envVar，建议清理（API Key 应仅存于 settings.json）"
            }
        }

        Write-UiSuccess "供应商配置验证通过"
        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = "验证供应商配置失败: $($_.Exception.Message)"
        Write-UiError $result.ErrorMessage
    }

    return $result
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用
# settings.json 路径获取统一使用 Provider.ps1 的 Get-ProviderSettingsPath
