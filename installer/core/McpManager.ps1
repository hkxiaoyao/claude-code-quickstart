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

        # 保存到 vault（$removedPermissions 已就绪）
        $meta["servers"][$ServerId] = @{
            disabled       = $true
            credentials    = $credentials
            config         = $existingConfig
            permissions    = $removedPermissions
            definitionHash = $defHash
            updatedAt      = (Get-Date).ToUniversalTime().ToString("o")
        }

        # 从 .claude.json 移除
        $claudeJson["mcpServers"].Remove($ServerId)

        # 原子写入 .claude.json
        $claudeJsonContent = $claudeJson | ConvertTo-Json -Depth 10
        $null = Write-FileAtomically -FilePath $claudeJsonPath -Content $claudeJsonContent

        # 写入 vault
        $null = Write-McpMeta $meta

        Write-UiSuccess "MCP Server '$ServerId' 已禁用"
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
                # 恢复凭据到 env
                if ($credentials.Count -gt 0 -and $serverConfig -and -not $serverConfig.ContainsKey("env")) {
                    $serverConfig["env"] = @{}
                }
                if ($credentials.Count -gt 0 -and $serverConfig) {
                    foreach ($key in $credentials.Keys) {
                        $serverConfig["env"][$key] = $credentials[$key]
                    }
                }
            }
            catch {
                Write-UiWarn "重建 MCP 配置失败: $($_.Exception.Message)"
                # 尝试使用 vault 中保存的原始配置
                if ($vaultEntry.ContainsKey("config") -and $vaultEntry["config"]) {
                    $serverConfig = $vaultEntry["config"]
                }
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
                    # 无保存的权限记录，确保基础 mcp 权限存在
                    if ($settings["permissions"]["allow"] -notcontains "mcp") {
                        $settings["permissions"]["allow"] += "mcp"
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
        $currentStatus = if ($statusMap.ContainsKey($id)) { $statusMap[$id] } else { "Unknown" }

        $toggleResult = switch ($currentStatus) {
            "Active"   { Disable-McpServer -ServerId $id }
            "Disabled" { Enable-McpServer -ServerId $id }
            default {
                Write-UiWarn "MCP Server '$id' 状态为 $currentStatus，跳过 toggle"
                @{ Success = $false; ServerId = $id; Status = $currentStatus }
            }
        }

        $results += $toggleResult
        if ($toggleResult.Success) { $successCount++ } else { $failureCount++ }
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
                $toggleable = @($statuses | Where-Object { $_.Status -in @("Active", "Disabled") })
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
