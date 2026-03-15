# Registry.ps1 - 共享步骤注册表模块
# 功能: 统一管理步骤元数据、分组定义、依赖关系
#        消除 Install-ClaudeEnv.ps1 与 Manage-ClaudeEnv.ps1 之间的重复定义

#Requires -Version 7.0

Set-StrictMode -Version Latest

# ─── 注册表缓存（消除重复计算，一次构建多处复用） ──────────────────────────
$script:_registryCache = $null
$script:_registryIndex = $null

function Get-StepRegistry {
    <#
    .SYNOPSIS
    返回步骤注册表数组（含 Order 字段用于拓扑排序 tie-break）
    .DESCRIPTION
    内部使用缓存，首次调用构建数组，后续调用直接返回缓存副本。
    .RETURNS
    hashtable[] - 每条记录包含步骤的完整元数据
    #>
    param()

    if ($null -ne $script:_registryCache) {
        return $script:_registryCache
    }

    $script:_registryCache = @(
        @{
            StepId          = "NodeJS"
            StepName        = "Node.js"
            Description     = "安装 Node.js ，支持 nvm-windows / Node.js 二选一，并保留 fnm 检测与迁移能力"
            StepFile        = "steps/NodeJS.ps1"
            SubModules      = @(
                "steps/NodeJS-Detect.ps1"
                "steps/NodeJS-Common.ps1"
                "steps/NodeJS-Fnm.ps1"
                "steps/NodeJS-Nvm.ps1"
                "steps/NodeJS-Direct.ps1"
            )
            TestFunction    = "Test-NodeJSInstalled"
            InstallFunction = "Install-NodeJS"
            VerifyFunction  = "Verify-NodeJS"
            UpdateFunction  = ""
            SkipIfInstalled = $false
            IsOptional      = $false
            Order           = 10
            Dependencies    = @()
            Group           = "Basic"
        },
        @{
            StepId          = "Git"
            StepName        = "Git"
            Description     = "安装 Git 版本控制系统"
            StepFile        = "steps/Git.ps1"
            TestFunction    = "Test-GitInstalled"
            InstallFunction = "Install-Git"
            VerifyFunction  = "Verify-Git"
            UpdateFunction  = ""
            SkipIfInstalled = $true
            IsOptional      = $false
            Order           = 20
            Dependencies    = @()
            Group           = "Basic"
        },
        @{
            StepId          = "ClaudeCode"
            StepName        = "Claude Code"
            Description     = "通过 npm 全局安装 Claude Code CLI"
            StepFile        = "steps/ClaudeCode.ps1"
            TestFunction    = "Test-ClaudeCodeInstalled"
            InstallFunction = "Install-ClaudeCode"
            VerifyFunction  = "Verify-ClaudeCode"
            UpdateFunction  = "Update-ClaudeCode"
            SkipIfInstalled = $true
            IsOptional      = $false
            Order           = 30
            Dependencies    = @("NodeJS")
            Group           = "Basic"
        },
        @{
            StepId          = "ApiKey"
            StepName        = "第三方供应商配置"
            Description     = "配置第三方 AI 供应商连接到 ~/.claude/settings.json (env.ANTHROPIC_AUTH_TOKEN)"
            StepFile        = "steps/ApiKey.ps1"
            TestFunction    = "Test-ApiKeyInstalled"
            InstallFunction = "Install-ApiKey"
            VerifyFunction  = "Verify-ApiKey"
            UpdateFunction  = ""
            SkipIfInstalled = $true
            IsOptional      = $false
            Order           = 40
            Dependencies    = @("ClaudeCode")
            Group           = "Basic"
        },
        @{
            StepId          = "Ccline"
            StepName        = "CCometixLine"
            Description     = "安装 CCometixLine 状态栏增强工具"
            StepFile        = "steps/Ccline.ps1"
            TestFunction    = "Test-CclineInstalled"
            InstallFunction = "Install-Ccline"
            VerifyFunction  = "Verify-Ccline"
            UpdateFunction  = "Update-Ccline"
            SkipIfInstalled = $true
            IsOptional      = $false
            Order           = 50
            Dependencies    = @("ClaudeCode")
            Group           = "Advanced"
        },
        @{
            StepId          = "ClaudeConfig"
            StepName        = "Claude 基础配置"
            Description     = "写入 Claude Code 常用配置（语言、模型、权限、超时、归因等）"
            StepFile        = "steps/ClaudeConfig.ps1"
            TestFunction    = "Test-ClaudeConfigInstalled"
            InstallFunction = "Install-ClaudeConfig"
            VerifyFunction  = "Verify-ClaudeConfig"
            UpdateFunction  = "Update-ClaudeConfig"
            SkipIfInstalled = $true
            IsOptional      = $false
            Order           = 60
            Dependencies    = @("ClaudeCode")
            Group           = "Advanced"
        },
        @{
            StepId          = "ClaudeMd"
            StepName        = "CLAUDE.md 配置"
            Description     = "创建全局 CLAUDE.md 配置文件，定义 Claude Code 工作规范"
            StepFile        = "steps/ClaudeMd.ps1"
            TestFunction    = "Test-ClaudeMdInstalled"
            InstallFunction = "Install-ClaudeMd"
            VerifyFunction  = "Verify-ClaudeMd"
            UpdateFunction  = "Update-ClaudeMd"
            SkipIfInstalled = $true
            IsOptional      = $false
            Order           = 70
            Dependencies    = @()
            Group           = "Advanced"
        },
        @{
            StepId          = "Mcp"
            StepName        = "MCP Server 配置"
            Description     = "配置 MCP (Model Context Protocol) 插件服务器"
            StepFile        = "steps/Mcp.ps1"
            TestFunction    = "Test-McpInstalled"
            InstallFunction = "Install-Mcp"
            VerifyFunction  = "Verify-Mcp"
            UpdateFunction  = ""
            SkipIfInstalled = $false
            IsOptional      = $false
            Order           = 80
            Dependencies    = @("ClaudeCode")
            Group           = "Advanced"
        },
        @{
            StepId          = "CcgWorkflow"
            StepName        = "CCG 工作流"
            Description     = "安装 Claude Code Generator 工作流脚本和 Slash Commands"
            StepFile        = "steps/CcgWorkflow.ps1"
            TestFunction    = "Test-CcgWorkflowInstalled"
            InstallFunction = "Install-CcgWorkflow"
            VerifyFunction  = "Verify-CcgWorkflow"
            UpdateFunction  = "Update-CcgWorkflow"
            SkipIfInstalled = $true
            IsOptional      = $false
            Order           = 90
            Dependencies    = @("NodeJS")
            Group           = "Advanced"
        },
        @{
            StepId          = "OpenSpec"
            StepName        = "OpenSpec CLI"
            Description     = "安装 OpenSpec CLI（规范驱动开发工具）"
            StepFile        = "steps/OpenSpec.ps1"
            TestFunction    = "Test-OpenSpecInstalled"
            InstallFunction = "Install-OpenSpec"
            VerifyFunction  = "Verify-OpenSpec"
            UpdateFunction  = "Update-OpenSpec"
            SkipIfInstalled = $true
            IsOptional      = $false
            Order           = 100
            Dependencies    = @("NodeJS")
            Group           = "Advanced"
        },
        @{
            StepId          = "CcSwitch"
            StepName        = "cc-switch"
            Description     = "安装 cc-switch，Claude Code / Codex / Gemini CLI 全方位辅助工具"
            StepFile        = "steps/CcSwitch.ps1"
            TestFunction    = "Test-CcSwitchInstalled"
            InstallFunction = "Install-CcSwitch"
            VerifyFunction  = "Verify-CcSwitch"
            UpdateFunction  = ""
            SkipIfInstalled = $true
            IsOptional      = $true
            Order           = 110
            Dependencies    = @("ClaudeCode")
            Group           = "Advanced"
        },
        @{
            StepId          = "CodexCli"
            StepName        = "Codex CLI"
            Description     = "安装 OpenAI Codex CLI（多模型协作可选工具）"
            StepFile        = "steps/CodexCli.ps1"
            TestFunction    = "Test-CodexCliInstalled"
            InstallFunction = "Install-CodexCli"
            VerifyFunction  = "Verify-CodexCli"
            UpdateFunction  = "Update-CodexCli"
            SkipIfInstalled = $true
            IsOptional      = $true
            Order           = 120
            Dependencies    = @("NodeJS")
            Group           = "Advanced"
        },
        @{
            StepId          = "GeminiCli"
            StepName        = "Gemini CLI"
            Description     = "安装 Google Gemini CLI（多模型协作可选工具）"
            StepFile        = "steps/GeminiCli.ps1"
            TestFunction    = "Test-GeminiCliInstalled"
            InstallFunction = "Install-GeminiCli"
            VerifyFunction  = "Verify-GeminiCli"
            UpdateFunction  = "Update-GeminiCli"
            SkipIfInstalled = $true
            IsOptional      = $true
            Order           = 130
            Dependencies    = @("NodeJS")
            Group           = "Advanced"
        }
    )

    # 构建 StepId → StepConfig 索引（O(1) 查找）
    $script:_registryIndex = @{}
    foreach ($step in $script:_registryCache) {
        $script:_registryIndex[$step.StepId] = $step
    }

    return $script:_registryCache
}

