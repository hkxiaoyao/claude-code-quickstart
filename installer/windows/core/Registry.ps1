# Registry.ps1 - 共享步骤注册表模块
# 功能: 统一管理步骤元数据、分组定义、依赖关系
#        消除 Install.ps1 与 Manage.ps1 之间的重复定义

#Requires -Version 7.0

Set-StrictMode -Version Latest

# ─── 注册表缓存（消除重复计算，一次构建多处复用） ──────────────────────────
$script:_registryCache = $null
$script:_registryIndex = $null
$script:_groupCache = $null
$script:_stepContractCache = $null

function Get-RegistryWindowsRoot {
    <#
    .SYNOPSIS
    返回 Windows 平台根目录 installer/windows。
    #>
    param()

    if (Get-Variable -Name WindowsRoot -Scope Script -ErrorAction SilentlyContinue) {
        $windowsRoot = [string]$script:WindowsRoot
        if (-not [string]::IsNullOrWhiteSpace($windowsRoot)) {
            return $windowsRoot
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $currentRoot = $PSScriptRoot
        if ((Split-Path -Leaf $currentRoot) -ieq 'core') {
            return (Split-Path -Parent $currentRoot)
        }
        return $currentRoot
    }

    return ''
}

function Get-RegistryInstallerRoot {
    <#
    .SYNOPSIS
    返回 installer 根目录，用于定位 contracts 与平台目录。
    #>
    param()

    if (Get-Variable -Name InstallerRoot -Scope Script -ErrorAction SilentlyContinue) {
        $installerRoot = [string]$script:InstallerRoot
        if (-not [string]::IsNullOrWhiteSpace($installerRoot)) {
            return $installerRoot
        }
    }

    $windowsRoot = Get-RegistryWindowsRoot
    if (-not [string]::IsNullOrWhiteSpace($windowsRoot)) {
        return (Split-Path -Parent $windowsRoot)
    }

    return ''
}

function Get-RegistryContractsRoot {
    <#
    .SYNOPSIS
    返回 contracts 根目录；优先使用内嵌 artifact 暴露的环境变量。
    #>
    param()

    if (-not [string]::IsNullOrWhiteSpace($env:CCQ_CONTRACTS_DIR)) {
        return $env:CCQ_CONTRACTS_DIR
    }

    $installerRoot = Get-RegistryInstallerRoot
    if ([string]::IsNullOrWhiteSpace($installerRoot)) {
        return ''
    }

    return (Join-Path $installerRoot 'contracts')
}

function Get-StepsContractPath {
    <#
    .SYNOPSIS
    返回 steps.json 契约路径。
    #>
    param()

    if (-not [string]::IsNullOrWhiteSpace($env:CCQ_STEPS_CONTRACT)) {
        return $env:CCQ_STEPS_CONTRACT
    }

    $contractsRoot = Get-RegistryContractsRoot
    if ([string]::IsNullOrWhiteSpace($contractsRoot)) {
        return ''
    }

    return (Join-Path $contractsRoot 'steps.json')
}

function Get-RegistryValue {
    <#
    .SYNOPSIS
    安全读取 IDictionary 字段，避免 StrictMode 下访问缺失键。
    #>
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Table,

        [Parameter(Mandatory)]
        [string]$Key,

        [object]$Default = $null
    )

    if ($Table.Contains($Key) -and $null -ne $Table[$Key]) {
        return $Table[$Key]
    }
    return $Default
}

function Get-StepContract {
    <#
    .SYNOPSIS
    优先读取 installer/contracts/steps.json；不可用时返回 $null。
    #>
    param()

    if ($null -ne $script:_stepContractCache) {
        return $script:_stepContractCache
    }

    $contractPath = Get-StepsContractPath
    if ([string]::IsNullOrWhiteSpace($contractPath) -or -not (Test-Path $contractPath -PathType Leaf)) {
        return $null
    }

    try {
        $script:_stepContractCache = Get-Content -Path $contractPath -Encoding UTF8 -Raw | ConvertFrom-Json -AsHashtable
        return $script:_stepContractCache
    } catch {
        Write-Verbose "读取 steps 契约失败，改用 Registry 内联 fallback: $($_.Exception.Message)"
        return $null
    }
}

