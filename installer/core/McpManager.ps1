# McpManager.ps1 - MCP Server CRUD 管理 + 凭据 Vault
# 作者: 哈雷酱 (本小姐的 MCP 管理杰作！)
# 功能: 状态查看、禁用/启用、删除、凭据持久化、腐败恢复

#Requires -Version 7.0
Set-StrictMode -Version Latest

# 导入依赖模块
. "$PSScriptRoot\Ui.ps1"
. "$PSScriptRoot\Process.ps1"
. "$PSScriptRoot\Profile.ps1"

# ─── 常量 ─────────────────────────────────────────────────────────────────────

$script:McpMetaFileName = "mcp-meta.json"
$script:McpMetaSchemaVersion = 1
$script:McpMaxCorruptBackups = 5
$script:McpMutexName = "Global\CCQ.Mcp.Lock"
$script:McpMutexTimeoutMs = 30000

# ─── MCP Rules 分类配置 ─────────────────────────────────────────────────────

$script:McpRulesCategories = @{
    "Search" = @{
        FileName = "ccq-mcp-search.md"
        Title    = "搜索工具"
        Desc     = "联网搜索和内容提取。"
        Chains   = @(
            @{
                Scenario = "联网搜索"
                Steps    = @(
                    @{ McpId = "exa";    Tool = "mcp__exa__web_search_exa" }
                    @{ McpId = "tavily"; Tool = "mcp__tavily__tavily_search" }
                )
                Fallback = "WebSearch"
            }
            @{
                Scenario = "深度研究"
                Steps    = @( @{ McpId = "tavily"; Tool = "mcp__tavily__tavily_research" } )
            }
            @{
                Scenario = "URL 内容提取"
                Steps    = @( @{ McpId = "tavily"; Tool = "mcp__tavily__tavily_extract" } )
            }
            @{
                Scenario = "网站爬取/结构映射"
                Steps    = @(
                    @{ McpId = "tavily"; Tool = "mcp__tavily__tavily_crawl" }
                    @{ McpId = "tavily"; Tool = "mcp__tavily__tavily_map" }
                )
            }
            @{
                Scenario = "公司研究"
                Steps    = @( @{ McpId = "exa"; Tool = "mcp__exa__company_research_exa" } )
            }
            @{
                Scenario = "代码示例搜索"
                Steps    = @( @{ McpId = "exa"; Tool = "mcp__exa__get_code_context_exa" } )
            }
        )
        Tips = @(
            "联网搜索优先 exa，不可用时自动回退 tavily"
            "选择原则：语义理解优先搜索工具，精确匹配用 Grep"
        )
    }
    "Documentation" = @{
        FileName = "ccq-mcp-docs.md"
        Title    = "文档检索工具"
        Desc     = "库文档和开源项目文档检索。"
        Chains   = @(
            @{
                Scenario = "库官方文档"
                Steps    = @( @{ McpId = "context7"; Tool = "mcp__context7__resolve-library-id → mcp__context7__query-docs" } )
            }
            @{
                Scenario = "GitHub 开源项目"
                Steps    = @( @{ McpId = "deepwiki"; Tool = "mcp__deepwiki__ask_question / read_wiki_structure / read_wiki_contents" } )
            }
        )
        Tips = @(
            "context7 先 resolve-library-id 再 query-docs"
            "deepwiki 用于理解 GitHub 项目架构"
        )
    }
    "Development" = @{
        FileName = "ccq-mcp-code.md"
        Title    = "代码检索工具"
        Desc     = "代码语义搜索和上下文检索。"
        Chains   = @(
            @{
                Scenario = "代码语义检索"
                Steps    = @(
                    @{ McpId = "ace-tool";      Tool = "mcp__ace-tool__search_context" }
                    @{ McpId = "contextweaver"; Tool = "mcp__contextweaver__codebase-retrieval" }
                )
                Fallback = "Grep + Glob"
            }
            @{
                Scenario = "Prompt 增强"
                Steps    = @( @{ McpId = "ace-tool"; Tool = "mcp__ace-tool__enhance_prompt" } )
            }
        )
        StaticRows = @(
            @{ Scenario = "精确字符串/正则";  Tool = "Grep" }
            @{ Scenario = "文件名匹配";      Tool = "Glob" }
            @{ Scenario = "深度代码库探索";   Tool = "Agent + subagent_type=Explore" }
            @{ Scenario = "技术方案规划";     Tool = "EnterPlanMode / Agent + subagent_type=Plan" }
        )
        Tips = @(
            "语义理解用 ace-tool/contextweaver，精确匹配用 Grep"
            "使用 ContextWeaver 时，加入 `technical_terms`（精确符号名）可显著提升召回率"
        )
    }
    "Design" = @{
        FileName = "ccq-mcp-design.md"
        Title    = "设计工具"
        Desc     = "设计稿解析和代码生成。"
        Chains   = @(
            @{
                Scenario = "设计稿解析"
                Steps    = @(
                    @{ McpId = "mastergo"; Tool = "mcp__mastergo__*（getDsl / getComponentLink / getMeta / getComponentGenerator）" }
                    @{ McpId = "figma";    Tool = "mcp__figma__*" }
                )
            }
            @{
                Scenario = "矢量设计"
                Steps    = @( @{ McpId = "pencil"; Tool = "Pencil 桌面端（自动注册 MCP）" } )
            }
        )
    }
    "Automation" = @{
        FileName = "ccq-mcp-automation.md"
        Title    = "自动化工具"
        Desc     = "浏览器自动化和调试。"
        Chains   = @(
            @{
                Scenario = "浏览器自动化"
                Steps    = @( @{ McpId = "playwright"; Tool = "mcp__playwright__browser_*（navigate / click / snapshot）" } )
            }
            @{
                Scenario = "Chrome 调试"
                Steps    = @( @{ McpId = "chrome-devtools"; Tool = "mcp__chrome-devtools__*" } )
            }
        )
    }
}

# ─── MCP Rules 渲染函数 ─────────────────────────────────────────────────────

function Get-McpRulesDir {
    <#
    .SYNOPSIS
    获取 MCP Rules 目录路径（~/.claude/rules）
    #>
    $rulesDir = Join-Path (Get-UserHome) ".claude/rules"
    if (-not (Test-Path $rulesDir)) {
        New-Item -Path $rulesDir -ItemType Directory -Force | Out-Null
    }
    return $rulesDir
}