function Get-StepConfigById {
    <#
    .SYNOPSIS
    按 StepId 查找步骤配置（O(1) 索引查找，替代 Where-Object 管道过滤）
    .PARAMETER StepId
    步骤唯一标识
    .RETURNS
    hashtable - 步骤配置，未找到返回 $null
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$StepId
    )

    # 确保索引已构建
    if ($null -eq $script:_registryIndex) {
        $null = Get-StepRegistry
    }

    if ($script:_registryIndex.ContainsKey($StepId)) {
        return $script:_registryIndex[$StepId]
    }
    return $null
}

function Get-StepGroups {
    <#
    .SYNOPSIS
    返回 Basic/Advanced 分组定义
    .RETURNS
    hashtable - 分组名称 → 分组配置
    #>
    param()

    $registry = Get-StepRegistry

    $basicIds = @($registry | Where-Object { $_.Group -eq "Basic" } | ForEach-Object { $_.StepId })
    $advancedIds = @($registry | Where-Object { $_.Group -eq "Advanced" } | ForEach-Object { $_.StepId })

    return @{
        Basic = @{
            Label       = "基础环境"
            Description = "Claude Code 最小可用环境"
            InstallMode = "OneClickOnly"
            StepIds     = $basicIds
        }
        Advanced = @{
            Label       = "进阶扩展"
            Description = "增强工具、配置优化、多模型协作"
            InstallMode = "OneClickOrSelect"
            StepIds     = $advancedIds
        }
    }
}