function ConvertTo-StepRegistryFromContract {
    <#
    .SYNOPSIS
    将 steps.json 契约转换为 Windows PowerShell 注册表。
    #>
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Contract
    )

    $registry = [System.Collections.Generic.List[hashtable]]::new()
    $steps = @(Get-RegistryValue -Table $Contract -Key 'Steps' -Default @() | Sort-Object { [int](Get-RegistryValue -Table $_ -Key 'Order' -Default 0) })

    foreach ($step in $steps) {
        $subModules = @(Get-RegistryValue -Table $step -Key 'SubModules' -Default @() | ForEach-Object { [string]$_ })
        $dependencies = @(Get-RegistryValue -Table $step -Key 'Dependencies' -Default @() | ForEach-Object { [string]$_ })

        $entry = @{
            StepId          = [string](Get-RegistryValue -Table $step -Key 'StepId' -Default '')
            StepName        = [string](Get-RegistryValue -Table $step -Key 'StepName' -Default '')
            Description     = [string](Get-RegistryValue -Table $step -Key 'Description' -Default '')
            StepFile        = [string](Get-RegistryValue -Table $step -Key 'StepFile' -Default '')
            TestFunction    = [string](Get-RegistryValue -Table $step -Key 'TestFunction' -Default '')
            InstallFunction = [string](Get-RegistryValue -Table $step -Key 'InstallFunction' -Default '')
            VerifyFunction  = [string](Get-RegistryValue -Table $step -Key 'VerifyFunction' -Default '')
            UpdateFunction  = [string](Get-RegistryValue -Table $step -Key 'UpdateFunction' -Default '')
            SkipIfInstalled = [bool](Get-RegistryValue -Table $step -Key 'SkipIfInstalled' -Default $false)
            IsOptional      = [bool](Get-RegistryValue -Table $step -Key 'IsOptional' -Default $false)
            Order           = [int](Get-RegistryValue -Table $step -Key 'Order' -Default 0)
            Dependencies    = $dependencies
            Group           = [string](Get-RegistryValue -Table $step -Key 'Group' -Default '')
        }

        if ($subModules.Count -gt 0) {
            $entry['SubModules'] = $subModules
        }
        if ($step.Contains('SkipIfInstalledWhenAutoAdded')) {
            $entry['SkipIfInstalledWhenAutoAdded'] = [bool](Get-RegistryValue -Table $step -Key 'SkipIfInstalledWhenAutoAdded' -Default $false)
        }

        $registry.Add($entry)
    }

    return @($registry)
}

function ConvertTo-StepGroupsFromContract {
    <#
    .SYNOPSIS
    将 steps.json 分组契约转换为 Windows 分组表。
    #>
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Contract
    )

    $groupsNode = Get-RegistryValue -Table $Contract -Key 'Groups' -Default $null
    if (-not ($groupsNode -is [System.Collections.IDictionary])) {
        return $null
    }

    $groups = @{}
    foreach ($groupName in @('Basic', 'Advanced')) {
        if (-not $groupsNode.Contains($groupName)) {
            continue
        }

        $group = $groupsNode[$groupName]
        $groups[$groupName] = @{
            Label       = [string](Get-RegistryValue -Table $group -Key 'Label' -Default $groupName)
            Description = [string](Get-RegistryValue -Table $group -Key 'Description' -Default '')
            InstallMode = [string](Get-RegistryValue -Table $group -Key 'InstallMode' -Default '')
            StepIds     = @(Get-RegistryValue -Table $group -Key 'StepIds' -Default @() | ForEach-Object { [string]$_ })
        }
    }

    return $groups
}