function Get-EnabledMcpIdsByCategory {
    <#
    .SYNOPSIS
    获取各分类下已启用的 MCP Server ID 列表
    .PARAMETER McpStatus
    从 Get-McpStatus 获取的 MCP 状态数组（hashtable[]）
    .RETURNS
    Hashtable：{ CategoryName = @(McpId1, McpId2, ...) }
    #>
    param([Parameter(Mandatory)][array]$McpStatus)

    # 将数组转换为 Id -> Status 的映射表
    $statusById = @{}
    foreach ($item in $McpStatus) {
        if ($item -is [hashtable] -and $item.ContainsKey("Id")) {
            $id = [string]$item["Id"]
            if (-not [string]::IsNullOrWhiteSpace($id)) {
                $statusById[$id] = [string]$item["Status"]
            }
        }
    }

    $result = @{}
    foreach ($catName in $script:McpRulesCategories.Keys) {
        $cat = $script:McpRulesCategories[$catName]
        $enabledIds = [System.Collections.ArrayList]::new()

        foreach ($chain in $cat.Chains) {
            foreach ($step in $chain.Steps) {
                $mcpId = $step.McpId
                # 检查是否启用（Active 状态）
                if ($statusById.ContainsKey($mcpId) -and $statusById[$mcpId] -eq "Active") {
                    if (-not $enabledIds.Contains($mcpId)) {
                        [void]$enabledIds.Add($mcpId)
                    }
                }
            }
        }
        $result[$catName] = @($enabledIds)
    }
    return $result
}

