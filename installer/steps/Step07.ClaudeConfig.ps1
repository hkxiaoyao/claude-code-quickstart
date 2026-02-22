# Claude Code 配置步骤 - Claude Code 环境安装器
# 功能: 完整的 Claude Code settings.json 配置写入（基于 HC-13 约束）

#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 导入依赖模块
. "$PSScriptRoot\..\core\Ui.ps1"
. "$PSScriptRoot\..\core\Profile.ps1"

function Test-Step07Installed {
    <#
    .SYNOPSIS
    检测 Claude Code 配置是否已完成
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

        # 检查关键配置项（Claude Code 真实 schema）
        $hasEnv         = $settings.PSObject.Properties.Name -contains "env"
        $hasAuthToken   = $hasEnv -and -not [string]::IsNullOrWhiteSpace($settings.env.ANTHROPIC_AUTH_TOKEN)
        $hasPermissions = $settings.PSObject.Properties.Name -contains "permissions"
        $hasLanguage    = $settings.PSObject.Properties.Name -contains "language"

        if ($hasAuthToken -and $hasPermissions -and $hasLanguage) {
            Write-UiSuccess "✓ Claude Code 配置已完成"
            $result.IsInstalled = $true
            $result.Message     = "Claude Code 配置已完成"
        } else {
            $result.Message = "Claude Code 配置不完整（缺少 env/permissions/language）"
        }
    }
    catch {
        $result.Message = "检测 Claude Code 配置时出错: $($_.Exception.Message)"
        Write-UiError $result.Message
    }

    return $result
}

function Install-Step07 {
    <#
    .SYNOPSIS
    安装 Claude Code 配置（在 Step06 基础上补全 settings.json）
    .RETURNS
    包含 Success 字段的结果对象
    #>

    $result = @{
        Success      = $false
        ErrorMessage = ""
        Data         = @{}
    }

    try {
        Write-UiInfo "配置 Claude Code settings.json..."

        $settingsPath = Get-ClaudeSettingsPath
        $settings = @{}

        # 读取现有配置（Step06 已写入 env.ANTHROPIC_AUTH_TOKEN）
        if (Test-Path $settingsPath) {
            try {
                $existingContent = Get-Content $settingsPath -Raw
                $settings = $existingContent | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
                if (-not $settings) { $settings = @{} }
                Write-UiInfo "已读取现有配置，将补全配置项"
            }
            catch {
                Write-UiWarn "无法解析现有 settings.json，将创建新配置"
                $settings = @{}
            }
        }

        # 补全 env 配置（不覆盖 Step06 已写入的 ANTHROPIC_AUTH_TOKEN）
        if (-not $settings.ContainsKey("env")) {
            $settings["env"] = @{}
        }
        # 添加超时和行为相关配置（不含 API Key）
        if (-not $settings["env"].ContainsKey("BASH_DEFAULT_TIMEOUT_MS")) {
            $settings["env"]["BASH_DEFAULT_TIMEOUT_MS"] = "600000"
        }
        if (-not $settings["env"].ContainsKey("BASH_MAX_TIMEOUT_MS")) {
            $settings["env"]["BASH_MAX_TIMEOUT_MS"] = "3600000"
        }
        if (-not $settings["env"].ContainsKey("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC")) {
            $settings["env"]["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
        }
        if (-not $settings["env"].ContainsKey("MAX_THINKING_TOKENS")) {
            $settings["env"]["MAX_THINKING_TOKENS"] = "31999"
        }

        # 语言设置
        $settings["language"] = "简体中文"

        # 模型设置
        if (-not $settings.ContainsKey("model")) {
            $settings["model"] = "sonnet"
        }

        # 权限配置（Claude Code 真实 schema）
        $settings["permissions"] = @{
            "allow" = @(
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
            "deny" = @()
        }

        # statusLine 配置（若 Step04 安装了 ccline 会在那步写入，这里提供占位）
        if (-not $settings.ContainsKey("statusLine")) {
            $settings["statusLine"] = @{
                "type"    = "disabled"
                "padding" = 0
            }
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

        Write-UiSuccess "✓ Claude Code 配置已写入 ~/.claude/settings.json"
        Write-UiInfo "配置路径: $settingsPath"
        Write-UiInfo "配置摘要:"
        Write-UiInfo "  - 语言: 简体中文"
        Write-UiInfo "  - 模型: $($settings['model'])"
        Write-UiInfo "  - 权限项: $($settings['permissions']['allow'].Count) 项"

        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = "配置 Claude Code 失败: $($_.Exception.Message)"
        Write-UiError $result.ErrorMessage
    }

    return $result
}

function Verify-Step07 {
    <#
    .SYNOPSIS
    验证 Claude Code 配置
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

        # 验证 env.ANTHROPIC_AUTH_TOKEN 存在（Step06 责任）
        if (-not $settings.env -or [string]::IsNullOrWhiteSpace($settings.env.ANTHROPIC_AUTH_TOKEN)) {
            throw "env.ANTHROPIC_AUTH_TOKEN 未配置（请先运行 Step06）"
        }

        # 验证 language 配置
        if (-not $settings.language) {
            throw "language 配置缺失"
        }

        # 验证 permissions 配置
        if (-not $settings.permissions -or -not $settings.permissions.allow) {
            throw "permissions.allow 配置缺失"
        }

        Write-UiSuccess "✓ Claude Code 配置验证通过"
        Write-UiInfo "  - env.ANTHROPIC_AUTH_TOKEN: ✓"
        Write-UiInfo "  - language: $($settings.language)"
        Write-UiInfo "  - permissions.allow: $($settings.permissions.allow.Count) 项"

        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = "验证 Claude Code 配置失败: $($_.Exception.Message)"
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