function Convert-StepRegistryToComparableJson {
    <#
    .SYNOPSIS
    生成用于比较 contracts 与内联 fallback 的稳定 JSON。
    #>
    param(
        [Parameter(Mandatory)]
        [object[]]$Registry
    )

    $items = foreach ($step in @($Registry | Sort-Object { [int](Get-RegistryValue -Table $_ -Key 'Order' -Default 0) })) {
        [ordered]@{
            StepId                        = [string](Get-RegistryValue -Table $step -Key 'StepId' -Default '')
            StepName                      = [string](Get-RegistryValue -Table $step -Key 'StepName' -Default '')
            Description                   = [string](Get-RegistryValue -Table $step -Key 'Description' -Default '')
            StepFile                      = [string](Get-RegistryValue -Table $step -Key 'StepFile' -Default '')
            SubModules                    = @(Get-RegistryValue -Table $step -Key 'SubModules' -Default @() | ForEach-Object { [string]$_ })
            TestFunction                  = [string](Get-RegistryValue -Table $step -Key 'TestFunction' -Default '')
            InstallFunction               = [string](Get-RegistryValue -Table $step -Key 'InstallFunction' -Default '')
            VerifyFunction                = [string](Get-RegistryValue -Table $step -Key 'VerifyFunction' -Default '')
            UpdateFunction                = [string](Get-RegistryValue -Table $step -Key 'UpdateFunction' -Default '')
            SkipIfInstalled               = [bool](Get-RegistryValue -Table $step -Key 'SkipIfInstalled' -Default $false)
            SkipIfInstalledWhenAutoAdded  = [bool](Get-RegistryValue -Table $step -Key 'SkipIfInstalledWhenAutoAdded' -Default $false)
            IsOptional                    = [bool](Get-RegistryValue -Table $step -Key 'IsOptional' -Default $false)
            Order                         = [int](Get-RegistryValue -Table $step -Key 'Order' -Default 0)
            Dependencies                  = @(Get-RegistryValue -Table $step -Key 'Dependencies' -Default @() | ForEach-Object { [string]$_ })
            Group                         = [string](Get-RegistryValue -Table $step -Key 'Group' -Default '')
        }
    }

    return ($items | ConvertTo-Json -Depth 8 -Compress)
}

function Assert-StepRegistryFallbackConsistency {
    <#
    .SYNOPSIS
    确保源码 contracts 与 release fallback 的步骤语义保持一致。
    #>
    param(
        [Parameter(Mandatory)]
        [object[]]$ContractRegistry
    )

    $contractJson = Convert-StepRegistryToComparableJson -Registry $ContractRegistry
    $fallbackJson = Convert-StepRegistryToComparableJson -Registry (Get-InlineStepRegistry)
    if ($contractJson -ne $fallbackJson) {
        throw 'installer/contracts/steps.json 与 Registry.ps1 内联 fallback 不一致，请同步更新二者。'
    }
}

function Set-StepRegistryCaches {
    <#
    .SYNOPSIS
    设置注册表、索引与分组缓存。
    #>
    param(
        [Parameter(Mandatory)]
        [object[]]$Registry,

        [hashtable]$Groups = $null
    )

    $script:_registryCache = @($Registry)
    $script:_registryIndex = @{}
    foreach ($step in $script:_registryCache) {
        $script:_registryIndex[[string]$step['StepId']] = $step
    }
    $script:_groupCache = $Groups
}