function Render-McpToolChain {
    <#
    .SYNOPSIS
    渲染单个分类的 Markdown 文件内容
    .PARAMETER CategoryName
    分类名称（如 Search、Documentation 等）
    .PARAMETER EnabledMcpIds
    该分类下已启用的 MCP ID 数组
    .RETURNS
    Markdown 字符串
    #>
    param(
        [Parameter(Mandatory)][string]$CategoryName,
        [Parameter(Mandatory)][array]$EnabledMcpIds
    )

    $cat = $script:McpRulesCategories[$CategoryName]
    if (-not $cat) { return $null }

    $sb = [System.Text.StringBuilder]::new()

    # 头部
    [void]$sb.AppendLine("# $($cat.Title)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("> 自动生成，请勿手动编辑。由 MCP Manager 根据已启用的 MCP Server 动态渲染。")
    [void]$sb.AppendLine("")
    if ($cat.Desc) {
        [void]$sb.AppendLine($cat.Desc)
        [void]$sb.AppendLine("")
    }

    # 工具链表格
    [void]$sb.AppendLine("| 场景 | 工具链 |")
    [void]$sb.AppendLine("|------|--------|")

    foreach ($chain in $cat.Chains) {
        $scenario = $chain.Scenario
        $tools = [System.Collections.ArrayList]::new()

        foreach ($step in $chain.Steps) {
            $mcpId = $step.McpId
            if ($EnabledMcpIds -contains $mcpId) {
                [void]$tools.Add($step.Tool)
            }
        }

        # 添加 Fallback（如果有且前面的工具都不可用）
        if ($chain -is [hashtable] -and $chain.ContainsKey('Fallback') -and $chain['Fallback']) {
            [void]$tools.Add("$($chain['Fallback'])（兜底）")
        }

        if ($tools.Count -gt 0) {
            $toolChain = $tools -join " → "
            [void]$sb.AppendLine("| $scenario | ``$toolChain`` |")
        }
    }

    # 静态行（如 Development 的 Grep/Glob）
    if ($cat -is [hashtable] -and $cat.ContainsKey('StaticRows') -and $cat['StaticRows']) {
        foreach ($row in $cat['StaticRows']) {
            [void]$sb.AppendLine("| $($row.Scenario) | ``$($row.Tool)`` |")
        }
    }

    [void]$sb.AppendLine("")

    # Tips
    if ($cat -is [hashtable] -and $cat.ContainsKey('Tips') -and $cat['Tips'].Count -gt 0) {
        [void]$sb.AppendLine("**Tips**:")
        foreach ($tip in $cat['Tips']) {
            [void]$sb.AppendLine("- $tip")
        }
    }

    return $sb.ToString()
}

function Sync-McpCategoryRules {
    <#
    .SYNOPSIS
    同步单个分类的 MCP Rules 文件
    .PARAMETER CategoryName
    分类名称
    .PARAMETER McpStatus
    MCP 状态数组（hashtable[]）
    .RETURNS
    @{ Changed = $bool; FileName = $string }
    #>
    param(
        [Parameter(Mandatory)][string]$CategoryName,
        [Parameter(Mandatory)][array]$McpStatus
    )

    $cat = $script:McpRulesCategories[$CategoryName]
    if (-not $cat) {
        return @{ Changed = $false; FileName = "" }
    }

    $rulesDir = Get-McpRulesDir
    $filePath = Join-Path $rulesDir $cat.FileName

    # 获取该分类下的已启用 MCP
    $enabledByCategory = Get-EnabledMcpIdsByCategory -McpStatus $McpStatus
    $enabledIds = @($enabledByCategory[$CategoryName])

    # 如果该分类没有任何已启用的 MCP，删除对应文件
    if ($enabledIds.Count -eq 0) {
        if (Test-Path $filePath) {
            Remove-Item $filePath -Force
            return @{ Changed = $true; FileName = $cat.FileName; Action = "Deleted" }
        }
        return @{ Changed = $false; FileName = $cat.FileName }
    }

    # 渲染内容
    $content = Render-McpToolChain -CategoryName $CategoryName -EnabledMcpIds $enabledIds

    # 比较是否需要更新
    $existingContent = ""
    if (Test-Path $filePath) {
        $existingContent = Get-Content $filePath -Raw -ErrorAction SilentlyContinue
    }

    $contentNormalized = ($content -replace "`r`n", "`n").Trim()
    $existingNormalized = ($existingContent -replace "`r`n", "`n").Trim()

    if ($contentNormalized -ne $existingNormalized) {
        $writeOk = Write-FileAtomically -FilePath $filePath -Content $content
        if (-not $writeOk) {
            throw "写入 MCP Rules 文件失败: $($cat.FileName)"
        }
        return @{ Changed = $true; FileName = $cat.FileName; Action = "Updated" }
    }

    return @{ Changed = $false; FileName = $cat.FileName }
}

function Sync-AllMcpRules {
    <#
    .SYNOPSIS
    同步所有 MCP Rules 文件（根据当前 MCP 状态动态渲染）
    .DESCRIPTION
    遍历所有分类，根据已启用的 MCP Server 动态生成/更新/删除对应的 rules 文件。
    .RETURNS
    @{ Success = $bool; ChangedFiles = @(...); ErrorMessage = $string }
    #>

    $result = @{
        Success      = $false
        ChangedFiles = @()
        ErrorMessage = ""
    }

    try {
        # 获取当前 MCP 状态
        $mcpStatus = Get-McpStatus
        if (-not $mcpStatus) {
            $result.ErrorMessage = "无法获取 MCP 状态"
            return $result
        }

        $changedFiles = [System.Collections.ArrayList]::new()

        # 遍历所有分类
        foreach ($catName in $script:McpRulesCategories.Keys) {
            $syncResult = Sync-McpCategoryRules -CategoryName $catName -McpStatus $mcpStatus
            if ($syncResult.Changed) {
                [void]$changedFiles.Add($syncResult)
            }
        }

        $result.ChangedFiles = @($changedFiles)
        $result.Success = $true

        if ($changedFiles.Count -gt 0) {
            Write-UiInfo "MCP Rules 已同步 ($($changedFiles.Count) 个文件变更)"
        }
    }
    catch {
        $result.ErrorMessage = $_.Exception.Message
        Write-UiWarn "MCP Rules 同步失败: $($result.ErrorMessage)"
    }

    return $result
}

# ─── Task 2.1: 目录管理 + 文件骨架 ───────────────────────────────────────────

function Ensure-CcqMetaDir {
    <#
    .SYNOPSIS
    确保 ~/.ccq/ 目录存在（首次使用时自动创建）
    .RETURNS
    目录绝对路径
    #>
    $dir = Join-Path (Get-UserHome) ".ccq"
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    return $dir
}

function Get-McpMetaPath {
    <#
    .SYNOPSIS
    获取 mcp-meta.json 文件路径
    #>
    return Join-Path (Ensure-CcqMetaDir) $script:McpMetaFileName
}

function New-EmptyMcpMeta {
    <#
    .SYNOPSIS
    创建空的 v1 vault 结构
    .RETURNS
    hashtable - 合法的空 vault
    #>
    $now = (Get-Date).ToUniversalTime().ToString("o")
    return @{
        schemaVersion = $script:McpMetaSchemaVersion
        createdAt     = $now
        updatedAt     = $now
        servers       = @{}
    }
}

# ─── Task 2.2: Read-McpMeta + 腐败恢复 ──────────────────────────────────────

function Invoke-McpCorruptionRecovery {
    <#
    .SYNOPSIS
    vault 文件腐败恢复：重命名 + 清理旧备份 + 返回空 vault
    .PARAMETER FilePath
    损坏的 vault 文件路径
    .RETURNS
    hashtable - 新的空 vault
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    $timestamp = (Get-Date).ToString("yyyyMMddHHmmss")
    $corruptName = "$FilePath.corrupt.$timestamp"

    try {
        Move-Item -Path $FilePath -Destination $corruptName -Force
        Write-UiWarn "Vault 文件损坏，已重命名为 $(Split-Path $corruptName -Leaf)，重新初始化"
    }
    catch {
        Write-UiWarn "Vault 文件损坏且无法重命名: $($_.Exception.Message)"
    }

    # 清理超出上限的 corrupt 备份
    $corruptFiles = @(Get-ChildItem -Path (Split-Path $FilePath -Parent) -Filter "*.corrupt.*" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime)
    if ($corruptFiles.Count -gt $script:McpMaxCorruptBackups) {
        $toDelete = $corruptFiles | Select-Object -First ($corruptFiles.Count - $script:McpMaxCorruptBackups)
        foreach ($file in $toDelete) {
            Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    return New-EmptyMcpMeta
}

function Read-McpMeta {
    <#
    .SYNOPSIS
    读取 vault 文件（mcp-meta.json）+ 腐败恢复 + schema 校验
    .RETURNS
    hashtable - vault 数据
    #>

    $metaPath = Get-McpMetaPath

    # 文件不存在 → 返回空 vault（lazy create，不写入磁盘）
    if (-not (Test-Path $metaPath)) {
        return New-EmptyMcpMeta
    }

    # 读取 + 解析
    $meta = $null
    try {
        $raw = Get-Content -Path $metaPath -Raw -Encoding UTF8
        $meta = $raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    }
    catch {
        return Invoke-McpCorruptionRecovery -FilePath $metaPath
    }

    # Schema 校验：schemaVersion 必须是正整数
    if (-not $meta -or
        -not $meta.ContainsKey("schemaVersion") -or
        $meta["schemaVersion"] -isnot [int] -or
        $meta["schemaVersion"] -lt 1) {
        return Invoke-McpCorruptionRecovery -FilePath $metaPath
    }

    # Schema 校验：servers 必须是 hashtable
    if (-not $meta.ContainsKey("servers") -or $meta["servers"] -isnot [hashtable]) {
        return Invoke-McpCorruptionRecovery -FilePath $metaPath
    }

    # 高版本检测：可读取但标记只读
    if ($meta["schemaVersion"] -gt $script:McpMetaSchemaVersion) {
        $meta["_readOnly"] = $true
    }

    # 未知字段：保留（不删除）
    return $meta
}

# ─── Task 2.3: Write-McpMeta ────────────────────────────────────────────────

function Write-McpMeta {
    <#
    .SYNOPSIS
    原子写入 vault 文件 + 时间戳更新 + 版本检查
    .PARAMETER Meta
    vault 数据 hashtable
    .RETURNS
    $true 写入成功
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Meta
    )

    # 高版本检查
    if ($Meta.ContainsKey("schemaVersion") -and $Meta["schemaVersion"] -gt $script:McpMetaSchemaVersion) {
        throw "schema version too high: $($Meta['schemaVersion']) > $($script:McpMetaSchemaVersion)"
    }

    # 只读检查
    if ($Meta.ContainsKey("_readOnly") -and $Meta["_readOnly"]) {
        throw "vault is read-only (newer schema version)"
    }

    # 更新根 updatedAt
    $now = (Get-Date).ToUniversalTime().ToString("o")
    $Meta["updatedAt"] = $now

    # 确保根 updatedAt ≥ max(servers[*].updatedAt)
    if ($Meta.ContainsKey("servers") -and $Meta["servers"] -is [hashtable]) {
        foreach ($serverId in $Meta["servers"].Keys) {
            $server = $Meta["servers"][$serverId]
            if ($server -is [hashtable] -and $server.ContainsKey("updatedAt")) {
                if ([string]$server["updatedAt"] -gt [string]$Meta["updatedAt"]) {
                    $Meta["updatedAt"] = $server["updatedAt"]
                }
            }
        }
    }

    # 删除内部标记字段
    $cleanMeta = @{}
    foreach ($key in $Meta.Keys) {
        if ($key -notlike "_*") {
            $cleanMeta[$key] = $Meta[$key]
        }
    }

    # 序列化
    $json = $cleanMeta | ConvertTo-Json -Depth 10

    # 原子写入
    Ensure-CcqMetaDir | Out-Null
    $null = Write-FileAtomically -FilePath (Get-McpMetaPath) -Content $json

    return $true
}

# ─── Task 2.4: Mutex 包装 ───────────────────────────────────────────────────

function Invoke-WithMcpLock {
    <#
    .SYNOPSIS
    在 Mutex 保护下执行操作（防止并发写入）
    .PARAMETER Action
    要在锁内执行的脚本块
    .RETURNS
    脚本块的返回值
    #>
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    $mutex = [System.Threading.Mutex]::new($false, $script:McpMutexName)
    $acquired = $false
    try {
        $acquired = $mutex.WaitOne($script:McpMutexTimeoutMs)
        if (-not $acquired) {
            throw "无法获取 MCP 锁（另一个实例正在操作），请稍后重试"
        }
        return & $Action
    }
    finally {
        if ($acquired) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

# ─── Task 2.5: Get-McpDefinitionHash ────────────────────────────────────────

function ConvertTo-CanonicalObject {
    <#
    .SYNOPSIS
    递归规范化对象：hashtable 键排序为 ordered，确保 JSON 序列化确定性
    #>
    param($Obj)

    if ($Obj -is [hashtable] -or $Obj -is [System.Collections.Specialized.OrderedDictionary]) {
        $sorted = [ordered]@{}
        foreach ($key in ($Obj.Keys | Sort-Object)) {
            $sorted[$key] = ConvertTo-CanonicalObject $Obj[$key]
        }
        return $sorted
    }
    elseif ($Obj -is [array]) {
        return @($Obj | ForEach-Object { ConvertTo-CanonicalObject $_ })
    }
    return $Obj
}

function Get-McpDefinitionHash {
    <#
    .SYNOPSIS
    计算 MCP Server 定义的哈希值（SHA-256 前 8 位）
    .PARAMETER ServerDef
    server 定义 hashtable
    .RETURNS
    8 字符哈希字符串
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ServerDef
    )

    # 排除非运行时字段，仅保留影响行为的字段
    $runtimeFields = @{}
    $excludeKeys = @("Description", "Category", "Priority", "Recommended", "Name", "RuntimeDeps")
    foreach ($key in $ServerDef.Keys) {
        if ($key -notin $excludeKeys) {
            $runtimeFields[$key] = $ServerDef[$key]
        }
    }

    # 递归规范化 hashtable 键排序以确保确定性（CONS-2）
    $canonical = ConvertTo-CanonicalObject $runtimeFields
    $json = $canonical | ConvertTo-Json -Depth 10 -Compress

    # 计算 SHA-256
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $hash = $sha256.ComputeHash($bytes)
        # 取前 8 位十六进制
        return ($hash[0..3] | ForEach-Object { $_.ToString("x2") }) -join ""
    }
    finally {
        $sha256.Dispose()
    }
}

# ─── CJK 显示宽度辅助函数 ───────────────────────────────────────────────────

function Get-StringDisplayWidth {
    <#
    .SYNOPSIS
    计算字符串在终端的显示宽度（CJK 字符占 2 列）
    #>
    param([Parameter(Position = 0)][AllowEmptyString()][AllowNull()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return 0 }
    $width = 0
    foreach ($c in $Text.ToCharArray()) {
        $code = [int]$c
        if (($code -ge 0x2E80 -and $code -le 0x9FFF) -or
            ($code -ge 0xF900 -and $code -le 0xFAFF) -or
            ($code -ge 0xFE30 -and $code -le 0xFE4F) -or
            ($code -ge 0xFF00 -and $code -le 0xFF60) -or
            ($code -ge 0xFFE0 -and $code -le 0xFFE6)) {
            $width += 2
        } else {
            $width += 1
        }
    }
    return $width
}

function Format-DisplayPad {
    <#
    .SYNOPSIS
    按显示宽度右填充字符串（CJK 感知）
    #>
    param([Parameter(Position = 0)][AllowEmptyString()][AllowNull()][string]$Text, [Parameter(Position = 1)][int]$Width)
    if ([string]::IsNullOrEmpty($Text)) { return (' ' * $Width) }
    $displayWidth = Get-StringDisplayWidth $Text
    $padding = [Math]::Max(0, $Width - $displayWidth)
    return "$Text$(' ' * $padding)"
}

# ─── Task 2.6: Get-McpStatus + Show-McpStatusTable ──────────────────────────

function Get-McpStatus {
    <#
    .SYNOPSIS
    计算所有 MCP Server 的状态列表（ADR-06 优先级）
    .RETURNS
    hashtable[] - @{ Id; Name; Status; McpType; Category; HasCredentials }
    #>

    # 读取 .claude.json
    $claudeJsonPath = "$(Get-UserHome)\.claude.json"
    $claudeServers = @{}
    if (Test-Path $claudeJsonPath) {
        try {
            $claudeJson = Get-Content -Path $claudeJsonPath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            if ($claudeJson -and $claudeJson.ContainsKey("mcpServers") -and $claudeJson["mcpServers"]) {
                $claudeServers = $claudeJson["mcpServers"]
            }
        } catch { }
    }

    # 读取 vault
    $meta = Read-McpMeta

    # 收集所有 server ID（union）
    $allIds = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($id in $claudeServers.Keys) { [void]$allIds.Add($id) }
    if ($script:McpServers) {
        foreach ($id in $script:McpServers.Keys) { [void]$allIds.Add($id) }
    }
    foreach ($id in $meta["servers"].Keys) { [void]$allIds.Add($id) }

    # 判定每个 server 的状态
    $results = @()
    foreach ($id in $allIds) {
        $inClaudeJson = $claudeServers.ContainsKey($id)
        $inMcpServers = ($script:McpServers -and $script:McpServers.Contains($id))
        $inMeta = $meta["servers"].ContainsKey($id)
        $isDisabled = ($inMeta -and $meta["servers"][$id] -is [hashtable] -and
                       $meta["servers"][$id].ContainsKey("disabled") -and $meta["servers"][$id]["disabled"])

        # ADR-06 优先级：Custom > Disabled > Active > Missing
        $status = if ($inClaudeJson -and -not $inMcpServers) { "Custom" }
                  elseif ($isDisabled) { "Disabled" }
                  elseif ($inClaudeJson -and $inMcpServers) { "Active" }
                  elseif ($inMcpServers -and -not $inClaudeJson -and -not $isDisabled) { "Missing" }
                  else { "Unknown" }

        # 获取名称和类型
        $name = $id
        $mcpType = ""
        $category = ""
        $hasCredentials = $false

        if ($inMcpServers) {
            $def = $script:McpServers[$id]
            $name = if ($def.Name) { $def.Name } else { $id }
            $mcpType = if ($def.McpType) { $def.McpType } else { "" }
            $category = if ($def.Category) { $def.Category } else { "" }
            $hasCredentials = ($def.CredentialType -ne "none")
        }
        elseif ($inMeta -and $meta["servers"][$id] -is [hashtable]) {
            $hasCredentials = $meta["servers"][$id].ContainsKey("credentials") -and $meta["servers"][$id]["credentials"]
        }

        $results += @{
            Id             = $id
            Name           = $name
            Status         = $status
            McpType        = $mcpType
            Category       = $category
            HasCredentials = $hasCredentials
        }
    }

    # 按状态排序：Custom → Active → Disabled → Missing → Unknown
    $statusOrder = @{ "Custom" = 0; "Active" = 1; "Disabled" = 2; "Missing" = 3; "Unknown" = 4 }
    $results = @($results | Sort-Object { $statusOrder[$_.Status] })

    return $results
}

function Show-McpStatusTable {
    <#
    .SYNOPSIS
    格式化输出 MCP 状态表格（带 ANSI 着色）
    .PARAMETER StatusList
    Get-McpStatus 返回的状态数组
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$StatusList
    )

    if ($StatusList.Count -eq 0) {
        Write-UiInfo "没有 MCP Server"
        return
    }

    Write-Host ""
    Write-UiInfo "MCP Server 状态："
    Write-Host ""

    # 列宽定义（按显示宽度，CJK 字符占 2 列）
    $colWidths = @(12, 20, 10, 15, 5)

    # 表头（使用 CJK 感知填充）
    $headerLine = "  " +
        (Format-DisplayPad "状态" $colWidths[0]) + " " +
        (Format-DisplayPad "名称" $colWidths[1]) + " " +
        (Format-DisplayPad "类型" $colWidths[2]) + " " +
        (Format-DisplayPad "分类" $colWidths[3]) + " " +
        (Format-DisplayPad "凭据" $colWidths[4])
    Write-Host $headerLine -ForegroundColor White
    $sepWidth = ($colWidths | Measure-Object -Sum).Sum + $colWidths.Count - 1
    Write-Host ("  " + [string]::new("-", $sepWidth)) -ForegroundColor Gray

    foreach ($item in $StatusList) {
        $statusText = "[$($item.Status)]"
        $credText = if ($item.HasCredentials) { "有" } else { "-" }

        $color = switch ($item.Status) {
            "Active"   { "Green" }
            "Disabled" { "Yellow" }
            "Missing"  { "Gray" }
            "Custom"   { "Cyan" }
            default    { "White" }
        }

        $line = "  " +
            (Format-DisplayPad $statusText $colWidths[0]) + " " +
            (Format-DisplayPad "$($item.Name)" $colWidths[1]) + " " +
            (Format-DisplayPad "$($item.McpType)" $colWidths[2]) + " " +
            (Format-DisplayPad "$($item.Category)" $colWidths[3]) + " " +
            (Format-DisplayPad $credText $colWidths[4])
        Write-Host $line -ForegroundColor $color
    }
    Write-Host ""
}

# ─── Task 2.7: Disable-McpServer ────────────────────────────────────────────

function Disable-McpServer {
    <#
    .SYNOPSIS
    禁用 MCP Server：从 .claude.json 移除 + 保存到 vault + 清理 permissions
    .PARAMETER ServerId
    server ID
    .RETURNS
    @{ Success; ServerId; Status }
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerId
    )

    return Invoke-WithMcpLock {
        $claudeJsonPath = "$(Get-UserHome)\.claude.json"

        # 读取 .claude.json
        $claudeJson = @{}
        if (Test-Path $claudeJsonPath) {
            $claudeJson = Get-Content -Path $claudeJsonPath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        }
        if (-not $claudeJson) { $claudeJson = @{} }
        if (-not $claudeJson.ContainsKey("mcpServers")) { $claudeJson["mcpServers"] = @{} }

        # 检查 server 是否存在于 .claude.json
        if (-not $claudeJson["mcpServers"].ContainsKey($ServerId)) {
            # 检查 meta 是否已标记 disabled
            $meta = Read-McpMeta
            if ($meta["servers"].ContainsKey($ServerId) -and
                $meta["servers"][$ServerId] -is [hashtable] -and
                $meta["servers"][$ServerId].ContainsKey("disabled") -and
                $meta["servers"][$ServerId]["disabled"]) {
                # 已禁用，幂等返回
                return @{ Success = $true; ServerId = $ServerId; Status = "Disabled" }
            }
            Write-UiWarn "MCP Server '$ServerId' 未在 .claude.json 中找到"
            return @{ Success = $false; ServerId = $ServerId; Status = "NotFound" }
        }

        # 保存完整配置到 vault
        $existingConfig = $claudeJson["mcpServers"][$ServerId]
        $meta = Read-McpMeta

        # 提取凭据
        $credentials = @{}
        if ($existingConfig -is [hashtable] -and $existingConfig.ContainsKey("env") -and $existingConfig["env"]) {
            $credentials = $existingConfig["env"]
        }

        # 计算定义哈希
        $defHash = ""
        if ($script:McpServers -and $script:McpServers.Contains($ServerId)) {
            $defHash = Get-McpDefinitionHash $script:McpServers[$ServerId]
        }

        # 从 settings.json permissions 移除匹配项（保存到 vault 以便恢复）
        $settingsPath = "$(Get-UserHome)\.claude\settings.json"
        $removedPermissions = @()
        if (Test-Path $settingsPath) {
            $settings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
            if ($settings -and $settings.ContainsKey("permissions") -and $settings["permissions"].ContainsKey("allow")) {
                $escapedId = [regex]::Escape($ServerId)
                $pattern = "^mcp__${escapedId}__"
                $removedPermissions = @($settings["permissions"]["allow"] | Where-Object { $_ -cmatch $pattern })
                $settings["permissions"]["allow"] = @($settings["permissions"]["allow"] | Where-Object { $_ -cnotmatch $pattern })
                # 原子写入 settings.json
                $settingsJson = $settings | ConvertTo-Json -Depth 10
                $null = Write-FileAtomically -FilePath $settingsPath -Content $settingsJson
            }
        }

        # 保存到 vault（$removedPermissions 已就绪）— 先写 vault 再删 .claude.json，确保数据不丢失
        $meta["servers"][$ServerId] = @{
            disabled       = $true
            credentials    = $credentials
            config         = $existingConfig
            permissions    = $removedPermissions
            definitionHash = $defHash
            updatedAt      = (Get-Date).ToUniversalTime().ToString("o")
        }
        $null = Write-McpMeta $meta

        # 从 .claude.json 移除（vault 已安全写入）
        $claudeJson["mcpServers"].Remove($ServerId)
        $claudeJsonContent = $claudeJson | ConvertTo-Json -Depth 10
        $null = Write-FileAtomically -FilePath $claudeJsonPath -Content $claudeJsonContent

        Write-UiSuccess "MCP Server '$ServerId' 已禁用"

        # 同步 MCP Rules 文件
        $null = Sync-AllMcpRules

        return @{ Success = $true; ServerId = $ServerId; Status = "Disabled" }
    }
}

# ─── Task 2.8: Enable-McpServer ─────────────────────────────────────────────

function Enable-McpServer {
    <#
    .SYNOPSIS
    启用 MCP Server：从 vault 恢复到 .claude.json + 恢复 permissions
    .PARAMETER ServerId
    server ID
    .RETURNS
    @{ Success; ServerId; Status }
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerId
    )

    return Invoke-WithMcpLock {
        $meta = Read-McpMeta

        # 检查是否处于禁用状态
        if (-not $meta["servers"].ContainsKey($ServerId) -or
            -not ($meta["servers"][$ServerId] -is [hashtable]) -or
            -not $meta["servers"][$ServerId].ContainsKey("disabled") -or
            -not $meta["servers"][$ServerId]["disabled"]) {
            # 非禁用状态，幂等返回
            return @{ Success = $true; ServerId = $ServerId; Status = "Active" }
        }

        $vaultEntry = $meta["servers"][$ServerId]

        # 检查 definitionHash 变更
        if ($script:McpServers -and $script:McpServers.Contains($ServerId)) {
            $currentHash = Get-McpDefinitionHash $script:McpServers[$ServerId]
            if ($vaultEntry.ContainsKey("definitionHash") -and
                $vaultEntry["definitionHash"] -ne "" -and
                $vaultEntry["definitionHash"] -ne $currentHash) {
                Write-UiWarn "MCP 定义已变更，使用最新定义恢复"
            }
        }

        # 获取凭据
        $credentials = @{}
        if ($vaultEntry.ContainsKey("credentials") -and $vaultEntry["credentials"] -is [hashtable]) {
            $credentials = $vaultEntry["credentials"]
        }

        # 重建 server 配置
        $serverConfig = $null
        if ($script:McpServers -and $script:McpServers.Contains($ServerId)) {
            # 使用最新定义 + vault 凭据重建
            try {
                $serverConfig = New-McpSettingsEntry -ServerId $ServerId -Server $script:McpServers[$ServerId] -Credentials $credentials
                # 恢复凭据到 env（仅在重建成功时）
                if ($serverConfig -and $credentials.Count -gt 0) {
                    if (-not $serverConfig.ContainsKey("env")) {
                        $serverConfig["env"] = @{}
                    }
                    foreach ($key in $credentials.Keys) {
                        $serverConfig["env"][$key] = $credentials[$key]
                    }
                }
            }
            catch {
                Write-UiWarn "重建 MCP 配置失败: $($_.Exception.Message)"
            }
            # 重建失败或返回 $null 时（如 software 类型），回退到 vault 保存的原始配置
            if (-not $serverConfig -and $vaultEntry.ContainsKey("config") -and $vaultEntry["config"]) {
                Write-UiInfo "使用 vault 保存的原始配置恢复"
                $serverConfig = $vaultEntry["config"]
            }
        }
        elseif ($vaultEntry.ContainsKey("config") -and $vaultEntry["config"]) {
            # 使用 vault 中保存的原始配置
            $serverConfig = $vaultEntry["config"]
        }

        if (-not $serverConfig) {
            Write-UiError "无法恢复 MCP Server '$ServerId'：缺少配置信息"
            return @{ Success = $false; ServerId = $ServerId; Status = "Error" }
        }

        # 写入 .claude.json
        $claudeJsonPath = "$(Get-UserHome)\.claude.json"
        $claudeJson = @{}
        if (Test-Path $claudeJsonPath) {
            $claudeJson = Get-Content -Path $claudeJsonPath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        }
        if (-not $claudeJson) { $claudeJson = @{} }
        if (-not $claudeJson.ContainsKey("mcpServers")) { $claudeJson["mcpServers"] = @{} }

        $claudeJson["mcpServers"][$ServerId] = $serverConfig

        # 原子写入 .claude.json
        $claudeJsonContent = $claudeJson | ConvertTo-Json -Depth 10
        $null = Write-FileAtomically -FilePath $claudeJsonPath -Content $claudeJsonContent

        # 恢复 permissions（优先从 vault 恢复具体权限）
        $settingsPath = "$(Get-UserHome)\.claude\settings.json"
        if (Test-Path $settingsPath) {
            $settings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
            if ($settings) {
                if (-not $settings.ContainsKey("permissions")) { $settings["permissions"] = @{} }
                if (-not $settings["permissions"].ContainsKey("allow")) { $settings["permissions"]["allow"] = @() }

                # 从 vault 恢复保存的具体权限
                $vaultPerms = @()
                if ($vaultEntry.ContainsKey("permissions") -and $vaultEntry["permissions"]) {
                    $vaultPerms = @($vaultEntry["permissions"])
                }

                $permChanged = $false
                if ($vaultPerms.Count -gt 0) {
                    foreach ($perm in $vaultPerms) {
                        if ($settings["permissions"]["allow"] -notcontains $perm) {
                            $settings["permissions"]["allow"] += $perm
                            $permChanged = $true
                        }
                    }
                } else {
                    # 无保存的权限记录，确保基础 Mcp 权限存在
                    if ($settings["permissions"]["allow"] -notcontains "Mcp") {
                        $settings["permissions"]["allow"] += "Mcp"
                        $permChanged = $true
                    }
                }

                if ($permChanged) {
                    $settingsJson = $settings | ConvertTo-Json -Depth 10
                    $null = Write-FileAtomically -FilePath $settingsPath -Content $settingsJson
                }
            }
        }

        # 更新 vault
        $meta["servers"][$ServerId]["disabled"] = $false
        if ($script:McpServers -and $script:McpServers.Contains($ServerId)) {
            $meta["servers"][$ServerId]["definitionHash"] = Get-McpDefinitionHash $script:McpServers[$ServerId]
        }
        $meta["servers"][$ServerId]["updatedAt"] = (Get-Date).ToUniversalTime().ToString("o")
        $null = Write-McpMeta $meta

        Write-UiSuccess "MCP Server '$ServerId' 已启用"

        # 同步 MCP Rules 文件
        $null = Sync-AllMcpRules

        return @{ Success = $true; ServerId = $ServerId; Status = "Active" }
    }
}