function Get-StepDependencies {
    <#
    .SYNOPSIS
    从注册表提取步骤依赖关系哈希表
    .RETURNS
    hashtable - StepId → 依赖 StepId 数组
    #>
    param()

    $registry = Get-StepRegistry
    $dependencies = @{}
    foreach ($step in $registry) {
        $dependencies[$step.StepId] = $step.Dependencies
    }
    return $dependencies
}

function Get-StepFiles {
    <#
    .SYNOPSIS
    返回步骤文件相对路径列表（相对于 installer/ 目录，按 Order 排序）
    .DESCRIPTION
    若步骤注册了 SubModules，子模块文件会排在主步骤文件之前，
    确保构建打包和运行时加载均能正确包含子模块内容。
    .RETURNS
    string[] - 步骤文件路径数组
    #>
    param()

    $registry = Get-StepRegistry
    $files = [System.Collections.Generic.List[string]]::new()
    foreach ($step in ($registry | Sort-Object { $_.Order })) {
        # 子模块排在主文件之前（构建时内联、运行时预加载）
        if ($step.ContainsKey('SubModules') -and $step.SubModules.Count -gt 0) {
            foreach ($sub in $step.SubModules) {
                $files.Add($sub)
            }
        }
        $files.Add($step.StepFile)
    }
    return @($files)
}
