# MCP Server 安装步骤 - Claude Code 环境安装器
# 作者: 哈雷酱 (本小姐的专业 MCP 管理！)
# 功能: MCP Server 安装、配置和 API Key 管理

#Requires -Version 5.1

# 严格模式
Set-StrictMode -Version Latest

# 导入依赖模块
. "$PSScriptRoot\..\core\Ui.ps1"
. "$PSScriptRoot\..\core\Profile.ps1"
. "$PSScriptRoot\..\core\Process.ps1"

# MCP Server 配置定义
$script:McpServers = @{
    "context7" = @{
        Name = "Context7"
        Description = "库文档和代码示例检索，支持最新的开发框架文档"
        Command = "npx"
        Args = @("@upstash/context7-mcp")
        RequiresApiKey = $false
        Category = "Documentation"
        Priority = 1
        Recommended = $true
    }
    "deepwiki" = @{
        Name = "DeepWiki"
        Description = "GitHub 仓库 AI 文档生成和问答"
        Command = "npx"
        Args = @("@modelcontextprotocol/server-deepwiki")
        RequiresApiKey = $false
        Category = "Documentation"
        Priority = 2
        Recommended = $true
    }
    "exa" = @{
        Name = "Exa Search"
        Description = "高质量网络搜索和内容提取"
        Command = "npx"
        Args = @("@modelcontextprotocol/server-exa")
        RequiresApiKey = $true
        ApiKeyName = "EXA_API_KEY"
        Category = "Search"
        Priority = 3
        Recommended = $true
    }
    "tavily" = @{
        Name = "Tavily"
        Description = "AI 搜索和研究工具"
        Command = "npx"
        Args = @("@modelcontextprotocol/server-tavily")
        RequiresApiKey = $true
        ApiKeyName = "TAVILY_API_KEY"
        Category = "Search"
        Priority = 4
        Recommended = $true
    }
    "playwright" = @{
        Name = "Playwright"
        Description = "网页自动化和截图工具"
        Command = "npx"
        Args = @("@modelcontextprotocol/server-playwright")
        RequiresApiKey = $false
        Category = "Automation"
        Priority = 5
        Recommended = $true
    }
    "ace-tool" = @{
        Name = "ACE Tool"
        Description = "代码上下文检索和语义搜索"
        Command = "npx"
        Args = @("@augment-code/mcp-server")
        RequiresApiKey = $false
        Category = "Development"
        Priority = 6
        Recommended = $false
    }
    "mastergo" = @{
        Name = "MasterGo"
        Description = "设计稿解析和代码生成"
        Command = "npx"
        Args = @("@mastergo/mcp-server")
        RequiresApiKey = $false
        Category = "Design"
        Priority = 7
        Recommended = $false
    }
    "pencil" = @{
        Name = "Pencil"
        Description = "UI/UX 设计和原型工具"
        Command = "npx"
        Args = @("@pencil-js/mcp-server")
        RequiresApiKey = $false
        Category = "Design"
        Priority = 8
        Recommended = $false
    }
    "filesystem" = @{
        Name = "Filesystem"
        Description = "文件系统操作和管理"
        Command = "npx"
        Args = @("@modelcontextprotocol/server-filesystem")
        RequiresApiKey = $false
        Category = "System"
        Priority = 9
        Recommended = $false
    }
    "sqlite" = @{
        Name = "SQLite"
        Description = "SQLite 数据库操作"
        Command = "npx"
        Args = @("@modelcontextprotocol/server-sqlite")
        RequiresApiKey = $false
        Category = "Database"
        Priority = 10
        Recommended = $false
    }
}

function Test-Step09Installed {
    <#
    .SYNOPSIS
    检测 MCP Server 是否已安装配置
    #>

    try {
        $settingsPath = Get-ClaudeSettingsPath
        if (-not (Test-Path $settingsPath)) {
            return $false
        }

        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if (-not $settings) {
            return $false
        }

        # 检查 MCP 配置
        $hasMcpServers = $settings.PSObject.Properties.Name -contains "mcpServers" -and $settings.mcpServers
        $hasPermissions = $settings.PSObject.Properties.Name -contains "permissions" -and
                         $settings.permissions -and $settings.permissions.allow

        if ($hasMcpServers -and $hasPermissions) {
            $mcpCount = ($settings.mcpServers | Get-Member -MemberType NoteProperty).Count
            Write-UiSuccess "✓ MCP Server 已配置 ($mcpCount 个)"
            return $true
        }

        return $false
    }
    catch {
        Write-UiError "检测 MCP Server 配置时出错: $($_.Exception.Message)"
        return $false
    }
}