# ─── Task 2.9: Remove-McpServer ─────────────────────────────────────────────

function Remove-McpServer {
    <#
    .SYNOPSIS
    删除 MCP Server：从所有文件清理 + 确认提示
    .PARAMETER ServerId
    server ID
    .RETURNS
    @{ Success; ServerId; Status }
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerId
    )

    # 状态检查
    $statuses = Get-McpStatus
    $serverStatus = $statuses | Where-Object { $_.Id -eq $ServerId } | Select-Object -First 1

    if (-not $serverStatus) {
        Write-UiWarn "MCP Server '$ServerId' 不存在"
        return @{ Success = $false; ServerId = $ServerId; Status = "NotFound" }
    }

    if ($serverStatus.Status -eq "Missing") {
        # 检查 meta 中有无记录
        $meta = Read-McpMeta
        if ($meta["servers"].ContainsKey($ServerId)) {
            # 孤立记录也需确认（HC-M5）
            $orphanConfirm = Show-SingleSelectMenu `
                -Title "发现 '$ServerId' 的孤立元数据记录，确定要清理？" `
                -Options @("是，清理", "否，取消")

            if ($orphanConfirm -ne 0) {
                Write-UiInfo "已取消清理"
                return @{ Success = $false; ServerId = $ServerId; Status = "Cancelled" }
            }

            return Invoke-WithMcpLock {
                $m = Read-McpMeta
                $m["servers"].Remove($ServerId)
                $null = Write-McpMeta $m
                Write-UiSuccess "已清理 '$ServerId' 的孤立元数据"
                return @{ Success = $true; ServerId = $ServerId; Status = "Removed" }
            }
        }
        Write-UiWarn "MCP Server '$ServerId' 未安装"
        return @{ Success = $false; ServerId = $ServerId; Status = "Missing" }
    }

    # Custom 类型额外确认
    if ($serverStatus.Status -eq "Custom") {
        Write-UiWarn "此 MCP 非 CCQ 管理，删除后无法通过 CCQ 恢复"
    }

    # 确认
    $confirmIndex = Show-SingleSelectMenu `
        -Title "确定要删除 $ServerId MCP Server？" `
        -Options @("是，删除", "否，取消")

    if ($confirmIndex -ne 0) {
        Write-UiInfo "已取消删除"
        return @{ Success = $false; ServerId = $ServerId; Status = "Cancelled" }
    }

    return Invoke-WithMcpLock {
        $claudeJsonPath = "$(Get-UserHome)\.claude.json"
        $settingsPath = "$(Get-UserHome)\.claude\settings.json"

        # 1. 从 .claude.json 移除
        if (Test-Path $claudeJsonPath) {
            $claudeJson = Get-Content -Path $claudeJsonPath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            if ($claudeJson -and $claudeJson.ContainsKey("mcpServers") -and
                $claudeJson["mcpServers"].ContainsKey($ServerId)) {
                $claudeJson["mcpServers"].Remove($ServerId)
            }

            # 2. 从 permissions 移除匹配项
            if (Test-Path $settingsPath) {
                $settings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
                if ($settings -and $settings.ContainsKey("permissions") -and
                    $settings["permissions"].ContainsKey("allow")) {
                    $escapedId = [regex]::Escape($ServerId)
                    $pattern = "^mcp__${escapedId}__"
                    $settings["permissions"]["allow"] = @($settings["permissions"]["allow"] | Where-Object { $_ -cnotmatch $pattern })
                    $settingsJson = $settings | ConvertTo-Json -Depth 10
                    $null = Write-FileAtomically -FilePath $settingsPath -Content $settingsJson
                }
            }

            # 3. 原子写入 .claude.json
            $claudeJsonContent = $claudeJson | ConvertTo-Json -Depth 10
            $null = Write-FileAtomically -FilePath $claudeJsonPath -Content $claudeJsonContent
        }

        # 4. 从 vault 移除
        $meta = Read-McpMeta
        if ($meta["servers"].ContainsKey($ServerId)) {
            $meta["servers"].Remove($ServerId)
        }

        # 5. 写入 vault
        $null = Write-McpMeta $meta

        Write-UiSuccess "MCP Server '$ServerId' 已删除"

        # 同步 MCP Rules 文件
        $null = Sync-AllMcpRules

        return @{ Success = $true; ServerId = $ServerId; Status = "Removed" }
    }
}