function Get-InlineStepRegistry {
    <#
    .SYNOPSIS
    返回 release artifact 或 contracts 不可用时使用的内联 fallback 注册表。
    #>
    param()

    return @(
        @{
            StepId          = "NodeJS"
            StepName        = "Node.js"
            Description     = "安装 Node.js ，支持 nvm-windows / Node.js 二选一，并保留 fnm 检测与迁移能力"
            StepFile        = "windows/steps/NodeJS.ps1"
            SubModules      = @(
                "windows/steps/NodeJS-Detect.ps1"
                "windows/steps/NodeJS-Common.ps1"
                "windows/steps/NodeJS-Fnm.ps1"
                "windows/steps/NodeJS-Nvm.ps1"
                "windows/steps/NodeJS-Direct.ps1"
            )
            TestFunction    = "Test-NodeJSInstalled"
            InstallFunction = "Install-NodeJS"
            VerifyFunction  = "Verify-NodeJS"
            UpdateFunction  = ""
            SkipIfInstalled                = $false
            SkipIfInstalledWhenAutoAdded   = $true
            IsOptional      = $false
            Order           = 10
            Dependencies    = @()
            Group           = "Basic"
        },
        @{
            StepId          = "Git"
            StepName        = "Git"
            Description     = "安装 Git 版本控制系统"
            StepFile        = "windows/steps/Git.ps1"
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
            StepFile        = "windows/steps/ClaudeCode.ps1"
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
            StepFile        = "windows/steps/ApiKey.ps1"
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
            StepFile        = "windows/steps/Ccline.ps1"
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
            StepFile        = "windows/steps/ClaudeConfig.ps1"
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
            StepFile        = "windows/steps/ClaudeMd.ps1"
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
            StepFile        = "windows/steps/Mcp.ps1"
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
            StepFile        = "windows/steps/CcgWorkflow.ps1"
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
            StepId          = "Skills"
            StepName        = "Skills"
            Description     = "Skills 管理模块（仅通过 Manage → Skills 管理安装/更新/卸载，不参与安装流程与统一更新）"
            StepFile        = "windows/steps/Skills.ps1"
            TestFunction    = "Test-SkillsInstalled"
            InstallFunction = "Install-Skills"
            VerifyFunction  = "Verify-Skills"
            UpdateFunction  = ""
            SkipIfInstalled = $false
            IsOptional      = $true
            Order           = 95
            Dependencies    = @("NodeJS", "ClaudeCode")
            Group           = "Manage"
        },
        @{
            StepId          = "OpenSpec"
            StepName        = "OpenSpec CLI"
            Description     = "安装 OpenSpec CLI（规范驱动开发工具）"
            StepFile        = "windows/steps/OpenSpec.ps1"
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
            StepFile        = "windows/steps/CcSwitch.ps1"
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
            StepFile        = "windows/steps/CodexCli.ps1"
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
            StepId          = "AntigravityCli"
            StepName        = "Antigravity CLI"
            Description     = "安装 Google Antigravity CLI（多模型协作可选工具）"
            StepFile        = "windows/steps/AntigravityCli.ps1"
            TestFunction    = "Test-AntigravityCliInstalled"
            InstallFunction = "Install-AntigravityCli"
            VerifyFunction  = "Verify-AntigravityCli"
            UpdateFunction  = "Update-AntigravityCli"
            SkipIfInstalled = $true
            IsOptional      = $true
            Order           = 130
            Dependencies    = @()
            Group           = "Advanced"
        }
    )
}

function Get-StepRegistry {
    <#
    .SYNOPSIS
    返回步骤注册表数组（含 Order 字段用于拓扑排序 tie-break）
    .DESCRIPTION
    源码模式优先读取 installer/contracts/steps.json；release artifact 或 contracts 不可用时使用内联 fallback。
    .RETURNS
    hashtable[] - 每条记录包含步骤的完整元数据
    #>
    param()

    if ($null -ne $script:_registryCache) {
        return @($script:_registryCache)
    }

    $contract = Get-StepContract
    if ($null -ne $contract) {
        $contractRegistry = @(ConvertTo-StepRegistryFromContract -Contract $contract)
        Assert-StepRegistryFallbackConsistency -ContractRegistry $contractRegistry
        $contractGroups = ConvertTo-StepGroupsFromContract -Contract $contract
        Set-StepRegistryCaches -Registry $contractRegistry -Groups $contractGroups
        return @($script:_registryCache)
    }

    Set-StepRegistryCaches -Registry @(Get-InlineStepRegistry)
    return @($script:_registryCache)
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
    if ($null -ne $script:_groupCache) {
        return $script:_groupCache
    }

    $basicIds = @($registry | Where-Object { $_['Group'] -eq "Basic" } | ForEach-Object { $_['StepId'] })
    $advancedIds = @($registry | Where-Object { $_['Group'] -eq "Advanced" } | ForEach-Object { $_['StepId'] })

    return @{
        Basic = @{
            Label       = "基础环境"
            Description = "Claude Code 最小可用环境"
            InstallMode = "OneClickOnly"
            StepIds     = $basicIds
        }
        Advanced = @{
            Label       = "进阶扩展"
            Description = "增强配置，MCP，Workflow"
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
        $dependencies[[string]$step['StepId']] = @($step['Dependencies'])
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
    foreach ($step in ($registry | Sort-Object { [int]$_['Order'] })) {
        # 子模块排在主文件之前（构建时内联、运行时预加载）
        if ($step.ContainsKey('SubModules') -and @($step['SubModules']).Count -gt 0) {
            foreach ($sub in @($step['SubModules'])) {
                $files.Add([string]$sub)
            }
        }
        $files.Add([string]$step['StepFile'])
    }
    return @($files)
}