function Install-Step09 {
    <#
    .SYNOPSIS
    安装 MCP Server 配置
    #>

    try {
        Write-UiInfo "配置 MCP Server..."

        # 显示安装模式选择
        $modeOptions = @(
            @{
                Label = "一键模式 (推荐)"
                Description = "自动安装核心 5 个 MCP Server，适合快速开始"
                Value = "quick"
            },
            @{
                Label = "自定义模式"
                Description = "手动选择需要的 MCP Server，适合高级用户"
                Value = "custom"
            }
        )

        Write-UiInfo "请选择安装模式:"
        $selectedMode = Show-SingleSelectMenu -Options $modeOptions -Title "MCP Server 安装模式"

        if (-not $selectedMode) {
            throw "未选择安装模式"
        }

        $selectedServers = @()

        if ($selectedMode -eq "quick") {
            # 一键模式：安装推荐的 MCP Server
            $selectedServers = $script:McpServers.Keys | Where-Object {
                $script:McpServers[$_].Recommended
            } | Sort-Object { $script:McpServers[$_].Priority }

            Write-UiInfo "一键模式将安装以下 MCP Server:"
            foreach ($serverId in $selectedServers) {
                $server = $script:McpServers[$serverId]
                Write-UiInfo "  - $($server.Name): $($server.Description)"
            }
        }
        else {
            # 自定义模式：多选菜单
            $serverOptions = @()
            foreach ($serverId in ($script:McpServers.Keys | Sort-Object { $script:McpServers[$_].Priority })) {
                $server = $script:McpServers[$serverId]
                $label = $server.Name
                if ($server.Recommended) {
                    $label += " (推荐)"
                }

                $serverOptions += @{
                    Label = $label
                    Description = "$($server.Description) [$($server.Category)]"
                    Value = $serverId
                    Selected = $server.Recommended
                }
            }

            Write-UiInfo "请选择要安装的 MCP Server:"
            $selectedServers = Show-MultiSelectMenu -Options $serverOptions -Title "MCP Server 选择"

            if (-not $selectedServers -or $selectedServers.Count -eq 0) {
                throw "未选择任何 MCP Server"
            }
        }

        # 收集需要 API Key 的服务
        $apiKeyServers = $selectedServers | Where-Object {
            $script:McpServers[$_].RequiresApiKey
        }

        $apiKeys = @{}
        if ($apiKeyServers.Count -gt 0) {
            Write-UiInfo "以下 MCP Server 需要 API Key:"
            foreach ($serverId in $apiKeyServers) {
                $server = $script:McpServers[$serverId]
                Write-UiInfo "  - $($server.Name): $($server.ApiKeyName)"
            }

            Write-UiWarn "注意: API Key 将安全存储在 settings.json 的 env 字段中"

            foreach ($serverId in $apiKeyServers) {
                $server = $script:McpServers[$serverId]

                do {
                    Write-UiInfo "请输入 $($server.Name) 的 API Key ($($server.ApiKeyName)):"
                    $apiKey = Read-Host -Prompt "API Key" -AsSecureString
                    $apiKeyPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($apiKey))

                    if ([string]::IsNullOrWhiteSpace($apiKeyPlain)) {
                        Write-UiError "API Key 不能为空，请重新输入"
                        continue
                    }

                    if ($apiKeyPlain.Length -lt 10) {
                        Write-UiError "API Key 长度过短，请检查后重新输入"
                        continue
                    }

                    $apiKeys[$server.ApiKeyName] = $apiKeyPlain
                    break
                } while ($true)
            }
        }

        # 读取现有配置
        $settingsPath = Get-ClaudeSettingsPath
        $settings = @{}

        if (Test-Path $settingsPath) {
            try {
                $existingContent = Get-Content $settingsPath -Raw
                $settings = $existingContent | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
                if (-not $settings) {
                    $settings = @{}
                }
                Write-UiInfo "已读取现有配置，将进行合并"
            }
            catch {
                Write-UiWarn "无法解析现有 settings.json，将创建新配置"
                $settings = @{}
            }
        }

        # 构建 MCP Server 配置
        if (-not $settings.ContainsKey("mcpServers")) {
            $settings["mcpServers"] = @{}
        }

        foreach ($serverId in $selectedServers) {
            $server = $script:McpServers[$serverId]

            $mcpConfig = @{
                command = $server.Command
                args = $server.Args
            }

            # 如果需要 API Key，添加环境变量配置
            if ($server.RequiresApiKey -and $apiKeys.ContainsKey($server.ApiKeyName)) {
                $mcpConfig["env"] = @{
                    $server.ApiKeyName = $apiKeys[$server.ApiKeyName]
                }
            }

            $settings["mcpServers"][$serverId] = $mcpConfig
        }

        # 更新权限配置
        if (-not $settings.ContainsKey("permissions")) {
            $settings["permissions"] = @{}
        }
        if (-not $settings["permissions"].ContainsKey("allow")) {
            $settings["permissions"]["allow"] = @()
        }

        # 添加 MCP 相关权限
        $mcpPermissions = @("mcp", "read", "write", "bash", "glob", "grep")
        foreach ($permission in $mcpPermissions) {
            if ($settings["permissions"]["allow"] -notcontains $permission) {
                $settings["permissions"]["allow"] += $permission
            }
        }

        # 添加 API Key 到全局 env 配置
        if ($apiKeys.Count -gt 0) {
            if (-not $settings.ContainsKey("env")) {
                $settings["env"] = @{}
            }

            foreach ($keyName in $apiKeys.Keys) {
                $settings["env"][$keyName] = $apiKeys[$keyName]
            }
        }

        # 确保目录存在
        $settingsDir = Split-Path $settingsPath -Parent
        if (-not (Test-Path $settingsDir)) {
            New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
        }

        # 原子写入
        Write-UiInfo "写入 MCP Server 配置..."
        $tempPath = "$settingsPath.tmp"
        $settings | ConvertTo-Json -Depth 10 | Set-Content $tempPath -Encoding UTF8
        Move-Item $tempPath $settingsPath -Force

        Write-UiSuccess "✓ MCP Server 配置已写入"
        Write-UiInfo "配置路径: $settingsPath"

        # 显示配置摘要
        Write-UiInfo "配置摘要:"
        Write-UiInfo "  - MCP Server 数量: $($selectedServers.Count)"
        Write-UiInfo "  - API Key 配置: $($apiKeys.Count) 个"
        Write-UiInfo "  - 权限策略: $($settings.permissions.allow.Count) 项"

        foreach ($serverId in $selectedServers) {
            $server = $script:McpServers[$serverId]
            $status = if ($server.RequiresApiKey) { "需要 API Key" } else { "无需 API Key" }
            Write-UiInfo "  - $($server.Name): $status"
        }

        # 清理敏感变量
        foreach ($key in $apiKeys.Keys) {
            $apiKeys[$key] = $null
        }

        return $true
    }
    catch {
        Write-UiError "配置 MCP Server 失败: $($_.Exception.Message)"
        return $false
    }
}