# ─── Task 2.10: Invoke-McpToggle ────────────────────────────────────────────

function Invoke-McpToggle {
    <#
    .SYNOPSIS
    批量 Toggle 禁用/启用
    .PARAMETER ServerIds
    要 toggle 的 server ID 数组
    .RETURNS
    @{ Results; SuccessCount; FailureCount }
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ServerIds
    )

    $results = @()
    $successCount = 0
    $failureCount = 0

    # 获取当前状态
    $statuses = Get-McpStatus
    $statusMap = @{}
    foreach ($s in $statuses) { $statusMap[$s.Id] = $s.Status }

    foreach ($id in $ServerIds) {
        try {
            $currentStatus = if ($statusMap.ContainsKey($id)) { $statusMap[$id] } else { "Unknown" }

            $toggleResult = switch ($currentStatus) {
                "Active"   { Disable-McpServer -ServerId $id }
                "Disabled" { Enable-McpServer -ServerId $id }
                "Missing"  {
                    # Missing = 注册表有定义但不在 .claude.json 也未禁用，尝试从定义重建
                    if ($script:McpServers -and $script:McpServers.Contains($id)) {
                        $newConfig = New-McpSettingsEntry -ServerId $id -Server $script:McpServers[$id] -Credentials @{}
                        if ($newConfig) {
                            $cjPath = "$(Get-UserHome)\.claude.json"
                            $cj = @{}
                            if (Test-Path $cjPath) {
                                $cj = Get-Content -Path $cjPath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
                            }
                            if (-not $cj) { $cj = @{} }
                            if (-not $cj.ContainsKey("mcpServers")) { $cj["mcpServers"] = @{} }
                            $cj["mcpServers"][$id] = $newConfig
                            $writeOk = Write-FileAtomically -FilePath $cjPath -Content ($cj | ConvertTo-Json -Depth 10)
                            if (-not $writeOk) {
                                throw "更新 .claude.json 失败"
                            }
                            Write-UiSuccess "MCP Server '$id' 已恢复"

                            # 同步 MCP Rules 文件
                            $syncResult = Sync-AllMcpRules
                            if (-not $syncResult.Success) {
                                Write-UiWarn "MCP Rules 同步失败: $($syncResult.ErrorMessage)"
                            }

                            @{ Success = $true; ServerId = $id; Status = "Active" }
                        } else {
                            Write-UiWarn "MCP Server '$id' 配置类型不支持自动恢复（如需凭据请使用安装功能）"
                            @{ Success = $false; ServerId = $id; Status = "Missing" }
                        }
                    } else {
                        Write-UiWarn "MCP Server '$id' 未在注册表中定义"
                        @{ Success = $false; ServerId = $id; Status = "Unknown" }
                    }
                }
                default {
                    Write-UiWarn "MCP Server '$id' 状态为 $currentStatus，跳过 toggle"
                    @{ Success = $false; ServerId = $id; Status = $currentStatus }
                }
            }

            $results += $toggleResult
            if ($toggleResult.Success) { $successCount++ } else { $failureCount++ }
        }
        catch {
            Write-UiError "Toggle '$id' 失败: $($_.Exception.Message)"
            $results += @{ Success = $false; ServerId = $id; Status = "Error" }
            $failureCount++
        }
    }

    return @{
        Results      = $results
        SuccessCount = $successCount
        FailureCount = $failureCount
    }
}

# ─── Task 2.13: MCP 管理子菜单 ─────────────────────────────────────────────

function Show-McpManageMenu {
    <#
    .SYNOPSIS
    MCP 管理交互菜单（查看状态 / 切换 / 删除）
    #>

    while ($true) {
        $options = @(
            "查看 MCP 状态"
            "切换 MCP 状态"
            "删除 MCP"
        )
        $choice = Show-SingleSelectMenu -Title "MCP 管理" -Options $options -DefaultIndex 0

        if ($choice -eq -1) { return }

        switch ($choice) {
            0 {
                # 查看状态
                $statuses = Get-McpStatus
                Show-McpStatusTable $statuses
                Write-Host ""
                Write-Host "按任意键返回..." -ForegroundColor Gray
                $null = [Console]::ReadKey($true)
            }
            1 {
                # 切换状态
                $statuses = Get-McpStatus
                $toggleable = @($statuses | Where-Object { $_.Status -in @("Active", "Disabled", "Missing") })
                if ($toggleable.Count -eq 0) {
                    Write-UiWarn "没有可切换状态的 MCP Server"
                    Write-Host "按任意键返回..." -ForegroundColor Gray
                    $null = [Console]::ReadKey($true)
                    continue
                }

                $menuOptions = @($toggleable | ForEach-Object { "$($_.Name) [$($_.Status)]" })
                $defaultSelected = @()
                for ($i = 0; $i -lt $toggleable.Count; $i++) {
                    if ($toggleable[$i].Status -eq "Active") {
                        $defaultSelected += $i
                    }
                }

                $selections = Show-MultiSelectMenu -Title "切换 MCP 状态（空格切换，Active=已勾选）" -Options $menuOptions -DefaultSelected $defaultSelected
                if ($null -ne $selections) {
                    $selectedIndices = @($selections)
                    $toggleIds = @()
                    for ($i = 0; $i -lt $toggleable.Count; $i++) {
                        $wasActive = $toggleable[$i].Status -eq "Active"
                        $isSelected = $selectedIndices -contains $i
                        # Active 取消勾选 → Disable; Disabled 勾选 → Enable
                        if (($wasActive -and -not $isSelected) -or (-not $wasActive -and $isSelected)) {
                            $toggleIds += $toggleable[$i].Id
                        }
                    }
                    if ($toggleIds.Count -gt 0) {
                        $result = Invoke-McpToggle $toggleIds
                        Write-UiSuccess "切换完成: $($result.SuccessCount) 成功, $($result.FailureCount) 失败"
                    } else {
                        Write-UiInfo "未更改任何状态"
                    }
                }

                Write-Host ""
                Write-Host "按任意键返回..." -ForegroundColor Gray
                $null = [Console]::ReadKey($true)
            }
            2 {
                # 删除
                $statuses = Get-McpStatus
                $removable = @($statuses | Where-Object { $_.Status -ne "Missing" })
                if ($removable.Count -eq 0) {
                    Write-UiWarn "没有可删除的 MCP Server"
                    Write-Host "按任意键返回..." -ForegroundColor Gray
                    $null = [Console]::ReadKey($true)
                    continue
                }

                $menuOptions = @($removable | ForEach-Object { "$($_.Name) [$($_.Status)]" })
                $selected = Show-SingleSelectMenu -Title "选择要删除的 MCP" -Options $menuOptions -DefaultIndex 0
                if ($selected -ge 0 -and $selected -lt $removable.Count) {
                    Remove-McpServer $removable[$selected].Id
                }

                Write-Host ""
                Write-Host "按任意键返回..." -ForegroundColor Gray
                $null = [Console]::ReadKey($true)
            }
        }
    }
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用