function Verify-Step09 {
    <#
    .SYNOPSIS
    验证 MCP Server 配置
    #>

    try {
        $settingsPath = Get-ClaudeSettingsPath
        if (-not (Test-Path $settingsPath)) {
            throw "settings.json 文件不存在"
        }

        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json

        # 验证 MCP Server 配置
        if (-not $settings.mcpServers) {
            throw "缺少 MCP Server 配置"
        }

        $configuredServers = ($settings.mcpServers | Get-Member -MemberType NoteProperty).Name
        if ($configuredServers.Count -eq 0) {
            throw "未配置任何 MCP Server"
        }

        # 验证每个 MCP Server 配置
        foreach ($serverId in $configuredServers) {
            $serverConfig = $settings.mcpServers.$serverId

            if (-not $serverConfig.command) {
                throw "MCP Server '$serverId' 缺少 command 配置"
            }

            if (-not $serverConfig.args) {
                throw "MCP Server '$serverId' 缺少 args 配置"
            }

            # 验证 API Key（如果需要）
            if ($script:McpServers.ContainsKey($serverId)) {
                $serverDef = $script:McpServers[$serverId]
                if ($serverDef.RequiresApiKey) {
                    $hasApiKey = $false

                    # 检查 MCP 级别的 env 配置
                    if ($serverConfig.env -and $serverConfig.env.($serverDef.ApiKeyName)) {
                        $hasApiKey = $true
                    }

                    # 检查全局 env 配置
                    if ($settings.env -and $settings.env.($serverDef.ApiKeyName)) {
                        $hasApiKey = $true
                    }

                    if (-not $hasApiKey) {
                        Write-UiWarn "⚠️ MCP Server '$serverId' 需要 API Key: $($serverDef.ApiKeyName)"
                    }
                }
            }
        }

        # 验证权限配置
        if (-not $settings.permissions -or -not $settings.permissions.allow) {
            throw "缺少权限配置"
        }

        $requiredPermissions = @("mcp", "read", "write")
        foreach ($permission in $requiredPermissions) {
            if ($settings.permissions.allow -notcontains $permission) {
                Write-UiWarn "⚠️ 缺少权限: $permission"
            }
        }

        Write-UiSuccess "✓ MCP Server 配置验证通过"
        Write-UiInfo "  - 配置的 MCP Server: $($configuredServers.Count) 个"
        Write-UiInfo "  - 权限配置: ✓"

        foreach ($serverId in $configuredServers) {
            Write-UiInfo "  - ${serverId}: ✓"
        }

        return $true
    }
    catch {
        Write-UiError "验证 MCP Server 配置失败: $($_.Exception.Message)"
        return $false
    }
}

# 辅助函数
function Get-ClaudeSettingsPath {
    <#
    .SYNOPSIS
    获取 Claude Code settings.json 路径（HC-12: ~/.claude/settings.json）
    #>

    return "$env:USERPROFILE\.claude\settings.json"
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用
